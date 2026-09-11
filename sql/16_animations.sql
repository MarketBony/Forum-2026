-- =====================================================================
--  Forum Pièces Bony 2026 — 16 — Les 6 animations réelles
--
--  Remplace les 4 animations de démonstration par les 6 du Forum.
--
--  POURQUOI LE MÊME BARÈME 20 / 10 / 5 / 0 PARTOUT :
--  si un jeu rapporte plus que les autres, toute la halle fait la queue
--  au même endroit et les cinq autres animateurs regardent passer la
--  journée. L'échelle est donc identique ; seul le vocabulaire change,
--  parce qu'un animateur doit lire SON jeu, pas une grille abstraite.
--
--  LE COÛT DE PARTICIPATION EST LE RÉGULATEUR DE RYTHME.
--  Il est à 2 points. Ce n'est pas un prix, c'est un frein : sans lui,
--  un garage enchaîne trois parties de basket, a « fait » l'animation
--  en un quart d'heure et il lui reste six heures à tuer. Il se règle
--  en direct, sans redéploiement, jeu par jeu :
--      update animations set cout = 3 where nom = 'BASKET ARCADE';
--
--  ⚠️ LES SEUILS CHIFFRÉS SONT DES MARQUE-PLACES.
--  BASKET ARCADE, BLAZZPOD et BORNE D'ARCADE sont notés sur un score
--  affiché par la machine. Je n'ai pas vu ces machines : les paliers
--  ci-dessous sont plausibles, pas mesurés. Il faut trois parties
--  d'essai par jeu à la répétition, sinon soit tout le monde fait 20,
--  soit personne n'y arrive. Se corrige d'une ligne :
--      update bareme set libelle = '…' where id = '…';
--
--  POURQUOI LES PIN 1001 À 1006 :
--  l'alphabet des codes garage exclut O, I, 0 et 1. Un PIN contenant
--  un 0 ou un 1 ne peut donc PAS heurter un code garage — impossible
--  par construction. verifier_portes() le recontrôle quand même.
--
--  Rejouable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Retrait des 4 animations de démonstration
--
--  Même précaution que pour les stands : on ne supprime pas une
--  animation qui a écrit au journal (clé étrangère) ni une animation
--  à laquelle un téléphone est rattaché. Celles-là sont désactivées et
--  leur PIN retiré — elles quittent la porte sans amputer le journal.
-- ---------------------------------------------------------------------
update public.animations
   set actif = false, code_pin = null
 where nom in ('Lancer de basket', 'Pétanque', 'Fléchettes', 'Chamboule-tout');

delete from public.animations a
 where a.actif = false
   and not exists (select 1 from public.journal   j where j.animation_id = a.id)
   and not exists (select 1 from public.appareils p where p.animation_id = a.id);

-- ---------------------------------------------------------------------
-- 2. Les 6 animations
--
--  Les noms sont recopiés tels que Bony les a donnés — c'est ce qui
--  sera écrit sur le panneau du stand, et l'animateur doit retrouver
--  le même libellé sur son téléphone.
-- ---------------------------------------------------------------------
insert into public.animations (nom, cout, code_pin, ordre, actif) values
  ('BASKET ARCADE',    2, '1001', 1, true),
  ('FLÉCHETTES',       2, '1002', 2, true),
  ('ATELIER PÉTANQUE', 2, '1003', 3, true),
  ('BORNE D''ARCADE',  2, '1004', 4, true),
  ('BLAZZPOD',         2, '1005', 5, true),
  ('CORN HOLE',        2, '1006', 6, true)
on conflict (nom) do update
  set cout     = excluded.cout,
      code_pin = excluded.code_pin,
      ordre    = excluded.ordre,
      actif    = true;

