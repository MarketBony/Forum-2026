/* =====================================================================
   badges.js — le générateur de badges du Forum.

   IL NE FAIT QUE LIRE LA BASE. Décision de l'utilisateur, le
   14 septembre : plus aucun import de fichier ici. Le générateur
   affiche la table public.participants, telle que
   scripts\exporter-badges.ps1 l'a déposée dans participants.json, et
   fabrique des PDF. C'est tout.

   POURQUOI. La version précédente croisait deux sources — les 1 407
   invités en base, et les fichiers d'inscription. Le fichier consolidé
   du 14 septembre a montré que ce croisement ne pouvait pas marcher :
   l'identifiant d'invitation n'est pas une clé, BONY00250 a servi à
   trois sociétés successives, et des salariés Bony se sont inscrits
   via le lien d'un client. Le rapprochement se fait maintenant UNE
   fois, à l'écriture, par scripts\importer-inscriptions.ps1 — qui
   signale ce qu'il ne sait pas rattacher au lieu de le deviner.

   La seule chose que ce fichier retient en propre, c'est ce qui a déjà
   été exporté : une information locale sur du papier imprimé, qui n'a
   rien à faire dans la base du Forum.
   ===================================================================== */

'use strict';

/* =====================================================================
   1. CONFIGURATION — c'est ici, et seulement ici, qu'on touche
   ===================================================================== */

/* L'adresse encodée dans le QR. Identique sur tous les badges : le QR
   ouvre l'accueil, on tape ensuite ses quatre caractères. */
const SITE = 'https://forum-2026.bonyauto-mobile.workers.dev/';

const EVENEMENT_1 = 'Le Grand Bal des Fournisseurs';
const EVENEMENT_2 = '17 septembre 2026 · Grande Halle d\'Auvergne';

/* Les six catégories. Les clés sont celles de la contrainte SQL
   participants_categorie_connue : les changer ici sans changer la base
   ferait disparaître des badges sans un mot. */
const CATEGORIES = {
  GARAGE:       { libelle: 'Garage',       couleur: '#C5963C' },
  EXPOSANT:     { libelle: 'Exposant',     couleur: '#D15B30' },
  ANIMATION:    { libelle: 'Animation',    couleur: '#6FBE7E' },
  HOTESSE:      { libelle: 'Hôtesse',      couleur: '#B0286E' },
  EQUIPE_BONY:  { libelle: 'Équipe Bony',  couleur: '#2E1B3E' },
  CONSTRUCTEUR: { libelle: 'Constructeur', couleur: '#7B3FA0' }
};

/* =====================================================================
   2. OUTILS
   ===================================================================== */

