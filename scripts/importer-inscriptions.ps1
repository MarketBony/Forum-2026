#requires -Version 5
# =====================================================================
#  importer-inscriptions.ps1 — pousse un listing d'inscrits dans la
#  table public.participants, qui alimente le générateur de badges.
#
#    .\scripts\importer-inscriptions.ps1 -Fichier "...\consolidees.xlsx"
#    .\scripts\importer-inscriptions.ps1 -Fichier "..." -Appliquer
#
#  SANS -Appliquer, IL N'ÉCRIT RIEN. Il lit, rapproche, et rend un
#  rapport. C'est délibéré : on regarde ce qu'il a compris avant de le
#  laisser toucher la base.
#
#  LE RAPPROCHEMENT, ET POURQUOI IL EST DANS CET ORDRE.
#  Le fichier consolidé du 14 septembre prouve que l'identifiant
#  d'invitation n'est pas une clé : BONY00250 a servi à trois sociétés
#  successives, et des salariés Bony se sont inscrits via le lien d'un
#  client. On rapproche donc D'ABORD sur la raison sociale, et l'ID ne
#  sert que de second recours — signalé comme tel dans le rapport.
#
#  CE QU'IL NE FAIT JAMAIS : deviner. Deux sociétés homonymes en base,
#  ou une société introuvable et ambiguë, sont listées à part. Une
#  société franchement absente reçoit un NOUVEAU garage et un code
#  généré : c'est une création, pas une supposition.
# =====================================================================
param(
  [Parameter(Mandatory = $true)][string]$Fichier,
  [string]$Feuille = 'INSCRITS_CONSOLIDES',
  # AUTO   : garage, sauf e-mail @bonyauto-mobile.com -> équipe Bony.
  #          C'est le cas du fichier d'inscriptions, qui mélange les deux.
  # EXPOSANT : tout le fichier est du personnel de stand, on rattache aux
  #            stands et pas aux garages.
  [ValidateSet('AUTO', 'EXPOSANT')][string]$Categorie = 'AUTO',
  # Deux societes homonymes en base, le script REFUSE de choisir : rien
  # dans le listing ne les departage, et attribuer a quelqu'un le code
  # d'un autre garage est la pire erreur possible. Cet interrupteur ne
  # lui fait pas deviner : il lui fait creer un TROISIEME compte, au nom
  # de l'inscrit, avec son propre code. Arbitrage de Bastien du
  # 15 septembre : « si homonyme on cree le compte de l'inscrit, et y'aura
  # un doublon dans la base au cas ou un deuxieme garage a le meme nom
  # dans un lieu different ».
  [switch]$CreerHomonymes,
  [switch]$Appliquer
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

# =====================================================================
#  Lecture du classeur
# =====================================================================

# Le fichier peut être ouvert dans Excel : on demande un partage.
function LireXlsx($chemin) {
  $fs = New-Object IO.FileStream($chemin, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  $z = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Read)
  $t = @{}
  foreach ($e in $z.Entries) {
    $sr = New-Object IO.StreamReader($e.Open(), [Text.Encoding]::UTF8)
    $t[$e.FullName] = $sr.ReadToEnd(); $sr.Close()
  }
  $z.Dispose(); $fs.Dispose(); return $t
}

function Colonnes($ref) {
  $n = 0
  foreach ($c in ($ref -replace '[0-9]', '').ToCharArray()) { $n = $n * 26 + ([int][char]$c - 64) }
  return $n - 1
}

function Lignes($t, $nomFeuille) {
  $ss = @()
  if ($t['xl/sharedStrings.xml']) {
    $x = [xml]$t['xl/sharedStrings.xml']
    foreach ($si in $x.sst.si) {
      # Une chaîne mise en forme est découpée en plusieurs <t> : il faut
      # les recoller, sinon « Carrosserie Michel » perd la moitié.
      $s = ''
      foreach ($n in $si.SelectNodes('.//*[local-name()="t"]')) { $s += $n.InnerText }
      $ss += $s
    }
  }
  $wb = [xml]$t['xl/workbook.xml']
  $i = 0; $cible = $null
  foreach ($f in $wb.workbook.sheets.sheet) {
    $i++
    if ($f.name -eq $nomFeuille) { $cible = "xl/worksheets/sheet$i.xml" }
  }
  if (-not $cible) { throw "Feuille « $nomFeuille » introuvable. Feuilles : " + (($wb.workbook.sheets.sheet | ForEach-Object { $_.name }) -join ', ') }

  $x = [xml]$t[$cible]
  $res = @()
  foreach ($row in $x.worksheet.sheetData.row) {
    $cells = @{}
    foreach ($c in $row.c) {
      # Une cellule vide n'est pas écrite : on lit la référence, jamais
      # la position dans la liste, sinon tout se décale.
      $i = Colonnes $c.r
      $v = if ($c.t -eq 's') { $ss[[int]$c.v] } elseif ($c.t -eq 'inlineStr') { $c.is.t } else { $c.v }
      if ($null -ne $v -and "$v" -ne '') { $cells[$i] = ("$v").Trim() }
    }
    if ($cells.Count) { $res += ,$cells }
  }
  return $res
}

# =====================================================================
#  Normalisation — la même des deux côtés, sinon rien ne se rapproche
# =====================================================================

function Norm($s) {
  if (-not $s) { return '' }
  $x = ([string]$s).Normalize([Text.NormalizationForm]::FormD)
  $b = New-Object Text.StringBuilder
  foreach ($ch in $x.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne 'NonSpacingMark') { [void]$b.Append($ch) }
  }
  return (($b.ToString().ToLower() -replace '[^a-z0-9]+', ' ').Trim())
}

