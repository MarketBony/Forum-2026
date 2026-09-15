-- =====================================================================
--  Forum Pièces Bony 2026 — 18 — Les 100 lots réels sur la grille
--
--  LA COMPOSITION DES 200 CASES
--    85  lot        un lot remis pendant le Forum, au stand des lots,
--                   contre le code de retrait affiché sur le téléphone
--    15  billet     le TICKET D'OR : il ne dit pas ce qu'on gagne, il
--                   donne droit à l'un des 15 gros lots, remis le soir
--   100  perdante   rien
--
--  Soit 100 cases gagnantes sur 200 — UNE CHANCE SUR DEUX — et
--  exactement un lot par case gagnante : 85 + 15 = les 100 lots du
--  stock. C'est l'énoncé le plus simple possible du jeu.
--
--  POURQUOI EXACTEMENT 15 TICKETS POUR 15 GROS LOTS :
--  une première version en posait 30, pour que le tirage du soir ait
--  de vrais perdants. C'était une faute. Un garage qui lit « Vous êtes
--  qualifié ! », reste pour le cocktail, monte sur scène et redescend
--  les mains vides garde un plus mauvais souvenir que s'il était tombé
--  sur une case perdante : on lui avait promis quelque chose.
--  À quinze pour quinze, PERSONNE NE PERD, et le tirage garde tout son
--  suspense — il ne décide plus qui gagne, il décide QUI GAGNE QUOI,
--  entre le sac cuir Alpine à 379 € et l'avion Caudron à 72 €.
--
--  ⚠️ LES 15 GROS LOTS NE SONT PAS NOMMÉS ICI. Chacun est collé à SON
--  ticket d'or par sql/23_grand_tirage.sql, dans les colonnes gros_lot
--  et gros_lot_ordre — invisibles du garage jusqu'au soir. Le ticket
--  garde donc le libellé neutre « Ticket d'or » toute la journée.
--
--  LES LIBELLÉS SONT RECOPIÉS TELS QUELS depuis "stock forum.xlsx",
--  en majuscules comprises. C'est volontaire : le garagiste présente
--  son téléphone au stand des lots, et la personne au comptoir doit
--  retrouver MOT POUR MOT la ligne de son état de stock. Une jolie
--  casse ici, c'est une hésitation là-bas.
--
--  LES NUMÉROS SONT FIGÉS DANS CE FICHIER, tirés une fois d'une graine
--  fixe ("grand-bal-2026-lots"). Rejouer le fichier redonne donc
--  exactement la même grille : la répartition est vérifiable, et
--  personne ne peut prétendre qu'elle a été retouchée en cours de
--  soirée.
--
--  LES 15 TICKETS SONT TIRÉS PAR TRANCHES, un par tranche de ~13 cases
--  (graine "grand-bal-2026-tickets"). Un tirage libre en avait mis
--  quatre sur les cases 9, 10, 11 et 12 : invisible pour les joueurs,
--  mais une zone de la grille aurait été deux fois plus riche que les
--  autres. Par tranches, un garage qui choisit ses cases dans n'importe
--  quel coin de la grille a les mêmes chances.
--
--  Rejouable — mais REMET LA GRILLE À NEUF. À ne pas lancer en pleine
--  soirée : les cases déjà achetées perdraient leur sens.
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
-- 1. Garde-fou : on ne recompose pas une grille déjà jouée
--
--  Ce fichier efface l'attribution des cases. Si des garages ont déjà
--  acheté, leur case changerait de nature sous leurs pieds alors que
--  le journal, lui, est en ajout seul et garderait la trace du débit.
--  On refuse plutôt que de créer un écart impossible à rattraper.
-- ---------------------------------------------------------------------
do $$
declare v_jouees int;
begin
  select count(*) into v_jouees from public.grille where achete_le is not null;
  if v_jouees > 0 then
    raise exception
      'Grille déjà jouée : % case(s) achetée(s). Recomposer effacerait des achats inscrits au journal. Lancer 99_remise_a_zero.sql d''abord si c''est voulu.',
      v_jouees;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 2. Retour à une grille entièrement perdante
