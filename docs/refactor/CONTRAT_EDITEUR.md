# Contrat de test — éditeur de carte (`CONTRAT_EDITEUR`)

> Généré par `tools/refactor/editor_contract.ps1` le 2026-11-17 21:09. **Ne pas éditer à la main** : relancer le script.

## 1. À quoi sert ce document

Les tests headless de `game/scripts/tests/` instancient la scène `map_editor.tscn` et pilotent **directement** les membres de l'éditeur (y compris privés). Ce sont eux, pas `docs/ARCHITECTURE.md`, qui définissent l'API réellement utilisée :

- **Renommer / déplacer un membre listé ici casse un test** — ou ne casse rien et laisse le contrat dériver silencieusement ;
- lors des vagues d'extraction (phase 3 du plan), ces membres doivent rester exposés par des **wrappers** sur les god files ;
- un membre absent du tableau n'est pas forcément inutilisé par le jeu : il n'est simplement atteint par aucun test.

## 2. Méthode de mesure (reproductible)

1. scan de `game/scripts/tests/*.gd` (aucun autre dossier) ;
2. détection des variables d'instance par leurs initialiseurs :
   - éditeur : `(load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()` ou `<scene>.instantiate()` après chargement du PackedScene ;
   - document : `<DocScript>.new()` (script `map_edit_document.gd`), `load(...map_edit_document.gd).new()`, ou alias `var doc = <editor>.doc` ;
   - moteur : `<EngineScript>.new()` (script `complex_map_engine_3d.gd`), `load(...complex_map_engine_3d.gd).new()`, ou alias `var engine = <editor>._engine` ;
3. extraction des accès : `<instance>.<membre>` au premier niveau, plus `<editor>.doc.<membre>`, `<editor>._engine.<membre>` et les nœuds `%Nom` de la scène ;
4. comptage des **membres distincts**, du nombre d'accès et des `fichier:ligne` uniques (dédupliqués).

Les compteurs de la colonne « Audit §2 » proviennent de `docs/refactor/AUDIT_EDITEUR_CARTE.md` §2. L'écart éventuel vient de la méthode de comptage de l'audit (accès indirects/chaînes) : ce script mesure les accès directs ci-dessus, de façon stable et rejouable.

## 3. Synthèse

| Cible | Fichiers pilotés | Membres atteints | dont privés | Audit §2 | Écart |
|---|---:|---:|---:|---:|---:|
| Éditeur `map_complex_editor.gd` | 49 | 169 | 153 | 169 | +0 |
| Document `MapEditDocument` | 40 | 99 | 1 | 99 | +0 |
| Moteur `ComplexMapEngine3D` | 51 | 128 | 47 | 130 | -2 |

Fichiers qui chargent la scène map_editor.tscn : **50**. Nœuds %Nom distincts atteints : **2**.

Notes de lecture : les membres hérités de `Node`/`Control` (`size`, `queue_free`, `set_anchors_and_offsets_preset`…) apparaissent car les tests les appellent sur l'instance d'éditeur : ils ne sont pas des contrats propres à l'éditeur. Le nombre de « fichiers pilotés » du moteur est plus élevé que l'audit (§2 : 32) car des tests instancient le moteur seul, hors scène d'éditeur. L'écart de -2 membres sur le moteur vient de la méthode (seuls les accès directs sont comptés).

## 4. Top des membres les plus atteints

### 4.1 Éditeur

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| **doc** | 231 | 34 | game/scripts/tests/cite_demo_catalog_test.gd:126, game/scripts/tests/cite_demo_catalog_test.gd:129, game/scripts/tests/cite_demo_catalog_test.gd:131, game/scripts/tests/cite_demo_catalog_test.gd:136, game/scripts/tests/cite_demo_catalog_test.gd:139, game/scripts/tests/cite_showcase_shot_test.gd:54, … |
| `_engine` | 97 | 22 | game/scripts/tests/camera_navigation_test.gd:22, game/scripts/tests/cite_eau_shot_test.gd:108, game/scripts/tests/cite_eau_shot_test.gd:109, game/scripts/tests/cite_showcase_shot_test.gd:55, game/scripts/tests/cite_showcase_shot_test.gd:56, game/scripts/tests/cite_showcase_shot_test.gd:70, … |
| **load_map** | 49 | 48 | game/scripts/tests/camera_navigation_test.gd:19, game/scripts/tests/cite_demo_catalog_test.gd:124, game/scripts/tests/cite_eau_shot_test.gd:104, game/scripts/tests/cite_showcase_shot_test.gd:47, game/scripts/tests/cite_showcase_shot_test.gd:221, game/scripts/tests/city_scene_test.gd:47, … |
| **size** | 47 | 39 | game/scripts/tests/camera_navigation_test.gd:16, game/scripts/tests/cite_demo_catalog_test.gd:121, game/scripts/tests/cite_eau_shot_test.gd:103, game/scripts/tests/cite_showcase_shot_test.gd:46, game/scripts/tests/city_scene_test.gd:44, game/scripts/tests/demo_saules_shot_test.gd:49, … |
| `_set_tool` | 37 | 10 | game/scripts/tests/camera_navigation_test.gd:28, game/scripts/tests/camera_navigation_test.gd:87, game/scripts/tests/map_25d_editor_shot_test.gd:60, game/scripts/tests/map_25d_editor_shot_test.gd:94, game/scripts/tests/map_areas_test.gd:254, game/scripts/tests/map_editor_snap_test.gd:40, … |
| `_on_pointer_pressed` | 32 | 6 | game/scripts/tests/map_areas_test.gd:259, game/scripts/tests/map_editor_snap_test.gd:294, game/scripts/tests/map_editor_snap_test.gd:495, game/scripts/tests/map_editor_test.gd:534, game/scripts/tests/map_editor_test.gd:555, game/scripts/tests/map_editor_test.gd:563, … |
| **queue_free** | 30 | 26 | game/scripts/tests/cite_eau_shot_test.gd:115, game/scripts/tests/demo_saules_shot_test.gd:100, game/scripts/tests/editor_drag_perf_test.gd:136, game/scripts/tests/map_areas_test.gd:281, game/scripts/tests/map_editor_library_filter_test.gd:57, game/scripts/tests/map_editor_parametres_shot_test.gd:128, … |
| `_right_tabs` | 29 | 5 | game/scripts/tests/map_25d_editor_shot_test.gd:66, game/scripts/tests/map_25d_editor_shot_test.gd:67, game/scripts/tests/map_25d_editor_shot_test.gd:77, game/scripts/tests/map_25d_editor_shot_test.gd:104, game/scripts/tests/map_25d_editor_shot_test.gd:105, game/scripts/tests/map_25d_editor_shot_test.gd:107, … |
| `_world_panel` | 28 | 3 | game/scripts/tests/map_25d_editor_shot_test.gd:104, game/scripts/tests/map_25d_editor_shot_test.gd:105, game/scripts/tests/map_25d_editor_shot_test.gd:109, game/scripts/tests/map_25d_editor_shot_test.gd:110, game/scripts/tests/map_25d_editor_shot_test.gd:118, game/scripts/tests/map_25d_editor_shot_test.gd:121, … |
| `_on_pointer_released` | 16 | 5 | game/scripts/tests/map_areas_test.gd:261, game/scripts/tests/map_editor_snap_test.gd:296, game/scripts/tests/map_editor_snap_test.gd:502, game/scripts/tests/map_editor_test.gd:582, game/scripts/tests/map_editor_test.gd:590, game/scripts/tests/map_editor_test.gd:596, … |
| `_on_pointer_moved` | 15 | 6 | game/scripts/tests/map_areas_test.gd:260, game/scripts/tests/map_editor_snap_test.gd:295, game/scripts/tests/map_editor_snap_test.gd:496, game/scripts/tests/map_editor_test.gd:581, game/scripts/tests/map_editor_test.gd:589, game/scripts/tests/map_editor_test.gd:595, … |
| **set_editable** | 14 | 12 | game/scripts/tests/cite_eau_shot_test.gd:105, game/scripts/tests/cite_showcase_shot_test.gd:148, game/scripts/tests/cite_showcase_shot_test.gd:196, game/scripts/tests/demo_saules_shot_test.gd:51, game/scripts/tests/map_editor_test.gd:748, game/scripts/tests/map_editor_test.gd:751, … |
| `_overlay` | 13 | 4 | game/scripts/tests/map_editor_snap_test.gd:497, game/scripts/tests/map_editor_test.gd:545, game/scripts/tests/map_editor_test.gd:606, game/scripts/tests/map_editor_test.gd:624, game/scripts/tests/map_editor_test.gd:639, game/scripts/tests/map_editor_test.gd:648, … |
| **set_anchors_and_offsets_preset** | 13 | 13 | game/scripts/tests/cite_eau_shot_test.gd:100, game/scripts/tests/cite_showcase_shot_test.gd:43, game/scripts/tests/demo_saules_shot_test.gd:46, game/scripts/tests/map_25d_editor_shot_test.gd:44, game/scripts/tests/map_editor_library_filter_test.gd:18, game/scripts/tests/map_editor_parametres_shot_test.gd:37, … |
| `_apply_responsive_layout` | 12 | 5 | game/scripts/tests/map_25d_editor_shot_test.gd:51, game/scripts/tests/map_25d_editor_shot_test.gd:62, game/scripts/tests/map_editor_parametres_shot_test.gd:44, game/scripts/tests/map_editor_test.gd:429, game/scripts/tests/map_editor_test.gd:503, game/scripts/tests/map_editor_test.gd:513, … |
| `_create_mesh` | 12 | 4 | game/scripts/tests/map_25d_editor_shot_test.gd:64, game/scripts/tests/map_editor_snap_test.gd:45, game/scripts/tests/map_editor_snap_test.gd:56, game/scripts/tests/map_editor_snap_test.gd:95, game/scripts/tests/map_editor_snap_test.gd:113, game/scripts/tests/map_editor_snap_test.gd:124, … |
| `_dock_left_w` | 11 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:74, game/scripts/tests/map_editor_test.gd:430, game/scripts/tests/map_editor_test.gd:432, game/scripts/tests/map_editor_test.gd:504, game/scripts/tests/map_editor_test.gd:506, game/scripts/tests/map_editor_test.gd:514, … |
| `_dock_right_w` | 11 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:74, game/scripts/tests/map_editor_test.gd:431, game/scripts/tests/map_editor_test.gd:432, game/scripts/tests/map_editor_test.gd:505, game/scripts/tests/map_editor_test.gd:506, game/scripts/tests/map_editor_test.gd:514, … |
| `_construction` | 10 | 7 | game/scripts/tests/cite_demo_catalog_test.gd:137, game/scripts/tests/cite_showcase_shot_test.gd:52, game/scripts/tests/city_scene_test.gd:60, game/scripts/tests/map_context_decor_test.gd:32, game/scripts/tests/map_context_decor_test.gd:46, game/scripts/tests/map_context_decor_test.gd:60, … |
| `_create_mesh_wall_chain` | 10 | 1 | game/scripts/tests/map_editor_snap_test.gd:191, game/scripts/tests/map_editor_snap_test.gd:203, game/scripts/tests/map_editor_snap_test.gd:233, game/scripts/tests/map_editor_snap_test.gd:281, game/scripts/tests/map_editor_snap_test.gd:392, game/scripts/tests/map_editor_snap_test.gd:418, … |

### 4.2 Document (`MapEditDocument`)

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| **count_of_kind** | 61 | 7 | game/scripts/tests/demo_saules_shot_test.gd:61, game/scripts/tests/map_25d_editor_shot_test.gd:70, game/scripts/tests/map_areas_test.gd:49, game/scripts/tests/map_areas_test.gd:62, game/scripts/tests/map_areas_test.gd:262, game/scripts/tests/map_editor_test.gd:64, … |
| **map_data** | 60 | 18 | game/scripts/tests/cite_demo_catalog_test.gd:129, game/scripts/tests/cite_demo_catalog_test.gd:131, game/scripts/tests/city_scene_test.gd:228, game/scripts/tests/demo_saules_shot_test.gd:59, game/scripts/tests/map_context_decor_test.gd:56, game/scripts/tests/map_editor_snap_test.gd:276, … |
| **get_element** | 58 | 9 | game/scripts/tests/map_areas_test.gd:51, game/scripts/tests/map_areas_test.gd:72, game/scripts/tests/map_context_decor_test.gd:47, game/scripts/tests/map_editor_snap_test.gd:174, game/scripts/tests/map_editor_snap_test.gd:183, game/scripts/tests/map_editor_snap_test.gd:371, … |
| **undo** | 46 | 13 | game/scripts/tests/city_scene_test.gd:269, game/scripts/tests/map_editor_test.gd:107, game/scripts/tests/map_editor_test.gd:114, game/scripts/tests/map_editor_test.gd:130, game/scripts/tests/map_editor_test.gd:138, game/scripts/tests/map_editor_test.gd:147, … |
| **elements_of_kind** | 44 | 16 | game/scripts/tests/cite_demo_catalog_test.gd:126, game/scripts/tests/cite_demo_catalog_test.gd:136, game/scripts/tests/cite_demo_catalog_test.gd:139, game/scripts/tests/cite_showcase_shot_test.gd:60, game/scripts/tests/city_scene_test.gd:63, game/scripts/tests/city_scene_test.gd:271, … |
| **add_element** | 42 | 13 | game/scripts/tests/map_areas_test.gd:45, game/scripts/tests/map_areas_test.gd:71, game/scripts/tests/map_context_decor_test.gd:21, game/scripts/tests/map_editor_parametres_test.gd:213, game/scripts/tests/map_editor_snap_test.gd:103, game/scripts/tests/map_editor_snap_test.gd:134, … |
| **terrain_height** | 40 | 4 | game/scripts/tests/map_terrain_doc_test.gd:38, game/scripts/tests/map_terrain_doc_test.gd:42, game/scripts/tests/map_terrain_doc_test.gd:44, game/scripts/tests/map_terrain_doc_test.gd:48, game/scripts/tests/map_terrain_doc_test.gd:49, game/scripts/tests/map_terrain_doc_test.gd:52, … |
| **load_map** | 32 | 13 | game/scripts/tests/map_25d_mesh_demo_test.gd:37, game/scripts/tests/map_areas_test.gd:43, game/scripts/tests/map_areas_test.gd:61, game/scripts/tests/map_editor_test.gd:57, game/scripts/tests/map_editor_test.gd:93, game/scripts/tests/map_editor_test.gd:101, … |
| **terrain_material** | 28 | 2 | game/scripts/tests/map_terrain_doc_test.gd:62, game/scripts/tests/map_terrain_doc_test.gd:63, game/scripts/tests/map_terrain_doc_test.gd:90, game/scripts/tests/map_terrain_doc_test.gd:92, game/scripts/tests/map_terrain_doc_test.gd:94, game/scripts/tests/map_terrain_doc_test.gd:95, … |
| **elements_sorted** | 17 | 8 | game/scripts/tests/editor_drag_perf_test.gd:41, game/scripts/tests/map_context_decor_test.gd:34, game/scripts/tests/map_context_decor_test.gd:49, game/scripts/tests/map_context_decor_test.gd:62, game/scripts/tests/map_context_decor_test.gd:75, game/scripts/tests/map_editor_snap_test.gd:518, … |
| **redo** | 17 | 8 | game/scripts/tests/city_scene_test.gd:274, game/scripts/tests/map_editor_test.gd:109, game/scripts/tests/map_editor_test.gd:116, game/scripts/tests/map_editor_test.gd:132, game/scripts/tests/map_organic_creation_test.gd:231, game/scripts/tests/map_organic_creation_test.gd:323, … |
| **to_map_data** | 16 | 12 | game/scripts/tests/map_25d_mesh_demo_test.gd:42, game/scripts/tests/map_areas_test.gd:56, game/scripts/tests/map_editor_test.gd:79, game/scripts/tests/map_mesh_test.gd:88, game/scripts/tests/map_mesh_test.gd:145, game/scripts/tests/map_mesh_test.gd:181, … |
| **element_ids** | 15 | 1 | game/scripts/tests/map_editor_test.gd:61, game/scripts/tests/map_editor_test.gd:94, game/scripts/tests/map_editor_test.gd:200, game/scripts/tests/map_editor_test.gd:203, game/scripts/tests/map_editor_test.gd:207, game/scripts/tests/map_editor_test.gd:270, … |
| **history_labels** | 15 | 1 | game/scripts/tests/map_editor_test.gd:120, game/scripts/tests/map_editor_test.gd:122, game/scripts/tests/map_editor_test.gd:142, game/scripts/tests/map_editor_test.gd:144, game/scripts/tests/map_editor_test.gd:146, game/scripts/tests/map_editor_test.gd:653, … |
| **is_selected** | 14 | 3 | game/scripts/tests/map_areas_test.gd:269, game/scripts/tests/map_editor_test.gd:643, game/scripts/tests/map_editor_test.gd:677, game/scripts/tests/map_editor_test.gd:682, game/scripts/tests/map_editor_test.gd:692, game/scripts/tests/map_props_test.gd:316 |