const norm = s => (s == null ? '' : String(s))
  .normalize('NFD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/* Tri alphabétique français : « Éts Martin » doit tomber avec les E,
   pas être rejeté après le Z comme le ferait un tri sur les octets. */
const comparer = (a, b) =>
  String(a).localeCompare(String(b), 'fr', { sensitivity: 'base', numeric: true });

const echap = s => (s == null ? '' : String(s))
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/* Blanc ou noir sur le bandeau ? Calculé, pas choisi à l'œil : le vert
   des animations est clair, le violet nuit de l'équipe Bony est sombre,
   et la septième catégorie sera peut-être n'importe quoi. */
function texteSur(hex) {
  const c = n => {
    const v = parseInt(hex.substr(n, 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  };
  const l = 0.2126 * c(1) + 0.7152 * c(3) + 0.0722 * c(5);
  return l > 0.45 ? '#1A0E22' : '#FFFFFF';
}

const $ = id => document.getElementById(id);
const nomDeFichier = s => norm(s).replace(/ /g, '-').replace(/[^a-z0-9-]/g, '');

/* Mélange une couleur avec du blanc (ratio > 0) ou du noir (ratio < 0).
   Sert à fabriquer les deux bouts d'un dégradé à partir de la seule
   couleur déclarée par la catégorie : ajouter une septième catégorie
   reste une ligne, et son dégradé se calcule tout seul. */
function melange(hex, ratio) {
  const v = n => parseInt(hex.substr(n, 2), 16);
  const cible = ratio > 0 ? 255 : 0;
  const t = Math.abs(ratio);
  const c = n => Math.round(v(n) + (cible - v(n)) * t).toString(16).padStart(2, '0');
  return '#' + c(1) + c(3) + c(5);
}

/* =====================================================================
   LA GUINGUETTE — dégradés et guirlandes, en SVG et pas en CSS
   =====================================================================
   POURQUOI SVG. Un `background: linear-gradient(...)` est un fond, et un
   navigateur qui imprime peut décider de ne pas imprimer les fonds : le
   badge sortirait blanc sur blanc sans que rien ne prévienne. Un
   `<rect fill="url(#grad)">` est du CONTENU : il s'imprime toujours,
   comme une lettre. Tout ce qui est coloré sur le badge passe donc par
   là. Ne pas « simplifier » en CSS.

   Les dégradés et les guirlandes sont définis UNE fois dans <defs> et
   repris par <use> : à 434 badges, recopier le tracé à chaque
   exemplaire ferait des mégaoctets de DOM pour un dessin identique. */

/* Une guirlande de fanions : une ficelle qui pend, et huit fanions
   alternant la couleur de la catégorie et l'or. C'est la signature
   guinguette, et elle tient en trois centimètres de haut. */
function guirlande(cat) {
  const P0 = [0, 2], P1 = [100, 15], P2 = [200, 2];
  const point = t => [
    (1 - t) * (1 - t) * P0[0] + 2 * (1 - t) * t * P1[0] + t * t * P2[0],
    (1 - t) * (1 - t) * P0[1] + 2 * (1 - t) * t * P1[1] + t * t * P2[1]
  ];
  let fanions = '';
  for (let i = 0; i < 8; i++) {
    const t = 0.08 + i * 0.12;
    const [x, y] = point(t);
    const rempli = (i % 2 === 0) ? 'url(#grad-' + cat + ')' : 'url(#grad-or)';
    fanions += '<path d="M' + (x - 6.5).toFixed(1) + ' ' + y.toFixed(1) +
               'L' + (x + 6.5).toFixed(1) + ' ' + y.toFixed(1) +
               'L' + x.toFixed(1) + ' ' + (y + 12).toFixed(1) + 'Z" fill="' + rempli + '"/>';
  }
  /* Le rapport du viewBox doit egaler celui de la boite CSS (83 x 11 mm,
     soit 7,5) : avec « meet » et un rapport different, le dessin se
     retrecit au centre au lieu d'occuper la largeur. */
  return '<symbol id="guirlande-' + cat + '" viewBox="0 0 200 27" preserveAspectRatio="xMidYMin meet">' +
    '<path d="M0 2Q100 15 200 2" fill="none" stroke="#C5963C" stroke-width="0.9"/>' +
    fanions + '</symbol>';
}

/* Deux filets et un losange : le petit ornement qui sépare la raison
   sociale du nom, à la place d'un trait nu. */
/* PIÈGE SVG. Les deux traits sont peints en COULEUR PLEINE, pas avec le
   dégradé : un dégradé en unités `objectBoundingBox` — le défaut — n'a
   rien à peindre sur un trait parfaitement horizontal, dont la boîte
   englobante est de hauteur nulle. Les filets étaient tout simplement
   invisibles, pendant que le losange, lui, s'affichait. */
const FILET_ORNE =
  '<symbol id="filet-orne" viewBox="0 0 120 10" preserveAspectRatio="xMidYMid meet">' +
    '<path d="M0 5h50M70 5h50" stroke="#C5963C" stroke-width="1.7" fill="none"/>' +
    '<path d="M60 0 67 5 60 10 53 5Z" fill="url(#grad-or)"/>' +
  '</symbol>';

/* Les dégradés vivent dans <defs>, une fois pour toutes. */
function preparerOrnements() {
  let d = '';
  d += '<linearGradient id="grad-or" x1="0" y1="0" x2="0" y2="1">' +
         '<stop offset="0%" stop-color="#EFD79A"/>' +
         '<stop offset="52%" stop-color="#C5963C"/>' +
         '<stop offset="100%" stop-color="#9A6C26"/></linearGradient>';
  for (const k of Object.keys(CATEGORIES)) {
    const c = CATEGORIES[k].couleur;
    d += '<linearGradient id="grad-' + k + '" x1="0" y1="0" x2="0" y2="1">' +
           '<stop offset="0%" stop-color="' + melange(c, 0.30) + '"/>' +
           '<stop offset="55%" stop-color="' + c + '"/>' +
           '<stop offset="100%" stop-color="' + melange(c, -0.22) + '"/></linearGradient>';
  }
  d += FILET_ORNE;
  for (const k of Object.keys(CATEGORIES)) d += guirlande(k);
  $('defs').querySelector('defs').insertAdjacentHTML('beforeend', d);
}

/* La raison sociale s'écrit en quatre tailles, choisies sur la longueur
   plutôt que mesurées au pixel : mesurer des centaines de badges
   coûterait des secondes de reflow pour un résultat identique. Le mot
   le plus long compte double — « TRANSMISSIONSAUTOMATIQUES » déborde là
   où trois mots courts de même longueur totale tiennent très bien. */
function palier(t) {
  const motLePlusLong = String(t || '').split(/\s+/)
    .reduce((m, w) => Math.max(m, w.length), 0);
  const poids = Math.max(String(t || '').length, motLePlusLong * 2);
  if (poids <= 14) return 't1';
  if (poids <= 24) return 't2';
  if (poids <= 38) return 't3';
  return 't4';
}

/* =====================================================================
   3. LE QR — dessiné une seule fois
   ===================================================================== */

/* Le QR est le MÊME sur tous les badges. On le calcule une fois, on le
   pose dans un <symbol>, et chaque verso n'en porte qu'un <use>. Le
   recopier à chaque exemplaire ferait des mégaoctets de DOM pour un
   dessin strictement identique, et Chrome s'étrangle à l'impression.

   Niveau de correction M et marge de 4 modules : ce sont les valeurs de
   la norme. Réduire la marge fait échouer certains lecteurs de
   téléphone, et ça ne se voit qu'une fois le badge imprimé. */
function construireQR(texte) {
  const q = qrcode(0, 'M');
  q.addData(texte);
  q.make();
  const n = q.getModuleCount();
  const marge = 4;
  let d = '';
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (q.isDark(r, c)) d += 'M' + (c + marge) + ' ' + (r + marge) + 'h1v1h-1z';
    }
  }
  const sym = document.querySelector('#qr');
  sym.setAttribute('viewBox', '0 0 ' + (n + marge * 2) + ' ' + (n + marge * 2));
  sym.innerHTML = '<path d="' + d + '" fill="#000000" shape-rendering="crispEdges"/>';
}

/* =====================================================================
   4. LES DONNÉES
   ===================================================================== */

let BADGES = [];      // un élément = un badge à imprimer
let MARQUES = {};     // id de participant -> date du dernier export
let CAT = 'GARAGE';

/* La table renvoie une ligne par PERSONNE inscrite, avec son nombre de
   badges. On déplie ici : le premier porte son nom, les suivants
   portent la même société et le même code sans nom — on ne connaît pas
   la personne qui l'accompagne, et l'inventer serait pire que blanc. */
function deplier(participants) {
  const out = [];
  for (const p of participants) {
    const n = Math.max(1, Math.min(20, parseInt(p.nb_badges, 10) || 1));
    for (let k = 0; k < n; k++) {
      out.push({
        id: p.id, rang: k, cat: p.categorie,
        raison: p.raison_sociale || '',
        prenom: k === 0 ? (p.prenom || '') : '',
        nom:    k === 0 ? (p.nom || '') : '',
        /* Le nom du PORTEUR, garde meme sur les badges d'accompagnant.
           Il ne s'imprime pas — on ne connait pas la personne qui
           accompagne, et l'inventer serait pire que blanc — il sert
           uniquement a trier. Sans lui, un tri par nom de famille voit
           une chaine vide, et les badges d'accompagnant s'empilent
           tous EN TETE, detaches de leur titulaire : on les retrouve
           au massicot, cinq cartons anonymes avant la lettre A. */
        triNom: p.nom || '',
        triPrenom: p.prenom || '',
        commune: p.commune || '',
        code: (p.code || '').toUpperCase(),
        /* Inscrit a la reunion d'agents du matin. Porte par la personne,
           donc recopie sur CHACUN de ses badges : l'accompagnant d'un
           agent va a la meme reunion que lui, et separer les deux a
           l'impression obligerait a les rechercher un par un. */
        agent: !!p.reunion_agents,
        accompagne: k > 0
      });
    }
  }
  return out;
}

async function charger() {
  let r;
  try {
    r = await fetch('./participants.json', { cache: 'no-store' });
  } catch (e) {
    throw new Error('Cette page doit être ouverte par l\'icône « Badges — Forum 2026 » ' +
      'du Bureau, pas en double-cliquant le fichier.');
  }
  if (r.status === 404) {
    throw new Error('participants.json est absent. Relance l\'icône : le générateur ' +
      'lit la base, et rien d\'autre.');
  }
  if (!r.ok) throw new Error('Lecture de participants.json : HTTP ' + r.status);
  BADGES = deplier(await r.json());

  /* MARQUES doit rester un OBJET. Si le fichier contient un tableau — et
     il a contenu « [] » à un moment — JSON.stringify jette les propriétés
     nommées à l'enregistrement, et tout ce qui a été imprimé est oublié
     sans le moindre message. On se méfie du contenu du fichier. */
  MARQUES = {};
  try {
    const m = await fetch('./marques.json', { cache: 'no-store' });
    if (m.ok) {
      const d = await m.json();
      if (d && typeof d === 'object' && !Array.isArray(d)) MARQUES = d;
    }
  } catch (e) { MARQUES = {}; }
}

/* Ce qui a été imprimé est une information LOCALE sur du papier : elle
   n'a rien à faire dans la base du Forum, et se reconstruit en une
   impression si on la perd. */
/* Écriture IMMÉDIATE, et on l'attend. Une version différée de 250 ms
   perdait tout si la fenêtre se fermait juste après un export — ce qui
   est exactement le moment où l'on ferme la fenêtre. Les marques ne
   changent qu'à l'export : il n'y a rien à amortir. */
async function enregistrerMarques() {
  try {
    const r = await fetch('./marques.json', {
      method: 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(MARQUES)
    });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return true;
  } catch (e) {
    console.warn('marques non enregistrées', e);
    return false;
  }
}

/* =====================================================================
   5. LE BADGE — fabrication du HTML
   ===================================================================== */

function styleCat(cat) {
  const c = CATEGORIES[cat] || CATEGORIES.GARAGE;
  return 'style="--cat:' + c.couleur + ';--cat-txt:' + texteSur(c.couleur) + '"';
}

/* Le bandeau de catégorie : un rectangle SVG en dégradé, et le libellé
   posé PAR-DESSUS en HTML — le texte reste ainsi du vrai texte, net et
   sélectionnable dans le PDF, pendant que la couleur est du contenu
   graphique qui s'imprime toujours. */
function bandeau(cat, libelle) {
  return '<div class="bandeau">' +
    '<svg class="bandeau-fond" viewBox="0 0 200 30" preserveAspectRatio="none">' +
      '<rect x="0" y="0" width="200" height="30" rx="2.5" fill="url(#grad-' + cat + ')"/>' +
    '</svg>' +
    '<b>' + echap(libelle) + '</b></div>';
}

function recto(b, pos) {
  const cat = CATEGORIES[b.cat] ? b.cat : 'GARAGE';
  const c = CATEGORIES[cat];
  const personne = [b.prenom, b.nom].filter(Boolean).join(' ').trim();
  let corps;
  if (b.vierge) {
    corps = '<div class="aecrire"></div><div class="aecrire"></div><div class="aecrire"></div>';
  } else {
    /* La commune a été retirée du badge le 14 septembre : elle
       n'apprenait rien à personne et volait de la place au nom. */
    corps =
      '<div class="raison ' + palier(b.raison) + '">' + echap(b.raison) + '</div>' +
      '<svg class="filet-orne" viewBox="0 0 120 10"><use href="#filet-orne"/></svg>' +
      (personne ? '<div class="personne">' + echap(personne) + '</div>' : '');
  }
  return '<div class="cellule ' + pos + '" ' + styleCat(cat) + '>' +
    '<svg class="guirlande" viewBox="0 0 200 27"><use href="#guirlande-' + cat + '"/></svg>' +
    bandeau(cat, c.libelle) +
    '<div class="corps">' + corps + '</div>' +
    '<div class="pied">' +
      '<svg class="blason" viewBox="0 0 62.09 63.05"><use href="#blason"/></svg>' +
      '<div class="script">' + EVENEMENT_1 + '</div>' +
      '<div class="evenement">' + EVENEMENT_2 + '</div>' +
    '</div></div>';
}

function verso(b, pos) {
  const cat = CATEGORIES[b.cat] ? b.cat : 'GARAGE';
  const c = CATEGORIES[cat];
  const code = (b.code || '').toUpperCase();
  /* L'encadré du code est lui aussi un SVG : un contour en dégradé se
     voit, et surtout s'imprime, là où un `border` en dégradé n'existe
     pas en CSS. */
  return '<div class="cellule ' + pos + '" ' + styleCat(cat) + '>' +
    '<svg class="guirlande" viewBox="0 0 200 27"><use href="#guirlande-' + cat + '"/></svg>' +
    '<div class="corps verso">' +
      '<div class="cat-verso">' + echap(c.libelle) + '</div>' +
      '<svg class="qr" viewBox="0 0 1 1"><use href="#qr"/></svg>' +
      '<div class="consigne">Scanne, puis tape <b>ton code</b>.</div>' +
      '<div class="etiq">Ton code d\'accès</div>' +
      '<div class="boite-code' + (code ? '' : ' sans') + '">' +
        '<svg class="boite-fond" viewBox="0 0 200 60" preserveAspectRatio="none">' +
          '<rect x="2" y="2" width="196" height="56" rx="6" fill="none" ' +
            'stroke="url(#grad-' + cat + ')" stroke-width="3.2"/>' +
        '</svg>' +
        '<div class="valeur">' + (code ? echap(code) : '&nbsp;&nbsp;&nbsp;&nbsp;') + '</div>' +
      '</div>' +
    '</div>' +
    '<div class="pied">' +
      '<div class="script">' + EVENEMENT_1 + '</div>' +
      '<div class="evenement">forum-2026.bonyauto-mobile.workers.dev</div>' +
    '</div></div>';
}

const REPERES =
  '<div class="reperes">' +
    '<div class="coupe"></div><div class="pli"></div>' +
    '<span class="l-coupe">couper</span><span class="l-pli">plier</span>' +
  '</div>';

/* Une feuille = deux badges. Recto à gauche, verso à droite : on coupe
   la feuille en deux dans la largeur, on plie chaque bande sur le trait
   du milieu en rabattant le verso DERRIÈRE le recto.

   Pourquoi ce montage plutôt qu'un recto-verso d'imprimante : replier
   puis retourner la carte autour de l'axe vertical sont deux rotations
   qui s'annulent, le verso se lit donc à l'endroit sans miroir. Et
   l'impression reste en simple face, donc aucun décalage de calage
   duplex — invisible tant qu'on n'a pas imprimé, très visible sur un
   bandeau de couleur. */
function construireFeuilles(lot) {
  let h = '';
  for (let i = 0; i < lot.length; i += 2) {
    h += '<div class="feuille">' +
      recto(lot[i], 'r1c1') + verso(lot[i], 'r1c2') +
      (lot[i + 1]
        ? recto(lot[i + 1], 'r2c1') + verso(lot[i + 1], 'r2c2')
        : '<div class="cellule r2c1"></div><div class="cellule r2c2"></div>') +
      REPERES + '</div>';
  }
  return h;
}

/* =====================================================================
   6. L'EXPORT PDF
   ===================================================================== */

/* Le navigateur est le seul à savoir dessiner un badge ; le serveur est
   le seul à savoir écrire un fichier. On fabrique donc ici une page
   HTML complète et autonome par PDF, le serveur la pose sur le disque
   et la fait imprimer par un Chrome sans fenêtre.

   Le fichier est écrit dans badges\_impression\, d'où le « ../ ». */
function pageAutonome(lot, titre) {
  return '<!doctype html><html lang="fr"><head><meta charset="utf-8">' +
    '<title>' + echap(titre) + '</title>' +
    '<link rel="stylesheet" href="../polices.css">' +
    '<link rel="stylesheet" href="../badges.css">' +
    '</head><body>' +
    '<svg width="0" height="0" style="position:absolute" aria-hidden="true">' +
      $('defs').innerHTML +
    '</svg>' +
    construireFeuilles(lot) +
    '</body></html>';
}

/* DEUX TRIS, ET PAS UN SEUL, PARCE QUE LES DEUX PILES NE SE CHERCHENT
   PAS PAREIL.

   GARAGE — les agents en tete, puis le reste, chaque moitie de A a Z
   sur la raison sociale. La reunion d'agents a lieu le matin, avant le
   Forum : cette pile-la se distribue en premier et doit pouvoir se
   separer d'un geste au massicot plutot que de piocher 51 badges dans
   145. « Agents de A a Z puis reste des garages de A a Z », 16/09.

   Le drapeau vient de la base, pas de la lettre de profil : `profil`
   dit qui a ete INVITE a la reunion, `reunion_agents` dit qui s'y est
   INSCRIT — voir sql/28_reunion_agents.sql, le premier se trompait sur
   20 lignes des 145.

   EQUIPE BONY — nom de famille de A a Z, un seul bloc. « Pour l'export
   il faut que ce soit par ordre alphabetique des NOMS DE FAMILLE »,
   17/09. On NE coupe PAS cette pile en deux : un badge Bony se cherche
   par le nom de la personne, jamais par sa presence a la reunion du
   matin, et scinder la liste obligerait a regarder deux fois. La
   raison sociale ne departage plus rien non plus — elles sont toutes
   identiques depuis sql/29_equipe_bony.sql.

   LES AUTRES — inchangees : exposants, animateurs, hotesses et
   constructeurs n'ont ni nom de personne ni drapeau d'agent utile, le
   tri tombe naturellement sur la raison sociale. */
const TRI_PAR_NOM = ['EQUIPE_BONY'];

function selection() {
  let l = BADGES.filter(b => b.cat === CAT);
  if ($('f-neufs').checked) l = l.filter(b => !MARQUES[b.id]);
  if (TRI_PAR_NOM.includes(CAT)) {
    return l.sort((a, b) =>
      comparer(a.triNom || '', b.triNom || '') ||
      comparer(a.triPrenom || '', b.triPrenom || '') ||
      comparer(a.raison, b.raison) ||
      (a.rang - b.rang));
  }
  return l.sort((a, b) =>
    (b.agent === a.agent ? 0 : a.agent ? -1 : 1) ||
    comparer(a.raison, b.raison) ||
    comparer(a.nom || '', b.nom || '') ||
    comparer(a.prenom || '', b.prenom || '') ||
    (a.rang - b.rang));
}

/* Le decoupage par lettre ne doit pas melanger les deux piles : un PDF
   « agents-M » et un PDF « reste-M » restent deux tas distincts, alors
   qu'un seul « M » contenant les deux obligerait a retrier a la main ce
   que le tri venait de separer.

   POURQUOI « reste- » ET PAS LA LETTRE SEULE. Les deux series doivent
   aussi se ranger dans le bon ordre DANS L'EXPLORATEUR, parce que c'est
   la qu'on les selectionne pour les envoyer a l'imprimante. Avec la
   lettre nue, « badges-garage-a » tombait AVANT « badges-garage-agents-a »
   — le tiret vaut moins que le g — et les deux piles s'entrelacaient.
   Le prefixe met tous les agents devant tout le reste, partout.

   Une categorie sans aucun agent garde la lettre nue : rien ne bouge
   pour les exposants, les animateurs et les hotesses. */
function decouper(sel) {
  if (!$('f-decouper').checked) return [{ cle: '', badges: sel }];
  // Le decoupage suit le critere de tri : decouper l'equipe Bony sur
  // l'initiale de « Bony auto-mobile » ferait un seul fichier « B » de
  // 124 badges, ce qui n'est pas un decoupage.
  const parNom = TRI_PAR_NOM.includes(CAT);
  const melange = !parNom && sel.some(b => b.agent) && sel.some(b => !b.agent);
  const m = new Map();
  for (const b of sel) {
    const l = (norm(parNom ? (b.triNom || b.raison) : b.raison)[0] || '#').toUpperCase();
    const cle = (melange ? (b.agent ? 'agents-' : 'reste-') : '') + l;
    if (!m.has(cle)) m.set(cle, []);
    m.get(cle).push(b);
  }
  return Array.from(m.entries())
    .sort((a, b) =>
      // Les agents passent devant UNIQUEMENT quand les deux piles
      // coexistent. Sans cette garde, l'equipe Bony sortait « f, h, v,
      // z, a, b, c… » : les groupes dont le premier badge portait le
      // drapeau reunion remontaient en tete, et l'alphabet partait en
      // morceaux.
      (melange ? (a[1][0].agent === b[1][0].agent ? 0 : a[1][0].agent ? -1 : 1) : 0) ||
      comparer(a[0], b[0]))
    .map(e => ({ cle: e[0], badges: e[1] }));
}

let exportEnCours = false;

async function exporterPdf() {
  if (exportEnCours) return;
  const sel = selection();
  if (!sel.length) { alert('Il n\'y a aucun badge à exporter dans cette catégorie.'); return; }

  const lots = decouper(sel);
  const jour = new Date().toISOString().slice(0, 10);
  const fichiers = lots.map(l => ({
    nom: 'badges-' + nomDeFichier(CATEGORIES[CAT].libelle) + (l.cle ? '-' + nomDeFichier(l.cle) : '') + '-' + jour,
    html: pageAutonome(l.badges, CATEGORIES[CAT].libelle)
  }));

  exportEnCours = true;
  $('b-pdf').disabled = true;
  const z = $('progression');
  z.hidden = false;
  z.className = 'progression';
  z.innerHTML = '<b>Fabrication des PDF…</b> ' + sel.length + ' badges, ' +
    Math.ceil(sel.length / 2) + ' feuilles, ' + fichiers.length + ' fichier' +
    (fichiers.length > 1 ? 's' : '') + '.';

  try {
    const r = await fetch('./exporter', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fichiers })
    });
    const d = await r.json();
    if (!r.ok || d.erreur) throw new Error(d.erreur || ('HTTP ' + r.status));

    let fini = null;
    for (let i = 0; i < 3000; i++) {
      await new Promise(ok => setTimeout(ok, 600));
      let e;
      try { e = await (await fetch('./export-etat', { cache: 'no-store' })).json(); } catch (x) { continue; }
      z.innerHTML = '<b>Fabrication des PDF…</b> ' + e.fait + ' sur ' + e.total + ' terminé' +
        (e.fait > 1 ? 's' : '') + '.';
      if (e.etat === 'fini') { fini = e; break; }
    }
    if (!fini) throw new Error('L\'export n\'a pas rendu la main. Regarde badges\\_export-etat.json.');

    const rates = fini.fichiers.filter(f => !f.ok);
    if (rates.length) {
      z.className = 'progression rate';
      z.innerHTML = '<b>' + rates.length + ' PDF n\'ont pas pu être fabriqués :</b> ' +
        echap(rates.map(f => f.nom).join(', ')) + '.';
    } else {
      z.className = 'progression fini';
      z.innerHTML = '<b>' + fini.fichiers.length + ' PDF écrit' +
        (fini.fichiers.length > 1 ? 's' : '') + '</b> dans <code>' + echap(fini.dossier) + '</code> — ' +
        fini.fichiers.map(f => echap(f.nom) + '.pdf (' + Math.round(f.octets / 1024) + ' Ko)').join(', ') +
        '. <button class="action creux" id="b-ouvrir">Ouvrir le dossier</button>';
      $('b-ouvrir').onclick = () => fetch('./ouvrir', { method: 'POST' });

      const q = new Date().toISOString();
      for (const b of sel) MARQUES[b.id] = q;
      await enregistrerMarques();
      dessinerListe();
    }
  } catch (e) {
    z.className = 'progression rate';
    z.innerHTML = '<b>L\'export a échoué.</b> ' + echap(e.message);
  } finally {
    exportEnCours = false;
    $('b-pdf').disabled = false;
  }
}

