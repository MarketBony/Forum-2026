-- =====================================================================
--  Forum Pièces Bony 2026 — 27 — Les collaborateurs et les constructeurs
--
--  Source : « LISTING INVITATION COLLABORATEURS BONY — FORUM —
--  SEPTEMBRE 2026 », remis le 16 septembre. Deux onglets :
--    « bony »    — 116 collaborateurs, dont 60 s'étaient déjà inscrits
--                  par le formulaire et sont donc en base depuis le 15.
--    « renault » — 21 invités constructeur, identifiés par leur SEULE
--                  adresse e-mail : ni nom ni prénom dans le fichier.
--
--  POURQUOI UN FICHIER SQL ET PAS importer-inscriptions.ps1.
--  L'importateur existe pour rapprocher un inscrit de SON GARAGE, sur
--  la raison sociale. Ce listing-ci n'a pas de colonne société, et
--  personne dedans n'a de garage : ce sont des salariés et des invités
--  constructeur. Il n'y a rien à rapprocher, seulement à écrire — d'où
--  ce fichier plutôt qu'un passage de l'outil, qui refuserait d'ailleurs
--  le classeur faute de colonne « raison sociale ».
--
--  LES NOMS DÉDUITS D'UNE ADRESSE. 25 lignes n'ont ni nom ni prénom. On
--  les tire de la partie locale (prenom.nom@), en traitant un jeton du
--  milieu d'une ou deux lettres comme une initiale de désambiguïsation :
--  « jean-luc.j.bisch » donne Jean-Luc BISCH, « gerard.gg.gros » donne
--  Gerard GROS.
--
--  ⚠️ LES ACCENTS NE SONT JAMAIS INVENTÉS. Un prénom n'est accentué que
--  si Bony l'a elle-même écrit ainsi ailleurs dans CE classeur — « Théo »,
--  « François », « Rémi », « Jérome » y sont attestés, donc repris tels
--  quels, y compris « Jérome » sans accent circonflexe, qui est la
--  graphie de Bony. Deux prénoms restent sans accent faute d'attestation :
--  Gerard GROS et Herve MOREAU. Ils sortiront ainsi plutôt que mal
--  orthographiés ; deux `update` d'une ligne suffiront si quelqu'un
--  connaît la bonne graphie.
--
--  Rejouable : cle_source vaut « mail:<adresse> », comme pour l'import
--  du 15 septembre. Repousser ce fichier met à jour, il ne duplique pas.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Une correction : la ligne de Franck TIXIER porte le nom d'un autre
-- ---------------------------------------------------------------------
--  L'import du 15 a écrit « Thierry DUBERNAT » sur la ligne dont
--  l'adresse est franck.tixier@bonyauto-mobile.com. Le listing du 16
--  départage les deux sans ambiguïté : DUBERNAT Thierry a sa propre
--  adresse (thierry.dubernat@), et franck.tixier@ est bien Franck
--  TIXIER. Sans cette correction, Franck Tixier portait au cou le badge
--  de son collègue, et Thierry Dubernat en recevait un second.
update public.participants
   set prenom = 'Franck', nom = 'TIXIER'
 where cle_source = 'mail:franck.tixier@bonyauto-mobile.com'
   and nom = 'DUBERNAT';

-- ---------------------------------------------------------------------
-- 2. Les collaborateurs Bony absents de la base
-- ---------------------------------------------------------------------
--  raison_sociale = « Bony Auto-mobile » pour tous : le fichier ne porte
--  aucune société, et le nom du groupe est vrai pour chacun. Arbitrage
--  du 16/09. Les 60 déjà en base gardent la filiale qu'ils avaient
--  saisie eux-mêmes (« EAA », « BSO », « BONY AUTOMOBILES »…) : on ne
--  l'écrase pas, c'est une information qu'ils ont donnée et nous pas.
--
--  AUCUN CODE, volontairement — voir sql/19_participants.sql : le code
--  supervision ouvre la remise des lots, les corrections de points et
--  l'écran de projection. L'imprimer sur 124 badges reviendrait à le
--  distribuer à tout le monde. La boîte du verso sort vide, prête à
--  être remplie à la main pour les deux ou trois qui en ont besoin.
insert into public.participants
  (categorie, raison_sociale, prenom, nom, email, nb_badges, cle_source, note)
