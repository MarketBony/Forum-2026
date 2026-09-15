#requires -Version 5
# =====================================================================
#  simuler-forum.ps1
#  Une journée de Forum entière, jouée par l'API RÉELLE, jusqu'à ce que
#  les 200 cases soient prises.
#
#    .\scripts\simuler-forum.ps1                 # essai a blanc, n'ecrit rien
#    .\scripts\simuler-forum.ps1 -Appliquer      # remet a zero PUIS simule
#
#  ---------------------------------------------------------------------
#  POURQUOI PAR L'API ET PAS EN SQL DIRECT
#  Injecter des lignes en SQL ne prouverait RIEN : ni les plafonds, ni
#  l'idempotence, ni la concurrence sur une case, ni le pool PostgREST.
#  Tout passe donc par api_ouvrir, api_participation, api_resultat,
#  api_points_achat et api_jouer_case — le chemin exact des telephones.
#
#  POURQUOI C'EST SURESTIME, ET DE COMBIEN
#  Le Forum attend 212 inscrits, 320 avec les accompagnants. On en joue
#  400, chacun avec son telephone : pres du DOUBLE. Et on ne les etale
#  pas sur six heures — on compresse la journee en quelques minutes, ce
#  qui multiplie encore le debit par cent. Si ca tient ici, ca tient
#  jeudi avec une marge qu'on peut chiffrer.
#
#  CE QUE CE BANC NE PROUVE PAS, ET IL FAUT LE DIRE
#  Les 400 sessions partent d'UNE machine et d'UNE connexion Internet.
#  Il mesure Supabase, pas le wifi de la Grande Halle. Le wifi reste le
#  risque le plus probable de la soiree, et aucun script ne le testera.
#
#  ⚠️ IL REMET LA BASE A ZERO ET ECRIT DEDANS.
#  Avec -Appliquer, il lance 99_remise_a_zero.sql. A la fin, les 200
#  cases sont prises : IL FAUT RELANCER 99_remise_a_zero.sql AVANT LE
#  17, sinon aucun garage ne trouvera de case le jour J.
# =====================================================================
[CmdletBinding()]
param(
  [int]$Garages     = 400,   # 212 inscrits reels -> on en joue 400
  [int]$Vague       = 60,    # requetes tirees en meme temps
  [switch]$Appliquer
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
  $o = $null; try { $o = $t | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; data = $o; texte = $t }
}

# --- le collecteur de mesures ----------------------------------------
#  Une entree par appel : nom, duree, code HTTP, code d'erreur metier.
#  C'est lui qui produit tout le rapport final ; rien n'est calcule a la
#  volee, pour ne pas fausser la mesure avec le cout de la mesure.
$script:mes = New-Object System.Collections.ArrayList
$script:t0  = $null

function Jeton($graine) {
  # Jetons DETERMINISTES : une place d'appareil ne se rend pas (cle
  # etrangere depuis le journal) et le plafond est de 6 par garage.
  # Des jetons au hasard en consommeraient une a chaque execution, et le
  # banc tomberait en panne au 7e essai.
  $h = [System.Security.Cryptography.MD5]::Create().ComputeHash(
        [Text.Encoding]::UTF8.GetBytes("simu-forum-2026|$graine"))
  return (($h | ForEach-Object { $_.ToString('x2') }) -join '') * 2
}

