# Le Grand Bal des Points — dossier de reprise

> **À lire en entier avant de toucher au code.** Ce document est écrit pour une
> session de travail qui ne connaît rien au projet. Il dit ce qu'est
> l'application, pourquoi elle est construite ainsi, ce qui a été fait, ce qui
> reste, les pièges rencontrés, et la méthode de travail attendue.
>
> Dernière mise à jour : **11 septembre 2026**. Événement : **jeudi 17 septembre 2026**.
> Il reste **six jours**.

---

## 1. En une page

| | |
|---|---|
| **Quoi** | Un portefeuille de points virtuel pour un salon professionnel B2B |
| **Pour qui** | Bony Automobile, Clermont-Ferrand — distributeur de pièces automobiles |
| **Quand** | Jeudi 17 septembre 2026, toute la journée puis cocktail dînatoire |
| **Où** | Grande Halle d'Auvergne, Cournon-d'Auvergne |
| **Public** | 1 407 garages invités, **~150 attendus**, ~20 stands fournisseurs |
| **Remplace** | Les jetons en carton de l'édition précédente |
| **En ligne** | https://forum-2026.bonyauto-mobile.workers.dev/ |
| **Dépôt** | `MarketBony/Forum-2026` — **privé**, doit le rester |
| **Coût** | 0 € (Cloudflare Workers gratuit + Supabase gratuit) |
| **État** | Fonctionnel de bout en bout, 104 tests verts, en attente de décisions |

L'interlocuteur est **Bastien Fuziol** (`bastien.fuziol@bonyauto-mobile.com`),
au service marketing. Technique sans être développeur : il comprend
l'architecture, lit du SQL, mais n'écrit pas le code. Il tutoie, va droit au but,
et **demande des preuves chiffrées plutôt que des affirmations**. Quand il dit
qu'une chose ne va pas sur le terrain, c'est son terrain : il a raison.

---

## 2. Le principe du jeu

Un garagiste arrive au Forum. Il entre un code à quatre caractères dans son
téléphone, et son portefeuille s'ouvre — pas de compte à créer, pas de mot de
passe. Il gagne des points en jouant aux animations, il en gagne en concluant des
opérations sur les stands fournisseurs, et il les dépense sur une **grille de cent
cases** où se cachent les lots. Le soir, au cocktail, les détenteurs de « billets »
décrochés dans la grille jouent un grand tirage sur l'écran géant.

```
        ┌──────────────┐
        │  ACCUEIL     │  l'hôtesse retrouve le garage et lui donne son code
        └──────┬───────┘
               ▼
        ┌──────────────┐  +10 points de bienvenue
        │  LE GARAGE   │◄──────────────┬──────────────┐
        │  entre son   │               │              │
        │  code        │        ┌──────┴─────┐  ┌─────┴──────┐
        └──────┬───────┘        │ ANIMATEUR  │  │FOURNISSEUR │
               │                │ 0 à 20 pts │  │ 5 à 50 pts │
               ▼                └────────────┘  └────────────┘
        ┌──────────────┐
        │ LA GRILLE    │  20 pts la case · 50 perdantes / 45 lots / 5 billets
        └──────┬───────┘
               ▼
        ┌──────────────┐
        │ GRAND TIRAGE │  écran géant, le soir, entre porteurs de billets
        └──────────────┘
```

### Les cinq profils

| Profil | Entre avec | Peut faire |
|---|---|---|
| **Garage** | son code à 4 caractères | voir son solde et ses opérations, acheter une case |
| **Animateur** | le code de son animation | chercher un garage, lancer une partie, noter le résultat |
| **Fournisseur** | le code de son stand | chercher un garage, créditer une opération |
| **Accueil** | le code hôtesse | chercher parmi les 1 407 invités, **lire un code**, voir le compteur d'arrivées |
| **Équipe Bony** | le code direction | supervision, remise des lots, corrections, écran de projection |

L'accueil ne voit **ni les soldes ni le journal** : c'est du personnel d'extra,
deux pouvoirs et pas un de plus.

---

## 3. L'architecture, et pourquoi elle est ainsi

```
Navigateur (modules ES natifs, aucune compilation)
   │  servi par Cloudflare Workers — ressources statiques, pas de code serveur
   │
   │  HTTPS direct, il n'y a AUCUNE API applicative
   ▼
Supabase ─┬─ PostgREST      appelle les fonctions api_* en RPC
          └─ PostgreSQL 17  RLS active PARTOUT, AUCUNE policy
```

### Les trois contraintes qui ont tout décidé

