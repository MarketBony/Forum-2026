#requires -Version 5
# =====================================================================
#  sms-listes.ps1 — les deux listes de diffusion SMS de la veille.
#
#    AGENTS  : inscrits a la reunion d'agents + Forum
#    AUTRES  : inscrits au Forum seulement
#
#  Le partage se fait sur participants.reunion_agents, le meme drapeau
#  qui trie les badges (voir sql/30... non : sql/28_reunion_agents.sql).
#  C'est l'INSCRIPTION reelle a la reunion, pas la lettre de profil du
#  fichier d'invitation — les deux different sur 20 lignes sur 145.
#
#  ⚠️ DEUX PIEGES QUI FONT RATER UNE CAMPAGNE, ET QUI NE SE VOIENT PAS.
#
#  1. LES NUMEROS SONT EN QUATRE FORMATS dans le listing consolide :
#     « 470415669 » (9 chiffres, zero initial perdu par Excel),
#     « 33466474685 », « +33473281919 », « 0565995186 ». Envoyes tels
#     quels, les trois quarts partent nulle part. Tout est normalise en
#     E.164 (+33XXXXXXXXX) ici.
#
#  2. LA MOITIE SONT DES FIXES. Un SMS sur un 04 ou un 05 n'arrive
#     jamais et ne rend aucune erreur : la passerelle l'accepte, le
#     message disparait. La colonne « Type » les separe, et le fichier
#     les range APRES les mobiles pour qu'on puisse selectionner le bloc
#     du haut sans reflechir.
#
#  Les fichiers vont dans exports\, ignore par git : ils portent des
#  noms, des numeros et les codes d'acces.
#
#    .\scripts\sms-listes.ps1
# =====================================================================
param([string]$Dossier = (Join-Path $PSScriptRoot '..\exports'))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$ref = $conf['SUPABASE_PROJECT_REF']; $pat = $conf['SUPABASE_ACCESS_TOKEN']
$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(120)

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $t = $r.Content.ReadAsStringAsync().Result
  if (-not $r.IsSuccessStatusCode) { throw "SQL : HTTP $([int]$r.StatusCode) — $t" }
  # ConvertFrom-Json rend un tableau comme UN SEUL objet : assigner sans
  # @(), compter avec @().
  $d = $t | ConvertFrom-Json
  return $d
}

# --- normalisation E.164 ---------------------------------------------
function Numero($brut) {
  $d = ($brut -replace '[^0-9]', '')
  if (-not $d) { return $null }
  if ($d.Length -eq 11 -and $d.StartsWith('33')) { $n = $d.Substring(2) }
  elseif ($d.Length -eq 12 -and $d.StartsWith('033')) { $n = $d.Substring(3) }
  elseif ($d.Length -eq 10 -and $d.StartsWith('0'))  { $n = $d.Substring(1) }
  elseif ($d.Length -eq 9)                            { $n = $d }
  else { return $null }
  if ($n.Length -ne 9) { return $null }
  return '+33' + $n
}
function EstMobile($e164) {
  if (-not $e164) { return $false }
  return ($e164.Substring(3,1) -eq '6' -or $e164.Substring(3,1) -eq '7')
}

# --- les deux messages ------------------------------------------------
#  ECRITS POUR L'ALPHABET GSM-7, et c'est une contrainte de cout, pas de
#  style. Un seul caractere hors de cet alphabet — un accent
#  circonflexe, une apostrophe typographique, des points de suspension —
#  bascule TOUT le message en UCS-2 : le segment tombe de 160 a 70
#  caracteres, et la facture double ou triple sans prevenir.
#  Sont disponibles et donc UTILISES : a-grave, e-aigu, e-grave,
#  u-grave, i-grave, o-grave. Ne le sont PAS : tous les circonflexes,
#  les tremas sauf a/o/u, la cedille minuscule, le A-grave MAJUSCULE,
#  l'apostrophe typographique et les points de suspension.
#  « cocktail dinatoire » est donc devenu « cocktail du soir » : le
#  i-circonflexe aurait fait basculer les 145 SMS en UCS-2, et ecrire
#  « dinatoire » sans accent est une faute qui se voit.
$MSG = @{
  AGENTS = "Bony Auto-mobile - Demain jeudi 17/09, Grande Halle d'Auvergne. " +
           "Accueil et viennoiseries dès 9h30 au Centre de Conférences, " +
           "réunion agents de 10h30 à 13h, puis cocktail déjeunatoire. " +
           "Forum Pièces de 15h à 20h et cocktail du soir dès 20h. A demain !"
  AUTRES = "Bony Auto-mobile - Demain jeudi 17/09, Grande Halle d'Auvergne. " +
           "Forum Pièces de 15h à 20h, Salon Haute-Loire. " +
           "Cocktail du soir dès 20h et remise des lots, Salon Allier. " +
           "Votre badge vous attend à l'accueil. A demain !"
}
$TITRE = @{ AGENTS = 'Agents - Reunion + Forum'; AUTRES = 'Autres garages - Forum' }