-- ---------------------------------------------------------------------
-- 3. Les barèmes
--
--  ordre 1 = le meilleur résultat. L'application affiche dans cet
--  ordre : l'animateur tape en haut le coup réussi, qui est le cas
--  qu'il saisira le plus souvent sous la pression de la file.
--
--  On repart de zéro pour que le fichier soit rejouable sans laisser
--  d'anciens paliers orphelins derrière une correction de libellé.
-- ---------------------------------------------------------------------
delete from public.bareme
 where animation_id in (select id from public.animations
                         where nom in ('BASKET ARCADE','FLÉCHETTES','ATELIER PÉTANQUE',
                                       'BORNE D''ARCADE','BLAZZPOD','CORN HOLE'));

insert into public.bareme (animation_id, libelle, points, ordre)
select a.id, b.libelle, b.points, b.ordre
from public.animations a
join (values
  -- score lu sur la machine — SEUILS À CONFIRMER À LA RÉPÉTITION
  ('BASKET ARCADE',    '10 paniers et plus',      20, 1),
  ('BASKET ARCADE',    '6 à 9 paniers',           10, 2),
  ('BASKET ARCADE',    '1 à 5 paniers',            5, 3),
  ('BASKET ARCADE',    'Aucun panier',             0, 4),

  -- résultat visible sur la cible, aucun seuil à caler
  ('FLÉCHETTES',       'Bull',                    20, 1),
  ('FLÉCHETTES',       'Zone 2',                  10, 2),
  ('FLÉCHETTES',       'Zone 3',                   5, 3),
  ('FLÉCHETTES',       'Hors cible',               0, 4),

  ('ATELIER PÉTANQUE', 'Carreau',                 20, 1),
  ('ATELIER PÉTANQUE', 'Le point',                10, 2),
  ('ATELIER PÉTANQUE', 'Dans le cercle',           5, 3),
  ('ATELIER PÉTANQUE', 'Manqué',                   0, 4),

  -- score lu sur la borne — SEUILS À CONFIRMER À LA RÉPÉTITION
  ('BORNE D''ARCADE',  'Meilleur score du jour',  20, 1),
  ('BORNE D''ARCADE',  'Dans le tableau des dix', 10, 2),
  ('BORNE D''ARCADE',  'Partie terminée',          5, 3),
  ('BORNE D''ARCADE',  'Partie abandonnée',        0, 4),

  -- nombre de touches sur le temps imparti — SEUILS À CONFIRMER
  ('BLAZZPOD',         '25 touches et plus',      20, 1),
  ('BLAZZPOD',         '18 à 24 touches',         10, 2),
  ('BLAZZPOD',         '10 à 17 touches',          5, 3),
  ('BLAZZPOD',         'Moins de 10 touches',      0, 4),

  -- résultat visible sur la planche, aucun seuil à caler
  ('CORN HOLE',        'Dans le trou',            20, 1),
  ('CORN HOLE',        'Sur la planche',          10, 2),
  ('CORN HOLE',        'Touche la planche',        5, 3),
  ('CORN HOLE',        'À côté',                   0, 4)
) as b(animation, libelle, points, ordre) on b.animation = a.nom;

-- ---------------------------------------------------------------------
-- 4. Contrôle immédiat
-- ---------------------------------------------------------------------
do $$
declare
  v_anim integer;
  v_sans integer;
  v_pins integer;
begin
  select count(*) into v_anim from public.animations where actif;
  select count(*) into v_sans
    from public.animations a
   where a.actif and not exists (select 1 from public.bareme b where b.animation_id = a.id);
  select count(distinct code_pin) into v_pins from public.animations where actif;

  if v_anim <> 6 then
    raise exception '6 animations actives attendues, % trouvées', v_anim;
  end if;
  if v_sans > 0 then
    raise exception '% animation(s) sans barème : écran animateur vide', v_sans;
  end if;
  if v_pins <> 6 then
    raise exception 'PIN d''animation en double : % distincts pour 6 animations', v_pins;
  end if;
  raise notice '6 animations actives, 24 résultats, 6 PIN distincts.';
end;
$$;
