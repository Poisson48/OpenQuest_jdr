# Rapport — Intégration des rochers Tripo3D dans la bibliothèque 3D

Branche : `feat/carte-2.5d-editeur` · Chantier : assets 3D de la carte 2.5D
· Pipeline : `tools/blender/build_tripo_rocks.py`
· Auteurs des modèles : service **Tripo3D** (modèle `P1-20260311`, `face_limit`
1100), revue initiale dans `artifacts/tripo-review/rock-kit/`.

## 1. Contexte et décision

Les quatre prototypes `rocher_socle`, `rocher_bloc`, `rocher_coin` et
`rocher_couronne` avaient été générés pour un **kit de mur de rochers
empilables**. La revue ([`request.json`](../artifacts/tripo-review/rock-kit/request.json))
conclut qu'ils sont **trop plats pour être empilés** : leurs faces supérieures
sont stables mais les volumes ne s'emboîtent pas, et les assembler produit des
murs « en accordéon ». Ils étaient donc restés hors du jeu, et
`game/scripts/tests/rock_kit_library_test.gd` documentait explicitement leur
absence.

Décision : **ne pas les transformer en kit empilable**, mais les livrer comme
**rochers décoratifs / d'affleurement** utilisables dans l'éditeur, à la
qualité du kit Valbois. Le kit empilable du projet reste inchangé
(`rocher`, `gros_rocher`, `falaise` + planificateur
`game/scripts/maps/construction/procedural_rock_wall.gd`).

## 2. Livré

| Fichier | Rôle |
|---|---|
| `tools/blender/build_tripo_rocks.py` | pipeline Blender headless complet (import → pivot → palette → budget → export → vignettes → manifeste → rapport) |
| `tools/blender/render_tripo_rocks_review.py` | rendus de revue avant/après + comparaison d'échelle avec le kit |
| `game/assets/objects3d/terrain/bloc_rocheux_{socle,bloc,coin,couronne}.glb` | les 4 assets livrés (textures embarquées) |
| `game/assets/objects3d/terrain/bloc_rocheux_*_thumb.png` | vignettes 512×512 fond transparent |
| `game/assets/objects3d/manifest.json` | 4 entrées `terrain` ajoutées (89 assets au total) |
| `game/assets/objects3d/README.md` | section « Rochers Tripo3D — usage décoratif » + catalogue |
| `game/scripts/tests/rock_kit_library_test.gd` | test étendu : liste, vignette, chargement, pivot, budget, vertex colors |
| `artifacts/tripo-review/rock-kit/build_report.json` | mesures machine de chaque asset |
| `artifacts/tripo-review/rock-kit/renders_final/*.png` | captures de contrôle avant/après |
| `docs/RAPPORT_TRIPO_ROCKS.md` | ce rapport |

## 3. Pipeline (Blender 4.5.10 LTS headless)

Commande :

```powershell
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/build_tripo_rocks.py
```

Étapes par asset :

1. **Import** du GLB déjà recoloré (`artifacts/tripo-review/rock-kit/recolored_1024/`,
   textures 1024, ~0,4–1 Mo) ; fusion des meshes en un objet unique.
2. **Budget** : `DECIMATE` (COLLAPSE, triangulé) uniquement si le mesh dépasse
   **1 500 triangles**. Les 4 sources Tripo en comptent 973 à 1 036 : la
   décimation est donc **sautée** (le rapport indique
   `"decimated": false`), mais le garde-fou est actif pour une future
   génération plus dense. Budget final mesuré : **973 à 1 036 tris**.
3. **Échelle + orientation** : échelle uniforme pour une emprise de 1,75 à
   2,05 cases (cohérente avec `gros_rocher` 2,12 et `falaise` 2,32), rotation
   appliquée autour de Z, face avant vers **+Z** (convention glTF/Godot),
   transforms neutres.
4. **Pivot** : origine au **centre de la base** (`min_z = 0`, X/Y centrés),
   contrôlé par le script (`verify_asset`) puis par `verify_glb.py`.
5. **Palette Valbois** : l'albédo recoloré est désaturé (0,92), remonté
   (+26 %) et teinté chaud (`(1,08 ; 1,00 ; 0,88)` en sRGB) ; la normale Tripo
   est conservée ; l'ORM photographique est abandonné. Matériau **mat**
   (`metallic 0`, `roughness 0,92`, `specular 0,15`), `doubleSided: false`,
   alpha opaque.
6. **Vertex colors** : `COLOR_0` = AO (0,5) + mottling (0,07) + teinte de
   mousse éparse sur les faces tournées vers le ciel (`MOSS_STRENGTH 0,52`),
   même multiplie-color que le kit.
7. **Ombrage facetté** (`use_smooth = false`, normales personnalisées Tripo
   effacées) pour coller au low-poly du kit ; option `--smooth` pour l'ombre
   lissée.
