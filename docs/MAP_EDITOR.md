# Éditeur de cartes OpenQuest

> Complète [INTERACTIVE_MAPS.md](./INTERACTIVE_MAPS.md) (moteur de rendu) et
> [INTERACTIVE_MAPS_STRATEGY.md](./INTERACTIVE_MAPS_STRATEGY.md) (feuille de route).
>
> L'architecture reprend celle de l'éditeur **Meownopoly** de PattouneCorp
> (document + deltas + machine à états d'outils + panneaux), transposée de
> QML/C++ vers GDScript et adaptée au JDR : tokens, brouillard de guerre,
> murs, lumières, zones d'effet et notes MJ à la place des cases de plateau.

---

## 1. Ouvrir l'éditeur

Hub → une carte → **✏️ Modifier**. Les cartes en mode **Complexe** ouvrent
l'éditeur de battlemap 3D décrit ici ; les cartes en mode **Simple** gardent
l'éditeur de tuiles historique.

L'interface est en trois colonnes :

```
┌──────────────┬──────────────────────────────────┬─────────────────┐
│ Outils       │ Barre d'action (undo/zoom/menu)  │ Inspecteur      │
│ Options      │                                  │ Calques         │
│ Aimantation  │        Vue 3D + overlay 2D       │ Carte           │
│ Mini-carte   │                                  │ Biblio          │
│              │ Barre de statut                  │ Historique      │
└──────────────┴──────────────────────────────────┴─────────────────┘
```

---

## 1 bis. Le cas d'usage principal : une carte de village où l'on zoome

L'éditeur sert d'abord à ceci : importer une **carte illustrée** (un village
dessiné à la main ou généré), y poser des **lieux nommés**, puis **entrer dans
un lieu** pour arriver sur sa propre carte détaillée — celle où l'on place
vraiment les personnages.

```
Valbois (image du village)          →   Place du Marché (image détaillée)
├── 🏠 Taverne du Cerf ──────────┐       ├── 🧍 tokens des joueurs
├── 💰 Épicerie                   │       ├── 🧱 murs, 💡 lumières
├── ⭐ Place du Marché ───────────┘       └── ⭕ zones, 🔥 effets
└── ➡  Chemin de la Capitale
```

**La recette, de bout en bout :**

1. Créez une carte en mode Complexe, **Carte → Fond → Importer PNG…** et
   choisissez l'illustration du village. La grille s'ajuste à l'image.
2. Outil **🏠 Lieu** (`A`). Saisissez le nom (« Taverne du Cerf »), choisissez
   la catégorie, puis **glissez** sur l'illustration pour délimiter le bâtiment.
   Un cartouche de nom apparaît, relié au lieu par un trait.
3. Dans l'inspecteur du lieu : **🗺 Créer la carte de ce lieu**. Une carte
   enfant est créée, nommée d'après le lieu et reliée dans les deux sens.
4. **↳ Ouvrir cette carte** : l'éditeur bascule dessus. Importez-y
   l'illustration détaillée, posez murs, lumières et tokens.
5. Le **fil d'Ariane** en haut (`Valbois › Place du Marché`) ramène d'un clic à
   l'échelle supérieure.

La profondeur n'est pas limitée : village → place du marché → intérieur de la
taverne. En session, cliquer un lieu descend d'un cran, et un bouton retour
remonte.

Un lieu qui possède une carte est souligné en doré et marqué d'une loupe ;
un lieu purement décoratif (une simple étiquette « Moulin ») reste en bleu.

## 1 ter. Décors : composer la carte par-dessus le fond

Une carte de jeu, ce n'est pas qu'une image de fond : c'est un fond **plus** des
bâtiments, des charrettes, du mobilier, des objets — puis les personnages qu'on
déplace dessus. L'outil **🏚 Décor** (`P`) sert à cette couche intermédiaire.

**Bibliothèque** (onglet Biblio, en tête) — sept catégories : Bâtiments,
Véhicules, Mobilier, Végétation, Objets, Personnages, Sols & chemins.
**＋ Importer des images…** accepte une sélection multiple de PNG détourés
(fond transparent). Les fichiers déposés à la main dans
`user://map_assets/props/<catégorie>/` sont adoptés automatiquement au
rafraîchissement — pas besoin de passer par le bouton.

**Poser** — cliquez une vignette pour armer l'outil, puis cliquez la carte.
L'aperçu sous le curseur montre **la vraie image**, à la bonne taille : on voit
où tombe la maison avant de valider. Les proportions de la source sont
respectées, donc une charrette large reste large.

**Dressé ou couché** — deux façons de poser une image :

| Pose | Pour quoi | Rendu |
|------|-----------|-------|
| **Dressé** (défaut) | Maisons, arbres, charrettes, personnages | L'image se tient debout, pied posé sur la case, et fait face à la caméra |
| **Couché** | Chemins, tapis, ombres, flaques | L'image épouse le sol |

Un décor est **non éclairé** par défaut : une illustration porte déjà ses
propres ombres, et un éclairage 3D par-dessus la salirait. Cochez « Éclairé »
seulement si vous voulez que les torches et le soleil l'affectent.

Les décors se sélectionnent, se déplacent, se dupliquent, se groupent et
s'annulent comme tout le reste. Ils vivent sur le calque **Décor**, entre le
fond et les structures — masquez ce calque pour retrouver le fond nu.

**Et les personnages ?** Ce sont des **tokens** (`1`), pas des décors : eux
seuls se déplacent à la souris pendant la partie, portent un portrait, un rayon
de vision et une fiche. Un décor est du mobilier de scène, un token est un
acteur.

## 2. Outils

Chaque outil est un mode de la machine à états : il décide de ce que font le
clic, le glisser et le relâchement (équivalent des `MouseLogic_*` de Meownopoly).

| Groupe | Outil | Touche | Comportement |
|--------|-------|--------|--------------|
| Navigation | 👆 Sélection | `V` | Clic : sélectionner · glisser dans le vide : rectangle de sélection · glisser un élément : déplacer |
| Navigation | ✋ Navigation | `H` | Clic-glisser : déplacer la vue (aussi : clic milieu, ou `Espace` maintenu) |
| Placer | 🧍 Token | `1` | Pose un token joueur/PNJ (taille et couleur réglables) |
| Placer | 📍 Marqueur | `2` | Pose un marqueur narratif (PNJ, indice, danger, ville…) |
| Placer | 🔥 Effet | `3` | Pose un effet de particules (feu, fumée, magie, pluie) |
| Placer | ⭕ Zone ronde | `4` | Pose une zone circulaire (sort, piège, aura) |
| Placer | ▭ Zone rect. | `5` | Trace une zone rectangulaire au glisser |
| Placer | ⬡ Zone libre | `6` | Clics successifs = sommets · `Entrée` ou clic droit ferme le polygone |
| Placer | 🟫 Plateforme | `7` | Trace une plateforme surélevée (étage, pont, estrade) |
| Placer | 🧱 Mur | `8` | Trace un mur 3D qui projette de vraies ombres (`Maj` : contraint à l'axe) |
| Placer | 🏚 Décor | `P` | Pose l'image sélectionnée dans la bibliothèque (bâtiment, charrette, mobilier…) |
| Placer | 🏠 Lieu | `A` | Délimite un lieu nommé, avec cartouche et carte enfant optionnelle |
| Placer | 📝 Note MJ | `9` | Épingle une note visible du MJ uniquement |
| Placer | 💡 Lumière | `0` | Pose une source lumineuse (torche, brasier) avec vacillement |
| Terrain | 🖌 Terrain | `B` | Peint les tuiles de sol (taille de pinceau réglable) |
| Terrain | 🪣 Remplir | `G` | Remplit la zone contiguë de même tuile |
| Brouillard | 🌫 Révéler | `R` | Révèle le brouillard autour du curseur |
| Brouillard | 🚫 Masquer | `T` | Remasque des cases déjà révélées |
| Outils | 🔗 Lier | `L` | Clic source puis clic cible : crée un lien orienté |
| Outils | 📏 Mesurer | `M` | Mesure une distance en cases et en mètres |
| Outils | 🧩 Template | `K` | Pose le template sélectionné (`R` pour le pivoter) |
| Outils | 🧹 Gomme | `E` | Supprime l'élément sous le curseur |

### Aimantation

Quatre modes : **Libre**, **¼ case**, **½ case**, **1 case** (défaut). Le mode
choisi s'applique au placement, au déplacement et au tracé.

---

## 3. Sélection et manipulation

- **Clic** : sélectionne l'élément le plus haut sous le curseur.
- **Glisser dans le vide** : rectangle de sélection, mis à jour en temps réel
  (test d'intersection AABB sur les empreintes projetées à l'écran — donc
  correct aussi en vue isométrique).
- **Ctrl+clic** : ajoute/retire de la sélection · **Maj+clic** : ajoute.
- **Alt+glisser** : duplique en glissant.
- Sélectionner un membre d'un **groupe** sélectionne tout le groupe.
- **Flèches** : décale la sélection d'un pas d'aimantation (`Maj` : 1 case).
- Les éléments **verrouillés** et les calques verrouillés ne sont pas sélectionnables.

### Alignement

La barre d'action propose aligner à gauche/droite, centrer verticalement et
distribuer horizontalement ; le document expose aussi `top`, `bottom`,
`center_h` et la distribution verticale.

---

## 4. Historique undo/redo

L'historique fonctionne **par deltas**, pas par instantanés complets — chaque
action enregistre un `{ before, after }` minimal.

```gdscript
{ "type": "elem_mod", "id": "tok-…", "before": {…}, "after": {…}, "note": "Déplacement" }
```

Types de delta : `elem_add`, `elem_del`, `elem_mod`, `meta` (réglages de carte),
`tiles` (peinture, stockée en cellules éparses), `fog`, `order`.

**Transactions** — `begin_transaction()` / `commit_transaction()` regroupent
plusieurs deltas en **une seule étape** d'annulation. Utilisé par le déplacement
multiple, le collage, la pose d'un template et les modifications de lot.

**Copie de référence (shadow copy)** — chaque élément conserve son dernier état
validé. Pendant un glisser, la position est modifiée « à vif » sans écrire dans
l'historique ; au relâchement, `commit_live_edit()` compare avec la copie de
référence et n'écrit un delta que s'il y a un vrai changement. `Échap` en cours
de glisser appelle `revert_live_edit()` et restaure la copie.

L'onglet **Historique** liste les étapes ; l'historique est plafonné à 120 étapes.

---

## 5. Liens entre éléments

Les liens sont **bidirectionnels et automatiques** : `link_elements(a, b)`
ajoute `b` dans `a.links.next` **et** `a` dans `b.links.prev`. Ils sont dessinés
comme des flèches sur l'overlay.

Usages JDR : chemin de patrouille d'un garde, chaîne d'indices dans une enquête,
porte reliée à sa contrepartie, ordre de déclenchement d'un piège.

Supprimer un élément nettoie automatiquement les références de ses voisins.

---

## 6. Calques

Six calques par défaut : Terrain, Décor, Structures, Zones & effets, Tokens,
Notes MJ. Chacun peut être **renommé**, **masqué** ou **verrouillé** depuis
l'onglet Calques, qui sert aussi d'arborescence :

- recherche plein texte (nom, type, notes) ;
- visibilité et verrou par élément ;
- clic pour sélectionner, `Ctrl+clic` pour ajouter, double-clic pour recadrer ;
- suppression directe.

L'ordre d'empilement se règle avec **Page ↑ / Page ↓** ou les boutons
premier plan / arrière-plan.

---

## 6 bis. Ligne de vue, portes et brouillard dynamique

Activez **Carte → Brouillard → Ligne de vue**. Le brouillard cesse alors d'être
peint à la main : il découle de ce que voient les tokens du groupe.

- **Murs** : un mur avec « Bloque la vue » arrête la lumière et le regard.
- **Portes** : cochez « Porte » sur un mur. Une porte fermée bloque, une porte
  ouverte laisse passer. En session, l'ouverture est un **fait de partie**
  (`doorStates` dans l'état de jeu) — la carte elle-même n'est jamais modifiée,
  donc rejouer le scénario repart de portes fermées.
- **Vision par token** : chaque token porte un rayon (`visionRadius`, 8 cases
  par défaut) et un drapeau `providesVision`. Par défaut **seuls les tokens
  rattachés à un membre du groupe éclairent** : un gobelin embusqué ne révèle
  pas sa propre cachette aux joueurs.
- **Lumières** : une lumière avec `revealsFog` participe au champ de vision.
- **Aperçu** : Carte → Affichage éditeur → **Aperçu ligne de vue** éclaire les
  cases atteintes depuis l'élément sélectionné. Ce qui reste sombre est dans
  l'ombre d'un mur. Les portes sont dessinées en vert (ouvertes) ou orange.

Deux notions de brouillard cohabitent :

| Champ | Sens |
|-------|------|
| `fogRevealed` | **Mémoire** de la partie : une case vue une fois le reste |
| `visibleNow` | Ce qui est éclairé à l'instant t, recalculé à chaque déplacement |

## 6 ter. Avatars de token

Inspecteur d'un token → **Importer une image…** (PNG, JPEG, WebP). L'image est
copiée dans `user://map_assets/tokens/`, découpée en disque et cerclée de la
couleur du personnage. Les portraits déjà importés sont proposés dans une liste
pour être réutilisés d'un token à l'autre. Sans image, le disque coloré
historique est conservé.

## 7. Templates

Un template est un groupe d'éléments enregistré avec ses **positions relatives**,
replaçable en un clic.

1. Sélectionnez des éléments → **Biblio → ＋ Depuis la sélection** → nommez-le.
2. Le template apparaît dans la liste ; cliquez-le pour armer l'outil Template.
3. `⟳` (ou `R`) le fait pivoter par quarts de tour avant la pose.
4. Cliquez la carte : les éléments sont posés avec de **nouveaux identifiants**
   (les liens internes au lot sont remappés), en une seule étape d'annulation.

Stockage : `user://map_templates/<nom_normalisé>_template.json`

```json
{
  "templateInfo": { "name": "Salle de garde", "elementCount": 6,
                    "boundingBoxWidth": 8, "boundingBoxHeight": 5,
                    "creationDate": "2026-09-03T10:00:00" },
  "elements": [ { "kind": "token", "relativePositionX": 0, "relativePositionY": 0, … } ]
}
```

---

## 8. Réglages de carte

Onglet **Carte** :

- **Fond** : import PNG/JPEG/WebP (les dimensions de grille sont déduites de
  l'image), ajout de calques d'élévation, retrait du fond.
- **Dimensions** : redimensionnement non destructif — le terrain existant est
  conservé au coin haut-gauche.
- **Grille** : affichage, taille en pixels, opacité, couleur.
- **Échelle** : distance réelle par case (défaut 1,5 m ≈ 5 pieds), unité libre —
  utilisée par l'outil de mesure.
- **Brouillard** : activation, tout masquer, tout révéler.
- **Perspective** : vue de dessus, isométrique, perspective inclinée.
- **Atmosphère** : teinte d'ambiance, opacité, vignettage.
- **Éclairage global** : lumière directionnelle, direction, intensité.
- **Affichage éditeur** : afficher les liens, afficher les noms.
- **Sauvegarde** : politique **Manuelle**, **À chaque modification** ou
  **Périodique (30 s)**.
- **Import / Export JSON** de la carte complète.

---

## 9. Raccourcis clavier

| Touches | Action |
|---------|--------|
| `Ctrl+Z` | Annuler |
| `Ctrl+Y` / `Ctrl+Maj+Z` | Rétablir |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copier / Couper / Coller (au curseur) |
| `Ctrl+D` | Dupliquer la sélection |
| `Ctrl+A` / `Ctrl+I` | Tout sélectionner / Inverser |
| `Ctrl+G` / `Ctrl+Maj+G` | Grouper / Dégrouper |
| `Ctrl+S` | Enregistrer |
| `Suppr` / `Retour arrière` | Supprimer la sélection |
| `Échap` | Annuler l'action en cours, sinon ouvrir le menu éditeur |
| `Entrée` | Fermer le polygone en cours |
| Flèches | Décaler la sélection (`Maj` : 1 case) |
| `Page ↑` / `Page ↓` | Avancer / reculer d'un rang |
| `F` | Recadrer sur la sélection |
| Molette | Zoom · clic milieu : déplacer la vue |
| `Espace` maintenu | Navigation temporaire |
| `V H 1..0 B G R T L M K E` | Sélection directe d'un outil |

---

## 10. Architecture

```
scripts/maps/
├── map_complex_editor.gd            # Hôte : outils, panneaux, machine à états
├── complex_map_engine_3d.gd         # Rendu 3D + projection + entrée souris
├── map_vision.gd                    # Ligne de vue, champ de vision, portes
├── map_asset_library.gd             # Bibliothèque de décors (import, index, vignettes)
├── map_layers/
│   ├── map_props_3d.gd              # Décors images (dressés ou couchés au sol)
│   ├── map_walls_3d.gd              # Murs volumétriques (ombres réelles)
│   ├── map_lights_3d.gd             # Sources lumineuses + vacillement
│   └── … (sol, grille, tokens, effets, zones, brouillard, élévations)
└── editor/
    ├── map_edit_document.gd         # ⭐ Modèle + historique deltas + sélection
    ├── map_editor_tools.gd          # Catalogue d'outils, aimantation, raccourcis
    ├── map_editor_overlay.gd        # Overlay 2D : sélection, liens, aperçus, règle
    ├── map_editor_minimap.gd        # Mini-carte cliquable
    ├── map_editor_inspector.gd      # Inspecteur + effets visuels
    ├── map_editor_outliner.gd       # Arborescence / calques
    └── map_editor_templates.gd      # Lecture/écriture des templates
```

### Séparation des responsabilités

Le moteur 3D **ne décide de rien** en mode éditeur : il traduit l'entrée souris
en coordonnées grille et émet `editor_pointer_pressed/moved/released`. L'éditeur
applique l'outil courant et écrit dans le document ; le document notifie
(`changed`, `selection_changed`, `history_changed`, `dirty_changed`) ; les
panneaux et l'overlay se rafraîchissent.

### Projection

L'overlay dessine en 2D par-dessus le viewport 3D via
`engine.grid_to_screen(gx, gy, hauteur)` (qui s'appuie sur
`Camera3D.unproject_position`). C'est ce qui permet au rectangle de sélection,
aux contours et aux flèches de liens de rester justes quelle que soit la
perspective.

### Modèle unifié

Tous les éléments partagent la même forme, quel que soit leur type :

```gdscript
{
  "id": "tok-…", "kind": "token",           # token|marker|effect|zone|platform
  "x": 3.0, "y": 4.0, "w": 1.0, "h": 1.0,   # overlay|wall|note|light|link|area|prop
  "label": "Garde", "layer": 4, "zOrder": 0.004,
  "locked": false, "hidden": false, "group": "", "notes": "",
  "display": { "rotation": 0.0, "mirrorH": false, "mirrorV": false,
               "scale": 1.0, "opacity": 1.0, "tint": "",
               "colorize": 0.0, "brightness": 0.0,
               "contrast": 0.0, "saturation": 0.0 },
  "links": { "next": [], "prev": [] }
}
```

À la sauvegarde, `to_map_data()` répartit ce modèle plat dans le format de
fichier historique — `playDefaults.tokens/effects/zones`, `elevationLayers`,
`walls`, `notes`, `lighting.sources`, `locationLinks`, `areas` — pour que les
cartes existantes et le mode session continuent de fonctionner sans migration.

Un **décor** (`kind: "prop"`) porte en plus :

```gdscript
{
  "asset": "user://map_assets/props/buildings/taverne-….png",
  "standing": true,        # dressé face caméra, ou couché au sol
  "billboard": true,       # suit la caméra quand il est dressé
  "lit": false,            # soumis aux lumières de la scène
  "elevation": 0.0
}
```

Un **lieu** (`kind: "area"`) porte en plus :

```gdscript
{
  "shape": "rect",                  # rect | circle | polygon
  "category": "shop",               # building | shop | poi | exit | nature
  "icon": "",                       # surcharge l'icône de la catégorie
  "label": "Taverne du Cerf",
  "targetMapId": "map-…",           # carte enfant, vide si simple étiquette
  "showCallout": true,
  "labelOffset": { "x": 0.0, "y": -2.8 }
}
```

### Schéma de carte (version 3)

Ajouts en version 3 : `walls`, `notes`, `layers`, `measure`. En version 4 :
`areas` (les lieux), `props` (les décors) et `parentMapId` (la carte dont
celle-ci est le zoom).
`MapData.ensure_map_schema()` les crée à la volée sur les cartes anciennes.

---

## 11. Synchronisation en session

Les modifications de carte ne passent plus par une rediffusion complète de la
partie. Chaque geste devient une **opération** de quelques dizaines d'octets :

```gdscript
{ "type": "move_token", "tokenId": "tok-…", "x": 7.0, "y": 3.0 }
```

Types : `move_token`, `place`, `erase`, `fog_reveal`, `fog_hide`, `door`,
`effect_trigger`, `select`.

**Autorité MJ** — `GameData.submit_map_op()` est le point d'entrée unique. Côté
joueur, l'opération part au MJ (`request_map_op`), qui la valide
(`can_apply_map_op`), l'applique et la rediffuse (`sync_map_op`). Hors P2P
(solo, MJ IA) tout est autorisé. Un joueur ne peut que déplacer **son propre**
token, ouvrir une porte et changer sa sélection ; le reste est réservé au MJ.

**Vue filtrée joueur** — `filter_map_entry_for_player()` retire les éléments
marqués `gmOnly` ou masqués, et **omet les tokens tapis dans une case que le
groupe ne voit pas**. Le brouillard cesse d'être un simple calque graphique :
l'information n'est pas envoyée au client.

## 12. Tests

```bash
godot --headless --path game --script scripts/tests/map_editor_test.gd
godot --headless --path game --script scripts/tests/map_vision_test.gd
godot --headless --path game --script scripts/tests/map_areas_test.gd
godot --headless --path game --script scripts/tests/map_props_test.gd
```

`map_editor_test.gd` couvre le document (aller-retour de sérialisation des dix
types d'éléments), l'historique (annulation d'ajout/suppression/modification,
transactions, édition à vif, métadonnées), la sélection et le presse-papiers,
les liens bidirectionnels et leur nettoyage à la suppression, les calques, le
terrain et le brouillard, l'alignement, les templates (enregistrement, rotation,
pose, suppression), puis pilote l'interface réelle : pose de chaque type
d'élément, tracés au glisser, polygone, peinture, mesure, annulation et
persistance dans `MapData`.

`map_vision_test.gd` couvre la ligne de vue (extraction des segments, ombre
portée d'un mur, contournement par l'extrémité, champ de vision à plusieurs
sources), les portes (état de session sans toucher la carte), le brouillard
dynamique et sa mémoire, les opérations de carte et leur autorité, la vue
filtrée pour les joueurs, et les portraits de token.

`map_areas_test.gd` couvre les lieux (modèle, sérialisation, catégories), le
test de survol (un lieu imbriqué l'emporte sur celui qui le contient), la
création de cartes enfants et son idempotence, le fil d'Ariane sur trois
niveaux, la navigation de session en profondeur avec placement de token à
l'échelle atteinte, et le tracé d'un lieu dans l'éditeur réel.

`map_props_test.gd` couvre la bibliothèque (catégories, import, refus des
sources invalides, renommage, suppression), les textures et vignettes avec leur
cache, la pose d'un décor dans le document et son aller-retour de
sérialisation, le rendu 3D (dressé contre couché, éléments masqués ou sans
image ignorés, déplacement sans reconstruction) et l'outil dans l'éditeur réel.

> Note : en mode `--script`, les autoloads ne sont pas des identifiants globaux
> au moment de la compilation. Les scripts qui référencent `MapData` sont donc
> chargés à l'exécution via `load()` dans le test.
