# Audit architecture — client Godot (core, autoloads, scénario, session)

**Agent** : `godot-core` (task-1) · **Date** : 2026-11-17 · **Mode** : READ-ONLY (aucun fichier de
`game/` ni `server/` modifié, aucun commit).

**Périmètre** : `game/scripts/autoload/`, `core/`, `session/`, `hub/`, `ui/`, `scenario_editor.gd` +
`scenario_editor/panels/`, `quest_navigation.gd`, `multiplayer/multiplayer_manager.gd`,
`multiplayer/webrtc_p2p.gd`, `interactive_map.gd`. Hors périmètre : `game/scripts/maps/**`
(→ `AUDIT_EDITEUR_CARTE.md`), `server/**` + `data/schemas/**` (→ `AUDIT_SERVEUR.md`) ; les
recoupements sont signalés.

**Méthode** : comptage physique des lignes (`(Get-Content $f).Count`, = numérotation citée), même
convention que `docs/refactor/INVENTAIRE_TECHNIQUE.md` (vérifié : `game_data.gd` 4 586 l. des deux
côtés). ⚠️ `Measure-Object -Line` renvoie les lignes **non vides** (`game_data.gd` → 4 225) : ne pas
mélanger les deux unités. Usages via `Select-String` + indexation croisée des références. Aucun
Godot lancé : la suite headless tourne en parallèle (`baseline-tests`), relancer Godot aurait faussé
ses mesures de durée.

**Note de fraîcheur** : mesures prises sur l'état commité `4514c61`. Pendant la rédaction, un autre
agent a modifié 3 fichiers de ce périmètre (`core/persistence/json_store.gd` +6 l.,
`core/rules/stats.gd` ±1 l., `debug/carte_25d_session_boot.gd` : correction d'un `func` avalé par un
commentaire) et supprimé 2 fichiers de `maps/` (hors périmètre) : `core/` vaut donc 2 686 l.
aujourd'hui (±7 l., aucun impact sur les conclusions). Relancer l'annexe avant de figer des chiffres
dans `PLAN_REFACTORISATION.md`.

**Volume du périmètre** : **76 fichiers `.gd`, 27 431 lignes**. Densité de dette : 18 fichiers
> 400 l. (24 % des fichiers) = **77 % des lignes** ; 7 fichiers > 1 000 l. = **56 % des lignes** ;
`core/` n'est vivant qu'à **28 %** (754 l. / 2 679 l.).

## 1. Inventaire chiffré

### 1.1 God files (> 1 000 lignes) et responsabilités mélangées