8. **Textures** : albédo et normale redimensionnés à **512** et réencodés en
   **JPEG qualité 88**, embarqués dans le GLB (asset autonome, aucune texture
   externe, aucune transparence).
9. **Export GLB** (Y-up, sans caméra ni lumière, `COLOR_0` exporté), puis
   **vignette** 512×512 fond transparent avec le pipeline studio du projet
   (`oq_common.render_thumbnail`, preview vertex colors activé après export).
10. **Manifeste** : fusion des entrées dans `manifest.json`, tri
    catégorie/nom, reste du catalogue préservé. **Rapport JSON** de mesures
    écrit dans `artifacts/tripo-review/rock-kit/build_report.json`.

## 4. Avant / après (mesures)

| Asset | Source | Tris source → livré | Poids source → livré | Dimensions sources (cases) | Dimensions livrées (cases) | Vignette |
|---|---|---|---|---|---|---|
| `bloc_rocheux_socle` | `rocher_socle` | 1 014 → **1 014** | 379 → **164 Ko** (−57 %) | 0,90 × 1,00 × 0,54 | **1,86 × 2,05 × 1,11** | 165 Ko |
| `bloc_rocheux_bloc` | `rocher_bloc` | 973 → **973** | 652 → **183 Ko** (−72 %) | 0,88 × 1,00 × 0,32 | **1,71 × 1,95 × 0,63** | 152 Ko |
| `bloc_rocheux_coin` | `rocher_coin` | 1 028 → **1 028** | 1 001 → **230 Ko** (−77 %) | 0,83 × 1,00 × 0,81 | **1,46 × 1,75 × 1,41** | 170 Ko |
| `bloc_rocheux_couronne` | `rocher_couronne` | 1 036 → **1 036** | 708 → **184 Ko** (−74 %) | 0,76 × 1,00 × 0,23 | **1,53 × 2,00 × 0,47** | 144 Ko |

Total : **2,68 Mo → 761 Ko** de GLB (−72 %), 4 051 triangles au total,
maximum 1 036 par asset. Les sources pesaient lourd à cause des trois
textures 1024 (albédo, ORM, normale) ; les livraisons n'embarquent plus que
deux JPEG 512, sans ORM.

Avant/après visuels (rendus Blender, même éclairage, même cadrage, sources à
l'échelle d'arrivée) :

| Capture | Contenu |
|---|---|
| [01_avant_rochers_bruts.png](../artifacts/tripo-review/rock-kit/renders_final/01_avant_rochers_bruts.png) | GLB recolorés bruts : pierre froide sans AO, sans mousse, pivot centré sur le volume |
| [02_apres_rochers_livres.png](../artifacts/tripo-review/rock-kit/renders_final/02_apres_rochers_livres.png) | assets livrés : palette chaude, AO/mousse, facettes low-poly, posés au sol |
| [03_apres_echelle_kit.png](../artifacts/tripo-review/rock-kit/renders_final/03_apres_echelle_kit.png) | comparaison d'échelle avec `gros_rocher`, `falaise`, `galets_de_rive` et les `caillou_*` |
| [04_apres_affleurement.png](../artifacts/tripo-review/rock-kit/renders_final/04_apres_affleurement.png) | mise en scène décorative (4 rochers + cailloux) |

Les rendus de revue d'origine restent disponibles dans
`artifacts/tripo-review/rock-kit/renders/` et `renders_1024/`, et les vignettes
livrées dans `game/assets/objects3d/terrain/`.

## 5. Choix et compromis

- **Pas de coque d'encre** (`*_outline`) : le budget renforcé (< 1 500 tris)
  ne permet pas de doubler le maillage. Les rochers sont donc sans trait
  d'encrage, contrairement aux assets du kit Valbois. Si l'encrage devient
  indispensable, il faudra soit relever le budget, soit passer par un contour
  shader côté moteur.
- **Textures conservées** : malgré le style « aplats » du kit, garder l'albédo
  et la normale Tripo préserve le modelé sculpté (fissures, strates) ; le
  matériau mat, l'AO vertex color et la palette chaude les fondent dans le
  décor. Les textures sont **dans le GLB** : pas de fichier annexe.
- **Mousse et teinte** appliquées en vertex colors (pas de seconde texture) :
  un seul matériau, pas de transparence, aucun surcoût de poids.
- **Non empilables** : les faces supérieures sont utilisables comme support
  de décor (dalle), mais l'assemblage en mur reste réservé au kit du projet.
  `procedural_rock_wall.gd` n'a pas été modifié.
- **Échelle** : ~2 cases d'emprise, hauteur 0,47 à 1,41 case. Les rochers sont
  des **affleurements** : ils affleurent du sol, avec une silhouette basse
  (couronne, bloc) ou en arête (coin).

## 6. Usage dans le jeu / l'éditeur

- Les 4 GLB sont scannés automatiquement par `MapAssetLibrary.list_object3d_assets()`
  (catégorie `terrain`, vignette `<nom>_thumb.png`). Ils apparaissent dans la
  palette 3D de l'éditeur sous les noms « Bloc rocheux socle », « … bloc »,
  « … coin », « … couronne ».
