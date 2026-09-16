# Le Grand Bal des Fournisseurs — dossier de reprise

> **À lire en entier avant de toucher au code.** Ce document est écrit pour une
> session de travail qui ne connaît rien au projet. Il dit ce qu'est
> l'application, pourquoi elle est construite ainsi, ce qui a été fait, ce qui
> reste, les pièges rencontrés, et la méthode de travail attendue.
>
> Dernière mise à jour : **16 septembre 2026, tard le soir**, juste après la
> remise à zéro. Événement : **jeudi 17 septembre 2026** — c'est **demain**.
>
> Les §1 à §14 décrivent l'application. Le **§15** décrit le générateur de
> badges : outil local, séparé, jamais déployé. Le **§16** décrit la vitrine,
> ajoutée le 16 au soir. Le **§17** dit où en est le projet à cette minute et
> ce qui reste ouvert — **à lire en premier si vous reprenez la main**. Le
> **§18** est l'étude de tenue en charge, refaite le 16 au soir après la panne
> de l'application GRID : il contient les mesures, le banc des 344 appareils,
> et **le piège des trois batteries de tests, qui effacent la base**.
>
> 🟢 **TOUT EST PRÊT. LA BASE EST À ZÉRO.**
> Journal 0 · cases 0 · soldes 0 · écarts 0 · `tirage_revele = non` ·
> 85 lots + 15 tickets · 516 badges imprimés · déployé en `gbp-v27`.
>
> 🔴 **NE PAS RELANCER `99_remise_a_zero.sql`.** Elle est passée le 16 au soir,
> après la simulation de 400 garages. La relancer pendant le Forum effacerait
> une vraie journée. Voir §17.
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
| **État** | **Terminé, déployé (`gbp-v27`), base à zéro** — 114 tests verts, voir §17 |
| **Badges** | **516 badges**, 258 feuilles A4, **imprimés** — voir §15 |
| **Profils** | **six** : garage, animateur, fournisseur, accueil, direction, **vitrine** (§16) |
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

> 🔴 **La remise à zéro est DÉJÀ FAITE** (16 au soir). Ne pas la relancer.
> Il ne reste qu'à **vérifier**, et à ouvrir.

```powershell
# 1. Vérifier que tout est encore à zéro et que la composition a survécu
.\scripts\push-sql.ps1 -Quiet -Query "select (select count(*) from journal) as journal, (select count(*) from grille where garage_id is not null) as cases_prises, (select count(*) from verifier_soldes()) as ecarts, (select count(*) from grille where nature='lot') as lots, (select count(*) from grille where nature='billet') as tickets"
# attendu : journal=0  cases_prises=0  ecarts=0  lots=85  tickets=15
# Si journal > 0, le Forum a COMMENCÉ : ne touchez à rien.

# 2. Vérifier que le site servi est bien à jour
(New-Object System.Net.WebClient).DownloadString(
  'https://forum-2026.bonyauto-mobile.workers.dev/sw.js?t=' + (Get-Random)
) -match "const VERSION = '([^']+)'" ; $Matches[1]
# attendu : gbp-v27

# 3. Sur CHAQUE appareil de service (projection, supervision, accueil) :
#    Ctrl + Maj + R une fois. Le service worker garde l'ancienne version
#    en cache, et c'est le piège qui fait croire qu'un correctif n'est
#    pas parti.
```

### Le test du prestataire audiovisuel sur écran géant

> Le presta veut éprouver le grand tirage en vraie grandeur avant l'ouverture.
> Il faut donc une base **pleine** pendant quelques minutes, puis vide.
> **Tout repose sur une seule condition : que personne n'ait encore ouvert
> l'application.**

**LE VERROU, à lire avant tout le reste.** La remise à zéro est tout-ou-rien :
elle vide le journal entier, efface `inscrit_le`, remet les soldes à zéro et
**supprime tous les appareils**. Si des agents sont déjà entrés, ils sont tous
**déconnectés d'un coup** — leur téléphone garde son jeton, la ligne
`appareils` a disparu, `api_etat` répond `APPAREIL_INCONNU` et l'application
retombe sur l'écran de code. Ils devront retaper leur code au moment précis où
le Forum ouvre. Et pendant le test, `api_etat` renvoyant l'état complet de la
grille, **chaque agent connecté verrait la grille déjà prise**.

```powershell
# ---- 0. LE FEU VERT. Sans lui, on ne lance RIEN. --------------------
.\scripts\push-sql.ps1 -Quiet -Query "select (select count(*) from journal) as journal, (select count(*) from appareils) as appareils"
#    attendu : journal=0
#    journal > 0  =>  quelqu'un est deja arrive. ON ANNULE LE TEST.
#    Il n'y a pas de demi-mesure : a partir de la, remplir puis vider
#    detruirait l'arrivee de ces gens-la.

# ---- 1. Remplir (quelques minutes) ---------------------------------
.\scripts\simuler-forum.ps1 -Appliquer
#    Elle remet a zero PUIS joue une journee : 200 cases prises,
#    15 tickets d'or decroches. C'est exactement ce qu'il faut a l'ecran.

# ---- 2. La tablette de projection a ete deconnectee par l'etape 1 ---
#    (tous les appareils ont ete supprimes). Ressaisir le PIN direction.

# ---- 3. Le presta fait son test -------------------------------------
#    Supervision -> Grand tirage au sort -> Lancer la revelation.
#    6,5 s par lot, ~100 s pour les 15. Le bouton Repetition rabaisse le
#    drapeau si on veut le rejouer : les codes de retrait ne bougent pas,
#    sans importance ici puisque l'etape 4 les efface.

# ---- 4. Vider, et LIRE CE QU'ELLE REPOND ----------------------------
.\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql
#    Elle finit par un controle. TOUT doit etre a zero :
#      lignes_journal 0 · appareils 0 · tentatives 0 · tirage_revele non
#      garages_avec_solde 0 · cases_jouees 0 · ecarts 0
#    et la composition doit avoir SURVECU :
#      cases_lot 85 · tickets_or 15 · cases_perdantes 100
#    Si une seule de ces valeurs n'y est pas : NE PAS OUVRIR, relancer.

# ---- 5. Le controle d'etat habituel, puis on ouvre ------------------
#    (celui du debut de ce paragraphe, plus verifier_portes/badges)
```

**Trois choses à savoir :**

- **La fenêtre se referme au premier agent connecté.** Le seul juge est le
  compteur `journal` : il passe à 1 dès la première arrivée, parce que le bonus
  d'accueil s'y écrit. C'est le feu vert de l'étape 0, et il ne se discute pas.
- **Aucun `Ctrl + Maj + R` n'est nécessaire** : rien n'est déployé, seule la
  base bouge. En revanche **tous les postes de service** — projection,
  supervision, accueil — devront ressaisir leur PIN après l'étape 4.
- **`simuler-forum.ps1 -Appliquer` commence elle-même par une remise à zéro.**
  Elle est donc aussi destructrice que `99_remise_a_zero.sql`, et soumise au
  même interdit une fois le Forum commencé.

> Si le test devait avoir lieu **après** la distribution des codes, cette
> procédure ne convient pas : il faudrait une injection marquée et un nettoyage
> chirurgical qui préserve les agents déjà entrés. Ça n'a pas été écrit, et ça
> ne s'improvise pas le matin même.

