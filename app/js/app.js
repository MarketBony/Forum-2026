// =====================================================================
//  app.js — Le Grand Bal des Fournisseurs
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
  palier: 0,            // INDICE du palier choisi dans le barème du stand
  revele: null,         // résultat d'un tirage
  sup: null,            // tableau de bord Bony
  accueil: null,        // compteur d'arrivées du poste d'accueil
  trouves: null,        // résultats de recherche de l'accueil
  codeZoom: null,       // code affiché en très grand
  lots: null,
  tirage: null,       // etat du grand tirage du soir
  vitrine: null,      // la vue lecture seule de l'equipe Bony et des constructeurs
  vitrineVue: false,  // les chiffres ne se comptent qu'a la PREMIERE ouverture
  vitrineHaut: null,  // signature de la 1re ligne de journal deja vue
  panne: null,        // derniere panne de chargement, affichee plutot qu'avalee
  quota: null,        // refus de quota sur le garage vise — bandeau persistant
  deplie: {},         // sections longues de la supervision ouvertes en entier
  avantRegles: null,  // ecran d'ou l'on a ouvert les regles, pour y revenir
  sante: null,        // sonde de sante de la base, bande d'etat de la supervision
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

// Un refus de quota n'est pas une panne : c'est une REGLE. Un toast de
// quatre secondes disparait pendant que l'animateur relit le nom du
// garage, et il retente. Le bandeau reste tant qu'on regarde ce
// garage-la, et s'efface des qu'on passe au suivant.
// Une liste longue sur la supervision, c'est un écran qu'on scrolle au
// lieu de le lire. On n'en montre que le haut — le reste est à un appui.
// Le compte des masquées est dans le bouton : sans lui, on ne sait pas
// s'il y a trois lignes de plus ou vingt.
const APERCU = 6;

//  `interne` sert au journal : ses lignes veulent un conteneur
//  `.mouvements` a l'interieur du `.groupe`, sinon la grille des
//  colonnes heure / libelle / delta ne s'applique pas.
function sectionRepliable(cle, titre, lignes, rendreLigne, interne) {
  const tout = S.deplie[cle] === true;
  const vues = tout ? lignes : lignes.slice(0, APERCU);
  const reste = lignes.length - vues.length;
  const corps = vues.length
    ? vues.map(rendreLigne).join('')
    : '<p class="vide">Rien pour le moment.</p>';
  return `<div class="section">
      <p class="etiq">${esc(titre)}</p>
      <div class="groupe">${interne && vues.length
        ? `<div class="${interne}">${corps}</div>` : corps}</div>
      ${(reste > 0 || tout) ? `<button class="deplier" data-a="deplier" data-cle="${esc(cle)}">
        ${tout ? 'Réduire' : `Développer · ${reste} de plus`}</button>` : ''}
    </div>`;
}

