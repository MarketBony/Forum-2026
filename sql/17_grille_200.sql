-- =====================================================================
--  Forum Pièces Bony 2026 — 17 — La grille passe à 200 cases
--
--  POURQUOI 200 ET PAS 150 :
--  Bony met 100 lots au Forum. Il faut donc au moins 100 cases
--  gagnantes. À 150 cases, gagner deviendrait 2 fois sur 3 : la case
--  ne serait plus un pari mais un distributeur. À 200, on retrouve la
--  chance d'une sur deux qui était le principe d'origine, et il y a
--  deux fois plus de place pour les garages arrivés en fin de journée.
--
--  POURQUOI UN PLAFOND DE CASES PAR GARAGE :
--  le modèle de points donne ~86 points par garage sur la journée, soit
--  ~12 900 points émis pour 150 garages. À 20 points la case, la
--  demande vaut ~645 cases pour 200 disponibles. Sans plafond, la
--  grille est vidée en début d'après-midi et les garages qui arrivent
--  après ne trouvent plus une seule case. (Modèle, pas mesure : aucune
--  donnée de terrain de l'édition précédente ne l'étaye.)
--
--  Le plafond SE LÈVE en direct, il ne se baisse jamais — baisser
--  pénaliserait ceux qui ont déjà acheté :
--      update config set valeur = '5' where cle = 'cases_max_garage';
--      update config set valeur = '0' where cle = 'cases_max_garage';  -- illimité
--
--  ⚠️ CE FICHIER NE POSE AUCUN LOT. Il ne fait que la structure.
--  Les cases 101 à 200 arrivent en « perdante ». La composition
--  (100 lots, dont les 15 gros lots du soir) est dans 18_lots.sql, en
--  attente de l'arbitrage Bony sur le mode de remise des gros lots.
--
--  Rejouable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Le nouveau plafond de numérotation
-- ---------------------------------------------------------------------
alter table public.grille drop constraint if exists grille_numero_check;
alter table public.grille
  add constraint grille_numero_check check (numero between 1 and 200);

insert into public.grille (numero)
select generate_series(101, 200)
on conflict (numero) do nothing;

-- ---------------------------------------------------------------------
-- 2. Le plafond de cases par garage
--    0 = illimité, ce qui est l'ancien comportement à l'identique.
-- ---------------------------------------------------------------------
insert into public.config (cle, valeur, description) values
  ('cases_max_garage', '3',
   'Cases maximum par garage · 0 = illimité · se lève en direct, ne se baisse jamais')
on conflict (cle) do update set valeur = excluded.valeur,
                                description = excluded.description;

-- ---------------------------------------------------------------------
-- 3. Achat d'une case : plafond par garage, et borne lue dans la table
--
--  La borne du numéro n'est plus écrite en dur. Elle se déduit de la
--  table : ajouter des cases l'an prochain ne demandera plus de
--  retoucher la fonction, et on ne peut plus se retrouver avec une
--  grille de 200 cases dont la fonction n'en accepte que 100.
-- ---------------------------------------------------------------------
create or replace function public.api_jouer_case(
  p_jeton text, p_numero integer, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a        appareils;
  v_cout   integer := cfg_int('cout_grille', 20);
  v_max    integer := cfg_int('cases_max_garage', 0);
  v_deja   integer;
  v_mode   text := coalesce((select valeur from config where cle = 'revelation'), 'immediate');
  v_ancien bigint;
  v_case   grille;
  v_r      jsonb;
  v_code   text;
begin
  a := _appareil(p_jeton);
  if a.garage_id is null then
    raise exception 'APPAREIL_SANS_GARAGE' using detail = 'Seul un garage peut jouer.';
  end if;

  -- Rejeu : la clé a déjà servi, on renvoie le résultat d'origine.
  -- IMPÉRATIVEMENT avant le plafond : sinon un réseau qui bégaye sur la
  -- dernière case autorisée ferait répondre « plafond atteint » à un
  -- garage qui a bel et bien payé sa case.
  select id into v_ancien from journal where cle_idem = p_cle;
  if v_ancien is not null then
    select * into v_case from grille where journal_id = v_ancien;
    return _resultat_case(v_case, true, (select solde from garages where id = a.garage_id));
  end if;

  if p_numero is null or not exists (select 1 from grille where numero = p_numero) then
    raise exception 'CASE_INVALIDE'
      using detail = format('Le numéro doit être entre 1 et %s.',
                            (select max(numero) from grille));
  end if;

  if v_max > 0 then
    select count(*) into v_deja from grille where garage_id = a.garage_id;
    if v_deja >= v_max then
      raise exception 'PLAFOND_CASES'
        using detail = format('Vous avez déjà pris vos %s cases. L''équipe Bony peut lever le plafond en fin de journée.', v_max);
    end if;
  end if;

  -- Débit d'abord : si le solde est insuffisant, rien n'est réservé.
  v_r := _ecrire(a.garage_id, -v_cout,
                 'Bingo · case n°' || p_numero, 'recompense', p_cle, a.id);

  v_code := upper(substr(md5(p_cle || p_numero::text), 1, 5));

  -- Réservation atomique. En mode différé, revele_le et code_retrait
  -- restent nuls : la case est achetée, pas encore ouverte.
  update grille
     set garage_id    = a.garage_id,
         journal_id   = (v_r->>'journal_id')::bigint,
         achete_le    = now(),
         revele_le    = case when v_mode = 'immediate' then now() else null end,
         code_retrait = case when v_mode = 'immediate' and nature = 'lot' then v_code else null end
   where numero = p_numero
     and garage_id is null
  returning * into v_case;

  if not found then
    raise exception 'CASE_DEJA_PRISE'
      using detail = format('La case n°%s vient d''être prise. Choisissez-en une autre.', p_numero);
  end if;

  return _resultat_case(v_case, false, (v_r->>'solde')::int);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. L'état du garage annonce la taille de la grille et son plafond
--
--  L'application déduisait le nombre de cases d'un « 100 » écrit en
--  dur dans app.js. C'est la base qui fait foi désormais : changer la
--  taille de la grille ne demandera plus de redéployer le front.
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
  v_max integer := cfg_int('cases_max_garage', 0);
begin
  a := _appareil(p_jeton);
  if a.garage_id is null then
    raise exception 'APPAREIL_SANS_GARAGE'
      using detail = 'Cet appareil est un appareil de service, pas un garage.';
  end if;
  select * into v_g from garages where id = a.garage_id;

  return jsonb_build_object(
    'garage', jsonb_build_object(
        'id', v_g.id, 'nom', v_g.nom, 'ville', v_g.ville, 'solde', v_g.solde),
    'cout_grille', cfg_int('cout_grille', 20),
    'revelation', coalesce((select valeur from config where cle = 'revelation'), 'immediate'),
    'cases_total', (select count(*) from grille),
    'cases_libres', (select count(*) from grille where garage_id is null),
    'cases_max', v_max,
    'mes_cases_nb', (select count(*) from grille where garage_id = v_g.id),
    'billets_restants', (select count(*) from grille where nature = 'billet' and garage_id is null),
    -- un caractère par case : '0' libre, '1' déjà prise. 200 octets.
    'grille', (select string_agg(case when garage_id is null then '0' else '1' end, ''
                                 order by numero) from grille),
    -- ce que le garage possède : révélé ou non
    'mes_cases', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'numero', numero,
                 'revelee', revele_le is not null,
                 'nature', case when revele_le is null then null else nature end,
                 'lot', case when revele_le is null or nature = 'perdante' then null else lot end,
                 'code_retrait', code_retrait,
                 'remis', remis)
               order by numero)
        from grille where garage_id = v_g.id), '[]'::jsonb),
    'operations', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'heure', to_char(cree_le at time zone 'Europe/Paris', 'HH24:MI'),
                 'libelle', libelle, 'source', source, 'delta', delta)
               order by id desc)
        from (select * from journal where garage_id = v_g.id
              order by id desc limit 12) d), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 5. La supervision compte les cases dans la table, et non sur 100
