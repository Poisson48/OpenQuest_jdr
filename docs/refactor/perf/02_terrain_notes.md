# 02 — Sculpture / édition 3D du terrain : diagnostic perf

> Symptôme rapporté (verbatim) : « pareil pour l'édition 3d du terrain ça rame du
> cul et j'ai pas la même chose quand je remblaye que quand je relâche la
> souris ».
>
> Périmètre : outils de relief de l'éditeur 3D (`map_complex_editor.gd`), modes
> classiques (`raise`/`lower`/`flatten`/`smooth`) **et** modes volumétriques 3D
> (`carve`/`fill`/`smooth3d`/…), chaîne document → moteur → couches
> (`map_edit_document.gd`, `complex_map_engine_3d.gd`, `map_ground_3d.gd`,
> `map_meshes_3d.gd`, `map_props_3d.gd`, `terrain_carve_field.gd`,
> `terrain_carve_chunks.gd`).
>
> Aucun fichier de prod n'a été modifié. Reproducteur : `game/scripts/debug/perf_probe_terrain.gd`.

---

## 0. TL;DR — les 4 causes réelles (chiffres mesurés)

| # | Cause | Coût mesuré | Où |
|---|-------|-------------|----|
| **1** | **Chaque tampon 3D reconstruit TOUT le pipeline de sculpture** : resérialisation intégrale de la grille `terrainSculpt` (360 k voxels), 5 champs `TerrainCarveField` neufs + 1 désérialisation dans le ground (6 désérialisations du JSON), recalcul des régions de sculpture, **rebuild de TOUS les clusters Marching Cubes (`force=true`)**, repositionnement des 114 meshes 3D. | **184–327 ms / tampon** (3–5 FPS pendant le trait) | `map_complex_editor.gd:2674-2677`, `map_edit_document.gd:1568-1575`, `terrain_carve_field.gd:851-877,929-950`, `map_ground_3d.gd:429-450`, `map_meshes_3d.gd:305-317`, `map_props_3d.gd:91-103` |
| **2** | **Le relâchement fait un « polish » pleine résolution + rattrapage complet** : la résolution Marching Cubes passe de **1 (aperçu) à 3 (final)** et **tous** les clusters sont reconstruits ; puis `refresh_terrain` reconstruit l'eau, la végétation et repositionne tout. | **release 1,06–2,04 s** (polish 0,63–0,86 s + refresh 0,47–0,52 s) | `map_ground_3d.gd:455-477,1623-1643`, `map_complex_engine_3d.gd:1741-1745,1788-1790`, `map_complex_editor.gd:2788-2792` |
| **3** | **Les modes classiques (`Monter/Baisser/Aplatir/Lisser`) refont un `_apply_config()` COMPLET à chaque événement souris** : maillage heightfield entier + AO de cuvettes + champ de creusement neuf + matières + jupe de falaise + repositionnement. Pire : si une sculpture 3D existe, le chemin incrémental est **court-circuité** (il exige `terrainCarves` non vide) et chaque tampon rebâtit en plus **tous les clusters MC**. | **110–130 ms/tampon** à froid ; **274–283 ms/tampon** dès qu'une sculpture existe | `map_ground_3d.gd:336-359` (surtout **348**), `:618-674`, `:1301-1398` |
| **4** | **Grille de sculpture surdimensionnée et scannée intégralement** : `88×64×64 = 360 448` voxels pour une carte 44×32 (`SCULPT_RES=2`, 64 couches Y). `get_sculpt()` et `sculpt_regions()` **scannent toute la grille à chaque tampon**, et le champ est resérialisé 1 fois puis désérialisé 6 fois par tampon (dont 5 champs neufs). | `get_sculpt()` 46–55 ms, `sculpt_regions()` 22–27 ms, `TerrainCarveField.new()` 16–19 ms ×5 | `terrain_carve_field.gd:75-89,233-242,851-877,881-916,929-950` |

**Hypothèse du brief infirmée** : `_on_doc_changed` **n'appelle PAS `_sync_engine()`** pour le motif `"terrain"` (`map_complex_editor.gd:4438` ne contient pas `"terrain"`), et la trace moteur le prouve : **0 appel `_sync_engine` pendant tous les traits mesurés** (compteur `SYNC_BEFORE` incrémenté 0 fois), alors qu'un `_sync_engine()` complet coûte **1,62–1,83 s** — soit 5 à 15× le coût d'un tampon. Le rebuild global n'est donc pas le coupable pendant le drag : ce sont les rebuilds **ciblés mais mal découpés** décrits ci-dessus.

---

## 1. Chemin d'appel exact d'un tampon

### 1.1 Press / move / release

| Événement | Code | Ce qui se passe |
|---|---|---|
| press | `map_editor_edit_ops.gd:139-143` | `_press_mode="relief"`, `doc.begin_transaction()`, `_paint_relief(grid, mods)` |
| move | `map_editor_edit_ops.gd:403-404` | `_paint_relief(grid, mods)` **à chaque événement souris**, sans throttle par frame |
| release | `map_editor_edit_ops.gd:475-488` | `doc.commit_transaction()` puis `_finish_carve_stroke()` |

### 1.2 Deux familles de modes, deux chemins

`_paint_relief` (`map_complex_editor.gd:2579`) aiguille :

```gdscript
# map_complex_editor.gd:2582-2588
if _relief_mode in ["carve", "fill", "smooth3d", ..., "cloth3d"] \
        or bool(mods.get("shift", false)):
    _paint_carve(grid, mods)
    return
doc.paint_terrain_brush(grid, _relief_radius, _relief_strength, _relief_mode, "Relief")
```

**Famille A — modes classiques** (`raise`, `lower`, `flatten`, `smooth`, défaut `raise` :
`map_complex_editor.gd:81`) :

