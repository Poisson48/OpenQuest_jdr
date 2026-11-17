# 01 — Diagnostic perf : déplacement / rotation / redimensionnement d'objets 3D

> **Symptôme utilisateur (verbatim)** : « dans l'éditeur de map 3d déplacer un objet ou
> le tourner fait freez le jeu une ou deux secondes, ça doit être fluide ».
>
> **Périmètre** : `game/scripts/maps/map_complex_editor.gd`,
> `game/scripts/maps/editor/map_editor_edit_ops.gd`,
> `game/scripts/maps/editor/map_edit_document.gd`,
> `game/scripts/maps/complex_map_engine_3d.gd`, `game/scripts/maps/map_layers/*.gd`,
> `game/scripts/maps/editor/map_editor_overlay.gd`.
>
> **Reproducteur livré** : `game/scripts/debug/perf_probe_transform.gd` (voir §2).
>
> Date : 2026-11-17 · Godot **4.7.2-stable** · Windows · dépôt `D:\git\OpenQuest_jdr`.
> Aucun fichier de production n'a été modifié (lecture seule, sonde + notes uniquement).

---

## 1. Résumé exécutif

Le déplacement et la rotation **pendant le geste** sont bien incrémentaux (0,03–0,17 ms
par mouvement de souris, aucun rebuild de couche, nœud 3D conservé). Le gel de 1–2 s **ne
vient pas du drag** : il vient de **ce qui se passe au relâchement du bouton**, et de la
**frame suivante** :

| # | Cause | Coût mesuré (carte cité HD, 114 objets 3D) | Effet perçu |
|---|---|---|---|
| **1** | `_on_pointer_released` déclenche **DEUX `_sync_engine()` complets** (commit → signal `changed("commit")` → sync #1, puis `_ed._sync_engine()` explicite → sync #2). | **3,1–3,8 s** de release = ratio **×1,7–2,4** d'un `_sync_engine` (1,52–2,16 s) | le freeze à chaque fin de drag, déplacer **ou** tourner |
| **2** | Un `_sync_engine()` = `engine.configure()` qui **reconstruit toutes les couches sans aucune garde d'idempotence** ; la couche meshes (`MapMeshes3D.configure`) ré-instancie les **114 GLB** : **1,39–2,03 s** (un 2ᵉ appel immédiat coûte pareil). | `_rebuild_layers` = 1,39–1,64 s dont meshes **1,39–1,65 s** | c'est le contenu du freeze #1, payé deux fois |
| **3** | Au release, `_refresh_panels()` (et au 1ᵉʳ clic de sélection) diffère le rebuild **outliner** + **inspecteur** : outliner **338–504 ms**, inspecteur mesh **27–35 ms**. | frame suivante du release **396–531 ms** ; frame du 1ᵉʳ clic **404–497 ms** | prolonge le gel après le relâchement et gèle le premier clic |
| **4** | Rotation/redimensionnement d'un **décor non-mesh** (`KIND_PROP`) : aucune API live (le moteur appelle `set_prop_fields`, **méthode inexistante**), et `_apply_handle_rotate` force `_live_incremental = false`. Le 3D ne bouge qu'au rebuild du release. | rotation décor **0,03–0,04 ms/mouvement** mais **0/10 mouvements appliqués au nœud 3D** ; release 3,11–3,81 s | l'objet semble ne pas tourner pendant le drag ; seule la fin de drag (rebuild) le fait bouger |
| **5** | Chemins multi-sync par élément : décor contextuel des murs (`add_element`/`remove_element` émettent `changed("add"/"remove")` **par élément**, jamais filtré par `_live_incremental`). | non mesuré sur la cité (aucun mur) ; **vérifié par code**, jusqu'à ~2 + N + N rebuilds par release de mur | freezes bien pires sur les cartes à murs décorés |
| **6** | Autosave `SAVE_ON_CHANGE` : au release, si `_live_incremental` est faux (rotation/resize de décor), `_on_doc_changed` appelle `save_now()` → sérialise toute la carte + `MapData.save_maps()` (écrit **toutes** les cartes). | non mesuré (conditionnel au réglage utilisateur) | gel supplémentaire pour les utilisateurs en autosave |
| **7** | Coût par mouvement de souris : redraw overlay `_draw()` **4,1–5,2 ms**, hit-test `elements_at_screen` **4,7–8,6 ms** au press. | ~5–9 ms | marge de fluidité (60 Hz = 16,6 ms/frame) ; pas la cause du gel 1–2 s |
| **8** | Divers : `doc.to_map_data()` 2,4–3,7 ms, `_load_ground()` 53–68 ms par rebuild, `JSON.stringify` des deltas undo, `layout_changed` émis sans abonné. | quelques ms | négligeable devant #1/#2 |

**Conclusion** : le commit `d4eca08` a bien supprimé le freeze **pendant** le drag, mais le
contrat « **une édition = un rebuild complet** » n'a pas changé : il a juste été déplacé du
`move` vers le `release`, en **double**. La cible « fluide » exige de rendre le **commit**
incrémental et de **ne plus reconstruire les couches** sur un simple changement de
transform.

---

## 2. Méthode de mesure et reproto repro

### 2.1 Reproducteur

`game/scripts/debug/perf_probe_transform.gd` (nouveau fichier, aucune modification de prod) :

```powershell
& "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\
  GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\
  Godot_v4.7.2-stable_win64_console.exe" `
  --headless --path game --script res://scripts/debug/perf_probe_transform.gd
```

Durée observée : **60–100 s** (le script fait volontairement plusieurs rebuilds), sortie
`[perf] ...`, terminaison `quit(0)` (sonde, pas de test d'assertion). Il fait :

1. charge la carte lourde `res://scripts/debug/cite_eau_boot.gd` (`build_map(MapData)` :
   44×32 cases, **114 meshes**, canal + lac, preset `cinema`) dans `map_editor.tscn` ;