function bandeauQuota() {
  if (!S.quota) return '';
  return `<div class="bandeau quota"><i></i>${esc(S.quota)}</div>`;
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

// --- la porte : un seul champ pour tout le monde (§6) -----------------
//  Garages, animateurs, fournisseurs, hôtesses et Bony tapent leur code
//  au même endroit. Personne n'a plus d'onglet à trouver, et personne ne
//  peut plus se tromper de champ.
function vueAccueil() {
  return guirlande() + `
    <div class="ecran">
      ${barre('Forum Pièces 2026')}
      <div class="entete">
        <div class="script">Bienvenue au</div>
        <h1 class="titre">${esc(CONFIG.evenement.nom)}</h1>
        <p class="sous">${esc(CONFIG.evenement.date)} · ${esc(CONFIG.evenement.lieu)}</p>
      </div>
      <div class="section">
        <p class="etiq">Votre code</p>
        <input class="champ code" id="cg" type="text" inputmode="text"
               autocomplete="off" autocapitalize="characters" spellcheck="false"
               maxlength="8" placeholder="••••" value="${esc(S.code)}"
               aria-label="Code d'accès" ${S.envoi ? 'disabled' : ''}>
        <button class="bouton" data-a="entrer" ${S.envoi ? 'disabled' : ''}>Entrer</button>
      </div>
      <p class="sous">Garages : votre code figure sur l'invitation. Vous l'avez
        perdu&nbsp;? L'accueil vous le redonne en trois secondes.<br>
        Animateurs, fournisseurs et équipe Bony : votre code de stand ou
        d'animation s'utilise ici aussi.</p>
    </div>`;
}

// --- espace garage (§7, §14) -----------------------------------------
function vueParticipant() {
  const e = S.etat;
  if (!e) return `<div class="ecran"><p class="chargement">Un instant…</p></div>`;
  const g = e.garage;
  return guirlande() + `
    <div class="ecran">
      ${barre('Mon espace', null,
        `<button class="lien" data-a="regles">Règles</button>
         <button class="lien" data-a="rafraichir">Actualiser</button>
         <button class="lien" data-a="quitter">Quitter</button>`)}
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
              // Après la révélation du soir, le ticket d'or cesse d'être
              // une promesse : il porte le nom du gros lot et son code de
              // retrait, au même endroit et dans la même forme que les
              // autres lots. Le garage n'a rien de nouveau à comprendre.
              if (c.nature === 'billet') return `<div class="lot">
                <span class="principal">
                  <span class="lnom">${esc(c.gros_lot || c.lot || "Ticket d'or")}</span>
                  <span class="ldetail">${c.gros_lot
                    ? `Case n°${c.numero} · code <b>${esc(c.code_retrait)}</b> ·
                       ${c.remis ? 'déjà retiré' : 'à retirer au stand des lots'}`
                    : `Case n°${c.numero} · un gros lot vous revient ce soir`}</span>
                </span>
                ${c.remis ? '<span class="lremis">Retiré</span>' : '<span class="cachet billet">★</span>'}</div>`;
              if (c.nature === 'lot') return `<div class="lot">
                <span class="principal">
                  <span class="lnom">${esc(c.lot)}</span>
                  <span class="ldetail">Case n°${c.numero} · code <b>${esc(c.code_retrait)}</b> ·
                    ${c.remis ? 'déjà retiré' : 'à retirer au stand des lots'}</span>
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
  // La taille de la grille vient de la base — un caractère par case
  // dans e.grille. Elle n'est plus écrite ici : redimensionner la
  // grille ne demande plus de redéployer le front.
  const total = e.cases_total || (e.grille ? e.grille.length : 0);
  const peut = e.garage.solde >= e.cout_grille;
  // Plafond de cases par garage : 0 = illimité.
  const reste = e.cases_max > 0 ? Math.max(0, e.cases_max - (e.mes_cases_nb || 0)) : null;
  const prises = e.grille || '0'.repeat(total);
  let cases = '';
  for (let n = 1; n <= total; n++) {
    const dispo = prises[n - 1] === '0';
    cases += `<button class="case" data-a="jouer" data-n="${n}" ${(!dispo || !peut || reste === 0) ? 'disabled' : ''}
      aria-label="Case ${n}${dispo ? '' : ' déjà jouée'}">${n}</button>`;
  }
  return guirlande() + `
    <div class="ecran">
      ${barre('Garage', 'espace')}
      ${bandeauReseau()}
      <div class="entete">
        <div class="script">La grille</div>
        <h1 class="titre">des ${total} cases</h1>
        <p class="sous">Une case au hasard, un lot peut-être. Chaque case ne se joue qu'une fois.</p>
      </div>
      <div class="surface duo">
        <div><span class="etiq">Participation</span><span class="dv">${e.cout_grille} pts</span></div>
        <div><span class="etiq">Votre solde</span>
          <span class="dv ${peut ? 'suffisant' : 'faible'}">${e.garage.solde} pts</span></div>
      </div>
      ${reste === 0
        ? `<div class="bandeau"><i></i>Vous avez pris vos ${e.cases_max} cases — l'équipe Bony peut en rouvrir en fin de journée</div>`
        : peut ? '' : `<div class="bandeau"><i></i>Il vous manque ${e.cout_grille - e.garage.solde} points — jouez ou achetez</div>`}
      <div class="section">
        <div class="grille">${cases}</div>
        <div class="legende"><span><i></i>${e.cases_libres} libres</span><span><i class="prise"></i>${total - e.cases_libres} jouées</span>${
          reste !== null && reste > 0 ? `<span>${reste} case${reste > 1 ? 's' : ''} pour vous</span>` : ''}</div>
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
        <div class="rk">${billet ? 'Vous avez' : (lot ? 'Bravo,' : 'Cette fois,')}</div>
        <div class="rt">${billet ? 'un gros lot !' : (lot ? "c'est gagné !" : "c'est raté")}</div>
        ${billet ? `<div class="rlot">${esc(r.lot || "Ticket d'or")}
            <div class="rnote">L'un des quinze gros lots vous revient. Il est
              déjà sous cette case ; il se révélera ce soir sur l'écran géant —
              <b>il faut être là</b>.</div></div>`
          : lot ? `<div class="rlot">${esc(r.lot)}
            <div class="rcode">${esc(r.code_retrait)}</div>
            <div class="rnote">Code de retrait, à présenter au stand des lots</div></div>`
          : `<p class="sous">Il reste des cases, et la soirée est longue.</p>`}
        <div class="rcase">Case n°${r.numero}</div>
      </div>
      <div class="pile">
        <button class="bouton" data-a="grille">Retenter ma chance</button>
        <button class="bouton creux" data-a="espace">Revenir à mon solde</button>
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
      ${barre(r.libelle, null, `<button class="lien" data-a="regles">Règles</button>
        <button class="lien" data-a="quitter">Quitter</button>`)}
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
      ${bandeauQuota()}
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
//  Les paliers ne sont plus écrits ici. Ils viennent du barème de la
//  CATÉGORIE du stand, que la porte renvoie avec le profil : « 200 à
//  699 € » chez FACOM, « 13 à 24 pneus » chez MICHELIN, « Contact »
//  chez CASTROL. Le représentant lit son propre vocabulaire au lieu de
//  traduire un nombre de points dans sa tête, un verre à la main.
//  S.palier est l'INDICE dans r.bareme, pas un nombre de points : deux
//  paliers pourraient un jour valoir le même nombre de points.
function vueFournisseur() {
  const r = S.r;
  if (!S.cible) {
    const liste = api.chercherLocal(S.q, 10);
    return `<div class="ecran">
      ${barre(r.libelle, null, `<button class="lien" data-a="regles">Règles</button>
        <button class="lien" data-a="quitter">Quitter</button>`)}
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
  // Le palier le plus bas est présélectionné : une frappe malheureuse
  // coûte 5 points, jamais 20. Une correction par le haut se remarque,
  // une correction par le bas passe inaperçue.
  const bar = r.bareme || [];
  const idx = Math.min(S.palier, bar.length - 1);
  const sel = bar[idx];
  return `<div class="ecran">
      ${barre(r.libelle, 'recherche')}
      ${bandeauReseau()}
      ${bandeauQuota()}
      <div class="groupe">
        <div class="rangee">
          <span class="principal"><span class="nom">${esc(S.cible.nom)}</span>
            <span class="detail">${esc(S.cible.ville)}</span></span>
          <span class="valeur"><b>${S.cible.solde}</b><span>pts</span></span>
        </div>
      </div>
      <div class="section">
        <p class="etiq">L'opération conclue</p>
        <div class="paliers">
          ${bar.map((b, i) =>
            `<button class="palier" data-a="palier" data-p="${i}" aria-pressed="${i === idx}">
               <span class="pl">${esc(b.libelle)}</span><span class="pp">+${b.points}</span>
             </button>`).join('')}
        </div>
        <p class="sous">Barème ${esc(r.categorie || '')} · l'écriture est signée au nom du stand.</p>
      </div>
      <button class="bouton bas" data-a="attribuer" ${(S.envoi || !sel) ? 'disabled' : ''}>Attribuer +${sel ? sel.points : 0} points</button>
    </div>`;
}


// =====================================================================
//  LES RÈGLES DU JEU — une version par profil
//
//  POURQUOI PAS UNE SEULE PAGE POUR TOUT LE MONDE. Un garagiste n'a rien
//  à faire des quotas de stand, et un représentant se moque de la grille
//  à 200 cases. Une page commune, c'est une page que personne ne lit
//  jusqu'au bout. Chacun voit SON mode d'emploi, en quatre ou cinq
//  temps, et rien d'autre.
//
//  LES CHIFFRES VIENNENT DE LA BASE, PAS DU TEXTE. Le coût d'une case,
//  le plafond de cases, la participation : tout est lu dans l'état
//  renvoyé par l'API. Si Bony change `cout_grille` en direct, les règles
//  changent avec — sinon elles mentiraient dès la première journée, et
//  des règles qui mentent sont pires que pas de règles.
//
//  LES PICTOS SONT DU SVG EN LIGNE, au trait, dans l'or de la charte.
//  Pas d'emoji : leur dessin change d'un téléphone à l'autre et certains
//  sortent en noir et blanc. Pas d'image non plus : un fichier de plus à
//  charger sur le wifi d'une halle, pour un dessin de vingt lignes.
// =====================================================================
const PICTO = {
  cle:     'M7 14a4 4 0 1 1 3.9-5h9.1l2 2-2 2-1.5-1.5L17 13l-1.5-1.5L14 13h-3.1A4 4 0 0 1 7 14Z',
  cadeau:  'M4 11h16v9H4zM2 7h20v4H2zM12 7v13M12 7S9.5 3 7.5 4 9 7 12 7Zm0 0s2.5-4 4.5-3-1.5 3-4.5 3Z',
  grille:  'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z',
  ticket:  'M12 3l2.6 5.6 6.1.8-4.5 4.2 1.2 6L12 16.8 6.6 19.6l1.2-6L3.3 9.4l6.1-.8z',
  loupe:   'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14zM20 20l-4.2-4.2',
  manette: 'M7 8h10a4 4 0 0 1 4 4v1a3 3 0 0 1-5.2 2L14 13h-4l-1.8 2A3 3 0 0 1 3 13v-1a4 4 0 0 1 4-4ZM7.5 11v2M6.5 12h2M16 11.5h.01M18 13h.01',
  poignee: 'M8 12l3-3 3 3 3-3M3 10l4-4 4 4M21 10l-4-4-4 4M6 14l4 4 3-3 3 3 4-4',
  ecran:   'M3 5h18v11H3zM9 20h6M12 16v4',
  horloge: 'M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM12 8v4l3 2',
  scene:   'M4 18V9l8-5 8 5v9M9 18v-5h6v5M2 18h20',
};

function picto(nom) {
  return `<svg class="pic" viewBox="0 0 24 24" aria-hidden="true"><path d="${PICTO[nom] || PICTO.cle}"/></svg>`;
}

//  Chaque profil : une note manuscrite, un titre, des temps numérotés,
//  et — quand ça aide — une rangée de chiffres clés.
function reglesDe(role) {
  const e = S.etat;
  const cout    = (e && e.cout_grille) || 20;
  const maxCase = (e && e.cases_max) || 5;
  const bonus   = 10;
  const cout_p  = (S.r && S.r.cout != null) ? S.r.cout : 2;

  if (role === 'garage') return {
    script: 'Trois choses', titre: 'à savoir, et c\'est tout',
    temps: [
      ['cle', 'Votre code ouvre tout', `Les quatre caractères de votre invitation. Pas de compte, pas de mot de passe. Il rouvre votre solde sur n'importe quel téléphone.`],
      ['manette', 'Vous gagnez des points', `${bonus} points en arrivant. Puis aux six animations, et sur les stands fournisseurs à chaque opération conclue.`],
      ['grille', 'Vous les dépensez sur la grille', `${cout} points la case, ${maxCase} cases maximum. Une case sur deux est gagnante.`],
      ['cadeau', 'Vous retirez votre lot', `Un code de retrait s'affiche. Vous le présentez au stand des lots, on vous remet le cadeau.`],
      ['ticket', 'Le ticket d\'or', `Quinze cases cachent un gros lot qui ne dit pas son nom. Il se révèle sur scène au cocktail — <b>il faut être là</b>.`],
    ],
    chiffres: [[cout, 'points la case'], ['1 sur 2', 'cases gagnantes'], [15, 'gros lots le soir']],
    note: `Perdu votre code ? L'accueil vous le redonne en trois secondes.`,
  };

  if (role === 'animateur') return {
    script: 'Votre stand', titre: 'en quatre gestes',
    temps: [
      ['loupe', 'Retrouvez le garage', `Tapez les premières lettres de son nom. La liste se réduit toute seule.`],
      ['manette', 'Lancez la partie', `${cout_p} points sont débités à ce moment-là. C'est le seul prix à payer pour jouer.`],
      ['cadeau', 'Notez le résultat', `Un seul appui sur le résultat obtenu. Le meilleur est en haut. Un double appui ne crédite jamais deux fois.`],
      ['horloge', 'Le quota', `Un garage ne peut pas tirer un nombre illimité de points de VOTRE animation. Quand il a eu sa part, un bandeau vous le dit — il peut aller jouer ailleurs.`],
    ],
    note: `Pas de réseau ? Continuez : tout part tout seul dès que ça revient.`,
  };

  if (role === 'fournisseur') return {
    script: 'Une vente', titre: 'conclue, et c\'est tout',
    temps: [
      ['loupe', 'Retrouvez le garage', `Les premières lettres de son nom suffisent.`],
      ['poignee', 'Choisissez ce qui a été conclu', `Les paliers sont ceux de VOTRE métier — un montant, un nombre de pneus, un simple contact. Pas de points à calculer.`],
      ['cadeau', 'Validez', `Les points partent sur son portefeuille immédiatement. Le palier le plus bas est présélectionné : une frappe malheureuse ne coûte jamais cher.`],
      ['horloge', 'Le quota', `Un garage ne peut pas tirer un nombre illimité de points de VOTRE stand. Quand il a eu sa part, un bandeau vous le dit.`],
    ],
    note: `Le compteur de votre stand est partagé par les cinq badges.`,
  };

  if (role === 'accueil') return {
    script: 'Votre poste', titre: 'en deux gestes',
    temps: [
      ['loupe', 'Cherchez l\'invité', `Par son nom ou sa commune. Les accents et les traits d'union n'ont pas d'importance.`],
      ['cle', 'Lisez-lui son code', `Quatre caractères, affichés en très grand. Il le tape sur son téléphone et son portefeuille s'ouvre.`],
      ['cadeau', 'Il n\'est pas dans la liste ?', `Remettez-lui un badge vierge et appelez l'équipe Bony. Personne ne reste à la porte.`],
    ],
    note: `Vous ne voyez ni les soldes ni le journal : ce n'est pas votre rôle, et c'est volontaire.`,
  };

  //  La vitrine : on parle a des gens qui REGARDENT. Pas un geste a
  //  apprendre, pas un bouton a trouver — juste ce que l'ecran raconte,
  //  et ce qu'il ne racontera pas.
  if (role === 'vitrine') return {
    script: 'Votre écran', titre: 'suit le Forum tout seul',
    temps: [
      ['ecran', 'Rien à faire', `L'écran se met à jour tout seul, toutes les trente secondes. Laissez-le ouvert, il vit avec la salle.`],
      ['grille', "Le Forum en un coup d’œil", `Combien de garages sont entrés, combien de points circulent, où en est la grille de deux cents cases.`],
      ['ticket', 'Les podiums', `Les garages qui marquent le plus, les stands qui distribuent le plus, les animations les plus jouées. Ça bouge toute la journée.`],
      ['horloge', 'Le journal en direct', `Chaque mouvement de points, à la minute. C'est là qu'on voit la salle travailler.`],
      ['cadeau', "Les tickets d’or", `Vous voyez combien sont décrochés, jamais par qui : le suspense est le même pour vous que pour la salle.`],
    ],
    note: `Votre code est personnel et il n'ouvre que cet écran — aucune écriture, aucun réglage. Ne le prêtez pas : c'est le seul moyen de savoir qui regarde.`,
  };

  return {
    script: 'La supervision', titre: 'et la soirée',
    temps: [
      ['ecran', 'L\'état de la base', `La console en haut de l\'écran. Tant que la santé globale est verte, tout va bien. Le tableau de bord Supabase, lui, comptera chaque refus voulu comme une erreur — ne vous y fiez pas.`],
      ['cadeau', 'La remise des lots', `« Suivi des lots » : le garage présente son code, vous le retrouvez, vous cochez « Remettre ».`],
      ['ticket', 'Les tickets d\'or', `Le détail de qui détient quoi. <b>Cet écran nomme les gros lots avant la révélation</b> — ne le montrez à personne.`],
      ['scene', 'Le grand tirage', `Un bouton, et la révélation se déroule seule, 6,5 secondes par lot. Un clic sur l'écran fait tomber le nom tout de suite, un second passe au lot suivant.`],
      ['horloge', 'Toutes les heures', `Exportez le journal en CSV. C'est la seule vraie sauvegarde de la soirée.`],
    ],
    note: `Le code supervision n'est sur aucun badge. Ne le donnez pas.`,
  };
}

function vueRegles() {
  const role = (S.r && S.r.role) || 'garage';
  const r = reglesDe(role);
  return `<div class="ecran regles">
      ${barre('Règles du jeu', 'retour-regles')}
      <div class="entete">
        <div class="script">${esc(r.script)}</div>
        <h1 class="titre">${esc(r.titre)}</h1>
      </div>
      ${r.chiffres ? `<div class="rchiffres">${r.chiffres.map(([v, l]) =>
        `<div class="rc"><b>${esc(String(v))}</b><span>${esc(l)}</span></div>`).join('')}</div>` : ''}
      <ol class="rtemps">
        ${r.temps.map(([ico, titre, texte], i) => `<li class="rt">
          <span class="rnum">${i + 1}</span>
          ${picto(ico)}
          <span class="rtx"><b>${esc(titre)}</b>${texte}</span>
        </li>`).join('')}
      </ol>
      ${r.note ? `<p class="rnote">${r.note}</p>` : ''}
      <button class="bouton creux bas" data-a="retour-regles">J'ai compris</button>
    </div>`;
}

