-- =====================================================================
--  Forum Pièces Bony 2026 — 09 — Le poste d'accueil
--
--  Un garagiste qui se présente sans son code, ce n'est pas une
--  hypothèse : c'est une certitude sur 150 arrivées. Les hôtesses ont
--  donc leur propre profil, avec exactement deux pouvoirs :
--    - chercher un garage parmi les 1 407 invités, arrivé ou non ;
--    - lire son code d'accès pour le lui donner.
--
--  Elles ne voient NI le journal, NI les soldes, NI la supervision, et
--  ne peuvent pas corriger de points. C'est du personnel d'extra : leur
--  donner le code administrateur serait absurde.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Le code du poste d'accueil
-- ---------------------------------------------------------------------
insert into public.config (cle, valeur, description) values
  ('pin_accueil', '4200', 'Code du poste d''accueil — À CHANGER avant l''événement')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- 2. Le rôle « accueil » devient légitime
-- ---------------------------------------------------------------------
alter table public.appareils drop constraint if exists appareils_role_check;
alter table public.appareils
  add constraint appareils_role_check
    check (role in ('garage','animateur','fournisseur','admin','accueil'));

-- ---------------------------------------------------------------------
-- 3. Connexion : on ajoute le poste d'accueil aux codes reconnus
-- ---------------------------------------------------------------------
create or replace function public.api_connexion(p_jeton text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_an  animations;
  v_st  stands;
  v_pin text;
  v_app uuid;
begin
  if p_jeton is null or length(p_jeton) < 20 then
    raise exception 'JETON_INVALIDE' using detail = 'Jeton d''appareil trop court.';
  end if;
  v_pin := trim(coalesce(p_pin, ''));
  if length(v_pin) < 4 then
    raise exception 'PIN_INVALIDE' using detail = 'Le code doit faire au moins 4 chiffres.';
  end if;

  select * into v_an from animations where code_pin = v_pin and actif;
  if found then
    insert into appareils (jeton, role, animation_id, libelle)
    values (p_jeton, 'animateur', v_an.id, v_an.nom)
    on conflict (jeton) do update
      set role = 'animateur', animation_id = v_an.id, stand_id = null,
          garage_id = null, libelle = v_an.nom, vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'animateur', 'animation_id', v_an.id,
      'libelle', v_an.nom, 'cout', v_an.cout,
      'bareme', (select jsonb_agg(jsonb_build_object(
                   'id', id, 'libelle', libelle, 'points', points)
                 order by ordre, points desc)
                 from bareme where animation_id = v_an.id));
  end if;

  select * into v_st from stands where code_pin = v_pin and actif;
  if found then
    insert into appareils (jeton, role, stand_id, libelle)
    values (p_jeton, 'fournisseur', v_st.id, v_st.nom)
    on conflict (jeton) do update
      set role = 'fournisseur', stand_id = v_st.id, animation_id = null,
          garage_id = null, libelle = v_st.nom, vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'fournisseur', 'stand_id', v_st.id,
      'libelle', v_st.nom, 'plafond_operation', v_st.plafond_operation);
  end if;

  if v_pin = coalesce((select valeur from config where cle = 'pin_accueil'), '@@aucun@@') then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'accueil', 'Accueil du Forum')
    on conflict (jeton) do update
      set role = 'accueil', libelle = 'Accueil du Forum',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'accueil', 'libelle', 'Accueil du Forum');
  end if;

  if v_pin = coalesce((select valeur from config where cle = 'pin_admin'), '@@aucun@@') then
    insert into appareils (jeton, role, libelle)
    values (p_jeton, 'admin', 'Équipe Bony')
    on conflict (jeton) do update
      set role = 'admin', libelle = 'Équipe Bony',
          garage_id = null, animation_id = null, stand_id = null, vu_le = now()
    returning id into v_app;
    return jsonb_build_object('role', 'admin', 'libelle', 'Équipe Bony');
  end if;

  raise exception 'PIN_INCONNU' using detail = 'Code non reconnu.';
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Recherche d'accueil : nom, commune ou code postal
--    Deux caractères minimum, quinze résultats au plus. C'est le seul
--    endroit de l'application où un code d'accès est lisible, et il est
--    réservé à l'accueil et à Bony.
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
        and (recherche like '%' || norm(v_q) || '%' or cp like v_q || '%')
      order by nom
      limit 15
    ) s), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Où en est-on ? Le compteur d'arrivées
-- ---------------------------------------------------------------------
create or replace function public.api_accueil_etat(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['accueil','admin']);
  return jsonb_build_object(
    'invites', (select count(*) from garages where actif),
    'arrives', (select count(*) from garages where inscrit_le is not null),
    'derniers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nom', nom, 'ville', ville,
               'heure', to_char(inscrit_le at time zone 'Europe/Paris', 'HH24:MI'))
             order by inscrit_le desc)
      from (select nom, ville, inscrit_le from garages
             where inscrit_le is not null
             order by inscrit_le desc limit 6) d), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.api_connexion(text, text)          to anon;
grant execute on function public.api_accueil_chercher(text, text)   to anon;
grant execute on function public.api_accueil_etat(text)             to anon;

select (select valeur from config where cle='pin_accueil') as pin_accueil;
