-- =====================================================================
--  Forum Pièces Bony 2026 — 25 — La santé de la base, dans l'application
--
--  POURQUOI CET APPEL EXISTE.
--  CONTEXTE.md le dit depuis le début : « le pool PostgREST plafonne à
--  11 connexions, c'est le vrai goulot, et il ne figure sur aucun tableau
--  de bord ». Le tableau de bord Supabase montre des requêtes et des
--  erreurs — c'est-à-dire des SYMPTÔMES, jamais la cause. Et il compte
--  comme « erreur » chaque refus voulu : un soir d'événement, il sera
--  rouge vif alors que tout va bien, ce qui est pire que s'il ne disait
--  rien.
--
--  api_sante_detail() rend les quatre chiffres qui, eux, annoncent une
--  catastrophe AVANT qu'elle arrive. Ils sont lus par la bande d'état en
--  haut de l'écran de supervision, toutes les dix secondes.
--
--  CE QUI COMPTE VRAIMENT, ET DANS QUEL ORDRE :
--
--   1. LE POOL POSTGREST. C'est le plafond dur. Quand les 11 connexions
--      sont prises, les téléphones suivants n'obtiennent RIEN — pas une
--      erreur lente, pas une file : rien. Et ces requêtes-là
--      n'apparaissent même pas dans pg_stat_statements, puisqu'elles
--      n'ont jamais obtenu de connexion. C'est l'angle mort total.
--
--   2. LES VERROUS EN ATTENTE. Zéro en permanence. Un seul verrou qui
--      dure, c'est une transaction coincée qui bloque les suivantes —
--      typiquement le « select ... for update » d'un achat de case.
--
--   3. LES TRANSACTIONS OUVERTES SANS RIEN FAIRE (idle in transaction).
--      Elles tiennent leurs verrous sans avancer. C'est la panne la plus
--      sournoise : la base n'est pas chargée, elle est bloquée.
--
--   4. LE RYTHME D'ÉCRITURE. Il ne dit pas la santé mais le CONTEXTE :
--      200 écritures à la minute avec un pool à 9, c'est une montée en
--      charge ; 0 écriture avec un pool à 9, c'est un blocage.
--
--  CE QUI N'EST PAS ICI, ET POURQUOI.
--  Le temps de réponse n'est pas mesuré en base : il se mesure dans le
--  NAVIGATEUR, aller-retour compris. C'est le seul chiffre qui voit le
--  wifi de la halle — et le wifi est, de tous les risques listés, le
--  plus probable. Une base à 2 ms derrière un wifi à 3 secondes est une
--  base en panne du point de vue d'un garagiste.
--
--  RÉSERVÉ À L'ÉQUIPE BONY. pg_stat_activity expose les requêtes en
--  cours ; rien de tout cela ne doit partir sur le téléphone d'un
--  garage. On ne rend d'ailleurs que des COMPTEURS, jamais un texte de
--  requête ni un nom d'utilisateur.
--
--  Coût mesuré : voir le contrôle en fin de fichier.
--
--  Rejouable.
-- =====================================================================

create or replace function public.api_sante_detail(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a           appareils;
  v_pool      integer;
  v_actives   integer;
  v_verrous   integer;
  v_bloquees  integer;
  v_max       integer;
begin
  a := _exige_role(p_jeton, array['admin']);

  -- « authenticator » est le rôle par lequel PostgREST se connecte :
  -- compter ses sessions, c'est compter le pool. Les autres connexions
  -- (sauvegardes, tableau de bord Supabase, ce script) ne le consomment
  -- pas et ne doivent donc pas être mêlées au compte.
  select count(*) filter (where usename = 'authenticator'),
         count(*) filter (where state = 'active'),
         count(*) filter (where wait_event_type = 'Lock'),
         count(*) filter (where state = 'idle in transaction')
    into v_pool, v_actives, v_verrous, v_bloquees
    from pg_stat_activity;

  select setting::int into v_max from pg_settings where name = 'max_connections';

  return jsonb_build_object(
    -- le goulot, et sa borne
    'pool',            v_pool,
    'pool_max',        11,
    'connexions_max',  v_max,
    -- les deux signaux de blocage : ils doivent rester à zéro
    'verrous',         v_verrous,
    'bloquees',        v_bloquees,
    'actives',         v_actives,
    -- le contexte : sans lui, un pool à 9 ne se lit pas
    'ecritures_min',   (select count(*) from journal
                         where cree_le > now() - interval '1 minute'),
    'ecritures_10min', (select count(*) from journal
                         where cree_le > now() - interval '10 minutes'),
    -- l'intégrité, qui ne doit jamais bouger de zéro
    'ecarts',          (select count(*) from verifier_soldes()),
    'heure',           to_char(now() at time zone 'Europe/Paris', 'HH24:MI:SS'));
end;
$$;

-- ---------------------------------------------------------------------
-- Contrôle : la fonction répond, et elle est assez peu coûteuse pour
-- être appelée toutes les dix secondes pendant six heures.
--
-- verifier_soldes() est la partie chère (elle balaie le journal) : si
-- elle devient lente le jour J, c'est CE contrôle qui le dira, et la
-- clé à tourner sera de la sortir de la bande d'état.
-- ---------------------------------------------------------------------
do $$
declare
  v_t0 timestamptz;
  v_ms numeric;
begin
  v_t0 := clock_timestamp();
  perform (select count(*) filter (where usename = 'authenticator') from pg_stat_activity);
  perform (select count(*) from public.journal where cree_le > now() - interval '1 minute');
  perform (select count(*) from public.verifier_soldes());
  v_ms := extract(epoch from (clock_timestamp() - v_t0)) * 1000;
  raise notice 'api_sante_detail : % ms par appel', round(v_ms, 2);
  if v_ms > 200 then
    raise exception 'sonde trop coûteuse : % ms, elle serait appelée toutes les 10 s', round(v_ms, 2);
  end if;
end;
$$;