// --- la bande d'état : la santé de la base, en haut de la supervision --
//
//  Cinq voyants, dans l'ordre où ils annoncent une catastrophe. Chacun
//  répond à une question qu'on se pose dans la halle, pas à une métrique
//  d'ingénieur.
//
//  Le premier — la RÉPONSE — est mesuré dans le navigateur, aller-retour
//  compris. C'est le seul qui voit le wifi, et le wifi est le risque le
//  plus probable de la soirée. Les quatre autres viennent de la base.
//
//  Le POOL est le voyant à surveiller : 11 connexions, plafond dur.
//  Au-delà, les téléphones suivants n'obtiennent RIEN — pas une erreur
//  lente, pas une file : rien. Et ces requêtes-là ne figurent même pas
//  dans les statistiques de Supabase, puisqu'elles n'ont jamais obtenu
//  de connexion. C'est l'angle mort que cette bande existe pour couvrir.
//
//  Les seuils sont volontairement PESSIMISTES : mieux vaut un orange
//  pour rien qu'un vert le soir où ça lâche.
//  LA FORME : une console d'instruments, pas un tableau de chiffres.
//
//  Chaque mesure est une LIGNE — libellé à gauche, barre au milieu, chiffre
//  à droite — parce qu'on ne compare pas ces cinq grandeurs entre elles :
//  on regarde, pour chacune, à quelle distance du rouge elle est. Une
//  barre horizontale dit ça d'un coup d'œil ; cinq tuiles carrées, non.
//
//  La barre est graduée en douze crans plutôt que continue. C'est le seul
//  parti pris purement graphique : un remplissage lisse se lit comme une
//  barre de chargement, une rangée de crans se lit comme un instrument, et
//  on voit le pas bouger même quand la valeur change peu.
//
//  charge() rend une fraction de 0 à 1 : la distance parcourue vers le
//  point de rupture. C'est ce qui permet de mettre sur la même échelle des
//  millisecondes, un nombre de connexions et un compte de verrous.
function crans(part, etat) {
  const N = 12, pleins = Math.min(N, Math.max(part > 0 ? 1 : 0, Math.round(part * N)));
  let out = '';
  for (let i = 0; i < N; i++) out += `<i class="${i < pleins ? 'on' : ''}"></i>`;
  return `<span class="cran ${etat}">${out}</span>`;
}

function mesure(nom, valeur, unite, part, etat, detail) {
  return `<div class="mes ${etat}" title="${esc(detail || '')}">
      <span class="mn">${esc(nom)}</span>
      ${crans(part, etat)}
      <span class="mv">${esc(String(valeur))}${unite ? `<i>${esc(unite)}</i>` : ''}</span>
    </div>`;
}

function bandeSante() {
  const h = S.sante;
  if (!h) {
    return `<div class="console attente">
      <div class="ctitre"><span class="cpuce"></span>État de la base de données</div>
      <div class="mes neutre"><span class="mn">Relevé en cours</span>
        ${crans(0, 'neutre')}<span class="mv">…</span></div>
    </div>`;
  }
  const pool = h.pool_max || 11;
  const ton = (p) => p < 0.55 ? 'ok' : (p < 0.8 ? 'tiede' : 'chaud');
  // Fraction du chemin vers la rupture, bornée à 1.
  const part = (v, rupture) => Math.min(1, Math.max(0, v / rupture));

  const pRtt     = part(h.rtt, 2000);       // 2 s : on croit que c'est cassé
  const pPool    = part(h.pool, pool);      // le plafond dur
  const pVerrous = part(h.verrous, 5);
  const pBloq    = part(h.bloquees, 3);
  const pEcarts  = h.ecarts > 0 ? 1 : 0;    // binaire : zéro, ou on arrête tout

  const lignes = [
    mesure('Réponse', h.rtt, 'ms', pRtt, ton(pRtt),
           'Aller-retour complet depuis cet appareil, wifi compris. Le seul chiffre qui voit le réseau de la halle.'),
    // Ce sont les connexions QUI TRAVAILLENT, pas celles que le pool
    // garde ouvertes. Mesuré le 15 septembre : après la montée en charge
    // les 11 restent ouvertes et inactives, et compter le total affichait
    // « 11/11 critique » en permanence pendant que tout répondait en
    // 105 ms — le rouge permanent qui ne veut plus rien dire.
    mesure('Pool PostgREST', `${h.pool}/${pool}`, '', pPool, ton(pPool),
           `Connexions en train de travailler, sur ${pool}.`
           + (h.pool_ouvertes != null ? ` ${h.pool_ouvertes} ouvertes en réserve.` : '')
           + ' Au plafond, les téléphones suivants attendent.'),
    mesure('Verrous en attente', h.verrous, '', pVerrous, h.verrous === 0 ? 'ok' : ton(Math.max(pVerrous, 0.6)),
           'Requêtes qui attendent qu\'une autre lâche un verrou. Doit rester à zéro.'),
    mesure('Transactions bloquées', h.bloquees, '', pBloq, h.bloquees === 0 ? 'ok' : ton(Math.max(pBloq, 0.6)),
           'Transactions ouvertes qui n\'avancent plus et tiennent leurs verrous.'),
    mesure('Soldes ↔ journal', h.ecarts, '', pEcarts, pEcarts ? 'chaud' : 'ok',
           'Écarts entre un solde affiché et la somme de son journal. Zéro, toujours.'),
  ].join('');

  // LA SANTÉ GLOBALE est la PIRE des cinq, pas leur moyenne. Une moyenne
  // noierait un écart de solde sous quatre voyants verts — or c'est
  // précisément le seul cas où il faut tout arrêter.
  const pires = [pRtt, pPool, pVerrous, pBloq, pEcarts];
  const pire = Math.max(...pires);
  const sante = Math.round((1 - pire) * 100);
  const tonGlobal = ton(pire);
  const verdict = tonGlobal === 'ok' ? 'Tout va bien'
                : tonGlobal === 'tiede' ? 'Sous tension — à surveiller'
                : 'Critique — agir maintenant';

  const alerte = h.ecarts > 0 ? 'Un solde ne correspond plus à son journal — arrêter les écritures et exporter le journal'
               : h.bloquees > 1 ? 'Des transactions sont bloquées : la base n\'est pas chargée, elle est coincée'
               : h.pool >= pool - 2 ? 'Le pool est presque plein — les téléphones vont commencer à ne plus répondre'
               : h.rtt >= 1200 ? 'Réponse très lente : regarder le wifi de la halle avant de soupçonner la base'
               : null;

  return `<div class="console">
      <div class="ctitre"><span class="cpuce ${tonGlobal}"></span>État de la base de données
        <span class="cheure">${esc(h.heure)}</span></div>
      ${lignes}
      <div class="cglobal ${tonGlobal}">
        <div class="cgt"><span>Santé globale</span><b>${sante}<i>%</i></b></div>
        <div class="cgb"><span style="width:${sante}%"></span></div>
        <div class="cgv">${verdict} · ${h.ecritures_min} écriture${h.ecritures_min > 1 ? 's' : ''}
          la dernière minute, ${h.ecritures_10min} sur dix</div>
      </div>
      ${alerte ? `<div class="valerte">${esc(alerte)}</div>` : ''}
    </div>`;
}

