-- =====================================================================
--  Forum Pièces Bony 2026 — 31 — Les gros lots peuvent être cochés « remis »
--
--  LE DÉFAUT. `sql/23_grand_tirage.sql` a élargi aux tickets d'or deux
--  choses sur trois :
--
--    * la contrainte `grille_remise_coherente`, qui autorise
--      explicitement `nature in ('lot','billet')` à porter `remis` ;
--    * `api_lots`, qui renvoie désormais les billets ET les lots, en
--      triant les gros lots EN TÊTE des non-remis.
--
--  Mais pas `api_remettre_lot`, restée sur `nature = 'lot'`. La base
--  autorisait donc ce que la seule fonction capable de le faire
--  refusait.
--
--  CE QUE ÇA DONNAIT LE SOIR. Après la révélation, les 15 gros lots
--  arrivent en tête de l'écran « Suivi des lots », chacun avec son
--  bouton « Remettre ». Chacun de ces boutons échouait, et l'équipe
--  lisait « Impossible — Case inconnue, sans lot, non révélée, ou lot
--  déjà remis » au stand des lots, juste après le spectacle, sur les
--  quinze lots les plus importants de la soirée. L'indicateur « Gros
--  lots déjà remis » de l'écran des tickets d'or restait à 0 pour
--  toujours.
--
--  Mesuré sur la base de production le 16 septembre au soir, en
--  transaction annulée : `api_remettre_lot` rendait OK sur un lot
--  ordinaire et `LOT_NON_REMISABLE` sur un ticket d'or.
--
--  CE QUI CHANGE. Deux choses, et rien d'autre :
--    1. `nature in ('lot','billet')` au lieu de `nature = 'lot'` ;
--    2. le libellé rendu est `gros_lot` pour un billet, comme le fait
--       déjà `api_lots` — sans quoi le bandeau de confirmation
--       annoncerait « Ticket d'or » au lieu du nom du gros lot.
--
--  Le reste du corps est recopié À L'IDENTIQUE. On ne profite pas d'un
--  correctif de la veille pour améliorer autre chose.
--
--      .\scripts\push-sql.ps1 -File sql\31_remise_gros_lots.sql
-- =====================================================================

begin;

create or replace function public.api_remettre_lot(p_jeton text, p_numero integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils; v_case grille;
begin
  a := _exige_role(p_jeton, array['admin']);
  update grille set remis = true, remis_le = now()
   where numero = p_numero
     -- ICI LE CORRECTIF : un ticket d'or est un lot qu'on remet aussi.
     and nature in ('lot', 'billet')
     and garage_id is not null and revele_le is not null and not remis
  returning * into v_case;
  if not found then
    raise exception 'LOT_NON_REMISABLE'
      using detail = 'Case inconnue, sans lot, non révélée, ou lot déjà remis.';
  end if;
  return jsonb_build_object(
    'numero', v_case.numero,
    -- Un billet porte son intitulé dans `gros_lot`, pas dans `lot` :
    -- c'est déjà ce que fait api_lots pour l'affichage de la liste.
    'lot',    case when v_case.nature = 'billet' then v_case.gros_lot else v_case.lot end,
    'remis',  true);
end;
$$;

grant execute on function public.api_remettre_lot(text, integer) to anon;

commit;

-- ---------------------------------------------------------------------
-- CONTRÔLE — il éprouve la contrainte au lieu de l'affirmer.
--
--  Le contrôle simule l'état du soir (une case billet gagnée et
--  révélée), coche le lot, puis ANNULE tout : la manipulation vit dans
--  un sous-bloc plpgsql, et une exception dans un sous-bloc annule ce
--  que ce sous-bloc a écrit. Rien ne survit — ni l'appareil de
--  contrôle, ni la case attribuée, ni la coche.
--
--  Si le correctif n'avait pas pris, ce contrôle fait échouer le
--  fichier avec un message explicite plutôt que de laisser croire que
--  c'est passé.
-- ---------------------------------------------------------------------
do $$
declare
  v_jeton  text := repeat('c', 64);
  v_billet integer;
  v_garage uuid;
  v_ok     boolean := false;
begin
  select id     into v_garage from public.garages where actif order by id limit 1;
  select numero into v_billet from public.grille  where nature = 'billet' order by numero limit 1;

  begin
    insert into public.appareils (jeton, role, libelle)
         values (v_jeton, 'admin', 'CONTROLE 31');
    update public.grille
       set garage_id = v_garage, achete_le = now(), revele_le = now()
     where numero = v_billet;

    perform public.api_remettre_lot(v_jeton, v_billet);
    v_ok := true;                      -- l'appel a abouti

    -- On annule volontairement : une exception dans un sous-bloc
    -- plpgsql défait tout ce que ce sous-bloc a écrit. Les variables,
    -- elles, gardent leur valeur — c'est ce qui permet de rendre le
    -- verdict après coup.
    raise exception 'ANNULATION_VOULUE';
  exception when others then
    if sqlerrm <> 'ANNULATION_VOULUE' then
      v_ok := false;                   -- l'appel lui-même a échoué
    end if;
  end;

  if not v_ok then
    raise exception
      'CONTROLE ECHOUE : api_remettre_lot refuse toujours un ticket d''or (case n°%)', v_billet;
  end if;
  raise notice 'Controle OK : le ticket d''or de la case n° % peut etre coche remis.', v_billet;
end;
$$;

-- Et la preuve que rien n'a été laissé derrière.
select (select count(*) from public.grille where remis)                          as cases_remises,
       (select count(*) from public.grille where garage_id is not null)          as cases_prises,
       (select count(*) from public.appareils where libelle = 'CONTROLE 31')     as appareils_controle,
       (select count(*) from public.journal)                                     as journal,
       position('''billet''' in pg_get_functiondef(
         'public.api_remettre_lot(text,integer)'::regprocedure)) > 0             as fonction_corrigee;
