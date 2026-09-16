#requires -Version 5
# =====================================================================
#  emargement.ps1 — la liste papier des hôtesses.
#
#  POURQUOI DU PAPIER ALORS QU'IL Y A UN ÉCRAN D'ACCUEIL.
#  L'écran d'accueil sait retrouver n'importe lequel des 1 456 invités
#  et lire son code ; le papier ne sait rien faire de tout ça. Il sert à
#  autre chose : COCHER. Deux hôtesses qui accueillent 320 personnes en
#  deux heures ont besoin de savoir qui est déjà passé, et un écran
#  partagé ne se coche pas à deux mains. C'est aussi le seul document
#  qui survit à une panne de wifi.
#
#  ⚠️ AUCUN CODE D'ACCÈS N'Y FIGURE, ET C'EST VOLONTAIRE.
#  Une feuille d'émargement traîne sur une table d'accueil toute la
#  journée, et se photographie en une seconde. Les codes restent sur
#  l'écran d'accueil, qui en montre UN à la fois, à la demande. Même
#  règle que pour la présentation à la direction.
#
#  L'ORDRE EST CELUI DES PILES DE BADGES, pas l'ordre alphabétique
#  global. Une hôtesse cherche un badge dans une pile ET une ligne sur
#  une feuille : si les deux ne sont pas rangés pareil, elle cherche
#  deux fois. Les garages suivent donc « agents d'abord », et l'équipe
#  Bony suit le nom de famille — exactement comme badges\badges.js.
#
#    .\scripts\emargement.ps1
#    .\scripts\emargement.ps1 -Categories GARAGE
# =====================================================================
param(
  [string[]]$Categories = @('GARAGE', 'EQUIPE_BONY', 'CONSTRUCTEUR', 'EXPOSANT', 'ANIMATION', 'HOTESSE'),
  [string]$Dossier = (Join-Path $PSScriptRoot '..\exports')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$envPath = Join-Path $PSScriptRoot '..\.env.local'
if (-not (Test-Path $envPath)) { throw "Fichier .env.local introuvable ($envPath)" }
$conf = @{}
Get-Content $envPath -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$ref = $conf['SUPABASE_PROJECT_REF']
$pat = $conf['SUPABASE_ACCESS_TOKEN']
if (-not $ref -or -not $pat) { throw 'SUPABASE_PROJECT_REF ou SUPABASE_ACCESS_TOKEN absent de .env.local' }

# HttpClient et pas Invoke-WebRequest : celui-ci ne rend pas le corps des
# reponses 4xx, et decode les accents selon un en-tete que Supabase
# n'annonce pas toujours — « Autos Republique » revenait casse.
$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(120)

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $corps = $r.Content.ReadAsStringAsync().Result
  if (-not $r.IsSuccessStatusCode) { throw "Lecture impossible : HTTP $([int]$r.StatusCode) — $corps" }
  # ConvertFrom-Json rend un tableau comme UN SEUL objet : on assigne
  # sans @(), et on compte avec @() au moment de compter.
  $d = $corps | ConvertFrom-Json
  return $d
}

function TrouverChrome {
  foreach ($exe in 'chrome.exe', 'msedge.exe') {
    $cle = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe"
    foreach ($c in @($cle, ($cle -replace 'HKLM:', 'HKCU:'))) {
      try { $v = (Get-ItemProperty $c -ErrorAction Stop).'(default)'
            if ($v -and (Test-Path $v)) { return $v } } catch {}
    }
    foreach ($b in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
      foreach ($s in @('Google\Chrome\Application', 'Microsoft\Edge\Application')) {
        $p = Join-Path (Join-Path $b $s) $exe
        if (Test-Path $p) { return $p }
      }
    }
  }
  return $null
}

function Echapper($t) {
  return ([string]$t).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;')
}

$LIBELLE = @{
  'GARAGE'       = 'Garages'
  'EQUIPE_BONY'  = 'Équipe Bony'
  'CONSTRUCTEUR' = 'Constructeurs'
  'EXPOSANT'     = 'Exposants'
  'ANIMATION'    = 'Animateurs'
  'HOTESSE'      = 'Hôtesses'
}

Write-Output ''
Write-Output "  Liste d'emargement du $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
Write-Output ''

