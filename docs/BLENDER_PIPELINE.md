# Pipeline Blender — objets 3D de la carte 2.5D

> Dernière mise à jour : 30 octobre 2026 · Blender **4.5.10 LTS** · branche
> `feat/carte-2.5d-editeur`
>
> Compagnon de [CARTE_25D.md](./CARTE_25D.md) et de
> [`game/assets/objects3d/README.md`](../game/assets/objects3d/README.md).

Ce document décrit comment **fabriquer, exporter, vérifier et intégrer** les
objets 3D de la carte 2.5D : un décor peint en perspective, des découpes 2D et
des meshes 3D posés sur une grille, dans l'esprit d'une carte de League of
Legends ou d'un champ de bataille Warhammer.

Objectif de style : des objets **lisibles de dessus** mais **fondus dans
l'illustration Valbois** (peinture détaillée, palette terre/bois/pierre, encre
sombre). Pas de rendu PBR brillant, pas de couleur saturée, pas de découpe nette
avec le sol.

---

## 1. Prérequis

| Élément | Valeur |
|---|---|
| Blender | **4.5.10 LTS**, installé en `C:\Program Files\Blender Foundation\Blender 4.5\blender.exe` |
| PATH | Blender **n'est pas** dans le PATH : toujours utiliser le chemin complet |
| Python | inutile : les scripts tournent dans le Python embarqué de Blender |
| Pillow | uniquement pour la planche de vignettes (`make_contact_sheet.py`) |

Vérifier l'installation :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --version
# Blender 4.5.10 LTS
```

Tous les scripts sont **offline** : aucune texture importée, aucun téléchargement,
aucun asset externe. Les objets sont procéduraux, et les textures de sol sont
générées par du bruit périodique (numpy + Pillow).

Le pipeline couvre désormais le **kit v7** (modules de toiture et de façade), le
**kit v6** (figurines de personnages et créatures), le **kit v5** (relief,
forêt, berges, eau), le **kit v4** (bâtiments variés, détails de toit, figurines
PNJ), le **kit v3** (intérieur de taverne, donjon, petits décors), le **kit
enrichi v2** (murs, mobilier urbain, étal de marché, charrette, foin) et les
**textures de sol tuilables** (herbe, terre/chemin, pavé de pierre).

---

## 2. Arborescence du pipeline

```text
tools/blender/
├── oq_common.py            # helpers partagés (scène, matériaux, primitives,
│                           #   normalisation, vertex colors, contour, export, rendu)
├── build_prototypes.py     # génère les 75 modèles + variantes (GLB + vignettes)
├── export_blend.py         # CLI générique : .blend d'artiste -> GLB + vignette
├── verify_glb.py           # contrôle qualité GLB + vignettes (reimport Blender)
├── make_terrain_textures.py # textures de sol 512² seamless (numpy + Pillow)
├── make_contact_sheet.py   # planche PNG de toutes les vignettes (+ terrains)
└── run_build.ps1           # build complet + vérification + textures + planche

game/assets/objects3d/
├── README.md               # catalogue et mode d'emploi côté moteur
├── manifest.json           # métadonnées générées (nom, dims, tris, tags)
├── _planche_assets.png     # planche de contrôle v1
├── _planche_assets2.png    # planche v2 (historique)
├── _planche_assets3.png    # planche v3 (historique)
├── _planche_assets4.png    # planche v4 (historique)
├── _planche_assets5.png    # planche v5 (historique)
├── _planche_assets6.png    # planche v6 (historique)
├── _planche_assets7.png    # planche courante v7 (sols + 80 objets)
├── buildings/              # maison*, tour*, mur, mur_coin, herse, forge, chapelle,
│                           #   grange, ecurie, maison_etage, manoir, tour_guet_bois,
│                           #   marche_couvert, toit_lucarne, toit_2pentes, toit_croupe,
│                           #   toit_appentis, toit_clocheton, toit_chaume, cheminee_fumante,
│                           #   colombage_panneau, porte_auvent, fenetre_volets, balcon_bois,
│                           #   escalier_exterieur, auvent_etal
├── props/                  # pont, caisse*, palissade, puits, barriere, etal_marche,
│                           #   tonneau, lanterne, banc, panneau, charrette, botte_foin,
│                           #   table_tabourets, comptoir, tonneau_couche, tapis, lit,
│                           #   torche_murale, chaine_murale, sarcophage, pile_os, enseigne,
│                           #   fontaine, puits_couvert, pnj_aventurier, pnj_archere, pnj_mage,
│                           #   pnj_voleuse, pnj_pretresse, pnj_garde, pnj_marchand,
│                           #   pnj_villageois, pnj_gobelin, pnj_squelette
├── vegetation/             # arbre, arbre_automne, buisson, arbre_majestueux,
│                           #   haie, bosquet, roseaux, nenuphars
└── terrain/                # rocher, falaise, gros_rocher

game/assets/terrain/
├── README.md               # usage des textures de sol
├── grass.png               # herbe 512², tuilable
├── dirt.png                # terre / chemin 512², tuilable
├── stone.png               # pavé de pierre 512², tuilable
├── *_thumb.png             # 256² pour la bibliothèque
└── _planche_terrain.png    # contrôle du raccord (tuile 2x2)
```

---

## 3. Conventions 3D (non négociables)

| Convention | Détail |
|---|---|
| **Échelle** | 1 unité Blender = **1 case de carte** |
| **Origine** | **centre de la base**, base posée à `z = 0` (sol) |
| **Objets muraux** | origine au **pied du mur** (`z = 0`, mur en `+Y`) : géométrie suspendue au-dessus du sol (torche, chaîne, enseigne) |
| **Modules de toit** | `anchor="roof"` : origine à la **base du toit** (`z = 0`), centrée, sans dalle ; à empiler sur un bâtiment (`height_above_floor` = hauteur du module) |
| **Élément de toit** | `toit_lucarne` : origine à la **base du toit** (`z = 0`), pas de dalle, à poser au sommet d'un bâtiment |
| **Figurines** | socle rond discret (`anchor="base"`), pas de jupe : utilisables en intérieur comme en extérieur ; tags `class:...` / `creature:...` |
| **Objets d'eau** | `ponton`, `barque`, `nenuphars` : pas de jupe, origine au niveau de l'eau (`z = 0`) |
| **Axes Blender** | `+Z` = haut, face avant de l'objet vers `-Y` |
| **Axes glTF/Godot** | export `export_yup=True` : `+Y` = haut, face avant vers **`+Z`** |
| **Transforms** | rotation/scale à 1, location à 0 : tout est cuit dans le mesh |
| **Budget** | < **5 000 triangles** par asset, **contour encre inclus** |
| **Matériaux** | mats (roughness ≈ 0,92), metallic 0, specular 0,15, **opaques**, faces simples (`doubleSided: false`) |
| **Caméra / lumière** | **jamais exportées** (options `export_cameras=False`, `export_lights=False`, export par sélection) |
| **Vignette** | `<nom>_thumb.png` 512×512 RGBA, cadrage 3/4 commun |

La conversion glTF est automatique : dans Blender, un objet « regarde » vers
`-Y` ; après `export_yup=True`, cette direction devient `+Z` côté glTF/Godot.
Les scripts de contrôle vérifient l'origine au pied et le centrage de la base.
Pour les **objets muraux** (ancre `wall` du manifeste), l'origine est au pied du
mur : le mesh commence au-dessus du sol, `verify_glb.py` le tolère et l'éditeur
doit tourner l'objet pour plaquer son côté `+Y` contre le mur.

Trois ancres existent dans le manifeste : `base` (objet au sol, origine au pied),
`wall` (élément de façade, origine au pied du mur) et `roof` (module de toit,
origine à la base du toit, posé au sommet d'un bâtiment). `verify_glb.py`
contrôle `roof` comme `base` (géométrie au sol de l'asset, bbox centrée).

### Assemblage et normalisation

`oq_common.finalize_asset()` fusionne les primitives en un seul mesh puis
`normalize_asset()` garantit : origine au centre de la base, `z_min = 0`,
`x/y` centrés, rotation/scale neutres, facettes plates (`use_smooth = False`).
Avec `anchor="wall"`, la normalisation ne recentre ni ne plaque au sol : le mesh
doit être construit avec le mur en `y = 0` et le sol en `z = 0`.

### Fermeture des volumes

Tous les matériaux ont `use_backface_culling = True` → glTF `doubleSided:
false`. C'est nécessaire pour le contour encre (coque inversée) et pour des
volumes fermés corrects. Ne pas forcer le double face côté Godot.

---

## 4. Style 2.5D : palette, matières, contour, jupe

### 4.1 Palette échantillonnée sur Valbois

Palette partagée définie dans `oq_common.DEFAULT_PALETTE` (hex sRGB). Rien de
saturé, rien de gris pur :

| Rôle | Hex | Usage |
|---|---|---|
| `plaster` | `#d9c7a6` | enduit crème/beige chaud (murs) |
| `plaster_light` | `#e3d4b8` | rehaut d'enduit |
| `plaster_dark` | `#bfa987` | enduit à l'ombre |
| `wood` | `#6d4b32` | bois brun moyen (colombages, planches) |
| `wood_dark` | `#4a3222` | bois sombre (encadrements, poutres) |
| `wood_light` | `#8a6242` | bois clair (planches de pont) |
| `stone` | `#8c887d` | pierre chaude |
| `stone_dark` | `#6e6a61` | pierre sombre (socle, joints) |
| `stone_light` | `#a29d92` | pierre claire (linteaux, margelle) |
| `roof` | `#9a5a45` | tuile terre cuite désaturée |
| `roof_dark` | `#7a4536` | liteaux / ombre de toit |
| `roof_slate` | `#4c5a66` | ardoise bleu-gris (variante) |
| `roof_slate_dark` | `#3b4650` | ardoise sombre |
| `leaf` | `#5d6b45` | feuillage vert désaturé (olive) |
| `leaf_light` / `leaf_dark` | `#6f7d52` / `#475336` | volumes de feuillage |
| `leaf_autumn*` | `#8a6a44` / `#9a784c` / `#6f5538` | variante automne |
| `water` | `#4a6a70` | eau désaturée |
| `grass` | `#64704a` | jupe herbe |
| `dirt` | `#8a755c` | jupe terre |
| `glow` | `#d9b96a` | fenêtres chaudes (pas de jaune saturé) |
| `ink` | `#241f1a` | **contour encre** |