### 4.3 Moteur (`ComplexMapEngine3D`)

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| `_camera` | 126 | 23 | game/scripts/tests/camera_navigation_test.gd:25, game/scripts/tests/camera_navigation_test.gd:30, game/scripts/tests/camera_navigation_test.gd:35, game/scripts/tests/camera_navigation_test.gd:55, game/scripts/tests/camera_navigation_test.gd:59, game/scripts/tests/camera_navigation_test.gd:62, … |
| `_ground` | 80 | 17 | game/scripts/tests/cite_eau_shot_test.gd:53, game/scripts/tests/map_25d_mesh_demo_test.gd:57, game/scripts/tests/map_backdrop_test.gd:243, game/scripts/tests/map_quality_cs2_test.gd:714, game/scripts/tests/map_terrain_materials_test.gd:546, game/scripts/tests/map_terrain_materials_test.gd:549, … |
| **configure** | 69 | 32 | game/scripts/tests/cite_eau_shot_test.gd:46, game/scripts/tests/cliff_shot_test.gd:26, game/scripts/tests/fog_quality_shot_test.gd:78, game/scripts/tests/fog_quality_shot_test.gd:184, game/scripts/tests/fog_quality_shot_test.gd:211, game/scripts/tests/map_25d_mesh_demo_test.gd:48, … |
| **size** | 57 | 29 | game/scripts/tests/cite_eau_shot_test.gd:44, game/scripts/tests/fog_quality_shot_test.gd:76, game/scripts/tests/map_25d_mesh_demo_test.gd:45, game/scripts/tests/map_25d_mesh_demo_test.gd:64, game/scripts/tests/map_ambient_fx_test.gd:394, game/scripts/tests/map_backdrop_test.gd:231, … |
| `_meshes_layer` | 37 | 8 | game/scripts/tests/cite_eau_shot_test.gd:61, game/scripts/tests/cite_eau_shot_test.gd:62, game/scripts/tests/cite_eau_shot_test.gd:63, game/scripts/tests/cite_eau_shot_test.gd:64, game/scripts/tests/editor_drag_perf_test.gd:142, game/scripts/tests/map_25d_mesh_demo_test.gd:55, … |
| `_sun` | 36 | 5 | game/scripts/tests/map_editor_parametres_test.gd:82, game/scripts/tests/map_editor_parametres_test.gd:92, game/scripts/tests/map_lighting_test.gd:47, game/scripts/tests/map_quality_cs2_test.gd:686, game/scripts/tests/map_quality_cs2_test.gd:687, game/scripts/tests/map_quality_cs2_test.gd:688, … |
| **terrain_height_at** | 25 | 6 | game/scripts/tests/map_25d_mesh_demo_test.gd:59, game/scripts/tests/map_render_quality_test.gd:102, game/scripts/tests/map_terrain_test.gd:161, game/scripts/tests/map_terrain_test.gd:162, game/scripts/tests/map_terrain_test.gd:163, game/scripts/tests/map_terrain_test.gd:164, … |
| `_editor_gui_input` | 23 | 3 | game/scripts/tests/camera_navigation_test.gd:40, game/scripts/tests/camera_navigation_test.gd:44, game/scripts/tests/camera_navigation_test.gd:48, game/scripts/tests/camera_navigation_test.gd:53, game/scripts/tests/pan_cursor_tracking_test.gd:56, game/scripts/tests/pan_cursor_tracking_test.gd:60, … |
| `_water_layer` | 23 | 9 | game/scripts/tests/cite_eau_shot_test.gd:52, game/scripts/tests/map_flora_water_integration_test.gd:36, game/scripts/tests/map_water_test.gd:322, game/scripts/tests/map_water_test.gd:326, game/scripts/tests/map_water_test.gd:327, game/scripts/tests/map_water_test.gd:328, … |
| `_world_env` | 23 | 4 | game/scripts/tests/fog_quality_shot_test.gd:83, game/scripts/tests/fog_quality_shot_test.gd:103, game/scripts/tests/fog_quality_shot_test.gd:104, game/scripts/tests/fog_quality_shot_test.gd:108, game/scripts/tests/fog_quality_shot_test.gd:115, game/scripts/tests/fog_quality_shot_test.gd:295, … |
| **grid_to_screen** | 23 | 6 | game/scripts/tests/map_editor_test.gd:634, game/scripts/tests/map_editor_test.gd:686, game/scripts/tests/map_editor_test.gd:687, game/scripts/tests/map_editor_test.gd:689, game/scripts/tests/map_editor_test.gd:724, game/scripts/tests/map_terrain_test.gd:235, … |
| **queue_free** | 19 | 14 | game/scripts/tests/cite_eau_shot_test.gd:95, game/scripts/tests/cliff_shot_test.gd:45, game/scripts/tests/map_camera_test.gd:91, game/scripts/tests/map_camera_test.gd:150, game/scripts/tests/map_camera_test.gd:176, game/scripts/tests/map_lighting_test.gd:48, … |
| **zoom** | 19 | 10 | game/scripts/tests/camera_navigation_test.gd:74, game/scripts/tests/cite_showcase_shot_test.gd:72, game/scripts/tests/cite_showcase_shot_test.gd:161, game/scripts/tests/fog_quality_shot_test.gd:136, game/scripts/tests/fog_quality_shot_test.gd:155, game/scripts/tests/fog_quality_shot_test.gd:247, … |
| `_cell_size` | 17 | 11 | game/scripts/tests/cite_showcase_shot_test.gd:174, game/scripts/tests/fog_quality_shot_test.gd:266, game/scripts/tests/fog_quality_shot_test.gd:267, game/scripts/tests/map_mesh_test.gd:158, game/scripts/tests/map_mesh_test.gd:193, game/scripts/tests/map_meshes_3d_test.gd:280, … |
| `_dice` | 17 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:136, game/scripts/tests/table_poc_screenshot_test.gd:140, game/scripts/tests/table_view_test.gd:78, game/scripts/tests/table_view_test.gd:90, game/scripts/tests/table_view_test.gd:91, game/scripts/tests/table_view_test.gd:95, … |

## 5. Tableau complet — éditeur (contrat de `map_complex_editor.gd`)

