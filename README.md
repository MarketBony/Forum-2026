# Le Grand Bal des Fournisseurs — Forum Pièces Bony 2026

Portefeuille de points du Forum Pièces Bony, édition du **jeudi 17 septembre 2026**,
Grande Halle d'Auvergne (Cournon-d'Auvergne). Remplace les jetons de carton de
l'édition précédente.

**En ligne :** https://forum-2026.bonyauto-mobile.workers.dev/

> 📘 **Pour reprendre le projet, lire [`CONTEXTE.md`](CONTEXTE.md)** — l'histoire
> complète, les décisions, la méthode, les pièges et ce qui reste à faire. Ce
> README ne décrit que le fonctionnement courant.

## Cinq profils, une seule porte

| Profil | Entre avec | Peut faire |
|---|---|---|
| **Garage** | son code à 4 caractères | son solde, ses opérations, acheter une case |
| **Animateur** | le code de son animation | lancer une partie, noter le résultat |
| **Fournisseur** | le code de son stand | créditer une opération conclue |
| **Accueil** | le code hôtesse | chercher parmi les 1 457 invités, lire un code |
| **Équipe Bony** | le code direction | supervision, lots, corrections, projection |

Tout le monde tape son code **dans le même champ** : `api_ouvrir` reconnaît
elle-même de quelle porte il s'agit. Il n'y a pas d'écran « Équipe » à trouver.

## Architecture

```
Navigateur (modules ES natifs, aucune compilation)
   │  servi par Cloudflare Workers — ressources statiques, pas de code serveur
   ▼
Supabase ─┬─ PostgREST      appelle les fonctions api_* en RPC
          └─ PostgreSQL 17  RLS active partout, AUCUNE policy
```

L'application est **statique** : le navigateur parle directement aux fonctions
`api_*` de la base. RLS est active sur toutes les tables avec zéro policy, donc
les rôles publics ne peuvent rien lire ni écrire en direct — les 23 fonctions
`security definer` sont les seules portes d'entrée.

**Le site WordPress de Bony n'intervient pas** : multisite géré par MotorK (ni
plugin ni PHP) et un CSP qui interdit d'appeler Supabase depuis ses pages.
L'hébergement séparé apporte en prime le service worker, donc le vrai mode hors
ligne.

## Déploiement

Déployé en **Worker avec ressources statiques** : `wrangler.jsonc` ne déclare que
le dossier à servir, il n'y a aucun champ `main`. Chaque `git push` sur `main`
redéploie ; retour arrière en un clic depuis l'historique Cloudflare.

> ⚠️ **Après chaque push :** incrémenter `VERSION` dans `app/sw.js`, puis vérifier
> la version réellement servie. Les builds Cloudflare ont déjà échoué en silence
> deux fois.

```powershell
(New-Object System.Net.WebClient).DownloadString(
  'https://forum-2026.bonyauto-mobile.workers.dev/sw.js?t=' + (Get-Random)
) -match "const VERSION = '([^']+)'" ; $Matches[1]
```

## Base de données

Fichiers numérotés et rejouables. `.\scripts\push-sql.ps1 -File sql\01_schema.sql`

