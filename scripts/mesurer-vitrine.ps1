#requires -Version 5
# =====================================================================
#  mesurer-vitrine.ps1 — ce que coûtent api_vitrine, api_etat et
#  api_supervision sur un journal de VRAIE soirée, mesuré sur la base
#  de production SANS Y ÉCRIRE UNE SEULE LIGNE.
#
#  ---------------------------------------------------------------------
#  POURQUOI CE BANC EXISTE
#
#  api_vitrine est le seul coût NON CONSTANT de l'application. Elle est
#  appelée par 140 téléphones toutes les 30 secondes et elle fait, à
#  chaque appel, un verifier_soldes() (balayage du journal joint aux
#  1 456 garages), quatre agrégats sur le journal et trois podiums en
#  group by. Son prix grandit donc avec la soirée — c'est le seul
#  analogue, dans ce projet, de la cause n° 2 de la panne de GRID du
#  8 septembre 2026 (voir §18 de CONTEXTE.md).
#
#  Or on ne peut pas mesurer ça le jour J : quand le journal est enfin
#  plein, il est trop tard pour changer quoi que ce soit. Et on ne peut
#  pas le mesurer la veille non plus, puisque la base doit rester à
#  zéro. D'où ce banc.
#
#  ---------------------------------------------------------------------
#  POURQUOI IL EST SÛR — ET POURQUOI IL S'AFFICHE EN ÉCHEC
#
#  Tout se passe dans UN SEUL bloc DO qui se termine par un
#  RAISE EXCEPTION. Une exception plpgsql annule la transaction
#  entière : les lignes de journal, les appareils de mesure et les
#  soldes retouchés disparaissent tous, quoi qu'il arrive — y compris
#  si la connexion tombe au milieu.
#
#  Le rapport de mesure est donc transporté DANS le message d'erreur,
#  précisément parce qu'il n'existe aucun moyen de faire sortir une
#  donnée d'une transaction annulée. **L'ÉCHEC EST LE FONCTIONNEMENT
#  NORMAL DE CE SCRIPT.** Un HTTP 400 ici est le signe que tout s'est
#  bien passé.
#
#  C'est aussi pour ça qu'il n'utilise pas push-sql.ps1 :
#  Invoke-WebRequest ne rend pas le corps des réponses 4xx (voir
#  §Environnement de CLAUDE.md), et le corps est justement le rapport.
#
#  Seule trace possible : la séquence journal_id_seq avance du nombre de
#  lignes simulées. Sans conséquence — rien ne dépend de la continuité
#  des identifiants du journal.
#
#  ---------------------------------------------------------------------
#  CE QU'IL NE MESURE PAS : le réseau. Les temps rendus sont des temps
#  EN BASE, pris par clock_timestamp() de part et d'autre de l'appel.
#  Pour le bout-en-bout vu d'un téléphone, c'est banc-jour-j.ps1.
#
#    .\scripts\mesurer-vitrine.ps1
#    .\scripts\mesurer-vitrine.ps1 -Volumes 0,3000,10000
#    .\scripts\mesurer-vitrine.ps1 -Appels 30       # plus d'appels, p50 plus sûr
# =====================================================================
[CmdletBinding()]
param(
  [int[]]$Volumes = @(0, 1500, 3000, 6000, 12000, 20000),
  [int]$Appels    = 12,    # par volume et par fonction ; le 1er est jeté
  [int]$Garages   = 300    # garages porteurs du journal simulé
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$ref = $conf['SUPABASE_PROJECT_REF']
$pat = $conf['SUPABASE_ACCESS_TOKEN']

$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(300)

function Sql($requete) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $requete } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat")
  $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $t = $r.Content.ReadAsStringAsync().Result
  return @{ ok = $r.IsSuccessStatusCode; http = [int]$r.StatusCode; corps = $t }
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Coût des lectures selon le volume du journal'
Write-Output '  (transaction annulée — rien ne sera écrit)'
Write-Output '===================================================================='
Write-Output ''

# ---------------------------------------------------------------------
#  GARDE-FOU. Le banc simule un journal ; si le vrai journal n'est pas
#  vide, ses lignes se mélangeraient aux vraies dans les agrégats et la
#  mesure ne voudrait rien dire. Et surtout : pendant le Forum, on ne
#  prend pas de verrous sur `garages` pour le plaisir de mesurer.
#  La transaction s'annule de toute façon, mais la bonne règle reste
#  celle du §18.4 — on ne joue pas avec la base pendant la soirée.
# ---------------------------------------------------------------------
$etat = (Sql "select (select count(*) from journal) as journal").corps | ConvertFrom-Json
if ([int]$etat.journal -gt 0) {
  Write-Output ('  ARRET : le journal porte deja {0} ligne(s).' -f $etat.journal)
  Write-Output '  Le Forum a commence, ou une repetition n''a pas ete nettoyee.'
  Write-Output '  Ce banc ne se lance que sur une base au repos.'
  Write-Output ''
  exit 1
}
Write-Output '  Base au repos (journal 0) — mesure en cours, ~1 minute...'

