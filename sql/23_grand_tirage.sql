-- =====================================================================
--  Forum Pièces Bony 2026 — 23 — Le grand tirage devient une RÉVÉLATION
--
--  L'ARBITRAGE BONY QUI MANQUAIT (CONTEXTE §11, décision n°2 du soir) :
--  chaque ticket d'or est collé à SON gros lot, décidé maintenant, une
--  fois pour toutes. Le soir, il n'y a plus rien à tirer — on ouvre les
--  enveloppes, voilà tout.
--
--      case 182  →  ticket d'or  →  SAC CUIR ALPINE JAUNE 48H
--
--  LE SEUL HASARD DE LA SOIRÉE A DÉJÀ EU LIEU : c'est le garagiste qui
--  a choisi la case 182 à 15 h 40 sans savoir ce qu'il y avait dessous.
--  Le reste n'est que du théâtre, et c'est exactement ce qu'on veut :
--  un tirage truqué est un scandale, une révélation ne peut pas l'être.
--  Personne ne peut prétendre qu'on a retouché quoi que ce soit le soir
--  même, puisqu'il n'y a rien à retoucher — les 15 lignes ci-dessous
--  sont figées dans ce fichier et poussées AVANT le Forum.
--
--  CE QUE CE FICHIER SUPPRIME.
--  L'ancienne mécanique d'élimination manche par manche (api_tirage_
--  ouvrir, api_tirage_manche, table tirage) ne servait qu'à désigner UN
--  gagnant parmi les porteurs de billet. Elle n'a plus d'objet et elle
--  est retirée : laisser deux mécaniques contradictoires en place, c'est
--  garantir qu'on appuiera sur le mauvais bouton à 22 h sur scène.
--
--  POURQUOI UNE COLONNE gros_lot ET PAS grille.lot.
--  grille.lot part sur le téléphone du garage à l'instant de l'achat.
--  Y écrire « SAC CUIR ALPINE JAUNE 48H » vendrait la mèche à 15 h 40 et
--  il n'y aurait plus de soirée. Le ticket garde donc son libellé
--  « Ticket d'or » toute la journée, et gros_lot reste invisible jusqu'à
--  ce que l'équipe Bony appuie sur le bouton.
--
--  L'ORDRE DE RÉVÉLATION EST UN ORDRE DE SPECTACLE, pas un classement.
--  Deux règles, et elles se lisent dans la colonne ordre ci-dessous :
--    · jamais deux fois le même lot à la suite — sur cinq avions Caudron
--      identiques, les annoncer d'affilée tue la salle ;
--    · les trois pièces uniques à la fin, par valeur croissante, le sac
--      cuir Alpine à 379 € en dernier. On finit sur le sommet.
--
--  L'AFFECTATION case → lot EST TIRÉE D'UNE GRAINE FIXE
--  (« grand-bal-2026-revelation »), comme la grille elle-même : le rang
--  d'une case vient de md5(graine|numéro). Aucune corrélation entre le
--  numéro de la case et la valeur du lot — sans quoi il aurait suffi de
--  lire ce fichier pour savoir que la case 182 valait 379 €.
--
--  LES 15 LOTS VIENNENT DE « STOCK LOT FORUM - 2026.xlsx », PAR SOUSTRACTION :
--  100 unités proposées au Forum, moins les 85 posées sur la grille par
--  sql/18_lots.sql. Il reste exactement 15 unités pour 1 695,68 € HT —
--  ce qui recoupe les deux chiffres notés dans CONTEXTE.md (15 lots,
--  1 696 €). Les libellés sont recopiés MOT POUR MOT du fichier de
--  stock, casse comprise : la personne au comptoir doit retrouver la
--  ligne de son état de stock sans hésiter.
--
--  Rejouable. Ne touche à aucune case achetée.
-- =====================================================================

-- ---------------------------------------------------------------------
--  🔒 SCELLÉ LE 15 SEPTEMBRE 2026
--
--  La liste case ↔ lot est sortie en classeur d'étiquetage
--  (« Lots Forum 2026 - etiquetage.xlsx ») et les lots physiques portent
--  désormais leur numéro de case. Décision de Bastien, verbatim :
--  « les lots et tickets d'or seront scellés à leur numéros et ne
--  pourront plus bouger ».
--
--  CE FICHIER NE DOIT PLUS CHANGER DE VALEURS. Le rejouer à l'identique
--  reste sans danger — il réécrit exactement les mêmes lignes — mais
--  modifier un numéro ou un libellé rendrait fausses les étiquettes déjà
--  collées, et personne ne s'en apercevrait avant le comptoir.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 1. Les deux colonnes
--
--  gros_lot_ordre est l'ordre de SPECTACLE figé ici. L'ordre réellement
--  joué le soir se recalcule au lancement sur les seuls tickets
--  décrochés : si trois tickets ne trouvent pas preneur dans la
--  journée, le spectacle passe de 15 à 12 révélations sans un trou.
-- ---------------------------------------------------------------------
alter table public.grille add column if not exists gros_lot       text;
alter table public.grille add column if not exists gros_lot_ordre integer;

