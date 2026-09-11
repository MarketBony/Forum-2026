# =====================================================================
#  test-invariants.ps1
#  Vérifie, à travers la VRAIE API REST et avec la clé publique, que la
#  base refuse tout ce qu'elle doit refuser — et le prouve par les
#  EFFETS (solde, cases, lignes de journal), pas par le texte des
#  messages d'erreur.
#
#    .\scripts\test-invariants.ps1
#
#  Note : on utilise HttpClient et non Invoke-WebRequest, car ce dernier
#  ne restitue pas le corps des réponses 4xx sous PowerShell 5.1.
# =====================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$base = $conf['SUPABASE_URL'].TrimEnd('/')
$pub  = $conf['SUPABASE_PUBLISHABLE_KEY']
$ref  = $conf['SUPABASE_PROJECT_REF']
$pat  = $conf['SUPABASE_ACCESS_TOKEN']

$script:ok = 0; $script:ko = 0

function Jeton { (([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))) }
function Cle   { [guid]::NewGuid().ToString('N') }

$cli = New-Object System.Net.Http.HttpClient
$cli.DefaultRequestHeaders.Add('apikey', $pub)
$cli.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")
$cli.Timeout = [TimeSpan]::FromSeconds(30)

# --- RPC via PostgREST, clé publique (le chemin exact de l'app) -------
function Rpc($nom, $corps) {
  $c = New-Object System.Net.Http.StringContent(
        ($corps | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8, 'application/json')
  $r = $cli.PostAsync("$base/rest/v1/rpc/$nom", $c).Result
  $b = $r.Content.ReadAsStringAsync().Result
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  return @{ http = [int]$r.StatusCode; ok = $r.IsSuccessStatusCode; data = $o
            code = $(if ($o) { $o.message } else { '' })
            detail = $(if ($o) { $o.details } else { '' }) }
}

# --- SQL direct via API de management (préparation et lecture) --------
function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat")
  $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $b = $r.Content.ReadAsStringAsync().Result
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  return @{ http = [int]$r.StatusCode; ok = $r.IsSuccessStatusCode; data = $o }
}

