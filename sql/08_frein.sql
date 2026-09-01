-- =====================================================================
--  Forum Pièces Bony 2026 — 08 — Correction du frein sur les tentatives
--
--  LE BUG : api_entrer enregistrait la tentative ratée PUIS levait une
--  exception. Or une exception annule la transaction — y compris
--  l'enregistrement de la tentative. Le compteur ne montait donc jamais
--  et le frein était purement décoratif.
--
--  LA CORRECTION : un code refusé n'est plus une exception, c'est un
--  RÉSULTAT. La fonction renvoie { erreur, detail } avec un HTTP 200, la
--  transaction va au bout, et la tentative est bien comptée.
--
--  Les autres refus (jeton absent, code trop court, plafond d'appareils)
--  continuent de lever une exception : ils n'ont rien à compter.
-- =====================================================================

create or replace function public.api_entrer(p_jeton text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code   text;
  v_g      garages;
  v_bonus  integer := cfg_int('bonus_inscription', 10);
  v_max    integer := cfg_int('appareils_max', 3);
  v_essais integer := cfg_int('tentatives_max', 8);
  v_app    uuid;
  v_nb     integer;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE'
      using detail = 'Rechargez la page depuis le QR code.';
  end if;

  -- on tolère les espaces, les tirets et les minuscules à la saisie
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_code) < 4 then
    raise exception 'CODE_TROP_COURT'
      using detail = 'Votre code fait 4 caractères.';
  end if;

  select count(*) into v_nb from tentatives
   where jeton = p_jeton and quand > now() - interval '5 minutes';
  if v_nb >= v_essais then
    return jsonb_build_object(
      'erreur', 'TROP_DE_TENTATIVES',
      'detail', 'Trop d''essais. Patientez une minute, ou demandez à l''accueil.');
  end if;

  select * into v_g from garages where upper(code) = v_code and actif;
  if not found then
    -- pas d'exception ici : sinon cette insertion serait annulée avec elle
    insert into tentatives (jeton, code) values (p_jeton, v_code);
    return jsonb_build_object(
      'erreur', 'CODE_INCONNU',
      'detail', 'Ce code ne correspond à aucun garage. Vérifiez-le, ou demandez à l''accueil.',
      'restantes', greatest(0, v_essais - v_nb - 1));
  end if;

  if not exists (select 1 from appareils where jeton = p_jeton and garage_id = v_g.id) then
    select count(*) into v_nb from appareils where garage_id = v_g.id;
    if v_nb >= v_max then
      raise exception 'TROP_D_APPAREILS'
        using detail = format('Ce garage a déjà %s appareils connectés. Voyez avec l''accueil.', v_nb);
    end if;
  end if;

  insert into appareils (jeton, role, garage_id, libelle)
  values (p_jeton, 'garage', v_g.id, v_g.nom)
  on conflict (jeton) do update
    set garage_id = excluded.garage_id, role = 'garage',
        libelle = excluded.libelle, vu_le = now()
  returning id into v_app;

  if v_bonus > 0 then
    perform _ecrire(v_g.id, v_bonus, 'Bienvenue au Forum', 'inscription',
                    'inscription:' || v_g.id::text, v_app);
  end if;

  update garages set inscrit_le = coalesce(inscrit_le, now()) where id = v_g.id;
  delete from tentatives where jeton = p_jeton;     -- compteur remis à zéro

  return api_etat(p_jeton);
end;
$$;

grant execute on function public.api_entrer(text, text) to anon;

-- Ménage : les tentatives de plus d'une heure n'ont plus d'intérêt.
delete from public.tentatives where quand < now() - interval '1 hour';