# Formes juridiques : présentes dans ce que les gens tapent, absentes de
# la base qui a été nettoyée. « GGE » pour « Garage » vient de l'export
# Sarbacane d'origine. « ste » avant « st », sinon « ste » devient
# « saint + e » — même ordre que norm_requete() côté SQL.
$FORMES = @('sarl', 'sasu', 'sas', 'sa', 'eurl', 'sarlu', 'sci', 'snc', 'scop', 'cie')
function NormFort($s) {
  $n = Norm $s
  $n = $n -replace '\bgges\b', 'garages'
  $n = $n -replace '\bgge\b',  'garage'
  $n = $n -replace '\bste\b',  'sainte'
  $n = $n -replace '\bst\b',   'saint'
  $mots = @($n -split ' ' | Where-Object { $_ -and ($FORMES -notcontains $_) })
  return ($mots -join ' ')
}

# =====================================================================
#  Génération de code — même règle que scripts\importer-garages.ps1
# =====================================================================
#  L'alphabet exclut O, I, 0 et 1 : à la lecture d'un badge, sous les
#  néons, un O et un zéro ne se distinguent pas. Le code est dérivé du
#  nom : relancer l'import ne change JAMAIS un code déjà imprimé.
$ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
$SEL = 'grand-bal-2026'
$md5 = [Security.Cryptography.MD5]::Create()

function CodeDe($graine, $variante) {
  $o = $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("$SEL|$graine|$variante"))
  $c = ''
  for ($i = 0; $i -lt 4; $i++) { $c += $ALPHABET[$o[$i] % 32] }
  return $c
}

# =====================================================================
#  La base
# =====================================================================
function Sql($q) {
  $r = & (Join-Path $PSScriptRoot 'push-sql.ps1') -Query $q -Quiet
  if (-not $r) { return @() }
  # ConvertFrom-Json rend un tableau comme UN seul objet en PowerShell
  # 5.1 : on assigne, puis on énumère. Ne pas envelopper dans @().
  $d = $r | ConvertFrom-Json
  return $d
}

function Echap($s) { return ([string]$s).Replace("'", "''") }

Write-Output ''
Write-Output "  Lecture de $(Split-Path $Fichier -Leaf) / $Feuille"
$lignes = Lignes (LireXlsx $Fichier) $Feuille
if ($lignes.Count -lt 2) { throw 'Feuille vide.' }