async function exporterLot(fichiers, quoi) {
  const z = $('progression');
  z.hidden = false; z.className = 'progression';
  z.innerHTML = '<b>Fabrication…</b> ' + echap(quoi);
  try {
    const r = await fetch('./exporter', { method: 'POST', headers: { 'Content-Type': 'application/json' },
                                          body: JSON.stringify({ fichiers }) });
    const d = await r.json();
    if (!r.ok || d.erreur) throw new Error(d.erreur || ('HTTP ' + r.status));
    for (let i = 0; i < 600; i++) {
      await new Promise(ok => setTimeout(ok, 600));
      const e = await (await fetch('./export-etat', { cache: 'no-store' })).json();
      if (e.etat === 'fini') {
        z.className = 'progression fini';
        z.innerHTML = '<b>PDF écrit</b> dans <code>' + echap(e.dossier) + '</code>. ' +
          '<button class="action creux" id="b-ouvrir2">Ouvrir le dossier</button>';
        $('b-ouvrir2').onclick = () => fetch('./ouvrir', { method: 'POST' });
        return;
      }
    }
    throw new Error('L\'export n\'a pas rendu la main.');
  } catch (e) {
    z.className = 'progression rate';
    z.innerHTML = '<b>L\'export a échoué.</b> ' + echap(e.message);
  }
}

