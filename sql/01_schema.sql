-- =====================================================================
--  Forum Pièces Bony 2026 — « Le Grand Bal des Points »
--  01 — Schéma : tables, contraintes, index, verrouillage des accès
--
--  Principes non négociables encodés ici :
--   1. Le journal est en ajout seul. Aucune ligne ne peut être modifiée
--      ni supprimée, même par erreur d'application.
--   2. Le solde affiché est un cache, et l'invariant
--      « solde = somme(journal) » est vérifiable à tout moment.
--   3. Une opération portant une clé d'idempotence déjà vue est ignorée.
--   4. Une case de la grille ne peut être prise qu'une seule fois.
--   5. Aucun client ne touche une table directement : tout passe par
--      des fonctions vérifiées (voir 02_fonctions.sql).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Recherche insensible aux accents et à la casse, sans extension.
-- translate() + lower() sont immutables : utilisable en colonne générée.
-- ---------------------------------------------------------------------
create or replace function public.norm(t text)
returns text
language sql
immutable
strict
parallel safe
as $$
  select lower(translate(t,
    'àáâäãåÀÁÂÄÃÅçÇèéêëÈÉÊËìíîïÌÍÎÏñÑòóôöõÒÓÔÖÕùúûüÙÚÛÜÿŸ',
    'aaaaaaAAAAAAcCeeeeEEEEiiiiIIIInNoooooOOOOOuuuuUUUUyY'))
$$;

-- ---------------------------------------------------------------------
-- Réglages (barèmes, coûts) — modifiables sans redéploiement
-- ---------------------------------------------------------------------
create table if not exists public.config (
  cle         text primary key,
  valeur      text not null,
  description text
);

create or replace function public.cfg_int(p_cle text, p_defaut int)
returns int
language sql
stable
as $$
  select coalesce((select valeur::int from public.config where cle = p_cle), p_defaut)
$$;

-- ---------------------------------------------------------------------
-- Garages : la liste fermée des invités. Porteur du portefeuille.
-- Un portefeuille par garage, partagé entre ses accompagnants.
-- ---------------------------------------------------------------------
create table if not exists public.garages (
  id          uuid primary key default gen_random_uuid(),
  nom         text not null,
  ville       text not null default '',
  -- solde = cache de somme(journal.delta). Jamais écrit par un client.
  solde       integer not null default 0,
  inscrit_le  timestamptz,
  actif       boolean not null default true,
  cree_le     timestamptz not null default now(),
  recherche   text generated always as (public.norm(nom || ' ' || ville)) stored,
  constraint garages_solde_positif check (solde >= 0)
);

create index if not exists garages_recherche_idx on public.garages (recherche);
create unique index if not exists garages_nom_ville_idx
  on public.garages (public.norm(nom), public.norm(ville));

-- ---------------------------------------------------------------------
-- Appareils : un téléphone / une tablette. Pas de mot de passe pour les
-- garages ; un code PIN de stand pour le personnel.
-- ---------------------------------------------------------------------
create table if not exists public.appareils (
  id           uuid primary key default gen_random_uuid(),
  jeton        text not null unique,
  role         text not null check (role in ('garage','animateur','fournisseur','admin')),
  garage_id    uuid references public.garages(id) on delete cascade,
  animation_id uuid,
  stand_id     uuid,
  libelle      text,
  cree_le      timestamptz not null default now(),
  vu_le        timestamptz not null default now(),
  -- un appareil « garage » est forcément rattaché à un garage
  constraint appareils_garage_coherent
    check (role <> 'garage' or garage_id is not null)
);

create index if not exists appareils_garage_idx on public.appareils (garage_id);

-- ---------------------------------------------------------------------
-- Animations et leurs barèmes
-- ---------------------------------------------------------------------
create table if not exists public.animations (
  id      uuid primary key default gen_random_uuid(),
  nom     text not null unique,
  cout    integer not null default 0 check (cout >= 0),
  code_pin text,
  actif   boolean not null default true,
  ordre   integer not null default 0
);

create table if not exists public.bareme (
  id           uuid primary key default gen_random_uuid(),
  animation_id uuid not null references public.animations(id) on delete cascade,
  libelle      text not null,
  points       integer not null check (points >= 0),
  ordre        integer not null default 0,
  unique (animation_id, libelle)
);

create index if not exists bareme_animation_idx on public.bareme (animation_id, ordre);

