-- =====================================================================
--  Forum Pièces Bony 2026 — 12 — « st bonnet » doit trouver Saint-Bonnet
--
--  Les noms stockés sont développés — « Saint-Bonnet », « Sainte-Croix »
--  — parce que c'est ce qu'un garagiste doit lire sur son téléphone.
--  Mais une hôtesse pressée tape l'abréviation. On développe donc st et
--  ste du côté de la REQUÊTE, jamais du côté des données.
--
--  L'ordre compte : sainte avant saint, sinon « ste » deviendrait
--  « saint + e ».
-- =====================================================================

create or replace function public.norm_requete(t text)
returns text
language sql
immutable
strict
parallel safe
as $$
  select regexp_replace(
           regexp_replace(public.norm(t), '\mste\M', 'sainte', 'g'),
           '\mst\M', 'saint', 'g')
$$;

-- ---------------------------------------------------------------------
-- Les deux recherches passent à la nouvelle normalisation
-- ---------------------------------------------------------------------
create or replace function public.api_accueil_chercher(p_jeton text, p_q text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_q text;
begin
  a := _exige_role(p_jeton, array['accueil','admin']);

  v_q := trim(coalesce(p_q, ''));
  if length(v_q) < 2 then
    raise exception 'RECHERCHE_TROP_COURTE'
      using detail = 'Tapez au moins deux caractères : un nom, une commune ou un code postal.';
  end if;

  return coalesce((
    select jsonb_agg(x order by x->>'nom')
    from (
      select jsonb_build_object(
               'id', id, 'nom', nom, 'ville', ville, 'cp', cp,
               'code', code,
               'arrive', inscrit_le is not null,
               'arrive_a', to_char(inscrit_le at time zone 'Europe/Paris', 'HH24:MI'),
               'appareils', (select count(*) from appareils ap where ap.garage_id = garages.id)
             ) as x, nom
      from garages
      where actif
        and (recherche like '%' || norm_requete(v_q) || '%' or cp like v_q || '%')
      order by nom
      limit 15
    ) s), '[]'::jsonb);
end;
$$;

create or replace function public.api_chercher(p_jeton text, p_q text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['animateur','fournisseur','admin']);
  return coalesce((
    select jsonb_agg(x order by x->>'nom')
    from (
      select jsonb_build_object('id', id, 'nom', nom,
               'ville', coalesce(nullif(cp, '') || ' ', '') || ville,
               'solde', solde) as x, nom
      from garages
      where actif and inscrit_le is not null
        and (coalesce(p_q, '') = ''
             or recherche like '%' || norm_requete(p_q) || '%'
             or cp like p_q || '%')
      order by nom limit 12
    ) s), '[]'::jsonb);
end;
$$;

grant execute on function public.norm_requete(text)              to anon;
grant execute on function public.api_accueil_chercher(text,text) to anon;
grant execute on function public.api_chercher(text,text)         to anon;

select norm_requete('st bonnet')   as abrege,
       norm_requete('ste croix')   as abrege_feminin,
       norm_requete('Saint-Céré')  as deja_developpe,
       (select count(*)::int from garages
         where recherche like '%' || norm_requete('st bonnet') || '%') as trouve_st_bonnet;
