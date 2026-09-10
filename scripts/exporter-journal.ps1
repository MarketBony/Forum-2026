#requires -Version 5
# =====================================================================
#  exporter-journal.ps1 — la vraie protection des données de la soirée
#
#  POURQUOI CE SCRIPT EXISTE. L'offre gratuite de Supabase ne garde
#  aucune sauvegarde ; l'offre payante en garde une par jour, prise la
#  nuit. Ni l'une ni l'autre ne contient les données du 17 septembre au
#  moment où elles comptent, c'est-à-dire PENDANT la soirée. La seule
#  chose qui protège vraiment une soirée, c'est un export pendant la
#  soirée.
#
#  Ce que l'export contient : le journal en entier — chaque point, son
#  auteur, son heure, son motif — les soldes, les lots gagnés et leur
#  code de retrait, et les arrivées. De quoi tout reconstituer et, au
#  pire, terminer la soirée au papier sans avoir rien perdu.
#
#    .\scripts\exporter-journal.ps1
#    .\scripts\exporter-journal.ps1 -Dossier D:\sauvegardes
# =====================================================================
param([string]$Dossier = (Join-Path $PSScriptRoot '..\exports'))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$ref = $conf['SUPABASE_PROJECT_REF']
$pat = $conf['SUPABASE_ACCESS_TOKEN']

$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(60)

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  if (-not $r.IsSuccessStatusCode) { throw "Export impossible : HTTP $([int]$r.StatusCode)" }
  return ($r.Content.ReadAsStringAsync().Result | ConvertFrom-Json)
}

if (-not (Test-Path $Dossier)) { New-Item -ItemType Directory -Force $Dossier | Out-Null }
$horo = Get-Date -Format 'yyyy-MM-dd_HHmm'

Write-Output ''
Write-Output ("  Export du {0}" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'))

# --- 1. Le journal, la pièce maîtresse -------------------------------
$journal = Sql @"
select j.id,
       to_char(j.cree_le at time zone 'Europe/Paris', 'YYYY-MM-DD HH24:MI:SS') as heure,
       g.nom as garage, g.ville, g.code, j.delta, j.libelle, j.source,
       coalesce(a.nom, s.nom, '') as origine
from public.journal j
join public.garages g on g.id = j.garage_id
left join public.animations a on a.id = j.animation_id
left join public.stands s on s.id = j.stand_id
order by j.id
"@
$f = Join-Path $Dossier "journal_$horo.csv"
$journal | Export-Csv -Path $f -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Write-Output ("  Journal          : {0,5} ecritures  ->  {1}" -f $journal.Count, (Split-Path $f -Leaf))

# --- 2. Les soldes ----------------------------------------------------
$soldes = Sql @"
select g.code, g.nom, g.ville, g.cp, g.solde,
       to_char(g.inscrit_le at time zone 'Europe/Paris', 'HH24:MI') as arrive_a
from public.garages g where g.inscrit_le is not null order by g.nom
"@
$f = Join-Path $Dossier "soldes_$horo.csv"
$soldes | Export-Csv -Path $f -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Write-Output ("  Soldes           : {0,5} garages    ->  {1}" -f $soldes.Count, (Split-Path $f -Leaf))

# --- 3. Les lots : qui a gagné quoi, et qui l'a retiré ---------------
$lots = Sql @"
select gr.numero, gr.nature, gr.lot, gr.code_retrait, gr.remis,
       g.nom as garage, g.ville, g.code as code_garage,
       to_char(gr.achete_le at time zone 'Europe/Paris', 'HH24:MI') as joue_a,
       to_char(gr.remis_le  at time zone 'Europe/Paris', 'HH24:MI') as remis_a
from public.grille gr
left join public.garages g on g.id = gr.garage_id
where gr.achete_le is not null order by gr.numero
"@
$f = Join-Path $Dossier "lots_$horo.csv"
$lots | Export-Csv -Path $f -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Write-Output ("  Cases jouees     : {0,5} cases      ->  {1}" -f $lots.Count, (Split-Path $f -Leaf))

# --- 4. Le contrôle de cohérence, joint à l'export -------------------
$ecarts = Sql "select count(*)::int as n from public.verifier_soldes()"
$total  = Sql "select coalesce(sum(delta),0)::int as emis from public.journal where delta > 0"
Write-Output ''
Write-Output ("  Points emis      : {0}" -f $total[0].emis)
if ($ecarts[0].n -eq 0) {
  Write-Output '  Coherence        : OK — aucun ecart entre les soldes et le journal.'
} else {
  Write-Output ("  Coherence        : {0} ECART(S) — le journal fait foi, il est complet ci-dessus." -f $ecarts[0].n)
}
Write-Output ''
Write-Output ("  Tout est dans {0}" -f (Resolve-Path $Dossier).Path)
Write-Output ''
