#requires -Version 5
# =====================================================================
#  exporter-badges.ps1 — donne au générateur de badges ce que dit la
#  base, et rien d'autre.
#
#  DEPUIS LE 14 SEPTEMBRE, LE GÉNÉRATEUR NE CROISE PLUS RIEN. Il lisait
#  jusque-là les 1 407 invités d'un côté et les fichiers d'inscription
#  de l'autre ; ce croisement s'est révélé impraticable, le fichier
#  consolidé ayant montré que l'identifiant d'invitation n'est pas une
#  clé (BONY00250 a servi à trois sociétés). Le rapprochement se fait
#  désormais UNE fois, par scripts\importer-inscriptions.ps1, et la
#  table public.participants fait foi.
#
#  Ce script ne produit donc qu'un fichier : la vue v_badges, à plat.
#
#  badges\participants.json CONTIENT DES CODES D'ACCÈS. Il est ignoré
#  par git, au même titre que exports\. Ne le sortez pas du poste.
#
#    .\scripts\exporter-badges.ps1
# =====================================================================
param([string]$Dossier = (Join-Path $PSScriptRoot '..\badges'))

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

# HttpClient et pas Invoke-WebRequest : celui-ci ne rend pas le corps
# des réponses 4xx, et décode les accents selon l'en-tête du serveur.
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
  # ConvertFrom-Json rend un tableau comme UN seul objet en PowerShell
  # 5.1 : on assigne, puis on énumère. Ne pas envelopper dans @().
  $d = $corps | ConvertFrom-Json
  return $d
}

# Écriture SANS BOM : JSON.parse() du navigateur refuse un BOM en tête
# de fichier. C'est l'inverse de la règle des .ps1, qui eux en ont besoin.
function EcrireJson($chemin, $objet) {
  $json = ConvertTo-Json @($objet) -Depth 5 -Compress
  [IO.File]::WriteAllText($chemin, $json, (New-Object Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Dossier)) { New-Item -ItemType Directory -Force $Dossier | Out-Null }
$Dossier = (Resolve-Path $Dossier).Path

Write-Output ''
Write-Output ("  Export badges du {0}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))
Write-Output ''

# --- ce que le générateur affiche ------------------------------------
$badges = Sql @"
select id::text as id, categorie, raison_sociale, prenom, nom, commune,
       nb_badges, coalesce(code, '') as code
from public.v_badges
order by categorie, raison_sociale, nom, prenom
"@
EcrireJson (Join-Path $Dossier 'participants.json') $badges

$parCat = @{}
foreach ($b in $badges) { $parCat[$b.categorie] = [int]$parCat[$b.categorie] + [int]$b.nb_badges }
Write-Output ("  participants.json   {0,4} personnes" -f @($badges).Count)
foreach ($c in ($parCat.Keys | Sort-Object)) { Write-Output ("      {0,-14} {1,4} badges" -f $c, $parCat[$c]) }

# --- les garde-fous ---------------------------------------------------
# Un badge sans code valide sort avec un encadré vide : le porteur ne
# peut pas ouvrir son portefeuille. Mieux vaut le savoir avant la
# rame de papier.
$soucis = Sql "select categorie, raison_sociale, prenom, nom, souci from public.verifier_badges()"
# Deux personnes avec le même code ouvrent la même session : c'est une
# erreur de données, pas un détail d'affichage.
$doublons = Sql @"
select code, count(*) as n, string_agg(distinct raison_sociale, ' | ') as qui
from public.v_badges where coalesce(code,'') <> '' and categorie <> 'EQUIPE_BONY'
group by code having count(distinct raison_sociale) > 1
"@

$etat = [ordered]@{
  quand   = (Get-Date).ToString('s')
  export  = 'ok'
  message = ''
  soucis  = @($soucis | ForEach-Object { "$($_.categorie) · $($_.raison_sociale) · $($_.prenom) $($_.nom) : $($_.souci)" })
  doublons = @($doublons | ForEach-Object { "$($_.code) partage par $($_.qui)" })
}
[IO.File]::WriteAllText((Join-Path $Dossier '_etat.json'),
  (ConvertTo-Json $etat -Depth 4 -Compress), (New-Object Text.UTF8Encoding($false)))

Write-Output ''
if (@($soucis).Count) {
  Write-Output ("  /!\  {0} badge(s) sans code utilisable :" -f @($soucis).Count)
  $soucis | ForEach-Object { Write-Output ("       {0} · {1} {2} : {3}" -f $_.raison_sociale, $_.prenom, $_.nom, $_.souci) }
} else {
  Write-Output '  Tous les badges ont un code utilisable.'
}
if (@($doublons).Count) {
  Write-Output ("  /!\  {0} code(s) partage(s) par deux societes differentes :" -f @($doublons).Count)
  $doublons | ForEach-Object { Write-Output ("       {0} : {1}" -f $_.code, $_.qui) }
}

Write-Output ''
Write-Output '  participants.json contient des codes d''acces : il reste sur ce poste.'
Write-Output '  Generateur : icone « Badges - Forum 2026 » sur le Bureau.'
Write-Output ''
