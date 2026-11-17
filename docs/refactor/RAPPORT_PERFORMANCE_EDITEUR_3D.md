# Rapport de performance — éditeur de carte 3D

> **Contexte** : un refactor de l'éditeur est en cours (`docs/refactor/INVENTAIRE_TECHNIQUE.md`,
> `docs/REFACTOR_EDITEUR.md`). Ce rapport fixe les cibles de performance mesurées pour
> que le refactor ne se contente pas de déplacer la dette : pour chaque symptôme
> signalé, la cause racine exacte, son coût mesuré, et le contrat que le code
> refactoré doit tenir.
>
> Date : 2026-11-17 · Godot 4.7.2-stable · Windows · dépôt `D:\git\OpenQuest_jdr`
> Machine de mesure : AMD Ryzen 5 3600 (6C/12T).
>
> **Aucun fichier de production n'a été modifié.** Les diagnostics sont livrés avec
> des sondes reproductibles (`game/scripts/debug/perf_probe_*.gd`) et des notes
> détaillées (`docs/refactor/perf/0*.md`).

---

## 1. Résumé exécutif

Trois symptômes signalés, trois causes racines distinctes — **toutes mesurées en
exécutant réellement l'éditeur**, pas déduites :

| Symptôme utilisateur | Cause racine | Coût mesuré | Où |
|---|---|---|---|
| « déplacer ou tourner un objet fait freez 1–2 s » | **Chaque fin de drag déclenche 2 reconstructions complètes de toutes les couches 3D** (chacune ré-instancie les 114 GLB de la carte). Le drag lui-même est devenu incrémental (0,08–0,17 ms/mouvement) mais le **relâchement** ne l'est pas. S'y ajoutent les rebuilds différés de l'outliner/inspecteur et un **bug** : rotation/taille d'un décor non-mesh jamais appliquée en live (le 3D ne bouge qu'au rebuild final). | **release = 3 072–3 612 ms** (2 × 1,5–2,1 s) + **0,4–0,5 s** de panneaux ; 1ᵉʳ clic **0,4–0,5 s**. Test existant : rebuild = **2 524 ms**. | `map_editor_edit_ops.gd:427-448`, `map_complex_editor.gd:4427-4445`, `complex_map_engine_3d.gd:531-619`, `map_meshes_3d.gd:163-203` |
| « l'édition 3D du terrain rame et n'est pas pareille quand je remblaye et quand je relâche » | **Chaque tampon de brosse** resérialise toute la grille de sculpture (360 k voxels) et reconstruit 5 champs `TerrainCarveField` + tous les clusters Marching Cubes + repositionne les 114 objets. Au **relâchement**, un « polish » repasse la résolution MC de 1 à 3 (**vertices ×2,8 à ×5,2**) puis reconstruit eau/végétation/caméra : la géométrie visible change littéralement et le gel atteint 1–2 s. | **184–327 ms / tampon** (3–9 FPS) ; **release 1,06–2,04 s** | `map_complex_editor.gd:2605-2680,2788-2792`, `map_ground_3d.gd:336-359,400-477`, `map_edit_document.gd:1559-1611`, `terrain_carve_field.gd:851-877,929-950` |
| « la bibliothèque d'objets met 1–2 s à charger » | **Détourage pixel-par-pixel en GDScript des 93 vignettes 512² déjà transparentes** (`_ensure_cutout_alpha`) + décodage 93 PNG 512² (93 Mo de textures pour des boutons 84×92). | **1,87–2,00 s** pour les vignettes ; refresh froid **2,00–2,33 s** ; geste réel (clic outil MESH) **2,07–2,09 s** | `map_asset_library.gd:263-277,301-366,632-645`, `map_complex_editor.gd:3184-3218` |

**Le fil rouge des trois problèmes est le même** : l'éditeur propage tout changement
d'état sous forme de **snapshot complet + reconstruction complète** (`doc.to_map_data()`
→ `engine.configure()` → toutes les couches), au lieu de propager des **ensembles de
différences** (quelle couche a changé, quels objets sont touchés). Les gains déjà
livrés (commit `d4eca08`) sont des **correctifs incrémentaux ciblés** (drag live,
`refresh_meshes_only`, `set_terrain_*`) qui interceptent certains chemins mais ne
couvrent ni le commit, ni les panneaux, ni les couches non traitées (décors, eau,
végétation, vignettes).

**Correctifs structurants recommandés** (détaillés §7) :

1. **Ne plus jamais faire `configure()` complet en réponse à une édition** : introduire
   un état « couches sales » (`dirty layers`) entre le document et le moteur, et un
   `commit` incrémental qui ne reconstruit aucune couche.
2. **Rendre `MapMeshes3D.configure()` diff-based** : réutiliser les nœuds existants
   (id et asset inchangés) au lieu de tout libérer/reconstruire — c'est 1,6–1,9 s par
   appel aujourd'hui (§4.3).
3. **Sortir la préparation des vignettes du thread principal et du chemin de refresh**
   (§6) : supprimer le détourage sur vignettes 3D, vignettes 128² pré-cuites, refresh
   sans rebuild, chargement progressif.

Gain attendu des quick wins : **release de drag ≈ 3,5 s → < 50 ms** ; **bibliothèque
≈ 2 000 ms → ≈ 70 ms** ; **terrain : 184–327 ms/tampon → < 50 ms et release
1–2 s → < 100 ms perçu** (étalé/async).

