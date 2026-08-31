-- =====================================================================
--  Forum Pièces Bony 2026 — 02 — Couche d'API
--
--  Aucun client ne touche une table. Tout passe par ces fonctions, qui
--  sont les seules à posséder les droits (security definer) et dont le
--  search_path est épinglé pour éviter tout détournement.
--
--  Toute écriture de points passe par _ecrire(), qui garantit :
--   - le verrou sur la ligne du garage (deux téléphones d'un même
--     garage sont sérialisés, les autres garages ne sont pas bloqués) ;
--   - l'idempotence par clé unique (double clic, réessai réseau) ;
--   - l'impossibilité de descendre sous zéro ;
--   - la mise à jour du solde en cache dans la même transaction.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Résolution d'un appareil à partir de son jeton
-- ---------------------------------------------------------------------
create or replace function public._appareil(p_jeton text)
returns public.appareils
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a public.appareils;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE' using detail = 'Jeton absent ou trop court.';
  end if;
  select * into a from appareils where jeton = p_jeton;
  if not found then
    raise exception 'APPAREIL_INCONNU'
      using detail = 'Cet appareil n''est pas enregistré. Rescannez le QR code.';
  end if;
  return a;
end;
$$;

create or replace function public._exige_role(p_jeton text, p_roles text[])
returns public.appareils
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a public.appareils;
begin
  a := _appareil(p_jeton);
  if not (a.role = any(p_roles)) then
    raise exception 'ROLE_INSUFFISANT'
      using detail = format('Rôle %s, requis : %s', a.role, array_to_string(p_roles, ' ou '));
  end if;
  return a;
end;
$$;

-- ---------------------------------------------------------------------
-- Écriture de points — le cœur du système
-- ---------------------------------------------------------------------
create or replace function public._ecrire(
  p_garage    uuid,
  p_delta     integer,
  p_libelle   text,
  p_source    text,
  p_cle       text,
  p_appareil  uuid default null,
  p_animation uuid default null,
  p_stand     uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_solde integer;
  v_id    bigint;
begin
  if p_cle is null or length(p_cle) < 8 then
    raise exception 'CLE_IDEMPOTENCE_REQUISE'
      using detail = 'Chaque opération doit porter une clé unique générée par le client.';
  end if;

  -- Verrou sur le garage : sérialise les opérations concurrentes de ses
  -- appareils, sans impact sur les 399 autres garages.
  select solde into v_solde from garages where id = p_garage for update;
  if not found then
    raise exception 'GARAGE_INCONNU' using detail = 'Garage introuvable.';
  end if;

  -- Barrière d'idempotence : si la clé existe déjà, on ne rejoue rien.
  insert into journal (garage_id, delta, libelle, source,
                       animation_id, stand_id, appareil_id, cle_idem)
  values (p_garage, p_delta, p_libelle, p_source,
          p_animation, p_stand, p_appareil, p_cle)
  on conflict (cle_idem) do nothing
  returning id into v_id;

  if v_id is null then
    -- Opération déjà enregistrée : on renvoie l'état, sans rien changer.
    return jsonb_build_object('solde', v_solde, 'deja_traite', true, 'journal_id', null);
  end if;

  if p_delta < 0 and v_solde + p_delta < 0 then
    raise exception 'SOLDE_INSUFFISANT'
      using detail = format('Solde %s, opération %s.', v_solde, p_delta);
  end if;

  update garages set solde = solde + p_delta where id = p_garage
    returning solde into v_solde;

  return jsonb_build_object('solde', v_solde, 'deja_traite', false, 'journal_id', v_id);
end;
$$;

-- ---------------------------------------------------------------------
-- Inscription d'un garage (§6)
-- Le bonus d'inscription est versé une seule fois par garage, quel que
-- soit le nombre d'accompagnants qui scannent le QR code.
-- ---------------------------------------------------------------------
create or replace function public.api_inscrire(p_jeton text, p_garage uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_g     garages;
  v_bonus integer := cfg_int('bonus_inscription', 10);
  v_app   uuid;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE'
      using detail = 'Le jeton d''appareil doit faire au moins 20 caractères.';
  end if;

  select * into v_g from garages where id = p_garage and actif;
  if not found then
    raise exception 'GARAGE_INCONNU'
      using detail = 'Ce garage n''est pas dans la liste des invités.';
  end if;

  insert into appareils (jeton, role, garage_id, libelle)
  values (p_jeton, 'garage', p_garage, v_g.nom)
  on conflict (jeton) do update set vu_le = now(), garage_id = excluded.garage_id
  returning id into v_app;

  if v_bonus > 0 then
    perform _ecrire(p_garage, v_bonus, 'Bienvenue au Forum', 'inscription',
                    'inscription:' || p_garage::text, v_app);
  end if;

  update garages set inscrit_le = coalesce(inscrit_le, now()) where id = p_garage;

  return api_etat(p_jeton);
end;
$$;

-- ---------------------------------------------------------------------
-- État complet pour l'écran garage (§7, §11, §14)
-- UNE seule requête ramène solde + historique + état de la grille.
-- C'est ce qui garde la charge de lecture très basse.
-- ---------------------------------------------------------------------
create or replace function public.api_etat(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a     appareils;
  v_g   garages;
  v_res jsonb;
begin
  a := _appareil(p_jeton);
  if a.garage_id is null then
    raise exception 'APPAREIL_SANS_GARAGE'
      using detail = 'Cet appareil est un appareil de service, pas un garage.';
  end if;

  select * into v_g from garages where id = a.garage_id;

  select jsonb_build_object(
    'garage', jsonb_build_object(
        'id', v_g.id, 'nom', v_g.nom, 'ville', v_g.ville, 'solde', v_g.solde),
    'cout_grille', cfg_int('cout_grille', 20),
    'cases_libres', (select count(*) from grille where garage_id is null),
    -- 100 caractères : '0' = libre, '1' = déjà jouée. 100 octets au total.
    'grille', (select string_agg(case when garage_id is null then '0' else '1' end, ''
                                 order by numero) from grille),
    'mes_lots', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'numero', numero, 'lot', lot, 'code_retrait', code_retrait, 'remis', remis)
               order by numero)
        from grille where garage_id = v_g.id and gagnante), '[]'::jsonb),
    'operations', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'heure', to_char(cree_le at time zone 'Europe/Paris', 'HH24:MI'),
                 'libelle', libelle, 'source', source, 'delta', delta)
               order by id desc)
        from (select * from journal where garage_id = v_g.id
              order by id desc limit 12) d), '[]'::jsonb)
  ) into v_res;

  return v_res;