$listeVolumes = ($Volumes | Sort-Object -Unique) -join ', '

# ---------------------------------------------------------------------
#  La mesure. Le SQL est en here-string LITTÉRALE (@'...'@) : pas
#  d'interpolation PowerShell, donc les $$ du plpgsql et les %s de
#  format() passent intacts. Les trois réglages sont injectés après.
# ---------------------------------------------------------------------
$sql = @'
do $$
declare
  v_volumes  int[] := array[@@VOLUMES@@];
  v_appels   int   := @@APPELS@@;
  v_garages  int   := @@GARAGES@@;
  v_vol      int;
  v_actuel   bigint;
  v_jv       text := repeat('v', 64);
  v_ja       text := repeat('a', 64);
  v_jg       text := repeat('g', 64);
  v_garage   uuid;
  v_t0       timestamptz;
  v_lat      numeric[];
  v_i        int;
  v_p50      numeric;
  v_p95      numeric;
  v_ms       numeric;
  v_rapport  text := '';
begin
  -- Trois appareils de mesure, un par profil à chronométrer.
  select id into v_garage from public.garages where actif order by id limit 1;
  insert into public.appareils (jeton, role, libelle) values (v_jv, 'vitrine', 'MESURE');
  insert into public.appareils (jeton, role, libelle) values (v_ja, 'admin',   'MESURE');
  insert into public.appareils (jeton, role, garage_id, libelle)
       values (v_jg, 'garage', v_garage, 'MESURE');

  v_rapport := E'\n'
    || '  journal | api_vitrine p50 | p95      | api_etat p50 | api_supervision p50' || E'\n'
    || '  --------+-----------------+----------+--------------+--------------------' || E'\n';

  foreach v_vol in array v_volumes loop
    select count(*) into v_actuel from public.journal;

    if v_vol > v_actuel then
      -- Réparti en TOURNIQUET (order by n, rg) : au tour n, les N
      -- garages prennent une ligne chacun. Remplir garage par garage
      -- concentrerait le journal sur une poignée de garages, et les
      -- podiums grouperaient sur dix valeurs au lieu de trois cents —
      -- la mesure serait fausse dans le sens rassurant.
      --
      -- La cible est ABSOLUE et non un delta : les lignes du tour
      -- précédent portent les mêmes cle_idem et sont écartées par le
      -- ON CONFLICT. Avec un delta, le volume ne montait plus à partir
      -- du troisième tour — défaut constaté au premier passage.
      insert into public.journal
        (garage_id, delta, libelle, source, animation_id, stand_id, cle_idem, cree_le)
      select x.id,
             case when x.n % 3 = 0 then -2 else 5 + (x.n % 4) * 5 end,
             'mesure de charge',
             case when x.n % 3 = 0 then 'animation' else 'fournisseur' end,
             case when x.n % 3 = 0 then
               (select id from public.animations order by id
                 offset (x.n % (select count(*) from public.animations)) limit 1) end,
             case when x.n % 3 <> 0 then
               (select id from public.stands order by id
                 offset (x.n % (select count(*) from public.stands)) limit 1) end,
             'mesure|' || x.id || '|' || x.n,
             now() - ((x.n % 360) || ' minutes')::interval
        from (
          select g.id, n, row_number() over (order by n, g.rg) as rn
            from (select id, row_number() over (order by id) as rg
                    from public.garages where actif order by id limit v_garages) g
            cross join generate_series(1, 400) n
        ) x
       where x.rn <= v_vol
      on conflict (cle_idem) do nothing;

      -- Recaler les soldes : sur la vraie base l'invariant
      -- « solde = somme(journal) » tient, donc verifier_soldes() rend
      -- ZÉRO ligne. Mesurer avec trois cents écarts fabriquerait un cas
      -- qui n'existe pas le jour J.
      update public.garages g
         set solde = s.total
        from (select garage_id, sum(delta)::int as total
                from public.journal group by garage_id) s
       where s.garage_id = g.id and g.solde <> s.total;
    end if;

    select count(*) into v_actuel from public.journal;

    -- api_vitrine : les 140 téléphones de l'équipe Bony
    v_lat := array[]::numeric[];
    for v_i in 1..v_appels loop
      v_t0 := clock_timestamp();
      perform public.api_vitrine(v_jv);
      if v_i > 1 then   -- le premier appel paie le cache froid
        v_lat := v_lat || (extract(epoch from (clock_timestamp() - v_t0)) * 1000)::numeric;
      end if;
    end loop;
    select percentile_cont(0.5)  within group (order by x),
           percentile_cont(0.95) within group (order by x)
      into v_p50, v_p95 from unnest(v_lat) as x;

    -- api_etat : le sondage des 200 garagistes
    v_lat := array[]::numeric[];
    for v_i in 1..v_appels loop
      v_t0 := clock_timestamp();
      perform public.api_etat(v_jg);
      if v_i > 1 then
        v_lat := v_lat || (extract(epoch from (clock_timestamp() - v_t0)) * 1000)::numeric;
      end if;
    end loop;
    select percentile_cont(0.5) within group (order by x) into v_ms from unnest(v_lat) as x;

    v_rapport := v_rapport || format('  %7s | %12s ms | %5s ms | %9s ms | ',
                   v_actuel, round(v_p50, 2), round(v_p95, 2), round(v_ms, 3));

    -- api_supervision : la tablette Bony
    v_lat := array[]::numeric[];
    for v_i in 1..greatest(3, v_appels / 2) loop
      v_t0 := clock_timestamp();
      perform public.api_supervision(v_ja);
      if v_i > 1 then
        v_lat := v_lat || (extract(epoch from (clock_timestamp() - v_t0)) * 1000)::numeric;
      end if;
    end loop;
    select percentile_cont(0.5) within group (order by x) into v_ms from unnest(v_lat) as x;

    v_rapport := v_rapport || format('%15s ms', round(v_ms, 2)) || E'\n';
  end loop;

  -- -------------------------------------------------------------------
  --  Décomposition au plus gros volume : OÙ part le temps ?
  --  C'est ce tableau qui dit quelle clé tourner si ça dérape un jour.
  --  Relevé le 16/09/2026 à 20 000 lignes : les trois podiums pèsent
  --  74 ms sur 120, et verifier_soldes() seulement 22. Sortir l'audit
  --  des soldes ne récupérerait que 18 % du temps — ce sont les podiums
  --  qu'il faudrait plafonner.
  -- -------------------------------------------------------------------
  select count(*) into v_actuel from public.journal;
  v_rapport := v_rapport || E'\n'
    || format('  DECOMPOSITION DE api_vitrine A %s LIGNES', v_actuel) || E'\n\n';

  v_t0 := clock_timestamp();
  for v_i in 1..5 loop perform count(*) from public.verifier_soldes(); end loop;
  v_rapport := v_rapport || format('    verifier_soldes() .............. %s ms',
    round(extract(epoch from (clock_timestamp() - v_t0)) * 1000 / 5, 2)) || E'\n';

  v_t0 := clock_timestamp();
  for v_i in 1..5 loop
    perform count(*) filter (where usename = 'authenticator' and state = 'active')
       from pg_stat_activity;
  end loop;
  v_rapport := v_rapport || format('    pg_stat_activity ............... %s ms',
    round(extract(epoch from (clock_timestamp() - v_t0)) * 1000 / 5, 2)) || E'\n';

  v_t0 := clock_timestamp();
  for v_i in 1..5 loop
    perform (select jsonb_agg(x) from (
      select jsonb_build_object('nom', g.nom, 'points', sum(j.delta)) as x
        from public.journal j join public.garages g on g.id = j.garage_id
       where j.delta > 0 group by g.id, g.nom order by sum(j.delta) desc limit 5) t);
  end loop;
  v_rapport := v_rapport || format('    podium garages ................. %s ms',
    round(extract(epoch from (clock_timestamp() - v_t0)) * 1000 / 5, 2)) || E'\n';

  v_t0 := clock_timestamp();
  for v_i in 1..5 loop
    perform (select jsonb_agg(x) from (
      select jsonb_build_object('nom', s.nom, 'points', sum(j.delta)) as x
        from public.journal j join public.stands s on s.id = j.stand_id
       where j.delta > 0 group by s.id, s.nom order by sum(j.delta) desc limit 5) t);
    perform (select jsonb_agg(x) from (
      select jsonb_build_object('nom', a.nom, 'parties', count(*)) as x
        from public.journal j join public.animations a on a.id = j.animation_id
       group by a.id, a.nom order by count(*) desc limit 5) t);
  end loop;
  v_rapport := v_rapport || format('    podiums stands + animations .... %s ms',
    round(extract(epoch from (clock_timestamp() - v_t0)) * 1000 / 5, 2)) || E'\n';

  v_t0 := clock_timestamp();
  for v_i in 1..5 loop
    perform (select jsonb_agg(jsonb_build_object('garage', g.nom, 'delta', j.delta))
               from (select * from public.journal order by id desc limit 40) j
               join public.garages g on g.id = j.garage_id);
  end loop;
  v_rapport := v_rapport || format('    journal en direct (40 lignes) .. %s ms',
    round(extract(epoch from (clock_timestamp() - v_t0)) * 1000 / 5, 2)) || E'\n';

  v_t0 := clock_timestamp();
  for v_i in 1..5 loop
    perform (select count(*) from public.journal where delta > 0);
    perform (select coalesce(sum(delta), 0) from public.journal where delta > 0);
    perform (select count(*) from public.journal where source = 'animation' and delta < 0);
    perform (select count(*) from public.journal where source = 'fournisseur');
    perform (select count(*) from public.journal where cree_le > now() - interval '1 minute');
    perform (select count(*) from public.journal where cree_le > now() - interval '10 minutes');
  end loop;
  v_rapport := v_rapport || format('    les 6 compteurs de journal ..... %s ms',
    round(extract(epoch from (clock_timestamp() - v_t0)) * 1000 / 5, 2)) || E'\n';

  -- L'ANNULATION. Elle n'est pas une précaution, c'est le mécanisme :
  -- une exception plpgsql annule la transaction entière.
  raise exception E'%', v_rapport;