# Lance un lot d'appels EN MEME TEMPS et rend les taches. La rafale est
# le pire cas et c'est le cas reel : des telephones cales sur le meme
# rythme tapent a la meme milliseconde.
function Rafale($appels) {
  $taches = New-Object 'System.Collections.Generic.List[object]'
  foreach ($a in $appels) {
    $c = New-Object System.Net.Http.StringContent(
          ($a.corps | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8, 'application/json')
    $depart = [DateTime]::UtcNow
    $t = $cli.PostAsync("$base/rest/v1/rpc/$($a.nom)", $c)
    $taches.Add([pscustomobject]@{ nom = $a.nom; tache = $t; depart = $depart; ctx = $a.ctx })
  }
  $sorties = New-Object 'System.Collections.Generic.List[object]'
  foreach ($t in $taches) {
    $ms = 0; $http = 0; $code = ''; $data = $null
    try {
      $r = $t.tache.Result
      $ms = ([DateTime]::UtcNow - $t.depart).TotalMilliseconds
      $http = [int]$r.StatusCode
      $corps = $r.Content.ReadAsStringAsync().Result
      try { $data = $corps | ConvertFrom-Json } catch {}
      if (-not $r.IsSuccessStatusCode -and $data) { $code = [string]$data.message }
    } catch {
      $ms = ([DateTime]::UtcNow - $t.depart).TotalMilliseconds
      $http = -1; $code = 'RESEAU'
    }
    [void]$script:mes.Add([pscustomobject]@{
      nom = $t.nom; ms = $ms; http = $http; code = $code
      quand = ([DateTime]::UtcNow - $script:t0).TotalSeconds })
    [void]$sorties.Add([pscustomobject]@{ ctx = $t.ctx; http = $http; code = $code; data = $data })
  }
  return $sorties
}

function Titre($t) {
  Write-Output ''
  Write-Output ('=' * 68)
  Write-Output ("  $t")
  Write-Output ('=' * 68)
}

# =====================================================================
Titre 'SIMULATION DU FORUM — une journee entiere, par l API reelle'
Write-Output ("  Garages joues .......... {0}   (212 inscrits reels : x{1:N1})" -f $Garages, ($Garages / 212))
Write-Output ("  Rafale ................. {0} requetes simultanees" -f $Vague)
Write-Output ("  Ecriture en base ....... {0}" -f $(if ($Appliquer) { 'OUI — la base est remise a zero' } else { 'NON — essai a blanc' }))

if (-not $Appliquer) {
  Write-Output ''
  Write-Output '  Relancer avec -Appliquer pour executer. RIEN N A ETE FAIT.'
  return
}

# --- 0. remise a zero -------------------------------------------------
Titre '0. Remise a zero'
# [System.IO.File]::ReadAllText et pas Get-Content -Raw : ce dernier
# rendait un objet la ou l'API attend une chaine, et Supabase repondait
# « expected string, received object » sans dire d'ou ca venait.
$cheminRaz = Join-Path $PSScriptRoot '..\sql\99_remise_a_zero.sql'
$sqlRaz = [System.IO.File]::ReadAllText($cheminRaz, [System.Text.Encoding]::UTF8)
$rz = Sql $sqlRaz
if (-not $rz.ok) { throw "La remise a zero a echoue : $($rz.texte)" }
$etat0 = (Sql @'
select (select count(*) from journal)                           as journal,
       (select count(*) from appareils)                         as appareils,
       (select count(*) from grille where garage_id is not null) as cases_prises,
       (select count(*) from garages where solde <> 0)          as soldes_non_nuls
'@).data[0]
Write-Output ("  journal={0}  appareils={1}  cases prises={2}  soldes non nuls={3}" -f `
              $etat0.journal, $etat0.appareils, $etat0.cases_prises, $etat0.soldes_non_nuls)

# --- le terrain -------------------------------------------------------
$codes = (Sql "select code from garages where actif order by md5(code) limit $Garages").data |
         ForEach-Object { $_.code }
$anims = (Sql @'
select a.code_pin, b.id as bareme, b.points
  from animations a join bareme b on b.animation_id = a.id
 where a.actif order by a.ordre, b.ordre
'@).data
$stands = (Sql "select code_pin from stands where actif").data | ForEach-Object { $_.code_pin }
$pinsAnim = @($anims | ForEach-Object { $_.code_pin } | Select-Object -Unique)
Write-Output ("  {0} codes garage, {1} animations, {2} stands" -f `
              @($codes).Count, @($pinsAnim).Count, @($stands).Count)

$script:t0 = [DateTime]::UtcNow

# --- 1. les arrivees --------------------------------------------------
Titre '1. Les arrivees — chaque garage ouvre son portefeuille'
$i = 0
while ($i -lt @($codes).Count) {
  $lot = @()
  for ($k = 0; $k -lt $Vague -and $i -lt @($codes).Count; $k++, $i++) {
    $lot += @{ nom = 'api_ouvrir'; ctx = $codes[$i]
               corps = @{ p_jeton = (Jeton "g$($codes[$i])"); p_code = $codes[$i] } }
  }
  Rafale $lot | Out-Null
  Write-Host "`r  $i / $($codes.Count)" -NoNewline
}
Write-Output ''
$arrives = (Sql "select count(*)::int as n from garages where inscrit_le is not null").data[0].n
Write-Output ("  {0} garages arrives, bonus verse une seule fois chacun" -f $arrives)

# --- 2. le personnel se connecte --------------------------------------
Titre '2. Le personnel — 6 animateurs, 23 stands, la supervision'
$lot = @()
foreach ($p in $pinsAnim) { $lot += @{ nom = 'api_connexion'; ctx = $p; corps = @{ p_jeton = (Jeton "a$p"); p_pin = $p } } }
foreach ($p in $stands)   { $lot += @{ nom = 'api_connexion'; ctx = $p; corps = @{ p_jeton = (Jeton "s$p"); p_pin = $p } } }
$pinAdm = (Sql "select valeur from config where cle='pin_admin'").data[0].valeur
$lot += @{ nom = 'api_connexion'; ctx = 'admin'; corps = @{ p_jeton = (Jeton 'adm'); p_pin = $pinAdm } }
$rep = Rafale $lot
Write-Output ("  {0} connexions, {1} refus" -f @($rep).Count, @($rep | Where-Object { $_.http -ne 200 }).Count)

# --- 3. la journee : animations et stands -----------------------------
Titre '3. La journee — animations et stands fournisseurs'
#  Chaque garage joue 4 animations (participation PUIS resultat : deux
#  ecritures) et passe sur 5 stands. Soit 13 ecritures par garage, contre
#  8 dans le modele de CONTEXTE.md — la surestimation porte aussi sur ce
#  que CHACUN fait, pas seulement sur combien ils sont.
#
#  Trois passes plutot qu'un melange : les participations d'abord (le
#  solde descend a 10 - 2x4 = 2, jamais negatif), les resultats ensuite,
#  les stands pour finir. Dans une rafale l'ordre n'est pas garanti ; en
#  passes il l'est, et on ne mesure pas des refus de solde insuffisant
#  qui n'auraient aucun sens au Forum.

# Le detail des animations : un id d'animation, et son meilleur palier.
$detAnim = (Sql @'
select a.id as anim, a.code_pin, b.id as bareme, b.points,
       row_number() over (partition by a.id order by b.points desc) as rg
  from animations a join bareme b on b.animation_id = a.id
 where a.actif
'@).data | Where-Object { $_.rg -eq 1 }
Write-Output ("  {0} animations resolues (id + meilleur palier)" -f @($detAnim).Count)

# Le palier haut de chaque categorie de stand, pour que l'ecriture soit
# journalisee avec un libelle qui existe vraiment.
$palStand = @{}
(Sql @'
select s.code_pin, bs.libelle,
       row_number() over (partition by s.code_pin order by bs.points desc) as rg
  from stands s join bareme_stand bs on bs.categorie = s.categorie
 where s.actif
'@).data | Where-Object { $_.rg -eq 1 } | ForEach-Object { $palStand[$_.code_pin] = $_.libelle }

$idParCode = @{}
(Sql "select code, id from garages where actif").data | ForEach-Object { $idParCode[$_.code] = $_.id }

function Jouer($lot, $libelle) {
  $i = 0
  while ($i -lt @($lot).Count) {
    $paquet = @()
    for ($k = 0; $k -lt $Vague -and $i -lt @($lot).Count; $k++, $i++) { $paquet += $lot[$i] }
    Rafale $paquet | Out-Null
    Write-Host "`r  $libelle : $i / $(@($lot).Count)   " -NoNewline
  }
  Write-Output ''
}

# passe 1 : les participations (-2 chacune)
$lot = @()
foreach ($c in $codes) {
  for ($j = 0; $j -lt 4; $j++) {
    $a = $detAnim[(Get-Random -Maximum @($detAnim).Count)]
    $lot += @{ nom = 'api_participation'; ctx = $c
      corps = @{ p_jeton = (Jeton "a$($a.code_pin)"); p_garage = $idParCode[$c]
                 p_animation = $a.anim; p_cle = "simu-part-$c-$j" } }
  }
}
Jouer $lot 'participations'

# passe 2 : les resultats (le gain)
$lot = @()
foreach ($c in $codes) {
  for ($j = 0; $j -lt 4; $j++) {
    $a = $detAnim[(Get-Random -Maximum @($detAnim).Count)]
    $lot += @{ nom = 'api_resultat'; ctx = $c
      corps = @{ p_jeton = (Jeton "a$($a.code_pin)"); p_garage = $idParCode[$c]
                 p_bareme = $a.bareme; p_cle = "simu-res-$c-$j" } }
  }
}
Jouer $lot 'resultats     '

# passe 3 : les stands, 20 points chacun (le plafond par operation)
$lot = @()
foreach ($c in $codes) {
  for ($j = 0; $j -lt 5; $j++) {
    $st = $stands[(Get-Random -Maximum @($stands).Count)]
    $lot += @{ nom = 'api_points_achat'; ctx = $c
      corps = @{ p_jeton = (Jeton "s$st"); p_garage = $idParCode[$c]; p_points = 20
                 p_cle = "simu-stand-$c-$j"; p_palier = $palStand[$st] } }
  }
}
Jouer $lot 'stands        '

$soldes = (Sql @'
select count(*)::int as avec_solde, coalesce(sum(solde),0)::int as total,
       coalesce(max(solde),0)::int as plus_haut, coalesce(round(avg(solde)),0)::int as moyen
  from garages where solde > 0
'@).data[0]
Write-Output ("  {0} garages avec un solde · {1} points en circulation · moyen {2} · plus haut {3}" -f `
              $soldes.avec_solde, $soldes.total, $soldes.moyen, $soldes.plus_haut)

# --- 4. la grille jusqu'a epuisement ----------------------------------
Titre '4. La grille — jusqu a ce que les 200 cases soient prises'
$plafond = (Sql "select valeur from config where cle='cases_max_garage'").data[0].valeur
Write-Output ("  plafond de {0} cases par garage — il faut au moins {1} acheteurs" -f `
              $plafond, [Math]::Ceiling(200 / [int]$plafond))

$tour = 0
$libres = (Sql "select count(*)::int as n from grille where garage_id is null").data[0].n
while ($libres -gt 0 -and $tour -lt 40) {
  $tour++
  $dispo = (Sql "select numero from grille where garage_id is null order by numero").data |
           ForEach-Object { $_.numero }
  $acheteurs = (Sql @"
select g.code from garages g
 where g.actif and g.solde >= 20
   and (select count(*) from grille gr where gr.garage_id = g.id) < $plafond
 order by md5(g.code) limit 400
"@).data | ForEach-Object { $_.code }
  if (@($acheteurs).Count -eq 0) { Write-Output '  plus aucun garage solvable — on arrete'; break }

  $lot = @()
  $z = 0
  foreach ($c in @($acheteurs)) {
    if ($z -ge @($dispo).Count) { break }
    $lot += @{ nom = 'api_jouer_case'; ctx = $c
      corps = @{ p_jeton = (Jeton "g$c"); p_numero = $dispo[$z]
                 p_cle = "simu-case-$c-$tour-$z" } }
    $z++
  }
  $r = Rafale $lot
  $pris = @($r | Where-Object { $_.http -eq 200 }).Count
  $libres = (Sql "select count(*)::int as n from grille where garage_id is null").data[0].n
  Write-Output ("  tour {0,2} : {1,3} achats tentes, {2,3} aboutis, {3,3} cases encore libres" -f `
                $tour, @($lot).Count, $pris, $libres)
}

# --- 5. le soir -------------------------------------------------------
Titre '5. Le soir — la revelation des tickets d or'
$rev = Rafale @(@{ nom = 'api_tirage_lancer'; ctx = 'soir'; corps = @{ p_jeton = (Jeton 'adm') } })
$tk = (Sql "select count(*)::int as n from grille where nature='billet' and garage_id is not null").data[0].n
Write-Output ("  revelation : HTTP {0}, {1} tickets d or decroches" -f @($rev)[0].http, $tk)

# =====================================================================
Titre 'RESULTAT'
$duree = ([DateTime]::UtcNow - $script:t0).TotalSeconds
$tout  = @($script:mes)
$ok    = @($tout | Where-Object { $_.http -eq 200 })
$refus = @($tout | Where-Object { $_.http -eq 400 })
$durs  = @($tout | Where-Object { $_.http -ne 200 -and $_.http -ne 400 })

Write-Output ("  Duree ................... {0:N1} s" -f $duree)
Write-Output ("  Appels .................. {0}" -f $tout.Count)
Write-Output ("  Debit moyen ............. {0:N1} req/s" -f ($tout.Count / $duree))
Write-Output ("  Reussites ............... {0}" -f $ok.Count)
Write-Output ("  Refus metier (HTTP 400) . {0}   <- attendus : case prise, plafond, solde" -f $refus.Count)
Write-Output ("  ECHECS DURS ............. {0}   <- doivent etre a ZERO" -f $durs.Count)

# Le debit de POINTE, seconde par seconde : c'est lui qui sature un pool,
# pas la moyenne. Le rapport d'incident GRID est parti d'une rafale.
$parSeconde = $tout | Group-Object { [int]$_.quand } | ForEach-Object { $_.Count }
$pointe = ($parSeconde | Measure-Object -Maximum).Maximum
Write-Output ("  Debit de POINTE ......... {0} req/s   (charge attendue au Forum : ~20)" -f $pointe)

Write-Output ''
Write-Output '  Latence par appel (ms)'
Write-Output ('  {0,-24} {1,6} {2,8} {3,8} {4,8} {5,8}' -f 'appel', 'n', 'mediane', 'p95', 'p99', 'pire')
foreach ($g in ($tout | Group-Object nom | Sort-Object Count -Descending)) {
  $t = @($g.Group | ForEach-Object { $_.ms } | Sort-Object)
  $q = { param($p) $t[[Math]::Min($t.Count - 1, [int][Math]::Floor($t.Count * $p))] }
  Write-Output ('  {0,-24} {1,6} {2,8:N0} {3,8:N0} {4,8:N0} {5,8:N0}' -f `
    $g.Name, $t.Count, (& $q 0.5), (& $q 0.95), (& $q 0.99), $t[-1])
}

if ($refus.Count -gt 0) {
  Write-Output ''
  Write-Output '  Refus metier par motif (ce sont des succes du point de vue des garde-fous)'
  foreach ($g in ($refus | Group-Object code | Sort-Object Count -Descending)) {
    Write-Output ('  {0,-34} {1,5}' -f $(if ($g.Name) { $g.Name } else { '(sans code)' }), $g.Count)
  }
}
if ($durs.Count -gt 0) {
  Write-Output ''
  Write-Output '  ECHECS DURS PAR MOTIF'
  foreach ($g in ($durs | Group-Object code | Sort-Object Count -Descending)) {
    Write-Output ('  {0,-34} {1,5}' -f $(if ($g.Name) { $g.Name } else { '(sans code)' }), $g.Count)
  }
}

Write-Output ''
Write-Output '  Etat final de la base'
$fin = (Sql @'
select (select count(*) from journal)                                 as lignes_journal,
       (select count(distinct cle_idem) from journal)                 as cles_distinctes,
       (select count(*) from garages where inscrit_le is not null)    as garages_arrives,
       (select coalesce(sum(solde),0) from garages)                   as points_en_circulation,
       (select count(*) from grille where garage_id is not null)      as cases_prises,
       (select count(*) from grille where garage_id is null)          as cases_libres,
       (select count(*) from grille where nature='billet' and garage_id is not null) as tickets_or,
       (select count(*) from verifier_soldes())                       as ecarts_solde,
       (select count(*) from appareils)                               as appareils,
       (select count(*) from pg_stat_activity where usename='authenticator') as pool
'@).data[0]
foreach ($p in $fin.PSObject.Properties) {
  Write-Output ('  {0,-26} {1}' -f $p.Name, $p.Value)
}

Write-Output ''
if ($durs.Count -eq 0 -and [int]$fin.ecarts_solde -eq 0 -and [int]$fin.lignes_journal -eq [int]$fin.cles_distinctes) {
  Write-Output '  VERDICT : aucun echec dur, aucun ecart de solde, aucune cle d idempotence en double.'
} else {
  Write-Output '  VERDICT : ANOMALIE — voir les lignes ci-dessus.'
}
Write-Output ''
Write-Output '  ⚠️ Les 200 cases sont prises. RELANCER 99_remise_a_zero.sql AVANT LE 17.'
Write-Output ''
