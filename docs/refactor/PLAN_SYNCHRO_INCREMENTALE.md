# Plan de synchro incrémentale de l'éditeur de cartes (phase 4 / perf)

> **Statut : design validé pour implémentation** — round 3 (2026-11-17).
> **Problème utilisateur** : « déplacer ou tourner un objet fait freezer le jeu une à deux secondes », « l'édition 3D du terrain rame ».
> **Mesures** : voir [RAPPORT_PERFORMANCE_EDITEUR_3D.md](RAPPORT_PERFORMANCE_EDITEUR_3D.md) — `configure()` complet ≈ **1,7 s par mutation** en headless (`_meshes_layer.configure` = 1 694 ms / 1 734 ms), fin de drag ≈ 2 reconstructions + panneaux ≈ **4 s**.
> **Cause racine** : toute édition propage un **snapshot complet** (`doc.to_map_data()` → `engine.configure()` → `_rebuild_layers()`), au lieu de diffs par couche.
> **Preuve de faisabilité** : un test qui mute ~150 fois le document coûtait 257 s (timeout runner) ; en supprimant la synchro 3D pendant le test, il passe en 33 s. La synchro complète est donc bien le coût dominant.

---

## 1. Objectif et critères d'acceptation

| Scénario | Aujourd'hui | Cible (ADR de perf) |
|---|---:|---:|
| Ajout/mofication d'un module 3D (clic outil) | 1 600–1 900 ms | **≤ 100 ms** |
| Fin de drag (déplacement/rotation/redimensionnement) | ≈ 2 reconstructions + panneaux ≈ 4 s | **≤ 150 ms** |
| Tampon de brosse terrain | 184–327 ms (3–9 FPS) | **≤ 16 ms** (1 frame) |
| Relâchement brosse (polish) | 1,06–2,04 s + géométrie qui change | **≤ 250 ms**, géométrie identique pendant et après le trait |
| Ouverture de la bibliothèque d'objets | 1,87–2,00 s | **≤ 150 ms** (cache vignettes) |

Critère global : **ne jamais appeler `ComplexMapEngine3D.configure()` complet en réponse à une édition** ; le `configure()` complet reste réservé au chargement de carte, au changement de style/qualité et au mode joueur.

---

## 2. Architecture cible

```
MapEditDocument ──(layers_changed: PackedStringArray)──► MapComplexEditor._on_doc_changed(reason)
                                                               │
                                                               ▼
                                               ComplexMapEngine3D.update_layers(layers, snapshot, tokens…)
                                                               │
                                     ┌───────────────┬─────────┴─────────┬───────────────┐
                                     ▼               ▼                   ▼               ▼
                            _meshes_layer.sync   _props_layer.sync   _tokens_layer…   _water/_vegetation…
                              (diff par id/asset)  (diff par id)      (rebuild ciblé)  (rebuild ciblé)
```

Règles :

