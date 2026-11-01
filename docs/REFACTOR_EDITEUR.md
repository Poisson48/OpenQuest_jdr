# Refactor de l'éditeur de cartes 2.5D

## Pourquoi

`map_complex_editor.gd` concentrait le contrôleur de scène, l'UI, le dessin,
la sélection, les réglages et toute la construction. Il faisait **5 331 lignes et
227 fonctions**, difficile à naviguer et à faire évoluer sans régression.

Le refactor extrait des modules spécialisés, branchés par composition, en
conservant les wrappers/API utilisés par les tests et les signaux du moteur.

## Architecture après refactor

| Fichier | Lignes | Rôle |
|---|---:|---|
| `game/scripts/maps/map_complex_editor.gd` | **3 253** (−39 %) | contrôleur de scène, UI, signaux, réglages, wrappers fins |
| `game/scripts/maps/editor/map_editor_construction.gd` | 1 549 | toute la construction : murs, coins/jonctions, pièce, maison, toit, dallage, portes/fenêtres, clôture, chemin, escalier, mobilier, intérieurs, tracé organique, végétation, helpers AABB/snap |
| `game/scripts/maps/editor/map_editor_edit_ops.gd` | 436 | pointeurs, sélection, déplacement, duplication, poignées resize/rotate, contrainte d'axe, aperçu de drag |
| `game/scripts/maps/editor/map_editor_tool_options.gd` | 305 | options contextuelles des outils (`_rebuild_tool_options`) |

Les modules sont des `RefCounted` avec `setup(editor)` et accèdent à l'état via
`_ed` (référence dynamique), ce qui évite les dépendances circulaires de préchargement.

Modules purs déjà extraits et conservés :

- `game/scripts/maps/construction/organic_path.gd` — lissage Catmull-Rom,
  ré-échantillonnage, génération de chaîne organique.
- `game/scripts/maps/construction/organic_scatter.gd` — dispersion déterministe
  de végétation.

## Wrappers conservés

**32 wrappers fins** restent dans l'éditeur :

- 20 pour la construction (`_create_mesh_room`, `_create_mesh_roof`,
  `_create_mesh_house`, `_insert_door`, `_insert_window`, `_insert_stairs`,
  `_create_path`, `_create_mesh_fence`, helpers organiques, etc.) ;
- 11 pour l'édition (`_on_pointer_pressed`, `_on_pointer_moved`,
  `_on_pointer_released`, `_apply_handle_resize`, etc.) ;
- 1 pour les options d'outil (`_rebuild_tool_options`).

Les tests, boutons undo/redo, raccourcis et signaux `editor_pointer_*` continuent
d'appeler exactement les mêmes méthodes.

## Validation

- Parse/compile : aucune erreur de syntaxe ou de typage sur les 3 modules + l'éditeur.
- Tests requis : `map_editor_test`, `map_editor_snap_test`,
  `map_organic_creation_test`, `map_editor_library_filter_test`,
  `scene_load_test` — **PASS**.
- Suite complète : **45 tests, 44 PASS** ; seul échec connu
  `webrtc_pooling_e2e_test` (serveur LAN absent).
- Parité baseline/refactor sur les suites headless : mêmes résultats.
- Smoke `carte_25d_boot.tscn` : scène chargée, 39 boutons d'outils, 16 outils
  reconstruits, press/move/release via `MapEditorEditOps` OK.

## Limites et suite

Couplage dynamique `_ed` : une faute de frappe sur un membre de l'éditeur ne se
voit qu'à l'exécution du chemin concerné. Pour tout nouveau code, préférer
`_construction.x`, `_edit_ops.x`, `_tool_opts.x` aux wrappers.

Restent dans le contrôleur (extractions possibles plus tard) :

- bindings des réglages (~350 l.) ;
- `_refresh_ghost` (~130 l.) ;
- panneaux bibliothèque/templates inline ;
- `_unhandled_key_input` (~120 l.).

Les anciens modules morts `editor_input_handler.gd`, `editor_tool_handlers.gd`,
`editor_view_controller.gd` et `editor_save_controller.gd` n'ont pas été touchés.
