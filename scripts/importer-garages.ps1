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

# =====================================================================
#  ACCENTS
#  Le fichier source n'en contient aucun. On ne devine JAMAIS sur un
#  patronyme : seuls entrent ici des mots dont l'orthographe accentuée ne
#  fait aucun doute, et des expressions vérifiées dans les données.
#
#  Le piège qui justifie les deux niveaux : CERE donne « Cère » à
#  Vic-sur-Cère et Arpajon-sur-Cère (Cantal, la rivière), mais « Céré » à
#  Saint-Céré (Lot). Une règle au mot seul en aurait écorché un des deux.
# =====================================================================

# Niveau 1 — expressions entières, appliquées avant les mots isolés.
$EXPRESSIONS = [ordered]@{
  'Vic sur Cere'      = 'Vic-sur-Cère'
  'Arpajon sur Cere'  = 'Arpajon-sur-Cère'
  # avec ET sans tiret : la mise en forme transforme « ST CERE » en
  # « Saint-Cere » avant que les accents soient appliqués
  'Saint-Cere'        = 'Saint-Céré'
  'Saint Cere'        = 'Saint-Céré'
  'de la Cere'        = 'de la Cère'
}

# Niveau 2 — mots isolés dont l'accentuation est certaine, quel que soit
# le contexte. Aucun nom de famille, aucun mot tronqué.
$ACCENTS = @{
  # noms communs
  'republique'   = 'République';   'mecanique'  = 'Mécanique'
  'meca'         = 'Méca';         'vehicule'   = 'Véhicule'
  'vehicules'    = 'Véhicules';    'equipement' = 'Équipement'
  'equipements'  = 'Équipements';  'electrique' = 'Électrique'
  'electricite'  = 'Électricité';  'electro'    = 'Électro'
  'electronique' = 'Électronique'; 'general'    = 'Général'
  'generale'     = 'Générale';     'reparation' = 'Réparation'
  'reparations'  = 'Réparations';  'depannage'  = 'Dépannage'
  'securite'     = 'Sécurité';     'qualite'    = 'Qualité'
  'specialiste'  = 'Spécialiste';  'freres'     = 'Frères'
  'eglise'       = 'Église';       'chateau'    = 'Château'
  'pres'         = 'près';         'foret'      = 'Forêt'
  'cevennes'     = 'Cévennes';     'vallee'     = 'Vallée'
  'riviere'      = 'Rivière';      'rivieres'   = 'Rivières'
  'depot'        = 'Dépôt';        'echappement'= 'Échappement'
  'revision'     = 'Révision';     'renovation' = 'Rénovation'
  'esthetique'   = 'Esthétique';   'numero'     = 'Numéro'
  'reseau'       = 'Réseau';       'proximite'  = 'Proximité'
  'marechal'     = 'Maréchal';     'etoile'     = 'Étoile'
  'ideal'        = 'Idéal';        'clee'       = 'Clé'
  # toponymes certains
  'aubiere'      = 'Aubière';      'chamalieres'= 'Chamalières'
  'severac'      = 'Sévérac';      'chely'      = 'Chély'
  'geniez'       = 'Géniez';       'perignat'   = 'Pérignat'
  'sarlieve'     = 'Sarliève';     'vezie'      = 'Vézie'
  'truyere'      = 'Truyère';      'neuveglise' = 'Neuvéglise'
  'courpiere'    = 'Courpière';    'montlucon'  = 'Montluçon'
  'pourcain'     = 'Pourçain';     'cerilly'    = 'Cérilly'
  'allegre'      = 'Allègre';      'decazeville'= 'Décazeville'
  'requista'     = 'Réquista';     'realmont'   = 'Réalmont'
  'valderies'    = 'Valdériès';    'monesties'  = 'Monestiés'
  'eloy'         = 'Éloy'
}