2. mesure un `_sync_engine()` complet (référence) et son sous-découpage
   (`doc.to_map_data`, `engine.configure`, `_load_ground`, `_rebuild_layers`,
   `_meshes_layer.configure`, boucle `_build_mesh` répliquée, panneaux, overlay) ;
3. joue un **cycle réel** sur un mesh : `_on_pointer_pressed` → `_on_pointer_moved` × 10 →
   `_on_pointer_released` (wrapper public de l'éditeur, donc chemin de code réel) ;
4. rejoue le même cycle sur la **poignée de rotation** d'un mesh, puis sur un **décor
   `KIND_PROP`** (créé par la sonde : un PNG jouet dans `user://`, un `add_element`, puis
   press/move/release via les vraies poignées) ;
5. mesure séparément les briques du release (`commit_live_edit`, `_sync_engine`,
   `_rebuild_lights_illumination`, `_refresh_context_decor_for_walls`, `_refresh_panels`,
   inspecteur, outliner) et reconstitue le release pour vérifier l'addition.

### 2.2 Contexte / limites

- `--headless` : pas de rendu réel (rendering driver dummy). Les coûts **CPU** mesurés
  sont donc un **plancher** : sur une vraie fenêtre, la duplication de matériaux par
  surface et l'upload GPU des rebuilds s'ajoutent (cf. §5, cause 2).
- Carte de test = celle du test existant (`cite_eau_boot`, 114 objets), la plus lourde du
  dépôt. Les valeurs absolues dépendent de la machine ; les **rapports** entre postes sont
  stables et recoupés sur 6 runs (et recoupés par la sonde Lead
  `perf_probe_layers.gd`, qui trouve aussi ~15 ms/objet en rebuild in-scene).
- Aucune autre instance Godot n'a été lancée pendant les runs retenus (7 runs dépouillés).

### 2.3 Chiffres de référence

| Poste mesuré | Valeur (min–max sur 7 runs) |
|---|---:|
| `load_map()` (1ᵉʳ build complet + 1ᵉʳ `_sync_engine`) | **1 893–2 184 ms** |
| `_sync_engine()` complet | **1 520–2 159 ms** (moyenne par run : 1 541–2 071) |
| ↳ `doc.to_map_data()` | 2,4–3,7 ms |
| ↳ `engine.configure()` | 1 515–1 706 ms |
| ↳ `_load_ground()` | 53–68 ms |
| ↳ `_rebuild_layers()` | **1 387–1 642 ms** |
| ↳ `_meshes_layer.configure()` (114 objets) | **1 391–1 653 ms** |
| ↳ 2ᵉ `_meshes_layer.configure()` immédiat | **1 511–2 029 ms** (aucune idempotence) |
| ↳ `_props_layer.configure()` (0 décor sur cette carte) | 4–6 ms |
| `_build_mesh()` hors scène, objet seul (114 objets) | **146–189 ms** (**1,4–1,8 ms/objet**) |
| `_build_mesh()` + `add_child` in-scene, 114 objets (réplique de `configure`) | **1 434–1 522 ms** (build 1 430–1 517 + add ~2 + dup. entrées ~2), pire objet **52–54 ms** (`maison_grande.glb` / `grange.glb`) |
| ménage (`free()`) des 114 nœuds | 17–20 ms |
| `_outliner.rebuild()` | **338–504 ms** |
| `_inspector.rebuild()` (mesh sélectionné) | 24–35 ms |
| overlay `_draw()` | 4,1–6,1 ms |
| `elements_at_screen()` (114 éléments) | 4,7–8,6 ms |
| **press** objet déjà sélectionné (démarrage drag) | 1,9–2,9 ms (frame suivante 4,2–6,6 ms) |
| **move mesh / mouvement** | **0,08–0,13 ms** (nœud conservé, transform appliquée) |
| **rotate mesh / mouvement** | **0,10–0,17 ms** (yaw appliqué en live) |
| **move prop / mouvement** | 0,04–0,06 ms (position appliquée en live) |
| **rotate prop / mouvement** | 0,03–0,04 ms — **0/10 appliqués au nœud 3D** |
| **release move mesh** | **3 072–3 612 ms** (frame suivante 396–531 ms) |
| **release rotate mesh** | **3 095–3 535 ms** (frame suivante 414–486 ms) |
| **release move prop** | 3 089–3 526 ms |
| **release rotate prop** | 3 110–3 805 ms (frame suivante 432–500 ms) |
| commit `commit_live_edit()` seul (contient le sync #1) | 1 535–1 899 ms |
| `_sync_engine()` explicite (le 2ᵉ du release) | 1 536–1 794 ms |
| release reconstitué (commit + sync + divers) | **3 083–3 697 ms** |
| release réel de contrôle | 2 891–4 055 ms · **ratio release/_sync = 1,7–2,4 (~2)** |
| `_rebuild_lights_illumination([mesh])` (no-op non-lumière) | 0,01–0,03 ms |
| `_refresh_context_decor_for_walls([mesh])` (early-return sans décor) | 1,7–2,3 ms |
| `_refresh_panels()` partie synchrone | 0,8–2,5 ms |
| frame différée du 1ᵉʳ clic de sélection | **404–497 ms** |

Ces chiffres suffisent à reconnaître le symptôme : **un clic-glisser-relâcher sur un
objet de la cité coûte ~3,5 s de gel CPU en headless** (et le premier clic ~0,5 s de plus) ;
sur une carte plus légère, la même arithmétique donne les 1–2 s observés par l'utilisateur.

---

## 3. Causes classées (de la plus coûteuse à la moindre)

### C1 — Le release reconstruit TOUT, **deux fois** (3,1–3,8 s mesurés)

**Chemin d'appel** (déplacement) :

```
_on_pointer_released (map_editor_edit_ops.gd:427-432)
  └─ doc.commit_live_edit(ids, "Déplacement")            (map_edit_document.gd:1012)
       └─ changed.emit("commit")                        (map_edit_document.gd:1027)
            └─ _on_doc_changed("commit")                (map_complex_editor.gd:4427)
                 └─ _sync_engine()        ← rebuild #1 (le garde-fou ne couvre QUE "modify")
  └─ _construction._refresh_context_decor_for_walls(ids)
  └─ _rebuild_lights_illumination(ids)
  └─ _ed._sync_engine()                ← rebuild #2 explicite
  └─ (fin) _refresh_panels() → call_deferred(rebuild inspector + outliner)  ← frame suivante
```

Extraits :

```gdscript
# game/scripts/maps/editor/map_editor_edit_ops.gd:427
"move":
    if _ed._press_moved:
        _ed.doc.commit_live_edit(_ed._drag_ids, "Déplacement")
        _ed._construction._refresh_context_decor_for_walls(_ed._drag_ids)
        _ed._rebuild_lights_illumination(_ed._drag_ids)
        _ed._sync_engine()          # ← 2e reconstruction complète
```

```gdscript
# game/scripts/maps/editor/map_edit_document.gd:1027
commit_transaction()
changed.emit("commit")              # ← déclenche déjà _sync_engine() côté éditeur
```

```gdscript
# game/scripts/maps/map_complex_editor.gd:4437-4440
var live_incremental := _press_mode in ["move", "resize", "rotate"] and _live_incremental
if reason in ["undo", "redo", "meta", "fog", "tiles", "order", "light_reveal",
        "modify", "commit", "add", "remove"]:
    if not (live_incremental and reason == "modify"):
        _sync_engine()          # ← "commit" n'est jamais filtré
```

**Preuve mesurée** : `commit_live_edit()` seul = **1 535–1 899 ms** (il contient le sync #1
via le signal) ; `_sync_engine()` explicite = **1 534–1 794 ms** ; les deux additionnés
reconstituent le release mesuré (3 083–3 697 ms prévus vs 3 072–3 805 ms réels, ratio
release/_sync **1,7–2,4**). Le nœud 3D est **remplacé** au release (`get_instance_id()`
change) : c'est bien un rebuild, pas une mise à jour.

**Pourquoi c'est inutile ici** : pendant le drag, `set_live_position`/`set_live_fields` +
`engine.set_element_position`/`set_element_live_fields` ont **déjà** appliqué la
transform aux nœuds 3D (vérifié : nœud identique, x/y ou yaw à jour). Le commit n'a donc
que deux choses à faire : pousser le **delta undo** et rafraîchir les panneaux. Rien à
reconstruire.

**Correctif proposé**
- **A. Supprimer le 2ᵉ `_sync_engine()` explicite** du release (move/resize/rotate). Fait
  passer le release de ~3,3 s à ~1,6 s. *Effort S (30 min), risque faible, impact −50 %.*
- **B. Ne pas router `commit_live_edit` vers `_sync_engine()`** : dans `_on_doc_changed`,
  traiter `reason == "commit"` comme `"modify"` quand `_press_mode in ["move","resize",
  "rotate"]` et que `_live_incremental` est vrai (ou mieux : ne jamais émettre `"commit"`
  depuis `commit_live_edit` — l'éditeur sait déjà qu'il vient de committer). *Effort S,
  risque faible, impact release → ~0 ms de rebuild.*
- **C. Rendre le commit 100 % incrémental** (cible finale) : à la fin du drag, ne faire
  que (i) `push_delta` undo, (ii) mise à jour des nœuds déjà faite, (iii) rafraîchir les
  panneaux concernés. Aucun `configure()`. *Effort M, risque moyen (undo/redo, murs
  attachés), impact : release < 50 ms.*

---

### C2 — `_sync_engine()` / `engine.configure()` reconstruit toutes les couches sans idempotence (1,39–2,03 s par appel)

**Chemin d'appel** :

```
_sync_engine()                              (map_complex_editor.gd:4088)
  └─ doc.to_map_data()                      (map_edit_document.gd:362)  ~2,5 ms
  └─ engine.configure(snapshot, …)          (complex_map_engine_3d.gd:531)
       ├─ _load_ground()                    (l.1268)  ~55–68 ms
       ├─ _load_backdrop / _load_water / _load_ambient_fx / _load_vegetation / _load_elevations
       └─ _rebuild_layers()                 (l.2346)
            ├─ _props_layer.configure()     (map_props_3d.gd:47)
            ├─ _meshes_layer.configure()    (map_meshes_3d.gd:163)  ← 1,39–1,65 s
            ├─ _walls_layer.configure()
            └─ _lights_layer.configure()
```

Extrait de la boucle coupable :

```gdscript
# game/scripts/maps/map_layers/map_meshes_3d.gd:183
for child in get_children():
    remove_child(child)
    child.free()
_nodes.clear()
_mesh_entries.clear()
...
for mesh_variant in meshes:
    var mesh: Dictionary = mesh_variant
    if bool(mesh.get("hidden", false)):
        continue
    var node := _build_mesh(mesh)          # instancie le GLB + matériaux + ombre
    if node == null:
        continue
    add_child(node)
    _nodes[str(mesh.get("id", ""))] = node
    _mesh_entries[str(mesh.get("id", ""))] = mesh.duplicate(true)
```

**Preuves mesurées**
- `_rebuild_layers()` = **1 387–1 642 ms**, dont `_meshes_layer.configure()` =
  **1 391–1 653 ms**. Le reste des couches ≈ 20–50 ms.
- **Aucune garde d'idempotence** : deux `_sync_engine()` consécutifs sans modification de
  la carte coûtent **1 520 / 1 546 ms** (run 5 : 1 542,1 / 1 546,8 / 1 539,2) ; deux
  `_meshes_layer.configure()` immédiats : 1 391 puis 1 653 ms.
- Une réplique exacte de la boucle (build + add, dans la couche réelle) coûte
  **1 434–1 522 ms** avec un pire objet à **52–54 ms** (`maison_grande.glb`, `grange.glb`), alors que les
  mêmes 114 `_build_mesh()` **hors scène** coûtent **146–189 ms** (1,4–1,8 ms/objet). Le
  coût marginal (~13–15 ms/objet) apparaît donc quand les objets **restent vivants dans la
  scène** : enregistrement des instances de rendu + duplication d'un matériau **par
  surface** de chaque GLB (`_sanitize_visual` → `_apply_lit_materials` →
  `_lit_material` : `source.duplicate()`), plus la création des ombres de contact
  (`_add_contact_shadow`). La sonde Lead `perf_probe_layers.gd` retrouve ce même
  ~15 ms/objet.
- À comparer : `_props_layer.configure()` = 4–6 ms (0 décor ici) ; la couche eau
  (`map_water_3d.gd:175-186`) **a** une garde d'idempotence (`_arrays_equal` /
  `str()` comparés puis `return`) — le pattern à généraliser.

**Correctif proposé**
- **A. Garde d'idempotence par couche** : dans `MapMeshes3D.configure` (et `MapProps3D`,
  `MapWalls3D`, `MapLights3D`, `MapGround3D`), mémoriser une empreinte bon marché de
  l'entrée (`size` + hash des ids + hash des transforms/asset) et `return` si identique.
  Coût d'un `_sync_engine()` « à vide » → ~5–10 ms. *Effort M, risque faible, impact :
  supprime les rebuilds inutiles (C5, autosave, sélections, réglages).*