### Pendant la journée

- **La console de santé** est en haut de l'écran de supervision. Tant que la
  santé globale est verte, il n'y a rien à faire. Le **tableau de bord Supabase,
  lui, sera rouge vif** : il compte chaque refus voulu comme une erreur. Ne pas
  s'y fier.
- **Exporter le journal toutes les heures** : `.\scripts\exporter-journal.ps1`.
  C'est la seule vraie sauvegarde de la soirée.
- **Une panne ?** `.\scripts\diagnostic.ps1` répond à la seule question utile :
  « est-ce la base, ou la couche devant ? »
- **La liste d'émargement** est imprimée d'avance — `.\scripts\emargement.ps1`
  la régénère si besoin. Elle ne porte aucun code.

### Le soir

1. Supervision → **Grand tirage au sort** → *Lancer la révélation*.
2. 6,5 s par lot, soit ~100 s pour 15 tickets. Un clic sur la scène fait tomber le nom tout de suite, un second
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
| `appareils_max` | `10` | téléphones par garage · **une place prise ne se rend pas** — passé de 6 à 10 le 16 au soir, voir §18 |
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
| Un garage a épuisé ses 10 appareils | c'est un plafond dur, et **l'accueil ne peut rien** ; `update config set valeur='15' where cle='appareils_max'` — effet immédiat, aucun déploiement |
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

### Les six profils

| Profil | Entre avec | Peut faire |
|---|---|---|
| **Garage** | son code à 4 caractères | voir son solde et ses opérations, acheter une case |
| **Animateur** | le code de son animation | chercher un garage, lancer une partie, noter le résultat |
| **Fournisseur** | le code de son stand | chercher un garage, créditer une opération |
| **Accueil** | le code hôtesse | chercher parmi les 1 457 invités, **lire un code**, voir le compteur d'arrivées |
| **Équipe Bony** | le code direction | supervision, remise des lots, corrections, **détail des tickets d'or**, écran de projection |
| **Vitrine** | un code personnel | **lecture seule** — compteurs, podiums, journal en direct. 119 équipe Bony + 21 constructeurs, voir §16 |

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
> pour cela que `appareils_max` est passé à **6**, puis à **10** le 16 septembre
> au soir : le plafond ne protège rien — le portefeuille est partagé par garage
> de toute façon — alors qu'un garage enfermé dehors est une panne visible que
> **l'accueil ne sait pas réparer**. Voir §18.

> ⚠️ **ET C'EST POURQUOI SE DÉCONNECTER N'EFFACE PAS LE JETON.** `api_entrer` ne
> compte l'appareil dans le plafond que si son jeton n'est pas *déjà* rattaché au
> garage. Un jeton neuf à chaque retour, c'est donc une ligne de plus à chaque
> aller-retour — et au dixième, le garage se retrouve enfermé dehors avec un
> « Ce garage a déjà 10 appareils connectés ». Le bouton « Quitter » n'oublie donc
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

## 11. Ce qui reste — état au 16 septembre 2026, tard le soir

### 🟢 Plus rien de bloquant

**La remise à zéro est passée**, après la simulation de 400 garages. Relevé
juste après : journal **0** · cases prises **0** · soldes **0** · écarts **0** ·
`tirage_revele = non` · 85 lots + 15 tickets en place.

> 🔴 **`99_remise_a_zero.sql` ne doit plus être relancée.** Pendant le Forum,
> elle effacerait une vraie journée. Le détail de la passation est au **§17**.

Le seul geste avant l'ouverture est de **vérifier** :

```powershell
.\scripts\push-sql.ps1 -Quiet -Query "select (select count(*) from grille where garage_id is not null) as cases_prises, (select count(*) from journal) as journal, (select count(*) from verifier_soldes()) as ecarts"
```

Si `journal` n'est pas à zéro, **le Forum a commencé** : ne toucher à rien.

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
| 11 | ~~Constructeurs~~ | ✅ **21 invités Renault** importés le 16/09 — `sql/27_collaborateurs.sql` |
| 12 | ~~Une interface pour l'équipe Bony et les constructeurs~~ | ✅ **la vitrine**, 140 codes nominatifs — §16 |
| 13 | **Supabase Pro** | 🟡 **la seule décision encore ouverte** — voir §17, les mesures disent que ce n'est pas nécessaire |

### Ce qui reste en dehors du code

> 1. **Dire aux animateurs du BASKET ARCADE et du BLAZZPOD** d'écrire le score à
>    battre sur une ardoise. Le prestataire a écrit « TOP SCORE EN 45 SECONDES,
>    4 PTS À GAGNER » : ça donne un plafond, aucun seuil, et l'application
>    demande un RÉSULTAT, pas un nombre. C'est la seule consigne humaine qui
>    manque au dispositif.
> 2. **Exporter le journal toutes les heures** le jour J :
>    `.\scripts\exporter-journal.ps1`. Le plan gratuit n'a aucune sauvegarde —
>    relevé le 16 au soir : `"backups": []`.
> 3. **`Ctrl + Maj + R` sur les postes de service** avant d'ouvrir. Le service
>    worker resert l'ancienne version sans rien dire.
> 4. **Un garage absent des 1 456** ne peut pas être servi par l'accueil : aucune
>    fonction `api_*` ne crée de garage. Arbitrage de Bastien le 16 au soir :
>    **pas de création de compte**. Le cas se traite à la main, à sa demande.

### Ce qui n'a jamais été éprouvé, et qu'il faut dire

> - **Le mode hors ligne sur un vrai téléphone en mode avion.** Bastien a
>   tranché : « on en a pas besoin, c'est un plus que je ne testerai pas ».
> - ~~**L'écran de projection sur le vrai écran LED.**~~ ✅ **Testé sur place par
>   Bastien le 16 septembre au soir**, en même temps que le wifi de la halle.
>   C'était la plus grosse inconnue du dispositif, et la seule qu'aucun script
>   n'aurait pu lever.
> - **La présentation agents sur le vidéoprojecteur de la salle de réunion.**
>   Zéro débordement mesuré à 1 280 × 720, 1 366 × 768 et 1 920 × 1 080, mais la
>   lisibilité à dix mètres ne se mesure pas depuis un navigateur.
> - **La vitrine sur 140 appareils réels.** Mesurée en rafale depuis UNE machine :
>   0 échec sur 420 appels, médiane 275 ms à concurrence réaliste. Ce n'est pas
>   la même chose que 140 téléphones sur le wifi de la halle.
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
**6 500 ms**. Le plafond de 5 s posé dans la journée du 16 a été relevé le soir même,
après passage sur scène : à 4 s, le temps de lire le nom du gagnant manquait.

Le budget global a disparu avec cette passe, et c'est le bon modèle : ce que la
salle ressent, c'est le temps d'UNE annonce, pas la somme. Un budget total
faisait dépendre le rythme du nombre de tickets décrochés — à 8 tickets au lieu
de 15, chaque annonce durait presque le double sans que personne l'ait demandé.