**1. Le site WordPress de Bony est inutilisable.** C'est un multisite géré par le
prestataire MotorK : ni plugin, ni PHP, ni accès au DNS. Bastien peut seulement
créer des pages Elementor ou injecter du HTML/CSS. Pire, le site impose un CSP
— une unique directive `default-src` listant 96 hôtes, en mode `enforce` — qui
**interdit à toute page du site d'appeler Supabase**. Une page tremplin sur
`bonyauto-mobile.com` avait été envisagée puis écartée : tout passe par
Cloudflare. *Décision de l'utilisateur, verbatim : « on oublie elementor et le
site bony mec, tout passe par cloudflare désormais ».*

**2. Le budget est strictement de 0 €.** Supabase Pro a été explicitement refusé
au début du projet (« j'ai pas un rond à dépenser avec la boite là »). Tout est
dimensionné pour l'offre gratuite, et la viabilité a été **mesurée, pas
affirmée** — voir §8.

**3. Aucun nom de domaine ne sera acheté.** L'URL `*.workers.dev` porte déjà le
nom de l'entreprise, ce qui a suffi.

### Ce qui découle de l'absence de serveur applicatif

- **Les fonctions `security definer` sont la seule barrière.** RLS est active sur
  toutes les tables avec **zéro policy** : les rôles publics ne peuvent donc rien
  lire ni écrire en direct. Les 23 fonctions `api_*` sont les seules portes.
- **La clé publiée dans le navigateur ne donne accès à aucune table.** C'est la
  clé `publishable`, publique par nature, et elle ne permet que d'appeler les
  fonctions vérifiées.
- **Aucun endroit où amortir ou mettre en cache** côté serveur. Le seul
  régulateur possible est dans le navigateur.

---

## 4. Le modèle de données

Huit tables. Le fichier `sql/01_schema.sql` fait foi.

| Table | Rôle |
|---|---|
| `config` | réglages clé/valeur — codes, coûts, plafonds, mode de révélation |
| `garages` | les 1 407 invités : compte Bony, nom, commune, CP, e-mail, **code**, solde |
| `appareils` | un téléphone = un jeton ; porte le rôle et le rattachement |
| `animations` | les 4 jeux, leur mise et leur code |
| `bareme` | les résultats possibles de chaque jeu et leurs points |
| `stands` | les stands fournisseurs, leur code et leurs plafonds |
| `journal` | **le registre en ajout seul** — chaque point, daté et signé |
| `grille` | les 100 cases : nature, lot, code de retrait, qui l'a prise |
| `tentatives` | les codes erronés, pour le frein anti-devinette |
| `tirage` | les manches du grand tirage, pour qu'il soit rejouable |

### Le journal est en ajout seul, et c'est structurel

Un trigger interdit physiquement toute modification ou suppression :

```sql
raise exception
  'Le journal est en ajout seul : une erreur se corrige par une écriture
   inverse, pas par une modification (tentative de % sur la ligne %)',
  tg_op, coalesce(old.id, 0);
```

`garages.solde` est un **cache** mis à jour dans la même transaction que
l'insertion au journal. `verifier_soldes()` compare en permanence les deux et
rend les écarts. **L'invariant : zéro écart, toujours.** La supervision l'affiche
et le signale en rouge s'il devient non nul.

> Conséquence pratique : **on ne peut pas supprimer un appareil qui a écrit**
> (clé étrangère depuis le journal), ni le détacher de son garage (contrainte
> `appareils_garage_coherent`). Une place d'appareil prise ne se rend pas. C'est
> pour cela que `appareils_max` est passé à **6**.

### L'idempotence, partout

Toute écriture porte une `cle_idem` unique, générée par le client et **jamais
régénérée entre deux tentatives**. `on conflict (cle_idem) do nothing` : un double
appui, un réseau qui bégaye, une file d'attente qui rejoue — rien ne crédite deux
fois. C'est ce qui rend le mode hors ligne sûr.

### La réservation atomique d'une case

`api_jouer_case` verrouille la ligne (`select ... for update`) avant de
l'attribuer. Vérifié : huit appareils visant la même case au même instant, **un
seul gagnant, les sept autres non débités**.

---

## 5. L'accès : une seule porte

C'est le dernier gros chantier terminé (commit `405e7b5`).

**Un seul champ pour les cinq profils.** `api_ouvrir(p_jeton, p_code)` reconnaît
elle-même de quelle porte il s'agit : personnel d'abord (ensemble fermé d'une
dizaine de codes), garages ensuite.

### Trois pièges désamorcés, à ne pas réintroduire

**1. L'alphabet des codes garage exclut `O`, `I`, `0` et `1`** pour éviter les
confusions à la lecture. Mais les PIN du personnel sont pleins de 0 et de 1
(`1001`, `4200`). La normalisation de saisie garde donc **`A-Z0-9`**, et
l'alphabet restreint ne sert **qu'à la génération** des codes. Filtrer à la
saisie viderait « 1001 » sous les doigts de l'animateur.

**2. Un code refusé est un RÉSULTAT, pas une exception.** Une exception annulerait
la transaction — donc l'enregistrement de la tentative — et le frein anti-devinette
ne compterait jamais. La fonction renvoie `{erreur, detail, restantes}` en HTTP 200.
*Ce bug a réellement existé et a été corrigé dans `sql/08_frein.sql`.*

**3. Aucun code garage ne doit valoir un PIN du personnel**, sinon l'un des deux
est bloqué. `verifier_portes()` le contrôle — **0 collision** sur 1 407 codes
garage et 11 codes personnel. **À relancer après tout changement de PIN.**

### Les codes déterministes

`scripts/importer-garages.ps1` dérive chaque code du numéro de compte Bony :

```powershell
$ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
$SEL = 'grand-bal-2026'
# md5($SEL|$compte|$variante) -> 4 caractères
```

Réexécuter l'import **ne change jamais** un code déjà parti dans un emailing, et
`on conflict (compte) do update` ne touche volontairement pas la colonne `code`.

> ⚠️ **Six vrais garages portent aujourd'hui un code de test posé à la main** —
> `GRND`, `BNY2`, `TEST`, `BAL2`, `FRUM`, `JEUX`. Leurs codes générés sont
> respectivement `FCT9`, `C4MB`, `R5MB`, `A9AJ`, `6XQ3`, `UREL`. Voir §11.

---

## 6. L'application

Vanilla, modules ES natifs, **aucune étape de compilation** — c'est délibéré : pas
de Node, pas de `npm install`, un `git push` suffit. 138 Ko en 10 fichiers.

| Fichier | Rôle |
|---|---|
| `app/index.html` | la coquille, 33 lignes |
| `app/config.js` | URL, clé publique, rythmes de sondage, libellés de l'événement |
| `app/js/api.js` | les appels RPC, la file d'attente hors ligne, le cache des garages |
| `app/js/app.js` | ~1 130 lignes, toutes les vues et toutes les actions |
| `app/js/verre.js` | le verre liquide (filtre SVG de réfraction) |
| `app/app.css` | la charte complète |
| `app/sw.js` | service worker, coquille hors ligne — **`VERSION` à incrémenter à chaque déploiement** |

### Le mode hors ligne

Dans une halle, le réseau tombe. Les **écritures** partent dans une file
persistée en `localStorage` et repartent seules au retour du signal. Les
**lectures** ne sont jamais mises en cache : un solde périmé serait pire qu'une
absence de solde. Les erreurs 5xx et 429 sont traitées comme du réseau (on
réessaie) ; les 4xx sont des refus métier définitifs et ne sont **jamais** mis en
file.

> ⚠️ Le mode hors ligne n'a **jamais été éprouvé sur un vrai téléphone en mode
> avion**. À faire à la répétition. C'est le seul point du produit dont je ne peux
> pas garantir le comportement réel.

### La charte

Une guinguette la nuit. Fond violet nuit, or, terracotta. Trois polices aux rôles
stricts : **Playfair Display** (le solde et un titre par écran), **Petit Formal
Script** (une note manuscrite par écran), **Hanken Grotesk** (tout le reste). Les
surfaces ne sont pas encadrées : elles se détachent par un reflet en haut et une
ombre en bas.

Par-dessus, un **verre liquide** : carte de déplacement générée en canvas depuis
une SDF de rectangle arrondi, chaîne de filtres SVG avec trois `feDisplacementMap`
(un par canal RVB, échelles légèrement divergentes) mélangés en `screen` pour
l'aberration chromatique, plus deux anneaux spéculaires.

> **PIÈGE MAJEUR, déjà tombé deux fois.** `feDisplacementMap` déforme le **contenu**
> de l'élément filtré, pas seulement ce qu'on voit à travers. Appliquer le filtre
> directement sur un conteneur tord son propre texte. La solution en place : une
> **vitre** — une couche vide en position absolue derrière le contenu, qui porte
> seule le flou et le filtre. Lire le commentaire en tête de `app/js/verre.js`
> avant d'y toucher.

Le verre est désactivé sur Firefox, sous `prefers-reduced-motion`, et sur les
machines à ≤ 2 cœurs ou ≤ 2 Go.

---

## 7. Ce qui a été fait, dans l'ordre

| Commit | Chantier |
|---|---|
| `2d8781c` | base, API, application — le socle |
| `132b1ae` | déploiement Cloudflare en Workers + ressources statiques |
| `59019af` | refonte graphique : la lumière remplace les cadres |
| `4972220` | le bingo : 50 perdantes / 45 lots / 5 billets, et le grand tirage |
| `e258a22` | entrée par code garage — la clé d'entrée sert aussi de clé de retour |
| `1746638` → `cb36a09` | verre liquide (4 commits, voir §11) |
| `1aa2186` | le poste d'accueil sur tablette |
| `ee3592e` | dictionnaire d'accents restreint, deux défauts de recherche |
| `04d6339` | communes reconstituées depuis le code postal, et unifiées |
| `405e7b5` | **une seule porte** : le même champ pour les cinq profils |
| `83856e4` | présentation à la direction, en HTML |
| `ebe8b34` | dimensionnement mesuré contre un rapport d'incident |

### Le nettoyage des données

L'export Sarbacane fourni était sale : raisons sociales tronquées à 30
caractères, communes tronquées à 20, accents perdus, « GGE » pour « Garage ».
Trois tables curatives dans `scripts/importer-garages.ps1` :

- `$EXPRESSIONS` — expressions entières (« Vic sur Cere » → « Vic-sur-Cère ») ;
- `$ACCENTS` — mots français dont l'orthographe ne fait **aucun** doute ;
- `$COMMUNES` — 72 entrées indexées sur **`CP|libellé brut`**, pour qu'une
  correction ne puisse jamais s'appliquer par ricochet ;
- `$UNIFIEES` — fait converger les orthographes multiples d'une même commune.

Résultat : **576 communes distinctes, aucune en double orthographe, 1 407 codes
intacts.**

**Les 20 raisons sociales tronquées ont été laissées telles quelles.** Le nom
qu'un garagiste s'est choisi ne s'invente pas. Une commune se reconstitue depuis
un code postal — c'est de la donnée publique ; un nom d'entreprise, non.
*Distinction validée par l'utilisateur.*

`SAINT SULPICE L APOI` au CP 15310 n'a pas pu être identifié avec certitude et a
été laissé intact plutôt que deviné.

---

## 8. Le dimensionnement — la question ouverte

C'est le sujet en cours au moment de ce passage de relais, et il n'est **pas
clos**.

### Le déclencheur

L'utilisateur a transmis un rapport d'incident sur **GRID**, un autre projet à
l'architecture identique (front statique, pas d'API, navigateur → PostgREST, RLS)
qui est tombé en pleine session avec ~25 postes connectés. Sa crainte : si
Supabase n'a pas tenu 25 utilisateurs là-bas, il ne tiendra pas 50 ici.

