-- =====================================================================
--  Forum Pièces Bony 2026 — 19 — Les participants, et rien qu'eux
--
--  POURQUOI CETTE TABLE EXISTE.
--  Le générateur de badges croisait jusqu'ici deux sources : les 1 407
--  invités en base d'un côté, les fichiers d'inscription de l'autre. Ce
--  croisement s'est révélé impraticable, et le fichier consolidé du
--  14 septembre dit pourquoi noir sur blanc : l'identifiant d'invitation
--  n'est PAS une clé. BONY00250 a servi à trois sociétés successives
--  (onglet TRANSFERTS_ID), et des salariés Bony se sont inscrits via le
--  lien d'un client (onglet ID_MAUVAISE_CIBLE). Rapprocher sur cet
--  identifiant attribuait donc parfois le code d'un autre garage.
--
--  Décision de l'utilisateur, le 14 septembre : le générateur ne lit
--  plus que la base, et la base porte la liste des inscrits. Le
--  rapprochement se fait UNE fois, au moment de pousser le listing, par
--  scripts\importer-inscriptions.ps1 — qui signale ce qu'il ne sait pas
--  rattacher au lieu de deviner.
--
--  CE QUE CETTE TABLE N'EST PAS. Ce n'est pas le contrôle d'accès. Les
--  codes restent dans garages.code, stands.code_pin, animations.code_pin
--  et config : cette table ne fait que DÉSIGNER qui porte quel badge.
--  Les 1 407 invités restent actifs dans `garages` — un garagiste qui
--  se présente sans s'être inscrit doit pouvoir entrer, l'hôtesse le
--  retrouve et lui lit son code (voir sql\09_accueil.sql). Il n'aura
--  simplement pas de badge imprimé d'avance.
--
--  AUCUNE FONCTION api_* NE TOUCHE CETTE TABLE. L'application ne la
--  connaît pas. Elle n'est lue que par le générateur de badges, en
--  local, via l'API de management. RLS active, zéro policy, aucun
--  grant : les rôles publics ne peuvent ni la lire ni l'écrire.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La table
-- ---------------------------------------------------------------------
create table if not exists public.participants (
  id             uuid primary key default gen_random_uuid(),

  categorie      text not null,
  raison_sociale text not null,
  prenom         text not null default '',
  nom            text not null default '',
  commune        text not null default '',
  email          text,
  telephone      text,

  -- Un inscrit qui vient à deux ne remplit qu'une ligne du formulaire.
  -- Le second badge porte la même société et le même code, sans nom :
  -- on ne connaît pas la personne qui l'accompagne, et l'inventer
  -- serait pire que de laisser blanc.
  nb_badges      integer not null default 1,

  -- Le rattachement à ce qui porte le code. Un seul des trois est
  -- renseigné, et il peut n'y en avoir aucun (un constructeur qui ne
  -- crédite personne n'a pas besoin de code).
  garage_id      uuid references public.garages(id),
  stand_id       uuid references public.stands(id),
  animation_id   uuid references public.animations(id),

  -- Échappatoire : un code posé à la main, qui l'emporte sur tout le
  -- reste. Sert aux cas qu'aucune table ne couvre.
  code_force     text,

  -- Idempotence, même principe que cle_idem dans le journal : rejouer
  -- le même listing met à jour au lieu de dupliquer. Sans cela, deux
  -- imports du même fichier donnent deux badges par personne, et on
  -- s'en aperçoit à l'imprimante.
  cle_source     text not null,

  actif          boolean not null default true,
  note           text,
  cree_le        timestamptz not null default now(),
  maj_le         timestamptz not null default now(),

  constraint participants_categorie_connue check (categorie in (
    'GARAGE', 'EXPOSANT', 'ANIMATION', 'HOTESSE', 'EQUIPE_BONY', 'CONSTRUCTEUR')),
  constraint participants_nb_badges_sense check (nb_badges between 1 and 20),
  constraint participants_un_seul_rattachement check (
    (case when garage_id    is not null then 1 else 0 end) +
    (case when stand_id     is not null then 1 else 0 end) +
    (case when animation_id is not null then 1 else 0 end) <= 1),
  -- Même contrainte de forme que garages.code : un code qui ne peut pas
  -- être saisi dans l'application n'a rien à faire sur un badge.
  constraint participants_code_force_forme check (
    code_force is null or code_force ~ '^[A-Za-z0-9]{4,6}$')
);

