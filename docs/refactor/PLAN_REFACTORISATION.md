# Grand plan de refactorisation — OpenQuest JDR

> **Statut : lancé le 2026-11-17** · HEAD de départ : `4514c61` (branche `feat/carte-2.5d-editeur`)
> **Portée** : client Godot 4.7 (388 scripts / 116 299 lignes au départ ; **361 scripts / 113 024 lignes après la phase 1**) + serveur Node/TypeScript (26 fichiers / 4 863 lignes au départ ; **13 fichiers / 2 539 lignes** après archivage)
> **Documents liés** : [audit client Godot](AUDIT_GODOT.md) · [audit éditeur de cartes](AUDIT_EDITEUR_CARTE.md) · [audit serveur](AUDIT_SERVEUR.md) · [baseline tests](BASELINE_TESTS.md) · [inventaire technique](INVENTAIRE_TECHNIQUE.md) · [index du chantier](README.md)

---

## 0. Synthèse en une page

### Pourquoi ce chantier

Le projet a grossi par accumulation de fonctionnalités : **20 fichiers dépassent 1 000 lignes**, les 7 plus gros concentrent **56 %** des lignes du client, `core/` n'est **vivant qu'à 28 %**, le serveur ne **compilait plus depuis deux mois** (classe `AiGM` supprimée sans migrer ses appelants) et les principes d'architecture du projet (`core/` pur, fichiers < 400 lignes, un seul contrat de données) n'étaient plus appliqués. Aucune CI ne pouvait le voir.

### Ce que la phase 0 a déjà réglé (2026-11-17)

| Livré | Preuve |
|---|---|
| **Porte de compilation** du client (391 scripts + 86 scènes) | 477 fichiers chargés en ~12 s, **0 échec** (`game/scripts/debug/compile_check.gd`) |
| **Porte de vérification unifiée** | [`verify.ps1`](../../tools/refactor/verify.ps1) : compilation + typecheck serveur + socle rapide de tests |
| **Build serveur réparé** | `npm run typecheck` et `npm run build` **verts** ; `npm test` **vert** (401 vérifications : lobby 81 + protocole 302 + intégration 18) |
| **Chaîne de jeu serveur archivée** | 13 fichiers TS morts → `server/legacy/` (hors compilation), `AiGM`/MCP documentés comme archivés |
| **6 scripts qui ne compilaient pas** | 4 réparés, 2 dead/broken supprimés (voir §6) |
| **Mesure reproductible** | [`metrics.ps1`](../../tools/refactor/metrics.ps1) → [inventaire](INVENTAIRE_TECHNIQUE.md) |
| **Baseline de tests** | [BASELINE_TESTS.md](BASELINE_TESTS.md) (référence de non-régression) |

### Ordre de marche

```
Phase 0  Filets & vert                    ✅ 2026-11-17
Phase 1  Purge du code mort               ✅ 2026-11-17  (−3 276 lignes, 27 scripts supprimés)
Phase 2  Contrats & cœur client           ✅ 2.0-2.7 livrés (+ 2.8 image) ; reste 2.8 schéma/démos
Phase 3  Éditeur de scénario              🔄 3.1-3.5 livrées (routeur, style, graphe, panneaux) : 3 204 → 1 596 l. ; slices console/méta pour ≤800
Phase 4  Éditeur de cartes 2.5D (5 vagues)🔄 4a-4d livrées : commit 1 506→45 ms, release 1 492→47 ms (×32) ; vagues d'extraction V1-V5 et 4e/4f à suivre
Phase 5  Serveur & contrat de données     ✅ 5.2-5.5 livrées (dés uniques, validateur, contrat v2, ADR-004)
Phase 6  Industrialisation & docs         🔄 6.1-6.3 livrées (CI, index docs, CONTRIBUTING) ; 6.4 métriques finales à suivre
```

---

## 1. Objectifs et non-objectifs

### Objectifs

1. **Réduire la taille et le couplage** des god files sans changer le comportement observable du jeu.
2. **Supprimer le code mort** prouvé (≈ 4 000 lignes client + 13 fichiers serveur archivés).
3. **Établir des contrats** : tests de contrat sur les API publiques, un seul moteur de dés exécutable, un contrat de données `data/schemas` réellement utilisé.
4. **Rendre la vérification rapide** (< 2 min) pour qu'elle soit réellement utilisée à chaque commit.
5. **Rendre la documentation véridique** : les docs décrivent l'état réel et la cible, pas une architecture abandonnée.

### Non-objectifs (pour ce chantier)

