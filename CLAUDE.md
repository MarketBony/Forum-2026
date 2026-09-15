# Consignes de travail — Le Grand Bal des Fournisseurs

**Lire [`CONTEXTE.md`](CONTEXTE.md) avant la première modification.** Ce fichier-ci
ne contient que les règles à respecter en permanence.

Événement : **jeudi 17 septembre 2026**, Grande Halle d'Auvergne. Interlocuteur :
Bastien Fuziol, service marketing de Bony Automobile — technique sans être
développeur, tutoie, demande des preuves chiffrées.

---

## Les règles non négociables

**Mesurer, jamais affirmer.** Toute affirmation de performance, de capacité ou de
correction doit être adossée à un chiffre obtenu sur la vraie base. « Ça devrait
tenir » n'est pas une réponse ; un tableau de mesures en est une.

**Rejouer les 109 tests après toute modification SQL.** Ils tournent contre la base
de production, sans mock.

```powershell
.\scripts\test-porte.ps1 ; .\scripts\test-invariants.ps1 ; .\scripts\test-bingo.ps1
```

**Vérifier le déploiement après chaque `git push`.** Les builds Cloudflare ont
échoué **en silence** deux fois sur une douzaine de poussées, et l'utilisateur a
perdu une session à croire qu'un correctif ne marchait pas alors qu'il n'était
jamais parti. Incrémenter `VERSION` dans `app/sw.js`, pousser, puis :

```powershell
(New-Object System.Net.WebClient).DownloadString(
  'https://forum-2026.bonyauto-mobile.workers.dev/sw.js?t=' + (Get-Random)
) -match "const VERSION = '([^']+)'" ; $Matches[1]
```

**Commentaires en français, et ils expliquent le POURQUOI.** Le code est commenté
pour que Bastien puisse le relire seul l'an prochain. Un commentaire qui décrit un
piège vaut dix commentaires qui paraphrasent une ligne.

**Le terrain de l'utilisateur l'emporte sur le raisonnement.** S'il dit qu'une
chose se passe autrement au Forum, c'est son Forum.

**Ne pas sur-concevoir.** Un garagiste, un verre à la main, dans le bruit, doit y
arriver du premier coup. Toute mécanique qui demande une explication est à revoir.

**Signaler ce qui n'a pas été vérifié.** Ne jamais présenter comme éprouvé ce qui
n'a pas été testé.

---

## Environnement

- **Windows, PowerShell 5.1.** Pas de `&&` ni de `||` : `; if ($?) { }`.
- **Pas de Node, pas de build.** Modules ES natifs servis tels quels. C'est
  délibéré : ne pas introduire de chaîne de compilation.
- **Tous les `.ps1` ont un BOM UTF-8.** Sans lui, PowerShell 5.1 les lit en CP1252
  et les comparaisons accentuées cassent silencieusement. **Le conserver.**
- **`System.Net.Http.HttpClient`, jamais `Invoke-WebRequest`** dans les scripts de
  test : `Invoke-WebRequest` ne rend pas le corps des réponses 4xx, et son
  `.Content` décode les accents selon un en-tête que Supabase n'annonce pas
  toujours — « Autos République » revenait en « Autos RÃ©publique ».
- **Ne jamais nommer un paramètre `$args`** — variable automatique, le corps part
  vide et PostgREST répond « function without parameters not found ».
- **`ConvertFrom-Json` rend un tableau comme UN SEUL objet**, sans l'énumérer.
  `$x = @(… | ConvertFrom-Json)` l'emballe donc dans un tableau à un élément :
  assigner **sans** `@()`, et compter avec `@()` au moment de compter.
- **`$x = if (…) { @(…) } else { @() }` déroule le tableau** : à un seul élément,
  `$x` devient l'objet et `.Count` rend `$null`. Affecter **hors** du `if`.
- **`Start-Process -ArgumentList` en tableau ne met aucun guillemet** : un chemin
  contenant un espace — et le projet vit dans `APP FORUM` — se coupe en deux.
  Passer une **chaîne** avec les guillemets posés à la main.
- **Fichiers temporaires dans le scratchpad**, pas à la racine du projet.