function badgesVierges() {
  const n = parseInt(prompt('Combien de feuilles de badges vierges ' +
    '(2 badges par feuille, à remplir au marqueur) ?', '10'), 10);
  if (!n || n < 1) return;
  const lot = [];
  for (let i = 0; i < n * 2; i++) lot.push({ id: 'v' + i, rang: 0, cat: CAT, vierge: true, raison: '', code: '' });
  const jour = new Date().toISOString().slice(0, 10);
  exporterLot([{ nom: 'badges-vierges-' + nomDeFichier(CATEGORIES[CAT].libelle) + '-' + jour,
                 html: pageAutonome(lot, 'Badges vierges') }], n + ' feuilles vierges');
}

/* =====================================================================
   7. L'INTERFACE
   ===================================================================== */

function dessinerPastilles() {
  $('pastilles').innerHTML = Object.keys(CATEGORIES).map(k => {
    const c = CATEGORIES[k];
    const n = BADGES.filter(b => b.cat === k).length;
    const actif = k === CAT;
    return '<button class="pastille" data-cat="' + k + '" aria-pressed="' + actif + '" ' +
      'style="color:' + c.couleur + (actif ? ';background:' + c.couleur : '') + '">' +
      echap(c.libelle) + '<span class="n">' + n + '</span></button>';
  }).join('');
  for (const b of $('pastilles').querySelectorAll('button')) {
    b.onclick = () => {
      CAT = b.dataset.cat;
      $('progression').hidden = true;
      dessinerPastilles(); dessinerListe();
    };
  }
}