# --- reconnaissance des colonnes par leur en-tête ---------------------
$tete = $lignes[0]
$col = @{}
foreach ($i in $tete.Keys) {
  switch (Norm $tete[$i]) {
    'statut'         { $col['statut'] = $i }
    'nom'            { $col['nom'] = $i }
    'prenom'         { $col['prenom'] = $i }
    'raison sociale' { $col['raison'] = $i }
    'entreprise'     { $col['raison'] = $i }
    'societe'        { $col['raison'] = $i }
    'profil'         { $col['profil'] = $i }
    'email'          { $col['email'] = $i }
    'telephone'      { $col['tel'] = $i }
    'id s'           { $col['id'] = $i }
    'forum'          { $col['forum'] = $i }
    'nb forum'       { $col['nb'] = $i }
  }
}
if ($null -eq $col['raison']) { throw "Colonne « raison sociale » (ou « entreprise ») introuvable dans l'en-tete." }
# La colonne Forum n'existe que dans le fichier d'inscriptions. Le
# listing fournisseurs n'a pas de filtre : tout le monde vient.
$filtreForum = ($null -ne $col['forum'])
Write-Output ("  Colonnes reconnues : " + (($col.Keys | Sort-Object) -join ', '))

# --- le référentiel de la base ---------------------------------------
$garages = Sql "select id, ref_bony, nom, ville, code from public.garages where actif"
$parNom = @{}; $parRef = @{}; $codesPris = @{}
foreach ($g in $garages) {
  $k = NormFort $g.nom
  if (-not $parNom.ContainsKey($k)) { $parNom[$k] = New-Object Collections.ArrayList }
  [void]$parNom[$k].Add($g)
  if ($g.ref_bony) { $parRef[$g.ref_bony.ToUpper()] = $g }
  if ($g.code) { $codesPris[$g.code.ToUpper()] = $true }
}
$pins = Sql "select code_pin as c from public.stands where actif union all select code_pin from public.animations where actif union all select valeur from public.config where cle in ('pin_accueil','pin_admin')"
foreach ($p in $pins) { if ($p.c) { $codesPris[$p.c.ToUpper()] = $true } }
Write-Output ("  Base : {0} garages actifs, {1} codes deja pris" -f @($garages).Count, $codesPris.Count)

# Les stands, pour le mode EXPOSANT. Un stand porte le PIN qui permet de
# créditer une opération : rattacher la bonne personne au bon stand,
# c'est lui donner le bon pouvoir.
$stands = @()
if ($Categorie -eq 'EXPOSANT') {
  $stands = Sql "select id, nom from public.stands where actif"
  Write-Output ("  Stands actifs : {0}" -f @($stands).Count)
}

# =====================================================================
#  Rapprochement
# =====================================================================
$rows = @(); $ecartes = 0; $doublons = @(); $reportees = 0
$nouvelles = @{}      # nom normalisé -> société à créer
$aArbitrer = @()
$homonymesCrees = @()
$vus = @{}
$derniereRaison = ''

