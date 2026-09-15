#requires -Version 5
# =====================================================================
#  test-bingo.ps1
#  Vérifie la mécanique du bingo par l'API réelle, dans les DEUX modes
#  de révélation, puis déroule la RÉVÉLATION des tickets d'or du soir.
#
#    .\scripts\test-bingo.ps1
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

function Rpc($nom, $corps) {
  $c = New-Object System.Net.Http.StringContent(
        ($corps | ConvertTo-Json -Depth 5 -Compress), [Text.Encoding]::UTF8, 'application/json')
  $r = $cli.PostAsync("$base/rest/v1/rpc/$nom", $c).Result
  $b = $r.Content.ReadAsStringAsync().Result
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; http = [int]$r.StatusCode; data = $o
            code = $(if ($o) { $o.message } else { '' }); detail = $(if ($o) { $o.details } else { '' }) }
}
function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $o = $null; try { $o = $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; http = [int]$r.StatusCode; data = $o }
}
function Verdict($libelle, $attendu, $preuve) {
  if ($attendu) { $script:ok++; Write-Output ("  [OK]    {0}" -f $libelle) }
  else          { $script:ko++; Write-Output ("  [ECHEC] {0}" -f $libelle) }
  Write-Output ("          preuve : {0}" -f $preuve)
}
function Mode($m) { Sql "update config set valeur='$m' where cle='revelation'" | Out-Null }

# --- terrain propre ----------------------------------------------------
Write-Output ''
Write-Output '===================================================================='
Write-Output '  Le bingo - verification des deux modes et du grand tirage'
Write-Output '===================================================================='
Write-Output ''
Sql @'
update public.grille set garage_id=null, journal_id=null, achete_le=null, revele_le=null,
       code_retrait=null, remis=false, remis_le=null;
alter table public.journal disable trigger journal_pas_de_modif;
delete from public.journal;
alter table public.journal enable trigger journal_pas_de_modif;
update public.garages set solde=0, inscrit_le=null;
delete from public.appareils;
update public.config set valeur='non' where cle='tirage_revele';
'@ | Out-Null
Write-Output '  Terrain propre.'

$rep = (Sql "select nature, count(*)::int as n from grille group by nature order by nature").data
Write-Output ('  Repartition : ' + (($rep | ForEach-Object { "$($_.n) $($_.nature)" }) -join ' / '))

# On dote six garages réels, désignés par leur code d'accès de test, de
# quoi acheter plusieurs cases.
$six = (Sql "select id, nom, code from garages where code in ('TEST','BNY2','GRND','BAL2','FRUM','JEUX') order by code").data
if ($six.Count -lt 6) { throw "Les six codes de test sont absents de la base." }
$noms = @($six | ForEach-Object { $_.nom })
$jetons = @{}
foreach ($g in $six) {
  $n = $g.nom; $id = $g.id
  $j = Jeton
  Rpc 'api_entrer' @{ p_jeton = $j; p_code = $g.code } | Out-Null
  Sql @"
insert into journal (garage_id, delta, libelle, source, cle_idem)
values ('$id', 200, 'Dotation test bingo', 'administration', 'bingo-$id');
update garages set solde = (select coalesce(sum(delta),0) from journal where garage_id='$id')
 where id = '$id';
"@ | Out-Null
  $jetons[$n] = @{ jeton = $j; id = $id }
}
Write-Output ("  6 garages dotes de 210 points chacun.")

# =====================================================================
Write-Output ''
Write-Output '=== MODE IMMEDIAT : le garage decouvre a l achat ==================='
Mode 'immediate'
$j1 = $jetons[$noms[0]].jeton

# une perdante, un lot, un billet : on prend des numeros connus
$perdante = (Sql "select min(numero)::int as n from grille where nature='perdante' and garage_id is null").data[0].n
$lot      = (Sql "select min(numero)::int as n from grille where nature='lot' and garage_id is null").data[0].n
$billet   = (Sql "select min(numero)::int as n from grille where nature='billet' and garage_id is null").data[0].n