function Verdict($libelle, $attendu, $preuve) {
  if ($attendu) { $script:ok++; Write-Output ("  [OK]    {0}" -f $libelle) }
  else          { $script:ko++; Write-Output ("  [ECHEC] {0}" -f $libelle) }
  Write-Output ("          preuve : {0}" -f $preuve)
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Forum Pieces Bony 2026 - verification des garanties de la base'
Write-Output '===================================================================='
Write-Output ''
Write-Output '--- Remise a zero du terrain de test -------------------------------'
# Le journal refuse tout DELETE, y compris ici : c'est voulu. Une remise
# a zero est une operation exceptionnelle, qui desactive explicitement le
# verrou le temps de l'operation puis le remet en place.
$r = Sql @'
-- 1. on libere les references de la grille vers le journal (cle etrangere)
update public.grille
   set garage_id=null, journal_id=null, achete_le=null, revele_le=null,
       code_retrait=null, remis=false, remis_le=null;
delete from public.tirage;
delete from public.tentatives;
-- 2. purge du journal, verrou d'immuabilite momentanement leve
alter table public.journal disable trigger journal_pas_de_modif;
delete from public.journal;
alter table public.journal enable trigger journal_pas_de_modif;
-- 3. remise a zero des portefeuilles et des appareils
update public.garages set solde=0, inscrit_le=null;
delete from public.appareils;
select count(*)::int as garages from public.garages;
'@
Write-Output ('  ' + $(if ($r.ok) { 'Terrain propre — ' + $r.data[0].garages + ' garages en base.' } else { 'Nettoyage HTTP ' + $r.http }))
# On travaille sur trois garages réels tirés de la base, désignés par
# leur code d'accès : c'est le chemin exact que prendra un garagiste.
$trois = (Sql "select id, nom, code from garages where code in ('TEST','BNY2','GRND') order by code").data
if ($trois.Count -lt 3) { throw "Codes de test TEST/BNY2/GRND absents de la base." }
$gA = $trois[0]; $gB = $trois[1]; $gC = $trois[2]
$dupont = $gA.id; $dupuy = $gB.id; $vidal = $gC.id
Write-Output ("  Garages temoins : {0} ({1}), {2} ({3}), {4} ({5})" -f `
               $gA.nom, $gA.code, $gB.nom, $gB.code, $gC.nom, $gC.code)

# =====================================================================
Write-Output ''
Write-Output '=== 1. Un portefeuille par garage, partage entre ses telephones ====='
$tel1 = Jeton; $tel2 = Jeton
$a = Rpc 'api_entrer' @{ p_jeton = $tel1; p_code = $gA.code }
Verdict 'Premier telephone : bonus d inscription verse' `
        ($a.data.garage.solde -eq 10) ('solde = ' + $a.data.garage.solde + ' (attendu 10)')

$b = Rpc 'api_entrer' @{ p_jeton = $tel2; p_code = $gA.code }
Verdict 'Second telephone du MEME garage : aucun second bonus' `
        ($b.data.garage.solde -eq 10) ('solde = ' + $b.data.garage.solde + ' (attendu 10, pas 20)')

$nbApp = (Sql "select count(*)::int as n from appareils where garage_id = '$dupont'").data[0].n
Verdict 'Les deux telephones voient le meme portefeuille' `
        ($nbApp -eq 2) ($nbApp.ToString() + ' appareils rattaches au garage, 1 seul solde')

# =====================================================================
Write-Output ''
Write-Output '=== 2. Double clic animateur : un seul mouvement de points =========='
$telAnim = Jeton
$anim = Rpc 'api_connexion' @{ p_jeton = $telAnim; p_pin = '1001' }
Verdict 'Connexion animateur par code PIN' `
        ($anim.data.role -eq 'animateur') ('role = ' + $anim.data.role + ', animation = ' + $anim.data.libelle)

$idAnim   = $anim.data.animation_id
$idPanier = ($anim.data.bareme | Where-Object { $_.points -eq 10 })[0].id

$cle = Cle
$p1 = Rpc 'api_participation' @{ p_jeton=$telAnim; p_garage=$dupont; p_animation=$idAnim; p_cle=$cle }
$p2 = Rpc 'api_participation' @{ p_jeton=$telAnim; p_garage=$dupont; p_animation=$idAnim; p_cle=$cle }
$n = (Sql "select count(*)::int as n from journal where cle_idem = '$cle'").data[0].n
Verdict 'Participation envoyee 2 fois : 1 seule ligne de journal' `
        (($n -eq 1) -and ($p2.data.solde -eq 8) -and ($p2.data.deja_traite -eq $true)) `
        ('lignes = ' + $n + ', solde = ' + $p2.data.solde + ', deja_traite = ' + $p2.data.deja_traite)

$cle2 = Cle
1..3 | ForEach-Object { $script:rr = Rpc 'api_resultat' @{ p_jeton=$telAnim; p_garage=$dupont; p_bareme=$idPanier; p_cle=$cle2 } }
$n2 = (Sql "select count(*)::int as n from journal where cle_idem = '$cle2'").data[0].n
Verdict 'Resultat tape 3 fois tres vite : 1 seul credit' `
        (($n2 -eq 1) -and ($script:rr.data.solde -eq 18)) `
        ('lignes = ' + $n2 + ', solde = ' + $script:rr.data.solde + ' (attendu 18 = 10 -2 +10)')

# =====================================================================
Write-Output ''
Write-Output '=== 3. Solde insuffisant : ni point debite, ni case consommee ======='
Sql "update grille set garage_id=null, journal_id=null, achete_le=null, revele_le=null, code_retrait=null where numero=77" | Out-Null
$telV = Jeton
Rpc 'api_entrer' @{ p_jeton = $telV; p_code = $gC.code } | Out-Null   # 10 pts de bonus
$j = Rpc 'api_jouer_case' @{ p_jeton = $telV; p_numero = 77; p_cle = (Cle) }
$apres = (Sql "select (select solde from garages where id='$vidal') as solde, (select garage_id is null from grille where numero=77) as libre").data[0]
Verdict 'Tirage a 20 pts avec 10 pts : refuse proprement' `
        (($j.http -eq 400) -and ($j.code -eq 'SOLDE_INSUFFISANT')) `
        ('HTTP ' + $j.http + ' / ' + $j.code + ' : "' + $j.detail + '"')
Verdict 'Le solde n a pas bouge et la case reste libre' `
        (($apres.solde -eq 10) -and ($apres.libre -eq $true)) `
        ('solde = ' + $apres.solde + ', case 77 libre = ' + $apres.libre)

# =====================================================================
Write-Output ''
Write-Output '=== 4. Garde-fous fournisseur (anti-inflation de points) ============'
$telF = Jeton
$four = Rpc 'api_connexion' @{ p_jeton = $telF; p_pin = '2001' }
Verdict 'Connexion fournisseur par code PIN' `
        ($four.data.role -eq 'fournisseur') ('role = ' + $four.data.role + ', stand = ' + $four.data.libelle)

# Le plafond par operation vaut desormais 20 : c'est le palier le plus
# haut du bareme arrete par Bony (5 / 10 / 20). Ce n'est plus une regle
# commerciale, c'est un garde-fou contre la faute de frappe.
$trop = Rpc 'api_points_achat' @{ p_jeton=$telF; p_garage=$dupont; p_points=500; p_cle=(Cle) }
Verdict 'Attribution de 500 pts (plafond 20) : refusee' `
        (($trop.http -eq 400) -and ($trop.code -eq 'PLAFOND_OPERATION')) `
        ($trop.code + ' : "' + $trop.detail + '"')

# FAAB est en categorie CA : ses paliers sont 1 a 199 EUR / 200 a 699 EUR /
# 700 EUR et plus. Le palier remonte doit etre repris dans le journal.
$bon = Rpc 'api_points_achat' @{ p_jeton=$telF; p_garage=$dupont; p_points=20; p_cle=(Cle); p_palier='700 € et plus' }
Verdict 'Attribution au palier haut : acceptee et tracee au nom du stand' `
        ($bon.data.solde -eq 38) ('solde = ' + $bon.data.solde + ', stand = ' + $bon.data.stand + ', cumul stand = ' + $bon.data.cumul_stand)

Verdict 'Le palier choisi est repris dans l ecriture' `
        ($bon.data.palier -eq '700 € et plus') ('palier journalise = ' + $bon.data.palier)

# Un libelle qui n'appartient pas au bareme de la categorie ne doit pas
# entrer dans un journal en ajout seul : il est ignore, pas recopie.
$faux = Rpc 'api_points_achat' @{ p_jeton=$telF; p_garage=$dupont; p_points=5; p_cle=(Cle); p_palier='Cadeau du patron' }
Verdict 'Un palier invente est ignore, pas journalise' `
        (($faux.http -eq 200) -and ($null -eq $faux.data.palier)) `
        ('palier = ' + $(if ($null -eq $faux.data.palier) { '(nul)' } else { $faux.data.palier }) + ', solde = ' + $faux.data.solde)

# =====================================================================
Write-Output ''
Write-Output '=== 5. Une case de la grille ne part qu une seule fois =============='
$telD = Jeton
Rpc 'api_entrer' @{ p_jeton = $telD; p_code = $gB.code } | Out-Null
Sql @"
insert into journal (garage_id, delta, libelle, source, cle_idem)
values ('$dupuy', 490, 'Dotation de test', 'administration', 'prep-' || gen_random_uuid()::text);
update garages set solde = (select coalesce(sum(delta),0) from journal where garage_id='$dupuy')
 where id = '$dupuy';
"@ | Out-Null

$c1 = Rpc 'api_jouer_case' @{ p_jeton = $telD; p_numero = 13; p_cle = (Cle) }
Verdict 'Le garage prend la case 13 et decouvre son contenu' `
        (($c1.ok) -and ($c1.data.revelee -eq $true) -and ($null -ne $c1.data.nature)) `
        ('lot = ' + $c1.data.lot + ', code de retrait = ' + $c1.data.code_retrait + ', solde = ' + $c1.data.solde)

$c2 = Rpc 'api_jouer_case' @{ p_jeton = $tel1; p_numero = 13; p_cle = (Cle) }
$soldeDupont = (Sql "select solde from garages where id='$dupont'").data[0].solde
Verdict 'Un autre garage sur la MEME case : refuse' `
        (($c2.http -eq 400) -and ($c2.code -eq 'CASE_DEJA_PRISE')) `
        ($c2.code + ' : "' + $c2.detail + '"')
# 18 apres l animation, + 20 au palier haut, + 5 au palier bas = 43.
Verdict 'Le garage refuse n a rien paye' `
        ($soldeDupont -eq 43) ('solde Dupont = ' + $soldeDupont + ' (attendu 43, inchange)')

# --- vraie concurrence : 8 requetes simultanees sur la meme case -----
$taches = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task[System.Net.Http.HttpResponseMessage]]'
for ($i = 0; $i -lt 8; $i++) {
  $c = New-Object System.Net.Http.StringContent(
        ((@{ p_jeton=$telD; p_numero=55; p_cle=(Cle) }) | ConvertTo-Json -Compress),
        [Text.Encoding]::UTF8, 'application/json')
  $taches.Add($cli.PostAsync("$base/rest/v1/rpc/api_jouer_case", $c))
}
[System.Threading.Tasks.Task]::WaitAll($taches.ToArray())
$succes = 0; foreach ($t in $taches) { if ($t.Result.IsSuccessStatusCode) { $succes++ } }
$nJ = (Sql "select count(*)::int as n from journal where libelle like '%case n°55%'").data[0].n
Verdict '8 tirages SIMULTANES sur la case 55 : 1 seul aboutit' `
        (($succes -eq 1) -and ($nJ -eq 1)) `
        ($succes.ToString() + ' succes / ' + (8 - $succes) + ' refus, et ' + $nJ + ' ligne de journal')

# =====================================================================
Write-Output ''
Write-Output '=== 6. Le journal est en ajout seul, meme pour un administrateur ===='
$t = (Sql "select id, delta from journal order by id limit 1").data[0]
$u = Sql ("update journal set delta = 9999 where id = " + $t.id)
$d1 = (Sql ("select delta from journal where id = " + $t.id)).data[0].delta
Verdict 'UPDATE direct en base : rejete, ligne intacte' `
        (($u.http -eq 400) -and ($d1 -eq $t.delta)) `
        ('HTTP ' + $u.http + ', delta ' + $t.delta + ' -> ' + $d1)

$n1 = (Sql "select count(*)::int as n from journal").data[0].n
$dd = Sql ("delete from journal where id = " + $t.id)
$n2 = (Sql "select count(*)::int as n from journal").data[0].n
Verdict 'DELETE direct en base : rejete, aucune ligne perdue' `
        (($dd.http -eq 400) -and ($n1 -eq $n2)) `
        ('HTTP ' + $dd.http + ', lignes ' + $n1 + ' -> ' + $n2)

# =====================================================================
Write-Output ''
Write-Output '=== 7. La cle publique ne peut lire aucune table en direct =========='
foreach ($tbl in @('garages','journal','grille','appareils','config')) {
  $rq = $cli.GetAsync("$base/rest/v1/$tbl" + '?select=*&limit=1').Result
  $bd = $rq.Content.ReadAsStringAsync().Result
  $bloque = ((-not $rq.IsSuccessStatusCode) -or ($bd.Trim() -eq '[]'))
  Verdict ("Lecture directe de la table $tbl") $bloque ('HTTP ' + [int]$rq.StatusCode + ' corps = ' + $bd.Trim())
}
$w = Rpc 'api_supervision' @{ p_jeton = $tel1 }
Verdict 'Un telephone de garage ne peut pas ouvrir la supervision' `
        (($w.http -eq 400) -and ($w.code -eq 'ROLE_INSUFFISANT')) ($w.code + ' : "' + $w.detail + '"')

# =====================================================================
Write-Output ''
Write-Output '=== 8. Invariant : solde en cache = somme du journal ================'
$ec = (Sql "select count(*)::int as n from verifier_soldes()").data[0].n
Verdict 'Aucun ecart sur aucun garage' ($ec -eq 0) ('garages en ecart = ' + $ec)

$telAdm = Jeton
Rpc 'api_connexion' @{ p_jeton = $telAdm; p_pin = '9137' } | Out-Null
$s = (Rpc 'api_supervision' @{ p_jeton = $telAdm }).data
Verdict 'La supervision Bony repond et se recoupe' `
        ($s.ecarts_solde -eq 0) `
        ('points en circulation = ' + $s.points_circulation + ', cases jouees = ' + $s.cases_jouees +
         '/100, parties financables = ' + $s.parties_financables + ', tension = ' + $s.tension + ', ecarts = ' + $s.ecarts_solde)

# =====================================================================
Write-Output ''
Write-Output '===================================================================='
Write-Output ("  RESULTAT : {0} reussis, {1} echoues" -f $script:ok, $script:ko)
Write-Output '===================================================================='