Règle : une variante ne change qu'une ou deux teintes (toit ardoise vs terre
cuite, feuillage d'automne), jamais la géométrie.

### 4.2 Matières non plates : AO + mottling en vertex colors

Chaque prototype reçoit une couche de couleurs par sommet (`Col`, domaine
POINT, exportée en **`COLOR_0`**) :

* **AO approximatif** : lancer de rayons hémisphériques (BVH, 28 rayons,
  distance 0,32 case) → coins, pieds de murs, dessous de toit plus sombres ;
* **mottling** : bruit sinusoïdal déterministe (± 9 %) pour casser les aplats.

Les valeurs sont **grises multiplicatrices** (`min 0,55`, moyenne ≈ 0,8) :

* le matériau garde sa couleur de palette (`baseColorFactor` glTF) ;
* le moteur multiplie par `COLOR_0` (spec glTF) → volume et variation ;
* si un moteur ignore `COLOR_0`, l'objet garde ses couleurs plates : dégradation
  douce, jamais de casse.

Le pipeline subdivise d'abord les longues arêtes (`subdivide_long_edges`,
max 0,5 case, 2 passes) pour que les vertex colors aient des sommets où
s'exprimer, puis triangule (`triangulate_mesh`) pour un comptage de triangles
identique entre l'export et le reimport.

> Les vignettes Blender montrent l'AO/mottling : après l'export, les matériaux
> sont recâblés (nœud Vertex Color × couleur de base) uniquement pour le rendu.
> Le GLB, lui, garde des matériaux à couleur constante + `COLOR_0`.

### 4.3 Contour encre (« inverted hull »)

Chaque asset exporte **deux meshes** dans le même GLB :

* `<nom>` : mesh principal ;
* `<nom>_outline` : coque dupliquée, sommets décalés le long des normales
  (0,014 case), faces inversées, matériau `ink` presque noir.

Avec `doubleSided: false`, seules les faces arrière de la coque sont visibles :
un trait sombre fin autour de la silhouette, qui rappelle l'encrage de
l'illustration. À l'échelle d'une case, 0,014 ≈ 1–2 px selon le zoom.

**Important** : la coque ne doit pas projeter d'ombre (sinon elle assombrit
l'objet et le sol). Côté Blender, les flags `visible_shadow`/`visible_diffuse`
sont désactivés ; côté Godot, mettre `cast_shadow = SHADOW_CASTING_SETTING_OFF`
sur tout nœud dont le nom finit par `_outline` (voir § 10).

### 4.4 Jupe de raccord au sol

Sous chaque objet, une **dalle elliptique irrégulière très plate** (0,04 case
d'épaisseur, bords ondulés) en herbe (`grass`) ou terre (`dirt`), légèrement
plus large que le bâti. Elle casse la ligne de coupe entre le mesh et
l'illustration peinte et sert de « base large » aux objets. L'ombre de contact
reste gérée par le moteur : **aucune ombre n'est cuite** dans les assets.

Exception assumée : le `pont` n'a pas de jupe (il enjambe l'eau) ; ses culées
en pierre sont élargies.

**Intérieurs (kit v3)** : les meubles de taverne utilisent une **dalle plate en
bois** (`wood_dark`) et ceux du donjon une **dalle en pierre** (`stone_dark`) au
lieu de la jupe d'herbe : même rôle de raccord, mais avec la matière du sol
intérieur. Les objets muraux (torche, chaîne, enseigne) n'ont pas de dalle : ils
se fixent au mur, origine au pied du mur.

### 4.5 Lisibilité de dessus

Formes massives, toits contrastés (terre cuite ou ardoise sur enduit clair),
détails structurants qui restent lisibles à la verticale : arêtes de toit,
bandeaux de pierre, colombages, planches. Pas de feuilles alpha, pas de
transparence (elles se trieraient mal avec les découpes 2D).

### 4.6 Variantes sans réglage

Le MJ ne doit pas avoir à régler des échelles : les variantes de taille/teinte
sont générées et nommées (`maison_petite`, `maison`, `maison_grande`,
`tour_grande`, `caisse_grande`, `arbre_automne`). Une variante coûte une entrée
`Variant` dans `build_prototypes.py` (échelle + overrides de palette).

---

## 5. Échelle de référence (AABB réelles, contour inclus)

