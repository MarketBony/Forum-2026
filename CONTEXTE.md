# Le Grand Bal des Fournisseurs — dossier de reprise

> **À lire en entier avant de toucher au code.** Ce document est écrit pour une
> session de travail qui ne connaît rien au projet. Il dit ce qu'est
> l'application, pourquoi elle est construite ainsi, ce qui a été fait, ce qui
> reste, les pièges rencontrés, et la méthode de travail attendue.
>
> Dernière mise à jour : **16 septembre 2026, au soir**. Événement :
> **jeudi 17 septembre 2026** — c'est **demain**.
>
> Les §1 à §14 décrivent l'application. Le **§15** décrit le générateur de
> badges, ajouté les 14 et 15 septembre : c'est un outil local, séparé, qui ne
> touche pas à l'application et n'est jamais déployé.
>
> 🔴 **LA SEULE CHOSE QUI RESTE À FAIRE AVANT LE FORUM** :
> `.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql`
> La base porte encore les traces des tests et de la simulation. Sans cette
> remise à zéro, des cases sont déjà prises et des garages arrivent avec un
> solde fictif. **Rien d'autre n'est bloquant.**
>
> ⚠️ **L'événement s'appelle « Le Grand Bal des FOURNISSEURS ».** Les commits et
> les captures antérieurs au 15 septembre disent « des Points » : c'était une
> erreur de nom, corrigée partout ce jour-là — application, badges, présentation,
> documentation. Le nom vient de la page d'invitation de Bony, il ne s'invente
> pas. Seuls `maquette-grand-bal-points.html` (historique, plus maintenu) et
> l'identifiant du service worker `gbp-*` gardent l'ancienne trace.

---

## 1. En une page

| | |
|---|---|
| **Quoi** | Un portefeuille de points virtuel pour un salon professionnel B2B |
| **Pour qui** | Bony Automobile, Clermont-Ferrand — distributeur de pièces automobiles |
| **Quand** | Jeudi 17 septembre 2026, toute la journée puis cocktail dînatoire |
| **Où** | Grande Halle d'Auvergne, Cournon-d'Auvergne |
| **Public** | **1 457 garages** en base ; **211 personnes inscrites** retenues, 320 annoncées |
| **Remplace** | Les jetons en carton de l'édition précédente |
| **En ligne** | https://forum-2026.bonyauto-mobile.workers.dev/ — **et rien d'autre**, voir §10 |
| **Dépôt** | `MarketBony/Forum-2026` — **privé**, doit le rester |
| **Coût** | 0 € (Cloudflare Workers gratuit + Supabase gratuit) |
| **État** | **Terminé et déployé** (`gbp-v22`), 114 tests verts, plus aucune décision bloquante |
| **Badges** | **516 badges**, 258 feuilles A4 — voir §15 |
| **Éprouvé** | simulation de 400 garages par l'API réelle : **0 échec sur 5 831 appels** — voir §8 |

> Le chiffre de « ~150 attendus » qui figurait ici jusqu'au 11 septembre était une
> estimation. Le listing consolidé du 14 septembre l'a remplacée par une mesure :
> **212 personnes inscrites au Forum**, 320 annoncées en comptant les
> accompagnants. C'est deux fois plus que prévu, et ça ne change rien au
> dimensionnement — voir §8, la rupture était à 800 requêtes simultanées.

L'interlocuteur est **Bastien Fuziol** (`bastien.fuziol@bonyauto-mobile.com`),
au service marketing. Technique sans être développeur : il comprend
l'architecture, lit du SQL, mais n'écrit pas le code. Il tutoie, va droit au but,
et **demande des preuves chiffrées plutôt que des affirmations**. Quand il dit
qu'une chose ne va pas sur le terrain, c'est son terrain : il a raison.

---

## 1 bis. Le jour J, en une page

> Pour une session ouverte le matin du Forum. Tout le reste du document explique
> le pourquoi ; celle-ci dit quoi faire.

### Avant l'ouverture

```powershell
# 1. Remettre la base à zéro. OBLIGATOIRE. Elle préserve la grille.
.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql

# 2. Vérifier que tout est à zéro et que la composition a survécu
.\scripts\push-sql.ps1 -Quiet -Query "select (select count(*) from journal) as journal, (select count(*) from grille where garage_id is not null) as cases_prises, (select count(*) from verifier_soldes()) as ecarts, (select count(*) from grille where nature='lot') as lots, (select count(*) from grille where nature='billet') as tickets"
# attendu : journal=0  cases_prises=0  ecarts=0  lots=85  tickets=15

# 3. Vérifier que le site servi est bien à jour
(New-Object System.Net.WebClient).DownloadString(
  'https://forum-2026.bonyauto-mobile.workers.dev/sw.js?t=' + (Get-Random)
) -match "const VERSION = '([^']+)'" ; $Matches[1]
```

### Pendant la journée

- **La console de santé** est en haut de l'écran de supervision. Tant que la
  santé globale est verte, il n'y a rien à faire. Le **tableau de bord Supabase,
  lui, sera rouge vif** : il compte chaque refus voulu comme une erreur. Ne pas
  s'y fier.
- **Exporter le journal toutes les heures** : `.\scripts\exporter-journal.ps1`.
  C'est la seule vraie sauvegarde de la soirée.
- **Une panne ?** `.\scripts\diagnostic.ps1` répond à la seule question utile :
  « est-ce la base, ou la couche devant ? »

### Le soir

1. Supervision → **Grand tirage au sort** → *Lancer la révélation*.
2. 4 s par lot, soit ~61 s pour 15 tickets. Un clic sur la scène fait tomber le nom tout de suite, un second
   passe au lot suivant.
3. Le récapitulatif reste affiché, et sert au stand des lots.
   **Si l'écran est rouvert plus tard**, il ne réaffiche rien de lui-même :
   un bouton *Afficher le récapitulatif* le rappelle.
4. **Un dernier export du journal** avant de fermer.

### Les réglages, tous en direct dans `config`

| Clé | Valeur au 16/09 | Ce qu'elle fait |
|---|---|---|
| `cout_grille` | `20` | le prix d'une case |
| `cases_max_garage` | `5` | cases par garage · `0` = illimité |
| `bonus_inscription` | `10` | les points offerts à l'arrivée |
| `appareils_max` | `6` | téléphones par garage · **une place prise ne se rend pas** |
| `quota_animation_x` | `4` | × le meilleur palier = points max d'UNE animation par garage |
| `quota_stand_x` | `3` | × le plafond d'opération = points max d'UN stand par garage |
| `revelation` | `immediate` | `differee` = tout se révèle le soir |
| `tentatives_max` | `8` | essais de code par appareil sur 5 minutes |
| `tirage_revele` | `non` | passe à `oui` quand la révélation a eu lieu |

### Les gestes qui sauvent

| Situation | Geste |
|---|---|
| Il reste des cases en fin de journée | monter `cases_max_garage`, ou le passer à `0` (illimité) |
| La grille se vide trop vite | **on ne baisse jamais le plafond** : ce serait pénaliser ceux qui ont déjà acheté. Le frein, ce sont les quotas — `quota_animation_x`, `quota_stand_x` |
| Une animation est désertée | `update animations set cout = 0 where nom = '…'` |
| Un garage n'a pas son code | l'accueil le retrouve et le lit — `sql/09_accueil.sql` sait déjà le faire |
| Un garage a épuisé ses 6 appareils | c'est un plafond dur ; `update config set valeur='8' where cle='appareils_max'` |
| Une erreur de points | **jamais de modification** : une écriture inverse, par la supervision |

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
| **Accueil** | le code hôtesse | chercher parmi les 1 457 invités, **lire un code**, voir le compteur d'arrivées |
| **Équipe Bony** | le code direction | supervision, remise des lots, corrections, **détail des tickets d'or**, écran de projection |

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

**Douze tables**, comptées en base le 15 septembre. `sql/01_schema.sql` fait foi
pour le socle, `sql/15_fournisseurs.sql` pour `bareme_stand`, et
`sql/19_participants.sql` pour `participants`.

| Table | Rôle |
|---|---|
| `config` | réglages clé/valeur — codes, coûts, plafonds, mode de révélation |
| `garages` | les 1 457 invités : compte Bony, nom, commune, CP, e-mail, **code**, solde |
| `appareils` | un téléphone = un jeton ; porte le rôle et le rattachement |
| `animations` | les 4 jeux, leur mise et leur code |
| `bareme` | les résultats possibles de chaque jeu et leurs points |
| `bareme_stand` | le barème fournisseur **par catégorie** — voir §11 |
| `stands` | les stands fournisseurs, leur code et leurs plafonds |
| `journal` | **le registre en ajout seul** — chaque point, daté et signé |
| `grille` | les 100 cases : nature, lot, code de retrait, qui l'a prise |
| `tentatives` | les codes erronés, pour le frein anti-devinette |
| `tirage` | les manches du grand tirage, pour qu'il soit rejouable |
| `participants` | **qui porte un badge** — l'application ne la connaît pas, voir §15 |

> `participants` est à part : aucune fonction `api_*` n'y touche, elle n'est lue
> que par le générateur de badges, en local. Elle ne porte **aucun code** — ils
> sont résolus à la lecture par la vue `v_badges`.

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

