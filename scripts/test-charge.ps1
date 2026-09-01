#requires -Version 5
# =====================================================================
#  test-charge.ps1
#  Mesure la tenue en charge du projet Supabase GRATUIT, sur le chemin
#  réel de l'application (PostgREST + clé publique).
#
#    .\scripts\test-charge.ps1
#
#  Scénario, calé sur la soirée du 17 septembre 2026 :
#    Phase 0  400 inscriptions en rafale        (ouverture des portes)
#    Phase 1  400 participants, sondage 30 s    (~13 req/s — le nominal)
#    Phase 2  idem à 6 s                        (~66 req/s — 5x le nominal)
#    Phase 3  idem à 3 s                        (~133 req/s — 10x)
#    Phase 4  8 animateurs qui écrivent en même temps que les lectures
# =====================================================================
$ErrorActionPreference = 'Stop'

$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$base = $conf['SUPABASE_URL'].TrimEnd('/')
$pub  = $conf['SUPABASE_PUBLISHABLE_KEY']
$ref  = $conf['SUPABASE_PROJECT_REF']
$pat  = $conf['SUPABASE_ACCESS_TOKEN']

# ---------------------------------------------------------------------
#  Générateur de charge en C# : mesure fiable des latences en asynchrone.
#  ServicePointManager.DefaultConnectionLimit est indispensable — sa
#  valeur par défaut (2 connexions par hôte) serialiserait tout.
# ---------------------------------------------------------------------
if (-not ("Charge" -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public class Resultat {
  public double[] Latences;
  public int Total;
  public int Succes;
  public int Erreurs;
  public string DetailErreurs;
  public double DureeSec;
  public double DebitReel;
}

public class Charge {
  static HttpClient _c;

  public static void Init(string apikey) {
    ServicePointManager.DefaultConnectionLimit = 2000;
    ServicePointManager.Expect100Continue = false;
    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
    var h = new HttpClientHandler { MaxConnectionsPerServer = 2000, UseProxy = false };
    _c = new HttpClient(h);
    _c.DefaultRequestHeaders.Add("apikey", apikey);
    _c.DefaultRequestHeaders.Add("Authorization", "Bearer " + apikey);
    _c.Timeout = TimeSpan.FromSeconds(30);
  }

  // corps[] : un gabarit JSON par travailleur. "@@CLE@@" est remplacé par
  // un identifiant unique à chaque envoi (clé d'idempotence).
  // paceMs = 0 -> chaque travailleur envoie une seule requête (rafale).
  public static Resultat Executer(string url, string[] corps, int dureeSec, int paceMs) {
    var lat = new ConcurrentBag<double>();
    var codes = new ConcurrentDictionary<string, int>();
    var chrono = Stopwatch.StartNew();
    var fin = paceMs == 0 ? TimeSpan.Zero : TimeSpan.FromSeconds(dureeSec);

    var taches = new List<Task>();
    for (int w = 0; w < corps.Length; w++) {
      string gabarit = corps[w];
      int seed = w;
      taches.Add(Task.Run(async () => {
        var rnd = new Random(seed * 7919 + 13);
        // départs échelonnés : on ne fait pas partir 400 téléphones à la
        // milliseconde près, ce serait un artefact de test
        if (paceMs > 0) await Task.Delay(rnd.Next(0, Math.Min(paceMs, 3000)));
        do {
          string charge = gabarit.Replace("@@CLE@@", Guid.NewGuid().ToString("N"));
          var t0 = chrono.Elapsed.TotalMilliseconds;
          try {
            using (var ct = new StringContent(charge, Encoding.UTF8, "application/json"))
            using (var rep = await _c.PostAsync(url, ct)) {
              await rep.Content.ReadAsStringAsync();
              lat.Add(chrono.Elapsed.TotalMilliseconds - t0);
              codes.AddOrUpdate(((int)rep.StatusCode).ToString(), 1, (k, v) => v + 1);
            }
          } catch (Exception ex) {
            lat.Add(chrono.Elapsed.TotalMilliseconds - t0);
            var n = ex.GetType().Name;
            codes.AddOrUpdate("EX:" + n, 1, (k, v) => v + 1);
          }
          if (paceMs == 0) break;
          await Task.Delay(paceMs);
        } while (chrono.Elapsed < fin);
      }));
    }
    Task.WaitAll(taches.ToArray());
    chrono.Stop();

    var r = new Resultat();
    r.Latences = lat.OrderBy(x => x).ToArray();
    r.Total = r.Latences.Length;
    r.Succes  = codes.Where(k => k.Key == "200").Sum(k => k.Value);
    r.Erreurs = r.Total - r.Succes;
    r.DetailErreurs = string.Join(", ", codes.Where(k => k.Key != "200")
                                             .Select(k => k.Key + " x" + k.Value));
    r.DureeSec = chrono.Elapsed.TotalSeconds;
    r.DebitReel = r.Total / Math.Max(chrono.Elapsed.TotalSeconds, 0.001);
    return r;
  }
}
'@ -ReferencedAssemblies 'System.Net.Http','System.Core' | Out-Null
}
[Charge]::Init($pub)

Add-Type -AssemblyName System.Net.Http
# $cli : API de management (l'autorisation est posée par message)
$cli = New-Object System.Net.Http.HttpClient
# $rest : PostgREST, avec la clé publique en en-tête par défaut
$rest = New-Object System.Net.Http.HttpClient
$rest.DefaultRequestHeaders.Add('apikey', $pub)
$rest.DefaultRequestHeaders.Add('Authorization', "Bearer $pub")

function Post($url, $obj) {
  $c = New-Object System.Net.Http.StringContent(
        ($obj | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $r = $rest.PostAsync($url, $c).Result
  $b = $r.Content.ReadAsStringAsync().Result
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; http = [int]$r.StatusCode; data = $o }
}

function Sql($q) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $q } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat"); $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $b = $r.Content.ReadAsStringAsync().Result
  $o = $null; try { $o = $b | ConvertFrom-Json } catch {}
  return @{ ok = $r.IsSuccessStatusCode; http = [int]$r.StatusCode; data = $o }
}

