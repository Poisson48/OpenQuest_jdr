# Objets 3D — carte 2.5D

Assets **procéduraux low‑poly** prêts à poser sur la grille de la carte 2.5D
(type League of Legends / Warhammer) : un mix de découpes 2D et de meshes 3D
posés sur une grille, avec un décor peint en fond. Les objets sont pensés pour
être **lisibles de dessus mais fondus dans l'illustration Valbois** : palette
terre/bois/pierre chaude et désaturée, matériaux mats, AO + mottling cuits en
vertex colors, contour encre et jupe de raccord au sol.

Le kit est complété par les **textures de sol tuilables**
[`game/assets/terrain/`](../terrain/README.md) (herbe, terre/chemin, pavé).

> Ces fichiers sont **générés** par `tools/blender/build_prototypes.py` et
> `tools/blender/make_terrain_textures.py`. Ne pas les retoucher à la main :
> modifier les scripts puis régénérer.
> Voir [docs/BLENDER_PIPELINE.md](../../docs/BLENDER_PIPELINE.md) pour le
> workflow complet, la palette et les conventions.

---

## Conventions (identiques pour tous les assets)

| Contrainte | Valeur |
|---|---|
| Échelle | **1 unité Blender = 1 case de carte** (dimensions réelles ci-dessous) |
| Origine | **centre de la base**, posée sur le sol (`y = 0` en glTF/Godot) |
| Axes glTF | `+Y` = haut, face avant de l'objet vers **`+Z`** |
| Transforms | rotation/scale à 1, location à 0 (bake dans le mesh) |
| Budget | **< 5 000 triangles** par asset (contour encre inclus ; max actuel : 2 304) |
| Matériaux | mats (roughness 0,92, metallic 0, specular 0,15), palette Valbois, **aucune transparence, aucune texture alpha**, faces simples (backface culling) |
| Détail | AO + mottling en **vertex colors `COLOR_0`** (multiplicateur) |
| Contour | coque inversée `*_outline` en encre sombre (double le nombre de triangles) |
| Sol | **jupe de raccord** herbe/terre très plate, débordant du bâti |
| Caméra/lumière | **jamais exportées** dans le GLB |
| Vignette | `<nom>_thumb.png` 512×512, fond transparent, cadrage 3/4 identique pour tous |

L'ombre de contact est gérée **côté moteur**, rien n'est cuit dans les assets.

---

## Catalogue

23 assets (18 modèles + 5 variantes de taille/teinte), **22 228 triangles** au
total, 2 304 au maximum. Dimension = AABB réelle du GLB (contour inclus).

### Bâtiments et structures — `buildings/`

| Asset | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|
| `maison_petite` | 1.60 × 1.49 × 1.54 | 1 856 (928+928) | Petite habitation, annexe, échoppe ; toit ardoise |
| `maison` | 1.95 × 1.81 × 1.88 | 1 928 (964+964) | Habitation de village standard ; toit terre cuite |
| `maison_grande` | 2.26 × 2.10 × 2.17 | 2 304 (1 152+1 152) | Auberge, maison bourgeoise, bâtiment public |
| `tour` | 1.47 × 1.33 × 2.37 | 1 088 (544+544) | Tour de guet, poste de garde |
| `tour_grande` | 1.71 × 1.54 × 2.74 | 1 144 (572+572) | Donjon secondaire, tour de siège |
| `mur` | 2.36 × 0.70 × 1.30 | 784 (392+392) | Enceinte, mur de soutènement (module 2 cases) |
| `mur_coin` | 2.10 × 1.69 × 1.29 | 1 336 (668+668) | Coin d'enceinte en L |

### Décors — `props/`

| Asset | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|
| `pont` | 2.64 × 1.30 × 1.09 | 1 880 (940+940) | Franchissement de rivière (2 cases + culées) |
| `caisse` | 1.07 × 1.05 × 0.76 | 688 (344+344) | Marchandise, couverture, obstacle bas |
| `caisse_grande` | 1.34 × 1.32 × 0.95 | 720 (360+360) | Cargaison, entrepôt, couvert |
| `palissade` | 2.20 × 0.51 × 1.24 | 620 (310+310) | Clôture de camp, ligne défensive (module 2 cases) |
| `puits` | 1.20 × 1.02 × 1.44 | 816 (408+408) | Point d'eau, place de village |
| `barriere` | 2.10 × 0.44 × 0.94 | 496 (248+248) | Clôture basse de chemin ou pâture |
| `etal_marche` | 1.96 × 1.53 × 2.00 | 1 792 (896+896) | Étal de marché, auvent à rayures |
| `tonneau` | 0.92 × 0.91 × 0.84 | 648 (324+324) | Tonneau cerclé de métal |
| `lanterne` | 0.84 × 0.84 × 2.30 | 396 (198+198) | Lanterne sur poteau, fanal émissif |
| `banc` | 1.32 × 0.68 × 0.98 | 488 (244+244) | Banc de place / jardin |
| `panneau` | 0.87 × 0.78 × 2.01 | 344 (172+172) | Panneau indicateur, deux flèches |
| `charrette` | 1.61 × 1.74 × 0.94 | 1 208 (604+604) | Charrette à bras, roues et brancards |
| `botte_foin` | 1.10 × 0.85 × 0.67 | 548 (274+274) | Botte de foin liée |