values
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Hugo', 'CULETTO', 'hugo.culetto@bonyauto-mobile.com', 1, 'mail:hugo.culetto@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Alexis', 'PERZ', 'alexis.perz@bonyauto-mobile.com', 1, 'mail:alexis.perz@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Franck', 'NOGUES', 'franck.nogues@bonyauto-mobile.com', 1, 'mail:franck.nogues@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Gilles', 'PARRAIN', 'gilles.parrain@bonyauto-mobile.com', 1, 'mail:gilles.parrain@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Yoann', 'PICARD', 'yoann.picard@bonyauto-mobile.com', 1, 'mail:yoann.picard@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Jérome', 'HEBERT', 'jerome.hebert@bonyauto-mobile.com', 1, 'mail:jerome.hebert@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Magali', 'MICHEL', 'magali.michel@bonyauto-mobile.com', 1, 'mail:magali.michel@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Jean-Paul', 'RANVOISE', 'jean-paul.ranvoise@bonyauto-mobile.com', 1, 'mail:jean-paul.ranvoise@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Arthur', 'DURANTON', 'arthur.duranton@bonyauto-mobile.com', 1, 'mail:arthur.duranton@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Thierry', 'DUBERNAT', 'thierry.dubernat@bonyauto-mobile.com', 1, 'mail:thierry.dubernat@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Virginie', 'CUMINAL', 'virginie.cuminale@bonyauto-mobile.com', 1, 'mail:virginie.cuminale@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Robin', 'RABOISSON', 'robin.raboisson@bonyauto-mobile.com', 1, 'mail:robin.raboisson@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Robin', 'GUERY', 'robin.guery@bonyauto-mobile.com', 1, 'mail:robin.guery@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Julien', 'SPADAT', 'julien.spadat@bonyauto-mobile.com', 1, 'mail:julien.spadat@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Daniel', 'ESTEVES', 'daniel.esteves@bonyauto-mobile.com', 1, 'mail:daniel.esteves@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Dorian', 'ALLEGRE', 'dorian.allegre@bonyauto-mobile.com', 1, 'mail:dorian.allegre@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Thomas', 'BERT', 'thomas.bert@bonyauto-mobile.com', 1, 'mail:thomas.bert@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Romain', 'BOISSONNADE', 'romain.boissonnade@bonyauto-mobile.com', 1, 'mail:romain.boissonnade@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Rémi', 'DEGAND', 'remi.degand@bonyauto-mobile.com', 1, 'mail:remi.degand@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Anthony', 'ENJALBERT', 'anthony.enjalbert@bonyauto-mobile.com', 1, 'mail:anthony.enjalbert@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Laurent', 'BRESSAN', 'laurent.bressan@bonyauto-mobile.com', 1, 'mail:laurent.bressan@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Elsa', 'AGRINIER', 'elsa.agrinier@bonyauto-mobile.com', 1, 'mail:elsa.agrinier@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Christophe', 'DARROUS', 'christophe.darrous@bonyauto-mobile.com', 1, 'mail:christophe.darrous@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Germain', 'ENDRINAL', 'germain.endrinal@bonyauto-mobile.com', 1, 'mail:germain.endrinal@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Béatrice', 'VIRAZELS', 'beatrice.virazels@bonyauto-mobile.com', 1, 'mail:beatrice.virazels@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Mickael', 'MOINE', 'mickael.moine@bonyauto-mobile.com', 1, 'mail:mickael.moine@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Guillaume', 'SEGUI', 'guillaume.segui@bonyauto-mobile.com', 1, 'mail:guillaume.segui@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Flavien', 'MILLON', 'flavien.millon@bonyauto-mobile.com', 1, 'mail:flavien.millon@bonyauto-mobile.com', 'Profil A - Réunion Agents + Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Didier', 'SAROTTI', 'didier.sarotti@bonyauto-mobile.com', 1, 'mail:didier.sarotti@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Christophe', 'DEBEAUCE', 'christophe.debeauce@bonyauto-mobile.com', 1, 'mail:christophe.debeauce@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Michel', 'PESSIEAU', 'michel.pessieau@bonyauto-mobile.com', 1, 'mail:michel.pessieau@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Jean-Marc', 'BERTHEZENE', 'jean-marc.berthezene@bonyauto-mobile.com', 1, 'mail:jean-marc.berthezene@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Christelle', 'SABATIER', 'christelle.sabatier@bonyauto-mobile.com', 1, 'mail:christelle.sabatier@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Christophe', 'PASQUIER', 'christophe.pasquier@bonyauto-mobile.com', 1, 'mail:christophe.pasquier@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Olivier', 'BONNOT', 'olivier.bonnot@bonyauto-mobile.com', 1, 'mail:olivier.bonnot@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Gyslain', 'MULLER', 'gyslain.muller@bonyauto-mobile.com', 1, 'mail:gyslain.muller@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Didier', 'PRADAYROL', 'didier.pradayrol@bonyauto-mobile.com', 1, 'mail:didier.pradayrol@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Thierry', 'GINESTE', 'thierry.gineste@bonyauto-mobile.com', 1, 'mail:thierry.gineste@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Coralie', 'LABORIE', 'coralie.laborie@bonyauto-mobile.com', 1, 'mail:coralie.laborie@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Maxime', 'CHARENTON', 'maxime.charenton@bonyauto-mobile.com', 1, 'mail:maxime.charenton@bonyauto-mobile.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Louis', 'MERCIER', 'louis.mercier@bonyauto-mobile.com', 1, 'mail:louis.mercier@bonyauto-mobile.com', 'Profil C - Forum'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Mimoun', 'AFKIR', 'mimoun.afkir@bonyauto-mobile.com', 1, 'mail:mimoun.afkir@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Gaetan', 'ALBESPY', 'gaetan.albespy@bonyauto-mobile.com', 1, 'mail:gaetan.albespy@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Christopher', 'AURAT', 'christopher.aurat@bonyauto-mobile.com', 1, 'mail:christopher.aurat@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Ozan', 'AYYILDIZ', 'ozan.ayyildiz@bonyauto-mobile.com', 1, 'mail:ozan.ayyildiz@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Gilles', 'BOUKIR', 'gilles.boukir@bonyauto-mobile.com', 1, 'mail:gilles.boukir@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Géraud', 'COMBOURIEU', 'geraud.combourieu@bonyauto-mobile.com', 1, 'mail:geraud.combourieu@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Jeremy', 'DOMPS', 'jeremy.domps@bonyauto-mobile.com', 1, 'mail:jeremy.domps@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Bruno', 'GRANGEON', 'bruno.grangeon@bonyauto-mobile.com', 1, 'mail:bruno.grangeon@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Julien', 'GUESDON', 'julien.guesdon@bonyauto-mobile.com', 1, 'mail:julien.guesdon@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Olivier', 'GUILLON', 'olivier.guillon@bonyauto-mobile.com', 1, 'mail:olivier.guillon@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Franck', 'LLORENS', 'franck.llorens@bonyauto-mobile.com', 1, 'mail:franck.llorens@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Emmanuel', 'PAPON', 'emmanuel.papon@bonyautomobiles.com', 1, 'mail:emmanuel.papon@bonyautomobiles.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Jean-François', 'ROSIER', 'jean-francois.rosier@bonyauto-mobile.com', 1, 'mail:jean-francois.rosier@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation'),
  ('EQUIPE_BONY', 'Bony Auto-mobile', 'Nicolas', 'TABARAN', 'nicolas.tabaran@bonyauto-mobile.com', 1, 'mail:nicolas.tabaran@bonyauto-mobile.com', 'Listing collaborateurs 16/09 - sans profil d''invitation')