- **B. Sync par couche sale** : `_sync_engine(dirty: Dictionary)` où `dirty` liste les
  couches touchées (`meshes`, `props`, `walls`, `water`, `terrain`, `lights`) ; l'éditeur
  déduit `dirty` du `reason`/des `ids`. `engine.configure_layer(kind)` plutôt que
  `configure()` complet. *Effort M-L, risque moyen, impact : une édition d'objet ne
  touche plus jamais terrain/eau/lumières (~60–100 ms économisés par sync) et l'on peut
  viser 0 rebuild en transform.*
- **C. Pool/réutilisation dans `MapMeshes3D`** : `upsert_mesh(id)`/`remove_mesh(id)` qui
  gardent les nœuds existants (asset identique) et ne reconstruisent que l'objet modifié.
  C'est le vrai correctif de fond ; il rend aussi `refresh_meshes_only()` complet.
  *Effort L, risque moyen (ombres, contact shadow, bridges), impact : rebuild d'un objet
  ~15 ms au lieu de ~1 500 ms.*

> ⚠️ Le simple fait de supprimer le 2ᵉ sync (C1-A/B) laisse **1,54–2,07 s par release** :
> insuffisant pour « fluide ». C2-C (ou à défaut C1-C) est indispensable.

---

### C3 — Rebuild **différé** inspecteur + outliner à chaque release et au 1ᵉʳ clic (338–504 ms)