**169** membres distincts (dont **153** privés). **gras** = API publique, ` privé ` = membre interne.

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| **doc** | 231 | 34 | game/scripts/tests/cite_demo_catalog_test.gd:126, game/scripts/tests/cite_demo_catalog_test.gd:129, game/scripts/tests/cite_demo_catalog_test.gd:131, game/scripts/tests/cite_demo_catalog_test.gd:136, game/scripts/tests/cite_demo_catalog_test.gd:139, game/scripts/tests/cite_showcase_shot_test.gd:54, … |
| `_engine` | 97 | 22 | game/scripts/tests/camera_navigation_test.gd:22, game/scripts/tests/cite_eau_shot_test.gd:108, game/scripts/tests/cite_eau_shot_test.gd:109, game/scripts/tests/cite_showcase_shot_test.gd:55, game/scripts/tests/cite_showcase_shot_test.gd:56, game/scripts/tests/cite_showcase_shot_test.gd:70, … |
| **load_map** | 49 | 48 | game/scripts/tests/camera_navigation_test.gd:19, game/scripts/tests/cite_demo_catalog_test.gd:124, game/scripts/tests/cite_eau_shot_test.gd:104, game/scripts/tests/cite_showcase_shot_test.gd:47, game/scripts/tests/cite_showcase_shot_test.gd:221, game/scripts/tests/city_scene_test.gd:47, … |
| **size** | 47 | 39 | game/scripts/tests/camera_navigation_test.gd:16, game/scripts/tests/cite_demo_catalog_test.gd:121, game/scripts/tests/cite_eau_shot_test.gd:103, game/scripts/tests/cite_showcase_shot_test.gd:46, game/scripts/tests/city_scene_test.gd:44, game/scripts/tests/demo_saules_shot_test.gd:49, … |
| `_set_tool` | 37 | 10 | game/scripts/tests/camera_navigation_test.gd:28, game/scripts/tests/camera_navigation_test.gd:87, game/scripts/tests/map_25d_editor_shot_test.gd:60, game/scripts/tests/map_25d_editor_shot_test.gd:94, game/scripts/tests/map_areas_test.gd:254, game/scripts/tests/map_editor_snap_test.gd:40, … |
| `_on_pointer_pressed` | 32 | 6 | game/scripts/tests/map_areas_test.gd:259, game/scripts/tests/map_editor_snap_test.gd:294, game/scripts/tests/map_editor_snap_test.gd:495, game/scripts/tests/map_editor_test.gd:534, game/scripts/tests/map_editor_test.gd:555, game/scripts/tests/map_editor_test.gd:563, … |
| **queue_free** | 30 | 26 | game/scripts/tests/cite_eau_shot_test.gd:115, game/scripts/tests/demo_saules_shot_test.gd:100, game/scripts/tests/editor_drag_perf_test.gd:136, game/scripts/tests/map_areas_test.gd:281, game/scripts/tests/map_editor_library_filter_test.gd:57, game/scripts/tests/map_editor_parametres_shot_test.gd:128, … |
| `_right_tabs` | 29 | 5 | game/scripts/tests/map_25d_editor_shot_test.gd:66, game/scripts/tests/map_25d_editor_shot_test.gd:67, game/scripts/tests/map_25d_editor_shot_test.gd:77, game/scripts/tests/map_25d_editor_shot_test.gd:104, game/scripts/tests/map_25d_editor_shot_test.gd:105, game/scripts/tests/map_25d_editor_shot_test.gd:107, … |
| `_world_panel` | 28 | 3 | game/scripts/tests/map_25d_editor_shot_test.gd:104, game/scripts/tests/map_25d_editor_shot_test.gd:105, game/scripts/tests/map_25d_editor_shot_test.gd:109, game/scripts/tests/map_25d_editor_shot_test.gd:110, game/scripts/tests/map_25d_editor_shot_test.gd:118, game/scripts/tests/map_25d_editor_shot_test.gd:121, … |
| `_on_pointer_released` | 16 | 5 | game/scripts/tests/map_areas_test.gd:261, game/scripts/tests/map_editor_snap_test.gd:296, game/scripts/tests/map_editor_snap_test.gd:502, game/scripts/tests/map_editor_test.gd:582, game/scripts/tests/map_editor_test.gd:590, game/scripts/tests/map_editor_test.gd:596, … |
| `_on_pointer_moved` | 15 | 6 | game/scripts/tests/map_areas_test.gd:260, game/scripts/tests/map_editor_snap_test.gd:295, game/scripts/tests/map_editor_snap_test.gd:496, game/scripts/tests/map_editor_test.gd:581, game/scripts/tests/map_editor_test.gd:589, game/scripts/tests/map_editor_test.gd:595, … |
| **set_editable** | 14 | 12 | game/scripts/tests/cite_eau_shot_test.gd:105, game/scripts/tests/cite_showcase_shot_test.gd:148, game/scripts/tests/cite_showcase_shot_test.gd:196, game/scripts/tests/demo_saules_shot_test.gd:51, game/scripts/tests/map_editor_test.gd:748, game/scripts/tests/map_editor_test.gd:751, … |
| `_overlay` | 13 | 4 | game/scripts/tests/map_editor_snap_test.gd:497, game/scripts/tests/map_editor_test.gd:545, game/scripts/tests/map_editor_test.gd:606, game/scripts/tests/map_editor_test.gd:624, game/scripts/tests/map_editor_test.gd:639, game/scripts/tests/map_editor_test.gd:648, … |
| **set_anchors_and_offsets_preset** | 13 | 13 | game/scripts/tests/cite_eau_shot_test.gd:100, game/scripts/tests/cite_showcase_shot_test.gd:43, game/scripts/tests/demo_saules_shot_test.gd:46, game/scripts/tests/map_25d_editor_shot_test.gd:44, game/scripts/tests/map_editor_library_filter_test.gd:18, game/scripts/tests/map_editor_parametres_shot_test.gd:37, … |
| `_apply_responsive_layout` | 12 | 5 | game/scripts/tests/map_25d_editor_shot_test.gd:51, game/scripts/tests/map_25d_editor_shot_test.gd:62, game/scripts/tests/map_editor_parametres_shot_test.gd:44, game/scripts/tests/map_editor_test.gd:429, game/scripts/tests/map_editor_test.gd:503, game/scripts/tests/map_editor_test.gd:513, … |
| `_create_mesh` | 12 | 4 | game/scripts/tests/map_25d_editor_shot_test.gd:64, game/scripts/tests/map_editor_snap_test.gd:45, game/scripts/tests/map_editor_snap_test.gd:56, game/scripts/tests/map_editor_snap_test.gd:95, game/scripts/tests/map_editor_snap_test.gd:113, game/scripts/tests/map_editor_snap_test.gd:124, … |
| `_dock_left_w` | 11 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:74, game/scripts/tests/map_editor_test.gd:430, game/scripts/tests/map_editor_test.gd:432, game/scripts/tests/map_editor_test.gd:504, game/scripts/tests/map_editor_test.gd:506, game/scripts/tests/map_editor_test.gd:514, … |
| `_dock_right_w` | 11 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:74, game/scripts/tests/map_editor_test.gd:431, game/scripts/tests/map_editor_test.gd:432, game/scripts/tests/map_editor_test.gd:505, game/scripts/tests/map_editor_test.gd:506, game/scripts/tests/map_editor_test.gd:514, … |
| `_construction` | 10 | 7 | game/scripts/tests/cite_demo_catalog_test.gd:137, game/scripts/tests/cite_showcase_shot_test.gd:52, game/scripts/tests/city_scene_test.gd:60, game/scripts/tests/map_context_decor_test.gd:32, game/scripts/tests/map_context_decor_test.gd:46, game/scripts/tests/map_context_decor_test.gd:60, … |
| `_create_mesh_wall_chain` | 10 | 1 | game/scripts/tests/map_editor_snap_test.gd:191, game/scripts/tests/map_editor_snap_test.gd:203, game/scripts/tests/map_editor_snap_test.gd:233, game/scripts/tests/map_editor_snap_test.gd:281, game/scripts/tests/map_editor_snap_test.gd:392, game/scripts/tests/map_editor_snap_test.gd:418, … |
| `_mesh_asset` | 10 | 4 | game/scripts/tests/map_25d_editor_shot_test.gd:58, game/scripts/tests/map_editor_snap_test.gd:44, game/scripts/tests/map_editor_snap_test.gd:55, game/scripts/tests/map_editor_snap_test.gd:94, game/scripts/tests/map_editor_snap_test.gd:112, game/scripts/tests/map_editor_snap_test.gd:123, … |
| `_layout_force` | 9 | 4 | game/scripts/tests/map_25d_editor_shot_test.gd:50, game/scripts/tests/map_editor_parametres_shot_test.gd:43, game/scripts/tests/map_editor_test.gd:428, game/scripts/tests/map_editor_test.gd:502, game/scripts/tests/map_editor_test.gd:512, game/scripts/tests/map_editor_test.gd:520, … |
| `_water_mode` | 9 | 2 | game/scripts/tests/river_live_shot_test.gd:37, game/scripts/tests/water_tools_ui_test.gd:38, game/scripts/tests/water_tools_ui_test.gd:58, game/scripts/tests/water_tools_ui_test.gd:75, game/scripts/tests/water_tools_ui_test.gd:85 |
| `_wall_height` | 8 | 4 | game/scripts/tests/map_editor_snap_test.gd:202, game/scripts/tests/map_editor_snap_test.gd:230, game/scripts/tests/map_editor_snap_test.gd:383, game/scripts/tests/map_editor_snap_test.gd:455, game/scripts/tests/map_house_floors_test.gd:20, game/scripts/tests/map_house_windows_test.gd:20, … |
| **get_viewport_rect** | 8 | 7 | game/scripts/tests/cite_eau_shot_test.gd:103, game/scripts/tests/demo_saules_shot_test.gd:49, game/scripts/tests/map_25d_editor_shot_test.gd:47, game/scripts/tests/map_25d_editor_shot_test.gd:72, game/scripts/tests/map_editor_parametres_shot_test.gd:40, game/scripts/tests/riviere_s_shot_test.gd:36, … |
| `_handle_state` | 7 | 3 | game/scripts/tests/editor_drag_perf_test.gd:83, game/scripts/tests/editor_drag_perf_test.gd:109, game/scripts/tests/map_editor_snap_test.gd:177, game/scripts/tests/map_editor_snap_test.gd:186, game/scripts/tests/map_editor_snap_test.gd:467, game/scripts/tests/map_editor_snap_test.gd:490, … |
| `_scene_seed` | 7 | 7 | game/scripts/tests/cite_demo_catalog_test.gd:134, game/scripts/tests/cite_showcase_shot_test.gd:50, game/scripts/tests/city_scene_test.gd:58, game/scripts/tests/map_scene_apply_test.gd:26, game/scripts/tests/map_scene_zone_test.gd:20, game/scripts/tests/scene_rocks_shot_test.gd:30, … |
| `_scene_style` | 7 | 7 | game/scripts/tests/cite_demo_catalog_test.gd:133, game/scripts/tests/cite_showcase_shot_test.gd:49, game/scripts/tests/city_scene_test.gd:57, game/scripts/tests/map_scene_apply_test.gd:25, game/scripts/tests/map_scene_zone_test.gd:19, game/scripts/tests/scene_rocks_shot_test.gd:29, … |
| `_tool` | 7 | 4 | game/scripts/tests/map_editor_ui_v2_test.gd:45, game/scripts/tests/map_props_test.gd:305, game/scripts/tests/river_live_shot_test.gd:36, game/scripts/tests/water_tools_ui_test.gd:37, game/scripts/tests/water_tools_ui_test.gd:57 |
| **theme** | 7 | 3 | game/scripts/tests/map_editor_parametres_shot_test.gd:117, game/scripts/tests/map_editor_parametres_test.gd:262, game/scripts/tests/map_editor_parametres_test.gd:268, game/scripts/tests/map_editor_parametres_test.gd:275, game/scripts/tests/map_editor_ui_v2_test.gd:32, game/scripts/tests/map_editor_ui_v2_test.gd:34, … |
| `_do_undo` | 6 | 3 | game/scripts/tests/map_areas_test.gd:280, game/scripts/tests/map_editor_test.gd:660, game/scripts/tests/map_editor_test.gd:666, game/scripts/tests/map_editor_test.gd:728, game/scripts/tests/map_editor_test.gd:734, game/scripts/tests/map_props_test.gd:323 |
| `_immersive_dock` | 6 | 2 | game/scripts/tests/map_editor_test.gd:507, game/scripts/tests/map_editor_test.gd:750, game/scripts/tests/map_editor_test.gd:753, game/scripts/tests/map_editor_ui_v2_test.gd:46, game/scripts/tests/map_editor_ui_v2_test.gd:51, game/scripts/tests/map_editor_ui_v2_test.gd:53 |
| `_refresh_asset_library` | 6 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:61, game/scripts/tests/map_editor_library_filter_test.gd:25, game/scripts/tests/map_editor_library_filter_test.gd:35, game/scripts/tests/map_editor_library_filter_test.gd:41, game/scripts/tests/map_editor_library_filter_test.gd:48, game/scripts/tests/map_editor_library_filter_test.gd:54 |
| `_scene_density` | 6 | 6 | game/scripts/tests/cite_demo_catalog_test.gd:135, game/scripts/tests/cite_showcase_shot_test.gd:51, game/scripts/tests/city_scene_test.gd:59, game/scripts/tests/map_scene_apply_test.gd:27, game/scripts/tests/scene_rocks_shot_test.gd:31, game/scripts/tests/scene_rocks_test.gd:29 |
| `_status_lbl` | 6 | 2 | game/scripts/tests/map_editor_snap_test.gd:499, game/scripts/tests/map_organic_creation_test.gd:246, game/scripts/tests/map_organic_creation_test.gd:315 |
| `_sync_engine` | 6 | 5 | game/scripts/tests/camera_navigation_test.gd:60, game/scripts/tests/camera_navigation_test.gd:80, game/scripts/tests/editor_drag_perf_test.gd:36, game/scripts/tests/map_editor_parametres_test.gd:86, game/scripts/tests/rock_formation_shot_test.gd:58, game/scripts/tests/terrain_palette_shot_test.gd:49 |
| `_fps_lbl` | 5 | 2 | game/scripts/tests/map_editor_parametres_test.gd:171, game/scripts/tests/map_editor_parametres_test.gd:175, game/scripts/tests/map_editor_parametres_test.gd:270, game/scripts/tests/map_editor_parametres_test.gd:277, game/scripts/tests/map_editor_ui_v2_test.gd:38 |
| `_mesh_snap_modules` | 5 | 2 | game/scripts/tests/map_editor_snap_test.gd:41, game/scripts/tests/map_editor_snap_test.gd:93, game/scripts/tests/map_editor_snap_test.gd:111, game/scripts/tests/map_editor_snap_test.gd:143, game/scripts/tests/map_stacking_test.gd:22 |
| `_object3d_filter` | 5 | 1 | game/scripts/tests/map_editor_library_filter_test.gd:23, game/scripts/tests/map_editor_library_filter_test.gd:34, game/scripts/tests/map_editor_library_filter_test.gd:40, game/scripts/tests/map_editor_library_filter_test.gd:46, game/scripts/tests/map_editor_library_filter_test.gd:53 |
| `_wall_endpoints` | 5 | 1 | game/scripts/tests/map_editor_snap_test.gd:401, game/scripts/tests/map_editor_snap_test.gd:402, game/scripts/tests/map_editor_snap_test.gd:408, game/scripts/tests/map_editor_snap_test.gd:409, game/scripts/tests/map_editor_snap_test.gd:442 |
| **get** | 5 | 2 | game/scripts/tests/cite_showcase_shot_test.gd:149, game/scripts/tests/cite_showcase_shot_test.gd:197, game/scripts/tests/cite_showcase_shot_test.gd:200, game/scripts/tests/cite_showcase_shot_test.gd:231, game/scripts/tests/rock_formation_shot_test.gd:140 |
| `_active_water_tool_id` | 4 | 1 | game/scripts/tests/water_tools_ui_test.gd:39, game/scripts/tests/water_tools_ui_test.gd:59, game/scripts/tests/water_tools_ui_test.gd:77, game/scripts/tests/water_tools_ui_test.gd:86 |
| `_fps_overlay` | 4 | 1 | game/scripts/tests/map_editor_parametres_test.gd:167, game/scripts/tests/map_editor_parametres_test.gd:168, game/scripts/tests/map_editor_parametres_test.gd:171, game/scripts/tests/map_editor_parametres_test.gd:175 |
| `_gen_panel` | 4 | 2 | game/scripts/tests/map_quick_start_test.gd:22, game/scripts/tests/map_scene_zone_test.gd:24 |
| `_open_parametres` | 4 | 2 | game/scripts/tests/map_editor_parametres_shot_test.gd:52, game/scripts/tests/map_editor_parametres_test.gd:132, game/scripts/tests/map_editor_parametres_test.gd:188, game/scripts/tests/map_editor_parametres_test.gd:230 |
| `_options_bar` | 4 | 1 | game/scripts/tests/map_editor_ui_v2_test.gd:41, game/scripts/tests/map_editor_ui_v2_test.gd:45, game/scripts/tests/map_editor_ui_v2_test.gd:46, game/scripts/tests/map_editor_ui_v2_test.gd:49 |
| `_press_mode` | 4 | 2 | game/scripts/tests/editor_drag_perf_test.gd:59, game/scripts/tests/editor_drag_perf_test.gd:81, game/scripts/tests/editor_drag_perf_test.gd:107, game/scripts/tests/river_live_shot_test.gd:68 |
| `_relief_mode` | 4 | 2 | game/scripts/tests/map_terrain_doc_test.gd:182, game/scripts/tests/terrain_sculpt_live_test.gd:31, game/scripts/tests/terrain_sculpt_live_test.gd:59, game/scripts/tests/terrain_sculpt_live_test.gd:74 |
| `_scatter_seed` | 4 | 1 | game/scripts/tests/map_organic_creation_test.gd:284, game/scripts/tests/map_organic_creation_test.gd:339, game/scripts/tests/map_organic_creation_test.gd:353, game/scripts/tests/map_organic_creation_test.gd:361 |
| `_scatter_stroke_points` | 4 | 1 | game/scripts/tests/map_organic_creation_test.gd:287, game/scripts/tests/map_organic_creation_test.gd:328, game/scripts/tests/map_organic_creation_test.gd:340, game/scripts/tests/map_organic_creation_test.gd:354 |
| `_tool_options` | 4 | 3 | game/scripts/tests/map_editor_ui_v2_test.gd:26, game/scripts/tests/map_terrain_materials_test.gd:506, game/scripts/tests/water_tools_ui_test.gd:44, game/scripts/tests/water_tools_ui_test.gd:64 |
| `_context_decor_seed` | 3 | 1 | game/scripts/tests/map_context_decor_test.gd:31, game/scripts/tests/map_context_decor_test.gd:59, game/scripts/tests/map_context_decor_test.gd:72 |
| `_create_mesh_house` | 3 | 3 | game/scripts/tests/map_editor_snap_test.gd:352, game/scripts/tests/map_house_floors_test.gd:25, game/scripts/tests/map_house_windows_test.gd:24 |
| `_delete_confirm_dialog` | 3 | 1 | game/scripts/tests/map_editor_parametres_test.gd:220, game/scripts/tests/map_editor_parametres_test.gd:221, game/scripts/tests/map_editor_parametres_test.gd:223 |
| `_help_dialog` | 3 | 1 | game/scripts/tests/map_editor_test.gd:488, game/scripts/tests/map_editor_test.gd:489 |
| `_insert_window` | 3 | 2 | game/scripts/tests/map_editor_snap_test.gd:218, game/scripts/tests/map_editor_snap_test.gd:248, game/scripts/tests/procedural_wall_window_test.gd:29 |
| `_left_scroll` | 3 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:78, game/scripts/tests/map_editor_test.gd:750, game/scripts/tests/map_editor_test.gd:753 |
| `_library_dock` | 3 | 1 | game/scripts/tests/map_editor_ui_v2_test.gd:48, game/scripts/tests/map_editor_ui_v2_test.gd:51, game/scripts/tests/map_editor_ui_v2_test.gd:53 |
| `_live_incremental` | 3 | 1 | game/scripts/tests/editor_drag_perf_test.gd:60, game/scripts/tests/editor_drag_perf_test.gd:82, game/scripts/tests/editor_drag_perf_test.gd:108 |
| `_mesh_actual_dimensions` | 3 | 1 | game/scripts/tests/map_editor_snap_test.gd:175, game/scripts/tests/map_editor_snap_test.gd:183, game/scripts/tests/map_editor_snap_test.gd:372 |
| `_mesh_scale` | 3 | 3 | game/scripts/tests/map_25d_editor_shot_test.gd:59, game/scripts/tests/map_mesh_test.gd:213, game/scripts/tests/map_stacking_test.gd:23 |
| `_object3d_search` | 3 | 1 | game/scripts/tests/map_editor_library_filter_test.gd:24, game/scripts/tests/map_editor_library_filter_test.gd:47, game/scripts/tests/map_editor_library_filter_test.gd:52 |
| `_organic_asset` | 3 | 1 | game/scripts/tests/map_organic_creation_test.gd:191, game/scripts/tests/map_organic_creation_test.gd:252, game/scripts/tests/map_organic_creation_test.gd:264 |
| `_prop_category` | 3 | 3 | game/scripts/tests/map_25d_editor_shot_test.gd:57, game/scripts/tests/map_editor_library_filter_test.gd:22, game/scripts/tests/map_editor_ui_v2_test.gd:48 |
| `_scatter_zone_mode` | 3 | 1 | game/scripts/tests/map_organic_creation_test.gd:285, game/scripts/tests/map_organic_creation_test.gd:352, game/scripts/tests/map_organic_creation_test.gd:356 |
| `_toggle_palette` | 3 | 2 | game/scripts/tests/map_editor_test.gd:440, game/scripts/tests/map_editor_test.gd:482, game/scripts/tests/ui_palette_shot_test.gd:40 |
| `_token_dialogue` | 3 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:93, game/scripts/tests/map_editor_test.gd:760, game/scripts/tests/map_editor_test.gd:785 |
| `_token_kind` | 3 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:91, game/scripts/tests/map_editor_test.gd:758, game/scripts/tests/map_editor_test.gd:783 |
| `_token_label` | 3 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:92, game/scripts/tests/map_editor_test.gd:759, game/scripts/tests/map_editor_test.gd:784 |
| `_validate_dialog` | 3 | 1 | game/scripts/tests/map_editor_test.gd:495, game/scripts/tests/map_editor_test.gd:497 |
| `_water_river_bed` | 3 | 3 | game/scripts/tests/river_live_shot_test.gd:39, game/scripts/tests/river_user_trace_shot_test.gd:47, game/scripts/tests/river_user_trace_test.gd:42 |
| `_water_river_depth` | 3 | 3 | game/scripts/tests/river_live_shot_test.gd:40, game/scripts/tests/river_user_trace_shot_test.gd:48, game/scripts/tests/river_user_trace_test.gd:43 |
| `_water_river_width` | 3 | 3 | game/scripts/tests/river_live_shot_test.gd:38, game/scripts/tests/river_user_trace_shot_test.gd:49, game/scripts/tests/river_user_trace_test.gd:44 |
| **get_children** | 3 | 2 | game/scripts/tests/cite_showcase_shot_test.gd:152, game/scripts/tests/cite_showcase_shot_test.gd:201, game/scripts/tests/rock_formation_shot_test.gd:143 |
| **save_now** | 3 | 2 | game/scripts/tests/demo_saules_shot_test.gd:65, game/scripts/tests/map_editor_test.gd:740, game/scripts/tests/map_editor_test.gd:770 |
| `_apply_handle_resize` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:182, game/scripts/tests/map_editor_snap_test.gd:473 |
| `_asset_grid` | 2 | 2 | game/scripts/tests/map_25d_editor_shot_test.gd:69, game/scripts/tests/map_editor_library_filter_test.gd:70 |
| `_auto_stack` | 2 | 1 | game/scripts/tests/map_stacking_test.gd:21, game/scripts/tests/map_stacking_test.gd:38 |
| `_build_organic_chain` | 2 | 1 | game/scripts/tests/map_organic_creation_test.gd:195, game/scripts/tests/map_organic_creation_test.gd:254 |
| `_carve_river_bed` | 2 | 2 | game/scripts/tests/river_user_trace_shot_test.gd:50, game/scripts/tests/river_user_trace_test.gd:46 |
| `_create_floor` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:322, game/scripts/tests/map_editor_snap_test.gd:334 |
| `_create_mesh_roof` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:313, game/scripts/tests/map_editor_snap_test.gd:344 |
| `_delete_selection` | 2 | 1 | game/scripts/tests/map_editor_parametres_test.gd:218, game/scripts/tests/map_editor_parametres_test.gd:225 |
| `_do_redo` | 2 | 1 | game/scripts/tests/map_editor_test.gd:662, game/scripts/tests/map_editor_test.gd:736 |
| `_edit_ops` | 2 | 2 | game/scripts/tests/editor_drag_perf_test.gd:31, game/scripts/tests/procedural_bridge_mesh_test.gd:92 |
| `_esc_menu` | 2 | 1 | game/scripts/tests/map_editor_parametres_test.gd:157 |
| `_floor_material` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:333, game/scripts/tests/map_editor_snap_test.gd:338 |
| `_house_auto_interior` | 2 | 2 | game/scripts/tests/map_house_floors_test.gd:24, game/scripts/tests/map_house_windows_test.gd:23 |
| `_house_auto_windows` | 2 | 2 | game/scripts/tests/map_house_floors_test.gd:23, game/scripts/tests/map_house_windows_test.gd:22 |
| `_immersive_buttons` | 2 | 1 | game/scripts/tests/map_editor_ui_v2_test.gd:42, game/scripts/tests/map_editor_ui_v2_test.gd:47 |
| `_insert_door` | 2 | 2 | game/scripts/tests/map_editor_snap_test.gd:239, game/scripts/tests/procedural_wall_door_test.gd:29 |
| `_inspector` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:368, game/scripts/tests/map_editor_snap_test.gd:370 |
| `_parametres` | 2 | 2 | game/scripts/tests/map_editor_parametres_shot_test.gd:47, game/scripts/tests/map_editor_parametres_test.gd:129 |
| `_press_start_grid` | 2 | 2 | game/scripts/tests/editor_drag_perf_test.gd:64, game/scripts/tests/map_editor_snap_test.gd:466 |
| `_roof_asset` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:342, game/scripts/tests/map_editor_snap_test.gd:346 |
| `_roof_height` | 2 | 2 | game/scripts/tests/map_house_floors_test.gd:21, game/scripts/tests/map_house_windows_test.gd:21 |
| `_sym_x` | 2 | 1 | game/scripts/tests/terrain_sculpt_live_test.gd:75, game/scripts/tests/terrain_sculpt_live_test.gd:96 |
| `_toggle_ui` | 2 | 1 | game/scripts/tests/map_editor_ui_v2_test.gd:50, game/scripts/tests/map_editor_ui_v2_test.gd:52 |
| `_validate_text` | 2 | 1 | game/scripts/tests/map_editor_test.gd:496 |
| `_viewport_frame` | 2 | 2 | game/scripts/tests/map_editor_test.gd:438, game/scripts/tests/map_editor_ui_v2_test.gd:40 |
| `_wall_chain_plan` | 2 | 1 | game/scripts/tests/map_editor_snap_test.gd:384, game/scripts/tests/map_editor_snap_test.gd:432 |
| **get_node** | 2 | 1 | game/scripts/tests/map_editor_parametres_test.gd:180, game/scripts/tests/map_editor_parametres_test.gd:183 |
| **open_map_requested** | 2 | 2 | game/scripts/tests/map_editor_snap_test.gd:36, game/scripts/tests/world_editor_test.gd:143 |
| `_area_category` | 1 | 1 | game/scripts/tests/map_areas_test.gd:253 |
| `_area_label` | 1 | 1 | game/scripts/tests/map_areas_test.gd:252 |
| `_asset_filter_row` | 1 | 1 | game/scripts/tests/map_editor_library_filter_test.gd:28 |
| `_asset_search` | 1 | 1 | game/scripts/tests/map_editor_library_filter_test.gd:29 |
| `_carve_offset` | 1 | 1 | game/scripts/tests/terrain_sculpt_live_test.gd:33 |
| `_carve_radius` | 1 | 1 | game/scripts/tests/terrain_sculpt_live_test.gd:32 |
| `_collect_map_issues` | 1 | 1 | game/scripts/tests/map_editor_test.gd:491 |
| `_context_decor_density` | 1 | 1 | game/scripts/tests/map_context_decor_test.gd:30 |
| `_context_decor_radius` | 1 | 1 | game/scripts/tests/map_context_decor_test.gd:29 |
| `_create_bridge` | 1 | 1 | game/scripts/tests/procedural_bridge_mesh_test.gd:72 |
| `_create_interior_at` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:69 |
| `_create_mesh_fence` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:264 |
| `_create_mesh_room` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:303 |
| `_create_path` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:275 |
| `_create_token` | 1 | 1 | game/scripts/tests/map_editor_test.gd:761 |
| `_cycle_world_map` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:37 |
| `_drag_ids` | 1 | 1 | game/scripts/tests/editor_drag_perf_test.gd:61 |
| `_drag_origins` | 1 | 1 | game/scripts/tests/editor_drag_perf_test.gd:62 |
| `_export_map_image` | 1 | 1 | game/scripts/tests/map_25d_editor_shot_test.gd:176 |
| `_finish_water_lake` | 1 | 1 | game/scripts/tests/water_bodies_test.gd:180 |
| `_furnish_preset` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:254 |
| `_generate_scene_area_live` | 1 | 1 | game/scripts/tests/map_scene_zone_test.gd:21 |
| `_house_floors` | 1 | 1 | game/scripts/tests/map_house_floors_test.gd:22 |
| `_insert_furniture` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:255 |
| `_insert_stairs` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:227 |
| `_left_panel` | 1 | 1 | game/scripts/tests/map_editor_ui_v2_test.gd:29 |
| `_library_panel` | 1 | 1 | game/scripts/tests/map_editor_ui_v2_test.gd:20 |
| `_mesh_rotation` | 1 | 1 | game/scripts/tests/map_mesh_test.gd:214 |
| `_minimap` | 1 | 1 | game/scripts/tests/map_editor_test.gd:546 |
| `_on_child_map_requested` | 1 | 1 | game/scripts/tests/map_areas_test.gd:272 |
| `_on_dock_tool_pressed` | 1 | 1 | game/scripts/tests/demo_saules_shot_test.gd:75 |
| `_on_import_selected` | 1 | 1 | game/scripts/tests/demo_saules_shot_test.gd:56 |
| `_on_quick_lighting` | 1 | 1 | game/scripts/tests/map_quick_start_test.gd:32 |
| `_on_quick_start` | 1 | 1 | game/scripts/tests/map_quick_start_test.gd:19 |
| `_open_help` | 1 | 1 | game/scripts/tests/map_editor_test.gd:486 |
| `_organic_smoothing` | 1 | 1 | game/scripts/tests/map_organic_creation_test.gd:193 |
| `_paint_ground_material` | 1 | 1 | game/scripts/tests/camera_navigation_test.gd:90 |
| `_paint_relief` | 1 | 1 | game/scripts/tests/map_terrain_doc_test.gd:183 |
| `_paint_tile` | 1 | 1 | game/scripts/tests/map_editor_test.gd:609 |
| `_palette_v2` | 1 | 1 | game/scripts/tests/water_tools_ui_test.gd:27 |
| `_palette_wrappers` | 1 | 1 | game/scripts/tests/map_editor_test.gd:445 |
| `_path_material` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:274 |
| `_path_width` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:273 |
| `_prop_asset` | 1 | 1 | game/scripts/tests/map_props_test.gd:304 |
| `_prop_size` | 1 | 1 | game/scripts/tests/map_props_test.gd:307 |
| `_rebuild_tool_options` | 1 | 1 | game/scripts/tests/map_terrain_materials_test.gd:501 |
| `_relief_radius` | 1 | 1 | game/scripts/tests/map_terrain_doc_test.gd:180 |
| `_relief_strength` | 1 | 1 | game/scripts/tests/map_terrain_doc_test.gd:181 |
| `_scatter_active` | 1 | 1 | game/scripts/tests/map_organic_creation_test.gd:369 |
| `_scatter_density` | 1 | 1 | game/scripts/tests/map_organic_creation_test.gd:281 |
| `_scatter_mode` | 1 | 1 | game/scripts/tests/map_organic_creation_test.gd:280 |
| `_scatter_radius` | 1 | 1 | game/scripts/tests/map_organic_creation_test.gd:283 |
| `_scatter_size` | 1 | 1 | game/scripts/tests/map_organic_creation_test.gd:282 |
| `_sculpt_probe` | 1 | 1 | game/scripts/tests/terrain_sculpt_live_test.gd:76 |
| `_select_prop_asset` | 1 | 1 | game/scripts/tests/map_props_test.gd:303 |
| `_settings_panel` | 1 | 1 | game/scripts/tests/map_quality_cs2_test.gd:870 |
| `_snap_wall_endpoint` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:213 |
| `_split_inner` | 1 | 1 | game/scripts/tests/map_25d_editor_shot_test.gd:76 |
| `_split_outer` | 1 | 1 | game/scripts/tests/map_25d_editor_shot_test.gd:75 |
| `_unhandled_key_input` | 1 | 1 | game/scripts/tests/map_editor_parametres_test.gd:150 |
| `_validate_map` | 1 | 1 | game/scripts/tests/map_editor_test.gd:493 |
| `_wall_chain_corner_specs` | 1 | 1 | game/scripts/tests/map_editor_snap_test.gd:435 |
| `_water_lake_level` | 1 | 1 | game/scripts/tests/water_bodies_test.gd:187 |
| **find_child** | 1 | 1 | game/scripts/tests/camera_navigation_test.gd:66 |
| **find_children** | 1 | 1 | game/scripts/tests/map_editor_parametres_test.gd:159 |
| **get_viewport** | 1 | 1 | game/scripts/tests/ui_palette_shot_test.gd:54 |

