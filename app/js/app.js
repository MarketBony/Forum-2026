// =====================================================================
//  app.js — Le Grand Bal des Points
//  Quatre profils, une seule page. Pas d'étape de compilation : des
//  modules ES natifs, servis tels quels par Cloudflare Pages.
// =====================================================================
import { CONFIG } from '../config.js';
import * as api from './api.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// ---------------------------------------------------------------------
//  État de l'écran courant
// ---------------------------------------------------------------------
const S = {
  vue: 'chargement',
  r: null,              // rôle : {role, libelle, animation_id, cout, bareme, stand_id...}
  etat: null,           // réponse de api_etat pour un garage
  q: '',                // saisie de recherche
  cible: null,          // garage visé par le personnel
  palier: 20,           // points choisis par le fournisseur
  revele: null,         // résultat d'un tirage
  sup: null,            // tableau de bord Bony
  lots: null,
  cleEnCours: null,     // clé d'idempotence de l'opération en cours
  envoi: false,         // garde anti-double-appui
  horsLigne: !navigator.onLine,
  enFile: 0,
};

// ---------------------------------------------------------------------
//  Décor — guirlande et loupiottes, réservés aux écrans garage
// ---------------------------------------------------------------------
const LOUPIOTTES = [
  [6,9,9,4.2,0],[16,6,6,5.1,1.2],[27,13,5,3.6,.6],[38,8,8,4.8,2.1],[49,12,6,3.9,.4],
  [61,7,10,5.4,1.7],[72,14,5,4.0,2.6],[84,9,7,5.3,.9],[93,13,6,4.6,1.4],
  [9,44,7,4.4,1.1],[31,50,5,5.6,.3],[54,55,6,3.8,2.0],[77,47,8,5.0,.7],[90,58,5,4.3,1.9],
  [14,78,6,4.9,.2],[44,84,5,3.9,2.3],[68,80,7,5.5,1.3],[88,88,6,4.1,.8],
];

function monterDecor() {
  const d = $('#decor');
  if (d.dataset.pret) return;
  d.innerHTML =
    '<div class="halo h1"></div><div class="halo h2"></div><div class="halo h3"></div>' +
    '<div class="vichy"></div>' +
    LOUPIOTTES.map(([x, y, t, dur, del]) =>
      `<span class="loupiotte" style="left:${x}%;top:${y}%;width:${t}px;height:${t}px;--d:${dur}s;--r:${del}s"></span>`
    ).join('');
  d.dataset.pret = '1';
}

/** Guirlande : fil en courbes de Bézier, ampoules suspendues à hauteurs
 *  et teintes variées. Reprise de la page d'invitation. */
function guirlande() {
  const appuis = [{x:0,y:10},{x:185,y:7},{x:415,y:13},{x:610,y:6},{x:805,y:12},{x:1000,y:9}];
  const creux = [36, 31, 39, 33, 35];
  let d = `M ${appuis[0].x} ${appuis[0].y}`;
  const segs = [];
  for (let i = 0; i < appuis.length - 1; i++) {
    const a = appuis[i], b = appuis[i + 1];
    const cx = (a.x + b.x) / 2, cy = Math.max(a.y, b.y) + creux[i];
    segs.push({ a, b, cx, cy });
    d += ` Q ${cx} ${cy} ${b.x} ${b.y}`;
  }
  const pt = (s, t) => {
    const u = 1 - t;
    return { x: u*u*s.a.x + 2*u*t*s.cx + t*t*s.b.x, y: u*u*s.a.y + 2*u*t*s.cy + t*t*s.b.y };
  };
  const teintes = [['#FFF3D6','#F0C36A'],['#FFE9B0','#E0A23C'],['#FFD9A0','#D98A33'],
                   ['#FFFFFF','#F1E7D2'],['#FFE0C0','#E6824A'],['#FFEFC4','#E9B24A']];
  const places = [[0.30,0.62],[0.28,0.55,0.80],[0.40,0.70],[0.33,0.60,0.85],[0.45,0.72]];
  const tailles = [11,14,10,13,12,15,11,14,10,13,12,11];
  const pendus  = [8,17,5,14,21,10,18,7,13,23,11,16];
  const halos   = [5,9,4,8,11,6,9,5,7,12,6,8];
  const plancher= [.5,.66,.4,.55,.7,.45,.6,.5,.58,.42,.62,.5];
  const durees  = [3.0,4.2,2.6,3.6,4.8,3.2,4.0,2.8,3.4,4.6,3.0,3.8];
  let k = 0, html = '';
  places.forEach((liste, s) => liste.forEach((t) => {
    const p = pt(segs[s], t), c = teintes[k % 6], i = k % 12;
    html += `<span class="ampoule" style="left:${(p.x/1000*100).toFixed(2)}%;top:${(p.y+pendus[i]).toFixed(1)}px;`
          + `--t:${tailles[i]}px;--p:${pendus[i]}px;--g:${halos[i]}px;--c1:${c[0]};--c2:${c[1]};`
          + `--f:${plancher[i]};--dt:${durees[i]}s;--ds:${(durees[i]+2.2).toFixed(1)}s;--dl:${((k*0.37)%3).toFixed(2)}s"></span>`;
    k++;
  }));
  return `<div class="guirlande" aria-hidden="true">
    <svg viewBox="0 0 1000 74" preserveAspectRatio="none"><path class="fil" d="${d}"/></svg>
    <div class="ampoules">${html}</div></div>`;
}

