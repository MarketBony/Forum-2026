#requires -Version 5
# =====================================================================
#  diagnostic.ps1 — À LANCER SI L'APPLICATION SEMBLE MALADE, LE 17
#
#  Il répond à UNE question, celle qui fait perdre le plus de temps :
#  est-ce la base, ou est-ce le composant devant elle ?
#
#  La réponse ne se lit pas sur le tableau de bord Supabase. Celui-ci
#  agrège des sondes qui passent par le même goulot : quand la couche
#  API sature, il affiche « Postgres unhealthy » alors que Postgres va
#  très bien. Il désigne le symptôme, jamais la cause.
#
#  Ce script interroge la base par l'API de management, qui NE PASSE PAS
#  par PostgREST. C'est ce qui lui permet de répondre même quand
#  l'application est à l'arrêt.
#
#    .\scripts\diagnostic.ps1
# =====================================================================
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Net.Http
[System.Net.ServicePointManager]::DefaultConnectionLimit = 50

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$base = $conf['SUPABASE_URL'].TrimEnd('/')
$pub  = $conf['SUPABASE_PUBLISHABLE_KEY']
$ref  = $conf['SUPABASE_PROJECT_REF']
$pat  = $conf['SUPABASE_ACCESS_TOKEN']

$rest = New-Object System.Net.Http.HttpClient
$rest.Timeout = [TimeSpan]::FromSeconds(10)
$rest.DefaultRequestHeaders.Add('apikey', $pub)
$rest.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")
$mgmt = New-Object System.Net.Http.HttpClient
$mgmt.Timeout = [TimeSpan]::FromSeconds(20)

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  try {
    $r = $mgmt.SendAsync($m).Result
    return ($r.Content.ReadAsStringAsync().Result | ConvertFrom-Json)
  } catch { return $null }
}
function Section($t) {
  Write-Output ''
  Write-Output ('== ' + $t + ' ' + ('=' * [Math]::Max(0, 64 - $t.Length)))
}