## 6. Tableau complet — document (`MapEditDocument`)

**99** membres distincts (dont **1** privé(s)).

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| **count_of_kind** | 61 | 7 | game/scripts/tests/demo_saules_shot_test.gd:61, game/scripts/tests/map_25d_editor_shot_test.gd:70, game/scripts/tests/map_areas_test.gd:49, game/scripts/tests/map_areas_test.gd:62, game/scripts/tests/map_areas_test.gd:262, game/scripts/tests/map_editor_test.gd:64, … |
| **map_data** | 60 | 18 | game/scripts/tests/cite_demo_catalog_test.gd:129, game/scripts/tests/cite_demo_catalog_test.gd:131, game/scripts/tests/city_scene_test.gd:228, game/scripts/tests/demo_saules_shot_test.gd:59, game/scripts/tests/map_context_decor_test.gd:56, game/scripts/tests/map_editor_snap_test.gd:276, … |
| **get_element** | 58 | 9 | game/scripts/tests/map_areas_test.gd:51, game/scripts/tests/map_areas_test.gd:72, game/scripts/tests/map_context_decor_test.gd:47, game/scripts/tests/map_editor_snap_test.gd:174, game/scripts/tests/map_editor_snap_test.gd:183, game/scripts/tests/map_editor_snap_test.gd:371, … |
| **undo** | 46 | 13 | game/scripts/tests/city_scene_test.gd:269, game/scripts/tests/map_editor_test.gd:107, game/scripts/tests/map_editor_test.gd:114, game/scripts/tests/map_editor_test.gd:130, game/scripts/tests/map_editor_test.gd:138, game/scripts/tests/map_editor_test.gd:147, … |
| **elements_of_kind** | 44 | 16 | game/scripts/tests/cite_demo_catalog_test.gd:126, game/scripts/tests/cite_demo_catalog_test.gd:136, game/scripts/tests/cite_demo_catalog_test.gd:139, game/scripts/tests/cite_showcase_shot_test.gd:60, game/scripts/tests/city_scene_test.gd:63, game/scripts/tests/city_scene_test.gd:271, … |
| **add_element** | 42 | 13 | game/scripts/tests/map_areas_test.gd:45, game/scripts/tests/map_areas_test.gd:71, game/scripts/tests/map_context_decor_test.gd:21, game/scripts/tests/map_editor_parametres_test.gd:213, game/scripts/tests/map_editor_snap_test.gd:103, game/scripts/tests/map_editor_snap_test.gd:134, … |
| **terrain_height** | 40 | 4 | game/scripts/tests/map_terrain_doc_test.gd:38, game/scripts/tests/map_terrain_doc_test.gd:42, game/scripts/tests/map_terrain_doc_test.gd:44, game/scripts/tests/map_terrain_doc_test.gd:48, game/scripts/tests/map_terrain_doc_test.gd:49, game/scripts/tests/map_terrain_doc_test.gd:52, … |
| **load_map** | 32 | 13 | game/scripts/tests/map_25d_mesh_demo_test.gd:37, game/scripts/tests/map_areas_test.gd:43, game/scripts/tests/map_areas_test.gd:61, game/scripts/tests/map_editor_test.gd:57, game/scripts/tests/map_editor_test.gd:93, game/scripts/tests/map_editor_test.gd:101, … |
| **terrain_material** | 28 | 2 | game/scripts/tests/map_terrain_doc_test.gd:62, game/scripts/tests/map_terrain_doc_test.gd:63, game/scripts/tests/map_terrain_doc_test.gd:90, game/scripts/tests/map_terrain_doc_test.gd:92, game/scripts/tests/map_terrain_doc_test.gd:94, game/scripts/tests/map_terrain_doc_test.gd:95, … |
| **elements_sorted** | 17 | 8 | game/scripts/tests/editor_drag_perf_test.gd:41, game/scripts/tests/map_context_decor_test.gd:34, game/scripts/tests/map_context_decor_test.gd:49, game/scripts/tests/map_context_decor_test.gd:62, game/scripts/tests/map_context_decor_test.gd:75, game/scripts/tests/map_editor_snap_test.gd:518, … |
| **redo** | 17 | 8 | game/scripts/tests/city_scene_test.gd:274, game/scripts/tests/map_editor_test.gd:109, game/scripts/tests/map_editor_test.gd:116, game/scripts/tests/map_editor_test.gd:132, game/scripts/tests/map_organic_creation_test.gd:231, game/scripts/tests/map_organic_creation_test.gd:323, … |
| **to_map_data** | 16 | 12 | game/scripts/tests/map_25d_mesh_demo_test.gd:42, game/scripts/tests/map_areas_test.gd:56, game/scripts/tests/map_editor_test.gd:79, game/scripts/tests/map_mesh_test.gd:88, game/scripts/tests/map_mesh_test.gd:145, game/scripts/tests/map_mesh_test.gd:181, … |
| **element_ids** | 15 | 1 | game/scripts/tests/map_editor_test.gd:61, game/scripts/tests/map_editor_test.gd:94, game/scripts/tests/map_editor_test.gd:200, game/scripts/tests/map_editor_test.gd:203, game/scripts/tests/map_editor_test.gd:207, game/scripts/tests/map_editor_test.gd:270, … |
| **history_labels** | 15 | 1 | game/scripts/tests/map_editor_test.gd:120, game/scripts/tests/map_editor_test.gd:122, game/scripts/tests/map_editor_test.gd:142, game/scripts/tests/map_editor_test.gd:144, game/scripts/tests/map_editor_test.gd:146, game/scripts/tests/map_editor_test.gd:653, … |
| **is_selected** | 14 | 3 | game/scripts/tests/map_areas_test.gd:269, game/scripts/tests/map_editor_test.gd:643, game/scripts/tests/map_editor_test.gd:677, game/scripts/tests/map_editor_test.gd:682, game/scripts/tests/map_editor_test.gd:692, game/scripts/tests/map_props_test.gd:316 |
| **get_tile_at** | 13 | 2 | game/scripts/tests/map_editor_test.gd:297, game/scripts/tests/map_editor_test.gd:299, game/scripts/tests/map_editor_test.gd:303, game/scripts/tests/map_editor_test.gd:304, game/scripts/tests/map_editor_test.gd:306, game/scripts/tests/map_editor_test.gd:309, … |
| **terrain_carves** | 13 | 1 | game/scripts/tests/terrain_carve_test.gd:233, game/scripts/tests/terrain_carve_test.gd:236, game/scripts/tests/terrain_carve_test.gd:237, game/scripts/tests/terrain_carve_test.gd:238, game/scripts/tests/terrain_carve_test.gd:241, game/scripts/tests/terrain_carve_test.gd:242, … |
| **selection_size** | 12 | 3 | game/scripts/tests/map_editor_snap_test.gd:259, game/scripts/tests/map_editor_snap_test.gd:308, game/scripts/tests/map_editor_test.gd:169, game/scripts/tests/map_editor_test.gd:171, game/scripts/tests/map_editor_test.gd:173, game/scripts/tests/map_editor_test.gd:175, … |
| **has_element** | 11 | 1 | game/scripts/tests/map_editor_test.gd:108, game/scripts/tests/map_editor_test.gd:110, game/scripts/tests/map_editor_test.gd:129, game/scripts/tests/map_editor_test.gd:131, game/scripts/tests/map_editor_test.gd:133, game/scripts/tests/map_editor_test.gd:137, … |
| **modify_element** | 11 | 1 | game/scripts/tests/map_editor_test.gd:112, game/scripts/tests/map_editor_test.gd:121, game/scripts/tests/map_editor_test.gd:260, game/scripts/tests/map_editor_test.gd:262, game/scripts/tests/map_editor_test.gd:266, game/scripts/tests/map_editor_test.gd:706, … |
| **select_only** | 11 | 4 | game/scripts/tests/map_editor_snap_test.gd:369, game/scripts/tests/map_editor_snap_test.gd:465, game/scripts/tests/map_editor_test.gd:168, game/scripts/tests/map_editor_test.gd:176, game/scripts/tests/map_editor_test.gd:188, game/scripts/tests/map_editor_test.gd:652, … |
| **clear_selection** | 10 | 3 | game/scripts/tests/cite_showcase_shot_test.gd:54, game/scripts/tests/map_editor_test.gd:630, game/scripts/tests/map_editor_test.gd:646, game/scripts/tests/map_editor_test.gd:685, game/scripts/tests/map_editor_test.gd:696, game/scripts/tests/rock_formation_shot_test.gd:57 |
| **terrain_heights** | 10 | 3 | game/scripts/tests/demo_saules_shot_test.gd:62, game/scripts/tests/map_terrain_doc_test.gd:37, game/scripts/tests/map_terrain_doc_test.gd:129, game/scripts/tests/map_terrain_doc_test.gd:134, game/scripts/tests/map_terrain_doc_test.gd:136, game/scripts/tests/map_terrain_doc_test.gd:137, … |
| **water_bodies** | 10 | 2 | game/scripts/tests/demo_saules_shot_test.gd:60, game/scripts/tests/water_bodies_test.gd:186, game/scripts/tests/water_bodies_test.gd:192, game/scripts/tests/water_bodies_test.gd:207, game/scripts/tests/water_bodies_test.gd:210, game/scripts/tests/water_bodies_test.gd:211, … |
| **selection** | 9 | 5 | game/scripts/tests/map_editor_parametres_test.gd:222, game/scripts/tests/map_editor_parametres_test.gd:227, game/scripts/tests/map_editor_snap_test.gd:394, game/scripts/tests/map_editor_snap_test.gd:438, game/scripts/tests/map_editor_test.gd:763, game/scripts/tests/map_mesh_test.gd:224, … |
| **set_terrain_height** | 9 | 3 | game/scripts/tests/map_context_decor_test.gd:57, game/scripts/tests/map_context_decor_test.gd:58, game/scripts/tests/map_terrain_doc_test.gd:41, game/scripts/tests/map_terrain_doc_test.gd:81, game/scripts/tests/map_terrain_doc_test.gd:82, game/scripts/tests/map_terrain_doc_test.gd:121, … |
| **set_terrain_material** | 9 | 3 | game/scripts/tests/map_context_decor_test.gd:69, game/scripts/tests/map_context_decor_test.gd:70, game/scripts/tests/map_context_decor_test.gd:71, game/scripts/tests/map_terrain_doc_test.gd:91, game/scripts/tests/map_terrain_doc_test.gd:140, game/scripts/tests/map_terrain_doc_test.gd:151, … |
| **layer_stack_index** | 8 | 1 | game/scripts/tests/map_editor_test.gd:709, game/scripts/tests/map_editor_test.gd:712 |
| **fog_cells** | 7 | 1 | game/scripts/tests/map_editor_test.gd:323, game/scripts/tests/map_editor_test.gd:325, game/scripts/tests/map_editor_test.gd:327, game/scripts/tests/map_editor_test.gd:329, game/scripts/tests/map_editor_test.gd:331, game/scripts/tests/map_editor_test.gd:615 |
| **set_selection** | 7 | 2 | game/scripts/tests/map_editor_parametres_test.gd:216, game/scripts/tests/map_editor_test.gd:185, game/scripts/tests/map_editor_test.gd:195, game/scripts/tests/map_editor_test.gd:205, game/scripts/tests/map_editor_test.gd:209, game/scripts/tests/map_editor_test.gd:268, … |
| **paint_terrain_material_brush** | 6 | 3 | game/scripts/tests/map_terrain_doc_test.gd:93, game/scripts/tests/map_terrain_materials_test.gd:426, game/scripts/tests/map_terrain_materials_test.gd:429, game/scripts/tests/map_terrain_materials_test.gd:474, game/scripts/tests/terrain_palette_shot_test.gd:45, game/scripts/tests/terrain_palette_shot_test.gd:47 |
| **remove_element** | 6 | 3 | game/scripts/tests/map_editor_test.gd:136, game/scripts/tests/map_editor_test.gd:233, game/scripts/tests/map_editor_test.gd:719, game/scripts/tests/map_night_reveal_test.gd:110, game/scripts/tests/map_terrain_doc_test.gd:113 |
| **set_layer_locked** | 6 | 1 | game/scripts/tests/map_editor_test.gd:252, game/scripts/tests/map_editor_test.gd:254, game/scripts/tests/map_editor_test.gd:695, game/scripts/tests/map_editor_test.gd:701 |
| **set_meta_values** | 6 | 4 | game/scripts/tests/map_editor_parametres_test.gd:287, game/scripts/tests/map_editor_parametres_test.gd:290, game/scripts/tests/map_editor_test.gd:156, game/scripts/tests/map_organic_creation_test.gd:338, game/scripts/tests/map_quality_cs2_test.gd:172, game/scripts/tests/map_quality_cs2_test.gd:191 |
| **add_carve** | 5 | 1 | game/scripts/tests/terrain_carve_test.gd:235, game/scripts/tests/terrain_carve_test.gd:246, game/scripts/tests/terrain_carve_test.gd:247, game/scripts/tests/terrain_carve_test.gd:268, game/scripts/tests/terrain_carve_test.gd:269 |
| **light_revealed_cells** | 5 | 1 | game/scripts/tests/map_night_reveal_test.gd:96, game/scripts/tests/map_night_reveal_test.gd:101, game/scripts/tests/map_night_reveal_test.gd:107, game/scripts/tests/map_night_reveal_test.gd:111, game/scripts/tests/map_night_reveal_test.gd:113 |
| **link_elements** | 5 | 1 | game/scripts/tests/map_editor_test.gd:220, game/scripts/tests/map_editor_test.gd:221, game/scripts/tests/map_editor_test.gd:222, game/scripts/tests/map_editor_test.gd:229, game/scripts/tests/map_editor_test.gd:240 |
| **paint_terrain_brush** | 5 | 1 | game/scripts/tests/map_terrain_doc_test.gd:47, game/scripts/tests/map_terrain_doc_test.gd:51, game/scripts/tests/map_terrain_doc_test.gd:53, game/scripts/tests/map_terrain_doc_test.gd:131, game/scripts/tests/map_terrain_doc_test.gd:132 |
| **begin_transaction** | 4 | 3 | game/scripts/tests/map_editor_test.gd:125, game/scripts/tests/map_editor_test.gd:394, game/scripts/tests/map_terrain_doc_test.gd:130, game/scripts/tests/terrain_carve_test.gd:245 |
| **can_undo** | 4 | 3 | game/scripts/tests/city_scene_test.gd:268, game/scripts/tests/map_editor_test.gd:102, game/scripts/tests/map_editor_test.gd:106, game/scripts/tests/map_quality_cs2_test.gd:176 |
| **commit_transaction** | 4 | 3 | game/scripts/tests/map_editor_test.gd:128, game/scripts/tests/map_editor_test.gd:397, game/scripts/tests/map_terrain_doc_test.gd:133, game/scripts/tests/terrain_carve_test.gd:248 |
| **has_terrain_relief** | 4 | 1 | game/scripts/tests/map_terrain_doc_test.gd:39, game/scripts/tests/map_terrain_doc_test.gd:43, game/scripts/tests/map_terrain_doc_test.gd:184 |
| **hit_element_at** | 4 | 1 | game/scripts/tests/simple_map_editor_test.gd:49, game/scripts/tests/simple_map_editor_test.gd:50, game/scripts/tests/simple_map_editor_test.gd:76, game/scripts/tests/simple_map_editor_test.gd:77 |
| **is_dirty** | 4 | 1 | game/scripts/tests/map_editor_test.gd:102, game/scripts/tests/map_editor_test.gd:105, game/scripts/tests/map_editor_test.gd:741 |
| **link_segments** | 4 | 1 | game/scripts/tests/map_editor_test.gd:227, game/scripts/tests/map_editor_test.gd:230, game/scripts/tests/map_editor_test.gd:238, game/scripts/tests/map_editor_test.gd:242 |
| **move_elements_by** | 4 | 4 | game/scripts/tests/map_context_decor_test.gd:45, game/scripts/tests/map_editor_test.gd:352, game/scripts/tests/map_props_test.gd:183, game/scripts/tests/procedural_bridge_mesh_test.gd:98 |
| **terrain_materials** | 4 | 2 | game/scripts/tests/map_terrain_doc_test.gd:89, game/scripts/tests/map_terrain_materials_test.gd:422, game/scripts/tests/map_terrain_materials_test.gd:465, game/scripts/tests/map_terrain_materials_test.gd:466 |
| `_sculpt_support` | 3 | 1 | game/scripts/tests/terrain_sculpt_test.gd:171, game/scripts/tests/terrain_sculpt_test.gd:173, game/scripts/tests/terrain_sculpt_test.gd:182 |
| **add_water_body** | 3 | 3 | game/scripts/tests/river_user_trace_shot_test.gd:51, game/scripts/tests/river_user_trace_test.gd:47, game/scripts/tests/water_bodies_test.gd:203 |
| **commit_live_edit** | 3 | 3 | game/scripts/tests/map_editor_test.gd:145, game/scripts/tests/map_night_reveal_test.gd:105, game/scripts/tests/procedural_bridge_mesh_test.gd:95 |
| **is_element_visible** | 3 | 1 | game/scripts/tests/map_editor_test.gd:248, game/scripts/tests/map_editor_test.gd:250, game/scripts/tests/map_editor_test.gd:263 |
| **layer_name** | 3 | 1 | game/scripts/tests/map_editor_test.gd:256, game/scripts/tests/map_editor_test.gd:258, game/scripts/tests/map_editor_test.gd:276 |
| **move_layer_down** | 3 | 1 | game/scripts/tests/map_editor_test.gd:281, game/scripts/tests/map_editor_test.gd:710 |
| **paint_tiles** | 3 | 2 | game/scripts/tests/map_editor_test.gd:302, game/scripts/tests/map_editor_test.gd:314, game/scripts/tests/simple_map_editor_test.gd:65 |
| **sculpt_stamp** | 3 | 1 | game/scripts/tests/terrain_sculpt_test.gd:169, game/scripts/tests/terrain_sculpt_test.gd:398, game/scripts/tests/terrain_sculpt_test.gd:399 |
| **set_live_position** | 3 | 2 | game/scripts/tests/map_editor_test.gd:143, game/scripts/tests/map_editor_test.gd:151, game/scripts/tests/map_night_reveal_test.gd:104 |
| **carve_path** | 2 | 1 | game/scripts/tests/map_terrain_doc_test.gd:57, game/scripts/tests/map_terrain_doc_test.gd:102 |
| **copy_selection** | 2 | 2 | game/scripts/tests/map_editor_test.gd:196, game/scripts/tests/map_props_test.gd:178 |
| **is_element_selectable** | 2 | 1 | game/scripts/tests/map_editor_test.gd:253, game/scripts/tests/map_editor_test.gd:261 |
| **paint_terrain_spline** | 2 | 1 | game/scripts/tests/map_terrain_doc_test.gd:67, game/scripts/tests/map_terrain_doc_test.gd:74 |
| **paste** | 2 | 2 | game/scripts/tests/map_editor_test.gd:197, game/scripts/tests/map_props_test.gd:179 |
| **rebuild_light_reveal_from_lights** | 2 | 1 | game/scripts/tests/map_night_reveal_test.gd:100, game/scripts/tests/map_night_reveal_test.gd:106 |
| **resize_grid** | 2 | 2 | game/scripts/tests/map_editor_test.gd:315, game/scripts/tests/map_terrain_materials_test.gd:464 |
| **reveal_fog** | 2 | 1 | game/scripts/tests/map_editor_test.gd:322, game/scripts/tests/map_editor_test.gd:324 |
| **select_all** | 2 | 1 | game/scripts/tests/map_editor_test.gd:174, game/scripts/tests/map_editor_test.gd:180 |
| **set_layer_visible** | 2 | 1 | game/scripts/tests/map_editor_test.gd:249, game/scripts/tests/map_editor_test.gd:251 |
| **toggle_selection** | 2 | 1 | game/scripts/tests/map_editor_test.gd:170, game/scripts/tests/map_editor_test.gd:172 |
| **add_layer** | 1 | 1 | game/scripts/tests/map_editor_test.gd:275 |
| **align_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:341 |
| **bring_to_front** | 1 | 1 | game/scripts/tests/map_editor_test.gd:271 |
| **bucket_fill** | 1 | 1 | game/scripts/tests/map_editor_test.gd:308 |
| **clear_all_terrain** | 1 | 1 | game/scripts/tests/map_terrain_materials_test.gd:485 |
| **clear_carves** | 1 | 1 | game/scripts/tests/terrain_carve_test.gd:254 |
| **clear_light_reveal** | 1 | 1 | game/scripts/tests/map_night_reveal_test.gd:112 |
| **cut_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:210 |
| **distribute_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:346 |
| **duplicate_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:206 |
| **expand_selection_to_groups** | 1 | 1 | game/scripts/tests/map_editor_test.gd:189 |
| **fill_all_material** | 1 | 1 | game/scripts/tests/map_terrain_materials_test.gd:478 |
| **flatten_terrain_rect** | 1 | 1 | game/scripts/tests/map_terrain_doc_test.gd:83 |
| **group_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:186 |
| **hide_fog** | 1 | 1 | game/scripts/tests/map_editor_test.gd:326 |
| **hit_stack_at** | 1 | 1 | game/scripts/tests/simple_map_editor_test.gd:88 |
| **invert_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:177 |
| **modify_selection** | 1 | 1 | game/scripts/tests/map_mesh_test.gd:81 |
| **move_layer_up** | 1 | 1 | game/scripts/tests/map_editor_test.gd:278 |
| **paint_path_material** | 1 | 1 | game/scripts/tests/map_terrain_doc_test.gd:60 |
| **remove_elements** | 1 | 1 | game/scripts/tests/simple_map_editor_test.gd:90 |
| **remove_layer** | 1 | 1 | game/scripts/tests/map_editor_test.gd:284 |
| **rename_layer** | 1 | 1 | game/scripts/tests/map_editor_test.gd:255 |
| **reveal_all_fog** | 1 | 1 | game/scripts/tests/map_editor_test.gd:330 |
| **revert_live_edit** | 1 | 1 | game/scripts/tests/map_editor_test.gd:152 |
| **selection_bounds** | 1 | 1 | game/scripts/tests/map_editor_test.gd:181 |
| **send_to_back** | 1 | 1 | game/scripts/tests/map_editor_test.gd:269 |
| **set_layer_for_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:282 |
| **terrain_size** | 1 | 1 | game/scripts/tests/terrain_sculpt_live_test.gd:77 |
| **ungroup_selection** | 1 | 1 | game/scripts/tests/map_editor_test.gd:191 |
| **unlink_elements** | 1 | 1 | game/scripts/tests/map_editor_test.gd:241 |
| **update_water_body** | 1 | 1 | game/scripts/tests/water_bodies_test.gd:209 |

