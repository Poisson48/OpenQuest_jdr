# Architecture OpenQuest JDR

> **État décrit : 2026-11-17** (HEAD de départ `4514c61`, chantier de refactorisation — phases 0 et 1 livrées, phases 2-6 planifiées).
> Ce document décrit **le code réellement exécuté**, puis **la cible** du chantier. Il remplace la version précédente, qui décrivait l'architecture cible d'une branche de refactor (`refactor/st-refacto`) jamais atteinte : ses principes étaient présentés comme acquis, alors qu'ils sont des objectifs avec **écart mesuré** (§6).
>
> Preuves et feuille de route : [plan de refactorisation](refactor/PLAN_REFACTORISATION.md) · [audit client Godot](refactor/AUDIT_GODOT.md) · [audit éditeur de cartes](refactor/AUDIT_EDITEUR_CARTE.md) · [audit serveur](refactor/AUDIT_SERVEUR.md) · [inventaire technique](refactor/INVENTAIRE_TECHNIQUE.md).
> Comptage : lignes physiques (`(Get-Content <fichier>).Count`).

---

## 1. Runtime réel

Jeu desktop **Godot 4.7** (GDScript, rendu Forward+). Le multijoueur est un **hôte Godot autoritaire** : le PC du MJ calcule l'état de jeu, les dés et les actions, et diffuse aux pairs (ENet en LAN, WebRTC sinon). Le **serveur Node** ne fait que le **pooling** : salons à code 4 chiffres, tickets de reprise, rate-limit, relais de signalisation WebRTC — **aucune logique de jeu** (voir [MULTIPLAYER.md](MULTIPLAYER.md), [SESSION_PROTOCOLE.md](SESSION_PROTOCOLE.md)).

Conséquence : le moteur de jeu TypeScript (`game_session`, `bots`, `ai-gm`, `narrative/*`, `mcp/*`…) et le serveur MCP/MJ IA sont **archivés** dans [`server/legacy/`](../server/legacy/README.md), hors compilation et hors imports (décision **ADR-001** du plan). `docs/MCP.md` et `docs/STACK.md` portent un bandeau d'obsolescence.

---

## 2. Arborescence réelle

```
OpenQuest_jdr/
├── game/                               # Client Godot 4.7
│   ├── scripts/
│   │   ├── autoload/                   # GameData, MapData, AppSettings, ThemeColors, UiLayout, LocaleSettings, ButtonSizing
│   │   ├── core/                       # Modules purs : rules/{dice_engine,formula,ruleset}, los/visibility_polygon
│   │   ├── session/                    # session_shell, session_view_model, session_style, world_navigation + panels/*
│   │   ├── scenario_editor/            # panels/* de l'éditeur de scénario (graph_link_overlay, editor_views, …)
│   │   ├── maps/                       # Éditeur + moteur de cartes 3D
│   │   │   ├── editor/                 # document (pur), construction, edit_ops, tool_options, panneaux
│   │   │   ├── map_layers/             # couches 3D : ground, water, meshes, props, tokens, fog, lights, …
│   │   │   ├── terrain/                # terrain_carve_field (champ de terrain pur)
│   │   │   ├── construction/           # procédural : cité, ponts, clôtures, chemins…
│   │   │   ├── world/                  # monde de zones / liens de bords
│   │   │   └── simple/                 # éditeur 2D simple
│   │   ├── multiplayer/                # multiplayer_manager (pooling + transports + autorité hôte), webrtc_p2p
│   │   ├── hub/ · ui/ · shared/ · theme/ · debug/ · tests/
│   │   └── …                           # racine : main_menu, hub, scenario_editor, quest_navigation, interactive_map…
│   ├── data/                           # scénarios, cartes, bots, cas de dés partagés
│   └── assets/ · scenes/
├── server/                             # Node/TS — pooling uniquement
│   ├── src/                            # index, pooling/, lobby/, game_types, party_utils (dés TS archivés en phase 5.2)
│   └── legacy/                         # moteur de jeu TS + MCP archivés (non compilés, non importés)
├── data/schemas/                       # 8 schémas JSON : contrat CIBLE, lu par aucun code aujourd'hui (§5)
├── tools/refactor/                     # verify.ps1, metrics.ps1, fast-tests.txt
├── scripts/                            # play-godot*.ps1, run_tests.ps1, setup
└── docs/                               # ARCHITECTURE, MULTIPLAYER, STACK (historique), refactor/, archive/…
```

