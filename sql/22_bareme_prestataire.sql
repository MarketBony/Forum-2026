-- =====================================================================
--  Forum Pièces Bony 2026 — 22 — Le barème du prestataire, recalibré
--
--  Remplace les paliers inventés de sql/16_animations.sql par ceux que
--  le prestataire de l'animation a réellement écrits, ramenés sur notre
--  échelle de points.
--
--  LA RÈGLE, EN UNE PHRASE :
--      UNE ANIMATION PLAFONNE À UNE DEMI-CASE.
--
--  Une case coûte 20 points. Le plus beau coup de la journée en rapporte
--  10 : il faut DEUX exploits pour s'offrir une case. C'est la seule
--  phrase à retenir, et elle se vérifie d'un coup d'œil sur la grille
--  ci-dessous — aucun palier ne dépasse 10.
--
--  Cinq valeurs, et cinq seulement : 10 · 5 · 3 · 2 · 0.
--  Pas de 6, pas de 12, pas de 16. Un animateur qui annonce « +5 » à
--  voix haute dans le bruit se fait comprendre du premier coup ; « +16 »
--  se fait répéter. Et un garagiste qui compte ses points de tête compte
--  par 5, pas par 4.
--
--  LE PALIER LE PLUS BAS VAUT 2, soit EXACTEMENT la participation.
--  C'est ce qui donne la règle que l'animateur peut gueuler par-dessus
--  la sono, et qui est la seule explication que le jeu demande :
--      « tu marques quelque chose, tu ne perds rien ;
--        tu ne marques rien, ça t'a coûté 2. »
--
--  POURQUOI PAS LE BARÈME DU PRESTATAIRE AU PIED DE LA LETTRE.
--  Sa feuille (10/5/2 à la pétanque, 8/4/2 au corn hole, 6 à Pac-Man…)
--  classe ses jeux entre eux, ce qui est son métier. Mais elle est
--  calibrée contre rien : chez nous le seul nombre qui a un sens, c'est
--  20 = une case. Son CLASSEMENT est donc conservé intact, jeu par jeu —
--  le tir paie plus que le pointeur à chaque niveau, comme chez lui —
--  et c'est le NIVEAU qu'on pose, parce qu'il n'appartient qu'à nous.
--
--  POURQUOI LES PLAFONDS NE SONT PAS ÉGAUX D'UN JEU À L'AUTRE.
--  sql/16_animations.sql imposait 20 partout pour que la halle ne fasse
--  pas la queue au même endroit. Cette règle sautait parce que les six
--  jeux étaient notés au doigt mouillé et se valaient donc par défaut.
--  Ici, les trois jeux où l'exploit est RARE (les 3 boules au tir, les
--  3 sachets, le centre rouge) plafonnent à 10 ; les trois où le bon
--  résultat est courant (finir le niveau 1 de Pac-Man, faire un score
--  correct en 45 s) plafonnent à 5. Payer pareil un coup rare et un coup
--  courant, c'est ce qui vide un stand. Et ce qui répartira vraiment la
--  foule n'est de toute façon pas le barème, c'est le DÉBIT : 45 s le
--  basket, plusieurs minutes le niveau 1 de Pac-Man.
--
--  LA PARTICIPATION RESTE À 2 POINTS, décision de Bony, inchangée.
--  Elle se règle toujours en direct, jeu par jeu, sans redéploiement :
--      update animations set cout = 3 where nom = 'BASKET ARCADE';
--
--  ⚠️ LES NOMS DES SIX ANIMATIONS NE BOUGENT PAS.
--  Le prestataire écrit « PETANQUE », « BORNE ARCADE » ; la base dit
--  « ATELIER PÉTANQUE », « BORNE D'ARCADE ». Ce sont ces noms-là qui
--  sont IMPRIMÉS sur les 6 badges animateur et qui portent les PIN 1001
--  à 1006. Les aligner sur le prestataire jetterait les badges pour un
--  gain nul : l'animateur lit le nom de SON jeu, pas celui du voisin.
--
--  ⚠️ À POUSSER AVANT LE JOUR J, PAS PENDANT.
--  api_noter() retrouve le palier par son id. Un téléphone animateur
--  resté ouvert sur l'ancien écran garde les anciens id en mémoire : sa
--  prochaine saisie échouerait. Le journal, lui, ne risque rien — il
--  recopie le libellé en texte et ne référence pas bareme.
--
--  Rejouable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. On repart de zéro sur les six barèmes
--
--  Aucune clé étrangère ne pointe vers bareme depuis le journal : une
--  ligne supprimée n'ampute aucun historique. C'est ce qui rend ce
--  fichier rejouable sans laisser de paliers orphelins derrière une
--  correction de libellé.
-- ---------------------------------------------------------------------
delete from public.bareme
 where animation_id in (select id from public.animations
                         where nom in ('BASKET ARCADE','FLÉCHETTES','ATELIER PÉTANQUE',
                                       'BORNE D''ARCADE','BLAZZPOD','CORN HOLE'));