```
_on_pointer_moved
└─ _paint_relief                              map_complex_editor.gd:2579
   ├─ doc.paint_terrain_brush()               map_edit_document.gd:1213  (boucle cases du brush)
   │  └─ _push_delta() + changed.emit("terrain")   :1256-1257
   ├─ engine.set_terrain_carve_preview(true)  :2592  (gèle eau/végétation/caméra)
   └─ engine.refresh_terrain(doc.map_data)    :2594-2595
      └─ complex_map_engine_3d.refresh_terrain :1753
         ├─ _sync_terrain_from_map()          :1756  → TerrainCarveField.new() (champ neuf)
         ├─ ground.set_terrain_heights()      :1771
         │  └─ map_ground_3d.set_terrain_heights :336
         │     └─ si pas de terrainCarves : _apply_config() COMPLET  :359 / :618
         │        ├─ TerrainCarveField.new()                 :651
         │        ├─ sculpt_regions() + compute_clusters()   :653-655
         │        ├─ _make_terrain_mesh()                    :656  (heightfield entier)
         │        ├─ _update_splat_texture() / _apply_terrain_material()  :659-661
         │        ├─ _rebuild_object_occlusion()             :664-665
         │        ├─ _rebuild_carve_meshes()                 :672  (TOUS les clusters MC)
         │        └─ _rebuild_cliff()                        :673
         ├─ ground.set_terrain_carves()/set_terrain_sculpt() :1772-1775 (early-out si inchangé)
         ├─ _load_backdrop() / _load_ambient_fx()            :1779-1781
         ├─ _load_water() / _load_vegetation()  SI preview=false :1788-1790
         ├─ props/meshes layers set_terrain_*()              :1796-1813
         └─ tokens + _ensure_camera_above_terrain()          :1814-1824
```

**Famille B — modes volumétriques 3D** (`carve`, `fill`, …) :

```
_on_pointer_moved
└─ _paint_relief → _paint_carve               map_complex_editor.gd:2605
   ├─ throttle d'espacement                   :2606-2609  (max(0.25, rayon*0.35) cases)
   ├─ _carve_hit(grid)                        :2770      (raycast moteur, ~0,01 ms)
   ├─ pour chaque point de symétrie : _sculpt_op_at()  :2623-2627 / :2701
   │  └─ doc.sculpt_stamp() (ou sculpt_smooth/flatten/…)   map_edit_document.gd:1559
   │     ├─ field.sculpt_stamp()              terrain_carve_field.gd:317  (écrit ~1 600 voxels)
   │     ├─ map_data["terrainSculpt"] = field.get_sculpt()   :1568
   │     │  └─ SCAN INTÉGRAL de la grille + sérialisation     :851-877
   │     ├─ _push_delta({before/after voxels})                :1569-1575
   │     └─ changed.emit("terrain")                           :1575
   ├─ engine.set_terrain_carve_preview(true)  :2674
   └─ engine.refresh_terrain(doc.map_data)    :2676-2677
      ├─ _sync_terrain_from_map()             :1756  → TerrainCarveField.new() (désérialise TOUT le sculpt)
      ├─ ground.set_terrain_sculpt(dict, preview)  :1774
      │  └─ map_ground_3d.set_terrain_sculpt :429
      │     ├─ _carve_field.set_sculpt(dict)  :441  (désérialise TOUT le sculpt)
      │     ├─ sculpt_regions()               :442  (SCAN INTÉGRAL)
      │     ├─ compute_clusters()             :443-444
      │     ├─ _rebuild_dirty_carve_meshes(cell, **force=true**)  :446  ← TOUS les clusters
      │     └─ _carve_cut_mask() (+ _make_terrain_mesh si le masque change)  :447-450
      ├─ _load_water()/... SI preview=false   :1788-1790
      └─ props/meshes/tokens : set_terrain_carves() + set_terrain_sculpt()
         → CHACUN reconstruit un TerrainCarveField complet
            map_meshes_3d.gd:305-317, map_props_3d.gd:91-103
```

**Conséquence comptable, par tampon 3D** : le champ de sculpture est
**sérialisé 1×** (document), puis **désérialisé 6× / construit 5×** (moteur
`_sync_terrain_from_map`, ground `set_terrain_sculpt`, meshes `set_terrain_carves`
+ `set_terrain_sculpt`, props idem) et **scanné 3×** (2× `sculpt_regions`,
1× `get_sculpt`). Le tout pour un brush qui n'a touché qu'une vingtaine de
colonnes.

---

## 2. Mesures (chiffres réels)

### 2.1 Protocole

- Commande : `godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://scripts/debug/perf_probe_terrain.gd`
- Sonde : `game/scripts/debug/perf_probe_terrain.gd` (fichier neuf, aucune modif de prod).
- Carte : « Cité au fil de l'eau » (`game/scripts/debug/cite_eau_boot.gd`) — **44×32**, `groundMode=terrain3d`, **114 meshes 3D** posés, 2 bassins d'eau, `terrainDetail=1`, **1 485 vertices** de heightfield. Grille de sculpture **88×64×64 = 360 448 voxels**.
- Traits simulés via les vrais handlers (`_on_pointer_pressed/moved/released`), écran calculé par `engine.grid_to_screen()` pour que `_carve_hit` raycaste réellement le long du trait.
- Compteurs : `changed.emit("terrain")` via `doc.changed` ; `_sync_engine()` via la trace moteur (`SYNC_BEFORE`, redirigée vers `user://`) ; rebuilds du maillage sol via l'identité de l'`ArrayMesh` ; clusters/vertices via les nœuds MC.
- Environnement : 3 autres instances Godot d'autres coéquipiers tournaient pendant les mesures (12 vCPU) → **valeurs absolues ±20–30 %**, mais deux runs indépendants donnent des chiffres à ±15 % et les comparaisons relatives sont stables.

### 2.2 Coût de référence (rebuild global)

| Mesure | Run 1 | Run 2 |
|---|---|---|
| `_sync_engine()` complet | **1 699–1 749 ms** | **1 619–1 743 ms** |

C'est le coût du rebuild complet (couches 3D + 114 meshes HD + eau + caméra). Il
**n'est pas** exécuté pendant un trait : la trace compte **0 `_sync_engine`** sur
tous les traits. Le drag n'est donc pas « un `_sync_engine` par tampon », mais des
rebuilds partiels répétés qui coûtent quand même 0,18–0,32 s chacun.

### 2.3 Coût par tampon et par release (familles de modes)

| Trait (12–14 événements souris) | ms / tampon | pire tampon | release | remarque |
|---|---|---|---|---|
| `raise` classique, carte **neuve** (sans sculpture) | **110–130** | 137–162 | 74–87 ms | **12/12** événements rebâtissent le maillage sol entier |
| `fill` (« Remblayer 3D »), **état froid** | **184–210** | 229–261 | **1 091–1 307 ms** | 15 tampons réels |
| `fill`, **état chaud** (clusters déjà présents) | **226–260** | 263–306 | **1 635–1 894 ms** | +20 % vs froid : le cluster fusionné grossit |
| `raise` classique **sur carte déjà sculptée** | **274–283** | 293–317 | **1 840–2 047 ms** | 8/8 événements refont `_apply_config()` complet |
| `carve` (« Creuser 3D ») | **291–327** | 329–345 | polish 602–671 + refresh 449–519 + commit 0,9–1,5 + résiduel 137–151 ≈ **1,2–1,3 s** | |
| `smooth3d` (« Lisser 3D ») | **279–301** | 310–343 | **1 043–1 078 ms** | |

