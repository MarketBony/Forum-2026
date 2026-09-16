#requires -Version 5
# =====================================================================
#  charge-vitrine.ps1 — ce que coûtent 140 vitrines ouvertes en même
#  temps, mesuré par l'API RÉELLE.
#
#  POURQUOI CE BANC EXISTE. La simulation du Forum joue des garages, des
#  animateurs et des fournisseurs ; elle ne connaît pas le profil
#  vitrine, ajouté le 16 septembre. Or c'est 140 téléphones qui
#  appellent api_vitrine toutes les 30 secondes pendant six heures, en
#  PLUS de la charge des garages — et api_vitrine fait un verifier_soldes()
#  à chaque appel, qui balaie le journal.
#
#  CE QU'IL MESURE : le temps de réponse de api_vitrine quand N appels
#  partent en même temps, et le taux d'échec.
#
#  CE QU'IL NE PROUVE PAS : les 140 sessions partent d'UNE machine et
#  d'UNE connexion. Il mesure Supabase, pas le wifi de la Grande Halle.
#
#  Il n'écrit rien d'autre que des lignes dans `appareils` — une par
#  jeton, réutilisée d'une exécution à l'autre parce que les jetons sont
#  déterministes. Les codes lus sont ceux de la base, aucun n'est créé.
#
#    .\scripts\charge-vitrine.ps1
#    .\scripts\charge-vitrine.ps1 -Vitrines 140 -Tours 3
# =====================================================================
param(
  [int]$Vitrines = 140,   # 119 equipe Bony + 21 constructeurs
  [int]$Tours    = 3      # trois rafales : la 1re paie le reveil du pool
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
# Sans ce relevement, .NET plafonne a 2 connexions par hote et le banc
# mesurerait le client au lieu du serveur. Piege deja paye.
[System.Net.ServicePointManager]::DefaultConnectionLimit = 2000
[System.Net.ServicePointManager]::Expect100Continue = $false

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$base = $conf['SUPABASE_URL'].TrimEnd('/')
$pub  = $conf['SUPABASE_PUBLISHABLE_KEY']
$ref  = $conf['SUPABASE_PROJECT_REF']
$pat  = $conf['SUPABASE_ACCESS_TOKEN']

$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(60)
$cli.DefaultRequestHeaders.Add('apikey', $pub)
$cli.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $t = $r.Content.ReadAsStringAsync().Result
  if (-not $r.IsSuccessStatusCode) { throw "SQL : HTTP $([int]$r.StatusCode) — $t" }
  # ConvertFrom-Json rend un tableau comme UN SEUL objet : on assigne
  # sans @(), on compte avec @().
  $d = $t | ConvertFrom-Json
  return $d
}

function Jeton($graine) {
  # Jetons DETERMINISTES : une ligne d'appareils se reutilise d'une
  # execution a l'autre au lieu d'en creer une nouvelle a chaque fois.
  $h = [System.Security.Cryptography.MD5]::Create().ComputeHash(
        [Text.Encoding]::UTF8.GetBytes("charge-vitrine-2026|$graine"))
  return (($h | ForEach-Object { $_.ToString('x2') }) -join '') * 2
}