# =====================================================================
#  COMMUNES : reconstitution des libellés coupés par l'export
#
#  L'export tronque la colonne commune à 20 caractères. Un nom de commune
#  est une donnée publique et le code postal lève l'ambiguïté, donc on
#  reconstitue — contrairement aux raisons sociales, qu'on ne touche pas :
#  le nom qu'un garagiste s'est choisi ne s'invente pas.
#
#  La clé est « CP|libellé brut » : la correction ne peut donc s'appliquer
#  qu'au cas exact prévu, jamais par ricochet sur une autre ligne.
#  Chaque entrée est vérifiable à l'œil, code postal en main.
# =====================================================================
$COMMUNES = @{
  '03160|BOURBON L ARCHAMBAUL' = "Bourbon-l'Archambault"
  '03250|LE MAYET DE MONTAGNE' = 'Le Mayet-de-Montagne'
  '03260|ST GERMAIN DES FOSSE' = 'Saint-Germain-des-Fossés'
  '03290|DOMPIERRE SUR BESBRE' = 'Dompierre-sur-Besbre'
  '03500|ST POURCAIN SUR SIOU' = 'Saint-Pourçain-sur-Sioule'
  '03700|BELLERIVE SUR ALLIER' = 'Bellerive-sur-Allier'
  '07310|ST MARTIN DE VALAMAS' = 'Saint-Martin-de-Valamas'
  '12100|ST GEORGES DE LUZENC' = 'Saint-Georges-de-Luzençon'
  '12130|ST GENIEZ D OLT ET D' = "Saint-Geniez-d'Olt-et-d'Aubrac"
  '12200|VILLEFRANCHE DE ROUE' = 'Villefranche-de-Rouergue'
  '12230|L HOSPITALET DU LARZ' = "L'Hospitalet-du-Larzac"
  '12250|ROQUEFORT SUR SOULZO' = 'Roquefort-sur-Soulzon'
  '12310|LAISSAC SEVERAC L EG' = "Laissac-Sévérac-l'Église"
  '12330|ST CHRISTOPHE VALLON' = 'Saint-Christophe-Vallon'
  '12430|VILLEFRANCHE DE PANA' = 'Villefranche-de-Panat'
  '12440|LA SALVETAT PEYRALES' = 'La Salvetat-Peyralès'
  '12490|SAINT ROME DE CERNON' = 'Saint-Rome-de-Cernon'
  '12800|SAUVETERRE DE ROUERG' = 'Sauveterre-de-Rouergue'
  '15130|LAFEUILLADE EN VEZIE' = 'Lafeuillade-en-Vézie'
  '15170|NEUSSARGUES EN PINAT' = 'Neussargues en Pinatelle'
  '15220|ST MAMET LA SALVETAT' = 'Saint-Mamet-la-Salvetat'
  '15260|NEUVEGLISE SUR TRUYE' = 'Neuvéglise-sur-Truyère'
  '15270|CHAMPS SUR TARENTAIN' = 'Champs-sur-Tarentaine-Marchal'
  '19400|ARGENTAT SUR DORDOGN' = 'Argentat-sur-Dordogne'
  '30940|ST ANDRE DE VALBORGN' = 'Saint-André-de-Valborgne'
  '34520|ST PIERRE DE LA FAGE' = 'Saint-Pierre-de-la-Fage'
  '43000|LE PUY EN VELAY CEDE' = 'Le Puy-en-Velay'
  '43130|ST ANDRE DE CHALENCO' = 'Saint-André-de-Chalencon'
  '43140|SAINT VICTOR MALESCO' = 'Saint-Victor-Malescours'
  '43150|LE MONASTIER SUR GAZ' = 'Le Monastier-sur-Gazeille'
  "43230|SAINT GEORGES D'AURA" = "Saint-Georges-d'Aurac"
  '43260|ST ETIENNE LARDEYROL' = 'Saint-Étienne-Lardeyrol'
  '43360|BOURNONCLE ST PIERRE' = 'Bournoncle-Saint-Pierre'
  '43370|ST CHRISTOPHE SUR DO' = 'Saint-Christophe-sur-Dolaison'
  '43400|LE CHAMBON SUR LIGNO' = 'Le Chambon-sur-Lignon'
  '43410|LEMPDES SUR ALLAGNON' = 'Lempdes-sur-Allagnon'
  '46190|SOUSCEYRAC EN QUERCY' = 'Sousceyrac-en-Quercy'
  '46400|ST MEDARD DE PRESQUE' = 'Saint-Médard-de-Presque'
  '46400|ST LAURENT LES TOURS' = 'Saint-Laurent-les-Tours'
  '48110|STE CROIX VALLEE FRA' = 'Sainte-Croix-Vallée-Française'
  '48120|ST ALBAN SUR LIMAGNO' = 'Saint-Alban-sur-Limagnole'
  '48170|CHATEAUNEUF DE RANDO' = 'Châteauneuf-de-Randon'
  '48190|MONT LOZERE ET GOULE' = 'Mont Lozère et Goulet'
  '48220|PONT DE MONTVERT SUD' = 'Pont de Montvert - Sud Mont Lozère'
  '48250|LA BASTIDE PUYLAUREN' = 'La Bastide-Puylaurent'
  '48400|FLORAC TROIS RIVIERE' = 'Florac-Trois-Rivières'
  '48500|MASSEGROS CAUSSES GO' = 'Massegros Causses Gorges'
  '63100|CLERMONT FERRAND CED' = 'Clermont-Ferrand'
  '63122|ST GENES CHAMPANELLE' = 'Saint-Genès-Champanelle'
  '63170|PERIGNAT LES SARLIEV' = 'Pérignat-lès-Sarliève'
  '63210|ST BONNET PRES ORCIV' = 'Saint-Bonnet-près-Orcival'
  '63310|ST CLEMENT DE REGNAT' = 'Saint-Clément-de-Régnat'
  '63330|ST MAURICE PRES PION' = 'Saint-Maurice-près-Pionsat'
  '63340|CHARBONNIER LES MINE' = 'Charbonnier-les-Mines'
  '63380|CONDAT EN COMBRAILLE' = 'Condat-en-Combraille'
  '63390|ST GERVAIS D AUVERGN' = "Saint-Gervais-d'Auvergne"
  '63410|CHARBONNIERES-LES-VA' = 'Charbonnières-les-Varennes'
  '63430|LES MARTRES D ARTIER' = "Les Martres-d'Artière"
  '63500|SAUVAGNAT STE MARTHE' = 'Sauvagnat-Sainte-Marthe'
  '63610|BESSE ET ST ANASTAIS' = 'Besse-et-Saint-Anastaise'
  '63650|LA MONNERIE LE MONTE' = 'La Monnerie-le-Montel'
  '63660|ST CLEMENT DE VALORG' = 'Saint-Clément-de-Valorgue'
  '63730|LES MARTRES DE VEYRE' = 'Les Martres-de-Veyre'
  '63820|ST JULIEN PUY LAVEZE' = 'Saint-Julien-Puy-Lavèze'
  '63850|EGLISENEUVE D ENTRAI' = "Égliseneuve-d'Entraigues"
  '63950|ST SAUVES D AUVERGNE' = "Saint-Sauves-d'Auvergne"
  '81140|CASTELNAU DE MONTMIR' = 'Castelnau-de-Montmiral'
  '81190|MIRANDOL BOURGNOUNAC' = 'Mirandol-Bourgnounac'
  '81370|ST SULPICE LA POINTE' = 'Saint-Sulpice-la-Pointe'
  '81400|ST BENOIT DE CARMAUX' = 'Saint-Benoît-de-Carmaux'
  '81430|VILLEFRANCHE D ALBIG' = "Villefranche-d'Albigeois"
  '82140|ST ANTONIN NOBLE VAL' = 'Saint-Antonin-Noble-Val'
  # '15310|SAINT SULPICE L APOI' : NON IDENTIFIÉE avec certitude, laissée
  # telle quelle plutôt que devinée. À vérifier avec Bony.
}

