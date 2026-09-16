-- =====================================================================
--  Forum Pièces Bony 2026 — 32 — Les fonctions internes se ferment pour de bon
--
--  LA FAILLE. Les fichiers 02 et 30 contenaient bien des lignes
--  `revoke all on function public._xxx(...) from anon, authenticated;`.
--  Elles n'ont **jamais rien fermé**.
--
--  PostgreSQL accorde `EXECUTE` à **PUBLIC** sur toute fonction créée,
--  par défaut. Retirer la concession explicite à `anon` ne retire pas
--  celle de `PUBLIC` — et `anon` est membre de `PUBLIC`. Dans
--  `pg_proc.proacl`, ça se lit à la première entrée : `=X/postgres`,
--  sans rôle devant le `=`, c'est PUBLIC.
--
--  MESURÉ LE 17 SEPTEMBRE À 00 h 11, par la vraie porte HTTPS et avec la
--  seule clé publique du front :
--
--      POST /rest/v1/rpc/_ecrire   ->  HTTP 400  GARAGE_INCONNU
--
--  Ce refus est un refus MÉTIER : la fonction s'est exécutée. Avec un
--  identifiant de garage valide — que chaque téléphone reçoit dans la
--  réponse de `api_etat` — et un `p_delta` non nul, elle aurait ÉCRIT.
--  N'importe qui pouvait donc se créditer des points sans passer par
--  aucun contrôle de rôle, et l'invariant `solde = somme(journal)`
--  serait resté à zéro écart : la console de santé n'aurait rien vu.
--
--  Quatre fonctions `security definer` étaient dans ce cas :
--    _ecrire       écrit au journal et met à jour le solde
--    _personnel    la porte des 31 PIN, SANS le frein anti-devinette
--                  qui vit dans api_ouvrir
--    _appareil     lit une ligne d'appareil par son jeton
--    _exige_role   rend l'appareil et son rôle
--  Plus `_code_vitrine`, qui fabrique un code de vitrine à partir d'une
--  clé source.
--
--  POURQUOI LES AUTRES N'ÉTAIENT PAS EXPOSÉES. `verifier_soldes()`,
--  `_quota_stand()` et les autres ne sont **pas** `security definer` :
--  elles s'exécutent avec les droits de l'appelant, et la RLS sans
--  policy leur refuse la lecture des tables. Mesuré : HTTP 401,
--  `42501 permission denied for table garages`. C'est la conception du
--  projet qui les a sauvées, pas les `revoke`.
--
--  CE QUI N'EST PAS TOUCHÉ, ET POURQUOI :
--    * `norm()`, `norm_requete()`, `cfg_int()` — `norm()` est utilisée
--      par la colonne GÉNÉRÉE `garages.recherche`. Lui retirer EXECUTE
--      casserait tout insert ou update sur `garages`. On ne touche pas.
--    * `journal_immuable()`, `_participants_maj()` — fonctions de
--      trigger. Appelées directement elles refusent déjà toutes seules
--      (« can only be called as a trigger »), et bricoler leurs droits
--      la veille du Forum n'apporte rien.
--    * les fonctions non `security definer` déjà bloquées par la RLS —
--      les fermer davantage n'ajoute aucune sécurité aujourd'hui et
--      ajoute un risque. On s'en tient à ce qui change quelque chose.
--
--  LES api_* CONTINUENT DE MARCHER. Un appel imbriqué dans une fonction
--  `security definer` s'exécute sous l'identité du PROPRIÉTAIRE
--  (postgres), qui garde son EXECUTE explicite. `api_participation`
--  appelle donc toujours `_ecrire` sans difficulté.
--
--  ⚠️ CE DERNIER POINT EST UN RAISONNEMENT, PAS UNE MESURE. Il est
--  solide — un appel imbriqué sous `security definer` s'exécute sous
--  l'identité du propriétaire — mais il n'a PAS été rejoué de bout en
--  bout, faute de pouvoir écrire dans le journal la nuit précédant le
--  Forum. **Après avoir passé ce fichier, éprouver une entrée de garage
--  par un vrai code** (`api_ouvrir` appelle `_ecrire` pour verser le
--  bonus d'arrivée). Si elle passe, le reste passe : c'est le même
--  mécanisme pour les six flux. Et si elle ne passait pas, le retour
--  arrière tient en une ligne :
--      grant execute on function public._ecrire(uuid,integer,text,text,text,uuid,uuid,uuid) to public;
--
--      .\scripts\push-sql.ps1 -File sql\32_verrou_fonctions_internes.sql
-- =====================================================================

begin;

-- `from public` est le mot qui manquait. On retire aussi les
-- concessions explicites, pour que la fermeture ne dépende pas de
-- l'ordre dans lequel les fichiers ont été rejoués.
revoke execute on function public._ecrire(uuid, integer, text, text, text, uuid, uuid, uuid)
  from public, anon, authenticated;

revoke execute on function public._personnel(text, text)
  from public, anon, authenticated;

revoke execute on function public._appareil(text)
  from public, anon, authenticated;

revoke execute on function public._exige_role(text, text[])
  from public, anon, authenticated;

revoke execute on function public._code_vitrine(text, integer)
  from public, anon, authenticated;

commit;

-- ---------------------------------------------------------------------
-- CONTRÔLE — les cinq doivent être fermées à anon, et les 24 api_*
-- doivent rester ouvertes. Un fichier qui fermerait une porte de trop
-- se verrait ici plutôt qu'au premier garagiste.
-- ---------------------------------------------------------------------
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and p.proname in ('_ecrire','_personnel','_appareil','_exige_role','_code_vitrine')
      and has_function_privilege('anon', p.oid, 'EXECUTE'))            as internes_encore_ouvertes,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.proname like 'api\_%'
      and has_function_privilege('anon', p.oid, 'EXECUTE'))            as api_ouvertes_a_anon,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.proname like 'api\_%')
                                                                        as api_total;