// --- supervision Bony (§12, §18) --------------------------------------
function vueAdmin() {
  const s = S.sup;
  if (!s) return ecranAttente('Supervision Bony', null);
  return `<div class="ecran">
      ${barre('Supervision Bony', null, `<button class="lien" data-a="regles">Règles</button>
        <button class="lien" data-a="quitter">Quitter</button>`)}
      ${bandeauReseau()}
      ${bandeSante()}
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
          <div class="iv">${s.cases_jouees} / ${s.cases_total}</div>
          <div class="il">Cases jouées · ${s.parties_financables} parties encore finançables avec les points en circulation</div>
          <!-- La largeur était le nombre de cases jouées pris DIRECTEMENT
               pour un pourcentage : juste tant que la grille faisait 100
               cases, faux dès qu'elle en fait 200. -->
          <div class="jauge"><span style="width:${Math.round(s.cases_jouees / Math.max(s.cases_total, 1) * 100)}%"></span></div>
        </div>
        ${s.ecarts_solde > 0 ? `<div class="indic large alerte"><div class="iv">${s.ecarts_solde}</div>
          <div class="il">Écarts entre solde et journal — à signaler immédiatement</div></div>` : ''}
      </div>
      ${s.tension ? `<div class="bandeau"><i></i>Plus de points en circulation que de cases restantes — resserrer les barèmes</div>` : ''}
      ${sectionRepliable('stands', 'Distribution par stand',
        // Les stands qui ont distribué en premier : un stand à zéro
        // n'apprend rien, et il y en a vingt-trois.
        [...s.par_stand].sort((x, y) => y.distribue - x.distribue),
        (p) => `<div class="rangee">
            <span class="principal"><span class="nom">${esc(p.stand)}</span></span>
            <span class="valeur"><b>${p.distribue}</b><span>/ ${p.plafond}</span></span>
          </div>`)}
      ${sectionRepliable('journal', 'Journal en direct', s.journal,
        (j) => `<div class="mvt"><span class="mh">${esc(j.heure)}</span>
            <span class="ml">${esc(j.garage + ' · ' + j.libelle)}<small>${esc(j.source)}</small></span>
            <span class="md ${j.delta > 0 ? 'plus' : 'moins'}">${j.delta > 0 ? '+' : ''}${j.delta}</span>
          </div>`, 'mouvements')}
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
            <span class="principal"><span class="nom">Tickets d'or</span>
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
        </div>
      </div>
      <!-- Le grand tirage a sa propre section, et le bouton est plein et
           seul : c'est le geste du soir, celui qu'on cherche sur scène
           avec le micro dans l'autre main. Il ne doit pas se confondre
           avec les boutons creux de service qui l'entourent. -->
      <div class="section">
        <p class="etiq">Le soir, au cocktail</p>
        <div class="pile">
          <button class="bouton" data-a="projection">Grand tirage au sort</button>
          <button class="bouton creux" data-a="tickets">Les tickets d'or en détail</button>
        </div>
        <p class="sous">${s.billets_vendus} ticket${s.billets_vendus > 1 ? 's' : ''} d'or
          décroché${s.billets_vendus > 1 ? 's' : ''} sur 15. Chaque ticket porte déjà son gros
          lot : la soirée ne tire rien, elle ouvre les enveloppes.</p>
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

// --- poste d'accueil : donner son code à un garage qui l'a perdu -----
function vueAccueilHotesse() {
  const e = S.accueil;      // compteur d'arrivées
  const r = S.trouves;      // résultats de recherche
  const zoom = S.codeZoom;  // un code affiché en très grand

  // Un code montré en grand, lisible de l'autre côté du comptoir.
  if (zoom) {
    return `<div class="ecran large">
      ${barre('Accueil du Forum', 'accueil-retour')}
      <div class="verre zoom">
        <div class="znom">${esc(zoom.nom)}</div>
        <div class="zlieu">${esc(zoom.cp || '')} ${esc(zoom.ville || '')}</div>
        <div class="zcode">${esc(zoom.code)}</div>
        <div class="znote">${zoom.arrive
          ? `Déjà entré dans l'application à ${esc(zoom.arrive_a)} · ${zoom.appareils} appareil${zoom.appareils > 1 ? 's' : ''}`
          : `Pas encore entré. Ce code ouvre son portefeuille.`}</div>
      </div>
      <button class="bouton creux bas" data-a="accueil-retour">Chercher un autre garage</button>
    </div>`;
  }

  const restants = e ? e.invites - e.arrives : 0;
  const part = e && e.invites ? Math.round((e.arrives / e.invites) * 100) : 0;

  return `<div class="ecran large">
    ${barre('Accueil du Forum', null, `<button class="lien" data-a="regles">Règles</button>
      <button class="lien" data-a="quitter">Quitter</button>`)}
    ${e ? `<div class="verre compteur">
      <div class="cchiffres"><b>${e.arrives}</b><span>sur ${e.invites} invités</span></div>
      <div class="jauge"><span style="width:${part}%"></span></div>
      <div class="cnote">${restants} garages pas encore entrés dans l'application</div>
    </div>` : ''}
    <div class="section">
      <p class="etiq">Chercher un garage</p>
      <input class="champ" id="q" type="text" autocomplete="off" spellcheck="false"
             placeholder="Nom, commune ou code postal…" value="${esc(S.q)}">
      ${r === null
        ? `<p class="sous">Deux caractères suffisent. La recherche ignore les accents et les majuscules.</p>`
        : (r.length === 0
            ? `<div class="groupe"><p class="vide">Aucun garage ne correspond.<br>Essayez la commune ou le code postal.</p></div>`
            : `<div class="groupe">${r.map((g) => `
                <button class="rangee accueil" data-a="zoom" data-id="${g.id}">
                  <span class="principal">
                    <span class="nom">${esc(g.nom)}</span>
                    <span class="detail">${esc(g.cp || '')} ${esc(g.ville || '')}${
                      g.arrive ? ` · arrivé à ${esc(g.arrive_a)}` : ''}</span>
                  </span>
                  <span class="codebulle${g.arrive ? ' vu' : ''}">${esc(g.code)}</span>
                </button>`).join('')}</div>`)}
    </div>
    ${e && e.derniers.length ? `<div class="section">
      <p class="etiq">Dernières arrivées</p>
      <div class="groupe">${e.derniers.map((d) => `
        <div class="rangee"><span class="principal">
          <span class="nom">${esc(d.nom)}</span>
          <span class="detail">${esc(d.ville)}</span></span>
          <span class="valeur"><b>${esc(d.heure)}</b></span></div>`).join('')}</div>
    </div>` : ''}
  </div>`;
}

// --- les tickets d'or en détail, pour l'équipe Bony -------------------
//
//  L'écran de projection est fait pour la salle ; celui-ci est fait pour
//  le comptoir. Il répond à trois questions qu'on se pose vraiment le
//  jour J : qui détient quoi, qui n'est pas encore sorti, et qui est
//  déjà reparti avec son lot.
//
//  ⚠️ IL NOMME LES GROS LOTS AVANT LA RÉVÉLATION. C'est voulu — Bony
//  prépare sa soirée — mais c'est le seul écran de l'application qui
//  vend la mèche. À ne pas montrer à un garage, ni projeter par erreur.
function vueTickets() {
  const t = S.tirage;
  if (!t) return ecranAttente("Tickets d'or", 'admin');

  const tous = t.tickets || [];
  const pris = tous.filter((k) => k.rang);
  const libres = tous.filter((k) => !k.rang);
  const remis = pris.filter((k) => k.remis).length;

  // Deux lignes différentes pour deux questions différentes. Sur un
  // ticket décroché on cherche QUI ; sur un ticket libre on cherche
  // QUELLE CASE — répéter « pas encore décroché » quinze fois sous un
  // titre qui le dit déjà ne renseigne personne.
  const ligne = (k) => k.rang ? `
    <div class="lot">
      <span class="principal">
        <span class="lnom">${esc(k.garage)}</span>
        <span class="ldetail">Case n°${k.numero} · ${esc(k.gros_lot)}${
          k.ville ? ' · ' + esc(k.ville) : ''}${
          k.decroche_a ? ' · décroché à ' + esc(k.decroche_a) : ''}${
          k.code_retrait ? ' · code <b>' + esc(k.code_retrait) + '</b>' : ''}</span>
      </span>
      ${k.remis
        ? '<span class="lremis">Remis</span>'
        : `<span class="cachet billet">${k.rang}</span>`}
    </div>` : `
    <div class="lot">
      <span class="principal">
        <span class="lnom" style="color:var(--txt-2)">Case n°${k.numero}</span>
        <span class="ldetail">${esc(k.gros_lot)}</span>
      </span>
      <span class="cachet">—</span>
    </div>`;

  return `<div class="ecran">
      ${barre("Tickets d'or", 'admin')}
      ${bandeauReseau()}
      <div class="entete">
        <div class="script">Les quinze</div>
        <h1 class="titre">tickets d'or</h1>
        <p class="sous">${t.revele
          ? 'Révélés. Le chiffre à droite est l\'ordre de passage sur scène.'
          : 'Pas encore révélés. Les garages ne savent pas ce qu\'ils ont gagné.'}</p>
      </div>
      <div class="indics">
        <div class="indic"><div class="iv">${pris.length} / 15</div><div class="il">Décrochés</div></div>
        <div class="indic"><div class="iv">${remis}</div><div class="il">Gros lots déjà remis</div></div>
      </div>
      ${libres.length > 0 ? `<div class="bandeau"><i></i>${libres.length} ticket${
        libres.length > 1 ? 's' : ''} encore dans la grille — ${libres.length > 1 ? 'ils seront passés' : 'il sera passé'
        } en silence pendant la révélation</div>` : ''}
      <div class="section">
        <p class="etiq">Décrochés · dans l'ordre de passage</p>
        <div class="groupe">
          ${pris.length ? pris.map(ligne).join('')
                        : '<p class="vide">Aucun ticket d\'or décroché pour le moment.</p>'}
        </div>
      </div>
      ${libres.length ? `<div class="section">
        <p class="etiq">Encore dans la grille</p>
        <div class="groupe">${libres.map(ligne).join('')}</div>
      </div>` : ''}
      <div class="section">
        <div class="pile">
          <button class="bouton creux" data-a="projection">Écran de projection</button>
          <button class="bouton creux" data-a="admin">Retour à la supervision</button>
        </div>
      </div>
    </div>`;
}

// --- écran de projection : la révélation des tickets d'or (§11) -------
//
//  Ce n'est plus un tirage : chaque ticket d'or est collé à son gros lot
//  depuis sql/23_grand_tirage.sql, et le seul hasard de la soirée a eu
//  lieu dans la journée, quand un garagiste a choisi sa case. L'écran
//  ouvre les enveloppes, dans un ordre de spectacle décidé à l'avance.
//
//  L'ANIMATION NE PASSE PAS PAR rendre(). Elle est montée une seule fois
//  et pilotée ensuite en basculant des classes sur le DOM en place :
//  réécrire innerHTML à chaque temps rejouerait les transitions CSS
//  depuis zéro et le texte clignoterait au lieu d'apparaître.
function vueProjection() {
  const t = S.tirage;
  if (!t) return `<div class="projection"><p class="chargement">Chargement du grand tirage…</p></div>`;

  const joues = (t.tickets || []).filter((k) => k.rang);   // les tickets décrochés
  const n = joues.length;

  // --- avant le lancement : la salle n'est pas encore prête ----------
  if (!t.revele && !S.revel) {
    return `<div class="projection">
      <div class="pscript">Le grand tirage</div>
      <div class="ptitre">${n} ticket${n > 1 ? 's' : ''} d'or</div>
      <div class="pinfo">${n} gros lot${n > 1 ? 's' : ''} à révéler${
        t.orphelins > 0
          ? ` · ${t.orphelins} ticket${t.orphelins > 1 ? 's' : ''} n'${t.orphelins > 1 ? 'ont' : 'a'} pas trouvé preneur, ${
              t.orphelins > 1 ? 'ils seront passés' : 'il sera passé'} en silence`
          : ''}</div>
      <div class="pactions">
        ${n > 0
          ? `<button class="bouton" data-a="tirage-lancer">Lancer la révélation</button>`
          : `<div class="bandeau"><i></i>Aucun ticket d'or décroché : rien à révéler</div>`}
        <button class="bouton creux" data-a="admin">Quitter la projection</button>
      </div>
    </div>`;
  }

  // --- le spectacle a déjà eu lieu : ON NE MONTRE RIEN ---------------
  //  L'écran de projection est branché sur le vidéoprojecteur AVANT le
  //  lancement, et c'est exactement cet écran que la salle regarde en
  //  attendant. Il affichait jusqu'ici le récapitulatif complet — noms
  //  des gagnants et lots — dès que le drapeau `tirage_revele` était
  //  levé. Une répétition non remise à zéro, et toute la salle lisait
  //  les quinze gagnants avant la première annonce.
  //
  //  Le récapitulatif reste à UN CLIC : l'équipe s'en sert au stand des
  //  lots pour retrouver qui a gagné quoi. Mais il faut désormais le
  //  demander, et ça ne s'ouvre pas tout seul sur un écran géant.
  if (t.revele && S.revel && S.revel.masque) {
    return `<div class="projection">
      <div class="pscript">Le grand tirage</div>
      <!-- NI TITRE NI EXPLICATION. Retiré le 16 septembre : cet écran
           est projeté sur grand écran avant le lancement, et « 15 gros
           lots attribués » disait déjà à la salle que tout était joué.
           Le pourquoi de la garde se lit ici, dans le code, pas sur le
           mur. Il reste le nom du spectacle et les boutons. -->
      <div class="pactions">
        <button class="bouton" data-a="tirage-recap">Afficher le récapitulatif</button>
        <button class="bouton creux" data-a="tirage-rejouer">Rejouer l'animation</button>
        <button class="bouton creux" data-a="admin">Quitter la projection</button>
      </div>
    </div>`;
  }

  // --- la scène, montée une fois pour toute la durée du spectacle ----
  //  Les cartes du récapitulatif sont posées tout de suite mais masquées :
  //  c'est ce qui permet à chaque temps de n'être qu'un ajout de classe.
  const pastilles = joues.map((k) =>
    `<span class="ppast" data-rang="${k.rang}"></span>`).join('');

  // Le garage AVANT le lot, comme sur la scène : c'est le nom qu'on
  // cherche dans ce tableau, au stand des lots comme depuis la salle.
  const cartes = joues.map((k) =>
    `<div class="ptk" data-rang="${k.rang}">
       <div class="ptknum">n°${k.numero}</div>
       <div class="ptkgar">${esc(k.garage)}</div>
       <div class="ptklot">${esc(k.gros_lot)}</div>
     </div>`).join('');

  return `<div class="projection revelation" id="scene">
      <div class="pscene" id="pscene">
        <div class="pscript">Le grand tirage</div>
        <div class="ptlot"   id="ptlot"></div>
        <div class="ptvers"  id="ptvers">revient à</div>
        <!-- Le halo est un élément à part, DERRIÈRE le nom. Le mettre en
             ombre portée sur le texte lui-même l'empâtait : à 100 px de
             haut, une lueur sur les lettres mange les contreformes et le
             nom devient illisible au fond de la salle. -->
        <div class="ptnom">
          <div class="pthalo" id="pthalo" aria-hidden="true"></div>
          <div class="ptgarage" id="ptgarage"></div>
        </div>
        <div class="ptdetail" id="ptdetail"></div>
      </div>
      <div class="ppastilles" id="ppastilles">${pastilles}</div>
      <div class="pgrille" id="pgrille">${cartes}</div>
      <div class="pactions" id="pactions">
        <button class="bouton creux" data-a="tirage-rejouer">Rejouer l'animation</button>
        <button class="bouton creux" data-a="admin">Quitter la projection</button>
      </div>
    </div>`;
}

// ---------------------------------------------------------------------
//  Le moteur de la révélation
//
//  LA DURÉE SE COMPTE PAR LOT, PLUS EN BUDGET TOTAL. Le réglage s'est
//  fait en quatre passes, sur scène et jamais au jugé :
//    57 s au total   → « un poil trop rapide »
//    95 s au total   → « un poil trop long »
//    80 s au total   → 4,4 s par lot, mais 8,9 s pour les trois derniers
//    4 s PAR LOT     → « 5 secondes par tirage grand max, et que ça
//                       enchaîne vite d'un tirage à l'autre »
//    6,5 s PAR LOT   → le réglage retenu. 4 s était trop sec une fois
//                       vu sur scène : le temps de lire le nom du
//                       gagnant manquait.
//
//  Le budget global a disparu avec cette dernière passe, et c'est le
//  bon modèle : ce que la salle ressent, c'est le temps d'UNE annonce,
//  pas la somme. Un budget total faisait dépendre le rythme du nombre
//  de tickets décrochés — à 8 tickets au lieu de 15, chaque annonce
//  durait presque le double, sans que personne l'ait demandé.
//
//  ⚠️ LE TEMPS DOUBLE DES TROIS DERNIERS A SAUTÉ. Il portait le
//  crescendo sur les trois pièces uniques — sac à dos Alpine,
//  weekender, sac cuir jaune à 379 € — et il est incompatible avec le
//  plafond de 5 s posé par Bastien : à poids double, elles tombaient à
//  8 s. Le spectacle finit donc sur le plus beau lot, mais au même
//  rythme que le reste. C'est un arbitrage de scène, pas un oubli.
//
//  Dans chaque temps : le LOT apparaît d'abord, seul. Le nom du garage
//  ne tombe qu'aux deux tiers du temps imparti. Ce silence-là est tout
//  le spectacle ; sans lui on affiche un tableau, on ne révèle rien.
// ---------------------------------------------------------------------
// Durée d'UN lot, hors carton de fin. 15 tickets = 97 s.
//
// LA ROULETTE DOIT AVOIR LE TEMPS DE FINIR SA DÉCÉLÉRATION. Elle se
// coupe net au temps imparti (garde-fou de scène, voir revelRouler), et
// une roulette coupée en plein élan s'arrête sans ralentir : on dirait
// une panne, pas un verdict. À 6,5 s, la part de suspense vaut 4,03 s
// et les 32 sauts en prennent 3,93 — ça passe, de 100 ms. Toucher à
// REVEL_PAR_LOT ou à REVEL_SUSPENSE sans rejouer un passage complet,
// c'est risquer de repasser sous cette marge sans que rien ne le dise.
const REVEL_PAR_LOT = 6500;
// Part du temps d'un ticket consacrée au SUSPENSE (roulette des noms).
// Le reste laisse le nom du gagnant affiché, en clair, avant de passer.
// Montée de 0,50 à 0,62 pour « enchaîner vite » : c'est le temps mort
// APRÈS la chute du nom qui donnait l'impression de traîner, pas la
// roulette. À 6,5 s, ça fait 4,0 s de roulette et 2,5 s de nom en
// clair — de quoi lire « Carrosserie Desmartin » au fond de la salle.
const REVEL_SUSPENSE = 0.62;
let revelMinuteur = null;

// La roulette : les noms des porteurs de ticket défilent de plus en plus
// lentement et s'arrêtent sur le gagnant. C'est du théâtre — le lot lui
// est attribué depuis la veille — mais c'est le théâtre que la salle
// attend, et il ne ment sur rien : tous les noms qui défilent sont bien
// ceux de garages qui ont décroché un ticket.
//
// La décélération est en p² : les premiers sauts s'enchaînent presque
// sans reprise, les derniers se détachent un par un. Un ralentissement
// linéaire donne une impression de panne, pas de suspense.
function revelRouler(el, noms, gagnant, duree, fin) {
  const sauts = Math.max(10, Math.round(duree / 127));   // cf. calage ci-dessous
  const debut = performance.now();
  let i = 0;
  el.classList.add('roule');
  const tic = () => {
    // GARDE-FOU DE SCÈNE. Un navigateur bride setTimeout à ~1 Hz dès que
    // l'onglet passe en arrière-plan : les 21 sauts de la roulette
    // s'étalaient alors sur 21 secondes au lieu de 2,6, et le spectacle
    // se serait enlisé si quelqu'un avait basculé de fenêtre en pleine
    // annonce. On se cale donc sur l'horloge murale, pas sur le nombre
    // de sauts effectués : au-delà du temps imparti, on s'arrête net.
    if (i >= sauts || performance.now() - debut >= duree) {
      el.classList.remove('roule');
      el.textContent = gagnant;
      fin();
      return;
    }
    // On évite de tomber sur le gagnant avant l'heure : le voir passer
    // puis repartir casse l'effet.
    let n = gagnant;
    if (noms.length > 1) { while (n === gagnant) n = noms[(Math.random() * noms.length) | 0]; }
    el.textContent = n;
    const p = i / sauts;
    i++;
    // 40 ms au départ, ~300 ms à l'arrivée. La moyenne de 40 + 260p²
    // vaut 40 + 260/3 ≈ 127 ms, d'où le diviseur du nombre de sauts.
    revelMinuteur = setTimeout(tic, 40 + 260 * p * p);
  };
  tic();
}

function revelArreter() {
  if (revelMinuteur) { clearTimeout(revelMinuteur); revelMinuteur = null; }
}

function revelJoues() {
  return ((S.tirage && S.tirage.tickets) || []).filter((k) => k.rang);
}

// Allume la pastille et la carte d'un rang. Appelé au moment où le nom
// tombe, et une seconde fois en bloc à la fin : le récapitulatif doit
// être COMPLET quelle que soit la façon dont le spectacle a été mené.
// Un animateur qui accélère à la main ne doit pas laisser neuf cartes
// éteintes derrière lui sous un titre qui annonce onze lots remis.
function revelAllumer(rang) {
  const p = $(`.ppast[data-rang="${rang}"]`); if (p) p.classList.add('vu');
  const c = $(`.ptk[data-rang="${rang}"]`);   if (c) c.classList.add('vu');
}

function revelFin() {
  revelArreter();
  const joues = revelJoues();
  S.revel = { rang: joues.length, total: joues.length, fini: true };
  const scene = $('#scene');
  if (!scene) return;
  scene.classList.add('fini');
  joues.forEach((k) => revelAllumer(k.rang));
  const lot = $('#ptlot'), gar = $('#ptgarage'), det = $('#ptdetail');
  if (lot) lot.textContent = `${joues.length} gros lot${joues.length > 1 ? 's' : ''} remis`;
  if (gar) gar.textContent = '';
  if (det) det.textContent = 'Rendez-vous au stand des lots avec votre code de retrait.';
}

function revelJouer(depart = 0) {
  revelArreter();
  const joues = revelJoues();
  if (!joues.length) return;

  // Un temps identique pour chaque lot : voir le plafond de 5 s en tête
  // de fichier. Plus de poids, plus de budget à répartir.
  const unite = REVEL_PAR_LOT;

  const scene = $('#scene');
  if (scene) scene.classList.remove('fini', 'nomme');
  // Rejouer repart d'un tableau vierge. Sans ça, les pastilles et les
  // cartes restaient allumées du passage précédent et le spectacle
  // s'ouvrait en annonçant que tout était déjà révélé.
  if (depart === 0) {
    $$('.ppast').forEach((p) => p.classList.remove('vu'));
    $$('.ptk').forEach((c) => c.classList.remove('vu'));
  }

  const noms = joues.map((k) => k.garage);

  // Fait tomber le nom du gagnant du temps courant. Séparé de l'étape
  // pour qu'un clic puisse le déclencher AVANT la fin du suspense.
  const nommer = (i) => {
    const k = joues[i];
    const gar = $('#ptgarage'), det = $('#ptdetail'), halo = $('#pthalo');
    if (!gar || !scene) return;
    revelArreter();
    gar.classList.remove('roule');
    gar.textContent = k.garage;
    det.textContent = `${k.ville || ''}${k.ville ? ' · ' : ''}case n°${k.numero}`;
    scene.classList.add('nomme');
    // On rejoue l'éclat en le retirant puis le remettant : sans ce
    // reflow forcé, l'animation ne repart pas d'un ticket à l'autre.
    if (halo) { halo.classList.remove('eclate'); void halo.offsetWidth; halo.classList.add('eclate'); }
    revelAllumer(k.rang);
  };

  const etape = (i) => {
    if (i >= joues.length) return revelFin();
    const k = joues[i];
    const duree = unite;

    // Arrêter la roulette à la main ne doit pas figer le spectacle : on
    // nomme tout de suite, puis on repart sur le minuteur normal. Sans
    // ça, un animateur qui presse le pas une fois devait ensuite cliquer
    // pour CHAQUE lot restant, micro dans l'autre main.
    const nommerPuisSuivre = () => {
      nommer(i);
      S.revel.nomme = true;
      revelMinuteur = setTimeout(() => etape(i + 1), duree * (1 - REVEL_SUSPENSE));
    };
    S.revel = { rang: i + 1, total: joues.length, nomme: false, nommer: nommerPuisSuivre };

    // 1. le lot s'annonce, et la roulette part aussitôt
    const lot = $('#ptlot'), gar = $('#ptgarage'), det = $('#ptdetail'),
          vers = $('#ptvers'), halo = $('#pthalo');
    if (!lot || !scene) return;             // l'écran a été quitté
    scene.classList.remove('nomme');
    if (halo) halo.classList.remove('eclate');
    lot.textContent = k.gros_lot;
    det.textContent = '';
    lot.classList.remove('entre'); void lot.offsetWidth; lot.classList.add('entre');
    vers.classList.remove('entre'); void vers.offsetWidth; vers.classList.add('entre');

    // 2. la roulette ralentit et s'arrête sur le gagnant, puis le nom
    //    reste en clair avant qu'on passe au lot suivant
    revelRouler(gar, noms, k.garage, duree * REVEL_SUSPENSE, nommerPuisSuivre);
  };

  etape(depart);
}

// Un clic n'importe où sur la scène fait avancer le spectacle : sur une
// estrade, l'animateur doit pouvoir presser le pas si la salle décroche.
// DEUX TEMPS, pas un : le premier clic fait tomber le nom du gagnant en
// cours, le second passe au lot suivant. Un clic unique qui sauterait
// directement au suivant escamoterait le nom — c'est-à-dire la seule
// chose que la salle attend.
function revelClic(e) {
  if (e.target.closest('.pactions')) return;      // les boutons gardent leur rôle
  if (!S.revel || S.revel.fini) return;
  if (!S.revel.nomme && S.revel.nommer) {
    revelArreter();
    S.revel.nommer();
    S.revel.nomme = true;
    return;
  }
  revelJouer(S.revel.rang);                        // reprend au temps suivant
}

// Retour sur un spectacle déjà joué : tout est montré d'emblée. C'est
// l'écran dont l'équipe se sert au stand des lots pour retrouver qui a
// gagné quoi, pas une rediffusion.
function revelRecapito() {
  revelArreter();
  const scene = $('#scene');
  if (!scene) return;
  scene.classList.add('fini');
  $$('.ppast').forEach((p) => p.classList.add('vu'));
  $$('.ptk').forEach((c) => c.classList.add('vu'));
  const joues = ((S.tirage && S.tirage.tickets) || []).filter((k) => k.rang);
  const lot = $('#ptlot'), det = $('#ptdetail');
  if (lot) lot.textContent = `${joues.length} gros lot${joues.length > 1 ? 's' : ''} attribué${joues.length > 1 ? 's' : ''}`;
  if (det) det.textContent = 'Le spectacle a déjà eu lieu.';
}

// =====================================================================
//  La vitrine — équipe Bony et invités constructeur
//
//  LECTURE SEULE, ET C'EST LA BASE QUI LE GARANTIT, PAS CET ÉCRAN. Le
//  rôle `vitrine` n'a accès qu'à api_vitrine ; aucune fonction
//  d'écriture ne l'accepte. Retirer un bouton d'ici ne protégerait rien
//  — voir sql/30_vitrine.sql.
//
//  Elle sera ouverte sur ~140 téléphones pendant six heures et se
//  rafraîchit seule au rythme participant. UN SEUL APPEL par
//  rafraîchissement : le pool PostgREST plafonne à 11 connexions, et
//  chacune prise ici est une case que quelqu'un n'achète pas.
// =====================================================================

// La barre de santé, et RIEN DE PLUS. La console de supervision montre
// le pool, les verrous et les transactions bloquées ; ces chiffres
// n'apprennent rien à un invité constructeur, et le serveur ne les
// envoie même pas jusqu'ici — api_vitrine ne rend que le verdict.
function santeVitrine(h) {
  if (!h) return '';
  const verdict = h.ton === 'ok' ? 'Tout tourne'
                : h.ton === 'tiede' ? 'Sous tension' : 'Ralenti';
  return `<div class="console vit">
      <div class="cglobal ${h.ton}">
        <div class="cgt"><span><span class="cpuce ${h.ton}"></span>Santé du Forum</span><b>${h.pct}<i>%</i></b></div>
        <div class="cgb"><span style="width:${h.pct}%"></span></div>
        <div class="cgv">${verdict} · ${h.ecritures_min} mouvement${h.ecritures_min > 1 ? 's' : ''}
          la dernière minute, ${h.ecritures_10min} sur les dix dernières</div>
      </div>
    </div>`;
}

// Un podium. LA BARRE EST PROPORTIONNELLE AU PREMIER, PAS AU TOTAL :
// sur cinq lignes, une part du total donne cinq traits minuscules là où
// une part du meilleur donne une silhouette qui se lit de loin.
function podium(titre, lignes, valeur, legende) {
  if (!lignes || !lignes.length) {
    return `<div class="section"><p class="etiq">${esc(titre)}</p>
      <div class="groupe"><p class="vide">Rien encore. Ça va venir.</p></div></div>`;
  }
  const max = Math.max(...lignes.map(valeur), 1);
  return `<div class="section"><p class="etiq">${esc(titre)}</p>
    <div class="podium">${lignes.map((x, i) => `
      <div class="pod r${i + 1}">
        <span class="podrang">${i + 1}</span>
        <span class="podcorps">
          <span class="podnom">${esc(x.nom)}${x.ville ? `<small>${esc(x.ville)}</small>` : ''}</span>
          <span class="podbar"><i style="width:${Math.round(valeur(x) / max * 100)}%"></i></span>
        </span>
        <span class="podval"><b data-compte="${valeur(x)}">0</b><span>${esc(legende(x))}</span></span>
      </div>`).join('')}</div></div>`;
}

function vueVitrine() {
  const v = S.vitrine;
  if (!v) return ecranAttente('Le Forum en direct', null);

  // Les lignes arrivées depuis le dernier passage sont marquées : sur un
  // écran qu'on regarde de loin, c'est le mouvement qui dit que ça vit.
  const sig = (j) => `${j.heure}|${j.garage}|${j.libelle}|${j.delta}`;
  const journal = v.journal || [];
  let neuves = 0;
  if (S.vitrineHaut) {
    const i = journal.findIndex((j) => sig(j) === S.vitrineHaut);
    neuves = i < 0 ? 0 : i;
  }
  S.vitrineHaut = journal.length ? sig(journal[0]) : null;

  const restants = v.billets_total - v.billets_vendus;

  return `<div class="ecran">
      ${barre('Le Forum en direct', null, `<button class="lien" data-a="regles">Règles</button>
        <button class="lien" data-a="quitter">Quitter</button>`)}
      ${bandeauReseau()}
      ${santeVitrine(v.sante)}
      <div class="entete">
        <div class="script">Le Forum</div>
        <h1 class="titre">en un coup d'œil</h1>
        <p class="sous">${esc(v.libelle)} · relevé de ${esc(v.heure)}, il se met à jour tout seul</p>
      </div>
      <div class="indics">
        <div class="indic"><div class="iv"><b data-compte="${v.garages_actifs}">0</b></div>
          <div class="il">Garages entrés, sur ${v.garages_invites} invités</div></div>
        <div class="indic"><div class="iv"><b data-compte="${v.points_emis}">0</b></div>
          <div class="il">Points distribués depuis ce matin</div></div>
        <div class="indic"><div class="iv"><b data-compte="${v.points_circulation}">0</b></div>
          <div class="il">Points encore dans les poches</div></div>
        <div class="indic"><div class="iv"><b data-compte="${v.operations}">0</b></div>
          <div class="il">Opérations conclues sur les stands</div></div>
        <div class="indic"><div class="iv"><b data-compte="${v.parties_jouees}">0</b></div>
          <div class="il">Parties jouées aux animations</div></div>
        <div class="indic"><div class="iv"><b data-compte="${v.lots_gagnes}">0</b></div>
          <div class="il">Lots gagnés · ${v.lots_remis} déjà remis</div></div>
        <div class="indic large">
          <div class="iv"><b data-compte="${v.cases_jouees}">0</b> / ${v.cases_total}</div>
          <div class="il">Cases jouées sur la grille · ${v.cases_libres} encore libres, à ${v.cout_grille} points</div>
          <div class="jauge"><span style="width:${Math.round(v.cases_jouees / Math.max(v.cases_total, 1) * 100)}%"></span></div>
        </div>
      </div>

      ${podium('Les garages qui marquent le plus', v.podium_garages,
        (x) => x.points, () => 'points')}
      ${podium('Les stands qui distribuent le plus', v.podium_stands,
        (x) => x.points, (x) => `points · ${x.operations} op.`)}
      ${podium('Les animations les plus jouées', v.podium_animations,
        (x) => x.parties, () => 'parties')}

      ${sectionRepliable('vjournal', 'Journal en direct', journal,
        (j, i) => `<div class="mvt${i < neuves ? ' neuf' : ''}"><span class="mh">${esc(j.heure)}</span>
            <span class="ml">${esc(j.garage + ' · ' + j.libelle)}</span>
            <span class="md ${j.delta > 0 ? 'plus' : 'moins'}">${j.delta > 0 ? '+' : ''}${j.delta}</span>
          </div>`, 'mouvements')}

      <div class="section">
        <p class="etiq">Les tickets d'or</p>
        <div class="groupe">
          <div class="rangee">
            <span class="principal">
              <span class="nom">Décrochés à cette heure</span>
              <span class="detail">Chacun cache un gros lot, déjà attribué</span></span>
            <span class="valeur"><b>${v.billets_vendus}</b><span>/ ${v.billets_total}</span></span>
          </div>
        </div>
        <!-- La phrase de situation vit ICI et pas dans .detail : cette
             classe coupe à l'ellipse sur une ligne, et la moitié du sens
             partait avec. -->
        <p class="sous">${v.tirage_revele
          ? 'La révélation a eu lieu. Les gros lots se retirent au stand des lots.'
          : restants > 0
            ? `${restants} dorme${restants > 1 ? 'nt' : ''} encore sous la grille, quelque part entre les deux cents cases.`
            : 'Tous décrochés. Rendez-vous ce soir sur scène pour savoir qui gagne quoi.'}</p>
        <!-- AUCUN NOM, AUCUN LOT, JAMAIS. Cet écran est ouvert sur 140
             téléphones dans la salle ; le détail des tickets d'or reste
             à la direction, et à elle seule. Arbitrage du 16 septembre. -->
        <p class="sous">La soirée ne tire rien au sort : chaque ticket porte déjà son gros lot.
          Elle ouvre les enveloppes.</p>
      </div>
    </div>`;
}

// LES CHIFFRES MONTENT UNE SEULE FOIS, à la première ouverture. Les
// rejouer à chaque rafraîchissement — toutes les trente secondes,
// pendant six heures — transformerait un écran d'information en machine
// à sous, et empêcherait de lire un chiffre qui bouge tout le temps.
function animerVitrine() {
  const doux = matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Les barres des podiums partent de zéro à CHAQUE rendu : elles sont
  // reconstruites par rendre(), donc l'animation repart d'elle-même, et
  // elle est assez discrète pour supporter la répétition.
  if (!doux) requestAnimationFrame(() => $$('.podbar i').forEach((b) => b.classList.add('pousse')));
  if (S.vitrineVue) { $$('[data-compte]').forEach((el) => { el.textContent = el.dataset.compte; }); return; }
  S.vitrineVue = true;
  $$('[data-compte]').forEach((el) => {
    const fin = parseInt(el.dataset.compte, 10) || 0;
    if (doux || fin === 0) { el.textContent = fin; return; }
    const debut = performance.now(), duree = 900;
    const pas = (t) => {
      const p = Math.min(1, (t - debut) / duree);
      // Sortie cubique : le chiffre part vite et se pose, au lieu de
      // s'arrêter net sur sa valeur.
      el.textContent = Math.round(fin * (1 - Math.pow(1 - p, 3)));
      if (p < 1) requestAnimationFrame(pas);
    };
    requestAnimationFrame(pas);
  });
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
  vitrine: vueVitrine,
  animateur: vueAnimateur,
  fournisseur: vueFournisseur,
  admin: vueAdmin,
  lots: vueLots,
  tickets: vueTickets,
  regles: vueRegles,
  projection: vueProjection,
  accueil_hotesse: vueAccueilHotesse,
};

function rendre(garderFocus) {
  // Décor animé et verre complet : les écrans garage, et la supervision
  // Bony — c'est UNE tablette, branchée, elle n'a aucune raison d'être
  // moins belle que le reste.
  // Verre allégé, sans flou : les seuls écrans animateur et fournisseur,
  // ceux qui tournent cinq heures dans une main.
  const avecDecor = ['accueil', 'espace', 'grille', 'revelation',
                     'projection', 'admin', 'vitrine', 'lots', 'tickets', 'regles',
                     'accueil_hotesse'].includes(S.vue);
  const enService = ['animateur', 'fournisseur'].includes(S.vue);
  document.body.classList.toggle('decore', avecDecor);
  document.body.classList.toggle('service', enService);
  if (avecDecor) monterDecor();

  const champ = $('#q') || $('#cg');
  const pos = champ ? champ.selectionStart : null;
  const idChamp = champ ? champ.id : null;

  $('#app').innerHTML = (VUES[S.vue] || VUES.chargement)();

  // Le verre liquide — la vraie réfraction par filtre SVG — est posé sur
  // les surfaces principales de l'écran, dans l'ordre d'importance et
  // plafonné : la chaîne de filtres est coûteuse, on ne la met pas
  // partout. Jamais sur les écrans animateur et fournisseur.
  // UN SEUL ÉLÉMENT VERRÉ, pas quatre. Le commentaire en tête de
  // verre.js disait déjà « réservée à UN élément par écran » ; le code en
  // verrait quatre, et chaque rendu détruisait puis recréait autant de
  // couches filtrées — à chaque sondage, donc toutes les 30 secondes sur
  // un téléphone, toutes les 10 sur la tablette. Le verre est une note de
  // grâce : la quatrième ne se voit pas et se paie quand même.
  if (avecDecor) {
    const cible = $('.solde') || $('.fiche') || $('.duo')
               || $('.revele .rlot') || $('.indic.large') || $('.groupe');
    if (cible && verre.verrer(cible)) verre.sonder();
  }

  if (garderFocus && idChamp) {
    const encore = $('#' + idChamp);
    if (encore) { encore.focus(); try { encore.setSelectionRange(pos, pos); } catch {} }
  }

  // Les animations de la vitrine se posent APRÈS l'écriture du DOM :
  // elles lisent des éléments qui n'existaient pas une ligne plus haut.
  if (S.vue === 'vitrine') animerVitrine();
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

// ---------------------------------------------------------------------
//  Une session peut mourir sous les pieds de l'écran
//
//  PIÈGE PAYÉ, ET IL IMMOBILISAIT LA TABLETTE BONY. chargerSupervision()
//  et chargerAccueil() avalaient TOUTE erreur dans un `catch {}` vide.
//  Quand l'appareil disparaît de la base — remise à zéro, purge des
//  appareils par une batterie de tests, rôle réattribué — l'appel échoue,
//  S.sup reste nul, et l'écran affiche « Chargement… » POUR TOUJOURS :
//  pas de message, pas de bouton, pas d'issue. Vu sur un vrai téléphone
//  le 15 septembre.
//
//  Les trois chargeurs réagissent donc pareil désormais : une session
//  morte renvoie à l'écran de code, et toute autre panne est retenue
//  dans S.panne pour que l'écran puisse le dire et proposer de
//  réessayer. Un « Chargement… » qui ne finit jamais est le pire des
//  états : il ne dit rien et n'offre rien.
// ---------------------------------------------------------------------
const SESSION_MORTE = ['APPAREIL_INCONNU', 'APPAREIL_SANS_GARAGE',
                       'JETON_INVALIDE', 'ROLE_INSUFFISANT'];

function sessionMorte(e) {
  if (e instanceof api.ErreurApi && SESSION_MORTE.includes(e.code)) {
    api.definirRole(null);
    S.r = null; S.sup = null; S.etat = null; S.accueil = null;
    S.lots = null; S.tirage = null; S.panne = null;
    S.vue = 'accueil';
    return true;
  }
  return false;
}

async function chargerSupervision() {
  try { S.sup = await api.lire.supervision(); S.panne = null; }
  catch (e) { if (!sessionMorte(e)) S.panne = e.detail || e.message; }
  // La sonde de santé est chargée À PART et ne fait jamais échouer la
  // supervision : si elle tombe, on veut quand même le tableau de bord.
  // Un voyant muet vaut mieux qu'un écran vide.
  try { S.sante = await api.lire.sante(); }
  catch { S.sante = null; }
}

// La vitrine tient en un seul appel : compteurs, podiums, journal et
// barre de sante. Voir sql/30_vitrine.sql.
async function chargerVitrine() {
  try { S.vitrine = await api.lire.vitrine(); S.panne = null; }
  catch (e) { if (!sessionMorte(e)) S.panne = e.detail || e.message; }
}

async function chargerAccueil() {
  try { S.accueil = await api.lire.accueilEtat(); S.panne = null; }
  catch (e) { if (!sessionMorte(e)) S.panne = e.detail || e.message; }
}

// Écran d'attente honnête : soit ça charge, soit ça a échoué et on le
// dit, avec de quoi s'en sortir.
function ecranAttente(titre, retour) {
  if (!S.panne) {
    return `<div class="ecran">${barre(titre, retour)}
      <p class="chargement">Chargement…</p></div>`;
  }
  return `<div class="ecran">${barre(titre, retour)}
    <div class="entete">
      <h1 class="titre">Rien n'est arrivé</h1>
      <p class="sous">${esc(S.panne)}</p>
    </div>
    <div class="pile">
      <button class="bouton" data-a="reessayer">Réessayer</button>
      <button class="bouton creux" data-a="quitter">Ressaisir mon code</button>
    </div></div>`;
}

let minuteurSondage = null;
function sondage() {
  if (minuteurSondage) clearInterval(minuteurSondage);
  const rythme = S.r && S.r.role === 'admin' ? CONFIG.sondageAdminMs : CONFIG.sondageMs;
  minuteurSondage = setInterval(async () => {
    if (document.hidden) return;
    if (S.vue === 'espace') { if (await chargerEtat()) rendre(); }
    else if (S.vue === 'admin') { await chargerSupervision(); rendre(); }
    else if (S.vue === 'vitrine') { await chargerVitrine(); rendre(); }
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
    case 'espace':    S.vue = 'espace'; await chargerEtat(); return rendre();
    case 'grille':    S.vue = 'grille'; await chargerEtat(); return rendre();
    case 'recherche': S.cible = null; S.partieLancee = false; S.q = ''; S.quota = null; return rendre();
    // On recharge toujours en revenant au tableau de bord : sinon un lot
    // que Bony vient de remettre reste affiché comme « à remettre »
    // jusqu'au sondage suivant, et l'équipe doute de l'outil.
    case 'admin':     S.vue = 'admin'; rendre(); await chargerSupervision(); return rendre();
    case 'rafraichir':
      if (await chargerEtat()) { rendre(); toast('Solde à jour', `<b>${S.etat.garage.solde}</b> points`); }
      else toast('Pas de réseau', 'Le solde affiché est celui de la dernière consultation.', 'attente');
      return;
    // Relance le chargement de l'écran courant après une panne. Le
    // bouton n'existe que sur ecranAttente, donc uniquement là où un
    // chargement a échoué.
    // Les règles s'ouvrent depuis n'importe quel écran et rendent la main
    // exactement où on était : au milieu d'une file d'attente, on ne veut
    // pas avoir à retrouver son garage.
    case 'regles':
      S.avantRegles = S.vue; S.vue = 'regles'; return rendre();
    case 'retour-regles':
      S.vue = S.avantRegles || 'accueil'; S.avantRegles = null; return rendre();

    case 'deplier': {
      const k = el.dataset.cle;
      S.deplie[k] = !S.deplie[k];
      return rendre();
    }
    case 'reessayer': {
      S.panne = null; rendre();
      if (S.vue === 'admin')        { await chargerSupervision(); return rendre(); }
      if (S.vue === 'accueil_hotesse') { await chargerAccueil();  return rendre(); }
      if (S.vue === 'tickets')      return agir('tickets');
      if (S.vue === 'lots')         return agir('lots');
      if (S.vue === 'espace')       { await chargerEtat();        return rendre(); }
      return rendre();
    }

    // ---------------- se déconnecter ----------------
    //
    //  PIÈGE PAYÉ ICI, ET IL EST INVISIBLE. On effaçait le JETON en même
    //  temps que le rôle. Or api_entrer ne compte l'appareil dans le
    //  plafond QUE si le jeton n'est pas déjà rattaché au garage :
    //
    //      if not exists (select 1 from appareils
    //                      where jeton = p_jeton and garage_id = v_g.id)
    //
    //  Un jeton neuf à chaque retour, c'est donc une ligne d'appareil de
    //  plus à chaque aller-retour — et une place prise ne se rend pas
    //  (le journal la référence). Au sixième, le garage se retrouve
    //  enfermé DEHORS avec un « Ce garage a déjà 6 appareils connectés ».
    //  C'est pour cette raison que l'écran garage n'avait pas de bouton.
    //
    //  On garde donc le jeton : c'est l'identité de l'APPAREIL, pas celle
    //  de la session. Seul le rôle s'efface, et le même téléphone qui
    //  ressaisit le même code retombe sur sa propre ligne.
    //
    //  La file d'attente hors ligne n'est pas vidée non plus : des points
    //  attribués sur un stand sans réseau doivent partir même si
    //  l'animateur a quitté son écran entre-temps.
    case 'quitter': {
      // Le garage, lui, confirme : son solde est derrière ce bouton, et
      // un pouce qui glisse dans le bruit ne doit pas le lui fermer.
      if (S.r && S.r.role === 'garage' &&
          !confirm('Fermer votre espace ? Il se rouvre avec votre code à 4 caractères.')) return;
      api.definirRole(null);
      S.r = null; S.etat = null; S.cible = null;
      S.vue = 'accueil'; S.q = ''; S.code = '';
      return rendre();
    }

    // ---------------- la porte unique ----------------
    case 'entrer': {
      if (S.envoi) return;
      clearTimeout(minuteurPorte);
      const code = (S.code || '').trim();
      if (code.length < 4) { toast('Code incomplet', 'Un code fait au moins 4 caractères.', 'attente'); return; }
      S.envoi = true; rendre();
      try {
        const r = await api.lire.ouvrir(code);

        // Un code refusé revient en résultat, pas en exception : c'est ce
        // qui permet au frein sur les tentatives d'être réellement compté.
        if (r && r.porte === 'refus') {
          S.envoi = false; rendre(true);
          const reste = (r.restantes != null && r.restantes <= 3)
            ? ` Encore ${r.restantes} essai${r.restantes > 1 ? 's' : ''}.` : '';
          toast(r.erreur === 'CODE_INCONNU' ? 'Code inconnu' : 'Trop d\'essais',
                (r.detail || '') + reste, 'negatif');
          return;
        }

        // Personnel : animateur, fournisseur, hôtesse ou Bony.
        if (r.porte === 'personnel') {
          api.definirRole(r); S.r = r;
          S.vue = r.role === 'admin' ? 'admin'
                : (r.role === 'accueil' ? 'accueil_hotesse' : r.role);
          S.q = ''; S.code = ''; S.cible = null; S.partieLancee = false;
          S.trouves = null; S.codeZoom = null; S.envoi = false;
          rendre();
          toast('Connecté', esc(r.libelle));
          if (r.role === 'accueil') { await chargerAccueil(); rendre(); }
          // La vitrine ne cherche jamais un garage : inutile de lui
          // telecharger le cache des 1 456, c'est 200 Ko pour rien sur
          // le wifi de la halle.
          else if (r.role !== 'vitrine') { api.rafraichirGarages().then(() => rendre()).catch(() => {}); }
          if (r.role === 'admin') { await chargerSupervision(); rendre(); }
          if (r.role === 'vitrine') { await chargerVitrine(); rendre(); }
          sondage();
          return;
        }

        // Garage.
        S.etat = r;
        api.definirRole({ role: 'garage' });
        S.r = { role: 'garage' };
        S.envoi = false; S.code = '';
        S.vue = 'espace'; rendre(); sondage();
        toast('Bienvenue !', `${esc(S.etat.garage.nom)} · <b>${S.etat.garage.solde}</b> points`);
      } catch (e) {
        S.envoi = false; rendre(true);
        toast(e.code === 'CODE_TROP_COURT' ? 'Code incomplet' : 'Impossible',
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
          else if (r.nature === 'billet') toast("Ticket d'or !", 'Un des quinze gros lots vous revient — rendez-vous au tirage de ce soir');
          else if (r.nature === 'lot') toast('Lot gagné !', esc(r.lot));
          else toast(`Case n°${n} perdante`, `−${S.etat.cout_grille} points · nouveau solde <b>${r.solde}</b>`, 'negatif');
        }
      } catch (e) {
        toast(e.code === 'CASE_DEJA_PRISE' ? 'Case déjà prise' : 'Impossible', e.detail || e.message, 'negatif');
        await chargerEtat();
      } finally { S.envoi = false; rendre(); }
      return;
    }

    // ---------------- personnel : cibler un garage ----------------
    case 'cibler': {
      S.quota = null;                 // on change de garage : le quota du precedent ne le concerne pas
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
        if (e.code === 'QUOTA_ANIMATION') S.quota = e.detail || e.message;
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
      const bar = (S.r && S.r.bareme) || [];
      const choix = bar[Math.min(S.palier, bar.length - 1)];
      if (!choix) return;                     // stand sans barème : rien à envoyer
      S.envoi = true; rendre();
      const nom = S.cible.nom, pts = choix.points;
      const cle = api.nouvelleCle();
      try {
        const r = await api.ecrit.achat(S.cible.id, pts, choix.libelle, cle);
        ajusterCache(S.cible.id, pts);
        // Le palier revient au plus bas pour le garage suivant : laisser
        // « Commande » armé ferait créditer 20 points au visiteur d'après.
        S.cible = null; S.q = ''; S.palier = 0;
        if (r.enAttente) toast('Enregistré hors ligne', `${esc(nom)} · +${pts} pts en attente d'envoi`, 'attente');
        else toast(`+${pts} points ajoutés`, `${esc(nom)} · nouveau solde <b>${r.solde}</b>`);
      } catch (e) {
        // Le quota reste affiché sous les yeux du représentant : il doit
        // comprendre que ce garage a eu sa part, pas croire à une panne
        // et réessayer trois fois.
        if (e.code === 'QUOTA_STAND') S.quota = e.detail || e.message;
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
      try { S.lots = await api.lire.lots(); S.panne = null; S.vue = 'lots'; rendre(); }
      catch (e) {
        if (!sessionMorte(e)) S.panne = e.detail || e.message;
        rendre(); toast('Impossible', e.detail || e.message, 'negatif');
      }
      return;
    }
    // ---------------- poste d'accueil ----------------
    case 'accueil-retour': S.codeZoom = null; return rendre();
    case 'zoom': {
      const g = (S.trouves || []).find((x) => x.id === el.dataset.id);
      if (g) { S.codeZoom = g; rendre(); }
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
    case 'tickets': {
      S.vue = 'tickets'; rendre();
      // On recharge à chaque entrée : c'est l'écran qu'on rouvre pour
      // vérifier qu'un lot vient d'être remis, il ne doit jamais montrer
      // l'état d'il y a dix minutes.
      try { S.tirage = await api.lire.tirage(); S.panne = null; rendre(); }
      catch (e) {
        if (!sessionMorte(e)) S.panne = e.detail || e.message;
        rendre(); toast('Impossible', e.detail || e.message, 'negatif');
      }
      return;
    }
    case 'projection': {
      revelArreter(); S.revel = null;
      S.vue = 'projection'; rendre();
      try {
        S.tirage = await api.lire.tirage(); rendre();
        // Déjà révélé : on n'affiche NI l'animation, ni les gagnants. Un
        // écran de garde, et deux boutons. Rejouer la minute serait une
        // punition pour qui vient chercher un code de retrait ; déballer
        // le récapitulatif serait pire, l'écran est branché au
        // vidéoprojecteur. Voir vueProjection().
        if (S.tirage.revele) { S.revel = { fini: true, masque: true }; rendre(); }
      } catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      return;
    }
    case 'tirage-lancer': {
      if (S.envoi) return;
      S.envoi = true;
      try {
        S.tirage = await api.ecrit.tirageLancer();
        S.revel = { rang: 0 };
        rendre();
        revelJouer(0);
      } catch (e) { toast('Impossible', e.detail || e.message, 'negatif'); }
      finally { S.envoi = false; }
      return;
    }
    case 'tirage-recap': {
      // Le geste volontaire de l'équipe, au stand des lots.
      S.revel = { fini: true };
      rendre();
      revelRecapito();
      return;
    }
    case 'tirage-rejouer': {
      // Depuis l'écran de garde, la scène n'est pas montée : revelJouer()
      // ne trouverait ni #scene ni #ptlot et rendrait la main sans un
      // mot. On la monte d'abord, puis on joue.
      if (S.revel && S.revel.masque) { S.revel = { rang: 0 }; rendre(); }
      revelJouer(0);
      return;
    }
    case 'tirage-reset': {
      if (!confirm('Remettre le grand tirage à « non révélé » ? À ne faire qu\'après une répétition.')) return;
      revelArreter(); S.revel = null;
      try { S.tirage = await api.ecrit.tirageReset(); rendre(); }
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
  if (!el) {
    // Hors bouton : sur l'écran de projection, un clic fait avancer le
    // spectacle. Délégué ici parce que rendre() remonte le DOM et
    // emporterait un écouteur posé sur la scène elle-même.
    if (S.vue === 'projection') revelClic(ev);
    return;
  }
  ev.preventDefault();
  agir(el.dataset.a, el);
});

