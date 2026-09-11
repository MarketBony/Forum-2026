-- =====================================================================
--  Forum Pièces Bony 2026 — 15 — Les 23 fournisseurs réels
--
--  Remplace les 5 stands de démonstration par les 23 stands du Forum,
--  et introduit le BARÈME PAR CATÉGORIE.
--
--  POURQUOI un barème et pas un simple plafond :
--  jusqu'ici le fournisseur choisissait un montant libre parmi quatre
--  paliers écrits en dur dans l'application (+5 / +10 / +20 / +50).
--  Le barème arrêté par Bony n'est pas le même d'une catégorie à
--  l'autre : « 200 à 699 € » chez FACOM, « 13 à 24 pneus » chez
--  MICHELIN, « Contact » chez CASTROL. Le représentant sur le stand
--  doit lire SON vocabulaire, pas un nombre de points à traduire dans
--  sa tête un verre à la main. Les paliers viennent donc de la base.
--
--  POURQUOI les PIN 2001 à 2023 :
--  l'alphabet des codes garage exclut O, I, 0 et 1. Un PIN qui
--  contient un 0 ou un 1 ne peut donc PAS heurter un code garage —
--  la collision est impossible par construction, pas par chance.
--  verifier_portes() le recontrôle quand même.
--
--  Rejouable : tout est en on conflict / idempotent.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La catégorie, portée par le stand
-- ---------------------------------------------------------------------
alter table public.stands
  add column if not exists categorie text;

-- ---------------------------------------------------------------------
-- 2. Le barème, porté par la catégorie
--
--  Il est volontairement recopié pour chacune des trois catégories qui
--  partagent aujourd'hui « Passage / Contact / Commande ». Si l'une des
--  trois change l'an prochain, c'est un update sur une ligne et non une
--  reprise du modèle.
-- ---------------------------------------------------------------------
create table if not exists public.bareme_stand (
  id        uuid primary key default gen_random_uuid(),
  categorie text    not null,
  libelle   text    not null,
  points    integer not null check (points > 0),
  ordre     integer not null default 0,
  unique (categorie, libelle)
);

create index if not exists bareme_stand_idx on public.bareme_stand (categorie, ordre);

-- Même verrouillage que partout ailleurs : RLS active, aucune policy,
-- les fonctions security definer sont les seules portes.
alter table public.bareme_stand enable row level security;
revoke all on public.bareme_stand from anon, authenticated;

-- La composition du barème change : on repart de zéro pour que le
-- fichier soit rejouable sans laisser d'anciens paliers orphelins.
delete from public.bareme_stand;

insert into public.bareme_stand (categorie, libelle, points, ordre) values
  -- CA — seuils en euros de chiffre d'affaires.
  -- Le document écrit « 1 < X ≤ 199€ » puis « 200 < X ≤ 699€ » : à la
  -- lettre, une commande de 200,00 € pile ne tombe dans aucun palier.
  -- Les bornes sont donc rendues inclusives ici, ce qu'un humain lit
  -- de toute façon sur l'écran.
  ('CA',               '1 à 199 €',           5, 1),
  ('CA',               '200 à 699 €',        10, 2),
  ('CA',               '700 € et plus',      20, 3),

  ('ENTRETIEN USURE',  '1 à 499 €',           5, 1),
  ('ENTRETIEN USURE',  '500 à 999 €',        10, 2),
  ('ENTRETIEN USURE',  '1 000 € et plus',    20, 3),

  ('HUILES',           'Passage',             5, 1),
  ('HUILES',           'Contact',            10, 2),
  ('HUILES',           'Commande',           20, 3),

  ('SOLUTIONS',        'Passage',             5, 1),
  ('SOLUTIONS',        'Contact',            10, 2),
  ('SOLUTIONS',        'Commande',           20, 3),

  ('GROS ÉQUIPEMENT',  'Passage',             5, 1),
  ('GROS ÉQUIPEMENT',  'Contact',            10, 2),
  ('GROS ÉQUIPEMENT',  'Commande',           20, 3),

  ('PNEUS',            '1 à 12 pneus',        5, 1),
  ('PNEUS',            '13 à 24 pneus',      10, 2),
  ('PNEUS',            '25 pneus et plus',   20, 3);

-- ---------------------------------------------------------------------
-- 3. Retrait des 5 stands de démonstration
--
--  On ne peut pas supprimer un stand qui a déjà écrit au journal
--  (clé étrangère) ni un stand auquel un téléphone est rattaché.
--  Ceux-là sont donc désactivés et leur PIN retiré — ils disparaissent
--  de la porte sans que le journal ne perde sa signature.
-- ---------------------------------------------------------------------
update public.stands
   set actif = false, code_pin = null
 where nom in ('Filtres Auvergne', 'Équip''Pro Diagnostic', 'Freinage Massif',
               'Lubrifiants Volcan', 'Pneus Chaîne des Puys');