end;
$$;

-- ---------------------------------------------------------------------
-- Recherche de garage — personnel uniquement (§8, §10)
-- ---------------------------------------------------------------------
create or replace function public.api_chercher(p_jeton text, p_q text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v jsonb;
begin
  a := _exige_role(p_jeton, array['animateur','fournisseur','admin']);

  select coalesce(jsonb_agg(x order by x->>'nom'), '[]'::jsonb) into v
  from (
    select jsonb_build_object('id', id, 'nom', nom, 'ville', ville, 'solde', solde) as x,
           nom
    from garages
    where actif
      and (coalesce(p_q, '') = '' or recherche like '%' || norm(p_q) || '%')
    order by nom
    limit 12
  ) s;

  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- Animation : participation puis résultat (§8, §9)
-- ---------------------------------------------------------------------
create or replace function public.api_participation(
  p_jeton text, p_garage uuid, p_animation uuid, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_an animations;
  v_r  jsonb;
begin
  a := _exige_role(p_jeton, array['animateur','admin']);
  select * into v_an from animations where id = p_animation and actif;
  if not found then
    raise exception 'ANIMATION_INCONNUE' using detail = 'Animation introuvable ou inactive.';
  end if;

  if v_an.cout = 0 then
    return jsonb_build_object('solde', (select solde from garages where id = p_garage),
                              'deja_traite', false, 'gratuit', true);
  end if;

  v_r := _ecrire(p_garage, -v_an.cout, v_an.nom || ' · participation', 'animation',
                 p_cle, a.id, v_an.id);
  return v_r || jsonb_build_object('animation', v_an.nom, 'cout', v_an.cout);
end;
$$;

create or replace function public.api_resultat(
  p_jeton text, p_garage uuid, p_bareme uuid, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_b bareme;
  v_an animations;
  v_r jsonb;
begin
  a := _exige_role(p_jeton, array['animateur','admin']);
  select * into v_b from bareme where id = p_bareme;
  if not found then
    raise exception 'BAREME_INCONNU' using detail = 'Résultat introuvable.';
  end if;
  select * into v_an from animations where id = v_b.animation_id;

  if v_b.points = 0 then
    -- Résultat nul : on ne pollue pas le journal d'une écriture à zéro.
    return jsonb_build_object(
      'solde', (select solde from garages where id = p_garage),
      'deja_traite', false, 'points', 0,
      'animation', v_an.nom, 'resultat', v_b.libelle);
  end if;

  v_r := _ecrire(p_garage, v_b.points,
                 v_an.nom || ' · ' || lower(v_b.libelle), 'animation',
                 p_cle, a.id, v_an.id);
  return v_r || jsonb_build_object('points', v_b.points,
                                   'animation', v_an.nom, 'resultat', v_b.libelle);
end;
$$;

-- ---------------------------------------------------------------------
-- Fournisseur : attribution de points avec garde-fous (§10)
-- ---------------------------------------------------------------------
create or replace function public.api_points_achat(
  p_jeton text, p_garage uuid, p_points integer, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_s stands;
  v_cumul integer;
  v_r jsonb;
begin
  a := _exige_role(p_jeton, array['fournisseur','admin']);
  if a.stand_id is null then
    raise exception 'STAND_NON_RATTACHE'
      using detail = 'Cet appareil n''est rattaché à aucun stand.';
  end if;
  select * into v_s from stands where id = a.stand_id and actif;
  if not found then
    raise exception 'STAND_INCONNU' using detail = 'Stand introuvable ou inactif.';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'POINTS_INVALIDES' using detail = 'Le nombre de points doit être positif.';
  end if;
  if p_points > v_s.plafond_operation then
    raise exception 'PLAFOND_OPERATION'
      using detail = format('Maximum %s points par opération sur ce stand.', v_s.plafond_operation);
  end if;

  select coalesce(sum(delta), 0) into v_cumul from journal where stand_id = v_s.id;
  if v_cumul + p_points > v_s.plafond_soiree then
    raise exception 'PLAFOND_SOIREE'
      using detail = format('Ce stand a distribué %s points sur %s autorisés.',
                            v_cumul, v_s.plafond_soiree);
  end if;

  v_r := _ecrire(p_garage, p_points, 'Achat — ' || v_s.nom, 'fournisseur',
                 p_cle, a.id, null, v_s.id);
  return v_r || jsonb_build_object('stand', v_s.nom, 'points', p_points,
                                   'cumul_stand', v_cumul + p_points,
                                   'plafond_soiree', v_s.plafond_soiree);
end;
$$;

-- ---------------------------------------------------------------------
-- Grille des lots (§11)
-- Débit et réservation dans la même transaction. Une case déjà prise
-- fait échouer l'opération entière : pas de point débité pour rien.
-- ---------------------------------------------------------------------
create or replace function public.api_jouer_case(
  p_jeton text, p_numero integer, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a         appareils;
  v_cout    integer := cfg_int('cout_grille', 20);
  v_ancien  bigint;
  v_case    grille;
  v_r       jsonb;
  v_code    text;
begin
  a := _appareil(p_jeton);
  if a.garage_id is null then
    raise exception 'APPAREIL_SANS_GARAGE' using detail = 'Seul un garage peut jouer.';
  end if;

  -- Rejeu : la clé a déjà servi, on renvoie le résultat d'origine
  -- au lieu de rejouer ou de renvoyer une erreur.
  select id into v_ancien from journal where cle_idem = p_cle;
  if v_ancien is not null then
    select * into v_case from grille where journal_id = v_ancien;
    return jsonb_build_object(
      'deja_traite', true,
      'solde', (select solde from garages where id = a.garage_id),
      'numero', v_case.numero, 'gagnante', coalesce(v_case.gagnante, false),
      'lot', v_case.lot, 'code_retrait', v_case.code_retrait);
  end if;

  if p_numero is null or p_numero < 1 or p_numero > 100 then
    raise exception 'CASE_INVALIDE' using detail = 'Le numéro doit être entre 1 et 100.';
  end if;

  -- Débit d'abord : si le solde est insuffisant, rien n'est réservé.
  v_r := _ecrire(a.garage_id, -v_cout,
                 'Grille des lots · case n°' || p_numero, 'recompense', p_cle, a.id);

  v_code := upper(substr(md5(p_cle || p_numero::text), 1, 5));

  -- Réservation atomique : le premier arrivé prend la case, le second
  -- obtient 0 ligne mise à jour et voit sa transaction annulée.
  update grille
     set garage_id    = a.garage_id,
         journal_id   = (v_r->>'journal_id')::bigint,
         joue_le      = now(),
         code_retrait = case when gagnante then v_code else null end
   where numero = p_numero
     and garage_id is null
  returning * into v_case;

  if not found then
    raise exception 'CASE_DEJA_PRISE'
      using detail = format('La case n°%s vient d''être prise. Choisissez-en une autre.', p_numero);
  end if;

  return v_r || jsonb_build_object(
    'numero', v_case.numero, 'gagnante', v_case.gagnante,
    'lot', v_case.lot, 'code_retrait', v_case.code_retrait,
    'cases_libres', (select count(*) from grille where garage_id is null));
end;
$$;

-- ---------------------------------------------------------------------
-- Connexion du personnel par code PIN de stand ou d'animation
-- ---------------------------------------------------------------------
create or replace function public.api_connexion(p_jeton text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_an  animations;
  v_st  stands;
  v_app uuid;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE' using detail = 'Jeton d''appareil trop court.';
  end if;
  if p_pin is null or length(trim(p_pin)) < 4 then
    raise exception 'PIN_INVALIDE' using detail = 'Le code doit faire au moins 4 chiffres.';
  end if;

  select * into v_an from animations where code_pin = trim(p_pin) and actif;
  if found then
    insert into appareils (jeton, role, animation_id, libelle)
    values (p_jeton, 'animateur', v_an.id, v_an.nom)
    on conflict (jeton) do update
      set role = 'animateur', animation_id = v_an.id, libelle = v_an.nom, vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'animateur', 'animation_id', v_an.id,
                              'libelle', v_an.nom, 'cout', v_an.cout,
                              'bareme', (select jsonb_agg(jsonb_build_object(
                                    'id', id, 'libelle', libelle, 'points', points)
                                  order by ordre, points desc)
                                from bareme where animation_id = v_an.id));
  end if;

  select * into v_st from stands where code_pin = trim(p_pin) and actif;
  if found then
    insert into appareils (jeton, role, stand_id, libelle)
    values (p_jeton, 'fournisseur', v_st.id, v_st.nom)
    on conflict (jeton) do update
      set role = 'fournisseur', stand_id = v_st.id, libelle = v_st.nom, vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'fournisseur', 'stand_id', v_st.id,
                              'libelle', v_st.nom,
                              'plafond_operation', v_st.plafond_operation);
  end if;

  if trim(p_pin) = coalesce((select valeur from config where cle = 'pin_admin'), '@@aucun@@') then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'admin', 'Équipe Bony')
    on conflict (jeton) do update
      set role = 'admin', libelle = 'Équipe Bony', vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'admin', 'libelle', 'Équipe Bony');
  end if;

  raise exception 'PIN_INCONNU' using detail = 'Code non reconnu.';
end;
$$;

-- ---------------------------------------------------------------------
-- Supervision Bony (§12, §18)
-- ---------------------------------------------------------------------
create or replace function public.api_supervision(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_circulation int;
  v_cout int := cfg_int('cout_grille', 20);
  v_libres int;
begin
  a := _exige_role(p_jeton, array['admin']);

  select coalesce(sum(solde), 0) into v_circulation from garages;
  select count(*) into v_libres from grille where garage_id is null;

  return jsonb_build_object(
    'garages_invites',  (select count(*) from garages where actif),
    'garages_actifs',   (select count(*) from garages where inscrit_le is not null),
    'points_circulation', v_circulation,
    'points_emis',      (select coalesce(sum(delta), 0) from journal where delta > 0),
    'cases_jouees',     100 - v_libres,
    'cases_libres',     v_libres,
    'parties_financables', floor(v_circulation::numeric / greatest(v_cout, 1))::int,
    'tension',          (floor(v_circulation::numeric / greatest(v_cout, 1))::int > v_libres),
    'lots_gagnes',      (select count(*) from grille where gagnante and garage_id is not null),
    'lots_remis',       (select count(*) from grille where remis),
    'ecarts_solde',     (select count(*) from verifier_soldes()),
    'par_stand', coalesce((
      select jsonb_agg(jsonb_build_object('stand', s.nom,
               'distribue', coalesce(t.total, 0), 'plafond', s.plafond_soiree)
             order by coalesce(t.total, 0) desc)
      from stands s
      left join (select stand_id, sum(delta) as total from journal
                 where stand_id is not null group by stand_id) t on t.stand_id = s.id
      ), '[]'::jsonb),
    'journal', coalesce((
      select jsonb_agg(jsonb_build_object(
               'heure', to_char(j.cree_le at time zone 'Europe/Paris', 'HH24:MI'),
               'garage', g.nom, 'libelle', j.libelle,
               'source', j.source, 'delta', j.delta) order by j.id desc)
      from (select * from journal order by id desc limit 15) j
      join garages g on g.id = j.garage_id), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Correction manuelle (§12) — ajoute une écriture, n'écrase jamais rien
-- ---------------------------------------------------------------------
create or replace function public.api_corriger(
  p_jeton text, p_garage uuid, p_delta integer, p_motif text, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['admin']);
  if p_delta = 0 then
    raise exception 'DELTA_NUL' using detail = 'Une correction de zéro point n''a pas de sens.';
  end if;
  return _ecrire(p_garage, p_delta,
                 'Correction · ' || coalesce(nullif(trim(p_motif), ''), 'équipe Bony'),
                 'administration', p_cle, a.id);
end;
$$;

-- ---------------------------------------------------------------------
-- Remise d'un lot (§11) — comble le trou du cahier des charges
-- ---------------------------------------------------------------------
create or replace function public.api_remettre_lot(p_jeton text, p_numero integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils; v_case grille;
begin
  a := _exige_role(p_jeton, array['admin']);
  update grille set remis = true, remis_le = now()
   where numero = p_numero and gagnante and garage_id is not null and not remis
  returning * into v_case;
  if not found then
    raise exception 'LOT_NON_REMISABLE'
      using detail = 'Case inconnue, non gagnante, non jouée, ou lot déjà remis.';
  end if;
  return jsonb_build_object('numero', v_case.numero, 'lot', v_case.lot, 'remis', true);
end;
$$;

-- =====================================================================
--  Droits : les rôles publics ne peuvent QUE appeler ces fonctions.
--  Les fonctions internes (préfixe _) restent inaccessibles.
-- =====================================================================
revoke all on function public._ecrire(uuid,integer,text,text,text,uuid,uuid,uuid) from anon, authenticated;
revoke all on function public._appareil(text) from anon, authenticated;
revoke all on function public._exige_role(text,text[]) from anon, authenticated;
revoke all on function public.verifier_soldes() from anon, authenticated;

grant execute on function public.api_inscrire(text,uuid)                   to anon;
grant execute on function public.api_etat(text)                            to anon;
grant execute on function public.api_chercher(text,text)                   to anon;
grant execute on function public.api_participation(text,uuid,uuid,text)    to anon;
grant execute on function public.api_resultat(text,uuid,uuid,text)         to anon;
grant execute on function public.api_points_achat(text,uuid,integer,text)  to anon;
grant execute on function public.api_jouer_case(text,integer,text)         to anon;
grant execute on function public.api_connexion(text,text)                  to anon;
grant execute on function public.api_supervision(text)                     to anon;
grant execute on function public.api_corriger(text,uuid,integer,text,text) to anon;
grant execute on function public.api_remettre_lot(text,integer)            to anon;