| Asset | Largeur × profondeur × hauteur (cases) | Cible |
|---|---|---|
| `maison_petite` | 1.60 × 1.49 × 1.54 | ~1,5 × 1,5 |
| `maison` | 1.95 × 1.81 × 1.88 | ~2 × 2 |
| `maison_grande` | 2.26 × 2.10 × 2.17 | ~2,3 × 2,2 |
| `tour` | 1.47 × 1.33 × 2.37 | ~1,5 de large |
| `tour_grande` | 1.71 × 1.54 × 2.74 | ~1,7 de large |
| `arbre` / `arbre_automne` | 1.03 × 1.05 × 2.10 | ~1 case |
| `puits` | 1.20 × 1.02 × 1.44 | ~1 case |
| `caisse` / `caisse_grande` | 1.07 × 1.05 / 1.34 × 1.32 | ~1 case |
| `palissade` | 2.20 × 0.51 × 1.24 | module 2 cases |
| `pont` | 2.64 × 1.30 × 1.09 | ~2,5 cases de long |
| `rocher` | 1.45 × 1.18 × 0.87 | ~1,4 case |
| `mur` | 2.36 × 0.70 × 1.30 | module 2 cases |
| `mur_coin` | 2.10 × 1.69 × 1.29 | coin en L |
| `barriere` | 2.10 × 0.44 × 0.94 | module 2 cases |
| `etal_marche` | 1.96 × 1.53 × 2.00 | ~2 cases |
| `tonneau` | 0.92 × 0.91 × 0.84 | ~0,8 case |
| `lanterne` | 0.84 × 0.84 × 2.30 | ~2,3 cases de haut |
| `banc` | 1.32 × 0.68 × 0.98 | ~1,1 case |
| `panneau` | 0.87 × 0.78 × 2.01 | ~1,9 case de haut |
| `charrette` | 1.61 × 1.74 × 0.94 | ~1,6 case (brancards inclus) |
| `botte_foin` | 1.10 × 0.85 × 0.67 | ~0,9 case |

Ces dimensions incluent le contour (+0,014 de chaque côté) et la jupe. Le
manifeste et le récapitulatif de `run_build.ps1` les affichent. Les objets
muraux du kit v3 sont listés en §5.2 avec, en plus, leur **hauteur au-dessus du
pied du mur** ; le kit v4 (bâtiments et figurines) est en §5.3.

### 5.1 Kit enrichi v2 (10 objets)

Deuxième passe qualité (objectif Dofus) : un kit de décor urbain et champêtre
pour composer une place de village, un camp ou un chemin, sans réglage.

| Asset | Catégorie | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|---|
| `mur` | buildings | 2.36 × 0.70 × 1.30 | 784 (392+392) | Enceinte, mur de soutènement (module 2 cases) |
| `mur_coin` | buildings | 2.10 × 1.69 × 1.29 | 1 336 (668+668) | Coin d'enceinte en L |
| `barriere` | props | 2.10 × 0.44 × 0.94 | 496 (248+248) | Clôture basse de chemin ou pâture |
| `etal_marche` | props | 1.96 × 1.53 × 2.00 | 1 792 (896+896) | Étal de marché avec auvent à rayures |
| `tonneau` | props | 0.92 × 0.91 × 0.84 | 648 (324+324) | Tonneau cerclé de métal |
| `lanterne` | props | 0.84 × 0.84 × 2.30 | 396 (198+198) | Lanterne sur poteau, fanal émissif |
| `banc` | props | 1.32 × 0.68 × 0.98 | 488 (244+244) | Banc de place / jardin |
| `panneau` | props | 0.87 × 0.78 × 2.01 | 344 (172+172) | Panneau indicateur, deux flèches |
| `charrette` | props | 1.61 × 1.74 × 0.94 | 1 208 (604+604) | Charrette à bras, roues et brancards |
| `botte_foin` | props | 1.10 × 0.85 × 0.67 | 548 (274+274) | Botte de foin liée |

Notes de style :

* murs et mobilier en pierre/bois de la palette Valbois, même pipeline AO +
  mottling + contour encre que le kit v1 ;
* l'**étal de marché** utilise un auvent rayé (deux matériaux mats, aucun
  alpha) et des marchandises colorées très désaturées ;
* la **lanterne** a un matériau `lamp` **émissif** (exporté en `emissiveFactor`
  glTF) : Godot peut l'utiliser en source de lumière douce ;
* les jupes de sol (herbe/terre) restent posées sous chaque objet pour le
  raccord avec le décor peint.

### 5.2 Kit v3 (12 objets) — intérieur taverne, donjon, petits décors

Troisième passe : donner de la vie aux zones **taverne (10×8)** et **donjon
(9×9)**, plus deux décors extérieurs. Les chopes et bouteilles sont intégrées
sur la table et le comptoir (pas de prop séparé).

| Asset | Catégorie | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|---|
| `table_tabourets` | props | 1.74 × 1.76 × 1.29 | 1 400 (700+700) | Table ronde + 3 tabourets, chope et bouteille |
| `comptoir` | props | 2.34 × 1.28 × 1.87 | 2 536 (1 268+1 268) | Comptoir + arrière-bar à bouteilles |
| `tonneau_couche` | props | 1.18 × 0.98 × 0.75 | 784 (392+392) | Tonneau couché sur cales, robinet |
| `tapis` | props | 2.02 × 1.26 × 0.08 | 1 352 (676+676) | Tapis à motif losange, plaque plate opaque |
| `lit` | props | 1.48 × 2.04 × 0.78 | 888 (444+444) | Lit de taverne (bois, matelas, couverture) |
| `torche_murale` | props | 0.22 × 0.51 × 0.89 · h sol 2.39 | 308 (154+154) | Torche murale émissive (flamme) |
| `chaine_murale` | props | 0.29 × 0.19 × 1.64 · h sol 1.73 | 1 144 (572+572) | Chaîne et anneau muraux |
| `sarcophage` | props | 1.44 × 0.96 × 1.02 | 760 (380+380) | Sarcophage de pierre avec gisant |
| `pile_os` | props | 1.32 × 1.06 × 0.41 | 984 (492+492) | Pile d'os et de crânes |
| `enseigne` | props | 1.04 × 1.00 × 1.08 · h sol 2.53 | 1 080 (540+540) | Enseigne de taverne suspendue |
| `herse` | buildings | 2.22 × 0.44 × 2.44 | 1 152 (576+576) | Herse / grille en fer relevable |
| `buisson` | vegetation | 1.23 × 1.07 × 0.78 | 492 (246+246) | Buisson touffu avec fleurs |

Notes :

* **ancrage mural** : `torche_murale`, `chaine_murale` et `enseigne` sont
  suspendus ; leur origine est au pied du mur (géométrie au-dessus du sol) ;
* **émission** : `flame`/`flame_core` pour la torche (en plus de `lamp` pour la
  lanterne) ; exportées en `emissiveFactor` glTF ;
* **aucun alpha** : le tapis, les flammes et les chaînes sont de la géométrie
  opaque (pas de feuille alpha, pas de transparence) ;
* les dalles de raccord intérieures (bois/pierre) évitent la coupure nette avec
  le sol peint.

### 5.3 Kit v4 (14 objets) — bâtiments variés, toit, figurines PNJ

Quatrième passe : varier le village et peupler les lieux. Les 8 bâtiments sont
volontairement distincts en silhouette et en toiture (tuile, ardoise, bois) ;
les figurines font ~1 case avec un socle rond discret.

| Asset | Catégorie | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|---|
| `forge` | buildings | 2.45 × 2.17 × 2.57 | 2 068 | Forge : pierre, grosse cheminée, enclume, tonnelet |
| `chapelle` | buildings | 2.58 × 2.62 × 3.40 | 1 648 | Chapelle : clocher, flèche, vitraux, croix |
| `grange` | buildings | 2.93 × 3.18 × 2.48 | 2 488 | Grange à colombages, grandes portes |
| `ecurie` | buildings | 2.88 × 2.51 × 2.35 | 2 208 | Écurie ouverte : stalles, abreuvoir, foin |
| `maison_etage` | buildings | 2.24 × 2.05 × 3.17 | 2 128 | Maison à étage, encorbellement |
| `manoir` | buildings | 3.94 × 3.13 × 3.66 | 3 036 | Manoir / petit château : tourelle, aile, porche |
| `tour_guet_bois` | buildings | 1.91 × 1.93 × 3.54 | 2 392 | Tour de guet bois : plateforme, échelle |
| `marche_couvert` | buildings | 3.15 × 2.74 × 2.96 | 1 808 | Marché couvert : poteaux, toit, étals, lanternes |
| `toit_lucarne` | buildings | 1.53 × 1.13 × 0.87 | 372 | Élément de toit à lucarne + cheminée, posable |
| `fontaine` | props | 2.10 × 2.29 × 1.41 | 1 064 | Fontaine : bassin octogonal, colonne, vasque |
| `puits_couvert` | props | 1.69 × 1.71 × 2.29 | 1 400 | Puits couvert : margelle, 4 poteaux, poulie |
| `pnj_aventurier` | props | 0.70 × 0.70 × 1.08 | 776 | Figurine PNJ aventurier (cape, épée, sacoche) |
| `pnj_marchand` | props | 0.74 × 0.70 × 1.21 | 944 | Figurine PNJ marchand (chapeau, bourse, ballot) |
| `pnj_garde` | props | 0.85 × 0.70 × 1.78 | 956 | Figurine PNJ garde (casque, lance, bouclier) |