$rp = Rpc 'api_jouer_case' @{ p_jeton = $j1; p_numero = $perdante; p_cle = (Cle) }
Verdict "Case perdante n°$perdante : revelee immediatement, sans lot" `
        (($rp.data.revelee -eq $true) -and ($rp.data.nature -eq 'perdante') -and ($null -eq $rp.data.lot)) `
        ("revelee=$($rp.data.revelee) nature=$($rp.data.nature) lot=$($rp.data.lot) solde=$($rp.data.solde)")

$rl = Rpc 'api_jouer_case' @{ p_jeton = $j1; p_numero = $lot; p_cle = (Cle) }
Verdict "Case lot n°$lot : lot et code de retrait immediats" `
        (($rl.data.nature -eq 'lot') -and $rl.data.lot -and $rl.data.code_retrait) `
        ("lot=$($rl.data.lot) code=$($rl.data.code_retrait)")

$rb = Rpc 'api_jouer_case' @{ p_jeton = $j1; p_numero = $billet; p_cle = (Cle) }
Verdict "Case billet n°$billet : annoncee comme billet, sans code de retrait" `
        (($rb.data.nature -eq 'billet') -and ($null -eq $rb.data.code_retrait)) `
        ("nature=$($rb.data.nature) lot=$($rb.data.lot) code=$($rb.data.code_retrait)")

$etat = Rpc 'api_etat' @{ p_jeton = $j1 }
Verdict 'L ecran garage voit ses trois cases, toutes revelees' `
        ((@($etat.data.mes_cases).Count -eq 3) -and (@($etat.data.mes_cases | Where-Object { -not $_.revelee }).Count -eq 0)) `
        ("cases=$($etat.data.mes_cases.Count) billets restants=$($etat.data.billets_restants) mode=$($etat.data.revelation)")

# =====================================================================
Write-Output ''
Write-Output '=== MODE DIFFERE : le garage achete a l aveugle ===================='
Mode 'differee'
$j2 = $jetons[$noms[1]].jeton
$n2 = (Sql "select min(numero)::int as n from grille where nature='lot' and garage_id is null").data[0].n
$rd = Rpc 'api_jouer_case' @{ p_jeton = $j2; p_numero = $n2; p_cle = (Cle) }
Verdict "Case n°$n2 achetee : RIEN n est revele" `
        (($rd.data.revelee -eq $false) -and ($null -eq $rd.data.nature) -and ($null -eq $rd.data.lot)) `
        ("revelee=$($rd.data.revelee) nature=$($rd.data.nature) lot=$($rd.data.lot) solde=$($rd.data.solde)")

$e2 = Rpc 'api_etat' @{ p_jeton = $j2 }
# @() est indispensable : sur un seul element, Where-Object renvoie un
# scalaire et non un tableau, donc .Count vaut $null sous PowerShell 5.1.
$toutes = @($e2.data.mes_cases)
$nonRev = @($toutes | Where-Object { -not $_.revelee }).Count
Verdict 'La case apparait chez le garage, mais fermee' `
        (($toutes.Count -ge 1) -and ($nonRev -ge 1)) `
        ("cases possedees = $($toutes.Count), dont non revelees = $nonRev")

