-- =====================================================================
--  Forum Pièces Bony 2026 — 06 — Le bingo
--
--  La grille des 100 cases devient le bingo. Trois natures de case :
--    perdante  (50)  rien
--    lot       (45)  un lot remis au comptoir
--    billet    ( 5)  une place au grand tirage du soir, sur écran géant
--
--  DEUX MODES DE RÉVÉLATION, un seul réglage à basculer :
--    'immediate' — le garage découvre à l'achat (le ticket à gratter :
--                  la boucle gagner / rechercher des points / rejouer)
--    'differee'  — le garage achète à l'aveugle, tout se révèle le soir
--                  sur l'écran géant (le grand suspense collectif)
--
--  Le choix se fait dans config.revelation, jusqu'à la dernière minute.
--  Toute la mécanique d'achat est commune : ce qui change, c'est
--  uniquement le moment où grille.revele_le est renseigné.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Réglages
-- ---------------------------------------------------------------------
insert into public.config (cle, valeur, description) values
  ('revelation', 'immediate',
   'immediate = le garage découvre à l''achat · differee = tout se révèle le soir'),
  ('tirage_ouvert', 'non',
   'oui quand le grand tirage du soir a été ouvert par l''équipe Bony')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- 2. La grille : nature des cases, et séparation achat / révélation
-- ---------------------------------------------------------------------
alter table public.grille drop constraint if exists grille_lot_coherent;
alter table public.grille drop constraint if exists grille_remise_coherente;

alter table public.grille
  add column if not exists nature text not null default 'perdante',
  add column if not exists achete_le timestamptz,
  add column if not exists revele_le timestamptz;

-- reprise de l'ancien booléen avant de le supprimer
update public.grille set nature = 'lot' where gagnante and nature = 'perdante';
update public.grille set achete_le = joue_le where achete_le is null and joue_le is not null;
update public.grille set revele_le = joue_le where revele_le is null and joue_le is not null;

alter table public.grille drop column if exists gagnante;
alter table public.grille drop column if exists joue_le;

alter table public.grille
  add constraint grille_nature_valide
    check (nature in ('perdante','lot','billet'));
alter table public.grille
  add constraint grille_lot_nomme
    check (nature <> 'lot' or lot is not null);
-- on ne révèle que ce qui a été acheté
alter table public.grille
  add constraint grille_revelation_apres_achat
    check (revele_le is null or achete_le is not null);
-- on ne remet un lot que sur une case achetée, révélée et gagnante
alter table public.grille
  add constraint grille_remise_coherente
    check (not remis or (nature = 'lot' and garage_id is not null and revele_le is not null));

create index if not exists grille_nature_idx on public.grille (nature);

-- ---------------------------------------------------------------------
-- 3. Répartition : 50 perdantes · 45 lots · 5 billets
--    Les numéros sont figés ici, donc reproductibles et vérifiables.
--    Les libellés « à définir » sont des marque-places assumés.
-- ---------------------------------------------------------------------
-- La composition de la grille change : tout état de jeu antérieur perd son
-- sens (une case achetée comme « lot » pourrait devenir perdante). On remet
-- donc la grille à neuf avant de redistribuer. À l'événement, ce fichier
-- s'exécutera sur une grille vierge et cette étape ne fera rien.
update public.grille
   set garage_id = null, journal_id = null, achete_le = null, revele_le = null,
       code_retrait = null, remis = false, remis_le = null,
       nature = 'perdante', lot = null;

-- 5 billets pour le grand tirage
update public.grille set nature = 'billet', lot = 'Billet pour le grand tirage'
 where numero in (17, 34, 58, 76, 93);

