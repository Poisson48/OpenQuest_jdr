# Inventaire technique — OpenQuest JDR

Généré par `tools/refactor/metrics.ps1` le 2026-11-17 23:30. Mesure reproductible : relancer ce script après chaque phase de refactor pour comparer.

## Volumétrie

| Mesure | Valeur |
|---|---|
| Scripts Godot (.gd) | 384 |
| Lignes Godot | 118300 |
| Fichiers > 1000 l. | 19 |
| Fichiers > 500 l. | 55 |
| Fichiers < 100 l. | 142 |
| Autoloads | 8 |
| Scènes .tscn | 86 |
| Scripts de test | 181 |
| Fichiers TS serveur | 11 |
| Lignes TS serveur | 1682 |
## Top god files (scripts Godot)

| Fichier | Lignes | Fonctions |
|---|---|---|
| `game/scripts/maps/map_complex_editor.gd` | 5453 | 276 |
| `game/scripts/maps/complex_map_engine_3d.gd` | 4333 | 213 |
| `game/scripts/autoload/game_data.gd` | 4199 | 293 |
| `game/scripts/maps/editor/map_editor_construction.gd` | 2685 | 104 |
| `game/scripts/maps/editor/map_edit_document.gd` | 2644 | 182 |
| `game/scripts/scenario_editor.gd` | 2386 | 165 |
| `game/scripts/maps/map_layers/map_ground_3d.gd` | 2303 | 132 |
| `game/scripts/maps/map_layers/map_water_3d.gd` | 2235 | 83 |
| `game/scripts/maps/editor/map_editor_parametres.gd` | 2131 | 102 |
| `game/scripts/autoload/map_data.gd` | 1954 | 117 |
| `game/scripts/maps/map_layers/map_meshes_3d.gd` | 1647 | 77 |
| `game/scripts/maps/construction/procedural_city.gd` | 1611 | 52 |
| `game/scripts/maps/editor/map_editor_world_panel.gd` | 1487 | 70 |
| `game/scripts/maps/terrain/terrain_carve_field.gd` | 1364 | 65 |
| `game/scripts/session/panels/map_workspace.gd` | 1321 | 77 |
| `game/scripts/scenario_editor/panels/graph_link_overlay.gd` | 1176 | 55 |
| `game/scripts/interactive_map.gd` | 1103 | 70 |
| `game/scripts/maps/editor/map_editor_tool_options.gd` | 1018 | 10 |
| `game/scripts/multiplayer/multiplayer_manager.gd` | 1007 | 93 |
| `game/scripts/maps/editor/map_editor_inspector.gd` | 1000 | 50 |
| `game/scripts/debug/perf_probe_transform.gd` | 998 | 25 |
| `game/scripts/tests/terrain_quality_shot_test.gd` | 989 | 33 |
| `game/scripts/tests/map_quality_cs2_test.gd` | 966 | 28 |
| `game/scripts/maps/simple/simple_map_editor.gd` | 956 | 56 |
| `game/scripts/maps/editor/map_editor_overlay.gd` | 861 | 42 |

## Répartition par dossier

| Dossier | Fichiers | Lignes |
|---|---|---|
| maps | 79 | 46355 |
| tests | 181 | 33901 |
| debug | 40 | 7433 |
| autoload | 7 | 7225 |
| session | 26 | 5496 |
| scenario_editor | 10 | 4172 |
| core | 15 | 3785 |
| scenario_editor.gd | 1 | 2386 |
| multiplayer | 2 | 1221 |
| interactive_map.gd | 1 | 1103 |
| game_setup.gd | 1 | 658 |
| hub | 7 | 652 |
| ui | 2 | 638 |
| character_editor.gd | 1 | 597 |
| hub.gd | 1 | 594 |
| scenario_list.gd | 1 | 499 |
| quest_navigation.gd | 1 | 464 |
| theme | 1 | 422 |
| map_viewer.gd | 1 | 271 |
| shared | 4 | 256 |
| main_menu.gd | 1 | 133 |
| screenshot_boot.gd | 1 | 39 |

## Autoloads

| Nom | Fichier | Lignes |
|---|---|---|
| ThemeColors | `scripts/autoload/theme_colors.gd` | 94 |
| UiLayout | `scripts/autoload/ui_layout.gd` | 91 |
| LocaleSettings | `scripts/autoload/locale_settings.gd` | 47 |
| AppSettings | `scripts/autoload/app_settings.gd` | 803 |
| GameData | `scripts/autoload/game_data.gd` | 4199 |
| MapData | `scripts/autoload/map_data.gd` | 1954 |
| MultiplayerManager | `scripts/multiplayer/multiplayer_manager.gd` | 1007 |
| ButtonSizing | `scripts/autoload/button_sizing.gd` | 37 |

## Candidats code mort (aucune référence trouvée)

Un script est listé si son nom de fichier et son éventuel `class_name` n'apparaissent dans aucun autre `.gd/.tscn/.tres/.cfg/project.godot` ou script d'outillage. À vérifier manuellement (chargement dynamique possible par `load()`/chemin construit).

