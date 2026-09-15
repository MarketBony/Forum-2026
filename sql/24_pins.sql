-- =====================================================================
--  Forum Pièces Bony 2026 — 24 — Les 31 PIN définitifs du personnel
--
--  Remplace les PIN de démonstration (9137, 4200, 1001-1006, 2001-2023)
--  par des codes définitifs. Décision n°4 de CONTEXTE.md, la seule qui
--  était encore bloquante — levée le 15 septembre parce que les badges
--  n'étaient pas encore imprimés.
--
--  CE QUI CLOCHAIT AVEC LES ANCIENS : ils étaient SÉQUENTIELS. Un PIN de
--  stand est partagé par les cinq badges du stand et se porte au cou.
--  Quelqu'un qui lisait « 2001 » au dos d'un badge retourné ouvrait les
--  vingt-trois stands en comptant jusqu'à 2023 — et « 9137 », imprimé
--  nulle part mais écrit dans la documentation, ouvrait la supervision.
--  Les nouveaux ne se déduisent pas les uns des autres.
--
--  LA GARANTIE ANTI-COLLISION EST STRUCTURELLE, PAS VÉRIFIÉE APRÈS COUP.
--  L'alphabet des codes garage exclut O, I, 0 et 1 (sql/07_acces.sql).
--  Un PIN qui contient un 0 ou un 1 ne PEUT donc pas heurter un code
--  garage : c'est impossible par construction, pas improbable. Les 31
--  PIN ci-dessous contiennent tous un 0 ou un 1. verifier_portes() le
--  recontrôle quand même, et le contrôle en fin de fichier échoue s'il
--  trouve une seule collision.
--
--  ILS SONT TIRÉS D'UNE GRAINE FIXE (« grand-bal-2026-pins-definitifs »),
--  comme la grille et les codes garage : sha256(graine|rang) modulo
--  10000. Écartés au tirage : les PIN sans 0 ni 1, ceux à moins de trois
--  chiffres distincts (1011, 2002…) et les suites (1234, 9876). Le
--  tirage est donc rejouable et vérifiable — personne ne peut prétendre
--  qu'un PIN a été choisi à la main pour arranger quelqu'un.
--
--  ⚠️ À POUSSER AVANT D'IMPRIMER LES BADGES.
--  La vue v_badges résout le code À LA LECTURE : changer un PIN ici met
--  à jour les badges concernés sans toucher une ligne de participants.
--  Il suffit donc de relancer scripts\exporter-badges.ps1 puis l'export
--  PDF. Après impression, en revanche, un changement jette le papier :
--  115 badges exposants, 6 animateurs et 2 hôtesses portent ces codes.
--
--  ⚠️ LES BATTERIES DE TESTS NE DOIVENT PLUS ÉCRIRE DE PIN EN DUR.
--  Elles lisaient 1001, 2001, 4200 et 9137 dans leur code ; elles vont
--  désormais les chercher en base. Un test qui recopie un secret casse
--  le jour où le secret change, et fait croire à une panne applicative.
--
--  Rejouable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Les deux codes de config
-- ---------------------------------------------------------------------
update public.config set valeur = '6305' where cle = 'pin_admin';
update public.config set valeur = '7132' where cle = 'pin_accueil';

-- ---------------------------------------------------------------------
-- 2. Les six animations
--
--  L'ordre est celui de animations.ordre, pour qu'on retrouve la même
--  liste ici et sur l'écran animateur.
-- ---------------------------------------------------------------------
update public.animations a set code_pin = v.pin
from (values
  ('BASKET ARCADE',    '0237'),
  ('FLÉCHETTES',       '3156'),
  ('ATELIER PÉTANQUE', '1462'),
  ('BORNE D''ARCADE',  '1240'),
  ('BLAZZPOD',         '2418'),
  ('CORN HOLE',        '4815')
) as v(nom, pin)
where a.nom = v.nom;

-- ---------------------------------------------------------------------
-- 3. Les vingt-trois stands
--
--  Regroupés par catégorie pour la relecture, mais les PIN ne suivent
--  volontairement AUCUN ordre : deux stands voisins sur le plan n'ont
--  pas deux codes voisins.
-- ---------------------------------------------------------------------
update public.stands s set code_pin = v.pin
from (values
  -- CA
  ('FAAB',               '7199'),
  ('IXELL',              '1033'),
  ('ACCESSOIRES',        '2915'),
  ('FACOM',              '1018'),
  ('SAM',                '0363'),
  ('NILFISK',            '8341'),
  ('SPM',                '8761'),
  -- ENTRETIEN USURE
  ('MOTRIO',             '8506'),
  ('AGENT',              '5919'),
  -- HUILES
  ('CASTROL',            '0677'),
  ('ELF',                '3080'),
  -- SOLUTIONS
  ('SIDEXA',             '3065'),
  ('WYZ',                '8980'),
  ('BARDHAL',            '6085'),
  ('FIDUCIAL',           '5661'),
  ('CHIMIREC',           '8908'),
  -- GROS ÉQUIPEMENT
  ('CISCAR',             '3179'),
  ('PROVAC',             '0263'),
  ('MATEXPERT',          '0592'),
  ('FILLON TECHNOLOGIE', '6134'),
  ('EXADIS',             '9810'),
  -- PNEUS
  ('GOODYEAR',           '7179'),
  ('MICHELIN',           '7500')
) as v(nom, pin)
where s.nom = v.nom;

-- ---------------------------------------------------------------------
-- 4. Contrôle immédiat
--
--  Cinq invariants. Le plus important est le troisième : un PIN sans 0
--  ni 1 perdrait la garantie structurelle et ne tiendrait plus que par
--  la chance du tirage.
-- ---------------------------------------------------------------------
do $$
declare
  v_tous   text[];
  v_n      integer;
  v_sans   integer;
  v_coll   integer;
  v_court  integer;
begin
  select array_agg(p) into v_tous from (
    select valeur as p from public.config where cle in ('pin_admin','pin_accueil')
    union all select code_pin from public.animations where actif and code_pin is not null
    union all select code_pin from public.stands     where actif and code_pin is not null
  ) t;

  v_n := array_length(v_tous, 1);
  select count(*) into v_court from unnest(v_tous) p where length(p) <> 4;
  select count(*) into v_sans  from unnest(v_tous) p where p !~ '[01]';
  select count(*) into v_coll  from public.verifier_portes();

  if v_n <> 31 then
    raise exception '31 PIN attendus, % trouvés', v_n;
  end if;
  if (select count(distinct p) from unnest(v_tous) p) <> 31 then
    raise exception 'PIN en double : % distincts pour 31', (select count(distinct p) from unnest(v_tous) p);
  end if;
  if v_sans > 0 then
    raise exception '% PIN sans 0 ni 1 : la garantie anti-collision structurelle est perdue', v_sans;
  end if;
  if v_court > 0 then
    raise exception '% PIN qui ne font pas 4 caractères', v_court;
  end if;
  if v_coll > 0 then
    raise exception '% collision(s) entre un code garage et un PIN', v_coll;
  end if;
  raise notice '31 PIN définitifs, tous distincts, tous porteurs d''un 0 ou d''un 1, 0 collision.';
end;
$$;
