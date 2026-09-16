-- =====================================================================
--  Forum Pièces Bony 2026 — 30 — La vitrine : équipe Bony & constructeurs
--
--  CE QUE C'EST. Un sixième profil, en LECTURE SEULE. L'équipe Bony et
--  les invités constructeur voient le Forum vivre — les compteurs, le
--  journal en direct, les podiums — sans pouvoir rien écrire. Demande
--  de Bastien le 17 septembre.
--
--  POURQUOI CE N'EST PAS LE CODE DIRECTION. Le code supervision ouvre
--  la remise des lots, les corrections de points, l'écran de projection
--  et le détail des tickets d'or. Le donner à 140 personnes reviendrait
--  à le publier. La vitrine n'a aucun de ces pouvoirs, et c'est la
--  raison d'être d'un rôle séparé plutôt que d'un `admin` bridé côté
--  navigateur : une restriction qui ne vit que dans le front n'est pas
--  une restriction.
--
--  UN CODE PAR PERSONNE, ET PAS UN CODE COMMUN. Verbatim : « un code
--  différent pour tout le monde, ça évite les fuites si y'a qu'un code
--  unique ». Un code qui circule ne se révoque pas ; 140 codes
--  distincts se désactivent un par un (`participants.actif = false`).
--  Plus un code de secours pour « les couillons qui sont pas sur la
--  liste », rangé dans `config.pin_vitrine`.
--
--  LES CODES VIVENT DANS participants.code_force. C'est le champ que
--  `v_badges` résout en priorité (voir sql/19_participants.sql) : poser
--  le code ici suffit à le faire apparaître sur le badge, sans toucher
--  au générateur ni à la vue. Rien à recopier nulle part.
--
--  ⚠️ LES TICKETS D'OR NE SONT JAMAIS NOMMÉS. La vitrine rend des
--  COMPTEURS — « 9 décrochés sur 15 » — et rien d'autre. Ni qui les
--  détient, ni quel gros lot est dessous. Arbitrage du 17 septembre.
--  L'écran direction, lui, garde le détail, et sa mise en garde.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Le rôle
-- ---------------------------------------------------------------------
alter table public.appareils drop constraint if exists appareils_role_check;
alter table public.appareils
  add constraint appareils_role_check
    check (role in ('garage','animateur','fournisseur','admin','accueil','vitrine'));

-- ---------------------------------------------------------------------
-- 2. Les codes, un par personne
-- ---------------------------------------------------------------------
--  MÊME ALGORITHME QUE LES CODES GARAGE, et pour la même raison :
--  déterministe, donc rejouable sans jamais changer un code déjà
--  imprimé sur un badge. La graine est fixe, la variante ne bouge que
--  s'il y a collision.
--
--  L'ALPHABET EXCLUT O, I, 0 ET 1. Un code se lit à voix haute au
--  milieu du bruit, et « I » contre « 1 » se perd. Les PIN du personnel
--  contiennent des 0 et des 1, eux, parce qu'ils sont tapés depuis une
--  fiche et pas dictés — la normalisation de saisie garde donc A-Z0-9,
--  l'alphabet restreint ne sert qu'à la GÉNÉRATION.
--
--  UNE COLLISION EST UN ACCIDENT SILENCIEUX : deux personnes avec le
--  même code, ou pire, un code de vitrine qui vaut le code d'un garage
--  et ouvre son portefeuille. La boucle ci-dessous réessaie jusqu'à
--  trouver un code libre de TOUS les autres, et verifier_portes() le
--  revérifie après coup.
create or replace function public._code_vitrine(p_source text, p_variante int)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select string_agg(
           substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                  (get_byte(decode(md5('grand-bal-2026-vitrine|' || p_source
                                       || '|' || p_variante), 'hex'), i) % 32) + 1, 1),
           '' order by i)
  from generate_series(0, 3) as i;
$$;

do $$
declare
  r        record;
  v_code   text;
  v_var    int;
  v_poses  int := 0;
  v_gardes int := 0;
