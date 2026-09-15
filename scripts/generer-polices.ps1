#requires -Version 5
# =====================================================================
#  generer-polices.ps1 — fabrique badges\polices.css à partir des
#  fichiers .woff2 de badges\polices\.
#
#  À relancer uniquement si l'on change de police. Le résultat est
#  versionné : le générateur doit fonctionner sans connexion, et sans
#  qu'on ait à se souvenir de cette étape.
#
#  DEUX PIÈGES PAYÉS ICI, TOUS LES DEUX INVISIBLES À L'ÉCRAN.
#
#  1. PAS DE POLICE VARIABLE. Google Fonts sert par défaut un seul
#     fichier variable pour toutes les graisses d'une famille. Il
#     s'affiche parfaitement dans la fenêtre — et le Chrome sans
#     fenêtre qui fabrique le PDF ne l'incorpore PAS : le premier PDF
#     d'essai ne contenait qu'une police sur deux, tout le texte en
#     Hanken sortait en police de secours, et rien ne le signalait.
#     Il faut donc des instances STATIQUES, une par graisse, obtenues
#     en demandant la feuille de style avec l'agent d'un vieux Chrome
#     (Chrome/50), qui ne sait pas lire les polices variables.
#
#  2. DU base64 ET PAS UN url(). Une URL data: est disponible en même
#     temps que la feuille de style ; un fichier, lui, se charge, et
#     rien ne garantit qu'il arrive avant que Chrome imprime.
#
#  Vérifier après toute modification : le PDF doit contenir CINQ
#  polices incorporées (/FontFile2), pas une.
#
#    .\scripts\generer-polices.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$dossier = Join-Path (Split-Path $PSScriptRoot -Parent) 'badges'
$source  = Join-Path $dossier 'polices'

#  Les trois familles de la charte, aux rôles stricts : Playfair pour le
#  titre, Petit Formal Script pour la note de grâce — une par badge, pas
#  deux — et Hanken Grotesk pour tout le reste.
$familles = @(
  @{ fichier = 'playfairdisplay-700.woff2';   nom = 'Playfair Display';    poids = '700' },
  @{ fichier = 'petitformalscript-400.woff2'; nom = 'Petit Formal Script'; poids = '400' },
  @{ fichier = 'hankengrotesk-400.woff2';     nom = 'Hanken Grotesk';      poids = '400' },
  @{ fichier = 'hankengrotesk-500.woff2';     nom = 'Hanken Grotesk';      poids = '500' },
  @{ fichier = 'hankengrotesk-600.woff2';     nom = 'Hanken Grotesk';      poids = '600' },
  @{ fichier = 'hankengrotesk-700.woff2';     nom = 'Hanken Grotesk';      poids = '700' }
)

$b = New-Object System.Text.StringBuilder
[void]$b.AppendLine(@'
/* =====================================================================
   polices.css — GENERE, ne pas editer a la main.
   Produit par scripts\generer-polices.ps1 a partir de badges\polices\.

   Instances STATIQUES encastrees en base64. Ni l'un ni l'autre n'est du
   confort : un Chrome sans fenetre n'incorpore pas une police variable
   dans un PDF, et n'attend pas un fichier de police. Lire l'en-tete du
   script avant d'y toucher, les deux pieges sont invisibles a l'ecran.

   Playfair Display et Hanken Grotesk, licence SIL Open Font License 1.1
   (https://scripts.sil.org/OFL). Sous-ensemble latin de base.
   ===================================================================== */
'@)

foreach ($f in $familles) {
  $chemin = Join-Path $source $f.fichier
  if (-not (Test-Path $chemin)) { throw "Police introuvable : $chemin" }
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($chemin))
  [void]$b.AppendLine('')
  [void]$b.AppendLine('@font-face{')
  [void]$b.AppendLine(('  font-family:"{0}";' -f $f.nom))
  [void]$b.AppendLine(('  src:url(data:font/woff2;base64,{0}) format("woff2");' -f $b64))
  [void]$b.AppendLine(('  font-weight:{0}; font-style:normal; font-display:block;' -f $f.poids))
  [void]$b.AppendLine('}')
}

$sortie = Join-Path $dossier 'polices.css'
[IO.File]::WriteAllText($sortie, $b.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("  polices.css ecrit : {0} Ko, {1} familles" -f [math]::Round((Get-Item $sortie).Length / 1KB), $familles.Count)