```gdscript
# game/scripts/maps/map_complex_editor.gd:4395
func _refresh_panels() -> void:
    if _inspector:
        _inspector.call_deferred("rebuild")
    if _outliner:
        _outliner.call_deferred("rebuild")
    if _minimap:
        _minimap.set_context(_engine, doc)
    _refresh_breadcrumb()
    _refresh_history()
    _refresh_effect_list()
    _refresh_status_badges()
```

```gdscript
# game/scripts/maps/editor/map_editor_outliner.gd:45
func rebuild() -> void:
    ...
    for elem_variant in doc.elements_sorted():       # 114 éléments
        ...
    for i in range(layers.size() - 1, -1, -1):
        ...
        _add_element_row(items[j])                   # ~1 contrôle par élément + thème
```

`_refresh_panels()` est appelé par `_on_pointer_released` (`edit_ops:496`, quand
`was_live`), et par `_on_selection_changed` (`map_complex_editor.gd:4447`) → **chaque
premier clic sur un objet**.

**Preuves mesurées** : `_outliner.rebuild()` = **338–504 ms**, `_inspector.rebuild()` pour
un mesh = **27–35 ms**. Frame suivant le release = **396–531 ms** ; frame du 1ᵉʳ clic =
**404–497 ms**. La partie synchrone de `_refresh_panels()` (breadcrumb/historique/badges/
minimap) est négligeable (0,8–2,5 ms) : **tout le coût est dans les rebuilds différés**.

**Correctif proposé**
- Sur une **sélection** ou un **release de transform**, ne pas reconstruire l'arbre :
  mettre à jour la ligne sélectionnée (`_highlight_selected()`) et l'inspecteur
  uniquement si le kind change. Un `rebuild()` complet throttlé (drapeau `_dirty` +
  `call_deferred` coalescent, ou 1 rebuild max / 250 ms pendant une rafale) suffit.
  *Effort S-M, risque faible, impact −0,4 à −0,5 s par clic/release.*
- Découpler `_refresh_panels()` en `refresh_selection()` (léger) et `rebuild_tree()`
  (lourd, réservé aux add/remove/undo/redo/load). *Effort S, risque faible.*

---

### C4 — Rotation/redimensionnement des décors non-mesh : **aucune mise à jour live**, et flag `_live_incremental` faux