on conflict (cle_source) do update set
  categorie = excluded.categorie, prenom = excluded.prenom,
  nom = excluded.nom, email = excluded.email, note = excluded.note,
  actif = true;

-- ---------------------------------------------------------------------
-- 3. Les invités constructeur
-- ---------------------------------------------------------------------
--  CONSTRUCTEUR est une catégorie prévue depuis le 14 septembre et
--  restée vide jusqu'ici. Elle n'a volontairement AUCUN code : un
--  constructeur ne joue pas, ne crédite personne et n'achète pas de
--  case. verifier_badges() l'exclut pour cette raison précise.
--
--  DEUX D'ENTRE EUX SONT DÉJÀ EN BASE, EN CATÉGORIE GARAGE. Jean-Luc
--  BISCH et Thierry WINTZENRIETH se sont inscrits par le lien d'un
--  client — c'est exactement le cas « ID_MAUVAISE_CIBLE » décrit dans
--  sql/19_participants.sql — et l'import du 15 leur a fabriqué un
--  garage « RENAULT ». Le `on conflict` ci-dessous les bascule ET remet
--  garage_id à null. Sans ce null, la contrainte d'un seul rattachement
--  tiendrait toujours, mais v_badges leur résoudrait encore le code du
--  garage fantôme : leur badge « Constructeur » sortirait avec un code
--  jouable, et deux invités Renault pourraient acheter des cases.
--
--  Olivier BOEUF figure dans l'onglet constructeur avec une adresse
--  Bony. La catégorie suit l'onglet (arbitrage du 16/09), la société
--  suit l'adresse : on ne le déclare pas salarié Renault.
insert into public.participants
  (categorie, raison_sociale, prenom, nom, email, nb_badges, cle_source, note)
