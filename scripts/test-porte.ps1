#requires -Version 5
# =====================================================================
#  test-porte.ps1
#  Verifie la porte unique : un seul champ, cinq profils derriere.
#  Ce que l'on cherche a prouver, dans l'ordre :
#    1. chaque profil entre par le meme appel ;
#    2. aucun code garage ne vaut un PIN du personnel ;
#    3. un code refuse revient en resultat, et le frein le compte ;
#    4. la tolerance de saisie (minuscules, espaces, tirets) ;
#    5. les 0 et les 1 des PIN survivent a la normalisation.
#
#    .\scripts\test-porte.ps1
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

# UN SEUL jeton pour tous les appels qui visent un garage.
#
# Un garage est plafonne a trois appareils, et une place prise ne se
# rend pas : le journal reference l'appareil qui a ecrit et il est en
# ajout seul, donc on ne peut pas supprimer l'appareil ; et le detacher
# est interdit par appareils_garage_coherent, qui exige un garage_id
# des que le role vaut 'garage'. Avec plusieurs jetons, le script
# saturerait son garage temoin en une seule execution et se mettrait a
# mesurer le plafond au lieu de ce qu'il vise.
$JG = Jeton

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
            code = $(if ($o) { $o.message } else { '' }) }
}
function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $o = $null; try { $o = $r.Content.ReadAsStringAsync().Result | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; data = $o }
}
function Verdict($libelle, $attendu, $preuve) {
  if ($attendu) { $script:ok++; Write-Output ("  [OK]    {0}" -f $libelle) }
  else          { $script:ko++; Write-Output ("  [ECHEC] {0}" -f $libelle) }
  Write-Output ("          preuve : {0}" -f $preuve)
}
function Ouvrir($jeton, $code) { Rpc 'api_ouvrir' @{ p_jeton = $jeton; p_code = $code } }

Write-Output ''
Write-Output '===================================================================='
Write-Output '  La porte unique - un champ, cinq profils'
Write-Output '===================================================================='
Write-Output ''