Synthèse : **** candidat(s) hors tests/debug, 166 scripts de test (exécutés par scripts/run_tests.ps1, donc « non référencés » par nature), 5 scripts de debug (lancés par scripts/play-godot*.ps1).

### Hors tests et debug (vrais candidats)

| Fichier | Lignes | ClassName |
|---|---|---|
| `game/scripts/screenshot_boot.gd` | 39 | — |

## class_name dupliqués

Aucun.
## Noms de fonctions répétés (>= 3 fichiers, hors cycle de vie)

| Fonction | Occurrences | Fichiers |
|---|---|---|
| `_run` | 187 | `game/scripts/debug/perf_probe_layers.gd`, `game/scripts/debug/perf_probe_library.gd`, `game/scripts/debug/perf_probe_terrain.gd`, `game/scripts/debug/perf_probe_transform.gd` |
| `_assert` | 140 | `game/scripts/debug/valbois_session_simulator.gd`, `game/scripts/tests/camera_navigation_test.gd`, `game/scripts/tests/carve_normals_test.gd`, `game/scripts/tests/cite_demo_catalog_test.gd` |
| `_finish` | 21 | `game/scripts/debug/valbois_session_simulator.gd`, `game/scripts/tests/carve_normals_test.gd`, `game/scripts/tests/cite_demo_catalog_test.gd`, `game/scripts/tests/cite_eau_test.gd` |
| `configure` | 21 | `game/scripts/interactive_map.gd`, `game/scripts/maps/complex_map_engine_3d.gd`, `game/scripts/maps/construction/wave_function_collapse.gd`, `game/scripts/maps/map_areas_overlay.gd` |
| `_shot` | 18 | `game/scripts/tests/cite_eau_shot_test.gd`, `game/scripts/tests/cite_showcase_shot_test.gd`, `game/scripts/tests/fog_quality_shot_test.gd`, `game/scripts/tests/map_25d_mesh_demo_shot_test.gd` |
| `_wait_frames` | 16 | `game/scripts/tests/map_ambient_fx_test.gd`, `game/scripts/tests/map_backdrop_test.gd`, `game/scripts/tests/map_camera_test.gd`, `game/scripts/tests/map_cliff_skirt_test.gd` |
| `build` | 14 | `game/scripts/core/rules/ruleset.gd`, `game/scripts/maps/construction/procedural_bridge_mesh.gd`, `game/scripts/maps/construction/procedural_campfire_mesh.gd`, `game/scripts/maps/construction/procedural_fence_mesh.gd` |
| `_step` | 11 | `game/scripts/tests/character_editor_test.gd`, `game/scripts/tests/command_palette_test.gd`, `game/scripts/tests/editor_minimap_test.gd`, `game/scripts/tests/editor_views_test.gd` |
| `build_from_element` | 10 | `game/scripts/maps/construction/procedural_campfire_mesh.gd`, `game/scripts/maps/construction/procedural_fence_mesh.gd`, `game/scripts/maps/construction/procedural_floor_mesh.gd`, `game/scripts/maps/construction/procedural_flower_zone.gd` |
| `_quad` | 10 | `game/scripts/maps/construction/procedural_bridge_mesh.gd`, `game/scripts/maps/construction/procedural_campfire_mesh.gd`, `game/scripts/maps/construction/procedural_fence_mesh.gd`, `game/scripts/maps/construction/procedural_floor_mesh.gd` |
| `_write_report` | 10 | `game/scripts/tests/character_editor_test.gd`, `game/scripts/tests/command_palette_test.gd`, `game/scripts/tests/editor_minimap_test.gd`, `game/scripts/tests/editor_views_test.gd` |
| `_make_map` | 9 | `game/scripts/tests/map_ambient_fx_test.gd`, `game/scripts/tests/map_backdrop_test.gd`, `game/scripts/tests/map_flora_water_integration_test.gd`, `game/scripts/tests/map_organic_creation_test.gd` |
| `_settle` | 9 | `game/scripts/debug/valbois_session_simulator.gd`, `game/scripts/tests/scenario_editor_refonte_shot_test.gd`, `game/scripts/tests/scenario_graph_links_shot_test.gd`, `game/scripts/tests/scenario_graph_routing_shot_test.gd` |
| `_tri` | 9 | `game/scripts/maps/construction/procedural_bridge_mesh.gd`, `game/scripts/maps/construction/procedural_campfire_mesh.gd`, `game/scripts/maps/construction/procedural_fence_mesh.gd`, `game/scripts/maps/construction/procedural_floor_mesh.gd` |
| `_is_blank` | 9 | `game/scripts/tests/cite_eau_shot_test.gd`, `game/scripts/tests/fog_quality_shot_test.gd`, `game/scripts/tests/map_quality_cs2_shot_test.gd`, `game/scripts/tests/slab_quality_shot_test.gd` |
| `_wait_scene` | 9 | `game/scripts/tests/character_editor_test.gd`, `game/scripts/tests/keyboard_nav_test.gd`, `game/scripts/tests/scenario_editor_refonte_shot_test.gd`, `game/scripts/tests/scenario_editor_test.gd` |
| `_arm_watchdog` | 8 | `game/scripts/tests/game_data_contract_test.gd`, `game/scripts/tests/map_schema_contract_test.gd`, `game/scripts/tests/session_halfscreen_layout_test.gd`, `game/scripts/tests/session_layout_check.gd` |
| `_gui_input` | 8 | `game/scripts/interactive_map.gd`, `game/scripts/maps/complex_map_engine_3d.gd`, `game/scripts/maps/editor/map_editor_minimap.gd`, `game/scripts/maps/editor/map_editor_world_panel.gd` |
| `_make_heights` | 7 | `game/scripts/tests/map_cliff_skirt_test.gd`, `game/scripts/tests/map_quality_cs2_shot_test.gd`, `game/scripts/tests/map_terrain_materials_test.gd`, `game/scripts/tests/map_terrain_test.gd` |
| `_capture` | 7 | `game/scripts/screenshot_boot.gd`, `game/scripts/tests/demo_saules_shot_test.gd`, `game/scripts/tests/map_editor_parametres_shot_test.gd`, `game/scripts/tests/riviere_s_shot_test.gd` |
| `_result_ok` | 7 | `game/scripts/tests/command_palette_test.gd`, `game/scripts/tests/editor_minimap_test.gd`, `game/scripts/tests/editor_views_test.gd`, `game/scripts/tests/quest_navigation_test.gd` |
| `_rebuild` | 7 | `game/scripts/maps/map_layers/map_ambient_fx_3d.gd`, `game/scripts/maps/map_layers/map_backdrop_3d.gd`, `game/scripts/maps/map_layers/map_fog_3d.gd`, `game/scripts/maps/map_layers/map_vegetation_3d.gd` |
| `_wait` | 6 | `game/scripts/debug/valbois_menu_lan_agent.gd`, `game/scripts/debug/valbois_session_simulator.gd`, `game/scripts/tests/map_25d_editor_shot_test.gd`, `game/scripts/tests/map_editor_parametres_shot_test.gd` |
| `_on_back_pressed` | 6 | `game/scripts/character_editor.gd`, `game/scripts/game_setup.gd`, `game/scripts/map_viewer.gd`, `game/scripts/scenario_editor.gd` |
| `_on_locale_changed` | 6 | `game/scripts/hub.gd`, `game/scripts/hub/panels/bot_card.gd`, `game/scripts/hub/panels/character_card.gd`, `game/scripts/hub/panels/scenario_card.gd` |