**Interprétation** : à 110–330 ms par événement souris, on est à **3–9 FPS**
pendant un trait — d'où le « ça rame du cul ». Et chaque relâchement ajoute
**1 à 2 secondes** de gel.

### 2.4 Décomposition du coût d'un tampon 3D (micro-benchmarks)

Relevés sur l'état sculpté (2 clusters MC, résolution finale) — moyennes de 2 runs,
une seule exécution par opération quand elle mute l'état :

| Étape d'un tampon 3D | ms |
|---|---|
| `doc.sculpt_stamp()` seul (brush + `get_sculpt()` + `_push_delta`) | 40–49 |
| dont `field.get_sculpt()` — scan+sérialisation de la grille entière | **46–55** |
| `field.sculpt_regions()` — scan des 128 chunks | **26–27** |
| `TerrainCarveField.new(heights, carves, sculpt)` (1 des 5) | 17–19 |
| `TerrainCarveChunks.compute_clusters()` | **24–29** |
| `engine._sync_terrain_from_map()` (relit `map_data`, champ neuf) | 17–20 |
| `ground.set_terrain_sculpt()` (désérialise + clusters + masque) | 14,8–17,9 |
| `meshes_layer.set_terrain_sculpt()` (+ repositionnement 114 meshes) | 27–31 |
| `meshes_layer.set_terrain_carves()` (champ neuf même si inchangé) | 26–33 |
| `meshes_layer.set_terrain_heights()` | 13–17 |
| `props_layer.set_terrain_sculpt()` | 19–21 |
| `_load_water()` | 16–20 |
| `_load_backdrop()` / `_load_ambient_fx()` | 0,01 |
| `_raycast_ground()` (visée du curseur) | 0,01 |
| `_on_doc_changed("terrain")` seul (overlay + layout signal) | **0,00** |
| **`_rebuild_dirty_carve_meshes(cell, force=true)` en résolution FINALE** | **641–700** |
| **`ground.set_terrain_heights()` classique (1 case changée, avec clusters)** | **671–754** |
| **`ground._apply_config()` COMPLET** | **708** |
| `_make_terrain_mesh()` (1 485 vertices) | 36–46 |
| dont `_compute_cavity_ao()` | 12,4 |
| `_update_splat_texture()` / `_rebuild_cliff()` | 2,1 / 8,1 |
| `set_terrain_carve_preview(false)` = **polish release** | **855–956** |

Ordre de grandeur : sur ~200–300 ms de tampon 3D, on retrouve
~46-55 (sérialisation) + ~27 (régions) + ~17-20 (champ neuf) + ~24-29 (clusters)
+ ~15 (set_terrain_sculpt) + ~27-31 + ~26-33 + ~13-17 (calques meshes) +
~19-21 (props) + ~40 (brush) ≈ **250–320 ms**. Le pipeline se recoupe.

### 2.5 Effet du détail du maillage heightfield (facteur d'aggravation)

`map_ground_3d.gd:_make_terrain_mesh` (ligne 1301) reconstruit **tout** le
heightfield en GDScript à chaque appel (`O(w·h·detail²)`), AO de cuvettes incluse :

| `detail` | vertices | `_make_terrain_mesh()` |
|---|---|---|
| 1 | 1 485 | 36–40 ms |
| 2 | 5 785 | 105–108 ms |
| 3 | 12 901 | 232 ms |
| 4 | 22 833 | 357–414 ms |

La carte de test est en `detail=1` : **sur une carte 100×100 en détail 2, un seul
tampon classique coûtera ≈ 0,4–0,5 s** rien que pour le heightfield, et la
sérialisation sculpture (§2.4) passe de 360 k à ≈ 2,56 M voxels (×7).

### 2.6 Écart visuel drag → release (le « pas la même chose »)

| Trait | Résolution MC pendant le drag | après release | Vertices MC pendant le drag → final | Triangles |
|---|---|---|---|---|
| `fill` froid | `res=1` | `res=3` | **1 159 → 5 516 (×4,8)** | 1 109 → 8 958 |
| `fill` chaud | `res=1` | `res=3` | **1 685 → 8 165 (×4,8)** | 1 649 → 13 487 |
| `raise` sur carte sculptée | `res=1` | `res=3` | **1 802 → 9 342 (×5,2)** | 1 834 → 15 459 |
| `carve` | `res=1` | `res=3` | **2 354 → 6 663 (×2,8)** | 2 741 → 10 704 |
| `smooth3d` | `res=1` | `res=2` (aire > 400) | **2 362 → 6 681 (×2,8)** | 2 752 → 10 752 |

La géométrie de la surface **change littéralement** au relâchement : pendant le
trait on rend une polygonisation grossière (résolution 1 = un échantillon de
champ par case), au release une polygonisation 3× plus fine. Ce n'est pas un
simple « plus joli » : les parois, crêtes et silhouettes se déplacent
visiblement. C'est **la** réponse au « j'ai pas la même chose quand je relâche ».

---

## 3. Causes détaillées, preuves et extraits

### Cause 1 — Le tampon 3D resérialise et reconstruit tout (dominant pendant le drag)

**(a) `map_data["terrainSculpt"]` est re-sérialisé intégralement à CHAQUE tampon**

```gdscript
# game/scripts/maps/editor/map_edit_document.gd:1559-1575
func sculpt_stamp(center: Vector3, radius: float, strength: float, ...) -> void:
    var field := _sculpt_support()
    var delta: Array = field.sculpt_stamp(center, radius, strength, kernel, angle, falloff, smooth_after)
    if delta.is_empty():
        return
    map_data["terrainSculpt"] = field.get_sculpt()      # ← scan + sérialisation de TOUTE la grille
    _push_delta({ ..., "before": {"mode": "voxels", "values": delta[0]}, ... })
    changed.emit("terrain")
```

