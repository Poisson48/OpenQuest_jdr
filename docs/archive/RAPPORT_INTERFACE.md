# Rapport d'interface — Terrain 3D ↔ Blender (sculpt mode, version récente)

## 1. État des lieux de l'interface actuelle

L'éditeur de carte (`map_viewer` → onglet **Cartes → Modifier**) repose sur :

| Zone | Contenu actuel |
|---|---|
| **Barre du haut** | Retour au Hub · titre de carte · Enregistrer · Aperçu ; 2ᵉ ligne : annuler/rétablir, sauvegarder, copier, corbeille, historique, Démarrage, Chemins, flèches de niveaux, zoom %, +, recadrer, palettes, zones ‹ ›, Tester |
| **Barre d'icônes gauche** | Outils globaux (sélection, formes, dessin, **⛰ Relief**, 💧 Eau, décor, murs, toits, personnages, calques…) |
| **Panneau d'options d'outil** (sous la barre gauche) | ⛰ Relief : menu **Mode** (21 brosses) + **Rayon (cases)** + **Force (cases)** (champs SpinBox) + boutons divers selon le mode |
| **Zone de dessin** | carte 3D, curseur-fantôme de brosse (disque de rayon), barre d'état en bas (case survolée, outil actif, rappel des raccourcis) |
| **Panneau droit** | onglets Inspecteur / Calques / Carte / Monde |
| **Raccourcis** | U = relief, Espace/main = pan, molette = zoom vers souris, clic droit = navigation, Ctrl+Z/Y = undo/redo |

Points forts : les 21 brosses sont là, undo par trait, aperçu en direct.
Points faibles comparés à Blender : la sélection de brosse est un **menu
déroulant textuel**, Rayon/Force sont des **champs numériques** (pas de
curseurs ni de valeurs HUD), **pas de symétrie**, pas de raccourcis de
brosse (Shift/Ctrl/[ ]/F), pas de panneau de paramètres (falloff), pas de
barre d'outils de brosses.

## 2. Référence — Blender 4.x, Sculpt Mode

| Élément Blender | Rôle |
|---|---|
| **Header (barre du haut)** | sélecteur d'outil actif (icône + nom), sélecteur de **brosse** (aperçu + nom + liste d'assets), **Radius** (px + curseur), **Strength** (0-100 % + curseur), **symétrie X/Y/Z** (icônes cliquables), remesh, dyntopo |
| **Toolbar gauche** | colonne verticale d'icônes (une par famille d'outil) |
| **Properties > Tool** (panneau N) | *Active Tool* : Brush (Radius, Strength, Blend, Auto-Smooth), **Falloff** (forme + courbe : Smooth, Sphere, Root, Sharp, Linear, Constant…), Texture, Stroke (spacing, dash, jitter), Mask |
| **Canvas** | cercle de brosse (rayon + densité d'aplat), point central ; **Shift** = lisser, **Ctrl** = inverser (ajout ↔ retrait), **F** = rayon radial, **[**/**]** = rayon -, +, Alt+clic = pipette |
| **Pie menu** (clic droit) | accès rapide : rayon, force, lissage, falloff |

## 3. Correspondance retenue (uniquement l'interface du terrain 3D)

| Blender | Notre interface cible |
|---|---|
| Header Sculpt : sélecteur de brosse | **Barre Sculpt** : bouton icône+nom (21 brosses en liste groupée par familles) |
| Radius / Strength curseurs | **Rayon / Force** : sliders horizontaux + valeur éditable (cases) |
| Symmetry X/Y/Z | **Symétrie X/Y/Z** : 3 boutons bascule (tampons miroirs, un seul undo) |
| Toolbar gauche | **Colonne de brosses** verticale (icônes par famille, visible quand ⛰ est actif) |
| Properties > Tool > Falloff | **Paramètres de brosse** : forme de dégradé (Smooth, Sphère, Racine, Net, Linéaire, Constant) + auto-lissage |
| Shift = smooth | **Maj maintenu** = Lisser (quel que soit la brosse) |
| Ctrl = invert | **Ctrl maintenu** = inverser (Creuser ↔ Remblayer, Gonfler ↔ Dégonfler…) |
| [ ] = radius | **[** / **]** = rayon −/+ (pas de 10 %) |
| F = radius radial | **F** = réglage radial du rayon (HUD cercle) |
| Cercle de brosse | déjà présent (fantôme) — enrichi : double cercle rayon/lissage |

Hors périmètre (honnêteté) : remesh/dyntopo (le terrain a sa propre
résolution), textures de brosse, stroke dash/jitter, courbe de falloff
éditable (seules les formes prédéfinies sont prévues).

## 4. Plan d'implémentation

1. **Barre Sculpt** (header contextuel au-dessus de la zone de dessin quand
   l'outil ⛰ est actif) : sélecteur de brosse, Rayon, Force, symétrie.
2. **Symétrie X/Y/Z** dans le dispatch de brosse (tampons miroirs groupés en
   une seule étape d'undo).
3. **Raccourcis** Maj/Ctrl/[ ]/F dans la chaîne de pointeur.
4. **Paramètres de brosse** : forme de dégradé transmise au moteur
   (`sculpt_stamp(..., kernel)` étendu à un paramètre `falloff`).
5. **Colonne de brosses** verticale (icônes par famille).
6. Tests UI + non-régression.

## 5. État d'avancement

**Livré (vérifié par tests) :**
- **Carte plein écran** : la vue 3D occupe ~94 % de la fenêtre
  (`ui_map_full_width`) ; le bandeau gauche est une **colonne d'icônes
  unique** de 56 px (toolbar Blender) — aimantation et mini-carte déplacées
  dans la palette d'options.
- **Palettes flottantes** repliables au-dessus de la carte (docks GIMP) :
  **N** = inspecteur / calques / carte / monde (fermée par défaut),
  **B** = bibliothèque de décors, **S** = options d'outil ; boutons
  ⚙ 🗂 📋 dans la barre d'actions. **Déplaçables à la souris** (glisser la
  barre de titre, bouton ✕ pour replier — vérifié par `palette_moved` /
  `palette_close_hides`).
- **Barre de sculpture façon Blender** : sélecteur de 21 brosses, Rayon/Force
  en curseurs, **symétrie X/Y/Z** (tampons miroirs groupés en un seul undo —
  vérifié bout en bout dans `terrain_sculpt_live_test`).
- **Raccourcis Blender** : Maj = lisser, Ctrl = inverser la brosse,
  **[** / **]** = rayon −/+.
- **Paramètres de brosse** : **Dégradé** (6 courbes de falloff façon Blender :
  Doux, Sphère, Racine, Net, Linéaire, Constant) + **Auto-lissage** intégré au
  tampon dans le même undo.

**Raffinements optionnels (hors liste nominale) :**
- Colonne de brosses verticale à icônes (par famille).
- Touche F (réglage radial du rayon).

**Tests** : `map_editor_test` (contrat palettes + plein écran),
`map_editor_ui_v2_test`, `terrain_sculpt_live_test` (symétrie),
`terrain_sculpt_test` (21 brosses), `scene_load_test` (50 scènes).
**Capture** : `docs/screenshots/ui_palettes.png`.
