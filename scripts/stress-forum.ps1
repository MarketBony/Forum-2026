#requires -Version 5
# =====================================================================
#  stress-forum.ps1
#  Simule une salle pleine : 150 sessions simultanees qui martelent
#  l'application pendant plusieurs minutes.
#
#    .\scripts\stress-forum.ps1 -Minutes 3
#
#  LE PROFIL, tel que Bony l'a decrit :
#    100 garages      solde en boucle, achat de cases
#     20 directions   supervision en boucle  <-- le poste le plus cher
#     30 personnels   15 fournisseurs + 15 animateurs, que des ecritures
#
#  POURQUOI DES VAGUES SIMULTANEES et non des minuteurs independants :
#  c'est le pire cas, et c'est le cas reel. 150 telephones cales sur le
#  meme rythme de sondage tapent a la meme milliseconde. C'est la RAFALE
#  qui tue un pool de connexions, pas le debit moyen — voir le rapport
#  d'incident GRID dans CONTEXTE.md.
#
#  POURQUOI DES JETONS DETERMINISTES :
#  appareils_max vaut 6 par garage et une place d'appareil NE SE REND
#  PAS (cle etrangere depuis le journal). Des jetons tires au hasard en
#  consommeraient une a chaque execution, et le banc tomberait en panne
#  au 7e essai. Ici, rejouer le test reutilise les memes appareils.
#
#  CE QUE CE TEST NE PROUVE PAS : les 150 sessions partent d'UNE SEULE
#  machine et d'UNE SEULE connexion Internet. Il mesure Supabase, pas le
#  wifi de la Grande Halle.
#
#  ⚠️ IL ECRIT DANS LA BASE DE PRODUCTION. Lancer 99_remise_a_zero.sql
#  apres. Le script restaure lui-meme le plafond de cases par garage.
# =====================================================================
[CmdletBinding()]
param(
  [double]$Minutes = 3,      # accepte les fractions : 0.5 = 30 secondes
  [int]$Garages    = 100,
  [int]$Directions = 20,
  [int]$Personnels = 30,
  [int]$PauseMs    = 700
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
# Sans ce relevement, .NET plafonne a 2 connexions par hote et le banc
# mesurerait le client au lieu du serveur.
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

$rest = New-Object System.Net.Http.HttpClient
$rest.Timeout = [TimeSpan]::FromSeconds(30)
$rest.DefaultRequestHeaders.Add('apikey', $pub)
$rest.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")
$mgmt = New-Object System.Net.Http.HttpClient
$mgmt.Timeout = [TimeSpan]::FromSeconds(60)

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $mgmt.SendAsync($m).Result
  $b = $r.Content.ReadAsStringAsync().Result
  if (-not $r.IsSuccessStatusCode) { throw "SQL $([int]$r.StatusCode) : $b" }
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  # PAS de « return ,@($o) » : la virgule ajoute un niveau de tableau et
  # « @(Sql ...) » rend alors UN element contenant toutes les lignes.
  # $g.code renvoyait les 100 codes d'un coup, et la porte repondait
  # CODE_INCONNU sur un tableau serialise en JSON.
  return @($o)
}
function Tache($nom, $params) {
  $c = New-Object System.Net.Http.StringContent(
        ($params | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8, 'application/json')
  $rest.PostAsync("$base/rest/v1/rpc/$nom", $c)
}
function Sync($nom, $params) {
  $r = (Tache $nom $params).Result
  $b = $r.Content.ReadAsStringAsync().Result
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; http = [int]$r.StatusCode; data = $o }
}
function Cle { [guid]::NewGuid().ToString('N') }
function Pct($tri, $p) {
  if (@($tri).Count -eq 0) { return 0 }
  $i = [int][Math]::Ceiling(@($tri).Count * $p) - 1
  if ($i -lt 0) { $i = 0 }
  return [Math]::Round($tri[$i], 0)
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  STRESS — une salle pleine pendant plusieurs minutes'
Write-Output '===================================================================='
Write-Output ("  Profil : {0} garages · {1} directions · {2} personnels = {3} sessions" -f `
              $Garages, $Directions, $Personnels, ($Garages + $Directions + $Personnels))
Write-Output ("  Duree  : {0} min · pause entre vagues : {1} ms" -f $Minutes, $PauseMs)

# =====================================================================
#  1. Preparation du terrain
# =====================================================================
Write-Output ''
Write-Output '-- 1. Preparation ---------------------------------------------------'

$avant = (Sql @"
select (select count(*) from journal)::int                            as journal,
       (select count(*) from grille where achete_le is not null)::int as cases,
       (select valeur from config where cle='cases_max_garage')       as plafond
"@)[0]
Write-Output ("  Depart : {0} lignes de journal, {1} cases achetees, plafond={2}" -f `
              $avant.journal, $avant.cases, $avant.plafond)

# Le plafond de 3 cases est leve pendant le test : on veut eprouver la
# COURSE sur les cases, pas le refus qui l'evite. Restaure a la fin.
Sql "update config set valeur='0' where cle='cases_max_garage'" | Out-Null

# Dotation large : un SOLDE_INSUFFISANT masquerait ce qu'on cherche.
Sql @"
with c as (select id from garages where code is not null order by compte limit $Garages)
insert into journal (garage_id, delta, libelle, source, cle_idem)
select id, 100000, 'Dotation stress', 'administration', 'stress-dot-'||id::text from c
on conflict (cle_idem) do nothing
"@ | Out-Null
Sql @"
update garages set solde = (select coalesce(sum(delta),0) from journal j where j.garage_id = garages.id)
 where id in (select garage_id from journal where libelle = 'Dotation stress')
"@ | Out-Null

$cibles = @(Sql @"
select g.id, g.code from garages g
 where exists (select 1 from journal j where j.garage_id=g.id and j.libelle='Dotation stress')
 order by g.compte
"@)
$idsCibles = @($cibles | ForEach-Object { $_.id })
Write-Output ("  {0} garages dotes de 100 000 points." -f $idsCibles.Count)

$pinAdmin  = (Sql "select valeur from config where cle='pin_admin'")[0].valeur
$pinsStand = @(Sql "select code_pin from stands where actif order by code_pin"     | ForEach-Object { $_.code_pin })
$pinsAnim  = @(Sql "select code_pin from animations where actif order by code_pin" | ForEach-Object { $_.code_pin })

# --- construction des sessions ---------------------------------------
# Le bourrage de zeros porte le jeton au-dela des 20 caracteres exiges
# par api_ouvrir, tout en restant reproductible d'une execution a l'autre.
$bourre = '0' * 40
$sessions = New-Object System.Collections.ArrayList
foreach ($g in $cibles) {
  $null = $sessions.Add(@{ type='garage'; jeton=("stress-garage-$($g.code)-$bourre"); code=$g.code; gid=$g.id })
}
for ($i = 1; $i -le $Directions; $i++) {
  $null = $sessions.Add(@{ type='direction'; jeton=("stress-direction-{0:D3}-$bourre" -f $i); code=$pinAdmin })
}
$nbF = [int][Math]::Floor($Personnels / 2); $nbA = $Personnels - $nbF
for ($i = 0; $i -lt $nbF; $i++) {
  $null = $sessions.Add(@{ type='fournisseur'; jeton=("stress-four-{0:D3}-$bourre" -f $i)
                           code=$pinsStand[$i % $pinsStand.Count] })
}
for ($i = 0; $i -lt $nbA; $i++) {
  $null = $sessions.Add(@{ type='animateur'; jeton=("stress-anim-{0:D3}-$bourre" -f $i)
                           code=$pinsAnim[$i % $pinsAnim.Count] })
}

Write-Output ("  Ouverture des {0} sessions..." -f $sessions.Count)
foreach ($s in $sessions) {
  $r = Sync 'api_ouvrir' @{ p_jeton = $s.jeton; p_code = $s.code }
  if (-not $r.ok) { throw ("Session {0} code {1} : HTTP {2}" -f $s.type, $s.code, $r.http) }
  if ($r.data.erreur) { throw ("Session {0} code {1} refusee : {2}" -f $s.type, $s.code, $r.data.erreur) }
  if ($s.type -eq 'animateur') {
    $s.animation = $r.data.animation_id
    $s.baremes   = @($r.data.bareme | ForEach-Object { $_.id })
  }
  if ($s.type -eq 'fournisseur') {
    $p = @($r.data.bareme)[0]
    $s.palierLib = $p.libelle; $s.palierPts = $p.points
  }
}
Write-Output '  Toutes les sessions sont ouvertes.'

# =====================================================================
#  2. Les vagues
# =====================================================================
# Tout ce qui suit est sous try/finally : une interruption (Ctrl+C, une
# erreur) ne doit pas laisser cases_max_garage a 0 dans la config de
# production. Une premiere version l'a fait, et le defaut est silencieux.
try {

Write-Output ''
Write-Output '-- 2. Charge --------------------------------------------------------'
Write-Output '  vague   envoyees   servies   refus   ECHECS   vague(ms)   p50   p95   max'

$stat = @{}       # endpoint -> liste de latences (ms)
$codes = @{}      # code d'erreur metier -> nombre
$echecs = @{}     # panne reelle -> nombre
$totEnv = 0; $totOk = 0; $totRef = 0; $totKo = 0
$vaguesMs = New-Object System.Collections.ArrayList
$chrono = [Diagnostics.Stopwatch]::StartNew()
$fin = (Get-Date).AddMinutes($Minutes)
$vague = 0
$echDb = $null

while ((Get-Date) -lt $fin) {
  $vague++
  $noms = New-Object System.Collections.ArrayList
  $arr  = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task]'

  foreach ($s in $sessions) {
    switch ($s.type) {
      'garage' {
        # Une vague sur six est un achat de case : le reste du temps un
        # garage regarde son solde, ce qui est le vrai rapport de force.
        if (($vague % 6) -eq 0) {
          $n = Get-Random -Minimum 1 -Maximum 201
          $null = $noms.Add('api_jouer_case')
          $arr.Add((Tache 'api_jouer_case' @{ p_jeton=$s.jeton; p_numero=$n; p_cle=(Cle) }))
        } else {
          $null = $noms.Add('api_etat')
          $arr.Add((Tache 'api_etat' @{ p_jeton = $s.jeton }))
        }
      }
      'direction' {
        $null = $noms.Add('api_supervision')
        $arr.Add((Tache 'api_supervision' @{ p_jeton = $s.jeton }))
      }
      'fournisseur' {
        if (($vague % 2) -eq 0) {
          $g = $idsCibles[(Get-Random -Maximum $idsCibles.Count)]
          $null = $noms.Add('api_points_achat')
          $arr.Add((Tache 'api_points_achat' @{ p_jeton=$s.jeton; p_garage=$g
                                                p_points=$s.palierPts; p_cle=(Cle); p_palier=$s.palierLib }))
        } else {
          $null = $noms.Add('api_chercher')
          $arr.Add((Tache 'api_chercher' @{ p_jeton=$s.jeton; p_q='gar' }))
        }
      }
      'animateur' {
        $g = $idsCibles[(Get-Random -Maximum $idsCibles.Count)]
        if (($vague % 2) -eq 0) {
          $null = $noms.Add('api_participation')
          $arr.Add((Tache 'api_participation' @{ p_jeton=$s.jeton; p_garage=$g
                                                 p_animation=$s.animation; p_cle=(Cle) }))
        } else {
          $b = $s.baremes[(Get-Random -Maximum $s.baremes.Count)]
          $null = $noms.Add('api_resultat')
          $arr.Add((Tache 'api_resultat' @{ p_jeton=$s.jeton; p_garage=$g; p_bareme=$b; p_cle=(Cle) }))
        }
      }
    }
  }

  # --- attente, en notant l'ordre et l'instant d'arrivee de chacun ----
  # WaitAny rend la main des qu'UNE requete est servie : on horodate a
  # cet instant, ce qui donne la distribution des latences sans avoir a
  # ouvrir 150 processus PowerShell (qui mesureraient le client).
  $t0 = [Diagnostics.Stopwatch]::StartNew()
  $reste = [System.Collections.ArrayList]@(0..($arr.Count - 1))
  $lat = New-Object 'Double[]' $arr.Count
  while ($reste.Count -gt 0) {
    $sous = [System.Threading.Tasks.Task[]]@($reste | ForEach-Object { $arr[$_] })
    $k = [System.Threading.Tasks.Task]::WaitAny($sous)
    $idx = $reste[$k]
    $lat[$idx] = $t0.Elapsed.TotalMilliseconds
    $reste.RemoveAt($k)
  }
  $dureeVague = $t0.Elapsed.TotalMilliseconds
  $null = $vaguesMs.Add($dureeVague)

  # --- depouillement --------------------------------------------------
  $vOk = 0; $vRef = 0; $vKo = 0
  for ($i = 0; $i -lt $arr.Count; $i++) {
    $nom = $noms[$i]; $t = $arr[$i]
    if (-not $stat.ContainsKey($nom)) { $stat[$nom] = New-Object System.Collections.ArrayList }
    $null = $stat[$nom].Add($lat[$i])
    $totEnv++

    if ($t.IsFaulted -or $t.IsCanceled) {
      $vKo++; $totKo++
      $e = 'reseau/timeout'
      if (-not $echecs.ContainsKey($e)) { $echecs[$e] = 0 }
      $echecs[$e]++
      continue
    }
    $rep = $t.Result
    $http = [int]$rep.StatusCode
    if ($rep.IsSuccessStatusCode) {
      # Un refus metier peut aussi arriver en HTTP 200 : la porte rend
      # {erreur:...} plutot qu'une exception, pour que le frein compte.
      $vOk++; $totOk++
    }
    elseif ($http -eq 400) {
      # Refus metier : case deja prise, plafond, solde insuffisant.
      # C'est un RESULTAT, pas une panne.
      $vRef++; $totRef++
      $b = $rep.Content.ReadAsStringAsync().Result
      $c = 'inconnu'; try { $c = ($b | ConvertFrom-Json).message } catch {}
      if (-not $codes.ContainsKey($c)) { $codes[$c] = 0 }
      $codes[$c]++
    }
    else {
      # 5xx, 429, 401, 503 : la panne qu'on cherche.
      $vKo++; $totKo++
      $e = "HTTP $http"
      if (-not $echecs.ContainsKey($e)) { $echecs[$e] = 0 }
      $echecs[$e]++
    }
    $rep.Dispose()
  }

  $tri = @($lat | Sort-Object)
  Write-Output ("  {0,5}   {1,8}   {2,7}   {3,5}   {4,6}   {5,9}   {6,3}   {7,3}   {8,3}" -f `
    $vague, $arr.Count, $vOk, $vRef, $vKo, [Math]::Round($dureeVague,0), (Pct $tri .50), (Pct $tri .95), (Pct $tri 1))

  # Un releve de l'interieur de la base, au milieu de l'effort.
  if ($vague -eq 5) {
    $echDb = (Sql @"
select (select count(*) from pg_stat_activity)::int                                              as connexions,
       (select count(*) from pg_stat_activity where state='active')::int                         as actives,
       (select count(*) from pg_stat_activity where wait_event_type='Lock')::int                 as attentes_verrou,
       (select count(*) from pg_stat_activity where state='idle in transaction')::int            as bloquees_en_transaction,
       (select setting from pg_settings where name='max_connections')                            as max_connexions
"@)[0]
  }

  if ($PauseMs -gt 0) { Start-Sleep -Milliseconds $PauseMs }
}
$total = $chrono.Elapsed.TotalSeconds

# =====================================================================
#  3. Resultat
# =====================================================================
Write-Output ''
Write-Output '-- 3. Bilan ---------------------------------------------------------'
Write-Output ("  {0} vagues en {1:N0} s · {2} requetes · {3:N1} req/s soutenues" -f `
              $vague, $total, $totEnv, ($totEnv / $total))
Write-Output ("  Servies : {0}  ·  Refus metier : {1}  ·  ECHECS REELS : {2}" -f $totOk, $totRef, $totKo)

Write-Output ''
Write-Output '  Latence par appel (ms, sur toute la duree du test) :'
Write-Output '    appel                 n      p50     p95     p99     max'
foreach ($k in ($stat.Keys | Sort-Object)) {
  $tri = @($stat[$k] | Sort-Object)
  Write-Output ("    {0,-18} {1,6}   {2,6}  {3,6}  {4,6}  {5,6}" -f `
    $k, $tri.Count, (Pct $tri .50), (Pct $tri .95), (Pct $tri .99), (Pct $tri 1))
}

$triV = @($vaguesMs | Sort-Object)
Write-Output ''
Write-Output ("  Vague complete (les {0} servies) : p50 {1} ms · p95 {2} ms · pire {3} ms" -f `
              $sessions.Count, (Pct $triV .50), (Pct $triV .95), (Pct $triV 1))

if ($codes.Count -gt 0) {
  Write-Output ''
  Write-Output '  Refus metier — attendus, ce sont des reponses et non des pannes :'
  foreach ($k in ($codes.Keys | Sort-Object { -$codes[$_] })) {
    Write-Output ("    {0,-28} {1}" -f $k, $codes[$k])
  }
}
if ($echecs.Count -gt 0) {
  Write-Output ''
  Write-Output '  ECHECS REELS :'
  foreach ($k in ($echecs.Keys | Sort-Object { -$echecs[$_] })) {
    Write-Output ("    {0,-28} {1}" -f $k, $echecs[$k])
  }
} else {
  Write-Output ''
  Write-Output '  Aucun echec reel : ni 5xx, ni 429, ni timeout.'
}

if ($echDb) {
  Write-Output ''
  Write-Output '  Vue de l''interieur de la base, en pleine charge :'
  Write-Output ("    connexions {0} / {1} · actives {2} · attentes de verrou {3} · bloquees en transaction {4}" -f `
    $echDb.connexions, $echDb.max_connexions, $echDb.actives, $echDb.attentes_verrou, $echDb.bloquees_en_transaction)
}

# =====================================================================
#  4. Les invariants ont-ils tenu ?
#     C'est la seule question qui compte vraiment : un debit honorable
#     avec des soldes faux serait un echec complet.
# =====================================================================
Write-Output ''
Write-Output '-- 4. Invariants apres l''effort -------------------------------------'
$inv = (Sql @"
select
  (select count(*) from verifier_soldes())::int                                    as ecarts_solde,
  (select count(*) from garages where solde < 0)::int                              as soldes_negatifs,
  (select count(*) from journal)::int                                              as lignes_journal,
  (select count(distinct cle_idem) from journal)::int                              as cles_distinctes,
  (select count(*) from grille where achete_le is not null)::int                   as cases_achetees,
  (select count(*) from grille where achete_le is not null and journal_id is null)::int as cases_sans_ecriture,
  (select count(*) from (select journal_id from grille where journal_id is not null
                          group by journal_id having count(*) > 1) d)::int         as ecritures_partagees,
  (select count(*) from grille where nature='lot')::int                            as cases_lot,
  (select count(*) from grille where nature='billet')::int                         as tickets_or
"@)[0]

function Verdict($libelle, $ok, $preuve) {
  if ($ok) { Write-Output ("  [OK]    {0}`n          preuve : {1}" -f $libelle, $preuve) }
  else     { Write-Output ("  [ECHEC] {0}`n          preuve : {1}" -f $libelle, $preuve); $script:ko++ }
}
$script:ko = 0
Verdict 'Solde en cache = somme du journal, sur les 1407 garages' `
        ($inv.ecarts_solde -eq 0) ("ecarts = " + $inv.ecarts_solde)
Verdict 'Aucun solde negatif' `
        ($inv.soldes_negatifs -eq 0) ("soldes < 0 : " + $inv.soldes_negatifs)
Verdict 'Aucun double credit : une cle d idempotence = une ligne' `
        ($inv.lignes_journal -eq $inv.cles_distinctes) `
        ("$($inv.lignes_journal) lignes pour $($inv.cles_distinctes) cles")
Verdict 'Toute case achetee porte son ecriture' `
        ($inv.cases_sans_ecriture -eq 0) ("cases sans ecriture : " + $inv.cases_sans_ecriture)
Verdict 'Une case = un seul gagnant (aucune ecriture partagee)' `
        ($inv.ecritures_partagees -eq 0) ("ecritures servant a 2 cases : " + $inv.ecritures_partagees)
Verdict 'La composition de la grille est intacte' `
        (($inv.cases_lot -eq 85) -and ($inv.tickets_or -eq 15)) `
        ("$($inv.cases_lot) lots / $($inv.tickets_or) tickets d or")

Write-Output ''
Write-Output ("  Journal : {0} -> {1} lignes · cases achetees : {2}" -f `
              $avant.journal, $inv.lignes_journal, $inv.cases_achetees)

}
finally {
  # --- restauration, quoi qu'il arrive --------------------------------
  Sql "update config set valeur='$($avant.plafond)' where cle='cases_max_garage'" | Out-Null
  Write-Output ("  Plafond de cases par garage restaure a {0}." -f $avant.plafond)
}
Write-Output ''
Write-Output '  ⚠️ La base porte encore les ecritures du test.'
Write-Output '     Lancer : .\scripts\push-sql.ps1 -File sql\99_remise_a_zero.sql'
Write-Output ''
Write-Output '===================================================================='
if (($totKo -eq 0) -and ($script:ko -eq 0)) {
  Write-Output '  TENU : aucun echec reseau, aucun invariant casse.'
} else {
  Write-Output ("  A REGARDER : {0} echec(s) reel(s), {1} invariant(s) casse(s)." -f $totKo, $script:ko)
}
Write-Output '===================================================================='
Write-Output ''