`get_sculpt()` parcourt **tous** les chunks 8³ de la grille (`gx*gy*gz`) et, pour
chaque chunk, fait un premier passage `_chunk_nonzero()` (512 lectures) puis un
second pour encoder en int8 localement :

```gdscript
# game/scripts/maps/terrain/terrain_carve_field.gd:851-877
func get_sculpt() -> Dictionary:
    ...
    for cz in range(gz):
        for cy in range(gy):
            for cx in range(gx):
                if not _chunk_nonzero(cx, cy, cz):      # 512 lectures par chunk
                    continue
                ...
                for z ... for y ... for x ...
                    data.append(clampi(int(roundf(_sculpt[row + x] / scale * 127.0)), -127, 127))
```

Coût mesuré : **46–55 ms** par tampon, pour un brush de 1,2 case. Et il **croît
linéairement avec la taille de la carte**, pas avec le brush : sur 100×100
(2,56 M voxels) → ~0,35 s par tampon pour cette seule étape.

**(b) `_sync_terrain_from_map()` reconstruit un `TerrainCarveField` neuf (donc désérialise tout le sculpt)**

```gdscript
# game/scripts/maps/complex_map_engine_3d.gd:1612-1631
func _sync_terrain_from_map() -> void:
    ...
    _terrain_sculpt = map_data.get("terrainSculpt", {}) ...
    _terrain_field = TerrainCarveField.new(
        _terrain_heights, _terrain_w, _terrain_h, _terrain_carves, _terrain_sculpt)   # ← 17-20 ms
```

`_init` → `set_data()` → `_rebuild_vertex_cache()` (`O(w·h)`) + `set_carves()`
(scan des hauteurs) + `set_sculpt()` (boucle sur tous les chunks non nuls) :

```gdscript
# game/scripts/maps/terrain/terrain_carve_field.gd:215-226
func _init(heights, map_w, map_h, carves, sculpt) -> void:
    set_data(heights, map_w, map_h, carves)
    if sculpt is Dictionary and not (sculpt as Dictionary).is_empty():
        set_sculpt(sculpt)

func set_data(...) -> void:
    _heights = heights ; _w = map_w ; _h = map_h
    _rebuild_vertex_cache()          # 956-964 : (w+3)*(h+3) vertex_height()
    set_carves(carves)               # 967+ : scan de toutes les hauteurs
```

**(c) Les calques 3D reconstruisent CHACUN leur champ complet à chaque tampon**

```gdscript
# game/scripts/maps/map_layers/map_meshes_3d.gd:305-317
func set_terrain_carves(carves: Array) -> void:
    _terrain_carves = TerrainCarveField.normalize_carves(carves)
    _terrain_field = TerrainCarveField.new(
        _terrain_heights, _terrain_w, _terrain_h, _terrain_carves, _terrain_sculpt)
    _reseat_nodes()

func set_terrain_sculpt(sculpt: Dictionary) -> void:
    _terrain_sculpt = sculpt if sculpt is Dictionary else {}
    _terrain_field = TerrainCarveField.new(
        _terrain_heights, _terrain_w, _terrain_h, _terrain_carves, _terrain_sculpt)
    _reseat_nodes()
```

Idem `game/scripts/maps/map_layers/map_props_3d.gd:91-103`. Et
`complex_map_engine_3d.gd:1796-1813` appelle ces 3 setters pour **meshes** et
**props**, plus `_token_nodes` : soit **5 champs neufs + 1 désérialisation ground** et **2
repositionnements complets de 114 meshes** par tampon, alors que seuls les objets dont
l'empreinte touche le brush devraient bouger.

**(d) Le ground rebâtit TOUS les clusters MC (`force=true`) à chaque tampon**

```gdscript
# game/scripts/maps/map_layers/map_ground_3d.gd:429-450
func set_terrain_sculpt(sculpt: Dictionary, preview: bool = false) -> void:
    ...
    if str(_terrain_sculpt) == str(next):      # comparaison de DEUX dicts sérialisés
        return
    ...
    _carve_field.set_sculpt(next)              # désérialise tout
    var regions: Array = _carve_field.sculpt_regions()      # scan intégral (26-27 ms)
    _carve_clusters = ... TerrainCarveChunks.compute_clusters(_terrain_carves, regions)  # 24-29 ms
    _rebuild_dirty_carve_meshes(cell_size, true)   # ← force = TOUS les clusters reconstruits
    var mask := _carve_cut_mask()
    if not _byte_arrays_equal(mask, _last_cut_mask):
        _last_cut_mask = mask
        _mesh_instance.mesh = _make_terrain_mesh(cell_size)   # 36-46 ms
```

`force=true` est nécessaire parce que la **clé** d'un cluster
(`map_ground_3d.gd:1646-1649` : emprise + ids) ne change pas quand seul le
**contenu** du champ change ; sans `force`, `_rebuild_dirty_carve_meshes`
(`:1623-1643`) considérerait les clusters comme propres. Il n'existe donc aucun
moyen actuel de ne rebâtir que les clusters réellement touchés — d'où le
`force=true` systématique.

**(e) Fusion des clusters → un seul gros cluster qui grossit**

`TerrainCarveChunks.compute_clusters` (`terrain_carve_chunks.gd:52-101`) fusionne
itérativement toutes les emprises qui se recouvrent (marge 0,25 case, `:66-73` +
boucle `while merged` `:75-86`). Un trait continu avec brush 1,2 case crée des
régions toutes adjacentes → **un seul cluster** couvrant tout le trait. Comme ce
cluster est reconstruit **entier** à chaque tampon, le coût par tampon croît avec
la longueur du trait : mesuré **+20 % entre le 1er trait (184–210 ms) et un trait
dans une zone déjà sculptée (226–260 ms)**, et le release croît encore plus
(1,09 s → 1,63 s). `compute_clusters` lui-même est O(n²) dans sa boucle de fusion
(peu visible ici, mais latent sur une carte riche en creusements).

### Cause 2 — Le release : polish pleine résolution + rattrapage global

```gdscript
# game/scripts/maps/map_complex_editor.gd:2788-2792
func _finish_carve_stroke() -> void:
    if _engine != null and _engine.has_method("set_terrain_carve_preview"):
        _engine.call("set_terrain_carve_preview", false)   # ← POLISH
    if _engine != null and _engine.has_method("refresh_terrain"):
        _engine.call("refresh_terrain", doc.map_data)      # ← rebuild eau/végétation/layers
```