--
--  « par_stand » est restreint aux stands actifs : les 5 stands de
--  démonstration désactivés en 15 n'ont plus à encombrer un tableau
--  qui en compte déjà 23.
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
  v_total int;
begin
  a := _exige_role(p_jeton, array['admin']);
  select coalesce(sum(solde), 0) into v_circulation from garages;
  select count(*) into v_libres from grille where garage_id is null;
  select count(*) into v_total  from grille;

  return jsonb_build_object(
    'garages_invites',  (select count(*) from garages where actif),
    'garages_actifs',   (select count(*) from garages where inscrit_le is not null),
    'points_circulation', v_circulation,
    'points_emis',      (select coalesce(sum(delta), 0) from journal where delta > 0),
    'cases_total',      v_total,
    'cases_jouees',     v_total - v_libres,
    'cases_libres',     v_libres,
    'cases_max_garage', cfg_int('cases_max_garage', 0),
    'parties_financables', floor(v_circulation::numeric / greatest(v_cout, 1))::int,
    'tension',          (floor(v_circulation::numeric / greatest(v_cout, 1))::int > v_libres),
    'revelation',       coalesce((select valeur from config where cle = 'revelation'), 'immediate'),
    'a_reveler',        (select count(*) from grille where achete_le is not null and revele_le is null),
    'lots_gagnes',      (select count(*) from grille where nature = 'lot' and garage_id is not null),
    'lots_remis',       (select count(*) from grille where remis),
    'billets_vendus',   (select count(*) from grille where nature = 'billet' and garage_id is not null),
    'billets_restants', (select count(*) from grille where nature = 'billet' and garage_id is null),
    'ecarts_solde',     (select count(*) from verifier_soldes()),
    'par_stand', coalesce((
      select jsonb_agg(jsonb_build_object('stand', s.nom,
               'distribue', coalesce(t.total, 0), 'plafond', s.plafond_soiree)
             order by coalesce(t.total, 0) desc)
      from stands s
      left join (select stand_id, sum(delta) as total from journal
                 where stand_id is not null group by stand_id) t on t.stand_id = s.id
      where s.actif
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
-- 6. Contrôle immédiat
-- ---------------------------------------------------------------------
do $$
declare v_n int; v_max int;
begin
  select count(*) into v_n from public.grille;
  select cfg_int('cases_max_garage', 0) into v_max;
  if v_n <> 200 then
    raise exception '200 cases attendues, % trouvées', v_n;
  end if;
  if v_max <> 3 then
    raise exception 'plafond de cases attendu à 3, trouvé %', v_max;
  end if;
  raise notice '200 cases, plafond de % cases par garage.', v_max;
end;
$$;