**Mesuré à 6,5 s : écarts de 6,65 à 6,68 s entre deux annonces**, premier nom
à 4,2 s. Les ~2,5 % au-dessus de la consigne sont l'empilement des `setTimeout`
de la roulette ; c'est constant et sans effet visible.

> ⚠️ **Pour 15 tickets, ça fait ~100 secondes** — soit PLUS que les 80 s jugées
> « un poil trop long » le 16. Le réglage porte sur le temps d'UNE annonce, pas
> sur le total, et c'est assumé : une annonce trop brève rate sa cible même si
> le spectacle est court. Si c'est le total qui coince un jour, c'est
> `REVEL_PAR_LOT` qu'on baisse, pas le nombre de lots.

> **Cinq passes, toutes sur retour de scène.** 57 s au total : « un poil trop
> rapide ». 95 s : « un poil trop long ». 80 s : le compromis du 16, mais 8,9 s
> sur les trois derniers lots. 4 s par lot : un réglage du 16, trop sec
> une fois projeté. **6,5 s par lot** : le réglage retenu.
>
> ⚠️ **Le temps double des trois derniers a sauté.** Il portait le crescendo sur
> les trois pièces uniques — sac à dos Alpine, weekender, sac cuir jaune — et il
> est incompatible avec le plafond de 5 s : à poids double, elles tombaient à
> 8 s. Le spectacle finit toujours sur le plus beau lot, mais au même rythme que
> le reste. C'est un arbitrage de scène, pas un oubli.
>
> `REVEL_SUSPENSE` vaut **0,62** : c'est le temps mort APRÈS la chute du nom qui
> donnait l'impression de traîner, pas la roulette. À 6,5 s, ça fait 4,0 s de
> roulette et 2,5 s de nom en clair — de quoi lire « Carrosserie Desmartin » au
> fond de la salle.
>
> ⚠️ **LA ROULETTE DOIT AVOIR LE TEMPS DE FINIR SA DÉCÉLÉRATION.** Elle se coupe
> net au temps imparti — c'est le garde-fou de scène — et une roulette coupée en
> plein élan s'arrête sans ralentir : on dirait une panne, pas un verdict. À
> 6,5 s, les 32 sauts prennent 3,93 s pour 4,03 s disponibles : **100 ms de
> marge**. Vérifié en horodatant chaque saut — le dernier dure 277 ms contre
> 52 ms pour le premier, la décélération va donc bien à son terme. Toucher à
> `REVEL_PAR_LOT` ou à `REVEL_SUSPENSE` sans rejouer un passage complet, c'est
> risquer de repasser sous cette marge sans que rien ne le dise.

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
ensemble, et `visibilitychange` (`app/js/app.js:2176`) relance une lecture dès
qu'un écran revient au premier plan, sans dispersion : si toute la salle sort
son téléphone à la même seconde, les 344 appareils appellent ensemble. C'est le
correctif n° 4 de GRID (« disperser »), et il manque toujours.

**Mesuré le 16 septembre au soir, et c'est ce qui clôt la question** —
`banc-jour-j.ps1`, phase 2 : 344 requêtes **dans la même milliseconde**
s'écoulent en **1 751 ms, zéro échec** (1 301 ms à dix fois le rythme réel).
La gigue supprimerait donc un problème qu'on n'a pas, au prix d'un déploiement
et d'un `Ctrl + Maj + R` sur tous les postes. **Décision : on ne la fait pas.**
Dix lignes si le besoin apparaissait un jour. Détail au §18.

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
#
# 🔴 DEUX D'ENTRE ELLES EFFACENT LA BASE. test-invariants.ps1 et
#    test-bingo.ps1 commencent par vider le journal (en levant le verrou
#    d'immuabilité), remettre tous les soldes à zéro, effacer tous les
#    appareils et libérer la grille. C'est 99_remise_a_zero.sql sous un
#    autre nom. Et elles ne nettoient RIEN en sortant : elles laissent
#    leurs garages témoins, leurs cases achetées et leurs lignes de
#    journal derrière elles.
#    => PENDANT LE FORUM, LES LANCER EFFACE LA JOURNÉE. Voir §18.
#
#    Et test-porte.ps1 n'est pas inoffensive non plus : elle ouvre de
#    VRAIS garages par api_ouvrir, ce qui crée des appareils, verse le
#    bonus d'arrivée et inscrit des garages qui ne sont pas venus. Elle
#    vide aussi la table `tentatives`, donc le frein anti-devinette.
#    AUCUNE DES TROIS ne se lance pendant le Forum.
.\scripts\test-porte.ps1        # 53 : la porte, le frein, les 31 PIN — ⚠️ ÉCRIT (inscrit des garages)
.\scripts\test-invariants.ps1   # 32 : double crédit, quotas, solde négatif — ⚠️ EFFACE TOUT D'ABORD
.\scripts\test-bingo.ps1        # 29 : les deux modes, la revelation, 200 cases — ⚠️ EFFACE TOUT D'ABORD

# Serveur local (le service worker ne fonctionne pas depuis file://)
.\scripts\serveur.ps1                                   # l'application, http://localhost:8123
.\scripts\serveur.ps1 -Dossier presentation -Port 8125  # les deux présentations

# Dimensionnement
.\scripts\mesurer-charge.ps1    # coût unitaire, taille du pool, rythme d'une soirée
.\scripts\trouver-plafond.ps1   # rafale montante jusqu'à la rupture

# LA SIMULATION — une journée entière par l'API réelle, jusqu'à ce que les
# 200 cases soient prises. SANS -Appliquer elle n'écrit RIEN.
# ⚠️ Avec -Appliquer elle REMET LA BASE À ZÉRO, puis la remplit. NE PAS
#    LA LANCER avant ou pendant le Forum : elle prend 200 cases sur 200.
#    Elle a servi le 16 au soir, et la base a été remise à zéro après.
.\scripts\simuler-forum.ps1
.\scripts\simuler-forum.ps1 -Appliquer

# LE JOUR J
.\scripts\diagnostic.ps1        # « est-ce la base, ou la couche devant ? »
.\scripts\exporter-journal.ps1  # journal, soldes et lots en CSV — toutes les heures

# 🔴 REMISE À ZÉRO — DÉJÀ PASSÉE le 16 septembre au soir. NE PLUS LA
#    LANCER avant le Forum : elle efface les achats, le journal, les
#    soldes et les appareils. Pendant la journée, c'est une vraie
#    journée qui disparaît. Elle ne sert plus qu'après une répétition,
#    et seulement sur décision de Bastien. Voir §17.
# .\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql

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

### La liste d'émargement des hôtesses

`scripts/emargement.ps1` produit un PDF A4 — **15 pages, 316 lignes, 516
badges** — à poser sur la table d'accueil.

**Pourquoi du papier alors qu'il y a un écran d'accueil.** L'écran sait
retrouver n'importe lequel des 1 456 invités et lire son code ; le papier ne
sait rien faire de tout ça. Il sert à autre chose : **cocher**. Deux hôtesses
qui accueillent 320 personnes en deux heures ont besoin de savoir qui est déjà
passé, et un écran partagé ne se coche pas à deux mains. C'est aussi le seul
document qui survit à une panne de wifi.