function Pct($tri, $p) {
  if ($tri.Count -eq 0) { return 0 }
  $i = [Math]::Ceiling($p / 100.0 * $tri.Count) - 1
  if ($i -lt 0) { $i = 0 }
  return [Math]::Round($tri[$i], 0)
}
function Rapport($titre, $r, $cible) {
  $l = @($r.Latences)
  Write-Output ''
  Write-Output ("  $titre")
  Write-Output ("    requetes      : {0}  en {1:N1} s  ->  {2:N1} req/s reelles (cible {3})" -f `
                 $r.Total, $r.DureeSec, $r.DebitReel, $cible)
  Write-Output ("    latence       : med {0} ms | p95 {1} ms | p99 {2} ms | max {3} ms" -f `
                 (Pct $l 50), (Pct $l 95), (Pct $l 99), (Pct $l 100))
  if ($r.Erreurs -eq 0) {
    Write-Output ("    erreurs       : 0  (100 % de reussite)")
  } else {
    Write-Output ("    erreurs       : {0} sur {1}  ({2:N2} %)  -> {3}" -f `
                   $r.Erreurs, $r.Total, (100.0 * $r.Erreurs / $r.Total), $r.DetailErreurs)
  }
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Test de charge - Supabase plan GRATUIT - region eu-west-3 (Paris)'
Write-Output '===================================================================='

# ---------------------------------------------------------------------
Write-Output ''
Write-Output '--- Preparation : remise a zero -------------------------------------'
$rz = Sql @'
delete from public.tirage;
delete from public.tentatives;
update public.grille set garage_id=null, journal_id=null, achete_le=null, revele_le=null,
       code_retrait=null, remis=false, remis_le=null;
alter table public.journal disable trigger journal_pas_de_modif;
delete from public.journal;
alter table public.journal enable trigger journal_pas_de_modif;
update public.garages set solde=0, inscrit_le=null;
delete from public.appareils;
select count(*)::int as n from public.garages;
'@
Write-Output ("  Base propre : " + $rz.data[0].n + " garages")

# On simule 400 arrivées : chaque garage entre par SON code, comme le
# fera un garagiste. La base compte 1 407 invités, on en prend 400.
$ids = (Sql "select id, code from public.garages order by nom limit 400").data
$jetons = @()
foreach ($g in $ids) { $jetons += (([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N'))) }

# ---------------------------------------------------------------------
Write-Output ''
Write-Output '--- Phase 0 : 400 entrees par code en rafale (ouverture des portes) ---'
$corps = @()
for ($i = 0; $i -lt 400; $i++) {
  $corps += (@{ p_jeton = $jetons[$i]; p_code = $ids[$i].code } | ConvertTo-Json -Compress)
}
$r0 = [Charge]::Executer("$base/rest/v1/rpc/api_entrer", $corps, 0, 0)
Rapport 'Phase 0 - entrees simultanees' $r0 'rafale'
$inscrits = (Sql "select count(*)::int as n from public.garages where inscrit_le is not null").data[0].n
Write-Output ("    controle      : {0} garages inscrits en base" -f $inscrits)

# ---------------------------------------------------------------------
$corpsEtat = @()
for ($i = 0; $i -lt 400; $i++) { $corpsEtat += (@{ p_jeton = $jetons[$i] } | ConvertTo-Json -Compress) }

Write-Output ''
Write-Output '--- Phases 1 a 3 : 400 participants qui consultent leur solde --------'
$r1 = [Charge]::Executer("$base/rest/v1/rpc/api_etat", $corpsEtat, 40, 30000)
Rapport 'Phase 1 - sondage 30 s (le nominal)' $r1 '~13 req/s'

# Phase 2 jouee DEUX FOIS : la premiere passe subit l'etablissement de
# 400 connexions TLS neuves, la seconde travaille sur un pool chaud.
# C'est ce qui distingue un artefact de client d'une saturation serveur.
$r2a = [Charge]::Executer("$base/rest/v1/rpc/api_etat", $corpsEtat, 40, 6000)
Rapport 'Phase 2a - sondage 6 s, pool de connexions froid' $r2a '~66 req/s'

$r2b = [Charge]::Executer("$base/rest/v1/rpc/api_etat", $corpsEtat, 40, 6000)
Rapport 'Phase 2b - sondage 6 s, pool de connexions chaud' $r2b '~66 req/s'

$r3 = [Charge]::Executer("$base/rest/v1/rpc/api_etat", $corpsEtat, 40, 3000)
Rapport 'Phase 3 - sondage 3 s (10x le nominal)' $r3 '~133 req/s'

# ---------------------------------------------------------------------
Write-Output ''
Write-Output '--- Phase 4 : ecritures animateurs pendant les lectures --------------'
# 8 animateurs connectes sur les 4 animations
$idAnim = (Sql "select id from public.animations order by ordre limit 1").data[0].id

# Les 8 garages cibles doivent pouvoir payer ~50 participations a 2 pts.
# On les dote via le journal, pour que l'invariant reste vrai.
$cibles = @(); for ($i = 0; $i -lt 8; $i++) { $cibles += $ids[$i * 7].id }
$listeSql = ($cibles | ForEach-Object { "'" + $_ + "'" }) -join ','
Sql @"
insert into public.journal (garage_id, delta, libelle, source, cle_idem)
select id, 500, 'Dotation test de charge', 'administration',
       'charge-' || id::text
  from public.garages where id in ($listeSql)
on conflict (cle_idem) do nothing;
update public.garages g
   set solde = (select coalesce(sum(delta),0) from public.journal j where j.garage_id = g.id)
 where g.id in ($listeSql);
"@ | Out-Null

$corpsAnim = @()
$connectes = 0
for ($i = 0; $i -lt 8; $i++) {
  $jt = (([guid]::NewGuid().ToString('N')) + ([guid]::NewGuid().ToString('N')))
  $co = Post "$base/rest/v1/rpc/api_connexion" @{ p_jeton = $jt; p_pin = '1001' }
  if ($co.ok) { $connectes++ }
  $corpsAnim += (@{ p_jeton = $jt; p_garage = $cibles[$i]; p_animation = $idAnim; p_cle = '@@CLE@@' } | ConvertTo-Json -Compress)
}
Write-Output ("  animateurs connectes : {0}/8" -f $connectes)

$r4 = [Charge]::Executer("$base/rest/v1/rpc/api_participation", $corpsAnim, 40, 900)
Rapport 'Phase 4 - 8 animateurs en ecriture continue' $r4 '~9 ecritures/s'

# ---------------------------------------------------------------------
Write-Output ''
Write-Output '--- Controles de coherence apres la charge ---------------------------'
$fin = (Sql @'
select
  (select count(*)::int from public.journal)                  as lignes_journal,
  (select count(*)::int from public.appareils)                as appareils,
  (select count(*)::int from public.verifier_soldes())        as ecarts_solde,
  (select count(distinct cle_idem)::int from public.journal)  as cles_distinctes,
  (select pg_size_pretty(pg_database_size(current_database()))) as taille_base
'@).data[0]
Write-Output ("  lignes de journal      : " + $fin.lignes_journal)
Write-Output ("  cles idempotence uniq. : " + $fin.cles_distinctes + "  (doit egaler le nombre de lignes)")
Write-Output ("  appareils enregistres  : " + $fin.appareils)
Write-Output ("  ecarts solde/journal   : " + $fin.ecarts_solde + "  (doit valoir 0)")
Write-Output ("  taille de la base      : " + $fin.taille_base)

Write-Output ''
Write-Output '===================================================================='
Write-Output '  Fin du test de charge'
Write-Output '===================================================================='