- Aucun changement de gameplay, d'UI ou de protocole réseau.
- Aucune nouvelle fonctionnalité (MCP/MJ IA reste archivé tant qu'une décision produit n'est pas prise).
- Pas de réécriture « big bang » : chaque lot est isolé, vérifié et réversible.
- On ne renomme pas les membres privés atteints par les tests sans mettre à jour les tests dans le **même** commit.

---

## 2. Décisions d'architecture (ADR)

| # | Décision | Justification | Réversible ? |
|---|---|---|---|
| **ADR-001** | **Architecture serveur : hôte Godot autoritaire + serveur de pooling sans logique de jeu.** La chaîne de jeu TS (`game_session`, `bots`, `ai-gm`, `narrative/*`, `mcp/*`, …) est archivée dans `server/legacy/`. | C'est le modèle réellement codé (`src/index.ts` ne démarre que le pooling ; `MULTIPLAYER.md`/`SESSION_PROTOCOLE.md` décrivent l'hôte autoritaire). Le serveur autoritaire + MCP est une direction non financée qui a pourri pendant deux mois. | Oui : `server/legacy/README.md` décrit la restauration (git history). |
| **ADR-002** | **`core/` : supprimer les modules morts et périmés, conserver les modules exécutés.** Suppression de `core/persistence/**`, `core/session/**`, `core/maps/`, `core/navigation/{investigation,semantic_move}.gd`, `core/rules/{stats,dice}.gd` (si non référencés) ; conservation de `core/rules/{dice_engine,formula,ruleset}.gd` et `core/los/visibility_polygon.gd`. | 72 % de `core/` n'est jamais exécuté et travaille sur un modèle périmé (`map_play` vs `mapPlayState`) : le « rebrancher » coûterait une réécriture complète. Le supprimer rend la règle « `core/` pur » honnête et évite d'entretenir une fausse architecture. | Oui (git revert). |
| **ADR-003** | **Convention d'état de carte figée : `mapPlayState` (camelCase).** Tout nouveau code de brouillard/vision/navigation/état de session utilise cette clé. `map_play` est proscrit. | C'est la convention de la production (`game_data.gd:1743`), contre laquelle le code mort a divergé. | Non (convention stable). |
| **ADR-004** | **`data/schemas/` reste le contrat cible**, mais n'est pas bloquant : validateur générique branché en phase 5 (gate CI bot+ruleset, dérive scenario/map informative) ; pas de migration de données ; schéma réaligné en P1 plutôt que les données. Décision complète : [ADR-004-schemas.md](ADR-004-schemas.md). | Les 8 schémas ne sont lus par aucun code et dérivent déjà ; les brancher d'un bloc introduirait des régressions massives. | Oui. |
| **ADR-005** | **Dés : une seule implémentation exécutable, le moteur GDScript** (`game/scripts/core/rules/dice_engine.gd`). Le formatage est client (BBCode Godot). `game/data/tests/dice_cases.json` + `data/schemas/dice_roll.json` sont la **spécification**. La chaîne TS de jeu (`server/src/dice.ts`, `server/src/rules/dice_engine.ts`) est archivée en phase 5, une fois ses tests migrés. | L'hôte P2P autoritaire calcule les dés (ADR-001) ; deux moteurs divergents (Markdown vs BBCode, RNG seedé non compatible) sans contrat inter-langages sont un piège. | Oui (archive, historique git). |
| **ADR-006** | **Les tests sont le contrat d'API de l'éditeur.** On gèle la liste des membres atteints par les tests (`docs/refactor/CONTRAT_EDITEUR.md`, généré) et on ajoute des tests de contrat explicites ; un membre privé ne bouge jamais sans son test dans le même commit. | 50 tests atteignent 169 membres de l'éditeur (dont 153 privés) : le contrat réel est privé et invisible. | Oui. |
| **ADR-007** | **Aucune sonde dans `game/scripts/tests/`.** Les sondes de debug vont dans `game/scripts/debug/` (hors runner) ; le runner ne doit compter que de vrais tests avec `:PASS`. | `tests/zz_probe_grid.gd` ne peut pas produire `PASS` → FAIL artificiel qui pollue la baseline et masque les vrais échecs. | Oui. |
| **ADR-008** | **La porte locale [`verify.ps1`](../../tools/refactor/verify.ps1) est obligatoire avant chaque commit du chantier** ; une CI GitHub Actions sera ajoutée en phase 6 (typecheck serveur + compilation Godot + tests rapides). | Pas de CI aujourd'hui : deux mois de build rouge invisibles. La porte locale est immédiate et suffisante pour démarrer. | Oui. |
| **ADR-009** | **Frontière de propriété : tout module extrait ne reçoit plus de nouvelle responsabilité ensuite ; tout nouveau code va dans un module de < 400 lignes.** Le contrôleur final d'un god file ne dépasse pas 1 000 lignes. | `map_complex_editor.gd` est passé de 3 253 à 5 359 lignes après un refactor réussi : sans frontière de propriété, l'extraction ne borne pas la croissance. | Non (règle de travail). |