---

## 2. Méthode de mesure

- **Godot 4.7.2-stable** (`Godot_v4.7.2-stable_win64_console.exe`), exécution
  `--headless --path game --script res://scripts/debug/perf_probe_*.gd`.
- **Carte de test réaliste** : `res://scripts/debug/cite_eau_boot.gd` (celle du test
  `editor_drag_perf_test.gd`) — **114 objets 3D, 44×32 cases**, eau, végétation. C'est
  la carte la plus lourde du dépôt.
- Mesures `Time.get_ticks_usec()` autour de chaque appel ; les sondes n'ont pas
  d'assertion (mesures descriptives, sortie `[probe]`/`[perf]`, `quit(0)`).
- Plusieurs runs indépendants par sujet (2 à 7), avec recoupement entre sondes
  (ex. le coût de `_meshes_layer.configure()` est retrouvé à ±10 % par la sonde Lead
  et par la sonde transform).
- **Limites honnêtes** :
  - `--headless` ne rend rien : les coûts **CPU** mesurés sont un **plancher**. Sur
    une vraie fenêtre s'ajoutent l'upload GPU, la compilation de shaders (la
    reconstruction duplique un matériau par surface à chaque rebuild) et les
    rebuilds de ressources de rendu. Le gel perçu est donc **supérieur** aux chiffres
    ci-dessous.
  - Machine partagée pendant une partie des runs (jusqu'à 8 instances Godot
    concurrentes) : ±20–50 % sur les valeurs absolues ; les rapports entre postes et
    la hiérarchie des causes sont stables et recoupés.
  - Les valeurs dépendent de la carte : la cité (114 objets) est un **majorant**.
    Sur une carte 2× plus petite, la même arithmétique donne les 1–2 s décrites par
    l'utilisateur.

---

## 3. Architecture du chemin de données (le problème structurel)

### 3.1 Flux actuel

```
geste utilisateur
  │
  ├─ map_editor_edit_ops.gd  (press / move / release)
  │     └─ map_edit_document.gd   (set_live_position / set_live_fields / commit_live_edit)
  │           └─ signal changed(reason)   ← "modify", "commit", "terrain", "add", …
  │
  └─ map_complex_editor.gd  _on_doc_changed(reason)            (l.4427)
        ├─ _refresh_panels()          (inspector + outliner + historique + statuts)
        ├─ _sync_engine()             (l.4088)  → doc.to_map_data() (snapshot COMPLET)
        │     └─ complex_map_engine_3d.gd  configure()         (l.531)
        │           ├─ _load_ground() / _load_backdrop() / _load_water()
        │           ├─ _load_ambient_fx() / _load_vegetation() / _load_elevations()
        │           ├─ _apply_camera_perspective() / _apply_lighting() / _apply_atmosphere()
        │           └─ _rebuild_layers()                       (l.2346)
        │                 ├─ _grid_layer.configure · _fog_layer.configure
        │                 ├─ _props_layer.configure             (tout reconstruit)
        │                 ├─ _meshes_layer.configure            (TOUS les GLB ré-instanciés)
        │                 ├─ _walls_layer.configure
        │                 └─ _lights_layer.configure
        └─ save_now() si SAVE_ON_CHANGE et dirty (l.4442)
```

`configure()` **ne compare rien** : il reconstruit toutes les couches à chaque appel
(`complex_map_engine_3d.gd:581-619`). `_sync_engine()` est appelé **~50 fois** dans
l'éditeur, y compris pour des chemins non liés au rendu 3D (taille de grille, ambiance,
import, réglages). Chaque appel = rebuild complet.

### 3.2 Coût mesuré d'un rebuild complet (carte cité, 114 objets 3D)

| Poste | Mesure |
|---|---:|
| `doc.to_map_data()` (snapshot complet) | 2,4–3,7 ms |
| `_sync_engine()` total | **1 520–2 159 ms** |
| ↳ `engine.configure()` | 1 515–1 706 ms |
| ↳ `_rebuild_layers()` | **1 387–1 930 ms** |
| ↳↳ `_meshes_layer.configure()` (114 objets) | **1 390–2 029 ms** |
| ↳↳ `_props_layer.configure()` (0 prop ici) | 4–9 ms |
| ↳ `_load_ground()` (terrain reconstruit à chaque sync) | 53–68 ms |
| ménage (`free()` des 114 racines) | 17–21 ms |
| 2ᵉ `_sync_engine()` immédiatement après | **1 838–2 331 ms** (aucune mémoïsation) |
| `_refresh_panels()` + frame (rebuilds différés) | **359–531 ms** |

**Conclusion de mesure** : le rebuild n'est ni le terrain (53–68 ms), ni le backdrop
(0,2 ms), ni l'eau (0,8–20 ms), ni les lumières : **c'est la couche des objets 3D qui
ré-instancie tous les GLB**, à ~15 ms l'objet **quand il reste vivant dans la scène**.

### 3.3 Conséquence pour le refactor

Tant que le contrat « 1 édition = 1 `configure()` complet » subsiste, **toute**
optimisation locale sera un pansement. Le refactor doit introduire un **contrat de
changement** entre `MapEditDocument` et `ComplexMapEngine3D` :

- le document expose **ce qui a changé** (`{"layers": ["meshes"], "ids": [...]}`) au
  lieu d'un snapshot ;