```gdscript
# game/scripts/maps/editor/map_editor_edit_ops.gd:634
func _apply_handle_rotate(grid: Vector2) -> void:
    ...
    var elem: Dictionary = _ed.doc.get_element(id)
    var is_mesh := str(elem.get("kind", "")) == DocumentScript.KIND_MESH
    _ed._live_incremental = is_mesh          # ← false pour PROP / LIGHT / WALL legacy
    _ed.doc.set_live_fields(id, fields)
    if is_mesh:
        _ed._engine.set_element_live_fields(id, fields)   # ← jamais appelé sinon
```

```gdscript
# game/scripts/maps/complex_map_engine_3d.gd:3047
func set_element_live_fields(element_id: String, fields: Dictionary) -> void:
    if _meshes_layer and _meshes_layer.has_method("set_mesh_fields"):
        _meshes_layer.set_mesh_fields(element_id, fields)
    if _props_layer and _props_layer.has_method("set_prop_fields"):
        _props_layer.set_prop_fields(element_id, fields)   # ← n'existe PAS
```

`grep` : `map_props_3d.gd` n'expose que `set_prop_position` (l.264) — pas de
`set_prop_fields`. L'appel est **silencieusement ignoré** (`has_method` cache le bug).

**Preuves mesurées** (décor `KIND_PROP` créé par la sonde) :
- rotation : **0,03–0,04 ms/mouvement**, nœud 3D identique pendant **tout** le drag,
  yaw nœud **−0,00 → −0,00** alors que le document passe à **−157,86°** ;
  **0/10** mouvements où le nœud a suivi le doc ;
- au release, le nœud est **remplacé** par le rebuild et le yaw devient enfin **−157,86°**.
- le même trou existe au **redimensionnement** d'un décor : `_apply_handle_resize`
  (`edit_ops:552-595`) n'envoie des `fields` au moteur que pour `KIND_MESH` (et
  `KIND_LIGHT`, rayon). Un décor redimensionné ne change de taille qu'au release.
- `_live_incremental = false` pendant ces gestes a un second effet : si un `changed`
  `"modify"`/`"commit"`/`"add"` part pendant le drag (mur raccordé, décor contextuel,
  autosave…), la condition `map_complex_editor.gd:4437-4439` ne filtre plus rien →
  rebuild complet **par mouvement**, exactement le symptôme d'origine.

**Correctif proposé**
- **A. Implémenter `MapProps3D.set_prop_fields(id, fields)`** : rotation
  (`root.rotation_degrees.y = -display.rotation`, ou `mesh.rotation_degrees.x` pour un
  décor à plat), échelle/taille (`QuadMesh.size`, `display.scale`), toggle `standing`.
  Puis router **tous** les kinds via `set_element_live_fields` (mesh, prop ; lumière =
  position/rayon ; token/effect/zone = position). *Effort S-M, risque faible, impact :
  le décor tourne/scale pendant le drag, plus besoin du rebuild pour « voir » le résultat.*
- **B. Supprimer `_ed._live_incremental = is_mesh`** et le remplacer par « vrai si le
  kind a une API live » (table de capacités). Sinon garder au minimum
  `_live_incremental = true` pour ne pas armer un rebuild en plein geste. *Effort S,
  risque faible.*
- **C. Test de capacité** : le test existant doit échouer si un kind sélectionnable n'a
  pas de méthode live correspondante (voir §4).

---

### C5 — Chemins multi-sync par élément (murs + décor contextuel) — vérifié par code

```gdscript
# game/scripts/maps/editor/map_editor_construction.gd:2231
func _refresh_context_decor_for_walls(wall_ids: Array) -> void:
    ...
    _ed.doc.remove_elements(old_decor)          # 1 changed("remove") PAR élément
    for id_variant in wall_ids:
        ...
        _decorate_wall_context(wall)            # jusqu'à 8 add_element → 8 changed("add")
```

```gdscript
# game/scripts/maps/editor/map_edit_document.gd:880
func add_element(...) -> String:
    ...
    changed.emit("add")          # ← _on_doc_changed("add") → _sync_engine() complet
```

`_on_doc_changed` ne filtre `"add"`/`"remove"` que par `live_incremental` **et**
`reason == "modify"` : un ajout/suppression **pendant un drag** déclenche un rebuild
complet **par élément**. Sur une carte avec murs décorés, le release d'un mur peut donc
coûter `2 + N_retirés + N_ajoutés` rebuilds (jusqu'à ~18 × ~1,5 s).

**Preuve** : code (`add_element`/`remove_element` émettent par élément,
`map_complex_editor.gd:4438-4440`) ; non mesuré sur la cité (aucun mur). La sonde mesure
`_refresh_context_decor_for_walls([mesh])` = **1,7–2,3 ms** (early-return sans décor), donc
c'est bien le cas « mur avec décor » qui explose.

**Correctif proposé**
- **Batch de signaux** : `MapEditDocument` émet `changed(reason, ids)` **une seule fois**
  par transaction (les `begin_transaction`/`commit_transaction` existent déjà) ;
  `_on_doc_changed` ne sync qu'une fois. *Effort M, risque moyen (ordre des signaux,
  undo), impact : supprime les multiplicateurs N.*
- Ou au minimum : dans `_refresh_context_decor_for_walls`, ouvrir une transaction et
  suspendre les syncs (`_syncing`) le temps du batch, puis un seul `_sync_engine()`.
  *Effort S, risque faible.*

---

### C6 — Autosave `SAVE_ON_CHANGE` au release (conditionnel)

```gdscript
# game/scripts/maps/map_complex_editor.gd:4442
if _save_policy == SAVE_ON_CHANGE and doc.is_dirty() and reason != "load" \
        and not live_incremental:
    save_now()
```

`save_now()` (`l.583`) fait `apply_to_map_data()` (→ `doc.to_map_data()`, 2,4–3,7 ms) puis
`MapData.update_map(snapshot)` → `save_maps()` → `_save_json(MAPS_PATH, maps)` : **écrit
tout le fichier de cartes sur disque** (`map_data.gd:1702-1711`, `:214-216`).

