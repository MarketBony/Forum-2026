// =====================================================================
//  app.js — Le Grand Bal des Points
//  Quatre profils, une seule page. Pas d'étape de compilation : des
//  modules ES natifs, servis tels quels par Cloudflare Pages.
// =====================================================================
import { CONFIG } from '../config.js';
import * as api from './api.js';
import * as verre from './verre.js';

const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
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
  code: '',             // saisie du code garage
  cible: null,          // garage visé par le personnel
  palier: 20,           // points choisis par le fournisseur
  revele: null,         // résultat d'un tirage
  sup: null,            // tableau de bord Bony
  lots: null,
  tirage: null,       // etat du grand tirage du soir
  cleEnCours: null,     // clé d'idempotence de l'opération en cours
  envoi: false,         // garde anti-double-appui
  horsLigne: !navigator.onLine,
  enFile: 0,
};

// ---------------------------------------------------------------------
//  Décor — guirlande et loupiottes, réservés aux écrans garage
// ---------------------------------------------------------------------
/* Loupiottes : deux tailles pour la profondeur. Elles restent hors de la
   zone de lecture — le verre des surfaces les laisse deviner par-dessous,
   ce qui suffit largement. */
const LOUPIOTTES = [
  [7, 5, 5, 7.0, 0],   [19, 10, 3, 8.5, 1.4], [31, 4, 4, 6.2, 2.6],
  [44, 9, 3, 9.0, .8], [56, 5, 5, 7.5, 3.1],  [68, 11, 3, 8.0, 1.9],
  [81, 4, 4, 6.8, 2.2], [92, 9, 3, 9.4, .5],
  [4, 34, 3, 10.0, 1.1], [96, 41, 3, 9.2, 2.8],
  [12, 88, 3, 8.8, 3.4], [88, 92, 4, 7.8, 1.6],
];

/* Braises : x, taille, durée, retard, dérive horizontale */
const BRAISES = [
  [10, 6, 19, 0, 42], [23, 4, 24, 3.5, -32], [36, 5, 17, 7, 54],
  [48, 6, 22, 1.5, -48], [59, 4, 26, 9, 36], [70, 5, 18, 4.5, -26],
  [82, 6, 23, 11, 58], [93, 4, 20, 2.5, -42],
];

function monterDecor() {
  const d = $('#decor');
  if (d.dataset.pret) return;
  d.innerHTML =
    '<div class="nappe"></div>' +
    '<div class="halo h1"></div><div class="halo h2"></div><div class="halo h3"></div>' +
    '<div class="vichy"></div>' +
    LOUPIOTTES.map(([x, y, t, dur, del]) =>
      `<span class="loupiotte" style="left:${x}%;top:${y}%;width:${t}px;height:${t}px;--d:${dur}s;--r:${del}s"></span>`
    ).join('') +
    BRAISES.map(([x, t, dur, del, dx]) =>
      `<span class="braise" style="left:${x}%;width:${t}px;height:${t}px;--rd:${dur}s;--rl:${del}s;--dx:${dx}px"></span>`
    ).join('') +
    '<div class="grain"></div>';
  d.dataset.pret = '1';
}

/** Guirlande : fil en courbes de Bézier, ampoules suspendues à hauteurs
 *  et teintes variées. Reprise de la page d'invitation. */
