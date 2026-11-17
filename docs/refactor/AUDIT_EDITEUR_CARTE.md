# Audit d'architecture — god files de l'éditeur de cartes 2.5D/3D

> Audit **READ-ONLY** du périmètre `game/scripts/maps/**` + `game/scenes/map_editor/**` + tests associés.
> Baseline : commit `4514c61` (« chore(artefacts)… »), worktree propre hors artefacts déjà non suivis.
> Aucun fichier existant n'a été modifié ; seul livrable = ce document.
> Compléments : [INVENTAIRE_TECHNIQUE.md](./INVENTAIRE_TECHNIQUE.md) (volumétrie globale, générée par `tools/refactor/metrics.ps1`),
> patron de refactor à réutiliser : [REFACTOR_EDITEUR.md](../REFACTOR_EDITEUR.md), architecture cible : [ARCHITECTURE.md](../ARCHITECTURE.md).
> Toutes les lignes citées sont vérifiées sur la baseline ; les comptages « lignes/fonctions » excluent les lignes vides résiduelles de fin de fichier.

## 0. Verdict en une page

**Cinq problèmes majeurs**

1. **L'éditeur a regrossi après le refactor réussi.** `map_complex_editor.gd` faisait 3 253 l. après le refactor documenté ([REFACTOR_EDITEUR.md:16](../REFACTOR_EDITEUR.md)) ; il fait **5 359 l. / 269 fonctions** aujourd'hui (+65 %). Preuve que l'extraction seule ne borne pas la croissance : il manque des **frontières de propriété** (un module extrait ne doit plus être réécrit dans le contrôleur).
2. **Les tests sont devenus le vrai contrat d'API, et il est privé.** 50 fichiers de test instancient `map_editor.tscn` et atteignent **169 membres distincts** de l'éditeur (dont **153 privés**) ; 41 tests atteignent **99 membres** de `MapEditDocument` ; 32 tests atteignent **130 membres** du moteur 3D (dont **49 internes** `_camera`, `_meshes_layer`, `_orbit_*`, `_table_*`). Tout renommage casse silencieusement un test — ou pire, ne casse rien et laisse le contrat dériver.
3. **Le patron `setup(editor)` + `_ed` non typé atteint sa limite.** Les modules extraits totalisent **508** accès `_ed.` sur **109 membres distincts** pour `map_editor_tool_options.gd`, 469/77 pour `map_editor_construction.gd`, 425/59 pour `map_editor_edit_ops.gd`. Aucune vérification à la compilation : une faute de frappe ne se voit qu'au runtime du chemin concerné (limite déjà notée, [REFACTOR_EDITEUR.md:57-61](../REFACTOR_EDITEUR.md)).
4. **La logique de terrain existe en 4 copies qui se déclarent elles-mêmes « mêmes formules ».** `MapGround3D._vertex_height` (map_ground_3d.gd:1551), `TerrainCarveField.vertex_height` (terrain_carve_field.gd:1183, commentaire « **même formule que** `MapGround3D._vertex_height` »), `TerrainCarveField.cell_bilinear` (terrain_carve_field.gd:1210, « même formule que `ComplexMapEngine3D.terrain_height_at` ») et la méthode dupliquée à l'identique dans 3 calques (map_meshes_3d.gd:363, map_props_3d.gd:142, map_token_3d.gd:136). Toute correction de convention de hauteur doit être faite 4 fois.
5. **Code mort et doublons v1/v2 encore chargés.** 4 modules d'éditeur « morts » (547 l., 0 référence), 6 scripts legacy (666 l., 0 référence), la grille d'outils v1 construite puis **masquée** (map_complex_editor.gd:653 puis 660), la palette d'environnement instanciée puis masquée (674-680) mais encore synchronisée (4546-4547), et la même logique de barre d'options réécrite dans 3 fichiers (`map_complex_editor.gd:5153`, `map_editor_tool_options.gd:204`, `simple_map_editor.gd:245`).

**Trois cibles prioritaires**

1. `game/scripts/maps/editor/map_edit_document.gd` (2 623 l.) — modèle pur `RefCounted`, 41 tests, 99 API : meilleur ratio gain/risque.
2. `game/scripts/maps/editor/map_editor_construction.gd` (2 679 l.) — 10 sous-domaines déjà lisibles par blocs ; wrappers testés donc extraction sans rupture.
3. `game/scripts/maps/map_layers/map_water_3d.gd` (2 235 l.) — une seule fonction de 435 l. (`_build_river_body`, l. 899) et une API `configure()` stable : gain immédiat, risque faible.

**Ce qui va bien (à préserver)**

- Séparation document / moteur / overlay / panneaux documentée et réelle ([MAP_EDITOR.md:592-606](../MAP_EDITOR.md)).
- `MapEditDocument` est pur (aucun `Node`, aucun autoload direct hors `MapData`), entièrement couvert.
- Les convertisseurs purs de construction sont **déjà partagés** entre éditeur et carte démo (`ProceduralCity.build_city_elements`, map_editor_construction.gd:2025-2072) : pas de duplication éditeur/Hub à corriger.
- `.tscn` propre : `map_editor.tscn` ne fait que 245 l. et tout passe par `unique_name_in_owner` (`%Nom`), pas par des chemins de nœuds fragiles.

## 1. Inventaire quantifié

| Fichier | Lignes | Fonctions | Signaux | `preload` | Vars top-level | Nœuds `.new()` en code |
|---|---:|---:|---:|---:|---:|---:|
| `maps/map_complex_editor.gd` | 5 359 | 269 | 2 | 32 | 243 | 87 |
| `maps/complex_map_engine_3d.gd` | 4 230 | 209 | 16 | 20 | 144 | 4 (+35 sous-nœuds 3D) |
| `maps/editor/map_editor_construction.gd` | 2 679 | 104 | 0 | 9 | 1 | 0 |
| `maps/map_layers/map_ground_3d.gd` | 2 303 | 132 | 0 | 5 | 45 | 0 |
| `maps/map_layers/map_water_3d.gd` | 2 235 | 83 | 0 | 2 | 35 | 0 |
| `maps/editor/map_editor_parametres.gd` | 2 131 | 99 | 1 | 2 | 71 | 92 |
| `maps/editor/map_edit_document.gd` | 2 623 | 181 | 4 | 2 | 14 | 0 |
| `maps/map_layers/map_meshes_3d.gd` | 1 512 | 72 | 0 | 20 | 30 | 0 |
| `maps/editor/map_editor_world_panel.gd` | 1 487 | 70 | 1 | 1 | 50 | 55 |
| `maps/construction/procedural_city.gd` | 1 611 | 52 | 0 | 1 | 0 | 0 |
| `maps/terrain/terrain_carve_field.gd` | 1 364 | 65 | 0 | 0 | 12 | 0 |
| `maps/editor/map_editor_tool_options.gd` | 1 018 | 10 | 0 | 7 | 6 | 49 |
| `maps/editor/map_editor_inspector.gd` | 1 000 | 50 | 6 | 6 | 3 | 43 |
| `maps/editor/map_editor_overlay.gd` | 861 | 42 | 0 | 1 | 23 | 0 |
| `maps/simple/simple_map_editor.gd` | 956 | 56 | 3 | 4 | 43 | 23 |

Fonctions les plus longues (mesure bornée à la prochaine déclaration top-level) :