---

## 3. Dépendances réelles

```
UI / scènes (session_shell, map_complex_editor, scenario_editor, hub, panneaux…)
        │  lit via SessionViewModel (signal active_game_updated)
        │  … mais aussi appels directs aux autoloads (violation mesurée : map_workspace 94 refs)
        ▼
Autoloads : GameData (4 586 l., domaine + persistance + état de session + réseau)
            MapData (2 287 l., catalogue + images + démo) · AppSettings (803 l.) · MultiplayerManager (1 007 l.)
        │                     │                          │
        │                     │                          └─► pooling WebSocket + transports P2P (hôte autoritaire)
        ▼                     ▼
core/rules/dice_engine (610 l., vivant)     data/schemas/ : contrat cible, non branché
core/los/visibility_polygon (144 l., vivant)         ✗ aucun validateur (client ni serveur)
core/rules/formula+ruleset (848 l., consommés par les tests / validation de ruleset)

quest_navigation.gd (464 l., pur, statique) ◄── GameData, scenario_editor
session/world_navigation.gd (151 l., pur)   ◄── session, transitions de bord de carte
server/src/pooling (487 l.) : seule chaîne serveur exécutée ; types partagés game_types/party_utils
server/legacy/ : archivé, hors compilation
```

---

## 4. Modules actifs (état mesuré)