| Fichier | Contenu |
|---|---|
| `01_schema.sql` | tables, journal en ajout seul, verrouillage des accès |
| `02_fonctions.sql` | les fonctions `api_*` — seule porte d'entrée |
| `03_donnees.sql` | animations, barèmes, stands, grille de 100 cases |
| `04_complements.sql` | liste des garages, export CSV, suivi des lots |
| `05_inscription.sql` | *(historique — `api_garages_invites` a été supprimée en 07)* |
| `06_bingo.sql` | nature des cases, deux modes de révélation |
| `23_grand_tirage.sql` | les 15 gros lots collés aux tickets, la révélation du soir |
| `24_pins.sql` | les **31 PIN définitifs** du personnel, tirés d'une graine fixe |
| `25_sante_detail.sql` | la sonde de santé lue par la console de supervision |
| `26_quotas.sql` | **5 cases par garage**, quota de points par animation et par stand |
| `27_collaborateurs.sql` | les 55 collaborateurs Bony du listing du 16 et les 21 constructeurs |
| `28_reunion_agents.sql` | qui est **inscrit à la réunion d'agents** — ces badges sortent en tête |
| `07_acces.sql` | codes garage, profils, table des tentatives |
| `08_frein.sql` | un code refusé devient un résultat, pour que le frein compte |
| `09_accueil.sql` | le poste d'accueil : recherche et lecture des codes |
| `10_garages.sql` | les 1 457 invités — **généré**, ne pas éditer à la main |
| `11_recherche.sql` | `norm()` neutralise aussi la ponctuation |
| `12_requete.sql` | « st » et « ste » développés côté requête seulement |
| `13_porte.sql` | **la porte unique** et `verifier_portes()` |
| `14_sante.sql` | `api_sante()`, la sonde de vie |
| `15_fournisseurs.sql` | les 23 stands réels et le **barème par catégorie** |
| `16_animations.sql` | les 6 animations réelles et leurs PIN |
| `22_bareme_prestataire.sql` | le barème du prestataire, recalibré — **10 / 5 / 3 / 2 / 0** |
| `17_grille_200.sql` | la grille passe à **200 cases**, plafond par garage |
| `18_lots.sql` | les 100 lots réels et les 15 tickets d'or |
| `19_participants.sql` | **qui porte un badge** — table `participants`, vue `v_badges` |
| `20_inscrits.sql` | les garages et l'équipe Bony inscrits — **généré** |
| `21_personnel.sql` | exposants (5 par stand), animateurs (1 par jeu), 2 hôtesses |
| `99_remise_a_zero.sql` | purge après la répétition générale |

## ⚠️ Une seule URL

**`https://forum-2026.bonyauto-mobile.workers.dev/`**

Une `forum-2026.theo-labonne.workers.dev` a existé : le tout premier
déploiement, jamais mis à jour, dont le nom ne résout plus. Mais son **service
worker survit dans les navigateurs qui l'ont connue** et continue de servir la
coquille d'origine depuis le cache, avec les vraies données de Supabase
par-dessous — une application qui a l'air de marcher et qui a trois mois de
retard. Signature imparable : la supervision annonce « / 100 » au lieu de
« / 200 ».

Pour en sortir : effacer les données du site sur l'ancienne URL, désinstaller
l'application si elle a été ajoutée à l'écran d'accueil, repartir de la bonne.
**À vérifier sur tous les téléphones de l'équipe avant le Forum.**

## Vérifications — 114 contrôles

À rejouer après **toute** modification SQL. Ils tournent contre la vraie base.

```powershell
.\scripts\test-porte.ps1        # 53 : la porte, le frein, les 31 PIN, les collisions
.\scripts\test-invariants.ps1   # 32 : double crédit, quotas, solde négatif, plafonds, paliers
.\scripts\test-bingo.ps1        # 29 : les deux modes, la revelation, 200 cases, plafond
```

## Le jour J

```powershell
# 🔴 AVANT L'OUVERTURE — obligatoire. Efface achats, journal, soldes et
#    appareils ; PRÉSERVE la grille (100 lots, 15 tickets d'or).
.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql

.\scripts\diagnostic.ps1        # « est-ce la base, ou la couche devant ? »
.\scripts\exporter-journal.ps1  # journal, soldes et lots en CSV — toutes les heures
```

**La remise à zéro est la seule manœuvre qui rendrait le Forum injouable si on
l'oubliait** : la base porte les traces des tests et de la simulation, donc des
cases déjà prises et des soldes fictifs.

`diagnostic.ps1` interroge Postgres par l'API de management, qui **ne passe pas
par PostgREST** : il répond donc même quand l'application est à l'arrêt. C'est ce
qui permet de distinguer une base malade d'une couche API saturée — les deux
donnent le même symptôme à l'écran.

`exporter-journal.ps1` est la seule vraie protection des données de la soirée :
une sauvegarde quotidienne est prise la nuit et ne contient rien du 17.

## Dimensionnement

