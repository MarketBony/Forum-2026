#requires -Version 5
# =====================================================================
#  banc-jour-j.ps1 — les SIX PROFILS EN MÊME TEMPS, au rythme réel,
#  pendant que l'occupation du pool est relevée en continu.
#
#  ---------------------------------------------------------------------
#  POURQUOI CE BANC EXISTE, ALORS QU'IL Y EN A DÉJÀ QUATRE
#
#  Les quatre bancs existants mesurent chacun une chose, seule :
#    test-charge.ps1     400 garages qui sondent — garages SEULEMENT,
#                        et les phases s'enchaînent au lieu de se
#                        superposer ;
#    charge-vitrine.ps1  140 vitrines — en rafale, pas en régime ;
#    simuler-forum.ps1   une journée d'écritures — mais elle REMET LA
#                        BASE À ZÉRO, donc elle est interdite depuis
#                        le 16 au soir ;
#    trouver-plafond.ps1 une rafale montante — sans mélange de profils.
#
#  Or la panne de GRID du 8 septembre 2026 n'est venue d'aucun profil
#  pris isolément : elle est venue de la SIMULTANÉITÉ. 25 postes qui
#  réagissaient au même message à la même milliseconde sur un pool de
#  10 connexions. Aucun banc mono-profil ne pouvait la voir, et aucune
#  des 210 vérifications automatiques de GRID ne l'a vue.
#
#  Ce banc-ci joue donc les 342 appareils ENSEMBLE, et il ajoute le
#  scénario que GRID a subi : la meute — tout le monde qui appelle dans
#  la même seconde. Au Forum, ça arrive quand une annonce au micro fait
#  sortir 340 téléphones des poches en même temps, ou quand le wifi
#  revient après une coupure.
#
#  ---------------------------------------------------------------------
#  CE QU'IL MESURE            latence p50/p95/p99 et taux d'échec, PAR
#                             PROFIL, plus l'occupation réelle du pool
#                             PostgREST relevée toutes les 2 secondes
#                             pendant que la charge tourne.
#
#  CE QU'IL N'ÉCRIT PAS       aucune ligne de journal, aucun solde,
#                             aucune case. Il est en LECTURE SEULE sur
#                             les données du Forum. Le chemin d'écriture
#                             a déjà été éprouvé le 15 septembre par
#                             simuler-forum.ps1 : 5 800 écritures,
#                             0 échec, 0 écart de solde. Ce n'est pas
#                             lui qu'il reste à prouver.
#
#  CE QU'IL ÉCRIT QUAND MÊME  342 lignes dans `appareils`, marquées
#                             `BANC JOUR J`, effacées à la fin. Elles
#                             sont posées en SQL et non par api_ouvrir :
#                             ouvrir 200 sessions par la porte
#                             consommerait une place d'appareil sur 200
#                             VRAIS garages (plafond de 6), et un
#                             garagiste qui arrive avec son téléphone
#                             jeudi trouverait une place en moins.
#
#  CE QU'IL NE PROUVE PAS     les 342 sessions partent d'UNE machine et
#                             d'UNE connexion Internet. Il mesure
#                             Supabase, pas le wifi de la Grande Halle.
#                             Le wifi reste le risque le plus probable
#                             de la soirée, et aucun script ne le
#                             testera jamais.
#
#    .\scripts\banc-jour-j.ps1                       # régime + meute, 3 min
#    .\scripts\banc-jour-j.ps1 -Minutes 10           # plus long
#    .\scripts\banc-jour-j.ps1 -Facteur 3            # 3x le rythme réel
#    .\scripts\banc-jour-j.ps1 -Garder               # laisse les sessions
# =====================================================================
[CmdletBinding()]
param(
  [int]$Garages   = 200,   # téléphones de garagistes qui sondent leur solde
  [int]$Vitrines  = 140,   # 119 équipe Bony + 21 constructeurs
  [int]$Tablettes = 2,     # supervision Bony
  [int]$Accueils  = 2,     # les deux hôtesses
  [int]$Minutes   = 3,     # durée du régime permanent
  [int]$Facteur   = 1,     # 1 = rythme réel ; 3 = trois fois plus vite
  [switch]$SansMeute,      # ne joue que le régime permanent
  [switch]$Garder          # ne supprime pas les sessions du banc à la fin
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http

# Sans ce relèvement, .NET plafonne à 2 connexions par hôte et le banc
# mesurerait le client au lieu du serveur. Piège déjà payé deux fois.
[System.Net.ServicePointManager]::DefaultConnectionLimit = 2000
[System.Net.ServicePointManager]::Expect100Continue = $false
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# --- environnement ----------------------------------------------------
$conf = @{}
Get-Content (Join-Path $PSScriptRoot '..\.env.local') -Encoding UTF8 | ForEach-Object {
  if ($_ -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $conf[$Matches[1]] = $Matches[2].Trim() }
}
$base = $conf['SUPABASE_URL'].TrimEnd('/')
$pub  = $conf['SUPABASE_PUBLISHABLE_KEY']
$ref  = $conf['SUPABASE_PROJECT_REF']
$pat  = $conf['SUPABASE_ACCESS_TOKEN']

$cli = New-Object System.Net.Http.HttpClient
$cli.Timeout = [TimeSpan]::FromSeconds(180)

function Sql($requete) {
  $c = New-Object System.Net.Http.StringContent(
        (@{ query = $requete } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
  $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post,
        "https://api.supabase.com/v1/projects/$ref/database/query")
  $m.Headers.Add('Authorization', "Bearer $pat")
  $m.Content = $c
  $r = $cli.SendAsync($m).Result
  $t = $r.Content.ReadAsStringAsync().Result
  if (-not $r.IsSuccessStatusCode) { throw "SQL : HTTP $([int]$r.StatusCode) — $t" }
  # ConvertFrom-Json rend un tableau comme UN SEUL objet : on assigne
  # sans @(), on compte avec @() au moment de compter.
  return ($t | ConvertFrom-Json)
}

Write-Output ''
Write-Output '===================================================================='
Write-Output '  BANC DU JOUR J — les six profils en même temps'
Write-Output '===================================================================='
Write-Output ''

# ---------------------------------------------------------------------
#  GARDE-FOU : si le Forum a commencé, on ne joue pas avec.
#  Un banc qui ouvre 342 sessions pendant que des garagistes achètent
#  des cases fausse leur soirée et fausse la mesure. Le compteur du
#  journal est le seul juge fiable : à zéro, le Forum n'a pas commencé.
# ---------------------------------------------------------------------
$etat = Sql "select (select count(*) from journal) as journal,
                    (select count(*) from grille where garage_id is not null) as cases,
                    (select count(*) from verifier_soldes()) as ecarts"
if ([int]$etat.journal -gt 0 -or [int]$etat.cases -gt 0) {
  Write-Output ('  ARRET : le journal porte {0} ligne(s) et {1} case(s) sont prises.' -f $etat.journal, $etat.cases)
  Write-Output '  Le Forum a commencé. Ce banc ne doit pas tourner pendant la soirée :'
  Write-Output '  il ajouterait 342 sessions à une charge réelle et fausserait les deux.'
  Write-Output ''
  exit 1
}
Write-Output ('  Base au repos ......... journal {0}, cases {1}, ecarts {2}' -f $etat.journal, $etat.cases, $etat.ecarts)

# ---------------------------------------------------------------------
#  1. Les sessions du banc, posées en SQL et marquées
# ---------------------------------------------------------------------
#  Jetons DÉTERMINISTES : relancer le banc réutilise les mêmes lignes
#  au lieu d'en empiler de nouvelles. Le libellé `BANC JOUR J` est ce
#  qui permet de toutes les retrouver et de toutes les effacer — et de
#  prouver ensuite qu'il n'en reste aucune.
Write-Output '  Pose des sessions ..... en cours'
$poser = @"
insert into public.appareils (jeton, role, garage_id, libelle)
select 'banc' || md5('banc-jour-j|garage|' || g.rg) || md5('sel|garage|' || g.rg),
       'garage', g.id, 'BANC JOUR J'
  from (select id, row_number() over (order by id) as rg
          from public.garages where actif order by id limit $Garages) g
on conflict (jeton) do nothing;

insert into public.appareils (jeton, role, libelle)
select 'banc' || md5('banc-jour-j|vitrine|' || i) || md5('sel|vitrine|' || i),
       'vitrine', 'BANC JOUR J'
  from generate_series(1, $Vitrines) i
on conflict (jeton) do nothing;

insert into public.appareils (jeton, role, libelle)
select 'banc' || md5('banc-jour-j|admin|' || i) || md5('sel|admin|' || i),
       'admin', 'BANC JOUR J'
  from generate_series(1, $Tablettes) i
on conflict (jeton) do nothing;

insert into public.appareils (jeton, role, libelle)
select 'banc' || md5('banc-jour-j|accueil|' || i) || md5('sel|accueil|' || i),
       'accueil', 'BANC JOUR J'
  from generate_series(1, $Accueils) i
on conflict (jeton) do nothing;

select role, count(*) as n, jsonb_agg(jeton order by jeton) as jetons
  from public.appareils where libelle = 'BANC JOUR J' group by role order by role;
"@
$sessions = Sql $poser
$parRole = @{}
foreach ($l in $sessions) { $parRole[$l.role] = @($l.jetons) }
foreach ($r in ($parRole.Keys | Sort-Object)) {
  Write-Output ('  Sessions {0,-12} {1}' -f $r, @($parRole[$r]).Count)
}
Write-Output ''

# ---------------------------------------------------------------------
#  2. Le générateur de charge
# ---------------------------------------------------------------------
#  Un profil = une URL, un corps par appareil virtuel, un rythme. Tous
#  les profils tournent DANS LE MÊME Task.WaitAll : c'est le point de ce
#  banc, et c'est ce qu'aucun des quatre autres ne fait.
if (-not ("BancMulti" -as [type])) {
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

public class Profil {
  public string Nom;
  public string Url;
  public string[] Corps;     // un par appareil virtuel
  public int PaceMs;         // 0 = une seule requête (rafale)
  public bool Disperser;     // départs échelonnés (le régime permanent)
}

public class Bilan {
  public string Nom;
  public double[] Latences;
  public int Total, Succes, Erreurs;
  public string DetailErreurs;
}

public class BancMulti {
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

  // Tous les profils partent ensemble et s'arrêtent ensemble.
  public static Bilan[] Executer(Profil[] profils, int dureeSec) {
    var lat = new ConcurrentDictionary<string, ConcurrentBag<double>>();
    var codes = new ConcurrentDictionary<string, ConcurrentDictionary<string,int>>();
    foreach (var p in profils) {
      lat[p.Nom] = new ConcurrentBag<double>();
      codes[p.Nom] = new ConcurrentDictionary<string,int>();
    }

    var chrono = Stopwatch.StartNew();
    var fin = TimeSpan.FromSeconds(dureeSec);
    var taches = new List<Task>();

    foreach (var p in profils) {
      var prof = p;
      for (int w = 0; w < prof.Corps.Length; w++) {
        string gabarit = prof.Corps[w];
        int seed = w + prof.Nom.GetHashCode();
        taches.Add(Task.Run(async () => {
          var rnd = new Random(seed);
          // Départs échelonnés : 340 téléphones ne s'allument pas à la
          // milliseconde près. Les faire partir ensemble en régime
          // permanent fabriquerait une meute permanente, qui est un
          // artefact — la meute se teste à part, phase 2.
          if (prof.Disperser && prof.PaceMs > 0)
            await Task.Delay(rnd.Next(0, Math.Min(prof.PaceMs, 30000)));
          do {
            string charge = gabarit;
            var t0 = chrono.Elapsed.TotalMilliseconds;
            try {
              using (var ct = new StringContent(charge, Encoding.UTF8, "application/json"))
              using (var rep = await _c.PostAsync(prof.Url, ct)) {
                await rep.Content.ReadAsStringAsync();
                lat[prof.Nom].Add(chrono.Elapsed.TotalMilliseconds - t0);
                codes[prof.Nom].AddOrUpdate(((int)rep.StatusCode).ToString(), 1, (k, v) => v + 1);
              }
            } catch (Exception ex) {
              lat[prof.Nom].Add(chrono.Elapsed.TotalMilliseconds - t0);
              codes[prof.Nom].AddOrUpdate("EX:" + ex.GetType().Name, 1, (k, v) => v + 1);
            }
            if (prof.PaceMs == 0) break;
            await Task.Delay(prof.PaceMs);
          } while (chrono.Elapsed < fin);
        }));
      }
    }
    Task.WaitAll(taches.ToArray());
    chrono.Stop();

    var sortie = new List<Bilan>();
    foreach (var p in profils) {
      var b = new Bilan();
      b.Nom = p.Nom;
      b.Latences = lat[p.Nom].OrderBy(x => x).ToArray();
      b.Total = b.Latences.Length;
      b.Succes = codes[p.Nom].Where(k => k.Key == "200").Sum(k => k.Value);
      b.Erreurs = b.Total - b.Succes;
      b.DetailErreurs = string.Join(", ", codes[p.Nom].Where(k => k.Key != "200")
                                          .Select(k => k.Key + " x" + k.Value));
      sortie.Add(b);
    }
    return sortie.ToArray();
  }
}
'@ -ReferencedAssemblies 'System.Net.Http','System.Core' | Out-Null
}
[BancMulti]::Init($pub)

function Corps($jetons, $modele) {
  # ConvertTo-Json sur un hashtable d'un seul champ suffit ici : les
  # jetons sont hexadécimaux, aucun échappement à craindre.
  $sortie = New-Object System.Collections.ArrayList
  foreach ($j in @($jetons)) { [void]$sortie.Add(($modele -f $j)) }
  return $sortie.ToArray()
}

# ---------------------------------------------------------------------
#  3. Les profils, au rythme RÉEL de l'application
# ---------------------------------------------------------------------
#  Les rythmes viennent de app/config.js (sondageMs 30 000,
#  sondageAdminMs 10 000) et de app/js/app.js:1716. Les changer ici
#  sans les changer là-bas mesurerait une application qui n'existe pas.
$paceGarage  = [int](30000 / $Facteur)
$paceVitrine = [int](30000 / $Facteur)
$paceAdmin   = [int](10000 / $Facteur)
$paceAccueil = [int](4000  / $Facteur)   # une hôtesse qui cherche par intermittence

$profils = [Profil[]]@(
  (New-Object Profil -Property @{
     Nom = 'garage (api_etat)'; Url = "$base/rest/v1/rpc/api_etat";
     Corps = (Corps $parRole['garage'] '{{"p_jeton":"{0}"}}'); PaceMs = $paceGarage; Disperser = $true }),
  (New-Object Profil -Property @{
     Nom = 'vitrine (api_vitrine)'; Url = "$base/rest/v1/rpc/api_vitrine";
     Corps = (Corps $parRole['vitrine'] '{{"p_jeton":"{0}"}}'); PaceMs = $paceVitrine; Disperser = $true }),
  (New-Object Profil -Property @{
     Nom = 'Bony (api_supervision)'; Url = "$base/rest/v1/rpc/api_supervision";
     Corps = (Corps $parRole['admin'] '{{"p_jeton":"{0}"}}'); PaceMs = $paceAdmin; Disperser = $true }),
  (New-Object Profil -Property @{
     Nom = 'accueil (recherche)'; Url = "$base/rest/v1/rpc/api_accueil_chercher";
     Corps = (Corps $parRole['accueil'] '{{"p_jeton":"{0}","p_q":"mar"}}'); PaceMs = $paceAccueil; Disperser = $true })
)

$total = 0; foreach ($p in $profils) { $total += $p.Corps.Count }
Write-Output ('  {0} appareils virtuels, rythme reel x{1}' -f $total, $Facteur)
Write-Output ('  Debit theorique ....... {0:N1} req/s' -f (
  ($profils | ForEach-Object { $_.Corps.Count * 1000.0 / $_.PaceMs } | Measure-Object -Sum).Sum))
Write-Output ''

# ---------------------------------------------------------------------
#  4. Le relevé du pool, PENDANT que la charge tourne
# ---------------------------------------------------------------------
#  C'est le seul instrument qui aurait vu venir la panne de GRID : un
#  pool saturé ne se voit ni dans le taux d'erreur (les requêtes
#  finissent par passer) ni dans pg_stat_statements (les requêtes
#  refoulées n'y figurent JAMAIS). Il se voit ici, et nulle part
#  ailleurs : des connexions `authenticator` en `active`, et des
#  attentes en `ClientRead`.
$releve = @'
select count(*) filter (where usename = 'authenticator')                          as pool,
       count(*) filter (where usename = 'authenticator' and state = 'active')     as actives,
       count(*) filter (where usename = 'authenticator' and state = 'idle in transaction') as bloquees,
       count(*) filter (where wait_event_type = 'Lock')                           as verrous,
       count(*) filter (where usename = 'authenticator' and wait_event = 'ClientRead') as clientread
  from pg_stat_activity where datname = current_database()
'@

$sonde = [powershell]::Create()
[void]$sonde.AddScript({
  param($uri, $jeton, $requete, $secondes)
  Add-Type -AssemblyName System.Net.Http
  $c = New-Object System.Net.Http.HttpClient
  $c.Timeout = [TimeSpan]::FromSeconds(20)
  $fin = (Get-Date).AddSeconds($secondes)
  $sortie = New-Object System.Collections.ArrayList
  while ((Get-Date) -lt $fin) {
    try {
      $ct = New-Object System.Net.Http.StringContent(
             (@{ query = $requete } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8, 'application/json')
      $m = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, $uri)
      $m.Headers.Add('Authorization', "Bearer $jeton")
      $m.Content = $ct
      $r = $c.SendAsync($m).Result
      $t = $r.Content.ReadAsStringAsync().Result
      if ($r.IsSuccessStatusCode) { [void]$sortie.Add(($t | ConvertFrom-Json)) }
    } catch { }
    # 600 ms et pas 2 s : une rafale de meute s'écoule en moins de deux
    # secondes, et un échantillonnage à 2 s peut la manquer ENTIÈREMENT
    # — on conclurait « le pool n'a rien vu » alors qu'on n'a pas
    # regardé. L'appel de sonde coûte lui-même ~150 ms, donc on ne
    # descend pas plus bas sans mesurer surtout la sonde.
    Start-Sleep -Milliseconds 600
  }
  return $sortie
})
[void]$sonde.AddParameters(@{
  uri      = "https://api.supabase.com/v1/projects/$ref/database/query"
  jeton    = $pat
  requete  = $releve
  secondes = ($Minutes * 60) + 40
})
$sondeEnCours = $sonde.BeginInvoke()

# ---------------------------------------------------------------------
#  5. Phase 1 — le régime permanent
# ---------------------------------------------------------------------
Write-Output ('--- Phase 1 : regime permanent, {0} minute(s) ------------------------' -f $Minutes)
Write-Output '    (departs echelonnes, comme 342 telephones qui s''allument au fil de'
Write-Output '     la matinee — c''est la charge de fond de la journee)'
Write-Output ''
$bilan1 = [BancMulti]::Executer($profils, $Minutes * 60)

function Rapport($titre, $bilans) {
  Write-Output ('  {0}' -f $titre)
  Write-Output '  profil                   appels     p50      p95      p99      max   echecs'
  Write-Output '  ----------------------- ------- ------- -------- -------- -------- --------'
  foreach ($b in $bilans) {
    $l = $b.Latences
    if ($l.Count -eq 0) { continue }
    $p50 = $l[[int][math]::Floor($l.Count * 0.50)]
    $p95 = $l[[math]::Min($l.Count - 1, [int][math]::Floor($l.Count * 0.95))]
    $p99 = $l[[math]::Min($l.Count - 1, [int][math]::Floor($l.Count * 0.99))]
    Write-Output ('  {0,-23} {1,7} {2,6:N0}ms {3,6:N0}ms {4,6:N0}ms {5,6:N0}ms {6,8}' -f `
      $b.Nom, $b.Total, $p50, $p95, $p99, $l[$l.Count - 1], $b.Erreurs)
    if ($b.Erreurs -gt 0) { Write-Output ('      -> {0}' -f $b.DetailErreurs) }
  }
  Write-Output ''
}
Rapport 'REGIME PERMANENT' $bilan1

# ---------------------------------------------------------------------
#  6. Phase 2 — LA MEUTE
# ---------------------------------------------------------------------
#  Le scénario exact de GRID : tout le monde appelle dans la même
#  seconde. Au Forum, le déclencheur n'est pas un message diffusé (il
#  n'y a pas de Realtime) mais un geste humain — une annonce au micro,
#  le lancement du grand tirage, ou le retour du wifi après une
#  coupure : `visibilitychange` dans app/js/app.js:2176 relance une
#  lecture DÈS qu'un écran revient au premier plan, sans gigue.
if (-not $SansMeute) {
  Write-Output '--- Phase 2 : LA MEUTE — les 342 appareils dans la meme seconde ------'
  Write-Output '    (le scenario qui a tue GRID le 8 septembre : ici il n''y a pas de'
  Write-Output '     diffusion, mais visibilitychange fait le meme effet si toute la'
  Write-Output '     salle sort son telephone en meme temps)'
  Write-Output ''
  for ($tour = 1; $tour -le 3; $tour++) {
    $rafale = New-Object 'System.Collections.Generic.List[Profil]'
    foreach ($p in $profils) {
      $rafale.Add((New-Object Profil -Property @{
        Nom = $p.Nom; Url = $p.Url; Corps = $p.Corps; PaceMs = 0; Disperser = $false }))
    }
    $t0 = Get-Date
    $b = [BancMulti]::Executer($rafale.ToArray(), 60)
    $duree = ((Get-Date) - $t0).TotalMilliseconds
    $n = 0; $e = 0
    foreach ($x in $b) { $n += $x.Total; $e += $x.Erreurs }
    Write-Output ('  Tour {0} : {1} requetes simultanees ecoulees en {2:N0} ms — {3} echec(s)' -f `
      $tour, $n, $duree, $e)
    if ($tour -eq 3) { Rapport 'MEUTE (3e tour, pool chaud)' $b }
    else { Start-Sleep -Seconds 5 }
  }
}

# ---------------------------------------------------------------------
#  7. Ce que le pool a vraiment fait pendant ce temps
# ---------------------------------------------------------------------
$echantillons = @($sonde.EndInvoke($sondeEnCours))
$sonde.Dispose()

Write-Output '--- Occupation du pool PostgREST pendant le banc ----------------------'
if ($echantillons.Count -eq 0) {
  Write-Output '  Aucun echantillon (la sonde n''a rien rendu).'
} else {
  $plat = New-Object System.Collections.ArrayList
  foreach ($e in $echantillons) { foreach ($l in @($e)) { [void]$plat.Add($l) } }
  $act = @($plat | ForEach-Object { [int]$_.actives })
  $poo = @($plat | ForEach-Object { [int]$_.pool })
  $blo = @($plat | ForEach-Object { [int]$_.bloquees })
  $ver = @($plat | ForEach-Object { [int]$_.verrous })
  Write-Output ('  Echantillons .......... {0} (toutes les 600 ms)' -f $plat.Count)
  Write-Output ('  Connexions du pool .... max {0}  (le plafond mesure est 11)' -f (($poo | Measure-Object -Maximum).Maximum))
  Write-Output ('  Connexions ACTIVES .... max {0}, moyenne {1:N2}   <-- LE chiffre' -f `
    (($act | Measure-Object -Maximum).Maximum), (($act | Measure-Object -Average).Average))
  Write-Output ('  Idle in transaction ... max {0}  (doit rester a 0)' -f (($blo | Measure-Object -Maximum).Maximum))
  Write-Output ('  Attentes de verrou .... max {0}  (doit rester a 0)' -f (($ver | Measure-Object -Maximum).Maximum))
  Write-Output ''
  Write-Output '  Rappel de lecture : un pool qui GRANDIT n''est pas un pool occupe.'
  Write-Output '  PostgREST garde ses connexions ouvertes en `idle` une fois ouvertes.'
  Write-Output '  L''occupation, c''est ACTIVES sur 11 — et rien d''autre.'
}
Write-Output ''

# ---------------------------------------------------------------------
#  8. Ménage — et la preuve qu'il a eu lieu
# ---------------------------------------------------------------------
if ($Garder) {
  Write-Output '  Sessions du banc CONSERVEES (-Garder). Pour les retirer :'
  Write-Output '    .\scripts\push-sql.ps1 -Query "delete from appareils where libelle = ''BANC JOUR J''"'
} else {
  $reste = Sql @"
delete from public.appareils where libelle = 'BANC JOUR J';
select (select count(*) from public.appareils where libelle = 'BANC JOUR J') as restantes,
       (select count(*) from public.appareils) as appareils,
       (select count(*) from public.journal) as journal,
       (select count(*) from public.grille where garage_id is not null) as cases,
       (select count(*) from verifier_soldes()) as ecarts;
"@
  Write-Output ('  Menage ................ {0} session(s) du banc restante(s)' -f $reste.restantes)
  Write-Output ('  Etat final ............ appareils {0}, journal {1}, cases {2}, ecarts {3}' -f `
    $reste.appareils, $reste.journal, $reste.cases, $reste.ecarts)
  if ([int]$reste.journal -ne 0 -or [int]$reste.cases -ne 0 -or [int]$reste.ecarts -ne 0) {
    Write-Output ''
    Write-Output '  ATTENTION : la base n''est plus a zero. Ce banc n''ecrit pourtant'
    Write-Output '  rien dans le journal — verifiez si quelqu''un utilise l''application.'
  }
}
Write-Output ''