-- 45 lots
update public.grille g set nature = 'lot', lot = v.lot
from (values
  ( 3,'Coffret à outils 120 pièces'), ( 7,'Enceinte nomade'),
  (11,'Bon d''achat 100 €'),          (13,'Nettoyeur haute pression'),
  (18,'Panier gourmand d''Auvergne'), (22,'Bon d''achat 50 €'),
  (26,'Caméra de recul sans fil'),    (29,'Coffret de douilles'),
  (31,'Bon d''achat 100 €'),          (38,'Casque Bluetooth'),
  (40,'Ballon officiel ASM'),         (44,'Bon d''achat 50 €'),
  (45,'Week-end pour deux en Auvergne'),
  ( 5,'Lot à définir 14'), ( 9,'Lot à définir 15'), (15,'Lot à définir 16'),
  (20,'Lot à définir 17'), (24,'Lot à définir 18'), (28,'Lot à définir 19'),
  (36,'Lot à définir 20'), (42,'Lot à définir 21'), (47,'Lot à définir 22'),
  (49,'Lot à définir 23'), (52,'Lot à définir 24'), (54,'Lot à définir 25'),
  (57,'Lot à définir 26'), (61,'Lot à définir 27'), (63,'Lot à définir 28'),
  (66,'Lot à définir 29'), (68,'Lot à définir 30'), (70,'Lot à définir 31'),
  (72,'Lot à définir 32'), (74,'Lot à définir 33'), (77,'Lot à définir 34'),
  (79,'Lot à définir 35'), (81,'Lot à définir 36'), (83,'Lot à définir 37'),
  (86,'Lot à définir 38'), (88,'Lot à définir 39'), (90,'Lot à définir 40'),
  (91,'Lot à définir 41'), (95,'Lot à définir 42'), (97,'Lot à définir 43'),
  (98,'Lot à définir 44'), (99,'Lot à définir 45')
) as v(numero, lot)
where g.numero = v.numero;

-- ---------------------------------------------------------------------
-- 4. Le grand tirage du soir
--    Chaque manche est tracée : on peut rejouer l'historique et
--    justifier le résultat, ce qui compte quand un lot est en jeu.
-- ---------------------------------------------------------------------
create table if not exists public.tirage (
  id        bigint generated always as identity primary key,
  manche    integer not null,
  numero    integer not null references public.grille(numero),
  garage_id uuid not null references public.garages(id),
  sorti     boolean not null default false,   -- éliminé à cette manche
  gagnant   boolean not null default false,
  cree_le   timestamptz not null default now(),
  unique (manche, numero)
);
create index if not exists tirage_manche_idx on public.tirage (manche desc);

alter table public.tirage enable row level security;
revoke all on public.tirage from anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Achat d'une case — remplace api_jouer_case
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
  select id into v_ancien from journal where cle_idem = p_cle;
  if v_ancien is not null then
    select * into v_case from grille where journal_id = v_ancien;
    return _resultat_case(v_case, true, (select solde from garages where id = a.garage_id));
  end if;

  if p_numero is null or p_numero < 1 or p_numero > 100 then
    raise exception 'CASE_INVALIDE' using detail = 'Le numéro doit être entre 1 et 100.';
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

-- Mise en forme du résultat d'une case, selon qu'elle est révélée ou non
create or replace function public._resultat_case(
  p_case grille, p_deja boolean, p_solde integer)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'numero', p_case.numero,
    'deja_traite', p_deja,
    'solde', p_solde,
    'revelee', p_case.revele_le is not null,
    'nature', case when p_case.revele_le is null then null else p_case.nature end,
    'lot', case when p_case.revele_le is null or p_case.nature = 'perdante'
                then null else p_case.lot end,
    'code_retrait', p_case.code_retrait,
    'cases_libres', (select count(*) from grille where garage_id is null)
  )
$$;

