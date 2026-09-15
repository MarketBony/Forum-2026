#requires -Version 5
# =====================================================================
#  serveur-badges.ps1 — le petit moteur local du générateur de badges.
#
#  Il sert le dossier badges\ ET rend trois services que la page, seule
#  dans son navigateur, ne peut pas rendre :
#
#    GET  /marques.json    ce qui a déjà été exporte en PDF
#    PUT  /marques.json    l'enregistre sur le disque
#    POST /exporter        fabrique les PDF et dit où ils sont
#    GET  /export-etat     l'avancement de l'export en cours
#    POST /ouvrir          ouvre un dossier dans l'Explorateur
#
#  QUI PORTE UN BADGE VIENT DE LA BASE, PAS D'ICI. Le générateur lit
#  participants.json, produit par exporter-badges.ps1. La seule chose
#  que ce serveur retient en propre, c'est marques.json : ce qui a
#  déjà été imprimé. Une information locale sur du papier, qui n'a
#  rien à faire dans la base du Forum et se reconstruit en une
#  impression si on la perd.
#
#  POURQUOI L'EXPORT PART EN TÂCHE DE FOND. HttpListener traite une
#  requête à la fois. Si l'export bloquait ici, la page ne pourrait
#  plus rien demander — pas même l'avancement. La tâche écrit donc sa
#  progression dans _export-etat.json, que la page interroge.
#
#    .\scripts\serveur-badges.ps1 -Port 8124
# =====================================================================
param([int]$Port = 8124)

$ErrorActionPreference = 'Stop'

$racine  = (Resolve-Path (Join-Path $PSScriptRoot '..\badges')).Path
$etatExp = Join-Path $racine '_export-etat.json'
$sortie  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Badges Forum 2026'

$types = @{
  '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'
  '.js'='text/javascript; charset=utf-8'; '.json'='application/json; charset=utf-8'
  '.svg'='image/svg+xml'; '.ico'='image/x-icon'; '.png'='image/png'
  '.woff2'='font/woff2'; '.txt'='text/plain; charset=utf-8'; '.pdf'='application/pdf'
}

function Utf8($t) { [Text.Encoding]::UTF8.GetBytes($t) }

function EcrireSansBom($chemin, $texte) {
  [IO.File]::WriteAllText($chemin, $texte, (New-Object Text.UTF8Encoding($false)))
}

# --- Où est Chrome ? --------------------------------------------------
# Le même que celui qui affiche la fenêtre. Edge fait le travail aussi
# bien : c'est le même moteur d'impression.
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
$chrome = TrouverChrome

$ecouteur = New-Object System.Net.HttpListener
$ecouteur.Prefixes.Add("http://localhost:$Port/")
try { $ecouteur.Start() } catch {
  Write-Output "Impossible d'ouvrir le port $Port : $($_.Exception.Message)"; exit 1
}

Write-Output "Generateur de badges -> http://localhost:$Port/"
Write-Output "Dossier servi        -> $racine"
Write-Output "Chrome               -> $(if ($chrome) { $chrome } else { 'INTROUVABLE — export PDF indisponible' })"
Write-Output "PDF ecrits dans      -> $sortie"