function guirlande() {
  const appuis = [{x:0,y:8},{x:185,y:6},{x:415,y:10},{x:610,y:5},{x:805,y:9},{x:1000,y:7}];
  const creux = [26, 22, 28, 24, 25];
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
  // Moins d'ampoules, plus petites, suspendues moins bas : la guirlande
  // signe l'écran au lieu de le charger.
  const places = [[0.34,0.68],[0.32,0.74],[0.42],[0.36,0.72],[0.48]];
  const tailles = [7,9,6,8,7,9,6,8];
  const pendus  = [6,12,4,10,15,7,13,5];
  const halos   = [5,8,4,7,9,5,8,4];
  const plancher= [.6,.72,.52,.64,.76,.56,.68,.6];
  const durees  = [4.8,6.4,4.2,5.6,7.0,5.0,6.0,4.6];
  let k = 0, html = '';
  places.forEach((liste, s) => liste.forEach((t) => {
    const p = pt(segs[s], t), c = teintes[k % teintes.length], i = k % tailles.length;
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
    return `<div class="groupe"><p class="vide">Aucun garage ne correspond.<br>Vérifiez l'orthographe.</p></div>`;
  }
  return `<div class="groupe">` + liste.map((g) => `
    <button class="rangee" data-a="${action}" data-id="${g.id}" data-nom="${esc(g.nom)}" data-ville="${esc(g.ville)}">
      <span class="principal"><span class="nom">${esc(g.nom)}</span><span class="detail">${esc(g.ville)}</span></span>
      ${avecSolde && g.solde != null
        ? `<span class="valeur"><b>${g.solde}</b><span>pts</span></span>`
        : ''}
      <span class="fleche"></span>
    </button>`).join('') + `</div>`;
}

function mouvements(ops, groupe = true) {
  const corps = (!ops || !ops.length)
    ? `<p class="vide">Aucune opération pour le moment.</p>`
    : `<div class="mouvements">` + ops.map((m) => `
        <div class="mvt"><span class="mh">${esc(m.heure)}</span>
          <span class="ml">${esc(m.libelle)}<small>${esc(m.source)}</small></span>
          <span class="md ${m.delta > 0 ? 'plus' : 'moins'}">${m.delta > 0 ? '+' : ''}${m.delta}</span>
        </div>`).join('') + `</div>`;
  return groupe ? `<div class="groupe">${corps}</div>` : corps;
}

// =====================================================================
//  VUES
// =====================================================================

// --- accueil / inscription (§6) --------------------------------------
function vueAccueil() {
  return guirlande() + `
    <div class="ecran">
      ${barre('Forum Pièces 2026', null, '<button class="lien" data-a="service">Équipe</button>')}
      <div class="entete">
        <div class="script">Bienvenue au</div>
        <h1 class="titre">${esc(CONFIG.evenement.nom)}</h1>
        <p class="sous">${esc(CONFIG.evenement.date)} · ${esc(CONFIG.evenement.lieu)}</p>
      </div>
      <div class="section">
        <p class="etiq">Votre code garage</p>
        <input class="champ code" id="cg" type="text" inputmode="text"
               autocomplete="off" autocapitalize="characters" spellcheck="false"
               maxlength="6" placeholder="••••" value="${esc(S.code)}"
               ${S.envoi ? 'disabled' : ''}>
        <button class="bouton" data-a="entrer" ${S.envoi ? 'disabled' : ''}>Entrer</button>
      </div>
      <p class="sous">Le code figure sur votre invitation. Vous l'avez perdu&nbsp;?
        L'accueil vous le redonne en trois secondes.</p>
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
      <div class="surface solde">
        <div class="gnom">${esc(g.nom)}</div>
        <div class="gville">${esc(g.cp ? g.cp + ' ' : '')}${esc(g.ville)}</div>
        <div class="chiffre">${g.solde}</div>
        <div class="unite">points</div>
        ${g.code ? `<div class="rappel">Votre code <b>${esc(g.code)}</b><span>Notez-le : il rouvre
          votre solde si vous fermez l'application ou changez de téléphone.</span></div>` : ''}
      </div>
      <button class="bouton" data-a="grille">Tenter un lot · ${e.cout_grille} pts</button>
      ${e.mes_cases && e.mes_cases.length ? `
        <div class="section">
          <p class="etiq">Mes cases</p>
          <div class="groupe">
            ${e.mes_cases.map((c) => {
              if (!c.revelee) return `<div class="lot">
                <span class="principal">
                  <span class="lnom" style="color:var(--txt-2)">Case n°${c.numero}</span>
                  <span class="ldetail">Verdict ce soir, sur l'écran géant</span>
                </span>
                <span class="cachet">?</span></div>`;
              if (c.nature === 'billet') return `<div class="lot">
                <span class="principal">
                  <span class="lnom">Billet pour le grand tirage</span>
                  <span class="ldetail">Case n°${c.numero} · rendez-vous au tirage de la soirée</span>
                </span>
                <span class="cachet billet">★</span></div>`;
              if (c.nature === 'lot') return `<div class="lot">
                <span class="principal">
                  <span class="lnom">${esc(c.lot)}</span>
                  <span class="ldetail">Case n°${c.numero} · code <b>${esc(c.code_retrait)}</b> ·
                    ${c.remis ? 'déjà retiré' : 'à retirer au comptoir Bony'}</span>
                </span>
                ${c.remis ? '<span class="lremis">Retiré</span>' : ''}</div>`;
              return `<div class="lot">
                <span class="principal">
                  <span class="lnom" style="color:var(--txt-3)">Case n°${c.numero}</span>
                  <span class="ldetail">Perdante</span>
                </span></div>`;
            }).join('')}
          </div>
        </div>` : ''}
      <div class="section">
        <p class="etiq">Mes opérations</p>
        ${mouvements(e.operations)}
      </div>
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
      <div class="entete">
        <div class="script">La grille</div>
        <h1 class="titre">des 100 cases</h1>
        <p class="sous">Une case au hasard, un lot peut-être. Chaque case ne se joue qu'une fois.</p>
      </div>
      <div class="surface duo">
        <div><span class="etiq">Participation</span><span class="dv">${e.cout_grille} pts</span></div>
        <div><span class="etiq">Votre solde</span>
          <span class="dv ${peut ? 'suffisant' : 'faible'}">${e.garage.solde} pts</span></div>
      </div>
      ${peut ? '' : `<div class="bandeau"><i></i>Il vous manque ${e.cout_grille - e.garage.solde} points — jouez ou achetez</div>`}
      <div class="section">
        <div class="grille">${cases}</div>
        <div class="legende"><span><i></i>${e.cases_libres} libres</span><span><i class="prise"></i>${100 - e.cases_libres} jouées</span></div>
      </div>
    </div>`;
}

function vueRevelation() {
  const r = S.revele;

  // Mode différé : la case est réservée, le verdict attend l'écran géant.
  if (!r.revelee) {
    return guirlande() + `
      <div class="ecran">
        ${barre('Garage', 'espace')}
        <div class="revele attente">
          <div class="rk">Votre case est</div>
          <div class="rt">réservée</div>
          <div class="rlot">Case n°${r.numero}
            <div class="rnote">Personne ne peut plus la prendre. Le verdict tombera
              ce soir, sur l'écran géant, en même temps que pour tout le monde.</div></div>
        </div>
        <div class="pile">
          <button class="bouton" data-a="grille">Prendre une autre case</button>
          <button class="bouton creux" data-a="espace">Revenir à mon solde</button>
        </div>
      </div>`;
  }

  const billet = r.nature === 'billet';
  const lot = r.nature === 'lot';
  return guirlande() + `
    <div class="ecran">
      ${barre('Garage', 'espace')}
      <div class="revele ${(billet || lot) ? '' : 'perdu'}">
        <div class="rk">${billet ? 'Vous êtes' : (lot ? 'Bravo,' : 'Cette fois,')}</div>
        <div class="rt">${billet ? 'qualifié !' : (lot ? "c'est gagné !" : "c'est raté")}</div>
        ${billet ? `<div class="rlot">Billet pour le grand tirage
            <div class="rnote">Rendez-vous ce soir : le tirage se fait en direct
              sur l'écran géant, entre les détenteurs de billets.</div></div>`
          : lot ? `<div class="rlot">${esc(r.lot)}
            <div class="rcode">${esc(r.code_retrait)}</div>
            <div class="rnote">Code de retrait, à présenter au comptoir Bony</div></div>`
          : `<p class="sous">Il reste des cases, et la soirée est longue.</p>`}
        <div class="rcase">Case n°${r.numero}</div>
      </div>
      <div class="pile">
        <button class="bouton" data-a="grille">Retenter ma chance</button>
        <button class="bouton creux" data-a="espace">Revenir à mon solde</button>
      </div>
    </div>`;
}

// --- connexion du personnel ------------------------------------------
function vueService() {
  return `<div class="ecran">
      ${barre('Accès équipe', 'accueil')}
      <div class="entete">
        <div class="script">Animateurs,</div>
        <h1 class="titre">fournisseurs, équipe Bony</h1>
        <p class="sous">Saisissez le code de votre stand ou de votre animation.</p>
      </div>
      <input class="champ code" id="pin" type="text" inputmode="numeric" autocomplete="off"
             maxlength="8" placeholder="••••">
      <button class="bouton" data-a="connexion" ${S.envoi ? 'disabled' : ''}>Se connecter</button>
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
      <div class="entete">
        <h1 class="titre">Qui joue&nbsp;?</h1>
        <p class="sous">Participation : ${r.cout} point${r.cout > 1 ? 's' : ''}</p>
      </div>
      <input class="champ" id="q" type="text" autocomplete="off" placeholder="Nom du garage…"
             value="${esc(S.q)}">
      ${liste === null
        ? `<div class="groupe"><p class="vide">Chargement de la liste des garages…</p></div>`
        : listeGarages(liste, 'cibler')}
    </div>`;
  }
  // fiche du garage : on lance la partie
  if (!S.partieLancee) {
    const assez = S.cible.solde >= r.cout;
    return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      <div class="surface fiche">
        <div class="fnom">${esc(S.cible.nom)}</div>
        <div class="fville">${esc(S.cible.ville)}</div>
        <div class="fsolde">${S.cible.solde}</div>
        <div class="funite">points au compteur</div>
      </div>
      ${assez
        ? `<button class="bouton bas" data-a="lancer" ${S.envoi ? "disabled" : ""}>Lancer la partie · −${r.cout} pts</button>`
        : `<div class="bandeau"><i></i>Solde insuffisant — participation à ${r.cout} pts</div>`}
      <p class="sous">La participation est débitée au lancement. Le résultat se saisit juste après.</p>
    </div>`;
  }
  // saisie du résultat
  return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      <div class="entete">
        <h1 class="titre">${esc(S.cible.nom)}</h1>
        <p class="sous">Participation débitée. Sélectionnez le résultat.</p>
      </div>
      <div class="surface duo">
        <div><span class="etiq">Participation</span><span class="dv">−${r.cout} pts</span></div>
        <div><span class="etiq">Solde après débit</span><span class="dv">${S.cible.solde} pts</span></div>
      </div>
      <div class="baremes bas">
        ${(() => {
          // La couleur est RELATIVE au barème du jeu, pas à un seuil absolu :
          // le vert désigne le meilleur résultat de CE jeu, et lui seul.
          // Sinon un animateur voit deux barres vertes et hésite.
          const max = Math.max(...r.bareme.map((b) => b.points));
          return r.bareme.map((b) => {
          const ton = b.points === 0 ? 'nul' : (b.points === max ? 'gagne' : 'moyen');
          return `<button class="note ${ton}" data-a="noter" data-id="${b.id}" data-pts="${b.points}"
            data-lib="${esc(b.libelle)}" ${S.envoi ? 'disabled' : ''}>
            <span class="nl">${esc(b.libelle)}</span>
            <span class="np">${b.points > 0 ? '+' : ''}${b.points}</span></button>`;
          }).join('');
        })()}
      </div>
      <p class="sous">Un seul appui suffit. Un double appui ne crédite jamais deux fois.</p>
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
      <div class="entete">
        <div class="script">Une vente</div>
        <h1 class="titre">vient d'être conclue&nbsp;?</h1>
        <p class="sous">Retrouvez le garage, attribuez les points de l'opération.</p>
      </div>
      <input class="champ" id="q" type="text" autocomplete="off" placeholder="Nom du garage…"
             value="${esc(S.q)}">
      ${liste === null
        ? `<div class="groupe"><p class="vide">Chargement de la liste des garages…</p></div>`
        : listeGarages(liste, 'cibler')}
    </div>`;
  }
  return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      <div class="groupe">
        <div class="rangee">
          <span class="principal"><span class="nom">${esc(S.cible.nom)}</span>
            <span class="detail">${esc(S.cible.ville)}</span></span>
          <span class="valeur"><b>${S.cible.solde}</b><span>pts</span></span>
        </div>
      </div>
      <div class="section">
        <p class="etiq">Points de l'opération</p>
        <div class="paliers">
          ${PALIERS.filter((p) => p <= (r.plafond_operation || 50)).map((p) =>
            `<button class="palier" data-a="palier" data-p="${p}" aria-pressed="${S.palier === p}">+${p}</button>`).join('')}
        </div>
        <p class="sous">Plafond de ${r.plafond_operation || 50} points par opération.
          L'écriture est signée au nom du stand.</p>
      </div>
      <button class="bouton bas" data-a="attribuer" ${S.envoi ? 'disabled' : ''}>Attribuer +${S.palier} points</button>
    </div>`;
}

// --- supervision Bony (§12, §18) --------------------------------------
function vueAdmin() {
  const s = S.sup;
  if (!s) return `<div class="ecran">${barre('Supervision Bony')}<p class="chargement">Chargement…</p></div>`;
  return `<div class="ecran">
      ${barre('Supervision Bony', null, `<button class="lien" data-a="quitter">Quitter</button>`)}
      ${bandeauReseau()}
      <div class="entete">
        <div class="script">Le Forum</div>
        <h1 class="titre">en un coup d'œil</h1>
      </div>
      <div class="indics">
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
      ${s.tension ? `<div class="bandeau"><i></i>Plus de points en circulation que de cases restantes — resserrer les barèmes</div>` : ''}
      <div class="section">
        <p class="etiq">Distribution par stand</p>
        <div class="groupe">
          ${s.par_stand.map((p) => `<div class="rangee">
            <span class="principal"><span class="nom">${esc(p.stand)}</span></span>
            <span class="valeur"><b>${p.distribue}</b><span>/ ${p.plafond}</span></span>
          </div>`).join('')}
        </div>
      </div>
      <div class="section">
        <p class="etiq">Journal en direct</p>
        ${mouvements(s.journal.map((j) => ({ heure: j.heure, libelle: j.garage + ' · ' + j.libelle, source: j.source, delta: j.delta })))}
      </div>
      <div class="section">
        <p class="etiq">Le bingo</p>
        <div class="groupe">
          <div class="rangee">
            <span class="principal"><span class="nom">Mode de révélation</span>
              <span class="detail">${s.revelation === 'immediate'
                ? 'Immédiate — le garage découvre à l\'achat'
                : 'Différée — tout se révèle ce soir'}</span></span>
          </div>
          <div class="rangee">
            <span class="principal"><span class="nom">Billets de tirage</span>
              <span class="detail">${s.billets_restants} encore à décrocher</span></span>
            <span class="valeur"><b>${s.billets_vendus}</b><span>vendus</span></span>
          </div>
          ${s.a_reveler > 0 ? `<div class="rangee">
            <span class="principal"><span class="nom">Cases en attente de révélation</span>
              <span class="detail">Achetées, verdict non encore ouvert</span></span>
            <span class="valeur"><b>${s.a_reveler}</b></span></div>` : ''}
        </div>
        <div class="pile">
          ${s.a_reveler > 0
            ? `<button class="bouton" data-a="reveler">Révéler les ${s.a_reveler} cases achetées</button>`
            : ''}
          <button class="bouton creux" data-a="projection">Écran de projection du tirage</button>
        </div>
      </div>
      <div class="section">
        <p class="etiq">Sauvegarde</p>
        <p class="sous">Le plan gratuit n'a pas de sauvegarde automatique. Exportez le
          journal une fois en milieu de soirée et une fois à la fin.</p>
        <div class="pile">
          <button class="bouton creux" data-a="export">Télécharger le journal (CSV)</button>
          <button class="bouton creux" data-a="lots">Suivi des lots</button>
        </div>
      </div>
    </div>`;
}

function vueLots() {
  const l = S.lots || [];
  return `<div class="ecran">
      ${barre('Suivi des lots', 'admin')}
      <div class="entete">
        <h1 class="titre">Lots gagnés</h1>
        <p class="sous">${l.filter((x) => !x.remis).length} à remettre sur ${l.length} gagnés</p>
      </div>
      <div class="groupe">
        ${l.length === 0 ? `<p class="vide">Aucun lot gagné pour le moment.</p>` : l.map((x) => `
          <div class="lot">
            <span class="principal">
              <span class="lnom">${esc(x.lot)}</span>
              <span class="ldetail">${esc(x.garage)} · case n°${x.numero} · ${esc(x.joue_a)} · code <b>${esc(x.code_retrait)}</b></span>
            </span>
            ${x.remis
              ? `<span class="lremis">Remis</span>`
              : `<button class="bouton petit" data-a="remettre" data-n="${x.numero}" style="width:auto;flex:0 0 auto">Remettre</button>`}
          </div>`).join('')}
      </div>
    </div>`;
}

// --- écran de projection du grand tirage (§11) -----------------------
function vueProjection() {
  const t = S.tirage;
  if (!t) return `<div class="projection"><p class="chargement">Chargement du tirage…</p></div>`;

  const gagnant = t.gagnant;
  const enCourse = t.en_course || [];
  const sortis = t.sortis || [];

  let tete;
  if (gagnant) {
    tete = `<div class="pscript">Et le grand gagnant est</div>
            <div class="ptitre">${esc(gagnant.garage)}</div>
            <div class="pinfo">${esc(gagnant.ville)} · billet n°${gagnant.numero}</div>`;
  } else if (!t.ouvert) {
    tete = `<div class="pscript">Le grand tirage</div>
            <div class="ptitre">${t.billets_reveles} billet${t.billets_reveles > 1 ? 's' : ''} en jeu</div>
            <div class="pinfo">Ouvrez le tirage quand la salle est prête.</div>`;
  } else {
    tete = `<div class="pscript">Manche ${t.manche}</div>
            <div class="ptitre">${enCourse.length} encore en course</div>
            <div class="pinfo">${sortis.length} éliminé${sortis.length > 1 ? 's' : ''}</div>`;
  }

  const jetons = [
    ...enCourse.map((b) => `<div class="pbillet${gagnant && gagnant.numero === b.numero ? ' gagnant' : ''}">
        <span class="pnum">${b.numero}</span>${esc(b.garage)}</div>`),
    ...sortis.map((b) => `<div class="pbillet sorti"><span class="pnum">${b.numero}</span>${esc(b.garage)}</div>`),
  ].join('');

  return `<div class="projection">
      ${tete}
      <div class="pcourse">${jetons}</div>
      <div class="pactions">
        ${!t.ouvert
          ? `<button class="bouton" data-a="tirage-ouvrir">Ouvrir le tirage</button>`
          : (gagnant
              ? `<button class="bouton creux" data-a="tirage-reset">Recommencer</button>`
              : `<button class="bouton" data-a="tirage-manche">${enCourse.length === 2 ? 'Désigner le gagnant' : 'Manche suivante'}</button>`)}
        <button class="bouton creux" data-a="admin">Quitter la projection</button>
      </div>
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
  projection: vueProjection,
};

function rendre(garderFocus) {
  // Décor animé et verre complet : les écrans garage, et la supervision
  // Bony — c'est UNE tablette, branchée, elle n'a aucune raison d'être
  // moins belle que le reste.
  // Verre allégé, sans flou : les seuls écrans animateur et fournisseur,
  // ceux qui tournent cinq heures dans une main.
  const avecDecor = ['accueil', 'espace', 'grille', 'revelation',
                     'projection', 'admin', 'lots', 'service'].includes(S.vue);
  const enService = ['animateur', 'fournisseur'].includes(S.vue);
  document.body.classList.toggle('decore', avecDecor);
  document.body.classList.toggle('service', enService);
  if (avecDecor) monterDecor();

  const champ = $('#q') || $('#pin') || $('#cg');
  const pos = champ ? champ.selectionStart : null;
  const idChamp = champ ? champ.id : null;

  $('#app').innerHTML = (VUES[S.vue] || VUES.chargement)();

  // Le verre liquide — la vraie réfraction par filtre SVG — est posé sur
  // les surfaces principales de l'écran, dans l'ordre d'importance et
  // plafonné : la chaîne de filtres est coûteuse, on ne la met pas
  // partout. Jamais sur les écrans animateur et fournisseur.
  if (avecDecor) {
    const candidats = $$('.solde, .fiche, .duo, .revele .rlot, .indic.large, .groupe');
    candidats.slice(0, 4).forEach((el) => verre.verrer(el));
  }

  if (garderFocus && idChamp) {
    const encore = $('#' + idChamp);
    if (encore) { encore.focus(); try { encore.setSelectionRange(pos, pos); } catch {} }
  }
}

// =====================================================================
//  Actions
// =====================================================================
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
    case 'accueil':   S.vue = 'accueil'; S.q = ''; S.code = ''; return rendre();
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

    // ---------------- entrée par code garage ----------------
    case 'entrer': {
      if (S.envoi) return;
      const code = (S.code || '').trim();
      if (code.length < 4) { toast('Code incomplet', 'Votre code fait 4 caractères.', 'attente'); return; }
      S.envoi = true; rendre();
      try {
        const r = await api.lire.entrer(code);
        // Un code refusé revient en résultat, pas en exception : c'est ce
        // qui permet au frein sur les tentatives d'être réellement compté.
        if (r && r.erreur) {
          S.envoi = false; rendre(true);
          const reste = (r.restantes != null && r.restantes <= 3)
            ? ` Encore ${r.restantes} essai${r.restantes > 1 ? 's' : ''}.` : '';
          toast(r.erreur === 'CODE_INCONNU' ? 'Code inconnu' : 'Trop d\'essais',
                (r.detail || '') + reste, 'negatif');
          return;
        }
        S.etat = r;
        api.definirRole({ role: 'garage' });
        S.r = { role: 'garage' };
        S.envoi = false; S.code = '';
        S.vue = 'espace'; rendre(); sondage();
        toast('Bienvenue !', `${esc(S.etat.garage.nom)} · <b>${S.etat.garage.solde}</b> points`);
      } catch (e) {
        S.envoi = false; rendre(true);
        toast(e.code === 'CODE_INCONNU' ? 'Code inconnu' : 'Impossible',
              e.detail || e.message, 'negatif');
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
          toast('Sans réseau', 'Une case exige une réponse immédiate. Réessayez quand le réseau revient.', 'attente');
        } else {
          S.revele = r; S.vue = 'revelation';
          await chargerEtat();
          if (!r.revelee) toast(`Case n°${n} réservée`, `−${S.etat.cout_grille} points · verdict ce soir`, 'attente');
          else if (r.nature === 'billet') toast('Billet décroché !', 'Vous êtes qualifié pour le grand tirage');
          else if (r.nature === 'lot') toast('Lot gagné !', esc(r.lot));
          else toast(`Case n°${n} perdante`, `−${S.etat.cout_grille} points · nouveau solde <b>${r.solde}</b>`, 'negatif');
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
    // ---------------- bingo : révélation et grand tirage ----------------
    case 'reveler': {
      if (!confirm('Révéler toutes les cases achetées ? Cette action est définitive.')) return;
      try {
        const r = await api.ecrit.reveler();
        await chargerSupervision(); rendre();
        toast('Cases révélées', `${r.revelees} case${r.revelees > 1 ? 's' : ''} ouverte${r.revelees > 1 ? 's' : ''}`);
      } catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      return;
    }
    case 'projection': {
      S.vue = 'projection'; rendre();
      try { S.tirage = await api.lire.tirage(); rendre(); }
      catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      return;
    }
    case 'tirage-ouvrir': {
      try { S.tirage = await api.ecrit.tirageOuvrir(); rendre();
            toast('Tirage ouvert', `${S.tirage.en_course.length} billets en course`); }
      catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      return;
    }
    case 'tirage-manche': {
      if (S.envoi) return;
      S.envoi = true;
      try {
        S.tirage = await api.ecrit.tirageManche(); rendre();
        if (S.tirage.gagnant) toast('Gagnant désigné', esc(S.tirage.gagnant.garage));
      } catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      finally { S.envoi = false; }
      return;
    }
    case 'tirage-reset': {
      if (!confirm('Effacer le tirage et recommencer ?')) return;
      try { await api.ecrit.tirageReset(); S.tirage = await api.lire.tirage(); rendre(); }
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

$('#app').addEventListener('input', (ev) => {
  const el = ev.target;

  // Saisie du code garage : on normalise à la volée et on valide dès que
  // les 4 caractères sont là. À l'entrée du Forum, un appui économisé sur
  // 150 personnes, ça compte.
  if (el.id === 'cg') {
    const avant = el.value;
    const propre = avant.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, '');
    S.code = propre;
    if (propre !== avant) { el.value = propre; }
    if (propre.length >= 4 && !S.envoi) agir('entrer', el);
    return;
  }

  if (el.id !== 'q') return;
  S.q = el.value;
  rendre(true);      // personnel : recherche locale, donc instantanée
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