Notes :

* **toit_lucarne** est un **module de toit** : origine à la base du toit, pas de
  dalle de sol, à poser au sommet d'un bâtiment pour varier les toitures ;
* **figurines PNJ** : socle rond discret sans jupe (utilisables en intérieur),
  visages peints (yeux/nez), couleurs distinctes (vert, ocre, acier/rouge) ;
  hauteurs 1,08 à 1,78 case (la lance du garde dépasse) ;
* les bâtiments gardent la **jupe d'herbe** extérieure et le pipeline complet
  (AO + mottling, contour encre, dalles intérieures pour les meubles).

### 5.4 Kit v5 (12 objets) — environnement, relief, eau

Cinquième passe : donner du relief et de la vie aux bords de terrain et d'eau
(forêt, étang, bords de zone). Pas de bâtiment ici, uniquement des modules
d'environnement.

| Asset | Catégorie | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|---|
| `falaise` | terrain | 2.32 × 2.31 × 2.00 | 1 552 | Module 2×2 de falaise : roche, dalles, plateau herbeux |
| `gros_rocher` | terrain | 2.12 × 1.88 × 1.36 | 620 | Gros rocher en trois blocs avec mousse |
| `arbre_majestueux` | vegetation | 2.52 × 2.29 × 4.43 | 1 580 | Grand arbre : racines, branches, large houppier |
| `haie` | vegetation | 2.47 × 0.90 × 0.95 | 520 | Haie taillée (module 2 cases) |
| `bosquet` | vegetation | 2.41 × 2.37 × 2.48 | 1 004 | Bosquet : trois jeunes arbres et sous-bois |
| `roseaux` | vegetation | 1.44 × 1.17 × 1.74 | 1 088 | Roseaux de berge : tiges, épis, feuilles |
| `ponton` | props | 2.26 × 0.92 × 1.28 | 984 | Ponton sur pilotis, planches, corde |
| `barque` | props | 1.88 × 0.98 × 0.50 | 952 | Barque creuse : coque, bancs, rames, corde |
| `nenuphars` | vegetation | 1.33 × 1.01 × 0.19 | 728 | Touffe de nénuphars flottants et fleurs |
| `banniere` | props | 1.34 × 0.89 × 2.97 | 712 | Bannière sur mât : emblème et fanion |
| `cloture_basse` | props | 2.21 × 0.41 × 0.68 | 624 | Clôture basse (module 2 cases) |
| `tas_de_bois` | props | 1.38 × 1.00 × 1.04 | 1 360 | Bûches empilées et hache plantée |

Notes :

* **falaise** est un module 2×2 : plateau herbeux au sommet, faces rocheuses sur
  les côtés, à poser en bord de relief (pas de dalle intérieure) ;
* **objets d'eau** : `ponton`, `barque` et `nenuphars` n'ont pas de jupe et sont
  calés sur le niveau de l'eau (`z = 0`) ; le plan d'eau est animé côté moteur ;
* **barque** creuse (coque, bau, bancs, rames) ; **nénuphars** plats sans alpha ;
* **bannière** non émissive, drapée sur mât avec emblème peint.

### 5.6 Kit v7 (12 modules) — toitures et façades

Septième passe : enrichir les bâtiments existants sans les refaire, sous forme
de modules posables. `anchor="roof"` pour les toitures (origine à la base du
toit, centrée), `anchor="wall"` pour les éléments de façade (origine au pied du
mur), `anchor="base"` pour l'escalier extérieur.