for ($n = 1; $n -lt $lignes.Count; $n++) {
  $l = $lignes[$n]
  $val = { param($c) if ($null -eq $col[$c]) { '' } else { if ($l.ContainsKey($col[$c])) { $l[$col[$c]] } else { '' } } }

  if ($filtreForum) {
    $forum = & $val 'forum'
    if ((Norm $forum) -notlike 'oui*') { $ecartes++; continue }
  }

  # REPORT VERS LE BAS. Dans le listing fournisseurs, la colonne
  # ENTREPRISE n'est remplie que sur la première ligne d'un groupe :
  # Goodyear a trois personnes, Michelin cinq, et les lignes suivantes
  # ont la case vide. Sans ce report, neuf personnes sur quarante-huit
  # perdaient leur société.
  $raison = & $val 'raison'
  if ($raison) { $derniereRaison = $raison } elseif ($derniereRaison) { $raison = $derniereRaison; $reportees++ }
  if (-not $raison) { continue }
  $email  = (& $val 'email').ToLower()
  $prenom = & $val 'prenom'
  $nom    = & $val 'nom'
  if ($nom -eq '.') { $nom = '' }          # marqueur « pas de nom » du fichier
  $statut = & $val 'statut'
  $idBony = (& $val 'id').ToUpper()

  $nb = 1
  $nbTexte = & $val 'nb'
  if ($nbTexte) { $d = 0.0; if ([double]::TryParse(($nbTexte -replace ',', '.'), [ref]$d)) { $nb = [int]$d } }
  if ($nb -lt 1) { $nb = 1 }
  if ($nb -gt 20) { $nb = 20 }

  # La clé d'idempotence : l'e-mail quand il y en a un, il est propre à
  # la personne. Sinon la personne elle-même. Rejouer le fichier met à
  # jour au lieu de créer un second badge.
  $cle = if ($email) { "mail:$email" } else { "pers:" + (Norm "$raison $nom $prenom") }
  if ($vus.ContainsKey($cle)) { $doublons += "$prenom $nom ($raison)"; continue }
  $vus[$cle] = $true

  # --- mode EXPOSANT : on rattache à un stand, pas à un garage -------
  if ($Categorie -eq 'EXPOSANT') {
    $kf = NormFort $raison
    $st = $null; $comment = ''
    foreach ($s in $stands) { if ((NormFort $s.nom) -eq $kf) { $st = $s; $comment = 'nom exact'; break } }
    if (-not $st) {
      # Règle explicite, pas une devinette : le nom du stand est CONTENU
      # dans celui de la société (« ABC IXELL » contient « IXELL »).
      # Chaque rattachement de ce type est listé dans le rapport pour
      # que Bony puisse le refuser.
      foreach ($s in $stands) {
        $ks = NormFort $s.nom
        if ($ks -and ($kf -split ' ') -contains $ks) { $st = $s; $comment = "inclusion -> $($s.nom)"; break }
      }
    }
    $rows += [pscustomobject]@{
      cat = 'EXPOSANT'; raison = $raison; prenom = $prenom; nom = $nom; email = $email
      tel = (& $val 'tel'); nb = $nb; cle = $cle; codeNouveau = $null; garageNom = $null
      standId = $(if ($st) { $st.id } else { $null })
      via = $(if ($st) { $comment } else { 'AUCUN STAND' }); note = $statut
    }
    continue
  }

  # Équipe Bony : le domaine de messagerie est le seul signe fiable. Une
  # raison sociale « BSO » ou « EAA » ne dit rien à qui ne connaît pas
  # les sites du groupe.
  $estBony = ($email -like '*@bonyauto-mobile.com') -or ((Norm $raison) -like 'bony*')

  if ($estBony) {
    $rows += [pscustomobject]@{
      cat = 'EQUIPE_BONY'; raison = $raison; prenom = $prenom; nom = $nom; email = $email
      tel = (& $val 'tel'); nb = $nb; cle = $cle; codeNouveau = $null; garageNom = $null
      standId = $null
      via = 'equipe Bony'; note = $statut
    }
    continue
  }

  # --- garage : le nom d'abord, l'ID en second recours ---------------
  $k = NormFort $raison
  # PIÈGE DÉJÀ PAYÉ, ET IL NE SE VOIT QUE SUR LES CAS À UN SEUL RÉSULTAT.
  # `$x = if (...) { @(...) } else { @() }` fait passer le tableau par le
  # tuyau, qui le DÉROULE : avec un seul candidat, $x devenait l'objet
  # lui-même, .Count rendait $null, et la ligne tombait dans la branche
  # suivante. Avec deux candidats le tableau survivait — les homonymes
  # marchaient, donc rien ne semblait cassé. Affecter hors du `if`.
  $cands = @()
  if ($parNom.ContainsKey($k)) { $cands = @($parNom[$k]) }
  $g = $null; $via = ''
  if (@($cands).Count -eq 1) {
    $g = $cands[0]; $via = 'nom'
  } elseif (@($cands).Count -gt 1 -and -not $CreerHomonymes) {
    $aArbitrer += "$raison  ->  " + (($cands | ForEach-Object { "$($_.nom) ($($_.ville)) $($_.code)" }) -join '   |   ')
    continue
  } elseif (@($cands).Count -gt 1) {
    # -CreerHomonymes : on ne choisit toujours pas parmi les existants.
    # On laisse $g a null pour tomber dans la branche « societe creee »
    # plus bas, qui fabrique un compte neuf avec un code neuf.
    $homonymesCrees += "$raison  ->  nouveau compte (les " + @($cands).Count + " existants sont laisses intacts)"
  } elseif ($idBony) {
    $premier = ($idBony -split '[^A-Z0-9]')[0]
    if ($parRef.ContainsKey($premier)) { $g = $parRef[$premier]; $via = "id $premier -> $($g.nom)" }
  }

  if ($g) {
    $rows += [pscustomobject]@{
      cat = 'GARAGE'; raison = $g.nom; prenom = $prenom; nom = $nom; email = $email
      tel = (& $val 'tel'); nb = $nb; cle = $cle; codeNouveau = $null; garageNom = $g.nom
      standId = $null
      via = $via; note = $statut
    }
  } else {
    # Société absente de la base : on la crée, avec un code dérivé de
    # son nom. Déterministe, donc rejouable sans changer le code.
    if (-not $nouvelles.ContainsKey($k)) {
      $v = 0
      do { $c = CodeDe $k $v; $v++ } while ($codesPris.ContainsKey($c) -and $v -lt 500)
      $codesPris[$c] = $true
      $nouvelles[$k] = [pscustomobject]@{ nom = $raison; code = $c }
    }
    $rows += [pscustomobject]@{
      cat = 'GARAGE'; raison = $raison; prenom = $prenom; nom = $nom; email = $email
      tel = (& $val 'tel'); nb = $nb; cle = $cle; codeNouveau = $nouvelles[$k].code; garageNom = $raison
      standId = $null
      via = 'societe creee'; note = $statut
    }
  }
}