| Fichier | Lignes | Fonctions | Responsabilités constatées |
|---|---:|---:|---|
| `game/scripts/autoload/game_data.gd` | **4 586** | **293** | persistance JSON · CRUD personnages/scénarios/bots · registre de parties · état de session · opérations de carte synchronisées · modèle de session (barres/journal/tours/quickbar) · filtrage vue joueur · LOS + brouillard · navigation multi-échelles · **déplacement sémantique (533 l.)** · dés · navigation de scènes (`change_scene_to_file`) · données de démo en dur · **19 appels réseau** |
| `game/scripts/scenario_editor.gd` | **3 204** | **168** | contrôleur de scène · **style/UI inline (399 l., 92 `add_theme_*_override`)** · graphe (`GraphEdit` : nœuds, liens, positions, zoom) · panneau scène · éditeur de transitions · docks historique/journal · outils annotations · palette de commandes · validation |
| `game/scripts/autoload/map_data.gd` | **2 287** | **122** | catalogue de cartes (CRUD, brouillons, publication) · **pipeline image (~420 l.)** · helpers tuiles/sprites/textures (~330 l.) · **normaliseur de schéma (95 l.)** · création/duplication/redimensionnement · zones & mondes · **catalogue de démo en dur (484 l.)** |
| `game/scripts/scenario_editor/panels/graph_link_overlay.gd` | **1 848** | 84 | **routage A* des liens (~450 l.)** · simplification/occupancy/weights · dessin des câbles · couches d'actes (`class ActFrameLayer` l. 1098) · labels/ports · repli Bézier · 8 accesseurs de debug pour les tests |
| `game/scripts/session/panels/map_workspace.gd` | **1 321** | 77 | assemblage navigateur/scène/outils · **règles de déplacement + collision (232 l.)** · **transitions de zone (~74-120 l.)** · sélection de token · inspection/indices · HUD immersif · **94 références directes à `GameData`/`MapData`** |
| `game/scripts/interactive_map.gd` | **1 103** | 70 | rendu 2D (`_draw*` ~450 l.) · input/hit-testing (`_gui_input` 85 l.) · payload d'inspection · filtrage marqueurs/liens révélés · zoom/pan · **classe mère de `maps/simple/simple_map_renderer.gd:1`** |
| `game/scripts/multiplayer/multiplayer_manager.gd` | **1 007** | 93 | client pooling WebSocket (req_id, timeouts, codes d'erreur) · transports P2P (ENet/WebRTC) · cycle de vie des salons · tickets · dispatch protocole (`_handle_message`, 89 l.) · **autorité hôte** · réglages persistés · **API doublée `request_*` / `client_*`** |

Autres > 400 l. du périmètre : `autoload/app_settings.gd` 803 (réglages + fenêtre + keybindings +
presets + moteurs), `scenario_editor/panels/editor_views.gd` 704, `core/rules/dice_engine.gd` 610,
`core/rules/formula.gd` 560, `session/session_shell.gd` 534,
`scenario_editor/panels/command_palette.gd` 460, `scenario_editor/panels/editor_minimap.gd` 451,
`session/session_view_model.gd` 438, `ui/player_session_hud.gd` 412,
`session/world_map_overlay.gd` 406.

Répartition : `autoload/` 7 fichiers 7 945 l. · `session/` 26 f. 5 496 l. (dont `map_workspace`
1 321 = 24 %) · `scenario_editor/` 8 f. 3 773 l. · `core/` 17 f. 2 679 l. · `multiplayer/` 2 f.
1 221 l. · `hub/` 7 f. 652 l. · `ui/` 2 f. 638 l. · `shared/` 4 f. 256 l. · racine 3 f. 4 771 l.

### 1.2 Blocs internes mesurés (base des estimations du §6)

| Bloc | Fichier:lignes | Lignes |
|---|---|---:|
| Déplacement sémantique | `game_data.gd:3960-4492` | 533 |
| LOS / brouillard / indices | `game_data.gd:2992-3578` | 587 |
| Session active / cycle de partie | `game_data.gd:1060-1735` | 676 |
| Cartes interactives + opérations synchronisées | `game_data.gd:1736-2555` | 820 |
| Modèle de session (barres/journal/tours/quickbar) | `game_data.gd:2556-2945` | 390 |
| Navigation multi-échelles (hors sémantique) | `game_data.gd:3579-3959` + `4493-4570` | 459 |
| Pipeline image | `map_data.gd:690-765` + `1049-1405` | ~420 |
| Catalogue de démo en dur | `map_data.gd:1787-2270` | 484 |
| Style / UI inline | `scenario_editor.gd` (12 fonctions) | 399 |
| Routage des liens | `graph_link_overlay.gd:554-1000` | ~450 |
| Déplacement + collisions / transitions de zone | `map_workspace.gd:837-1025` | 232 + 74 |

## 2. Violations concrètes de `docs/ARCHITECTURE.md`

### 2.1 Principe 1 — « `core/` est pur » : respecté à la lettre, trahi en pratique

Aucune violation mécanique : **0 occurrence** de `extends Node`, `get_node(`, `@onready`,
`GameData.`, `MapData.` dans les 17 fichiers de `core/` (grep exhaustif). Le problème est l'inverse :
72 % de `core/` est **du code mort ou quasi-mort** (§4.1), et les modules morts travaillent sur un
modèle de données **divergent** de la production :

- `core/maps/map_fog.gd:67` et `core/navigation/investigation.gd:91` lisent `game["map_play"]` ; la
  production utilise `game["mapPlayState"]` (`game_data.gd:1743`, `1775`). Les brancher tels quels
  produirait un état fantôme silencieux.
- Les en-têtes annoncent des extractions de `game_data.gd` avec des plages périmées :
  `core/navigation/investigation.gd:4` « lignes ~2803-2940 » (réel : 3 231-3 360),
  `core/navigation/semantic_move.gd:4` « lignes ~3377-3910 » (réel : 3 960-4 492).

### 2.2 Principe 2 — « un seul contrat : `data/schemas/` » : non appliqué côté client

8 schémas existent (`data/schemas/`, 34 Ko : character, scenario, map, bot, ruleset, dice_roll,
session_model, save_game) mais **le client n'en lit aucun** : 0 référence dans `game/` hormis un
commentaire (`core/rules/ruleset.gd:10`). Le serveur valide avec **zod**
(`server/src/lobby/validate.ts:9`), pas avec `data/schemas/`. À la place, la validation est réécrite
à la main et dispersée : `map_data.gd:775-868` `ensure_map_schema()` (95 l. de « if not has… »),
`game_data.gd:258` `normalize_character()` (51 l.), `quest_navigation.gd:13`
`normalize_scenario()`, `game_data.gd:1084` `_normalize_saved_games_list()`,
`map_data.gd:874` `ensure_play_defaults()`. Aucune ne connaît le schéma JSON correspondant.

### 2.3 Principe 3 — « les autoloads ne font que déléguer » : faux à 88 %

`game_data.gd` : 293 fonctions, **36 seulement (12 %) font ≤ 4 lignes**. Les autres portent de la
logique métier (`_collect_semantic_candidates()` 119 l. l. 4252, `apply_map_op()` 70 l. l. 2469,
`create_new_game()` 76 l. l. 1209). Ce n'est pas une façade, c'est le domaine.

| Couplage constaté | Preuve | Effet |
|---|---|---|
| données → persistance JSON réimplémentée | `game_data.gd:53-76` (`_load_json_file`/`_save_json_file`) vs `core/persistence/json_store.gd:11-33` | deux propriétaires du même I/O |
| données → catalogue de cartes | **95** références `MapData.*` dans `game_data.gd` | un autoload en dépend d'un autre |
| données → réseau | **19** références `MultiplayerManager.*`, dont `game_data.gd:1770-1771` (`save_map_play_and_sync()` diffuse l'état) | la couche métier déclenche le transport |
| données → navigation de scènes | **6** changements de scène : `game_data.gd:722, 729, 734, 739, 747` + `:3719` (en `call_deferred`) | l'autoload pilote l'UI |
| données → rôle réseau | `game_data.gd:426-428`, `1987-1989` écrivent `MultiplayerManager.player_role/player_name/is_gm` | état de session piloté par la donnée |

### 2.4 Principe 4 — « fichiers < 400 lignes » : 77 % des lignes en infraction

18 fichiers > 400 l. concentrent 21 198 des 27 431 lignes. Le seuil est tenu dans les petits panneaux
(`session/panels/*` : 14 des 18 fichiers < 200 l.) mais pas sur les fichiers structurants :
`session/` = 5 496 l. dont **1 321 dans un seul panneau**.

### 2.5 Principe 5 — « signaux `SessionViewModel` » : lecture tenue, écriture non

- Lecture : **un seul** abonné à `GameData.active_game_updated` dans toute l'UI —
  `session/session_view_model.gd:45` ; les panneaux s'abonnent au modèle (`session_shell.gd:96-106`,
  11 signaux). Principe respecté.
- Écriture : `session_view_model.gd:295` documente « les panneaux n'écrivent jamais dans `GameData`
  directement ». Faux pour `map_workspace.gd` : **94 références** aux autoloads dont 11 mutations
  (`:518, :523, :737, :761, :774, :991, :1009, :1010`, …), plus `session_shell.gd:392, 528` et
  `hub/panels/pooling_panel.gd:265`.
- Le view-model déborde : `session_view_model.gd:407-435` `_simulate_ai_reply()` génère de la
  **narration de démo** avec `randi()` (non déterministe, non testable) ; `:187-219`
  `_build_navigation()` reconstruit un payload déjà fourni par `game_data.gd:1665-1678`.

## 3. Duplications et logique métier répétée

### 3.1 `game_data.gd` réimplémente `core/*` (le cœur « pur » n'est jamais appelé)

| Concept | Implémentation vivante (autoload) | Implémentation `core/` morte | Statut |
|---|---|---|---|
| Sauvegarde JSON | `game_data.gd:53-76` | `core/persistence/json_store.gd:11-33` | mort |
| Tours / journal | `game_data.gd:1285-1375` (`add_log_entry`, `next_turn`, `apply_player_action`, `set_waiting_for_gm`, `can_member_act`) | `core/session/turn_manager.gd:10-65` | mort |
| Scènes / navigation | `game_data.gd:1499-1525`, `1628` | `core/session/session_state.gd:40-98` | mort |
| Inventaire | `game_data.gd:2045-2260` | `core/session/inventory.gd:10-98` | mort |
| Brouillard | `game_data.gd:2992-3578` (587 l.) | `core/maps/map_fog.gd` (83 l.) | mort + clé divergente |
| Indices d'enquête | `game_data.gd:3231-3360` | `core/navigation/investigation.gd` (95 l.) | mort + clé divergente |
| Déplacement sémantique | `game_data.gd:3960-4492` (533 l.) | `core/navigation/semantic_move.gd` (126 l.) | **câblé dans aucun sens** |
| Façade dés | `game_data.gd:4575-4579` (preload direct de `dice_engine`) | `core/rules/dice.gd:15-20` | mort |

Fonctions dupliquées nom pour nom entre `game_data.gd` et le module `core` :
`parse_movement_delta` (`:4406` / `semantic_move.gd:24`), `_looks_like_movement_action` (`:4058` /
`:35`), `_has_semantic_destination_intent` (`:3984` / `:45`),
`_has_explicit_cardinal_direction` (`:3994` / `:50`), `resolve_semantic_destination` (`:4371` /
`:58`), `_manhattan` (`:4095` / `:112`). Les deux versions ont déjà divergé (le module pur résout
les marqueurs ; la version live gère PNJ, forêts, cartes liées).

### 3.2 Deux parseurs d'expressions dans `core/rules/` (12 helpers communs)

`core/rules/dice_engine.gd` (610 l.) et `core/rules/formula.gd` (560 l.) sont deux lexers + parseurs
en descente récursive écrits séparément. **12 noms de fonctions identiques** : `_is_digit`,
`_is_alpha`, `_lex`, `_peek`, `_advance`, `_is_op`, `_parse_sum`, `_parse_term`, `_parse_unary`,
`_parse_primary`, `_eval`, `_eval_comparison`. Deux sont **octet pour octet identiques** :
`formula.gd:92-96` et `dice_engine.gd:148-152` (`_is_digit` / `_is_alpha`). ~250 lignes de plomberie
en double, sans test croisé (`ruleset_test` teste `formula`, `dice_engine_test` teste `dice_engine`).
À noter : `server/src/rules/dice_engine.ts` (762 l.) est une 3ᵉ implémentation **assumée** par
`docs/MOTEUR_DES.md` (contrat `data/schemas/dice_roll.json` + cas partagés
`game/data/tests/dice_cases.json`) — dette d'outillage, pas de duplication fautive
(→ `AUDIT_SERVEUR.md`).

### 3.3 Navigation de scénario : trois versions qui se recouvrent

- Source vivante correcte : `quest_navigation.gd` (464 l., 21 fonctions statiques pures), consommée
  par `game_data.gd` (~30 appels) et `scenario_editor.gd` (25 appels).
- Doublons d'accès dans l'éditeur : `scenario_editor.gd:1389` `_scene_index_for_id()` duplique
  `quest_navigation.gd:95` `get_scene_index()` ; `scenario_editor.gd:1396` `_get_scene_dict()`
  duplique `quest_navigation.gd:86` `get_scene_by_id()`.
- Doublon de payload : `game_data.gd:1665-1678` `get_scene_navigation_summary()` et
  `session_view_model.gd:187-219` `_build_navigation()` produisent le même dictionnaire.
- Incohérence d'écriture dans l'éditeur : `_update_transition_field()` (`:2060`) copie avant
  mutation, `_clear_default_transitions()` (`:2071`) mute le tableau partagé.
- Placement : `quest_navigation.gd` et `session/world_navigation.gd` (151 l., module pur de qualité)
  devraient être dans `core/navigation/` (règle §1 du diagramme).

### 3.4 `multiplayer_manager.gd` expose deux générations d'API

| Ancienne | Ligne | Nouvelle | Ligne |
|---|---:|---|---:|
| `request_start_game()` | 869 | `client_request_start_game()` | 445 |
| `submit_action()` | 892 | `client_submit_action()` | 462 |
| `request_dice_roll()` | 898 | `client_request_dice_roll()` | 470 |
| `gm_broadcast()` | 904 | `client_gm_broadcast()` | 510 |
| `request_advance_turn()` | 912 | `client_advance_turn()` | 496 |
| `request_map_op()` | 962 | `client_request_map_op()` | 947 |

### 3.5 Autres répétitions

- **Faux MJ IA en double** : `session_view_model.gd:407-435` (29 l., 4 répliques) et
  `multiplayer_manager.gd:828-853` `_host_simulate_ai_response()` (26 l.), textes différents, deux
  couches différentes.
- **Données de démo en dur** : `map_data.gd:1787-2270` (484 l., `_build_demo_catalog`,
  `_cite_skyline_map` 82 l., `_brumeval_cemetery_map` 66 l., `_valbois_*`) ;
  `game_data.gd:3674-3685` (groupe de playtest) + `:466` `_create_seed_characters` (65 l.) +
  `:964` `_get_builtin_investigation_bots` (64 l.) + `:1924` `start_valbois_party_session` (69 l.)
  → **271 l.** Le catalogue démo est aussi verrouillé par `cite_demo_catalog_test`.
- **Style UI inline** : `scenario_editor.gd` 12 fonctions de style (399 l.), 5 `StyleBoxFlat.new()`,
  **92** `add_theme_*_override`. Le patron correct existe déjà : `session/session_style.gd` (188 l.,
  « aucun panneau ne code en dur une couleur ») et `theme/cartographer_theme.gd`.

## 4. Code mort / quasi-mort

### 4.1 `core/` : 1 925 l. mortes ou quasi-mortes (72 % du dossier)

| Module | Lignes | Références réelles | Verdict |
|---|---:|---|---|
| `core/persistence/json_store.gd` | 42 | 4 repositories de `core/` | **mort** (aucun appelant hors `core/`) |
| `core/persistence/scenario_repository.gd` | 118 | aucune | **mort** |
| `core/persistence/bot_repository.gd` | 104 | aucune | **mort** |
| `core/persistence/save_game_repository.gd` | 101 | aucune | **mort** |
| `core/persistence/character_repository.gd` | 94 | aucune | **mort** |
| `core/session/session_state.gd` | 98 | aucune | **mort** |
| `core/session/inventory.gd` | 98 | aucune | **mort** |
| `core/session/turn_manager.gd` | 65 | `session_state.gd` (mort) | **mort** |
| `core/navigation/semantic_move.gd` | 126 | aucune | **mort** (doublon de `game_data.gd:3960-4492`) |
| `core/navigation/investigation.gd` | 95 | aucune (`character_editor.gd:225` = chaîne UI) | **mort** (clé divergente) |
| `core/maps/map_fog.gd` | 83 | aucune | **mort** (clé divergente) |
| `core/rules/ruleset.gd` | 288 | `tests/ruleset_test.gd` seulement | **quasi-mort** (test-only) |
| `core/rules/formula.gd` | 560 | `ruleset.gd` + `ruleset_test.gd` | **quasi-mort** (test-only) |
| `core/rules/stats.gd` | 33 | aucune | **mort** |
| `core/rules/dice.gd` | 20 | aucune (GameData précharge `dice_engine` en direct) | **mort** (façade orpheline) |
| `core/rules/dice_engine.gd` | 610 | `game_data.gd:23/4576/4579`, `dice_engine_test` | **vivant** |
| `core/los/visibility_polygon.gd` | 144 | `maps/map_vision.gd:20`, `visibility_polygon_test` | **vivant** |

Méthode : recherche du nom de fichier, du chemin `res://` et du `class_name` dans tous les
`.gd/.tscn/.tres/.cfg/project.godot` (388 scripts) ; aucun chargement dynamique par chaîne construite
détecté (`load`/`preload` à argument littéral uniquement). ⚠️ **Décision requise** : ces modules ne
sont pas seulement inutilisés, ils sont **périmés** — « rebrancher » coûte plus cher que réécrire
(→ §7, B3).

### 4.2 Modules morts de l'éditeur cités par `docs/REFACTOR_EDITEUR.md:70-71` — confirmés

`maps/editor/editor_input_handler.gd` (222 l.), `editor_tool_handlers.gd` (174 l.),
`editor_view_controller.gd` (117 l.), `editor_save_controller.gd` (111 l.) : **0 référence**
chacun (aucun `preload`, aucun `class_name`) → **624 lignes mortes**, à recouper avec
`AUDIT_EDITEUR_CARTE.md`.

### 4.3 Autres candidats et dérive documentaire

- `maps/simple/simple_tileset.gd` (417 l.) et `scripts/screenshot_boot.gd` (39 l.) : aucune
  référence — déjà listés par `INVENTAIRE_TECHNIQUE.md:99-100`.
- `tests/zz_probe_grid.gd` (19 l.) : sonde de debug dans `tests/`, sans `:PASS` → **FAIL** garanti
  par le runner (§5.4).
- `game_data.gd:3654-3661` : le commentaire décrit `transition_map_edge` mais précède
  `start_world_playtest()` (l. 3662) ; la vraie fonction est en `:3722`.

## 5. Cartographie des tests

178 scripts dans `game/scripts/tests/` (**32 479 l.**, 28 % de tout le GDScript). `run_tests.ps1`
en exécute **121** en headless : 44 `*_shot_test.gd` + 13 fichiers contenant `save_png(` sont
écartés (`:46-51`) ; le runner exige `PASS`/`ALL_OK=true` dans la sortie (`:98-100`).

| Module du périmètre | Tests de protection existants | Verdict |
|---|---|---|
| **50 scènes** (session, scenario_editor, map_workspace, tous les panneaux) | `scene_load_test.gd` : charge + instancie 50 `.tscn` | **filet global**, à lancer à chaque phase |
| `QuestNavigation` | `quest_navigation_test.gd` (299 l.) : normalisation, transitions, layout, validation | solide |
| `scenario_editor.gd` | `scenario_editor_test.gd` (538 l.), `scenario_graph_links_test.gd` (327 l.), `scenario_graph_routing_test.gd` (661 l.), 3 `*_shot_test` | solide (via la scène) |
| `graph_link_overlay.gd` | `scenario_graph_routing_test` (A*, non-recouvrement, perf) + links test | **très bon** (critères numériques) |
| `WorldNavigation` | `world_navigation_test.gd` (143 l.), `world_edge_session_test.gd` | bon |
| `GameData` (modèle de session / tours) | `session_model_test.gd` (233 l.), `session_turn_test`, `session_story_log_test` | bon sur ces blocs |
| `GameData` (dés) | `dice_engine_test.gd` (178 l.) sur `core/rules/dice_engine` | indirect : `GameData.roll_dice` non testé |
| `MapData` | `cite_demo_catalog_test.gd` (164 l.) + ~45 tests `map_*` | bon en surface, pas de test du CRUD |
| `MultiplayerManager` | `session_protocol_test.gd` (128 l.), `webrtc_stun_test`, `session_turn_test` | partiel (pas de mock du pooling) |
| `AppSettings` | `map_editor_parametres_test.gd` (341 l.), `keyboard_nav_test` | indirect |
| `map_workspace.gd` | `session_monde_shot_test`, `session_move_tool_test`, `session_procedural_wall_block_test`, `scene_load_test` | **aucun test unitaire** |
| `interactive_map.gd` | `session_drag_move_test.gd` (174 l.), `session_map_input_test`, `zoom_to_cursor_test` | partiel |

**Trous à combler en phase 0** : `SessionViewModel` = **0 test** (cible n°9 et passage obligé de la
cible 6) · `core/session/*` = 0 test (cohérent avec leur statut mort, mais interdit de les
« rebrancher » sans filet) · `game_data.gd` (4 586 l.) n'a **aucun test unitaire direct** → toute
extraction exige des tests de caractérisation *avant* déplacement.

**Anomalies du runner** : `tests/zz_probe_grid.gd` est exécuté mais n'imprime jamais `PASS` → rouge
artificiel garanti (`:104`, « pas de PASS ») · `session_layout_check.gd` et `token_cutout_debug.gd`
ne sont pas des tests (exclus par le filtre `save_png`) · `valbois_diorama_setup.gd` imprime `:PASS`
donc passe, mais n'est pas un test · `npm run typecheck` **échoue** (5 erreurs TS, cf.
`docs/refactor/logs/server_typecheck_20261117_1925.log`) : la baseline ne peut pas être verte côté
serveur en l'état (→ `AUDIT_SERVEUR.md`).