> Ces quatre derniers points ont tous coûté une séance de débogage, et aucun ne
> se voit : le script ne plante pas, il fait silencieusement autre chose. Le
> détail de chacun est au §15 de `CONTEXTE.md`.

---

## Architecture, en trois phrases

Front statique sur Cloudflare Workers (aucun code serveur), navigateur qui appelle
directement les fonctions `api_*` de Supabase en RPC. **RLS active sur toutes les
tables avec zéro policy** : les 23 fonctions `security definer` sont les seules
portes d'entrée. Le journal est en **ajout seul** — une erreur se corrige par une
écriture inverse, jamais par une modification.

### Invariants à ne pas casser

| Invariant | Garanti par |
|---|---|
| `garages.solde` = somme du journal | `verifier_soldes()`, affiché en supervision |
| Aucun double crédit | `cle_idem` unique, générée par le client, jamais régénérée |
| Une case = un seul gagnant | `select ... for update` dans `api_jouer_case` |
| Aucun solde négatif | contrôle dans `_ecrire` |
| Aucun code garage = un PIN personnel | `verifier_portes()`, à relancer après tout changement de PIN |
| Le journal ne se modifie pas | trigger `journal_pas_de_modif` |
| Aucun badge sans code utilisable | `verifier_badges()`, à relancer après tout import |
| Un import de listing rejoué ne duplique rien | `cle_source` unique dans `participants` |

**Le générateur de badges est un outil local, à part.** Il lit la table
`participants` et n'écrit jamais dans l'application ; aucune fonction `api_*` ne
la touche ; `wrangler.jsonc` ne sert que `app/`, donc `badges/` n'est **jamais
déployé** — un badge porte le code d'accès de son porteur. Tout est au §15 de
`CONTEXTE.md`, y compris les neuf pièges payés pour y arriver.

---

## Pièges déjà payés — ne pas les redécouvrir

**L'alphabet des codes garage exclut `O`, `I`, `0`, `1`.** Mais les PIN du
personnel contiennent des 0 et des 1. La normalisation de saisie garde `A-Z0-9` ;
l'alphabet restreint ne sert qu'à la **génération**.

**Un code refusé est un résultat, pas une exception.** Une exception annulerait la
transaction, donc l'enregistrement de la tentative, et le frein anti-devinette ne
compterait jamais.

**`feDisplacementMap` déforme le contenu de l'élément filtré**, pas seulement ce
qu'on voit à travers. Le filtre est porté par une couche vide dédiée — la
« vitre ». Lire le commentaire en tête de `app/js/verre.js` avant d'y toucher.

**`/rest/v1/` répond 401 avec la clé publique** — c'est normal, pas une panne. La
sonde de vie est `api_sante()`.

**`pg_stat_statements` porte sur plusieurs jours**, et les requêtes qui n'ont
jamais obtenu de connexion n'y figurent pas : une saturation de pool y est
structurellement invisible.

**Le pool PostgREST plafonne à 11 connexions.** C'est le vrai goulot, et il ne
figure sur aucun tableau de bord. **Mais compter ses connexions ne mesure PAS son
occupation** : un pool ne rend jamais ses connexions, il grandit jusqu'à son
plafond et les garde `idle`. Mesuré le 15 septembre, la console affichait
« 11/11 · critique » en permanence pendant que tout répondait en 105 ms.
L'occupation, c'est `state = 'active'` **parmi** les connexions `authenticator`.

**Une grille CSS à deux colonnes avec trois enfants** place le troisième en
colonne 1 : déclarer `grid-column` explicitement.

---

## Sécurité

- Le dépôt est **privé** et doit le rester.
- `.env.local` n'est pas versionné. Seule la clé `publishable` est dans le front.
- `exports/` est ignoré : les exports contiennent les codes d'accès des garages.
- **Aucun code d'accès dans un document destiné à être partagé** — la présentation
  à la direction n'en contient volontairement aucun.
- Ne jamais inventer un nom de garage ni une donnée client. Une commune se
  reconstitue depuis un code postal (donnée publique) ; une raison sociale, non.
