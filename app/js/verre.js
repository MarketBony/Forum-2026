// =====================================================================
//  verre.js — le filtre « liquid glass »
//
//  Technique reprise de rdev/liquid-glass-react, elle-même dérivée de
//  shuding/liquid-glass, et adaptée en JavaScript natif sans React.
//
//  Principe : une carte de déplacement est calculée sur un canvas à
//  partir d'une fonction de distance signée de rectangle arrondi. Le
//  déplacement est nul au centre et croît vers les bords. Trois passes
//  feDisplacementMap à des échelles très légèrement différentes — une par
//  canal rouge, vert, bleu — sont recombinées en « screen » : c'est cette
//  divergence qui produit l'aberration chromatique des arêtes, la
//  signature du verre. Un masque radial limite l'effet aux bords, le
//  centre reste net.
//
//  COÛT : cette chaîne est lourde. Elle est donc réservée à UN élément
//  par écran — la carte du solde — et seulement sur les écrans garage.
//  Les écrans du personnel, qui tournent cinq heures, gardent le verre
//  économique : backdrop-filter et reflets spéculaires en CSS pur.
// =====================================================================

const ID = 'verre-liquide';

/* --- la fonction de forme, portée depuis le shader d'origine --------- */
function palier(a, b, t) {
  t = Math.max(0, Math.min(1, (t - a) / (b - a)));
  return t * t * (3 - 2 * t);
}
function longueur(x, y) { return Math.sqrt(x * x + y * y); }

/** Distance signée à un rectangle arrondi centré. */
function distanceRectArrondi(x, y, demiLargeur, demiHauteur, rayon) {
  const qx = Math.abs(x) - demiLargeur + rayon;
  const qy = Math.abs(y) - demiHauteur + rayon;
  return Math.min(Math.max(qx, qy), 0) + longueur(Math.max(qx, 0), Math.max(qy, 0)) - rayon;
}

/**
 * Génère la carte de déplacement en data URL.
 * R = déplacement horizontal, G et B = déplacement vertical, comme
 * attendu par feDisplacementMap avec xChannelSelector="R" et
 * yChannelSelector="B".
 */
