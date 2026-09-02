-- =====================================================================
--  Forum Pièces Bony 2026 — 13 — Une seule porte
--
--  LE DÉFAUT : il y avait deux champs de saisie, sur deux écrans. Le
--  garagiste tapait son code sur l'accueil ; l'animateur, le
--  fournisseur, l'hôtesse et Bony devaient d'abord trouver le lien
--  « Équipe », en petit, en haut à droite. Deux fois sur trois on tape
--  son code dans le mauvais champ — et le champ garage refusait un PIN
--  avant même de l'envoyer, puisque son clavier interdit les 0 et les 1.
--
--  LA CORRECTION : un seul champ, une seule fonction. On tape son code,
--  la base reconnaît toute seule de quelle porte il s'agit.
--
--  L'ORDRE : le personnel d'abord. C'est un ensemble fermé d'une
--  dizaine de codes que Bony maîtrise ; les garages sont 1 407. En cas
--  de collision c'est donc le personnel qui l'emporterait — et un
--  garage bloqué à l'entrée avec 150 personnes derrière lui coûte bien
--  plus cher qu'un animateur qu'on redote d'un PIN. verifier_portes(),
--  en bas de ce fichier, garantit que le cas ne se présente pas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. La reconnaissance du personnel, extraite pour être réutilisable
--
--    Renvoie null quand le code n'est pas un code de personnel : c'est
--    une réponse, pas une erreur — il reste la porte des garages à
--    essayer derrière.
-- ---------------------------------------------------------------------
create or replace function public._personnel(p_jeton text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_an  animations;
  v_st  stands;
  v_pin text;
begin
  -- même tolérance que pour les garages : espaces, tirets, minuscules
  v_pin := upper(regexp_replace(coalesce(p_pin, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_pin) < 4 then return null; end if;

  select * into v_an from animations
   where upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')) = v_pin and actif;
  if found then
    insert into appareils (jeton, role, animation_id, libelle)
    values (p_jeton, 'animateur', v_an.id, v_an.nom)
    on conflict (jeton) do update
      set role = 'animateur', animation_id = v_an.id, stand_id = null,
          garage_id = null, libelle = v_an.nom, vu_le = now();
    return jsonb_build_object('role', 'animateur', 'animation_id', v_an.id,
      'libelle', v_an.nom, 'cout', v_an.cout,
      'bareme', (select jsonb_agg(jsonb_build_object(
                   'id', id, 'libelle', libelle, 'points', points)
                 order by ordre, points desc)
                 from bareme where animation_id = v_an.id));
  end if;

  select * into v_st from stands
   where upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')) = v_pin and actif;
  if found then
    insert into appareils (jeton, role, stand_id, libelle)
    values (p_jeton, 'fournisseur', v_st.id, v_st.nom)
    on conflict (jeton) do update
      set role = 'fournisseur', stand_id = v_st.id, animation_id = null,
          garage_id = null, libelle = v_st.nom, vu_le = now();
    return jsonb_build_object('role', 'fournisseur', 'stand_id', v_st.id,
      'libelle', v_st.nom, 'plafond_operation', v_st.plafond_operation);
  end if;

  if v_pin = upper(coalesce((select valeur from config where cle = 'pin_accueil'), '@@aucun@@')) then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'accueil', 'Accueil du Forum')
    on conflict (jeton) do update
      set role = 'accueil', libelle = 'Accueil du Forum',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now();
    return jsonb_build_object('role', 'accueil', 'libelle', 'Accueil du Forum');
  end if;

  if v_pin = upper(coalesce((select valeur from config where cle = 'pin_admin'), '@@aucun@@')) then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'admin', 'Équipe Bony')
    on conflict (jeton) do update
      set role = 'admin', libelle = 'Équipe Bony',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now();
    return jsonb_build_object('role', 'admin', 'libelle', 'Équipe Bony');
  end if;

  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. api_connexion garde son contrat : les scripts de test et les
--    appareils déjà déployés continuent de fonctionner à l'identique.
-- ---------------------------------------------------------------------
create or replace function public.api_connexion(p_jeton text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_r jsonb;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE' using detail = 'Jeton d''appareil trop court.';
  end if;
  if length(trim(coalesce(p_pin, ''))) < 4 then
    raise exception 'PIN_INVALIDE' using detail = 'Le code doit faire au moins 4 chiffres.';
  end if;
  v_r := _personnel(p_jeton, p_pin);
  if v_r is null then
    raise exception 'PIN_INCONNU' using detail = 'Code non reconnu.';
  end if;
  return v_r;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. La porte unique
--
--    Un code refusé revient en RÉSULTAT et non en exception : c'est ce
--    qui permet au frein sur les tentatives d'être réellement compté
--    (une exception annulerait l'insertion de la tentative avec elle).
-- ---------------------------------------------------------------------
create or replace function public.api_ouvrir(p_jeton text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code   text;
  v_r      jsonb;
  v_g      garages;
  v_bonus  integer := cfg_int('bonus_inscription', 10);
  v_max    integer := cfg_int('appareils_max', 3);
  v_essais integer := cfg_int('tentatives_max', 8);
  v_app    uuid;
  v_nb     integer;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE'
      using detail = 'Rechargez la page pour repartir sur un appareil propre.';
  end if;

  -- On garde les chiffres 0 et 1 : ils sont exclus de l'alphabet des
  -- codes garage pour éviter la confusion avec O et I, mais les PIN du
  -- personnel en contiennent. Les filtrer ici viderait « 1001 ».
  v_code := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(v_code) < 4 then
    raise exception 'CODE_TROP_COURT'
      using detail = 'Un code fait au moins 4 caractères.';
  end if;

  -- ---- porte du personnel ----
  v_r := _personnel(p_jeton, v_code);
  if v_r is not null then
    return v_r || jsonb_build_object('porte', 'personnel');
  end if;

  -- ---- porte des garages ----
  select count(*) into v_nb from tentatives
   where jeton = p_jeton and quand > now() - interval '5 minutes';
  if v_nb >= v_essais then
    return jsonb_build_object(
      'porte',  'refus',
      'erreur', 'TROP_DE_TENTATIVES',
      'detail', 'Trop d''essais. Patientez une minute, ou demandez à l''accueil.');
  end if;

  select * into v_g from garages where upper(code) = v_code and actif;
  if not found then
    insert into tentatives (jeton, code) values (p_jeton, v_code);
    return jsonb_build_object(
      'porte',  'refus',
      'erreur', 'CODE_INCONNU',
      'detail', 'Ce code ne correspond à rien. Vérifiez-le, ou demandez à l''accueil.',
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

  return api_etat(p_jeton) || jsonb_build_object('porte', 'garage');
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Le garde-fou : aucun code garage ne doit valoir un PIN du
--    personnel. À relancer après tout changement de PIN.
-- ---------------------------------------------------------------------
create or replace function public.verifier_portes()
returns table(pin text, porte text, garage text)
language sql
stable
set search_path = public, pg_temp
as $$
  with pins as (
    select upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')) as p,
           'animation ' || nom as porte from animations where actif
    union all
    select upper(regexp_replace(code_pin, '[^A-Za-z0-9]', '', 'g')),
           'stand ' || nom from stands where actif
    union all
    select upper(valeur), cle from config where cle in ('pin_admin', 'pin_accueil')
  )
  select pins.p, pins.porte, g.nom
  from pins join garages g on upper(g.code) = pins.p and g.actif;
$$;

grant execute on function public.api_ouvrir(text, text)     to anon;
grant execute on function public.api_connexion(text, text)  to anon;
grant execute on function public.verifier_portes()          to anon;
revoke execute on function public._personnel(text, text) from anon;

select (select count(*)::int from verifier_portes())                    as collisions,
       (select count(*)::int from garages where actif)                  as codes_garage,
       (select count(*)::int from animations where actif)
       + (select count(*)::int from stands where actif) + 2             as codes_personnel;