> ⚠️ **ET C'EST POURQUOI SE DÉCONNECTER N'EFFACE PAS LE JETON.** `api_entrer` ne
> compte l'appareil dans le plafond que si son jeton n'est pas *déjà* rattaché au
> garage. Un jeton neuf à chaque retour, c'est donc une ligne de plus à chaque
> aller-retour — et au sixième, le garage se retrouve enfermé dehors avec un
> « Ce garage a déjà 6 appareils connectés ». Le bouton « Quitter » n'oublie donc
> que le **rôle** ; le jeton, qui est l'identité de l'appareil et non celle de la
> session, reste. `oublierAppareil()` existe toujours mais n'est plus appelé :
> c'est un outil de dépannage, pas un geste d'utilisateur.
>
> Mesuré le 15 septembre : **six allers-retours d'affilée sur le même téléphone,
> jeton inchangé, une seule ligne d'appareil, et le bonus d'arrivée versé une
> seule fois** (la clé `inscription:<garage>` tient l'idempotence).

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
est bloqué. `verifier_portes()` le contrôle — **0 collision** sur 1 457 codes
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
| `app/js/app.js` | toutes les vues et toutes les actions |
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
| `42cd267` | **renommage** en « des Fournisseurs », barème du prestataire, révélation du soir |
| `5c9b45b` | **case ↔ lot scellé** — le classeur d'étiquetage est sorti |
| `c22fe46` | le piège des deux origines et le service worker qui survit à son domaine |
| `0555b4c` | déconnexion garage sans brûler de place d'appareil, détail des tickets d'or |
| `f6b4eec` | un `catch {}` vide immobilisait la tablette sur « Chargement… » |
| `7095314` | **31 PIN définitifs**, la console de santé, le verre qui se mesure |
| `385dd6c` | **la simulation** de 400 garages, et le voyant de pool qui mentait |
| `7e31ee8` | **les quotas par garage**, deux listes repliables |
| `85a0f72` | **les règles du jeu**, une version par profil |
| `e892bc6` | **la présentation agents** pour la réunion du matin |

### Le nettoyage des données

L'export Sarbacane fourni était sale : raisons sociales tronquées à 30
caractères, communes tronquées à 20, accents perdus, « GGE » pour « Garage ».
Trois tables curatives dans `scripts/importer-garages.ps1` :

- `$EXPRESSIONS` — expressions entières (« Vic sur Cere » → « Vic-sur-Cère ») ;
- `$ACCENTS` — mots français dont l'orthographe ne fait **aucun** doute ;
- `$COMMUNES` — 72 entrées indexées sur **`CP|libellé brut`**, pour qu'une
  correction ne puisse jamais s'appliquer par ricochet ;
- `$UNIFIEES` — fait converger les orthographes multiples d'une même commune.

Résultat : **576 communes distinctes, aucune en double orthographe, 1 457 codes
intacts.**

**Les 20 raisons sociales tronquées ont été laissées telles quelles.** Le nom
qu'un garagiste s'est choisi ne s'invente pas. Une commune se reconstitue depuis
un code postal — c'est de la donnée publique ; un nom d'entreprise, non.
*Distinction validée par l'utilisateur.*

`SAINT SULPICE L APOI` au CP 15310 n'a pas pu être identifié avec certitude et a
été laissé intact plutôt que deviné.

---

## 8. Le dimensionnement — question close, et mesurée

Le sujet a été clos le 15 septembre par une simulation de 400 garages jouée par
l'API réelle : **0 échec sur 5 831 appels, 300 req/s de pointe contre ~20
attendus**. Le détail est plus bas ; l'historique qui suit explique pourquoi la
question s'était posée.

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
- **le wifi de la Grande Halle** restait le risque le plus probable de la
  soirée, bien avant Supabase. *Bastien l'a vérifié sur place le 15 septembre.*
  Il reste que ce banc mesure Supabase, pas le réseau de la halle ;
- rien ne remplace une répétition sur place.

### La simulation du 15 septembre — la question est close

`scripts/simuler-forum.ps1` joue **une journée entière par l'API réelle** :
arrivées, animations, stands, grille jusqu'à épuisement, révélation du soir.
Rien en SQL direct — une injection ne prouverait ni les plafonds, ni
l'idempotence, ni la concurrence, ni le pool.

**400 garages joués** contre 212 inscrits réels, et **13 écritures par garage**
contre 8 au modèle : la surestimation porte sur combien ils sont *et* sur ce que
chacun fait. La journée est compressée en 35 secondes.

```
Duree ................... 35,1 s
Appels .................. 5 831
Debit moyen ............. 166 req/s
Debit de POINTE ......... 300 req/s   (charge attendue au Forum : ~20)
Reussites ............... 5 831
ECHECS DURS ............. 0

api_points_achat   2000 appels   mediane 201 ms   p99 330 ms
api_participation  1600 appels   mediane 182 ms   p99 346 ms
api_resultat       1600 appels   mediane 199 ms   p99 283 ms
api_jouer_case      200 appels   mediane 1 100 ms  p99 1 132 ms

lignes_journal 5 800 · cles_distinctes 5 800 · ecarts_solde 0
cases_prises 200 · cases_libres 0 · tickets_or 15
```

5 800 clés d'idempotence pour 5 800 lignes : **aucun double crédit**. Zéro écart
de solde sur 400 garages. Les 200 cases parties, les 15 tickets décrochés, la
révélation jouée.

**Le point de rupture**, cherché au-delà : 0 échec jusqu'à **800 requêtes
simultanées** (deux passages), 0 échec à 1 200 et 2 000 mais avec des latences de
5 à 10 s, et ça casse entre 2 000 et 3 000 — où ma machine saturait ses sockets
autant que Supabase. Le pire cas réel au Forum, c'est 400 téléphones qui se
réveillent ensemble.

> Le débit mesuré varie d'un passage à l'autre (91 à 330 req/s à 800 simultanées)
> selon l'état de la machine cliente. **Le nombre d'échecs, lui, est
> invariablement zéro.** C'est celui-là qui compte.

### Décision sur le plan payant : NON, et c'est mesuré

**Pas pour la charge.** 300 req/s de pointe sans un échec contre ~20 attendus,
c'est **quinze fois la marge** ; 800 simultanées sans un échec contre 400
téléphones au pire. Le plan gratuit n'est pas le facteur limitant.

Les trois raisons de payer n'ont jamais été la charge, et elles ont fondu :
1. **la mise en veille après 7 jours** — sans objet à deux jours de l'événement ;
2. **l'absence de sauvegarde** — celle du plan Pro est prise la nuit et ne
   contiendrait **rien de la soirée du 17**. Ce qui protège vraiment, c'est
   `scripts/exporter-journal.ps1`, à lancer toutes les heures ;
3. **le canal de support** — le seul argument qui tienne encore : 25 $
   d'assurance pour avoir quelqu'un à qui écrire si Supabase lui-même tombe.
   C'est un arbitrage, pas une question technique.

*Décision de Bastien le 15 septembre : « on garde le plan gratuit pour l'instant
et j'arbitrerai demain si je prends le payant par précaution ».*

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

**Les tests tournent contre la vraie base.** Pas de mock. 114 contrôles :
`test-porte.ps1` (53), `test-invariants.ps1` (32), `test-bingo.ps1` (29). À
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
- ⚠️ **COMPTER LES CONNEXIONS DU POOL NE MESURE PAS SON OCCUPATION.** Mesuré le
  15 septembre pendant la simulation : après la montée en charge, les 11
  connexions `authenticator` restent ouvertes — **toutes à l'état `idle`** —
  parce qu'un pool ne rend pas ses connexions, il grandit jusqu'à son plafond et
  les garde. Le voyant de la console affichait donc « 11/11 · critique » en
  permanence pendant que tout répondait en 105 ms : exactement le défaut qu'on
  reproche au tableau de bord Supabase, un rouge permanent qui ne veut plus rien
  dire. Ce qui mesure l'occupation, c'est `state = 'active'` **parmi** les
  connexions `authenticator`. `api_sante_detail()` rend les deux : `pool` (celles
  qui travaillent) et `pool_ouvertes` (la réserve).

- **Realtime est `UNHEALTHY` sur notre projet.** On ne s'en sert pas, aucun impact.
  Illustration du principe : le tableau de bord désigne le symptôme, jamais la
  cause.

### Le déploiement

- ⚠️ **IL N'Y A QU'UNE SEULE URL : `forum-2026.bonyauto-mobile.workers.dev`.**
  Une `forum-2026.theo-labonne.workers.dev` a existé — le tout premier
  déploiement du projet, fait sur le sous-domaine Cloudflare personnel avant que
  l'intégration Git ne soit posée sur le compte Bony. **Elle n'a jamais reçu une
  seule mise à jour** et son nom ne résout plus. Elle n'apparaît dans aucun
  commit : `wrangler.jsonc` n'a jamais désigné que le worker `forum-2026`.

- ⚠️ **ET ELLE SURVIT DANS LES NAVIGATEURS QUI L'ONT CONNUE.** C'est le piège,
  et il est vicieux : `app/sw.js` a installé un service worker sur cette
  origine-là. Le domaine est mort, mais le navigateur sert toujours la coquille
  depuis son cache — **pendant que les appels RPC, eux, partent directement chez
  Supabase et rendent des données parfaitement à jour**. On obtient donc une
  application qui a l'air de marcher, avec les vrais chiffres du jour, dans
  l'habillage et la mécanique du premier commit.

  Symptômes vus le 15 septembre 2026, sur la supervision : cartes plates à
  bordure au lieu des surfaces éclairées, libellés en CAPITALES, aucune
  guirlande ni dégradé de fond, et surtout **« 12 / 100 » là où la base compte
  200 cases**. Ce « / 100 » est écrit en dur dans `2d8781c` et nulle part
  ailleurs : c'est la signature qui date la version affichée à coup sûr.

  **Comment en sortir** : ouvrir l'ancienne URL, « Effacer les données du site »
  (c'est ce qui tue le service worker), désinstaller l'application si elle a été
  ajoutée à l'écran d'accueil, puis repartir de la bonne URL.

  **À faire sur tous les téléphones de l'équipe avant le Forum.** Un animateur
  qui garde la vieille coquille aurait l'ancien barème, pas de ticket d'or, et
  une grille annoncée à 100 cases — avec les vraies données dessous, donc sans
  rien qui l'alerte.

- **Le tableau de bord Supabase compte comme « erreur » tout refus voulu.**
  Après un passage des 114 tests, il affiche ~70 erreurs Postgres : ce sont les
  `CASE_DEJA_PRISE` du test de concurrence (7 refus sur 8 achats simultanés =
  le test réussit), les `permission denied` qui prouvent que la clé publique ne
  lit aucune table, les plafonds qui plafonnent, le trigger d'inaltérabilité qui
  refuse un DELETE. **Zéro panne là-dedans.** Illustration du principe déjà noté
  plus haut : le tableau de bord désigne le symptôme, jamais la cause.

### L'application

- **`feDisplacementMap` déforme le contenu de l'élément filtré** — voir §6.
- **Le tableau de bord admin doit se recharger en y revenant**, sinon un lot que
  Bony vient de remettre reste affiché comme « à remettre » jusqu'au sondage
  suivant, et l'équipe doute de l'outil.
- ⚠️ **UN `catch {}` VIDE IMMOBILISE UN ÉCRAN POUR TOUJOURS.**
  `chargerSupervision()` et `chargerAccueil()` avalaient toute erreur sans un
  mot. Quand l'appareil disparaît de la base — remise à zéro, purge des
  appareils par une batterie de tests, rôle réattribué — l'appel échoue, la
  donnée reste nulle, et l'écran affiche « Chargement… » indéfiniment : pas de
  message, pas de bouton, pas d'issue. **Constaté sur un vrai téléphone le
  15 septembre.** Les trois chargeurs passent désormais par `sessionMorte()`
  (qui renvoie à l'écran de code) et retiennent toute autre panne dans `S.panne`,
  que `ecranAttente()` affiche avec « Réessayer ». Un « Chargement… » qui ne
  finit jamais est le pire des états : il ne dit rien et n'offre rien.
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

## 11. Ce qui reste — état au 16 septembre 2026, veille du Forum

### 🔴 La seule manœuvre obligatoire

```powershell
.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql
```

La base porte les traces des 114 tests et de la simulation de 400 garages. Sans
cette remise à zéro, des cases sont déjà prises et des garages arrivent avec un
solde fictif. **C'est la seule chose qui rendrait le Forum injouable si on
l'oubliait.** Elle préserve la composition de la grille — les 100 lots et les 15
tickets d'or restent en place, seuls les achats et le journal sont effacés.

Après elle, vérifier que tout est à zéro :

```powershell
.\scripts\push-sql.ps1 -Quiet -Query "select (select count(*) from grille where garage_id is not null) as cases_prises, (select count(*) from journal) as journal, (select count(*) from verifier_soldes()) as ecarts"
```

### Les décisions de Bony — toutes rendues

| # | Sujet | État |
|---|---|---|
| 1 | ~~Les 32 lots à nommer~~ | ✅ **100 lots réels**, issus de `stock forum.xlsx` |
| 2 | **Mode de révélation** | `immediate` aujourd'hui ; `differee` possible en une ligne |
| 2bis | ~~Attribution des 15 gros lots~~ | ✅ **collés aux tickets à l'avance**, le soir est une révélation |
| 3 | ~~Nombre de billets~~ | ✅ **15 tickets d'or** sur 200 cases, un par gros lot |
| 4 | ~~Codes définitifs du personnel~~ | ✅ **31 PIN définitifs** poussés le 15/09 — `sql/24_pins.sql` |
| 5 | ~~Barèmes et plafonds~~ | ✅ fournisseurs **par catégorie** ; 6 animations en **10/5/3/2/0** |
| 6 | ~~Répétition sur place~~ | ✅ le wifi de la halle a été vérifié par Bastien |
| 7 | ~~Les listings de participants~~ | ✅ **516 badges** en base, voir §15 |
| 8 | ~~Les arbitrages de badges~~ | ✅ tous tranchés le 15/09, détail en fin de §15 |
| 9 | ~~Un 3ᵉ palier aux fléchettes~~ | ✅ « Les 3 fléchettes dans la cible » à 2 pts — **marque-place assumé** |
| 10 | ~~« TOP SCORE EN 45 SECONDES »~~ | ✅ seuil sur ardoise — **consigne à donner de vive voix** |
| 11 | **Constructeurs** | 🟡 le seul listing encore attendu ; la catégorie est prête et vide |

### Ce qui reste en dehors du code

> 1. **Relancer `99_remise_a_zero.sql`.** Voir ci-dessus. C'est le seul point dur.
> 2. **Dire aux animateurs du BASKET ARCADE et du BLAZZPOD** d'écrire le score à
>    battre sur une ardoise. Le prestataire a écrit « TOP SCORE EN 45 SECONDES,
>    4 PTS À GAGNER » : ça donne un plafond, aucun seuil, et l'application
>    demande un RÉSULTAT, pas un nombre. C'est la seule consigne humaine qui
>    manque au dispositif.
> 3. **Le listing constructeurs**, quand Bastien l'aura, avec
>    `importer-inscriptions.ps1`. Renault est inscrit — deux personnes avec des
>    identifiants `EXTERN` — mais n'a aucun code en base.
> 4. **Exporter le journal toutes les heures** le jour J :
>    `.\scripts\exporter-journal.ps1`. Le plan gratuit n'a aucune sauvegarde, et
>    celle du plan payant ne contiendrait rien de la soirée de toute façon.

### Ce qui n'a jamais été éprouvé, et qu'il faut dire

> - **Le mode hors ligne sur un vrai téléphone en mode avion.** Bastien a
>   tranché : « on en a pas besoin, c'est un plus que je ne testerai pas ».
> - **L'écran de projection sur le vrai écran LED.** Vérifié au navigateur à
>   800 px, 1 280 × 720 et 1 920 × 1 080 — jamais en salle, jamais avec le rendu
>   couleur d'un projecteur. La taille du nom et le contraste du fond violet ne
>   se jugent que sur place.
> - **La présentation agents sur le vidéoprojecteur de la salle de réunion.**
>   Zéro débordement mesuré à 1 440 × 810 et 1 920 × 1 080, mais la lisibilité à
>   dix mètres ne se mesure pas depuis un navigateur.
> - **Le QR des badges lu par un vrai capteur**, sur papier, sous des néons. Il a
>   été décodé par une bibliothèque indépendante, jamais photographié.

### 🔒 Case ↔ lot : scellé le 15 septembre 2026

La liste complète a été sortie en classeur d'étiquetage et les lots physiques
portent leur **numéro de case**. *Verbatim : « les lots et tickets d'or seront
scellés à leur numéros et ne pourront plus bouger ».*

`exports/Lots Forum 2026 - etiquetage.xlsx`, hors dépôt — il nomme les 15 gros
lots du soir, qui sont le secret de la soirée. Trois feuilles :

| Feuille | Contenu |
|---|---|
| **Étiquettes** | les 85 lots remis au stand, par numéro de case |
| **Gros lots du soir** | les 15, par ordre de révélation — **confidentiel** |
| **Par référence** | 31 lignes, pour sortir les lots du stock |

**Le « code » de l'étiquette est le NUMÉRO DE CASE**, pas le code de retrait.
Le code de retrait n'existe pas avant l'achat : il est dérivé de la clé
d'idempotence au moment où le garage prend la case. Le parcours au comptoir est
donc : le garage montre son code → l'écran « Suivi des lots » de la tablette
donne le numéro de case → on prend l'objet étiqueté à ce numéro.

**Rapprochement vérifié, pas supposé.** Les libellés de la grille et ceux de
l'état de stock ne coïncident pas (« MINIATURE Renault Austral EA BLEU » contre
« 1L43 HHN MY25 EA BLEU ») : la correspondance est une table écrite à la main,
et le script refuse de produire le classeur si elle n'est pas exacte et
bijective. Résultat : **100 cases, 31 références, et la grille consomme
exactement le stock proposé, référence par référence.**

| | Unités | Valeur HT |
|---|---|---|
| Lots immédiats | 85 | 1 884,37 € |
| Gros lots du soir | 15 | 1 695,68 € |
| **Total** | **100** | **3 580,05 €** |

Ce total recoupe les 3 580 € notés depuis le 11 septembre. Les totaux du
classeur ont été recalculés par Excel : **zéro formule en erreur**.

**Conséquence : `sql/18_lots.sql` et `sql/23_grand_tirage.sql` ne doivent plus
changer de valeurs.** Les rejouer à l'identique reste sans danger — ils
réécrivent les mêmes lignes — mais modifier un numéro rendrait fausses des
étiquettes déjà collées, sans que rien ne le signale avant le comptoir.

### Ce que l'événement distribue, arrêté le 11 septembre

**100 lots**, valeur totale **3 580 € HT**, 31 références. Ils se gagnent de
**deux façons distinctes** :

| | Nombre | Comment | Où on le récupère |
|---|---|---|---|
| **Lots immédiats** | 85 | une case « lot » de la grille | au **stand des lots**, pendant le Forum, contre le code de retrait |
| **Gros lots** | 15 | une case « ticket d'or », puis le tirage du soir | sur scène, au cocktail |

Les 15 gros lots (1 696 € à eux seuls, dont le sac cuir Alpine à 379 €) **ne sont
pas nommés dans la grille**. La grille distribue **15 « tickets d'or »** — des
cases qui ne disent pas ce qu'on gagne.

**Quinze tickets pour quinze gros lots : personne ne perd.** Une première version
en posait trente, pour que le tirage ait de vrais perdants. C'était une faute,
relevée par l'utilisateur : un garage qui lit « qualifié ! », reste pour le
cocktail, monte sur scène et redescend les mains vides garde un plus mauvais
souvenir que s'il était tombé sur une case perdante — on lui avait promis quelque
chose. Le tirage ne décide donc plus *qui gagne* mais **qui gagne quoi**, entre le
sac Alpine à 379 € et l'avion Caudron à 72 €. Le suspense reste entier.

Résultat : **100 cases gagnantes sur 200, une chance sur deux, et exactement un
lot par case gagnante.** C'est l'énoncé le plus simple possible du jeu.

### Le soir n'est plus un tirage, c'est une révélation

**Arbitrage rendu le 15 septembre**, et il simplifie tout : *chaque ticket d'or
est collé à SON gros lot, décidé à l'avance.* `sql/23_grand_tirage.sql` fige les
15 affectations, case par case. Le seul hasard de la soirée a donc déjà eu lieu —
c'est le garagiste qui a choisi la case 182 à 15 h 40 sans savoir ce qu'il y avait
dessous.

> *Verbatim : « Pas d'aléatoire dans la soirée. Tout est prédéfini à l'avance. Le
> seul aléatoire c'est quand les garagistes cliquent sur les cases. »*

**Un tirage truqué est un scandale ; une révélation ne peut pas l'être.** Personne
ne peut prétendre qu'on a retouché quoi que ce soit sur scène, puisqu'il n'y a
rien à retoucher.

L'ancienne mécanique d'élimination (`api_tirage_ouvrir`, `api_tirage_manche`, la
table `tirage`) est **supprimée**. Laisser deux mécaniques contradictoires en
place, c'était garantir qu'on appuierait sur le mauvais bouton à 22 h.

| Ce qui remplace | Rôle |
|---|---|
| `grille.gros_lot` | le lot collé au ticket — **jamais renvoyé au garage avant le soir** |
| `grille.gros_lot_ordre` | l'ordre de spectacle, figé |
| `config.tirage_revele` | `non` / `oui` — l'état de la soirée |
| `api_tirage_etat` | les 15 tickets, décrochés ou non, pour préparer la scène |
| `api_tirage_lancer` | **un seul appel** : bascule, pose les codes de retrait, rend tout |
| `api_tirage_reset` | rabaisse le drapeau, pour la répétition |

**Les 15 gros lots ont été reconstitués par soustraction** depuis
`STOCK LOT FORUM - 2026.xlsx` : 100 unités proposées au Forum moins les 85 posées
sur la grille par `sql/18_lots.sql`. Il reste exactement 15 unités pour
**1 695,68 € HT**, ce qui recoupe les deux chiffres déjà notés ici (15 lots,
1 696 €) — donc rien d'inventé.

| Gros lot | Qté | PV HT |
|---|---|---|
| SAC CUIR ALPINE JAUNE 48H | 1 | 379,17 € |
| CIRCUIT ELECTRIQUE RACE TRACK V3 | 5 | 115,00 € |
| WEEKENDER 72H A290 | 1 | 101,15 € |
| SAC A DOS ALPINE ESSENTIAL | 1 | 93,75 € |
| MONTRE R5 JAUNE | 2 | 91,68 € |
| AVION CAUDRON BOIS | 5 | 72,65 € |

**L'ordre de révélation est un ordre de spectacle**, pas un classement : jamais
deux fois le même lot à la suite (sur cinq avions Caudron identiques, les
annoncer d'affilée tue la salle), et les trois pièces uniques à la fin, par
valeur croissante — le sac cuir Alpine en dernier. Un contrôle SQL refuse le
fichier si l'une de ces deux règles saute.

**L'affectation case → lot vient d'une graine fixe** (`grand-bal-2026-revelation`)
comme la grille elle-même : aucune corrélation entre le numéro de la case et la
valeur du lot, sans quoi il aurait suffi de lire le fichier pour savoir que la
case 182 valait 379 €.

#### L'écran de projection

**LA DURÉE SE COMPTE PAR LOT, PLUS EN BUDGET TOTAL.** `REVEL_PAR_LOT` vaut
**4 000 ms**, sous le plafond de 5 s posé par Bastien le 17 septembre :
*« 5 secondes par tirage d'un garage grand max, et que ça enchaîne vite d'un
tirage à l'autre »*.

Le budget global a disparu avec cette passe, et c'est le bon modèle : ce que la
salle ressent, c'est le temps d'UNE annonce, pas la somme. Un budget total
faisait dépendre le rythme du nombre de tickets décrochés — à 8 tickets au lieu
de 15, chaque annonce durait presque le double sans que personne l'ait demandé.

**Mesuré sur un passage complet de 15 tickets : 61,1 secondes.**

```
noms tombés à : 2,6 · 6,6 · 10,7 · 14,7 · 18,8 · 22,9 · 27,0 · 31,1 · 35,1
                39,2 · 43,3 · 47,4 · 51,5 · 55,5 · 59,6 s   → fin à 61,1 s
écarts        : 4,05 à 4,10 s, sans exception — plafond de 5 s tenu
```

> **Quatre passes, toutes sur retour de scène.** 57 s au total : « un poil trop
> rapide ». 95 s : « un poil trop long ». 80 s : le compromis du 16, mais 8,9 s
> sur les trois derniers lots. **4 s par lot** : le réglage du 17.
>
> ⚠️ **Le temps double des trois derniers a sauté.** Il portait le crescendo sur
> les trois pièces uniques — sac à dos Alpine, weekender, sac cuir jaune — et il
> est incompatible avec le plafond de 5 s : à poids double, elles tombaient à
> 8 s. Le spectacle finit toujours sur le plus beau lot, mais au même rythme que
> le reste. C'est un arbitrage de scène, pas un oubli.
>
> `REVEL_SUSPENSE` monte de 0,50 à **0,62** : c'est le temps mort APRÈS la chute
> du nom qui donnait l'impression de traîner, pas la roulette. À 4 s, ça fait
> 2,5 s de roulette et 1,5 s de nom en clair — la roulette a donc plus de temps
> qu'avant, et l'attente moins. Ne pas descendre sous 3 s par lot sans rejouer
> le spectacle : la roulette n'aurait plus la place de ralentir.

**Le titre de scène est détaché du lot.** « Le grand tirage » et le nom du lot
partageaient le gap commun de la scène — 12 px — et se lisaient de loin comme une
seule phrase : l'œil ne savait plus où s'arrêtait l'habillage et où commençait le
gain. L'écart est désormais donné en `vh` (`clamp(16px,3.2vh,44px)`), soit 49 px
mesurés à 720 px de haut, parce qu'un espace fixe en pixels se tasse à rien quand
le reste de la scène grandit avec l'écran. Il est remis à zéro sur le carton de
fin, qui n'annonce plus un lot mais un décompte.

Chaque temps se joue en deux moments. **Le lot s'annonce** — étiquette en
capitales espacées, or, volontairement discrète — puis **la roulette part** : les
noms des porteurs de ticket défilent et ralentissent jusqu'à s'arrêter sur le
gagnant. La décélération est en **p²** ; un ralentissement linéaire donne une
impression de panne, pas de suspense. Pendant le défilé le nom est en retrait (or,
à demi effacé, légèrement flou) : c'est du mouvement, pas de la lecture. À
l'arrêt, un **éclat d'or s'ouvre derrière le nom** et s'efface en une demi-seconde.

Tous les noms qui défilent sont de vrais porteurs de ticket : la roulette ne ment
sur rien, elle met en scène ce qui est déjà décidé.

**La hiérarchie typographique est inversée par rapport à l'intuition, et c'est
voulu.** Le lot est le sujet de la phrase, pas sa chute : 34 px au plus. Le nom du
garage est la chute, et c'est lui que la salle cherche : **jusqu'à 118 px**. Une
première version faisait l'inverse — on lisait le lot de loin et il fallait
plisser les yeux pour voir qui avait gagné.

**Les trois derniers temps durent le double.** C'est là que se trouvent les trois
pièces uniques : sac à dos Alpine, weekender, et le sac cuir jaune à 379 € qui
clôt le spectacle. On finit sur le sommet, sans se presser.

**Un clic sur la scène a deux temps** : le premier fait tomber le nom en cours, le
second passe au lot suivant. Un clic unique qui sauterait directement au suivant
escamoterait le nom — c'est-à-dire la seule chose que la salle attend. Après un
clic, le spectacle **repart tout seul** : sans ça, un animateur qui presse le pas
une fois devrait ensuite cliquer pour chaque lot restant, micro dans l'autre main.

**Les boutons de service s'effacent** pendant le spectacle (18 % d'opacité, pleins
au survol) : « Rejouer l'animation » au milieu d'une annonce de lot fait amateur.

**Rouvrir l'écran ne montre plus les gagnants.** Tant que `tirage_revele`
valait `oui`, l'écran de projection déballait le récapitulatif complet — noms et
lots — dès qu'on l'ouvrait. Or c'est cet écran-là qui est branché au
vidéoprojecteur **avant** le lancement : une répétition non remise à zéro, et
toute la salle lisait les quinze gagnants avant la première annonce. Relevé par
Bastien le 16 septembre : *« avant de lancer le tirage on projettera exactement
ça, donc si y'a déjà le nom des gagnants c'est con »*.

Un écran de garde le remplace : **le nom du spectacle, et trois boutons** —
*Afficher le récapitulatif*, *Rejouer l'animation*, *Quitter la projection*.
Ni titre ni explication : la première version affichait « 15 gros lots
attribués » et une phrase disant pourquoi les noms étaient cachés, ce qui
apprenait déjà à la salle que tout était joué. Le pourquoi se lit dans le code,
pas sur le mur.
**Les cartes ne sont pas seulement masquées, elles ne sont pas construites** :
vérifié au banc, zéro `.ptk` dans le DOM sur cet écran. Un nom caché par du CSS
reste lisible par qui inspecte la page, et surtout réapparaît au premier accident
de feuille de style — sur un écran géant, ça ne se rattrape pas.

Le récapitulatif reste à **un clic** : l'équipe s'en sert au stand des lots pour
retrouver qui a gagné quoi. Il faut simplement le demander. Et *Rejouer
l'animation* monte la scène avant de lancer, sinon `revelJouer()` ne trouvait ni
`#scene` ni `#ptlot` et rendait la main sans un mot.

> ⚠️ **Rien ne change à la fin d'un spectacle joué en direct** : le tableau se
> remplit sous les yeux de la salle, c'est le bouquet. La garde ne s'applique
> qu'à la RÉOUVERTURE d'un tirage déjà révélé.

**Le récapitulatif final tient d'un seul écran** — 4 colonnes, garage en gros et
lot en légende, un filet d'or à gauche pour les cartes sorties. Vérifié à
1 280 × 720 : aucune barre de défilement, ni de page ni interne. Une barre de
défilement sur un vidéoprojecteur veut dire que la moitié de la salle ne verra
jamais son nom.

**L'animation ne rappelle jamais la base** : un seul appel au lancement, puis tout
se déroule dans le navigateur. Vérifié en traçant `fetch` — zéro requête pendant
la minute de spectacle.

> **Garde-fou de scène, trouvé en mesurant.** Un navigateur bride `setTimeout` à
> ~1 Hz dès que l'onglet passe en arrière-plan : les 21 sauts de la roulette
> s'étalaient alors sur **21 secondes au lieu de 2,6**. La roulette se cale donc
> sur `performance.now()` et s'arrête net au temps imparti, quoi qu'il arrive au
> minuteur. Sans ça, quelqu'un qui bascule de fenêtre en pleine annonce enlisait
> le spectacle.

> ⚠️ **Jamais éprouvé sur un vrai vidéoprojecteur.** Vérifié au navigateur à
> 800 px et à 1 280 × 720, mais ni sur écran géant, ni dans une salle éclairée,
> ni avec le rendu couleur d'un projecteur. La taille du nom et le contraste du
> fond violet ne se jugent qu'en salle.

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

### Les 6 animations — le barème du prestataire, recalibré

PIN `1001` à `1006`, coût de participation **2 points**.
`sql/22_bareme_prestataire.sql` remplace les paliers inventés du 11 septembre par
ceux que le prestataire de l'animation a réellement écrits, ramenés sur notre
échelle.

**La règle tient en une phrase : une animation plafonne à une demi-case.** Une
case coûte 20 points, le plus beau coup de la journée en rapporte 10 — il en faut
deux pour s'offrir une case.

**Cinq valeurs, et cinq seulement : 10 · 5 · 3 · 2 · 0.** Pas de 6, pas de 12, pas
de 16. Un animateur qui annonce « +5 » par-dessus la sono se fait comprendre du
premier coup ; « +16 » se fait répéter. Un contrôle SQL refuse le fichier si un
palier sort de ces cinq valeurs.

**Le palier le plus bas vaut 2, soit exactement la participation.** D'où la seule
explication que le jeu demande, et que l'animateur peut crier :
*« tu marques quelque chose, tu ne perds rien ; tu ne marques rien, ça t'a
coûté 2 »*.

| Jeu | Résultat | Presta | Nous |
|---|---|---|---|
| **ATELIER PÉTANQUE** | Tir · 3 boules sur 3 | 10 | **10** |
| | Tir · 2 boules sur 3 | 5 | **5** |
| | Pointeur · 3 cerceaux | 5 | **5** |
| | Pointeur · 2 cerceaux | 3 | **3** |
| | Tir · 1 boule sur 3 | 2 | **2** |
| | Pointeur · 1 cerceau | 1 | **2** |
| | Rien de marqué | — | **0** |
| **CORN HOLE** | 3 / 2 / 1 sachet sur 3 | 8 / 4 / 2 | **10 / 5 / 2** |
| | Aucun sachet | — | **0** |
| **FLÉCHETTES** | Centre rouge | 6 | **10** |
| | Centre vert ou triple annoncé | 3 | **5** |
| | *Les 3 fléchettes dans la cible* | *—* | ***2*** |
| | À côté | — | **0** |
| **BORNE D'ARCADE** | Niveau 1 de Pac-Man terminé | 6 | **5** |
| | Niveau 1 non terminé | — | **0** |
| **BASKET ARCADE** | Meilleur score du moment | 4 | **5** |
| | *Score honorable* | *—* | ***2*** |
| | Petit score | — | **0** |
| **BLAZZPOD** | idem basket | 4 | **5 / 2 / 0** |

**Pourquoi les plafonds ne sont plus égaux d'un jeu à l'autre.** L'ancienne règle
imposait 20 partout pour que la halle ne fasse pas la queue au même endroit —
mais elle tenait parce que les six jeux étaient notés au doigt mouillé et se
valaient par défaut. Le prestataire, lui, a calibré la **difficulté**. Les trois
jeux où l'exploit est rare (les 3 boules au tir, les 3 sachets, le centre rouge)
plafonnent à 10 ; les trois où le bon résultat est courant plafonnent à 5. Payer
pareil un coup rare et un coup couru d'avance, c'est ce qui vide un stand. Et ce
qui répartit vraiment la foule, c'est le **débit** : 45 s le basket, plusieurs
minutes le niveau 1 de Pac-Man.

**Les noms des six animations n'ont pas bougé.** Le prestataire écrit
« PETANQUE » et « BORNE ARCADE », la base dit « ATELIER PÉTANQUE » et
« BORNE D'ARCADE » — et ce sont ces noms-là qui sont **imprimés** sur les
6 badges animateur, avec les PIN 1001 à 1006.

> ⚠️ **Deux paliers en italique sont des marque-places**, à confirmer à la
> répétition. « Les 3 fléchettes dans la cible » a été ajouté parce que le
> prestataire ne donne que deux paliers, tous deux hors de portée d'un garagiste
> un verre à la main : l'espérance du jeu tombait sous les 2 points de
> participation et le stand se serait vidé en une heure. **Un troisième palier a
> été demandé au prestataire.**

> ⚠️ **« TOP SCORE EN 45 SECONDES, 4 PTS À GAGNER » n'est pas un barème.** La
> phrase donne un plafond, aucun seuil, et l'application a besoin de paliers :
> l'animateur choisit un résultat, il ne saisit pas un nombre. L'hypothèse
> retenue est que l'animateur écrit le score à battre sur son ardoise. **Si
> c'est en réalité un classement journalier, il faut du code, pas une ligne de
> SQL.**

### L'économie des points — un modèle, pas une mesure

Hypothèse uniforme sur les paliers de chaque jeu, la même dans les deux colonnes
pour que la comparaison vaille quelque chose.

| Source | Hypothèse | Avant | Depuis le 15/09 |
|---|---|---|---|
| Bonus d'arrivée | | 10 | 10 |
| Animations | 4 jouées sur 6, **net du coût** | ~27 | **~5** |
| Fournisseurs | 4 stands sur 23, ~10 pts | ~40 | ~40 |
| **Total par garage** | | **~77** | **~55** |
| **En cases à 20 pts** | | 3,9 | **2,8** |

Le **plafond de cases par garage** (`config.cases_max_garage`), passé de 3 à
**5** le 15 septembre, tient donc toujours : un garage type arrive juste au-dessous, et 150 à 212 garages demandent
420 à 590 cases pour 200 disponibles. La grille se vide quand même, et c'est le
plafond qui la rationne. Il **se lève** en direct et ne se baisse jamais —
baisser pénaliserait ceux qui ont déjà acheté.

**Les animations ne financent plus la grille.** Elles pesaient 35 % des points
d'un garage, elles en font maintenant **9 %** : ce sont les 23 stands
fournisseurs qui la financent. C'est cohérent avec le nom de l'événement, et
c'est un choix assumé, pas un effet de bord. *Décision de l'utilisateur,
verbatim : « les mecs crament 2 points sur une partie et repartent avec beaucoup
trop de point je trouve ».*

**Trois jeux sortent à zéro net en moyenne** — Pac-Man, basket, Blazzpod. Un
garage qui les enchaîne ne gagne rien et ne perd rien : ce sont devenus des jeux
pour le plaisir. Volontaire — ce sont les trois où le résultat est le plus sûr,
donc les plus faciles à enchaîner.

> ⚠️ Ce tableau est un **modèle**. Aucune donnée de terrain de l'édition
> précédente ne l'étaye, et les taux de réussite réels des six jeux ne sont pas
> mesurés. Le nombre de stands qu'un garage visite est la variable la plus
> incertaine, et c'est celle qui pèse le plus.

> **Le curseur, c'est le plafond d'une animation.** S'il faut que les jeux
> paient davantage, il est à 10 et se remonte en une ligne — le contrôle SQL le
> borne à la moitié de `cout_grille`.

### Les règles du jeu, une version par profil

Ajoutées le 15 septembre. Un bouton **Règles** dans la barre des cinq écrans de
profil, qui ouvre un mode d'emploi et rend la main exactement où on était — au
milieu d'une file d'attente, on ne veut pas avoir à retrouver son garage.

**Pourquoi pas une page commune.** Un garagiste n'a rien à faire des quotas de
stand, un représentant se moque de la grille à 200 cases. Une page pour tout le
monde, c'est une page que personne ne lit jusqu'au bout. Chacun voit son mode
d'emploi en quatre ou cinq temps, et rien d'autre.

| Profil | Ce qu'il lit |
|---|---|
| Garage | son code, gagner, dépenser, retirer, le ticket d'or |
| Animateur | chercher, lancer, noter, le quota |
| Fournisseur | chercher, choisir le palier, valider, le quota |
| Hôtesse | chercher, lire le code, que faire d'un absent de la liste |
| Équipe Bony | la console, la remise, les tickets, le tirage, l'export horaire |

**Les chiffres viennent de la base, pas du texte.** Le coût d'une case, le
plafond de cases, la participation : tout est lu dans la réponse de l'API. Si
Bony change `cout_grille` en direct, les règles changent avec — sinon elles
mentiraient dès la première journée, et des règles qui mentent sont pires que
pas de règles.

**Les pictos sont du SVG en ligne, au trait.** Pas d'emoji — leur dessin change
d'un téléphone à l'autre et certains sortent en noir et blanc. Pas d'image non
plus : un fichier de plus à charger sur le wifi d'une halle, pour un dessin de
vingt lignes.

### Les quotas par garage — les freins anti-abus

Ajoutés le 15 septembre (`sql/26_quotas.sql`), à la demande de Bony.

| Frein | Valeur | Ce qu'il protège |
|---|---|---|
| Cases par garage | **5** (était 3) | « il en faut pour tout le monde » |
| Points d'UNE animation | **4 × son meilleur palier** — 20 ou 40 pts | le garage qui camperait devant une borne |
| Points d'UN stand | **3 × le plafond d'opération** — 60 pts | le fournisseur généreux avec un ami |

**Le refus tombe au LANCEMENT de la partie, pas au résultat.** `api_participation`
débite 2 points avant qu'on note le résultat : si le refus arrivait au résultat,
le garage aurait payé sa partie pour s'entendre dire qu'il n'a droit à rien. Le
résultat est quand même contrôlé, en ceinture, pour un résultat envoyé sans
participation (rejeu, file hors ligne).

**La dernière partie a le droit de dépasser.** Un garage à 38/40 qui lance et
fait un carreau touche ses 10 points et finit à 48. Le quota est un frein à la
répétition, pas une règle comptable — couper un gain en deux serait
incompréhensible au stand.

**L'équipe Bony n'est pas soumise aux quotas** : le rôle `admin` corrige et
compense, le bloquer avec un frein anti-abus lui retirerait l'outil au moment où
il en a besoin.

Les deux multiplicateurs sont dans `config` et se règlent en direct :
`quota_animation_x` (4) et `quota_stand_x` (3).

L'animateur et le fournisseur voient un **bandeau or persistant** — pas un toast
de quatre secondes qui disparaît pendant qu'ils relisent le nom du garage. Il
s'efface dès qu'ils passent au garage suivant.

### Travaux techniques identifiés, non faits

**A. Les six garages à code de test.** `GRND`, `BNY2`, `TEST`, `BAL2`, `FRUM`,
`JEUX` sont posés à la main sur de vrais clients. Deux conséquences : ces six-là
ont un code devinable, et si l'emailing est fabriqué depuis `sql/10_garages.sql`
plutôt que depuis la base, ils recevront un code qui ne marche pas. **Proposition
faite, décision en attente** : leur rendre leur code généré et faire chercher les
garages de test par numéro de compte. ~20 minutes.

**B. ~~Le ping anti-veille.~~** Sans objet : le projet est touché tous les jours
depuis le 11 septembre, et l'événement est le 17. *Verbatim de Bastien : « osef,
c'est dans 2 jours l'event ».*

**C. La gigue sur le sondage.** Les téléphones qui démarrent ensemble sondent
ensemble. La simulation dit que 300 req/s de pointe passent sans un échec, et le
banc de rupture que 800 simultanées aussi : **ce n'est pas nécessaire.** Dix
lignes si le besoin apparaissait un jour.

**D. Le mode hors ligne sur un vrai téléphone en mode avion.** Jamais fait, et
**ne le sera pas** : *« on en a pas besoin, donc c'est un plus que je ne
testerai pas ».* Le code est en place et les écritures partent bien en file ;
c'est le comportement réel sur un téléphone qui n'est pas éprouvé.

**E. `SAINT SULPICE L APOI`, CP 15310.** Non identifié, laissé intact.

**F. Les seuils des trois jeux à score.** BASKET ARCADE et BLAZZPOD ont un palier
intermédiaire (« Score honorable », 2 pts) qui est un **marque-place** : le
prestataire n'a donné qu'un plafond, pas de seuil. L'animateur écrit le score à
battre sur une ardoise et note par rapport à lui — **consigne à donner de vive
voix, elle n'est nulle part ailleurs.** Même chose pour le troisième palier des
fléchettes, « Les 3 fléchettes dans la cible » à 2 pts, ajouté parce que les deux
seuls paliers du prestataire faisaient perdre des points au jeu en moyenne.

---

## 12. Les commandes

```powershell
# Envoyer un fichier SQL, ou une requête directe
.\scripts\push-sql.ps1 -File sql\01_schema.sql
.\scripts\push-sql.ps1 -Query "select count(*) from garages" -Quiet

# Les trois batteries de tests — 114 contrôles, à rejouer après tout changement SQL
.\scripts\test-porte.ps1        # 53 : la porte, le frein, les 31 PIN, les collisions
.\scripts\test-invariants.ps1   # 32 : double crédit, quotas, solde négatif, plafonds, paliers
.\scripts\test-bingo.ps1        # 29 : les deux modes, la revelation, 200 cases, plafond

# Serveur local (le service worker ne fonctionne pas depuis file://)
.\scripts\serveur.ps1                                   # l'application, http://localhost:8123
.\scripts\serveur.ps1 -Dossier presentation -Port 8125  # les deux présentations

# Dimensionnement
.\scripts\mesurer-charge.ps1    # coût unitaire, taille du pool, rythme d'une soirée
.\scripts\trouver-plafond.ps1   # rafale montante jusqu'à la rupture

# LA SIMULATION — une journée entière par l'API réelle, jusqu'à ce que les
# 200 cases soient prises. SANS -Appliquer elle n'écrit RIEN.
# ⚠️ Avec -Appliquer elle REMET LA BASE À ZÉRO, puis la remplit. Il faut
#    relancer 99_remise_a_zero.sql après.
.\scripts\simuler-forum.ps1
.\scripts\simuler-forum.ps1 -Appliquer

# LE JOUR J
.\scripts\diagnostic.ps1        # « est-ce la base, ou la couche devant ? »
.\scripts\exporter-journal.ps1  # journal, soldes et lots en CSV — toutes les heures

# 🔴 REMISE À ZÉRO — obligatoire avant le Forum, et après toute répétition.
#    Elle efface les achats, le journal, les soldes et les appareils ; elle
#    PRÉSERVE la composition de la grille (100 lots, 15 tickets d'or).
.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql

# Réimporter les garages depuis l'export Sarbacane
.\scripts\importer-garages.ps1  # régénère sql\10_garages.sql

# LES BADGES — normalement on double-clique l'icône du Bureau. Voir §15.
.\scripts\creer-raccourci.ps1   # (re)poser l'icône, une fois, ou apres deplacement
.\scripts\badges.ps1 -Visible   # le lanceur avec la console, pour diagnostiquer
.\scripts\exporter-badges.ps1   # rafraichir participants.json sans ouvrir l'app
.\scripts\generer-polices.ps1   # refabriquer polices.css (seulement si on change de police)

# Pousser un listing d'inscrits dans la base. SANS -Appliquer il n'ecrit RIEN :
# il lit, rapproche et rend un rapport qu'on regarde avant de le laisser ecrire.
.\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx"
.\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx" -Appliquer
```

### Après chaque `git push`

1. incrémenter `VERSION` dans `app/sw.js` ;
2. vérifier la version réellement servie (§9) — **les builds ont déjà échoué en
   silence deux fois**.

---

## 13. Les codes

> ⚠️ **LES 31 PIN SONT DÉFINITIFS DEPUIS LE 15 SEPTEMBRE.** Les anciens — 9137,
> 4200, 1001-1006, 2001-2023 — étaient des codes de démonstration **et ils
> étaient séquentiels** : qui lisait « 2001 » au dos d'un badge retourné ouvrait
> les vingt-trois stands en comptant jusqu'à 2023. Ils ne valent plus rien.

| Profil | Combien | Où le lire |
|---|---|---|
| Supervision Bony | 1 | `sql/24_pins.sql` — **sur aucun badge**, ne se remet à personne |
| Poste d'accueil | 1, **partagé par les deux hôtesses** | `sql/24_pins.sql` |
| Les 6 animations | 6 | `sql/24_pins.sql`, et au verso du badge de chaque animateur |
| Les 23 stands | 23, **chacun partagé par les 5 badges du stand** | idem |

**La liste lisible est dans `exports/Codes personnel Forum 2026.xlsx`** — hors
dépôt, comme tout ce qui porte un code. Les valeurs elles-mêmes sont dans
`sql/24_pins.sql`, versionné : c'est la même décision que pour
`sql/10_garages.sql`, qui porte les 1 457 codes garage depuis l'origine. Le dépôt
est privé, et il doit le rester.

**La garantie anti-collision est structurelle.** L'alphabet des codes garage
exclut 0, 1, O et I ; un PIN qui contient un 0 ou un 1 ne peut donc PAS heurter
un code garage — impossible par construction, pas improbable. Les 31 en
contiennent tous un, et `sql/24_pins.sql` refuse de passer si ce n'est pas le
cas. `verifier_portes()` le recontrôle : **0 collision sur 1 457 codes garage et
31 PIN.**

Garages de démonstration : `GRND`, `BNY2`, `TEST`, `BAL2`, `FRUM`, `JEUX`.
**Ce sont de vrais clients** — voir « Travaux techniques identifiés, non faits »
au §11.

> Les « cases truquées » qui figuraient ici jusqu'au 11 septembre n'existent
> plus : la grille porte les 100 vrais lots depuis `sql/18_lots.sql`, et
> l'affectation case ↔ lot est **scellée** (§11).

`.env.local` contient les accès Supabase et **n'est pas versionné**. Il faudra le
recopier à la main sur le nouveau poste : URL, `SUPABASE_PROJECT_REF`,
`SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_ANON_JWT`,
`SUPABASE_SERVICE_ROLE_JWT`, `SUPABASE_ACCESS_TOKEN` (le PAT `sbp_`).

### Ce qui porte des codes, et qui reste sur le poste

| Fichier | Pourquoi il est hors dépôt |
|---|---|
| `.env.local` | les accès Supabase |
| `exports/` | journal, soldes et lots — noms de garages et codes de retrait |
| `badges/participants.json` | les 516 badges avec leur code, lu par le générateur |
| `badges/marques.json` | ce qui a déjà été imprimé — local à la machine |
| `badges/_etat.json`, `_export-etat.json`, `_journal-lancement.txt` | traces de lancement |
| `Badges — Forum 2026.lnk` | le raccourci, il porte un chemin absolu |

> **Deux fichiers versionnés contiennent malgré tout des codes** :
> `sql/10_garages.sql` (les 1 457 invités, décision d'origine) et
> `sql/20_inscrits.sql` (les inscrits, avec e-mails et téléphones). C'est
> cohérent avec le premier, mais le second ajoute des numéros de téléphone. Le
> dépôt est privé ; si ce n'est pas acceptable, une ligne de `.gitignore` suffit
> — au prix de la reproductibilité de l'import.

---

## 14. Les livrables annexes

- **`presentation/direction.html`** — diaporama de 14 diapositives pour la
  direction Bony, à la charte de l'application, avec les cinq interfaces en
  maquette. Publié en artefact privé. **Ne contient volontairement aucun code
  d'accès** : une présentation se partage.
- **`presentation/agents.html`** — **7 diapositives** pour la réunion d'agents
  du matin, projetées sur grand écran. Même charte, mais **tout est monté d'un
  cran** : les échelles typographiques et les maquettes de téléphone, qui
  passent de 238 à 320 px avec leurs textes internes agrandis d'autant. Ce qui
  se lit à un mètre sur un portable ne se lit pas au fond d'une salle de
  réunion. Quatre maquettes d'écran : entrée, espace garage, grille, ticket d'or.

  **Ramené de 12 à 7 le 16 septembre** — *« faut me la condenser, c'est trop
  long, et y'a un peu trop de textes par endroits »*. « Ce qui change » a fondu
  dans « l'entrée », « les animations » dans « gagner des points », « le
  verdict » dans « la grille », « à retenir » dans la clôture. « La journée en
  quatre temps » a été supprimée : elle redisait le reste du dossier dans
  l'ordre. **Sept est un plafond** : avant d'ajouter une diapositive, en
  retirer une. Une réunion d'agents dure vingt minutes.

  La clôture disait **« À jeudi »** — une faute, relevée par Bastien : la
  réunion se tient le matin même du Forum. On ne donne pas rendez-vous à un
  jour où l'on est déjà. Elle dit maintenant « Et maintenant, place au Forum »,
  et porte les trois choses à retenir.

  Vérifié à **1 280 × 720, 1 366 × 768 et 1 920 × 1 080** : les sept
  diapositives tiennent dans la hauteur, centrées, sans défilement interne ni
  débordement horizontal. La plus serrée garde 65 px de marge haut et bas.

  On y parle à des garagistes : aucune architecture, aucun chiffre de charge,
  aucun coût. Trois questions, et rien d'autre — comment j'entre, comment je
  gagne, qu'est-ce que je gagne.

  **Aucun code d'accès, et aucun numéro de case réel.** Le code montré dans les
  maquettes est `BAL1` : il contient un 1, or l'alphabet des codes garage exclut
  0, 1, O et I — il ne peut donc appartenir à personne, par construction. La
  grille de démonstration est un décor plausible, pas la vraie répartition : la
  présentation se donne le matin même, devant ceux qui vont jouer.

  Les flèches, PageUp/PageDown et l'espace naviguent : on ne veut pas découvrir
  en réunion que la télécommande du vidéoprojecteur ne fait rien.

  `wrangler.jsonc` ne sert que `app/` : les présentations ne sont **jamais
  déployées**. Elles s'ouvrent en double-cliquant le fichier, ou par
  `.\scripts\serveur.ps1 -Dossier presentation -Port 8125`.
- **`maquette-grand-bal-points.html`** — la maquette cliquable d'origine, à la
  racine. Historique, plus maintenue.
- **`exports/`** — sortie de `exporter-journal.ps1`, **ignorée par git** (contient
  les codes d'accès des garages).
- **`badges/`** — le générateur de badges. Voir **§15**, il a sa propre section.

---

## 15. Le générateur de badges

Ajouté les 14 et 15 septembre 2026. Il fabrique les badges A6 recto/verso que
tout le monde porte au cou le jour J : garages, exposants, animateurs, hôtesses,
équipe Bony, et constructeurs le moment venu.

**Il s'ouvre par son icône « Badges — Forum 2026 » sur le Bureau**, pas par une
commande. Bastien n'est pas développeur et l'a dit sans détour : *« je veux une
app, pas du bricolage »*.

### Ce qu'il est, en une phrase

Une page statique qui **lit la base et n'écrit rien**, servie en local par un
petit serveur PowerShell, affichée dans une fenêtre Chrome en mode application,
et qui fabrique de vrais PDF sur le disque.

```
icône du Bureau
   └─ wscript  scripts\badges-silencieux.vbs      (aucune console ne clignote)
       └─ powershell  scripts\badges.ps1          (caché)
           ├─ scripts\exporter-badges.ps1         lit la base -> participants.json
           ├─ scripts\serveur-badges.ps1          sert badges\ + 4 routes d'API
           └─ chrome --app=http://localhost:8124  la fenêtre
               └─ à sa fermeture, tout s'arrête
```

**Il n'est jamais déployé.** `wrangler.jsonc` ne sert que `app/`, et un badge
porte le code d'accès de son porteur.

### Le virage du 14 septembre — à comprendre avant tout

Le générateur croisait d'abord deux sources : les 1 457 invités en base, et les
fichiers d'inscription. Le fichier consolidé de Bastien a montré que ce
croisement ne pouvait pas marcher : **l'identifiant d'invitation n'est pas une
clé.** `BONY00250` a servi à trois sociétés successives (onglet `TRANSFERTS_ID`)
et des salariés Bony se sont inscrits via le lien d'un client
(`ID_MAUVAISE_CIBLE`). Rapprocher là-dessus attribuait à quelqu'un le code d'un
autre garage.

> *Verbatim : « c'est une vraie merde ça se croise super mal avec nos inscrits ».*

Depuis : **la base porte la liste des inscrits**, le rapprochement se fait **une
seule fois, à l'écriture**, et **le générateur ne fait plus que lire**. Tout
l'import Excel a été retiré de l'outil. C'est la décision structurante ; ne pas
la défaire sans relire ce paragraphe.

### Les 1 457 invités restent en base, et c'est volontaire

`garages` n'est pas un carnet d'adresses : **`garages.code` EST le contrôle
d'accès**. Un garagiste qui se présente sans s'être inscrit doit pouvoir entrer.
L'hôtesse le retrouve et lui lit son code — `sql/09_accueil.sql` sait déjà le
faire, il n'y avait rien à construire — et lui remet un badge vierge à remplir
au marqueur. Le générateur, lui, ne voit que les inscrits.

### Le modèle

`sql/19_participants.sql` :

- **`participants`** — qui porte un badge. Catégorie, raison sociale, prénom,
  nom, nombre de badges, et un rattachement vers `garages`, `stands` ou
  `animations`. **Aucun code n'y est recopié.**
- **`v_badges`** — la vue que lit le générateur. Elle résout le code à la
  lecture : `code_force`, sinon `garages.code`, sinon `stands.code_pin`, sinon
  `animations.code_pin`, sinon `config.pin_accueil` pour les hôtesses. Changer
  un PIN met donc à jour les badges concernés **sans toucher une seule ligne**
  de `participants` — la décision n°4 reste jouable jusqu'au dernier moment.
- **`verifier_badges()`** — rend une ligne par badge qui sortirait sans code
  utilisable. À lancer après chaque import. Doit rendre zéro ligne.

RLS active, zéro policy, aucun `grant` : l'application ne connaît pas cette
table, seul le générateur la lit, en local, par l'API de management.

`cle_source` (l'e-mail, sinon la personne) porte l'idempotence, comme `cle_idem`
dans le journal : repousser le même listing **met à jour** au lieu de créer un
second badge par personne.

### Comment on remplit la table

**Garages et équipe Bony** — depuis le listing consolidé de Bastien :

```powershell
.\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx"             # essai a blanc
.\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx" -Appliquer  # ecrit
```

Sans `-Appliquer`, **il n'écrit rien** : il lit, rapproche et rend un rapport.
Il rapproche d'abord sur la **raison sociale** normalisée — formes juridiques
retirées, « GGE » développé en « Garage », « st »/« ste » développés dans cet
ordre comme `norm_requete()` — et l'identifiant ne sert qu'en second recours,
signalé comme tel. Il **ne devine jamais** : les homonymes sont listés à part et
pas importés ; une société franchement absente reçoit un nouveau garage et un
code généré par le même algorithme déterministe que `importer-garages.ps1`.

Mesuré sur le listing consolidé du 15 septembre : 212 inscrits au Forum,
**211 retenus** (3 doublons écartés, 3 homonymes arbitrés en comptes neufs),
**319 badges garage et équipe Bony** — les
115 exposants, 6 animateurs et 2 hôtesses viennent d'ailleurs, voir plus bas.
91 sociétés retrouvées par leur nom, 4 par l'identifiant, 46 créées,
**0 badge sans code utilisable**.

**Exposants, animateurs, hôtesses** — `sql/21_personnel.sql`, pas de fichier :

| | Combien | Ce que porte le badge |
|---|---|---|
| Exposants | **5 par stand**, 23 stands = 115 | le nom du stand, pas de nom de personne |
| Animateurs | **1 par jeu**, 6 jeux | `BASKET ARCADE` / `Animateur 1` |
| Hôtesses | **2** | `Accueil` / `Hôtesse 1` et `2` |

Les libellés sont **ceux de Bony**, pas ceux de la base : « TOTAL ELF » plutôt
que « ELF », « AGENTS » plutôt que « AGENT ». Le rattachement, lui, se fait sur
le nom en base, qui porte le PIN.

> `importer-inscriptions.ps1 -Categorie EXPOSANT` sait aussi importer un listing
> nominatif de fournisseurs, en rattachant chaque personne à son stand. Le mode
> est écrit et essayé — 48 personnes, 29 entreprises, 39 rattachées — mais **il
> n'est pas utilisé** : Bastien a préféré 5 badges interchangeables par stand.
> Il resservira le jour où les exposants voudront leur nom.

**Collaborateurs Bony et constructeurs** — `sql/27_collaborateurs.sql`, poussé le
16 septembre depuis « LISTING INVITATION COLLABORATEURS BONY — FORUM —
SEPTEMBRE 2026 ». Deux onglets, deux catégories :

| Onglet | Lignes | Ce qui en est sorti |
|---|---|---|
| `bony` | 116 | 60 déjà en base depuis le 15, **55 ajoutés**, 1 écarté |
| `renault` | 21 | **21 constructeurs**, dont 2 basculés depuis `GARAGE` |

**Pourquoi un fichier SQL et pas `importer-inscriptions.ps1`.** L'importateur
existe pour rapprocher un inscrit de SON GARAGE, sur la raison sociale. Ce
listing n'a pas de colonne société, et personne dedans n'a de garage : ce sont
des salariés et des invités constructeur. Il n'y a rien à rapprocher, seulement
à écrire — l'outil refuserait d'ailleurs le classeur, faute d'en-tête
« raison sociale ».

**Les noms déduits d'une adresse.** 25 lignes n'ont ni nom ni prénom : tout
l'onglet `renault` et quatre collaborateurs. On les tire de la partie locale
(`prenom.nom@`), en traitant un jeton du milieu d'une ou deux lettres comme une
initiale de désambiguïsation — `jean-luc.j.bisch` donne Jean-Luc BISCH.

> ⚠️ **Les accents ne sont jamais inventés.** Un prénom n'est accentué que si
> Bony l'a elle-même écrit ainsi ailleurs dans CE classeur : « Théo »,
> « François », « Rémi », « Jérome » y sont attestés et repris tels quels — y
> compris « Jérome » sans circonflexe, qui est la graphie de Bony. Deux prénoms
> restent sans accent faute d'attestation, **Gerard GROS et Herve MOREAU** :
> deux `update` d'une ligne si quelqu'un connaît la bonne graphie. Un badge mal
> orthographié se remarque plus qu'un badge sobre.

**Trois corrections portées par ce fichier.**

1. **Franck TIXIER portait le badge de Thierry DUBERNAT.** L'import du 15 avait
   écrit « Thierry DUBERNAT » sur la ligne dont l'adresse est
   `franck.tixier@`. Le listing du 16 départage les deux : chacun a la sienne.
2. **Un garage fantôme « RENAULT » (code `93T5`) a été désactivé.** Il avait été
   fabriqué le 15 pour héberger Jean-Luc BISCH et Thierry WINTZENRIETH, qui
   s'étaient inscrits par le lien d'un client — le cas `ID_MAUVAISE_CIBLE`. Sans
   cette désactivation et sans le `garage_id = null` du `on conflict`, leur
   badge « Constructeur » serait sorti avec un code jouable, et deux invités
   Renault auraient pu acheter des cases. ⚠️ Ne pas confondre avec
   « Renault lezoux » (`2869`), qui est un agent du réseau et reste actif.
3. **Johann DUMAS n'a pas été ajouté deux fois.** Le listing l'écrit
   `@bonyautomobiles.com`, la base le connaît `@bonyauto-mobile.com` : deux
   graphies de domaine pour une seule personne. `cle_source` étant l'adresse,
   l'import aurait créé un second badge à son nom. Emmanuel PAPON porte la même
   graphie de domaine, sans équivalent en base : il entre tel quel.

**Trois doublons de personne restent en base, et c'est volontaire.** Ils datent
de l'import du 15, pas de celui-ci ; les retirer ferait perdre un badge ou un
code à quelqu'un la veille du Forum, et c'est un arbitrage de Bastien, pas une
correction technique :

| Qui | Ce qu'il y a | Effet |
|---|---|---|
| Denis FOSSIEZ | deux inscriptions, `contact@` et `denis.fossiez@` | 2 badges, **même garage et même code** — un badge de perdu, rien d'autre |
| Grégory MICHEL | « Michel » (Clermont, 2 badges) et « MICHEL AUBIERE » | 3 badges, 2 codes — plausiblement deux établissements |
| Franck TIXIER | ligne `EQUIPE_BONY` + ligne `GARAGE` sur « Espace automobile d'Auvergne » (`F52B`) | 2 badges, dont un code jouable. Son adresse était tapée `bonyhauto-mobile.com` : l'import du 15 ne l'a pas reconnue comme une adresse Bony |

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

### Les agents sortent en tête du PDF

Demande de Bastien le 16 septembre : *« Agents de A à Z puis reste des garages
de A à Z »*. La réunion d'agents a lieu le matin, avant le Forum : cette pile-là
se distribue en premier et doit pouvoir se séparer d'un geste au massicot.

**Mesuré** sur la catégorie Garage : 248 badges, dont **77 agents en tête, soit
les 39 premières feuilles** — le générateur affiche ce chiffre, pour qu'on n'ait
pas à recompter le tas debout devant l'imprimante. Les deux moitiés sont triées
A→Z chacune de son côté.

> ⚠️ **La lettre de profil ne répond pas à la question.** `garages.profil` vient
> du fichier Sarbacane et dit qui a été **invité** à quoi — `A` Réunion + Forum
> (Agent Historique), `B` Réunion + Visite + Forum (Agent BSO), `C` Forum,
> `D` Visite + Forum. Être invité n'est pas être inscrit, et le tri par lettre
> donnait une pile fausse dans les deux sens : **18 agents inscrits** sont
> rattachés à un garage de profil `INSCRIT` — créé par l'import du 15, lettre
> inconnue — et seraient restés au fond du tas ; **2 garages de profil A** ne
> se sont pas inscrits à la réunion et seraient montés dans la pile du matin
> pour rien. 33 lignes par la lettre contre **51 par l'inscription réelle**.

La source est donc la colonne **« Réunion »** du consolidé du 15 septembre
(onglet `INSCRITS_CONSOLIDES`), figée dans `participants.reunion_agents` par
`sql/28_reunion_agents.sql` et exposée par `v_badges`. Elle vaut « oui » pour
92 adresses, dont 89 portent un badge : 51 garages, 36 Équipe Bony, 2
constructeurs. Les trois autres viennent à la réunion mais pas au Forum.

> Les 55 collaborateurs arrivés par le listing du 16 (`sql/27`) ne sont **pas**
> marqués : ce fichier-là donne le profil d'**invitation**, pas l'inscription.
> Les marquer mélangerait deux choses sous un même drapeau. Ceux d'entre eux
> qui s'étaient inscrits par le formulaire sont déjà couverts.

**Avec « un PDF par lettre initiale »**, les deux séries restent deux tas :
`badges-garage-agents-a`… puis `badges-garage-reste-a`… Le préfixe `reste-`
n'est pas décoratif — avec la lettre nue, `badges-garage-a` se classait **avant**
`badges-garage-agents-a` dans l'Explorateur (le tiret vaut moins que le `g`) et
les deux piles s'entrelaçaient au moment de tout sélectionner pour imprimer.
Une catégorie sans aucun agent garde la lettre nue : rien ne change pour les
exposants, les animateurs et les hôtesses.

### La mécanique papier

**Une feuille A4 = deux badges.** Recto à gauche, verso à droite. On coupe la
feuille en deux dans la largeur, on plie chaque bande sur le trait du milieu en
rabattant le verso **derrière** le recto.

Pourquoi ce montage plutôt qu'un recto-verso d'imprimante : replier puis
retourner la carte autour de l'axe vertical sont deux rotations qui s'annulent,
le verso se lit donc à l'endroit, sans miroir. Et l'impression reste en **simple
face**, donc aucun décalage de calage duplex — un décalage de 1 à 3 mm est
invisible tant qu'on n'a pas imprimé, et très visible sur un bandeau de couleur.

### Le dessin

Fond blanc — exigence de Bastien, *« sinon à l'impression ça va être l'enfer »*.
La charte tient par une **guirlande de fanions** alternant la couleur de la
catégorie et l'or, un **bandeau en dégradé**, un **filet orné d'un losange**, le
blason en dégradé or, et « Le Grand Bal des Fournisseurs » en **Petit Formal Script** —
la note de grâce de la charte, une par face. La commune a été retirée du badge
le 14 septembre.

> **TOUT CE QUI EST COLORÉ EST DU SVG, JAMAIS UN FOND CSS.** Un navigateur qui
> imprime peut décider de ne pas imprimer les `background` : le bandeau
> sortirait blanc sur blanc sans que rien ne prévienne. Un
> `<rect fill="url(#grad)">` est du **contenu**, il s'imprime comme une lettre.
> C'est la raison des montages `.bandeau` et `.boite-code`, où un SVG en
> position absolue porte la couleur et le texte est posé par-dessus. Ne pas
> « simplifier » en CSS.

Les dégradés, la guirlande et le QR sont définis **une fois** dans `<defs>` et
repris par `<use>` : à 516 badges, recopier le tracé à chaque exemplaire ferait
des mégaoctets de DOM pour un dessin identique.

### L'export PDF

Un bouton, des fichiers sur le disque dans `Documents\Badges Forum 2026`. Le
navigateur fabrique une page HTML autonome par PDF, le serveur la pose sur le
disque et la fait imprimer par un **second Chrome sans fenêtre**
(`--headless --print-to-pdf`). L'export part en **tâche de fond** : `HttpListener`
traite une requête à la fois, et s'il bloquait, la page ne pourrait même plus
demander l'avancement.

Mesuré le 15 septembre, sur les fichiers produits :

| Export | Temps | Pages |
|---|---|---|
| Garage, 250 badges | 5 s | 125 |
| Exposant, 115 badges | 3 s | 58 |
| Équipe Bony, 69 badges | 3 s | 35 |
| Animation / Hôtesse | 2 s | 3 / 1 |

Et à l'époque où les 1 457 garages y étaient tous : **17 s** pour un PDF de
704 pages, 38 s pour les mêmes en 27 PDF par lettre initiale.

Vérifié **sur les fichiers**, pas à l'œil : toutes les pages à
**209,89 × 297,01 mm**, **cinq polices réellement incorporées**, et entre 40 et
56 dégradés axiaux par PDF.

### Les fichiers

| Fichier | Rôle |
|---|---|
| `badges/index.html` · `badges.css` · `badges.js` | la page : liste, filtre, aperçu, export |
| `badges/polices.css` | les 6 polices encastrées en base64 — **généré** |
| `badges/polices/*.woff2` | les sources des polices, instances statiques |
| `badges/vendor/qrcode.js` | encodeur QR MIT, version figée, relu avant intégration |
| `badges/icone.ico` · `icone.svg` | le blason Bony, l'icône du raccourci |
| `scripts/badges.ps1` | le lanceur : export, serveur, fenêtre, ménage |
| `scripts/badges-silencieux.vbs` | l'enveloppe wscript, pour qu'aucune console ne clignote |
| `scripts/creer-raccourci.ps1` | pose l'icône sur le Bureau — **une fois** |
| `scripts/serveur-badges.ps1` | sert `badges/` + `marques.json`, `/exporter`, `/ouvrir` |
| `scripts/exporter-badges.ps1` | lit `v_badges` -> `badges/participants.json` |
| `scripts/importer-inscriptions.ps1` | pousse un listing dans `participants` |
| `scripts/generer-polices.ps1` | refabrique `polices.css` depuis les `.woff2` |

**Hors dépôt** (ils portent des codes d'accès ou sont locaux à la machine) :
`badges/participants.json`, `badges/marques.json`, `badges/_etat.json`,
`badges/_export-etat.json`, `badges/_journal-lancement.txt`, et le `.lnk`.

`marques.json` retient ce qui a **déjà été exporté** — une information locale
sur du papier imprimé, qui n'a rien à faire dans la base du Forum et se
reconstruit en une impression si on la perd.

### Neuf pièges payés ici, tous invisibles à l'écran

1. **`Start-Process -ArgumentList` en tableau ne met pas de guillemets.** Le
   chemin `...\APP FORUM\scripts\...` se coupait sur l'espace de « APP FORUM »,
   le serveur mourait sans un mot et le lanceur accusait « un autre programme
   occupe le port ». Passer une **chaîne**, guillemets posés à la main.
2. **Le même `-ArgumentList` aplatit un tableau de tableaux.** La tâche d'export
   recevait trois chaînes au lieu d'un lot et itérait sur leurs caractères :
   elle produisait des fichiers nommés « \ » et « d ». Passer par un fichier
   JSON et un chemin.
3. **`ConvertFrom-Json` en PowerShell 5.1 émet un tableau comme UN SEUL objet**,
   sans l'énumérer. `$x = @(... | ConvertFrom-Json)` l'emballe donc dans un
   tableau à un élément. Avec un seul lot le bug se compensait tout seul ; à
   douze, un seul PDF était écrit et l'interface en annonçait un. Assigner
   **sans** `@()`, et compter avec `@()` au moment de compter.
4. **`$x = if (...) { @(...) } else { @() }` DÉROULE le tableau.** Avec un seul
   élément, `$x` devient l'objet lui-même et `.Count` rend `$null`. Le
   rapprochement des inscrits tombait donc toujours dans la branche suivante —
   sauf pour les homonymes, à deux éléments, qui marchaient et donnaient
   l'illusion que tout allait bien. Affecter **hors** du `if`.
5. **`push-sql.ps1` rendait les accents en mojibake** (« Autos RÃ©publique ») :
   `Invoke-WebRequest.Content` décode selon l'en-tête, que Supabase n'annonce pas
   toujours. Inoffensif tant qu'on regarde, mais le générateur lit cette sortie —
   38 sociétés sur 46 étaient déclarées « absentes de la base » à cause de ça, et
   le mojibake serait parti à l'impression. Corrigé en décodant
   `RawContentStream` en UTF-8.
6. **Un Chrome sans fenêtre n'incorpore pas une police variable dans un PDF.**
   Google Fonts en sert une par défaut. Le premier PDF d'essai n'embarquait
   qu'une police sur deux, tout le texte en Hanken sortait en police de secours,
   et rien ne le signalait. Il faut des instances **statiques**, une par graisse,
   encastrées en base64 : voir `scripts\generer-polices.ps1`. **Contrôle après
   toute modification : le PDF doit contenir cinq `/FontFile2`, pas un.**
7. **Le `viewBox` d'un SVG doit avoir le même rapport que sa boîte CSS**, sinon
   `preserveAspectRatio="meet"` rétrécit le dessin au centre au lieu de
   l'étaler : la guirlande n'occupait que la moitié de la largeur du badge.
8. **Un dégradé en unités `objectBoundingBox` n'a rien à peindre sur un trait
   horizontal**, dont la boîte englobante est de hauteur nulle. Les filets
   étaient purement invisibles pendant que le losange, lui, s'affichait.
9. **`marques.json` rendu comme `[]` au lieu de `{}`** faisait de `MARQUES` un
   tableau côté page, et `JSON.stringify` d'un tableau **jette les propriétés
   nommées** : tout ce qui avait été imprimé était oublié sans un message.

### Les huit arbitrages — tous rendus le 15 septembre

| # | Sujet | Décision de Bastien |
|---|---|---|
| 1 | ~~Figer les PIN~~ | ✅ faits avant impression — `sql/24_pins.sql` |
| 2 | **Feuille d'essai au réglet** | 🟡 à faire avant la série : la carte pliée doit faire 105 × 148,5 mm |
| 3 | **Scanner le QR** | 🟡 jamais lu par un vrai capteur, sur papier, sous des néons |
| 4 | ~~Qui reçoit le code supervision~~ | ✅ **personne.** Il est secret et n'apparaît sur aucun badge |
| 5 | ~~Les trois homonymes~~ | ✅ **un compte neuf au nom de l'inscrit**, les existants intacts |
| 6 | ~~`IXELL` / `MOTRIO`~~ | ✅ **deux fournisseurs sur un stand partagé**, on garde deux entrées |
| 7 | ~~Les deux hôtesses~~ | ✅ **même code**, « ça ne change rien » |
| 8 | **La catégorie `CONSTRUCTEUR`** | 🟡 prête et vide, le listing n'est pas encore à jour |

**Sur le n°5.** *Verbatim : « si homonyme on crée le compte de l'inscrit, et y'aura
un doublon dans la base au cas où un deuxième garage a le même nom dans un lieu
différent ».* `importer-inscriptions.ps1` a donc gagné `-CreerHomonymes` : le
script ne devine toujours pas — il refuse par défaut — mais l'opérateur peut lui
dire de créer un **troisième** compte, avec son propre code, sans toucher aux
deux existants.

| Nouveau compte | Code | Existants laissés intacts |
|---|---|---|
| BOUSQUET | `PH9Y` | Jussac `YCPQ` · Montfranc `7MQS` |
| GARAGE DU STADE | `U2UG` | Aubière `R83R` · Bagnac `B4TQ` |
| GARAGE SAQUET | `HCZF` | La Cavalerie `3KRC` · Nant `YULB` |

**Sur le n°4.** Le code de supervision ouvre la remise des lots, les corrections
et l'écran de projection. L'imprimer sur 69 badges reviendrait à le distribuer à
tout le monde ; le remettre nommément à deux ou trois personnes avait été
envisagé, puis écarté. Il reste dans `sql/24_pins.sql` et dans l'export, et nulle
part ailleurs.

Signalé aussi : un PIN de stand est **partagé par les cinq badges du stand**. Il
est au verso, donc contre la poitrine, mais quelqu'un qui lit `2001` sur un badge
retourné peut ouvrir le stand FAAB sur son propre téléphone.