### Végétation — `vegetation/`

| Asset | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|
| `arbre` | 1.03 × 1.05 × 2.10 | 396 (198+198) | Forêt, bosquet, bord de chemin (feuillu) |
| `arbre_automne` | 1.03 × 1.05 × 2.10 | 396 (198+198) | Variante de teinte ocre (même géométrie) |

### Terrain — `terrain/`

| Asset | Dimensions (cases) | Tris (mesh+contour) | Usage |
|---|---|---|---|
| `rocher` | 1.45 × 1.18 × 0.87 | 352 (176+176) | Obstacle, relief, décor minéral |

Chaque asset est accompagné de sa vignette : `buildings/maison_thumb.png`, etc.
Le fichier `manifest.json` liste tout (nom, catégorie, dimensions, triangles,
description) — il est **informatif** : l'éditeur peut scanner les dossiers.
`_planche_assets.png` est la planche du kit v1 ; `_planche_assets2.png` est la
planche de contrôle enrichie (textures de sol + 23 objets).

---

## Chargement côté Godot

```gdscript
const OBJECTS3D_DIR := "res://assets/objects3d"

func spawn_object(category: String, asset_name: String, cell: Vector2i) -> Node3D:
    var path := "%s/%s/%s.glb" % [OBJECTS3D_DIR, category, asset_name]
    var packed := load(path) as PackedScene
    if packed == null:
        push_error("Asset 3D introuvable : " + path)
        return null
    var node := packed.instantiate() as Node3D
    node.position = Vector3(cell.x, 0.0, cell.y)  # origine au pied
    # 1 unité = 1 case : scale = taille de case si la scène n'est pas déjà en cases
    _prepare_mesh_node(node)
    add_child(node)
    return node

func _prepare_mesh_node(root: Node) -> void:
    for child in root.get_children():
        if child is MeshInstance3D:
            # La coque d'encre ne doit pas projeter d'ombre (sinon elle
            # assombrit tout l'objet et le sol).
            if child.name.ends_with("_outline"):
                child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        _prepare_mesh_node(child)
```

Points d'intégration importants :

- **Origine au pied** : `position` = point au sol ; la face avant regarde `+Z`.
- **Contour** : le GLB contient deux meshes (`<nom>` et `<nom>_outline`).
  Mettre `cast_shadow = SHADOW_CASTING_SETTING_OFF` sur `*_outline`.
- **Vertex colors** : `COLOR_0` multiplie la couleur de base. Godot 4
  l'applique automatiquement à l'import glTF ; si un matériau semble plat,
  activer `Vertex Color > Use as Albedo` sur le `StandardMaterial3D`.
- **Faces simples** : `doubleSided: false` dans le GLB (indispensable au
  contour). Ne pas forcer le rendu double face côté moteur.
- **Lanterne** : le matériau `lamp` est émissif (`emissiveFactor` glTF) ; il
  peut servir de source de lumière douce côté moteur.
- **Sol** : textures tuilables dans `game/assets/terrain/` (voir
  [`../terrain/README.md`](../terrain/README.md)).
- Dimensions en cases : voir les tableaux (ex. `pont` = 2,64 cases).
- La vignette `<nom>_thumb.png` est utilisable telle quelle dans la
  bibliothèque d'assets (fond transparent, même angle pour tous).

---

## Régénérer les assets

```powershell
# Tout : GLB + vignettes + contrôle + textures de sol + planche enrichie
.\tools\blender\run_build.ps1

# Uniquement certains objets (itération)
.\tools\blender\run_build.ps1 -Only maison,mur,lanterne

# Fallback si EEVEE ne rend pas sur la machine (Cycles CPU)
.\tools\blender\run_build.ps1 -Engine cycles -Samples 24

# Sans textures de sol (si Pillow absent)
.\tools\blender\run_build.ps1 -SkipTerrainTextures

# Textures de sol seules + planche de contrôle du raccord
python tools/blender/make_terrain_textures.py
python tools/blender/make_contact_sheet.py --out game/assets/objects3d/_planche_assets2.png --terrain
```

Appel direct sans le wrapper :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/build_prototypes.py -- --only maison
```

Exporter un `.blend` d'artiste (contour encre optionnel) :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/export_blend.py -- `
    --input "D:\3d\maison.blend" --name maison --category buildings --outline
```

---

## Ajouter un objet

1. **Objet procédural** (aucun asset externe) : ajouter une fonction
   `build_<nom>(mats)` dans `tools/blender/build_prototypes.py`, puis une entrée
   `AssetSpec` (catégorie, description, tags, variantes éventuelles). Le
   pipeline applique automatiquement subdivision, AO/mottling, contour et jupe.
2. **Objet modélisé à la main** : livrer un `.blend` propre (un mesh, transforms
   appliquées, origine au pied, face avant vers `-Y` dans Blender, pas de
   caméra/lumière), puis passer par `export_blend.py` (éventuellement
   `--apply-transforms --origin-base --outline`).
3. Régénérer : `.\tools\blender\run_build.ps1 -Only <nom>` puis vérifier le
   récapitulatif, la planche de vignettes et `verify_glb.py`.

Le nommage est en **minuscules ASCII snake_case** (`maison_grande`,
`arbre_automne`) ; les variantes utilisent un suffixe de taille/teinte.
