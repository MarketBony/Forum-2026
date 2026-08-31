-- =====================================================================
--  Forum Pièces Bony 2026 — 99 — Remise à zéro
--
--  À exécuter APRÈS la répétition générale et AVANT l'ouverture des
--  portes, pour repartir d'un compteur vierge.
--
--    .\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql
--
--  Ce fichier existe parce que le journal refuse tout DELETE : c'est
--  volontaire, et cela veut dire qu'une purge doit être une opération
--  explicite, tracée, jamais un effet de bord d'une manipulation. Le
--  verrou d'immuabilité est levé pour la durée de l'opération puis
--  systématiquement remis en place.
--
--  ATTENTION : cette opération est irréversible et il n'y a pas de
--  sauvegarde automatique sur le plan gratuit. Exportez le journal
--  avant (voir l'export CSV de l'espace Bony).
-- =====================================================================

begin;

-- 1. Libérer les références de la grille vers le journal (clé étrangère)
update public.grille
   set garage_id = null, journal_id = null, joue_le = null,
       code_retrait = null, remis = false, remis_le = null;

-- 2. Purge du journal, verrou d'immuabilité momentanément levé
alter table public.journal disable trigger journal_pas_de_modif;
delete from public.journal;
alter table public.journal enable trigger journal_pas_de_modif;

-- 3. Portefeuilles et appareils
update public.garages set solde = 0, inscrit_le = null;
delete from public.appareils;

commit;

-- 4. Retirer les 388 garages de test de charge.
--    À décommenter une fois la vraie liste d'invités importée.
-- delete from public.garages where ville = 'DÉMO';

-- 5. Contrôle
select
  (select count(*) from public.journal)                          as lignes_journal,
  (select count(*) from public.appareils)                        as appareils,
  (select count(*) from public.garages where solde <> 0)         as garages_avec_solde,
  (select count(*) from public.grille where garage_id is not null) as cases_jouees,
  (select count(*) from public.verifier_soldes())                as ecarts;