function Rpc($nom, $corps) {
  $c = New-Object System.Net.Http.StringContent(
        ($corps | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  return $cli.PostAsync("$base/rest/v1/rpc/$nom", $c)
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Charge de la vitrine — api_vitrine par l''API reelle'
Write-Output '===================================================================='
Write-Output ''

# --- les codes, lus en base ------------------------------------------
$codes = Sql @"
select code_force from public.participants
 where actif and categorie in ('EQUIPE_BONY','CONSTRUCTEUR') and code_force is not null
 order by cle_source limit $Vitrines
"@
$liste = @($codes | ForEach-Object { $_.code_force })
Write-Output ("  Codes de vitrine lus ... {0}" -f $liste.Count)
if ($liste.Count -eq 0) { throw 'Aucun code de vitrine en base : lancez sql\30_vitrine.sql.' }

# --- ouverture des sessions ------------------------------------------
Write-Output '  Ouverture des sessions ...'
$jetons = New-Object System.Collections.ArrayList
$taches = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $liste.Count; $i++) {
  $j = Jeton $i
  [void]$jetons.Add($j)
  [void]$taches.Add((Rpc 'api_ouvrir' @{ p_jeton = $j; p_code = $liste[$i] }))
}
$ouvertes = 0
foreach ($t in $taches) { $r = $t.Result; if ($r.IsSuccessStatusCode) { $ouvertes++ } }
Write-Output ("  Sessions ouvertes ...... {0} / {1}" -f $ouvertes, $liste.Count)
Write-Output ''

# --- les rafales -----------------------------------------------------
#  Chaque tour lance TOUTES les vitrines en meme temps. C'est bien pire
#  que la realite — les 140 telephones se rafraichissent chacun a son
#  rythme, jamais a la meme milliseconde — et c'est voulu : on cherche
#  le plafond, pas la moyenne.
$tousMs = New-Object System.Collections.ArrayList
$echecs = 0
for ($tour = 1; $tour -le $Tours; $tour++) {
  $chrono = [Diagnostics.Stopwatch]::StartNew()
  $lot = New-Object System.Collections.ArrayList
  foreach ($j in $jetons) {
    $t0 = [Diagnostics.Stopwatch]::StartNew()
    [void]$lot.Add(@{ t = (Rpc 'api_vitrine' @{ p_jeton = $j }); c = $t0 })
  }
  $ms = New-Object System.Collections.ArrayList
  foreach ($x in $lot) {
    $r = $x.t.Result
    $x.c.Stop()
    [void]$ms.Add($x.c.Elapsed.TotalMilliseconds)
    if (-not $r.IsSuccessStatusCode) { $echecs++ }
  }
  $chrono.Stop()
  $tri = @($ms | Sort-Object)
  $p50 = $tri[[int][math]::Floor($tri.Count * 0.50)]
  $p95 = $tri[[int][math]::Min($tri.Count - 1, [math]::Floor($tri.Count * 0.95))]
  Write-Output ("  Tour {0} : {1} appels en {2:N2} s · median {3:N0} ms · p95 {4:N0} ms · max {5:N0} ms · {6:N0} req/s" -f `
    $tour, $ms.Count, $chrono.Elapsed.TotalSeconds, $p50, $p95, $tri[-1],
    ($ms.Count / [math]::Max($chrono.Elapsed.TotalSeconds, 0.001)))
  foreach ($v in $ms) { [void]$tousMs.Add($v) }
}

# --- le verdict -------------------------------------------------------
$tri = @($tousMs | Sort-Object)
$p50 = $tri[[int][math]::Floor($tri.Count * 0.50)]
$p95 = $tri[[int][math]::Min($tri.Count - 1, [math]::Floor($tri.Count * 0.95))]
Write-Output ''
Write-Output ("  Appels total ........... {0}" -f $tri.Count)
Write-Output ("  Echecs ................. {0}" -f $echecs)
Write-Output ("  Median / p95 / max ..... {0:N0} / {1:N0} / {2:N0} ms" -f $p50, $p95, $tri[-1])
Write-Output ''
#  LE CHIFFRE QUI COMPTE N'EST PAS LA RAFALE. Le jour J, 140 vitrines se
#  rafraichissent toutes les 30 s, soit 4,7 requetes par seconde reparties
#  dans le temps — pas 140 d'un coup. La rafale dit seulement que meme le
#  pire cas passe.
Write-Output ("  Le jour J : {0} vitrines / 30 s = {1:N1} req/s reparties." -f $liste.Count, ($liste.Count / 30))
if ($echecs -eq 0) { Write-Output '  Aucun echec : la vitrine tient la rafale.' }
else { Write-Output "  $echecs ECHEC(S) — a regarder avant le Forum." }
Write-Output ''