- le moteur applique des **opérations ciblées** (`upsert_mesh(id)`, `remove_mesh(id)`,
  `move_mesh(id, x, y)`, `apply_terrain_patch(rect)`, `set_water_bodies(ids)`…) avec
  pool/réutilisation des nœuds ;
- le rebuild complet reste **uniquement** le chemin « chargement de carte / changement
  de preset de rendu », jamais le chemin d'édition.

---

## 4. Symptôme A — déplacer / tourner un objet 3D (freeze 1–2 s)

> Mesures détaillées : `docs/refactor/perf/01_transform_notes.md` · sonde
> `game/scripts/debug/perf_probe_transform.gd`.

### 4.1 Le drag lui-même est bon ; c'est le **relâchement** qui gèle

Le commit `d4eca08` a bien rendu le geste incrémental : **0,03–0,17 ms par mouvement
de souris**, nœud 3D conservé, transform réellement appliquée (le test
`editor_drag_perf_test.gd` le vérifie). Le gel vient de ce qui se passe **au
relâchement du bouton**, et de la **frame suivante** :

| Événement (carte cité, 114 objets) | Mesure |
|---|---:|
| `press` (objet déjà sélectionné → début du drag) | 1,9–2,9 ms |
| `move` × 10 (mesh) | **0,08–0,13 ms / mouvement** |
| `rotate` × 10 (mesh) | **0,10–0,17 ms / mouvement** |
| **`release` move mesh** | **3 072–3 612 ms** (+ frame suivante 396–531 ms) |
| **`release` rotate mesh** | **3 095–3 535 ms** (+ frame suivante 414–486 ms) |
| **1ᵉʳ clic de sélection** (frame différée) | **404–497 ms** |

Sur une carte plus légère que la cité, la même arithmétique donne exactement les
**1–2 s** observées par l'utilisateur. Le nœud 3D est **remplacé** au release
(`get_instance_id()` change) : c'est un rebuild, pas une mise à jour.

### 4.2 Cause n°1 (dominante) : le release déclenche **DEUX** reconstructions complètes

```
_on_pointer_released                          map_editor_edit_ops.gd:427-448
  └─ doc.commit_live_edit(ids, "Déplacement")  map_edit_document.gd:1012
       └─ changed.emit("commit")              :1027
            └─ _on_doc_changed("commit")      map_complex_editor.gd:4427
                 └─ _sync_engine()            ← rebuild #1 (le garde-fou ne couvre que "modify")
  └─ _refresh_context_decor_for_walls(ids)
  └─ _rebuild_lights_illumination(ids)
  └─ _ed._sync_engine()                       ← rebuild #2 EXPLICITE (edit_ops:432/440/446)
  └─ _refresh_panels()                        ← frame suivante : outliner + inspecteur
```

```gdscript
# map_complex_editor.gd:4437-4440 — seul "modify" est filtré pendant un drag live
var live_incremental := _press_mode in ["move", "resize", "rotate"] and _live_incremental
if reason in [..., "modify", "commit", "add", "remove"]:
    if not (live_incremental and reason == "modify"):
        _sync_engine()
```

**Preuve mesurée** : `commit_live_edit()` seul = **1 535–1 899 ms** (il contient le
rebuild #1 via le signal) ; `_sync_engine()` explicite = **1 536–1 794 ms** ; la somme
reconstitue le release réel (ratio release/_sync = **1,7–2,4**). Or le commit n'a que
deux choses à faire : pousser le **delta undo** et rafraîchir les panneaux — la
transform est **déjà** appliquée aux nœuds 3D pendant le drag.

### 4.3 Cause n°2 : `configure()` reconstruit les 114 GLB, sans aucune idempotence

`_sync_engine()` → `engine.configure()` → `_rebuild_layers()` →
`MapMeshes3D.configure()` qui **libère les 114 nœuds puis ré-instancie les 114 scènes
GLB** (`map_meshes_3d.gd:183-202`). Coût : **1 390–2 029 ms** ; un deuxième appel
immédiat coûte pareil (aucune garde). Détail mesuré :

- `_build_mesh()` des 114 objets **hors scène** : 146–189 ms (**1,4–1,8 ms/objet**) ;
- les mêmes objets **ajoutés à la scène** : **1 434–1 522 ms** (~15 ms/objet, pire
  `maison_grande.glb` / `grange.glb` à **52–54 ms**) ;
- ménage des anciens nœuds : 17–20 ms ; `doc.to_map_data()` : 2,4–3,7 ms ;
  `_load_ground()` : 53–68 ms (reconstruit le terrain à chaque sync, pour rien).

Le coût marginal vient de l'enregistrement des instances de rendu, de la **duplication
d'un matériau par surface** pour chaque GLB (`_sanitize_visual` → `_apply_lit_materials`
→ `source.duplicate()`), de l'ombre de contact et — sur une vraie fenêtre — de la
**recompilation de shaders** et de l'upload GPU.

> À noter : la couche eau (`map_water_3d.gd:175-186`) a **déjà** une garde
> d'idempotence (`_arrays_equal`/`str()` puis `return`). C'est le pattern à généraliser.

### 4.4 Cause n°3 : les panneaux reconstruits en différé (+0,4–0,5 s par clic/release)

