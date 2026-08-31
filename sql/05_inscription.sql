-- =====================================================================
--  Forum Pièces Bony 2026 — 05 — Recherche d'inscription
--
--  Un téléphone qui vient de scanner le QR code n'a encore aucun rôle :
--  il ne peut pas appeler api_chercher, réservée au personnel. Il lui
--  faut pourtant trouver son garage dans la liste des invités.
--
--  Cette fonction est donc ouverte, avec trois garde-fous :
--   - un code d'événement, imprimé dans le QR code, que le participant
--     n'a jamais à saisir. Ce n'est pas un secret cryptographique :
--     juste de quoi empêcher qu'on aspire la liste des clients de Bony
--     depuis l'extérieur, sans être sur place.
--   - deux caractères minimum dans la recherche ;
--   - huit résultats au maximum, et AUCUN solde renvoyé.
-- =====================================================================

insert into public.config (cle, valeur, description) values
  ('code_evenement', 'bal2026',
   'Code porté par le QR code, exigé pour la recherche d''inscription')
on conflict (cle) do nothing;

create or replace function public.api_garages_invites(p_code text, p_q text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(p_code, '') <> coalesce((select valeur from config where cle = 'code_evenement'), '@@') then
    raise exception 'CODE_EVENEMENT_INVALIDE'
      using detail = 'Rescannez le QR code présent sur place.';
  end if;

  if length(coalesce(trim(p_q), '')) < 2 then
    raise exception 'RECHERCHE_TROP_COURTE'
      using detail = 'Tapez au moins deux lettres du nom de votre garage.';
  end if;

  return coalesce((
    select jsonb_agg(x order by x->>'nom')
    from (
      select jsonb_build_object('id', id, 'nom', nom, 'ville', ville) as x
      from garages
      where actif and recherche like '%' || norm(p_q) || '%'
      order by nom
      limit 8
    ) s), '[]'::jsonb);
end;
$$;

grant execute on function public.api_garages_invites(text, text) to anon;