---

## 3. Portes de qualité (gates)

| Porte | Commande | Durée cible | Couvre |
|---|---|---|---|
| Compilation client | `godot --headless --path game --scene res://scenes/debug/compile_check.tscn -- --scenes` | ~12 s | 388 scripts + 85 scènes (parse, `preload` cassés, scènes invalides) |
| Vérification complète | [`tools/refactor/verify.ps1`](../../tools/refactor/verify.ps1) | < 3 min | compilation + `tsc --noEmit` serveur + socle rapide (18 tests < 2 min) |
| Suite complète headless | [`scripts/run_tests.ps1`](../../scripts/run_tests.ps1) | 15-30 min | 178 tests déclarés, 121 exécutés en headless (57 exclusions : 44 `*_shot_test` + 13 écrivant `save_png`) |
| Captures / rendu | `scripts/run_tests.ps1 -IncludeShots` (fenêtre cachée) | variable | 57 tests `*_shot_test` — obligatoire avant tout refactor de rendu |
| Serveur | `cd server; npm run typecheck; npm run build; npm test` | ~15 s | build TS + 401 vérifications (lobby, contrat de protocole v2, intégration pooling) |
| Mesure | [`tools/refactor/metrics.ps1`](../../tools/refactor/metrics.ps1) | ~30 s | volumétrie, god files, code mort, régression de taille |

**Règle** : aucun commit du chantier sans `verify.ps1` vert ; après toute extraction d'un god file, relancer les tests du domaine (`-Filter <domaine>`) et comparer avec la [baseline](BASELINE_TESTS.md).

---

## 4. Baseline de référence

Voir [BASELINE_TESTS.md](BASELINE_TESTS.md) pour le détail complet (par test, durées, logs conservés dans `docs/refactor/logs/`).

| Mesure (commit `4514c61`, 2026-11-17) | Résultat | Durée |
|---|---|---|
| Suite Godot headless (121 tests, captures exclues) | **116 PASS / 5 FAIL / 0 SKIP** | 24 min 35 s |
| Échecs Godot (tous expliqués, aucun n'est une régression du refactor) | `map_editor_snap_test` (timeout sous charge), `map_editor_v2_palette_test` (artefact de compilation sous charge), `map_quality_cs2_test` (assertion `msaa` liée à l'environnement graphique), `webrtc_pooling_e2e_test` (pas de serveur LAN), `zz_probe_grid` (sonde sans `PASS` → ADR-007) | — |
| Suite serveur `npm test` | **PASS** (81 + 302 + 18 = 401 vérifications) | ~8 s |
| Typecheck serveur au commit de baseline | **rouge** (5 erreurs TS) — **corrigé en phase 0** | — |
| Socle rapide (adopté par `fast-tests.txt`) | 23 tests ≈ 102 s (voir `BASELINE_TESTS.md` §11) | — |

**Règle de non-régression** : après chaque phase, la suite complète doit rester **≤ 5 échecs connus** ; un sixième échec est une régression. Une suppression de code mort ne doit **jamais** changer cette liste, à l'exception de `zz_probe_grid`, supprimé en phase 1 (le total passe donc légitimement à 4 échecs connus). **Contrôle post-phase 1 effectué le 2026-11-17** : 120 tests, 115 PASS, 4 échecs connus + 1 flake de concurrence (`city_scene_test`, PASS en isolation) — voir [BASELINE_TESTS.md §14](BASELINE_TESTS.md).

**Avertissement** : la baseline a été mesurée sur une machine partagée avec d'autres agents ; les durées sont gonflées (ex. `map_quick_start_test` : 113 s en suite, 82,7 s isolé). Pour une comparaison stricte, rejouer les commandes sur un arbre figé.

---

## 5. Feuille de route détaillée

### Phase 0 — Filets & vert ✅ (2026-11-17)

| Lot | Contenu | Statut |
|---|---|---|
| 0.1 | Porte de compilation `game/scenes/debug/compile_check.tscn` + script | ✅ |
| 0.2 | `tools/refactor/verify.ps1`, `fast-tests.txt`, `metrics.ps1` | ✅ |
| 0.3 | Build serveur réparé : chaîne de jeu TS archivée dans `server/legacy/`, `ws`/`dotenv` en `dependencies`, `noEmitOnError` | ✅ |
| 0.4 | Réparation/suppression des 6 scripts qui ne compilaient pas | ✅ |
| 0.5 | Audits (client, éditeur, serveur) + inventaire + baseline | ✅ |
| 0.6 | Documentation de l'état et du plan | ✅ |

