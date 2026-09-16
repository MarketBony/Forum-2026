-- =====================================================================
--  Forum Pièces Bony 2026 — 28 — Qui est inscrit à la réunion d'agents
--
--  POURQUOI CETTE COLONNE.
--  Les badges des agents doivent sortir EN TÊTE du PDF garage : la
--  réunion d'agents a lieu le matin, avant le Forum, et on distribue
--  cette pile-là en premier. Demande de Bastien le 16 septembre :
--  « Agents de A à Z puis reste des garages de A à Z ».
--
--  ⚠️ LA LETTRE DE PROFIL NE RÉPOND PAS À LA QUESTION, et s'y fier
--  donnait une pile fausse. `garages.profil` vient du fichier Sarbacane
--  et dit qui a été INVITÉ à quoi :
--
--      A = Réunion + Forum                  Agent Historique  (49)
--      B = Réunion + Visite + Forum         Agent BSO         (43)
--      C = Forum                            MRA + Motrio Histo (1291)
--      D = Visite + Forum                   Motrio BSO         (24)
--
--  Être invité n'est pas être inscrit. Mesuré sur les 145 lignes garage :
--    · 18 agents inscrits sont rattachés à un garage de profil `INSCRIT`
--      — un garage créé par l'import du 15, dont la lettre est inconnue.
--      Le tri par lettre les aurait tous laissés dans la pile du fond.
--    ·  2 garages de profil A ne sont PAS inscrits à la réunion. Le tri
--      par lettre les aurait mis dans la pile du matin pour rien.
--  Soit 33 lignes par la lettre contre 51 par l'inscription réelle.
--
--  LA SOURCE, c'est donc la colonne « Réunion » de
--  FORUM_2026_Inscriptions_consolidees_15-09.xlsx, onglet
--  INSCRITS_CONSOLIDES : elle vaut « oui » quand la personne s'est
--  inscrite à la réunion, et reste vide pour les profils C et D, qui
--  n'y étaient pas conviés.
--
--  CE QUE LA COLONNE NE DIT PAS. Les 55 collaborateurs Bony arrivés par
--  le listing du 16 (sql/27) ne sont pas marqués : ce fichier-là donne
--  le profil d'INVITATION, pas l'inscription. Les marquer mélangerait
--  deux choses différentes sous un même drapeau. Ceux d'entre eux qui
--  s'étaient inscrits par le formulaire sont déjà couverts ci-dessous.
--
--  Rejouable : la liste est remise à plat avant d'être reposée, donc
--  retirer quelqu'un de ce fichier le retire bien du drapeau.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. La colonne
-- ---------------------------------------------------------------------
alter table public.participants
  add column if not exists reunion_agents boolean not null default false;

comment on column public.participants.reunion_agents is
  'Inscrit à la réunion d''agents du matin. Source : colonne « Réunion » du consolidé du 15/09. Sert à sortir ces badges en tête du PDF.';

-- ---------------------------------------------------------------------
-- 2. Qui est inscrit
-- ---------------------------------------------------------------------
--  On remet tout à faux d'abord : sans ça, quelqu'un retiré de la liste
--  garderait son drapeau et resterait dans la pile du matin sans qu'on
--  s'en aperçoive — une erreur qui ne se voit qu'à la table d'accueil.
update public.participants set reunion_agents = false where reunion_agents;

