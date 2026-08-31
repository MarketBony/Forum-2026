-- =====================================================================
--  Forum Pièces Bony 2026 — 03 — Données de départ
--
--  Tout est rejouable : ON CONFLICT DO NOTHING partout.
--  Les barèmes et les codes PIN sont des exemples : ils se modifient
--  depuis la table, sans redéploiement.
--
--  Les 388 garages marqués ville = 'DÉMO' servent au test de charge.
--  Pour les retirer avant l'événement :
--      delete from garages where ville = 'DÉMO';
-- =====================================================================

-- ---------------------------------------------------------------------
-- Réglages
-- ---------------------------------------------------------------------
insert into public.config (cle, valeur, description) values
  ('bonus_inscription', '10',   'Points offerts à l''inscription, une fois par garage'),
  ('cout_grille',       '20',   'Points pour une participation à la grille des lots'),
  ('pin_admin',         '9137', 'Code de l''espace Bony — À CHANGER avant l''événement')
on conflict (cle) do nothing;

-- ---------------------------------------------------------------------
-- Animations et barèmes (§9)
-- ---------------------------------------------------------------------
insert into public.animations (nom, cout, code_pin, ordre) values
  ('Lancer de basket', 2, '1001', 1),
  ('Pétanque',         2, '1002', 2),
  ('Fléchettes',       3, '1003', 3),
  ('Chamboule-tout',   2, '1004', 4)
on conflict (nom) do nothing;

insert into public.bareme (animation_id, libelle, points, ordre)
select a.id, b.libelle, b.points, b.ordre
from public.animations a
join (values
  ('Lancer de basket', 'Panier',        10, 1),
  ('Lancer de basket', 'Sur l''anneau',  5, 2),
  ('Lancer de basket', 'À côté',         0, 3),
  ('Pétanque',         'Carreau',       15, 1),
  ('Pétanque',         'Le point',       8, 2),
  ('Pétanque',         'Manqué',         0, 3),
  ('Fléchettes',       'Bull',          20, 1),
  ('Fléchettes',       'Zone 2',        10, 2),
  ('Fléchettes',       'Zone 3',         5, 3),
  ('Fléchettes',       'Hors cible',     0, 4),
  ('Chamboule-tout',   'Tout tombe',    12, 1),
  ('Chamboule-tout',   'Moitié',         6, 2),
  ('Chamboule-tout',   'Rien',           0, 3)
) as b(animation, libelle, points, ordre) on b.animation = a.nom
on conflict (animation_id, libelle) do nothing;

-- ---------------------------------------------------------------------
-- Stands fournisseurs (§10) — plafonds volontairement serrés
-- ---------------------------------------------------------------------
insert into public.stands (nom, code_pin, plafond_operation, plafond_soiree) values
  ('Filtres Auvergne',        '2001', 50, 1500),
  ('Équip''Pro Diagnostic',   '2002', 50, 1500),
  ('Freinage Massif',         '2003', 50, 1500),
  ('Lubrifiants Volcan',      '2004', 50, 1500),
  ('Pneus Chaîne des Puys',   '2005', 50, 1500)
on conflict (nom) do nothing;

-- ---------------------------------------------------------------------
-- La grille des 100 cases (§11) — 13 cases gagnantes
-- ---------------------------------------------------------------------
insert into public.grille (numero)
select generate_series(1, 100)
on conflict (numero) do nothing;

update public.grille g set gagnante = true, lot = v.lot
from (values
  ( 7, 'Coffret à outils 120 pièces'),
  (13, 'Enceinte nomade'),
  (22, 'Bon d''achat 100 €'),
  (31, 'Nettoyeur haute pression'),
  (38, 'Panier gourmand d''Auvergne'),
  (44, 'Bon d''achat 50 €'),
  (57, 'Caméra de recul sans fil'),
  (63, 'Coffret de douilles'),
  (71, 'Bon d''achat 100 €'),
  (79, 'Casque Bluetooth'),
  (86, 'Ballon officiel ASM'),
  (92, 'Bon d''achat 50 €'),
  (99, 'Week-end pour deux en Auvergne')
) as v(numero, lot)
where g.numero = v.numero and not g.gagnante;

-- ---------------------------------------------------------------------
-- Garages : 12 nommés (démonstration lisible) …
-- ---------------------------------------------------------------------
insert into public.garages (nom, ville) values
  ('Garage Dupont',          'Clermont-Ferrand'),
  ('Garage Dupuy',           'Cournon-d''Auvergne'),
  ('Carrosserie Marchand',   'Riom'),
  ('Auto Services Chabrier', 'Issoire'),
  ('Garage du Velay',        'Le Puy-en-Velay'),
  ('Méca Thiers',            'Thiers'),
  ('Garage Vidal',           'Aurillac'),
  ('Point Auto Vichy',       'Vichy'),
  ('Garage Fournier',        'Montluçon'),
  ('SARL Auto Brioude',      'Brioude'),
  ('Garage Delorme',         'Moulins'),
  ('Ambert Pneus & Méca',    'Ambert')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- … et 388 garages de charge, pour tester à l'échelle réelle (400)
-- ---------------------------------------------------------------------
insert into public.garages (nom, ville)
select 'Garage démo ' || lpad(i::text, 3, '0'), 'DÉMO'
from generate_series(1, 388) i
on conflict do nothing;