**Critère d'acceptation** : compilation client 0 échec, typecheck/build serveur verts, `npm test` vert, baseline consignée.

### Phase 1 — Purge du code mort ✅ (risque faible)

| Lot | Fichiers | Lignes | Statut |
|---|---|---|---|
| 1.1 | `game/scripts/core/**` morts et périmés (ADR-002) | −1 077 | ✅ |
| 1.2 | 4 modules d'éditeur morts (`editor_input_handler`, `editor_tool_handlers`, `editor_view_controller`, `editor_save_controller`) | −547 | ✅ |
| 1.3 | 6 calques/scripts legacy de `maps/` (token/lighting/zone/effect/fog/grid) | −666 | ✅ |
| 1.4 | `maps/simple/simple_tileset.gd` mort | −417 | ✅ |
| 1.5 | `tests/zz_probe_grid.gd` (sonde, ADR-007) | −20 | ✅ |
| 1.6 | Déjà fait en phase 0 : `maps/complex_map_engine.gd` (510 l. legacy 2D cassé) et `maps/map_layers/map_elevation_layer.gd` (64 l. cassé) | −574 | ✅ |

**Critère d'acceptation** : `verify.ps1` vert ✅ (compilation 452 fichiers 0 échec, typecheck vert, 23/23 tests), tests du domaine verts ✅ (17/17), `metrics.ps1` régénéré ✅ (361 scripts / 113 024 l.), aucune référence orpheline dans les scènes (gate `--scenes`) ✅.
**Gain mesuré (fin de phase 1)** : **67 chemins supprimés (−3 303 lignes au diff)** dont **27 scripts `.gd`** : −637 l. en phase 0 (`complex_map_engine.gd` 573, `map_elevation_layer.gd` 64) et −2 666 l. en phase 1. Les 17 god files vivants restent (c'est l'objet des phases 2-4), mais la surface morte disparaît.

### Phase 2 — Contrats & cœur client ⏳

| Lot | Contenu | Estimation | Risque |
|---|---|---|---|
| 2.0 | Corriger les 3 échecs de test connus (palette, msaa, snap trop lent) — ✅ test-only, suite ramenée à 1 échec connu (WebRTC) | S | Faible |
| 2.1 | `session_view_model_test.gd` (caractérisation du contrat de signaux) — ✅ 30 assertions, PASS | ~150 l. | Faible |
| 2.2 | `game_data_contract_test.gd` (30-40 assertions sur l'API publique de l'autoload) — ✅ 40 assertions, PASS | ~200 l. | Faible |
| 2.3 | `CONTRAT_EDITEUR.md` généré + test de contrat listant les membres atteints par les tests (ADR-006) — ✅ 536 l. générées, 169 membres éditeur + 99 document + 128 moteur, outil `editor_contract.ps1` rejouable | ~120 l. | Faible |
| 2.4 | `game_data.gd` lot 1 : `session_model` (~390 l. → `core/session/session_model.gd`), protégé par `session_model_test` — ✅ fait (commit 76e76a6) : god file 4 586 → 4 348 l. | M | Moyen |
| 2.5-2.7 | `game_data.gd` : `game_storage` (162 l.), `turn_flow` (91 l.), `roster` (133 l.) extraits — ✅ GameData 4 348 → 4 199 l., 291 fonctions inchangées | L (3 PR) | Élevé |
| 2.6 | `game_data.gd` : sortir le déplacement sémantique (533 l.) et la navigation d'échelle, une fois le modèle `mapPlayState` figé | L | Élevé |
| 2.7 | `session/panels/map_workspace.gd` (1 321 l.) : sortir le contrôleur de déplacement, respecter le contrat SessionViewModel | M | Moyen |
| 2.8 | `map_data.gd` (2 287 l.) : sortir l'image (`cutout`, `night_texture`, `thumbnail`) — ✅ 2 088 l., parité pixel prouvée (39 SHA-256) ; reste le schéma (`map_schema`) et les cartes de démo (`game/data/demo_maps/`) | L | Moyen |

**Critère d'acceptation** : `game_data.gd` ≤ 1 800 l. après 2.4-2.6, façade documentée ; tests de contrat ajoutés et verts ; suite complète sans nouvelle régression.

### Phase 3 — Éditeur de scénario ⏳