update public.participants set reunion_agents = true
 where lower(email) in (
  'arthur.duranton@bonyauto-mobile.com',
  'aurore.vaur@bonyauto-mobile.com',
  'benjamin.bourron@bonyauto-mobile.com',
  'benoit.rousseau@bonyauto-mobile.com',
  'caroline.fabre@bonyauto-mobile.com',
  'castel.auto@orange.fr',
  'cedric.daude@bonyauto-mobile.com',
  'christophe.aujols@bonyauto-mobile.com',
  'compta.bousquet@gmail.com',
  'contact@brauto48.fr',
  'contact@garage-brossy.fr',
  'contact@garage-du-haut-lignon.fr',
  'contact@garageliogier.com',
  'contact@langeacauto.fr',
  'denis.fossiez@garage-du-haut-lignon.fr',
  'excel-auto@orange.fr',
  'francis.dubois@bonyauto-mobile.com',
  'franck.salas@bonyauto-mobile.com',
  'franck.tixier@bonyauto-mobile.com',
  'franck.tixier@bonyhauto-mobile.com',
  'franckroddier1969@gmail.com',
  'fx.dub@orange.fr',
  'garage-bertrand-43370@orange.fr',
  'garage-gilliet-03160@orange.fr',
  'garage.bousquet0985@orange.fr',
  'garage.chapteuil@orange.fr',
  'garage.gascuel@orange.fr',
  'garage.gires@gmail.com',
  'garage.laplace.renault@gmail.com',
  'garage.mauriange@orange.fr',
  'garage.montagner-63910@orange.fr',
  'garage.observatoire@orange.fr',
  'garage.saquet@wanadoo.fr',
  'garage.sers@orange.fr',
  'garage.servel@orange.fr',
  'garage.tenceautoservices@gmail.com',
  'garage@grignac.com',
  'garageborsier@orange.fr',
  'garagecailhol@orange.fr',
  'garagechateaugayautos63119@orange.fr',
  'garagedejob42440@orange.fr',
  'garagedesorgues@orange.fr',
  'garagerenaultbillom@orange.fr',
  'garagerenaultlezoux@orange.fr',
  'garagethevenet.e@yahoo.com',
  'garageviguier@orange.fr',
  'garge.ayral@orange.fr',
  'ggevalleix@gmail.com',
  'gilles.parrain@bonyauto-mobile.com',
  'henrycampillo@orange.fr',
  'jean-baptiste.batisson@bonyauto-mobile.com',
  'jean-claude.davayat@bonyauto-mobile.com',
  'jean-francois.larget@bonyauto-mobile.com',
  'jean-luc.j.bisch@renault.com',
  'jean-philippe.cazes@bonyauto-mobile.com',
  'jeremy.mercadier12@orange.fr',
  'jerome.hebert@bonyauto-mobile.com',
  'julien.douzou@bonyauto-mobile.com',
  'julien.garagebassot@orange.fr',
  'julien.rafinesque@bonyauto-mobile.com',
  'laurent.garnier@bonyauto-mobile.com',
  'livernonautomobiles@orange.fr',
  'loic.tiers@bonyauto-mobile.com',
  'lucien.marchetti@bonyauto-mobile.com',
  'mecanique@garagegrandouiller.fr',
  'mickael.bony@bonyauto-mobile.com',
  'mickael.masson@bonyauto-mobile.com',
  'monteilletyohan@gmail.com',
  'olivier.rollet@bonyauto-mobile.com',
  'patrick.bruchet@bonyauto-mobile.com',
  'pierre-michel.erard@bonyauto-mobile.com',
  'pierre.duverger@bonyauto-mobile.com',
  'pmauto.albi@gmail.com',
  'raphael.fuziol@bonyauto-mobile.com',
  'remi.pizzi@bonyauto-mobile.com',
  'renault.gimel@gmail.com',
  'renault.massiac@orange.fr',
  'renaultamberta@gmaul.com',
  'renaultriom@gmail.com',
  'romain.fradetal@bonyauto-mobile.com',
  'romain.zennouche@bonyauto-mobile.com',
  'rose-marie.regis@bonyauto-mobile.com',
  'sarl-joaquimgomes@orange.fr',
  'sarlcanevet@wanadoo.fr',
  'sarljouveetfils@wanadoo.fr',
  'sasgarage.thomas03@gmail.com',
  'severine.besson@bonyauto-mobile.com',
  'station89.garage@gmail.com',
  'stephane.gaudon@bonyauto-mobile.com',
  'stephanie.marty@bonyauto-mobile.com',
  'thierry.coignac@bonyauto-mobile.com',
  'thierry.wintzenrieth@renault.com'
);

-- ---------------------------------------------------------------------
-- 3. La vue que lit le générateur
-- ---------------------------------------------------------------------
--  La colonne s'ajoute EN FIN de liste : `create or replace view`
--  accepte un ajout à la fin, jamais une insertion au milieu ni un
--  changement de type. Le reste de la vue est identique à
--  sql/19_participants.sql — si elle y est retouchée, reporter ici.
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
  p.note,
  p.reunion_agents
from public.participants p
left join public.garages    g on g.id = p.garage_id
left join public.stands     s on s.id = p.stand_id
left join public.animations a on a.id = p.animation_id
where p.actif;

revoke all on public.v_badges from anon, authenticated;

commit;
