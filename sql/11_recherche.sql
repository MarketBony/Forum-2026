-- =====================================================================
--  Forum Pièces Bony 2026 — 11 — La recherche ignore aussi la ponctuation
--
--  LE DÉFAUT : norm() ne neutralisait que les accents et la casse. La
--  colonne de recherche contenait donc « saint-bonnet pres riom » avec
--  son tiret, et « cadr'auto » avec son apostrophe. Or une hôtesse tape
--  « saint bonnet » avec une espace, et personne ne tape d'apostrophe.
--  Résultat : « vic sur cere » et « saint cere » ne trouvaient RIEN,
--  et toutes les communes en Saint-quelque-chose étaient introuvables
--  dès qu'on séparait les mots par une espace.
--
--  LA CORRECTION : norm() ramène désormais tirets, apostrophes, points
--  et barres obliques à une espace, puis réduit les espaces multiples.
--  La colonne générée est reconstruite pour être recalculée avec la
--  nouvelle règle — remplacer la fonction ne suffit pas, les valeurs
--  déjà stockées ne bougeraient pas.
-- =====================================================================

create or replace function public.norm(t text)
returns text
language sql
immutable
strict
parallel safe
as $$
  select trim(regexp_replace(
           regexp_replace(
             lower(translate(t,
               'àáâäãåÀÁÂÄÃÅçÇèéêëÈÉÊËìíîïÌÍÎÏñÑòóôöõÒÓÔÖÕùúûüÙÚÛÜÿŸ',
               'aaaaaaAAAAAAcCeeeeEEEEiiiiIIIInNoooooOOOOOuuuuUUUUyY')),
             '[-''’./&,()]+', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

-- La colonne générée doit être reconstruite pour être recalculée.
drop index if exists public.garages_recherche_idx;
alter table public.garages drop column if exists recherche;
alter table public.garages
  add column recherche text generated always as (public.norm(nom || ' ' || ville)) stored;
create index garages_recherche_idx on public.garages (recherche);

-- Contrôle : les cas qui échouaient doivent désormais passer.
select
  norm('Saint-Bonnet près Riom')                        as exemple_1,
  norm('Cadr''Auto')                                    as exemple_2,
  norm('Vic-sur-Cère')                                  as exemple_3,
  (select count(*)::int from garages
    where recherche like '%' || norm('vic sur cere') || '%')   as trouve_vic_sur_cere,
  (select count(*)::int from garages
    where recherche like '%' || norm('saint cere') || '%')     as trouve_saint_cere,
  (select count(*)::int from garages
    where recherche like '%' || norm('saint bonnet') || '%')   as trouve_saint_bonnet,
  (select count(*)::int from garages
    where recherche like '%' || norm('cadr auto') || '%')      as trouve_cadr_auto;