## Top scènes (.tscn)

| Scène | Lignes | Ko |
|---|---|---|
| `game/scenes/scenario_editor.tscn` | 938 | 35.6 |
| `game/scenes/character_editor.tscn` | 650 | 21.9 |
| `game/scenes/map_editor/panels/settings.tscn` | 545 | 16.5 |
| `game/scenes/hub.tscn` | 403 | 13.8 |
| `game/scenes/session/panels/player_hud.tscn` | 400 | 11.5 |
| `game/scenes/session/panels/character_sheet.tscn` | 285 | 9.2 |
| `game/scenes/game_setup.tscn` | 259 | 9.2 |
| `game/scenes/map_editor/map_editor.tscn` | 245 | 8 |
| `game/scenes/scenario_list.tscn` | 227 | 7.2 |
| `game/scenes/main_menu.tscn` | 217 | 7.8 |
| `game/scenes/hub/panels/pooling_panel.tscn` | 175 | 5.2 |
| `game/scenes/map_viewer/simple_editor.tscn` | 162 | 5.6 |
| `game/scenes/session/panels/gm_console.tscn` | 158 | 4.8 |
| `game/scenes/map_editor/panels/library.tscn` | 145 | 4.1 |
| `game/scenes/session/session.tscn` | 140 | 5 |

## Tests headless

Total : 181 scripts de test, 33902 lignes.

Liste complète : voir `game/scripts/tests/`. Les captures (`*_shot_test.gd`) sont exclues par défaut de `scripts/run_tests.ps1`.
## Top fichiers serveur TypeScript

| Fichier | Lignes |
|---|---|
| `server/src/pooling/server.ts` | 488 |
| `server/src/game_types.ts` | 290 |
| `server/src/lobby/rooms.ts` | 231 |
| `server/src/party_utils.ts` | 121 |
| `server/src/lobby/tickets.ts` | 120 |
| `server/src/lobby/types.ts` | 120 |
| `server/src/lobby/validate.ts` | 105 |
| `server/src/lobby/rate_limit.ts` | 101 |
| `server/src/lobby/protocol.ts` | 76 |
| `server/src/lan_utils.ts` | 22 |
| `server/src/index.ts` | 8 |

