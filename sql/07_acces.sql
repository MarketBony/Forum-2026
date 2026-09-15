-- =====================================================================
--  Forum Pièces Bony 2026 — 07 — Accès par code garage
--
--  Un code de 4 caractères par garage sert à la fois de clé d'entrée et
--  de clé de retour :
--    - à l'arrivée, le garagiste scanne le QR puis tape son code ;
--    - s'il vide son navigateur ou change de téléphone, il retape le
--      même code et retrouve son portefeuille à l'identique ;
--    - deux accompagnants d'un même garage tapent le même code et
--      partagent le portefeuille ;
--    - personne ne peut entrer dans un garage sans son code.
--
--  Ce qui disparaît : la recherche publique de garages. L'application
--  n'expose plus aucune liste, donc le fichier client de Bony ne sort
--  jamais de la base. Le code identifie le garage directement.
--
--  Alphabet sans caractères ambigus (ni O/0 ni I/1) : 32^4 ≈ 1 048 576
--  combinaisons pour 1 407 codes attribués, soit une chance sur 745 de
--  tomber juste au hasard — avec un frein sur les tentatives par-dessus.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Réglages
-- ---------------------------------------------------------------------
insert into public.config (cle, valeur, description) values
  ('appareils_max', '3', 'Nombre d''appareils simultanés autorisés par garage'),
  ('tentatives_max', '8', 'Tentatives de code autorisées par appareil sur 5 minutes')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- 2. Table de repli : on repart d'une base vierge de garages
--    Les lignes existantes sont des données de test sans numéro de
--    compte, or la colonne devient obligatoire et unique.
--    Le journal est purgé, sinon la suppression en cascade se heurte au
--    verrou d'immuabilité — qui fait exactement son travail.
-- ---------------------------------------------------------------------
update public.grille
   set garage_id = null, journal_id = null, achete_le = null, revele_le = null,
       code_retrait = null, remis = false, remis_le = null;
-- La table tirage a disparu avec sql/23_grand_tirage.sql : le soir est
-- une revelation, pas un tirage. Seul le drapeau retombe.
update public.config set valeur='non' where cle='tirage_revele';
alter table public.journal disable trigger journal_pas_de_modif;
delete from public.journal;
alter table public.journal enable trigger journal_pas_de_modif;
delete from public.appareils;
delete from public.garages;

-- ---------------------------------------------------------------------
-- 3. Le garage porte désormais son identité Bony et son code
-- ---------------------------------------------------------------------
alter table public.garages
  add column if not exists compte   text,
  add column if not exists ref_bony text,
  add column if not exists cp       text,
  add column if not exists profil   text,
  add column if not exists email    text,
  add column if not exists code     text;

-- L'index unique sur (nom, ville) doit tomber : 24 raisons sociales sont
-- en doublon dans le fichier des invités. La clé, c'est le compte.
drop index if exists public.garages_nom_ville_idx;

create unique index if not exists garages_compte_idx on public.garages (compte);
create unique index if not exists garages_code_idx   on public.garages (upper(code));

alter table public.garages
  drop constraint if exists garages_code_forme;
alter table public.garages
  add constraint garages_code_forme
    check (code is null or code ~ '^[A-HJ-NP-Z2-9]{4,6}$');

