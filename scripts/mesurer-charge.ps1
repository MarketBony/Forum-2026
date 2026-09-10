#requires -Version 5
# =====================================================================
#  mesurer-charge.ps1
#  Confronte l'application aux modes de panne du document GRID :
#    1. cout unitaire de chaque appel reellement sonde ;
#    2. taille REELLE du pool PostgREST, mesuree sous rafale ;
#    3. comportement sous la charge d'une soiree complete ;
#    4. signature de saturation (§7.3) : ClientRead + API en timeout.
#
#    .\scripts\mesurer-charge.ps1
#    .\scripts\mesurer-charge.ps1 -Postes 200 -Secondes 20
# =====================================================================
param(
  [int]$Postes = 150,      # garages connectes simultanement
  [int]$Secondes = 15,     # duree de la rafale
  [int]$Rafale = 80        # requetes simultanees pour sonder le pool
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

# Sans cela, .NET plafonne a 2 connexions simultanees par hote et l'on
# mesure le client au lieu du serveur.
[System.Net.ServicePointManager]::DefaultConnectionLimit = 400
[System.Net.ServicePointManager]::Expect100Continue = $false

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$base = $conf['SUPABASE_URL'].TrimEnd('/')
$pub  = $conf['SUPABASE_PUBLISHABLE_KEY']
$ref  = $conf['SUPABASE_PROJECT_REF']
$pat  = $conf['SUPABASE_ACCESS_TOKEN']

$rest = New-Object System.Net.Http.HttpClient
$rest.Timeout = [TimeSpan]::FromSeconds(20)
$rest.DefaultRequestHeaders.Add('apikey', $pub)
$rest.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")

# Client SEPARE pour l'API de management : c'est le point clef du §7.3.
# Il ne passe pas par PostgREST, donc il repond meme quand le pool est
# sature — c'est ce qui permet de voir la saturation de l'exterieur.
$mgmt = New-Object System.Net.Http.HttpClient
$mgmt.Timeout = [TimeSpan]::FromSeconds(20)

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $mgmt.SendAsync($m).Result
  $o = $null; try { $o = $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json } catch {}
  return $o
}
# PIEGE POWERSHELL : ne JAMAIS nommer un parametre $args. C'est une
# variable automatique qui contient les arguments non lies ; le
# parametre est ignore, le corps part vide, et PostgREST repond
# « function without parameters not found » — une erreur qui ne
# ressemble pas du tout a sa cause.
function Corps($params) {
  New-Object System.Net.Http.StringContent(
    ($params | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8, 'application/json')
}
function Appel($nom, $params) { $rest.PostAsync("$base/rest/v1/rpc/$nom", (Corps $params)) }

function Titre($t) {
  Write-Output ''
  Write-Output ('-- ' + $t + ' ' + ('-' * [Math]::Max(0, 66 - $t.Length)))
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Dimensionnement - confrontation aux modes de panne connus'
Write-Output '===================================================================='

# =====================================================================
#  0. Le terrain
# =====================================================================
Titre '0. Le terrain'
$s = (Sql "select setting from pg_settings where name='max_connections'")[0].setting
$b = (Sql "select (setting::bigint*8192/1024/1024)::int as mo from pg_settings where name='shared_buffers'")[0].mo
Write-Output ("  max_connections = {0} · shared_buffers = {1} Mo" -f $s, $b)
$g = (Sql "select count(*)::int as n from garages where actif")[0].n
Write-Output ("  {0} garages en base" -f $g)

# Un appareil de garage et un appareil admin, pour sonder les deux appels.
$jetonG = 'mesure' + ([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))
$jetonA = 'mesurA' + ([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))
$codeG = (Sql "select code from garages g where actif and inscrit_le is not null order by solde desc limit 1")[0].code
$r = (Appel 'api_ouvrir' @{ p_jeton = $jetonG; p_code = $codeG }).Result
if (-not $r.IsSuccessStatusCode) { throw "Impossible d'ouvrir un appareil garage : $($r.Content.ReadAsStringAsync().Result)" }
$pinAdmin = (Sql "select valeur from config where cle='pin_admin'")[0].valeur
$r = (Appel 'api_ouvrir' @{ p_jeton = $jetonA; p_code = $pinAdmin }).Result
if (-not $r.IsSuccessStatusCode) { throw "Impossible d'ouvrir un appareil admin" }
Write-Output ("  Appareils de mesure : garage {0}, admin" -f $codeG)

# =====================================================================
#  1. Cout unitaire de ce qui est REELLEMENT sonde
# =====================================================================
Titre '1. Cout unitaire des appels sondes'
function Mesurer($nom, $params, $n) {
  $t = @()
  for ($i = 0; $i -lt $n; $i++) {
    $c = [Diagnostics.Stopwatch]::StartNew()
    $rep = (Appel $nom $params).Result
    $c.Stop()
    if ($rep.IsSuccessStatusCode) { $t += $c.Elapsed.TotalMilliseconds }
  }
  if ($t.Count -eq 0) { return $null }
  $t = $t | Sort-Object
  return @{ med = [math]::Round($t[[int]($t.Count/2)],0); min = [math]::Round($t[0],0)
            max = [math]::Round($t[-1],0); n = $t.Count }
}
$appels = @(
  @{ n='api_etat';             a=@{ p_jeton=$jetonG }; qui='garage, toutes les 30 s' },
  @{ n='api_supervision';      a=@{ p_jeton=$jetonA }; qui='Bony, toutes les 10 s' },
  @{ n='api_accueil_etat';     a=@{ p_jeton=$jetonA }; qui='accueil, a la connexion' },
  @{ n='api_accueil_chercher'; a=@{ p_jeton=$jetonA; p_q='saint bonnet' }; qui='accueil, par frappe' },
  @{ n='api_chercher';         a=@{ p_jeton=$jetonA; p_q='garage' }; qui='animateur (cache local)' }
)
foreach ($x in $appels) {
  $m = Mesurer $x.n $x.a 7
  if ($m) { Write-Output ("  {0,-22} median {1,5} ms   min {2,4}   max {3,5}   ({4})" -f $x.n, $m.med, $m.min, $m.max, $x.qui) }
  else    { Write-Output ("  {0,-22} ECHEC" -f $x.n) }
}

# =====================================================================
#  2. La taille REELLE du pool PostgREST
#     Elle ne figure sur aucun graphique : on la fait apparaitre en
#     saturant, puis en comptant les connexions `authenticator`.
# =====================================================================
Titre "2. Taille reelle du pool PostgREST (rafale de $Rafale)"
$taches = @()
for ($i = 0; $i -lt $Rafale; $i++) { $taches += (Appel 'api_etat' @{ p_jeton = $jetonG }) }
Start-Sleep -Milliseconds 250
$pool = Sql @"
select count(*) filter (where usename='authenticator')::int as authenticator,
       count(*) filter (where usename='authenticator' and state='active')::int as actives,
       count(*)::int as toutes,
       coalesce(string_agg(distinct wait_event, ', ') filter (where usename='authenticator'), '-') as attentes
from pg_stat_activity where datname = current_database()
"@
[System.Threading.Tasks.Task]::WaitAll($taches)
$ok = @($taches | Where-Object { $_.Result.IsSuccessStatusCode }).Count
Write-Output ("  Connexions authenticator observees : {0} (dont {1} actives)" -f $pool[0].authenticator, $pool[0].actives)
Write-Output ("  Attentes : {0}" -f $pool[0].attentes)
Write-Output ("  Toutes connexions confondues : {0} / {1}" -f $pool[0].toutes, $s)
Write-Output ("  Rafale : {0}/{1} reponses correctes" -f $ok, $Rafale)

# =====================================================================
#  3. La soiree entiere, en accelere
#     On reproduit le rythme reel : chaque garage sonde son solde, Bony
#     sonde sa supervision, et l'accueil cherche.
# =====================================================================
Titre "3. Rythme d'une soiree ($Postes postes, $Secondes s)"
# Un poste = un appel api_etat toutes les 30 s. Sur la fenetre de mesure,
# cela fait Postes * Secondes / 30 appels de garage, plus la supervision
# toutes les 10 s, plus une recherche d'accueil toutes les 3 s.
$nGarage  = [int]($Postes * $Secondes / 30)
$nAdmin   = [int]($Secondes / 10) + 1
$nAccueil = [int]($Secondes / 3)
Write-Output ("  Prevu : {0} api_etat + {1} api_supervision + {2} recherches" -f $nGarage, $nAdmin, $nAccueil)

$chrono = [Diagnostics.Stopwatch]::StartNew()
$t = @()
for ($i = 0; $i -lt $nGarage;  $i++) { $t += (Appel 'api_etat' @{ p_jeton = $jetonG }) }
for ($i = 0; $i -lt $nAdmin;   $i++) { $t += (Appel 'api_supervision' @{ p_jeton = $jetonA }) }
for ($i = 0; $i -lt $nAccueil; $i++) { $t += (Appel 'api_accueil_chercher' @{ p_jeton=$jetonA; p_q='saint' }) }

# Pendant que la rafale tourne, on regarde la base de l'exterieur.
Start-Sleep -Milliseconds 400
$pendant = Sql @"
select count(*) filter (where usename='authenticator')::int as pool,
       count(*) filter (where wait_event = 'ClientRead')::int as clientread,
       count(*) filter (where state='active')::int as actives,
       count(*) filter (where wait_event_type='Lock')::int as verrous
from pg_stat_activity where datname = current_database()
"@
[System.Threading.Tasks.Task]::WaitAll($t)
$chrono.Stop()

$reussis = @($t | Where-Object { $_.Result.IsSuccessStatusCode }).Count
$rates   = $t.Count - $reussis
$sec     = [math]::Round($chrono.Elapsed.TotalSeconds, 1)
Write-Output ("  {0} requetes en {1} s = {2} req/s" -f $t.Count, $sec, [math]::Round($t.Count / $chrono.Elapsed.TotalSeconds, 0))
Write-Output ("  {0} reussies, {1} en echec" -f $reussis, $rates)
Write-Output ("  Pendant la rafale : pool={0}, actives={1}, ClientRead={2}, attentes de verrou={3}" -f `
  $pendant[0].pool, $pendant[0].actives, $pendant[0].clientread, $pendant[0].verrous)
if ($rates -gt 0) {
  $codes = $t | Where-Object { -not $_.Result.IsSuccessStatusCode } | ForEach-Object { [int]$_.Result.StatusCode }
  Write-Output ("  Codes d'echec : {0}" -f (($codes | Group-Object | ForEach-Object { "$($_.Name)x$($_.Count)" }) -join ' '))
}

# =====================================================================
#  4. La signature du §7.3, verifiee de l'exterieur
# =====================================================================
Titre '4. Signature de saturation'
$c = [Diagnostics.Stopwatch]::StartNew()
$h = $null; try { $h = $rest.GetAsync("$base/auth/v1/health").Result } catch {}
$c.Stop()
Write-Output ("  GET /auth/v1/health : {0} en {1} ms" -f `
  $(if ($h) { [int]$h.StatusCode } else { 'timeout' }), [math]::Round($c.Elapsed.TotalMilliseconds, 0))
$apres = Sql @"
select count(*) filter (where usename='authenticator')::int as pool,
       count(*) filter (where state='idle in transaction')::int as bloquees
from pg_stat_activity where datname = current_database()
"@
Write-Output ("  Apres la rafale : pool={0}, idle in transaction={1}" -f $apres[0].pool, $apres[0].bloquees)

# =====================================================================
#  5. Ce que la base a vraiment execute
# =====================================================================
Titre '5. Le cout vu de la base'
$stats = Sql @"
select calls, total_exec_time::numeric(12,0) as ms_total,
       mean_exec_time::numeric(9,2) as ms_moyen,
       left(replace(query, chr(10), ' '), 58) as requete
from extensions.pg_stat_statements
where dbid = (select oid from pg_database where datname = current_database())
order by total_exec_time desc limit 8
"@
if ($stats) {
  $fen = Sql "select (now() - stats_reset)::text as fenetre from extensions.pg_stat_statements_info"
  Write-Output ("  Fenetre de mesure : {0}" -f $(if ($fen) { $fen[0].fenetre } else { 'inconnue' }))
  foreach ($x in $stats) { Write-Output ("  {0,7} appels · {1,7} ms · moy {2,6} ms · {3}" -f $x.calls, $x.ms_total, $x.ms_moyen, $x.requete) }
} else {
  Write-Output '  pg_stat_statements indisponible.'
}

# --- menage : les appareils de mesure ne restent pas en base ----------
Sql "delete from appareils where jeton in ('$jetonG','$jetonA')" | Out-Null

Write-Output ''
Write-Output '===================================================================='
Write-Output ''