En rotation **de décor**, `live_incremental` est faux (C4) → **chaque release déclenche
l'écriture disque**, en plus des 2 rebuilds. En déplacement de mesh, `live_incremental`
vrai → pas d'écriture à ce moment (mais un `changed` ultérieur la déclenchera).

**Correctif proposé** : ne pas sauvegarder sur `commit` de transform ; sauvegarde
différée/coalescée (500 ms–2 s d'inactivité), et n'écrire que la carte modifiée plutôt que
tout `maps`. *Effort S-M, risque faible, impact : supprime une écriture disque par
release.*

---

### C7 — Coût par mouvement de souris (4–9 ms) : déjà acceptable, marge de fluidité

`_on_pointer_moved` (`edit_ops:292`) fait à chaque mouvement : `_ed._refresh_ghost()`
(`map_complex_editor.gd:4194`, retourne vite si l'outil n'est pas de pose),
`_ed._refresh_overlay()` (`:4162` → `queue_redraw()`), `_ed._update_status_position()`.
Le vrai coût est le `_draw()` de l'overlay à la frame suivante : **4,1–5,2 ms**, et le
hit-test `elements_at_screen` au press : **4,7–8,6 ms** (`map_editor_overlay.gd:766-787` :
boucle sur **tous** les éléments + `_footprint()` = 4 projections chacun, `:86-96`).
Sur une carte 2× plus grande, ces coûts doublent → risque de tomber sous 60 FPS pendant le
drag.

**Correctif proposé** : index spatial simple (grille écran/grille de cases) pour le
hit-test, cache des `PackedVector2Array` de footprint recalculés seulement si
x/y/w/h/rotation changent, et ne redessiner que le rectangle sale. *Effort M, risque
faible, impact : per-move ~1–2 ms, robustesse sur grosses cartes.*

---

### C8 — Micro-coûts (quelques ms, à ne pas optimiser en premier)

- `doc.to_map_data()` : 2,4–3,7 ms — copie profonde **de toute la carte**
  (`map_data.duplicate(true)` + `duplicate(true)` de chaque payload d'élément,
  `map_edit_document.gd:362-453`). À supprimer du chemin d'édition (snapshot seulement au
  chargement/save).
- `_load_ground()` : 53–68 ms par `configure()` (reconstruit le maillage du terrain à
  chaque sync, `map_ground_3d.gd:618-674`) : à exclure des syncs d'édition (C2-B).
- Deltas undo : `_states_equal` = `JSON.stringify(a) == JSON.stringify(b)`
  (`map_edit_document.gd:1036-1037`), appelé 2× par élément commité. Négligeable pour 1
  objet, linéaire pour une multi-sélection (114 ids → ~1–2 ms).
- `_mesh_actual_dimensions` / `_mesh_aabb_cells` : **déjà cachés**
  (`_mesh_aabb_cache`, `map_editor_construction.gd:2615-2637`) — RAS.
- `_terrain_base_y` par objet dans `_place_root`/`_reseat_nodes` : ~µs, RAS.
- `layout_changed.emit()` (`map_complex_editor.gd:4445`) : **aucun abonné** dans le dépôt —
  signal mort, à supprimer (bruit, pas de coût mesurable).

---

## 4. Ce qui est déjà bon / ce qui manque au test

### 4.1 Déjà bon (à préserver dans le refactor)

1. **Drag de déplacement incrémental** : `_start_move_drag` (`edit_ops:280-290`) pose
   `_live_incremental = true` ; `_on_pointer_moved` (`:313-326`) fait
   `doc.set_live_position` + `engine.set_element_position` → **0,08–0,12 ms/mouvement**,
   nœud 3D conservé (`get_instance_id()` stable), transform réellement appliquée (vérifié).
2. **Rotation de mesh incrémentale** : `_apply_handle_rotate` (`:634-649`) →
   `set_element_live_fields` → `MapMeshes3D.set_mesh_fields` (`map_meshes_3d.gd:1467-1490`)
   → `_place_root` + repose de l'ombre de contact : **0,10–0,17 ms/mouvement**, yaw live.
3. **Redimensionnement de mesh incrémental** : `_apply_handle_resize` (`:552-586`) pose le
   flag **avant** la mutation du document (commentaire l.581-583) et route les `fields`
   (`w/h/sizeX/Y/Z`, `display.scale`) au moteur.
4. **Le test `editor_drag_perf_test.gd` protège bien les per-move** : `MAX_STEP_SECONDS =
   0.12`, vérifie nœud non remplacé + transform appliquée (l.66-132). C'est ce qui a rendu
   `d4eca08` possible.
5. **Caches déjà en place** : `_mesh_aabb_cache` (dimensions GLB), cache de textures
   (`map_asset_library.gd:263-277`), garde d'idempotence de la couche eau
   (`map_water_3d.gd:175-186`), `refresh_meshes_only()` (`complex_map_engine_3d.gd:625`)
   pour la gomme, `set_terrain_heights`/`set_terrain_carves`/`set_terrain_sculpt`
   incrémentaux pour le relief.
6. **`_mesh_fields`/`_prop_position` existent déjà** côté couche : il manque peu de chose
   pour une API live complète (cf. C4).

### 4.2 Ce qui manque au test existant (`game/scripts/tests/editor_drag_perf_test.gd`)

Le test ne couvre que `_on_pointer_moved` en **forçant l'état à la main** ; il ne teste ni
le press ni le release, donc **il ne peut pas voir la régression n°1** :