> ⚠️ **Aucun code d'accès n'y figure, et c'est volontaire.** Une feuille
> d'émargement traîne sur une table toute la journée et se photographie en une
> seconde. Les codes restent sur l'écran d'accueil, qui en montre **un** à la
> fois, à la demande. Vérifié sur le fichier produit : **aucun des 312 codes de
> la base n'apparaît dans le document** — recoupé code par code, pas à l'œil.

**L'ordre est celui des piles de badges**, pas l'ordre alphabétique global. Une
hôtesse cherche un badge dans une pile ET une ligne sur une feuille : si les
deux ne sont pas rangés pareil, elle cherche deux fois. Les garages suivent donc
« agents d'abord », l'équipe Bony suit le nom de famille — exactement comme
`badges/badges.js`. Un trait horizontal marque l'endroit où les agents
s'arrêtent.

Le fichier va dans `exports/`, ignoré par git : il porte des noms.

### La charge de la vitrine

`scripts/charge-vitrine.ps1`. La simulation du Forum joue des garages, des
animateurs et des fournisseurs ; elle **ne connaît pas** le profil vitrine.
Or c'est 140 téléphones qui appellent `api_vitrine` toutes les 30 secondes,
**en plus** de la charge des garages.

Mesuré le 16 septembre, **sur une base pleine** (5 800 écritures au journal,
juste après la simulation — le pire cas) :

| | Rafale de 140 d'un coup | Concurrence réaliste (10) |
|---|---|---|
| Médiane | 2 350 ms | **275 ms** |
| p95 | 3 709 ms | 421 ms |
| Échecs | **0 sur 420** | **0 sur 30** |

**Le chiffre qui compte est celui de droite.** Le jour J, 140 vitrines se
rafraîchissent chacune sur son propre minuteur : **4,7 requêtes par seconde
réparties**, jamais 140 d'un coup. La rafale dit seulement que même le pire cas
passe, en dégradant la latence sans rien casser.

Un appel coûte **45 ms** côté base, dont seulement 5,6 ms pour
`verifier_soldes()` — qui balaie pourtant les 5 800 lignes du journal. À 4,7
req/s, la vitrine consomme donc ~21 % d'**une** connexion sur les onze du pool.

> Ce banc part d'UNE machine et d'UNE connexion : il mesure Supabase, pas le
> wifi de la Grande Halle. Le wifi reste le risque le plus probable, et aucun
> script ne le testera.

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

### L'équipe Bony : une seule société, et le tri par nom de famille

Deux demandes du 16 septembre : *« l'équipe Bony : tu mets la même raison
sociale à tout le monde »* et *« pour l'export il faut que ce soit par ordre
alphabétique des NOMS DE FAMILLE »*.

**Il y avait vingt et une raisons sociales pour 119 personnes**, toutes saisies
à la main dans le formulaire : « BONY AUTOMOBILES », « BONY AUTOMOBILES figeac »,
« eaa mozac », « SAS BONY AUTO MOBILE BSO », « E2A », « BONYAUTO-MOBILE »…
Sur un badge, cette ligne est écrite plus gros que le nom de la personne : 21
orthographes au cou de la même équipe, ça se voit de loin.
`sql/29_equipe_bony.sql` les aligne sur **« Bony auto-mobile »**, graphie qui
figurait déjà telle quelle sur trois lignes, saisies par leurs titulaires.

> ⚠️ **On perd l'information de filiale.** EAA, BSO, SODAVI, E2A étaient la
> seule trace de qui appartient à quelle enseigne, et elle n'est nulle part
> ailleurs dans cette base. Arbitrage d'affichage assumé : le badge dit le
> groupe, pas l'établissement. Si la filiale redevient utile, elle est à
> reprendre dans le listing consolidé du 15.

**Le tri par nom de famille a demandé trois corrections, toutes invisibles
jusqu'à ce qu'on regarde la pile.**

1. **Une fiche avait les deux champs à l'envers** — `prenom` = BRUCHET,
   `nom` = PATRICK. Le badge annonçait « BRUCHET PATRICK » et le tri l'aurait
   rangé à la lettre P, entre PAYA et PIZZI. L'adresse tranche : `patrick.bruchet@`.
   Les 118 autres lignes ont été recoupées avec la partie locale de leur
   adresse — aucune autre inversion.
2. **Les badges d'accompagnant remontaient en tête.** Ils ne portent pas de nom,
   volontairement — on ne connaît pas la personne qui accompagne — et un tri sur
   une chaîne vide les empile avant la lettre A. Le nom du porteur est désormais
   gardé dans un champ `triNom` qui **ne s'imprime pas** et ne sert qu'à trier :
   chaque accompagnant suit son titulaire.
3. **Le découpage par lettre sortait « f, h, v, z, a, b, c… »** : le tri des
   groupes appliquait encore la règle « agents d'abord », et les lettres dont le
   premier badge portait le drapeau réunion remontaient. La règle ne s'applique
   plus que lorsque les deux piles coexistent, c'est-à-dire aux garages.

**La règle « agents en tête » ne vaut donc QUE pour les garages.** Un badge Bony
se cherche par le nom de la personne, jamais par sa présence à la réunion du
matin ; scinder cette pile obligerait à regarder deux fois. Vérifié sur les
124 lignes : ordre conforme au nom de famille, zéro écart, et les garages
gardent leurs 77 agents en tête.

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

---

## 16. La vitrine — équipe Bony et invités constructeur

Ajoutée le 16 septembre, à la demande de Bastien : *« on va créer une nouvelle
interface pour l'équipe Bony mec. Et pour le constructeur aussi. Elle contiendra
les infos de ce que l'on retrouve de manière générale dans l'onglet direction
mais ce sera que de la vitrine. »*

### Un sixième profil, en lecture seule

| | |
|---|---|
| **Qui** | 119 équipe Bony + 21 constructeurs = **140 personnes** |
| **Rôle** | `vitrine` — il n'existe qu'ici, et il n'écrit rien |
| **Une seule fonction** | `api_vitrine(p_jeton)`, et c'est tout |
| **Codes** | **140 codes nominatifs** + 1 code de secours |

**Ce n'est pas un `admin` bridé côté navigateur.** Le code supervision ouvre la
remise des lots, les corrections de points, l'écran de projection et le détail
des tickets d'or ; le donner à 140 personnes reviendrait à le publier. La
vitrine est un rôle à part, et **une restriction qui ne vit que dans le front
n'est pas une restriction**. Vérifié sur la vraie base, avec un jeton de
vitrine — les sept portes sont fermées :

| Tentative | |
|---|---|
| `api_corriger` — ajouter des points | refusé |
| `api_supervision` — le tableau direction | refusé |
| `api_tirage_etat` — les tickets nommés | refusé |
| `api_tirage_lancer` — la révélation | refusé |
| `api_lots` — le suivi des lots | refusé |
| `api_journal_complet` — l'export CSV | refusé |
| `api_accueil_chercher` — lire un code garage | refusé |

### Un code par personne

*Verbatim : « un code différent pour tout le monde, ça évite les fuites si y'a
qu'un code unique ».* Un code qui circule ne se révoque pas ; 140 codes
distincts se coupent un par un (`participants.actif = false`).