1. **Le document est la seule source de données** ; il émet la liste des couches sales (`layers_changed`) en plus de `changed(reason)`.
2. **`update_layers` ne reconstruit que les couches demandées**. Les dépendances de données (ex. l'eau dépend des hauteurs de terrain) sont exprimées par une **fermeture de dépendances** (§4).
3. **`MapMeshes3D` devient diff-based** : réutilisation des nœuds dont `(id, asset)` n'a pas changé, mise à jour de la transform pour les modifiés, ajout/retrait seulement pour les différences — c'est le poste n°1 (1,69 s).
4. **Un commit = une synchro** : les mutations groupées (construction, collage, scène) passent par `_begin_bulk_edit`/`_end_bulk_edit` et accumulent leurs couches sales ; une seule `update_layers(union)` à la fin.
5. **Fallback sûr** : si la liste des couches n'est pas connue (chargement, undo/redo, meta, changement de style), on émet `["all"]` → `configure()` complet comme aujourd'hui. Aucun chemin ne peut oublier une synchro.

---

## 3. Étape a — Instrumentation et émission des couches sales (aucun changement de comportement)

1. `MapEditDocument` : ajouter `signal layers_changed(layers: PackedStringArray)`, émis par un helper `_notify(reason, layers)` qui remplace les `changed.emit(reason)` actuels (12 sites) :
   - `add`/`remove`/`modify` : couche(s) déduite(s) du `kind` de l'élément (tableau §4) ;
   - `terrain` : `["terrain"]` (fermeture → ground/water/vegetation/props) ;
   - `undo`/`redo`/`load`/`meta`/`order` : `["all"]` dans un premier temps.
2. `MapComplexEditor._on_doc_changed` : collecter les couches d'une transaction (`_pending_layers`), appeler `_sync_engine(false, layers)` au lieu de la synchro complète, avec `["all"]` temporaire pour ne rien changer.
3. Instrumenter `_rebuild_layers` : temps par couche (les 4 tops : `_meshes_layer`, `_water_layer`, `_vegetation_layer`, `_props_layer`) et exposer via `get_last_rebuild_stats()` (déjà partiel). Objectif : **preuve chiffrée** avant/après, pas d'optimisation à l'aveugle.
4. Tests : `map_editor_test`, `map_editor_snap_test`, `editor_drag_perf_test`, `map_quality_cs2_test` (aucune régression ; tous doivent rester PASS).

## 4. Table couche ↔ kind ↔ dépendances

| Kind du document (`map_edit_document`) | Couche(s) dirty | Dépend de |
|---|---|---|
| `mesh` | meshes | terrain (ancrage/AO) → inclure `ground` si carte cinéma |
| `prop` | props | terrain |
| `wall` / construction | walls (+ meshes pour portes/fenêtres) | terrain |
| `terrain` (heights/carves) | ground, water, vegetation, props, meshes-ancrage | — |
| `water` (body/lac/rivière) | water | terrain |
| `token` | tokens | — |
| `effect` | effects | — |
| `zone` | zones | — |
| `elevation` | elevations | — |
| `light` / ambiance | lights, world_env | terrain (hauteurs) |
| `note` | (overlay 2D seulement) | — |
| `link` / `area` | (overlay 2D seulement) | — |

**Fermetures** (à coder dans `CoreDirtyLayers.resolve(layers)` — module pur testable) :
`terrain → {ground, water, vegetation, props, meshes}` · `water → {water}` · `meshes → {meshes}` · `props → {props}` · `tokens → {tokens}` · `elevation → {elevations, water}` · `light → {lights, world_env}` · `["all"] → full configure`.

> ⚠️ Une couche manquante = objet fantôme jusqu'au prochain rebuild complet. La fermeture doit être testée par un **test de cohérence** : pour chaque kind, vérifier que la couche attendue est dans le résolveur (test unitaire pur, sans Godot 3D).

## 5. Étape b — `MapMeshes3D.sync()` diff-based (le gros gain)

Aujourd'hui `configure()` libère tous les enfants puis réinstancie les 114 GLB (~1,7 s). Cible :

1. Indexer les nœuds existants par `id` (`_nodes: Dictionary`).
2. Pour chaque mesh entrant : si le nœud existe et que `asset`/`variant` sont identiques → mettre à jour `transform`, `material`, visibilité, ombres seulement si nécessaire ; sinon instancier.
3. Libérer uniquement les nœuds absents du nouveau payload.
4. Conserver le budget d'ombres (`_shadow_budget_*`) et l'ancrage terrain (recalculer seulement pour les nœuds déplacés).
5. `_read_terrain(map_data)` seulement si la couche `ground` est dirty.

Tests de protection : `map_meshes_3d_test`, `map_editor_snap_test`, `map_render_quality_test`, `editor_drag_perf_test` (+ captures `map_25d_editor_shot_test` avant/après).

## 6. Étape c — dispatch par couches du moteur

`ComplexMapEngine3D.configure()` est scindé en :
- `configure(...)` (existant) = configuration globale + `_rebuild_layers()` complet (chargement/style) ;
- `update_layers(layers, map_data, tokens, party, effects, zones, fog, readonly, is_gm, view_state) =_configure_common si nécessaire + pour chaque couche demandée : `_rebuild_meshes_layer()`, `_rebuild_water_layer()`, etc. (fonctions extraites de `_rebuild_layers`).

`_rebuild_layers` devient une boucle sur toutes les couches → un seul code, deux chemins. Aucune duplication.

## 7. Étape d — chemins d'édition à brancher

| Chemin | Fichier | Comportement cible |
|---|---|---|
| Place/modify/remove d'élément (clic outil) | `map_complex_editor._on_doc_changed` | `layers` du signal → `update_layers` |
| Fin de drag (move/resize/rotate) | `map_editor_edit_ops.gd:427-448` | une seule `update_layers(["meshes"])` au release |
| Commit construction (murs, maison, pièce, route…) | `map_editor_construction._apply_scene_plan` + `_create_*` | accumulation bulk-edit + une `update_layers(union)` |
| Brosse terrain (tampon) | `map_complex_editor.gd:2605-2680` | `update_layers(["terrain"])` avec édition incrémentale de la grille (pas de resérialisation 360 k voxels) |
| Polish au relâchement | `map_ground_3d.gd:400-477`, `map_complex_editor.gd:2788-2792` | pas de changement de résolution MC ; lissage progressif |
| Panneaux (docks/labels) | `_refresh_panels` | ne pas rebuild pendant un drag (déjà géré) ; débounce 100 ms sinon |

## 8. Étape e — tests de performance et garde-fous

1. `editor_drag_perf_test` (existant) : vérifier qu'il reste vert ; le compléter d'un seuil sur le release.
2. Nouveau `editor_commit_perf_test.gd` : sur la carte démo « Cité », mesurer `_sync_engine` après (a) ajout d'un mesh, (b) modification, (c) suppression, (d) fin de drag simulée ; **seuils** : ≤ 100 ms (a/b/c), ≤ 150 ms (d) en headless. Échoue si dépassé (test de non-régression perf).
3. ✅ `map_editor_snap_test` : la synchro 3D a été RÉACTIVÉE (round 6) — le test redevient un vrai test de bout en bout avec la synchro complète : **PASS en ~75 s** (contre 257 s avant la phase 4b, pour laquelle il avait dû être suspendu).
4. Profilage ponctuel via `game/scripts/debug/perf_probe_*.gd` (déjà versionnés) pour les contre-performances (`_rebuild_layers` par couche).

## 9. Séquencement et risques

| Étape | Contenu | Risque | Tests |
|---|---|---|---|
| a | signal `layers_changed` + instrumentation + fallback `["all"]` | Faible | tous les tests éditeur |
| b | `MapMeshes3D.sync()` diff-based | Moyen (ombres, ancrage, matériaux) | `map_meshes_3d_test`, snap, captures |
| c | scinder `configure`/`_rebuild_layers` en fonctions par couche | Moyen | `map_quality_cs2_test`, captures |
| d | brancher les chemins d'édition + bulk edits | Moyen | `map_editor_test`, `map_organic_creation_test`, snap |
| e | tests de perf + réactivation synchro snap | Faible | perf tests |
| f | terrain incrémental (brosse) | **Élevé** (parité de hauteurs) | `terrain_carve_test`, `terrain_sculpt_test`, captures |

Interdits : changer une formule de hauteur pendant b-f (parité §RAPPORT) ; refactorer et optimiser dans le même commit ; dépasser un god file sans y laisser de wrapper.

## 10. Métriques de sortie

Avant/après mesurés par `docs/refactor/RAPPORT_PERFORMANCE_EDITEUR_3D.md` + les sondes versionnées : `configure()` complet doit rester ≈1,7 s mais **n'être appelé qu'au chargement** ; `update_layers(meshes)` ≤ 100 ms ; le nombre d'appels à `_rebuild_layers` par édition doit tomber à 0 ; la durée de `map_editor_snap_test` doit passer sous 60 s avec synchro active.