$('#app').addEventListener('input', (ev) => {
  const el = ev.target;

  // Saisie du code, toutes portes confondues.
  //
  // On normalise sur A-Z0-9, et surtout PAS sur l'alphabet des codes
  // garage : celui-ci exclut les 0 et les 1 pour qu'on ne les confonde
  // pas avec O et I, mais les PIN du personnel en sont pleins. Filtrer
  // ici transformerait « 1001 » en chaîne vide, sous les doigts de
  // l'animateur, sans un mot d'explication.
  //
  // La validation part toute seule, mais après une pause : un code
  // garage fait 4 caractères, un PIN peut en faire plus. Valider sec au
  // quatrième brûlerait un essai à celui qui n'a pas fini de taper.
  if (el.id === 'cg') {
    const avant = el.value;
    const propre = avant.toUpperCase().replace(/[^A-Z0-9]/g, '');
    S.code = propre;
    if (propre !== avant) { el.value = propre; }
    clearTimeout(minuteurPorte);
    if (propre.length >= 4 && !S.envoi) {
      minuteurPorte = setTimeout(() => agir('entrer', el), 700);
    }
    return;
  }

  if (el.id !== 'q') return;
  S.q = el.value;

  // L'accueil cherche parmi les 1 407 invités, donc côté serveur : on
  // attend la fin de la frappe pour ne pas envoyer une requête par lettre.
  if (S.vue === 'accueil_hotesse') {
    rendre(true);
    clearTimeout(minuteurAccueil);
    minuteurAccueil = setTimeout(async () => {
      const q = S.q.trim();
      if (q.length < 2) { S.trouves = null; return rendre(true); }
      try { S.trouves = await api.lire.accueilChercher(q); }
      catch (e) { S.trouves = []; }
      rendre(true);
    }, 260);
    return;
  }

  rendre(true);      // animateur et fournisseur : recherche locale
});
let minuteurAccueil = null;
let minuteurPorte = null;

