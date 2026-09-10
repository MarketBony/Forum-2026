-- =====================================================================
--  Forum Pièces Bony 2026 — 14 — Une sonde de vie
--
--  POURQUOI. Pour savoir si l'application répond, il faut un appel qui
--  emprunte EXACTEMENT le chemin des téléphones : navigateur →
--  PostgREST → PostgreSQL → retour. La racine /rest/v1/ ne convient
--  pas : elle répond 401 avec la clé publique, parce que la description
--  de l'API est réservée à la clé de service. On croirait à une panne
--  alors que tout va bien.
--
--  api_sante() est cet appel : sans jeton, sans écriture, sans donnée
--  personnelle, et assez peu coûteux pour être appelé en boucle un soir
--  d'événement.
--
--  CORRECTION AU PASSAGE. verifier_portes() avait été accordée à anon,
--  mais elle n'est pas « security definer » : elle s'exécute donc avec
--  les droits de l'appelant, qui n'a aucun accès aux tables. Le droit
--  était sans effet et faussement rassurant. On le retire : ce rapport
--  de collision de codes n'a rien à faire dans le navigateur, il est
--  fait pour les scripts, qui passent par l'API de management.
-- =====================================================================

create or replace function public.api_sante()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return jsonb_build_object(
    'ok', true,
    'heure', to_char(now() at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI:SS'),
    -- Deux compteurs qui disent si la soirée avance, sans rien exposer
    -- de nominatif : ni nom de garage, ni code, ni solde individuel.
    'arrives', (select count(*) from garages where inscrit_le is not null),
    'cases_libres', (select count(*) from grille where achete_le is null),
    'ecritures_10min', (select count(*) from journal
                         where cree_le > now() - interval '10 minutes'));
end;
$$;

grant execute on function public.api_sante() to anon;
revoke execute on function public.verifier_portes() from anon;

select api_sante() as sonde;