# =====================================================================
#  Le rapport
# =====================================================================
$parVia = @{}
foreach ($r in $rows) { $t = if ($r.via -like 'id *') { 'par identifiant (2e recours)' } else { $r.via }; $parVia[$t] = 1 + [int]$parVia[$t] }
$badges = ($rows | Measure-Object -Property nb -Sum).Sum

Write-Output ''
Write-Output '  ------------------------------------------------------------'
Write-Output ("  Lignes ecartees (pas au Forum) ........ {0}" -f $ecartes)
Write-Output ("  Doublons dans le fichier .............. {0}" -f $doublons.Count)
Write-Output ("  Lignes ayant herite de la societe ..... {0}" -f $reportees)
Write-Output ("  Personnes retenues .................... {0}" -f $rows.Count)
Write-Output ("  BADGES A PRODUIRE ..................... {0}" -f $badges)
Write-Output '  ------------------------------------------------------------'
foreach ($k in ($parVia.Keys | Sort-Object)) { Write-Output ("    {0,-32} {1}" -f $k, $parVia[$k]) }
Write-Output '  ------------------------------------------------------------'
Write-Output ("  Societes a creer en base .............. {0}" -f $nouvelles.Count)
Write-Output ("  A ARBITRER (homonymes en base) ........ {0}" -f $aArbitrer.Count)
if (@($homonymesCrees).Count -gt 0) {
  Write-Output ("  Homonymes : nouveaux comptes crees .... {0}" -f @($homonymesCrees).Count)
}
if ($aArbitrer.Count) {
  Write-Output ''
  Write-Output '  Ces lignes ne seront PAS importees : deux societes portent le meme'
  Write-Output '  nom en base et rien dans le fichier ne permet de les departager.'
  $aArbitrer | ForEach-Object { Write-Output "     $_" }
}
if ($doublons.Count) {
  Write-Output ''
  Write-Output '  Doublons ecartes (meme e-mail deux fois) :'
  $doublons | ForEach-Object { Write-Output "     $_" }
}