// Entrée au clavier : on n'attend pas la temporisation. C'est le geste
// de celui qui sait son code, et de tout le personnel sur ordinateur.
$('#app').addEventListener('keydown', (ev) => {
  if (ev.key !== 'Enter' || ev.target.id !== 'cg') return;
  ev.preventDefault();
  clearTimeout(minuteurPorte);
  agir('entrer', ev.target);
});

addEventListener('online',  () => { S.horsLigne = false; rendre(); api.viderFile(); });
addEventListener('offline', () => { S.horsLigne = true;  rendre(); });
api.surFile((n) => { S.enFile = n; if (S.vue !== 'chargement') rendre(); });

document.addEventListener('visibilitychange', async () => {
  if (document.hidden) return;
  if (S.vue === 'espace') { if (await chargerEtat()) rendre(); }
  if (S.vue === 'admin') { await chargerSupervision(); rendre(); }
  if (S.vue === 'vitrine') { await chargerVitrine(); rendre(); }
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
  //
  // PIÈGE : on retient le rôle dans une variable AVANT les chargements.
  // sessionMorte() met S.r à null quand le jeton n'est plus reconnu — et
  // la ligne suivante lisait alors S.r.role sur null, ce qui plantait le
  // démarrage sans un mot. Le cas arrive dès qu'un appareil disparaît de
  // la base, ce qui est exactement la situation où on a besoin que
  // l'application retombe proprement sur l'écran de code.
  const role = S.r.role;
  S.vue = role === 'admin' ? 'admin'
        : (role === 'accueil' ? 'accueil_hotesse' : role);
  rendre();
  if (role === 'admin') { await chargerSupervision(); rendre(); }
  else if (role === 'vitrine') { await chargerVitrine(); rendre(); }
  else if (role === 'accueil') { await chargerAccueil(); rendre(); }
  else api.rafraichirGarages().then(() => rendre()).catch(() => {});
  if (S.r) sondage();          // session morte entre-temps : rien à sonder
})();

// Service worker : coquille hors ligne
if ('serviceWorker' in navigator) {
  addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {}));
}