-- ⚠️ LES CONTRAINTES SONT POSÉES AU POINT 3bis, APRÈS LES AFFECTATIONS.
-- Les poser ici échouait : à cet instant les 15 tickets d'or existent
-- déjà en base avec gros_lot à NULL, et PostgreSQL valide une contrainte
-- CHECK sur les lignes EXISTANTES au moment du ALTER TABLE, pas
-- seulement sur les écritures futures.

-- La remise d'un lot était réservée à nature = 'lot'. Les gros lots se
-- remettent aussi, sur scène, contre le même code de retrait.
alter table public.grille drop constraint if exists grille_remise_coherente;
alter table public.grille
  add constraint grille_remise_coherente
  check (not remis or (nature in ('lot','billet')
                       and garage_id is not null and revele_le is not null));

-- ---------------------------------------------------------------------
-- 2. Le drapeau du soir
--
--  Une clé de config plutôt qu'une colonne : l'état « le tirage a eu
--  lieu » est un état de la SOIRÉE, pas d'une case. Et il se remet à
--  « non » d'une ligne si la répétition générale a lancé le spectacle
--  pour voir à quoi il ressemblait.
-- ---------------------------------------------------------------------
insert into public.config (cle, valeur, description) values
  ('tirage_revele', 'non',
   'oui quand les 15 tickets d''or ont été révélés sur scène · api_tirage_lancer')
on conflict (cle) do update set description = excluded.description;

-- ---------------------------------------------------------------------
-- 3. Les 15 affectations, figées
--
--  🔒 CES QUINZE LIGNES NE BOUGENT PLUS (voir le sceau en tête). Elles
--  sont sorties en classeur d'étiquetage et les lots physiques portent
--  leur numéro de case. Rejouer le fichier à l'identique est sans
--  danger ; changer un numéro rendrait fausse une étiquette déjà collée.
-- ---------------------------------------------------------------------
update public.grille g
   set gros_lot = v.lot, gros_lot_ordre = v.ordre
from (values
  --  case ordre   gros lot                               PV HT
  (138,  1, 'AVION CAUDRON BOIS'),              --         72,65
  ( 23,  2, 'CIRCUIT ELECTRIQUE RACE TRACK V3'),--        115,00
  ( 62,  3, 'AVION CAUDRON BOIS'),              --         72,65
  (163,  4, 'MONTRE R5 JAUNE'),                 --         91,68
  ( 27,  5, 'CIRCUIT ELECTRIQUE RACE TRACK V3'),--        115,00
  ( 83,  6, 'AVION CAUDRON BOIS'),              --         72,65
  (192,  7, 'CIRCUIT ELECTRIQUE RACE TRACK V3'),--        115,00
  (126,  8, 'MONTRE R5 JAUNE'),                 --         91,68
  ( 74,  9, 'AVION CAUDRON BOIS'),              --         72,65
  (103, 10, 'CIRCUIT ELECTRIQUE RACE TRACK V3'),--        115,00
  (152, 11, 'AVION CAUDRON BOIS'),              --         72,65
  ( 42, 12, 'CIRCUIT ELECTRIQUE RACE TRACK V3'),--        115,00
  (110, 13, 'SAC A DOS ALPINE ESSENTIAL'),      --         93,75
  (  9, 14, 'WEEKENDER 72H A290'),              --        101,15
  (182, 15, 'SAC CUIR ALPINE JAUNE 48H')        --        379,17
) as v(numero, ordre, lot)
where g.numero = v.numero;

-- ---------------------------------------------------------------------
-- 3bis. Les contraintes, maintenant que les 15 lignes sont remplies
--
--  Un ticket d'or sans gros lot, c'est un garage qui monte sur scène et
--  redescend les mains vides. Et un gros lot posé par erreur sur une
--  case ordinaire s'afficherait nulle part. L'égalité interdit les deux
--  d'un coup, en base, plutôt que de compter sur la vigilance d'un soir
--  de cocktail.
-- ---------------------------------------------------------------------
alter table public.grille drop constraint if exists grille_gros_lot_coherent;
alter table public.grille
  add constraint grille_gros_lot_coherent
  check ((nature = 'billet') = (gros_lot is not null));