Ils vivent dans **`participants.code_force`**, qui est le champ que `v_badges`
résout en priorité : poser le code là suffit à le faire apparaître sur le badge,
sans toucher au générateur ni à la vue. Même algorithme que les codes garage —
MD5 d'une graine fixe, alphabet sans `O`, `I`, `0` ni `1`, variante incrémentée
tant qu'il y a collision. **Déterministe, donc rejouable sans jamais changer un
code déjà imprimé** : un code posé n'est jamais repris.

Mesuré : **140 codes, 140 distincts, 0 collision** avec les 1 456 codes garage,
les 31 PIN du personnel et le code de secours. `verifier_portes()` couvre
désormais ces 140 codes et rend toujours zéro ligne — sans ça, un code de
vitrine qui vaudrait le code d'un garage ouvrirait le portefeuille de ce garage,
et personne ne le verrait avant que quelqu'un s'en plaigne.

**Le code de secours** est dans `config.pin_vitrine`, *« pour les couillons qui
sont pas sur la liste »*. Il ouvre la même vitrine, sans nom, et il n'est sur
**aucun badge** : il se donne de vive voix et se change en une ligne.

### Ce que l'écran montre

- **La barre de santé du Forum**, et rien de plus. La console de supervision
  détaille le pool, les verrous et les transactions bloquées ; ces chiffres
  n'apprennent rien à un invité Renault, et `api_vitrine` **ne les envoie même
  pas** — le verdict est calculé en base, on ne transmet qu'un pourcentage.
- **Le Forum en un coup d'œil** : sept compteurs.
- **Trois podiums** : garages, stands, animations. Le classement des garages se
  fait sur les points **gagnés**, pas sur le solde — un garage qui joue tout ce
  qu'il gagne finirait à zéro et disparaîtrait du podium alors que c'est lui le
  plus actif de la salle.
- **Le journal en direct**, 40 lignes. Noms de garages en clair : arbitrage du
  16 septembre, les constructeurs voient exactement la même chose que l'équipe
  Bony.
- **Les tickets d'or, en compteurs seulement.**

> ⚠️ **LES TICKETS D'OR NE SONT JAMAIS NOMMÉS.** « 9 décrochés sur 15 », et rien
> d'autre : ni qui les détient, ni quel gros lot est dessous. Cet écran est
> ouvert sur 140 téléphones dans la salle, dont ceux de gens qui parlent aux
> garagistes toute la journée. Le détail reste à la direction, et à elle seule.

### Un seul appel, et pourquoi

`api_vitrine` rend **tout l'écran en un aller-retour** : compteurs, podiums,
journal, santé. 140 téléphones pendant six heures, et le pool PostgREST plafonne
à 11 connexions — chaque aller-retour évité est une connexion qui reste libre
pour un garagiste qui achète une case. Pour la même raison, la vitrine **ne
télécharge pas** le cache des 1 456 garages : elle ne cherche jamais personne.

### Les animations

Les chiffres montent à l'ouverture, en sortie cubique, **une seule fois**. Les
rejouer à chaque rafraîchissement — toutes les trente secondes pendant six
heures — transformerait un écran d'information en machine à sous. Les barres des
podiums poussent à chaque rendu, elles sont assez discrètes pour le supporter.
Une ligne de journal qui vient d'arriver s'allume une fois et redevient normale :
on veut dire « ça bouge », pas réclamer l'attention en continu. Tout est neutralisé
sous `prefers-reduced-motion`.

---

## 17. Passation — où en est le projet le 16 septembre au soir

> **Si vous reprenez la main, commencez ici.** Cette section dit l'état exact à
> la minute de la passation, ce qui est fait, ce qui reste ouvert, et les deux
> ou trois gestes qui feraient des dégâts.

### L'état, relevé et pas supposé

| | |
|---|---|
| En ligne | `gbp-v27`, `js/app.js` identique au dépôt — **au contenu**, voir ci-dessous |
| Base | journal **0** · cases prises **0** · soldes **0** · inscrits **0** |
| Intégrité | écarts **0** · collisions de code **0** · badges sans code **0** |
| Grille | 85 lots + 15 tickets d'or, composition intacte |
| Soirée | `tirage_revele = non` |
| Badges | **516**, tous imprimés |
| Codes vitrine | **140** nominatifs + 1 de secours dans `config.pin_vitrine` |
| Tests | 114 verts (53 + 32 + 29) |
| Simulation | 400 garages, 5 800 écritures, 0 échec — puis remise à zéro |