| Lot | Contenu | Estimation | Risque |
|---|---|---|---|
| 3.1 | Routeur de liens extrait de `graph_link_overlay.gd` (1 849 l.) vers `core/graph/{link_router,cable_geometry}.gd` — ✅ 7 captures byte-identiques, overlay −36 % | L | Faible-Moyen |
| 3.2 | `scenario_editor.gd` (3 205 l.) : style sorti (~446 l., 13 fonctions statiques + 6 constantes) — ✅ 3 204 → 2 823 l. (−11,9 %), 7/9 captures byte-identiques (2 = horodatages non déterministes) | M | Faible |
| 3.3 | Sortir `graph_controller.gd` (~700 l. : nœuds, liens, zoom, positions) | L | Moyen |
| 3.4 | Sortir `transitions_panel.gd` (~350 l.), `scene_inspector.gd` (~330 l.), `dock_history.gd` (~350 l.) | L | Moyen |
| 3.5 | `command_palette` / `editor_views` / `editor_minimap` : consolider l'API | S | Faible |

**Critère d'acceptation** : `scenario_editor.gd` ≤ 800 l., routeur pur sous test unitaire, captures `scenario_editor_refonte_shot_test` et `scenario_graph_links_shot_test` identiques (ou différences justifiées).

### Phase 4 — Éditeur de cartes 2.5D (5 vagues) ⏳

| Vague | Cible | Lignes actuelles | Cible | Risque |
|---|---|---:|---:|---|
| V1 | `editor/map_edit_document.gd` → 7 modules purs | 2 623 | 600-800 | **Faible** |
| V1 | `terrain/terrain_carve_field.gd` (+ suppression des 4 copies de sampling) | 1 364 | ~450 | Moyen |
| V1 | `editor/map_editor_tool_options.gd` (fonction de 806 l. → dispatcher) | 1 018 | ~120 | Faible |
| V2 | `map_layers/map_water_3d.gd` (`_build_river_body` 435 l.) | 2 235 | ~350 | Faible |
| V2 | `map_layers/map_ground_3d.gd` | 2 303 | ~400 | Moyen |
| V2 | `map_layers/map_meshes_3d.gd` | 1 512 | ~250 | Faible |
| V3 | `editor/map_editor_construction.gd` (façade `setup(editor)`) | 2 679 | ~150 | Faible-Moyen |
| V3 | `complex_map_engine_3d.gd` (3 sous-vagues : rendu → caméra → tokens) | 4 230 | 500-700 | **Élevé** |
| V4 | `map_complex_editor.gd` par slices (builders UI → layout → settings → commandes → terrain/eau → placement) | 5 359 | ~900 | **Très élevé** |
| V0 | **Étape (a)** : couches sales (`DirtyLayers`, signal `layers_changed`, 173 vérifs) + instrumentation par couche — ✅ comportement inchangé | — | — | Faible |
| V0 | **Étape (b)** : `MapMeshes3D.sync()` diff-based + `update_meshes_layer()` + dispatch ciblé meshes — ✅ commit d'édition **1 506 → 45 ms** (−97 %, ×33) ; parité d'état prouvée (42 modules) ; garde-fou `editor_commit_perf_test` (seuil 150 ms) ; `map_editor_snap_test` réactivé en synchro complète (PASS 75 s vs 257 s) | — | — | Moyen |
| V0 | **Étape (d)** : releases de drag ciblés (move/resize/rotation/décor) — suppression des rebuilds complets, `update_layers(TARGETED_LAYERS)` au moteur + repli complet sûr ; `map_editor_snap_test` réactivé en synchro complète (75 s vs 257 s) — ✅ **release 1 492-2 916 ms → 47-55 ms (×30-60)**, création décor 1 447 → 56 ms | — | — | Faible |
| V0 | **Étape (c/e)** : dispatch par couches au moteur (`_rebuild_*_layer` extraits, ordre conservé), tests de perf `editor_commit_perf_test` + `editor_drag_perf_test` — ✅ | — | — | Moyen |
| V5 | Nettoyage : grille outils v1 masquée, palette environnement masquée, docs périmées | — | — | Faible |

Règles : **jamais deux god files dans le même commit** ; conserver les wrappers et les noms de membres atteints par les tests ; parité de hauteurs vérifiée par tests de référence avant remplacement ; captures avant/après obligatoires pour les vagues 2-4.