## 6. Top 10 des cibles de refactor

Effort : S ≤ 0,5 j · M = 1-2 j · L = 3-5 j · XL > 5 j. Estimations de lignes issues du §1.2.

### Cible 1 — `core/` : purger ou réécrire (1 925 l. de code mort)

- **Problème** : 72 % de `core/` n'est jamais exécuté et travaille sur un modèle périmé ; la règle
  « `core/` pur » est décorative.
- **Extraction proposée** : décision binaire par module. Recommandation : **supprimer**
  `core/persistence/**` (5 fichiers, 459 l.), `core/session/**` (3, 261 l.), `core/maps/map_fog.gd`
  (83), `core/navigation/investigation.gd` (95), `core/navigation/semantic_move.gd` (126),
  `core/rules/stats.gd` (33), `core/rules/dice.gd` (20) → **−1 077 l.** ; **conserver**
  `dice_engine.gd` + `visibility_polygon.gd` ; garder `ruleset.gd` + `formula.gd` (288 + 560 l.)
  seulement jusqu'à la phase « contrat ruleset », sinon supprimer avec `ruleset_test.gd`.
- **Risque / tests / effort** : risque **faible** (code non exécuté ; vérifier chaque suppression via
  `git grep -n "class_name <X>"`) ; filet `scene_load_test`, `dice_engine_test`, `ruleset_test` ;
  **M**.

