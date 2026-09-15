// =====================================================================
//  api.js — accès à la base et file d'attente hors ligne
//
//  Deux principes :
//
//  1. Toute ÉCRITURE porte une clé d'idempotence générée ici, côté
//     téléphone, et conservée avec l'opération. Si le réseau lâche au
//     mauvais moment, on peut réessayer autant de fois qu'on veut : la
//     base n'enregistrera l'opération qu'une seule fois.
//
//  2. Une écriture qui ne part pas n'est jamais perdue : elle entre dans
//     une file conservée dans le téléphone, qui se vide dès que le
//     réseau revient. C'est ce qui permet à un animateur de continuer à
//     travailler dans une halle où le Wi-Fi tombe.
// =====================================================================
import { CONFIG } from '../config.js';

const CLE_JETON = 'gbp.jeton';
const CLE_FILE  = 'gbp.file';
const CLE_ROLE  = 'gbp.role';

// ---------------------------------------------------------------------
//  Identité de l'appareil
// ---------------------------------------------------------------------
function alea() {
  if (crypto.randomUUID) return crypto.randomUUID().replace(/-/g, '');
  const o = new Uint8Array(16);
  crypto.getRandomValues(o);
  return [...o].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function jeton() {
  let j = localStorage.getItem(CLE_JETON);
  if (!j) {
    j = alea() + alea();
    localStorage.setItem(CLE_JETON, j);
  }
  return j;
}

export function nouvelleCle() {
  return alea();
}

export function role() {
  try { return JSON.parse(localStorage.getItem(CLE_ROLE) || 'null'); }
  catch { return null; }
}

export function definirRole(r) {
  if (r) localStorage.setItem(CLE_ROLE, JSON.stringify(r));
  else localStorage.removeItem(CLE_ROLE);
}

export function oublierAppareil() {
  localStorage.removeItem(CLE_JETON);
  localStorage.removeItem(CLE_ROLE);
  localStorage.removeItem(CLE_FILE);
}

// ---------------------------------------------------------------------
//  Erreurs
// ---------------------------------------------------------------------
export class ErreurApi extends Error {
  constructor(code, detail, statut) {
    super(detail || code);
    this.code = code;        // ex. SOLDE_INSUFFISANT
    this.detail = detail;    // phrase lisible par un humain
    this.statut = statut;    // code HTTP
    this.metier = statut >= 400 && statut < 500;
  }
}

export class ErreurReseau extends Error {
  constructor(cause) {
    super('Réseau indisponible');
    this.cause = cause;
    this.metier = false;
  }
}

// ---------------------------------------------------------------------
//  Appel brut
// ---------------------------------------------------------------------
async function appel(nom, params, { delaiMs = 12000 } = {}) {
  const ctrl = new AbortController();
  const minuteur = setTimeout(() => ctrl.abort(), delaiMs);
  let rep;
  try {
    rep = await fetch(`${CONFIG.url}/rest/v1/rpc/${nom}`, {
      method: 'POST',
      headers: {
        'apikey': CONFIG.cle,
        'Authorization': `Bearer ${CONFIG.cle}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(params),
      signal: ctrl.signal,
    });
  } catch (e) {
    throw new ErreurReseau(e);            // coupure, DNS, abandon : on réessaiera
  } finally {
    clearTimeout(minuteur);
  }

  const texte = await rep.text();
  let corps = null;
  try { corps = texte ? JSON.parse(texte) : null; } catch { /* corps non JSON */ }

  if (!rep.ok) {
    // 5xx et 429 : incident passager, on traite comme du réseau pour réessayer.
    if (rep.status >= 500 || rep.status === 429) throw new ErreurReseau(new Error(`HTTP ${rep.status}`));
    throw new ErreurApi(
      (corps && corps.message) || `HTTP ${rep.status}`,
      (corps && corps.details) || '',
      rep.status,
    );
  }
  return corps;
}

// ---------------------------------------------------------------------
//  Lectures — jamais mises en file, on réessaiera au prochain sondage
// ---------------------------------------------------------------------
export const lire = {
  etat:        ()       => appel('api_etat', { p_jeton: jeton() }),
  chercher:    (q)      => appel('api_chercher', { p_jeton: jeton(), p_q: q || '' }),
  supervision: ()       => appel('api_supervision', { p_jeton: jeton() }),
  // Une seule porte : la base reconnaît elle-même si le code est celui
  // d'un garage, d'une animation, d'un stand, de l'accueil ou de Bony.
  // Pour un garage, ce code est à la fois la clé d'entrée et la clé de
  // retour : le retaper rouvre le même portefeuille, sur n'importe quel
  // téléphone.
  ouvrir:      (code)   => appel('api_ouvrir', { p_jeton: jeton(), p_code: code }),
  garages:     ()       => appel('api_garages_liste', { p_jeton: jeton() }, { delaiMs: 25000 }),
  journal:     ()       => appel('api_journal_complet', { p_jeton: jeton() }, { delaiMs: 30000 }),
  lots:        ()       => appel('api_lots', { p_jeton: jeton() }),
  tirage:      ()       => appel('api_tirage_etat', { p_jeton: jeton() }),
  // Poste d'accueil : le seul endroit où un code de garage est lisible
  accueilChercher: (q) => appel('api_accueil_chercher', { p_jeton: jeton(), p_q: q }),
  accueilEtat:     ()  => appel('api_accueil_etat', { p_jeton: jeton() }),
};

// ---------------------------------------------------------------------
//  Cache local de la liste des garages : c'est lui qui rend la
//  recherche instantanée et, surtout, utilisable sans réseau.
// ---------------------------------------------------------------------
const CLE_GARAGES = 'gbp.garages';

export function garagesEnCache() {
  try { return JSON.parse(localStorage.getItem(CLE_GARAGES) || 'null'); }
  catch { return null; }
}

export async function rafraichirGarages() {
  const liste = await lire.garages();
  localStorage.setItem(CLE_GARAGES, JSON.stringify({ quand: Date.now(), liste }));
  return liste;
}

/** Recherche locale, insensible aux accents et à la casse. */
export function chercherLocal(q, max = 10) {
  const cache = garagesEnCache();
  if (!cache) return null;
  const n = (s) => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();
  const t = n((q || '').trim());
  const l = cache.liste;
  if (!t) return l.slice(0, max);
  return l.filter((g) => n(g.nom + ' ' + g.ville).includes(t)).slice(0, max);
}

// ---------------------------------------------------------------------
//  File d'attente des écritures
// ---------------------------------------------------------------------
const abonnes = new Set();

function fileLire() {
  try { return JSON.parse(localStorage.getItem(CLE_FILE) || '[]'); }
  catch { return []; }
}
function fileEcrire(f) {
  localStorage.setItem(CLE_FILE, JSON.stringify(f));
  abonnes.forEach((fn) => { try { fn(f.length); } catch {} });
}
export function fileTaille() { return fileLire().length; }
export function surFile(fn) { abonnes.add(fn); fn(fileTaille()); return () => abonnes.delete(fn); }

/**
 * Écriture fiable.
 *  - la clé d'idempotence est créée une fois et ne change JAMAIS, même
 *    après vingt réessais : c'est ce qui interdit le double crédit ;
 *  - si le réseau manque, l'opération est mise en file et la promesse
 *    est résolue avec { enAttente: true } pour que l'animateur ne soit
 *    pas bloqué ;
 *  - un refus métier (solde insuffisant, plafond, case prise) n'est
 *    JAMAIS mis en file : la base a répondu, sa réponse est définitive.
 */
export async function ecrire(nom, params, { cle = null, avecCle = true } = {}) {
  // api_remettre_lot n'attend pas de clé : elle est idempotente par sa
  // clause WHERE (on ne remet que ce qui n'est pas déjà remis).
  const p = { ...params, p_jeton: jeton() };
  if (avecCle) p.p_cle = cle || nouvelleCle();
  const op = { id: alea(), nom, params: p, depose: Date.now(), essais: 0 };
  try {
    const res = await appel(op.nom, op.params);
    return { ...res, enAttente: false };
  } catch (e) {
    if (e instanceof ErreurReseau) {
      const f = fileLire();
      f.push(op);
      fileEcrire(f);
      return { enAttente: true, cle: op.params.p_cle || null };
    }
    throw e;                               // refus métier : on remonte tel quel
  }
}

let videEnCours = false;
let minuteurFile = null;

/** Tente d'envoyer les opérations en attente, dans l'ordre de dépôt. */
export async function viderFile() {
  if (videEnCours) return;
  videEnCours = true;
  try {
    let f = fileLire();
    while (f.length) {
      const op = f[0];
      try {
        await appel(op.nom, op.params);
        f = fileLire(); f.shift(); fileEcrire(f);       // envoyée : on la retire
      } catch (e) {
        if (e instanceof ErreurReseau) break;           // toujours coupé : on garde la file
        // Refus métier au rattrapage : l'opération ne passera jamais.
        // On la sort de la file pour ne pas bloquer les suivantes, et on
        // la conserve dans un journal local consultable par Bony.
        f = fileLire();
        const morte = f.shift();
        fileEcrire(f);
        const rejets = JSON.parse(localStorage.getItem('gbp.rejets') || '[]');
        rejets.push({ ...morte, refus: e.code, detail: e.detail, quand: Date.now() });
        localStorage.setItem('gbp.rejets', JSON.stringify(rejets.slice(-50)));
      }
      f = fileLire();
    }
  } finally {
    videEnCours = false;
  }
}

export function rejets() {
  try { return JSON.parse(localStorage.getItem('gbp.rejets') || '[]'); }
  catch { return []; }
}

// Relances : retour du réseau, retour au premier plan, et battement lent.
export function demarrerFile() {
  addEventListener('online', viderFile);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) viderFile();
  });
  if (minuteurFile) clearInterval(minuteurFile);
  minuteurFile = setInterval(() => { if (fileTaille()) viderFile(); }, 15000);
  viderFile();
}

// ---------------------------------------------------------------------
//  Écritures métier
// ---------------------------------------------------------------------
export const ecrit = {
  participation: (garage, animation, cle) =>
    ecrire('api_participation', { p_garage: garage, p_animation: animation }, { cle }),
  resultat: (garage, bareme, cle) =>
    ecrire('api_resultat', { p_garage: garage, p_bareme: bareme }, { cle }),
  // p_palier porte le libellé du barème (« 200 à 699 € », « Contact »…).
  // La base le revérifie contre le barème de la catégorie avant de
  // l'inscrire au journal : un libellé inventé est ignoré, pas recopié.
  achat: (garage, points, palier, cle) =>
    ecrire('api_points_achat', { p_garage: garage, p_points: points, p_palier: palier }, { cle }),
  jouerCase: (numero, cle) =>
    ecrire('api_jouer_case', { p_numero: numero }, { cle }),
  corriger: (garage, delta, motif, cle) =>
    ecrire('api_corriger', { p_garage: garage, p_delta: delta, p_motif: motif }, { cle }),
  remettreLot: (numero) =>
    ecrire('api_remettre_lot', { p_numero: numero }, { avecCle: false }),

  // Le grand tirage : opérations d'estrade, jamais mises en file d'attente.
  // Sur scène, une opération qui « partira plus tard » n'a aucun sens : on
  // veut savoir tout de suite si elle a abouti.
  //
  // tirageLancer est le SEUL appel du spectacle. Il bascule la soirée et
  // rend les 15 tickets d'un coup ; les 60 secondes d'animation se
  // déroulent ensuite dans le navigateur, sans retoucher la base. C'est
  // volontaire : au moment où l'écran géant s'allume, 200 téléphones
  // sondent leur solde, ce n'est pas l'instant pour ajouter quinze
  // allers-retours par écran.
  reveler:      (numero = null) => appel('api_reveler', { p_jeton: jeton(), p_numero: numero }),
  tirageLancer: () => appel('api_tirage_lancer', { p_jeton: jeton() }),
  tirageReset:  () => appel('api_tirage_reset', { p_jeton: jeton() }),
};
