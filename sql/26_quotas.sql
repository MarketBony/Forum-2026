-- =====================================================================
--  Forum Pièces Bony 2026 — 26 — Les quotas par garage
--
--  Trois freins contre l'abus, demandés par Bony le 15 septembre :
--
--   1. CINQ CASES par garage au lieu de trois. « Il en faut pour tout le
--      monde » — mais trois était serré, et un garage qui a beaucoup
--      joué doit pouvoir dépenser.
--
--   2. UN PLAFOND DE POINTS PAR ANIMATION ET PAR GARAGE, à QUATRE FOIS
--      le meilleur palier de cette animation. Le corn hole plafonne à
--      10 points la partie : un garage ne peut donc pas en tirer plus de
--      40 sur ce jeu. C'est large — quatre parties parfaites — mais ça
--      ferme la porte au garage qui camperait devant une borne toute la
--      journée pendant que les autres font la queue.
--
--   3. LE MÊME, PAR STAND, à TROIS FOIS le plafond d'une opération.
--      20 points l'opération chez FAAB : 60 points maximum pour un
--      garage sur ce stand. Un fournisseur généreux avec un ami ne peut
--      plus vider sa réserve sur une seule personne.
--
--  POURQUOI LE CONTRÔLE EST AU LANCEMENT DE LA PARTIE, PAS AU RÉSULTAT.
--  api_participation débite 2 points AVANT qu'on note le résultat. Si le
--  refus tombait au résultat, le garage aurait payé sa partie pour
--  s'entendre dire qu'il n'a droit à rien — la pire des façons de
--  refuser. L'animateur voit donc le message AVANT de lancer.
--  Le résultat est quand même contrôlé, en ceinture : un résultat envoyé
--  sans participation (rejeu, file hors ligne) ne doit pas passer sous
--  le radar.
--
--  ON LAISSE DÉPASSER LA DERNIÈRE PARTIE. Un garage à 38/40 qui lance et
--  fait un carreau touche ses 10 points et finit à 48. C'est voulu : le
--  quota est un frein à la répétition, pas une règle comptable, et
--  couper un gain à moitié serait incompréhensible sur le terrain.
--
--  L'ÉQUIPE BONY N'EST PAS SOUMISE AUX QUOTAS. Le rôle admin corrige,
--  rattrape et compense ; le bloquer avec un frein anti-abus, c'est lui
--  retirer l'outil au moment où il en a besoin.
--
--  LES DEUX MULTIPLICATEURS SONT DANS config : ils se règlent en direct,
--  sans redéploiement, et à la hausse comme à la baisse.
--      update config set valeur = '6' where cle = 'quota_animation_x';
--
--  Rejouable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Les réglages
-- ---------------------------------------------------------------------
update public.config set valeur = '5' where cle = 'cases_max_garage';

insert into public.config (cle, valeur, description) values
  ('quota_animation_x', '4',
   'Points max qu''un garage peut tirer d''UNE animation = ce multiple du meilleur palier de cette animation'),
  ('quota_stand_x', '3',
   'Points max qu''un garage peut tirer d''UN stand = ce multiple du plafond par opération du stand')
on conflict (cle) do update set valeur = excluded.valeur,
                                description = excluded.description;