delete from public.stands s
 where s.actif = false
   and not exists (select 1 from public.journal   j where j.stand_id = s.id)
   and not exists (select 1 from public.appareils a where a.stand_id = s.id);

-- ---------------------------------------------------------------------
-- 4. Les 23 stands du Forum
--
--  Les raisons sociales sont recopiées telles quelles depuis le document
--  de Bony : un nom de marque ne s'invente pas, et le garagiste doit
--  retrouver à l'écran ce qui est écrit sur le panneau du stand.
--
--  plafond_operation = 20 : c'est le plus haut palier du barème. Le
--  plafond n'est plus une règle commerciale, c'est un garde-fou contre
--  la faute de frappe.
--
--  plafond_soiree = 3000 : 150 opérations au palier maximum. Aucun stand
--  ne s'en approchera ; c'est un filet, pas un quota.
-- ---------------------------------------------------------------------
insert into public.stands (nom, categorie, code_pin, plafond_operation, plafond_soiree, actif) values
  ('FAAB',                'CA',              '2001', 20, 3000, true),
  ('IXELL',               'CA',              '2002', 20, 3000, true),
  ('ACCESSOIRES',         'CA',              '2003', 20, 3000, true),
  ('FACOM',               'CA',              '2004', 20, 3000, true),
  ('SAM',                 'CA',              '2005', 20, 3000, true),
  ('NILFISK',             'CA',              '2006', 20, 3000, true),
  ('SPM',                 'CA',              '2007', 20, 3000, true),

  ('MOTRIO',              'ENTRETIEN USURE', '2008', 20, 3000, true),
  ('AGENT',               'ENTRETIEN USURE', '2009', 20, 3000, true),

  ('CASTROL',             'HUILES',          '2010', 20, 3000, true),
  ('ELF',                 'HUILES',          '2011', 20, 3000, true),

  ('SIDEXA',              'SOLUTIONS',       '2012', 20, 3000, true),
  ('WYZ',                 'SOLUTIONS',       '2013', 20, 3000, true),
  ('BARDHAL',             'SOLUTIONS',       '2014', 20, 3000, true),
  ('FIDUCIAL',            'SOLUTIONS',       '2015', 20, 3000, true),
  ('CHIMIREC',            'SOLUTIONS',       '2016', 20, 3000, true),

  ('CISCAR',              'GROS ÉQUIPEMENT', '2017', 20, 3000, true),
  ('PROVAC',              'GROS ÉQUIPEMENT', '2018', 20, 3000, true),
  ('MATEXPERT',           'GROS ÉQUIPEMENT', '2019', 20, 3000, true),
  ('FILLON TECHNOLOGIE',  'GROS ÉQUIPEMENT', '2020', 20, 3000, true),
  ('EXADIS',              'GROS ÉQUIPEMENT', '2021', 20, 3000, true),

  ('GOODYEAR',            'PNEUS',           '2022', 20, 3000, true),
  ('MICHELIN',            'PNEUS',           '2023', 20, 3000, true)
on conflict (nom) do update
  set categorie         = excluded.categorie,
      code_pin          = excluded.code_pin,
      plafond_operation = excluded.plafond_operation,
      plafond_soiree    = excluded.plafond_soiree,
      actif             = true;

-- Un stand actif sans catégorie n'aurait aucun palier à afficher :
-- l'écran fournisseur serait vide et le stand muet toute la soirée.
-- Mieux vaut que la base refuse cet état que de le découvrir sur place.
alter table public.stands drop constraint if exists stands_categorie_requise;
alter table public.stands
  add constraint stands_categorie_requise
    check (not actif or categorie is not null);

