#requires -Version 5
# =====================================================================
#  importer-garages.ps1
#  Lit le fichier Excel des invités, met les noms en forme, et produit
#  soit un aperçu (par défaut), soit le SQL d'import.
#
#    .\scripts\importer-garages.ps1 -Fichier "C:\...\Contacts.xlsx"
#    .\scripts\importer-garages.ps1 -Fichier "..." -Sql sql\10_garages.sql
#
#  Aucune dépendance : un .xlsx est une archive zip, on lit le XML.
# =====================================================================
param(
  [Parameter(Mandatory=$true)][string]$Fichier,
  [string]$Sql,
  [int]$Apercu = 24
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

# --- lecture du classeur ---------------------------------------------
$tmp = Join-Path $env:TEMP ("gbp-" + [guid]::NewGuid().ToString('N') + ".xlsx")
Copy-Item $Fichier $tmp -Force      # le fichier est souvent ouvert dans Excel
$zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
function Piece($nom) {
  $e = $zip.Entries | Where-Object { $_.FullName -eq $nom }
  if (-not $e) { return '' }
  $sr = New-Object System.IO.StreamReader($e.Open(), [System.Text.Encoding]::UTF8)
  $t = $sr.ReadToEnd(); $sr.Close(); return $t
}
$ss = Piece 'xl/sharedStrings.xml'
$sh = Piece 'xl/worksheets/sheet1.xml'
$zip.Dispose(); Remove-Item $tmp -Force

$chaines = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($ss, '<si>(.*?)</si>', 'Singleline')) {
  $t = ($([regex]::Matches($m.Groups[1].Value, '<t[^>]*>(.*?)</t>', 'Singleline') |
        ForEach-Object { $_.Groups[1].Value }) -join '')
  $t = $t.Replace('&amp;','&').Replace('&lt;','<').Replace('&gt;','>').Replace('&quot;','"').Replace('&apos;',"'")
  $chaines.Add($t)
}

$lignes = [regex]::Matches($sh, '<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', 'Singleline')
$brut = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -lt $lignes.Count; $i++) {
  $c = @{}
  foreach ($m in [regex]::Matches($lignes[$i].Groups[2].Value, '<c r="([A-Z]+)\d+"([^>]*)>(.*?)</c>', 'Singleline')) {
    $col = $m.Groups[1].Value; $att = $m.Groups[2].Value; $inn = $m.Groups[3].Value
    $mv = [regex]::Match($inn, '<v>(.*?)</v>', 'Singleline'); $v = ''
    if ($mv.Success) {
      if ($att -match 't="s"') { $v = $chaines[[int]$mv.Groups[1].Value] } else { $v = $mv.Groups[1].Value }
    }
    $c[$col] = $v
  }
  $brut.Add([pscustomobject]@{
    id = $c['C']; raison = $c['D']; compte = $c['E']
    cp = $c['F']; commune = $c['G']; profil = $c['B']; email = $c['A']
  })
}

# --- mise en forme ----------------------------------------------------
# Les formes juridiques sont retirées : « SARL Auto Dupont » se lit mieux
# « Auto Dupont » sur un téléphone, et l'hôtesse cherche par le nom usuel.
$formes = @('SARL','SASU','SAS','EURL','SCI','SNC','SA','SARLU')
$petits = @('de','du','des','la','le','les','et','au','aux','sur','sous','en')
$garder = @('ASM','TP','VL','PL','CTA','BMW','VW','JCB','MG','DS','AD','SPA','SN')

function Majuscule($mot) {
  # Le point déclenche aussi une majuscule (M.J.C.S, Ets G. Bonhomme).
  # Après une apostrophe, on ne capitalise que si le fragment fait au
  # moins deux lettres : « Cadr'Auto » oui, « Car's » non.
  $b = $mot.ToLower()
  $sb = New-Object System.Text.StringBuilder
  $debut = $true
  $n = $b.Length
  for ($i = 0; $i -lt $n; $i++) {
    $ch = $b[$i]
    if ($debut -and [char]::IsLetter($ch)) {
      [void]$sb.Append([char]::ToUpper($ch)); $debut = $false
    } else {
      [void]$sb.Append($ch)
      if ($ch -eq '-' -or $ch -eq ' ' -or $ch -eq '.') { $debut = $true }
      elseif ($ch -eq "'") {
        $reste = 0
        for ($k = $i + 1; $k -lt $n -and [char]::IsLetter($b[$k]); $k++) { $reste++ }
        $debut = ($reste -ge 2)
      }
    }
  }
  return $sb.ToString()
}

function Propre([string]$t, [bool]$commune) {
  if (-not $t) { return '' }
  $t = ($t -replace '\s+', ' ').Trim()
  $mots = New-Object System.Collections.Generic.List[string]
  foreach ($m in ($t -split ' ')) {
    if (-not $m) { continue }
    $u = $m.ToUpper().TrimEnd('.')
    if ((-not $commune) -and ($formes -contains $u)) { continue }
    if ($u -eq 'GGE')  { $mots.Add('Garage'); continue }
    if ($u -eq 'ETS')  { $mots.Add('Ets'); continue }
    if ($u -eq 'STE')  { $mots.Add($(if ($commune) { 'Sainte' } else { 'Société' })); continue }
    if ($u -eq 'ST')   { $mots.Add('Saint'); continue }
    if ($garder -contains $u) { $mots.Add($u); continue }
    if ($u -match '^[0-9]+$') { $mots.Add($u); continue }
    $b = $m.ToLower()
    if (($petits -contains $b) -and ($mots.Count -gt 0)) { $mots.Add($b); continue }
    $mots.Add((Majuscule $m))
  }
  $r = ($mots -join ' ').Trim()
  if ($commune) { $r = $r -replace '^Saint ', 'Saint-' -replace '^Sainte ', 'Sainte-' }
  return $r
}