**Éprouvé le 15 septembre par une simulation de 400 garages jouée par l'API
réelle** — `scripts/simuler-forum.ps1` : arrivées, animations, stands, grille
jusqu'à épuisement, révélation du soir.

```
5 831 appels · 166 req/s de moyenne · 300 req/s de POINTE
0 échec dur · 0 écart de solde · 5 800 clés d'idempotence pour 5 800 lignes
200 cases parties · 15 tickets d'or décrochés
```

La charge attendue au Forum est de ~20 req/s : **quinze fois la marge**. Le banc
de rupture ne trouve aucun échec jusqu'à 800 requêtes simultanées. Le plan
gratuit n'est pas le facteur limitant.

> Ce banc part d'**une seule machine et d'une seule connexion** : il mesure
> Supabase, pas le wifi de la Grande Halle.

Mesures de fond, à 20 128 lignes de journal (7× une vraie soirée) :

| Appel | Coût en base | Fréquence |
|---|---|---|
| `api_etat` | 1,06 ms | 150 postes / 30 s |
| `api_supervision` | 17,54 ms | 1 tablette / 10 s |
| `api_accueil_chercher` | 1,30 ms | par frappe |

Rafale simultanée : **800 requêtes, 0 échec, 314 req/s**. Charge attendue au pic :
~20 req/s. Le pool PostgREST plafonne à **11 connexions** — c'est le vrai goulot,
et il ne figure sur aucun tableau de bord.

```powershell
.\scripts\mesurer-charge.ps1    # coût unitaire, taille du pool, rythme d'une soirée
.\scripts\trouver-plafond.ps1   # rafale montante jusqu'à la rupture
```

## Le bingo

| Nature | Nombre | Effet |
|---|---|---|
| `perdante` | 100 | rien |
| `lot` | 85 | un lot, code de retrait, remis au **stand des lots** pendant le Forum |
| `billet` | 15 | un **ticket d'or** : l'un des 15 gros lots, remis le soir sur scène |

**100 cases gagnantes sur 200 — une chance sur deux — et un lot par case
gagnante.** Les 15 tickets d'or valent chacun un gros lot : le tirage du soir ne
désigne pas qui gagne, il désigne **qui gagne quoi**. Personne ne repart bredouille
d'un ticket d'or.

Un garage ne peut pas prendre plus de **5 cases** (`config.cases_max_garage`,
passé de 3 à 5 le 15 septembre). Le plafond se lève en direct et **ne se baisse
jamais** — baisser pénaliserait ceux qui ont déjà acheté :

```sql
update config set valeur = '0' where cle = 'cases_max_garage';  -- 0 = illimité
```

Les numéros sont figés dans `sql/06_bingo.sql`, donc reproductibles et
vérifiables. Les libellés « Lot à définir » sont des marque-places à remplacer.

### Deux modes de révélation, un seul réglage

```sql
update config set valeur = 'immediate' where cle = 'revelation';  -- ou 'differee'
```

- **`immediate`** — le garage découvre à l'achat. C'est le ticket à gratter : il
  gagne, donc il retourne chercher des points, donc il achète. La grille se vide
  visiblement, ce qui crée l'urgence.
- **`differee`** — le garage achète à l'aveugle. L'équipe Bony ouvre tout le soir
  avec `api_reveler`, sur l'écran géant. Le suspense est collectif, mais la boucle
  « je gagne, je rejoue » disparaît et les garages qui partent avant le cocktail
  ne savent jamais.

**Le mode se bascule jusqu'à la dernière minute** : la mécanique d'achat est
identique, seul le moment où `grille.revele_le` est renseigné change.

### Le grand tirage — qui n'en est pas un

**Chaque ticket d'or est collé à son gros lot depuis `sql/23_grand_tirage.sql`.**
Le soir n'attribue rien : il ouvre les enveloppes. Le seul hasard a eu lieu dans
la journée, quand un garagiste a choisi sa case sans savoir ce qu'il y avait
dessous — un tirage truqué est un scandale, une révélation ne peut pas l'être.