function dessinerListe() {
  const c = CATEGORIES[CAT];
  const tous = BADGES.filter(b => b.cat === CAT);
  const neufs = tous.filter(b => !MARQUES[b.id]).length;
  const filtre = norm($('f-filtre').value);
  const sel = selection().filter(b => !filtre ||
    norm(b.raison + ' ' + b.prenom + ' ' + b.nom + ' ' + b.commune + ' ' + b.code).includes(filtre));

  $('titre-liste').textContent = c.libelle + ' · ' + tous.length + ' badge' + (tous.length > 1 ? 's' : '') +
    ' · ' + neufs + ' jamais exporté' + (neufs > 1 ? 's' : '');

  const s = selection();
  const lots = decouper(s);
  /* On annonce où s'arrête la pile du matin. Sans ce chiffre, il faut
     compter les badges un par un pour savoir où couper le tas — et 77
     badges se recomptent mal, debout, à l'imprimante. */
  // « en tete » ne veut rien dire quand la pile est triee par nom :
  // l'equipe Bony sort dans l'ordre alphabetique, pas agents devant.
  const nAg = TRI_PAR_NOM.includes(CAT) ? 0 : s.filter(b => b.agent).length;
  $('chiffre-export').textContent = s.length
    ? s.length + ' badges · ' + Math.ceil(s.length / 2) + ' feuilles A4 · ' +
      lots.length + ' fichier' + (lots.length > 1 ? 's' : '') + ' PDF' +
      (nAg ? ' · dont ' + nAg + ' agent' + (nAg > 1 ? 's' : '') + ' en tête, soit les ' +
             Math.ceil(nAg / 2) + ' premières feuilles' : '')
    : 'rien à exporter';

  const MAX = 300;
  let h = '<thead><tr><th>Raison sociale</th><th>Prénom Nom</th><th>Commune</th>' +
          '<th>Code</th><th>Export</th></tr></thead><tbody>';
  if (!sel.length) {
    h += '<tr><td colspan="5" class="vide">Aucun badge dans cette catégorie. ' +
         'La liste vient de la base : si quelqu\'un manque, il faut l\'y pousser.</td></tr>';
  }
  for (const b of sel.slice(0, MAX)) {
    h += '<tr class="' + (b.code ? '' : 'orange') + '">' +
      '<td>' + echap(b.raison) + '</td>' +
      '<td>' + echap([b.prenom, b.nom].filter(Boolean).join(' ')) +
        (b.accompagne ? ' <span class="accomp">accompagnant</span>' : '') +
        (b.agent ? ' <span class="agent">réunion</span>' : '') + '</td>' +
      '<td>' + echap(b.commune) + '</td>' +
      '<td class="code">' + echap(b.code || '—') + '</td>' +
      '<td>' + (MARQUES[b.id]
        ? '<span class="quand">' + new Date(MARQUES[b.id]).toLocaleDateString('fr-FR') + '</span>'
        : '<span class="jamais">jamais</span>') + '</td></tr>';
  }
  if (sel.length > MAX) {
    h += '<tr><td colspan="5" class="vide">… et ' + (sel.length - MAX) +
         ' autres. Le tableau n\'en montre que ' + MAX + ' ; l\'export, lui, les prend tous.</td></tr>';
  }
  $('liste').innerHTML = h + '</tbody>';

  $('apercu').innerHTML = s.length
    ? '<div class="titre-lot">Aperçu de la première feuille</div>' + construireFeuilles(s.slice(0, 2))
    : '';
}

