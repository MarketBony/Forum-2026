-- =====================================================================
--  Forum Pièces Bony 2026 — 21 — Les badges du personnel
--
--  Exposants, animateurs et hôtesses. Contrairement aux garages et à
--  l'équipe Bony, ceux-là ne viennent d'aucun fichier nominatif :
--  décision de l'utilisateur le 14 septembre, on ne met pas de nom.
--
--    Exposants  : 5 badges par stand, interchangeables. Qui que soit la
--                 personne présente, elle prend un badge sur la pile.
--    Animateurs : un par jeu, « Animateur 1 » — le numéro laisse la
--                 place à un second si le jeu tourne à deux.
--    Hôtesses   : deux comptes, Hôtesse 1 et Hôtesse 2.
--
--  LES LIBELLÉS SONT CEUX DE BONY, PAS CEUX DE LA BASE. « TOTAL ELF »
--  plutôt que « ELF », « AGENTS » plutôt que « AGENT » : c'est ce qui
--  sera lu sur le badge et sur le stand. Le rattachement, lui, se fait
--  sur le nom en base, qui porte le PIN.
--
--  LE CODE N'EST PAS RECOPIÉ ICI. Il est résolu par la vue v_badges au
--  moment de la lecture : changer un PIN de stand met donc à jour les
--  badges de ce stand sans retoucher une ligne de cette table. La
--  décision n°4 — figer les PIN du personnel — reste jouable jusqu'au
--  dernier moment.
--
--  Rejouable : cle_source est stable, un second passage met à jour.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Les exposants — 5 badges par stand
-- ---------------------------------------------------------------------
--  IXELL et MOTRIO sont DEUX stands en base, avec deux PIN distincts.
--  La liste de Bony les écrit sur une seule ligne (« IXELL / MOTRIO ») ;
--  on les garde séparés, sinon la moitié des badges d'un stand portent
--  le code de l'autre. À fusionner si c'est bien un seul stand.
insert into public.participants
  (categorie, raison_sociale, prenom, nom, nb_badges, stand_id, cle_source)
select 'EXPOSANT', v.libelle, '', '', 5, s.id, 'stand:' || v.base
from (values
  ('MICHELIN',           'MICHELIN'),
  ('FILLON TECHNOLOGIE', 'FILLON TECHNOLOGIE'),
  ('IXELL',              'IXELL'),
  ('MOTRIO',             'MOTRIO'),
  ('AGENTS',             'AGENT'),
  ('ACCESSOIRES',        'ACCESSOIRES'),
  ('GOODYEAR',           'GOODYEAR'),
  ('SAM',                'SAM'),
  ('FAAB',               'FAAB'),
  ('CISCAR',             'CISCAR'),
  ('FACOM',              'FACOM'),
  ('SPM',                'SPM'),
  ('SIDEXA',             'SIDEXA'),
  ('NILFISK',            'NILFISK'),
  ('CASTROL',            'CASTROL'),
  ('MATEXPERT',          'MATEXPERT'),
  ('FIDUCIAL',           'FIDUCIAL'),
  ('WYZ',                'WYZ'),
  ('BARDHAL',            'BARDHAL'),
  ('CHIMIREC',           'CHIMIREC'),
  ('PROVAC',             'PROVAC'),
  ('TOTAL ELF',          'ELF'),
  ('EXADIS',             'EXADIS')
) as v(libelle, base)
join public.stands s on s.nom = v.base and s.actif
on conflict (cle_source) do update set
  categorie = excluded.categorie, raison_sociale = excluded.raison_sociale,
  nb_badges = excluded.nb_badges, stand_id = excluded.stand_id, actif = true;

-- ---------------------------------------------------------------------
-- 2. Les animateurs — un par jeu
-- ---------------------------------------------------------------------
insert into public.participants
  (categorie, raison_sociale, prenom, nom, nb_badges, animation_id, cle_source)
select 'ANIMATION', a.nom, '', 'Animateur 1', 1, a.id, 'anim:' || a.nom
from public.animations a
where a.actif
on conflict (cle_source) do update set
  categorie = excluded.categorie, raison_sociale = excluded.raison_sociale,
  nom = excluded.nom, nb_badges = excluded.nb_badges,
  animation_id = excluded.animation_id, actif = true;

-- ---------------------------------------------------------------------
-- 3. Les hôtesses — deux comptes
-- ---------------------------------------------------------------------
--  ⚠️ Les deux badges porteront le MÊME code : il n'y a qu'un
--  `pin_accueil` dans config. Deux codes distincts demanderaient une
--  modification de sql\13_porte.sql et un nouveau passage des 104
--  tests — à demander si c'est vraiment voulu.
insert into public.participants
  (categorie, raison_sociale, prenom, nom, nb_badges, cle_source)
values
  ('HOTESSE', 'Accueil', '', 'Hôtesse 1', 1, 'hotesse:1'),
  ('HOTESSE', 'Accueil', '', 'Hôtesse 2', 1, 'hotesse:2')
on conflict (cle_source) do update set
  categorie = excluded.categorie, raison_sociale = excluded.raison_sociale,
  nom = excluded.nom, nb_badges = excluded.nb_badges, actif = true;

commit;