const BLASON = `<svg class="blason" viewBox="0 0 62.09 63.05" aria-hidden="true"><path d="M57.36,24.68c-.41-.47-.85-.93-1.32-1.37.45-1.28.77-2.59.95-3.9.73-5.19-.63-10.07-3.84-13.76-3.16-3.64-7.73-5.64-12.86-5.64h-17.54l-4.05,22.05h23.55c3.27,0,6.34.86,8.89,2.49-3.14,5.81-9.41,9.71-15.66,9.71H5.25L0,63.05h36.5c12.26,0,23.64-9.97,25.36-22.22.86-6.09-.74-11.83-4.5-16.16h0ZM57.91,40.27c-1.46,10.36-11.06,18.78-21.4,18.78H4.81l3.76-20.81h26.92c7.41,0,14.74-4.34,18.74-11.08.04.04.08.09.11.13,2.99,3.44,4.25,8.04,3.56,12.98h0ZM53.04,18.85c-.09.64-.22,1.28-.39,1.92-3.04-1.78-6.62-2.71-10.39-2.71h-18.65l2.42-14.06h14.26c3.96,0,7.45,1.52,9.84,4.27,2.43,2.8,3.46,6.56,2.9,10.58h0Z"/></svg>`;

// ---------------------------------------------------------------------
//  Confirmation lisible (§16)
// ---------------------------------------------------------------------
let minuteurToast = null;
function toast(titre, corps, ton) {
  const t = $('#toast');
  t.className = 'visible' + (ton ? ' ' + ton : '');
  t.innerHTML = `<div class="tt">${titre}</div>` + (corps ? `<div class="tc">${corps}</div>` : '');
  clearTimeout(minuteurToast);
  minuteurToast = setTimeout(() => { t.className = ''; }, 4200);
}

// ---------------------------------------------------------------------
//  Fragments réutilisables
// ---------------------------------------------------------------------
function barre(qui, retour, extra = '') {
  return `<div class="barre">${BLASON}<span class="qui">${esc(qui)}</span>
    <span class="actions">${extra}
      ${retour ? `<button class="lien" data-a="${retour}">Retour</button>` : ''}
    </span></div>`;
}

function bandeauReseau() {
  if (S.enFile > 0) {
    const suite = S.horsLigne ? 'hors ligne' : 'envoi en cours';
    return `<div class="bandeau"><i></i>${S.enFile} opération${S.enFile > 1 ? 's' : ''} en attente · ${suite}</div>`;
  }
  if (S.horsLigne) return `<div class="bandeau"><i></i>Hors ligne — les opérations seront envoyées au retour du réseau</div>`;
  return '';
}

function listeGarages(liste, action, avecSolde = true) {
  if (!liste || !liste.length) {
    return `<p class="vide">Aucun garage ne correspond.<br>Vérifiez l'orthographe.</p>`;
  }
  return `<div class="resultats">` + liste.map((g) => `
    <button class="trouve" data-a="${action}" data-id="${g.id}" data-nom="${esc(g.nom)}" data-ville="${esc(g.ville)}">
      <span><span class="tn">${esc(g.nom)}</span><span class="tv">${esc(g.ville)}</span></span>
      ${avecSolde && g.solde != null ? `<span class="ts"><b>${g.solde}</b><span>points</span></span>` : ''}
    </button>`).join('') + `</div>`;
}

function mouvements(ops) {
  if (!ops || !ops.length) return `<p class="vide">Aucune opération pour le moment.</p>`;
  return `<div class="mouvements">` + ops.map((m) => `
    <div class="mvt"><span class="mh">${esc(m.heure)}</span>
      <span class="ml">${esc(m.libelle)}<small>${esc(m.source)}</small></span>
      <span class="md ${m.delta > 0 ? 'plus' : 'moins'}">${m.delta > 0 ? '+' : ''}${m.delta}</span>
    </div>`).join('') + `</div>`;
}

// =====================================================================
//  VUES
// =====================================================================