-- ---------------------------------------------------------------------
-- 2. Les paliers
--
--  ordre 1 = en haut de l'écran animateur. Il tape sous la pression de
--  la file : le résultat le plus valorisant en premier, le « rien » tout
--  en bas, là où un pouce ne glisse pas par accident.
--
--  Le chiffre en fin de ligne est celui de la feuille du prestataire,
--  reçue le 15 septembre 2026. Il n'est pas décoratif : c'est lui qui se
--  relit face au document, le jour où quelqu'un demandera pourquoi son
--  « 8 » est devenu un « 5 ».
-- ---------------------------------------------------------------------
insert into public.bareme (animation_id, libelle, points, ordre)
select a.id, b.libelle, b.points, b.ordre
from public.animations a
join (values
  -- PÉTANQUE — deux façons de jouer ses 3 boules, et l'animateur sait
  -- laquelle le joueur a choisie. Le préfixe « Tir » / « Pointeur »
  -- évite qu'il cherche sa ligne dans une liste de sept.
  -- Le tir paie plus que le pointeur à chaque niveau : c'est le seul
  -- rapport que le prestataire ait vraiment établi, et il est conservé.
  --                                                          presta
  ('ATELIER PÉTANQUE', 'Tir · 3 boules sur 3',          10, 1),  -- 10
  ('ATELIER PÉTANQUE', 'Tir · 2 boules sur 3',           5, 2),  --  5
  ('ATELIER PÉTANQUE', 'Pointeur · 3 cerceaux',          5, 3),  --  5
  ('ATELIER PÉTANQUE', 'Pointeur · 2 cerceaux',          3, 4),  --  3
  ('ATELIER PÉTANQUE', 'Tir · 1 boule sur 3',            2, 5),  --  2
  ('ATELIER PÉTANQUE', 'Pointeur · 1 cerceau',           2, 6),  --  1
  ('ATELIER PÉTANQUE', 'Rien de marqué',                 0, 7),

  -- CORN HOLE — même structure que le tir, sur 3 sachets. Les 3 sachets
  -- sont aussi rares que les 3 tirs : même plafond.
  ('CORN HOLE',        '3 sachets sur 3',               10, 1),  --  8
  ('CORN HOLE',        '2 sachets sur 3',                5, 2),  --  4
  ('CORN HOLE',        '1 sachet sur 3',                 2, 3),  --  2
  ('CORN HOLE',        'Aucun sachet',                   0, 4),

  -- BORNE D'ARCADE — le prestataire a tranché : Pac-Man et rien d'autre,
  -- un seul palier. Deux boutons, c'est le seul écran animateur qu'on ne
  -- peut pas se tromper à saisir. Les trois seuils « marque-place » de
  -- sql/16_animations.sql (meilleur score du jour, tableau des dix…)
  -- disparaissent, et c'est une bonne nouvelle : ils n'auraient jamais
  -- pu être calés sans voir la machine.
  -- À 5 et non 10 : finir le niveau 1 n'est pas un exploit, c'est une
  -- question de patience — et ça immobilise la borne plusieurs minutes.
  ('BORNE D''ARCADE',  'Niveau 1 terminé',               5, 1),  --  6
  ('BORNE D''ARCADE',  'Niveau 1 non terminé',           0, 2),

  -- FLÉCHETTES — le centre rouge est le coup le plus dur de la journée :
  -- il vaut donc le plafond, alors que le prestataire le mettait au même
  -- niveau que Pac-Man. C'est la seule fois où on s'écarte de son
  -- classement entre jeux, et c'est assumé.
  -- Un TROISIÈME PALIER a été demandé au prestataire : avec ses deux
  -- seuls paliers, l'espérance du jeu tombe sous les 2 pts de
  -- participation et le stand se vide après une heure. En attendant sa
  -- réponse, « Les 3 fléchettes dans la cible » est un MARQUE-PLACE :
  --   delete from bareme where libelle = 'Les 3 fléchettes dans la cible';
  ('FLÉCHETTES',       'Centre rouge',                  10, 1),  --  6
  ('FLÉCHETTES',       'Centre vert ou triple annoncé',  5, 2),  --  3
  ('FLÉCHETTES',       'Les 3 fléchettes dans la cible', 2, 3),  -- ajout
  ('FLÉCHETTES',       'À côté',                         0, 4),

  -- BASKET ARCADE et BLAZZPOD — « TOP SCORE EN 45 SECONDES, 4 PTS À
  -- GAGNER ». La phrase donne un plafond, aucun seuil, et l'application
  -- a besoin de paliers : l'animateur choisit un résultat, il ne saisit
  -- pas un nombre. Le palier du milieu est un MARQUE-PLACE, à caler en
  -- trois parties d'essai à la répétition — l'animateur écrit le score à
  -- battre sur son ardoise et note par rapport à lui.
  -- À 5 : 45 secondes, tout le monde marque, c'est le jeu le plus sûr
  -- de la halle. Le payer comme un carreau serait la porte ouverte à
  -- l'enchaînement — c'est précisément là que la file tourne le plus vite.
  ('BASKET ARCADE',    'Meilleur score du moment',       5, 1),  --  4
  ('BASKET ARCADE',    'Score honorable',                2, 2),  -- seuil
  ('BASKET ARCADE',    'Petit score',                    0, 3),

  ('BLAZZPOD',         'Meilleur score du moment',       5, 1),  --  4
  ('BLAZZPOD',         'Score honorable',                2, 2),  -- seuil
  ('BLAZZPOD',         'Petit score',                    0, 3)
) as b(animation, libelle, points, ordre) on b.animation = a.nom;

