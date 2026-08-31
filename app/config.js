// =====================================================================
//  Configuration publique de l'application.
//  La clé ci-dessous est la clé PUBLISHABLE : elle est publique par
//  nature, c'est son rôle d'être embarquée dans le navigateur. Elle ne
//  donne accès à AUCUNE table en direct — uniquement aux fonctions
//  api_* vérifiées côté base.
//  La clé secrète ne doit JAMAIS apparaître dans ce dossier.
// =====================================================================
export const CONFIG = {
  url: 'https://zjomxuolpmgwkdxyxasz.supabase.co',
  cle: 'sb_publishable_-_MG2sqrAvtSihZbiFeU-w_phY5jgnF',

  // Rythme de rafraîchissement du solde participant, en millisecondes.
  // 30 s : mesuré à 13 req/s pour 400 participants, très loin des limites.
  sondageMs: 30000,
  // Le tableau de bord Bony se rafraîchit plus vite (1 à 2 appareils).
  sondageAdminMs: 10000,

  evenement: {
    nom: 'Le Grand Bal des Fournisseurs',
    date: 'Jeudi 17 septembre 2026',
    lieu: "Grande Halle d'Auvergne",
  },
};