-- ---------------------------------------------------------------------
-- 4. L'état du grand tirage — équipe Bony uniquement
--
--  Rend TOUJOURS les 15 tickets, décrochés ou non : c'est l'écran sur
--  lequel Bony prépare la soirée, il doit voir les trous avant d'être
--  sur scène. Le champ « rang » ne numérote que les tickets décrochés,
--  et c'est lui que la page de projection déroule.
-- ---------------------------------------------------------------------
create or replace function public.api_tirage_etat(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a       appareils;
  v_fait  boolean;
begin
  a := _exige_role(p_jeton, array['admin']);
  v_fait := coalesce((select valeur from config where cle = 'tirage_revele'), 'non') = 'oui';

  return jsonb_build_object(
    'revele',    v_fait,
    'decroches', (select count(*) from grille where nature = 'billet' and garage_id is not null),
    'orphelins', (select count(*) from grille where nature = 'billet' and garage_id is null),
    'tickets', coalesce((
      select jsonb_agg(jsonb_build_object(
               'rang',         t.rang,
               'ordre',        t.gros_lot_ordre,
               'numero',       t.numero,
               'gros_lot',     t.gros_lot,
               'garage',       t.nom,
               'ville',        t.ville,
               'decroche_a',   t.decroche_a,
               'code_retrait', t.code_retrait,
               'remis',        t.remis)
             order by t.gros_lot_ordre)
      from (
        select gr.numero, gr.gros_lot, gr.gros_lot_ordre, gr.code_retrait, gr.remis,
               g.nom, g.ville,
               -- l'heure sert au suivi côté Bony : « décroché à 15h40 »
               to_char(gr.achete_le at time zone 'Europe/Paris', 'HH24:MI') as decroche_a,
               case when gr.garage_id is null then null
                    else row_number() over (partition by (gr.garage_id is not null)
                                            order by gr.gros_lot_ordre) end as rang
          from grille gr
          left join garages g on g.id = gr.garage_id
         where gr.nature = 'billet'
      ) t), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- 5. Lancer la révélation
--
--  Un seul appel, un seul basculement. La page de projection déroule
--  ensuite ses 60 secondes toute seule, sans rappeler la base : 200
--  téléphones qui sondent pendant le spectacle, ce n'est pas le moment
--  d'ajouter 15 allers-retours par écran.
--
--  Le code de retrait est posé ICI et pas à l'achat : avant la
--  révélation, un ticket d'or ne donne droit à rien qu'on puisse aller
--  chercher au comptoir.
-- ---------------------------------------------------------------------
create or replace function public.api_tirage_lancer(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a      appareils;
  v_n    integer;
begin
  a := _exige_role(p_jeton, array['admin']);

  select count(*) into v_n
    from grille where nature = 'billet' and garage_id is not null;
  if v_n = 0 then
    raise exception 'AUCUN_TICKET'
      using detail = 'Aucun ticket d''or n''a été décroché : il n''y a rien à révéler.';
  end if;

  -- Idempotent : relancer n'écrase aucun code déjà distribué. Un doigt
  -- qui tremble sur scène ne doit pas changer le code de retrait d'un
  -- garage qui a déjà vu le sien sur son téléphone.
  update grille
     set revele_le    = coalesce(revele_le, now()),
         code_retrait = coalesce(code_retrait,
                                 upper(substr(md5('or' || numero::text || achete_le::text), 1, 5)))
   where nature = 'billet' and garage_id is not null;

  update config set valeur = 'oui' where cle = 'tirage_revele';

  return api_tirage_etat(p_jeton);
end;
$$;

-- ---------------------------------------------------------------------
-- 6. Revenir en arrière — pour la répétition générale, pas pour le soir
--
--  Ne touche PAS aux codes de retrait déjà posés : si on rejoue le
--  spectacle, les mêmes garages gardent les mêmes codes. Seul le
--  drapeau retombe.
-- ---------------------------------------------------------------------
create or replace function public.api_tirage_reset(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare a appareils;
begin
  a := _exige_role(p_jeton, array['admin']);
  update config set valeur = 'non' where cle = 'tirage_revele';
  return api_tirage_etat(p_jeton);
end;
$$;

-- ---------------------------------------------------------------------
-- 7. L'ancienne mécanique s'en va
--
--  Deux boutons contradictoires sur un écran de scène, c'est un
--  incident garanti. On retire plutôt que de commenter.
-- ---------------------------------------------------------------------
drop function if exists public.api_tirage_ouvrir(text);
drop function if exists public.api_tirage_manche(text);
drop table    if exists public.tirage;
delete from public.config where cle = 'tirage_ouvert';

-- ---------------------------------------------------------------------
-- 8. Ce que le garage voit sur son téléphone
--
--  Avant la révélation : « Ticket d'or », comme toute la journée.
--  Après : le nom du gros lot et le code de retrait, sur le même écran
--  que ses autres lots. Il doit pouvoir le montrer au comptoir sans
--  qu'on lui explique où regarder.
-- ---------------------------------------------------------------------
create or replace function public.api_etat(p_jeton text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a      appareils;
  v_g    garages;
  v_fait boolean;
begin
  a := _appareil(p_jeton);
  if a.garage_id is null then
    raise exception 'APPAREIL_SANS_GARAGE'
      using detail = 'Cet appareil est un appareil de service, pas un garage.';
  end if;
  select * into v_g from garages where id = a.garage_id;
  v_fait := coalesce((select valeur from config where cle = 'tirage_revele'), 'non') = 'oui';

  return jsonb_build_object(
    'garage', jsonb_build_object(
        'id', v_g.id, 'nom', v_g.nom, 'ville', v_g.ville, 'solde', v_g.solde),
    'cout_grille', cfg_int('cout_grille', 20),
    'revelation', coalesce((select valeur from config where cle = 'revelation'), 'immediate'),
    'tirage_revele', v_fait,
    'cases_libres', (select count(*) from grille where garage_id is null),
    'billets_restants', (select count(*) from grille where nature = 'billet' and garage_id is null),
    'grille', (select string_agg(case when garage_id is null then '0' else '1' end, ''
                                 order by numero) from grille),
    'mes_cases', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'numero', numero,
                 'revelee', revele_le is not null,
                 'nature', case when revele_le is null then null else nature end,
                 -- Le gros lot ne remplace « Ticket d'or » qu'une fois
                 -- le spectacle passé. Tant que v_fait est faux, cette
                 -- ligne ne peut PAS fuiter le contenu de l'enveloppe.
                 'lot', case when revele_le is null or nature = 'perdante' then null
                             when nature = 'billet' and v_fait then gros_lot
                             else lot end,
                 'gros_lot', case when nature = 'billet' and v_fait then gros_lot else null end,
                 'code_retrait', code_retrait,
                 'remis', remis)
               order by numero)
        from grille where garage_id = v_g.id), '[]'::jsonb),
    'operations', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'heure', to_char(cree_le at time zone 'Europe/Paris', 'HH24:MI'),
                 'libelle', libelle, 'source', source, 'delta', delta)
               order by id desc)
        from (select * from journal where garage_id = v_g.id
              order by id desc limit 12) d), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- 9. Le suivi des lots accueille les gros lots