| Couche | Module | Lignes | Rôle réel |
|---|---|---:|---|
| **Autoloads** | `autoload/game_data.gd` | 4 586 | Domaine, persistance JSON, modèle de session, brouillard/LOS, navigation multi-échelles, déplacement sémantique, dés, 19 appels réseau, 6 changements de scène |
| | `autoload/map_data.gd` | 2 287 | Catalogue de cartes, pipeline image, normaliseur de schéma, cartes de démo |
| | `autoload/app_settings.gd` | 803 | Réglages, fenêtre, keybindings, presets |
| | `theme_colors` · `ui_layout` · `locale_settings` · `button_sizing` | 94 · 91 · 47 · 37 | Petits autoloads UI |
| **Règles (`core/`, pur)** | `core/rules/dice_engine.gd` | 610 | **Moteur de dés exécuté** (GameData, MultiplayerManager) — seul moteur exécutable après ADR-005 |
| | `core/rules/formula.gd` + `ruleset.gd` | 560 + 288 | Formules de fiches et validation de rulesets ; consommés par `ruleset_test` (quasi test-only, à trancher en phase 2/5) |
| | `core/los/visibility_polygon.gd` | 144 | Polygone de visibilité (LOS), consommé par `maps/map_vision.gd` |
| **Navigation** | `quest_navigation.gd` | 464 | 21 fonctions statiques pures : scènes, transitions, layout, validation (GameData + éditeur) |
| | `session/world_navigation.gd` | 151 | Liens de bords / transitions entre zones d'un monde |
| **Session** | `session/session_view_model.gd` | 438 | Pont état → UI : signaux de diff, un seul abonné à `GameData.active_game_updated` |
| | `session/session_shell.gd` · `session_style.gd` | 534 · 188 | Assemblage de la session MJ ; palette/conventions de style (aucune couleur en dur) |
| | `session/panels/*` | — | Panneaux : `fog_overlay`, `map_workspace` (1 321 l.), `map_stage`, `gm_console`, `story_log`, `dice_tray`, `party_dock`, `session_header`, `map_navigator`, `map_toolbar`… |
| **Éditeur de scénario** | `scenario_editor.gd` | 3 204 | Contrôleur de scène (graphe, transitions, style inline, docks, palette) |
| | `scenario_editor/panels/*` | — | `graph_link_overlay` 1 848, `editor_views` 704, `command_palette` 460, `editor_minimap` 451, `editor_backdrop`, `graph_node`, `npc_row`, `transition_row` |
| **Éditeur de cartes** | `maps/map_complex_editor.gd` | 5 359 | Contrôleur de l'éditeur 3D (UI, outils, palettes, raccourcis, wrappers) |
| | `maps/editor/map_edit_document.gd` | 2 623 | **Document pur `RefCounted`** : éléments, terrain, brouillard, liens, undo/redo par deltas |
| | `maps/editor/map_editor_construction.gd` | 2 679 | Construction : murs, pièces, toits, ouvertures, clôtures, chemins, mobilier, scènes procédurales |
| | `maps/editor/map_editor_edit_ops.gd` · `tool_options` | 660 · 1 018 | Pointeurs/drag/poignées · options contextuelles des outils |
| | `maps/editor/map_editor_parametres.gd` · `world_panel` · `inspector` · `overlay` | 2 131 · 1 487 · 1 000 · 861 | Panneaux de l'éditeur |
| | `maps/complex_map_engine_3d.gd` | 4 230 | Moteur de rendu 3D (SubViewport, caméra, lumière, couches, tokens, table) |
| | `maps/map_layers/*` | — | Couches : `ground` 2 303, `water` 2 235, `meshes` 1 512, `props`, `token`, `grid`, `fog`, `lights`, `vegetation`, `walls`, `zone`, `elevations`, `ambient_fx`, `backdrop`, `table_*` |
| | `maps/terrain/terrain_carve_field.gd` | 1 364 | Champ de terrain pur (SDF, 20 brosses, sampling, raycast) |
| | `maps/construction/procedural_city.gd` | 1 611 | Générateur pur partagé éditeur/démo — **contre-exemple à suivre** : long mais responsabilité unique, à ne pas découper |
| **Multijoueur** | `multiplayer/multiplayer_manager.gd` | 1 007 | Client pooling (req_id, timeouts), transports ENet/WebRTC, cycle des salons, **autorité hôte**, deux générations d'API `request_*`/`client_*` |
| | `multiplayer/webrtc_p2p.gd` | 214 | Couche P2P WebRTC |
| **Cartes 2D** | `interactive_map.gd` | 1 103 | Rendu 2D, input/hit-test, filtrage de visibilité ; classe mère de `maps/simple_map_renderer.gd` |
| **Tests** | `tests/*` | 178 scripts | Suite headless (32 479 l.), voir [baseline](refactor/BASELINE_TESTS.md) |

> **Code mort retiré (ne pas réintroduire)** — phase 0 : `maps/complex_map_engine.gd` (moteur 2D legacy, 510 l.) et `maps/map_layers/map_elevation_layer.gd` (64 l.), tous deux cassés et sans référence. Phase 1 (ADR-002) : `core/persistence/**`, `core/session/**`, `core/maps/**`, `core/navigation/{investigation,semantic_move}.gd`, `core/rules/{stats,dice}.gd` ; 4 modules d'éditeur morts (`editor_input_handler`, `editor_tool_handlers`, `editor_view_controller`, `editor_save_controller`), 6 scripts legacy de `maps/` (`map_token_node`, `map_lighting_layer`, `map_zone_node`, `map_effect_instance`, `map_fog_layer`, `map_grid_layer`), `simple_tileset.gd` et la sonde `tests/zz_probe_grid.gd`. Aucun n'avait de référence externe ; chaque suppression est vérifiée par `verify.ps1 -Scenes` (scènes incluses) et `git grep` avant le commit de la phase.

---

## 5. Contrat de données (état réel)