create unique index if not exists participants_cle_source_idx
  on public.participants (cle_source);
create index if not exists participants_categorie_idx
  on public.participants (categorie) where actif;

-- Le fichier consolidé change tous les jours jusqu'au 17 : on veut voir
-- d'un coup d'oeil ce qui a bougé depuis le dernier export de badges.
create or replace function public._participants_maj()
returns trigger language plpgsql as $$
begin
  new.maj_le := now();
  return new;
end;
$$;

drop trigger if exists participants_maj on public.participants;
create trigger participants_maj before update on public.participants
  for each row execute function public._participants_maj();

-- ---------------------------------------------------------------------
-- 2. La vue que lit le générateur
-- ---------------------------------------------------------------------
--  Le code n'est jamais recopié dans participants : il est résolu ici,
--  à la lecture. Changer un PIN de stand met donc à jour les badges de
--  ce stand sans retoucher une seule ligne de participants — et la
--  décision n°4 (figer les PIN du personnel) reste jouable jusqu'au
--  dernier moment.
--
--  EQUIPE_BONY n'a volontairement AUCUN code par défaut. Le code
--  supervision ouvre la remise des lots, les corrections de points et
--  l'écran de projection : l'imprimer sur 70 badges reviendrait à le
--  distribuer à tout le monde. Les deux ou trois personnes qui en ont
--  besoin le reçoivent par code_force, nommément.
create or replace view public.v_badges as
select
  p.id,
  p.categorie,
  p.raison_sociale,
  p.prenom,
  p.nom,
  coalesce(nullif(p.commune, ''), g.ville, '') as commune,
  p.nb_badges,
  coalesce(
    p.code_force,
    g.code,
    s.code_pin,
    a.code_pin,
    case p.categorie
      when 'HOTESSE' then (select valeur from public.config where cle = 'pin_accueil')
    end
  ) as code,
  p.note
from public.participants p
left join public.garages    g on g.id = p.garage_id
left join public.stands     s on s.id = p.stand_id
left join public.animations a on a.id = p.animation_id
where p.actif;

-- ---------------------------------------------------------------------
-- 3. Le verrouillage — même régime que les huit autres tables
-- ---------------------------------------------------------------------
alter table public.participants enable row level security;
-- Aucune policy, volontairement : les rôles publics ne peuvent rien.
-- Le générateur lit par l'API de management, qui passe outre RLS.
revoke all on public.participants from anon, authenticated;
revoke all on public.v_badges     from anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Le contrôle
-- ---------------------------------------------------------------------
--  À lancer après chaque import. Une ligne rendue = un badge qui
--  sortirait sans code alors que sa catégorie devrait en avoir un.
create or replace function public.verifier_badges()
returns table(categorie text, raison_sociale text, prenom text, nom text, souci text)
language sql stable as $$
  select v.categorie, v.raison_sociale, v.prenom, v.nom,
         case when v.code is null then 'aucun code'
              else 'code inconnu de la base' end
  from public.v_badges v
  where v.categorie <> 'EQUIPE_BONY'
    and v.categorie <> 'CONSTRUCTEUR'
    and (v.code is null
         or not exists (select 1 from public.garages    g where upper(g.code)    = upper(v.code))
        and not exists (select 1 from public.stands     s where upper(s.code_pin) = upper(v.code))
        and not exists (select 1 from public.animations a where upper(a.code_pin) = upper(v.code))
        and not exists (select 1 from public.config     c where c.cle in ('pin_accueil','pin_admin')
                                                            and upper(c.valeur) = upper(v.code)))
  order by v.categorie, v.raison_sociale;
$$;

comment on table public.participants is
  'Qui porte un badge. Ne contient aucun code : ils sont résolus par v_badges.';
comment on view public.v_badges is
  'Ce que lit le générateur de badges. Un badge par ligne, nb_badges exemplaires.';