// --- accueil / inscription (§6) --------------------------------------
function vueAccueil() {
  return guirlande() + `
    <div class="ecran">
      ${barre('Forum Pièces 2026', null, '<button class="lien" data-a="service">Équipe</button>')}
      <div class="script">Bienvenue au</div>
      <h1 class="titre">${esc(CONFIG.evenement.nom)}</h1>
      <p class="sous">${esc(CONFIG.evenement.date)} · ${esc(CONFIG.evenement.lieu)}</p>
      <div class="trait"></div>
      <p class="etiq">Votre garage</p>
      <input class="champ" id="q" type="text" inputmode="text" autocomplete="off"
             placeholder="Tapez les premières lettres…" value="${esc(S.q)}">
      <div id="zone">${S.invites === undefined ? '' : listeGarages(S.invites, 'inscrire', false)}</div>
      <p class="sous" style="margin-top:20px">Aucun mot de passe, aucun formulaire.
        Votre téléphone se souvient de vous jusqu'à la fin de la soirée.</p>
    </div>`;
}

// --- espace garage (§7, §14) -----------------------------------------
function vueParticipant() {
  const e = S.etat;
  if (!e) return `<div class="ecran"><p class="chargement">Un instant…</p></div>`;
  const g = e.garage;
  return guirlande() + `
    <div class="ecran">
      ${barre('Mon espace', null, '<button class="lien" data-a="rafraichir">Actualiser</button>')}
      ${bandeauReseau()}
      <div class="carte solde">
        <div class="gnom">${esc(g.nom)}</div>
        <div class="gville">${esc(g.ville)}</div>
        <div class="chiffre">${g.solde}</div>
        <div class="unite">points</div>
        <div class="maj">Touchez « Actualiser » à tout moment</div>
      </div>
      <div class="pile">
        <button class="bouton" data-a="grille">Tenter un lot · ${e.cout_grille} pts</button>
      </div>
      ${e.mes_lots && e.mes_lots.length ? `
        <div class="trait"></div>
        <p class="etiq">Mes lots</p>
        ${e.mes_lots.map((l) => `<div class="carte" style="margin-bottom:8px">
            <b style="font-family:var(--serif);font-size:17px;color:var(--creme-2)">${esc(l.lot)}</b>
            <div class="sous">Case n°${l.numero} · code de retrait <b style="color:var(--or-clair);letter-spacing:.2em">${esc(l.code_retrait)}</b>
            ${l.remis ? ' · déjà retiré' : ' · à retirer au comptoir Bony'}</div>
          </div>`).join('')}` : ''}
      <div class="trait"></div>
      <p class="etiq">Mes opérations</p>
      ${mouvements(e.operations)}
    </div>`;
}

// --- grille des lots (§11) -------------------------------------------
function vueGrille() {
  const e = S.etat;
  const peut = e.garage.solde >= e.cout_grille;
  const prises = e.grille || '0'.repeat(100);
  let cases = '';
  for (let n = 1; n <= 100; n++) {
    const dispo = prises[n - 1] === '0';
    cases += `<button class="case" data-a="jouer" data-n="${n}" ${(!dispo || !peut) ? 'disabled' : ''}
      aria-label="Case ${n}${dispo ? '' : ' déjà jouée'}">${n}</button>`;
  }
  return guirlande() + `
    <div class="ecran">
      ${barre('Garage', 'espace')}
      ${bandeauReseau()}
      <div class="script">La grille</div>
      <h1 class="titre">des 100 cases</h1>
      <p class="sous">Une case au hasard, un lot peut-être. Chaque case ne se joue qu'une fois.</p>
      <div class="carte" style="margin-top:16px;display:flex;gap:14px;align-items:center">
        <div><div class="etiq" style="margin:0 0 2px">Participation</div>
          <b style="font-family:var(--serif);font-size:24px;color:var(--or-clair)">${e.cout_grille} pts</b></div>
        <div style="margin-left:auto;text-align:right"><div class="etiq" style="margin:0 0 2px">Votre solde</div>
          <b style="font-family:var(--serif);font-size:24px;color:${peut ? 'var(--vert-ok-clair)' : 'var(--terracotta-clair)'}">${e.garage.solde} pts</b></div>
      </div>
      ${peut ? '' : `<div class="bandeau" style="margin-top:14px"><i></i>Il vous manque ${e.cout_grille - e.garage.solde} points — jouez ou achetez</div>`}
      <div class="grille">${cases}</div>
      <div class="legende"><span><i></i>${e.cases_libres} libres</span><span><i class="prise"></i>${100 - e.cases_libres} jouées</span></div>
    </div>`;
}

function vueRevelation() {
  const r = S.revele;
  return guirlande() + `
    <div class="ecran">
      ${barre('Garage', 'espace')}
      <div class="revele ${r.gagnante ? '' : 'perdu'}">
        <div class="rk">${r.gagnante ? 'Bravo,' : 'Cette fois,'}</div>
        <div class="rt">${r.gagnante ? "c'est gagné !" : "c'est raté"}</div>
        ${r.gagnante ? `<div class="rlot">${esc(r.lot)}
            <div class="rcode">Code de retrait ${esc(r.code_retrait)}</div>
            <div class="sous" style="font-family:var(--sans)">À présenter au comptoir Bony</div></div>`
          : `<p class="sous" style="max-width:26ch;margin:18px auto 0">Il reste des cases, et la soirée est longue.</p>`}
        <div class="rcase">Case n°${r.numero}</div>
      </div>
      <div class="pile">
        <button class="bouton creux" data-a="grille">Retenter ma chance</button>
        <button class="bouton creux" data-a="espace">Revenir à mon solde</button>
      </div>
    </div>`;
}