| Manque | Conséquence |
|---|---|
| Aucun appel à `_on_pointer_pressed` / `_on_pointer_released` (le test pose `_press_mode`, `_live_incremental`, `_drag_ids`, `_drag_origins`, `_handle_state` directement, l.59-65/81-90/107-118) | ne vérifie pas le **contrat réel** press→move→release ; ne mesure pas le coût du commit |
| Aucun budget sur le release (`MAX_STEP_SECONDS` ne s'applique qu'aux moves) | les **2 rebuilds + panneaux** (3,1–3,8 s) passent inaperçus |
| Aucun test **non-mesh** (prop/décor, lumière, mur) en rotate/resize | rate `_live_incremental = is_mesh` et l'absence de `set_prop_fields` (C4) |
| Aucune assertion que le **nœud 3D est conservé au release** (seulement pendant le drag) | un release qui rebuild n'est pas détecté ; le test tolère que la transform soit « rattrapée » par un rebuild |
| Aucune vérification de cohérence **doc ↔ nœud 3D après release** pour chaque kind | rate les mises à jour silencieusement perdues (`has_method` faux) |
| Aucune mesure de `_refresh_panels()` / `_inspector.rebuild` / `_outliner.rebuild` | rate C3 (~0,4–0,5 s) |
| Aucune mesure d'idempotence : `_sync_engine()` deux fois de suite | rate C2 (pas de garde) |
| Aucun test du **release sans rebuild** (compteur d'appels `configure` ou identité de nœuds) | le contrat cible du refactor n'est pas verrouillé |

**Test cible à ajouter** (peut s'appuyer sur la sonde livrée) :
`editor_transform_commit_test.gd` qui, sur la carte cité (ou une carte réduite) :
1. fait le vrai `_on_pointer_pressed` → `_on_pointer_moved` × N → `_on_pointer_released` ;
2. exige `release < 50 ms` **et** `engine._meshes_layer._nodes[id]` **conservé**
   (`get_instance_id()` identique) pour move/rotate/resize de mesh ;
3. exige qu'un décor tourné/redimensionné ait son nœud 3D à jour **avant** le release
   (yaw/scale, `instance_id` identique) ;
4. compte les `configure()` via un compteur injecté (ou vérifie que le nombre de nœuds
   reconstruits est 0) ;
5. surveille la frame suivante (`< 100 ms`) pour attraper les rebuilds différés de
   panneaux ;
6. vérifie `doc.get_element(id)` == transform du nœud 3D après release (cohérence).

---

## 5. Implications pour la refacto en cours

### 5.1 Le contrat à changer (cause racine commune)

Le fil rouge est le même que celui du rapport global
(`docs/refactor/RAPPORT_PERFORMANCE_EDITEUR_3D.md`) : `MapEditDocument` → `changed(reason)`
→ `_on_doc_changed` → **`to_map_data()` + `engine.configure()` complet**. Pour le
transform, le contrat cible est :

```
press  : sélectionner (léger) + démarrer le drag
move   : apply_live_transform(ids, fields)        (déjà fait, 0,1 ms)
release: commit_delta(ids)  +  refresh_selection() (léger)
         AUCUN configure(), AUCUN rebuild de couche, AUCUN rebuild d'arbre complet
```

### 5.2 Modules à découper (proposition)

| Module proposé | Responsabilité | Contenu à extraire |
|---|---|---|
| `MapEditorSyncController` | décider **quoi** resynchroniser | logique de `_on_doc_changed` (`map_complex_editor.gd:4427`) : raison → ensembles `dirty_layers`/`dirty_ids`, garde d'idempotence par couche, debounce/coalescing une frame |
| `MapEditorLiveTransform` | API live par kind | table de capacités `KIND_* → méthodes live` ; remplace les `if is_mesh` de `edit_ops` (`:583-586`, `:634-649`) et le routage partiel de `set_element_live_fields` |
| `MapMeshes3D` scindé | *factory* (build GLB, matériaux, ombre) vs *updater* (`set_mesh_fields`, `upsert_mesh`, `remove_mesh`) + pool | `_build_mesh`/`_sanitize_visual`/`_lit_material` (`map_meshes_3d.gd:451,1298,1384`) et le besoin d'un `update_mesh(id)` sans `free()` |
| `MapProps3D` | ajouter `set_prop_fields` (rotation/scale/taille) | `map_props_3d.gd:264-273` (n'a que `set_prop_position`) |
| `MapEditorPanels` | rebuilds coalescés | `_refresh_panels` (`map_complex_editor.gd:4395`), `_on_selection_changed` (`:4447`), `_refresh_history`, `rebuild()` outliner/inspector |
| `MapEditDocument.commit` | commit sans signal lourd | `commit_live_edit` (`map_edit_document.gd:1012-1027`) : ne doit pas émettre un `changed("commit")` qui route vers un rebuild complet ; signal séparé `transform_committed(ids)` |

### 5.3 API incrémentale manquante, par kind d'élément

| Kind | Position live | Rotation/échelle live | Manque |
|---|---|---|---|
| `mesh` (KIND_MESH) | ✅ `set_mesh_position` (`map_meshes_3d.gd:1443`) | ✅ `set_mesh_fields` (`:1467`) | rien côté API ; coût de `_place_root` OK |
| `prop` (KIND_PROP) | ✅ `set_prop_position` (`map_props_3d.gd:264`) | ❌ **rien** | `set_prop_fields` (rotation `root.rotation_degrees.y` / `mesh.rotation_degrees.x` à plat, `QuadMesh.size`, `display.scale`, `standing`) |
| `light` (KIND_LIGHT) | ✅ `set_light_position` (`set_element_position` l.3034) | rayon ✅ `set_light_radius` (`:3054`) ; énergie/couleur ❌ | `set_light_fields` (energy/color/flicker) si on veut le live complet ; et `_refresh_light_mask_live` seulement en mode nuit |
| `token` / `effect` / `zone` | ✅ `set_element_position` (`:3021-3043`) | rotation/échelle ❌ | faible priorité (pas de poignées rot/scale) |
| `wall` (mesh asset `mur*`) | ✅ via mesh | ✅ via `set_mesh_fields` (mais `_apply_wall_handle_resize` a son propre chemin `construction:488`) | vérifier que le resize mur passe bien par le live ; sinon rebuild |
| eau / végétation / relief | n/a (données de couche) | n/a | garder `set_water_bodies`/`set_terrain_*` et **ne pas** les resynchroniser sur un transform d'objet (dirty layers) |

### 5.4 Cibles chiffrées pour la refacto

| Scénario | Aujourd'hui (mesuré) | Cible après correctifs |
|---|---:|---:|
| move/rotate mesh par mouvement | 0,08–0,17 ms | inchangé (déjà bon) |
| **release** move/rotate mesh | **3,1–3,8 s + 0,4–0,5 s différé** | **< 50 ms** (commit delta + panneaux légers) |
| rotate/resize **décor** pendant le drag | 3D figé (0/10 maj) | 3D live (~0,1 ms) |
| release rotate décor | 3,1–3,8 s | < 50 ms |
| 1ᵉʳ clic de sélection | 0,4–0,5 s (frame différée) | < 30 ms (highlight seulement) |
| `_sync_engine()` à vide (idempotence) | 1,54–2,07 s | < 10 ms |
| release d'un mur décoré (N décos) | ~(2+N+N) rebuilds | 1 batch, 0 rebuild |

Ordre de mise en œuvre recommandé (rapport gain/risque) :
**C1-A/B (quick win, −50 % immédiat)** → **C3 (panneaux, −0,4 s)** → **C4 (décors live,
corrige un bug fonctionnel)** → **C2-A (garde d'idempotence)** → **C2-B/C (dirty layers +
pool meshes, le vrai correctif)** → **C5/C6/C7**.

---

## 6. Annexe — sortie de mesure (run de référence)

Commande : `Godot_v4.7.2-stable_win64_console.exe --headless --path game
--script res://scripts/debug/perf_probe_transform.gd` (carte cité, 114 meshes).

```
[perf] _sync_engine() complet #1 : 2159.2 ms
[perf] _sync_engine() complet #2 : 2115.2 ms
[perf] _sync_engine() complet #3 : 1937.8 ms
[perf] _sync_engine() → min 1937.8 · moy 2070.7 · max 2159.2 ms (n=3)
[perf] doc.to_map_data() seul : min 3.46 · moy 3.71 ms
[perf] engine.configure() seul : min 1655.6 ms
[perf]   dont _load_ground()      : 53.4 ms
[perf]   dont _rebuild_layers()   : 1483.6 ms
[perf]   dont _inspector.rebuild() : 1.0 ms · _outliner.rebuild() : 419.8 ms
[perf] reconfigure isolée : props 5.4/5.3 ms · meshes 1902.2/2029.3 ms (2e = idempotence)
[perf] _build_mesh() moyen (n=16) : 1.76 ms/objet · 114 objets → 200 ms
[perf] boucle _build_mesh() complète : 185.3 ms pour 114/114 objets (wall 188.9 ms)
[perf]   replique configure : build+add 114 objets = 1521.7 ms = build 1516.6 + add_child 2.7 + dup 1.8
[perf]   replique configure : build le plus lent 54.3 ms (maison_grande.glb)
[perf]   A/B : configure() reel (couche vide au depart) = 1591.3 ms

[perf] sélection (1er clic) : select_only 2.56 ms · frame différée 481.1 ms
       (inspector 34.3 + outliner 394.4 mesurés à part)
[perf] press (objet déjà sélectionné, start drag) : 1.9 ms — press_mode=move · frame suivante 4.5 ms
[perf] hit-test elements_at_screen() seul : 5.30 ms
[perf] move × 10 : min 0.07 · moy 0.09 · max 0.25 ms / mouvement
[perf] release (commit + rebuilds + panneaux) : 3289.3 ms — frame suivante 485.9 ms
[perf] release : nœud remplacé=true (rebuild) · position x 8.05 → 8.05

[perf] rotate mesh × 10 : min 0.11 · moy 0.17 · max 0.29 ms / mouvement
[perf] pendant la rotation : nœud identique=true · yaw -134.46 → -258.37 (mise à jour live)
[perf] release rotation mesh : 3379.5 ms — frame suivante 414.5 ms · nœud remplacé=true

[perf] rotate décor × 10 : min 0.02 · moy 0.04 · max 0.13 ms / mouvement
[perf] rotate décor : nœud identique pendant TOUT le drag=true · yaw nœud -0.00 → -0.00
       (attendu doc -157.86)
[perf] rotate décor : mouvements où le nœud 3D a suivi le doc = 0 / 10 (0 = update live PERDUE)
[perf] release rotation décor : 3804.9 ms · frame suivante 478.1 ms · nœud remplacé=true · yaw final -157.86

[perf] commit_live_edit() seul (dont _sync_engine #1 via signal) : 1898.7 ms
[perf] _sync_engine() explicite (2e du release) : 1793.6 ms
[perf] _rebuild_lights_illumination([mesh]) : 0.01 ms (no-op non-lumière)
[perf] _refresh_context_decor_for_walls([mesh]) : 2.03 ms
[perf] _refresh_panels() : 2.37 ms (rebuilds inspector/outliner différés non inclus)
[perf] release reconstitué = 1898.7 + 1793.6 + 0.01 + 2.03 + 2.37 = 3696.7 ms
[perf] release réel de contrôle (même état) : 3553.3 ms · ratio release/_sync = 1.83
```

Les autres runs (7 au total) donnent les mêmes proportions :
`_sync_engine` 1 520–2 159 ms, release 3 072–3 805 ms, ratio 1,7–2,4,
outliner 338–504 ms, frame différée 359–531 ms, moves 0,03–0,17 ms.
