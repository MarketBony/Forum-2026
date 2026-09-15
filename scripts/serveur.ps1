#requires -Version 5
# =====================================================================
#  serveur.ps1 — petit serveur statique pour tester l'application en
#  local. Aucune dépendance : HttpListener est dans .NET.
#
#    .\scripts\serveur.ps1                          (http://localhost:8123)
#    .\scripts\serveur.ps1 -Port 9000
#    .\scripts\serveur.ps1 -Dossier presentation -Port 8125
#
#  Sert le dossier app\ par défaut. Nécessaire parce que les modules ES
#  et les service workers ne fonctionnent pas depuis file://.
#
#  -Dossier sert autre chose que l'application : les présentations, par
#  exemple. Elles s'ouvrent très bien en double-cliquant le fichier, mais
#  pas dans un navigateur piloté — et une présentation qu'on ne peut pas
#  relire avant la réunion est une présentation qu'on découvre en même
#  temps que la salle.
#
#  Le générateur de badges a le sien, scripts\serveur-badges.ps1 : il
#  rend des services que celui-ci n'a pas à connaître.
# =====================================================================
param([int]$Port = 8123, [string]$Dossier = 'app')

$ErrorActionPreference = 'Stop'
$racine = (Resolve-Path (Join-Path $PSScriptRoot (Join-Path '..' $Dossier))).Path

$types = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.mjs'  = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.webmanifest' = 'application/manifest+json; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.ico'  = 'image/x-icon'
  '.woff2'= 'font/woff2'
  '.txt'  = 'text/plain; charset=utf-8'
}

$ecouteur = New-Object System.Net.HttpListener
$ecouteur.Prefixes.Add("http://localhost:$Port/")
try {
  $ecouteur.Start()
} catch {
  Write-Output "Impossible d'ouvrir le port $Port : $($_.Exception.Message)"
  exit 1
}

Write-Output "Serveur actif  -> http://localhost:$Port/"
Write-Output "Dossier servi  -> $racine"
Write-Output "Ctrl+C pour arreter."

while ($ecouteur.IsListening) {
  $ctx = $ecouteur.GetContext()
  $req = $ctx.Request
  $rep = $ctx.Response
  try {
    $chemin = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath)
    if ($chemin -eq '/' -or $chemin.EndsWith('/')) { $chemin += 'index.html' }
    # on refuse toute sortie du dossier servi
    $cible = [System.IO.Path]::GetFullPath((Join-Path $racine $chemin.TrimStart('/')))
    if (-not $cible.StartsWith($racine, [StringComparison]::OrdinalIgnoreCase)) {
      $rep.StatusCode = 403
    } elseif (Test-Path $cible -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($cible).ToLower()
      $rep.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
      $rep.Headers['Cache-Control'] = 'no-cache'
      $octets = [System.IO.File]::ReadAllBytes($cible)
      $rep.ContentLength64 = $octets.Length
      $rep.OutputStream.Write($octets, 0, $octets.Length)
      $rep.StatusCode = 200
    } else {
      $rep.StatusCode = 404
      $msg = [Text.Encoding]::UTF8.GetBytes('404')
      $rep.OutputStream.Write($msg, 0, $msg.Length)
    }
    Write-Output ("{0,-4} {1} {2}" -f $req.HttpMethod, $rep.StatusCode, $chemin)
  } catch {
    try { $rep.StatusCode = 500 } catch {}
    Write-Output ("ERR  " + $_.Exception.Message)
  } finally {
    try { $rep.OutputStream.Close() } catch {}
  }
}