end;
$$;
'@

$sql = $sql.Replace('@@VOLUMES@@', $listeVolumes).
            Replace('@@APPELS@@',  [string]$Appels).
            Replace('@@GARAGES@@', [string]$Garages)

$r = Sql $sql

# ---------------------------------------------------------------------
#  Un HTTP 200 ici serait une ANOMALIE : cela voudrait dire que la
#  transaction ne s'est pas annulée, donc que des lignes de mesure
#  peuvent avoir survécu. On le dit très fort.
# ---------------------------------------------------------------------
if ($r.ok) {
  Write-Output ''
  Write-Output '  !!! ANOMALIE : la requete a REUSSI.'
  Write-Output '  Elle aurait du echouer sur le RAISE EXCEPTION final, qui est ce'
  Write-Output '  qui annule la transaction. VERIFIEZ IMMEDIATEMENT que le journal'
  Write-Output '  est bien revenu a zero :'
  Write-Output '    .\scripts\push-sql.ps1 -Query "select count(*) from journal"'
  Write-Output ''
  exit 1
}

# Le rapport est dans le message d'erreur, avec ses sauts de ligne
# encodés en JSON. On rend le tout lisible.
#  Le `\s*` final d'une version precedente mangeait aussi les deux
#  espaces d'indentation de la premiere ligne du tableau : on ne retire
#  que le prefixe, et la ligne `CONTEXT:` que Postgres ajoute apres.
$message = ($r.corps | ConvertFrom-Json).message
$message = $message -replace '^Failed to run sql query: ERROR:\s+P0001:[ ]?', ''
$message = $message -replace '(?s)\r?\nCONTEXT:.*$', ''
Write-Output ''
Write-Output $message
Write-Output ''
Write-Output '  Note : ces temps varient d''une execution a l''autre (instance'
Write-Output '  partagee, caches froids ou chauds). Deux passages au meme volume'
Write-Output '  ont donne 13 et 21 ms le 16/09. C''est l''ORDRE DE GRANDEUR qui'
Write-Output '  compte, pas la decimale — et il reste a deux ordres de grandeur'
Write-Output '  du moment ou le pool commencerait a souffrir.'
Write-Output ''

# --- la preuve, et pas la parole -------------------------------------
$fin = (Sql @'
select (select count(*) from journal)                              as journal,
       (select count(*) from appareils where libelle = 'MESURE')   as appareils_mesure,
       (select coalesce(sum(solde), 0) from garages)               as soldes,
       (select count(*) from verifier_soldes())                    as ecarts
'@).corps | ConvertFrom-Json

Write-Output ('  Apres annulation : journal {0}, appareils de mesure {1}, soldes {2}, ecarts {3}' -f `
  $fin.journal, $fin.appareils_mesure, $fin.soldes, $fin.ecarts)
if ([int]$fin.journal -eq 0 -and [int]$fin.appareils_mesure -eq 0) {
  Write-Output '  => Rien n''a survecu. C''est le resultat attendu.'
} else {
  Write-Output '  => ATTENTION : des traces ont survecu, ce qui ne devrait pas arriver.'
}
Write-Output ''