`_refresh_panels()` (`map_complex_editor.gd:4395`) diffère `_inspector.rebuild()` et
`_outliner.rebuild()`. Mesures : **outliner 338–504 ms**, inspecteur mesh 24–35 ms →
frame suivant le release **396–531 ms**, frame du **1ᵉʳ clic 404–497 ms**. La partie
synchrone (historique/badges/minimap) est négligeable : tout le coût est dans les
rebuilds d'arbre, alors qu'un simple changement de sélection ne devrait mettre à jour
qu'une ligne et un inspecteur.

### 4.5 Cause n°4 — **bug fonctionnel** : les décors (KIND_PROP) ne tournent pas pendant le drag

`_apply_handle_rotate` (`edit_ops:634-649`) ne route la mise à jour live que pour
`KIND_MESH`, et `set_element_live_fields` appelle `_props_layer.set_prop_fields(...)` —
**méthode inexistante** (`map_props_3d.gd` n'a que `set_prop_position`). L'appel est
silencieusement ignoré (`has_method` masque l'erreur). Mesuré sur un décor :

- rotation **0,03–0,04 ms/mouvement**, mais **0 / 10 mouvements appliqués au nœud 3D**
  (yaw nœud −0,00 alors que le document passe à −157,86°) ;
- le décor ne tourne **qu'au release**, quand le rebuild complet le remplace.

Même trou au **redimensionnement** d'un décor (seuls mesh et lumière reçoivent des
`fields`). De plus `_live_incremental = is_mesh` laisse le flag **faux** pendant ces
gestes : tout `changed("add"/"remove"/"modify")` émis au même moment (mur raccordé,
décor contextuel, autosave) déclenche alors un **rebuild complet par mouvement**.

### 4.6 Causes secondaires (chemins multi-sync et autosave)

- **Murs + décor contextuel** : `remove_elements`/`add_element` émettent `changed`
  **par élément** (`map_edit_document.gd:880`…), jamais filtré par `_live_incremental`
  → un release de mur décoré peut coûter `2 + N_retirés + N_ajoutés` rebuilds complets
  (jusqu'à ~18 × ~1,5 s). Vérifié par code (non mesuré : la cité n'a pas de murs).
- **Autosave `SAVE_ON_CHANGE`** : au release, si `_live_incremental` est faux
  (rotation/redimensionnement de décor), `_on_doc_changed` appelle `save_now()` qui
  sérialise la carte puis **réécrit tout le fichier de cartes** (`map_data.gd`), en plus
  des rebuilds.
- **Coût par mouvement** (déjà acceptable mais à surveiller) : overlay `_draw()`
  **4,1–6,1 ms**, hit-test `elements_at_screen` **4,7–8,6 ms** au press. Marge de
  fluidité (60 Hz = 16,6 ms/frame) qui disparaît sur une carte 2× plus grande.

### 4.7 Ce que le test existant ne peut pas voir

`editor_drag_perf_test.gd` pose l'état à la main et n'appelle **ni**
`_on_pointer_pressed` **ni** `_on_pointer_released` : il ne mesure que les `move`. Il ne
peut donc pas détecter (a) le double rebuild du release, (b) les rebuilds différés de
panneaux, (c) le bug des décors non-mesh, (d) l'absence d'idempotence. C'est pour cela
que le commit `d4eca08` a pu être livré avec un test vert alors que le gel persistait
(§9 : test cible).

---

## 5. Symptôme B — sculpture / édition 3D du terrain

> Mesures détaillées : `docs/refactor/perf/02_terrain_notes.md` · sonde
> `game/scripts/debug/perf_probe_terrain.gd`.

### 5.1 Ce que l'utilisateur ressent, traduit en chiffres

Sur la carte cité (44×32, `groundMode=terrain3d`, 114 objets, heightfield 1 485
vertices, grille de sculpture **360 448 voxels**) :

| Trait de brosse (12–14 événements souris) | ms / tampon | Release |
|---|---:|---:|
| `raise` (« Monter ») classique, carte neuve | 110–130 ms | 74–87 ms |
| `fill` (« Remblayer 3D »), état froid | 184–210 ms | **1 091–1 307 ms** |
| `fill`, état chaud | 226–260 ms | **1 635–1 894 ms** |
| `raise` classique sur carte déjà sculptée | 274–283 ms | **1 840–2 047 ms** |
| `carve` (« Creuser 3D ») | 291–327 ms | ≈ 1,2 s (polish 632 ms + refresh 519 ms) |
| `smooth3d` (« Lisser 3D ») | 279–301 ms | 1 043–1 078 ms |

**110 à 330 ms par événement souris = 3 à 9 FPS pendant le trait** — c'est littéralement
le « ça rame du cul ». Et chaque relâchement ajoute **1 à 2 s** de gel.

### 5.2 Pourquoi c'est si cher : un tampon touche ~25 colonnes… mais rebâtit tout

| Étape d'un tampon 3D | Coût mesuré |
|---|---:|
| `field.get_sculpt()` — **scan + sérialisation de la grille entière** (chunks 8³) | **46–55 ms** |
| `field.sculpt_regions()` — scan des 128 chunks | 22–27 ms |
| `TerrainCarveChunks.compute_clusters()` | 23–29 ms |
| `TerrainCarveField.new()` — 5 champs neufs + 1 désérialisation dans le ground | 16–19 ms ×5 |
| `_sync_terrain_from_map()` | 17–20 ms |
| `ground.set_terrain_sculpt()` (désérialise + clusters + masque) | 15–18 ms |
| `meshes_layer.set_terrain_sculpt()` (+ reposage des 114 objets) | 27–31 ms |
| `meshes_layer.set_terrain_carves()` (champ neuf même si inchangé) | 26–33 ms |
| `props_layer.set_terrain_sculpt()` | 19–21 ms |
| `_rebuild_dirty_carve_meshes(force=true)` — **tous** les clusters MC | 641–700 ms en résolution finale |

Le champ de sculpture est **sérialisé 1×, désérialisé 6×, construit 5× et scanné 3×
par tampon**, alors que la brosse ne modifie qu'une vingtaine de colonnes. Le
`force=true` de `map_ground_3d.gd:446` est nécessaire parce que la clé de cluster
(`:1646-1649`) ne change pas quand seul le **contenu** du champ change : il n'existe
donc aujourd'hui aucun moyen de ne rebâtir que les clusters réellement touchés.

**Facteurs d'échelle** : coût proportionnel à la **surface de la carte** (×7 pour
100×100), au **détail du heightfield** (`_make_terrain_mesh` : 36 ms en détail 1 →
**232 ms en détail 3 → 357–414 ms en détail 4**) et à la **longueur du trait** (les
clusters adjacents fusionnent en un seul gros cluster reconstruit entièrement). Sur une
grande carte en détail 2–3, l'utilisateur voit des coûts **3 à 8× supérieurs** à ce
tableau.