### Ce que GRID avait, et que nous n'avons pas

| GRID | Nous | Vérification |
|---|---|---|
| Trigger `realtime.send()`, un message par écriture à **tous** les postes | **aucune diffusion** | `grep -r "realtime\|websocket\|subscribe" app/js sql` = vide |
| 16 requêtes par événement reçu, **par poste** | 1 RPC composite par écran | `api_etat` fait tout en un appel |
| Coût = écrivains × spectateurs (**quadratique**) | coût = somme des postes (**linéaire**) | chaque poste ne lit que son solde |
| 15 policies RLS évaluées **par ligne** | RLS active, **aucune policy** | une vérification par appel, pas par ligne |
| Fonction d'autorisation à nu dans une vue en `CROSS JOIN` | `_appareil` = une lecture sur index unique | — |

**Leur cause était le comportement du front, pas son hébergement.** Cloudflare
n'est impliqué nulle part dans leur rapport. Ce qui a cassé, c'est le pool de
connexions de PostgREST, côté Supabase. Ce qu'ils ont vu — « la page ne charge
plus » — était le symptôme, à un troisième endroit encore.

### Ce que nous partageons : le pool de 11

Mesuré sur notre base : **10 connexions de travail + 1 d'écoute**. Identique à
GRID. C'est un plafond dur, qui ne figure sur aucun tableau de bord.

