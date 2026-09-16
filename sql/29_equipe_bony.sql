-- =====================================================================
--  Forum Pièces Bony 2026 — 29 — L'équipe Bony sur les badges
--
--  DEUX DEMANDES DE BASTIEN, le 17 septembre :
--    « l'équipe Bony : tu mets la même raison sociale à tout le monde »
--    « pour l'export il faut que ce soit par ordre alphabétique des
--      NOMS DE FAMILLE »
--
--  La seconde se règle dans badges\badges.js ; celle-ci s'occupe des
--  données, et de ce qui empêchait le tri de marcher.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Une seule raison sociale
-- ---------------------------------------------------------------------
--  Il y en avait VINGT ET UNE pour 119 personnes, toutes saisies à la
--  main dans le formulaire d'inscription : « BONY AUTOMOBILES »,
--  « BONY AUTOMOBILES figeac », « eaa mozac », « SAS BONY AUTO MOBILE
--  BSO », « E2A », « BONYAUTO-MOBILE »… Sur un badge, cette ligne est
--  écrite en plus gros que le nom de la personne : 21 orthographes
--  côte à côte au cou de la même équipe, ça se remarque de loin.
--
--  La graphie retenue est celle de Bastien, au caractère près. Elle
--  figurait déjà telle quelle sur trois lignes, saisies par leurs
--  titulaires — ce n'est donc pas une invention.
--
--  ⚠️ ON PERD L'INFORMATION DE FILIALE. EAA, BSO, SODAVI, E2A étaient
--  la seule trace de qui appartient à quelle enseigne, et elle n'est
--  nulle part ailleurs dans cette base. C'est un arbitrage d'affichage,
--  assumé : le badge dit le groupe, pas l'établissement. Si la filiale
--  redevient utile un jour, elle est à reprendre dans le listing
--  consolidé du 15, pas ici.
update public.participants
   set raison_sociale = 'Bony auto-mobile'
 where actif
   and categorie = 'EQUIPE_BONY'
   and raison_sociale <> 'Bony auto-mobile';

-- ---------------------------------------------------------------------
-- 2. Le seul nom qui aurait mal trié
-- ---------------------------------------------------------------------
--  Trier par nom de famille suppose que la colonne `nom` en contienne
--  un. Elle vient du formulaire d'inscription, et une personne a rempli
--  les deux champs à l'envers : prenom = BRUCHET, nom = PATRICK. Son
--  badge annonçait donc « BRUCHET PATRICK », et le tri l'aurait rangé à
--  la lettre P, entre PAYA et PIZZI, où personne ne l'aurait cherché.
--
--  L'adresse tranche sans ambiguïté — patrick.bruchet@ — et c'est le
--  seul cas : les 118 autres lignes ont été recoupées avec la partie
--  locale de leur adresse, aucune autre inversion.
update public.participants
   set prenom = 'Patrick', nom = 'BRUCHET'
 where cle_source = 'mail:patrick.bruchet@bonyauto-mobile.com'
   and upper(prenom) = 'BRUCHET';

commit;
