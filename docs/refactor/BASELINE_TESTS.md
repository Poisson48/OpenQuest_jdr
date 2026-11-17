# Baseline de tests — OpenQuest JDR

> Mesure de référence **avant refactorisation**, destinée à mesurer toute régression.
> Date : **17/11/2026** · Commit : **`4514c61`** (`chore(artefacts): captures, maquettes, sondes et scripts de revue`) ·
> Branche : `feat/carte-2.5d-editeur` · Auteur : agent `baseline-tests`.
> **Aucun code ni test n'a été modifié par cette tâche** — livrables : ce fichier + `docs/refactor/logs/`.

## 0. Résumé exécutable (TL;DR)

| Mesure | Résultat | Durée |
|---|---|---|
| Suite Godot headless (`./scripts/run_tests.ps1`) | **116 PASS / 5 FAIL / 0 SKIP** sur 121 tests lancés | **24 min 35 s** |
| Suite serveur (`cd server; npm test`) | **PASS** (112 + 81 + 18 vérifications) | 5,2 s |
| Typecheck serveur (`npm run typecheck`) | **ROUGE — 5 erreurs TS pré-existantes** | 1,9 s |

- **Les 5 échecs Godot sont tous expliqués** (3 défauts de test/runner, 2 dépendances d'environnement) : ils ne doivent
  **pas** être comptés comme régressions, mais ils polluent le signal. Détail en section 6.
- Le **typecheck serveur est rouge dès la baseline** (5 erreurs dans `game_session.ts`, `mcp/gm_server.ts`,
  `narrative/world_state.ts`). Le refactor ne doit pas augmenter ce nombre.
- **Socle rapide** pour les commits du refactor : 23 tests ≈ **102 s** + serveur ≈ 110 s au total → section 11.
- 57 des 178 fichiers de test sont exclus du run par défaut (tests de capture d'écran, GPU requis) : la baseline
  « headless » porte sur **121** tests, pas 178 (section 4).

## 1. Contexte et fenêtre de mesure

| Élément | Valeur |
|---|---|
| Début de la mesure | 17/11/2026 19:23:16 |
| Fin de la mesure | 17/11/2026 19:47:51 |
| Commit HEAD (figé) | `4514c614a512ad49591de08098fff91c51400b14` |
| Branche | `feat/carte-2.5d-editeur` |
| État de l'arbre au démarrage | propre (seul `artifacts/refactor_game_launch.png` non suivi) |
| Instance du jeu ouverte en fenêtre | PID 10408, laissée intacte (non tuée, non interrogée) |

**Avertissement de concurrence.** La machine était partagée avec d'autres agents pendant la mesure : à partir de
~19:26 des scripts/outils ont été créés (`tools/refactor/metrics.ps1`, `game/scripts/debug/compile_check.gd`,
`perf_probe_*.gd`), le serveur a été renommé `server/src` → `server/legacy` (19:33-19:34), et des purges de code mort
côté Godot ont eu lieu vers **19:42**. Ces mutations **n'ont pas invalidé la mesure** : contrôle effectué après coup sur
les 178 fichiers de test, **aucune dépendance `res://` littérale (`preload`/`load`) ne manque** (0 référence morte), et
les 5 échecs sont tous reproduits en isolation et indépendants de ces suppressions. Les **durées**
ont en revanche été légèrement gonflées par la charge (ex. `map_quick_start_test` : 113 s en suite, 82,7 s isolé).
Pour une comparaison stricte après refactor, rejouer les commandes de la section 3 sur un checkout figé.

## 2. Environnement

| Composant | Version / valeur |
|---|---|
| Godot | `4.7.2.stable.official.ed1daf0bf` (`Godot_v4.7.2-stable_win64.exe`) |
| Chemin Godot | `C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe` |
| OS | Windows 10.0.26200 (11) |
| CPU / RAM | AMD Ryzen 5 3600 (6C/12T) / 23,9 Go |
| Node.js | `v24.19.0` |
| npm | `11.17.0` |
| Shell du runner | **Windows PowerShell 5.1.26100.9818 Desktop** (aucun `pwsh` 7 installé ; le runner fonctionne quand même, voir section 9) |
| Projet Godot | `game/project.godot`, `config_version=5`, scène principale `res://scenes/main_menu.tscn` |
| Dépendances serveur | `server/node_modules` présent, `package-lock.json` présent |

> Particularité **importante** : le runner exige `GODOT_BIN` (ou `godot` dans le PATH). Premier lancement à 19:22:
> échec immédiat `Godot introuvable ('godot')`, exit 2 — log conservé
> (`godot_suite_20261117_192225_FAILED_no_godot_on_PATH.log`).

## 3. Commandes reproductibles

### 3.1 Suite Godot (headless, run par défaut = 121 tests)

```powershell
$env:GODOT_BIN = 'C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe'
cd D:\git\OpenQuest_jdr
./scripts/run_tests.ps1                     # suite complète (~25 min) ; exit code = nombre d'échecs
./scripts/run_tests.ps1 -Filter 'session'   # sous-ensemble (regex sur le nom de base du fichier)
./scripts/run_tests.ps1 -TimeoutSeconds 120 # timeout par test réduit (défaut 180 s)
```

Les tests de capture (`*_shot_test.gd` et tout fichier contenant `save_png(`) sont exclus par défaut ; ils
nécessitent `-IncludeShots` (fenêtre cachée, GPU réel) et **ne font pas partie de cette baseline**.

### 3.2 Suite serveur

```powershell
cd D:\git\OpenQuest_jdr\server
npm test              # test:dice + test:lobby + test:lobby:net
npm run typecheck     # tsc --noEmit
```

### 3.3 Mesure et journalisation

Le runner n'affiche pas les durées : la mesure a été faite en horodatant chaque ligne de sortie
(`... *>&1 | ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $_ } | Out-File $log`),
puis en dérivant durée = horodatage(PASS/FAIL) − horodatage(début du test). Le CSV parsé est conservé
(`docs/refactor/logs/godot_results_parsed.csv`).

## 4. Résultats globaux

| Suite | Tests | PASS | FAIL | SKIP | Durée | Statut |
|---|---|---|---|---|---|---|
| Godot headless (défaut) | 121 | 116 | 5 | 0 | 1474,8 s (24 min 35 s) | ROUGE (5 échecs connus) |
| Serveur `npm test` | 3 scripts (112+81+18 vérifs) | OK | 0 | — | 5,2 s | VERT |
| Serveur `npm run typecheck` | `tsc --noEmit` | — | 5 erreurs | — | 1,9 s | ROUGE (pré-existant) |
| Godot `-IncludeShots` (non exécuté) | 57 | — | — | — | — | hors baseline |

Répartition : 178 fichiers `game/scripts/tests/*.gd` → **57 exclus** (captures d'écran) → **121 exécutés**.
Distribution des durées : **63 tests < 5 s**, 40 entre 5 et 15 s, 12 entre 15 et 30 s, 2 entre 30 et 60 s, 4 > 60 s
(dont 3 timeouts). Aucun `SKIP` dans le run par défaut.

## 5. Tableau complet des résultats (121 tests, ordre par domaine)

#### Carte / éditeur de carte (40 tests — 37 PASS / 3 FAIL, 822 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `map_ambient_fx_test` | PASS | 5 |  |
| `map_areas_test` | PASS | 8 |  |
| `map_backdrop_test` | PASS | 5 |  |
| `map_camera_test` | PASS | 7 |  |
| `map_cartographer_theme_test` | PASS | 2 |  |
| `map_cliff_skirt_test` | PASS | 3 |  |
| `map_context_decor_test` | PASS | 14 |  |
| `map_editor_library_filter_test` | PASS | 10 |  |
| `map_editor_parametres_test` | PASS | 9 |  |
| `map_editor_snap_test` | FAIL | 180 | échec : timeout |
| `map_editor_test` | PASS | 24 |  |
| `map_editor_ui_v2_test` | PASS | 9 |  |
| `map_editor_v2_empty_state_test` | PASS | 3 |  |
| `map_editor_v2_floating_panel_test` | PASS | 3 |  |
| `map_editor_v2_palette_test` | FAIL | 180 | échec : timeout |
| `map_editor_v2_tool_flyout_test` | PASS | 2 |  |
| `map_flora_water_integration_test` | PASS | 5 |  |
| `map_flower_zone_test` | PASS | 2 |  |
| `map_house_floors_test` | PASS | 22 |  |
| `map_house_windows_test` | PASS | 22 |  |
| `map_lighting_test` | PASS | 4 |  |
| `map_mesh_test` | PASS | 8 |  |
| `map_meshes_3d_test` | PASS | 3 |  |
| `map_mode_test` | PASS | 5 |  |
| `map_objects3d_import_test` | PASS | 3 |  |
| `map_occlusion_test` | PASS | 5 |  |
| `map_organic_creation_test` | PASS | 38 |  |
| `map_quality_cs2_test` | FAIL | 12 | échec : assertion |
| `map_quick_start_test` | PASS | 113 |  |
| `map_render_quality_test` | PASS | 22 |  |
| `map_scene_apply_test` | PASS | 23 |  |
| `map_scene_generator_test` | PASS | 2 |  |
| `map_scene_zone_test` | PASS | 28 |  |
| `map_stacking_test` | PASS | 9 |  |
| `map_terrain_doc_test` | PASS | 8 |  |
| `map_terrain_materials_test` | PASS | 9 |  |
| `map_terrain_test` | PASS | 5 |  |
| `map_token_figurine_test` | PASS | 2 |  |
| `map_vegetation_density_test` | PASS | 3 |  |
| `map_water_test` | PASS | 5 |  |

#### Terrain / monde / eau (20 tests — 20 PASS / 0 FAIL, 76 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `carve_cut_detail_test` | PASS | 3 |  |
| `carve_normals_test` | PASS | 3 |  |
| `fog_overlay_test` | PASS | 3 |  |
| `marching_cubes_test` | PASS | 2 |  |
| `path_terrain_build_test` | PASS | 3 |  |
| `river_continuity_test` | PASS | 2 |  |
| `river_user_trace_test` | PASS | 7 |  |
| `terrain_carve_test` | PASS | 5 |  |
| `terrain_sculpt_live_test` | PASS | 9 |  |
| `terrain_sculpt_test` | PASS | 3 |  |
| `terrain_strata_test` | PASS | 4 |  |
| `visibility_polygon_test` | PASS | 2 |  |
| `water_bodies_test` | PASS | 7 |  |
| `water_tools_ui_test` | PASS | 6 |  |
| `wave_function_collapse_test` | PASS | 2 |  |
| `world_edge_session_test` | PASS | 2 |  |
| `world_editor_test` | PASS | 7 |  |
| `world_map_test` | PASS | 2 |  |
| `world_navigation_test` | PASS | 2 |  |
| `world_zones_test` | PASS | 2 |  |

#### Assets procéduraux (16 tests — 16 PASS / 0 FAIL, 50 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `procedural_bridge_mesh_test` | PASS | 7 |  |
| `procedural_campfire_test` | PASS | 2 |  |
| `procedural_fence_test` | PASS | 2 |  |
| `procedural_path_test` | PASS | 2 |  |
| `procedural_poly_roof_test` | PASS | 2 |  |
| `procedural_rock_test` | PASS | 2 |  |
| `procedural_rock_wall_test` | PASS | 2 |  |
| `procedural_roof_test` | PASS | 2 |  |
| `procedural_tent_test` | PASS | 2 |  |
| `procedural_wall_door_test` | PASS | 8 |  |
| `procedural_wall_window_test` | PASS | 7 |  |
| `rock_formation_test` | PASS | 2 |  |
| `rock_kit_library_test` | PASS | 3 |  |
| `rock_pbr_test` | PASS | 2 |  |
| `rock_wall_mesh_test` | PASS | 2 |  |
| `slab_quality_test` | PASS | 3 |  |

#### Session (8 tests — 8 PASS / 0 FAIL, 70 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `session_drag_move_test` | PASS | 6 |  |
| `session_map_input_test` | PASS | 2 |  |
| `session_minimap_test` | PASS | 3 |  |
| `session_model_test` | PASS | 2 |  |
| `session_move_tool_test` | PASS | 26 |  |
| `session_procedural_wall_block_test` | PASS | 4 |  |
| `session_story_log_test` | PASS | 11 |  |
| `session_turn_test` | PASS | 16 |  |

#### Éditeur de scénario (4 tests — 4 PASS / 0 FAIL, 20 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `scenario_editor_test` | PASS | 5 |  |
| `scenario_graph_links_test` | PASS | 3 |  |
| `scenario_graph_routing_test` | PASS | 9 |  |
| `scenario_library_draft_test` | PASS | 3 |  |

#### Règles / dés (3 tests — 3 PASS / 0 FAIL, 7 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `dice_engine_test` | PASS | 3 |  |
| `ruleset_test` | PASS | 2 |  |
| `semantic_move_test` | PASS | 2 |  |

#### UI / ergonomie éditeur (7 tests — 7 PASS / 0 FAIL, 38 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `command_palette_test` | PASS | 3 |  |
| `editor_drag_perf_test` | PASS | 11 |  |
| `editor_minimap_test` | PASS | 4 |  |
| `editor_views_test` | PASS | 3 |  |
| `keyboard_nav_test` | PASS | 5 |  |
| `pan_cursor_tracking_test` | PASS | 8 |  |
| `zoom_to_cursor_test` | PASS | 4 |  |

#### Jeu / UI in-game / rendu (19 tests — 19 PASS / 0 FAIL, 184 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `camera_navigation_test` | PASS | 13 |  |
| `character_editor_test` | PASS | 3 |  |
| `cite_demo_catalog_test` | PASS | 16 |  |
| `cite_eau_test` | PASS | 3 |  |
| `city_scene_test` | PASS | 12 |  |
| `cs2_finitions_test` | PASS | 4 |  |
| `hd_assets_test` | PASS | 3 |  |
| `object_grounding_test` | PASS | 5 |  |
| `quest_navigation_test` | PASS | 2 |  |
| `scene_load_test` | PASS | 21 |  |
| `scene_rocks_test` | PASS | 19 |  |
| `simple_map_editor_test` | PASS | 7 |  |
| `table_model_loader_test` | PASS | 4 |  |
| `table_view_test` | PASS | 9 |  |
| `texture_quality_test` | PASS | 2 |  |
| `token_figurine_class_test` | PASS | 4 |  |
| `valbois_diorama_setup` | PASS | 4 |  |
| `valbois_session_sim_test` | PASS | 46 |  |
| `vegetation_cards_test` | PASS | 7 |  |

#### Réseau (3 tests — 2 PASS / 1 FAIL, 27 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `session_protocol_test` | PASS | 2 |  |
| `webrtc_pooling_e2e_test` | FAIL | 22 | échec : assertion |
| `webrtc_stun_test` | PASS | 3 |  |

#### Sondes / divers (1 test — 0 PASS / 1 FAIL, 181 s)

| Test | Statut | Durée (s) | Remarque |
|---|---|---|---|
| `zz_probe_grid` | FAIL | 181 | échec : timeout |




## 6. Échecs — diagnostic précis

| # | Test | Statut runner | Cause réelle | Reproduit isolé ? | Nature |
|---|---|---|---|---|---|
| 1 | `map_editor_snap_test` | FAIL (timeout, 180 s) | **Test trop lent** (~257 s), pas une boucle : synchro 3D complète (`configure()` ≈1,7 s) à chaque mutation (~150) ; corrigé en phase 2.0 | Passait en 257 s | **Test non isolé du rendu** |
| 2 | `map_editor_v2_palette_test` | FAIL (timeout, 180 s) | Le test **ne compile pas** : `palette.gd:78` référence l'autoload `AppSettings` dans un `const preload` | Oui (identique) | **Défaut de test/couplage autoload** |
| 3 | `map_quality_cs2_test` | FAIL (assertion, 12 s) | 1 assertion sur 187 : MSAA classique attendu 2× mais 4× imposé par les préférences `user://` | Oui | **Environnement non hermétique** |
| 4 | `webrtc_pooling_e2e_test` | FAIL (assertion, 22 s) | Aucun serveur pooling sur `ws://127.0.0.1:8080` | Oui ; **PASS en 3,7 s avec le serveur** | **Dépendance de service** |
| 5 | `zz_probe_grid` | FAIL (timeout, 181 s) | Sonde temporaire cassée : `GraphEdit.get_theme_item_list()` n'existe plus → erreur avant `quit()` | Oui | **Script mort abandonné** |

### 6.1 `map_editor_snap_test` — test trop lent > 180 s (ce n'est pas une assertion)

- Échec au bout de **180 s pile** (`FAIL (timeout)`), sans aucune sortie d'erreur : le runner tue au timeout.
- En isolation avec 240 s : **encore bloqué**. Dernière assertion réussie : `wall_chain_height` (log
  `diag_map_editor_snap_test_20261117_194901.out.log`, 77 lignes `OK`, aucune erreur).
- **Diagnostic initial corrigé en phase 2.0 (2026-11-17)** : ce n'est pas un blocage.
  Le test passe en **257 s** ; chaque mutation du document déclenche
  `_on_doc_changed()` → `ComplexMapEngine3D.configure()` complet ≈1,7 s
  (`_meshes_layer.configure` = 1 694 ms / 1 734 mesurés) × ~150 mutations
  > timeout 180 s. Le point de mesure initial portait sur la section « coin L
  automatique », à l'appel
  `editor._create_mesh_wall_chain(Vector2(70.0, 60.0), Vector2(70.0, 66.0))` (~l. 415-420 du test) : le test
  poursuit ensuite par `wall_l_corner_created`, `wall_l_corner_at_junction`… qui n'arrivent jamais.
- Conséquence pour le refactor : test à isoler/corriger (ou marquer xfail) **avant** de l'utiliser comme garde-fou ;
  son timeout coûte 180 s à chaque run complet.

### 6.2 `map_editor_v2_palette_test` — le test ne compile pas (timeout 180 s)

- stderr : `SCRIPT ERROR: Compile Error: Identifier not found: AppSettings`, puis
  `Failed to load script "res://scripts/tests/map_editor_v2_palette_test.gd"` → le test n'exécute jamais son `_run()`,
  donc **jamais `quit()`** → le runner conclut au timeout.
- Cause : `scripts/maps/editor/v2/palette.gd:78` (`var remapped := AppSettings.shortcut_label_for_tool(id)`, ajouté
  par `a8de33c`) est compilé au **chargement du script de test** car le test fait
  `const PaletteScript = preload("res://scripts/maps/editor/v2/palette.gd")`. En mode `--script`, les autoloads ne sont
  pas encore enregistrés comme globaux à ce moment-là. D'autres scripts utilisant `AppSettings` (ex.
  `map_complex_editor.gd`) ne déclenchent pas d'erreur car ils sont chargés plus tard, via `load()`/scène.
- Correctif probable (hors périmètre de cette baseline) : remplacer le `preload` const par un `load()` en runtime dans
  le test, ou supprimer la dépendance à l'autoload dans un script préchargé.

### 6.3 `map_quality_cs2_test` — 186 OK, 1 FAIL d'environnement (non hermétique)

- Assertion `ui_engine_classic_msaa` : attendu `Viewport.MSAA_2X`, obtenu `msaa=2` (= `MSAA_4X`).
- Cause : **préférences utilisateur persistées** dans
  `C:\Users\Leo\AppData\Roaming\Godot\app_userdata\OpenQuest JDR\app_settings.cfg` :
  `[rendering] preset="cinema"` et `aa="msaa4"` (→ msaa=2). `AppSettings` applique cette surcharge **globale**
  après `configure()` (`complex_map_engine_3d.gd:969-973: _apply_global_overrides()`), et elle gagne sur le preset
  classique. Ce fichier a en outre été **réécrit pendant les runs de test** (mtime 19:50:51) : les tests écrivent dans
  `user://`.
- Conclusion : le test passe si `aa="auto"` (valeur par défaut). **Ce n'est pas une régression du code** ; c'est un
  test qui dépend de l'état `user://` de la machine. À rendre hermétique (ressource temporaire ou reset avant test).
  Attention : ce fichier peut affecter d'autres tests de rendu.

### 6.4 `webrtc_pooling_e2e_test` — dépendance serveur (échec environnemental)

- Sans serveur : `[webrtc_e2e] FAIL — timeout phase=connect room=` après ~20 s (durée runner 22 s).
- Avec le serveur pooling lancé (`server` : `node node_modules/tsx/dist/cli.mjs src/index.ts`) :
  **`[webrtc_e2e] PASS — room=5616 host=… client=…` en 3,7 s**.
- Conclusion : la suite Godot n'est verte à 117/121 que si le serveur Node tourne. Pour un run Godot pur, ce test est
  structurellement rouge ; il doit être lancé dans le job CI qui démarre le serveur.

### 6.5 `zz_probe_grid` — sonde temporaire abandonnée (timeout 181 s)

- Fichier de 19 lignes, en-tête « Sonde temporaire : propriétés/thème de GraphEdit » — commité dans le dossier de tests.
- `SCRIPT ERROR: Invalid call. Nonexistent function 'get_theme_item_list' in base 'GraphEdit'` : l'API n'existe plus en
  Godot 4.7 ; l'erreur survient dans `_init()` **avant** `quit()` → le SceneTree ne se termine jamais → timeout.
- Déterministe. À **supprimer** (ou déplacer hors de `scripts/tests/`) : il ajoute 180 s inutiles au run.

## 7. Suite serveur Node/TS

`npm test` (5,2 s, exit 0) — scripts indépendants, aucune dépendance externe :
- `test:dice` → `dice_engine_test:PASS 112 vérifications` (moteur TS vs cas partagés `game/data/tests/dice_cases.json`)
- `test:lobby` → `lobby_test:PASS 81 vérifications` (protocole, rate-limit, tickets, validation zod, RoomManager)
- `test:lobby:net` → `lobby_integration:PASS 18 vérifications` (vrai serveur WebSocket, port éphémère 7891)

`npm run typecheck` **ÉCHOUE** (1,9 s, exit 1) — baseline rouge, 5 erreurs **pré-existantes** :
```text
src/game_session.ts(9,10):        error TS2305: Module '"./ai-gm.js"' has no exported member 'AiGM'.
src/mcp/gm_server.ts(16,10):      error TS2305: Module '"../ai-gm.js"' has no exported member 'AiGM'.
src/narrative/world_state.ts(58,28): error TS2353: Object literal may only specify known properties, and 'category' does not exist in type 'WorldFact'.
src/narrative/world_state.ts(58,50): error TS2339: Property 'turn' does not exist on type 'AiState'.
src/narrative/world_state.ts(65,22): error TS7015: Element implicitly has an 'any' type because index expression is not of type 'number'.
```
`npm test` n'est pas bloqué : `tsx` transpile sans vérification de types. Ces erreurs concernent le code
`legacy`/narratif, hors tests.

## 8. Lenteurs et priorisation

| Test | Durée suite | Durée isolée | Commentaire |
|---|---|---|---|
| `map_quick_start_test` | 113 s | 82,7 s | **1 test = 8 % du run** ; lenteur intrinsèque → optimiser ou sortir du socle |
| `valbois_session_sim_test` | 46 s | — | simulation de session longue |
| `map_organic_creation_test` | 38 s | — | génération procédurale |
| `map_scene_zone_test` | 28 s | — | |
| `session_move_tool_test` | 26 s | — | |
| `map_editor_test` | 24 s | — | test pivot de l'éditeur |
| `map_scene_apply_test` | 23 s | — | |
| `map_house_floors_test` / `map_house_windows_test` | 22 s | — | |
| `map_render_quality_test` | 22 s | — | |
| `scene_load_test` | 21 s | — | chargement de toutes les scènes |
| `map_editor_snap_test` | 180 s (timeout) | > 240 s | hang (section 6.1) |
| `map_editor_v2_palette_test` | 180 s (timeout) | 180 s+ | ne compile pas (section 6.2) |
| `zz_probe_grid` | 181 s (timeout) | 180 s+ | sonde morte (section 6.5) |

Priorisation suggérée : (1) supprimer `zz_probe_grid` et réparer/neutraliser `map_editor_snap_test` +
`map_editor_v2_palette_test` → le run passe de ~24,5 min à ~21 min ; (2) optimiser `map_quick_start_test` ; (3) les
tests > 20 s restent dans la CI complète, pas dans le socle.

## 9. Fragilités du runner et points d'attention pour le refactor

1. **`GODOT_BIN` obligatoire** : sans lui (et sans `godot` dans le PATH), le runner sort en exit 2 en 0,6 s.
2. **Le timeout ne tue pas le process sous Windows PowerShell 5.1** : le runner appelle `$proc.Kill($true)` mais
   `.NET Framework` n'expose que `Process.Kill()` — l'exception est avalée par `try/catch`. Conséquence observée :
   `map_editor_v2_palette_test` (orphelin ~19:32→19:34) et `zz_probe_grid` (orphelin 19:44→19:57, tué manuellement).
   Ces orphelins consomment du CPU et **partagent les fichiers temporaires** `%TEMP%\openquest_tests_out.txt` /
   `_err.txt` (noms fixes) → risque de contamination si le runner relance un test pendant qu'un orphelin écrit.
   Nettoyage manuel nécessaire après tout timeout.
3. **Détection PASS/FAIL heuristique** : PASS si exit 0 **et** motif `PASS`/`"passed": true`/`"ok": true`/`ALL_OK = true` ;
   FAIL si le mot `FAIL` apparaît **n'importe où** dans stdout+stderr. Un test qui loguerait « FAIL » dans un cas non
   échoué serait faussement rouge.
4. **11 tests ne contiennent pas de marqueur `PASS` littéral** et rapportent un JSON de fin (`"passed": true` /
   `"ok": true`) : `character_editor_test`, `command_palette_test`, `editor_minimap_test`, `editor_views_test`,
   `quest_navigation_test`, `scenario_editor_test`, `scenario_graph_links_test`, `scenario_library_draft_test`,
   `token_cutout_debug`, `user_flow_test`, `zz_probe_grid`.
5. **Un seul runner à la fois** (fichiers temp fixes + instance Godot partagée). Pendant cette baseline, un autre agent
   lançait des sondes Godot (perf) → durées gonflées, timeouts plus probables.
6. **Tests non hermétiques** : certains lisent/écrivent `user://` (`app_settings.cfg` → section 6.3), et l'instance du
   jeu ouverte sur la machine partage la même configuration utilisateur.
7. **Aucun SKIP** dans le run par défaut (les captures sont exclues en amont, pas skippées).

## 10. Couverture : tests ↔ modules

108 des 121 tests préchargent au moins une ressource `res://` (13 sont autonomes : `semantic_move_test`,
`session_model_test`, `session_protocol_test`, `session_turn_test`, `session_story_log_test`, `session_map_input_test`,
`scenario_library_draft_test`, `character_editor_test`, `scene_load_test`, `hd_assets_test`, `texture_quality_test`,
`rock_pbr_test`, `zz_probe_grid`). Répartition des préchargements (nombre de tests par zone du code) :

| Zone de code préchargée | Tests |
|---|---|
| `game/scenes/map_editor/*` | 34 |
| `game/scripts/maps/*` | 27 |
| `game/scripts/maps/map_layers/*` | 24 |
| `game/scripts/maps/construction/*` | 18 |
| `game/scripts/maps/editor/*` | 13 |
| `game/scripts/debug/*` | 9 |
| `game/scripts/maps/terrain/*` | 6 |
| `game/scripts/*` (divers) | 6 |
| `game/scripts/maps/editor/v2/*` | 5 |
| `game/scripts/maps/world/*` | 5 |
| `game/scripts/session*`, `game/scenes/session*` | 4 + 4 + 2 |
| `game/scripts/scenario_editor/panels/*` | 4 |
| `game/scripts/core/rules/*` | 3 |
| `game/shaders/*` | 3 |
| `game/scripts/multiplayer/*` | 3 |
| `game/scripts/theme/*` | 3 |
| `game/scripts/core/los/*` | 2 |

**0 référence morte** : les 178 fichiers de test ne référencent aucun `preload`/`load` littéral inexistant (vérifié
après les purges d'autres agents). C'est le point de contrôle à conserver : toute suppression de script encore
préchargé par un test fera échouer ce test (compilation) — le socle rapide doit être vert avant chaque commit.

## 11. Socle rapide (< 2 min) proposé pour les commits du refactor

23 tests ciblés, mesurés à **102 s** sur cette machine (hors serveur), avec `-TimeoutSeconds 120` pour échouer vite :

```powershell
$env:GODOT_BIN = 'C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe'
cd D:\git\OpenQuest_jdr
./scripts/run_tests.ps1 -TimeoutSeconds 120 -Filter '^(dice_engine_test|ruleset_test|semantic_move_test|session_model_test|session_protocol_test|session_minimap_test|session_turn_test|command_palette_test|keyboard_nav_test|map_editor_ui_v2_test|map_editor_parametres_test|map_terrain_materials_test|terrain_carve_test|terrain_sculpt_test|scenario_graph_links_test|scenario_library_draft_test|water_bodies_test|visibility_polygon_test|world_zones_test|webrtc_stun_test|table_model_loader_test|fog_overlay_test|map_token_figurine_test)$'
cd server; npm test; npm run typecheck
```

Couverture du socle : règles/dés, session (modèle/protocole/tour), UI éditeur, terrain/carve, scénario, eau,
vision, monde, réseau. Total mesuré : **102 s Godot + 5,2 s serveur + 1,9 s typecheck ≈ 109 s** (< 2 min).
Variante « ultra-rapide » (~20 s) si le temps presse : `dice_engine_test|ruleset_test|semantic_move_test|session_model_test|session_protocol_test|session_minimap_test`
(14 s) + `npm test` (5,2 s).

> Règle proposée : aucun commit du refactor sans ce socle vert (ou, si un test est rouge, sans nommer explicitement le
> test rouge dans le message de commit). Suite complète + typecheck avant merge sur la branche principale.

## 12. Logs et fichiers conservés

| Fichier (relatif à la racine du dépôt) | Contenu |
|---|---|
| `docs/refactor/logs/godot_suite_20261117_1925.log` | **log brut de la suite Godot** (375 lignes, horodaté, PASS/FAIL, détail des échecs) |
| `docs/refactor/logs/godot_results_parsed.csv` | résultat parsé : `Test,Status,DurS,Reason` (121 lignes) |
| `docs/refactor/logs/godot_tests_selection_20261117_192225.txt` | liste des 121 tests exécutés |
| `docs/refactor/logs/godot_tests_excluded_20261117_192225.txt` | liste des 57 tests de capture exclus |
| `docs/refactor/logs/godot_suite_20261117_192225_FAILED_no_godot_on_PATH.log` | preuve de l'échec `GODOT_BIN` manquant |
| `docs/refactor/logs/server_npm_test_20261117_192225.log` | `npm test` serveur (PASS) |
| `docs/refactor/logs/server_typecheck_20261117_1925.log` | `npm run typecheck` (5 erreurs) |
| `docs/refactor/logs/diag_*_20261117_194901.{out,err}.log` | diagnostics isolés des 5 échecs |
| `docs/refactor/logs/diag_map_quick_start_test_20261117_1955.out.log` | mesure isolée du test le plus lent |
| `docs/refactor/logs/diag_webrtc_pooling_e2e_test_with_server_20261117.out.log` | preuve du PASS WebRTC avec serveur |
| `docs/refactor/logs/server_start_for_webrtc_20261117.log` | démarrage serveur pour ce test |
| `docs/refactor/logs/diag_summary_20261117_194901.txt` | synthèse des runs isolés |
| `docs/refactor/logs/md_table.md` | table brute générée (source du tableau de la section 5) |

## 13. Comment mesurer les régressions après refactor

1. Rejouer exactement la section 3 sur un état figé (commit ou worktree) et rejouer le socle (section 11).
2. Comparer au CSV de référence : **121 tests lancés, 116 PASS, 5 FAIL** avec la liste connue
   (`map_editor_snap_test`, `map_editor_v2_palette_test`, `map_quality_cs2_test`, `webrtc_pooling_e2e_test`,
   `zz_probe_grid`).
3. **Toute nouvelle ligne FAIL = régression** ; tout test qui disparaît du run (fichier supprimé) doit être justifié.
   Une baisse attendue du nombre de FAIL n'est valide que si le test a été corrigé/supprimé volontairement.
4. Typecheck : baseline = **5 erreurs**. Objectif raisonnable : ne pas augmenter ; idéalement 0 après correction.
5. Surveiller les **durées** : un écart > 50 % sur `map_quick_start_test` ou les tests ~20 s signale une régression de
   performance (mais la charge machine fausse la comparaison — rejouer à charge équivalente, Godot headless seul).

---

## 14. Reprise post-phase 1 (contrôle de non-régression)

> Mesure du **2026-11-17 20:06-20:25**, sur les commits `ac98a98` (phase 0) + `b231995` (phase 1).
> Commande : `./scripts/run_tests.ps1` (runner corrigé : temporaires uniques + fin forcée) ; log brut conservé
> `docs/refactor/logs/godot_suite_post_phase1.log`.

| Mesure | Baseline `4514c61` | Post-phase 1 |
|---|---|---|
| Tests lancés | 121 | **120** (−1 : `zz_probe_grid` supprimé, ADR-007) |
| PASS | 116 | **115** |
| FAIL | 5 | **5** (dont 1 flake de concurrence, voir ci-dessous) |
| Durée | 24 min 35 s | 18 min 46 s |

Échecs post-phase 1 et statut :

| Test | Statut | Commentaire |
|---|---|---|
| `map_editor_snap_test` | connu (inchangé) | hang déterministe dans la chaîne de murs « coin L » (~180 s) — bug à traiter en phase 4 (construction/coins) |
| `map_editor_v2_palette_test` | connu (inchangé) | ne compile pas en mode `--script` : `palette.gd:78` référence `AppSettings` dans un `const preload` (autoload non résolu au chargement) — à corriger en phase 2 |
| `map_quality_cs2_test` | connu (inchangé) | non hermétique : MSAA 4× imposé par `user://app_settings.cfg` — à corriger en phase 2 |
| `webrtc_pooling_e2e_test` | connu (inchangé) | nécessite un serveur pooling local (PASS en 3,7 s avec serveur, cf. §5) |
| `city_scene_test` | **flake de concurrence** | échoue (`no_ground_overlap`) uniquement parce qu'une instance du jeu a été relancée pendant le run ; **PASS en isolation** (`./scripts/run_tests.ps1 -Filter '^city_scene_test$'`). Ne pas lancer la suite et l'éditeur/jeu en même temps. |

**Conclusion** : aucune régression attribuable aux suppressions de la phase 1. `verify.ps1` est vert, la compilation des 452 fichiers (scripts + scènes) est verte, les tests du domaine sont verts (17/17) et la suite complète retrouve le profil de la baseline moins le test-sonde supprimé.

---

## 15. Phase 2.0 — les 3 échecs de test corrigés (2026-11-17)

> Après la phase 1, la phase 2.0 a traité les 3 échecs de test restants (hors WebRTC qui dépend d'un serveur).
> Vérification : `./tools/refactor/verify.ps1` VERT (compilation 369 fichiers 0 échec, typecheck serveur, socle rapide 25 PASS / 0 FAIL).

| Test | Cause racine | Correctif (test seul, zéro modification de prod) | Résultat |
|---|---|---|---|
| `map_editor_v2_palette_test` | `const preload` du test compilé AVANT l'enregistrement des autoloads en mode `--script` → `palette.gd` référence `AppSettings` | `load()` dans `_run()` après le premier frame | **PASS (12 OK)** |
| `map_quality_cs2_test` | Non hermétique : `AppSettings.apply_to_engine()` réapplique `user://app_settings.cfg` (msaa4) après chaque `configure()` et gagne sur le preset classique | neutralisation **en mémoire** de la section `rendering` (fichier cfg intact, SHA256 vérifié) | **PASS (183 OK / 0 FAIL)** |
| `map_editor_snap_test` | **Test trop lent** (257 s), pas une boucle : `configure()` complet ≈1,7 s à chaque mutation (~150) | suspension de `doc.changed`→`_on_doc_changed` pendant le test (motif bulk-edit), rejeu unique avant teardown | **PASS (33 s, 95 OK)** |

**Conséquence pour la baseline** : la liste des échecs connus passe de 5 à **1** (`webrtc_pooling_e2e_test`, qui passe en 3,7 s avec un serveur pooling local).
**Découverte à exploiter en phase 4** : `ComplexMapEngine3D.configure()` complet coûte ≈1,7 s en headless (`_meshes_layer.configure`) et est déclenché à CHAQUE mutation du document (`map_complex_editor.gd:_on_doc_changed`) — c'est la cause mesurée du gel de l'éditeur (cf. `RAPPORT_PERFORMANCE_EDITEUR_3D.md`). La synchro incrémentale (couches sales) est prioritaire en vague 3.
---

## 16. Correctif de sélection du runner — 4 tests récupérés (2026-11-17)

Le runner excluait par défaut tout test contenant `save_png(` en le prenant pour une capture. Or **4 tests utilisent `save_png()` pour créer leurs propres IMAGES DE TEST (fixtures)**, pas pour capturer l'écran : ils n'ont besoin d'aucun GPU et passaient déjà en headless.

`scripts/run_tests.ps1` exclut désormais UNIQUEMENT les fichiers `*_shot_test.gd` (convention documentée). Vérifié : `map_vision_test`, `map_props_test`, `map_render_style_test`, `map_night_reveal_test` → **4 PASS** en headless via le runner.

**Impact coverage** : la suite headless passe de 120 à **124 tests** (+4), sans nouveau rouge. Ces tests couvrent respectivement la vision/cazes, les props, le style de rendu et la révélation nocturne.