values
  ('CONSTRUCTEUR', 'RENAULT', 'Antoine', 'RENAC', 'antoine.renac@renault.com', 1, 'mail:antoine.renac@renault.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Benoit', 'BEGUE', 'benoit.begue@renault.com', 1, 'mail:benoit.begue@renault.com', 'CDA R1 Coté So - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Benoit', 'MARGERIE', 'benoit.margerie@renault.com', 1, 'mail:benoit.margerie@renault.com', 'MANAGER CIE IXELL - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'David', 'VERISSIMO', 'david.verissimo@renault.com', 1, 'mail:david.verissimo@renault.com', 'ABM - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'François', 'DELION', 'francois.delion@renault.com', 1, 'mail:francois.delion@renault.com', 'monde - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Gerard', 'GROS', 'gerard.gg.gros@renault.com', 1, 'mail:gerard.gg.gros@renault.com', 'ACCESSOIRES ET RENAULT MERCH - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Guillaume', 'GOSSELIN', 'guillaume.gosselin@renault.com', 1, 'mail:guillaume.gosselin@renault.com', 'CDA R2 - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Guillaume', 'HUREL', 'guillaume.hurel@renault.com', 1, 'mail:guillaume.hurel@renault.com', 'directeur apv France - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Guillaume', 'MELLAC', 'guillaume.mellac@renault.com', 1, 'mail:guillaume.mellac@renault.com', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Herve', 'MOREAU', 'herve.moreau@renault.com', 1, 'mail:herve.moreau@renault.com', 'MCGE - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Jean-Luc', 'BISCH', 'jean-luc.j.bisch@renault.com', 1, 'mail:jean-luc.j.bisch@renault.com', 'DTVE SODICAM - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Jeremy', 'YVON', 'jeremy.yvon@renault.com', 1, 'mail:jeremy.yvon@renault.com', 'CTC IXELL - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Julien', 'DOMINGOS', 'julien.domingos@renault.com', 1, 'mail:julien.domingos@renault.com', 'RMV IXELL - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Mathieu', 'MIGNON', 'mathieu.mignon@renault.co.uk', 1, 'mail:mathieu.mignon@renault.co.uk', 'Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Steve', 'ROUMAGNAC', 'steve.roumagnac@renault.com', 1, 'mail:steve.roumagnac@renault.com', 'MRAV Coté So - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Thibaut', 'ALEXANDRE', 'thibaut.alexandre@renault.com', 1, 'mail:thibaut.alexandre@renault.com', 'ABM - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Thierry', 'WINTZENRIETH', 'thierry.wintzenrieth@renault.com', 1, 'mail:thierry.wintzenrieth@renault.com', 'RESPONSABLE ENSEIGNE MOTRIO - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Thomas', 'GARDNER', 'thomas.gardner@renault.com', 1, 'mail:thomas.gardner@renault.com', 'DT SODICAM - Profil B - Réunion Agents + Forum + Visite de la plateforme'),
  ('CONSTRUCTEUR', 'RENAULT', 'Christophe', 'REY', 'christophe.rey@renault.com', 1, 'mail:christophe.rey@renault.com', 'Listing constructeur 16/09'),
  ('CONSTRUCTEUR', 'RENAULT', 'Pierre-Yves', 'BEYRON', 'pierre-yves.beyron@renault.com', 1, 'mail:pierre-yves.beyron@renault.com', 'Listing constructeur 16/09'),
  ('CONSTRUCTEUR', 'Bony Auto-mobile', 'Olivier', 'BOEUF', 'olivier.boeuf@bonyauto-mobile.com', 1, 'mail:olivier.boeuf@bonyauto-mobile.com', 'Listing constructeur 16/09')
on conflict (cle_source) do update set
  categorie = excluded.categorie, raison_sociale = excluded.raison_sociale,
  prenom = excluded.prenom, nom = excluded.nom, email = excluded.email,
  nb_badges = excluded.nb_badges, note = excluded.note,
  garage_id = null, stand_id = null, animation_id = null,
  actif = true;

-- ---------------------------------------------------------------------
-- 4. Le garage fantôme « RENAULT »
-- ---------------------------------------------------------------------
--  Fabriqué par l'import du 15 pour héberger les deux Renault ci-dessus.
--  Il n'a pas de compte client, pas de commune, aucune écriture au
--  journal et aucune case : personne ne s'en sert. On le désactive
--  plutôt que de le supprimer — la table garages porte le contrôle
--  d'accès, et une ligne inactive se relit là où une ligne effacée ne
--  se relit plus. Les quatre `not exists` sont des garde-fous : si ce
--  garage s'était mis à servir entre-temps, la mise à jour ne touche
--  rien plutôt que de couper l'accès à quelqu'un.
--
--  ⚠️ Ne pas confondre avec « Renault lezoux » (code 2869), qui est un
--  agent du réseau et pas le constructeur. Celui-là reste actif.
update public.garages
   set actif = false
 where nom = 'RENAULT'
   and compte is null
   and not exists (select 1 from public.journal j where j.garage_id = garages.id)
   and not exists (select 1 from public.grille  g where g.garage_id = garages.id)
   and not exists (select 1 from public.participants p
                    where p.garage_id = garages.id and p.actif);

commit;
