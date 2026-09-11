# Le Grand Bal des Points — Forum Pièces Bony 2026

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
| **Accueil** | le code hôtesse | chercher parmi les 1 407 invités, lire un code |
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
| `06_bingo.sql` | nature des cases, deux modes de révélation, grand tirage |
| `07_acces.sql` | codes garage, profils, table des tentatives |
| `08_frein.sql` | un code refusé devient un résultat, pour que le frein compte |
| `09_accueil.sql` | le poste d'accueil : recherche et lecture des codes |
| `10_garages.sql` | les 1 407 invités — **généré**, ne pas éditer à la main |
| `11_recherche.sql` | `norm()` neutralise aussi la ponctuation |
| `12_requete.sql` | « st » et « ste » développés côté requête seulement |
| `13_porte.sql` | **la porte unique** et `verifier_portes()` |
| `14_sante.sql` | `api_sante()`, la sonde de vie |
| `15_fournisseurs.sql` | les 23 stands réels et le **barème par catégorie** |
| `16_animations.sql` | les 6 animations réelles et leurs barèmes |
| `17_grille_200.sql` | la grille passe à **200 cases**, plafond par garage |
| `99_remise_a_zero.sql` | purge après la répétition générale |

## Vérifications — 104 contrôles

À rejouer après **toute** modification SQL. Ils tournent contre la vraie base.

```powershell
.\scripts\test-porte.ps1        # 53 : la porte, le frein, les 31 PIN, les collisions
.\scripts\test-invariants.ps1   # 27 : double crédit, solde négatif, plafonds, paliers
.\scripts\test-bingo.ps1        # 24 : les deux modes, le tirage, 200 cases, plafond
```

## Le jour J

```powershell
.\scripts\diagnostic.ps1        # « est-ce la base, ou la couche devant ? »
.\scripts\exporter-journal.ps1  # journal, soldes et lots en CSV — toutes les heures
```

`diagnostic.ps1` interroge Postgres par l'API de management, qui **ne passe pas
par PostgREST** : il répond donc même quand l'application est à l'arrêt. C'est ce
qui permet de distinguer une base malade d'une couche API saturée — les deux
donnent le même symptôme à l'écran.

`exporter-journal.ps1` est la seule vraie protection des données de la soirée :
une sauvegarde quotidienne est prise la nuit et ne contient rien du 17.

## Dimensionnement

Mesuré, pas supposé. À 20 128 lignes de journal (7× une vraie soirée) :

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

> ⚠️ **Composition en cours de refonte.** La grille est passée à **200 cases**
> (`17_grille_200.sql`) pour accueillir les **100 lots** du stock réel, mais seule
> la *structure* est faite : les cases 101 à 200 sont encore toutes `perdante`.
> La composition définitive attend l'arbitrage Bony sur le mode de remise des
> **15 gros lots** du soir. Le tableau ci-dessous décrit donc l'état transitoire,
> pas la cible.

| Nature | Nombre | Effet |
|---|---|---|
| `perdante` | 150 | rien |
| `lot` | 45 | un lot, code de retrait, remis au comptoir Bony |
| `billet` | 5 | une place au grand tirage du soir |

Un garage ne peut pas prendre plus de **3 cases** (`config.cases_max_garage`).
Le plafond se lève en direct et ne se baisse jamais — baisser pénaliserait ceux
qui ont déjà acheté :

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

### Le grand tirage

Écran de projection accessible depuis l'espace Bony, pensé pour un vidéoprojecteur
en paysage et une lecture à dix mètres.

1. `api_tirage_ouvrir` photographie les billets vendus et révélés — la course est figée
2. `api_tirage_manche` élimine environ la moitié des concurrents, à chaque appui
3. quand il n'en reste qu'un, il est déclaré gagnant

Chaque manche est enregistrée dans la table `tirage` : le tirage peut être rejoué
et justifié, ce qui compte quand un lot est en jeu. `api_tirage_reset` efface tout.

## Codes

Stockés dans `config`, `animations` et `stands`. **Ce sont des codes de
démonstration : à changer avant l'événement**, puis relancer `verifier_portes()`
pour s'assurer qu'aucun ne heurte un code garage.

| Usage | Code |
|---|---|
| Supervision Bony | `9137` |
| Poste d'accueil | `4200` |
| Animations | `1001` à `1006` |
| Stands | `2001` à `2023` |

Tous les PIN contiennent un `0` ou un `1`. Ce n'est pas un hasard :
l'alphabet de génération des codes garage exclut `O`, `I`, `0` et `1`, donc un PIN
qui contient l'un de ces deux chiffres **ne peut pas** heurter un code garage. La
garantie est structurelle, et `test-porte.ps1` la vérifie au lieu de l'affirmer.

## Ce qui n'est pas dans ce dépôt

`.env.local` contient les accès Supabase et **n'est pas versionné**. Seule la clé
`publishable` apparaît dans `app/config.js` : elle est publique par nature et ne
donne accès à aucune table, uniquement aux fonctions vérifiées.

`exports/` est ignoré : les exports contiennent les codes d'accès des garages.

Le dépôt est **privé** et doit le rester.