begin
  for r in
    select id, cle_source, code_force
      from public.participants
     where actif and categorie in ('EQUIPE_BONY', 'CONSTRUCTEUR')
     order by cle_source
  loop
    -- Un code déjà posé ne bouge JAMAIS : il est peut-être déjà
    -- imprimé. Rejouer ce fichier ne redistribue pas les cartes.
    if r.code_force is not null then
      v_gardes := v_gardes + 1;
      continue;
    end if;

    v_var := 0;
    loop
      v_code := public._code_vitrine(r.cle_source, v_var);
      exit when not exists (select 1 from public.garages    g where upper(g.code)     = v_code and g.actif)
            and not exists (select 1 from public.animations a where upper(regexp_replace(a.code_pin, '[^A-Za-z0-9]', '', 'g')) = v_code and a.actif)
            and not exists (select 1 from public.stands     s where upper(regexp_replace(s.code_pin, '[^A-Za-z0-9]', '', 'g')) = v_code and s.actif)
            and not exists (select 1 from public.config     c where c.cle in ('pin_admin','pin_accueil','pin_vitrine') and upper(c.valeur) = v_code)
            and not exists (select 1 from public.participants p where upper(p.code_force) = v_code and p.id <> r.id);
      v_var := v_var + 1;
      if v_var > 200 then
        raise exception 'Impossible de trouver un code libre pour % après 200 variantes', r.cle_source;
      end if;
    end loop;

    update public.participants set code_force = v_code where id = r.id;
    v_poses := v_poses + 1;
  end loop;

  raise notice 'codes vitrine : % posés, % déjà en place', v_poses, v_gardes;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Le code de secours
-- ---------------------------------------------------------------------
--  Pour qui n'est pas sur la liste et se présente le soir. Il ouvre la
--  même vitrine, sans nom. On ne le met sur AUCUN badge : il se donne
--  de vive voix, et il se change en une ligne s'il tourne trop.
insert into public.config (cle, valeur)
select 'pin_vitrine', public._code_vitrine('secours', v.n)
from generate_series(0, 200) as v(n)
where not exists (select 1 from public.config where cle = 'pin_vitrine')
  and not exists (select 1 from public.garages    g where upper(g.code) = public._code_vitrine('secours', v.n) and g.actif)
  and not exists (select 1 from public.animations a where upper(regexp_replace(a.code_pin, '[^A-Za-z0-9]', '', 'g')) = public._code_vitrine('secours', v.n) and a.actif)
  and not exists (select 1 from public.stands     s where upper(regexp_replace(s.code_pin, '[^A-Za-z0-9]', '', 'g')) = public._code_vitrine('secours', v.n) and s.actif)
  and not exists (select 1 from public.config     c where c.cle in ('pin_admin','pin_accueil') and upper(c.valeur) = public._code_vitrine('secours', v.n))
  and not exists (select 1 from public.participants p where upper(p.code_force) = public._code_vitrine('secours', v.n))
order by v.n
limit 1;

-- ---------------------------------------------------------------------
-- 4. La porte
-- ---------------------------------------------------------------------
--  On se greffe sur _personnel, APRÈS les animations, les stands,
--  l'accueil et la direction. L'ordre compte : un code de vitrine ne
--  doit jamais pouvoir masquer une porte de service, et le jour où
--  deux codes se ressembleraient, c'est le métier qui gagne.
create or replace function public._personnel(p_jeton text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_an  animations;
  v_st  stands;
  v_p   participants;
  v_pin text;
begin
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
      'libelle', v_st.nom, 'plafond_operation', v_st.plafond_operation);
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

  -- ---- la vitrine : un code nominatif, ou le code de secours -------
  select * into v_p from participants
   where actif
     and categorie in ('EQUIPE_BONY', 'CONSTRUCTEUR')
     and upper(code_force) = v_pin;
  if found then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'vitrine', trim(v_p.prenom || ' ' || v_p.nom))
    on conflict (jeton) do update
      set role = 'vitrine', libelle = trim(v_p.prenom || ' ' || v_p.nom),
          garage_id = null, animation_id = null, stand_id = null, vu_le = now();
    return jsonb_build_object('role', 'vitrine',
      'libelle', trim(v_p.prenom || ' ' || v_p.nom),
      'categorie', v_p.categorie);
  end if;

  if v_pin = upper(coalesce((select valeur from config where cle = 'pin_vitrine'), '@@aucun@@')) then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'vitrine', 'Invité')
    on conflict (jeton) do update
      set role = 'vitrine', libelle = 'Invité',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now();
    return jsonb_build_object('role', 'vitrine', 'libelle', 'Invité',
      'categorie', 'SECOURS');
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Le garde-fou, élargi
-- ---------------------------------------------------------------------
--  Même contrat qu'avant — zéro ligne — mais il couvre maintenant les
--  140 codes de vitrine. Sans ça, un code de vitrine qui vaudrait le
--  code d'un garage ouvrirait le portefeuille de ce garage, et personne
--  ne le verrait avant que quelqu'un s'en plaigne.
create or replace function public.verifier_portes()
returns table(pin text, porte text, garage text)
language sql
stable
set search_path = public, pg_temp
as $$
  with pins as (
    select upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')) as p,
           'animation ' || nom as porte from animations where actif
    union all
    select upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')),
           'stand ' || nom from stands where actif
    union all
    select upper(valeur), cle from config
     where cle in ('pin_admin', 'pin_accueil', 'pin_vitrine')
    union all
    select upper(code_force), 'vitrine ' || trim(prenom || ' ' || nom)
      from participants
     where actif and code_force is not null
       and categorie in ('EQUIPE_BONY', 'CONSTRUCTEUR')
  )
  -- collision avec un code garage
  select pins.p, pins.porte, g.nom
    from pins join garages g on upper(g.code) = pins.p and g.actif
  union all
  -- collision entre deux portes de service
  select p, string_agg(porte, ' / '), '(deux portes du personnel)'
    from pins group by p having count(*) > 1;