> ⚠️ **« Octet pour octet » est faux sur une copie de travail Windows, et la
> fausse alerte est garantie.** Le fichier servi porte des fins de ligne **LF**
> (c'est ce qu'il y a dans le dépôt) ; le fichier sur le disque porte des
> **CRLF**, posés par `core.autocrlf` à chaque checkout. Comparer les deux
> donne donc toujours « différent » — mesuré le 16 au soir : 110 576 octets en
> local contre 108 353 servis, soit exactement **2 223 octets d'écart pour un
> fichier de 2 223 lignes**. Retirer les CR des deux côtés rend le **même
> SHA-256**. Comparer le contenu, jamais les octets :
>
> ```powershell
> $d = (New-Object System.Net.WebClient).DownloadData('https://forum-2026.bonyauto-mobile.workers.dev/js/app.js?t=' + (Get-Random))
> $l = [System.IO.File]::ReadAllBytes('app\js\app.js')
> $h = [System.Security.Cryptography.SHA256]::Create()
> ($h.ComputeHash([byte[]]@($d | ? { $_ -ne 13 })) -join '') -eq `
> ($h.ComputeHash([byte[]]@($l | ? { $_ -ne 13 })) -join '')
> ```

### 🔴 Les trois gestes à ne pas faire

1. **Ne pas relancer `sql/99_remise_a_zero.sql`.** Elle est passée le 16 au soir.
   La relancer pendant le Forum efface le journal, les soldes, les cases
   achetées et les appareils connectés — une vraie journée. Avant de la lancer
   un jour, lire le compteur `journal` : s'il n'est pas à zéro, le Forum a
   commencé.
2. **Ne pas régénérer les codes.** `sql/30_vitrine.sql` est écrit pour ne jamais
   reprendre un code déjà posé, et `sql/10_garages.sql` dérive les codes du
   numéro de compte — mais les **badges sont imprimés**. Un code qui change
   après impression est un badge mort.
3. **Ne pas oublier le `Ctrl + Maj + R`** sur un poste de service après un
   déploiement. Le service worker resert l'ancienne version, et on croit qu'un
   correctif n'est pas parti. Ça a coûté une mesure fausse le 16 (deux
   spectacles du grand tirage qui se chevauchaient sans que rien ne le dise).

### Ce qui a été fait le 16 septembre, dans l'ordre

| | Ce qui a changé | Où |
|---|---|---|
| Tirage | 95 s → 80 s → 4 s/lot → **6,5 s par lot** ; titre décollé du lot ; récapitulatif derrière un bouton | §11 |
| Badges | 55 collaborateurs Bony + 21 constructeurs ; agents en tête du PDF garage ; une seule raison sociale pour l'équipe Bony ; tri par nom de famille | §15 |
| Présentation agents | 12 → **7 diapositives**, « À jeudi » corrigé, 7 JPEG 1920×1080 dans `Documents\Slides Forum 2026` | §14 |
| **Vitrine** | sixième profil, lecture seule, 140 codes nominatifs | **§16** |
| Émargement | `scripts/emargement.ps1`, 15 pages A4, aucun code dessus | §15 |
| Listes SMS | `scripts/sms-listes.ps1`, deux listes E.164, messages GSM-7 | ci-dessous |
| Charge vitrine | `scripts/charge-vitrine.ps1` | §15 |

### Les listes SMS de la veille

`scripts/sms-listes.ps1` produit deux fichiers (`.xlsx` **et** `.csv`) dans
`exports/` : **agents** (réunion + Forum, 51 lignes) et **autres garages**
(Forum seul, 93 lignes). Deux pièges y sont désamorcés, et aucun ne se voit :

- **Quatre formats de numéro** cohabitaient dans le listing consolidé —
  `470415669` (zéro initial mangé par Excel), `33466474685`, `+33473281919`,
  `0565995186`. Tout est normalisé en **E.164**.
- **89 numéros sur 145 sont des FIXES.** Un SMS sur un 04 ou un 05 n'arrive
  jamais et la passerelle ne rend aucune erreur : elle accepte, le message
  disparaît. La colonne `Type` les sépare et les **mobiles sont rangés en
  tête** — 21 chez les agents, 34 chez les autres. On touche 55 personnes sur
  145, pas 145.
- Les messages sont écrits pour l'**alphabet GSM-7**. Un seul caractère hors de
  cet alphabet bascule tout le message en UCS-2 : le segment tombe de 160 à 70
  caractères et la facture double. « cocktail dînatoire » est donc devenu
  « cocktail du soir » — le `î` n'existe pas en GSM-7, et l'écrire sans accent
  serait une faute visible. Les `é`, `è` et `à`, eux, sont disponibles et gardés.

### Ce qui reste ouvert

> 🟢 **Les points 1 et 3 ci-dessous ont été repris et tranchés le 16 au soir,
> après une relecture du dossier de panne de GRID. Les mesures, le banc des
> 344 appareils et la décision sont au §18.** Résumé : le plan payant n'achète
> rien sur la charge, la vitrine a été mesurée à 13 ms sur un journal de vraie
> soirée, et 344 appareils simultanés s'écoulent en 1,7 s sans un échec.

**1. Supabase Pro — décision de Bastien, prise ce soir ou jamais.**
État relevé : plan **gratuit**, instance **Micro** (`max_connections` 60,
`shared_buffers` 224 Mo), base de **22 Mo** sur 500 autorisés,
**`"backups": []` — aucune sauvegarde**, PITR désactivé.
Les mesures disent que ce n'est pas nécessaire : ~25 req/s attendues au pic
contre **314 req/s sans le moindre échec** (§8), soit ×12 de marge. Le plan Pro
ne change d'ailleurs **pas** le pool PostgREST — seule la taille d'instance le
fait, et c'est un supplément qui **impose un redémarrage de la base**.
Ce que le Pro apporterait vraiment ici : les sauvegardes quotidiennes. Mais
l'export CSV horaire est une meilleure protection pour un événement d'un jour.
Facturation par organisation : `supabase.com/dashboard/org/kicrtzsusktftmmmromz/billing`.

**2. Un garage absent des 1 456 ne peut pas être servi par l'accueil.**
Vérifié : **aucune fonction `api_*` ne crée de garage**. Si quelqu'un se présente
et n'est nulle part en base, l'hôtesse cherche, ne trouve rien, et n'a aucun
moyen de lui donner un code. Bastien a tranché le 16 au soir : **pas de création
de compte**. Le cas se traite par un `insert` manuel depuis le poste de
direction, à sa demande.

**3. Ce qui n'a jamais été éprouvé, et qu'il faut dire tel quel.**
- La vitrine n'a **jamais tourné sur 140 appareils réels** — seulement en rafale
  depuis une machine : 0 échec sur 420 appels, médiane 275 ms à concurrence
  réaliste.
- Les bancs de charge partent tous d'**une** machine et d'**une** connexion : ils
  mesurent Supabase, pas le wifi de la halle. Bastien a confirmé le 16 au soir
  que **le wifi et l'écran sont testés et OK** — c'est la meilleure nouvelle de
  la préparation, et la seule qu'aucun script n'aurait pu donner.

### Où sont les documents qui ne sont pas dans le dépôt

`exports/` est ignoré par git et le restera : il porte des **noms, des numéros
de téléphone et des codes d'accès**.

| Fichier | Quoi |
|---|---|
| `exports/emargement-2026-09-16.pdf` | la liste des hôtesses, 15 pages |
| `exports/sms-agents-*.xlsx` · `.csv` | 51 lignes, mobiles en tête |
| `exports/sms-autres-garages-*.xlsx` · `.csv` | 93 lignes, mobiles en tête |
| `exports/sms-messages-*.txt` | les deux textes, prêts à coller |
| `badges/participants.json` | les 516 badges avec leur code |
| `Documents\Slides Forum 2026\*.jpg` | les 7 diapositives en 1920 × 1080 |
| `Documents\Badges Forum 2026\*.pdf` | les badges imprimables |

---

## 18. La tenue en charge, reprise à zéro le 16 au soir

> Écrit après une relecture du dossier GRID — l'autre application maison, même
> architecture, tombée le 8 septembre 2026 avec **30 utilisateurs**. Bastien :
> *« 200 appareils connectés en simultané et des requêtes en veux-tu en voilà,
> ça m'inquiète fort. »* L'inquiétude était légitime, et la réponse est mesurée.
>
> Les trois documents de GRID sont dans `C:\Users\Operateur\Documents\RELTEL\`.
> **`INCIDENT-ET-DIMENSIONNEMENT.md` est à lire** : il est écrit pour être
> transposé à un projet de même architecture, et c'est exactement notre cas.

### 18.1 Pourquoi la panne de GRID ne peut pas se reproduire ici

GRID est tombé de **deux causes de conception**, pas de dimensionnement. Ni
l'une ni l'autre n'existe dans le Forum, et ce n'est pas de la chance : les
deux choix inverses sont commentés dans le code.

| Ce qui a tué GRID | Dans le Forum | |
|---|---|---|
| Un trigger diffuse **un message par écriture à tous les postes** (Realtime) | `grep -ri "realtime\|websocket\|subscribe"` sur `app/` et `sql/` → **zéro occurrence**. Il n'y a aucune diffusion | absent |
| Chaque poste répond par un rechargement complet = **16 requêtes** | sondage à intervalle fixe = **1 requête** (`api_etat`, `api_vitrine` ou `api_supervision`) | absent |
| Coût = écrivains **×** spectateurs, donc quadratique | coût = appareils ÷ intervalle, **indépendant de l'activité de la salle** | absent |
| 15 policies RLS et une vue d'autorisation évaluée **par ligne** → 333 à 538 ms la lecture | **RLS active partout, zéro policy** : il n'y a aucune vue d'autorisation à évaluer. `_exige_role()` lit une ligne d'`appareils` par sa clé | structurellement absent |
| Pool PostgREST de **10** | pool de **11** | **identique** |

**La différence n'est pas le nombre de téléphones, c'est le prix d'une
requête.** Une lecture GRID coûtait 400 ms en base, une lecture Forum en coûte
0,6 à 13. La saturation d'un pool, c'est *débit × temps de service* :

```
GRID    18 req/s x 0,4 s = 7,3 connexions en permanence, pool de 10
        + des rafales de 400 requetes toutes les 14 s -> il en aurait fallu 11,4
        -> la file grossit sans fin -> timeouts