```gdscript
# game/scripts/maps/map_layers/map_ground_3d.gd:455-461
func set_terrain_carve_preview(on: bool) -> void:
    if on == _carve_preview:
        return
    _carve_preview = on
    if _carve_clusters.is_empty() or not is_terrain3d():
        return
    _rebuild_dirty_carve_meshes(float(_cfg.get("cell_size", 1.0)), true)   # force = tous
```

La résolution dépend du flag preview :

```gdscript
# game/scripts/maps/map_layers/map_ground_3d.gd:467-477
func _carve_resolution_for(cluster: Dictionary) -> int:
    var area := rect.size.x * rect.size.y
    if _carve_preview:
        return 2 if area <= 40 else 1        # aperçu : très grossier
    if area > 400:
        return 2
    return maxi(3, _terrain_detail)          # final : 3 (ou plus)
```

Chaque cluster est un maillage Marching Cubes échantillonné en
`nx × ny × nz × res³` :

```gdscript
# game/scripts/maps/terrain/terrain_carve_chunks.gd:157-176
var nx := rect.size.x * res
var nz := rect.size.y * res
var ny := maxi(1, int(ceil((y1 - y0) * float(res))))
...
for iz ... for iy ... for ix in range(gx_count):
    values[row + ix] = field.sample(Vector3(...))     # res³ échantillons de SDF
```

→ passer de `res=1` à `res=3`, c'est **×27 échantillons de champ** et un nombre de
triangles ×2,8 à ×5,2. Mesuré : **polish 632–956 ms**.

Puis `refresh_terrain` fait le rattrapage que le preview avait volontairement
gelé :

```gdscript
# game/scripts/maps/complex_map_engine_3d.gd:1782-1790
# Pendant un trait de creusement (qualité d'aperçu), ces calques ne sont
# PAS reconstruits à chaque tampon (rebuilds complets coûteux) : ils sont
# rattrapés au polissage de la relâche...
if not _terrain_carve_preview:
    _load_water()
    _load_vegetation()
```

`_load_water()` mesure 16–20 ms sur cette carte **mais** il reconstruit aussi les
textures de berge et la carte d'eau du terrain (`complex_map_engine_3d.gd:1504-1514`)
→ c'est ce qui fait « sauter » la ligne de rive au relâchement. Pour la caméra :
`_ensure_camera_above_terrain()` est gelé pendant le preview (`:1833`), donc elle
peut se retrouver sous le terrain sculpté jusqu'au release.