### 5.3 Le « pas la même chose quand je relâche » — trois mécanismes cumulés

1. **Résolution Marching Cubes preview → final** : `_carve_resolution_for()`
   (`map_ground_3d.gd:467-477`) renvoie `2`/`1` pendant le trait et `3` au relâchement.
   La géométrie **change littéralement** : vertices MC **1 685 → 8 165** (×4,8),
   **2 354 → 6 663** (×2,8) selon les modes. Ce n'est pas un simple lissage : parois,
   crêtes et silhouettes se déplacent au relâchement.
2. **Calques gelés pendant le trait, rattrapés au release** : `refresh_terrain`
   (`complex_map_engine_3d.gd:1788-1790`) ne reconstruit l'**eau** et la **végétation**
   que quand `_terrain_carve_preview` repasse à `false` (release), et la caméra n'est
   rehaussée qu'à ce moment (`:1833`) → « pop » de la ligne de rive et du cadrage.
3. **Le polish n'est pas une finition, c'est un rebuild complet** : il reconstruit
   **tous** les clusters (`force=true`), puis repose tous les meshes/tokens. Le
   résultat final ne devrait pas différer du preview si les deux partageaient la même
   géométrie.

### 5.4 Hypothèses infirmées (à ne pas re-diagnostiquer)

- **`_on_doc_changed("terrain")` n'appelle PAS `_sync_engine()`** :
  `map_complex_editor.gd:4438` ne contient pas `"terrain"`. Compteur de trace moteur :
  **0 `_sync_engine` pendant tous les traits mesurés**. Le rebuild global (1,6–1,8 s)
  n'est donc **pas** le coupable pendant le drag — contrairement à l'hypothèse de
  départ.
- `_raycast_ground` / `_carve_hit` : 0,01 ms. `begin_transaction`/`commit_transaction` :
  1,1–1,5 ms. Ni le raycast ni l'undo ne sont coupables côté CPU (l'undo de sculpture
  est en revanche volumineux en mémoire : 15 deltas / 33 792 entrées pour un trait
  `fill`, à surveiller pour les longs traits).
- La quantification int8 du sculpt n'explique pas l'écart visuel (erreur ≈ 0,002–0,005 case).

---

## 6. Symptôme C — bibliothèque d'objets (1–2 s de gel)

> Mesures détaillées : `docs/refactor/perf/03_library_notes.md` · sonde
> `game/scripts/debug/perf_probe_library.gd`.

### 6.1 Le gel, reproduit au millième

| Geste | Mesure |
|---|---:|
| Premier affichage « Objets 3D » (refresh froid) | **1 997–2 331 ms** |
| **Geste utilisateur réel** : clic sur l'outil MESH (`_on_dock_tool_pressed("mesh")`) à froid | **2 071–2 085 ms** |
| Refresh à chaud (cache statique rempli) | 42–55 ms |

C'est exactement le symptôme « met 1 à 2 s à charger ce qui freez le jeu ».

### 6.2 Cause n°1 (86 % du gel) : détourage pixel-par-pixel de vignettes déjà détourées

`load_object3d_thumbnail()` (`map_asset_library.gd:632`) passe par `load_texture()`
(`:263`) qui appelle **`_ensure_cutout_alpha()` (`:301`)** sur chaque vignette. Cette
fonction :

1. fait une **passe complète de 262 144 pixels en GDScript** via `Image.get_pixel()`
   (`:310-315`) pour compter les pixels transparents ;
2. ne teste la condition d'arrêt (≥ 8 % transparents) **qu'après** la passe complète ;
3. or les vignettes 3D sont **déjà transparentes** (mesuré : 59–87 % des pixels).

Coût mesuré : **15,2–24,9 ms par vignette × 93 vignettes = 1 871–2 002 ms** de travail
pur perdu, refait à chaque démarrage de process (cache statique vide).

### 6.3 Cause n°2 : vignettes 512×512 pour des boutons 84×92