$$;

-- ---------------------------------------------------------------------
-- 6. Ce que la vitrine a le droit de voir
-- ---------------------------------------------------------------------
--  UN SEUL APPEL pour tout l'écran. La vitrine sera ouverte sur 140
--  téléphones pendant six heures : chaque aller-retour évité est une
--  connexion qui reste libre pour un garagiste qui achète une case, et
--  le pool PostgREST plafonne à 11 (voir §8 de CONTEXTE.md).
--
--  LA SANTÉ EST CALCULÉE ICI, ET RENDUE EN UN SEUL POURCENTAGE. La
--  console de supervision expose le pool, les verrous et les
--  transactions bloquées ; ces chiffres n'apprennent rien à un invité
--  constructeur et les envoyer à 140 navigateurs serait donner le
--  détail de la plomberie à des gens qui veulent savoir si ça marche.
--  On applique la même règle que la console — LA PIRE des mesures, pas
--  leur moyenne — et on ne rend que le verdict.
create or replace function public.api_vitrine(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a            appareils;
  v_actives    integer;
  v_verrous    integer;
  v_bloquees   integer;
  v_ecarts     integer;
  v_pire       numeric;
  v_cout       integer := cfg_int('cout_grille', 20);
  v_total      integer;
  v_libres     integer;
  v_circul     integer;
begin
  -- admin est admis : la direction doit pouvoir regarder ce que voient
  -- ses invités sans ressaisir un code.
  a := _exige_role(p_jeton, array['vitrine', 'admin']);

  select count(*) filter (where usename = 'authenticator' and state = 'active'),
         count(*) filter (where wait_event_type = 'Lock'),
         count(*) filter (where state = 'idle in transaction')
    into v_actives, v_verrous, v_bloquees
    from pg_stat_activity;
  select count(*) into v_ecarts from verifier_soldes();

  v_pire := greatest(
    least(1.0, v_actives::numeric / 11),
    least(1.0, v_verrous::numeric / 5),
    least(1.0, v_bloquees::numeric / 3),
    case when v_ecarts > 0 then 1.0 else 0.0 end);

  select count(*), count(*) filter (where garage_id is null) into v_total, v_libres from grille;
  select coalesce(sum(solde), 0) into v_circul from garages;

  return jsonb_build_object(
    'libelle',   a.libelle,
    'heure',     to_char(now() at time zone 'Europe/Paris', 'HH24:MI'),

    -- --- la barre de santé, et rien de plus ---
    'sante', jsonb_build_object(
      'pct',  round((1 - v_pire) * 100)::int,
      'ton',  case when v_pire < 0.55 then 'ok'
                   when v_pire < 0.8  then 'tiede' else 'chaud' end,
      'ecritures_min',   (select count(*) from journal where cree_le > now() - interval '1 minute'),
      'ecritures_10min', (select count(*) from journal where cree_le > now() - interval '10 minutes')),

    -- --- le Forum en un coup d'œil ---
    'garages_invites',    (select count(*) from garages where actif),
    'garages_actifs',     (select count(*) from garages where inscrit_le is not null),
    'points_circulation', v_circul,
    'points_emis',        (select coalesce(sum(delta), 0) from journal where delta > 0),
    'cases_total',        v_total,
    'cases_jouees',       v_total - v_libres,
    'cases_libres',       v_libres,
    'cout_grille',        v_cout,
    'lots_gagnes',        (select count(*) from grille where nature = 'lot' and garage_id is not null),
    'lots_remis',         (select count(*) from grille where remis),
    -- `source` vaut 'animation' ou 'fournisseur' tout court ; le
    -- rattachement precis passe par journal.animation_id et
    -- journal.stand_id (voir le schema en sql/01_schema.sql). Joindre
    -- sur une chaine 'animation:<id>' ne rendait rien, et un podium
    -- vide ne se signale pas : il s'affiche vide.
    'parties_jouees',     (select count(*) from journal where source = 'animation' and delta < 0),
    'operations',         (select count(*) from journal where source = 'fournisseur'),

    -- --- les tickets d'or : DES COMPTEURS, JAMAIS DE NOMS ---
    'billets_vendus',     (select count(*) from grille where nature = 'billet' and garage_id is not null),
    'billets_total',      (select count(*) from grille where nature = 'billet'),
    'tirage_revele',      coalesce((select valeur from config where cle = 'tirage_revele'), 'non') = 'oui',

    -- --- les podiums ---
    --  Le classement des garages se fait sur les points GAGNÉS, pas sur
    --  le solde : un garage qui joue tout ce qu'il gagne finirait à
    --  zéro et disparaîtrait du podium alors que c'est lui le plus
    --  actif de la salle.
    'podium_garages', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('nom', g.nom, 'ville', g.ville,
                 'points', sum(j.delta)) as x
        from journal j join garages g on g.id = j.garage_id
        where j.delta > 0
        group by g.id, g.nom, g.ville
        order by sum(j.delta) desc, g.nom
        limit 5) t), '[]'::jsonb),

    'podium_stands', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('nom', s.nom, 'points', sum(j.delta),
                 'operations', count(*)) as x
        from journal j join stands s on s.id = j.stand_id
        where j.delta > 0
        group by s.id, s.nom
        order by sum(j.delta) desc, s.nom
        limit 5) t), '[]'::jsonb),

    'podium_animations', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object('nom', an.nom,
                 'parties', count(*) filter (where j.delta < 0),
                 'points', coalesce(sum(j.delta) filter (where j.delta > 0), 0)) as x
        from journal j join animations an on an.id = j.animation_id
        group by an.id, an.nom
        order by count(*) filter (where j.delta < 0) desc, an.nom
        limit 5) t), '[]'::jsonb),

    -- --- le journal en direct ---
    --  Quarante lignes : de quoi voir la salle bouger sans transporter
    --  plusieurs milliers d'écritures vers 140 téléphones.
    'journal', coalesce((
      select jsonb_agg(jsonb_build_object(
               'heure', to_char(j.cree_le at time zone 'Europe/Paris', 'HH24:MI'),
               'garage', g.nom, 'libelle', j.libelle, 'delta', j.delta)
             order by j.id desc)
      from (select * from journal order by id desc limit 40) j
      join garages g on g.id = j.garage_id), '[]'::jsonb));
end;
$$;

grant execute on function public.api_vitrine(text) to anon;
revoke all on function public._code_vitrine(text, int) from anon, authenticated;

commit;

-- ---------------------------------------------------------------------
-- Contrôle
-- ---------------------------------------------------------------------
select (select count(*)::int from verifier_portes())                       as collisions,
       (select count(*)::int from participants
         where actif and categorie in ('EQUIPE_BONY','CONSTRUCTEUR')
           and code_force is not null)                                     as codes_poses,
       (select count(*)::int from participants
         where actif and categorie in ('EQUIPE_BONY','CONSTRUCTEUR'))      as personnes,
       (select count(distinct code_force)::int from participants
         where actif and code_force is not null)                           as codes_distincts,
       (select count(*)::int from config where cle = 'pin_vitrine')        as code_secours;
