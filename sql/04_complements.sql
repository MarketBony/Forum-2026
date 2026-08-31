-- =====================================================================
--  Forum Pièces Bony 2026 — 04 — Compléments
--
--  api_garages_liste  : la liste complète, mise en cache dans le
--    téléphone du personnel. C'est ce qui permet à un animateur de
--    RECHERCHER UN GARAGE SANS RÉSEAU — sinon la file d'attente hors
--    ligne ne servirait à rien, faute de pouvoir désigner le garage.
--
--  api_journal_complet : export intégral pour l'espace Bony. Le plan
--    gratuit n'a pas de sauvegarde automatique : cet export est le
--    filet de sécurité, à déclencher une fois en milieu de soirée et
--    une fois à la fin.
--
--  api_lots : suivi de la remise des lots (§11).
-- =====================================================================

create or replace function public.api_garages_liste(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['animateur','fournisseur','admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'nom', nom, 'ville', ville, 'solde', solde)
                     order by nom)
    from garages where actif), '[]'::jsonb);
end;
$$;

create or replace function public.api_journal_complet(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', j.id,
             'quand', to_char(j.cree_le at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI:SS'),
             'garage', g.nom, 'ville', g.ville,
             'libelle', j.libelle, 'source', j.source, 'delta', j.delta,
             'stand', s.nom, 'animation', an.nom,
             'appareil', ap.libelle, 'cle', j.cle_idem)
           order by j.id)
    from journal j
    join garages g on g.id = j.garage_id
    left join stands s      on s.id = j.stand_id
    left join animations an on an.id = j.animation_id
    left join appareils ap  on ap.id = j.appareil_id), '[]'::jsonb);
end;
$$;

create or replace function public.api_lots(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['admin']);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'numero', gr.numero, 'lot', gr.lot, 'code_retrait', gr.code_retrait,
             'garage', g.nom, 'ville', g.ville, 'remis', gr.remis,
             'joue_a', to_char(gr.joue_le at time zone 'Europe/Paris', 'HH24:MI'))
           order by gr.remis, gr.joue_le)
    from grille gr
    join garages g on g.id = gr.garage_id
    where gr.gagnante and gr.garage_id is not null), '[]'::jsonb);
end;
$$;

grant execute on function public.api_garages_liste(text)  to anon;
grant execute on function public.api_journal_complet(text) to anon;
grant execute on function public.api_lots(text)            to anon;