### Les mesures, à 20 128 lignes de journal (7× une vraie soirée)

| Appel | Coût en base | Fréquence réelle |
|---|---|---|
| `api_etat` | **1,06 ms** | 150 postes toutes les 30 s |
| `api_supervision` | 17,54 ms | 1 tablette toutes les 10 s |
| `api_accueil_chercher` | 1,30 ms | à chaque frappe d'hôtesse |
| `verifier_soldes()` | 11,73 ms | inclus dans la supervision |

Rafale simultanée montante, jusqu'à la rupture :

| Simultanées | 25 | 50 | 100 | 200 | 400 | 800 |
|---|---|---|---|---|---|---|
| Échecs | 0 | 0 | 0 | 0 | 0 | **0** |
| Débit | 23/s | 56/s | 92/s | 170/s | 211/s | **314/s** |

Charge attendue au pic : **~20 req/s**. Aucune attente de verrou, aucune connexion
bloquée en transaction, authentification à 418 ms juste après l'effort.

### Pourquoi GRID est tombé et pas nous, en une ligne

Ce n'est pas le nombre d'utilisateurs, c'est **requêtes × coût unitaire**, et
surtout la **rafale**. GRID : 25 postes × 16 requêtes à 300–540 ms chacune,
déclenchées **à la même milliseconde** par le même message diffusé. Nous : chaque
poste lit son solde, seul, une requête à 1 ms, sans synchronisation entre postes.