- **`data/schemas/` = contrat cible, branché en partie seulement** : 8 schémas (`character`, `scenario`, `map`, `bot`, `ruleset`, `dice_roll`, `session_model`, `save_game`). Depuis la phase 5.3, le validateur [`tools/refactor/validate_data.py`](../tools/refactor/validate_data.py) est outillé et branché en porte (CI + `verify.ps1`) sur les 2 schémas conformes (`bot`, `ruleset`) ; les 2 schémas avec données mais en dérive (`scenario`, `map`) sont mesurés de façon informative ([RAPPORT_SCHEMAS.md](refactor/RAPPORT_SCHEMAS.md)) et les 4 sans données versionnées sont non couverts. Décision et critères de sortie : [ADR-004-schemas.md](refactor/ADR-004-schemas.md). Le client, lui, continue de valider par des **normaliseurs manuels** (`map_data.gd` `ensure_map_schema()`, `game_data.gd` `normalize_character()`, `quest_navigation.gd` `normalize_scenario()`, etc.).
- **Convention d'état de carte** : `mapPlayState` (camelCase), figée par **ADR-003**. L'ancienne clé `map_play` du code mort est proscrite.
- **Cas de dés partagés** : `game/data/tests/dice_cases.json` (29 cas) est la spécification exécutée par `dice_engine_test.gd` ; `data/schemas/dice_roll.json` décrit le résultat.

---

## 6. Écart mesuré aux principes (ce sont des cibles)

| Principe (cible) | Cible | Écart mesuré (2026-11-17) | Traitement |
|---|---|---|---|
| **`core/` pur** (aucun Node/autoload) | 100 % exécuté | Respecté mécaniquement (0 `extends Node`/autoload dans `core/`), mais 72 % du dossier était du code mort/périmé sur un modèle divergent (`map_play`) | Purge phase 1 (ADR-002) : `core/` = `dice_engine`, `formula`, `ruleset`, `visibility_polygon` uniquement |
| **Un seul contrat `data/schemas/`** | Validation branchée | 8 schémas, 0 validateur ; validation réécrite à la main et dispersée | ADR-004, validateur en phase 5 |
| **Les autoloads délèguent** | Façades ≤ 400 l. | `game_data.gd` : 293 fonctions, 12 % font ≤ 4 lignes ; 95 refs `MapData`, 19 réseau, 6 `change_scene` ; `map_data.gd` 2 287 l. | Lots en phase 2 ([cible 2](refactor/AUDIT_GODOT.md)) |
| **Fichiers < 400 lignes** | 0 fichier > 400 l. | 20 fichiers `.gd` > 1 000 l. ; les 7 plus gros du périmètre audité concentrent 56 % de ses lignes (18 fichiers > 400 l. = 77 %) | Phases 2 à 4 ; frontière de propriété ADR-009 |
| **Signaux `SessionViewModel`** | Un seul pont, aucune écriture directe | Lecture tenue (1 abonné) ; écriture contournée : `map_workspace.gd` = 94 références aux autoloads, 11 mutations | Phase 2.7 |
| **Contrôleur ≤ 1 000 l.** | Contrôleur final borné | `map_complex_editor.gd` 3 253 → **5 359 l.** après regonflement ; `scenario_editor.gd` 3 204 l. | Phases 3 et 4 (vagues) |

---

## 7. Serveur (état réel)

