#requires -Version 5
# =====================================================================
#  badges.ps1 — LE GÉNÉRATEUR DE BADGES, lancé par son icône.
#
#  Personne n'est censé taper cette commande : elle est là pour être
#  appelée par le raccourci « Badges — Forum 2026 » posé sur le Bureau
#  (voir creer-raccourci.ps1). Elle enchaîne quatre choses :
#
#    1. rafraîchit badges\garages.json et badges\personnel.json depuis
#       LA BASE, et note dans _etat.json si ça s'est bien passé ;
#    2. démarre un serveur local sur le dossier badges\, sans fenêtre ;
#    3. ouvre le navigateur en MODE APPLICATION — une fenêtre nue, sans
#       barre d'adresse ni onglets ;
#    4. attend que cette fenêtre se ferme, puis arrête le serveur.
#
#  POURQUOI UN SERVEUR PLUTÔT QU'UN DOUBLE-CLIC SUR LE .HTML. En
#  file://, fetch() refuse de lire garages.json : la page s'ouvrirait
#  vide, sans erreur compréhensible.
#
#  POURQUOI UN PROFIL DE NAVIGATEUR DÉDIÉ. Sans --user-data-dir, Chrome
#  confie l'ouverture à l'instance déjà lancée et rend la main tout de
#  suite : on n'aurait plus rien à attendre, et le serveur resterait en
#  vie indéfiniment. Le profil dédié donne une vraie fenêtre à nous.
#  CONSÉQUENCE À CONNAÎTRE : les badges saisis vivent dans le stockage
#  de CE profil. Ouvrir http://localhost:8124 dans le Chrome habituel
#  montrerait une liste vide. C'est pour ça que le bouton
#  « Sauvegarder » de la page reste la seule vraie protection.
#
#  RIEN NE DOIT ÉCHOUER EN SILENCE. La fenêtre étant cachée, toute
#  panne est affichée dans une vraie boîte de dialogue et écrite dans
#  badges\_journal-lancement.txt.
#
#    -Visible      garde la console ouverte (diagnostic)
#    -SansExport   n'interroge pas la base (hors connexion)
# =====================================================================
param([int]$Port = 8124, [switch]$SansExport, [switch]$Visible)

$ErrorActionPreference = 'Stop'

$racine  = Split-Path $PSScriptRoot -Parent
$dossier = Join-Path $racine 'badges'
$journal = Join-Path $dossier '_journal-lancement.txt'
$profil  = Join-Path $env:LOCALAPPDATA 'Bony-Badges-2026\navigateur'

function Noter($m) {
  $l = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
  try { Add-Content -Path $journal -Value $l -Encoding UTF8 } catch {}
  if ($Visible) { Write-Output $l }
}

function Alerte($texte) {
  Noter ("ALERTE : " + $texte)
  try {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
      $texte, 'Générateur de badges', 'OK', 'Error') | Out-Null
  } catch {}
}

# Le journal ne doit pas gonfler indéfiniment : on garde les 200
# dernières lignes, de quoi couvrir largement une semaine de lancements.
try {
  if (Test-Path $journal) {
    $l = @(Get-Content $journal -Encoding UTF8)
    if ($l.Count -gt 200) { $l[-200..-1] | Set-Content $journal -Encoding UTF8 }
  }
} catch {}

Noter "--- lancement ---"