Write-Output ''
Write-Output '===================================================================='
Write-Output ("  DIAGNOSTIC — {0}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))
Write-Output '===================================================================='

# =====================================================================
#  1. Les trois sondes qui tranchent
# =====================================================================
Section '1. Les trois sondes'

# a) la base, vue SANS passer par PostgREST
$c = [Diagnostics.Stopwatch]::StartNew()
$b = Sql "select 1 as ok"
$c.Stop()
$baseMs = [math]::Round($c.Elapsed.TotalMilliseconds, 0)
$baseOk = $null -ne $b
Write-Output ("  a) Base en direct (hors PostgREST) : {0} en {1} ms" -f `
  $(if ($baseOk) { 'REPOND' } else { 'MUETTE' }), $baseMs)

# b) l'application, par le même chemin que les téléphones.
#    On appelle une vraie fonction en lecture seule, pas la racine
#    /rest/v1/ : celle-ci repond 401 avec la cle publique (sa
#    description d'API est réservée à la clé de service) et ferait
#    croire à une panne alors que tout va bien.
$c = [Diagnostics.Stopwatch]::StartNew()
$restCode = 'TIMEOUT'
try {
  $corps = New-Object System.Net.Http.StringContent('{}', [Text.Encoding]::UTF8, 'application/json')
  $r = $rest.PostAsync("$base/rest/v1/rpc/api_sante", $corps).Result
  $restCode = [int]$r.StatusCode
} catch {}
$c.Stop()
$restMs = [math]::Round($c.Elapsed.TotalMilliseconds, 0)
Write-Output ("  b) PostgREST (chemin des telephones) : {0} en {1} ms" -f $restCode, $restMs)

# c) l'authentification, qui partage la même instance
$c = [Diagnostics.Stopwatch]::StartNew()
$authCode = 'TIMEOUT'
try { $authCode = [int]($rest.GetAsync("$base/auth/v1/health").Result).StatusCode } catch {}
$c.Stop()
$authMs = [math]::Round($c.Elapsed.TotalMilliseconds, 0)
Write-Output ("  c) GoTrue /auth/v1/health           : {0} en {1} ms" -f $authCode, $authMs)

# =====================================================================
#  2. Le verdict — la signature qui évite de chercher au mauvais endroit
# =====================================================================
Section '2. Verdict'
if (-not $baseOk) {
  Write-Output '  >> LA BASE NE REPOND PAS, meme hors PostgREST.'
  Write-Output '     C''est le seul cas ou le probleme est vraiment la base.'
  Write-Output '     Verifier que le projet n''est pas en veille (tableau de bord Supabase).'
} elseif ($baseMs -lt 1000 -and ($restCode -eq 'TIMEOUT' -or $restMs -gt 3000)) {
  Write-Output '  >> CE N''EST PAS LA BASE. C''est la couche devant elle.'
  Write-Output ("     La base repond en {0} ms, PostgREST non." -f $baseMs)
  Write-Output '     Signature d''une saturation du pool PostgREST : voir §3.'
  Write-Output '     Ne PAS agrandir le compute en premier — cela masquerait la cause.'
} elseif ($restMs -gt 1500) {
  Write-Output ("  >> LENT MAIS VIVANT. PostgREST repond en {0} ms." -f $restMs)
  Write-Output '     Regarder §3 (pool) puis §5 (requetes couteuses).'
} else {
  Write-Output '  >> TOUT REPOND NORMALEMENT.'
  Write-Output '     Si les utilisateurs se plaignent, le probleme est ailleurs :'
  Write-Output '     wifi de la halle, ou un seul appareil. Tester avec un 4G.'
}

# =====================================================================
#  3. Le pool — le plafond dur, invisible sur tout tableau de bord
# =====================================================================
Section '3. Le pool PostgREST et les connexions'
$p = Sql @"
select coalesce(usename,'?') as utilisateur,
       coalesce(nullif(application_name,''),'-') as appli,
       state, count(*)::int as n,
       coalesce(max(extract(epoch from (now() - state_change)))::int, 0) as plus_vieux_s
from pg_stat_activity where datname = current_database()
group by 1,2,3 order by n desc
"@
if ($p) {
  Write-Output ('  {0,-16} {1,-18} {2,-20} {3,4} {4,10}' -f 'UTILISATEUR','APPLI','ETAT','N','PLUS VIEUX')
  foreach ($x in $p) {
    Write-Output ('  {0,-16} {1,-18} {2,-20} {3,4} {4,8} s' -f `
      $x.utilisateur, $x.appli.Substring(0, [Math]::Min(18, $x.appli.Length)), $x.state, $x.n, $x.plus_vieux_s)
  }
}
$m = Sql @"
select (select setting::int from pg_settings where name='max_connections') as maxi,
       count(*) filter (where usename='authenticator')::int as pool,
       count(*)::int as total,
       count(*) filter (where state='idle in transaction')::int as bloquees,
       count(*) filter (where wait_event_type='Lock')::int as verrous
from pg_stat_activity where datname = current_database()
"@
if ($m) {
  Write-Output ''
  Write-Output ("  Pool PostgREST : {0} connexions ouvertes a cet instant." -f $m[0].pool)
  Write-Output '  Le PLAFOND mesure est de 11 (10 de travail + 1 d''ecoute). Il ne monte'
  Write-Output '  jamais au-dela, quelle que soit la charge : c''est le vrai goulot.'
  Write-Output ("  Total : {0} / {1}   ·   bloquees en transaction : {2}   ·   attentes de verrou : {3}" -f `
    $m[0].total, $m[0].maxi, $m[0].bloquees, $m[0].verrous)
  if ($m[0].bloquees -ge 5) { Write-Output '  !! Beaucoup de connexions bloquees en transaction : voir §4.' }
  if ($m[0].verrous -gt 0)  { Write-Output '  !! Des requetes attendent un verrou : voir §4.' }
}

# =====================================================================
#  4. Sur quoi attend-on ? — la requête qui a tranché chez GRID
# =====================================================================
Section '4. Sur quoi attend-on ?'
$w = Sql @"
select pid, coalesce(usename,'?') as usr, state,
       coalesce(wait_event_type,'-') as type_attente,
       coalesce(wait_event,'-') as attente,
       coalesce(extract(epoch from (now() - xact_start))::int, 0) as transaction_s,
       left(replace(coalesce(query,''), chr(10), ' '), 52) as requete
from pg_stat_activity
where datname = current_database() and pid <> pg_backend_pid() and state is not null
order by coalesce(xact_start, query_start) nulls last limit 12
"@
if ($w) {
  foreach ($x in $w) {
    Write-Output ('  {0,8} {1,-14} {2,-20} {3}/{4}  {5}s  {6}' -f `
      $x.pid, $x.usr, $x.state, $x.type_attente, $x.attente, $x.transaction_s, $x.requete)
  }
  $cr = @($w | Where-Object { $_.attente -eq 'ClientRead' }).Count
  Write-Output ''
  Write-Output ("  {0} connexion(s) en ClientRead sur {1} affichees." -f $cr, $w.Count)
  Write-Output '  ClientRead = la base a fini et attend le client. Si TOUT est la'
  Write-Output '  et que la sonde (a) du §1 est rapide, le probleme est DEVANT la base.'
}