93 PNG de 512×512 = **93 Mo de textures** chargées en RAM/VRAM pour une vignette
affichée en 84×92 px (≈ 34× la surface utile). Le décodage PNG seul coûte **370 ms**.
Variante mesurée sans détourage : 370 ms ; avec vignettes 128² pré-cuites : **23 ms**
(pour 5,8 Mo de VRAM).

### 6.4 Cause n°3 : la grille est entièrement reconstruite à chaque refresh

`_refresh_asset_library()` (`map_complex_editor.gd:3020`) vide puis recrée **94 boutons**
dans un `GridContainer` **non virtualisé** (`library.tscn:47`) à chaque :
- changement de catégorie / de filtre (`:3042`, `:3115-3129`) ;
- **chaque caractère tapé dans la recherche** (`:1386-1390`, `text_changed` → refresh) ;
- **clic sur une vignette** (`:3321` → refresh alors que le catalogue n'a pas changé).

Coût : 30,7–33,6 ms pour la grille seule, 42–55 ms pour le refresh complet, **52 ms par
clic de vignette**. Et après un import GLB, `clear_caches()` (`:3307`) vide les 93
textures → **le gel de 2 s revient une seconde fois**.

### 6.5 Non-causes vérifiées

Le scan disque (`list_object3d_assets`, `map_asset_library.gd:486`) coûte 10,6–17 ms
(< 1 %) ; la miniature est bien un **PNG disque pré-rendu** (aucun rendu GLB au
refresh) ; `image_size`/`aspect_ratio` ne sont pas appelés ; `instantiate_object3d_scene`
(3,8–10,5 s pour 93 GLB !) est **hors du chemin de refresh** (pose/import uniquement).

---

## 7. Correctifs priorisés (consolidé)

> Les correctifs détaillés (fichier:ligne, effort, risque) sont dans les notes
> `perf/01`, `perf/02`, `perf/03`. Ici : l'ordre de bataille recommandé pour le refactor.

### P0 — supprime les gels signalés (quick wins, risque faible)

| # | Correctif | Gain attendu | Cause |
|---|---|---|---|
| 1 | **Commit de drag sans rebuild** : sur `release`, ne plus appeler `_sync_engine()` ; ne plus router `changed("commit")` vers un rebuild complet (ou émettre un signal dédié `transform_committed(ids)`). | release ≈ 3,5 s → **~1,6 s** (puis < 50 ms avec le #2) | A n°1 |
| 2 | **`MapMeshes3D.configure()` diff-based** : réutiliser les nœuds dont l'id et l'asset n'ont pas changé, ne construire que les ajouts, libérer les retirés ; construire **hors scène** puis ajouter en batch (1,4–1,8 ms/objet au lieu de ~15 ms). | rebuild 1,4–2,0 s → **~0** quand rien ne change | A n°2 |
| 3 | **Panneaux légers** : sur sélection/release, rafraîchir la ligne sélectionnée + l'inspecteur (si le kind change) au lieu de `outliner.rebuild()` complet ; coalescer les rebuilds. | **−0,4 à −0,5 s** par clic/release | A n°3 |
| 4 | **`MapProps3D.set_prop_fields()`** + routage live de **tous** les kinds (table de capacités) ; supprimer `_live_incremental = is_mesh`. | décor tourne/scale en live (~0,1 ms) ; corrige un bug fonctionnel ; plus de rebuild par mouvement | A n°4 |
| 5 | **Supprimer le détourage sur vignettes 3D** (chemin dédié dans `load_object3d_thumbnail`, sans `_ensure_cutout_alpha`). | bibliothèque 2 000 → **370 ms** | C n°1 |
| 6 | **Vignettes 128² pré-cuites** (pipeline Blender ou cache disque). | 370 → **23 ms** ; VRAM 93 → 5,8 Mo | C n°2 |
| 7 | **Invalidation ciblée après import** au lieu de `clear_caches()`. | supprime le 2ᵉ gel de 2 s | C n°4 |
| 8 | **Sortir `get_sculpt()` du chemin chaud** : le champ vivant est la source de vérité, sérialisation du JSON au commit seulement. | **−46/−55 ms par tampon** terrain | B n°1 |
| 9 | **`force=false` sur les clusters MC pendant le drag** via une version/dirty par chunk dans la clé de cluster. | **−0,1/−0,15 s par tampon**, −0,4/−0,7 s au release | B n°2 |
| 10 | **Polish + eau/végétation au release en différé** (`call_deferred` / 1–2 frames) et non synchrones dans l'événement de relâchement. | release terrain 1–2 s → **< 100 ms perçu** | B n°2 |

### P1 — supprime le coût structurel (cœur du refactor)

| # | Correctif | Cible |
|---|---|---|
| 11 | **Dirty-layers entre document et moteur** : `configure()` complet réservé au chargement/preset ; les éditions passent par des opérations ciblées. | architecture §3.3 |
| 12 | **Patchs régionaux de terrain** : API `apply_terrain_patch(rect, changed_chunks, version)` implémentée par ground/props/meshes/tokens/water/vegetation ; **un seul** `TerrainCarveField` partagé, muté en place (aujourd'hui reconstruit 6× par tampon). | terrain |
| 13 | **Heightfield incrémental** : ne reconstruire que les vertices/indices du rect modifié, AO de cavité régionale ou mémoïsée. | terrain |
| 14 | **Chemins classiques sans `terrainCarves`** : supprimer la condition `map_ground_3d.gd:348` qui force `_apply_config()` complet dès qu'une sculpture existe. | terrain |
| 15 | **Chargement progressif des vignettes** (threads/lots par frame) + cache disque clé=mtime. | bibliothèque |
| 16 | **Grille virtualisée/recyclée** + pas de rebuild au clic/filtre + debounce de la recherche. | bibliothèque |
| 17 | **Unifier preview/final** (LOD de rendu sur la même géométrie plutôt que résolution MC différente rebâtie au release). | terrain |
| 18 | **Batch de signaux du document** : une seule émission `changed` par transaction (murs + décor contextuel = aujourd'hui jusqu'à N rebuilds par élément). | transform |
| 19 | **Autosave coalescé** : pas de `save_now()` sur un commit de transform ; sauvegarde différée et écriture de la seule carte modifiée. | transform |

### P2 — qualité de service / prévention

- Coalescer les événements souris (1 tampon max par frame, budget 16 ms) avec rejeu
  des positions manquantes pour ne pas perdre de matière.
- Matériaux : arrêter de dupliquer un matériau par surface à chaque rebuild (pool par
  asset) — les recompilations de shaders sont un gel non mesuré en headless.
- Hit-test de l'overlay : index spatial (grille de cases) au lieu de boucler sur tous
  les éléments ; cache des footprints.
- Instrumentation permanente : les sondes `perf_probe_*` deviennent des tests de
  non-régression avec seuils (§9).

---

## 8. Implications pour le refactor en cours

### 8.1 Le contrat cible

```
press  : sélectionner (léger) + démarrer le drag
move   : apply_live_transform(ids, fields)          (déjà fait : 0,1 ms)
release: commit_delta(ids) + refresh_selection()    (léger)
         AUCUN configure(), AUCUN rebuild de couche, AUCUN rebuild d'arbre complet
```

### 8.2 Modules à extraire (proposition alignée sur le refactor)

| Module proposé | Responsabilité | Contenu actuel à extraire |
|---|---|---|
| `MapEditorSyncController` | décider **quoi** resynchroniser : raison → `dirty_layers`/`dirty_ids`, garde d'idempotence par couche, coalescing/une frame | `_on_doc_changed` (`map_complex_editor.gd:4427`), `_sync_engine` (l.4088), `_refresh_panels` (l.4395) |
| `MapEditorLiveTransform` | API live par kind (table de capacités `KIND_* → méthodes live`) | `if is_mesh` de `edit_ops` (`:583-586`, `:634-649`) et routage partiel de `set_element_live_fields` (`complex_map_engine_3d.gd:3047`) |
| `MapMeshes3D` scindé | *factory* (build GLB, matériaux, ombre) vs *updater* (`set_mesh_fields`, `upsert_mesh`, `remove_mesh`) + pool | `_build_mesh`/`_sanitize_visual`/`_lit_material` (`map_meshes_3d.gd:451,1298,1384`) et `configure` (l.163) |
| `MapProps3D` | ajouter `set_prop_fields` (rotation/scale/taille/standing) | `map_props_3d.gd:264-273` (n'a que `set_prop_position`) |
| `MapEditorPanels` | rebuilds coalescés : `refresh_selection()` léger vs `rebuild_tree()` lourd | `_refresh_panels` (l.4395), `_on_selection_changed` (l.4447), `outliner.rebuild()` (`map_editor_outliner.gd:45`) |
| `MapEditDocument.commit` | commit **sans** signal lourd : `transform_committed(ids)` séparé de `changed` | `commit_live_edit` (`map_edit_document.gd:1012-1027`) |
| `TerrainFieldOwner` + `apply_terrain_patch` | un seul propriétaire du champ de terrain, patch régional | `_sculpt_support` (`map_edit_document.gd:1546`), `_sync_terrain_from_map` (`complex_map_engine_3d.gd:1612`), setters `set_terrain_*` des couches |
| `MapAssetCatalog` + `ThumbnailPipeline` | catalogue (scan/mtime) séparé du rendu de grille ; vignettes préparées **hors thread principal**, cache disque | `map_asset_library.gd` (scan, `load_texture`, `_ensure_cutout_alpha`, `load_object3d_thumbnail`), `_refresh_object3d_library` (`map_complex_editor.gd:3172`) |

### 8.3 API incrémentale manquante, par kind d'élément

| Kind | Position live | Rotation/échelle live | Manque |
|---|---|---|---|
| `mesh` (KIND_MESH) | ✅ `set_mesh_position` | ✅ `set_mesh_fields` | rien côté API ; prévoir `upsert_mesh` sans `free()` |
| `prop` (KIND_PROP) | ✅ `set_prop_position` | ❌ **rien** | `set_prop_fields` (rotation `root.rotation_degrees.y`, `QuadMesh.size`, `display.scale`, `standing`) |
| `light` (KIND_LIGHT) | ✅ `set_light_position` | rayon ✅ `set_light_radius` ; énergie/couleur ❌ | `set_light_fields` si live complet voulu ; `_refresh_light_mask_live` seulement en mode nuit |
| `token`/`effect`/`zone` | ✅ `set_element_position` | rotation/échelle ❌ | faible priorité (pas de poignées rot/scale) |
| `wall` (asset `mur*`) | ✅ via mesh | ✅ via `set_mesh_fields` (chemin propre `_apply_wall_handle_resize`) | vérifier que le resize mur passe bien par le live |

### 8.4 Budget de performance à inscrire dans la définition de « terminé »

| Scénario | Aujourd'hui (mesuré) | Cible |
|---|---:|---:|
| move/rotate par mouvement | 0,08–0,17 ms | inchangé |
| **release** move/rotate | **3,1–3,8 s + 0,4–0,5 s** | **< 50 ms**, zéro rebuild de couche |
| rotate/resize décor pendant le drag | 3D figé (0/10) | 3D live (~0,1 ms) |
| 1ᵉʳ clic de sélection (frame différée) | 0,4–0,5 s | < 30 ms |
| `_sync_engine()` à vide (idempotence) | 1,5–2,1 s | < 10 ms |
| release d'un mur décoré (N décors) | ~(2+N+N) rebuilds | 1 batch, 0 rebuild |
| tampon de relief (toutes familles) | 110–327 ms | **< 16 ms** |
| release de relief | 1–2 s | < 1 frame ou asynchrone |
| refresh bibliothèque 3D à froid | 2 000 ms | **< 100 ms** (ou progressif : 0 travail synchrone > 16 ms) |

---

## 9. Garde-fous / tests de non-régression à ajouter

Les sondes livrées sont des **reproducteurs de diagnostic** (sortie `[probe]`,
pas d'assertion). Il faut les promouvoir en tests de seuil :

1. **`editor_transform_commit_test.gd`** (nouveau, cf. notes transform §4.2) :
   vrai cycle `_on_pointer_pressed` → `_on_pointer_moved` × N → `_on_pointer_released` ;
   assertions : release **< 50 ms**, nœud 3D conservé (`get_instance_id()` identique),
   aucun `configure()` pendant le release (compteur injecté), frame suivante < 100 ms,
   doc == transform du nœud après release. Inclure un cas **décor `KIND_PROP`**
   rotaté/redimensionné (attrape le bug `set_prop_fields`).
2. **`editor_sync_idempotence_test.gd`** : deux `_sync_engine()` consécutifs →
   deuxième < 10 ms (garde d'idempotence par couche).
3. **`terrain_sculpt_budget_test.gd`** : un tampon `fill`/`carve` sur la carte cité
   < 16 ms et release < 1 frame (ou asynchrone) — seuils imprimés par
   `perf_probe_terrain.gd`.
4. **`map_editor_library_perf_test.gd`** : premier refresh bibliothèque 3D froid
   < 250 ms headless (aujourd'hui 2 000 ms), et pas de détourage sur vignettes 3D.
5. Conserver `editor_drag_perf_test.gd` (per-move déjà protégé) et **le compléter**
   par le test de commit.
6. Éviter d'ajouter les sondes telles quelles à `scripts/run_tests.ps1` (durée
   60–100 s chacune) : les mettre dans une suite « perf » séparée, déclenchée à la
   demande ou en CI nocturne, avec seuils.

---

## 10. Annexes — reproducteurs et notes détaillées

### 10.1 Commandes de reproduction

```powershell
$godot = "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

# Architecture du rebuild (Lead) : ~2 min
& $godot --headless --path game --script res://scripts/debug/perf_probe_layers.gd

# Déplacement / rotation / commit : ~60-100 s
& $godot --headless --path game --script res://scripts/debug/perf_probe_transform.gd

# Sculpture 3D du terrain : ~2-4 min
& $godot --headless --path game --script res://scripts/debug/perf_probe_terrain.gd

# Bibliothèque d'objets 3D : ~2-3 min
& $godot --headless --path game --script res://scripts/debug/perf_probe_library.gd
```

Toutes les sondes s'arrêtent avec `quit(0)` et n'écrivent aucun fichier de production.
Sur la machine de mesure, Godot n'était pas dans le `PATH` : utiliser le chemin complet
ci-dessus (ou définir `GODOT_BIN`).

### 10.2 Livrables

| Fichier | Contenu |
|---|---|
| `docs/refactor/RAPPORT_PERFORMANCE_EDITEUR_3D.md` | ce rapport (synthèse, mesures, correctifs, implications refactor) |
| `docs/refactor/perf/01_transform_notes.md` | diagnostic complet déplacement/rotation (causes C1–C8, preuves, correctifs, test cible) |
| `docs/refactor/perf/02_terrain_notes.md` | diagnostic complet sculpture terrain (causes, chemin d'appel d'un tampon, drag vs release, correctifs) |
| `docs/refactor/perf/03_library_notes.md` | diagnostic complet bibliothèque (vignettes, grille, variantes de correctif mesurées) |
| `game/scripts/debug/perf_probe_layers.gd` | sonde Lead : décomposition de `_sync_engine()` / `_rebuild_layers()` / couche meshes |
| `game/scripts/debug/perf_probe_transform.gd` | sonde drag/rotation/commit |
| `game/scripts/debug/perf_probe_terrain.gd` | sonde sculpture terrain |
| `game/scripts/debug/perf_probe_library.gd` | sonde bibliothèque |

### 10.3 Ce qui n'est pas couvert par ce rapport

- Les coûts **GPU réels** (shaders, upload de textures, ombres) : mesurables seulement
  en fenêtre réelle avec un profiler GPU ; les mesures headless sont un plancher CPU.
- Les cartes illustrées (PNG de fond) et le mode VTT/table : chemins de rendu
  différents, non mesurés ici.
- La consommation mémoire de l'undo de sculpture (documentée : jusqu'à 33 792 entrées
  pour un trait) : pas de fuite identifiée, mais à borner pour les très longs traits.
