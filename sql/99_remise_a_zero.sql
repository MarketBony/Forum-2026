-- =====================================================================
--  Forum Pièces Bony 2026 — 99 — Remise à zéro après la répétition
--
--  À LANCER LA VEILLE DE L'ÉVÉNEMENT, une fois la répétition terminée.
--  Efface tout ce qui a été joué ; ne touche NI aux garages, NI à leurs
--  codes d'accès, NI à la composition de la grille.
--
--      .\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql
--
--  ⚠️ CE QUE CE FICHIER NE FAIT PAS : il ne recompose pas la grille.
--  La nature des cases (85 lots / 15 tickets d'or / 100 perdantes) et
--  les libellés des lots sont conservés — c'est 18_lots.sql qui les
--  pose, et le refaire ici obligerait à retirer les numéros au sort
--  après chaque répétition.
--
--  ⚠️ IL EFFACE LE JOURNAL. Le journal est en ajout seul et le trigger
--  est désactivé le temps de la purge : c'est la SEULE circonstance où
--  cela se fait, et c'est pour cela que ce fichier porte le numéro 99.
--  Ne jamais le lancer pendant l'événement.
--
--  ---------------------------------------------------------------
--  CORRECTION DU 11 SEPTEMBRE 2026 — ce fichier était cassé.
--  Il remettait à zéro « joue_le », colonne SUPPRIMÉE par 06_bingo.sql
--  et remplacée par achete_le / revele_le. Lancé la veille du Forum, il
--  aurait échoué en bloc (toute la transaction annulée) et la grille
--  serait restée pleine des achats de la répétition — sans que rien
--  n'avertisse, sinon un HTTP 400 au milieu d'une sortie bavarde.
--  Il ne purgeait pas non plus les tentatives ni le tirage.
--  ---------------------------------------------------------------
-- =====================================================================

begin;

-- 1. La grille rend les cases, garde sa composition
--    nature et lot ne sont PAS touchés : voir l'avertissement ci-dessus.
update public.grille
   set garage_id    = null,
       journal_id   = null,
       achete_le    = null,
       revele_le    = null,
       code_retrait = null,
       remis        = false,
       remis_le     = null;

-- 2. Le journal — seul endroit du projet où le trigger d'immuabilité
--    est levé, et seulement le temps de cette transaction.
alter table public.journal disable trigger journal_pas_de_modif;
delete from public.journal;
alter table public.journal enable trigger journal_pas_de_modif;

-- 3. Les portefeuilles repartent à zéro, l'inscription est à refaire
--    (c'est elle qui redonnera le bonus d'arrivée le jour J).
update public.garages set solde = 0, inscrit_le = null;

-- 4. Les téléphones. À faire APRÈS le journal : la clé étrangère
--    journal.appareil_id interdirait la suppression autrement.
delete from public.appareils;

-- 5. Le frein anti-devinette. Sans cette purge, un téléphone qui a
--    épuisé ses essais pendant la répétition resterait bloqué le 17.
delete from public.tentatives;

-- 6. Le grand tirage, et le drapeau qui dit qu'il a été ouvert.
delete from public.tirage;
update public.config set valeur = 'non' where cle = 'tirage_ouvert';

commit;

-- ---------------------------------------------------------------------
-- Contrôle : tout doit être à zéro, et la composition intacte
-- ---------------------------------------------------------------------
select
  (select count(*) from public.journal)                             as lignes_journal,
  (select count(*) from public.appareils)                           as appareils,
  (select count(*) from public.tentatives)                          as tentatives,
  (select count(*) from public.tirage)                              as tirage,
  (select count(*) from public.garages where solde <> 0)            as garages_avec_solde,
  (select count(*) from public.grille where garage_id is not null)  as cases_jouees,
  (select count(*) from public.verifier_soldes())                   as ecarts,
  -- la composition, elle, doit AVOIR SURVÉCU
  (select count(*) from public.grille where nature = 'lot')         as cases_lot,
  (select count(*) from public.grille where nature = 'billet')      as tickets_or,
  (select count(*) from public.grille where nature = 'perdante')    as cases_perdantes;