### La réserve de l'utilisateur, à prendre au sérieux

> « ouais enfin mec y'a la théorie et la réalité »

Elle est en partie fondée et il faut le dire à la session suivante :

- les 800 requêtes ont été tirées **depuis une seule machine**, pas depuis 150
  téléphones différents sur le wifi d'une halle ;
- **le wifi de la Grande Halle n'a jamais été testé** et reste, à mon avis, le
  risque le plus probable de la soirée — bien avant Supabase ;
- rien ne remplace une répétition sur place.

### Décision sur le plan payant

L'utilisateur a dit qu'il paierait 10–20 € s'il le faut. Ma recommandation, à
confirmer avec lui : **Supabase Pro (~25 $/mois), pris vers le 14, coupé le 18**
— et **pas** Cloudflare, qui n'a rien à vendre ici (ressources statiques pures,
~4 000 requêtes sur la soirée, quota gratuit de 100 000/jour).

Les trois raisons de payer **ne sont pas la charge** :
1. un projet gratuit **se met en veille après 7 jours sans activité** ;
2. `"backups": []` — il n'y a **aucune sauvegarde** aujourd'hui ;
3. aucun canal de support en cas d'incident Supabase le soir même.

> ⚠️ **Une sauvegarde quotidienne est prise la nuit : elle ne contiendra rien de
> la soirée du 17.** Ce qui protège vraiment les données du jour J, c'est
> `scripts/exporter-journal.ps1`, à lancer toutes les heures pendant l'événement.

---

## 9. La méthode de travail attendue

C'est ce qui a fait tenir le projet. À reprendre telle quelle.

**Mesurer, jamais affirmer.** Chaque affirmation de performance, de capacité ou de
correction dans ce projet est adossée à un chiffre obtenu sur la vraie base. Quand
l'utilisateur demande « es-tu sûr », la réponse est un tableau de mesures, pas un
raisonnement.

**Vérifier le déploiement après chaque push.** Les builds Cloudflare ont
**silencieusement échoué deux fois** sur une douzaine de poussées. L'utilisateur a
perdu une session entière à croire que le correctif ne marchait pas alors qu'il
n'était jamais parti. Depuis, la règle est : après chaque `git push`, incrémenter
`VERSION` dans `app/sw.js` et vérifier la version réellement servie :

```powershell
(New-Object System.Net.WebClient).DownloadString(
  'https://forum-2026.bonyauto-mobile.workers.dev/sw.js?t=' + (Get-Random)
) -match "const VERSION = '([^']+)'" ; $Matches[1]
```

**Les tests tournent contre la vraie base.** Pas de mock. 104 contrôles :
`test-porte.ps1` (53), `test-invariants.ps1` (27), `test-bingo.ps1` (24). À
rejouer après **toute** modification SQL.

**Le terrain de l'utilisateur l'emporte.** Exemple : j'avais proposé de passer la
grille à 250 cases sur un raisonnement de « 2,5 cases par garage ». Réponse :
« nan l'année dernière on avait pile poil le bon nombre de cases et de lots mec ».
Sa donnée de terrain était juste, mon calcul était une spéculation. **100 cases.**

**Ne pas sur-concevoir.** Une proposition d'appairage hôtesse/téléphone a été
retoquée d'un « c'est un poil trop complexe pour les garagistes… on héberge pas
l'euromillion non plus mec ». La contrainte tient en une phrase : **un garagiste,
un verre à la main, dans le bruit, doit y arriver du premier coup.**

**Écrire les commentaires en français, et expliquer le POURQUOI.** Le code est
commenté pour que Bastien puisse le relire seul l'an prochain. Les commentaires
qui expliquent un piège valent dix commentaires qui décrivent une ligne.

**Signaler ce qui n'a pas été vérifié.** Le mode hors ligne réel, le wifi de la
halle, le rendu sur téléphone étroit de la présentation : tout ce qui n'a pas été
éprouvé est signalé comme tel, dans les réponses comme dans ce document.

---

## 10. Les pièges déjà rencontrés

À lire avant de perdre du temps à les redécouvrir.

### PowerShell 5.1