### Cible 2 — `game_data.gd` → façade + modules `core/` (4 586 l., 12 responsabilités)

- **Problème** : 95 couplages à `MapData`, 19 au réseau, 6 changements de scène, 88 % des fonctions
  portent de la logique (aucun test unitaire direct).
- **Extraction proposée** (lots indépendants ≤ 400 l.) : `core/persistence/game_storage.gd` (~120 l.,
  save/load + normalisations) · `core/session/session_model.gd` (~390 l. : barres, aura, journal,
  tour, quickbar — réutilise `data/schemas/session_model.json`) · `core/session/turn_flow.gd`
  (~150 l.) · `core/session/inventory_rules.gd` (~120 l.) · `core/maps/fog_vision.gd` (~587 l.,
  découpé en `fog_state.gd` + `los.gd`) · `core/maps/investigation_clues.gd` (~130 l.) ·
  `core/navigation/semantic_move.gd` (~533 l., réécrit sur le vrai modèle) ·
  `core/navigation/scale_navigation.gd` (~459 l.) · `core/party/roster.gd` (~271 l. + données dans
  `game/data/`). Façade cible : **≤ 400 l.** de délégations.
- **Risque / tests / effort** : risque **élevé** (traverse toute l'UI et les tests de scène) ; filet
  `session_model_test`, `quest_navigation_test`, `session_turn_test`, `session_story_log_test`,
  `scene_load_test` + ~40 tests utilisant l'autoload ; **créer d'abord**
  `game_data_contract_test.gd` ; effort **XL** (4-6 PR, une par lot).

### Cible 3 — `map_data.gd` : sortir l'image, le schéma et la démo (2 287 l.)

- **Problème** : un autoload catalogue contient ~420 l. de traitement d'image par pixel
  (`_fill_cutout_interior_holes` 62 l. `:1200`, `_knockout_edge_background` 64 l. `:1262`,
  `make_procedural_night_image` `:726`), 95 l. de normaliseur de schéma et 484 l. de cartes en
  littéraux.
- **Extraction proposée** : `core/image/portrait_cutout.gd` (~300 l.) + `night_texture.gd` (~80 l.)
  + `thumbnail.gd` (~60 l.) · `game/data/demo_maps/*.json` (ou `core/maps/demo_catalog.gd`, 484 l.
  déplacées) · `core/maps/map_schema.gd` (`ensure_map_schema` + `ensure_play_defaults`, ~110 l.) ;
  reste CRUD + helpers tuiles ~800 l. → autoload cible **≤ 900 l.**
- **Risque / tests / effort** : risque **moyen** (parité démo exigée par `cite_demo_catalog_test`,
  cache de cutout) ; filet `cite_demo_catalog_test`, `cite_eau_test`, ~45 tests `map_*`,
  `scene_load_test` ; **L** (image d'abord, testable isolément).

### Cible 4 — `scenario_editor.gd` (3 204 l., 168 fonctions)

- **Problème** : contrôleur + 399 l. de style + graphe + transitions + docks + palette.
- **Extraction proposée** : `scenario_editor/scenario_editor_style.gd` (patron `session_style.gd`,
  ~399 l.) · `scenario_editor/graph_controller.gd` (~700 l. : nœuds, liens, zoom, positions) ·
  `scenario_editor/transitions_panel.gd` (~350 l., l. 1836-2138) · `scenario_editor/
  scene_inspector.gd` (~330 l., l. 1615-1815) · `scenario_editor/dock_history.gd` (~350 l.,
  l. 969-1155 + 2743-2845) → contrôleur cible **≤ 800 l.**
- **Risque / tests / effort** : risque **moyen** (signaux `GraphEdit`, chemins de nœuds `%Unique`
  fragiles) ; filet `scenario_editor_test`, `scenario_graph_links_test`,
  `scenario_graph_routing_test`, `scenario_editor_refonte_shot_test`, `editor_views_test`,
  `command_palette_test`, `scene_load_test` ; **XL** (style d'abord).

### Cible 5 — `graph_link_overlay.gd` : extraire le routeur pur (1 848 l.)

- **Problème** : ~450 l. d'A* + grille + simplification + occupancy noyées dans un `Control` qui
  dessine → routeur non testable isolément.
- **Extraction proposée** : `core/graph/link_router.gd` (~450 l. : `_build_route_grid`,
  `_astar_points`, `_simplify_orthogonal`, `_route_grid`, `_mark_occupancy`, `_free_cell`…) +
  `core/graph/cable_geometry.gd` (~180 l. : `_smooth_cable`, `_round_polyline`, `_detour_*`) ;
  l'overlay ne garde que dessin + couches (~600 l.).
- **Risque / tests / effort** : risque **faible-moyen** (algorithmique pur) ; filet
  `scenario_graph_routing_test.gd` (661 l. : non-recouvrement, distance aux cartes, perf ≤ 300 ms,
  statistiques A*) + `scenario_graph_links_test.gd` ; **M** — **meilleur rapport valeur/risque**.

### Cible 6 — `map_workspace.gd` : sortir le contrôleur de déplacement (1 321 l.)

- **Problème** : le panneau contient les règles de déplacement (`_cell_blocked_by_building` 52 l.
  `:837`, `_cell_has_other_token` `:904`, `_move_selected_step` `:812`) et les transitions de zone,
  plus 94 appels directs aux autoloads.
- **Extraction proposée** : `session/map_move_controller.gd` (~232 l. : mouvement, collisions, pas à
  pas) · `session/zone_transition_controller.gd` (~120 l. : résolution `WorldNavigation` + fondu) ·
  assemblage HUD/navigation/toolbar (~500 l.) **passant par `SessionViewModel`** au lieu d'appeler
  `GameData` en direct.
- **Risque / tests / effort** : risque **moyen** (dépend de la cible 9, animations asynchrones) ;
  filet `session_move_tool_test`, `session_monde_shot_test`,
  `session_procedural_wall_block_test`, `session_drag_move_test`, `world_edge_session_test`,
  `scene_load_test` ; **créer** un test headless du contrôleur (aucun aujourd'hui) ; **M/L**.

### Cible 7 — `multiplayer_manager.gd` : pooling, transport, autorité (1 007 l.)

- **Problème** : 4 couches (client pooling + RPC + transports + autorité de partie) et **6 paires
  d'API dupliquées** `request_*` / `client_*` (§3.4).
- **Extraction proposée** : `multiplayer/pooling_client.gd` (~300 l. : WebSocket, `_send_request`,
  `_pending_requests`, `_expire_pending`, `POOLING_ERRORS`, tickets) ·
  `multiplayer/p2p_transport.gd` (~180 l. : ENet/WebRTC, host/client, peer events) ·
  `multiplayer/host_authority.gd` (~250 l. : start, actions, dés, tours, broadcast) · façade
  **≤ 400 l.** ; **supprimer la génération `request_*`** (6 × ~8 l. + appelants).
- **Risque / tests / effort** : risque **moyen-élevé** (peu de tests, RPC par nom de méthode) ;
  filet `session_protocol_test`, `session_turn_test`, `session_story_log_test`, `webrtc_stun_test`,
  `webrtc_pooling_e2e_test` (échoue sans serveur) ; **L** (conserver les noms de RPC en phase 1).

### Cible 8 — `interactive_map.gd` : rendu 2D vs input (1 103 l.)

- **Problème** : un `Control` qui dessine (`_draw*` ~450 l.), gère l'input/hit-test et filtre la
  visibilité ; `maps/simple/simple_map_renderer.gd:1` en **hérite** → toute retouche du rendu touche
  aussi l'éditeur simple.
- **Extraction proposée** : `maps/simple/map_cell_renderer.gd` (~450 l. : tuiles, tokens, props,
  marqueurs) · `maps/simple/map_hit_test.gd` (~150 l. : `_token_at`, `_prop_at_cell`,
  `_static_marker_at`, `_inspect_payload`) · `interactive_map.gd` garde input + zoom/pan (~350 l.) ;
  remplacer l'héritage par composition.
- **Risque / tests / effort** : risque **moyen** (parité visuelle, `user_flow_test` exclu par défaut
  donc peu de garde-fous) ; filet `session_drag_move_test`, `session_map_input_test`,
  `zoom_to_cursor_test`, `pan_cursor_tracking_test`, `simple_2d_shot_test` (hors suite) ; **M**.

### Cible 9 — `SessionViewModel` : appliquer le contrat « un seul pont » (438 l.)

- **Problème** : 29 l. de faux MJ IA dans le view-model (`:407-435`), payload de navigation dupliqué
  (`:187-219`), contrat d'écriture documenté `:295` contourné par `map_workspace`.
- **Extraction proposée** : `session/demo_narrator.gd` (~40 l., isolé et **déterministe** via RNG
  injectable) · `_build_navigation()` délégué à `get_scene_navigation_summary()` + `QuestNavigation`
  (−20 l.) · ajouter les commandes manquantes (`select_map`, `click_cell`, `move_token`,
  `enter_area`) puis convertir `map_workspace.gd` (prérequis de la cible 6).
- **Risque / tests / effort** : risque **faible** (module isolé) mais **0 test** → écrire
  `session_view_model_test.gd` (signaux émis, diff, rôle, P2P vs local) d'abord ; **S/M**.

### Cible 10 — `autoload/app_settings.gd` : 4 responsabilités dans un autoload (803 l.)

- **Problème** : valeurs + presets + application moteur + fenêtre + **keybindings** dans un seul
  autoload (51 fonctions).
- **Extraction proposée** : `core/settings/settings_store.gd` (~150 l. : valeurs, presets, save
  debounce) · `core/settings/key_bindings.gd` (~250 l. : `_ensure_action_defs`,
  `translate_key_event`, `can_use_binding`, réservés) · `core/settings/window_controller.gd`
  (~120 l. : résolution, clamp écran, mode fenêtre) ; autoload façade **≤ 250 l.**
- **Risque / tests / effort** : risque **faible** (pas d'effet réseau, rendu isolé derrière
  `register_engine`) ; filet `map_editor_parametres_test` (341 l.), `keyboard_nav_test` ; à compléter
  par un test unitaire de `key_bindings` ; **M**.

**Cibles secondaires** (à intégrer au plan) : factoriser les deux parseurs de `core/rules` en
`core/rules/expression_parser.gd` (~250 l. partagées, −250 l. ; filet `ruleset_test` +
`dice_engine_test`, risque moyen, M) · déplacer `quest_navigation.gd` + `session/world_navigation.gd`
dans `core/navigation/` (615 l., risque faible, S) et supprimer les doublons d'accès de l'éditeur
(`scenario_editor.gd:1389, 1396`) · données de démo → `game/data/` (271 + 484 l., filet
`cite_demo_catalog_test`, risque faible, M).

## 7. Ordre recommandé et points bloquants

**Séquence** — Phase 0 (filets) : `session_view_model_test.gd`, `game_data_contract_test.gd`
(caractérisation des API publiques, 30-40 assertions), test headless du contrôleur de déplacement
écrit **sur le code actuel** ; exclure `tests/zz_probe_grid.gd`. Phase 1 (sans risque) : cible 1,
cible 5, cible 9, placement `core/navigation/`. Phase 2 (UI) : cibles 4 (style d'abord), 3 (image
d'abord), 10. Phase 3 (gros morceaux) : cible 2 (par lots), 6 (après 9), 7 (après phase 2), 8
(isolable en parallèle).

**Décisions à trancher par le Lead** :

- **B1 — Baseline serveur rouge** : `npm run typecheck` échoue (5 erreurs TS). Corriger ou assumer
  avant de mesurer des progrès (→ `AUDIT_SERVEUR.md`).
- **B2 — Rouge artificiel garanti** : `tests/zz_probe_grid.gd` ne peut pas produire `PASS` → FAIL
  « pas de PASS » ; à exclure du runner ou sortir de `tests/`.
- **B3 — Politique `core/`** : *supprimer* les modules morts périmés (recommandé, −1 077 l.) ou *les
  réécrire* sur le vrai modèle. Sans ce choix, la cible 2 n'a pas de destination et la règle
  « `core/` pur » reste un trompe-l'œil.
- **B4 — Convention d'état de carte** : `mapPlayState` (production) vs `map_play` (code mort), à
  figer avant toute extraction brouillard/navigation.
- **B5 — Contrat `data/schemas`** : valider via les schémas (chargeur + validateur générique, ~200 l.)
  ou conserver les normaliseurs manuels ; sans décision, la cible 2 expédiera de la validation
  artisanale dans `core/`.
- **B6 — Arbitrage d'ordre avec `maps/`** : `maps/map_complex_editor.gd` (5 359 l.) et
  `maps/complex_map_engine_3d.gd` (4 230 l.) dominent l'inventaire global ; l'ordre de passage entre
  `maps/` et `autoload/` doit être arbitré (→ `AUDIT_EDITEUR_CARTE.md`).
- **B7 — Pas de test unitaire sur `game_data.gd`** : seule vraie dépendance d'ordonnancement — la
  cible 2 sans `game_data_contract_test.gd` préalable est un pari.

## Annexe — commandes de mesure (reproductibles)

```powershell
# Lignes physiques (convention de ce rapport) — PAS Measure-Object -Line
(Get-Content game\scripts\autoload\game_data.gd).Count

# Top god files + nombre de fonctions
Get-ChildItem game\scripts -Recurse -Filter *.gd -File | ForEach-Object {
  [pscustomobject]@{ Lines=(Get-Content $_.FullName).Count
    Funcs=(Select-String -Path $_.FullName -Pattern '^\s*(static\s+)?func\s+' -AllMatches).Count
    File=$_.FullName.Replace((Get-Location).Path+'\','') } } |
  Sort-Object Lines -Descending | Select-Object -First 25

# Usages d'un module (fichier + class_name + chemin res://)
Get-ChildItem game -Recurse -Include *.gd,*.tscn,*.tres,*.cfg,*.godot -File |
  Select-String -Pattern 'SemanticMove|semantic_move\.gd'

# Filets avant/après chaque phase (headless, sans captures)
./scripts/run_tests.ps1 -Filter 'scene_load|quest_navigation|scenario_editor|scenario_graph|session_model|world_navigation|dice_engine'
```