- Pose : outil **Objet 3D** (`Q`), clic sur la carte ; origine au pied, ils se
  posent directement sur le terrain (`position.y` = sol). Rotation et échelle
  sont libres dans l'éditeur ; l'échelle naturelle est `1.0` (≈ 2 cases).
- Pour distinguer du kit empilable : les `bloc_rocheux_*` sont dans
  `terrain/` avec les tags `rocher`, `affleurement`, `decor`, `tripo` (pas de
  `mousse`/`relief` du kit), n'ont pas de `*_outline` visible, et leur
  description/`manifest.json` indique « non empilable ». Les composer avec les
  `caillou_*` au pied et le kit `rocher`/`gros_rocher`/`falaise` pour varier.
- `get_object3d_meta()` renvoie pour chacun : `anchor: "base"`,
  `dimensions_cells`, `height_above_floor`, `triangles`, `vertices`,
  `source_glb`, `source_service`, `generator`.

## 7. Vérifications (preuves)

```text
# test Godot headless
& $godot --headless --path game --script res://scripts/tests/rock_kit_library_test.gd
rock_kit_library_test:PASS

# contrôle GLB + vignettes + pivot + budget (Blender)
blender --background --python-exit-code 1 --python tools/blender/verify_glb.py -- `
    --only bloc_rocheux_socle bloc_rocheux_bloc bloc_rocheux_coin bloc_rocheux_couronne
[OK] terrain/bloc_rocheux_bloc.glb     verts=2919 tris=973  dims=1.71 x 1.95 x 0.63 anchor=base outline=non thumb=512px
[OK] terrain/bloc_rocheux_coin.glb     verts=3076 tris=1028 dims=1.46 x 1.75 x 1.41 anchor=base outline=non thumb=512px
[OK] terrain/bloc_rocheux_couronne.glb verts=3108 tris=1036 dims=1.53 x 2.00 x 0.47 anchor=base outline=non thumb=512px
[OK] terrain/bloc_rocheux_socle.glb    verts=3036 tris=1014 dims=1.86 x 2.05 x 1.11 anchor=base outline=non thumb=512px
VERIFY_RESULT assets=4 ok=4 echecs=0 warnings=4 tris_total=4051 tris_max=1036
```

Le test vérifie en plus, pour chaque rocher : entrée `list_object3d_assets()`,
catégorie `terrain`, vignette existante, entrée `manifest.json` (ancre `base`,
`outline=false`, budget, dimensions), chargement `PackedScene`, mesh/matériau
non nuls, `COLOR_0` (AO : luminance min < 0,9 ; mousse : vert dominant),
texture d'albédo, matériau mat sans transparence, **pivot y ≈ 0** et X/Z
centrés, largeur 1,2–2,6 cases, hauteur 0,3–1,8 case, **tris < 1 500**.

```text
build_tripo_rocks.py      → TRIPO_ROCKS_RESULT ok=4 echecs=0
render_tripo_rocks_review → TRIPO_ROCKS_REVIEW:PASS (4 captures)
```

## 8. Régénérer / réutiliser

```powershell
# pipeline complet (GLB + vignettes + manifeste + rapport)
& "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" `
    --background --python-exit-code 1 `
    --python tools/blender/build_tripo_rocks.py

# itérations
... build_tripo_rocks.py -- --only bloc_rocheux_socle --no-manifest
... build_tripo_rocks.py -- --manifest-only          # réinjecte le dernier rapport
... build_tripo_rocks.py -- --smooth                 # ombrage lissé au lieu des facettes
... build_tripo_rocks.py -- --no-moss                # pierre nue

# captures de revue
blender --background --python-exit-code 1 `
    --python tools/blender/render_tripo_rocks_review.py
```

Après une régénération des GLB : `& $godot --headless --path game --import`
(réimport Godot), puis le test headless.

## 9. Limites et prochaines étapes

- Les assets n'ont pas encore été branchés dans un générateur de scène : ils
  sont disponibles dans la bibliothèque de l'éditeur et dans le manifeste. Le
  style « Cité » / les scènes génératives (task-2) peuvent les piocher comme
  rochers décoratifs (tags `affleurement`, `decor`) ; un placement scatter
  dédié (« semis de rochers ») serait la suite naturelle.
- Variantes possibles (non livrées, la mission demandait 4–6 GLB max) :
  variante « mousse » plus verte, variante teintée ardoise. Le pipeline
  expose `--no-moss` / les constantes de palette pour les produire.
- Contour encre absent (cf. §5) : à arbitrer si l'unité visuelle avec le kit
  Valbois prime sur le budget de 1 500 triangles.
- Aucun LOD nécessaire (< 1 100 tris par asset, 2 textures 512), poids GLB
  ~180 Ko en moyenne.
