# Refactor de l'éditeur de cartes 2.5D

> **Bandeau (2026-11-17) — document historique.** Ce texte décrit le **refactor de septembre 2026**, alors réussi : `map_complex_editor.gd` était passé de 5 331 à 3 253 lignes, et le patron « modules + wrappers » qu'il décrit reste la règle de travail. **Les compteurs ont été dépassés depuis** (tableau ci-dessous, colonne 2026-11-17) et les modules morts cités en fin de document ont été confirmés sans référence par l'audit puis supprimés en phase 1.
> **Refactor suivant** : [PLAN_REFACTORISATION.md](refactor/PLAN_REFACTORISATION.md), **phase 4 « Éditeur de cartes 2.5D »** (5 vagues V1 à V5). Audit et plans d'extraction par fichier : [AUDIT_EDITEUR_CARTE.md](refactor/AUDIT_EDITEUR_CARTE.md). État du chantier : [refactor/README.md](refactor/README.md).

## Pourquoi

`map_complex_editor.gd` concentrait le contrôleur de scène, l'UI, le dessin,
la sélection, les réglages et toute la construction. Il faisait **5 331 lignes et
227 fonctions**, difficile à naviguer et à faire évoluer sans régression.

Le refactor extrait des modules spécialisés, branchés par composition, en
conservant les wrappers/API utilisés par les tests et les signaux du moteur.

## Architecture après refactor

| Fichier | Lignes après refactor (2026-09) | Lignes au 2026-11-17 | Rôle |
|---|---:|---:|---|
| `game/scripts/maps/map_complex_editor.gd` | **3 253** (−39 %) | **5 359** (+65 % depuis) | contrôleur de scène, UI, signaux, réglages, wrappers fins |
| `game/scripts/maps/editor/map_editor_construction.gd` | 1 549 | 2 679 | toute la construction : murs, coins/jonctions, pièce, maison, toit, dallage, portes/fenêtres, clôture, chemin, escalier, mobilier, intérieurs, tracé organique, végétation, helpers AABB/snap |
| `game/scripts/maps/editor/map_editor_edit_ops.gd` | 436 | 660 | pointeurs, sélection, déplacement, duplication, poignées resize/rotate, contrainte d'axe, aperçu de drag |
| `game/scripts/maps/editor/map_editor_tool_options.gd` | 305 | **1 018** (une seule fonction `_rebuild_tool_options` de **806 l.**) | options contextuelles des outils |

Le regonflement n'est pas un échec du refactor de septembre : c'est la preuve qu'**extraire ne suffit pas sans frontière de propriété** (ADR-009 du plan). Un module extrait peut être réinvesti et regrossir ; l'audit de 2026-11-17 mesure le phénomène (50 tests atteignent 169 membres du contrôleur, dont 153 privés).

Les modules sont des `RefCounted` avec `setup(editor)` et accèdent à l'état via
`_ed` (référence dynamique), ce qui évite les dépendances circulaires de préchargement.

Modules purs déjà extraits et conservés :

- `game/scripts/maps/construction/organic_path.gd` — lissage Catmull-Rom,
  ré-échantillonnage, génération de chaîne organique.
- `game/scripts/maps/construction/organic_scatter.gd` — dispersion déterministe
  de végétation.

## Wrappers conservés

**32 wrappers fins** restaient dans l'éditeur au moment du refactor :

- 20 pour la construction (`_create_mesh_room`, `_create_mesh_roof`,
  `_create_mesh_house`, `_insert_door`, `_insert_window`, `_insert_stairs`,
  `_create_path`, `_create_mesh_fence`, helpers organiques, etc.) ;
- 11 pour l'édition (`_on_pointer_pressed`, `_on_pointer_moved`,
  `_on_pointer_released`, `_apply_handle_resize`, etc.) ;
- 1 pour les options d'outil (`_rebuild_tool_options`).

Les tests, boutons undo/redo, raccourcis et signaux `editor_pointer_*` continuent
d'appeler exactement les mêmes méthodes. Cette contrainte est reprise telle quelle
par le plan (phase 4 : « wrappers d'abord », noms privés gelés — ADR-006).

## Validation (résultats de septembre 2026)

- Parse/compile : aucune erreur de syntaxe ou de typage sur les 3 modules + l'éditeur.
- Tests requis : `map_editor_test`, `map_editor_snap_test`,
  `map_organic_creation_test`, `map_editor_library_filter_test`,
  `scene_load_test` — **PASS**.
- Suite complète : **45 tests, 44 PASS** ; seul échec connu
  `webrtc_pooling_e2e_test` (serveur LAN absent).
- Parité baseline/refactor sur les suites headless : mêmes résultats.
- Smoke `carte_25d_boot.tscn` : scène chargée, 39 boutons d'outils, 16 outils
  reconstruits, press/move/release via `MapEditorEditOps` OK.

> Ces chiffres valent pour cette étape. La référence de non-régression actuelle est
> [BASELINE_TESTS.md](refactor/BASELINE_TESTS.md) (178 tests déclarés, 121 exécutés en
> headless, échecs connus documentés).

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
`editor_view_controller.gd` et `editor_save_controller.gd` n'ont pas été touchés
par ce refactor.

> **Mise à jour 2026-11-17 — suite du chantier.**
> - Ces 4 modules morts ont été confirmés **à 0 référence** par l'audit ([§4.1](refactor/AUDIT_EDITEUR_CARTE.md)) puis **supprimés en phase 1** avec 6 autres scripts legacy et la sonde `tests/zz_probe_grid.gd`.
> - Le couplage `_ed` reste le point dur : `map_editor_tool_options.gd` atteint 508 accès `_ed.` sur 109 membres ; `map_editor_construction.gd` 469/77 ; `map_editor_edit_ops.gd` 425/59.
> - Le refactor à mener n'est plus celui des 4 modules de l'époque mais les **5 vagues du plan (phase 4)** : V1 `map_edit_document` + `terrain_carve_field` + `map_editor_tool_options` → V2 couches 3D (`water`, `ground`, `meshes`) → V3 `map_editor_construction` + `complex_map_engine_3d` → V4 `map_complex_editor` par slices (cible ≈ 900 l.) → V5 nettoyage (grille v1 masquée, palette d'environnement masquée, docs périmées).
> - Contraintes inchangées : une vague = des commits dédiés, **jamais deux god files dans le même commit**, wrappers conservés, captures avant/après pour les vagues de rendu, `tools/refactor/verify.ps1` vert avant chaque commit.