- **Les scripts `.ps1` sans BOM UTF-8 sont lus en CP1252.** Les comparaisons
  accentuées cassent silencieusement. **Tous les scripts du projet ont un BOM**,
  le conserver.
- **`Invoke-WebRequest` ne rend pas le corps des réponses 4xx.** Toutes les
  batteries de tests utilisent `System.Net.Http.HttpClient` pour cette raison.
- **`$args` est une variable automatique** : la nommer en paramètre de fonction
  fait partir un corps vide, et PostgREST répond « function without parameters
  not found » — une erreur qui ne ressemble pas du tout à sa cause.
- **`Where-Object` sur un seul élément rend un scalaire**, donc `.Count` vaut
  `$null`. Envelopper dans `@()`.
- **`ServicePointManager.DefaultConnectionLimit` vaut 2 par défaut** : sans le
  relever, un test de charge mesure le client et non le serveur.
- **Pas de `&&` ni de `||`** en 5.1. Utiliser `; if ($?) { }`.

### Supabase

- **`/rest/v1/` répond 401 avec la clé publique.** C'est normal : la description
  d'API est réservée à `service_role`. Ce n'est **pas** une panne. Une vraie sonde
  de vie existe désormais : `api_sante()`.
- **L'API de management n'accepte qu'un PAT `sbp_`**, jamais une clé de projet.
- **`pg_stat_statements` porte sur une fenêtre de plusieurs jours**, pas sur
  l'heure écoulée — vérifier `stats_reset` avant de conclure. Et les requêtes qui
  n'obtiennent jamais de connexion n'y figurent **pas** : une saturation de pool y
  est structurellement invisible.
- **Realtime est `UNHEALTHY` sur notre projet.** On ne s'en sert pas, aucun impact.
  Illustration du principe : le tableau de bord désigne le symptôme, jamais la
  cause.

### L'application

- **`feDisplacementMap` déforme le contenu de l'élément filtré** — voir §6.
- **Le tableau de bord admin doit se recharger en y revenant**, sinon un lot que
  Bony vient de remettre reste affiché comme « à remettre » jusqu'au sondage
  suivant, et l'équipe doute de l'outil.
- **Une grille CSS à deux colonnes avec trois enfants** place le troisième en
  colonne 1. Déclarer `grid-column` explicitement.

### La recherche

- `norm()` neutralise accents, casse **et ponctuation**. Sans ce dernier point,
  « saint bonnet » ne trouvait pas « Saint-Bonnet ».
- La colonne générée `recherche` doit être **supprimée et recréée** pour être
  recalculée : remplacer la fonction ne suffit pas.
- `norm_requete()` développe `ste` **avant** `st` (sinon « ste » devient
  « saint + e »), et **uniquement du côté de la requête**, jamais des données.

---

## 11. Ce qui reste — état au 11 septembre 2026

### Décisions attendues de Bony

> **Mise à jour du 11 septembre 2026, deuxième passe.** Bony a fourni le fichier
> fournisseurs/barèmes et l'état de stock. Les lignes 1, 3 et 5 ci-dessous sont
> désormais réglées ; ce qui reste est listé en dessous.

| # | Sujet | État |
|---|---|---|
| 1 | ~~Les 32 lots à nommer~~ | ✅ **100 lots réels**, issus de `stock forum.xlsx` |
| 2 | **Mode de révélation** | `immediate` aujourd'hui ; `differee` possible en une ligne |
| 3 | ~~Nombre de billets~~ | ✅ **30 tickets d'or** sur 200 cases, pour 15 gros lots |
| 4 | **Codes définitifs du personnel** | ceux en place sont des codes de démonstration — 31 PIN |
| 5 | ~~Barèmes et plafonds~~ | ✅ barème fournisseur **par catégorie**, 6 animations en 20/10/5/0 |
| 6 | **Répétition sur place** | non planifiée — **c'est le point le plus important** |

### Ce que l'événement distribue, arrêté le 11 septembre

**100 lots**, valeur totale **3 580 € HT**, 31 références. Ils se gagnent de
**deux façons distinctes** :

| | Nombre | Comment | Où on le récupère |
|---|---|---|---|
| **Lots immédiats** | 85 | une case « lot » de la grille | au **stand des lots**, pendant le Forum, contre le code de retrait |
| **Gros lots** | 15 | **tirage au sort du soir** | sur scène, au cocktail |

Les 15 gros lots (1 696 € à eux seuls, dont le sac cuir Alpine à 379 €) **ne sont
pas dans la grille**. La grille distribue **30 « tickets d'or »** — des cases qui
ne disent pas ce qu'on gagne et qui qualifient pour le tirage. Trente pour quinze
lots : moins, et le tirage n'en serait pas un.