if (-not $Appliquer) {
  Write-Output ''
  Write-Output '  RIEN N A ETE ECRIT. Relancer avec -Appliquer pour pousser en base.'
  Write-Output ''
  return
}

# =====================================================================
#  L'écriture
# =====================================================================
$sb = New-Object Text.StringBuilder
[void]$sb.AppendLine('-- Genere par scripts\importer-inscriptions.ps1 — ne pas editer a la main.')
[void]$sb.AppendLine('begin;')

# 1. Les sociétés absentes deviennent des garages, avec leur code.
foreach ($k in $nouvelles.Keys) {
  $s = $nouvelles[$k]
  [void]$sb.AppendLine(("insert into public.garages (nom, ville, code, profil) select '{0}', '', '{1}', 'INSCRIT' where not exists (select 1 from public.garages where upper(code) = '{1}');" -f (Echap $s.nom), $s.code))
}

# 2. Les participants. on conflict (cle_source) : rejouer met a jour.
foreach ($r in $rows) {
  $lien = 'null'
  $lienStand = 'null'
  if ($r.standId) { $lienStand = "'" + $r.standId + "'::uuid" }
  if ($r.cat -eq 'GARAGE') {
    if ($r.codeNouveau) { $lien = "(select id from public.garages where upper(code) = '$($r.codeNouveau)')" }
    else { $lien = "(select id from public.garages where nom = '$(Echap $r.garageNom)' and actif order by cree_le limit 1)" }
  }
  # Un texte SQL ou « null » : on prépare chaque valeur AVANT le -f,
  # les sous-expressions dans une liste de format sont illisibles et
  # cassent la continuation de ligne.
  $vEmail = if ($r.email) { "'" + (Echap $r.email) + "'" } else { 'null' }
  $vTel   = if ($r.tel)   { "'" + (Echap $r.tel)   + "'" } else { 'null' }
  $vNote  = if ($r.note)  { "'" + (Echap $r.note)  + "'" } else { 'null' }

  $modele = "insert into public.participants (categorie, raison_sociale, prenom, nom, email, telephone, nb_badges, garage_id, stand_id, cle_source, note) values ('{0}','{1}','{2}','{3}',{4},{5},{6},{7},{10},'{8}',{9}) on conflict (cle_source) do update set categorie=excluded.categorie, raison_sociale=excluded.raison_sociale, prenom=excluded.prenom, nom=excluded.nom, email=excluded.email, telephone=excluded.telephone, nb_badges=excluded.nb_badges, garage_id=excluded.garage_id, stand_id=excluded.stand_id, note=excluded.note, actif=true;"

  [void]$sb.AppendLine(($modele -f $r.cat, (Echap $r.raison), (Echap $r.prenom), (Echap $r.nom),
                                 $vEmail, $vTel, $r.nb, $lien, (Echap $r.cle), $vNote, $lienStand))
}
[void]$sb.AppendLine('commit;')

$sortie = Join-Path (Split-Path $PSScriptRoot -Parent) 'sql\20_inscrits.sql'
[IO.File]::WriteAllText($sortie, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Output ''
Write-Output ("  sql\20_inscrits.sql ecrit ({0} instructions)" -f ($rows.Count + $nouvelles.Count))

& (Join-Path $PSScriptRoot 'push-sql.ps1') -File 'sql\20_inscrits.sql'

Write-Output ''
Write-Output '  --- controle en base ---'
$ctl = Sql "select categorie, count(*) as personnes, sum(nb_badges) as badges from public.v_badges group by categorie order by categorie"
$ctl | ForEach-Object { Write-Output ("    {0,-14} {1,4} personnes  {2,4} badges" -f $_.categorie, $_.personnes, $_.badges) }
$sans = Sql "select count(*) as n from public.verifier_badges()"
Write-Output ("    badges sans code valide : {0}" -f ($sans | ForEach-Object { $_.n }))
Write-Output ''