# --- controle GSM-7 ---------------------------------------------------
$GSM = "@£`$¥èéùìòÇ`nØø`rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !`"#¤%&'()*+,-./0123456789:;<=>?" +
       "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
$GSMEXT = "^{}\[~]|€"
function Gsm7($t) {
  $hors = @()
  foreach ($c in $t.ToCharArray()) {
    if ($GSM.IndexOf($c) -lt 0 -and $GSMEXT.IndexOf($c) -lt 0) { $hors += $c }
  }
  # Les caracteres de l'extension comptent DOUBLE dans un segment.
  $n = 0
  foreach ($c in $t.ToCharArray()) { $n += $(if ($GSMEXT.IndexOf($c) -ge 0) { 2 } else { 1 }) }
  $seg = if ($n -le 160) { 1 } else { [math]::Ceiling($n / 153) }
  return @{ hors = ($hors | Select-Object -Unique); unites = $n; segments = $seg }
}

# --- ecriture d'un vrai .xlsx, sans Excel et sans dependance ----------
#  Un .xlsx est un zip d'XML. On ecrit le minimum vital : une feuille,
#  des chaines en ligne (inlineStr), pas de table de chaines partagees.
#  Plus verbeux dans le fichier, beaucoup plus simple a produire — et
#  Excel comme les logiciels de SMS le lisent sans broncher.
function EchXml($t) {
  return ([string]$t).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}