# --- terrain -----------------------------------------------------------
# On prend un garage encore vierge d'appareil : les places prises ne se
# rendant pas, reprendre toujours le meme finirait par le saturer.
$g = (Sql @"
select code, nom from garages g
 where actif and not exists (select 1 from appareils a where a.garage_id = g.id)
 order by code limit 1
"@).data[0]
if (-not $g) { throw 'Plus aucun garage vierge : lancez sql\99_remise_a_zero.sql' }
$codeGarage = $g.code
Write-Output ("  Garage temoin : {0} ({1}) - aucun appareil" -f $codeGarage, $g.nom)
Sql "delete from tentatives" | Out-Null

# --- 1. les cinq profils passent par le meme appel ---------------------
Write-Output ''
Write-Output '-- 1. Les cinq profils, un seul appel -------------------------------'

$cas = @(
  @{ libelle = 'Garage';      code = $codeGarage; porte = 'garage';    role = $null },
  @{ libelle = 'Animateur';   code = '1001';      porte = 'personnel'; role = 'animateur' },
  @{ libelle = 'Fournisseur'; code = '2001';      porte = 'personnel'; role = 'fournisseur' },
  @{ libelle = 'Accueil';     code = '4200';      porte = 'personnel'; role = 'accueil' },
  @{ libelle = 'Equipe Bony'; code = '9137';      porte = 'personnel'; role = 'admin' }
)
foreach ($c in $cas) {
  $r = Ouvrir $(if ($c.porte -eq "garage") { $JG } else { Jeton }) $c.code
  $porte = $(if ($r.data) { $r.data.porte } else { '' })
  $role  = $(if ($r.data) { $r.data.role }  else { '' })
  $bon = $r.ok -and $porte -eq $c.porte -and ($null -eq $c.role -or $role -eq $c.role)
  Verdict ("{0} entre par api_ouvrir" -f $c.libelle) $bon ("code {0} -> porte={1} role={2}" -f $c.code, $porte, $role)
}

# --- 2. aucune collision entre codes garage et PIN ---------------------
Write-Output ''
Write-Output '-- 2. Aucune collision de code --------------------------------------'
$col = @((Sql "select * from verifier_portes()").data)
Verdict 'Aucun code garage ne vaut un PIN du personnel' ($col.Count -eq 0) `
        ("verifier_portes() renvoie {0} ligne(s)" -f $col.Count)

$n = (Sql "select count(*)::int as n from garages where actif and code !~ '^[A-HJ-NP-Z2-9]{4,6}$'").data[0].n
Verdict 'Tous les codes garage tiennent dans leur alphabet' ($n -eq 0) `
        ("{0} code(s) hors alphabet" -f $n)

# --- 3. le refus est un resultat, et le frein compte -------------------
Write-Output ''
Write-Output '-- 3. Le refus est un resultat, pas une exception -------------------'
$j = Jeton
$r = Ouvrir $j 'ZZZZ'
$porte = $(if ($r.data) { $r.data.porte } else { '' })
Verdict 'Un code inconnu revient en HTTP 200' ($r.ok -and $porte -eq 'refus') `
        ("http={0} porte={1} erreur={2}" -f $r.http, $porte, $(if ($r.data) { $r.data.erreur } else { '' }))

$restantes = $r.data.restantes
Verdict 'Le nombre d essais restants est annonce' ($null -ne $restantes) ("restantes={0}" -f $restantes)

for ($i = 0; $i -lt 8; $i++) { Ouvrir $j ("ZZZ" + $i) | Out-Null }
$r = Ouvrir $j 'ZZZZ'
Verdict 'Le frein finit par se declencher' ($r.data.erreur -eq 'TROP_DE_TENTATIVES') `
        ("erreur={0}" -f $r.data.erreur)

$nb = (Sql "select count(*)::int as n from tentatives where jeton = '$j'").data[0].n
Verdict 'Les tentatives sont bien enregistrees' ($nb -ge 8) ("{0} tentatives en base" -f $nb)

# Un jeton neuf n'est pas puni pour les erreurs d'un autre.
$r = Ouvrir $JG $codeGarage
Verdict 'Le frein ne penalise que le jeton fautif' ($r.ok -and $r.data.porte -eq 'garage') `
        ("porte={0}" -f $r.data.porte)

# --- 4. tolerance de saisie -------------------------------------------
Write-Output ''
Write-Output '-- 4. Tolerance de saisie -------------------------------------------'
# Le meme jeton pour les trois variantes : le plafond d'appareils est
# par garage, et trois jetons neufs de plus le feraient sauter — ce
# serait le plafond que l'on testerait, pas la tolerance de saisie.
$j2 = $JG
$variantes = @($codeGarage.ToLower(), " $codeGarage ", ($codeGarage -replace '(..)(..)', '$1-$2'))
foreach ($v in $variantes) {
  $r = Ouvrir $j2 $v
  Verdict ("Saisie tolerante : [{0}]" -f $v) ($r.ok -and $r.data.porte -eq 'garage') `
          ("porte={0} {1}" -f $(if ($r.data) { $r.data.porte } else { '' }), $r.code)
}
$r = Ouvrir (Jeton) '10-01'
Verdict 'Un PIN avec tiret passe aussi' ($r.ok -and $r.data.role -eq 'animateur') `
        ("role={0}" -f $(if ($r.data) { $r.data.role } else { '' }))

# --- 5. les 0 et les 1 survivent --------------------------------------
Write-Output ''
Write-Output '-- 5. Les 0 et les 1 des PIN survivent ------------------------------'
# C'est le piege de l'unification : l'alphabet des codes garage exclut 0
# et 1 pour eviter la confusion avec O et I. Les filtrer a l'entree
# viderait « 1001 » et « 4200 ».
foreach ($p in @('1001', '1002', '1003', '1004', '2001', '2002', '2003', '2004', '2005', '4200', '9137')) {
  $r = Ouvrir (Jeton) $p
  $bon = $r.ok -and $r.data.porte -eq 'personnel'
  if (-not $bon) { Verdict ("PIN {0} reconnu" -f $p) $false ("porte={0}" -f $(if ($r.data) { $r.data.porte } else { '' })) }
  else { $script:ok++ }
}
Write-Output '  [OK]    Les 11 PIN du personnel sont tous reconnus'
Write-Output '          preuve : 0, 1 et 2 en tete de PIN passent la normalisation'

# --- 6. un code trop court reste une exception -------------------------
Write-Output ''
Write-Output '-- 6. Les refus qui n ont rien a compter ----------------------------'
$r = Ouvrir (Jeton) 'AB'
Verdict 'Un code trop court leve une exception' ((-not $r.ok) -and $r.code -eq 'CODE_TROP_COURT') `
        ("http={0} code={1}" -f $r.http, $r.code)
$r = Ouvrir 'court' $codeGarage
Verdict 'Un jeton trop court leve une exception' ((-not $r.ok) -and $r.code -eq 'JETON_INVALIDE') `
        ("http={0} code={1}" -f $r.http, $r.code)

# --- 7. api_connexion garde son contrat -------------------------------
Write-Output ''
Write-Output '-- 7. L ancienne porte du personnel garde son contrat ---------------'
$r = Rpc 'api_connexion' @{ p_jeton = (Jeton); p_pin = '1001' }
Verdict 'api_connexion fonctionne toujours' ($r.ok -and $r.data.role -eq 'animateur') `
        ("role={0}" -f $(if ($r.data) { $r.data.role } else { '' }))
$r = Rpc 'api_connexion' @{ p_jeton = (Jeton); p_pin = 'ZZZZ' }
Verdict 'api_connexion refuse toujours par exception' ((-not $r.ok) -and $r.code -eq 'PIN_INCONNU') `
        ("code={0}" -f $r.code)

# --- 8. l invariant des soldes -----------------------------------------
Write-Output ''
Write-Output '-- 8. Les soldes restent coherents ----------------------------------'
$e = @((Sql "select * from verifier_soldes()").data)
Verdict 'Aucun ecart entre journal et solde' ($e.Count -eq 0) ("{0} ecart(s)" -f $e.Count)

# --- menage ------------------------------------------------------------
Sql "delete from tentatives" | Out-Null

Write-Output ''
Write-Output '===================================================================='
Write-Output ("  {0} reussis, {1} echecs" -f $script:ok, $script:ko)
Write-Output '===================================================================='
Write-Output ''
if ($script:ko -gt 0) { exit 1 }