Écran de projection accessible depuis l'espace Bony par le bouton **Grand tirage
au sort**, pensé pour un vidéoprojecteur en paysage et une lecture à dix mètres.

1. l'écran annonce combien de tickets ont été décrochés, et combien sont restés
   en rayon — ceux-là sont passés en silence
2. `api_tirage_lancer` bascule la soirée **en un seul appel** : il pose les codes
   de retrait et rend les 15 tickets d'un coup
3. ~80 secondes d'animation, entièrement dans le navigateur : le lot apparaît
   seul, le nom du garage tombe à 45 % du temps — ce silence est tout le
   spectacle — et les trois derniers temps durent le double
4. le récapitulatif reste à l'écran, et sert ensuite au stand des lots

**Rouvrir l'écran après coup n'affiche plus les gagnants** : c'est ce même écran
qu'on projette *avant* de lancer, et une répétition non remise à zéro donnait les
quinze noms à la salle. Un écran de garde le remplace, et le récapitulatif
s'ouvre sur le bouton **Afficher le récapitulatif**. Les cartes ne sont pas
masquées en CSS, elles ne sont pas construites.

Un clic sur la scène fait tomber le nom tout de suite, un second passe au lot
suivant : l'animateur presse le pas sans escamoter le nom. `api_tirage_reset`
rabaisse le drapeau pour la répétition, **sans changer les codes de retrait
déjà distribués**.

## Les badges

Générateur de badges A6 recto/verso, dans `badges/`. **Il s'ouvre par son icône
« Badges — Forum 2026 » sur le Bureau**, pas par une commande.

**Il ne fait que LIRE la base.** Décision du 14 septembre : plus aucun import de
fichier dans l'outil. La table `public.participants` dit qui porte un badge, la
vue `public.v_badges` y ajoute le code, et `exporter-badges.ps1` dépose le tout
dans `badges/participants.json`. Le générateur affiche, filtre et imprime.

### Pourquoi le croisement a été abandonné

La version précédente rapprochait les 1 457 invités et les fichiers
d'inscription. Le fichier consolidé du 14 septembre a montré que c'était
impossible : **l'identifiant d'invitation n'est pas une clé.** `BONY00250` a servi
à trois sociétés successives, et des salariés Bony se sont inscrits via le lien
d'un client. Rapprocher là-dessus attribuait le code d'un autre garage.

Le rapprochement se fait donc **une fois, à l'écriture** :

```powershell
.\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx"             # essai a blanc
.\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx" -Appliquer  # ecrit en base
```