- **Seule chaîne exécutée** : `server/src/index.ts` → `startPoolingServer` (`pooling/server.ts`, 487 l.) : salons, tickets, rate-limit, relais `signal` WebRTC. Types partagés : `game_types.ts`, `party_utils.ts`, `lobby/*`. Contrat de protocole v2 gelé par `server/scripts/test_lobby_protocol.ts` ([MULTIPLAYER.md §3.3](MULTIPLAYER.md)).
- **Moteur de dés** : l'unique implémentation exécutable est GDScript (`game/scripts/core/rules/dice_engine.gd`, ADR-005) ; la chaîne TypeScript (`dice.ts`, `rules/dice_engine.ts`, `scripts/test_dice_engine.ts`) est **archivée dans `server/legacy/`** depuis la phase 5.2 — plus compilée, plus testée, plus atteignable.
- **`server/legacy/`** : 16 fichiers archivés — 13 en phase 0 (moteur narratif, `game_session`, `bots`, MCP) + 3 dès la phase 5.2 (moteur de dés TS et son test) — hors `tsconfig` et hors imports ; procédure de restauration dans [`server/legacy/README.md`](../server/legacy/README.md).
- `npm run typecheck`, `npm run build` et `npm test` sont **verts** depuis la phase 0 (`tsconfig` : `noEmitOnError`, `ws`/`dotenv` en dépendances). `npm test` couvre le pooling : `test:lobby` (81 vérif.) + `test:protocol` (contrat v2, 302 vérif. au 2026-11-17) + `test:lobby:net` (18 vérif.).
- **CI GitHub Actions** (`.github/workflows/tests.yml`, phase 6.1) : 3 jobs — serveur (typecheck/build/tests), Godot (compilation + scènes + socle rapide) et contrat `data/schemas` (gate `bot`+`ruleset`, dérive complète informative). La porte locale `tools/refactor/verify.ps1` reste la vérification de chaque commit (ADR-008).

---

## 8. Cible et trajectoire

Le plan fait foi : [PLAN_REFACTORISATION.md](refactor/PLAN_REFACTORISATION.md). En résumé :

1. **Phase 1** — purge du code mort (−2 639 lignes en phase 1, −3 276 au total avec la phase 0), `verify.ps1` vert.
2. **Phase 2** — contrats de test puis découpage de `game_data.gd`, `map_data.gd`, `map_workspace.gd`, `SessionViewModel`.
3. **Phase 3** — éditeur de scénario : routeur de liens pur dans `core/graph/`, `scenario_editor.gd` ≤ 800 l.
4. **Phase 4** — éditeur de cartes en 5 vagues : document/terrain/options → couches 3D → construction/moteur → contrôleur ≤ 1 000 l. → nettoyage.
5. **Phase 5** — serveur et contrat de données : un seul moteur de dés ✅ (ADR-005) ; validateur `data/schemas/` outillé et branché en gate sur `bot`/`ruleset` ; réalignement `scenario`/`map` et arbitrage des 4 schémas sans données selon [ADR-004-schemas.md](refactor/ADR-004-schemas.md).
6. **Phase 6** — CI ✅, consolidation documentaire, métriques finales.

Objectifs chiffrés (plan §9) : 0 fichier `.gd` > 1 000 lignes, `game_data.gd` ≤ 400 l. en façade, `map_complex_editor.gd` ≤ 1 000 l., `complex_map_engine_3d.gd` ≤ 700 l., `scenario_editor.gd` ≤ 800 l., une seule implémentation de dés, build serveur vert, CI active.

---

## 9. Documents liés

| Sujet | Document |
|---|---|
| Plan, ADR, phases, règles, métriques cibles | [refactor/PLAN_REFACTORISATION.md](refactor/PLAN_REFACTORISATION.md) |
| Audits (client, éditeur, serveur) · inventaire · baseline | [refactor/](refactor/README.md) |
| Multijoueur (P2P, pooling, protocole) | [MULTIPLAYER.md](MULTIPLAYER.md) · [SESSION_PROTOCOLE.md](SESSION_PROTOCOLE.md) |
| Éditeur de cartes (guide, patron de refactor) | [MAP_EDITOR.md](MAP_EDITOR.md) · [GUIDE_CARTE_25D.md](GUIDE_CARTE_25D.md) · [REFACTOR_EDITEUR.md](REFACTOR_EDITEUR.md) |
| Scénarios non linéaires | [QUEST_NAVIGATION.md](QUEST_NAVIGATION.md) · [MODELE_SESSION.md](MODELE_SESSION.md) |
| Serveur : historique et archive | [STACK.md](STACK.md) · [`server/legacy/README.md`](../server/legacy/README.md) |