**Contrat de performance (prérequis de la vague 3)** : voir le design détaillé [PLAN_SYNCHRO_INCREMENTALE.md](PLAN_SYNCHRO_INCREMENTALE.md) (couches sales, `MapMeshes3D.sync()` diff-based, seuils de perf). Le refactor ne doit pas seulement déplacer la dette — il doit tenir les cibles mesurées dans [RAPPORT_PERFORMANCE_EDITEUR_3D.md](RAPPORT_PERFORMANCE_EDITEUR_3D.md) : fin de drag ≤ 100 ms (aujourd'hui 1,6-1,9 s par reconstruction, ≈ 4 s au relâchement), tampon de sculpture ≤ 16 ms et géométrie identique entre « remblayer » et « relâcher » (aujourd'hui 184-327 ms puis 1-2 s avec changement visible de résolution), vignettes de bibliothèque ≤ 150 ms (aujourd'hui 1,87-2,00 s). La cause racine commune — propagation par *snapshot complet* (`doc.to_map_data()` → `engine.configure()` → toutes les couches) au lieu de diffs — doit être traitée par l'état « couches sales » (§5 du rapport) pendant la vague 3, pas reportée.

### Phase 5 — Serveur & contrat de données ⏳

| Lot | Contenu | Statut |
|---|---|---|
| 5.1 | Archiver la chaîne de jeu TS + MCP (ADR-001) | ✅ phase 0 |
| 5.2 | Dés : chaîne TS archivée (`server/legacy/`), `dice_cases.json` seul exécuté côté GDScript — ✅ (commits serveur, 0 import de dés actif) | ✅ |
| 5.3 | `data/schemas/` : validateur générique `tools/refactor/validate_data.py` (0 dépendance, 27 auto-tests) branché dans `verify.ps1` (gate bot+ruleset, dérive complète informative) + [RAPPORT_SCHEMAS.md](RAPPORT_SCHEMAS.md) (666 erreurs néanmoins : 0/12 scénarios et 0/3 cartes conformes ; realignement/archivage à décider) | ✅ outillé, réalignement ⏳ |
| 5.4 | Protocole pooling : figer `lobby/types.ts` + `protocol.ts` comme contrat v2 et ajouter un test de sérialisation (déjà 18 vérifications d'intégration) | ⏳ |
| 5.5 | Documentation serveur : `STACK.md`, `MULTIPLAYER.md` (contrat v2), `MOTEUR_DES.md`, `MCP.md`, `SESSION_PROTOCOLE.md`, `ARCHITECTURE.md` alignés — ✅ 455 liens vérifiés, 0 cassé ; [ADR-004-schemas.md](ADR-004-schemas.md) documente la décision data/schemas | ✅ |

### Phase 6 — Industrialisation & dette documentaire ⏳

| Lot | Contenu |
|---|---|
| 6.1 | CI GitHub Actions : `tsc --noEmit` + `npm test` + compilation Godot headless (binaire téléchargé) + tests rapides + job data/schemas — ✅ `.github/workflows/tests.yml` (3 jobs) |
| 6.2 | Consolider les ≈70 docs `docs/` : index, archives datées, documents obsolètes déplacés dans `docs/archive/` |
| 6.3 | Règle de frontière de propriété (ADR-009) + porte de vérification + règles de tests/schémas dans `CONTRIBUTING.md` — ✅ |
| 6.4 | Métriques finales : comparer [inventaire](INVENTAIRE_TECHNIQUE.md) avant/après ; objectif : 0 fichier > 1 000 lignes, 0 code mort |

---

## 6. Phase 0 — journal des changements

### 6.1 Porte de compilation client

- `game/scripts/debug/compile_check.gd` + `game/scenes/debug/compile_check.tscn` : chargent tous les `.gd` (et, avec `--scenes`, tous les `.tscn`) dans un vrai run headless (autoloads actifs), détectent les erreurs de parse/compilation (y compris le cas où `ResourceLoader.load` renvoie un `GDScript` invalide — `can_instantiate()` est le seul signal fiable). Sortie : `:PASS`/`:FAIL` + code retour.
- Premier passage réel : **5 scripts ne compilaient pas** (jamais vus par la suite de tests car non chargés) :
  - `core/persistence/character_repository.gd` — `JsonStore.generate_id()` manquant → implémenté dans `json_store.gd` ;
  - `core/rules/stats.gd` — `Array.join()` inexistant en GDScript → `" ".join(...)`, plus de gestion `race`/`class` vide ;
  - `debug/carte_25d_session_boot.gd` — commentaire `##` collé au `func` (erreur de syntaxe) ;
  - `debug/perf_probe_library.gd` — `Image.load_png_from_buffer` mal utilisé (retourne `Error` en 4.7) ;
  - `maps/complex_map_engine.gd` (510 l., moteur 2D legacy) et `maps/map_layers/map_elevation_layer.gd` (64 l.) — dead + cassés → **supprimés** (0 référence externe vérifiée).
- Les scènes sont aussi vérifiées : 477 fichiers (scripts + scènes) en ~12 s, 0 échec.

### 6.2 Serveur : build réparé, chaîne de jeu archivée

- `git mv` de 13 fichiers TS morts vers `server/legacy/` (hors `src/`, donc hors compilation) : `ai-gm`, `bots`, `game_session`, `state_serializer`, `types`, `scenario_loader`, `narrative/*`, `mcp/*`. Cause racine documentée : `8ecbfe2` a supprimé `AiGM` (−1 812 l.) sans migrer `game_session.ts`/`mcp/gm_server.ts`.
- `ConnectedClient` déplacé dans `party_utils.ts` (seul type du lobby encore consommé) ; `package.json` : `mcp` retiré, `ws`/`dotenv` passés en `dependencies` ; `tsconfig.json` : `noEmitOnError: true`.
- Résultat : `npm run typecheck` ✅ · `npm run build` ✅ · `npm test` ✅ (112 + 81 + 18 vérifications).

### 6.3 Outillage

- [`tools/refactor/verify.ps1`](../../tools/refactor/verify.ps1) : compilation + typecheck + socle rapide (23 tests, ≈ 110 s), résumé PASS/FAIL par étape, code retour exploitable.
- [`tools/refactor/fast-tests.txt`](../../tools/refactor/fast-tests.txt) : socle rapide mesuré par la baseline (règles/dés, session, UI éditeur, terrain, scénario, eau, vision, monde, réseau).
- [`tools/refactor/metrics.ps1`](../../tools/refactor/metrics.ps1) → [inventaire technique](INVENTAIRE_TECHNIQUE.md) : volumétrie, god files, répartition, autoloads, code mort (références exactes hors `.godot`), doublons de fonctions, scènes, tests, serveur.
- [`scripts/run_tests.ps1`](../../scripts/run_tests.ps1) : corrigé (phase 0) — fichiers temporaires uniques par run (plus de collision entre runners) et fin forcée compatible Windows PowerShell 5.1 (les timeouts laissaient des Godot orphelins) ; socle rapide `-Filter` + `-TimeoutSeconds 120`.

### 6.4 Documentation

- `docs/refactor/` : 3 audits (client, éditeur, serveur), inventaire, baseline, index, ce plan.
- `docs/MCP.md` : bandeau « archivé » ; `server/legacy/README.md` : cause, contenu, procédure de restauration.
- `docs/ARCHITECTURE.md`, `README.md`, `docs/STACK.md`, `docs/REFACTOR_EDITEUR.md` : réalignés sur l'état réel (phase 0 / docs).

---

## 7. Règles d'exécution du chantier

1. **Une phase = des commits dédiés**, un lot = un commit, message conventionnel : `refactor(<scope>): <lot> — <gain>`.
2. **Jamais deux god files dans le même commit** ; jamais un refactor + une feature dans le même commit.
3. **Aucun changement de comportement** : les tests et les captures sont la loi ; un diff de rendu doit être justifié.
4. **Wrappers d'abord** : on extrait le code, on laisse des wrappers d'une ligne dans le fichier d'origine ; on ne supprime un wrapper qu'en modifiant ses appelants/tests.
5. **Noms privés gelés** (ADR-006) : `docs/refactor/CONTRAT_EDITEUR.md` liste les membres atteints par les tests.
6. **Mesurer avant/après** : `metrics.ps1` + `verify.ps1` + tests du domaine ; consigner dans le commit.
7. **Réversibilité** : chaque lot est un commit isolé, revert possible sans casser la base.
8. **Frontière de propriété** (ADR-009) : un module extrait ne grossit plus ; tout nouveau code va dans un module dédié < 400 lignes.
9. **Pas de dette silencieuse** : toute décision reportée est écrite dans ce plan (ADR ou « à trancher »).

---

## 8. Risques et parades

| Risque | Où | Parade |
|---|---|---|
| Tests qui sondent des internes privés | éditeur (169 membres), moteur 3D (130) | geler la liste avant extraction (ADR-006) ; ne jamais renommer sans mettre à jour le test dans le même commit |
| Couplage dynamique `_ed` non typé | `map_editor_construction/tool_options/edit_ops` (1 402 accès) | wrappers + tests de contrat + doc générée ; toute typo ne se voit qu'au runtime — tester chaque chemin d'outil |
| Parité de hauteurs du terrain (4 copies) | `map_ground_3d`, `terrain_carve_field`, moteur 3D, 3 calques | extraire sans réécrire la formule ; test de parité sur cartes de référence avant remplacement |
| Rendu non vérifiable en headless | 57 tests `*_shot_test` | `-IncludeShots` (fenêtre cachée) avant/après toute vague de rendu |
| Régression de perf sur cartes denses | `_rebuild_layers`, `_apply_scene_plan`, drag | `editor_drag_perf_test`, `map_quality_cs2_test`, profil avant/après |
| Regonflement du contrôleur | `map_complex_editor.gd` (3 253 → 5 359 l.) | ADR-009 + contrôle final ≤ 1 000 l. |
| Portée qui dérive | `map_editor_parametres.gd`, `world_panel`, `scenario_editor.*` | listés « deuxième rideau » ; planifiés dans des phases distinctes |
| Auto-import Godot concurrent | jeu lancé + gate headless | lancer les gates en headless uniquement ; ne pas lancer deux éditeurs Godot |
| Baseline contaminée | tests lancés pendant les suppressions | vérifier `verify.ps1` après chaque lot ; comparer à [BASELINE_TESTS.md](BASELINE_TESTS.md) |

---

## 9. Métriques de succès (mesure avant → cible)

| Métrique | Avant (2026-11-17) | Cible après chantier |
|---|---:|---:|
| Fichiers `.gd` > 1 000 lignes | 20 → **19** (round 6) | 0 |
| Fichiers `.gd` > 500 lignes | 51 → **55** (round 6) | 0 |
| Lignes client | 116 299 → **118 886** (round 6) | stabiliser puis décroître |
| `core/` vivant | 28 % | 100 % (modules conservés = modules exécutés) |
| `game_data.gd` | 4 587 l. → **4 199** (round 3) | ≤ 400 l. (façade) |
| `map_complex_editor.gd` | 5 360 l. | ≤ 1 000 l. |
| `complex_map_engine_3d.gd` | 4 231 l. | ≤ 700 l. |
| `scenario_editor.gd` | 3 205 → **1 596** (round 6 : style, graphe, 3 panneaux) | ≤ 800 l. |
| Moteurs de dés exécutables | 2 (+2 façades) | **1** ✅ (phase 5.2) |
| Build serveur | ❌ rouge depuis 2 mois | ✅ vert |
| `verify.ps1` | n'existait pas | < 3 min, vert |
| CI | aucune | typecheck + tests rapides |

---

## 10. Prochaines actions immédiates

> **État au 2026-11-17 (fin de round 2)** : phases 0, 1 et 2.0-2.4 livrées et poussées ; `verify.ps1` vert (compilation 369 fichiers, socle rapide 25 tests).

> **État au 2026-11-17 (fin de round 3)** : phases 0-2 (2.0-2.8 image), 3.1 et 5.2 livrées et poussées ; `verify.ps1` vert ; 3 échecs de test corrigés + 4 tests récupérés par le runner (baseline → 1 échec connu WebRTC) ; `game_data.gd` 4 586 → 4 199 l., `map_data.gd` 2 287 → 2 088 l., overlay de liens −36 %.

> **État au 2026-11-17 (fin de round 5)** : phases 0-2 (dont 2.8 image + schéma), 3.1-3.3 (routeur, style, graphe), 4a-4b (synchro ciblée **1 506 → 45 ms**, release −50 %), 5.2-5.4 (dés uniques, validateur schemas, contrat protocole 302 vérifs) et 6.1-6.3 (CI, index docs, CONTRIBUTING) livrées et poussées. Reste : 2.8c (démos, reporté), 3.4-3.5, 4c-4f, 5.3-alignement/5.5, 6.4.

> **État au 2026-11-17 (fin de round 6)** : phases 0-2 complètes (2.8c livrée : MapData 1 954 → 1 533 l.), 3.1-3.5 (scenario_editor 3 204 → 1 596 l.), 4a-4d (**édition 1 506 → 45 ms ; release 1 492-2 916 → 47-55 ms**), 5.2-5.5 (dés uniques, validateur + ADR-004, contrat protocole 309 vérifs, docs 455 liens OK), 6.1-6.3 (CI, index docs, CONTRIBUTING) livrées et poussées ; bug client pooling corrigé (faux timeout 8 s).

1. **Round 7 — phase 4, vagues d'extraction** (le plus gros restant) : V1 `map_edit_document.gd` (2 644 l.) → 7 modules purs, `terrain_carve_field.gd` (1 364 l., supprimer les 4 copies de sampling), `map_editor_tool_options.gd` (1 019 l., fonction de 806 l.) ; puis V2 water/ground/meshes, V3 construction (2 685 l.) + moteur (4 401 l.), V4 contrôleur `map_complex_editor.gd` (5 477 l.).
2. **Round 7 — 4f terrain incrémental** : brosse ≤16 ms/frame et géométrie identique entre « remblayer » et « relâcher » (changement de résolution MC interdit).
3. **Round 7 — fin de 3.6** : slices « console chrome » (~173 l.) + méta/formats (~180 l.) pour `scenario_editor.gd` ≤ 800 l. ; puis `map_workspace.gd` (1 321 l.).
4. **Round 7 — suite complète propre + 6.4** : relancer la suite (attendu : 1 échec connu WebRTC + nouveaux tests), métriques finales avant/après dans l'inventaire.
5. **Dettes ciblées** : drag d'une lumière en repli complet (world_env hors TARGETED_LAYERS), `props` diff si une carte en contient beaucoup, alignement `scenario/map` schemas (P1 ADR-004).