# --- ce qu'on lit -----------------------------------------------------
#  reunion_agents porte le tri des garages, exactement comme dans le
#  generateur : agents d'abord, chaque moitie de A a Z. L'equipe Bony,
#  elle, se range par nom de famille. On NE lit AUCUN code.
$lignes = Sql @"
select p.categorie,
       p.raison_sociale,
       trim(p.prenom || ' ' || p.nom) as personne,
       coalesce(nullif(p.commune, ''), g.ville, '') as commune,
       p.nb_badges,
       p.reunion_agents
from public.participants p
left join public.garages g on g.id = p.garage_id
where p.actif
order by
  case p.categorie when 'GARAGE' then 0 when 'EQUIPE_BONY' then 1
                   when 'CONSTRUCTEUR' then 2 else 3 end,
  case when p.categorie = 'GARAGE' and p.reunion_agents then 0 else 1 end,
  case when p.categorie = 'EQUIPE_BONY' then upper(p.nom) end nulls last,
  upper(p.raison_sociale), upper(p.nom), upper(p.prenom)
"@

$parCat = @{}
foreach ($l in $lignes) {
  if (-not $parCat.ContainsKey($l.categorie)) { $parCat[$l.categorie] = New-Object Collections.ArrayList }
  [void]$parCat[$l.categorie].Add($l)
}