-- ---------------------------------------------------------------------
-- 2. Deux fonctions de lecture, pour ne pas recopier le calcul
--
--  Les recopier dans chacune des trois fonctions d'écriture, c'est
--  garantir qu'une correction future n'en touchera que deux sur trois.
-- ---------------------------------------------------------------------
create or replace function public._quota_animation(p_animation uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select cfg_int('quota_animation_x', 4)
       * coalesce((select max(points) from bareme where animation_id = p_animation), 0)
$$;

create or replace function public._quota_stand(p_stand uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select cfg_int('quota_stand_x', 3)
       * coalesce((select plafond_operation from stands where id = p_stand), 0)
$$;

-- Ce qu'un garage a DÉJÀ touché sur cette animation. Le filtre
-- « delta > 0 » n'est pas cosmétique : la participation écrit -2 avec le
-- même animation_id, et sans lui chaque partie jouée effacerait deux
-- points du compteur — le quota ne se remplirait jamais tout à fait.
create or replace function public._recu_animation(p_garage uuid, p_animation uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(sum(delta), 0)::int from journal
   where garage_id = p_garage and animation_id = p_animation and delta > 0
$$;

create or replace function public._recu_stand(p_garage uuid, p_stand uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(sum(delta), 0)::int from journal
   where garage_id = p_garage and stand_id = p_stand and delta > 0
$$;

-- ---------------------------------------------------------------------
-- 3. La participation : on refuse AVANT de débiter
-- ---------------------------------------------------------------------
create or replace function public.api_participation(
  p_jeton text, p_garage uuid, p_animation uuid, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_an animations;
  v_r  jsonb;
  v_quota integer;
  v_recu  integer;
begin
  a := _exige_role(p_jeton, array['animateur','admin']);
  select * into v_an from animations where id = p_animation and actif;
  if not found then
    raise exception 'ANIMATION_INCONNUE' using detail = 'Animation introuvable ou inactive.';
  end if;

  -- Le quota, sauf pour l'équipe Bony qui corrige et compense.
  if a.role <> 'admin' then
    v_quota := _quota_animation(v_an.id);
    v_recu  := _recu_animation(p_garage, v_an.id);
    if v_quota > 0 and v_recu >= v_quota then
      raise exception 'QUOTA_ANIMATION'
        using detail = format(
          'Quota de points atteint pour ce garage sur %s : %s points sur %s. Il peut jouer les autres animations.',
          v_an.nom, v_recu, v_quota);
    end if;
  end if;

  if v_an.cout = 0 then
    return jsonb_build_object('solde', (select solde from garages where id = p_garage),
                              'deja_traite', false, 'gratuit', true);
  end if;

  v_r := _ecrire(p_garage, -v_an.cout, v_an.nom || ' · participation', 'animation',
                 p_cle, a.id, v_an.id);
  return v_r || jsonb_build_object('animation', v_an.nom, 'cout', v_an.cout,
                                   'quota', v_quota, 'recu', v_recu);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Le résultat : ceinture, pour un résultat sans participation
-- ---------------------------------------------------------------------
create or replace function public.api_resultat(
  p_jeton text, p_garage uuid, p_bareme uuid, p_cle text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a appareils;
  v_b bareme;
  v_an animations;
  v_r jsonb;
  v_quota integer;
  v_recu  integer;
begin
  a := _exige_role(p_jeton, array['animateur','admin']);
  select * into v_b from bareme where id = p_bareme;
  if not found then
    raise exception 'BAREME_INCONNU' using detail = 'Résultat introuvable.';
  end if;
  select * into v_an from animations where id = v_b.animation_id;

  if v_b.points = 0 then
    -- Résultat nul : on ne pollue pas le journal d'une écriture à zéro.
    return jsonb_build_object(
      'solde', (select solde from garages where id = p_garage),
      'deja_traite', false, 'points', 0,
      'animation', v_an.nom, 'resultat', v_b.libelle);
  end if;

  if a.role <> 'admin' then
    v_quota := _quota_animation(v_an.id);
    v_recu  := _recu_animation(p_garage, v_an.id);
    -- On refuse seulement si le quota est DÉJÀ atteint. Sous le quota,
    -- le gain passe en entier, quitte à dépasser : la partie a été jouée
    -- et payée, on ne coupe pas un carreau en deux.
    if v_quota > 0 and v_recu >= v_quota then
      raise exception 'QUOTA_ANIMATION'
        using detail = format(
          'Quota de points atteint pour ce garage sur %s : %s points sur %s.',
          v_an.nom, v_recu, v_quota);
    end if;
  end if;

  v_r := _ecrire(p_garage, v_b.points,
                 v_an.nom || ' · ' || lower(v_b.libelle), 'animation',
                 p_cle, a.id, v_an.id);
  return v_r || jsonb_build_object('points', v_b.points,
                                   'animation', v_an.nom, 'resultat', v_b.libelle,
                                   'quota', v_quota, 'recu', v_recu + v_b.points);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Le stand : le quota par garage s'ajoute au plafond de la soirée
-- ---------------------------------------------------------------------
create or replace function public.api_points_achat(
  p_jeton text, p_garage uuid, p_points integer, p_cle text, p_palier text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a       appareils;
  v_s     stands;
  v_cumul integer;
  v_lib   text;
  v_r     jsonb;
  v_quota integer;
  v_recu  integer;
begin
  a := _exige_role(p_jeton, array['fournisseur','admin']);
  if a.stand_id is null then
    raise exception 'STAND_NON_RATTACHE'
      using detail = 'Cet appareil n''est rattaché à aucun stand.';
  end if;
  select * into v_s from stands where id = a.stand_id and actif;
  if not found then
    raise exception 'STAND_INCONNU' using detail = 'Stand introuvable ou inactif.';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'POINTS_INVALIDES' using detail = 'Le nombre de points doit être positif.';
  end if;
  if p_points > v_s.plafond_operation then
    raise exception 'PLAFOND_OPERATION'
      using detail = format('Maximum %s points par opération sur ce stand.', v_s.plafond_operation);
  end if;

  -- Le quota PAR GARAGE, qui est nouveau, et le plafond de la soirée
  -- PAR STAND, qui existait déjà. Les deux protègent des choses
  -- différentes : l'un un garage trop servi, l'autre un stand qui
  -- déborde.
  if a.role <> 'admin' then
    v_quota := _quota_stand(v_s.id);
    v_recu  := _recu_stand(p_garage, v_s.id);
    if v_quota > 0 and v_recu >= v_quota then
      raise exception 'QUOTA_STAND'
        using detail = format(
          'Quota de points atteint pour ce garage sur %s : %s points sur %s. Les autres stands restent ouverts.',
          v_s.nom, v_recu, v_quota);
    end if;
  end if;

  select coalesce(sum(delta), 0) into v_cumul from journal where stand_id = v_s.id;
  if v_cumul + p_points > v_s.plafond_soiree then
    raise exception 'PLAFOND_SOIREE'
      using detail = format('Ce stand a distribué %s points sur %s autorisés.',
                            v_cumul, v_s.plafond_soiree);
  end if;

  -- Le palier n'est retenu que s'il appartient vraiment au barème de la
  -- catégorie : un libellé libre venu du navigateur n'a rien à faire
  -- dans un journal en ajout seul.
  select libelle into v_lib
    from bareme_stand
   where categorie = v_s.categorie and libelle = p_palier and points = p_points;

  v_r := _ecrire(p_garage, p_points,
                 'Achat — ' || v_s.nom || coalesce(' · ' || v_lib, ''),
                 'fournisseur', p_cle, a.id, null, v_s.id);
  return v_r || jsonb_build_object('stand', v_s.nom, 'points', p_points,
                                   'palier', v_lib,
                                   'cumul_stand', v_cumul + p_points,
                                   'plafond_soiree', v_s.plafond_soiree,
                                   'quota', v_quota, 'recu', coalesce(v_recu, 0) + p_points);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. Contrôle immédiat
-- ---------------------------------------------------------------------
do $$
declare
  v_cases  integer;
  v_min_a  integer;
  v_min_s  integer;
  v_sans   integer;
begin
  v_cases := cfg_int('cases_max_garage', 0);
  select min(_quota_animation(id)) into v_min_a from animations where actif;
  select min(_quota_stand(id))     into v_min_s from stands     where actif;
  select count(*) into v_sans from animations a
   where a.actif and _quota_animation(a.id) = 0;

  if v_cases <> 5 then
    raise exception '5 cases par garage attendues, config en annonce %', v_cases;
  end if;
  if v_sans > 0 then
    raise exception '% animation(s) à quota nul : plus personne ne pourrait y jouer', v_sans;
  end if;
  -- Un quota inférieur au meilleur palier interdirait la première partie.
  if v_min_a < (select max(points) from bareme) then
    raise exception 'quota d''animation trop bas : % alors qu''un seul coup peut rapporter %',
      v_min_a, (select max(points) from bareme);
  end if;
  raise notice '5 cases/garage · quota animation min % pts · quota stand min % pts', v_min_a, v_min_s;
end;
$$;