-- ---------------------------------------------------------------------
update public.grille
   set garage_id = null, journal_id = null, achete_le = null, revele_le = null,
       code_retrait = null, remis = false, remis_le = null,
       nature = 'perdante', lot = null;

-- ---------------------------------------------------------------------
-- 3. Les 15 tickets d'or
--
--  lot porte un libellé parce que la contrainte grille_lot_nomme ne
--  l'exige que pour nature = 'lot' — mais un billet sans libellé
--  s'afficherait vide sur le téléphone du garage.
-- ---------------------------------------------------------------------
update public.grille set nature = 'billet', lot = 'Ticket d''or'
 where numero in (  9,  23,  27,  42,  62,  74,  83, 103,
                  110, 126, 138, 152, 163, 182, 192);

-- ---------------------------------------------------------------------
-- 4. Les 85 lots remis pendant le Forum
-- ---------------------------------------------------------------------
update public.grille g set nature = 'lot', lot = v.lot
from (values
  (  2, 'MINIATURE 1/43 AUSTRAL BLEU IRON'), (  4, 'MINIATURE 1/43 AUSTRAL BLEU IRON'),
  (  5, 'R5 PROTOTYPE 1/18'), (  6, 'MINIATURE R4 1/64'),
  ( 14, 'MINIATURE DUO 1/43 NOIR C2'), ( 15, 'VOITURE BOIS 4CV'),
  ( 16, 'CASQUETTE MBLZ BLANCHE BRODEE'), ( 18, 'RUBICUB R5'),
  ( 19, 'MINIATURE Renault Austral EA BLEU'), ( 22, 'COLLECTION PORTE GOBELET APV'),
  ( 26, 'MINIATURE Renault Austral EA BLEU'), ( 28, 'MINIATURE 4EVER 1/43 (2)'),
  ( 29, 'PORTE CLE R5 JAUNE'), ( 30, 'PORTE CLE R5 JAUNE'),
  ( 32, 'MINIATURE MUTE THE HOT ROD 1/43'), ( 33, 'MINIATURE R4 1/64'),
  ( 34, 'PORTE CLE R5 JAUNE'), ( 37, 'MINIATURE Renault Austral EA GRIS'),
  ( 39, 'MINIATURE SYMBIOZ E-TECH 1/64'), ( 40, 'PORTE CLE R5 JAUNE'),
  ( 41, 'RUBICUB R5'), ( 43, 'MINIATURE SYMBIOZ 1/43 EA'),
  ( 44, 'RUBICUB R5'), ( 47, 'PORTE CLE R5 JAUNE'),
  ( 49, 'MINIATURE MUTE THE HOT ROD 1/43'), ( 51, 'MINIATURE SYMBIOZ E-TECH 1/64'),
  ( 52, 'BOULE NEIGE R5'), ( 53, 'RUBICUB R5'),
  ( 54, 'MINIATURE Renault Austral EA BLEU'), ( 56, 'MINIATURE Renault Austral EA BLEU'),
  ( 61, 'PORTE CLE R5 JAUNE'), ( 63, 'PORTE CLE R5 JAUNE'),
  ( 65, 'RUBICUB R5'), ( 66, 'MINIATURE R4 1/64'),
  ( 68, 'MINIATURE 4EVER 1/43 (1)'), ( 69, 'MINIATURE SYMBIOZ 1/43 E4'),
  ( 70, 'MINIATURE DUO 1/43 NOIR C1'), ( 72, 'MINIATURE SYMBIOZ 1/43 E4'),
  ( 75, 'MINIATURE SYMBIOZ 1/43 E4'), ( 78, 'MINIATURE 4EVER 1/43 (2)'),
  ( 80, 'MINIATURE SYMBIOZ E-TECH 1/64'), ( 81, 'MINIATURE SYMBIOZ 1/43 E4'),
  ( 82, 'MINIATURE MUTE THE HOT ROD 1/43'), ( 84, 'MINIATURE SYMBIOZ 1/43 E4'),
  ( 85, 'PORTE CLE R5 JAUNE'), ( 87, 'MINIATURE 4EVER 1/43 (1)'),
  ( 88, 'MINIATURE DUO 1/43 NOIR ORANGE'), ( 93, 'VOITURE BOIS 7 TONNES'),
  ( 99, 'MINIATURE 4EVER 1/43 (2)'), (100, 'COLLECTION PORTE GOBELET APV'),
  (112, 'RUBICUB R5'), (117, 'PORTE CLE R5 JAUNE'),
  (125, 'PORTE CLE R5 JAUNE'), (130, 'PORTE CLE R5 JAUNE'),
  (131, 'MINIATURE SYMBIOZ 1/43 EA'), (133, 'MINIATURE SYMBIOZ E-TECH 1/64'),
  (140, 'MINIATURE DUO 1/43 NOIR C2'), (141, 'MINIATURE Renault Austral EA GRIS'),
  (143, 'MINIATURE SYMBIOZ 1/43 EA'), (144, 'MINIATURE 4EVER 1/43 (1)'),
  (146, 'MINIATURE SYMBIOZ 1/43 EA'), (147, 'MINIATURE DUO 1/43 NOIR C1'),
  (149, 'MINIATURE Renault Austral EA GRIS'), (150, 'MINIATURE SYMBIOZ 1/43 EA'),
  (157, 'RUBICUB R5'), (159, 'MINIATURE SYMBIOZ 1/43 EA'),
  (160, 'RUBICUB R5'), (166, 'MINIATURE Renault Austral EA GRIS'),
  (167, '3 MUGS LEGEND 1'), (169, 'RUBICUB R5'),
  (170, 'MINIATURE SYMBIOZ 1/43 E4'), (171, 'RUBICUB R5'),
  (172, 'COLLECTION PORTE GOBELET APV'), (173, 'GOURDE SOUPLE DUO'),
  (174, 'CASQUETTE DUO'), (178, 'MINIATURE Renault Austral EA BLEU'),
  (181, 'MINIATURE R4 1/64'), (184, 'SAC A DOS SIEGE CONDUCTEUR DUO'),
  (185, 'GOURDE SOUPLE DUO'), (187, 'MINIATURE Renault Austral EA GRIS'),
  (188, 'MINIATURE SYMBIOZ E-TECH 1/64'), (189, 'MINIATURE 4EVER 1/43 (1)'),
  (194, 'MINIATURE R4 1/64'), (199, 'MINIATURE 4EVER 1/43 (1)'),
  (200, 'GOURDE SOUPLE DUO')
) as v(numero, lot)
where g.numero = v.numero;

-- ---------------------------------------------------------------------
-- 5. Contrôle immédiat
-- ---------------------------------------------------------------------
do $$
declare v_l int; v_b int; v_p int; v_sans int;
begin
  select count(*) filter (where nature = 'lot'),
         count(*) filter (where nature = 'billet'),
         count(*) filter (where nature = 'perdante'),
         count(*) filter (where nature = 'lot' and (lot is null or lot = ''))
    into v_l, v_b, v_p, v_sans
    from public.grille;

  if v_l <> 85 then raise exception '85 cases lot attendues, % trouvées', v_l; end if;
  if v_b <> 15 then raise exception '15 tickets d''or attendus, % trouvés', v_b; end if;
  if v_p <> 100 then raise exception '100 cases perdantes attendues, % trouvées', v_p; end if;
  if v_sans > 0 then raise exception '% case(s) lot sans libellé', v_sans; end if;
  raise notice '200 cases : 85 lots, 15 tickets d''or, 100 perdantes — 100 gagnantes pour 100 lots.';
end;
$$;