// --- connexion du personnel ------------------------------------------
function vueService() {
  return `<div class="ecran">
      ${barre('Accès équipe', 'accueil')}
      <div class="script">Animateurs,</div>
      <h1 class="titre">fournisseurs, équipe Bony</h1>
      <p class="sous">Saisissez le code de votre stand ou de votre animation.</p>
      <input class="champ" id="pin" type="text" inputmode="numeric" autocomplete="off"
             maxlength="8" placeholder="Code à 4 chiffres" style="margin-top:18px;font-size:22px;letter-spacing:.3em;text-align:center">
      <div class="pile">
        <button class="bouton" data-a="connexion" ${S.envoi ? 'disabled' : ''}>Se connecter</button>
      </div>
    </div>`;
}

// --- animateur (§8) ---------------------------------------------------
function vueAnimateur() {
  const r = S.r;
  // recherche
  if (!S.cible) {
    const liste = api.chercherLocal(S.q, 10);
    return `<div class="ecran">
      ${barre(r.libelle, null, `<button class="lien" data-a="quitter">Quitter</button>`)}
      ${bandeauReseau()}
      <h1 class="titre">Qui joue&nbsp;?</h1>
      <p class="sous">Participation : ${r.cout} point${r.cout > 1 ? 's' : ''}</p>
      <input class="champ" id="q" type="text" autocomplete="off" placeholder="Nom du garage…"
             value="${esc(S.q)}" style="margin-top:14px">
      ${liste === null ? `<p class="vide">Liste des garages en cours de chargement…</p>` : listeGarages(liste, 'cibler')}
    </div>`;
  }
  // fiche du garage : on lance la partie
  if (!S.partieLancee) {
    const assez = S.cible.solde >= r.cout;
    return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      <div class="carte" style="text-align:center;padding:22px 16px">
        <div style="font-family:var(--serif);font-size:22px;color:var(--creme-2)">${esc(S.cible.nom)}</div>
        <div class="gville" style="font-size:11.5px;letter-spacing:.16em;text-transform:uppercase;opacity:.6;margin-top:4px">${esc(S.cible.ville)}</div>
        <div style="font-family:var(--serif);font-weight:700;font-size:54px;color:var(--or-clair);margin-top:12px;font-variant-numeric:tabular-nums">${S.cible.solde}</div>
        <div class="unite" style="font-size:12px;font-weight:600;letter-spacing:.3em;text-transform:uppercase;color:var(--or-clair)">points au compteur</div>
      </div>
      ${assez
        ? `<div class="pile"><button class="bouton" data-a="lancer" ${S.envoi ? 'disabled' : ''}>Lancer la partie · −${r.cout} pts</button></div>`
        : `<div class="bandeau" style="margin-top:16px"><i></i>Solde insuffisant — participation à ${r.cout} pts</div>`}
      <p class="sous" style="margin-top:14px">La participation est débitée au lancement. Le résultat se saisit juste après.</p>
    </div>`;
  }
  // saisie du résultat
  return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      <h1 class="titre">${esc(S.cible.nom)}</h1>
      <p class="sous">Partie lancée, participation débitée. Sélectionnez le résultat.</p>
      <div class="baremes">
        ${r.bareme.map((b) => {
          const ton = b.points === 0 ? 'nul' : (b.points >= 10 ? 'gagne' : 'moyen');
          return `<button class="note ${ton}" data-a="noter" data-id="${b.id}" data-pts="${b.points}"
            data-lib="${esc(b.libelle)}" ${S.envoi ? 'disabled' : ''}>
            <span class="nl">${esc(b.libelle)}</span>
            <span class="np">${b.points > 0 ? '+' : ''}${b.points}</span></button>`;
        }).join('')}
      </div>
      <p class="sous" style="margin-top:16px">Un seul appui suffit. Un double appui ne crédite jamais deux fois.</p>
    </div>`;
}

// --- fournisseur (§10) ------------------------------------------------
const PALIERS = [5, 10, 20, 50];
function vueFournisseur() {
  const r = S.r;
  if (!S.cible) {
    const liste = api.chercherLocal(S.q, 10);
    return `<div class="ecran">
      ${barre(r.libelle, null, `<button class="lien" data-a="quitter">Quitter</button>`)}
      ${bandeauReseau()}
      <div class="script">Une vente</div>
      <h1 class="titre">vient d'être conclue&nbsp;?</h1>
      <p class="sous">Retrouvez le garage, attribuez les points de l'opération.</p>
      <input class="champ" id="q" type="text" autocomplete="off" placeholder="Nom du garage…"
             value="${esc(S.q)}" style="margin-top:16px">
      ${liste === null ? `<p class="vide">Liste des garages en cours de chargement…</p>` : listeGarages(liste, 'cibler')}
    </div>`;
  }
  return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      <div class="carte" style="display:flex;align-items:center;gap:12px">
        <div><div style="font-family:var(--serif);font-size:19px;color:var(--creme-2)">${esc(S.cible.nom)}</div>
        <div style="font-size:11.5px;letter-spacing:.14em;text-transform:uppercase;opacity:.55;margin-top:2px">${esc(S.cible.ville)}</div></div>
        <div style="margin-left:auto;text-align:right">
          <b style="font-family:var(--serif);font-size:26px;color:var(--or-clair)">${S.cible.solde}</b>
          <div style="font-size:9.5px;letter-spacing:.18em;text-transform:uppercase;opacity:.5">points</div></div>
      </div>
      <div class="trait"></div>
      <p class="etiq">Points de l'opération</p>
      <div class="paliers">
        ${PALIERS.filter((p) => p <= (r.plafond_operation || 50)).map((p) =>
          `<button class="palier" data-a="palier" data-p="${p}" aria-pressed="${S.palier === p}">+${p} pts</button>`).join('')}
      </div>
      <p class="sous" style="margin-top:12px">Barème du stand · plafond de ${r.plafond_operation || 50} points par opération.</p>
      <div class="pile">
        <button class="bouton" data-a="attribuer" ${S.envoi ? 'disabled' : ''}>Attribuer +${S.palier} points</button>
      </div>
      <p class="sous" style="margin-top:12px">L'écriture est signée au nom du stand.</p>
    </div>`;
}

// --- supervision Bony (§12, §18) --------------------------------------
function vueAdmin() {
  const s = S.sup;
  if (!s) return `<div class="ecran">${barre('Supervision Bony')}<p class="chargement">Chargement…</p></div>`;
  return `<div class="ecran">
      ${barre('Supervision Bony', null, `<button class="lien" data-a="quitter">Quitter</button>`)}
      ${bandeauReseau()}
      <div class="script">Le Forum</div>
      <h1 class="titre">en un coup d'œil</h1>
      <div class="indics" style="margin-top:14px">
        <div class="indic"><div class="iv">${s.garages_actifs} / ${s.garages_invites}</div><div class="il">Garages actifs sur invités</div></div>
        <div class="indic"><div class="iv">${s.points_circulation}</div><div class="il">Points en circulation</div></div>
        <div class="indic"><div class="iv">${s.points_emis}</div><div class="il">Points émis</div></div>
        <div class="indic"><div class="iv">${s.lots_gagnes - s.lots_remis}</div><div class="il">Lots à remettre</div></div>
        <div class="indic large ${s.tension ? 'alerte' : ''}">
          <div class="iv">${s.cases_jouees} / 100</div>
          <div class="il">Cases jouées · ${s.parties_financables} parties encore finançables avec les points en circulation</div>
          <div class="jauge"><span style="width:${s.cases_jouees}%"></span></div>
        </div>
        ${s.ecarts_solde > 0 ? `<div class="indic large alerte"><div class="iv">${s.ecarts_solde}</div>
          <div class="il">Écarts entre solde et journal — à signaler immédiatement</div></div>` : ''}
      </div>
      ${s.tension ? `<div class="bandeau" style="margin-top:12px"><i></i>Plus de points en circulation que de cases restantes — resserrer les barèmes</div>` : ''}
      <div class="trait"></div>
      <p class="etiq">Distribution par stand</p>
      ${s.par_stand.map((p) => `<div class="mvt"><span class="ml">${esc(p.stand)}</span>
        <span class="md">${p.distribue} <span style="font-family:var(--sans);font-size:11px;opacity:.5">/ ${p.plafond}</span></span></div>`).join('')}
      <div class="trait"></div>
      <p class="etiq">Journal en direct</p>
      ${mouvements(s.journal.map((j) => ({ heure: j.heure, libelle: j.garage + ' · ' + j.libelle, source: j.source, delta: j.delta })))}
      <div class="trait"></div>
      <p class="etiq">Sauvegarde</p>
      <p class="sous" style="margin-bottom:12px">Le plan gratuit n'a pas de sauvegarde automatique.
        Exportez le journal une fois en milieu de soirée et une fois à la fin.</p>
      <div class="pile">
        <button class="bouton creux" data-a="export">Télécharger le journal (CSV)</button>
        <button class="bouton creux" data-a="lots">Suivi des lots</button>
      </div>
    </div>`;
}

function vueLots() {
  const l = S.lots || [];
  return `<div class="ecran">
      ${barre('Suivi des lots', 'admin')}
      <h1 class="titre">Lots gagnés</h1>
      <p class="sous">${l.filter((x) => !x.remis).length} à remettre sur ${l.length} gagnés</p>
      <div class="trait"></div>
      ${l.length === 0 ? `<p class="vide">Aucun lot gagné pour le moment.</p>` : l.map((x) => `
        <div class="carte" style="margin-bottom:9px;display:flex;align-items:center;gap:12px">
          <div style="flex:1 1 auto">
            <b style="font-family:var(--serif);font-size:16px;color:var(--creme-2)">${esc(x.lot)}</b>
            <div class="sous" style="margin-top:2px">${esc(x.garage)} · case n°${x.numero} · ${esc(x.joue_a)}
              · code <b style="color:var(--or-clair);letter-spacing:.16em">${esc(x.code_retrait)}</b></div>
          </div>
          ${x.remis
            ? `<span style="font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--vert-ok-clair)">Remis</span>`
            : `<button class="bouton petit" data-a="remettre" data-n="${x.numero}" style="width:auto;flex:0 0 auto">Remettre</button>`}
        </div>`).join('')}
    </div>`;
}

// =====================================================================
//  Rendu
// =====================================================================
const VUES = {
  chargement: () => `<div class="ecran"><p class="chargement">Un instant…</p></div>`,
  accueil: vueAccueil,
  espace: vueParticipant,
  grille: vueGrille,
  revelation: vueRevelation,
  service: vueService,
  animateur: vueAnimateur,
  fournisseur: vueFournisseur,
  admin: vueAdmin,
  lots: vueLots,
};

function rendre(garderFocus) {
  const avecDecor = ['accueil', 'espace', 'grille', 'revelation'].includes(S.vue);
  document.body.classList.toggle('decore', avecDecor);
  if (avecDecor) monterDecor();

  const champ = $('#q') || $('#pin');
  const pos = champ ? champ.selectionStart : null;
  const idChamp = champ ? champ.id : null;

  $('#app').innerHTML = (VUES[S.vue] || VUES.chargement)();

  if (garderFocus && idChamp) {
    const encore = $('#' + idChamp);
    if (encore) { encore.focus(); try { encore.setSelectionRange(pos, pos); } catch {} }
  }
}

// =====================================================================
//  Actions
// =====================================================================
function codeEvenement() {
  const p = new URLSearchParams(location.search).get('e');
  if (p) localStorage.setItem('gbp.code', p);
  return localStorage.getItem('gbp.code') || 'bal2026';
}

async function chargerEtat() {
  try {
    S.etat = await api.lire.etat();
    return true;
  } catch (e) {
    if (e instanceof api.ErreurApi && ['APPAREIL_INCONNU', 'APPAREIL_SANS_GARAGE', 'JETON_INVALIDE'].includes(e.code)) {
      api.definirRole(null);
      S.r = null; S.vue = 'accueil';
      return false;
    }
    // réseau : on garde l'écran précédent, le sondage réessaiera
    return false;
  }
}

async function chargerSupervision() {
  try { S.sup = await api.lire.supervision(); } catch {}
}

let minuteurSondage = null;
function sondage() {
  if (minuteurSondage) clearInterval(minuteurSondage);
  const rythme = S.r && S.r.role === 'admin' ? CONFIG.sondageAdminMs : CONFIG.sondageMs;
  minuteurSondage = setInterval(async () => {
    if (document.hidden) return;
    if (S.vue === 'espace') { if (await chargerEtat()) rendre(); }
    else if (S.vue === 'admin') { await chargerSupervision(); rendre(); }
  }, rythme);
}

/** Ajuste le solde affiché localement quand une écriture partira plus tard. */
function ajusterCache(garageId, delta) {
  const c = api.garagesEnCache();
  if (!c) return;
  const g = c.liste.find((x) => x.id === garageId);
  if (g) { g.solde = Math.max(0, (g.solde || 0) + delta); localStorage.setItem('gbp.garages', JSON.stringify(c)); }
  if (S.cible && S.cible.id === garageId) S.cible.solde = Math.max(0, S.cible.solde + delta);
}

function csv(lignes) {
  const cols = ['id','quand','garage','ville','libelle','source','delta','stand','animation','appareil','cle'];
  const q = (v) => '"' + String(v ?? '').replace(/"/g, '""') + '"';
  return '﻿' + cols.join(';') + '\n'
       + lignes.map((l) => cols.map((c) => q(l[c])).join(';')).join('\n');
}

function telecharger(nom, contenu, type) {
  const b = new Blob([contenu], { type });
  const u = URL.createObjectURL(b);
  const a = document.createElement('a');
  a.href = u; a.download = nom; document.body.appendChild(a); a.click();
  a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
}

async function agir(a, el) {
  switch (a) {
    // ---------------- navigation ----------------
    case 'accueil':   S.vue = 'accueil'; S.q = ''; S.invites = undefined; return rendre();
    case 'service':   S.vue = 'service'; return rendre();
    case 'espace':    S.vue = 'espace'; await chargerEtat(); return rendre();
    case 'grille':    S.vue = 'grille'; await chargerEtat(); return rendre();
    case 'recherche': S.cible = null; S.partieLancee = false; S.q = ''; return rendre();
    // On recharge toujours en revenant au tableau de bord : sinon un lot
    // que Bony vient de remettre reste affiché comme « à remettre »
    // jusqu'au sondage suivant, et l'équipe doute de l'outil.
    case 'admin':     S.vue = 'admin'; rendre(); await chargerSupervision(); return rendre();
    case 'rafraichir':
      if (await chargerEtat()) { rendre(); toast('Solde à jour', `<b>${S.etat.garage.solde}</b> points`); }
      else toast('Pas de réseau', 'Le solde affiché est celui de la dernière consultation.', 'attente');
      return;
    case 'quitter':
      api.definirRole(null); api.oublierAppareil();
      S.r = null; S.cible = null; S.vue = 'accueil'; S.q = '';
      return rendre();

    // ---------------- inscription ----------------
    case 'inscrire': {
      const id = el.dataset.id;
      try {
        S.etat = await api.lire.inscrire(id);
        api.definirRole({ role: 'garage' });
        S.r = { role: 'garage' };
        S.vue = 'espace'; rendre(); sondage();
        toast('Bienvenue !', `${esc(el.dataset.nom)} · <b>${S.etat.garage.solde}</b> points`);
      } catch (e) {
        toast('Inscription impossible', e.detail || e.message, 'negatif');
      }
      return;
    }

    // ---------------- grille (§11) ----------------
    case 'jouer': {
      if (S.envoi) return;
      const n = +el.dataset.n;
      S.envoi = true; rendre();
      const cle = api.nouvelleCle();
      try {
        const r = await api.ecrit.jouerCase(n, cle);
        if (r.enAttente) {
          toast('Sans réseau', 'Un tirage exige une réponse immédiate. Réessayez quand le réseau revient.', 'attente');
        } else {
          S.revele = r; S.vue = 'revelation';
          await chargerEtat();
          if (r.gagnante) toast('Lot gagné !', esc(r.lot));
          else toast(`Case n°${n} jouée`, `−${S.etat.cout_grille} points · nouveau solde <b>${r.solde}</b>`, 'negatif');
        }
      } catch (e) {
        toast(e.code === 'CASE_DEJA_PRISE' ? 'Case déjà prise' : 'Impossible', e.detail || e.message, 'negatif');
        await chargerEtat();
      } finally { S.envoi = false; rendre(); }
      return;
    }

    // ---------------- connexion personnel ----------------
    case 'connexion': {
      if (S.envoi) return;
      const pin = ($('#pin') || {}).value || '';
      S.envoi = true; rendre(true);
      try {
        const r = await api.lire.connexion(pin.trim());
        api.definirRole(r); S.r = r;
        S.vue = r.role === 'admin' ? 'admin' : r.role;
        S.q = ''; S.cible = null; S.partieLancee = false;
        S.envoi = false;
        rendre();
        toast('Connecté', esc(r.libelle));
        api.rafraichirGarages().then(() => rendre()).catch(() => {});
        if (r.role === 'admin') { await chargerSupervision(); rendre(); }
        sondage();
      } catch (e) {
        S.envoi = false; rendre();
        toast('Code refusé', e.detail || e.message, 'negatif');
      }
      return;
    }

    // ---------------- personnel : cibler un garage ----------------
    case 'cibler': {
      S.cible = { id: el.dataset.id, nom: el.dataset.nom, ville: el.dataset.ville, solde: 0 };
      const c = api.garagesEnCache();
      const g = c && c.liste.find((x) => x.id === S.cible.id);
      if (g) S.cible.solde = g.solde;
      S.partieLancee = false;
      rendre();
      // solde frais si le réseau est là
      try {
        const l = await api.lire.chercher(el.dataset.nom);
        const f = l.find((x) => x.id === S.cible.id);
        if (f) { S.cible.solde = f.solde; ajusterCache(f.id, 0); rendre(); }
      } catch {}
      return;
    }

    // ---------------- animateur ----------------
    case 'lancer': {
      if (S.envoi) return;
      S.envoi = true; rendre();
      const cle = api.nouvelleCle();
      try {
        const r = await api.ecrit.participation(S.cible.id, S.r.animation_id, cle);
        ajusterCache(S.cible.id, -S.r.cout);
        S.partieLancee = true;
        toast(r.enAttente ? 'Enregistré hors ligne' : 'Partie lancée',
              `−${S.r.cout} pts · ${esc(S.cible.nom)}` + (r.enAttente ? ' · sera envoyé au retour du réseau' : ` · solde <b>${r.solde}</b>`),
              r.enAttente ? 'attente' : 'negatif');
      } catch (e) {
        toast('Impossible', e.detail || e.message, 'negatif');
      } finally { S.envoi = false; rendre(); }
      return;
    }

    case 'noter': {
      if (S.envoi) return;
      S.envoi = true; rendre();
      const pts = +el.dataset.pts, lib = el.dataset.lib;
      const cle = api.nouvelleCle();
      const nom = S.cible.nom;
      try {
        const r = await api.ecrit.resultat(S.cible.id, el.dataset.id, cle);
        ajusterCache(S.cible.id, pts);
        S.cible = null; S.partieLancee = false; S.q = '';
        if (r.enAttente) toast('Enregistré hors ligne', `${esc(nom)} · ${esc(lib)} · +${pts} pts en attente`, 'attente');
        else if (pts > 0) toast(`+${pts} points ajoutés`, `${esc(nom)} · nouveau solde <b>${r.solde}</b>`);
        else toast('Résultat enregistré', `${esc(nom)} · ${esc(lib)}`, 'attente');
      } catch (e) {
        toast('Impossible', e.detail || e.message, 'negatif');
      } finally { S.envoi = false; rendre(); }
      return;
    }

    // ---------------- fournisseur ----------------
    case 'palier': S.palier = +el.dataset.p; return rendre();

    case 'attribuer': {
      if (S.envoi) return;
      S.envoi = true; rendre();
      const nom = S.cible.nom, pts = S.palier;
      const cle = api.nouvelleCle();
      try {
        const r = await api.ecrit.achat(S.cible.id, pts, cle);
        ajusterCache(S.cible.id, pts);
        S.cible = null; S.q = '';
        if (r.enAttente) toast('Enregistré hors ligne', `${esc(nom)} · +${pts} pts en attente d'envoi`, 'attente');
        else toast(`+${pts} points ajoutés`, `${esc(nom)} · nouveau solde <b>${r.solde}</b>`);
      } catch (e) {
        toast('Refusé', e.detail || e.message, 'negatif');
      } finally { S.envoi = false; rendre(); }
      return;
    }

    // ---------------- Bony ----------------
    case 'export': {
      try {
        const j = await api.lire.journal();
        telecharger(`journal-forum-pieces-${new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-')}.csv`,
                    csv(j), 'text/csv;charset=utf-8');
        toast('Journal exporté', `${j.length} opérations enregistrées dans le fichier`);
      } catch (e) { toast('Export impossible', e.detail || e.message, 'negatif'); }
      return;
    }
    case 'lots': {
      try { S.lots = await api.lire.lots(); S.vue = 'lots'; rendre(); }
      catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      return;
    }
    case 'remettre': {
      const n = +el.dataset.n;
      try {
        await api.ecrit.remettreLot(n);
        S.lots = await api.lire.lots();
        S.sup = null;                     // le tableau de bord devra se recharger
        rendre();
        toast('Lot remis', `Case n°${n}`);
      } catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      return;
    }
  }
}