| Asset | Ancre | Dimensions (cases) | Hauteur de pose (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|---|---|
| `toit_2pentes` | roof | 2.16 × 2.12 × 0.95 | 0.94 | 760 | Toit 2 pentes 2×2, tuiles + faîtière |
| `toit_croupe` | roof | 2.21 × 2.11 × 0.94 | 0.94 | 496 | Toit à croupe 2×2 |
| `toit_appentis` | roof | 2.12 × 1.11 × 0.66 | 0.65 | 624 | Appentis 2×1, un pan |
| `toit_clocheton` | roof | 0.65 × 0.65 × 1.82 | 1.81 | 312 | Clocheton de faîtage |
| `toit_chaume` | roof | 2.14 × 2.15 × 1.07 | 1.06 | 1 064 | Toit en chaume 2×2 |
| `cheminee_fumante` | roof | 0.82 × 0.64 × 2.54 | 2.53 | 536 | Cheminée + fumée opaque stylisée |
| `colombage_panneau` | wall | 2.06 × 0.20 × 1.81 | 1.80 | 840 | Panneau de colombage 2×1 |
| `porte_auvent` | wall | 1.37 × 0.74 × 2.36 | 2.35 | 760 | Porte + auvent |
| `fenetre_volets` | wall | 1.58 × 0.24 × 1.04 | 1.70 | 552 | Fenêtre à volets ouverts |
| `balcon_bois` | wall | 1.08 × 0.57 × 0.91 | 1.62 | 632 | Balcon 1×1 avec garde-corps |
| `escalier_exterieur` | base | 1.06 × 2.06 × 1.97 | 1.97 | 680 | Escalier bois 1×2 |
| `auvent_etal` | wall | 2.09 × 1.40 × 0.60 | 2.60 | 1 064 | Auvent d'étal rayé 2×1 |

Notes :

* **toits** : modules autoportés à empiler sur un bâtiment (2×2, 2×1, clocheton,
  chaume) ; `cheminee_fumante` inclut des volutes de fumée **opaques** stylisées
  (aucun alpha, aucune émission) ;
* **façades** : panneau de colombage, porte à auvent, fenêtre à volets, balcon,
  auvent d'étal se fixent au mur (côté `+Y`), origine au pied du mur ;
* **escalier_exterieur** est posé au sol (ancre `base`), 1×2 cases ;
* tous les modules suivent le pipeline commun (AO/mottling, contour encre,
  palette Valbois) et n'ont **pas** de jupe de sol.

### 5.5 Kit v6 (10 figurines) — personnages et créatures

Sixième passe : remplacer le choix par hash entre 3 PNJ par une vraie variété
lisible (classes + créatures), utilisable comme props ou tokens de session.
Toutes les figurines font ~1 case de large, socle rond sans jupe, visage peint,
et portent un tag `class:...` ou `creature:...` dans le manifeste.

| Asset | Tags | Dimensions (cases) | Tris (mesh+contour) | Description |
|---|---|---|---|---|
| `pnj_aventurier` | class:aventurier | 0.86 × 0.70 × 1.14 | 1 016 | Épée, bouclier, cape, sac à dos |
| `pnj_archere` | class:archere | 0.70 × 0.70 × 1.24 | 1 072 | Arc, carquois et flèches, capuche |
| `pnj_mage` | class:mage | 0.83 × 0.70 × 1.80 | 1 284 | Robe, chapeau pointu, bâton à orbe, barbe |
| `pnj_voleuse` | class:voleuse | 0.70 × 0.70 × 1.00 | 792 | Capuche, écharpe, deux dagues |
| `pnj_pretresse` | class:pretresse | 0.70 × 0.70 × 1.39 | 1 232 | Robe longue, cape, symbole sacré, diadème |
| `pnj_garde` | class:garde | 0.85 × 0.70 × 2.01 | 900 | Armure, casque à plumet, hallebarde |
| `pnj_marchand` | class:marchand | 0.84 × 0.70 × 1.60 | 1 120 | Chapeau large, sac, bâton |
| `pnj_villageois` | class:villageois | 0.81 × 0.70 × 1.05 | 1 016 | Tunique, tablier, seau |
| `pnj_gobelin` | creature:gobelin | 0.62 × 0.62 × 0.86 | 716 | Petit, vert, grandes oreilles, dague |
| `pnj_squelette` | creature:squelette | 0.68 × 0.66 × 1.19 | 1 096 | Ossature, crâne, épée rouillée |

Notes :

* les 3 noms historiques (`pnj_aventurier`, `pnj_marchand`, `pnj_garde`) sont
  **conservés** (compatibilité du code de démo) mais enrichis et re-taggés ;
* les tokens peuvent filtrer le manifeste sur `class:` / `creature:` pour
  choisir une figurine par rôle plutôt que par hash ;
* couleurs distinctes et silhouettes différentes (chapeau, arc, hallebarde,
  capuche, robe) pour rester lisibles vus de dessus ;
* pas d'animation : figurines en pose statique, socle inclus dans le maillage.

---

## 6. Générer les prototypes

```powershell
# Depuis la racine du dépôt : build + contrôle qualité + récapitulatif
.\tools\blender\run_build.ps1

# Itération sur un ou deux objets (liste PowerShell séparée par des virgules)
.\tools\blender\run_build.ps1 -Only maison,tour

# Repli moteur de rendu (voir § 12)
.\tools\blender\run_build.ps1 -Engine cycles -Samples 24
```

Appel direct Blender (le wrapper ne fait qu'ajouter les vérifications) :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/build_prototypes.py -- `
    --only maison --engine eevee --samples 32
```

Options de `build_prototypes.py` (après `--`) :

| Option | Effet |
|---|---|
| `--only NOM...` | ne génère que ces assets (nom de base ou nom final) |
| `--out-root DIR` | racine de sortie (défaut `game/assets/objects3d`) |
| `--engine eevee\|cycles` | moteur des vignettes (défaut `eevee`) |
| `--samples N` | échantillons de rendu (défaut 32) |
| `--thumb-size N` | taille carrée des vignettes (défaut 512) |
| `--no-thumbs` | exporte les GLB sans vignettes |
| `--no-export` | rend les vignettes sans exporter les GLB |
| `--no-outline` | désactive le contour encre (debug) |
| `--no-manifest` | n'écrit pas `manifest.json` |

Sortie : `<catégorie>/<nom>.glb` + `<catégorie>/<nom>_thumb.png`, un manifeste
JSON et, avec `make_contact_sheet.py`, une planche de contrôle :

```powershell
python tools/blender/make_contact_sheet.py
# -> game/assets/objects3d/_planche_assets.png
```

Durée observée sur cette machine (Blender 4.5.10, EEVEE headless) : ~11 s pour
les 23 assets, vignettes comprises (premier rendu plus lent, compilation des
shaders), plus ~3 s pour les textures de sol et la planche enrichie.

---

## 6 bis. Textures de sol tuilables

Trois textures **512×512 seamless** (elles se raccordent quand on les répète)
générées offline par `tools/blender/make_terrain_textures.py` (numpy + Pillow) :

| Fichier | Rôle | Palette |
|---|---|---|
| `grass.png` | herbe de prairie / sous-bois | `#3a4429` → `#64704a` → `#a3a870` + herbe sèche |
| `dirt.png` | terre, chemin, place battue | `#5c4b38` → `#8a755c` → `#b6a183` + cailloux |
| `stone.png` | pavé / dallage de pierre | `#545048` → `#8c887d` → `#b7b1a4` + mousse |

Chaque texture est accompagnée de `*_thumb.png` (256², bibliothèque) et la
planche `game/assets/terrain/_planche_terrain.png` montre chaque tuile répétée
en 2×2 pour vérifier le raccord.

### 6 bis.1 Commande

```powershell
python tools/blender/make_terrain_textures.py
# sortie par défaut : game/assets/terrain/
python tools/blender/make_terrain_textures.py --size 512 --seed 2026 --verify
```

Pillow est requis (comme pour la planche de vignettes). `run_build.ps1` exécute
cette étape automatiquement s'il trouve un Python avec Pillow
(`-PythonExe`, `$env:OQ_PYTHON`, `python`, `python3`).

### 6 bis.2 Comment le seamless est garanti

* bruit **périodique** : value noise sur grille bouclée, fBm multi-échelle
  (3 → 64 cellules) et domain warp périodique ;
* détails peints (brins, cailloux, fissures, joints) dessinés avec **repliement
  sur les bords** (copie décalée de ±512 px quand le motif approche d'un bord) ;
* pavé : cellules de Voronoï **périodiques** (distance calculée avec
  repliement), joints et mousse dérivés de la distance au bord de cellule ;
* flou/netteté appliqués sur une tuile 3×3 puis recadrés au centre (le flou ne
  casse donc pas le raccord) ;
* `--verify` mesure l'écart entre les bords opposés et le compare à l'écart
  entre colonnes voisines intérieures : si le raccord est visible, le script
  sort en erreur.

### 6 bis.3 Utilisation côté Godot

Pour un sol 3D simple (terrain maillé) ou un plan texturé :

```gdscript
var material := StandardMaterial3D.new()
material.albedo_texture = load("res://assets/terrain/grass.png")
material.roughness = 1.0
material.metallic = 0.0
material.uv1_scale = Vector3(2.0, 2.0, 1.0)  # 1 texture ≈ 2 cases
material.texture_repeat = true
material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
```

Règles :

* garder `roughness = 1`, `metallic = 0`, pas de normal map : le rendu reste
  mat et peint ;
* `uv1_scale` dépend de la taille de tuile voulue (test 1 texture = 2 cases,
  ajuster si les motifs paraissent trop gros) ;
* pas de transparence (PNG RGB opaque) ;
* pour un terrain déformé (relief), préférer un `uv1_scale` constant et des
  coordonnées UV projetées à plat (pas de triplanar, qui casse la continuité
  peinte) ;
* les objets posés dessus gardent leur jupe de raccord (herbe/terre) pour
  éviter une ligne nette à leur base.

## 7. Exporter un `.blend` d'artiste

`export_blend.py` est le CLI générique : un artiste livre un `.blend`, on en
sort un GLB propre et une vignette au même standard que les prototypes.

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/export_blend.py -- `
    --input "D:\3d\maison.blend" --name maison --category buildings `
    --apply-transforms --origin-base --outline
```

Le `.blend` peut aussi être ouvert par Blender (`blender --background
"modele.blend" --python tools/blender/export_blend.py -- --name ...`).

| Option | Effet |
|---|---|
| `--input PATH` | `.blend` à ouvrir (sinon fichier déjà chargé) |
| `--name NOM` | nom de l'asset (défaut : nom du `.blend`, slugifié) |
| `--category CAT` | `buildings` \| `props` \| `vegetation` \| `terrain` (défaut `props`) |
| `--out-root DIR` | racine de sortie |
| `--engine`, `--samples`, `--thumb-size`, `--thumb-margin` | réglages vignette |
| `--selected` | n'exporte que les objets sélectionnés |
| `--apply-transforms` | applique rotation/scale aux meshes |
| `--origin-base` | recentre l'origine au pied (un seul mesh fusionné) |
| `--outline`, `--outline-thickness` | ajoute le contour encre |
| `--no-thumb`, `--no-export` | vignette seule / GLB seul |
| `--strict` | échoue si budget poly dépassé |

Checklist du fichier artiste :

1. **un seul mesh** (ou une hiérarchie simple) fusionné avant export ;
2. transforms appliquées (rotation/scale à 1) ;
3. origine au centre de la base, base à `z = 0` ;
4. face avant vers `-Y` dans Blender (→ `+Z` en glTF) ;
5. matériaux mats, opaques, sans transparence ; pas de caméra/lumière
   (elles sont ignorées et masquées pendant le rendu) ;
6. < 5 000 triangles (contour inclus).

Le CLI totalise les triangles, applique éventuellement le contour, masque les
caméras/lumières du fichier pendant la vignette et active les vertex colors
s'il y en a.

---

## 8. Vignettes

Spécification commune à **tous** les assets (bibliothèque homogène) :

| Paramètre | Valeur |
|---|---|
| Taille | 512 × 512, PNG RGBA |
| Fond | transparent (`film_transparent`), alpha vérifié par `verify_glb.py` |
| Caméra | 3/4 : azimut **35°** (face avant + côté droit), élévation **38°** |
| FOV | 38° |
| Cadrage | bounding box entière, marge 1,14 (aucun objet rogné) |
| Lumière | clef soleil chaud + fill froid + rim, identiques pour tous |
| Color management | `Standard` (pas d'AgX qui délave les couleurs) |
| Moteur | EEVEE Next par défaut, Cycles CPU en repli |

Ces réglages sont centralisés dans `oq_common` (`DEFAULT_AZIMUTH_DEG`,
`DEFAULT_ELEVATION_DEG`, `DEFAULT_FOV_DEG`, `setup_studio_lights`,
`render_thumbnail`) : ne pas les modifier par asset, sinon la bibliothèque
devient hétérogène.

Planche de contrôle courante (tous les kits + textures de sol) :

```powershell
python tools/blender/make_contact_sheet.py
python tools/blender/make_contact_sheet.py --out game/assets/objects3d/_planche_assets7.png --terrain
```

La seconde ajoute une rangée de textures de sol : `_planche_assets7.png`
(83 cases : 3 sols + 80 objets). `_planche_assets.png` à
`_planche_assets6.png` restent les planches historiques v1→v6. Les objets
muraux y affichent leur hauteur au pied du mur, l'AABB seule ne mesurant que la
géométrie suspendue.

---

## 9. Vérification

```powershell
# via le wrapper : build + vérification + récapitulatif
.\tools\blender\run_build.ps1

# vérification seule
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/verify_glb.py -- [--root DIR] [--only nom ...] [--strict]
```

`verify_glb.py` combine deux contrôles indépendants :

1. **Lecture directe du conteneur GLB** (sans Blender) : pas de caméra, pas de
   lumière (`KHR_lights_punctual`), matériaux `alphaMode = OPAQUE`, matériaux
   non double face, présence de `COLOR_0`, présence du nœud `*_outline` et
   comptage des triangles via les accessors glTF.
2. **Reimport dans une scène Blender vide** : nombre d'objets/vertices/
   triangles, bounding box, origine au pied (`min_z ≈ 0`), base centrée,
   transforms neutres, absence de caméra/lumière.

Il contrôle aussi les vignettes : 512×512, coins transparents, objet visible et
centré (couverture alpha entre 3 % et 98 %), et signale un `manifest.json`
désynchronisé. Code de sortie 1 si un asset échoue → utilisable en CI/script.

---

## 10. Intégration au décor 2.5D

C'est la partie qui décide si les objets « jurent » ou non avec la carte.

### 10.1 Règles d'intégration appliquées aux assets

| Problème visuel | Réponse |
|---|---|
| Couleurs plates / cartoon | palette échantillonnée sur Valbois, désaturée, 5–6 teintes par objet |
| Surfaces uniformes, aspect placeholder | AO + mottling en vertex colors, assises/planches/bandeaux de détail |
| Arêtes sans trait | contour encre `*_outline` (inverted hull) fin |
| Découpe nette avec le sol peint | jupe de raccord herbe/terre plate et irrégulière |
| Objets trop gros | AABB cibles documentées (§ 5), maisons ~2 cases, arbre/puits ~1 |
| Aspect PBR brillant | mats : roughness 0,92, metallic 0, specular 0,15, pas de textures |

### 10.2 Rendu côté moteur (prérequis Godot)

1. **Contour** : deux meshes dans le GLB. Désactiver l'ombre de la coque :
   ```gdscript
   for child in root_node.find_children("*_outline", "MeshInstance3D", true, false):
       child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   ```
   Sinon la coque projette une ombre qui assombrit l'objet **et** le sol.
2. **Vertex colors** : Godot 4 applique `COLOR_0` en multiplication de
   l'albédo à l'import glTF. Si un matériau semble plat après import, activer
   `Vertex Color > Use as Albedo` sur le `StandardMaterial3D` correspondant.
3. **Face culling** : garder `doubleSided = false` (défaut glTF/Godot). Le
   contour en dépend.
4. **Ombre de contact** : gérée par le moteur (décale elliptique sous l'objet),
   pas par les assets. Ne pas baker d'ombre dans le GLB.
5. **Échelle** : 1 unité = 1 case ; `node.scale = Vector3.ONE` si la scène est
   déjà en cases, sinon `Vector3.ONE * cell_size`.
6. **Tri de profondeur** : les meshes 3D écrivent dans le depth buffer
   (occlusion réelle) ; les découpes 2D restent triées par priorité. Ne pas
   mélanger les deux sur un même objet.
7. **Vignettes** : `<nom>_thumb.png` (512, alpha) directement dans la
   bibliothèque de l'éditeur ; même angle pour tous → grille homogène.
8. **Sol** : textures tuilables `game/assets/terrain/{grass,dirt,stone}.png`
   en albédo mat (`roughness = 1`, `metallic = 0`), répétées avec
   `uv1_scale` constant ; ce sont elles qui donnent l'échelle et la matière
   générale, les objets se posent dessus via leur jupe de raccord.
9. **Objets muraux** : `torche_murale`, `chaine_murale`, `enseigne` ont leur
   origine au pied du mur ; les tourner pour que le côté `+Y` soit contre le mur.
   L'éditeur peut lire `anchor: "wall"` et `height_above_floor` dans le
   manifeste pour afficher l'empreinte et la hauteur de pose.
10. **Intérieurs** : poser les meubles de taverne/donjon sur leurs dalles
   (bois/pierre) ; l'ombre de contact reste moteur, comme pour les extérieurs.
11. **Bâtiments v4** : varier les silhouettes et les toitures ; `toit_lucarne`
   se pose au sommet d'un bâtiment (origine à la base du toit, pas de dalle).
12. **Figurines PNJ** : socle rond, origine au pied ; échelle ~1 case. Elles
   peuvent être traitées comme des props (bibliothèque) ou des tokens (calque
   personnages), avec la même ombre de contact moteur.
13. **Environnement v5** : poser `falaise` en bord de relief ; les objets d'eau
   (`ponton`, `barque`, `nenuphars`) se placent au niveau du plan d'eau animé,
   sans jupe ; `arbre_majestueux` et `bosquet` servent de masses forestières.
14. **Figurines v6** : les 10 figurines partagent le socle rond et l'origine au
   pied ; le moteur peut choisir un rôle via les tags `class:...` / `creature:...`
   du manifeste (fin du hash entre 3 PNJ).
15. **Modules v7** : les toits (`anchor="roof"`) se posent au sommet d'un
   bâtiment, origine à la base du toit ; les éléments de façade (`anchor="wall"`)
   se plaquent contre un mur (`+Y`), fenêtre/balcon livrés à leur hauteur de pose.
16. **Cheminee_fumante** : la fumée est un volume opaque statique (pas de shader
   ni d'alpha) ; libre au moteur d'y ajouter une animation ou un particules.

### 10.3 Composer sans réglage (MJ non technique)

Le MJ doit pouvoir poser un bâtiment sans toucher aux propriétés :

* variantes de taille déjà générées (`maison_petite` / `maison` /
  `maison_grande`) ;
* variantes de teinte pour varier les villages (`arbre_automne`, toits ardoise
  sur `maison_petite`) ;
* orientation par défaut face à la caméra 2.5D (`+Z` = face avant) ;
* origine au pied : la position sur la grille ne demande aucun offset ;
* manifeste JSON avec dimensions en cases : l'éditeur peut afficher l'empreinte
  et aimanter sans configuration.

---

## 11. Ajouter un objet

### A. Objet procédural (recommandé)

1. Écrire `build_<nom>(mats) -> list[Object]` dans `build_prototypes.py`
   (primitives `add_box`, `add_cylinder`, `add_cone`, `add_ico_sphere`,
   `add_mesh`, `gable_roof`, `add_ground_skirt`).
2. Ajouter une entrée `AssetSpec` : nom (ASCII snake_case), catégorie,
   description, tags, variantes éventuelles (`Variant(suffix, scale, palette)`).
3. Régénérer : `.\tools\blender\run_build.ps1 -Only <nom>`, vérifier la
   vignette et `verify_glb.py`.

Le pipeline applique automatiquement : fusion, normalisation, subdivision,
AO/mottling, contour, jupe (si le builder en pose une), export et vignette.

### B. Objet modélisé à la main

Livrer un `.blend` conforme à la checklist du § 7, puis :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/export_blend.py -- `
    --input "D:\3d\mon_objet.blend" --name mon_objet --category props `
    --apply-transforms --origin-base --outline
```

### C. Variante d'un objet existant

Ajouter un `Variant` (suffixe, échelle, overrides de palette) dans l'`AssetSpec`.
Une variante ne doit pas dupliquer la géométrie : même builder, autre teinte ou
échelle.

---

## 12. Nommage et catégories

* **minuscules ASCII snake_case**, pas de accents, pas d'espaces :
  `maison_grande`, `arbre_automne`, `puits` ;
* catégories imposées : `buildings/`, `props/`, `vegetation/`, `terrain/` ;
* vignette : `<nom>_thumb.png` à côté du `<nom>.glb` ;
* nœud de contour : `<nom>_outline` (sert au moteur pour couper l'ombre) ;
* variantes : suffixe de taille/teinte (`_petite`, `_grande`, `_automne`).

---

## 13. Budgets et poids

| Indicateur | Valeur actuelle |
|---|---|
| Assets 3D | 80 (75 modèles + 5 variantes) |
| Triangles / asset | 308 → **3 036** max (contour inclus), budget 5 000 |
| Triangles total | **86 008** |
| GLB / asset | ~33 → ~219 Ko (vertex colors + contour) |
| Vignette / asset | ~111 → ~195 Ko (512 RGBA) |
| Textures de sol | 3 × 512² RGB, ~510–550 Ko chacune (PNG), + thumbs 256² |
| Planches | `_planche_assets7.png` (83 cases), historiques `_planche_assets{,2,3,4,5,6}.png`, `_planche_terrain.png` |

Les GLB restent légers : pas de texture embarquée, pas d'animation, pas de
skin. Les textures de sol sont des PNG externes (réutilisables, non embarqués
dans les GLB).

---

## 14. Commandes PowerShell exactes (aide-mémoire)

```powershell
# Version de Blender
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --version

# Build complet + vérification + récapitulatif
.\tools\blender\run_build.ps1

# Build d'un sous-ensemble
.\tools\blender\run_build.ps1 -Only maison,tour

# Build avec Cycles CPU (si EEVEE headless échoue)
.\tools\blender\run_build.ps1 -Engine cycles -Samples 24

# Build sans vignettes / sans vérification
.\tools\blender\run_build.ps1 -SkipThumbs
.\tools\blender\run_build.ps1 -SkipVerify

# Textures de sol tuilables seules + planche de contrôle
python tools/blender/make_terrain_textures.py
python tools/blender/make_contact_sheet.py --out game/assets/objects3d/_planche_assets7.png --terrain

# Build complet sans les textures (Pillow absent par ex.)
.\tools\blender\run_build.ps1 -SkipTerrainTextures

# Build direct Blender (sans wrapper)
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/build_prototypes.py -- --only maison

# Export d'un .blend d'artiste
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/export_blend.py -- `
    --input "D:\3d\modele.blend" --name modele --category props --outline

# Vérification seule
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/verify_glb.py

# Planche de contrôle des vignettes
python tools/blender/make_contact_sheet.py
```

`run_build.ps1` accepte aussi `-BlenderExe "C:\...\blender.exe"` ou la variable
d'environnement `OQ_BLENDER` si Blender est installé ailleurs.

---

## 15. Dépannage

### Blender introuvable / mauvais chemin

`run_build.ps1` cherche dans cet ordre : `-BlenderExe`, `$env:OQ_BLENDER`,
`C:\Program Files\Blender Foundation\Blender 4.5\blender.exe`, les autres
versions installées, puis le PATH. Toujours mettre le chemin **entre
guillemets** (espaces dans `Program Files`).

### `blender --background` retourne 0 malgré une erreur Python

Toujours passer `--python-exit-code 1` (déjà fait dans tous les scripts et le
wrapper) : sans cette option, Blender peut sortir en 0 après une exception.

### EEVEE ne rend pas en headless

Constat sur cette machine : **EEVEE Next fonctionne en `--background`** sous
Blender 4.5.10 LTS (premier rendu ~3 s, compilation des shaders ; suivants
~0,1 s). Sur une machine sans contexte GPU/OpenGL exploitable, EEVEE peut
échouer ou produire une image noire. Repli officiel : **Cycles CPU**.

```powershell
.\tools\blender\run_build.ps1 -Engine cycles -Samples 24
```

ou en direct :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/build_prototypes.py -- `
    --engine cycles --samples 24
```

Cycles CPU : 24 échantillons suffisent à 512 px (denoising activé par le
pipeline). Le nom du moteur EEVEE est `BLENDER_EEVEE_NEXT` en 4.5 ; ne pas
utiliser l'ancien `BLENDER_EEVEE`.

### `Cycles` indisponible / « engine not found »

Cycles est un add-on. Les scripts tentent de l'activer ; si l'énumération ne le
propose pas (préférences d'usine), le pipeline revient à EEVEE en le signalant.
Vérifier l'installation Blender ou utiliser EEVEE.

### Fond noir autour des vignettes

C'est un visualiseur qui affiche l'alpha en noir, pas un bug : le PNG est bien
RGBA transparent. Vérifier avec `verify_glb.py` (coins alpha ≈ 0) ou dans un
outil qui affiche la transparence. Ne jamais activer `film_transparent = False`.

### Objet qui flotte ou enterré en jeu

Vérifier les conventions : `min_z ≈ 0`, base centrée, transforms neutres.
`verify_glb.py` échoue si l'origine n'est plus au pied. Pour un `.blend`
d'artiste, utiliser `--origin-base` (un seul mesh fusionné) ou corriger dans
Blender.

### Objet invisible/transparent dans Godot

Vérifier `doubleSided` (doit être `false`), `alphaMode` (`OPAQUE`) et que le
matériau importé n'a pas été rendu transparent. Les assets n'ont ni texture ni
alpha.

### Les vertex colors ne se voient pas dans Godot

Godot 4 importe `COLOR_0` et l'utilise en multiplication de l'albédo. Si
l'effet est absent : ouvrir le `StandardMaterial3D` importé et activer
`Vertex Color > Use as Albedo`. L'objet reste correct sans cela (couleurs
plates), juste moins de volume.

### Le contour assombrit tout / fait une grosse ombre

Le nœud `*_outline` projette une ombre : désactiver son `cast_shadow` côté
moteur (§ 10.2). Dans Blender c'est déjà neutralisé pour les vignettes.

### Contour trop épais / trop fin

`OUTLINE_THICKNESS = 0.014` case. Modifier la constante dans `oq_common.py`
(ou `--outline-thickness` pour `export_blend.py`) puis régénérer. À l'échelle
d'une case, rester entre 0,010 et 0,020.

### Triangles de travers / comptage incohérent entre export et reimport

Le pipeline triangule explicitement les meshes avant export et supprime les
arêtes dégénérées. Si vous ajoutez de la géométrie custom, passer par
`finalize_asset` puis `subdivide_long_edges` + `triangulate_mesh` (comme le
build), sinon `verify_glb.py` le signalera.

### Vignette vide / objet rogné

Le cadrage est calculé sur la bounding box des objets passés à
`render_thumbnail` : penser à inclure le contour (c'est fait dans le build).
Pour un asset très allongé, augmenter `--thumb-margin` (défaut 1,14).

### Build long ou première vignette lente

Le premier rendu EEVEE compile les shaders (~3 s) ; les suivants sont rapides.
Après un reboot ou un changement de pilote GPU, la première exécution peut
être plus lente : c'est normal.

---

### Python + Pillow introuvable (textures de sol, planche)

Les textures de sol et les planches nécessitent **Pillow** (les scripts 3D
tournent dans Blender, eux). `run_build.ps1` cherche `-PythonExe`,
`$env:OQ_PYTHON`, `python`, `python3`, puis teste `import PIL`. Si rien ne
convient, l'étape est sautée avec un avertissement (le build 3D reste OK).

```powershell
pip install pillow
.\tools\blender\run_build.ps1 -PythonExe "C:\Python312\python.exe"
```

### Raccord visible quand la texture est répétée

Lancer `python tools/blender/make_terrain_textures.py --verify` : il compare
l'écart entre bords opposés à l'écart entre colonnes voisines intérieures. Si
le script échoue, c'est que la génération a été modifiée sans respecter le
repliement (tout détail peint doit passer par `_draw_shifted`, tout bruit doit
être périodique).

### Texture de sol trop répétée / motifs trop gros

Ajuster `uv1_scale` côté Godot (1 texture = 2 cases par défaut). Si les motifs
restent trop gros, régénérer avec `--size 1024` (plus de détail, fichier plus
lourd) plutôt que de réduire l'échelle UV à l'extrême.

## 16. Checklist avant de rendre un asset

- [ ] nom ASCII snake_case, catégorie correcte ;
- [ ] AABB conforme aux cibles (§ 5), origine au pied, base centrée ;
- [ ] < 5 000 triangles **contour inclus** ;
- [ ] palette Valbois, matériaux mats/opaques, pas de texture ni d'alpha ;
- [ ] jupe de raccord au sol présente (sauf exception documentée) ;
- [ ] objets muraux : `anchor="wall"`, mur en `+Y`, origine au pied du mur ;
- [ ] `toit_lucarne` : pas de dalle de sol, origine à la base du toit ;
- [ ] modules de toit : `anchor="roof"`, origine à la base du toit, pas de dalle ;
- [ ] figurines PNJ : socle rond, pas de jupe, visage lisible, ~1 case ;
- [ ] objets d'eau : pas de jupe, origine au niveau de l'eau (z=0) ;
- [ ] figurines : socle rond, visage peint, tag `class:...` / `creature:...` ;
- [ ] contour `*_outline` présent, matériaux `doubleSided: false` ;
- [ ] `COLOR_0` présent sur le mesh principal ;
- [ ] GLB + vignette 512 générés, vignette lisible et cadrée ;
- [ ] `verify_glb.py` : 0 échec, warnings examinés ;
- [ ] récapitulatif `run_build.ps1` relu, planche de vignettes mise à jour ;
- [ ] manifeste à jour, aucune retouche manuelle des fichiers générés.

### Pour les textures de sol

- [ ] 512×512, RGB opaque, `<nom>.png` + `<nom>_thumb.png` ;
- [ ] `make_terrain_textures.py --verify` sans échec (raccord X et Y) ;
- [ ] planche `_planche_terrain.png` relue (tuile 2×2) ;
- [ ] pas de transparence, pas de normal map, matériau mat côté moteur.

---

## 17. Limites connues

* Les prototypes sont des **approximations stylisées**, pas des modèles
  d'artiste : détails procéduraux (planches, tuiles suggérées) volontairement
  simples.
* L'AO en vertex colors est une **approximation par lancer de rayons locaux**
  (distance 0,32 case) : elle donne du volume mais ne remplace pas un bake
  haute densité. Résolution limitée par la subdivision (max arête 0,5 case).
* Pas de LOD, pas d'animation, pas de textures : budget tenu par la
  géométrie et les vertex colors uniquement.
* Les vignettes sont rendues dans Blender (éclairage studio) : elles servent de
  vignettes de bibliothèque, pas de rendu d'intégration à la carte.
* Le contour « inverted hull » est sensible aux géométries très concaves
  (auto-intersections possibles) ; les volumes actuels sont convexes ou
  simples.
* Le pipeline exige EEVEE Next **ou** Cycles CPU ; le rendu GPU Cycles n'est
  pas testé.
* Les textures de sol sont **générées** (bruit + détails peints procéduraux) :
  elles sont seamless et cohérentes avec la palette, mais ne remplacent pas des
  textures peintes à la main par un artiste pour des zones très spécifiques.
* Les textures ne contiennent ni normal map ni height map : le relief reste
  porté par la géométrie du terrain.
* Une seule échelle de tuile par texture : pas d'atlas ni de mélange de
  transitions herbe/terre/pavé (à composer côté moteur si besoin).
* Les objets muraux (torche, chaîne, enseigne) ont une AABB qui ne mesure que la
  géométrie suspendue ; leur hauteur de pose est fournie séparément dans le
  manifeste (`height_above_floor`).
* Les vignettes d'objets ajourés (herse, chaîne) sont cadrées sur l'objet
  entier : le centre de l'image peut être transparent, c'est normal (le contrôle
  qualité mesure la couverture de la zone centrale, pas un pixel).
* Les bâtiments v4 à toiture large (écurie, marché couvert) sont vus de dessus :
  le toit masque une partie de l'intérieur sur les vignettes, c'est attendu.
* Les figurines PNJ sont volontairement très low-poly (~0,4–0,5 k tris) : à
  l'échelle d'une case, les visages sont suggérés (yeux/nez peints) et non
  sculptés ; les détails fins (armes, sacs) restent des volumes simples.
* Les objets d'eau (`ponton`, `barque`, `nenuphars`) flottent au niveau du plan
  d'eau : sans animation moteur, ils apparaissent posés sur le sol. Le ponton
  n'a pas de rambarde pour rester lisible et léger.
* Les modules v7 ne sont pas **aimantés** automatiquement aux bâtiments : c'est
  l'éditeur qui positionne toits et façades (aucune contrainte de snap dans le
  GLB). La fumée de `cheminee_fumante` est figée dans le mesh.
* La falaise est un module de relief 2×2 : elle ne gère pas de transitions
  douces avec les cases voisines (à composer côté éditeur/moteur).
* Les figurines v6 sont statiques et très low-poly (~0,7–1,3 k tris) : les
  visages sont peints (yeux/nez) et non sculptés, les armes/props restent des
  volumes simples. Le socle fait partie du maillage (pas d'objet séparé).
