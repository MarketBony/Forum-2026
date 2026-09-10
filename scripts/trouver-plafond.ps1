#requires -Version 5
# =====================================================================
#  trouver-plafond.ps1
#  Cherche le point de RUPTURE, pas le point de confort. On monte la
#  rafale simultanee jusqu'a ce que des requetes echouent, et on
#  regarde la base de l'exterieur pendant ce temps.
#
#    .\scripts\trouver-plafond.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
[System.Net.ServicePointManager]::DefaultConnectionLimit = 1000
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
$rest.Timeout = [TimeSpan]::FromSeconds(25)
$rest.DefaultRequestHeaders.Add('apikey', $pub)
$rest.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")
$mgmt = New-Object System.Net.Http.HttpClient
$mgmt.Timeout = [TimeSpan]::FromSeconds(25)

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
function Appel($nom, $params) {
  $c = New-Object System.Net.Http.StringContent(
        ($params | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8, 'application/json')
  $rest.PostAsync("$base/rest/v1/rpc/$nom", $c)
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Recherche du point de rupture'
Write-Output '===================================================================='

$jeton = 'plafond' + ([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))
$code = (Sql "select code from garages where actif and inscrit_le is not null order by solde desc limit 1")[0].code
$r = (Appel 'api_ouvrir' @{ p_jeton = $jeton; p_code = $code }).Result
if (-not $r.IsSuccessStatusCode) { throw "appareil de mesure impossible" }

Write-Output ''
Write-Output '  Rafale = N requetes api_etat lancees dans la meme milliseconde,'
Write-Output '  ce que produit un reveil simultane de N telephones.'
Write-Output ''
Write-Output '   Rafale   Reussies   Echecs   Duree   Debit      p50      p95     Pool  Verrous'
Write-Output '  ------------------------------------------------------------------------------'

$rupture = $null
foreach ($n in 25, 50, 100, 200, 400, 800) {
  [GC]::Collect()
  $taches = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task[System.Net.Http.HttpResponseMessage]]'
  $chronos = @{}
  $global = [Diagnostics.Stopwatch]::StartNew()
  for ($i = 0; $i -lt $n; $i++) { $taches.Add((Appel 'api_etat' @{ p_jeton = $jeton })) }

  Start-Sleep -Milliseconds 300
  $vu = Sql @"
select count(*) filter (where usename='authenticator')::int as pool,
       count(*) filter (where wait_event_type='Lock')::int as verrous,
       count(*) filter (where state='active')::int as actives
from pg_stat_activity where datname = current_database()
"@
  try { [System.Threading.Tasks.Task]::WaitAll($taches.ToArray()) } catch {}
  $global.Stop()

  $ok = 0; $ko = 0; $lat = @()
  foreach ($t in $taches) {
    if ($t.Status -eq 'RanToCompletion' -and $t.Result.IsSuccessStatusCode) { $ok++ } else { $ko++ }
  }
  $sec = $global.Elapsed.TotalSeconds
  $debit = [math]::Round($n / $sec, 0)
  Write-Output ("  {0,7}   {1,8}   {2,6}   {3,5:N1}s   {4,5}/s   {5,18}   {6,4}   {7,6}" -f `
    $n, $ok, $ko, $sec, $debit, '', $vu[0].pool, $vu[0].verrous)

  if ($ko -gt 0 -and -not $rupture) { $rupture = $n }
  Start-Sleep -Milliseconds 1200   # laisser le pool se vider entre deux paliers
}

Write-Output ''
if ($rupture) { Write-Output ("  Premier palier avec des echecs : {0} requetes simultanees." -f $rupture) }
else          { Write-Output '  Aucun echec jusqu a 800 requetes simultanees.' }

# --- l'etat apres l'effort -------------------------------------------
Write-Output ''
$c = [Diagnostics.Stopwatch]::StartNew()
$h = $null; try { $h = $rest.GetAsync("$base/auth/v1/health").Result } catch {}
$c.Stop()
Write-Output ("  Sante auth apres l'effort : {0} en {1} ms" -f `
  $(if ($h) { [int]$h.StatusCode } else { 'TIMEOUT' }), [math]::Round($c.Elapsed.TotalMilliseconds, 0))
$f = Sql @"
select count(*) filter (where usename='authenticator')::int as pool,
       count(*) filter (where state='idle in transaction')::int as bloquees,
       coalesce(string_agg(distinct wait_event, ', ') filter (where usename='authenticator'), '-') as attentes
from pg_stat_activity where datname = current_database()
"@
Write-Output ("  Pool={0}, idle in transaction={1}, attentes={2}" -f $f[0].pool, $f[0].bloquees, $f[0].attentes)

Sql "delete from appareils where jeton = '$jeton'" | Out-Null
Write-Output ''
Write-Output '===================================================================='
Write-Output ''