-- ---------------------------------------------------------------------
-- 6. État du garage — enrichi du bingo
-- ---------------------------------------------------------------------
create or replace function public.api_etat(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a   appareils;
  v_g garages;
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
    'cases_libres', (select count(*) from grille where garage_id is null),
    'billets_restants', (select count(*) from grille where nature = 'billet' and garage_id is null),
    -- 100 caractères : '0' libre, '1' déjà prise
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
-- 7. Révélation collective (mode différé) — équipe Bony, sur scène
-- ---------------------------------------------------------------------
create or replace function public.api_reveler(p_jeton text, p_numero integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils; v_n integer;
begin
  a := _exige_role(p_jeton, array['admin']);

  -- p_numero nul : on révèle tout d'un coup. Sinon case par case, pour
  -- dérouler le suspense au rythme voulu sur l'écran géant.
  update grille
     set revele_le = now(),
         code_retrait = case when nature = 'lot'
                             then upper(substr(md5(numero::text || achete_le::text), 1, 5))
                             else null end
   where achete_le is not null and revele_le is null
     and (p_numero is null or numero = p_numero);
  get diagnostics v_n = row_count;

  return jsonb_build_object('revelees', v_n, 'restantes',
    (select count(*) from grille where achete_le is not null and revele_le is null));
end;
$$;

-- ---------------------------------------------------------------------
-- 8. Le grand tirage, manche par manche
-- ---------------------------------------------------------------------
create or replace function public.api_tirage_etat(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils; v_manche integer;
begin
  a := _exige_role(p_jeton, array['admin']);
  select coalesce(max(manche), 0) into v_manche from tirage;

  return jsonb_build_object(
    'ouvert', coalesce((select valeur from config where cle = 'tirage_ouvert'), 'non') = 'oui',
    'manche', v_manche,
    'billets_vendus', (select count(*) from grille where nature = 'billet' and garage_id is not null),
    'billets_reveles', (select count(*) from grille
                        where nature = 'billet' and garage_id is not null and revele_le is not null),
    'en_course', coalesce((
      select jsonb_agg(jsonb_build_object('numero', t.numero, 'garage', g.nom, 'ville', g.ville)
                       order by g.nom)
      from tirage t join garages g on g.id = t.garage_id
      where t.manche = v_manche and not t.sorti), '[]'::jsonb),
    'sortis', coalesce((
      select jsonb_agg(jsonb_build_object('numero', t.numero, 'garage', g.nom, 'manche', t.manche)
                       order by t.manche, g.nom)
      from tirage t join garages g on g.id = t.garage_id
      where t.sorti), '[]'::jsonb),
    'gagnant', (select jsonb_build_object('numero', t.numero, 'garage', g.nom, 'ville', g.ville)
                from tirage t join garages g on g.id = t.garage_id
                where t.gagnant limit 1)
  );
end;
$$;

/* Ouvre le tirage : photographie les billets vendus et révélés.
   À partir de là, plus aucun billet ne peut entrer dans la course. */
create or replace function public.api_tirage_ouvrir(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils; v_n integer;
begin
  a := _exige_role(p_jeton, array['admin']);
  if exists (select 1 from tirage) then
    raise exception 'TIRAGE_DEJA_OUVERT'
      using detail = 'Le tirage a déjà été ouvert. Utilisez la remise à zéro pour recommencer.';
  end if;

  insert into tirage (manche, numero, garage_id)
  select 1, numero, garage_id
    from grille
   where nature = 'billet' and garage_id is not null and revele_le is not null;
  get diagnostics v_n = row_count;

  if v_n = 0 then
    raise exception 'AUCUN_BILLET'
      using detail = 'Aucun billet vendu et révélé : rien à tirer.';
  end if;

  update config set valeur = 'oui' where cle = 'tirage_ouvert';
  return api_tirage_etat(p_jeton);
end;
$$;

/* Une manche : élimine environ la moitié des concurrents. Quand il n'en
   reste qu'un, il est déclaré gagnant. Chaque manche est enregistrée. */
create or replace function public.api_tirage_manche(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_manche integer;
  v_reste  integer;
  v_garder integer;
begin
  a := _exige_role(p_jeton, array['admin']);
  select coalesce(max(manche), 0) into v_manche from tirage;
  if v_manche = 0 then
    raise exception 'TIRAGE_NON_OUVERT' using detail = 'Ouvrez d''abord le tirage.';
  end if;
  if exists (select 1 from tirage where gagnant) then
    raise exception 'TIRAGE_TERMINE' using detail = 'Le gagnant est déjà désigné.';
  end if;

  select count(*) into v_reste from tirage where manche = v_manche and not sorti;

  if v_reste = 1 then
    update tirage set gagnant = true where manche = v_manche and not sorti;
    return api_tirage_etat(p_jeton);
  end if;

  -- on garde la moitié, au moins un
  v_garder := greatest(1, v_reste / 2);

  insert into tirage (manche, numero, garage_id, sorti)
  select v_manche + 1, numero, garage_id, false
    from (select numero, garage_id from tirage
           where manche = v_manche and not sorti
           order by random() limit v_garder) s;

  -- les non retenus sont tracés comme sortis à la nouvelle manche
  insert into tirage (manche, numero, garage_id, sorti)
  select v_manche + 1, t.numero, t.garage_id, true
    from tirage t
   where t.manche = v_manche and not t.sorti
     and t.numero not in (select numero from tirage where manche = v_manche + 1);

  if (select count(*) from tirage where manche = v_manche + 1 and not sorti) = 1 then
    update tirage set gagnant = true where manche = v_manche + 1 and not sorti;
  end if;

  return api_tirage_etat(p_jeton);
end;
$$;

create or replace function public.api_tirage_reset(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['admin']);
  delete from tirage;
  update config set valeur = 'non' where cle = 'tirage_ouvert';
  return jsonb_build_object('remis_a_zero', true);
end;
$$;

-- ---------------------------------------------------------------------
-- 9. Fonctions existantes à réaligner sur « nature »
-- ---------------------------------------------------------------------
create or replace function public.api_lots(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'numero', gr.numero, 'lot', gr.lot, 'code_retrait', gr.code_retrait,
             'garage', g.nom, 'ville', g.ville, 'remis', gr.remis,
             'joue_a', to_char(gr.achete_le at time zone 'Europe/Paris', 'HH24:MI'))
           order by gr.remis, gr.achete_le)
    from grille gr
    join garages g on g.id = gr.garage_id
    where gr.nature = 'lot' and gr.garage_id is not null and gr.revele_le is not null),
    '[]'::jsonb);
end;
$$;

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
   where numero = p_numero and nature = 'lot'
     and garage_id is not null and revele_le is not null and not remis
  returning * into v_case;
  if not found then
    raise exception 'LOT_NON_REMISABLE'
      using detail = 'Case inconnue, sans lot, non révélée, ou lot déjà remis.';
  end if;
  return jsonb_build_object('numero', v_case.numero, 'lot', v_case.lot, 'remis', true);
end;
$$;

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
-- 10. Droits
-- ---------------------------------------------------------------------
revoke all on function public._resultat_case(public.grille, boolean, integer) from anon, authenticated;
grant execute on function public.api_jouer_case(text,integer,text)   to anon;
grant execute on function public.api_etat(text)                     to anon;
grant execute on function public.api_reveler(text,integer)          to anon;
grant execute on function public.api_tirage_etat(text)              to anon;
grant execute on function public.api_tirage_ouvrir(text)            to anon;
grant execute on function public.api_tirage_manche(text)            to anon;
grant execute on function public.api_tirage_reset(text)             to anon;
grant execute on function public.api_lots(text)                     to anon;
grant execute on function public.api_remettre_lot(text,integer)     to anon;
grant execute on function public.api_supervision(text)              to anon;

-- ---------------------------------------------------------------------
-- 11. Contrôle
-- ---------------------------------------------------------------------
select nature, count(*) as cases from public.grille group by nature order by nature;