-- ---------------------------------------------------------------------
-- 4. Frein sur les tentatives de code
-- ---------------------------------------------------------------------
create table if not exists public.tentatives (
  id      bigint generated always as identity primary key,
  jeton   text not null,
  code    text,
  quand   timestamptz not null default now()
);
create index if not exists tentatives_jeton_idx on public.tentatives (jeton, quand desc);
alter table public.tentatives enable row level security;
revoke all on public.tentatives from anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. Entrée dans l'application — remplace api_inscrire
-- ---------------------------------------------------------------------
create or replace function public.api_entrer(p_jeton text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code    text;
  v_g       garages;
  v_bonus   integer := cfg_int('bonus_inscription', 10);
  v_max     integer := cfg_int('appareils_max', 3);
  v_essais  integer := cfg_int('tentatives_max', 8);
  v_app     uuid;
  v_nb      integer;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE'
      using detail = 'Rechargez la page depuis le QR code.';
  end if;

  -- on tolère les espaces, les tirets et les minuscules à la saisie
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_code) < 4 then
    raise exception 'CODE_TROP_COURT'
      using detail = 'Votre code fait 4 caractères.';
  end if;

  -- frein : au-delà de N tentatives sur 5 minutes, on refuse
  select count(*) into v_nb from tentatives
   where jeton = p_jeton and quand > now() - interval '5 minutes';
  if v_nb >= v_essais then
    raise exception 'TROP_DE_TENTATIVES'
      using detail = 'Trop d''essais. Patientez une minute, ou demandez à l''accueil.';
  end if;

  select * into v_g from garages where upper(code) = v_code and actif;
  if not found then
    insert into tentatives (jeton, code) values (p_jeton, v_code);
    raise exception 'CODE_INCONNU'
      using detail = 'Ce code ne correspond à aucun garage. Vérifiez-le, ou demandez à l''accueil.';
  end if;

  -- plafond d'appareils, sauf si cet appareil est déjà rattaché
  if not exists (select 1 from appareils where jeton = p_jeton and garage_id = v_g.id) then
    select count(*) into v_nb from appareils where garage_id = v_g.id;
    if v_nb >= v_max then
      raise exception 'TROP_D_APPAREILS'
        using detail = format('Ce garage a déjà %s appareils connectés. Voyez avec l''accueil.', v_nb);
    end if;
  end if;

  insert into appareils (jeton, role, garage_id, libelle)
  values (p_jeton, 'garage', v_g.id, v_g.nom)
  on conflict (jeton) do update
    set garage_id = excluded.garage_id, role = 'garage',
        libelle = excluded.libelle, vu_le = now()
  returning id into v_app;

  -- bonus versé une seule fois par garage, quel que soit le nombre
  -- d'accompagnants qui saisissent le code
  if v_bonus > 0 then
    perform _ecrire(v_g.id, v_bonus, 'Bienvenue au Forum', 'inscription',
                    'inscription:' || v_g.id::text, v_app);
  end if;

  update garages set inscrit_le = coalesce(inscrit_le, now()) where id = v_g.id;
  delete from tentatives where jeton = p_jeton;

  return api_etat(p_jeton);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. api_etat renvoie le code, pour que le garagiste puisse le noter
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
        'id', v_g.id, 'nom', v_g.nom, 'ville', v_g.ville, 'cp', v_g.cp,
        'solde', v_g.solde, 'code', v_g.code),
    'cout_grille', cfg_int('cout_grille', 20),
    'revelation', coalesce((select valeur from config where cle = 'revelation'), 'immediate'),
    'cases_libres', (select count(*) from grille where garage_id is null),
    'billets_restants', (select count(*) from grille where nature = 'billet' and garage_id is null),
    'grille', (select string_agg(case when garage_id is null then '0' else '1' end, ''
                                 order by numero) from grille),
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
-- 7. La recherche de garage réservée au personnel affiche le code postal
--    pour départager les 24 raisons sociales en doublon
-- ---------------------------------------------------------------------
create or replace function public.api_chercher(p_jeton text, p_q text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['animateur','fournisseur','admin']);
  return coalesce((
    select jsonb_agg(x order by x->>'nom')
    from (
      select jsonb_build_object('id', id, 'nom', nom,
               'ville', coalesce(nullif(cp, '') || ' ', '') || ville,
               'solde', solde) as x, nom
      from garages
      where actif and inscrit_le is not null
        and (coalesce(p_q, '') = '' or recherche like '%' || norm(p_q) || '%')
      order by nom limit 12
    ) s), '[]'::jsonb);
end;
$$;

-- La liste mise en cache pour le hors ligne ne contient que les garages
-- effectivement entrés dans l'application : ni le personnel ni un
-- appareil volé n'obtiennent le fichier client complet.
create or replace function public.api_garages_liste(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['animateur','fournisseur','admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'nom', nom,
             'ville', coalesce(nullif(cp, '') || ' ', '') || ville, 'solde', solde)
                     order by nom)
    from garages where actif and inscrit_le is not null), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- 8. Ce qui n'a plus lieu d'être
-- ---------------------------------------------------------------------
drop function if exists public.api_garages_invites(text, text);
drop function if exists public.api_inscrire(text, uuid);

-- ---------------------------------------------------------------------
-- 9. Droits
-- ---------------------------------------------------------------------
grant execute on function public.api_entrer(text, text) to anon;
grant execute on function public.api_etat(text) to anon;
grant execute on function public.api_chercher(text, text) to anon;
grant execute on function public.api_garages_liste(text) to anon;

comment on column public.garages.code is
  'Code d''accès de 4 caractères : clé d''entrée ET clé de retour du garage.';
