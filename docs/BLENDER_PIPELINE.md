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

Tous les scripts sont **offline** : aucune texture, aucun téléchargement,
aucun asset externe. Les objets sont procéduraux.

---

## 2. Arborescence du pipeline

```text
tools/blender/
├── oq_common.py            # helpers partagés (scène, matériaux, primitives,
│                           #   normalisation, vertex colors, contour, export, rendu)
├── build_prototypes.py     # génère les 8 objets + variantes (GLB + vignettes)
├── export_blend.py         # CLI générique : .blend d'artiste -> GLB + vignette
├── verify_glb.py           # contrôle qualité GLB + vignettes (reimport Blender)
├── make_contact_sheet.py   # planche PNG de toutes les vignettes (Pillow)
└── run_build.ps1           # build complet + vérification + récapitulatif

game/assets/objects3d/
├── README.md               # catalogue et mode d'emploi côté moteur
├── manifest.json           # métadonnées générées (nom, dims, tris, tags)
├── _planche_assets.png     # planche de contrôle des vignettes
├── buildings/              # maison*, tour*
├── props/                  # pont, caisse*, palissade, puits
├── vegetation/             # arbre, arbre_automne
└── terrain/                # rocher
```

---

## 3. Conventions 3D (non négociables)

| Convention | Détail |
|---|---|
| **Échelle** | 1 unité Blender = **1 case de carte** |
| **Origine** | **centre de la base**, base posée à `z = 0` (sol) |
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

### Assemblage et normalisation

`oq_common.finalize_asset()` fusionne les primitives en un seul mesh puis
`normalize_asset()` garantit : origine au centre de la base, `z_min = 0`,
`x/y` centrés, rotation/scale neutres, facettes plates (`use_smooth = False`).

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

Ces dimensions incluent le contour (+0,014 de chaque côté) et la jupe. Le
manifeste et le récapitulatif de `run_build.ps1` les affichent.

---

## 6. Générer les prototypes

```powershell
# Depuis la racine du dépôt : build + contrôle qualité + récapitulatif
.\tools\blender\run_build.ps1

# Itération sur un ou deux objets
.\tools\blender\run_build.ps1 -Only maison tour

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

Durée observée sur cette machine (Blender 4.5.10, EEVEE headless) : ~13 s pour
les 13 assets, vignettes comprises (premier rendu plus lent, compilation des
shaders).

---

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
| Assets | 13 (8 objets + 5 variantes) |
| Triangles / asset | 352 → **2 304** max (contour inclus), budget 5 000 |
| Triangles total | **14 188** |
| GLB / asset | ~45 → ~165 Ko (vertex colors + contour) |
| Vignette / asset | ~130 → ~175 Ko (512 RGBA) |

Les GLB restent légers : pas de texture, pas d'image embarquée, pas
d'animation, pas de skin.

---

## 14. Commandes PowerShell exactes (aide-mémoire)

```powershell
# Version de Blender
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" --version

# Build complet + vérification + récapitulatif
.\tools\blender\run_build.ps1

# Build d'un sous-ensemble
.\tools\blender\run_build.ps1 -Only maison tour

# Build avec Cycles CPU (si EEVEE headless échoue)
.\tools\blender\run_build.ps1 -Engine cycles -Samples 24

# Build sans vignettes / sans vérification
.\tools\blender\run_build.ps1 -SkipThumbs
.\tools\blender\run_build.ps1 -SkipVerify

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

## 16. Checklist avant de rendre un asset

- [ ] nom ASCII snake_case, catégorie correcte ;
- [ ] AABB conforme aux cibles (§ 5), origine au pied, base centrée ;
- [ ] < 5 000 triangles **contour inclus** ;
- [ ] palette Valbois, matériaux mats/opaques, pas de texture ni d'alpha ;
- [ ] jupe de raccord au sol présente (sauf exception documentée) ;
- [ ] contour `*_outline` présent, matériaux `doubleSided: false` ;
- [ ] `COLOR_0` présent sur le mesh principal ;
- [ ] GLB + vignette 512 générés, vignette lisible et cadrée ;
- [ ] `verify_glb.py` : 0 échec, warnings examinés ;
- [ ] récapitulatif `run_build.ps1` relu, planche de vignettes mise à jour ;
- [ ] manifeste à jour, aucune retouche manuelle des fichiers générés.

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