export function carteDeplacement(largeur = 128, hauteur = 128) {
  const c = document.createElement('canvas');
  c.width = largeur; c.height = hauteur;
  const ctx = c.getContext('2d');
  if (!ctx) return null;

  const brut = new Float32Array(largeur * hauteur * 2);
  let echelleMax = 0;
  let i = 0;
  for (let y = 0; y < hauteur; y++) {
    for (let x = 0; x < largeur; x++) {
      const ux = x / largeur - 0.5;
      const uy = y / hauteur - 0.5;
      const d = distanceRectArrondi(ux, uy, 0.3, 0.2, 0.6);
      const deplacement = palier(0.8, 0, d - 0.15);
      const facteur = palier(0, 1, deplacement);
      const dx = (ux * facteur + 0.5) * largeur - x;
      const dy = (uy * facteur + 0.5) * hauteur - y;
      brut[i++] = dx; brut[i++] = dy;
      echelleMax = Math.max(echelleMax, Math.abs(dx), Math.abs(dy));
    }
  }
  echelleMax = Math.max(echelleMax, 1);

  const img = ctx.createImageData(largeur, hauteur);
  const px = img.data;
  i = 0;
  for (let y = 0; y < hauteur; y++) {
    for (let x = 0; x < largeur; x++) {
      const dx = brut[i++], dy = brut[i++];
      // adoucissement sur deux pixels au bord, sinon on voit une arête dure
      const bord = Math.min(x, y, largeur - x - 1, hauteur - y - 1);
      const lissage = Math.min(1, bord / 2);
      const r = (dx * lissage) / echelleMax + 0.5;
      const g = (dy * lissage) / echelleMax + 0.5;
      const p = (y * largeur + x) * 4;
      px[p]     = Math.max(0, Math.min(255, r * 255));
      px[p + 1] = Math.max(0, Math.min(255, g * 255));
      px[p + 2] = Math.max(0, Math.min(255, g * 255));
      px[p + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return c.toDataURL();
}

/**
 * Injecte le filtre SVG dans le document. À appeler une fois.
 * @param {number} echelle    intensité de la réfraction (px)
 * @param {number} aberration intensité de l'aberration chromatique (0-2)
 */
export function poserFiltre(echelle = 42, aberration = 1.4) {
  if (document.getElementById(ID)) return true;
  const carte = carteDeplacement();
  if (!carte) return false;

  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('aria-hidden', 'true');
  svg.style.cssText = 'position:absolute;width:0;height:0;overflow:hidden';
  svg.innerHTML = `
    <defs>
      <filter id="${ID}" x="-35%" y="-35%" width="170%" height="170%" color-interpolation-filters="sRGB">
        <feImage x="0" y="0" width="100%" height="100%" result="CARTE"
                 href="${carte}" preserveAspectRatio="xMidYMid slice"/>

        <!-- masque de bord dérivé de la carte elle-même -->
        <feColorMatrix in="CARTE" type="matrix" result="INTENSITE_BORD"
          values="0.3 0.3 0.3 0 0
                  0.3 0.3 0.3 0 0
                  0.3 0.3 0.3 0 0
                  0   0   0   1 0"/>
        <feComponentTransfer in="INTENSITE_BORD" result="MASQUE_BORD">
          <feFuncA type="discrete" tableValues="0 ${(aberration * 0.05).toFixed(3)} 1"/>
        </feComponentTransfer>

        <feOffset in="SourceGraphic" dx="0" dy="0" result="CENTRE"/>

        <!-- trois déplacements, une échelle par canal : l'aberration naît
             de leur très légère divergence -->
        <feDisplacementMap in="SourceGraphic" in2="CARTE" scale="${echelle}"
          xChannelSelector="R" yChannelSelector="B" result="D_R"/>
        <feColorMatrix in="D_R" type="matrix" result="C_R"
          values="1 0 0 0 0
                  0 0 0 0 0
                  0 0 0 0 0
                  0 0 0 1 0"/>

        <feDisplacementMap in="SourceGraphic" in2="CARTE"
          scale="${(echelle * (1 - aberration * 0.05)).toFixed(2)}"
          xChannelSelector="R" yChannelSelector="B" result="D_G"/>
        <feColorMatrix in="D_G" type="matrix" result="C_G"
          values="0 0 0 0 0
                  0 1 0 0 0
                  0 0 0 0 0
                  0 0 0 1 0"/>

        <feDisplacementMap in="SourceGraphic" in2="CARTE"
          scale="${(echelle * (1 - aberration * 0.1)).toFixed(2)}"
          xChannelSelector="R" yChannelSelector="B" result="D_B"/>
        <feColorMatrix in="D_B" type="matrix" result="C_B"
          values="0 0 0 0 0
                  0 0 0 0 0
                  0 0 1 0 0
                  0 0 0 1 0"/>

        <feBlend in="C_G" in2="C_B" mode="screen" result="GB"/>
        <feBlend in="C_R" in2="GB" mode="screen" result="RGB"/>
        <feGaussianBlur in="RGB" stdDeviation="${Math.max(0.1, 0.5 - aberration * 0.1).toFixed(2)}" result="RGB_DOUX"/>

        <!-- l'aberration ne s'applique qu'aux bords, le centre reste net -->
        <feComposite in="RGB_DOUX" in2="MASQUE_BORD" operator="in" result="BORDS"/>
        <feComponentTransfer in="MASQUE_BORD" result="MASQUE_INVERSE">
          <feFuncA type="table" tableValues="1 0"/>
        </feComponentTransfer>
        <feComposite in="CENTRE" in2="MASQUE_INVERSE" operator="in" result="CENTRE_NET"/>
        <feComposite in="BORDS" in2="CENTRE_NET" operator="over"/>
      </filter>
    </defs>`;
  document.body.appendChild(svg);
  return true;
}

/* =====================================================================
   L'APPAREIL TRANCHE LUI-MÊME
   ---------------------------------------------------------------------
   Compter les cœurs ne dit RIEN du coût réel. Un Pixel 10 Pro annonce
   8 cœurs et 12 Go et ramait ; un iPhone SE, plus modeste sur le papier,
   ne bronchait pas — parce que WebKit et Blink ne rastérisent pas cette
   chaîne de filtres de la même façon. Aucun seuil matériel écrit à
   l'avance ne peut départager ces deux-là.
   On mesure donc, sur l'appareil, ce qu'il en coûte VRAIMENT : un étalon
   de frames sans verre, une mesure avec, et il décide. Le verdict est
   retenu pour la session — on ne remesure pas à chaque écran.
   Le seuil est RELATIF à l'étalon, parce qu'un écran 120 Hz vise 8 ms et
   un 60 Hz 16,7 : un seuil en millisecondes absolues punirait le premier
   et laisserait passer le second.
   ===================================================================== */
const CLE_VERDICT = 'gbf-verre-verdict';
const SEUIL_RAPPORT = 1.6;   // 60 % plus lent que sans verre
const SEUIL_PLANCHER = 20;   // …et au-delà de 20 ms/frame, sinon on ne
                             // punit pas un appareil déjà fluide
// Le verdict mémorisé est relu DÈS LE CHARGEMENT DU MODULE, et pas dans
// sonder(). Sinon verreLiquidePossible() répond « oui » au tout premier
// rendu, le verre est posé, et il faut le retirer après coup : l'appareil
// lent paie quand même la première rastérisation, et l'écran cligne.
let verdict = null;          // null = pas encore mesuré
try {
  const memo = localStorage.getItem('gbf-verre-verdict');
  if (memo) verdict = memo === 'ok';
} catch {}

/** Médiane du temps entre frames pendant que `pendant` s'exécute. */
function mesurerFrames(nb, pendant) {
  return new Promise((res) => {
    const t = []; let prec = performance.now();
    function tic(now) {
      t.push(now - prec); prec = now;
      if (pendant) pendant(t.length);
      if (t.length < nb) requestAnimationFrame(tic);
      else { t.sort((a, b) => a - b); res(t[Math.floor(t.length / 2)]); }
    }
    requestAnimationFrame(tic);
  });
}

/**
 * Mesure une fois, puis retire le verre si l'appareil peine. Silencieux :
 * un garagiste n'a pas à savoir pourquoi son téléphone est plus fluide.
 */
export async function sonder() {
  if (verdict !== null) {
    if (!verdict) retirer();     // ceinture : rien ne doit rester posé
    return verdict;
  }

  const vitres = [...document.querySelectorAll('.vitre')];
  if (!vitres.length) return true;                 // rien à mesurer encore

  const bouger = (i) => vitres.forEach((v) => {
    v.style.transform = `translateZ(0) scale(${1 + (i % 2) * 0.0001})`;
  });

  vitres.forEach((v) => { v.dataset.f = v.style.filter; v.style.filter = 'none'; });
  const etalon = await mesurerFrames(24, bouger);
  vitres.forEach((v) => { v.style.filter = v.dataset.f; delete v.dataset.f; });
  const avec = await mesurerFrames(32, bouger);
  vitres.forEach((v) => { v.style.transform = ''; });

  verdict = !(avec > etalon * SEUIL_RAPPORT && avec > SEUIL_PLANCHER);
  try { localStorage.setItem(CLE_VERDICT, verdict ? 'ok' : 'lent'); } catch {}
  if (!verdict) retirer();
  // Laissé lisible depuis la console : c'est la seule façon de savoir sur
  // le téléphone de quelqu'un d'autre pourquoi le verre ne s'affiche pas.
  window.__verre = { etalon: +etalon.toFixed(1), avec: +avec.toFixed(1), garde: verdict };
  return verdict;
}

/** Retire tout le verre déjà posé, et empêche d'en reposer. */
export function retirer() {
  document.querySelectorAll('.vitre').forEach((v) => v.remove());
  document.querySelectorAll('.verre-liquide').forEach((e) => e.classList.remove('verre-liquide'));
}

/** Remet le verre en jeu — dépannage, depuis la console. */
export function reessayer() {
  try { localStorage.removeItem(CLE_VERDICT); } catch {}
  verdict = null;
}

/**
 * Le filtre est-il utilisable ? Firefox ne sait pas composer filter:url()
 * avec backdrop-filter, et on n'impose rien à qui demande moins de
 * mouvement ou à une machine visiblement modeste.
 */
export function verreLiquidePossible() {
  if (verdict === false) return false;
  const ff = /firefox/i.test(navigator.userAgent);
  const peuDeMouvement = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const petiteMachine = (navigator.hardwareConcurrency || 4) <= 2
                     || (navigator.deviceMemory || 4) <= 2;
  const supporte = CSS.supports && CSS.supports('backdrop-filter', 'blur(4px)');
  return !!supporte && !ff && !peuDeMouvement && !petiteMachine;
}

/**
 * Active le verre liquide sur un élément.
 *
 * ATTENTION, PIÈGE : feDisplacementMap déforme le CONTENU de l'élément
 * filtré, pas seulement ce qu'on voit à travers. Appliquer le filtre
 * directement sur un conteneur tord son texte et l'irise sur les bords —
 * spectaculaire, et illisible.
 *
 * On insère donc une vitre : une couche VIDE, en position absolue derrière
 * le contenu, qui porte seule le flou et le filtre de réfraction. Le
 * contenu reste net, au-dessus. C'est l'architecture du composant
 * d'origine, que j'avais court-circuitée.
 */
export function verrer(el) {
  if (!el || !verreLiquidePossible()) return false;
  if (el.querySelector(':scope > .vitre')) return true;
  if (!poserFiltre()) return false;
  const vitre = document.createElement('span');
  vitre.className = 'vitre';
  vitre.setAttribute('aria-hidden', 'true');
  vitre.style.filter = `url(#${ID})`;
  el.insertBefore(vitre, el.firstChild);
  el.classList.add('verre-liquide');
  return true;
}