while ($ecouteur.IsListening) {
  $ctx = $ecouteur.GetContext()
  $req = $ctx.Request
  $rep = $ctx.Response
  $chemin = [Uri]::UnescapeDataString($req.Url.AbsolutePath)
  try {

    # ---------------------------------------------------------------
    #  PUT /liste.json — la page enregistre son travail
    # ---------------------------------------------------------------
    if ($req.HttpMethod -eq 'PUT' -and $chemin -eq '/marques.json') {
      $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
      $corps = $sr.ReadToEnd(); $sr.Close()
      # Garde-fou : on n'écrase un travail existant qu'avec du JSON valide.
      $null = $corps | ConvertFrom-Json
      EcrireSansBom (Join-Path $racine 'marques.json') $corps
      $rep.ContentType = 'application/json; charset=utf-8'
      $o = Utf8 '{"ok":true}'; $rep.OutputStream.Write($o, 0, $o.Length); $rep.StatusCode = 200
    }

    # ---------------------------------------------------------------
    #  POST /exporter — fabrique les PDF
    # ---------------------------------------------------------------
    elseif ($req.HttpMethod -eq 'POST' -and $chemin -eq '/exporter') {
      if (-not $chrome) { throw "Chrome introuvable : impossible de fabriquer un PDF." }
      $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
      $corps = $sr.ReadToEnd(); $sr.Close()
      $demande = $corps | ConvertFrom-Json

      # Les pages HTML complètes arrivent déjà fabriquées par le
      # navigateur — lui seul sait dessiner un badge. On les pose dans
      # badges\ pour que ./badges.css et ./polices/ tombent juste, puis
      # Chrome les imprime en file://. Aucun aller-retour par le
      # serveur pendant le rendu : pas de blocage possible.
      $travail = Join-Path $racine '_impression'
      if (Test-Path $travail) { Remove-Item $travail -Recurse -Force }
      New-Item -ItemType Directory -Force $travail | Out-Null
      if (-not (Test-Path $sortie)) { New-Item -ItemType Directory -Force $sortie | Out-Null }

      $fichiers = @()
      $i = 0
      foreach ($f in $demande.fichiers) {
        $i++
        # Le nom vient de la page : on le réduit à ce qui ne peut pas
        # sortir du dossier de sortie. La page le nettoie déjà, mais un
        # nom de fichier construit ailleurs ne se fait jamais confiance.
        $nom = ($f.nom -replace '[^A-Za-z0-9._-]', '-')
        if (-not $nom) { $nom = "badges-$i" }
        $h = Join-Path $travail ("lot{0:D3}.html" -f $i)
        EcrireSansBom $h $f.html
        $fichiers += [pscustomobject]@{ html = $h; pdf = (Join-Path $sortie ($nom + '.pdf')); nom = $nom }
      }

      EcrireSansBom $etatExp (ConvertTo-Json ([ordered]@{
        etat = 'encours'; fait = 0; total = $fichiers.Count; dossier = $sortie; fichiers = @()
      }) -Compress)

      # PIÈGE DÉJÀ PAYÉ. Ne PAS passer la liste des lots par
      # -ArgumentList : PowerShell aplatit un tableau de tableaux, la
      # tâche recevait trois chaînes au lieu d'un lot et itérait sur
      # leurs caractères — elle produisait des fichiers nommés « \ » et
      # « d ». On écrit la liste dans un fichier, on passe un chemin.
      $liste = Join-Path $travail 'lots.json'
      EcrireSansBom $liste (ConvertTo-Json @($fichiers | ForEach-Object {
        [ordered]@{ html = $_.html; pdf = $_.pdf; nom = $_.nom } }) -Depth 4)

      # Tâche de fond : le serveur doit rester disponible pour répondre
      # à /export-etat pendant que Chrome travaille.
      $null = Start-Job -ArgumentList $chrome, $liste, $etatExp, $sortie, $travail -ScriptBlock {
        param($chrome, $liste, $etatExp, $sortie, $travail)
        function Ecrire($c, $t) { [IO.File]::WriteAllText($c, $t, (New-Object Text.UTF8Encoding($false))) }
        # PIÈGE DÉJÀ PAYÉ, ET IL NE SE VOIT QU'À PARTIR DE DEUX LOTS.
        # En PowerShell 5.1, ConvertFrom-Json émet un tableau comme UN
        # SEUL objet, sans l'énumérer. Écrire `$lots = @(... |
        # ConvertFrom-Json)` l'emballe donc dans un tableau à un élément :
        # la boucle ne tournait qu'une fois, $l.nom rendait les douze noms
        # d'un coup, et « -f » n'en gardait que le premier. Un seul PDF
        # était écrit, et l'interface en annonçait un. Avec un seul lot,
        # le bug se compensait tout seul — d'où l'illusion.
        # Assigner SANS @(), et compter avec @() au moment de compter.
        $lots = Get-Content $liste -Raw -Encoding UTF8 | ConvertFrom-Json
        $total = @($lots).Count
        $profil = Join-Path $env:TEMP 'bony-badges-impression'
        $faits = @(); $n = 0
        foreach ($l in $lots) {
          $n++
          if (Test-Path $l.pdf) { Remove-Item $l.pdf -Force }
          # $args est une variable automatique : la réutiliser enverrait
          # un corps vide. On la nomme autrement.
          $ligne = @(
            '--headless=new', '--disable-gpu', '--no-sandbox',
            '--no-pdf-header-footer',
            # Chrome imprime dès que la page est stable ; ce budget de
            # temps virtuel lui laisse charger les polices locales et
            # dessiner les feuilles avant de déclencher l'impression.
            '--virtual-time-budget=60000',
            ('--user-data-dir="{0}"' -f $profil),
            ('--print-to-pdf="{0}"' -f $l.pdf),
            ('"file:///{0}"' -f ($l.html -replace '\\', '/'))
          ) -join ' '
          # -Wait plutôt que -PassThru puis WaitForExit() : selon la
          # façon dont Chrome se lance, -PassThru peut rendre $null, et
          # l'appel de méthode sur $null tuerait la tâche en silence.
          Start-Process $chrome -ArgumentList $ligne -Wait -WindowStyle Hidden
          $ok = (Test-Path $l.pdf) -and ((Get-Item $l.pdf).Length -gt 1000)
          $faits += [ordered]@{ nom = $l.nom; ok = $ok
                                octets = $(if ($ok) { (Get-Item $l.pdf).Length } else { 0 }) }
          Ecrire $etatExp (ConvertTo-Json ([ordered]@{
            etat = 'encours'; fait = $n; total = $total; dossier = $sortie; fichiers = @($faits)
          }) -Depth 4 -Compress)
        }
        Ecrire $etatExp (ConvertTo-Json ([ordered]@{
          etat = 'fini'; fait = $n; total = $total; dossier = $sortie; fichiers = @($faits)
        }) -Depth 4 -Compress)
        try { Remove-Item $travail -Recurse -Force } catch {}
      }

      $rep.ContentType = 'application/json; charset=utf-8'
      $o = Utf8 (ConvertTo-Json @{ ok = $true; total = $fichiers.Count; dossier = $sortie } -Compress)
      $rep.OutputStream.Write($o, 0, $o.Length); $rep.StatusCode = 202
    }

    # ---------------------------------------------------------------
    #  POST /ouvrir — montrer les PDF à l'utilisateur
    # ---------------------------------------------------------------
    elseif ($req.HttpMethod -eq 'POST' -and $chemin -eq '/ouvrir') {
      if (Test-Path $sortie) { Start-Process explorer.exe $sortie }
      $rep.ContentType = 'application/json; charset=utf-8'
      $o = Utf8 '{"ok":true}'; $rep.OutputStream.Write($o, 0, $o.Length); $rep.StatusCode = 200
    }

    # ---------------------------------------------------------------
    #  GET — fichiers statiques, avec deux cas particuliers
    # ---------------------------------------------------------------
    else {
      if ($chemin -eq '/' -or $chemin.EndsWith('/')) { $chemin += 'index.html' }
      if ($chemin -eq '/export-etat') { $chemin = '/_export-etat.json' }

      $cible = [IO.Path]::GetFullPath((Join-Path $racine $chemin.TrimStart('/')))
      if (-not $cible.StartsWith($racine, [StringComparison]::OrdinalIgnoreCase)) {
        $rep.StatusCode = 403
      } elseif (Test-Path $cible -PathType Leaf) {
        $ext = [IO.Path]::GetExtension($cible).ToLower()
        $rep.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' })
        $rep.Headers['Cache-Control'] = 'no-store'
        $o = [IO.File]::ReadAllBytes($cible)
        $rep.ContentLength64 = $o.Length
        $rep.OutputStream.Write($o, 0, $o.Length); $rep.StatusCode = 200
      } elseif ($chemin -eq '/marques.json') {
        # Premier lancement : rien n'a encore ete imprime, ce n'est pas une
        # erreur. UN OBJET, PAS UN TABLEAU : marques.json associe un
        # identifiant a une date. Rendre '[]' faisait de MARQUES un tableau
        # cote page, et JSON.stringify d'un tableau JETTE les proprietes
        # nommees — les marques d'export repartaient vides sans un mot.
        $rep.ContentType = 'application/json; charset=utf-8'
        $o = Utf8 '{}'; $rep.OutputStream.Write($o, 0, $o.Length); $rep.StatusCode = 200
      } else {
        $rep.StatusCode = 404
        $o = Utf8 '404'; $rep.OutputStream.Write($o, 0, $o.Length)
      }
    }

    Write-Output ("{0,-5} {1} {2}" -f $req.HttpMethod, $rep.StatusCode, $chemin)

  } catch {
    try {
      $rep.StatusCode = 500
      $rep.ContentType = 'application/json; charset=utf-8'
      $o = Utf8 (ConvertTo-Json @{ erreur = $_.Exception.Message } -Compress)
      $rep.OutputStream.Write($o, 0, $o.Length)
    } catch {}
    Write-Output ("ERR   " + $chemin + " : " + $_.Exception.Message)
  } finally {
    try { $rep.OutputStream.Close() } catch {}
  }
}