// =====================================================================
//  Branchements
// =====================================================================
$('#app').addEventListener('click', (ev) => {
  const el = ev.target.closest('[data-a]');
  if (!el) return;
  ev.preventDefault();
  agir(el.dataset.a, el);
});

let minuteurSaisie = null;
$('#app').addEventListener('input', (ev) => {
  const el = ev.target;
  if (el.id !== 'q') return;
  S.q = el.value;
  if (S.vue === 'accueil') {
    // la recherche d'inscription passe par le réseau : on attend la frappe
    clearTimeout(minuteurSaisie);
    minuteurSaisie = setTimeout(async () => {
      if (S.q.trim().length < 2) { S.invites = []; return rendre(true); }
      try { S.invites = await api.lire.invites(codeEvenement(), S.q.trim()); }
      catch { S.invites = []; }
      rendre(true);
    }, 280);
  } else {
    rendre(true);   // personnel : recherche locale, donc instantanée
  }
});

addEventListener('online',  () => { S.horsLigne = false; rendre(); api.viderFile(); });
addEventListener('offline', () => { S.horsLigne = true;  rendre(); });
api.surFile((n) => { S.enFile = n; if (S.vue !== 'chargement') rendre(); });

document.addEventListener('visibilitychange', async () => {
  if (document.hidden) return;
  if (S.vue === 'espace') { if (await chargerEtat()) rendre(); }
  if (S.vue === 'admin') { await chargerSupervision(); rendre(); }
});

// =====================================================================
//  Démarrage
// =====================================================================
(async function demarrer() {
  codeEvenement();
  api.demarrerFile();

  S.r = api.role();
  if (!S.r) { S.vue = 'accueil'; return rendre(); }

  if (S.r.role === 'garage') {
    S.vue = 'espace';
    rendre();
    await chargerEtat();
    rendre();
    sondage();
    return;
  }

  // personnel : on affiche tout de suite, la liste se rafraîchit derrière
  S.vue = S.r.role === 'admin' ? 'admin' : S.r.role;
  rendre();
  if (S.r.role === 'admin') { await chargerSupervision(); rendre(); }
  api.rafraichirGarages().then(() => rendre()).catch(() => {});
  sondage();
})();

// Service worker : coquille hors ligne
if ('serviceWorker' in navigator) {
  addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
