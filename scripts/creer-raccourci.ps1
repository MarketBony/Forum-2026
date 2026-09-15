#requires -Version 5
# =====================================================================
#  creer-raccourci.ps1 — pose l'icône « Badges — Forum 2026 » sur le
#  Bureau, et une copie à la racine du projet.
#
#  À lancer UNE FOIS. Ensuite, le générateur s'ouvre d'un double-clic,
#  sans jamais taper de commande. À relancer si le dossier du projet
#  est déplacé : un raccourci Windows retient un chemin absolu.
#
#  Le raccourci pointe sur wscript.exe plutôt que sur powershell.exe,
#  pour qu'aucune console ne clignote au démarrage — voir l'en-tête de
#  badges-silencieux.vbs.
#
#    .\scripts\creer-raccourci.ps1
#    .\scripts\creer-raccourci.ps1 -Retirer      (enleve les raccourcis)
# =====================================================================
param([switch]$Retirer)

$ErrorActionPreference = 'Stop'

$racine = Split-Path $PSScriptRoot -Parent
$nom    = 'Badges — Forum 2026.lnk'
$cibles = @(
  (Join-Path ([Environment]::GetFolderPath('Desktop')) $nom),
  (Join-Path $racine $nom)
)

if ($Retirer) {
  foreach ($c in $cibles) { if (Test-Path $c) { Remove-Item $c -Force; Write-Output "  retire  $c" } }
  Write-Output ''
  return
}

$vbs   = Join-Path $PSScriptRoot 'badges-silencieux.vbs'
$icone = Join-Path $racine 'badges\icone.ico'
foreach ($f in @($vbs, $icone)) {
  if (-not (Test-Path $f)) { throw "Fichier introuvable : $f" }
}

$shell = New-Object -ComObject WScript.Shell
foreach ($c in $cibles) {
  $r = $shell.CreateShortcut($c)
  $r.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
  $r.Arguments        = '"' + $vbs + '"'
  $r.WorkingDirectory = $racine
  $r.IconLocation     = $icone + ',0'
  $r.Description      = 'Generateur de badges du Grand Bal des Fournisseurs — Forum Pieces Bony 2026'
  $r.Save()
  Write-Output "  cree    $c"
}

Write-Output ''
Write-Output '  Double-clic sur l''icone du Bureau : le generateur s''ouvre.'
Write-Output '  Clic droit -> Epingler a la barre des taches, si tu veux l''avoir sous la main.'
Write-Output ''