## 7. Tableau complet — moteur (`ComplexMapEngine3D`)

**128** membres distincts (dont **47** internes).

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| `_camera` | 126 | 23 | game/scripts/tests/camera_navigation_test.gd:25, game/scripts/tests/camera_navigation_test.gd:30, game/scripts/tests/camera_navigation_test.gd:35, game/scripts/tests/camera_navigation_test.gd:55, game/scripts/tests/camera_navigation_test.gd:59, game/scripts/tests/camera_navigation_test.gd:62, … |
| `_ground` | 80 | 17 | game/scripts/tests/cite_eau_shot_test.gd:53, game/scripts/tests/map_25d_mesh_demo_test.gd:57, game/scripts/tests/map_backdrop_test.gd:243, game/scripts/tests/map_quality_cs2_test.gd:714, game/scripts/tests/map_terrain_materials_test.gd:546, game/scripts/tests/map_terrain_materials_test.gd:549, … |
| **configure** | 69 | 32 | game/scripts/tests/cite_eau_shot_test.gd:46, game/scripts/tests/cliff_shot_test.gd:26, game/scripts/tests/fog_quality_shot_test.gd:78, game/scripts/tests/fog_quality_shot_test.gd:184, game/scripts/tests/fog_quality_shot_test.gd:211, game/scripts/tests/map_25d_mesh_demo_test.gd:48, … |
| **size** | 57 | 29 | game/scripts/tests/cite_eau_shot_test.gd:44, game/scripts/tests/fog_quality_shot_test.gd:76, game/scripts/tests/map_25d_mesh_demo_test.gd:45, game/scripts/tests/map_25d_mesh_demo_test.gd:64, game/scripts/tests/map_ambient_fx_test.gd:394, game/scripts/tests/map_backdrop_test.gd:231, … |
| `_meshes_layer` | 37 | 8 | game/scripts/tests/cite_eau_shot_test.gd:61, game/scripts/tests/cite_eau_shot_test.gd:62, game/scripts/tests/cite_eau_shot_test.gd:63, game/scripts/tests/cite_eau_shot_test.gd:64, game/scripts/tests/editor_drag_perf_test.gd:142, game/scripts/tests/map_25d_mesh_demo_test.gd:55, … |
| `_sun` | 36 | 5 | game/scripts/tests/map_editor_parametres_test.gd:82, game/scripts/tests/map_editor_parametres_test.gd:92, game/scripts/tests/map_lighting_test.gd:47, game/scripts/tests/map_quality_cs2_test.gd:686, game/scripts/tests/map_quality_cs2_test.gd:687, game/scripts/tests/map_quality_cs2_test.gd:688, … |
| **terrain_height_at** | 25 | 6 | game/scripts/tests/map_25d_mesh_demo_test.gd:59, game/scripts/tests/map_render_quality_test.gd:102, game/scripts/tests/map_terrain_test.gd:161, game/scripts/tests/map_terrain_test.gd:162, game/scripts/tests/map_terrain_test.gd:163, game/scripts/tests/map_terrain_test.gd:164, … |
| `_editor_gui_input` | 23 | 3 | game/scripts/tests/camera_navigation_test.gd:40, game/scripts/tests/camera_navigation_test.gd:44, game/scripts/tests/camera_navigation_test.gd:48, game/scripts/tests/camera_navigation_test.gd:53, game/scripts/tests/pan_cursor_tracking_test.gd:56, game/scripts/tests/pan_cursor_tracking_test.gd:60, … |
| `_water_layer` | 23 | 9 | game/scripts/tests/cite_eau_shot_test.gd:52, game/scripts/tests/map_flora_water_integration_test.gd:36, game/scripts/tests/map_water_test.gd:322, game/scripts/tests/map_water_test.gd:326, game/scripts/tests/map_water_test.gd:327, game/scripts/tests/map_water_test.gd:328, … |
| `_world_env` | 23 | 4 | game/scripts/tests/fog_quality_shot_test.gd:83, game/scripts/tests/fog_quality_shot_test.gd:103, game/scripts/tests/fog_quality_shot_test.gd:104, game/scripts/tests/fog_quality_shot_test.gd:108, game/scripts/tests/fog_quality_shot_test.gd:115, game/scripts/tests/fog_quality_shot_test.gd:295, … |
| **grid_to_screen** | 23 | 6 | game/scripts/tests/map_editor_test.gd:634, game/scripts/tests/map_editor_test.gd:686, game/scripts/tests/map_editor_test.gd:687, game/scripts/tests/map_editor_test.gd:689, game/scripts/tests/map_editor_test.gd:724, game/scripts/tests/map_terrain_test.gd:235, … |
| **queue_free** | 19 | 14 | game/scripts/tests/cite_eau_shot_test.gd:95, game/scripts/tests/cliff_shot_test.gd:45, game/scripts/tests/map_camera_test.gd:91, game/scripts/tests/map_camera_test.gd:150, game/scripts/tests/map_camera_test.gd:176, game/scripts/tests/map_lighting_test.gd:48, … |
| **zoom** | 19 | 10 | game/scripts/tests/camera_navigation_test.gd:74, game/scripts/tests/cite_showcase_shot_test.gd:72, game/scripts/tests/cite_showcase_shot_test.gd:161, game/scripts/tests/fog_quality_shot_test.gd:136, game/scripts/tests/fog_quality_shot_test.gd:155, game/scripts/tests/fog_quality_shot_test.gd:247, … |
| `_cell_size` | 17 | 11 | game/scripts/tests/cite_showcase_shot_test.gd:174, game/scripts/tests/fog_quality_shot_test.gd:266, game/scripts/tests/fog_quality_shot_test.gd:267, game/scripts/tests/map_mesh_test.gd:158, game/scripts/tests/map_mesh_test.gd:193, game/scripts/tests/map_meshes_3d_test.gd:280, … |
| `_dice` | 17 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:136, game/scripts/tests/table_poc_screenshot_test.gd:140, game/scripts/tests/table_view_test.gd:78, game/scripts/tests/table_view_test.gd:90, game/scripts/tests/table_view_test.gd:91, game/scripts/tests/table_view_test.gd:95, … |
| `_map_extent` | 15 | 7 | game/scripts/tests/camera_navigation_test.gd:73, game/scripts/tests/slab_quality_shot_test.gd:205, game/scripts/tests/staircase_cascade_shot_test.gd:85, game/scripts/tests/table_view_test.gd:73, game/scripts/tests/table_view_test.gd:121, game/scripts/tests/terrain_quality_shot_test.gd:528, … |
| **refresh_terrain** | 15 | 8 | game/scripts/tests/map_ambient_fx_test.gd:430, game/scripts/tests/map_ambient_fx_test.gd:435, game/scripts/tests/map_ambient_fx_test.gd:440, game/scripts/tests/map_ambient_fx_test.gd:445, game/scripts/tests/map_backdrop_test.gd:258, game/scripts/tests/map_terrain_materials_test.gd:568, … |
| **is_ambient_fx_active** | 14 | 2 | game/scripts/tests/map_ambient_fx_test.gd:402, game/scripts/tests/map_ambient_fx_test.gd:409, game/scripts/tests/map_ambient_fx_test.gd:415, game/scripts/tests/map_ambient_fx_test.gd:419, game/scripts/tests/map_ambient_fx_test.gd:424, game/scripts/tests/map_ambient_fx_test.gd:426, … |
| `_fit_to_view` | 13 | 7 | game/scripts/tests/cite_eau_shot_test.gd:69, game/scripts/tests/cite_eau_shot_test.gd:109, game/scripts/tests/fog_quality_shot_test.gd:120, game/scripts/tests/fog_quality_shot_test.gd:188, game/scripts/tests/fog_quality_shot_test.gd:219, game/scripts/tests/map_quality_cs2_shot_test.gd:69, … |
| `_apply_zoom` | 12 | 6 | game/scripts/tests/map_25d_mesh_demo_test.gd:64, game/scripts/tests/map_camera_test.gd:79, game/scripts/tests/table_poc_screenshot_test.gd:121, game/scripts/tests/table_poc_screenshot_test.gd:146, game/scripts/tests/table_view_test.gd:177, game/scripts/tests/table_view_test.gd:181, … |
| `_update_ortho_size` | 12 | 7 | game/scripts/tests/cite_showcase_shot_test.gd:73, game/scripts/tests/cite_showcase_shot_test.gd:162, game/scripts/tests/fog_quality_shot_test.gd:137, game/scripts/tests/fog_quality_shot_test.gd:156, game/scripts/tests/fog_quality_shot_test.gd:248, game/scripts/tests/map_quality_cs2_shot_test.gd:143, … |
| **get_atmospheric_fog_height_factor** | 12 | 3 | game/scripts/tests/fog_quality_shot_test.gd:222, game/scripts/tests/fog_quality_shot_test.gd:253, game/scripts/tests/fog_quality_shot_test.gd:254, game/scripts/tests/fog_quality_shot_test.gd:273, game/scripts/tests/fog_quality_shot_test.gd:274, game/scripts/tests/fog_quality_shot_test.gd:386, … |
| **map_data** | 12 | 4 | game/scripts/tests/fog_quality_shot_test.gd:395, game/scripts/tests/fog_quality_shot_test.gd:401, game/scripts/tests/fog_quality_shot_test.gd:407, game/scripts/tests/fog_quality_shot_test.gd:409, game/scripts/tests/map_camera_test.gd:143, game/scripts/tests/map_quality_cs2_shot_test.gd:90, … |
| `_backdrop_layer` | 11 | 2 | game/scripts/tests/map_backdrop_test.gd:238, game/scripts/tests/map_backdrop_test.gd:243, game/scripts/tests/map_backdrop_test.gd:244, game/scripts/tests/map_backdrop_test.gd:249, game/scripts/tests/map_backdrop_test.gd:251, game/scripts/tests/map_backdrop_test.gd:253, … |
| `_viewport` | 11 | 6 | game/scripts/tests/fog_quality_shot_test.gd:103, game/scripts/tests/map_25d_mesh_demo_test.gd:82, game/scripts/tests/map_quality_cs2_test.gd:897, game/scripts/tests/map_quality_cs2_test.gd:898, game/scripts/tests/map_quality_cs2_test.gd:907, game/scripts/tests/map_quality_cs2_test.gd:908, … |
| **reset_zoom** | 11 | 6 | game/scripts/tests/map_camera_test.gd:56, game/scripts/tests/map_camera_test.gd:138, game/scripts/tests/map_camera_test.gd:162, game/scripts/tests/table_poc_screenshot_test.gd:55, game/scripts/tests/table_poc_screenshot_test.gd:119, game/scripts/tests/table_poc_screenshot_test.gd:127, … |
| **get_quality_preset** | 10 | 2 | game/scripts/tests/map_quality_cs2_shot_test.gd:66, game/scripts/tests/map_quality_cs2_test.gd:709, game/scripts/tests/map_quality_cs2_test.gd:751, game/scripts/tests/map_quality_cs2_test.gd:825, game/scripts/tests/map_quality_cs2_test.gd:836, game/scripts/tests/map_quality_cs2_test.gd:846, … |
| **is_water_active** | 10 | 2 | game/scripts/tests/map_flora_water_integration_test.gd:30, game/scripts/tests/map_water_test.gd:323, game/scripts/tests/map_water_test.gd:335, game/scripts/tests/map_water_test.gd:344, game/scripts/tests/map_water_test.gd:351, game/scripts/tests/map_water_test.gd:358, … |
| **sync_atmospheric_fog** | 10 | 3 | game/scripts/tests/fog_quality_shot_test.gd:123, game/scripts/tests/fog_quality_shot_test.gd:191, game/scripts/tests/fog_quality_shot_test.gd:249, game/scripts/tests/fog_quality_shot_test.gd:269, game/scripts/tests/fog_quality_shot_test.gd:411, game/scripts/tests/map_quality_cs2_shot_test.gd:109, … |
| `_ambient_fx_layer` | 8 | 1 | game/scripts/tests/map_ambient_fx_test.gd:401, game/scripts/tests/map_ambient_fx_test.gd:405, game/scripts/tests/map_ambient_fx_test.gd:411, game/scripts/tests/map_ambient_fx_test.gd:417, game/scripts/tests/map_ambient_fx_test.gd:421, game/scripts/tests/map_ambient_fx_test.gd:464, … |
| `_center_focus_on` | 8 | 6 | game/scripts/tests/map_quality_cs2_shot_test.gd:144, game/scripts/tests/map_quality_cs2_shot_test.gd:539, game/scripts/tests/map_quality_cs2_test.gd:801, game/scripts/tests/map_quality_cs2_test.gd:811, game/scripts/tests/rock_formation_shot_test.gd:132, game/scripts/tests/scene_rocks_shot_test.gd:58, … |
| `_table_elev` | 8 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:113, game/scripts/tests/table_view_test.gd:152, game/scripts/tests/table_view_test.gd:157, game/scripts/tests/table_view_test.gd:159, game/scripts/tests/table_view_test.gd:163, game/scripts/tests/table_view_test.gd:169, … |
| **focus_grid_rect** | 8 | 5 | game/scripts/tests/cite_showcase_shot_test.gd:56, game/scripts/tests/cite_showcase_shot_test.gd:71, game/scripts/tests/cite_showcase_shot_test.gd:225, game/scripts/tests/cliff_shot_test.gd:29, game/scripts/tests/rock_formation_shot_test.gd:66, game/scripts/tests/rock_formation_shot_test.gd:118, … |
| **get_ambient_fx** | 8 | 1 | game/scripts/tests/map_ambient_fx_test.gd:403, game/scripts/tests/map_ambient_fx_test.gd:410, game/scripts/tests/map_ambient_fx_test.gd:416, game/scripts/tests/map_ambient_fx_test.gd:420, game/scripts/tests/map_ambient_fx_test.gd:433, game/scripts/tests/map_ambient_fx_test.gd:438, … |
| **get_viewport** | 8 | 8 | game/scripts/tests/cite_eau_shot_test.gd:139, game/scripts/tests/fog_quality_shot_test.gd:462, game/scripts/tests/map_quality_cs2_shot_test.gd:553, game/scripts/tests/slab_quality_shot_test.gd:290, game/scripts/tests/staircase_cascade_shot_test.gd:110, game/scripts/tests/terrain_quality_shot_test.gd:929, … |
| **has_method** | 8 | 6 | game/scripts/tests/cliff_shot_test.gd:28, game/scripts/tests/map_camera_test.gd:55, game/scripts/tests/map_terrain_doc_test.gd:187, game/scripts/tests/terrain_palette_shot_test.gd:51, game/scripts/tests/token_figurine_shot_test.gd:43, game/scripts/tests/token_figurine_shot_test.gd:45, … |
| **request_fit_to_view** | 8 | 8 | game/scripts/tests/demo_saules_shot_test.gd:69, game/scripts/tests/map_25d_mesh_demo_test.gd:51, game/scripts/tests/river_live_shot_test.gd:77, game/scripts/tests/river_user_trace_shot_test.gd:56, game/scripts/tests/riviere_s_shot_test.gd:46, game/scripts/tests/terrain_carve_shot_test.gd:100, … |
| **set_table_seat** | 8 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:104, game/scripts/tests/table_poc_screenshot_test.gd:107, game/scripts/tests/table_poc_screenshot_test.gd:112, game/scripts/tests/table_poc_screenshot_test.gd:128, game/scripts/tests/table_view_test.gd:133, game/scripts/tests/table_view_test.gd:138, … |
| `_ground_focus` | 7 | 4 | game/scripts/tests/camera_navigation_test.gd:73, game/scripts/tests/camera_navigation_test.gd:74, game/scripts/tests/map_camera_test.gd:174, game/scripts/tests/pan_cursor_tracking_test.gd:142, game/scripts/tests/pan_cursor_tracking_test.gd:165, game/scripts/tests/pan_cursor_tracking_test.gd:169, … |
| `_token_nodes` | 7 | 4 | game/scripts/tests/map_render_quality_test.gd:80, game/scripts/tests/map_render_quality_test.gd:81, game/scripts/tests/map_render_quality_test.gd:91, game/scripts/tests/map_render_quality_test.gd:92, game/scripts/tests/map_terrain_test.gd:250, game/scripts/tests/table_view_test.gd:56, … |
| **get_cell_size** | 7 | 6 | game/scripts/tests/map_backdrop_test.gd:246, game/scripts/tests/map_camera_test.gd:66, game/scripts/tests/map_camera_test.gd:146, game/scripts/tests/map_terrain_materials_test.gd:542, game/scripts/tests/map_terrain_test.gd:145, game/scripts/tests/map_water_test.gd:320, … |
| **get_ground_mode** | 7 | 1 | game/scripts/tests/map_terrain_test.gd:148, game/scripts/tests/map_terrain_test.gd:149, game/scripts/tests/map_terrain_test.gd:196, game/scripts/tests/map_terrain_test.gd:214, game/scripts/tests/map_terrain_test.gd:260, game/scripts/tests/map_terrain_test.gd:271, … |
| **is_backdrop_active** | 7 | 1 | game/scripts/tests/map_backdrop_test.gd:239, game/scripts/tests/map_backdrop_test.gd:260, game/scripts/tests/map_backdrop_test.gd:275, game/scripts/tests/map_backdrop_test.gd:285, game/scripts/tests/map_backdrop_test.gd:288, game/scripts/tests/map_backdrop_test.gd:291, … |
| **is_cinema_quality** | 7 | 3 | game/scripts/tests/map_quality_cs2_shot_test.gd:81, game/scripts/tests/map_quality_cs2_test.gd:710, game/scripts/tests/map_quality_cs2_test.gd:752, game/scripts/tests/map_quality_cs2_test.gd:837, game/scripts/tests/object_grounding_test.gd:34, game/scripts/tests/object_grounding_test.gd:56, … |
| **set_atmospheric_fog_enabled** | 7 | 2 | game/scripts/tests/fog_quality_shot_test.gd:107, game/scripts/tests/fog_quality_shot_test.gd:114, game/scripts/tests/fog_quality_shot_test.gd:291, game/scripts/tests/fog_quality_shot_test.gd:296, game/scripts/tests/fog_quality_shot_test.gd:373, game/scripts/tests/map_quality_cs2_test.gd:524, … |
| **set_atmospheric_tilt_aware** | 7 | 3 | game/scripts/tests/fog_quality_shot_test.gd:290, game/scripts/tests/fog_quality_shot_test.gd:381, game/scripts/tests/map_quality_cs2_shot_test.gd:122, game/scripts/tests/map_quality_cs2_shot_test.gd:577, game/scripts/tests/map_quality_cs2_shot_test.gd:602, game/scripts/tests/map_quality_cs2_test.gd:484, … |
| **set_quality_preset** | 7 | 3 | game/scripts/tests/map_quality_cs2_shot_test.gd:78, game/scripts/tests/map_quality_cs2_shot_test.gd:155, game/scripts/tests/map_quality_cs2_shot_test.gd:187, game/scripts/tests/map_quality_cs2_test.gd:748, game/scripts/tests/map_quality_cs2_test.gd:822, game/scripts/tests/object_grounding_test.gd:53, … |
| `_apply_lighting` | 6 | 2 | game/scripts/tests/fog_quality_shot_test.gd:402, game/scripts/tests/fog_quality_shot_test.gd:410, game/scripts/tests/map_quality_cs2_shot_test.gd:91, game/scripts/tests/map_quality_cs2_shot_test.gd:121, game/scripts/tests/map_quality_cs2_shot_test.gd:596, game/scripts/tests/map_quality_cs2_shot_test.gd:601 |
| `_table_env` | 6 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:59, game/scripts/tests/table_poc_screenshot_test.gd:130, game/scripts/tests/table_view_test.gd:42, game/scripts/tests/table_view_test.gd:43, game/scripts/tests/table_view_test.gd:234 |
| `_table_yaw` | 6 | 1 | game/scripts/tests/table_view_test.gd:135, game/scripts/tests/table_view_test.gd:139, game/scripts/tests/table_view_test.gd:151, game/scripts/tests/table_view_test.gd:156, game/scripts/tests/table_view_test.gd:162, game/scripts/tests/table_view_test.gd:168 |
| `_vegetation_layer` | 6 | 1 | game/scripts/tests/map_render_quality_test.gd:50, game/scripts/tests/map_render_quality_test.gd:124, game/scripts/tests/map_render_quality_test.gd:125, game/scripts/tests/map_render_quality_test.gd:133 |
| **center_on_grid** | 6 | 3 | game/scripts/tests/camera_navigation_test.gd:23, game/scripts/tests/cite_showcase_shot_test.gd:163, game/scripts/tests/pan_cursor_tracking_test.gd:41, game/scripts/tests/pan_cursor_tracking_test.gd:82, game/scripts/tests/pan_cursor_tracking_test.gd:122, game/scripts/tests/pan_cursor_tracking_test.gd:136 |
| **get_active_shadow_casters** | 6 | 2 | game/scripts/tests/map_quality_cs2_shot_test.gd:137, game/scripts/tests/map_quality_cs2_test.gd:795, game/scripts/tests/map_quality_cs2_test.gd:796, game/scripts/tests/map_quality_cs2_test.gd:805, game/scripts/tests/map_quality_cs2_test.gd:806, game/scripts/tests/map_quality_cs2_test.gd:807 |
| **get_water_level** | 6 | 1 | game/scripts/tests/map_water_test.gd:324, game/scripts/tests/map_water_test.gd:334, game/scripts/tests/map_water_test.gd:352, game/scripts/tests/map_water_test.gd:365, game/scripts/tests/map_water_test.gd:375, game/scripts/tests/map_water_test.gd:385 |
| **set_anchors_and_offsets_preset** | 6 | 6 | game/scripts/tests/cliff_shot_test.gd:24, game/scripts/tests/map_25d_mesh_demo_test.gd:44, game/scripts/tests/table_poc_screenshot_test.gd:44, game/scripts/tests/terrain_carve_shot_test.gd:93, game/scripts/tests/token_figurine_shot_test.gd:29, game/scripts/tests/valbois_screenshot_test.gd:47 |
| **terrain_has_relief** | 6 | 3 | game/scripts/tests/map_25d_mesh_demo_test.gd:56, game/scripts/tests/map_terrain_materials_test.gd:576, game/scripts/tests/map_terrain_test.gd:160, game/scripts/tests/map_terrain_test.gd:199, game/scripts/tests/map_terrain_test.gd:215, game/scripts/tests/map_terrain_test.gd:267 |
| `_control_to_viewport` | 5 | 2 | game/scripts/tests/pan_cursor_tracking_test.gd:61, game/scripts/tests/pan_cursor_tracking_test.gd:73, game/scripts/tests/pan_cursor_tracking_test.gd:127, game/scripts/tests/pan_cursor_tracking_test.gd:130, game/scripts/tests/zoom_to_cursor_test.gd:47 |
| `_orbit_target` | 5 | 3 | game/scripts/tests/cite_showcase_shot_test.gd:187, game/scripts/tests/map_camera_test.gd:172, game/scripts/tests/map_camera_test.gd:175, game/scripts/tests/riviere_s_shot_test.gd:66 |
| `_raycast_ground` | 5 | 2 | game/scripts/tests/pan_cursor_tracking_test.gd:61, game/scripts/tests/pan_cursor_tracking_test.gd:73, game/scripts/tests/pan_cursor_tracking_test.gd:127, game/scripts/tests/pan_cursor_tracking_test.gd:130, game/scripts/tests/zoom_to_cursor_test.gd:48 |
| **roll_table_dice_at** | 5 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:133, game/scripts/tests/table_view_test.gd:76, game/scripts/tests/table_view_test.gd:93, game/scripts/tests/table_view_test.gd:97, game/scripts/tests/table_view_test.gd:101 |
| **set_ambient_fx** | 5 | 1 | game/scripts/tests/map_ambient_fx_test.gd:408, game/scripts/tests/map_ambient_fx_test.gd:414, game/scripts/tests/map_ambient_fx_test.gd:418, game/scripts/tests/map_ambient_fx_test.gd:423, game/scripts/tests/map_ambient_fx_test.gd:425 |
| `_orbit_enabled` | 4 | 4 | game/scripts/tests/camera_navigation_test.gd:78, game/scripts/tests/cite_showcase_shot_test.gd:186, game/scripts/tests/map_camera_test.gd:169, game/scripts/tests/riviere_s_shot_test.gd:65 |
| **get_backdrop_material** | 4 | 1 | game/scripts/tests/map_backdrop_test.gd:240, game/scripts/tests/map_backdrop_test.gd:268, game/scripts/tests/map_backdrop_test.gd:276, game/scripts/tests/map_backdrop_test.gd:299 |
| **get_vegetation_count** | 4 | 1 | game/scripts/tests/map_render_quality_test.gd:49, game/scripts/tests/map_render_quality_test.gd:64, game/scripts/tests/map_render_quality_test.gd:68, game/scripts/tests/map_render_quality_test.gd:132 |
| **is_terrain_splat_active** | 4 | 1 | game/scripts/tests/map_terrain_materials_test.gd:545, game/scripts/tests/map_terrain_materials_test.gd:598, game/scripts/tests/map_terrain_materials_test.gd:605, game/scripts/tests/map_terrain_materials_test.gd:615 |
| **screen_to_grid_pos** | 4 | 4 | game/scripts/tests/map_editor_test.gd:636, game/scripts/tests/map_terrain_test.gd:244, game/scripts/tests/valbois_diorama_setup.gd:132, game/scripts/tests/valbois_screenshot_test.gd:71 |
| **set_ground_mode** | 4 | 2 | game/scripts/tests/map_backdrop_test.gd:286, game/scripts/tests/map_backdrop_test.gd:289, game/scripts/tests/map_terrain_test.gd:258, game/scripts/tests/map_terrain_test.gd:269 |
| **set_shadow_budget_cells** | 4 | 2 | game/scripts/tests/map_quality_cs2_shot_test.gd:134, game/scripts/tests/map_quality_cs2_shot_test.gd:149, game/scripts/tests/map_quality_cs2_test.gd:802, game/scripts/tests/map_quality_cs2_test.gd:817 |
| `_ground_span_per_pixel` | 3 | 1 | game/scripts/tests/map_camera_test.gd:61, game/scripts/tests/map_camera_test.gd:81, game/scripts/tests/map_camera_test.gd:145 |
| `_orbit_distance` | 3 | 3 | game/scripts/tests/cite_showcase_shot_test.gd:188, game/scripts/tests/map_camera_test.gd:173, game/scripts/tests/riviere_s_shot_test.gd:67 |
| `_table_target` | 3 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:145, game/scripts/tests/table_view_test.gd:164, game/scripts/tests/table_view_test.gd:170 |
| **begin_view_pan** | 3 | 2 | game/scripts/tests/map_camera_test.gd:83, game/scripts/tests/table_view_test.gd:153, game/scripts/tests/table_view_test.gd:165 |
| **get** | 3 | 3 | game/scripts/tests/fog_quality_shot_test.gd:460, game/scripts/tests/map_editor_test.gd:548, game/scripts/tests/map_quality_cs2_shot_test.gd:551 |
| **get_vegetation_counts** | 3 | 2 | game/scripts/tests/map_flora_water_integration_test.gd:33, game/scripts/tests/map_render_quality_test.gd:46, game/scripts/tests/map_render_quality_test.gd:167 |
| **is_sky_active** | 3 | 2 | game/scripts/tests/fog_quality_shot_test.gd:187, game/scripts/tests/map_render_quality_test.gd:146, game/scripts/tests/map_render_quality_test.gd:216 |
| **is_terrain3d_ground** | 3 | 2 | game/scripts/tests/map_terrain_materials_test.gd:544, game/scripts/tests/map_terrain_test.gd:150, game/scripts/tests/map_terrain_test.gd:261 |
| **is_vegetation_active** | 3 | 2 | game/scripts/tests/map_flora_water_integration_test.gd:31, game/scripts/tests/map_render_quality_test.gd:45, game/scripts/tests/map_render_quality_test.gd:131 |
| **set_table_dice_sides** | 3 | 1 | game/scripts/tests/table_view_test.gd:92, game/scripts/tests/table_view_test.gd:96, game/scripts/tests/table_view_test.gd:100 |
| **set_table_view** | 3 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:52, game/scripts/tests/table_view_test.gd:39, game/scripts/tests/table_view_test.gd:232 |
| **set_terrain_materials** | 3 | 1 | game/scripts/tests/map_terrain_materials_test.gd:587, game/scripts/tests/map_terrain_materials_test.gd:593, game/scripts/tests/map_terrain_materials_test.gd:595 |
| **update_view_pan** | 3 | 2 | game/scripts/tests/map_camera_test.gd:84, game/scripts/tests/table_view_test.gd:154, game/scripts/tests/table_view_test.gd:166 |
| `_lights_layer` | 2 | 1 | game/scripts/tests/map_lighting_test.gd:45, game/scripts/tests/map_lighting_test.gd:46 |
| `_orbit_pitch` | 2 | 2 | game/scripts/tests/cite_showcase_shot_test.gd:190, game/scripts/tests/riviere_s_shot_test.gd:69 |
| `_orbit_yaw` | 2 | 2 | game/scripts/tests/cite_showcase_shot_test.gd:189, game/scripts/tests/riviere_s_shot_test.gd:68 |
| `_pan_anchor_valid` | 2 | 1 | game/scripts/tests/pan_cursor_tracking_test.gd:163, game/scripts/tests/pan_cursor_tracking_test.gd:167 |
| `_table_target_point` | 2 | 2 | game/scripts/tests/table_poc_screenshot_test.gd:74, game/scripts/tests/table_view_test.gd:175 |
| `_terrain_sculpt` | 2 | 1 | game/scripts/tests/terrain_sculpt_live_test.gd:48, game/scripts/tests/terrain_sculpt_live_test.gd:49 |
| `_tokens_layer` | 2 | 2 | game/scripts/tests/map_terrain_test.gd:249, game/scripts/tests/procedural_bridge_mesh_test.gd:86 |
| `_viewport_to_control` | 2 | 1 | game/scripts/tests/map_terrain_test.gd:234, game/scripts/tests/map_terrain_test.gd:239 |
| **end_view_pan** | 2 | 1 | game/scripts/tests/table_view_test.gd:155, game/scripts/tests/table_view_test.gd:167 |
| **get_atmospheric_fog_settings** | 2 | 1 | game/scripts/tests/map_quality_cs2_test.gd:449, game/scripts/tests/map_quality_cs2_test.gd:487 |
| **get_shadow_budget_cells** | 2 | 1 | game/scripts/tests/map_quality_cs2_test.gd:790, game/scripts/tests/map_quality_cs2_test.gd:791 |
| **get_shadow_caster_count** | 2 | 2 | game/scripts/tests/map_quality_cs2_shot_test.gd:130, game/scripts/tests/map_quality_cs2_test.gd:792 |
| **get_table_seat** | 2 | 1 | game/scripts/tests/table_view_test.gd:141, game/scripts/tests/table_view_test.gd:229 |
| **get_terrain_materials** | 2 | 1 | game/scripts/tests/map_terrain_materials_test.gd:547, game/scripts/tests/map_terrain_materials_test.gd:597 |
| **is_arrival_pulse_playing** | 2 | 1 | game/scripts/tests/map_render_quality_test.gd:107, game/scripts/tests/map_render_quality_test.gd:109 |
| **is_atmospheric_tilt_aware** | 2 | 1 | game/scripts/tests/map_quality_cs2_test.gd:516, game/scripts/tests/map_quality_cs2_test.gd:522 |
| **is_table_view** | 2 | 1 | game/scripts/tests/table_view_test.gd:41, game/scripts/tests/table_view_test.gd:234 |
| **set_water_level** | 2 | 1 | game/scripts/tests/map_water_test.gd:333, game/scripts/tests/map_water_test.gd:343 |
| **terrain_normal_at** | 2 | 2 | game/scripts/tests/map_terrain_test.gd:173, game/scripts/tests/terrain_carve_test.gd:393 |
| **visible_grid_rect** | 2 | 2 | game/scripts/tests/map_camera_test.gd:71, game/scripts/tests/table_view_test.gd:195 |
| `_apply_view_state` | 1 | 1 | game/scripts/tests/table_view_test.gd:228 |
| `_begin_orbit_drag` | 1 | 1 | game/scripts/tests/map_camera_test.gd:166 |
| `_clamp_camera` | 1 | 1 | game/scripts/tests/zoom_to_cursor_test.gd:69 |
| `_create_token_node` | 1 | 1 | game/scripts/tests/procedural_bridge_mesh_test.gd:85 |
| `_table_dist_limits` | 1 | 1 | game/scripts/tests/table_view_test.gd:186 |
| `_update_orbit_drag` | 1 | 1 | game/scripts/tests/map_camera_test.gd:167 |
| `_update_shadow_budget` | 1 | 1 | game/scripts/tests/map_quality_cs2_test.gd:812 |
| `_visible_ground_size` | 1 | 1 | game/scripts/tests/water_bodies_shot_test.gd:85 |
| **begin_dice_throw** | 1 | 1 | game/scripts/tests/table_view_test.gd:111 |
| **call** | 1 | 1 | game/scripts/tests/map_editor_parametres_test.gd:67 |
| **cycle_table_seat** | 1 | 1 | game/scripts/tests/table_view_test.gd:140 |
| **end_dice_throw** | 1 | 1 | game/scripts/tests/table_view_test.gd:114 |
| **fit** | 1 | 1 | game/scripts/tests/token_figurine_shot_test.gd:44 |
| **get_camera_attributes** | 1 | 1 | game/scripts/tests/map_render_quality_test.gd:178 |
| **get_sky_material** | 1 | 1 | game/scripts/tests/map_render_quality_test.gd:148 |
| **get_view_state** | 1 | 1 | game/scripts/tests/table_view_test.gd:225 |
| **get_vignette_strength** | 1 | 1 | game/scripts/tests/map_render_quality_test.gd:177 |
| **has_element_node** | 1 | 1 | game/scripts/tests/map_mesh_test.gd:162 |
| **play_arrival_pulse** | 1 | 1 | game/scripts/tests/map_render_quality_test.gd:106 |
| **reset_editor_camera** | 1 | 1 | game/scripts/tests/scene_rocks_shot_test.gd:49 |
| **set_editor_mode** | 1 | 1 | game/scripts/tests/map_camera_test.gd:160 |
| **set_element_position** | 1 | 1 | game/scripts/tests/map_mesh_test.gd:164 |
| **set_table_dice_color** | 1 | 1 | game/scripts/tests/table_poc_screenshot_test.gd:129 |
| **TABLE_ELEV_MAX** | 1 | 1 | game/scripts/tests/table_view_test.gd:159 |
| **TABLE_ELEV_MIN** | 1 | 1 | game/scripts/tests/table_view_test.gd:159 |
| **table_seat_label** | 1 | 1 | game/scripts/tests/table_view_test.gd:142 |
| **update_dice_throw** | 1 | 1 | game/scripts/tests/table_view_test.gd:113 |

## 8. Nœuds `%Nom` de la scène atteints par les tests

Accès via les chemins de noeuds (has_node/get_node/find_child) sur les instances d'éditeur.

| Membre | Accès | Fichiers | Références (fichier:ligne) |
|---|---:|---:|---|
| **MinimapHost** | 2 | 1 | game/scripts/tests/map_editor_parametres_test.gd:180, game/scripts/tests/map_editor_parametres_test.gd:183 |
| **BtnParametres** | 1 | 1 | game/scripts/tests/map_editor_parametres_test.gd:157 |

## 9. Mode d'emploi

1. **Avant** une vague d'extraction : relancer ce script, conserver le document (git) ;
2. **Après** la vague : relancer et comparer. Tout membre disparu = accès de test perdu ou renommé sans mise à jour ;
3. un membre listé ici ne se renomme **jamais** sans mise à jour simultanée des tests (`game/scripts/tests/*.gd`) ;
4. en cas de doute sur un membre : `git grep -n "<membre>" -- game/scripts/tests` pour retrouver l'usage.