Coût total du release mesuré : **1,06–2,04 s**, dont ~0,63–0,96 s de polish,
~0,47–0,52 s de `refresh_terrain`, **1,1–1,5 ms** de `commit_transaction`
(la transaction n'est PAS le problème) et ~0,14 s de résiduel.

### Cause 3 — Modes classiques : `_apply_config()` complet à chaque événement

```gdscript
# game/scripts/maps/map_layers/map_ground_3d.gd:336-359
func set_terrain_heights(heights: Array) -> void:
    ...
    if _arrays_equal(_terrain_heights, next):      # 336-343 : early-out si rien ne change
        return
    # Chemin incrémental (terrain3d avec creusements) ...
    if is_terrain3d() and _carve_field != null and not _terrain_carves.is_empty():   # ← ligne 348
        var changed := _changed_height_rect(_terrain_heights, next)
        ...
        _mesh_instance.mesh = _make_terrain_mesh(cell_size)          # encore tout le mesh !
        _rebuild_clusters_in_rect(changed, cell_size)                # incrémental, LUI
        _rebuild_cliff(cell_size, ...)
        return
    _apply_config()                                    # ← sinon : rebuild total (ligne 359)
```

Deux problèmes :

1. La condition incrémentale (`:348`) exige **`terrainCarves` non vide**. Une carte
   simplement sculptée (sculpt sans carve) ou juste bombée prend donc le chemin
   **complet** `_apply_config()` (`:618-674`) : champ neuf, `sculpt_regions`,
   `compute_clusters`, `_make_terrain_mesh` (36–46 ms ici, 350 ms à detail 4),
   splat, matières, AO d'objets, **`_rebuild_carve_meshes()` de tous les clusters
   MC**, jupe de falaise, repositionnement.
2. Même le chemin incrémental existant refait `_make_terrain_mesh()` **entier**
   (`:355`) : seul le rebuild des clusters est régional, pas le heightfield.

Mesures : **110–130 ms/tampon** sur carte neuve ; **274–283 ms/tampon** dès
qu'une sculpture 3D existe (les clusters MC sont alors rebâtis à chaque tampon) ;
release correspondant **1,84–2,04 s**. `_compute_cavity_ao()` (12,4 ms) est
recalculée à chaque `_make_terrain_mesh()` alors qu'elle ne dépend que du
heightfield.

### Cause 4 — Grille de sculpture surdimensionnée (facteur d'échelle)

```gdscript
# game/scripts/maps/terrain/terrain_carve_field.gd:75-89
const SCULPT_RES := 2
const SCULPT_Y0 := -8.0
const SCULPT_Y1 := 24.0
...
func _ensure_sculpt() -> void:            # :233-242
    var dims := Vector3i(
        maxi(1, _w * SCULPT_RES),
        maxi(1, int((SCULPT_Y1 - SCULPT_Y0) * SCULPT_RES)),   # 64 couches
        maxi(1, _h * SCULPT_RES))
```

44×32 → `88 × 64 × 64 = 360 448` voxels. `sculpt_stamp` écrit **toute la colonne
verticale** pour chaque colonne touchée (`terrain_carve_field.gd:373-378` :
`for y in range(_sculpt_dims.y)`) : ~25 colonnes × 64 = 1 600 voxels par tampon
(et jusqu'à ~40 000 pour un rayon 6). Ce n'est pas le coût dominant, mais toute
la grille est ensuite scannée plusieurs fois par tampon (`get_sculpt`,
`sculpt_regions`, désérialisations), ce qui rend le coût **indépendant de la
taille du brush** et **proportionnel à la surface de la carte** — exactement le
profil d'un « ça rame même avec un petit pinceau ».

### Causes secondaires / infirmées

- **`changed.emit("terrain")` → `_sync_engine()` : INFIRMÉ.** 1 seul
  `changed.emit("terrain")` par tampon (mesuré `1,00`), et `_on_doc_changed`
  (`map_complex_editor.gd:4427-4445`) ne liste pas `"terrain"` dans les motifs qui
  appellent `_sync_engine` (`:4438`). La trace moteur confirme **0 `_sync_engine`**
  pendant les traits. `_on_doc_changed("terrain")` coûte ~0 ms.
- **Transaction/undo : non coupable côté CPU.** `begin_transaction`/`commit_transaction`
  (`map_edit_document.gd:607-620`) sont O(1) ; mesuré 1,1–1,5 ms au release. En
  revanche la **charge mémoire** de la transaction est lourde : 1 delta par
  tampon, chaque delta de sculpture portant les voxels modifiés en `before`/`after`.
  Mesuré : `fill` = **15 deltas / 33 792 entrées** (≈ 2 253 par delta), `carve` =
  **11 deltas / 25 600 entrées**, `smooth3d` = 9 deltas / 1 008 entrées ;
  `raise` classique = 13 deltas / 176 entrées seulement. À surveiller pour les
  longs traits (mémoire undo × 120 étapes possibles), sans impact CPU mesurable.
- **`_raycast_ground` / `_carve_hit` : non coupable** (0,01 ms).
- **Quantification int8 du sculpt : négligeable.** `get_sculpt()` quantifie chaque
  chunk sur une échelle locale ; l'erreur max est de l'ordre de `max|v|/254`
  (≈ 0,002–0,005 case) → invisible. Ce n'est pas la cause du « pas la même chose ».
- **`_load_backdrop` / `_load_ambient_fx` : négligeables** (0,01 ms).

---

## 4. Explication synthétique du symptôme

**« ça rame du cul »** : un événement souris = un tampon coûtant
**184–316 ms** (modes 3D) ou **110–283 ms** (modes classiques), soit **3–9 FPS**.
Le pipeline d'un tampon n'est pas dominé par une opération unique mais par
**une douzaine d'opérations globales redondantes** (resérialiser/désérialiser/
rescanner toute la sculpture, reconstruire tous les clusters, reposer tous les
meshes, reconstruire tout le heightfield) alors que le brush ne touche qu'une
vingtaine de colonnes. Le coût augmente avec la **taille de la carte**, le
**détail du maillage** et la **longueur du trait** (clusters fusionnés + AO +
sérialisation), ce qui explique que ce soit pire sur les vraies cartes que sur
une carte de test.

**« j'ai pas la même chose quand je relâche »** — trois mécanismes cumulés :

1. **Résolution MC drag → release** : `res=1` (ou 2) pendant le trait, `res=3` au
   release → la géométrie change (×2,8 à ×5,2 de triangles) : silhouette, parois,
   crêtes se déplacent. C'est le plus visible.
2. **Calques gelés pendant le trait, rattrapés au release** : eau (+ textures de
   berge/carte d'eau) et végétation ne suivent pas le trait, la caméra non plus
   (`_ensure_camera_above_terrain` gelé) → « pop » au relâchement.
3. **Le polish n'est pas une finition, c'est un rebuild complet** : même sans
   changement de forme attendu, il reconstruit **tous** les clusters et
   `refresh_terrain` repose tous les meshes/tokens → 1–2 s de gel qui donne
   l'impression que « le résultat final n'est pas celui qu'on voyait ».

---

## 5. Correctifs proposés (effort / risque / impact)

Ordonnés par ratio impact/effort. Aucun n'a été appliqué (mission lecture seule).

### P0 — Quick wins, fort impact, faible risque

| # | Correctif | Fichier(s) | Effort | Risque | Impact attendu |
|---|---|---|---|---|---|
| P0.1 | **Sortir `get_sculpt()` du chemin chaud** : ne plus réécrire `map_data["terrainSculpt"]` à chaque tampon ; garder le champ vivant comme source de vérité et ne sérialiser qu'au `commit_transaction()` (ou via un delta `D_SCULPT` déjà présent). Les consommateurs (moteur/calques) doivent recevoir le champ ou les chunks modifiés, pas le JSON complet. | `map_edit_document.gd:1568`, `:1578-1591`, autres `sculpt_*` | 0,5–1 j | Faible (l'undo utilise déjà `delta[0]/delta[1]` voxels) | **−46 à −55 ms/tampon** (et −0,3 s et plus sur grandes cartes) |
| P0.2 | **Ne plus reconstruire un champ par calque et par tampon** : dans `refresh_terrain`, remplacer les 3 setters des calques props/meshes (+tokens) par un `apply_terrain_patch(rect)` qui ne repose que les nœuds dont l'empreinte intersecte le rect modifié. À défaut, mémoïser le `TerrainCarveField` (un seul partagé, muté en place) et ne pas appeler `set_terrain_carves()` quand les carves n'ont pas changé. | `complex_map_engine_3d.gd:1796-1821`, `map_meshes_3d.gd:305-317`, `map_props_3d.gd:91-103` | 1–2 j | Moyen (4 consommateurs, tokens) | **−70 à −110 ms/tampon** |
| P0.3 | **Rendre le polish régional** : ne rebâtir au release que les clusters touchés par le trait, et non `force=true` sur tous. Introduire une version/dirty par chunk sculpté dans la clé de cluster, ou mémoriser l'ensemble des clusters touchés pendant le trait. | `map_ground_3d.gd:455-461`, `:1623-1649`, `terrain_carve_field.gd:929-950` | 1–2 j | Faible-moyen | **−0,4 à −0,7 s** sur le release |
| P0.4 | **Lisser le hit de release** : faire le polish + `_load_water()` en `call_deferred`/sur 1–2 frames (ou en thread pour le maillage) et ne pas reposer meshes/tokens/caméra de façon synchrone dans l'événement de relâchement. | `map_complex_editor.gd:2788`, `complex_map_engine_3d.gd:1788-1824` | 0,5 j | Faible | Gel du release **1,1–2,0 s → < 100 ms** perçu (micro-freezes étalés) |

### P1 — Refonte du chemin incrémental (impact structurel)

| # | Correctif | Fichier(s) | Effort | Risque | Impact |
|---|---|---|---|---|---|
| P1.1 | **Supprimer la condition `terrainCarves` non vide** du chemin incrémental de `set_terrain_heights` et l'utiliser aussi quand seule la sculpture existe ; remplacer `_apply_config()` par une mise à jour ciblée (mesh + clusters du rect + matières + jupe). | `map_ground_3d.gd:348-359` | 1 j | Faible | Modes classiques : **274–283 → ~60–90 ms/tampon** sur carte sculptée |
| P1.2 | **Maillage heightfield incrémental** : ne reconstruire que le bloc de vertices/indices du rect modifié (l'API `ArrayMesh.surface_update_*` ou des buffers réutilisés), et ne recalculer l'AO de cuvettes que sur le rect (ou la mémoïser). | `map_ground_3d.gd:1301-1398`, `:1456-1502` | 2–4 j | Moyen-fort (normales/couleurs/cavité aux bords, tests de rendu) | Modes classiques : **110–130 → ~20–40 ms/tampon** à detail 1 ; gain ×3–8 sur cartes détaillées |
| P1.3 | **Index incrémental des chunks sculptés** : maintenir la liste des chunks non nuls à la volée (mise à jour dans `sculpt_stamp`/`_sculpt_warp_impl`), au lieu de rescanner 360 k–2,5 M voxels dans `get_sculpt()` et `sculpt_regions()`. Mémoïser le résultat de `sculpt_regions()` entre deux tampons si aucun chunk n'apparaît/disparaît. | `terrain_carve_field.gd:851-877`, `:929-950` | 1–2 j | Faible-moyen | **−70 à −80 ms/tampon** sur cette carte, bien plus sur grandes cartes |
| P1.4 | **Clé de cluster « dirty »** : inclure un compteur de version par chunk dans `_cluster_key` pour pouvoir utiliser `force=false` en toute sécurité (rebuild uniquement des clusters dont un chunk a changé) pendant le drag. | `map_ground_3d.gd:1646-1649`, `:446` | 0,5–1 j | Faible | Coût drag découplé du nombre de clusters (utile quand plusieurs zones sculptées coexistent) |

### P2 — UX / régulation et unification preview/final

| # | Correctif | Effort | Risque | Impact |
|---|---|---|---|---|
| P2.1 | **Coalescer les événements souris** : au plus 1 tampon par frame (budget temps p.ex. 16 ms) et, au release, rejouer les positions manquantes de la trace pour ne pas perdre de matière. Aujourd'hui `_on_pointer_moved` empile les tampons à la fréquence souris alors que chacun coûte 0,2–0,3 s → latence qui s'accumule. | 0,5–1 j | Faible | Cadre stable, latence maîtrisée (la vitesse brute dépend de P0/P1) |
| P2.2 | **Unifier drag/final** : que la qualité d'aperçu soit un **LOD de rendu** de la même géométrie (décimation du mesh final ou résolution fixe pendant le trait *et* après), plutôt qu'une résolution MC différente rebâtie au relâchement. Sinon le résultat change toujours au release. | 2–3 j | Moyen | Supprime la cause n°1 du « pas la même chose » |
| P2.3 | **Ne pas geler l'eau si elle est peu coûteuse** : sur cette carte `_load_water()` = 16–20 ms ; le gel systématique en preview est un choix conservateur. On peut garder le gel pour la végétation/ombre et rafraîchir l'eau à basse fréquence (1 fois / 3 tampons) ou au release en différé. | 0,5 j | Faible | Supprime le « pop » de la rive |
| P2.4 | **Réduire/paramétrer la grille de sculpture** : `SCULPT_RES=2` + 64 couches Y fixes. Adapter `SCULPT_Y0/Y1` à l'amplitude réelle de la carte (bornes -2..12 cases déjà imposées au relief) réduirait la grille de ~30 % ; à discuter avec le rendu (précision des surplombs). | 0,5–1 j | Moyen (qualité de sculpture) | −30 % sur tous les scans, linéaire en surface de carte |

---

## 6. Implications pour la refacto en cours

1. **Un seul propriétaire du champ de terrain.** Aujourd'hui le champ
   `TerrainCarveField` est reconstruit/désérialisé **6 fois par tampon** (moteur + ground +
   meshes ×2 + props ×2, cf. §2.4). La refacto doit faire du champ édité
   (dans `MapEditDocument`) l'unique source de vérité, exposée en lecture aux
   couches, avec une API de **patch régional** :
   `apply_terrain_patch(rect: Rect2i, changed_chunks: Array, version: int)`.
   Les couches (ground, props, meshes, token, water, vegetation) implémentent
   ce patch et ne reposent que ce qui intersecte le rect.
2. **Sortir la sérialisation du chemin d'édition.** `map_data["terrainSculpt"]`
   (et `terrainHeights`, `terrainCarves`) doit être un **cache de sauvegarde**,
   écrit au commit/autosave, pas à chaque mouvement souris. L'undo dispose déjà
   de deltas voxellaires (`D_SCULPT`), donc rien n'empêche cette séparation.
3. **Découpler « aperçu » et « résultat ».** Le flag `_carve_preview`
   (`map_ground_3d.gd:260,455-477`) est un commutateur **global** de qualité qui
   rebâtit tout au basculement. La refacto doit le remplacer par un LOD de rendu
   par cluster, indépendant de l'état « trait en cours », ou par une résolution
   unique. Sinon le symptôme « pas la même chose au release » reviendra.
4. **Découper les rebuilds par région, pas par type d'objet.** Les helpers
   existent déjà et sont bons : `_changed_height_rect` (`:363-375`),
   `_rebuild_clusters_in_rect` (`:379-394`), `_rebuild_dirty_carve_meshes`
   (`:1623-1643`). Le problème est qu'ils ne sont utilisés que dans la branche
   « carves non vides » et que la clé de cluster ne détecte pas les changements
   de contenu. La refacto doit généraliser **ces** primitives (dirty rect +
   dirty chunks) et supprimer les `force=true` / `_apply_config()` du chemin
   d'édition.
5. **Budget perf de référence** à conserver dans les tests : un tampon de relief
   (toutes familles) doit rester **< 16 ms** pour tenir 60 FPS, avec un release
   qui ne doit pas dépasser 1 frame (ou être asynchrone). La sonde
   `perf_probe_terrain.gd` peut servir de test de non-régression (les seuils sont
   déjà imprimés en ms/tampon et ms/release).
6. **Attention aux cartes réelles** : toutes les mesures ci-dessus sont sur
   44×32 / `terrainDetail=1`. La sérialisation sculpture, `sculpt_regions`, le
   heightfield et l'AO scalent en surface (`×7` pour 100×100) et le maillage en
   `detail²` (`×8,7` de detail 1 à 3). Un utilisateur sur une grande carte en
   détail 2–3 verra des coûts **3 à 8×** supérieurs à ceux-ci.

---

## 7. Reproduire les mesures

```
$exe = "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
& $exe --headless --path game --script res://scripts/debug/perf_probe_terrain.gd
```

La sonde imprime des lignes `[perf] ...` :

- section **A** : coût `_sync_engine()` (référence) ;
- sections **B/C/D/D2/E/F** : traits classiques et 3D (`raise`, `fill` froid,
  `fill` chaud, `raise` sur carte sculptée, `carve` avec release décomposé,
  `smooth3d`), avec série temporelle par événement, signaux `terrain`,
  `_sync_engine` pendant le drag, rebuilds du maillage sol, clusters/vertices
  avant/après, résolutions preview/finale, transaction ;
- section **G** : micro-benchmarks de chaque étape du pipeline, effet du détail
  du maillage ;
- section **H** : synthèse (ms/tampon, pire, release, ratio).

Fichier : `game/scripts/debug/perf_probe_terrain.gd` (ne modifie aucun fichier de
prod ; la carte de test est construite à partir de
`game/scripts/debug/cite_eau_boot.gd`).

---

## 8. Annexe — relevés bruts (2 runs indépendants)

```
=== A) RÉFÉRENCE — coût d'un _sync_engine() complet ===
  _sync_engine() froid           :   1699.9 ms
  _sync_engine() chaud (2e)      :   1643.6 ms

=== B) TRAIT CLASSIQUE — mode raise (heightfield, sans creusement) ===
  press (1er tampon)      :    111.2 ms
  drag 12 événements     :   1318.3 ms  → 12 tampon(s) réels
  moyenne / tampon        :    110.0 ms  (médiane 111.0, pire 116.6)
  release (relâchement)   :     74.1 ms
  changed("terrain")/tampon : 1.00   (_sync_engine pendant le drag : 0)
  rebuilds du maillage SOL pendant le drag : 12 / 12 événements

=== C) TRAIT 3D — mode fill (« remblayer 3D »), état froid ===
  drag 14 événements     :   2583.2 ms  → 14 tampon(s) réels
  moyenne / tampon        :    184.3 ms  (médiane 171.3, pire 229.4)
  release (relâchement)   :   1091.2 ms
  rebuilds du maillage SOL pendant le drag : 3 / 14 événements
  clusters MC : 0 → 1  ·  vertices MC : 0 → 5516
  fin de drag (aperçu) : clusters=1 vertices=1159 tris=1109
  résolution preview : aucun cluster / finale : 1 cluster(s) res=[3]

=== D) TRAIT 3D — mode fill, état « chaud » ===
  moyenne / tampon        :    225.5 ms  (médiane 224.7, pire 263.2)
  release (relâchement)   :   1635.2 ms
  fin de drag (aperçu) : clusters=1 vertices=1685 tris=1649
  clusters MC : 1 → 1  ·  vertices MC : 5516 → 8165  ·  tris 8958 → 13487
  résolution preview : 1 cluster(s) res=[1] / finale : 1 cluster(s) res=[3]

=== D2) TRAIT CLASSIQUE (raise) sur carte déjà sculptée ===
  moyenne / tampon        :    274.1 ms  (médiane 280.9, pire 316.5)
  release (relâchement)   :   2039.7 ms
  rebuilds du maillage SOL pendant le drag : 8 / 8 événements
  fin de drag (aperçu) : clusters=1 vertices=1802 tris=1834
  clusters MC : 1 → 1  ·  vertices MC : 8165 → 9342  ·  tris 13487 → 15459

=== E) TRAIT 3D — mode carve + release décomposé ===
  moyenne / tampon        :    315.7 ms  (médiane 311.3, pire 336.3)
  release (relâchement)   :    151.3 ms (résiduel)
    ├ polish preview→full :    632.0 ms
    ├ refresh_terrain     :    519.1 ms
    ├ commit_transaction  :      1.5 ms
  fin de drag (aperçu) : clusters=1 vertices=2354 tris=2741
  après polish (final) : clusters=1 vertices=6663 tris=10704

=== F) TRAIT 3D — mode smooth3d ===
  moyenne / tampon        :    287.9 ms  (médiane 306.3, pire 316.3)
  release (relâchement)   :   1077.6 ms
  résolution preview : res=[1] / finale : res=[2]

=== G) MICRO-BENCHMARKS ===
  doc.to_map_data()                              :     4.84 ms
  field.get_sculpt()                             :    53.81 ms
  field.sculpt_regions()                         :    26.60 ms
  TerrainCarveField.new()                        :    17.96 ms
  TerrainCarveChunks.compute_clusters()          :    27.00 ms
  _sync_terrain_from_map()                       :    16.68 ms
  _load_water()                                  :    20.24 ms
  _make_terrain_mesh()                           :    46.01 ms
    dont _compute_cavity_ao()                    :    12.40 ms
  _apply_config() COMPLET                        :   708.02 ms
  _rebuild_dirty_carve_meshes(force=true)        :   690.48 ms
  ground.set_terrain_heights() (1 case changée)  :   718.61 ms
  doc.sculpt_stamp() seul                        :    48.48 ms
  editor._paint_relief() 3D                      :   752.55 ms
  editor._paint_relief() raise (avec sculpture)  :   428.63 ms
  editor._on_doc_changed("terrain")              :     0.00 ms
  meshes_layer.set_terrain_sculpt()              :    30.77 ms
  meshes_layer.set_terrain_carves()              :    33.32 ms
  meshes_layer.set_terrain_heights()             :    16.86 ms
  props_layer.set_terrain_sculpt()               :    21.36 ms
  set_terrain_carve_preview(false) = POLISH      :   956.48 ms
  refresh_terrain() full                         :   136.12 ms
  grille sculpture (88, 64, 64) = 360448 voxels, 128 chunks 8³, 2 clusters MC
  detail=1 : 35.87 ms (1485 vertices)   detail=2 : 104.65 ms (5785)
  detail=3 : 231.78 ms (12901)          detail=4 : 357.13 ms (22833)
```

> Note sur l'environnement : d'autres instances Godot (autres diagnostics perf)
> tournaient pendant les mesures sur une machine à 12 vCPU. Les valeurs absolues
> sont donc à prendre avec ±20–30 % ; les deux runs indépendants donnent des
> chiffres à ±15 % et les conclusions (ordres de grandeur, hiérarchie des causes,
> écart drag/release) sont stables.