# ---------------------------------------------------------------------
#  UNIFICATION : une commune, une seule orthographe
#
#  Deux sources de divergence. D'abord mes propres corrections : en
#  réparant « LE PUY EN VELAY CEDE » en « Le Puy-en-Velay », je laissais
#  ses voisines intactes écrites « Le Puy en Velay » — deux orthographes
#  pour la même ville. Ensuite la source elle-même, qui contient déjà
#  « ST LAURENT D OLT » et « ST LAURENT D'OLT ».
#
#  Cette table est indexée sur le nom réduit (minuscules, ponctuation
#  ramenée à des espaces), donc elle rattrape toutes les variantes d'un
#  coup et fonctionne quel que soit le code postal.
# ---------------------------------------------------------------------
$UNIFIEES = @{
  'clermont ferrand'    = 'Clermont-Ferrand'
  'le puy en velay'     = 'Le Puy-en-Velay'
  'saint laurent d olt' = "Saint-Laurent-d'Olt"
  'severac d aveyron'   = "Sévérac-d'Aveyron"
}

function Reduire([string]$t) {
  if (-not $t) { return '' }
  $s = $t.ToLower()
  $s = $s -replace "[-'’./&,()]+", ' '
  $s = ($s -replace '\s+', ' ').Trim()
  # les accents ne doivent pas empêcher la correspondance
  return $s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
}

function Unifier([string]$ville) {
  $k = Reduire $ville
  if ($UNIFIEES.ContainsKey($k)) { return $UNIFIEES[$k] }
  return $ville
}

function Accentuer([string]$t) {
  if (-not $t) { return '' }
  foreach ($e in $EXPRESSIONS.GetEnumerator()) {
    $t = [regex]::Replace($t, [regex]::Escape($e.Key), $e.Value, 'IgnoreCase')
  }
  foreach ($m in $ACCENTS.GetEnumerator()) {
    $t = [regex]::Replace($t, '\b' + [regex]::Escape($m.Key) + '\b', $m.Value, 'IgnoreCase')
  }
  return $t
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
  return (Accentuer $r)
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
$script:corrigees = 0
foreach ($g in $brut) {
  $nom = Propre $g.raison $false
  if (-not $nom) { $nom = Propre $g.raison $true }   # filet : nom vidé par le nettoyage

  $v = 0
  $code = CodeDe $g.compte $v
  while ($pris.ContainsKey($code)) { $v++; $collisions++; $code = CodeDe $g.compte $v }
  $pris[$code] = $g.compte

  # La table des communes prime sur la mise en forme automatique : elle
  # porte le libellé officiel, tirets et accents compris.
  $cle = ($g.cp + '|' + ($g.commune -replace '\s+', ' ').Trim())
  $ville = if ($COMMUNES.ContainsKey($cle)) { $COMMUNES[$cle] } else { Propre $g.commune $true }
  if ($COMMUNES.ContainsKey($cle)) { $script:corrigees++ }
  $ville = Unifier $ville      # une commune, une seule orthographe

  $propre.Add([pscustomobject]@{
    compte = $g.compte; ref = $g.id
    nom = $nom
    ville = $ville
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