# =====================================================================
#  5. Les requêtes coûteuses — avec le piège de la fenêtre
# =====================================================================
Section '5. Les requetes qui coutent'
$f = Sql "select (now() - stats_reset)::text as fenetre from extensions.pg_stat_statements_info"
if ($f) {
  Write-Output ("  ATTENTION : ces compteurs portent sur {0}, pas sur l'heure ecoulee." -f $f[0].fenetre)
  Write-Output '  Et les requetes qui n''ont JAMAIS obtenu de connexion n''y figurent pas :'
  Write-Output '  une saturation de pool y est structurellement invisible.'
}
$s = Sql @"
select calls, total_exec_time::numeric(12,0) as ms_total,
       mean_exec_time::numeric(9,2) as ms_moyen,
       left(replace(query, chr(10), ' '), 56) as requete
from extensions.pg_stat_statements
where dbid = (select oid from pg_database where datname = current_database())
order by total_exec_time desc limit 6
"@
if ($s) { foreach ($x in $s) { Write-Output ('  {0,7} appels · moy {1,7} ms · {2}' -f $x.calls, $x.ms_moyen, $x.requete) } }

# =====================================================================
#  6. L'état du jeu — est-ce que la soirée avance ?
# =====================================================================
Section '6. La soiree avance-t-elle ?'
$e = Sql @"
select (select count(*) from garages where inscrit_le is not null)::int as arrives,
       (select count(*) from journal)::int as ecritures,
       (select count(*) from journal where cree_le > now() - interval '10 minutes')::int as dix_min,
       (select coalesce(to_char(max(cree_le) at time zone 'Europe/Paris','HH24:MI:SS'),'-') from journal) as derniere,
       (select count(*) from grille where achete_le is not null)::int as cases_jouees,
       (select count(*) from verifier_soldes())::int as ecarts
"@
if ($e) {
  Write-Output ("  Garages arrives      : {0}" -f $e[0].arrives)
  Write-Output ("  Ecritures au journal : {0}   (dont {1} sur les 10 dernieres minutes)" -f $e[0].ecritures, $e[0].dix_min)
  Write-Output ("  Derniere ecriture    : {0}" -f $e[0].derniere)
  Write-Output ("  Cases jouees         : {0} / 100" -f $e[0].cases_jouees)
  Write-Output ("  Ecarts de solde      : {0}" -f $e[0].ecarts)
  if ($e[0].ecarts -gt 0) { Write-Output '  !! ECART ENTRE SOLDE ET JOURNAL — a signaler immediatement.' }
  if ($e[0].dix_min -eq 0 -and $e[0].arrives -gt 0) {
    Write-Output '  !! Aucune ecriture depuis 10 minutes alors que des garages sont la.'
    Write-Output '     Soit la soiree est en pause, soit les ecritures ne passent plus.'
  } else {
    Write-Output '  La soiree avance : des ecritures arrivent.'
  }
}

# =====================================================================
#  7. Que faire, dans l'ordre
# =====================================================================
Section '7. Que faire, dans cet ordre'
Write-Output '  1. Si §2 dit « ce n''est pas la base » : attendre 60 s et relancer ce'
Write-Output '     script. Le pool se vide seul quand la vague est passee.'
Write-Output '  2. Faire passer le sondage de 30 s a 90 s pour tout le monde :'
Write-Output '     modifier sondageMs dans app/config.js, puis redeployer. Cela divise'
Write-Output '     par trois la charge de fond en une minute.'
Write-Output '  3. Si des ecritures sont bloquees : .\scripts\exporter-journal.ps1'
Write-Output '     met le journal a l''abri AVANT toute manipulation.'
Write-Output '  4. Le compute vient EN DERNIER. L''agrandir masque une cause au lieu'
Write-Output '     de la corriger — et la panne revient, plus tard et plus fort.'
Write-Output ''
Write-Output '===================================================================='
Write-Output ''
