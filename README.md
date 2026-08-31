# Le Grand Bal des Points — Forum Pièces Bony 2026

Portefeuille de points du Forum Pièces Bony, édition du **jeudi 17 septembre 2026**,
Grande Halle d'Auvergne (Cournon-d'Auvergne).

Remplace les jetons de carton de l'édition précédente. Quatre profils :
garage, animateur, fournisseur, équipe Bony.

## Architecture

```
QR code  ->  bonyauto-mobile.com/forum-pieces-2026   (page Elementor, redirection)
         ->  <projet>.pages.dev                      (cette application, PWA)
         ->  Supabase                                (Postgres, plan gratuit)
```

L'application est **statique** : des modules JavaScript natifs, aucune étape de
compilation. Cloudflare Pages sert les fichiers, le navigateur parle directement
aux fonctions `api_*` de la base.

Le site WordPress de Bony est un multisite géré par MotorK : ni plugin, ni PHP, et
un CSP qui interdit d'appeler Supabase depuis ses pages. D'où l'hébergement séparé,
qui apporte en prime le service worker, donc le vrai mode hors ligne.

## Déploiement sur Cloudflare

Le projet est déployé en **Worker avec ressources statiques** (le flux actuel de
Cloudflare pour les sites statiques ; Pages reste possible mais n'évolue plus).
Il n'y a aucun code serveur : `wrangler.jsonc` ne déclare que le dossier à servir.

1. Cloudflare -> Create app -> Import a repository -> `MarketBony/Forum-2026`
2. **Build command** : *laisser vide*
3. **Deploy command** : `npx wrangler deploy` (valeur préremplie, à garder)
4. **Builds for non-production branches** : coché, pour obtenir des URL de
   prévisualisation sur les autres branches
5. **Protect with Cloudflare Access** : NON sur la production — 400 participants
   scannant un QR code ne peuvent pas franchir un portail d'authentification

Chaque `git push` sur `main` redéploie. Retour arrière en un clic depuis l'historique
des déploiements.

## Base de données

Les fichiers `sql/` sont numérotés et rejouables. Pour les envoyer :

```
.\scripts\push-sql.ps1 -File sql\01_schema.sql
```

| Fichier | Contenu |
|---|---|
| `01_schema.sql` | tables, contraintes, journal en ajout seul, verrouillage des accès |
| `02_fonctions.sql` | les fonctions `api_*` — seule porte d'entrée des clients |
| `03_donnees.sql` | animations, barèmes, stands, grille de 100 cases, garages |
| `04_complements.sql` | liste des garages (cache hors ligne), export CSV, suivi des lots |
| `05_inscription.sql` | recherche d'inscription, protégée par le code du QR code |
| `99_remise_a_zero.sql` | purge après la répétition générale |

## Vérifications

```
.\scripts\test-invariants.ps1
.\scripts\test-charge.ps1
```

Le premier prouve que la base refuse le double crédit, le double tirage sur une
même case, le solde négatif et les dépassements de plafond. Le second mesure la
tenue en charge.

## Codes

Stockés dans la table `config` et dans les tables `animations` / `stands`.
**À changer avant l'événement.**

| Usage | Code |
|---|---|
| Espace Bony | `9137` |
| Animations | `1001` à `1004` |
| Stands | `2001` à `2005` |
| Code d'événement (dans le QR) | `bal2026` |

Le QR code doit pointer vers `…/?e=bal2026`.

## Ce qui n'est pas dans ce dépôt

`.env.local` contient les accès Supabase et **n'est pas versionné**. Seule la clé
`publishable` apparaît dans `app/config.js` : elle est publique par nature et ne
donne accès à aucune table, uniquement aux fonctions vérifiées.