> ⚠️ **La mécanique du tirage à 15 gagnants reste à écrire.** `api_tirage_manche`
> élimine aujourd'hui jusqu'à **un** seul gagnant. Il faudra l'arrêter à quinze,
> et décider comment les 15 gros lots sont attribués aux 15 finalistes (ordre de
> sortie ? choix du gagnant ?). **Arbitrage Bony en attente**, l'utilisateur a dit
> « on verra ça après ».

### Les fournisseurs : un barème par catégorie

23 stands, 6 catégories, PIN `2001` à `2023`. Le barème n'est plus quatre nombres
nus dans le front : il vient de `bareme_stand`, indexé sur la catégorie, et le
représentant lit son propre vocabulaire.

| Catégorie | Stands | 5 pts | 10 pts | 20 pts |
|---|---|---|---|---|
| CA | FAAB, IXELL, ACCESSOIRES, FACOM, SAM, NILFISK, SPM | 1 à 199 € | 200 à 699 € | 700 € et + |
| ENTRETIEN USURE | MOTRIO, AGENT | 1 à 499 € | 500 à 999 € | 1 000 € et + |
| HUILES | CASTROL, ELF | Passage | Contact | Commande |
| SOLUTIONS | SIDEXA, WYZ, BARDHAL, FIDUCIAL, CHIMIREC | Passage | Contact | Commande |
| GROS ÉQUIPEMENT | CISCAR, PROVAC, MATEXPERT, FILLON TECHNOLOGIE, EXADIS | Passage | Contact | Commande |
| PNEUS | GOODYEAR, MICHELIN | 1 à 12 pneus | 13 à 24 pneus | 25 pneus et + |

> Le document Word fusionne verticalement la cellule « Passage / Contact /
> Commande » sur HUILES, SOLUTIONS et GROS ÉQUIPEMENT. Une extraction naïve du
> `document.xml` lit les cellules de continuation comme **vides** et fait croire
> que dix stands n'ont pas de barème. Lire les attributs `vMerge`.

> `BARDHAL` et `BLAZZPOD` sont recopiés tels qu'écrits par Bony (il s'agit
> probablement de *Bardahl* et *BlazePod*). Non corrigés faute de confirmation —
> un nom de marque ne s'invente pas plus qu'une raison sociale.

### Les 6 animations

PIN `1001` à `1006`, coût de participation **2 points** chacune, échelle
identique **20 / 10 / 5 / 0** : si un jeu rapportait plus, toute la halle ferait
la queue au même endroit et les cinq autres animateurs regarderaient passer la
journée.

BASKET ARCADE · FLÉCHETTES · ATELIER PÉTANQUE · BORNE D'ARCADE · BLAZZPOD ·
CORN HOLE

> ⚠️ **Les seuils de BASKET ARCADE, BLAZZPOD et BORNE D'ARCADE sont des
> marque-places.** Ces machines n'ont pas été vues. Il faut trois parties d'essai
> par jeu à la répétition, sinon soit tout le monde fait 20, soit personne.

> **Une animation rapporte net.** Elle coûte 2 points et rend ~9 en moyenne :
> **+7 par partie**, et rien dans le code n'empêche un garage d'enchaîner le même
> jeu toute la journée. Le seul frein réel est la file d'attente physique. Si la
> répétition montre un jeu monopolisé, le remède est le même que pour les cases :
> un plafond de parties par garage et par jeu, une clé de `config`, dix lignes.
> **Proposé, non fait** — l'utilisateur ne l'a pas demandé.

### L'économie des points — un modèle, pas une mesure

| Source | Hypothèse | Points par garage |
|---|---|---|
| Bonus d'arrivée | | 10 |
| Animations | 4 jouées sur 6, ~9 pts | ~36 |
| Fournisseurs | 4 stands sur 23, ~10 pts | ~40 |
| **Total** | × 150 garages = **~12 900 points émis** | **~86** |

200 cases à 20 points ne coûtent que **4 000 points** : la demande vaut trois fois
l'offre. D'où le **plafond de 3 cases par garage** (`config.cases_max_garage`),
sans lequel la grille serait vidée en début d'après-midi. Le plafond **se lève**
en direct et ne se baisse jamais — baisser pénaliserait ceux qui ont déjà acheté.

> ⚠️ Ce tableau est un **modèle**. Aucune donnée de terrain de l'édition
> précédente ne l'étaye. Le nombre de stands qu'un garage visite réellement est
> la variable la plus incertaine, et c'est celle qui pèse le plus.

### Travaux techniques identifiés, non faits