# --- code d'accès -----------------------------------------------------
# Déterministe, dérivé du numéro de compte : réexécuter l'import ne change
# JAMAIS un code déjà parti dans un emailing. Alphabet sans caractères
# ambigus : ni I ni O, ni 0 ni 1.
$ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
$SEL = 'grand-bal-2026'
$md5 = [System.Security.Cryptography.MD5]::Create()

function CodeDe([string]$compte, [int]$variante) {
  $src = "$SEL|$compte|$variante"
  $h = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($src))
  $c = ''
  for ($i = 0; $i -lt 4; $i++) { $c += $ALPHABET[$h[$i] % 32] }
  return $c
}

$propre = New-Object System.Collections.Generic.List[object]
$pris = @{}
$collisions = 0
foreach ($g in $brut) {
  $nom = Propre $g.raison $false
  if (-not $nom) { $nom = Propre $g.raison $true }   # filet : nom vidé par le nettoyage

  $v = 0
  $code = CodeDe $g.compte $v
  while ($pris.ContainsKey($code)) { $v++; $collisions++; $code = CodeDe $g.compte $v }
  $pris[$code] = $g.compte

  $propre.Add([pscustomobject]@{
    compte = $g.compte; ref = $g.id
    nom = $nom
    ville = Propre $g.commune $true
    cp = $g.cp; profil = $g.profil; email = $g.email
    code = $code
  })
}
$md5.Dispose()

# --- sortie -----------------------------------------------------------
if ($Sql) {
  $chemin = if ([System.IO.Path]::IsPathRooted($Sql)) { $Sql } else { Join-Path (Join-Path $PSScriptRoot '..') $Sql }
  $e = { param($s) "'" + ($s -replace "'", "''") + "'" }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("-- =====================================================================")
  [void]$sb.AppendLine("--  Garages invités au Grand Bal 2026 — généré depuis le fichier Sarbacane")
  [void]$sb.AppendLine("--  $($propre.Count) garages. Clé : le numéro de compte Bony (unique).")
  [void]$sb.AppendLine("--  Régénérer avec scripts\importer-garages.ps1, ne pas éditer à la main.")
  [void]$sb.AppendLine("-- =====================================================================")
  [void]$sb.AppendLine("--  Les codes sont dérivés du numéro de compte : réexécuter l'import ne")
  [void]$sb.AppendLine("--  change jamais un code déjà parti dans un emailing.")
  [void]$sb.AppendLine("-- =====================================================================")
  [void]$sb.AppendLine("insert into public.garages (compte, ref_bony, nom, ville, cp, profil, email, code) values")
  $l = @()
  foreach ($g in $propre) {
    $l += "  (" + (& $e $g.compte) + "," + (& $e $g.ref) + "," + (& $e $g.nom) + "," +
          (& $e $g.ville) + "," + (& $e $g.cp) + "," + (& $e $g.profil) + "," +
          (& $e $g.email) + "," + (& $e $g.code) + ")"
  }
  [void]$sb.AppendLine(($l -join ",`n"))
  [void]$sb.AppendLine("on conflict (compte) do update set")
  [void]$sb.AppendLine("  nom = excluded.nom, ville = excluded.ville, cp = excluded.cp,")
  [void]$sb.AppendLine("  profil = excluded.profil, email = excluded.email;")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("select count(*) as garages, count(distinct code) as codes_distincts from public.garages;")
  [System.IO.File]::WriteAllText($chemin, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  Write-Output ("SQL ecrit : $chemin  (" + $propre.Count + " garages)")
  exit 0
}

Write-Output ''
Write-Output ("=== {0} garages lus ===" -f $propre.Count)
Write-Output ("  comptes uniques : " + (($propre | Select-Object -ExpandProperty compte -Unique).Count))
Write-Output ("  noms distincts  : " + (($propre | Select-Object -ExpandProperty nom -Unique).Count))
Write-Output ("  GGE etendus     : " + (($brut | Where-Object { $_.raison -match '\bGGE\b' }).Count))
Write-Output ("  formes retirees : " + (($brut | Where-Object { $_.raison -match '\b(SARL|SASU|SAS|EURL|SCI|SNC)\b' }).Count))
Write-Output ("  communes en ST  : " + (($brut | Where-Object { $_.commune -match '^ST ' }).Count))
Write-Output ''
Write-Output "=== avant  ->  apres ==="
$vus = @{}; $sel = New-Object System.Collections.Generic.List[int]
function Prendre($predicat, $n) {
  $k = 0
  for ($i = 0; $i -lt $brut.Count; $i++) {
    if ($k -ge $n) { break }
    if ($vus.ContainsKey($i)) { continue }
    if (& $predicat $brut[$i]) { $vus[$i] = 1; $sel.Add($i); $k++ }
  }
}
Prendre { param($g) $g.raison -match '\bGGE\b' } 4
Prendre { param($g) $g.raison -match '^(SARL|SASU|SAS|EURL)\b' } 5
Prendre { param($g) $g.raison -match '\b(ETS|STE)\b' } 3
Prendre { param($g) $g.commune -match '^ST ' } 3
Prendre { param($g) $g.raison -match "'" } 2
Prendre { param($g) $true } $Apercu
foreach ($i in $sel) {
  Write-Output ("  {0,-34} -> {1}" -f $brut[$i].raison, $propre[$i].nom)
  Write-Output ("  {0,-34}    {1} {2}" -f '', $propre[$i].cp, $propre[$i].ville)
}