--
--  Même écran, même geste : Bony coche « remis » quand la personne
--  repart avec son sac. Un gros lot n'y apparaît qu'une fois révélé —
--  avant, il n'existe pas.
-- ---------------------------------------------------------------------
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
             'numero', gr.numero,
             'lot', case when gr.nature = 'billet' then gr.gros_lot else gr.lot end,
             'gros', gr.nature = 'billet',
             'code_retrait', gr.code_retrait,
             'garage', g.nom, 'ville', g.ville, 'remis', gr.remis,
             'joue_a', to_char(gr.achete_le at time zone 'Europe/Paris', 'HH24:MI'))
           order by gr.remis, (gr.nature = 'billet') desc, gr.achete_le)
    from grille gr
    join garages g on g.id = gr.garage_id
   where gr.nature in ('lot','billet') and gr.garage_id is not null
     and gr.revele_le is not null), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- 10. Contrôle immédiat
-- ---------------------------------------------------------------------
do $$
declare
  v_b int; v_sans int; v_ordres int; v_suite int; v_fin text;
begin
  select count(*) into v_b from public.grille where nature = 'billet';
  select count(*) into v_sans from public.grille
   where nature = 'billet' and (gros_lot is null or gros_lot_ordre is null);
  select count(distinct gros_lot_ordre) into v_ordres from public.grille where nature = 'billet';

  -- Deux fois le même lot à la suite dans l'ordre de spectacle
  select count(*) into v_suite from (
    select gros_lot, lag(gros_lot) over (order by gros_lot_ordre) as prec
      from public.grille where nature = 'billet') t
   where gros_lot = prec;

  select gros_lot into v_fin from public.grille
   where nature = 'billet' order by gros_lot_ordre desc limit 1;

  if v_b <> 15 then raise exception '15 tickets d''or attendus, % trouvés', v_b; end if;
  if v_sans > 0 then raise exception '% ticket(s) d''or sans gros lot affecté', v_sans; end if;
  if v_ordres <> 15 then
    raise exception 'ordre de révélation en double : % rangs distincts pour 15 tickets', v_ordres;
  end if;
  if v_suite > 0 then
    raise exception '% fois le même lot deux fois de suite : la salle décroche', v_suite;
  end if;
  if v_fin <> 'SAC CUIR ALPINE JAUNE 48H' then
    raise exception 'le spectacle ne finit pas sur le sac cuir Alpine mais sur « % »', v_fin;
  end if;
  raise notice '15 tickets d''or affectés, spectacle en 15 temps, final sur le sac Alpine.';
end;
$$;