$enBase = (Sql "select nature, lot from grille where numero = $n2").data[0]
Verdict 'La nature est bien deja fixee en base (rien de tire au moment du soir)' `
        ($enBase.nature -eq 'lot') ("en base : nature=$($enBase.nature) lot=$($enBase.lot)")

# --- revelation collective -------------------------------------------
$telAdm = Jeton
Rpc 'api_connexion' @{ p_jeton = $telAdm; p_pin = '9137' } | Out-Null
$rev = Rpc 'api_reveler' @{ p_jeton = $telAdm }
Verdict 'Revelation collective par l equipe Bony' `
        (($rev.ok) -and ($rev.data.restantes -eq 0)) `
        ("revelees=$($rev.data.revelees) restantes=$($rev.data.restantes)")

$e3 = Rpc 'api_etat' @{ p_jeton = $j2 }
$c = $e3.data.mes_cases | Where-Object { $_.numero -eq $n2 }
Verdict 'Le garage voit maintenant son lot et son code' `
        (($c.revelee -eq $true) -and $c.lot -and $c.code_retrait) `
        ("nature=$($c.nature) lot=$($c.lot) code=$($c.code_retrait)")

# =====================================================================
Write-Output ''
Write-Output '=== LE GRAND TIRAGE ================================================'
Mode 'immediate'
# les 4 billets restants sont achetes par 4 garages differents
$restants = (Sql "select numero from grille where nature='billet' and garage_id is null order by numero").data
$acheteurs = @($noms[1], $noms[2], $noms[3], $noms[4])
for ($i = 0; $i -lt [Math]::Min($restants.Count, $acheteurs.Count); $i++) {
  Rpc 'api_jouer_case' @{ p_jeton = $jetons[$acheteurs[$i]].jeton; p_numero = $restants[$i].numero; p_cle = (Cle) } | Out-Null
}
$vendus = (Sql "select count(*)::int as n from grille where nature='billet' and garage_id is not null and revele_le is not null").data[0].n
Verdict 'Les 5 billets sont vendus et reveles' ($vendus -eq 5) ("billets en course = $vendus")

# --- l'etat du soir, avant que quoi que ce soit ne soit revele -------
$et = Rpc 'api_tirage_etat' @{ p_jeton = $telAdm }
$joues = @($et.data.tickets | Where-Object { $null -ne $_.rang })
Verdict 'Les 15 tickets sont connus, 5 decroches, chacun porte son gros lot' `
        (($et.data.tickets.Count -eq 15) -and ($joues.Count -eq 5) -and `
         (@($et.data.tickets | Where-Object { [string]::IsNullOrEmpty($_.gros_lot) }).Count -eq 0)) `
        ("15 tickets, $($joues.Count) decroches, $($et.data.orphelins) orphelins")

# LE TEST QUI COMPTE : tant que la soiree n'a pas eu lieu, le contenu de
# l'enveloppe ne doit fuiter NULLE PART vers le telephone du garage.
$porteur = $joues[0]
$gPorteur = (Sql "select g.nom, g.code from garages g join grille gr on gr.garage_id=g.id where gr.numero=$($porteur.numero)").data[0]
$telP = Jeton
Rpc 'api_entrer' @{ p_jeton = $telP; p_code = $gPorteur.code } | Out-Null
$avant = Rpc 'api_etat' @{ p_jeton = $telP }
$caseAvant = @($avant.data.mes_cases | Where-Object { $_.numero -eq $porteur.numero })[0]
Verdict 'AVANT la revelation, le garage ne voit pas son gros lot' `
        (($avant.data.tirage_revele -eq $false) -and ($null -eq $caseAvant.gros_lot) -and `
         ($caseAvant.lot -eq "Ticket d'or") -and ($null -eq $caseAvant.code_retrait)) `
        ("lot affiche = '$($caseAvant.lot)' · gros_lot = '$($caseAvant.gros_lot)' · code = '$($caseAvant.code_retrait)'")

# --- le lancement ----------------------------------------------------
$lan = Rpc 'api_tirage_lancer' @{ p_jeton = $telAdm }
$lanJoues = @($lan.data.tickets | Where-Object { $null -ne $_.rang })
Verdict 'Le lancement revele les 5 tickets decroches et pose un code de retrait' `
        (($lan.ok) -and ($lan.data.revele -eq $true) -and ($lanJoues.Count -eq 5) -and `
         (@($lanJoues | Where-Object { [string]::IsNullOrEmpty($_.code_retrait) }).Count -eq 0)) `
        ("revele = $($lan.data.revele) · " + (($lanJoues | ForEach-Object { "$($_.gros_lot) -> $($_.garage)" }) -join ' | '))

Verdict 'Les tickets non decroches restent hors du spectacle' `
        ((@($lan.data.tickets | Where-Object { $null -eq $_.rang }).Count -eq 10) -and `
         ((($lanJoues | ForEach-Object { $_.rang }) -join ',') -eq '1,2,3,4,5')) `
        ("rangs joues = " + (($lanJoues | ForEach-Object { $_.rang }) -join ','))

# --- ce que le garage voit APRES -------------------------------------
$apres = Rpc 'api_etat' @{ p_jeton = $telP }
$caseApres = @($apres.data.mes_cases | Where-Object { $_.numero -eq $porteur.numero })[0]
Verdict 'APRES la revelation, le garage voit son gros lot et son code' `
        (($apres.data.tirage_revele -eq $true) -and ($caseApres.gros_lot -eq $porteur.gros_lot) -and `
         (-not [string]::IsNullOrEmpty($caseApres.code_retrait))) `
        ("$($caseApres.gros_lot) · code $($caseApres.code_retrait)")

# --- relancer ne rebat pas les cartes --------------------------------
$codes1 = (($lanJoues | Sort-Object rang | ForEach-Object { "$($_.numero):$($_.code_retrait)" }) -join ',')
$relance = Rpc 'api_tirage_lancer' @{ p_jeton = $telAdm }
$codes2 = ((@($relance.data.tickets | Where-Object { $null -ne $_.rang }) | Sort-Object rang |
            ForEach-Object { "$($_.numero):$($_.code_retrait)" }) -join ',')
Verdict 'Relancer est sans effet : aucun code de retrait ne change' `
        ($codes1 -eq $codes2) ("avant = $codes1")

# --- l'ordre de spectacle --------------------------------------------
$ordre = (Sql "select gros_lot, gros_lot_ordre from grille where nature='billet' order by gros_lot_ordre").data
$suite = 0
for ($i = 1; $i -lt $ordre.Count; $i++) { if ($ordre[$i].gros_lot -eq $ordre[$i-1].gros_lot) { $suite++ } }
Verdict 'Le spectacle ne repete jamais deux fois le meme lot de suite' `
        ($suite -eq 0) ("$suite repetition(s) sur 15 temps")

Verdict 'Le spectacle finit sur le sac cuir Alpine' `
        ($ordre[-1].gros_lot -eq 'SAC CUIR ALPINE JAUNE 48H') `
        ("dernier = $($ordre[-1].gros_lot)")

# --- le suivi des lots accueille les gros lots ------------------------
$suivi = Rpc 'api_lots' @{ p_jeton = $telAdm }
$gros = @($suivi.data | Where-Object { $_.gros -eq $true })
Verdict 'Les 5 gros lots reveles apparaissent dans le suivi des lots' `
        ($gros.Count -eq 5) ("$($gros.Count) gros lots au comptoir sur $($suivi.data.Count) lots au total")

# --- retour en arriere, pour la repetition generale -------------------
$reset = Rpc 'api_tirage_reset' @{ p_jeton = $telAdm }
Verdict 'La remise a zero du drapeau recache les gros lots' `
        (($reset.data.revele -eq $false) -and `
         ($null -eq (@((Rpc 'api_etat' @{ p_jeton = $telP }).data.mes_cases |
                       Where-Object { $_.numero -eq $porteur.numero })[0].gros_lot))) `
        ("revele = $($reset.data.revele)")
Rpc 'api_tirage_lancer' @{ p_jeton = $telAdm } | Out-Null   # on laisse la base revelee

# =====================================================================
#  La grille a 200 cases et le plafond par garage
#
#  Ces deux mecanismes protegent le meme risque : que la grille soit
#  videe en debut d'apres-midi et qu'un garage arrive a 17 h ne trouve
#  plus une seule case.
# =====================================================================
Write-Output ''
Write-Output '=== 200 CASES ET PLAFOND PAR GARAGE ================================'
Mode 'immediate'

$taille = (Sql "select count(*)::int as n, max(numero)::int as m from grille").data[0]
Verdict 'La grille compte bien 200 cases numerotees jusqu a 200' `
        (($taille.n -eq 200) -and ($taille.m -eq 200)) ("cases=$($taille.n) numero max=$($taille.m)")

# Un septieme garage, vierge de toute case : les six precedents ont
# deja joue et fausseraient le compte du plafond.
$g7 = (Sql @"
select id, nom, code from garages
 where code is not null and code not in ('TEST','BNY2','GRND','BAL2','FRUM','JEUX')
   and id not in (select garage_id from grille where garage_id is not null)
 limit 1
"@).data[0]
$j7 = Jeton
Rpc 'api_entrer' @{ p_jeton = $j7; p_code = $g7.code } | Out-Null
Sql @"
insert into journal (garage_id, delta, libelle, source, cle_idem)
values ('$($g7.id)', 200, 'Dotation test plafond', 'administration', 'plafond-$($g7.id)');
update garages set solde = (select coalesce(sum(delta),0) from journal where garage_id='$($g7.id)')
 where id = '$($g7.id)';
"@ | Out-Null

# Les cases 101 a 200 n'existaient pas avant 17_grille_200.sql : c'est
# la moitie neuve de la grille, celle qu'aucun test ne couvrait.
$hautes = @(150, 175, 200)
$prises = 0
foreach ($n in $hautes) {
  $r = Rpc 'api_jouer_case' @{ p_jeton = $j7; p_numero = $n; p_cle = (Cle) }
  if ($r.ok) { $prises++ }
}
Verdict 'Les cases de la moitie haute (101-200) sont jouables' `
        ($prises -eq 3) ("cases 150, 175 et 200 prises = $prises / 3")

$soldeAvant = (Sql "select solde from garages where id='$($g7.id)'").data[0].solde
$quatrieme  = Rpc 'api_jouer_case' @{ p_jeton = $j7; p_numero = 199; p_cle = (Cle) }
$soldeApres = (Sql "select solde from garages where id='$($g7.id)'").data[0].solde
Verdict 'La 4e case est refusee : le plafond de 3 tient' `
        (($quatrieme.http -eq 400) -and ($quatrieme.code -eq 'PLAFOND_CASES')) `
        ("$($quatrieme.code) : `"$($quatrieme.detail)`"")
Verdict 'Le garage plafonne n a rien paye et la case reste libre' `
        (($soldeApres -eq $soldeAvant) -and
         ((Sql "select count(*)::int as n from grille where numero=199 and garage_id is null").data[0].n -eq 1)) `
        ("solde $soldeAvant -> $soldeApres, case 199 libre")

# Un numero hors grille doit etre refuse comme invalide, pas provoquer
# un debit sans case en face.
$hors = Rpc 'api_jouer_case' @{ p_jeton = $j7; p_numero = 201; p_cle = (Cle) }
Verdict 'La case 201 n existe pas et est refusee comme telle' `
        (($hors.http -eq 400) -and ($hors.code -eq 'CASE_INVALIDE')) `
        ("$($hors.code) : `"$($hors.detail)`"")

# Le plafond se leve en direct, sans redeploiement : c'est ce qui
# permettra d'ouvrir le reste de la grille au cocktail.
Sql "update config set valeur='0' where cle='cases_max_garage'" | Out-Null
$levee = Rpc 'api_jouer_case' @{ p_jeton = $j7; p_numero = 199; p_cle = (Cle) }
Sql "update config set valeur='3' where cle='cases_max_garage'" | Out-Null
Verdict 'Le plafond se leve en direct depuis config' `
        ($levee.ok) ("4e case acceptee apres levee du plafond : http=$($levee.http)")

$remis = (Sql "select valeur from config where cle='cases_max_garage'").data[0].valeur
Verdict 'Le plafond est bien remis a 3 apres le test' `
        ($remis -eq '3') ("cases_max_garage = $remis")

# =====================================================================
Write-Output ''
Write-Output '=== Coherence finale ==============================================='
$fin = (Sql @'
select
  (select count(*)::int from verifier_soldes())                                    as ecarts,
  (select count(*)::int from grille where garage_id is not null)                   as cases_achetees,
  (select count(*)::int from grille where achete_le is not null and revele_le is null) as non_revelees,
  (select count(*)::int from journal where libelle like 'Bingo%')                  as lignes_bingo,
  (select count(distinct cle_idem)::int from journal where libelle like 'Bingo%')  as cles_bingo
'@).data[0]
Verdict 'Solde = somme du journal, sur tous les garages' ($fin.ecarts -eq 0) ("ecarts = $($fin.ecarts)")
Verdict 'Une ligne de journal par case achetee, sans doublon' `
        (($fin.lignes_bingo -eq $fin.cases_achetees) -and ($fin.cles_bingo -eq $fin.lignes_bingo)) `
        ("cases=$($fin.cases_achetees) lignes=$($fin.lignes_bingo) cles=$($fin.cles_bingo) non revelees=$($fin.non_revelees)")

Write-Output ''
Write-Output '===================================================================='
Write-Output ("  RESULTAT : {0} reussis, {1} echoues" -f $script:ok, $script:ko)
Write-Output '===================================================================='