/* =====================================================================
   8. ÉTAT DES DONNÉES ET DÉMARRAGE
   ===================================================================== */

/* Le lanceur tourne sans fenêtre : si la base n'a pas répondu, personne
   ne voit passer l'erreur. On la relit ici et on l'affiche, sinon on
   travaillerait sur des codes périmés en croyant qu'ils sont du jour.
   Les contrôles de l'export (badge sans code, code partagé par deux
   sociétés) remontent par le même chemin. */
async function afficherEtat() {
  let e = null;
  try { const r = await fetch('./_etat.json', { cache: 'no-store' }); if (r.ok) e = await r.json(); }
  catch (x) { return; }
  if (!e) return;
  const z = $('etat');
  const quand = new Date(e.quand);
  const q = isNaN(quand) ? '' : quand.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
  const soucis = (e.soucis || []).concat(e.doublons || []);

  if (e.export === 'echec') {
    z.className = 'etat perime';
    z.innerHTML = '<b>La base n\'a pas répondu au lancement.</b> Les badges affichés sont ceux ' +
      'du dernier export réussi et peuvent être périmés. Relance l\'icône avant d\'exporter.' +
      (e.message ? '<div class="detail">' + echap(e.message) + '</div>' : '');
  } else if (soucis.length) {
    z.className = 'etat perime';
    z.innerHTML = '<b>' + soucis.length + ' badge(s) à regarder avant d\'imprimer :</b>' +
      '<div class="detail">' + soucis.map(echap).join('<br>') + '</div>';
  } else {
    z.className = 'etat frais';
    z.innerHTML = 'Lu dans la base le <b>' + echap(q) + '</b> — tous les badges ont un code utilisable.';
  }
}

function brancher() {
  $('b-pdf').onclick = exporterPdf;
  $('f-neufs').onchange = dessinerListe;
  $('f-decouper').onchange = dessinerListe;
  $('f-filtre').oninput = dessinerListe;
  $('b-vierges').onclick = badgesVierges;
  $('b-relire').onclick = () => location.reload();
}

(async function () {
  construireQR(SITE);
  preparerOrnements();
  brancher();
  afficherEtat();
  try {
    await charger();
  } catch (e) {
    $('etat').className = 'etat perime';
    $('etat').innerHTML = '<b>' + echap(e.message) + '</b>';
  }
  dessinerPastilles();
  dessinerListe();
})();