-- ---------------------------------------------------------------------
-- Stands fournisseurs, avec garde-fous anti-inflation de points
-- ---------------------------------------------------------------------
create table if not exists public.stands (
  id                uuid primary key default gen_random_uuid(),
  nom               text not null unique,
  code_pin          text,
  plafond_operation integer not null default 50 check (plafond_operation > 0),
  plafond_soiree    integer not null default 2000 check (plafond_soiree > 0),
  actif             boolean not null default true
);

-- ---------------------------------------------------------------------
-- Journal des points — AJOUT SEUL
-- ---------------------------------------------------------------------
create table if not exists public.journal (
  id           bigint generated always as identity primary key,
  garage_id    uuid not null references public.garages(id) on delete cascade,
  delta        integer not null check (delta <> 0),
  libelle      text not null,
  source       text not null check (source in
                 ('inscription','animation','fournisseur','recompense','administration')),
  animation_id uuid references public.animations(id),
  stand_id     uuid references public.stands(id),
  appareil_id  uuid references public.appareils(id),
  cle_idem     text not null unique,
  cree_le      timestamptz not null default now()
);

create index if not exists journal_garage_idx on public.journal (garage_id, id desc);
create index if not exists journal_cree_idx   on public.journal (cree_le desc);
create index if not exists journal_stand_idx  on public.journal (stand_id) where stand_id is not null;

-- Verrou d'immuabilité : ni UPDATE ni DELETE, jamais, par personne.
create or replace function public.journal_immuable()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'Le journal est en ajout seul : une erreur se corrige par une écriture inverse, pas par une modification (tentative de % sur la ligne %)',
    tg_op, coalesce(old.id, 0);
end;
$$;

drop trigger if exists journal_pas_de_modif on public.journal;
create trigger journal_pas_de_modif
  before update or delete on public.journal
  for each row execute function public.journal_immuable();

-- ---------------------------------------------------------------------
-- Grille des 100 cases. L'unicité est structurelle : le numéro est la
-- clé primaire, et la prise de case est un UPDATE conditionnel.
-- ---------------------------------------------------------------------
create table if not exists public.grille (
  numero       integer primary key check (numero between 1 and 100),
  gagnante     boolean not null default false,
  lot          text,
  garage_id    uuid references public.garages(id) on delete set null,
  journal_id   bigint references public.journal(id),
  joue_le      timestamptz,
  code_retrait text,
  remis        boolean not null default false,
  remis_le     timestamptz,
  -- une case gagnante annonce forcément un lot
  constraint grille_lot_coherent check (not gagnante or lot is not null),
  -- on ne remet un lot que sur une case jouée et gagnante
  constraint grille_remise_coherente
    check (not remis or (gagnante and garage_id is not null))
);

create index if not exists grille_garage_idx on public.grille (garage_id) where garage_id is not null;

-- ---------------------------------------------------------------------
-- Audit de l'invariant : solde en cache contre somme du journal
-- ---------------------------------------------------------------------
create or replace function public.verifier_soldes()
returns table (garage_id uuid, nom text, solde_cache int, solde_journal int, ecart int)
language sql
stable
as $$
  select g.id, g.nom, g.solde,
         coalesce(sum(j.delta)::int, 0),
         g.solde - coalesce(sum(j.delta)::int, 0)
  from public.garages g
  left join public.journal j on j.garage_id = g.id
  group by g.id, g.nom, g.solde
  having g.solde <> coalesce(sum(j.delta)::int, 0)
$$;

-- =====================================================================
--  Verrouillage des accès
--  RLS active partout, AUCUNE policy : les rôles publics ne peuvent donc
--  rien lire ni écrire en direct. Tout passe par les fonctions du
--  fichier 02, qui sont les seules portes d'entrée.
-- =====================================================================
alter table public.config     enable row level security;
alter table public.garages    enable row level security;
alter table public.appareils  enable row level security;
alter table public.animations enable row level security;
alter table public.bareme     enable row level security;
alter table public.stands     enable row level security;
alter table public.journal    enable row level security;
alter table public.grille     enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

comment on table public.journal is
  'Journal des points, en ajout seul. Source de vérité du solde de chaque garage.';
comment on column public.garages.solde is
  'Cache de somme(journal.delta). Mis à jour dans la même transaction que l''écriture. Vérifiable via verifier_soldes().';
