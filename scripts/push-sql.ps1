# =====================================================================
#  push-sql.ps1 — exécute un fichier .sql (ou une requête) sur la base
#  Supabase du Forum Pièces Bony, via l'API de management.
#  Aucun outillage requis : ni Node, ni psql, ni Docker.
#
#    .\scripts\push-sql.ps1 -File sql\01_schema.sql
#    .\scripts\push-sql.ps1 -Query "select count(*) from garages"
# =====================================================================
param(
  [string]$File,
  [string]$Query,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# --- lecture de .env.local -------------------------------------------
$envPath = Join-Path $PSScriptRoot '..\.env.local'
if (-not (Test-Path $envPath)) { throw "Fichier .env.local introuvable ($envPath)" }
$conf = @{}
Get-Content $envPath -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$ref   = $conf['SUPABASE_PROJECT_REF']
$token = $conf['SUPABASE_ACCESS_TOKEN']
if (-not $ref)   { throw 'SUPABASE_PROJECT_REF absent de .env.local' }
if (-not $token) { throw 'SUPABASE_ACCESS_TOKEN absent de .env.local' }

# --- récupération du SQL ---------------------------------------------
if ($File) {
  $path = if ([System.IO.Path]::IsPathRooted($File)) { $File } else { Join-Path (Join-Path $PSScriptRoot '..') $File }
  if (-not (Test-Path $path)) { throw "Fichier SQL introuvable : $path" }
  $sql = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
  $etiquette = Split-Path $path -Leaf
} elseif ($Query) {
  $sql = $Query
  $etiquette = 'requête directe'
} else {
  throw 'Passez -File <chemin.sql> ou -Query "<sql>"'
}

# --- envoi ------------------------------------------------------------
$uri  = "https://api.supabase.com/v1/projects/$ref/database/query"
$body = @{ query = $sql } | ConvertTo-Json -Depth 3 -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

if (-not $Quiet) {
  Write-Output ("-> {0}  ({1} caracteres de SQL)" -f $etiquette, $sql.Length)
}

try {
  $r = Invoke-WebRequest -Uri $uri -Method POST `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType 'application/json' `
        -Body $bytes -TimeoutSec 120 -UseBasicParsing
  if (-not $Quiet) { Write-Output ("   OK  HTTP " + [int]$r.StatusCode) }
  # PIÈGE DÉJÀ PAYÉ. $r.Content décode les octets selon l'en-tête de la
  # réponse, et Supabase n'annonce pas toujours son charset : « Autos
  # République » revenait en « Autos RÃ©publique ». Inoffensif tant
  # qu'on ne fait que regarder, mais le générateur de badges lit cette
  # sortie — et aurait imprimé le mojibake sur les badges. On décode
  # les octets bruts en UTF-8, toujours.
  if ($r.RawContentStream) {
    Write-Output ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()))
  } elseif ($r.Content) {
    Write-Output $r.Content
  }
} catch {
  $code = 'n/a'
  if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
  $detail = ''
  try {
    $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream(), [System.Text.Encoding]::UTF8)
    $detail = $sr.ReadToEnd()
  } catch {}
  Write-Output ("   ECHEC  HTTP {0}" -f $code)
  Write-Output $detail
  exit 1
}