| Fonction | Fichier:ligne | Longueur |
|---|---|---:|
| `_rebuild_tool_options` | map_editor_tool_options.gd:204 | **806 l.** (fichier de 1 018 l.) |
| `_build_river_body` | map_water_3d.gd:899 | **435 l.** |
| `_ensure_dialogs` | map_editor_world_panel.gd:568 | **211 l.** |
| `_apply_render_quality` | complex_map_engine_3d.gd:1091 | 176 l. |
| `_build_viewport_tree` | complex_map_engine_3d.gd:357 | 173 l. |
| `_unhandled_key_input` | map_complex_editor.gd:3420 | 169 l. |
| `_build_action_bar` | map_complex_editor.gd:837 | 140 l. |
| `_refresh_ghost` | map_complex_editor.gd:4194 | 139 l. |
| `_build_procedural_visual` | map_meshes_3d.gd:511 | 136 l. |
| `_insert_window` | map_editor_construction.gd:1404 | 103 l. |
| `_make_terrain_mesh` | map_ground_3d.gd:1301 | 99 l. |
| `to_map_data` | map_edit_document.gd:362 | 96 l. |

Dette de forme à traiter avec le refactor : dans `map_complex_editor.gd` les `var` top-level sont **intercalés entre les fonctions** (ex. `_lake_radius` l. 272-273 suivi de 140 l. de variables l. 274-415 ; `_option_note` l. 1010 de `map_editor_tool_options.gd` suivi d'un en-tête de section orphelin l. 1012-1018). Cela fausse toute métrique naïve « taille de fonction » et complique les extractions automatiques.

## 2. Le contrat de test est le vrai cahier des charges

| Cible | Tests qui la touchent | Membres distincts atteints | Type de contrat |
|---|---:|---:|---|
| `map_complex_editor.gd` (via `scenes/map_editor/map_editor.tscn`) | **50** | **169** (153 privés + API + `%nodes`) | instanciation PackedScene, `load_map`, puis pilotage direct `editor._methode()` |
| `map_edit_document.gd` | **41** | **99** (1 privé) | API publique quasi complète (document pur) |
| `complex_map_engine_3d.gd` | **32** | **130** (49 internes) | `configure()` + getters + sondes internes (`_camera`, `_orbit_*`, `_table_*`) |
| `map_layers/map_*.gd` | 26 | API `configure()`/getters | 5 calques + rendu |
| `terrain_carve_field.gd` | 5 | API de champ | math + rendu clusters |
| `simple/simple_map_editor.gd` | 2 | API + `doc` | éditeur 2D |

Exemples de verrous (citations) : `editor._layout_force = true`, `editor._apply_responsive_layout()` (map_editor_test.gd:428-429) ; `editor._palette_wrappers.get("right")` (map_editor_test.gd:445) ; `editor._construction._generate_scene(...)` (city_scene_test.gd:60, cite_demo_catalog_test.gd:137, scene_rocks_test.gd:30, map_scene_apply_test.gd:28) ; `editor._edit_ops._apply_bridge_endpoint_drag(...)` (procedural_bridge_mesh_test.gd:92) ; `editor._carve_river_bed(path)` (river_user_trace_test.gd:46) ; `editor._finish_water_lake(...)` (water_bodies_test.gd:180).

**Conséquence opérationnelle** : tout plan d'extraction doit être « **wrappers conservés** » (patron [REFACTOR_EDITEUR.md:31-43](../REFACTOR_EDITEUR.md)). Recommandation complémentaire à faible coût : ajouter un **test de contrat** (nouveau fichier, hors périmètre de cet audit) qui instancie `map_editor.tscn`, `MapEditDocument` et `ComplexMapEngine3D` puis vérifie l'existence des membres listés dans une constante — il transforme les régressions de renommage en échec explicite, avant chaque vague.

## 3. Plans d'extraction par god file

### 3.1 `map_complex_editor.gd` — 5 359 l. → cible **800-1 000 l.**

| Bloc | Lignes | Responsabilité |
|---|---:|---|
| En-tête + 32 preloads | 1-54 | dépend de 32 scripts (UI, document, moteur, construction) |
| État éditeur + symétrie sculpture | 56-119 | 31 vars, `_sym_points` 108 |
| **Outil Eau** (rivière/lac) | 120-415 | `_finish_water_river` 141, `_carve_river_bed` 176, `_write_river_trace` 211, `_finish_water_lake` 225, `_lake_radius` 272 + 123 vars intercalées (274-415) |
| État interaction + dictionnaire de nœuds | 416-494 | 71 vars |
| Cycle de vie + API publique | 495-590 | `_ready` 495, `load_map` 552, `apply_to_map_data` 573, `save_now` 583 |
| Bind UI + palette droite flottante | 596-716 | `_bind_ui` 596, `_float_right_palette` 621 |
| Grille outils v1 + aimantation | 719-766 | `_populate_tools` 719, `_populate_snap` 756 |
| Moteur + overlay + overlay de génération | 770-836 | `_create_engine` 770 |
| Barre d'action | 837-975 | `_build_action_bar` (140 l.) |
| Chrome immersif + docks | 978-1159 | `_build_immersive_chrome` 978, `_on_dock_tool_pressed` 1100, `_bind_docks` 1127 |
| Onglets + layout responsive | 1160-1320 | `_apply_responsive_layout` 1194, `_adapt_tool_chrome` 1264 |
| Bind réglages/biblio | 1320-1430 | `_bind_settings_tab` 1320, `_bind_library_tab` 1378 |
| Palettes flottantes | 1430-1600 | `_float_palette` 1478, `_move_library_to_bottom` 1512, `_open_history_panel` 1592 |
| Dialogues + patch Blender + focus chemins | 1601-1804 | `_build_dialogs` 1601, `_generate_blender_path_patch` 1708, `_set_path_focus` 1776 |
| Palette v2 + flyout + récents + `_set_tool` | 1805-2036 | `_rebuild_palette_v2` 1805, `_open_flyout` 1915, `_set_tool` 1958 |
| Wrappers édition | 2037-2083 | 11 délégués à `_edit_ops` |
| Pose / placement / pipeline de dessin | 2084-2558 | `_finish_draw` 2084, `_place_pose_element` 2148, `_create_token` 2183, `_close_polygon` 2466, `_erase_at` 2524 |
| Outils terrain/eau | 2559-2997 | `_paint_terrain` 2559, `_paint_relief` 2579, `_paint_carve` 2605, `_sculpt_op_at` 2701, `_paint_fog` 2951, `_paint_water` 2967 |
| Templates | 2998-3019 / 3344-3419 | `_refresh_templates` 3344, `_place_template` 3396 |
| Bibliothèque assets + objets 3D | 3020-3343 | `_refresh_asset_library` 3020, `_refresh_object3d_library` 3172, vignettes 3253 |
| Raccourcis clavier | 3420-3623 | `_unhandled_key_input` 3420 (170 l.), `_apply_shortcut_tool` 3590 |
| Paramètres / affichage / thème | 3624-3769 | `_create_parametres_menu` 3624, `_retheme_subtree` 3742 |
| Commandes | 3770-4087 | delete/focus/undo/redo/test/validate/export/help/esc/monde |
| Synchro vue + fantôme + panneaux | 4088-4507 | `_sync_engine` 4088, `_refresh_overlay` 4162, `_refresh_ghost` 4194 (140 l.), `_refresh_panels` 4395 |
| Réglages : binding + ~20 handlers | 4508-5107 | `_sync_settings_ui` 4508 + `_on_*` 4550-5107 |
| Statut + factories + accesseurs | 5108-5359 | `_rebuild_palettes` 5108, `_rebuild_tool_options` 5153, `_section` 5220, `_spin` 5251 |

Modules proposés (tous conservent les wrappers éponymes dans l'éditeur) :

| Module | Responsabilité | Source | Est. lignes |
|---|---|---|---:|
| `editor/tools/map_editor_water_tools.gd` | rivière/lac/lit/trace QA | 120-415 | ~300 |
| `editor/ui/editor_chrome_builder.gd` | barre d'action, chrome immersif, docks, dialogues | 596-716, 837-1108, 1264-1600, 1601-1804 | ~850 |
| `editor/ui/editor_layout.gd` | responsive, onglets, resize, redock | 1160-1320 | ~240 |
| `editor/ui/editor_palette_controller.gd` | grille v1 (mode chemins), palette v2, flyout, récents, `_set_tool` | 719-766, 1805-2036 | ~300 |
| `editor/ui/editor_settings_binder.gd` | `_sync_settings_ui` + handlers + quick start/lumières/fond/effets/badges | 4508-5107 | ~600 |
| `editor/tools/map_editor_terrain_tools.gd` | sol, relief, carve, sculpture, spline, fleurs, fog, eau | 2559-2997 | ~430 |
| `editor/ui/editor_asset_library_ui.gd` | biblio décors, objets 3D, templates | 3020-3419 | ~380 |
| `editor/editor_shortcuts.gd` | touches, toggle UI, plein écran | 3420-3623 | ~210 |
| `editor/editor_commands.gd` | undo/redo, delete, focus, test, validation, export, aide/esc, navigation monde | 3770-4087 | ~300 |
| `editor/editor_view_sync.gd` | `_sync_engine`, overlay/vision/fantôme/fil d'Ariane/panneaux/handlers doc | 4088-4507 | ~420 |
| `editor/editor_appearance.gd` | menu Paramètres, préférences d'affichage, FPS, thème | 3624-3769 | ~140 |
| `editor/editor_placement_ops.gd` | `_finish_draw`, pose, polygone, gomme, liens, pickers | 2084-2558 | ~450 |
| `editor/ui/editor_widgets.gd` | factories `_section/_spin/_line_row/…` + accesseurs typés | 5163-5359 | ~190 |

**Seams à conserver impérativement** : signaux `layout_changed` / `open_map_requested` (13-14) ; API `load_map` 552, `apply_to_map_data` 573, `get_play_defaults` 578, `save_now` 583, `set_editable` 540 ; membres atteints par les tests (§2), en particulier `doc`, `_engine`, `_overlay`, `_construction`, `_edit_ops`, `_tool_opts`, `_palette_v2`, `_palette_wrappers`, `_options_bar`, `_library_dock`, `_world_panel`, `_parametres`, `_esc_menu`, `_validate_*`, `_water_*`, `_scatter_*`, `_scene_*`, `_mesh_*`, `_house_*`, `_relief_*` ; connexions `doc.changed/selection_changed/history_changed/dirty_changed` (505-508) et `engine.editor_pointer_*` (775-780), qui doivent rester câblées dans l'éditeur, pas dans les modules.

**Risque** : **très élevé** (50 tests, 169 membres, `%nodes`). **Effort** : XL. Ne jamais déplacer plus d'un bloc à la fois ; un bloc = un run `scripts/run_tests.ps1 -Filter map`.

### 3.2 `complex_map_engine_3d.gd` — 4 230 l. → cible **500-700 l.**

| Bloc | Lignes | Responsabilité |
|---|---:|---|
| En-tête : 16 signaux, 20 preloads, constantes brume | 1-305 | contrats session + éditeur (6-28) |
| Cycle de vie, pointeur de déplacement | 306-356 | `_ready` 306 |
| Arbre SubViewport / WorldEnvironment | 357-530 | `_build_viewport_tree` 357 (173 l.) |
| `configure` + refresh ciblé | 531-670 | `configure` 531 (94 l.), `refresh_meshes_only` 625, `update_bridge` 640 |
| Session & politique | 670-730 | `set_session_tool` 670, `set_move_policy` 675, `set_view_inset` 701 |
| Ciel / qualité / ombres / overrides | 731-1267 | `_ensure_sky` 731, `set_quality_preset` 855, `_update_shadow_budget` 887, `_apply_shadow_quality` 1003, `_apply_water_reflections` 1060, `_apply_render_quality` 1091 (176 l.) |
| Chargement des couches | 1268-1611 | `_load_ground` 1268 … `_load_ambient_fx` 1554 |
| Terrain | 1612-1830 | `_sync_terrain_from_map` 1612, `terrain_height_at` 1698, `terrain_normal_at` 1727, `refresh_terrain` 1753 |
| Caméra | 1830-1957 / 2531-2968 / 3661-3766 | `_apply_camera_perspective` 1923, `_fit_to_view` 2732, `_apply_zoom` 2788, `_begin_view_pan` 3661 |
| Lumière, brume, atmosphère | 1957-2345 | `_apply_lighting` 1957, `_apply_environment_fog` 2059, `_apply_atmosphere` 2238 |
| Orchestration des couches | 2346-2439 | `_rebuild_layers` 2346 (94 l.) |
| Tokens & overlay | 2441-2526 / 3214-3363 | `_create_token_node` 2441, `_rebuild_token_overlay` 3214 |
| Projection / picking / grille | 2854-2957 / 4118-4192 | `_raycast_ground` 2854, `grid_to_screen` 2928, `_handle_map_click` 4118 |
| Entrée souris | 3374-3660 | `_gui_input` 3374, `_editor_gui_input` 3555 |
| Vue table + dés | 3767-4117 | `set_table_view` 3767, `roll_table_dice_at` 3845, `_apply_table_camera` 4069 |
| API zoom / effets | 4193-4230 | `trigger_effect` 4193, `zoom_in/out/reset` 4212-4218 |

Modules proposés : `engine/map_viewport_builder.gd` (~300, 357-530 + construction des sous-nœuds), `engine/map_camera.gd` (~700, caméra/fit/zoom/pan/orbite), `engine/map_projection.gd` (~180, raycasts + conversions grille↔écran), `engine/map_render_quality.gd` (~430, presets/ombres/réflexions/overrides), `engine/map_lighting_atmosphere.gd` (~600, lumière + 3 brumes + ciel + vignette), `engine/map_terrain_sync.gd` (~200), `engine/map_layer_orchestrator.gd` (~450, `_load_*` + `_rebuild_layers`), `engine/map_tokens_view.gd` (~450, nœuds de token, overlay, figurines, picking), `engine/map_input_router.gd` (~500, souris/pan/click), `engine/map_table_mode.gd` (~360, table/fauteuils/dés), et une façade `complex_map_engine_3d.gd` (~600) qui garde `configure`, les 16 signaux et tous les getters/setters publics.

**Seams à conserver** : les 16 signaux (6-28) — y compris `editor_pointer_pressed/moved/released` et `view_changed` consommés par l'éditeur, et `token_moved`/`map_clicked`/`fog_*`/`area_*`/`table_dice_result` consommés par `map_stage.gd:52-87` ; l'API `configure` (531), `set_session_tool` 670, `set_move_policy` 675, `set_view_inset` 701, `get_view_state` 2293, `set_editor_mode` 3075, `refresh_terrain` 1753, `terrain_height_at` 1698, `grid_to_screen` 2928, `screen_to_grid_pos` 2941, `request_fit_to_view` 651, `refresh_meshes_only` 625, `trigger_effect` 4193.

**Risque** : **élevé** — 32 tests touchent ~70 internes (`_camera`, `_ground`, `_meshes_layer`, `_orbit_*`, `_table_*`, `_dice`, `_token_nodes`…). **Effort** : XL, en 3 sous-vagues (rendu/atmosphère → caméra/projection → tokens/table/entrée).

### 3.3 `map_edit_document.gd` — 2 623 l. → cible **600-800 l.** (façade + wrappers)

| Bloc | Lignes | Responsabilité | Module proposé | Est. |
|---|---:|---|---|---:|
| Types de delta, kinds, schéma | 23-115 | constantes, état | (reste dans le document) | — |
| Chargement / sérialisation / normalisation | 116-458 | `load_map` 116, `_deserialize` 178, `to_map_data` 362 | `document/element_store.gd` | ~450 |
| Requêtes & hit-test | 459-606 | `hit_element_at` 536, `hit_stack_at` 546, `element_contains` 589 | idem | — |
| Transactions, undo/redo, deltas, shadow copy | 607-864 | `begin_transaction` 607, `_push_delta` 626, `undo` 709, `_apply_delta` 739 | `document/history.gd` | ~300 |
| CRUD éléments + édition live | 865-1070 | `add_element` 880, `remove_element` 898, `modify_element` 961, `commit_live_edit` 1012, `move_elements_by` 1047 | `document/element_store.gd` | — |
| Terrain (hauteurs, peinture, spline, flatten, resize) | 1095-1500 | `paint_terrain_brush` 1213, `carve_path` 1263, `paint_terrain_spline` 1384, `resize_grid` 1958 | `document/terrain_model.gd` | ~600 |
| Creusements + 20 brosses de sculpture | 1503-1749 | `add_carve` 1519, `sculpt_stamp` 1559 … `sculpt_cloth` 1733, `_push_sculpt_delta` 1739 | `document/sculpt_ops.gd` | ~300 |
| Bassins d'eau | 1751-1811 | `add_water_body` 1766, `update_water_body` 1779 | `document/water_model.gd` | ~100 |
| Matières de sol, seau, resize | 1829-1998 | `paint_terrain_material_brush` 1901, `bucket_fill` 1931 | `document/terrain_model.gd` | — |
| Brouillard + révélation lumière | 2000-2118 | `reveal_fog` 2015, `rebuild_light_reveal_from_lights` 2088 | `document/fog_light.gd` | ~150 |
| Liens | 2120-2199 | `link_elements` 2120, `_unlink_all` 2158 | `document/links.gd` | ~110 |
| Sélection / presse-papiers / calques / ordre / alignement | 2202-2612 | `set_selection` 2211, `paste` 2338, `_reorder_selection` 2414, `add_layer` 2490, `align_selection` 2565 | `document/selection_clipboard.gd` + `document/layer_model.gd` | ~450+200 |

**Seams à conserver** : les 4 signaux (12-15) ; **les 99 méthodes atteintes par les tests** restent disponibles sur `MapEditDocument` comme wrappers d'une ligne (ex. `paint_terrain_brush`, `sculpt_stamp`, `to_map_data`, `undo/redo`). Aucune connexion de signal à déplacer (c'est l'éditeur qui connecte, lignes 505-508).

**Risque** : **faible** (pur, 41 tests, API publique). **Effort** : M — la meilleure première vague : elle prouve le patron « module + wrappers » sur un fichier non-UI.

### 3.4 `map_editor_construction.gd` — 2 679 l. → cible **~150 l.** (façade `setup(editor)`)

| Bloc | Lignes | Responsabilité | Module proposé | Est. |
|---|---:|---|---|---:|
| Constantes d'assets/styles | 25-84 | ROOF/FLOOR/FENCE/ORGANIC/FURNITURE, dims de murs | (reste) | — |
| Murs : chaînes, coins, jonctions, étirement, lissage | 85-433 | `_create_mesh_wall_chain` 369, `_add_wall_junction_corner` 259, `_apply_wall_handle_resize` 488 | `construction/wall_builder.gd` | ~420 |
| Pièce / maison rapide | 439-570 | `_create_mesh_room` 439, `_create_mesh_house` 570 | `construction/room_house_builder.gd` | ~180 |
| Chemin / clôture / procéduraux & organique | 623-950 | `_create_path` 623, `_create_mesh_fence` 649, `_build_organic_chain` 711, `_build_procedural_*` | `construction/path_fence_builder.gd` | ~300 |
| Dispersion de végétation au pinceau | 998-1166 | `_scatter_stroke_points` 1152, `_place_scatter_item` 1113 | `construction/scatter_brush.gd` | ~180 |
| Escaliers, intérieurs liés, mobilier | 1167-1370 | `_insert_stairs` 1167, `_create_interior_at` 1214, `_insert_furniture` 1371 | `construction/interior_builder.gd` | ~230 |
| Portes / fenêtres (y c. procédurales) | 1404-1805 | `_insert_window` 1404 (103 l.), `_insert_door` 1577, `_nearest_procedural_wall` 1654 | `construction/opening_builder.gd` | ~420 |
| Toit / dallage / décor | 1806-1937 | `_create_mesh_roof` 1806, `_create_floor` 1877, `_create_prop` 1906 | `construction/roof_floor_prop.gd` | ~180 |
| Scène procédurale (WFC, rochers, plan de cité) | 1938-2160 | `_generate_scene` 2002, `_apply_scene_plan` 2019, `_apply_city_plan` 2065 | `construction/scene_planner.gd` | ~250 |
| Décor contextuel | 2161-2393 | `_decorate_context` 2161, `_decorate_wall_context` 2173, `_decorate_path_context` 2257 | `construction/context_decor.gd` | ~250 |
| Placement de mesh, empilement, aimantation, AABB | 2421-2679 | `_create_mesh` 2421, `_snap_module_placement` 2506, `_mesh_actual_dimensions` 2597 | `construction/mesh_placement.gd` | ~270 |

**Seams** : `setup(editor)` 83 ; **tous les wrappers** utilisés par les tests restent dans `map_complex_editor.gd` : `_create_mesh_room` 2377, `_create_mesh_house` 2381, `_create_mesh_roof` 2385, `_insert_door` 2417, `_insert_window` 2413, `_insert_stairs` 2401, `_create_path` 2385, `_create_mesh_fence` 2389, `_build_organic_chain` 2393, `_scatter_stroke_points` 2397, `_create_mesh` 2429, `_wall_chain_plan` 2365, `_wall_chain_corner_specs` 2369, `_snap_wall_endpoint` 2361, `_mesh_actual_dimensions` 2433 (numéros de ligne dans `map_complex_editor.gd`, où vivent les délégations). **Risque** : faible-moyen (les tests passent par ces wrappers ; seuls 5 tests appellent `_construction.` directement, voir §2). **Effort** : M.

### 3.5 `map_editor_tool_options.gd` — 1 018 l. → cible **~120 l.** (dispatcher)

Une seule fonction de **806 l.** (`_rebuild_tool_options`, 204-1009) contenant une chaîne de 38 branches d'outil (`if _ed._tool == …` l. 215 puis 37 `elif`, dernière l. 1002) et **49 instanciations de nœuds**. Découpage proposé, par famille (le dispatcher garde `_rebuild_tool_options` et appelle le builder de la famille) :

| Module | Lignes sources | Familles | Est. |
|---|---|---|---:|
| `editor/options/tools_options_objects.gd` | 215-236, 527-592, 958-1002 | Token, Marker, Effect, Zone*, Prop, Mesh, Area, Select/Erase/Template, Light | ~200 |
| `editor/options/tools_options_build.gd` | 236-423 | Murs, pièce, toit, dallage, maison, fenêtre, mobilier, escalier, intérieur, clôture, chemin, cloisons/clôtures/chemins procéduraux | ~230 |
| `editor/options/tools_options_nature.gd` | 424-526 | Organique, dispersion, zones fleuries, décor contextuel, génération de scène | ~120 |
| `editor/options/tools_options_terrain.gd` | 593-710, 733-955 | Peinture, bridge, eau, relief, spline, matière de sol, brouillard | ~250 |
| `editor/options/tools_options_catalog.gd` | 675-732 | Toits procéduraux/poly | ~60 |
| `editor/options/tool_options_fields.gd` | 49-204 | factories `_field_hbox/_slider_field/_sep/_spin_field/_make_scrubbable/_line_field` | ~150 |

**Seams** : `setup(editor)` 42 et la méthode `_rebuild_tool_options` (appelée par l'éditeur l. 5153 et par `map_terrain_materials_test` via `editor._rebuild_tool_options`) ; les variables de mémorisation `_saved_per_tool`, `_options_tool_id`, `_spin_field_index`, `_relief_options_volumetric` (32-40) doivent rester dans le module (état interne). **Risque** : faible côté tests, **mais couplage dynamique maximal du dépôt** (508 `_ed.` / 109 membres). **Effort** : M. Recommandation : extraire d'abord les *factories* (49-204), puis les familles une par une ; ne pas changer une seule ligne de logique.

### 3.6 `map_layers/map_ground_3d.gd` — 2 303 l. → cible **~400 l.**

| Bloc | Lignes | Responsabilité | Module proposé | Est. |
|---|---:|---|---|---:|
| Constantes/vars | 1-261 | relief, splat, cliff, slab | (reste) | — |
| Instances + `configure` | 262-336 | `_ensure_*_instance`, `configure` 294 | (façade) | — |
| Hauteurs / creusements / sculpture / preview | 336-525 | `set_terrain_heights` 336, `set_terrain_carves` 400, `set_terrain_sculpt` 429 | `layers/terrain_field_sync.gd` | ~150 |
| Matières, splat, mode sol | 525-618 | `set_terrain_materials` 525, `set_ground_mode` 576 | `layers/ground_splat_material.gd` | ~350 |
| `_apply_config` | 618-713 | config composite du sol | (facade) | — |
| Nuit / light mask / matériau jour | 713-800, 1172-1240 | `update_light_mask` 713, `_build_light_mask` 1195 | `layers/ground_night_mask.gd` | ~150 |
| Setters de finition (cliff, AO, neige, relief auto, occlusion) | 800-930 | 12 setters + `_rebuild_object_occlusion` 874 | `layers/ground_finitions.gd` | ~180 |
| Matériau terrain + textures splat | 930-1170 | `_apply_terrain_material` 930 (98 l.), `_update_splat_texture` 1109 | `layers/ground_splat_material.gd` | — |
| Maillage heightfield (sommets, couleurs, AO cavité, variation) | 1269-1600 | `_make_ground_quad` 1269, `_make_terrain_mesh` 1301 (99 l.), `_compute_cavity_ao` 1456 | `layers/terrain_mesh_builder.gd` | ~420 |
| Clusters Marching Cubes des creusements | 1592-1679 | `_carve_cut_mask` 1592, `_rebuild_dirty_carve_meshes` 1623 | `layers/carve_clusters.gd` | ~200 |
| Jupe de falaise | 1696-1784, 1872-2093 | `_make_cliff_mesh` 1872, `_append_cliff_side` 1905, `_append_cliff_lip` 1973 | `layers/cliff_skirt_builder.gd` | ~380 |
| Dalle / strates | 1784-1872, 2093-2302 | `_make_slab_mesh` 2140, `_append_slab_side` 2209 | `layers/slab_builder.gd` | ~300 |

**Seams** : `configure(...)` 294, `get_cell_height` 1579, `get_terrain_heights` 1583, `get_terrain_carves` 492, `get_carve_field` 500, `get_terrain_materials` 555, `get_splat_texture` 559, `is_terrain3d` 591, `is_relief_active` 597, `get_ground_mode` 588, `get_map_extent` 2302, `update_light_mask` 713 (appelés par le moteur et 11 tests). **Risque** : moyen (11 tests indirects, rendu) ; **effort** M.

### 3.7 `map_layers/map_water_3d.gd` — 2 235 l. → cible **~350 l.**

| Bloc | Lignes | Responsabilité | Module proposé | Est. |
|---|---:|---|---|---:|
| Constantes/vars, corps multiples | 1-134 | bassins, brume, cascades | (reste) | — |
| Cycle + `configure` + niveaux | 135-359 | `configure` 153, `set_water_level` 225, `_rebuild` 359 | (façade) | — |
| Surfaces planes / polygones + triangulation | 420-530, 1934-2044 | `_build_plane_mesh` 420, `_build_polygon_water_mesh` 1934, `_triangulate_polygon` 1964 | `water/water_surface_builder.gd` | ~380 |
| **Rivière** (une seule fonction de 435 l.) | 899-1334 | `_build_river_body` 899 + annexes (`_subdivide_curvature` 1362, `_path_side` 1411, `_visibility_fades` 1465) | `water/river_surface_builder.gd` | ~600 |
| Cascades + brume | 1532-1604 | `_make_fall_material` 1532, `_append_mist_quad` 1574 | `water/water_falls.gd` | ~140 |
| Matériaux eau/fond/brume | 482-530, 675-690, 1777-1933 | `_build_material` 482, `_make_body_material` 1777 (156 l.) | `water/water_materials.gd` | ~300 |
| Texture de profondeur | 457-482, 1679-1776 | `_build_depth_texture` 457, `_make_river_depth` 1704 | `water/water_depth_texture.gd` | ~200 |
| Emprises / polygones d'eau | 1605-1678 | `_lowest_point` 1605, `_make_poly_footprint` 1617, `_make_river_footprint` 1642 | `water/water_footprints.gd` | ~120 |
| Rives + décor (lentilles, nénuphars) | 52-62, 756-835, 2045-2204 | `_build_shore_texture` 756, `_rebuild_decor` 2075, `_set_multimesh` 2145 | `water/water_shore_decor.gd` | ~300 |

**Seams** : `configure(...)` 153, `clear` 204, `set_water_level` 225, `set_terrain_heights/carves` 231/239, `set_water_bodies` 246, `set_night_mode` 253, `get_water_level` 284, `is_active` 288, `get_surface_y` 292, `get_depth_texture` 348, `get_water_material` 355, `get_body_count` 557, `set_mist_enabled` 618, `get_mist_count` 630, `get_fall_count` 642 (moteur + `map_water_test`, `water_bodies_test`, `water_quality_shot_test`, `cs2_finitions_test`). **Risque** : faible (API stable, couche isolée). **Effort** : M.

### 3.8 `map_layers/map_meshes_3d.gd` — 1 512 l. → cible **~250 l.**

`configure` 163 (55 l.), pose/terrain `_reseat_nodes` 320 / `_terrain_height_at` 363 / `_basis_with_up` 439, construction `_build_mesh` 451 (52 l.), visuel procédural `_build_procedural_visual` 511 (136 l.) + `_conform_procedural_mesh` 697 (55 l.), ponts 797-895, chemin texturé 895-1028, occlusion/transparence 648-697 + 1059-1080, ombres de contact 1197-1270, matériaux 1332-1442, position live 1443-1509. Modules : `layers/mesh_seating.gd` (~200), `layers/procedural_visual_factory.gd` (~350), `layers/mesh_bridge.gd` (~180), `layers/mesh_path_strip.gd` (~150), `layers/mesh_materials.gd` (~200), `layers/mesh_contact_shadow.gd` (~120). **Seams** : `configure` 163, `update_shadow_budget` 219, `set_terrain_*` 293/305/313, `set_mesh_position` 1443, `set_mesh_fields` 1467, `has_mesh` 1505, `update_bridge` 817, `bridge_height_at` 826, `raycast_bridges` 838 (moteur + `map_meshes_3d_test`, `map_terrain_test`, `object_grounding_test`). **Risque** : moyen ; effort M.

### 3.9 `terrain/terrain_carve_field.gd` — 1 364 l. → cible **~450 l.**

Champ de terrain pur (`RefCounted`) : normalisation/sérialisation des primitives (101-175), sculpture `G` (233-559), 20 brosses (247-807), grandeurs dérivées (831-1014), SDF + échantillonnage (1044-1163), surfaces/raycast (1165-1363).
Modules : `terrain/carve_primitives.gd` (~250 : normalize/to_json/parse_prim/sdf/smin/smax/sample), `terrain/sculpt_brushes.gd` (~450 : brosses + blur/quantize/warp/blend), `terrain/terrain_sampler.gd` (~150 : `height_at`, `vertex_height`, `cell_height`, `cell_bilinear`, `top_surface_at`, `normal_at`, `raycast`), `terrain/sculpt_storage.gd` (~120 : `get_sculpt`/`set_sculpt`/regions/chunks). Façade conservée ~450 l.
**Seams** : `normalize_carve(s)` 101/135, `to_json_carve(s)` 145/153, `bounds_of` 175, `size` 1014, `sample` 1097, `height_at` 1165, `top_surface_at` 1231, `normal_at` 1300, `raycast` 1326, `sculpt_stamp` 317, `get_sculpt` 851 — consommés par `map_edit_document.gd` (via `_sculpt_support`), `map_ground_3d.gd`, `map_water_3d.gd`, `map_meshes_3d.gd`, `map_props_3d.gd`, `map_token_3d.gd`, et 5 tests. **Risque** : moyen (exactitude bit-à-bit attendue : `terrain_carve_test`, `terrain_sculpt_test`, `carve_normals_test`). **Effort** : M — **cible n°2 recommandée**, car elle supprime la duplication de sampling (§4).

### 3.10 Deuxième rideau (à traiter après les 8 cibles)

- `map_editor_parametres.gd` (2 131 l., 92 nœuds construits) : panneau Paramètres applicatif (F10). Découper par **page** : `parametres_pages_graphismes.gd` (583-692), `..._affichage.gd` (692-724), `..._touches.gd` (724-766), `..._interface.gd` (766-842), `..._systeme.gd` (880-978), `parametres_preview.gd` (978-1214), `parametres_resolution.gd` (1341-1508), `parametres_factories.gd` (1790-2074). Seams : `setup(host)` 172, `open` 204, `close` 220, `is_open` 197, `current_page` 200, signal `closed` 27. Risque faible (2 tests), mais **sort du périmètre « éditeur de cartes »** : à planifier séparément.
- `map_editor_world_panel.gd` (1 487 l.) : `_ensure_dialogs` 568 (211 l.) → `world/world_dialogs.gd` ; dessin canvas 1097-1355 → `world/world_canvas.gd` ; CRUD monde 159-467 → façade. Seams : signal `open_map_requested` 10, `refresh` 159, `set_editor_root` 480, `create_zone` 406, `auto_link` 439, `validate_world` 468, `test_world` 543, `show_status` 560.
- `map_editor_inspector.gd` (1 000 l.) : `_build_kind_fields` 156 (177 l., 13 branches par type) → un fichier par famille ; seams : signaux 17-22, `set_document` 32, `rebuild` 36.
- `map_complex_editor.gd` doit ensuite devenir un **assemblage** (état + wrappers + câblage de signaux) et non un lieu d'implémentation : c'est la condition pour qu'il ne regrossisse pas (problème n°1).

### 3.11 `construction/procedural_city.gd` — 1 611 l. : **ne pas refactorer**

Ce fichier est déjà un module pur cohérent (générateur déterministe + convertisseurs `build_*_elements`, 1318-1611), sans UI, sans `_ed`, appelé à la fois par l'éditeur (`map_editor_construction.gd:2066-2145`) et par la carte démo (`map_data.gd:29`). C'est le contre-exemple à suivre : un fichier long mais **à responsabilité unique**. Ne le découper que si son API grossit.

## 4. Duplications et code mort

### 4.1 Code mort confirmé (0 référence externe, recherche `.gd/.tscn/.tres/.cfg` + `tools/`)

| Fichier | Lignes | Statut |
|---|---:|---|
| `maps/editor/editor_input_handler.gd` | 194 | mort — déjà signalé [REFACTOR_EDITEUR.md:70-71](../REFACTOR_EDITEUR.md), toujours présent |
| `maps/editor/editor_tool_handlers.gd` | 161 | mort |
| `maps/editor/editor_view_controller.gd` | 96 | mort |
| `maps/editor/editor_save_controller.gd` | 96 | mort |
| `maps/complex_map_engine.gd` | 573 | mort (legacy 2D, remplacé par `complex_map_engine_3d.gd`) |
| `maps/map_layers/map_grid_layer.gd` | 27 | mort (remplacé par `map_grid_3d.gd`) |
| `maps/map_layers/map_fog_layer.gd` | 34 | mort (remplacé par `map_fog_3d.gd`) |
| `maps/map_layers/map_elevation_layer.gd` | 57 | mort (remplacé par `map_elevations_3d.gd`) |
| `maps/map_layers/map_lighting_layer.gd` | 101 | mort (remplacé par `map_lights_3d.gd`) |
| `maps/simple/simple_tileset.gd` | 417 | mort (déjà repéré par l'inventaire) |

**Total ≈ 1 756 l. supprimables** sans effet runtime (à vérifier par `git grep` avant suppression, chargement dynamique toujours possible). Note : ces fichiers sont aussi une **source de confusion d'architecture** — `ARCHITECTURE.md:21-24` les décrit encore comme des composants actifs de l'éditeur.

### 4.2 Doublons v1/v2 encore vivants

- **Grille d'outils v1** : construite (map_complex_editor.gd:653 `_populate_tools(%ToolHost)`) puis **masquée** (660 `%ToolHost.visible = false`) ; réutilisée seulement en mode chemins (1785). Le corps de `_populate_tools` (719-754) est un quasi-doublon de `_rebuild_palette_v2` (1805-1823).
- **Palette d'environnement** : instanciée puis masquée (674-680, commentaire « doublon de l'onglet Carte ») et pourtant encore synchronisée (4546-4547 `_environ_palette.sync_from_host()`), alors que l'onglet Carte est la source d'UI. Candidat : suppression (113 l.) après vérification qu'aucun réglage n'y est unique.
- **Éditeur 2D vs 3D** : `simple_map_editor.gd` (956 l.) partage `MapEditDocument` et `MapEditorTools` (14-16) mais réimplémente le même squelette : `_bind_ui` (simple:108 / editor:596), `_populate_tools` (simple:202 / editor:719), `_rebuild_tool_options` (simple:245 / editor:5153), `_unhandled_input` (simple:900 / editor:3420). ~400-500 l. factorisables en `simple/editor_shell_shared.gd`.
- **Barre d'options** : la même logique de reconstruction existe dans 3 fichiers (voir §4.5).
- **Gabarits UI** : `_section/_hbox/_spin/_line_row/_color_row` (map_complex_editor.gd:5220-5314) dupliqués dans `map_editor_inspector.gd` (`_row`, `_spin`), `map_editor_parametres.gd` (`_box/_row/_label`), `map_editor_environ_palette.gd` → un `editor/ui/ui_factories.gd` commun est la cible.

### 4.3 Helpers strictement identiques (copier-coller, pas « même formule »)

| Helper | Copies | Lignes |
|---|---|---|
| `_terrain_height_at(gx, gy)` (bilinéaire + creusements) | 3 | map_meshes_3d.gd:363, map_props_3d.gd:142, map_token_3d.gd:136 |
| `_collect_mesh_aabbs(node, xform, out)` | 3 | map_editor_construction.gd:2672, map_editor_inspector.gd:598, map_meshes_3d.gd:1281 |
| `_mesh_actual_dimensions(elem, natural)` | 3 | map_complex_editor.gd:2433, map_editor_construction.gd:2597, map_editor_inspector.gd:607 |
| `_arrays_equal` / `_carves_equal` | 3 + 3 | map_ground_3d.gd:1161/503, map_vegetation_3d.gd:554/569, map_water_3d.gd:2205/2218 |
| `_terrain_base_y` (3 variantes incompatibles) | 3 | map_meshes_3d.gd:413, map_props_3d.gd:166, map_token_3d.gd:160 |

Correction recommandée : un seul `terrain/terrain_sampler.gd` fourni aux calques par le moteur (le moteur possède déjà `_terrain_heights/_terrain_carves/_terrain_sculpt` et `TerrainCarveField`), et les 3 calques consomment la même instance.

### 4.4 Terrain vs layers : 4 implémentations de la même convention

`MapGround3D._vertex_height` (1551) ≡ `TerrainCarveField.vertex_height` (1183, commentaire explicite « **même formule que** `MapGround3D._vertex_height` ») ; `TerrainCarveField.cell_bilinear` (1210, « **même formule que** `ComplexMapEngine3D.terrain_height_at` ») ; `ComplexMapEngine3D.terrain_height_at` (1698) ; `_terrain_height_at` ×3 calques (§4.3). La duplication est **assumée par commentaires** parce que le déterminisme de pose doit être conservé. Le refactor doit donc extraire **une** source de vérité avec un test de parité (mêmes valeurs qu'avant, au bit près) sur les cartes de `map_terrain_test.gd`, `map_terrain_materials_test.gd`, `terrain_carve_test.gd`, `object_grounding_test.gd`.

### 4.5 Raccourcis clavier : deux sources de vérité

Registre déclaratif dans `app_settings.gd:144-171` (id/label/groupe/key/ctrl/shift) **et** dispatch `match key.keycode` codé en dur dans `map_complex_editor.gd:3420-3589` ; `tool_flyout.gd` et `map_editor_parametres.gd:231/252` capturent aussi le clavier. Toute action ajoutée doit être écrite deux fois. Cible : un `editor/editor_shortcut_router.gd` qui lit `AppSettings` et appelle une table `action_id → Callable` (les wrappers d'actions restent dans l'éditeur).

### 4.6 Construction vs `procedural_city` : **pas** de duplication à corriger

`_apply_scene_plan` (map_editor_construction.gd:2019-2054) et `_apply_city_plan` (2065-2072) délèguent aux convertisseurs purs `ProceduralCity.build_*` (2066, 2108, 2117, 2132-2145) ; la carte démo passe par les mêmes (map_data.gd:29). Les deux pipelines de bâtiments (`_create_mesh_house` maison procédurale vs `build_building_elements` GLB de cité) sont **deux produits différents** (village stylisé vs cité en GLB) : à documenter, pas à fusionner.

## 5. Couplage `.tscn` et chemins de nœuds

- **`game/scenes/map_editor/map_editor.tscn`** : 245 l., 9 `ext_resource`, 25 nœuds `unique_name_in_owner`. L'éditeur y accède **exclusivement par `%Nom`** (25 noms distincts, 26 sites d'accès, ex. `_bind_ui` 596-616) : pas de chemins fragiles. Seules 2 exceptions en dur, à corriger : `palette.get_node("PaletteStack/TitleBar/CloseButton")` (map_complex_editor.gd:1557) et `_options_bar.get_node("PaletteStack/TitleBar/TitleLabel")` (5158) — chemins internes du composant `draggable_palette.gd`, donc à encapsuler dans ce composant.
- **Panneaux** : `panels/settings.tscn` (545 l., UI déclarative) et `panels/library.tscn` (145 l.) sont de vraies scènes ; `inspector.tscn` (9 l.), `world.tscn` (9 l.), `history.tscn` (50 l.), `outliner.tscn` (42 l.), `esc_menu.tscn` (124 l.) ne sont que des racines + script, le reste est construit en code. Le panneau Paramètres est donc la seule scène « lourde » du périmètre.
- **UI construite en code** : 87 instanciations de nœuds dans l'éditeur, 92 dans `map_editor_parametres.gd`, 49 dans `map_editor_tool_options.gd`, 55 dans `map_editor_world_panel.gd`. C'est la cause mécanique de la taille des fichiers ; le refactor doit **sortir ces builders du contrôleur** (§3), pas les convertir en `.tscn` (risque inutile).
- **Moteur** : 0 chemin de nœud en dur ; l'arbre `SubViewport`/`WorldEnvironment`/couches est construit en code (`_build_viewport_tree` 357-530), ce qui isole bien le rendu.
- **Éditeur 2D** : 10 accès `get_node("%…")` internes à `simple_editor.tscn` (simple_map_editor.gd:124-152) — même style, propres.
- **Hors périmètre mais à signaler** : `scenes/scenario_editor.tscn` (938 l.) est la plus grosse scène du dépôt et suit un autre modèle (UI en scène) ; ne pas l'inclure dans ce chantier.
- **Scripts de boot** : `scripts/debug/carte_25d_boot.gd` (580 l.) pilote l'éditeur via `load("res://scenes/map_editor/map_editor.tscn")` et quelques méthodes — il dépend donc des mêmes seams que les tests (à traiter comme un client de plus, non prioritaire).

## 6. Tests de protection existants

| God file | Tests à lancer avant/après | Ce qu'ils protègent |
|---|---|---|
| `map_edit_document.gd` | `map_editor_test` (794 l., 11 tests), `map_terrain_doc_test`, `terrain_sculpt_test` (`_test_doc_undo_serialize`), `map_terrain_materials_test` (`_test_document_materials`), `water_bodies_test`, `map_areas_test`, `map_props_test` | document, historique delta, sélection/presse-papiers, liens, calques, terrain/fog, templates, terrain sculpté undo+sérialisation |
| `map_editor_construction.gd` | `map_editor_snap_test` (540 l.), `map_organic_creation_test`, `map_house_floors_test`, `map_house_windows_test`, `city_scene_test`, `cite_demo_catalog_test`, `scene_rocks_test`, `map_scene_apply_test`, `map_stacking_test`, `procedural_wall_*_test` | murs/chaînes/coins, snap modules, maison/étages/fenêtres, organique, dispersion, application de plans de scène |
| `map_editor_tool_options.gd` | `map_terrain_materials_test` (`_test_editor_material_options`), `map_editor_test` (`_test_tools`) | présence et ordre des réglages par outil |
| `map_complex_editor.gd` | **50 tests** instanciant `map_editor.tscn` (dont `map_editor_test`, `map_editor_ui_v2_test`, `map_editor_v2_palette_test`, `map_editor_v2_tool_flyout_test`, `editor_drag_perf_test`, `map_editor_parametres_test`, `map_25d_editor_shot_test`, `map_mode_test`) | layout responsive, palettes, docks, raccourcis, raccordement des outils |
| `complex_map_engine_3d.gd` | **32 tests** (dont `map_camera_test`, `map_lighting_test`, `map_backdrop_test`, `map_ambient_fx_test`, `map_water_test`, `map_terrain_test`, `map_quality_cs2_test`, `table_view_test`, `zoom_to_cursor_test`, `pan_cursor_tracking_test`, `editor_views_test`) | configure, caméra/zoom/pan, qualité/ombres, atmosphère, table/dés, intégration des couches |
| `map_ground_3d.gd` | `map_terrain_test`, `map_terrain_materials_test`, `terrain_carve_test`, `terrain_sculpt_test`, `map_cliff_skirt_test`, `slab_quality_test`, `cs2_finitions_test`, `map_night_reveal_test` | maillage, splat, falaise, dalle, clusters MC, nuit |
| `map_water_3d.gd` | `map_water_test` (412 l.), `water_bodies_test`, `river_continuity_test`, `river_user_trace_test`, `cs2_finitions_test` | surface, profondeur, rivière, cascades/brume, décor |
| `map_meshes_3d.gd` | `map_meshes_3d_test` (328 l.), `map_terrain_test` (`_test_meshes_layer`), `object_grounding_test`, `map_occlusion_test`, `path_terrain_build_test` | pose terrain, ponts, chemin texturé, occlusion, ombres de contact |
| `terrain_carve_field.gd` | `terrain_carve_test`, `terrain_sculpt_test`, `carve_normals_test`, `carve_cut_detail_test`, `terrain_strata_test` | primitives SDF, top surface, raycast, clusters, 20 brosses |
| `map_editor_world_panel.gd` | `world_zones_test`, `world_editor_test`, `world_map_test`, `map_25d_editor_shot_test` | zones, liens, dessin du monde |
| `map_editor_parametres.gd` | `map_editor_parametres_test`, `map_editor_parametres_shot_test` | pages, sync, remap touches |

**Baseline de référence** : `docs/refactor/logs/godot_suite_20261117_1925.log` — les tests exécutés jusqu'ici (camera_navigation → map_editor_snap) sont PASS, mais le log est **tronqué** : la suite complète doit être rejouée avant la première extraction et servir de mètre-étalon. Attention : 4 tests non nommés `*_shot*` font de la capture d'écran (`map_vision_test`, `map_props_test`, `map_render_style_test`, `map_night_reveal_test`) et ont été écartés de la sélection headless courante ; les rejouer fenêtrés (`scripts/play-godot.ps1` ou `run_tests.ps1 -IncludeShots`) avant de toucher l'inspecteur, le render style ou le rendu des décors.

Commandes (le binaire Godot n'est pas sur le PATH) :
`$env:GODOT_BIN='C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe' ; ./scripts/run_tests.ps1 -Filter map`
et `./scripts/run_tests.ps1 -Filter terrain`, `-Filter city`, `-Filter world_zones`, `-Filter editor`.

## 7. Top 8 des cibles, priorisation et ordre de passage

| # | Cible | Lignes | Effort | Risque | Tests de protection | Gain principal |
|---:|---|---:|---|---|---|---|
| 1 | `editor/map_edit_document.gd` | 2 623 | M | **Faible** | 41 tests / 99 API | modèle éclaté en 7 modules purs, précédent pour tout le reste |
| 2 | `terrain/terrain_carve_field.gd` | 1 364 | M | Moyen | 5 tests dédiés | supprime la duplication de sampling (§4.3-4.4) |
| 3 | `editor/map_editor_construction.gd` | 2 679 | M | Faible-Moyen | 10 tests via wrappers | god file #3 ramené à une façade de ~150 l. |
| 4 | `editor/map_editor_tool_options.gd` | 1 018 | M | Faible (tests) / couplage max | 2 tests | élimine la fonction de 806 l. |
| 5 | `map_layers/map_water_3d.gd` | 2 235 | M | Faible | 5 tests + moteur | rivière de 435 l. découpée, matériaux/décor isolés |
| 6 | `map_layers/map_ground_3d.gd` | 2 303 | M | Moyen | 11 tests indirects | maillage/cliff/slab/clusters séparés |
| 7 | `complex_map_engine_3d.gd` | 4 230 | XL | **Élevé** | 32 tests / 130 membres | moteur en 10 modules + façade |
| 8 | `map_complex_editor.gd` | 5 359 | XL | **Très élevé** | 50 tests / 169 membres | contrôleur ~900 l., UI dans des builders |

**Ordre de passage recommandé** (une vague = plusieurs PR, **jamais deux god files dans le même commit**) :

1. **Vague 0 — mesure et filet** : rejouer la suite complète headless + les 4 tests de capture écartés ; consigner le résultat dans `docs/refactor/logs/` ; relancer `tools/refactor/metrics.ps1` pour figer la baseline ; ajouter le test de contrat (§2) listant les membres atteints par les tests.
2. **Vague 1 — fichiers purs, risque minimal** : #1 document puis #2 terrain_carve_field puis #4 tool options (factories d'abord, familles ensuite). À chaque extraction : wrappers d'une ligne + un run ciblé.
3. **Vague 2 — couches 3D isolées** : #5 water, #6 ground, puis `map_meshes_3d` (non listé au top 8 mais même patron). Profiter de la vague pour introduire le `TerrainSampler` unique et supprimer les 3 copies de `_terrain_height_at`.
4. **Vague 3 — construction et moteur** : #3 construction (mécanique : blocs contigus), puis #7 moteur en 3 sous-vagues (rendu/atmosphère → caméra/projection → tokens/table/entrée).
5. **Vague 4 — contrôleur** : #8 éditeur par slices de 200-400 l., dans cet ordre : builders UI (chrome/dialogues) → layout → settings binder → commandes/raccourcis → outils terrain/eau → placement. Le contrôleur final ne garde que l'état, les wrappers, le câblage de signaux et l'API publique.
6. **Vague 5 — nettoyage** : suppression du code mort (§4.1, ~1 756 l.), de la grille v1 masquée et de la palette d'environnement masquée ; mise à jour de `ARCHITECTURE.md` (qui décrit encore les modules morts) et de `REFACTOR_EDITEUR.md` (compteurs périmés).

**Règles d'exécution** : zéro changement de comportement par extraction ; conserver les noms exacts des membres privés atteints par les tests ; ne jamais supprimer un wrapper sans avoir modifié le test qui l'utilise ; mesurer avant/après avec `metrics.ps1` ; un module extrait ne reçoit **aucune** nouvelle responsabilité ensuite (frontière de propriété, réponse au problème n°1).

## 8. Risques transverses et parades

| Risque | Où | Parade |
|---|---|---|
| Couplage dynamique `_ed` non typé (typo invisible) | construction 469/77, edit_ops 425/59, tool_options 508/109 | test de contrat (§2) + doc `docs/refactor/CONTRAT_EDITEUR.md` généré depuis le code + wrappers délégants |
| Tests qui sondent des internes | moteur (70 internes), éditeur (140 privés) | geler la liste avant la vague 1 ; ne renommer aucun `_membre` ; si un interne doit bouger, mettre à jour le test dans le **même** commit |
| Parité de hauteurs | `terrain_height_at` / `cell_bilinear` / `vertex_height` | extraire sans réécrire la formule ; test de parité sur cartes de référence avant remplacement |
| Rendu non vérifiable en headless | 4 tests de capture + 60 `*_shot_test` | rejouer `-IncludeShots` (fenêtre cachée) sur les vagues 2-4 ; jamais de refactor de rendu sans capture avant/après |
| Régression de perf sur cartes denses | `_apply_render_quality`, `_rebuild_layers`, `_apply_scene_plan` | `editor_drag_perf_test`, `map_quality_cs2_test` comme garde-fous ; profil avant/après sur la cité de démo |
| Regonflement du contrôleur | `map_complex_editor.gd` (3 253 → 5 359 l.) | règle de frontière : tout code neuf va dans un module ; le contrôleur ne doit pas dépasser 1 000 l. après la vague 4 |
| Portée qui dérive | `map_editor_parametres.gd`, `map_editor_world_panel.gd`, `scenario_editor.*`, `game_data.gd`, `map_data.gd` | hors top 8 : planifier dans un chantier distinct (§3.10) |