Sans `-Appliquer`, **il n'écrit rien** : il lit, rapproche et rend un rapport. Il
rapproche d'abord sur la raison sociale, l'identifiant en second recours, et
**n'invente jamais** : les homonymes sont listés à part et pas importés. Une
société absente de la base reçoit un nouveau garage et un code généré — une
création, pas une supposition. `cle_source` (l'e-mail) rend l'import rejouable :
repousser le même listing met à jour au lieu de dupliquer.

Mesuré sur le listing consolidé du 15 septembre : 212 inscrits, **211 retenus**,
91 sociétés retrouvées par leur nom, 4 par l'identifiant, 46 créées, 3 homonymes
signalés pour arbitrage, **0 badge sans code utilisable**.

### Le personnel n'est pas nominatif

`sql/21_personnel.sql`, pas de fichier à importer : **5 badges interchangeables
par stand** (23 stands), **un animateur par jeu** (6), **deux hôtesses**. Les
libellés sont ceux de Bony — « TOTAL ELF », « AGENTS » — pas ceux de la base, qui
ne sert qu'au rattachement du PIN.

### État au 16 septembre 2026

| Catégorie | Lignes | Badges |
|---|---|---|
| Garage | 145 | 248 |
| Exposant | 23 | 115 |
| Équipe Bony | 119 | 124 |
| Constructeur | 21 | 21 |
| Animation | 6 | 6 |
| Hôtesse | 2 | 2 |
| **Total** | **316** | **516 badges · 258 feuilles A4** |

### Les 1 457 invités restent en base

Ils ne sont pas un carnet d'adresses : `garages.code` **est** le contrôle d'accès.
Un garagiste qui se présente sans s'être inscrit doit pouvoir entrer — l'hôtesse
le retrouve et lui lit son code (`sql/09_accueil.sql`), et lui remet un badge
vierge à remplir au marqueur. Le générateur, lui, ne voit que les inscrits.

### L'export PDF

Un bouton, des fichiers sur le disque : `Documents\Badges Forum 2026`. Pas de
boîte d'impression, pas de nom à taper. **Un PDF par catégorie**, et une case
« un PDF par lettre initiale » quand un fichier devient trop gros. Le navigateur
fabrique une page autonome, un **Chrome sans fenêtre** l'imprime
(`--headless --print-to-pdf`). Mesuré : 250 badges garage en **5 s** (125 pages),
115 exposants en 3 s, 69 équipe Bony en 3 s — et 1 457 badges en 17 s à l'époque
où ils y étaient tous. Vérifié **sur les fichiers**, pas à l'œil : toutes les
pages à **209,89 × 297,01 mm**, **cinq polices réellement incorporées**, et entre
40 et 56 dégradés axiaux par PDF.

### Le dessin du badge

Fond blanc, et la charte tient par **une guirlande de fanions**, un bandeau de
catégorie en dégradé, un filet orné d'un losange, le blason en dégradé or et
« Le Grand Bal des Fournisseurs » en **Petit Formal Script** — la note de grâce de la
charte, une par face. La commune a été retirée du badge le 14 septembre.

> **Tout ce qui est coloré est du SVG, jamais un fond CSS.** Un navigateur qui
> imprime peut décider de ne pas imprimer les `background` : le bandeau sortirait
> blanc sur blanc sans que rien ne prévienne. Un `<rect fill="url(#grad)">` est du
> contenu, il s'imprime comme une lettre. Vérifié sur les fichiers : chaque PDF
> contient entre 40 et 56 dégradés axiaux et **cinq polices incorporées**.
>
> Deux pièges SVG payés au passage. Le `viewBox` d'un dessin doit avoir **le même
> rapport que sa boîte CSS**, sinon `meet` le rétrécit au centre au lieu de
> l'étaler — la guirlande n'occupait que la moitié de la largeur. Et un dégradé
> en unités `objectBoundingBox` n'a **rien à peindre sur un trait horizontal**,
> dont la boîte englobante est de hauteur nulle : les filets étaient purement
> invisibles pendant que le losange, lui, s'affichait.

### La mécanique papier

**Une feuille A4 = deux badges.** Recto à gauche, verso à droite : on coupe la
feuille en deux dans la largeur, on plie chaque bande sur le trait du milieu en
rabattant le verso derrière le recto. Replier puis retourner la carte autour de
l'axe vertical sont deux rotations qui s'annulent : le verso se lit à l'endroit,
sans miroir. L'impression reste en **simple face**, donc aucun décalage de calage
recto/verso — invisible tant qu'on n'a pas imprimé, très visible sur un bandeau
de couleur.

Six catégories, une couleur chacune : Garage, Exposant, Animation, Hôtesse,
Équipe Bony, Constructeur. Elles se déclarent en une ligne en tête de
`badges/badges.js`, et doivent rester alignées sur la contrainte SQL
`participants_categorie_connue`.

```powershell
.\scripts\creer-raccourci.ps1   # une seule fois, ou apres avoir deplace le projet
.\scripts\badges.ps1 -Visible   # le meme lanceur, console ouverte, pour diagnostiquer
.\scripts\exporter-badges.ps1   # rafraichir participants.json sans ouvrir l'app
.\scripts\generer-polices.ps1   # seulement si l'on change de police
```

### Les fichiers du générateur

| Fichier | Rôle |
|---|---|
| `badges/index.html` · `badges.css` · `badges.js` | la page : liste, filtre, aperçu, export |
| `badges/polices.css` | les 6 polices encastrées en base64 — **généré** |
| `badges/polices/*.woff2` | les sources, instances **statiques** (pas variables) |
| `badges/vendor/qrcode.js` | encodeur QR MIT, version figée, relu avant intégration |
| `badges/icone.ico` · `icone.svg` | le blason Bony, l'icône du raccourci |
| `scripts/badges.ps1` | le lanceur : export, serveur, fenêtre, ménage |
| `scripts/badges-silencieux.vbs` | l'enveloppe wscript — aucune console ne clignote |
| `scripts/creer-raccourci.ps1` | pose l'icône sur le Bureau, **une fois** |
| `scripts/serveur-badges.ps1` | sert `badges/`, plus `marques.json`, `/exporter`, `/ouvrir` |
| `scripts/exporter-badges.ps1` | lit `v_badges` → `badges/participants.json` |
| `scripts/importer-inscriptions.ps1` | pousse un listing dans `participants` |
| `scripts/generer-polices.ps1` | refabrique `polices.css` depuis les `.woff2` |

Les fichiers de données (`participants.json`, `marques.json`, les traces de
lancement) sont **hors dépôt** : ils portent des codes d'accès, ou ne valent que
pour cette machine.

> 📘 **L'histoire complète est au §15 de [`CONTEXTE.md`](CONTEXTE.md)** : le
> virage du 14 septembre, le modèle de données, les mesures, et **neuf pièges
> payés** — tous invisibles à l'écran.

> ⚠️ **Les 31 PIN du personnel sont toujours ceux de démonstration**, et ils sont
> désormais imprimés sur 123 badges. Les figer avant la série ; les changer
> après jette ces badges. **Faits le 15 septembre, avant impression.**
> Reste une feuille d'essai au réglet avant la série : marges « Aucune », échelle
> 100 %, la carte pliée doit faire 105 × 148,5 mm.

## Les quotas par garage

Trois freins anti-abus, tous réglables en direct dans `config` — `sql/26_quotas.sql`.

| Frein | Valeur | Ce qu'il protège |
|---|---|---|
| Cases par garage | **5** | « il en faut pour tout le monde » |
| Points d'**une** animation | **4 × son meilleur palier** → 20 ou 40 pts | le garage qui camperait devant une borne |
| Points d'**un** stand | **3 × le plafond d'opération** → 60 pts | le fournisseur généreux avec un ami |

**Le refus tombe au LANCEMENT de la partie, pas au résultat.** `api_participation`
débite 2 points avant qu'on note le résultat : si le refus arrivait au résultat,
le garage aurait payé sa partie pour s'entendre dire qu'il n'a droit à rien. Le
résultat est quand même contrôlé, en ceinture, pour un résultat envoyé sans
participation.

**La dernière partie a le droit de dépasser** : un garage à 38/40 qui fait un
carreau touche ses 10 points et finit à 48. Le quota est un frein à la
répétition, pas une règle comptable.

**Le rôle `admin` n'y est pas soumis** : il corrige et compense, le bloquer lui
retirerait l'outil au moment où il en a besoin.

L'animateur et le fournisseur voient un **bandeau or persistant** — pas un toast
de quatre secondes qui disparaît pendant qu'ils relisent le nom du garage.

## La console de santé

En haut de l'écran de supervision, relevée toutes les dix secondes —
`sql/25_sante_detail.sql`.

| Mesure | D'où elle vient |
|---|---|
| **Réponse** | chronométrée **dans le navigateur**, aller-retour compris — le seul chiffre qui voit le wifi |
| **Pool PostgREST** | les connexions `authenticator` **qui travaillent**, sur 11 |
| **Verrous en attente** | doit rester à zéro |
| **Transactions bloquées** | doit rester à zéro |
| **Soldes ↔ journal** | `verifier_soldes()` — zéro, toujours |

La **santé globale** est la **pire** des cinq, jamais leur moyenne : une moyenne
noierait un écart de solde sous quatre barres vertes, or c'est exactement le seul
cas où il faut tout arrêter.

> ⚠️ Le tableau de bord Supabase, lui, **sera rouge vif le soir de l'événement
> alors que tout ira bien** : il compte chaque refus voulu comme une erreur. Après
> un passage des 114 tests il en affiche ~70 — les `CASE_DEJA_PRISE` du test de
> concurrence, les `permission denied` qui prouvent que la clé publique ne lit
> aucune table, les plafonds qui plafonnent. Se fier à la console, pas à lui.

## Les règles du jeu

Un bouton **Règles** dans la barre des cinq écrans de profil. Il ouvre un mode
d'emploi et rend la main exactement où on était.

**Une version par profil** : un garagiste n'a rien à faire des quotas de stand, un
représentant se moque de la grille à 200 cases. Quatre ou cinq temps chacun — un
gros chiffre, un picto au trait, un titre, une ligne.

**Les chiffres viennent de la base, pas du texte.** Coût d'une case, plafond de
cases, participation : tout est lu dans la réponse de l'API. Des règles qui
mentent sont pires que pas de règles.

## Les présentations

Deux diaporamas HTML, à la charte de l'application. `wrangler.jsonc` ne sert que
`app/` : **ils ne sont jamais déployés**.

| Fichier | Pour qui |
|---|---|
| `presentation/direction.html` | la direction Bony — 14 diapositives, les cinq interfaces en maquette |
| `presentation/agents.html` | la réunion d'agents du matin — 7 diapositives, quatre maquettes d'écran |

Celle des agents est **projetée dans une salle de réunion** : les échelles
typographiques sont montées d'un cran et les maquettes de téléphone passent de
238 à 320 px. Aucun code d'accès, et aucun numéro de case réel — la présentation
se donne le matin même, devant ceux qui vont jouer.

```powershell
.\scripts\serveur.ps1 -Dossier presentation -Port 8125
```

## Codes

Stockés dans `config`, `animations` et `stands`. **Les 31 PIN sont définitifs
depuis le 15 septembre** — `sql/24_pins.sql`. Les anciens (9137, 4200, 1001-1006,
2001-2023) étaient des codes de démonstration, et surtout ils étaient
**séquentiels** : qui lisait « 2001 » au dos d'un badge retourné ouvrait les
vingt-trois stands en comptant jusqu'à 2023. Les nouveaux sont tirés d'une graine
fixe et ne se déduisent pas les uns des autres.

| Usage | Combien | Où le lire |
|---|---|---|
| Supervision Bony | 1 | `sql/24_pins.sql` — **sur aucun badge** |
| Poste d'accueil | 1, partagé par les deux hôtesses | `sql/24_pins.sql` |
| Animations | 6 | idem, et au verso du badge de l'animateur |
| Stands | 23, chacun partagé par 5 badges | idem |

La liste lisible est dans `exports/Codes personnel Forum 2026.xlsx`, hors dépôt.

Tous les PIN contiennent un `0` ou un `1`. Ce n'est pas un hasard :
l'alphabet de génération des codes garage exclut `O`, `I`, `0` et `1`, donc un PIN
qui contient l'un de ces deux chiffres **ne peut pas** heurter un code garage. La
garantie est structurelle, et `test-porte.ps1` la vérifie au lieu de l'affirmer.

## Ce qui n'est pas dans ce dépôt

`.env.local` contient les accès Supabase et **n'est pas versionné**. Seule la clé
`publishable` apparaît dans `app/config.js` : elle est publique par nature et ne
donne accès à aucune table, uniquement aux fonctions vérifiées.

`exports/` est ignoré : les exports contiennent les codes d'accès des garages.
`badges/participants.json` l'est pour la même raison — c'est la liste des
516 badges avec leur code. `badges/marques.json` et les traces de lancement le
sont parce qu'elles ne valent que pour cette machine.

> Deux fichiers versionnés contiennent malgré tout des codes : `sql/10_garages.sql`
> (les 1 457 invités, décision d'origine) et `sql/20_inscrits.sql` (les inscrits,
> avec e-mails et téléphones). Cohérent avec le premier, mais le second ajoute des
> numéros de téléphone. Une ligne de `.gitignore` suffit à l'en sortir, au prix de
> la reproductibilité de l'import.

Le dépôt est **privé** et doit le rester.