# --- la page ----------------------------------------------------------
#  Sobre et imprimable : noir sur blanc, aucune couleur de fond. Une
#  hotesse coche au stylo sur du papier ordinaire ; un aplat de couleur
#  coute de l'encre et rend la case a cocher moins nette.
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine(@'
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<title>Émargement — Le Grand Bal des Fournisseurs</title>
<style>
  @page { size:A4 portrait; margin:12mm 10mm 14mm 10mm; }
  * { box-sizing:border-box }
  body { font:11pt/1.35 "Segoe UI",Arial,sans-serif; color:#000; margin:0 }
  h1 { font-size:15pt; margin:0 0 1mm }
  .sous { font-size:9pt; color:#444; margin:0 0 4mm }
  /* Chaque categorie repart sur une page : les piles de badges sont
     separees, les feuilles doivent l'etre aussi. */
  section { break-before:page }
  section:first-of-type { break-before:auto }
  h2 { font-size:13pt; margin:0 0 1mm; border-bottom:1.5pt solid #000; padding-bottom:1mm }
  .cpt { font-size:9pt; color:#444; margin:0 0 3mm }
  table { width:100%; border-collapse:collapse }
  /* L'en-tete se repete sur chaque page imprimee : sans ca, la page 2
     d'une liste de 145 lignes n'a plus de colonnes. */
  thead { display:table-header-group }
  tr { break-inside:avoid }
  th { font-size:8.5pt; text-transform:uppercase; letter-spacing:.06em;
       text-align:left; padding:1.5mm 1mm; border-bottom:1pt solid #000 }
  td { padding:1.6mm 1mm; border-bottom:.4pt solid #bbb; vertical-align:top }
  .case { width:9mm }
  .case i { display:block; width:4.5mm; height:4.5mm; border:1pt solid #000 }
  .qui { font-weight:700 }
  .pers { font-size:9.5pt; color:#333 }
  .com { font-size:9.5pt; color:#333; width:34mm }
  .nb { width:12mm; text-align:center; font-variant-numeric:tabular-nums }
  .sig { width:38mm }
  .sep td { background:#eee; font-weight:700; font-size:9pt;
            text-transform:uppercase; letter-spacing:.08em; border-bottom:1pt solid #000 }
  .pied { margin-top:4mm; font-size:8.5pt; color:#444 }
</style></head><body>
'@)
[void]$sb.AppendLine("<h1>Le Grand Bal des Fournisseurs — émargement</h1>")
[void]$sb.AppendLine("<p class='sous'>Jeudi 17 septembre 2026 · Grande Halle d'Auvergne · liste éditée le $(Get-Date -Format 'dd/MM/yyyy à HH:mm')</p>")

$total = 0
foreach ($cat in $Categories) {
  if (-not $parCat.ContainsKey($cat)) { continue }
  $l = $parCat[$cat]
  $nb = 0; foreach ($x in $l) { $nb += [int]$x.nb_badges }
  $total += $nb
  $titre = if ($LIBELLE.ContainsKey($cat)) { $LIBELLE[$cat] } else { $cat }

  [void]$sb.AppendLine("<section><h2>$(Echapper $titre)</h2>")
  $ordre = if ($cat -eq 'EQUIPE_BONY') { 'par nom de famille' }
           elseif ($cat -eq 'GARAGE')  { 'agents de la réunion d''abord, puis les autres — même ordre que la pile de badges' }
           else { 'par ordre alphabétique' }
  [void]$sb.AppendLine("<p class='cpt'>$(@($l).Count) ligne(s) · $nb badge(s) · $ordre</p>")
  [void]$sb.AppendLine("<table><thead><tr><th class='case'></th><th>Société</th><th>Personne</th><th>Commune</th><th class='nb'>Badges</th><th class='sig'>Signature</th></tr></thead><tbody>")

  $agentsFinis = $false
  foreach ($x in $l) {
    # Le trait qui separe les deux piles de garages. Il n'apparait que
    # la ou les agents s'arretent, et seulement s'il y en avait.
    if ($cat -eq 'GARAGE' -and -not $agentsFinis -and -not $x.reunion_agents) {
      $agentsFinis = $true
      [void]$sb.AppendLine("<tr class='sep'><td colspan='6'>Garages non inscrits à la réunion d'agents</td></tr>")
    }
    $pers = if ($x.personne) { Echapper $x.personne } else { '' }
    [void]$sb.AppendLine("<tr><td class='case'><i></i></td><td class='qui'>$(Echapper $x.raison_sociale)</td><td class='pers'>$pers</td><td class='com'>$(Echapper $x.commune)</td><td class='nb'>$($x.nb_badges)</td><td class='sig'></td></tr>")
  }
  [void]$sb.AppendLine("</tbody></table>")
  [void]$sb.AppendLine("<p class='pied'>Un invité absent de cette liste n'est pas un intrus : il ne s'était simplement pas inscrit. Badge vierge, et l'écran d'accueil retrouve son code.</p>")
  [void]$sb.AppendLine("</section>")
}
[void]$sb.AppendLine('</body></html>')

if (-not (Test-Path $Dossier)) { [void](New-Item -ItemType Directory -Force $Dossier) }
$Dossier = (Resolve-Path $Dossier).Path
$jour = Get-Date -Format 'yyyy-MM-dd'
$html = Join-Path $Dossier "emargement-$jour.html"
$pdf  = Join-Path $Dossier "emargement-$jour.pdf"
[IO.File]::WriteAllText($html, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))

foreach ($cat in $Categories) {
  if ($parCat.ContainsKey($cat)) {
    $l = $parCat[$cat]; $nb = 0; foreach ($x in $l) { $nb += [int]$x.nb_badges }
    Write-Output ("      {0,-14} {1,4} ligne(s)  {2,4} badge(s)" -f $LIBELLE[$cat], @($l).Count, $nb)
  }
}
Write-Output ''
Write-Output ("  HTML  -> {0}" -f $html)

$chrome = TrouverChrome
if ($chrome) {
  # Start-Process -ArgumentList en TABLEAU ne met aucun guillemet, et le
  # projet vit dans « APP FORUM » : un chemin a espace se couperait en
  # deux. On passe donc UNE chaine, guillemets poses a la main.
  $args = '--headless=new --disable-gpu --no-pdf-header-footer ' +
          '--print-to-pdf="' + $pdf + '" "file:///' + ($html -replace '\\', '/') + '"'
  Start-Process -FilePath $chrome -ArgumentList $args -Wait -NoNewWindow
  if (Test-Path $pdf) {
    Write-Output ("  PDF   -> {0}  ({1} Ko)" -f $pdf, [math]::Round((Get-Item $pdf).Length / 1KB))
  } else {
    Write-Output "  PDF   -> echec : imprimez le HTML depuis le navigateur."
  }
} else {
  Write-Output "  PDF   -> Chrome introuvable : ouvrez le HTML et imprimez-le."
}

Write-Output ''
Write-Output "  $total badge(s) au total."
Write-Output "  AUCUN code d'acces sur cette liste : ils restent sur l'ecran d'accueil."
Write-Output "  exports\ est ignore par git — la liste porte des noms, elle reste sur ce poste."