-- ---------------------------------------------------------------------
-- 3. Contrôle immédiat
--
--  Cinq invariants qui, s'ils cassaient, ne se verraient qu'au Forum :
--  une animation sans barème donne un écran animateur vide ; un palier
--  au-dessus d'une demi-case rouvre la porte à la case gagnée d'un seul
--  coup ; un jeu sans palier à 0 rend la participation gratuite ; un
--  palier qui n'est pas dans les cinq valeurs rondes est une faute de
--  frappe ; et une animation orpheline signifie qu'un nom a été mal
--  recopié dans le bloc values ci-dessus — la jointure l'aurait ignorée
--  sans un mot.
-- ---------------------------------------------------------------------
do $$
declare
  v_anim   integer;
  v_sans   integer;
  v_haut   integer;
  v_nul    integer;
  v_rond   integer;
  v_total  integer;
  v_max    integer := public.cfg_int('cout_grille', 20) / 2;
begin
  select count(*) into v_anim from public.animations where actif;

  select count(*) into v_sans
    from public.animations a
   where a.actif and not exists (select 1 from public.bareme b where b.animation_id = a.id);

  select count(*) into v_haut
    from public.bareme b join public.animations a on a.id = b.animation_id
   where a.actif and b.points > v_max;

  select count(*) into v_nul
    from public.animations a
   where a.actif and not exists
     (select 1 from public.bareme b where b.animation_id = a.id and b.points = 0);

  select count(*) into v_rond
    from public.bareme b join public.animations a on a.id = b.animation_id
   where a.actif and b.points not in (0, 2, 3, 5, 10);

  select count(*) into v_total
    from public.bareme b join public.animations a on a.id = b.animation_id where a.actif;

  if v_anim <> 6 then
    raise exception '6 animations actives attendues, % trouvées', v_anim;
  end if;
  if v_sans > 0 then
    raise exception '% animation(s) sans barème : écran animateur vide', v_sans;
  end if;
  if v_haut > 0 then
    raise exception '% palier(s) au-dessus d''une demi-case (% pts)', v_haut, v_max;
  end if;
  if v_nul > 0 then
    raise exception '% animation(s) sans palier à 0 : la participation devient gratuite', v_nul;
  end if;
  if v_rond > 0 then
    raise exception '% palier(s) hors des cinq valeurs rondes 0/2/3/5/10', v_rond;
  end if;
  raise notice '6 animations, % paliers, plafond % pts, participation 2.', v_total, v_max;
end;
$$;