FORUM   12 req/s x ~5 ms = 0,06 connexion sur 11, soit 0,5 % du pool
```

### 18.2 Ce que coûte `api_vitrine` selon le volume du journal

Le seul coût **non constant** de l'application, donc le seul analogue de la
cause n° 2 de GRID. Mesuré sur la base de production, dans une transaction
annulée par une exception : aucune ligne n'a survécu. Le banc est
`scripts/mesurer-vitrine.ps1`, rejouable tant que le journal est vide.

> ⚠️ **Ces temps varient d'une exécution à l'autre** — instance partagée,
> caches froids ou chauds. Deux passages au même volume de 3 000 lignes ont
> donné **13,14 ms puis 20,89 ms** le 16 au soir. C'est **l'ordre de grandeur**
> qui compte, pas la décimale : à 20 ms, les 140 vitrines occupent 0,09
> connexion sur 11. On reste à deux ordres de grandeur du moment où le pool
> commencerait à souffrir.

| journal | `api_vitrine` p50 | p95 | `api_etat` p50 | `api_supervision` p50 |
|---|---|---|---|---|
| 0 | 4,44 ms | 6,88 ms | 0,587 ms | 5,15 ms |
| 1 500 | 10,03 ms | 10,64 ms | 0,647 ms | 5,45 ms |
| **3 000** *(une vraie soirée)* | **13,14 ms** | 14,01 ms | 0,647 ms | 6,40 ms |
| 6 000 | 19,29 ms | 19,71 ms | 0,665 ms | 9,20 ms |
| 12 000 | 31,80 ms | 33,51 ms | 0,672 ms | 21,84 ms |
| 20 000 | **120,58 ms** | 144,25 ms | 0,681 ms | 34,28 ms |

Trois choses à retenir :

1. **`api_etat` est plat.** 0,59 ms à vide, 0,68 ms à 20 000 lignes. Les
   téléphones des garagistes ne coûteront rien, quoi qu'il arrive dans la
   soirée. Une vraie soirée pèse 2 000 à 3 000 lignes — la simulation de
   400 garages en avait produit 5 800, soit près du double du réel.
2. **Il y a un coude, entre 12 000 et 20 000 lignes** : le coût est multiplié
   par 4 quand un plan bascule. C'est 7× une vraie soirée, donc hors
   d'atteinte — mais si le journal explosait un jour, **la vitrine serait la
   première à souffrir, et brutalement**.
3. **La partie chère de `api_vitrine` n'est PAS celle qu'on croyait.**
   Décomposition à 20 000 lignes :

   ```
   podium garages ................. 44,20 ms   <- le vrai cout
   podiums stands + animations .... 29,44 ms   <-
   verifier_soldes() .............. 22,25 ms
   les 6 compteurs de journal ..... 13,90 ms
   journal en direct (40 lignes) ..  0,40 ms
   pg_stat_activity ...............  0,25 ms
   ```

   Les **podiums pèsent 74 ms sur 120** : trois `group by` sur tout le journal.
   Le commentaire de `sql/25_sante_detail.sql:118` — « `verifier_soldes()` est
   la partie chère, la clé à tourner sera de la sortir de la bande d'état » —
   reste **vrai pour `api_sante_detail`**, sa propre fonction. Il est **faux
   pour `api_vitrine`** : l'y appliquer ne récupérerait que 18 % du temps. Si
   un jour il faut tourner une clé sur la vitrine, **ce sont les podiums qu'il
   faut plafonner** (sur les dernières heures, ou en cache de 30 s).

### 18.3 Le banc du jour J — `scripts/banc-jour-j.ps1`

Les quatre bancs existants mesuraient chacun **un** profil. La panne de GRID
n'est venue d'aucun profil isolé : elle est venue de la **simultanéité**.

```powershell
.\scripts\banc-jour-j.ps1              # regime + meute, 3 min
.\scripts\banc-jour-j.ps1 -Facteur 10  # dix fois le rythme reel
```

344 appareils virtuels — 200 garages, 140 vitrines, 2 tablettes Bony,
2 hôtesses — **tous dans le même `Task.WaitAll`**, au rythme exact de
`app/config.js`. Puis **la meute** : les 344 dans la même milliseconde, trois
fois. Une sonde relève `pg_stat_activity` toutes les 600 ms pendant ce temps.

Trois garde-fous : il **refuse de démarrer si `journal > 0`** (le Forum a
commencé), il est **en lecture seule** sur les données du Forum, et il pose ses
344 sessions **en SQL plutôt que par `api_ouvrir`** — ouvrir 200 sessions par
la porte consommerait une place d'appareil sur 200 vrais garages. Il les efface
en sortant et le prouve.

**Régime nominal, 12 req/s, 344 appareils, 3 minutes :**

| profil | appels | p50 | p95 | p99 | échecs |
|---|---|---|---|---|---|
| garage `api_etat` | 1 198 | 98 ms | 293 ms | 382 ms | **0** |
| vitrine `api_vitrine` | 838 | 101 ms | 296 ms | 364 ms | **0** |
| Bony `api_supervision` | 36 | 97 ms | 169 ms | 204 ms | **0** |
| accueil recherche | 87 | 97 ms | 263 ms | 389 ms | **0** |

**À dix fois le rythme réel** (120 req/s soutenus, 13 652 requêtes) : **0 échec**,
p50 inchangé, et **6 connexions actives sur 11 au pic, 0,30 en moyenne**.

**La meute**, le scénario exact de GRID :

| | tour 1 (froid) | tour 2 | tour 3 (chaud) |
|---|---|---|---|
| 344 requêtes simultanées écoulées en | 6 962 ms | 2 296 ms | **1 751 ms** |
| échecs | 0 | 0 | 0 |

Si toute la salle sort son téléphone à la même seconde, **tout le monde a son
solde en moins de deux secondes et personne n'a d'erreur**. Le premier tour est
lent parce qu'il paie l'établissement des connexions TLS et la croissance du
pool de 5 à 11 : **c'est la première rafale de la journée qui sera la plus
lente, jamais les suivantes.**

> ⚠️ **`idle in transaction` est monté à 8 pendant la meute — et ce n'est PAS
> un problème.** C'est littéralement la signature de GRID (§3.1 de leur
> rapport). La différence tient à la colonne d'à côté : `actives` valait **1**
> au même instant. Des connexions en `idle in transaction` avec zéro requête
> active, c'est Postgres qui a fini et qui attend le client — le `ClientRead`.
> Chez GRID c'était le symptôme d'un goulot **devant** la base ; ici c'est un
> pool qui absorbe une rafale et rend la main. **Ne jamais lire `pool` ni
> `idle in transaction` sans lire `actives` en même temps.**

Pendant la meute, le débit réel atteint **~265 req/s avec 6 connexions
occupées** : le plafond est donc autour de 480 req/s, cohérent avec les
314 req/s mesurés le 15. À comparer aux **12 req/s attendus jeudi**.

### 18.4 🔴 Les trois batteries de tests DÉTRUISENT la base

**Trouvé en voulant les rejouer après le changement de `appareils_max`.** C'est
le piège le plus dangereux de tout le dossier, parce qu'il est **recommandé par
écrit** : `CLAUDE.md` et `README.md` disent tous les deux « rejouer les
114 tests après toute modification SQL », sans dire ce qu'ils font.

| Suite | Ce qu'elle fait à la base |
|---|---|
| `test-invariants.ps1` | **vide le journal** (en levant le verrou d'immuabilité), remet tous les soldes à 0, efface `inscrit_le`, **supprime tous les appareils**, libère la grille, vide `tentatives` |
| `test-bingo.ps1` | **exactement la même chose**, puis achète des cases avec six garages témoins |
| `test-porte.ps1` | n'efface rien, mais **ouvre de vrais garages par `api_ouvrir`** : elle crée des appareils, verse le bonus d'arrivée et **inscrit des garages qui ne sont pas venus**. Elle vide aussi `tentatives`, donc le frein anti-devinette |

Les deux premières sont `99_remise_a_zero.sql` sous un autre nom — et ce
fichier-là est interdit en rouge à trois endroits de la documentation. **Et
aucune des trois ne nettoie derrière elle** : elles laissent leurs garages
témoins, leurs cases achetées et leurs lignes de journal en base. Le seul
chemin documenté pour revenir à zéro après les avoir lancées est précisément le
script interdit.

Si personne ne l'a vu, c'est que l'ordre des opérations du 16 au soir l'a
masqué : tests → simulation → remise à zéro. La remise à zéro venait **après**.

> **Règle, désormais :** pendant le Forum, aucune des trois. Après une
> modification SQL faite le jour J — ce qui doit rester exceptionnel — la
> vérification est le contrôle d'état de `§1 bis` et rien d'autre :
> `journal`, `cases_prises`, `ecarts`, `verifier_portes()`, `verifier_badges()`.
> Ces cinq-là ne font que **lire**.

### 18.5 Ce qui a été changé, et ce qui ne l'a pas été

**`appareils_max` : 6 → 10.** Le seul risque de panne *visible* trouvé pendant
cette étude, et il n'a rien à voir avec la charge. `sql/13_porte.sql:185`
refuse le 11ᵉ appareil d'un garage, et **une place prise ne se rend pas** —
`journal.appareil_id` référence la ligne dès la première écriture. Scénario
réaliste : un gros garage vient à cinq, l'un d'eux navigue en privé ou vide ses
données, et la sixième personne reste dehors. **L'accueil ne peut rien pour
elle.** Le plafond ne protège rien — le portefeuille est partagé par garage de
toute façon. Passé à 10 le 16 au soir :

```powershell
.\scripts\push-sql.ps1 -Query "update config set valeur = '10' where cle = 'appareils_max'"
```

Effet immédiat, côté base, sans déploiement et sans recharger un seul
téléphone. **Les 114 tests n'ont volontairement PAS été rejoués** — voir §18.4 :
ils auraient effacé la base, et aucune fonction n'a été modifiée, seulement une
valeur de `config` lue à l'exécution. État relevé après : `journal 0 ·
cases 0 · écarts 0 · soldes 0 · 85 lots · 15 tickets · 0 collision de code ·
0 badge sans code`.

**Ce qui a été proposé et écarté :**

- **La gigue sur le sondage** (point C du §11) — mesurée inutile, voir §18.3.
  Elle coûterait un déploiement la veille au soir et un `Ctrl + Maj + R` sur
  tous les postes, pour supprimer un problème qui s'écoule en 1,3 s sans un
  échec.
- **Un interrupteur `config` sur les podiums de la vitrine** — le seul levier
  qui manque vraiment : si `api_vitrine` dérapait, il faudrait aujourd'hui
  écrire du SQL en direct sous pression. Le mettre derrière une clé
  transformerait ça en `update config`, **avec effet immédiat sur les
  140 téléphones et sans déploiement**, puisque c'est une fonction en base.
  Proposé, pas retenu : la probabilité mesurée est proche de zéro et la règle
  « ne pas sur-concevoir » tranche. À garder en tête pour 2027.

**Le levier qui n'existe pas, et qu'il faut connaître :** `sondageMs` est une
constante de `app/config.js`, donc dans le navigateur. On peut rendre une
requête **moins chère** en direct (c'est du SQL, effet immédiat partout) ; on ne
peut **pas réduire leur nombre** sans un déploiement *et* un rechargement sur
chaque appareil. C'est le seul angle mort du dispositif — sur un risque mesuré
à 3 % d'occupation du pool.

### 18.6 Les abonnements : la réponse est non, et elle est chiffrée

| Dépense | Ce que ça change | Verdict |
|---|---|---|
| **Cloudflare payant** | **rien.** `wrangler.jsonc` n'a aucun champ `main` : il n'y a pas une ligne de code Worker, et [les requêtes vers des ressources statiques sont gratuites et illimitées](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations) sur tous les plans. Cloudflare n'est même pas sur le chemin des données — tout part du téléphone vers Supabase | inutile |
| **Supabase Pro seul** | **ne change pas le pool PostgREST.** Le pool suit la taille de l'instance, pas le plan. Apporte les sauvegardes quotidiennes et le PITR | ne répond pas à la question posée |
| **Pro + compute Small** | pool et connexions plus larges ([60 → 90 connexions](https://supabase.com/docs/guides/platform/compute-and-disk)), **au prix d'un redémarrage de la base** — « moins de 2 minutes d'interruption ». Sans conséquence la veille, catastrophique à 11 h jeudi | à faire la veille ou pas du tout |
| **Le banc du §18.3** | transforme la peur en chiffre | 0 € |

Pour un événement d'une journée, la vraie protection des données n'est pas la
sauvegarde nocturne du plan Pro, c'est `exporter-journal.ps1` **toutes les
heures**.

### 18.7 Ce qui reste non mesuré, et qu'il faut dire tel quel

- **Le chemin d'écriture n'a pas été rejoué le 16 au soir** : impossible sans
  salir le journal. Il a été éprouvé le 15 par `simuler-forum.ps1` —
  5 800 écritures, 0 échec, 0 écart de solde. Ce n'est pas lui qui restait à
  prouver.
- **`api_garages_liste`** — les 1 456 garages téléchargés par les 29 appareils
  du personnel à leur connexion — n'a jamais été chronométrée. Chargée une fois
  par appareil, elle est négligeable *par construction* : c'est une déduction,
  pas une mesure.
- **Les 344 sessions partent d'UNE machine et d'UNE connexion.** Le p50 de
  ~100 ms est presque entièrement l'aller-retour réseau du poste ; le coût
  serveur est de 0,6 ms (`api_etat`) et 13 ms (`api_vitrine`). **Ce banc mesure
  Supabase, pas le wifi de la Grande Halle**, qui reste le risque le plus
  probable de la soirée et qu'aucun abonnement n'achète.