function Xlsx($chemin, $entetes, $lignes) {
  $col = { param($i) # 0 -> A, 25 -> Z, 26 -> AA
           $s = ''; $n = $i
           do { $s = [char](65 + ($n % 26)) + $s; $n = [math]::Floor($n / 26) - 1 } while ($n -ge 0)
           return $s }
  $sb = New-Object Text.StringBuilder
  [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
  [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
  [void]$sb.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
  [void]$sb.Append('<cols>')
  for ($i = 0; $i -lt $entetes.Count; $i++) {
    [void]$sb.Append('<col min="' + ($i+1) + '" max="' + ($i+1) + '" width="' + $(if ($i -le 1) { 16 } else { 30 }) + '" customWidth="1"/>')
  }
  [void]$sb.Append('</cols><sheetData>')
  [void]$sb.Append('<row r="1">')
  for ($i = 0; $i -lt $entetes.Count; $i++) {
    [void]$sb.Append('<c r="' + (& $col $i) + '1" t="inlineStr" s="1"><is><t>' + (EchXml $entetes[$i]) + '</t></is></c>')
  }
  [void]$sb.Append('</row>')
  $r = 1
  foreach ($l in $lignes) {
    $r++
    [void]$sb.Append('<row r="' + $r + '">')
    for ($i = 0; $i -lt $l.Count; $i++) {
      [void]$sb.Append('<c r="' + (& $col $i) + $r + '" t="inlineStr"><is><t xml:space="preserve">' + (EchXml $l[$i]) + '</t></is></c>')
    }
    [void]$sb.Append('</row>')
  }
  [void]$sb.Append('</sheetData></worksheet>')

  $parts = @{
    '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
    '_rels/.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    'xl/workbook.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Contacts" sheetId="1" r:id="rId1"/></sheets></workbook>'
    'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
    'xl/styles.xml' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs></styleSheet>'
    'xl/worksheets/sheet1.xml' = $sb.ToString()
  }
  if (Test-Path $chemin) { Remove-Item $chemin -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($chemin, 'Create')
  try {
    foreach ($k in $parts.Keys) {
      $e = $zip.CreateEntry($k, [System.IO.Compression.CompressionLevel]::Optimal)
      $s = $e.Open()
      $b = [Text.Encoding]::UTF8.GetBytes($parts[$k])
      $s.Write($b, 0, $b.Length); $s.Close()
    }
  } finally { $zip.Dispose() }
}

# =====================================================================
Write-Output ''
Write-Output '===================================================================='
Write-Output "  Listes SMS — $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Write-Output '===================================================================='

$rows = Sql @"
select p.reunion_agents, p.raison_sociale, trim(p.prenom || ' ' || p.nom) as personne,
       coalesce(nullif(p.commune,''), g.ville, '') as commune,
       coalesce(p.telephone,'') as tel, p.nb_badges,
       coalesce(g.code,'') as code
from public.participants p
left join public.garages g on g.id = p.garage_id
where p.actif and p.categorie = 'GARAGE'
order by upper(p.raison_sociale)
"@

if (-not (Test-Path $Dossier)) { [void](New-Item -ItemType Directory -Force $Dossier) }
$Dossier = (Resolve-Path $Dossier).Path
$jour = Get-Date -Format 'yyyy-MM-dd'
$ENT = @('Telephone','Type','Garage','Personne','Commune','Code','Badges')

foreach ($cle in @('AGENTS','AUTRES')) {
  $veutAgents = ($cle -eq 'AGENTS')
  $lot = @($rows | Where-Object { [bool]$_.reunion_agents -eq $veutAgents })

  $lignes = New-Object System.Collections.ArrayList
  $rejets = New-Object System.Collections.ArrayList
  foreach ($x in $lot) {
    $n = Numero $x.tel
    if (-not $n) {
      [void]$rejets.Add(@($x.raison_sociale, $x.personne, $x.tel))
      continue
    }
    [void]$lignes.Add(@{
      tel = $n; mobile = (EstMobile $n); garage = $x.raison_sociale
      personne = $x.personne; commune = $x.commune; code = $x.code; nb = $x.nb_badges })
  }
  # Les mobiles d'abord : on selectionne le bloc du haut sans reflechir.
  $tri = @($lignes | Sort-Object @{E={-[int][bool]$_.mobile}}, @{E={$_.garage}})
  $tab = @($tri | ForEach-Object {
    ,@($_.tel, $(if ($_.mobile) { 'Mobile' } else { 'Fixe' }), $_.garage, $_.personne, $_.commune, $_.code, [string]$_.nb) })

  $nom = if ($veutAgents) { 'sms-agents' } else { 'sms-autres-garages' }
  $csv = Join-Path $Dossier "$nom-$jour.csv"
  $xls = Join-Path $Dossier "$nom-$jour.xlsx"

  # CSV point-virgule + BOM : Excel francais l'ouvre en colonnes sans
  # assistant d'importation, et toutes les passerelles SMS le lisent.
  $sb = New-Object Text.StringBuilder
  [void]$sb.AppendLine(($ENT -join ';'))
  foreach ($l in $tab) { [void]$sb.AppendLine((($l | ForEach-Object { '"' + ($_ -replace '"','""') + '"' }) -join ';')) }
  [IO.File]::WriteAllText($csv, $sb.ToString(), (New-Object Text.UTF8Encoding($true)))
  Xlsx $xls $ENT $tab

  $mob = @($tri | Where-Object { $_.mobile }).Count
  $fix = @($tri | Where-Object { -not $_.mobile }).Count
  Write-Output ''
  Write-Output ("  {0}" -f $TITRE[$cle])
  Write-Output ("     {0,4} lignes   {1,4} mobiles   {2,4} fixes   {3,4} sans numero exploitable" -f @($lot).Count, $mob, $fix, $rejets.Count)
  Write-Output ("     -> {0}" -f $csv)
  Write-Output ("     -> {0}" -f $xls)
  foreach ($r in $rejets) { Write-Output ("     ! sans numero : {0} / {1} / « {2} »" -f $r[0], $r[1], $r[2]) }

  $g = Gsm7 $MSG[$cle]
  Write-Output ("     Message : {0} caracteres, {1} segment(s) SMS" -f $g.unites, $g.segments)
  if (@($g.hors).Count -gt 0) {
    Write-Output ("     ⚠ HORS ALPHABET GSM-7 : {0} — le message passerait en UCS-2 (70 car./segment)" -f (@($g.hors) -join ' '))
  } else {
    Write-Output "     Alphabet GSM-7 : conforme, aucun caractere ne fait basculer en UCS-2."
  }
}

# Les deux messages, en clair, a copier dans le logiciel.
$txt = Join-Path $Dossier "sms-messages-$jour.txt"
$m = New-Object Text.StringBuilder
[void]$m.AppendLine("LE GRAND BAL DES FOURNISSEURS - messages SMS du $jour")
[void]$m.AppendLine('')
foreach ($cle in @('AGENTS','AUTRES')) {
  $g = Gsm7 $MSG[$cle]
  [void]$m.AppendLine('=== ' + $TITRE[$cle] + ' ===')
  [void]$m.AppendLine(("({0} caracteres, {1} segment(s) SMS)" -f $g.unites, $g.segments))
  [void]$m.AppendLine('')
  [void]$m.AppendLine($MSG[$cle])
  [void]$m.AppendLine('')
}
[IO.File]::WriteAllText($txt, $m.ToString(), (New-Object Text.UTF8Encoding($true)))
Write-Output ''
Write-Output ("  Messages -> {0}" -f $txt)
Write-Output ''
Write-Output '  Les fichiers portent des numeros ET les codes d''acces : exports\ reste sur ce poste.'
Write-Output ''