**A. Les six garages à code de test.** `GRND`, `BNY2`, `TEST`, `BAL2`, `FRUM`,
`JEUX` sont posés à la main sur de vrais clients. Deux conséquences : ces six-là
ont un code devinable, et si l'emailing est fabriqué depuis `sql/10_garages.sql`
plutôt que depuis la base, ils recevront un code qui ne marche pas. **Proposition
faite, décision en attente** : leur rendre leur code généré et faire chercher les
garages de test par numéro de compte. ~20 minutes.

**B. Le ping anti-veille.** Un projet Supabase gratuit s'endort après 7 jours sans
activité. Personne ne touchera au projet entre le 11 et le 17. Un appel quotidien
à `api_sante()` suffit à l'empêcher, gratuitement. **Proposé, non mis en place.**

**C. La gigue sur le sondage.** Les 150 téléphones qui démarrent ensemble sondent
ensemble. La mesure dit que 800 requêtes simultanées passent sans broncher, donc
**ce n'est pas nécessaire** — mais c'est dix lignes. Proposé, décliné faute de
justification chiffrée.

**D. Le mode hors ligne sur un vrai téléphone en mode avion.** Jamais fait.

**E. `SAINT SULPICE L APOI`, CP 15310.** Non identifié, laissé intact.

---

## 12. Les commandes

```powershell
# Envoyer un fichier SQL, ou une requête directe
.\scripts\push-sql.ps1 -File sql\01_schema.sql
.\scripts\push-sql.ps1 -Query "select count(*) from garages" -Quiet

# Les trois batteries de tests — 104 contrôles, à rejouer après tout changement SQL
.\scripts\test-porte.ps1        # 53 : la porte, le frein, les 31 PIN, les collisions
.\scripts\test-invariants.ps1   # 27 : double crédit, solde négatif, plafonds, paliers
.\scripts\test-bingo.ps1        # 24 : les deux modes, le tirage, 200 cases, plafond

# Serveur local (le service worker ne fonctionne pas depuis file://)
.\scripts\serveur.ps1           # http://localhost:8123

# Dimensionnement
.\scripts\mesurer-charge.ps1    # coût unitaire, taille du pool, rythme d'une soirée
.\scripts\trouver-plafond.ps1   # rafale montante jusqu'à la rupture

# LE JOUR J
.\scripts\diagnostic.ps1        # « est-ce la base, ou la couche devant ? »
.\scripts\exporter-journal.ps1  # journal, soldes et lots en CSV — toutes les heures

# Remise à zéro après la répétition générale
.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql

# Réimporter les garages depuis l'export Sarbacane
.\scripts\importer-garages.ps1  # régénère sql\10_garages.sql
```

### Après chaque `git push`

1. incrémenter `VERSION` dans `app/sw.js` ;
2. vérifier la version réellement servie (§9) — **les builds ont déjà échoué en
   silence deux fois**.

---

## 13. Les codes

> Le dépôt est **privé** et doit le rester. Ces codes sont des codes de
> démonstration : **ils doivent être changés avant le 17**, et
> `verifier_portes()` relancé ensuite.

| Profil | Code |
|---|---|
| Supervision Bony | `9137` |
| Poste d'accueil | `4200` |
| Lancer de basket / Pétanque / Fléchettes / Chamboule-tout | `1001` / `1002` / `1003` / `1004` |
| Filtres Auvergne … Pneus Chaîne des Puys | `2001` à `2005` |

Garages de démonstration : `GRND` (460 pts), `BNY2` (68 pts), `TEST` (10 pts),
`BAL2` / `FRUM` / `JEUX` (vierges). **Voir §11-A : ce sont de vrais clients.**

Cases truquées pour une démonstration : **3** (coffret à outils), **7** (enceinte),
**11** (bon d'achat 100 €), **17 / 34 / 58 / 76 / 93** (billets), **1 / 2 / 4 / 6**
(perdantes).

`.env.local` contient les accès Supabase et **n'est pas versionné**. Il faudra le
recopier à la main sur le nouveau poste : URL, `SUPABASE_PROJECT_REF`,
`SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_ANON_JWT`,
`SUPABASE_SERVICE_ROLE_JWT`, `SUPABASE_ACCESS_TOKEN` (le PAT `sbp_`).

---

## 14. Les livrables annexes

- **`presentation/direction.html`** — diaporama de 14 diapositives pour la
  direction Bony, à la charte de l'application, avec les cinq interfaces en
  maquette. Publié en artefact privé. **Ne contient volontairement aucun code
  d'accès** : une présentation se partage.
- **`maquette-grand-bal-points.html`** — la maquette cliquable d'origine, à la
  racine. Historique, plus maintenue.
- **`exports/`** — sortie de `exporter-journal.ps1`, **ignorée par git** (contient
  les codes d'accès des garages).