-- ---------------------------------------------------------------------
-- 5. La porte renvoie désormais le barème du stand
--
--  Copie conforme de ce que fait déjà l'animateur : l'application
--  n'a plus aucun palier écrit en dur.
-- ---------------------------------------------------------------------
--  Le paramètre garde impérativement son nom `p_pin` : PostgreSQL
--  refuse de renommer un argument dans un create or replace.
create or replace function public._personnel(p_jeton text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_an  animations;
  v_st  stands;
  v_pin text;
begin
  -- Normalisation A-Z0-9 : les PIN du personnel contiennent des 0 et
  -- des 1, que l'alphabet restreint des codes garage exclut. Filtrer
  -- ici sur l'alphabet restreint viderait « 1001 » sous les doigts de
  -- l'animateur. Voir le commentaire de 13_porte.sql.
  v_pin := upper(regexp_replace(coalesce(p_pin, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_pin) < 4 then return null; end if;

  select * into v_an from animations
   where upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')) = v_pin and actif;
  if found then
    insert into appareils (jeton, role, animation_id, libelle)
    values (p_jeton, 'animateur', v_an.id, v_an.nom)
    on conflict (jeton) do update
      set role = 'animateur', animation_id = v_an.id, stand_id = null,
          garage_id = null, libelle = v_an.nom, vu_le = now();
    return jsonb_build_object('role', 'animateur', 'animation_id', v_an.id,
      'libelle', v_an.nom, 'cout', v_an.cout,
      'bareme', (select jsonb_agg(jsonb_build_object(
                   'id', id, 'libelle', libelle, 'points', points)
                 order by ordre, points desc)
                 from bareme where animation_id = v_an.id));
  end if;

  select * into v_st from stands
   where upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')) = v_pin and actif;
  if found then
    insert into appareils (jeton, role, stand_id, libelle)
    values (p_jeton, 'fournisseur', v_st.id, v_st.nom)
    on conflict (jeton) do update
      set role = 'fournisseur', stand_id = v_st.id, animation_id = null,
          garage_id = null, libelle = v_st.nom, vu_le = now();
    return jsonb_build_object('role', 'fournisseur', 'stand_id', v_st.id,
      'libelle', v_st.nom, 'categorie', v_st.categorie,
      'plafond_operation', v_st.plafond_operation,
      -- les paliers du stand, dans le vocabulaire de sa catégorie
      'bareme', coalesce((select jsonb_agg(jsonb_build_object(
                   'libelle', libelle, 'points', points)
                 order by ordre, points)
                 from bareme_stand where categorie = v_st.categorie), '[]'::jsonb));
  end if;

  if v_pin = upper(coalesce((select valeur from config where cle = 'pin_accueil'), '@@aucun@@')) then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'accueil', 'Accueil du Forum')
    on conflict (jeton) do update
      set role = 'accueil', libelle = 'Accueil du Forum',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now();
    return jsonb_build_object('role', 'accueil', 'libelle', 'Accueil du Forum');
  end if;

  if v_pin = upper(coalesce((select valeur from config where cle = 'pin_admin'), '@@aucun@@')) then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'admin', 'Équipe Bony')
    on conflict (jeton) do update
      set role = 'admin', libelle = 'Équipe Bony',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now();
    return jsonb_build_object('role', 'admin', 'libelle', 'Équipe Bony');
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. L'écriture porte le palier choisi
--
--  « Achat — FACOM » ne dit pas grand-chose trois mois plus tard.
--  « Achat — FACOM · 200 à 699 € » se justifie devant le fournisseur.
--  Le paramètre est optionnel : les appels déjà déployés et les
--  batteries de test continuent de fonctionner à l'identique.
-- ---------------------------------------------------------------------
create or replace function public.api_points_achat(
  p_jeton text, p_garage uuid, p_points integer, p_cle text,
  p_palier text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a       appareils;
  v_s     stands;
  v_cumul integer;
  v_lib   text;
  v_r     jsonb;
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

  -- Le palier n'est retenu que s'il appartient vraiment au barème de la
  -- catégorie : un libellé libre venu du navigateur n'a rien à faire
  -- dans un journal en ajout seul.
  select libelle into v_lib
    from bareme_stand
   where categorie = v_s.categorie and libelle = p_palier and points = p_points;

  v_r := _ecrire(p_garage, p_points,
                 'Achat — ' || v_s.nom || coalesce(' · ' || v_lib, ''),
                 'fournisseur', p_cle, a.id, null, v_s.id);
  return v_r || jsonb_build_object('stand', v_s.nom, 'points', p_points,
                                   'palier', v_lib,
                                   'cumul_stand', v_cumul + p_points,
                                   'plafond_soiree', v_s.plafond_soiree);
end;
$$;

-- L'ancienne signature à 4 arguments disparaît : PostgREST résout par
-- nom, deux fonctions homonymes rendraient l'appel ambigu.
drop function if exists public.api_points_achat(text, uuid, integer, text);

grant execute on function public.api_points_achat(text,uuid,integer,text,text) to anon;

-- ---------------------------------------------------------------------
-- 7. Contrôle immédiat
-- ---------------------------------------------------------------------
do $$
declare
  v_stands   integer;
  v_sans_bar integer;
begin
  select count(*) into v_stands from public.stands where actif;
  select count(*) into v_sans_bar
    from public.stands s
   where s.actif
     and not exists (select 1 from public.bareme_stand b where b.categorie = s.categorie);

  if v_stands <> 23 then
    raise exception '23 stands actifs attendus, % trouvés', v_stands;
  end if;
  if v_sans_bar > 0 then
    raise exception '% stand(s) actif(s) sans barème : écran fournisseur vide', v_sans_bar;
  end if;
  raise notice '23 stands actifs, tous pourvus d''un barème.';
end;
$$;