try {

  # --- 1. Les données -------------------------------------------------
  $etat = [ordered]@{
    quand   = (Get-Date).ToString('s')
    export  = 'saute'
    message = ''
  }
  if (-not $SansExport) {
    try {
      & (Join-Path $PSScriptRoot 'exporter-badges.ps1') | ForEach-Object { Noter $_ }
      $etat.export = 'ok'
      Noter 'export : OK'
    } catch {
      # Une base injoignable n'empêche pas de travailler : les fichiers
      # de la fois précédente sont toujours là. On le DIT dans la page
      # plutôt que de laisser croire que les codes sont à jour.
      $etat.export  = 'echec'
      $etat.message = $_.Exception.Message
      Noter ("export : ECHEC — " + $_.Exception.Message)
    }
  }
  try {
    [System.IO.File]::WriteAllText(
      (Join-Path $dossier '_etat.json'),
      (ConvertTo-Json $etat -Compress),
      (New-Object System.Text.UTF8Encoding($false)))
  } catch {}

  # participants.json est TOUT ce que le générateur lit. Sans lui, la
  # page s'ouvrirait vide : mieux vaut une vraie boîte de dialogue.
  if (-not (Test-Path (Join-Path $dossier 'participants.json'))) {
    Alerte ("Les donnees des badges sont absentes et la base n'a pas repondu." +
            "`n`n" + $etat.message +
            "`n`nVerifie la connexion, puis relance l'icone.")
    exit 1
  }

  # --- 2. Le serveur --------------------------------------------------
  # Déjà en écoute ? C'est un deuxième double-clic : on réutilise.
  $dejaLa = $false
  try {
    $t = New-Object System.Net.Sockets.TcpClient
    if ($t.ConnectAsync('127.0.0.1', $Port).Wait(400)) { $dejaLa = $true }
    $t.Close()
  } catch {}

  $serveur = $null
  if ($dejaLa) {
    # Le générateur tourne déjà : c'est un deuxième double-clic, parce
    # que la première fois « il ne s'est rien passé » pendant deux
    # secondes. On ramène la fenêtre existante au premier plan au lieu
    # d'en ouvrir une seconde — sinon les deux fenêtres partagent un
    # serveur qui appartient au premier lanceur, et fermer celle-là
    # casserait celle-ci.
    Noter "serveur : deja en ecoute sur $Port, on remonte la fenetre existante"
    Add-Type -Namespace Fen -Name Api -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);
'@
    $vue = $false
    foreach ($c in @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
                     Where-Object { $_.CommandLine -like '*Bony-Badges-2026*' })) {
      $pr = Get-Process -Id $c.ProcessId -ErrorAction SilentlyContinue
      if ($pr -and $pr.MainWindowHandle -ne 0) {
        [Fen.Api]::ShowWindowAsync($pr.MainWindowHandle, 9) | Out-Null   # 9 = restaurer
        [Fen.Api]::SetForegroundWindow($pr.MainWindowHandle) | Out-Null
        $vue = $true; break
      }
    }
    if (-not $vue) { Noter 'fenetre existante introuvable, on ouvre quand meme' }
    else { Noter '--- fin (fenetre existante remontee) ---'; exit 0 }
  }
  if (-not $dejaLa) {
    # PIÈGE DÉJÀ PAYÉ. -ArgumentList sous forme de TABLEAU recolle les
    # éléments avec des espaces et n'ajoute aucun guillemet : le chemin
    # « ...\APP FORUM\scripts\serveur.ps1 » se coupait sur l'espace de
    # « APP FORUM », powershell ne trouvait pas le fichier et mourait
    # sans un mot. Une seule chaîne, guillemets posés à la main.
    $cmd = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Port {1}' -f `
           (Join-Path $PSScriptRoot 'serveur-badges.ps1'), $Port
    $serveur = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList $cmd
    Noter ("serveur : demarre (PID " + $serveur.Id + ") sur $Port")

    # On attend que le port réponde vraiment. Ouvrir le navigateur avant
    # donnerait une page d'erreur que l'utilisateur prendrait pour une
    # panne de l'outil.
    $pret = $false
    for ($i = 0; $i -lt 60; $i++) {
      Start-Sleep -Milliseconds 100
      try {
        $t = New-Object System.Net.Sockets.TcpClient
        if ($t.ConnectAsync('127.0.0.1', $Port).Wait(200)) { $t.Close(); $pret = $true; break }
        $t.Close()
      } catch {}
    }
    if (-not $pret) {
      Alerte "Le serveur local n'a pas demarre sur le port $Port.`n`nUn autre programme l'occupe peut-etre."
      if ($serveur -and -not $serveur.HasExited) { Stop-Process -Id $serveur.Id -Force }
      exit 1
    }
    Noter 'serveur : pret'
  }

  # --- 3. Le navigateur, en mode application --------------------------
  function TrouverNavigateur($exe) {
    $cle = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe"
    foreach ($c in @($cle, ($cle -replace 'HKLM:', 'HKCU:'))) {
      try { $v = (Get-ItemProperty $c -ErrorAction Stop).'(default)'
            if ($v -and (Test-Path $v)) { return $v } } catch {}
    }
    foreach ($b in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
      foreach ($sous in @('Google\Chrome\Application', 'Microsoft\Edge\Application')) {
        $p = Join-Path (Join-Path $b $sous) $exe
        if (Test-Path $p) { return $p }
      }
    }
    return $null
  }

  $url = "http://localhost:$Port/"
  $nav = TrouverNavigateur 'chrome.exe'
  if (-not $nav) { $nav = TrouverNavigateur 'msedge.exe' }

  if ($nav) {
    if (-not (Test-Path $profil)) { New-Item -ItemType Directory -Force $profil | Out-Null }
    Noter ("navigateur : " + $nav)
    # Même précaution que pour le serveur : une chaîne, pas un tableau.
    # %LOCALAPPDATA% n'a pas d'espace sur ce poste, mais un profil
    # Windows nommé « Jean Dupont » en aurait un.
    $cmdNav = '--app={0} --user-data-dir="{1}" --no-first-run --no-default-browser-check ' +
              '--window-size=1500,1000 --disable-features=Translate,AutofillServerCommunication'
    $fenetre = Start-Process $nav -PassThru -ArgumentList ($cmdNav -f $url, $profil)
    Noter ("fenetre : PID " + $fenetre.Id + ", on attend sa fermeture")
    $fenetre.WaitForExit()
    Noter 'fenetre : fermee'
  } else {
    # Aucun navigateur Chromium trouvé — cas très improbable sous
    # Windows 11. On ouvre le navigateur par défaut ; comme on n'a plus
    # de processus à attendre, on prévient qu'il faudra fermer soi-même.
    Noter 'navigateur : aucun Chromium trouve, ouverture par defaut'
    Start-Process $url
    Alerte ("Le generateur est ouvert dans ton navigateur par defaut." +
            "`n`nFerme cette boite quand tu auras termine : le serveur s'arretera.")
  }

  # --- 4. Le ménage ---------------------------------------------------
  if ($serveur -and -not $serveur.HasExited) {
    Stop-Process -Id $serveur.Id -Force
    Noter 'serveur : arrete'
  }
  Noter '--- fin ---'

} catch {
  Alerte ("Le generateur n'a pas pu demarrer." + "`n`n" + $_.Exception.Message +
          "`n`nDetail dans badges\_journal-lancement.txt")
  exit 1
}
