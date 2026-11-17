# Chantier de refactorisation — index et mode d'emploi

> **Statut au 2026-11-17** : lancé le 2026-11-17 (HEAD de départ `4514c61`). **phases 0 et 1 livrées** (2026-11-17), phases 2-6 planifiées.
> **Le document qui fait foi** est le [plan de refactorisation](PLAN_REFACTORISATION.md) : ADR, feuille de route, portes de qualité, règles d'exécution, métriques cibles.
> **Convention de comptage** : lignes physiques (`(Get-Content <fichier>).Count`), comme les audits ; `metrics.ps1` compte la ligne finale (+1 par fichier). Ne pas mélanger les deux unités.

---

## 1. Objectif du chantier

Rendre le dépôt maintenable et mesurable **sans changer le comportement observable** :

1. **Supprimer le code mort** prouvé par les audits (client : **27 fichiers / 3 276 lignes** supprimés en phases 0-1 ; serveur : 13 fichiers archivés).
2. **Découper les god files** et figer des frontières de propriété (les principes d'architecture sont des **cibles** avec écart mesuré, pas des acquis).
3. **Établir des contrats** : tests de contrat sur les API publiques, un seul moteur de dés exécutable, un contrat `data/schemas/` réellement branché.
4. **Rendre la vérification rapide** (< 2 min de socle) pour qu'elle soit utilisée à chaque commit, à défaut de CI (phase 6).
5. **Rendre la documentation véridique** : décrire l'état réel et la cible, pas une architecture abandonnée.

Non-objectifs : aucun changement de gameplay, d'UI ou de protocole réseau ; aucune nouvelle fonctionnalité ; pas de réécriture « big bang ». Détail : [plan §1](PLAN_REFACTORISATION.md).

---

## 2. Documents du chantier

| Fichier | Contenu | Rôle |
|---|---|---|
| [PLAN_REFACTORISATION.md](PLAN_REFACTORISATION.md) | Plan consolidé : synthèse, ADR-001 à ADR-009, phases 0-6, portes, règles, métriques cibles | **source de vérité** |
| [AUDIT_GODOT.md](AUDIT_GODOT.md) | Audit du client Godot (`core/`, autoloads, scénario, session) : violations des principes, duplications, code mort, top 10 des cibles | preuve |
| [AUDIT_EDITEUR_CARTE.md](AUDIT_EDITEUR_CARTE.md) | Audit des god files de l'éditeur de cartes 2.5D/3D : blocs, plans d'extraction, contrat de test (169 membres atteints) | preuve |
| [AUDIT_SERVEUR.md](AUDIT_SERVEUR.md) | Audit du serveur Node/TS et du contrat `data/schemas` : build cassé depuis `8ecbfe2`, duplication des dés, code mort | preuve |
| [BASELINE_TESTS.md](BASELINE_TESTS.md) | Baseline de non-régression : 178 tests déclarés, 121 exécutés en headless (116 PASS / 5 FAIL connus), 57 tests de capture exclus, logs conservés, socle rapide proposé | référence |
| [INVENTAIRE_TECHNIQUE.md](INVENTAIRE_TECHNIQUE.md) | Mesure reproductible (`metrics.ps1`) : volumétrie, god files, répartition, candidats code mort, scènes, tests, serveur | référence |
| [RAPPORT_PERFORMANCE_EDITEUR_3D.md](RAPPORT_PERFORMANCE_EDITEUR_3D.md) | Mesures et causes racines des gels de l'éditeur 3D (rebuild ≈ 2,5 s, tampon de brosse 184-327 ms) + contrat de perf à tenir | référence |

Documents d'état (mis à jour avec ce chantier) : [ARCHITECTURE.md](../ARCHITECTURE.md) (runtime réel + cible), [REFACTOR_EDITEUR.md](../REFACTOR_EDITEUR.md) (refactor éditeur précédent, historique), [MULTIPLAYER.md](../MULTIPLAYER.md) (modèle P2P + pooling), [STACK.md](../STACK.md) (historique, bandeau « obsolète »).
Archive serveur : [`server/legacy/README.md`](../../server/legacy/README.md) (cause de l'archivage, contenu, procédure de restauration).

---

## 3. Outillage et commandes

| Outil | Commande | Rôle / durée |
|---|---|---|
| **Porte complète** | `./tools/refactor/verify.ps1` | compilation Godot + `tsc --noEmit` serveur + socle rapide (23 tests) — < 3 min, code retour 0/1/2 |
| Porte complète avec scènes | `./tools/refactor/verify.ps1 -Scenes` | idem + chargement des `.tscn` (attrape les références de scène cassées) |
| Compilation seule | `godot --headless --path game --scene res://scenes/debug/compile_check.tscn -- --scenes` | tous les scripts + scènes, `:PASS`/`:FAIL`, ~12 s |
| Socle rapide seul | `./tools/refactor/verify.ps1 -SkipServer` | 23 tests de logique pure (< 2 min, ≈ 102 s mesurés), liste dans [`fast-tests.txt`](../../tools/refactor/fast-tests.txt) |
| Suite complète headless | `./scripts/run_tests.ps1` | 121 tests exécutés (captures exclues) — baseline 116 PASS / 5 FAIL connus, 24 min 35 s |
| Captures / rendu | `./scripts/run_tests.ps1 -IncludeShots` | 57 tests de capture (44 `*_shot_test` + 13 autres écrivant `save_png`) — fenêtre cachée, obligatoire avant tout refactor de rendu |
| Mesure | `./tools/refactor/metrics.ps1` | régénère [INVENTAIRE_TECHNIQUE.md](INVENTAIRE_TECHNIQUE.md) |
| Serveur | `cd server; npm run typecheck; npm run build; npm test` | build TS + 211 vérifications (112 dés + 81 lobby + 18 intégration) |

Options utiles de `verify.ps1` : `-Scenes`, `-SkipTests`, `-SkipServer`, `-FullTests` (suite complète), `-TestFilter '<regex>'`.
Le binaire Godot est cherché via `GODOT_BIN`, le `PATH`, puis WinGet (`Godot_v4.7.2-stable_win64.exe`). Aucun Godot fenêtré : gates en `--headless` uniquement.

**Étalon phase 0 (2026-11-17)** : compile gate **477 fichiers (scripts + scènes), 0 échec, ~12 s** ; typecheck/build serveur **verts** ; `npm test` **vert (211 vérifications)**.
> La [baseline](BASELINE_TESTS.md) (§7) a mesuré 5 erreurs TS pré-existantes : elles concernaient les fichiers depuis **archivés dans `server/legacy/`** (hors `tsconfig`) ; `npm run typecheck` est vert depuis la phase 0. Les 5 échecs Godot de la baseline sont, eux, documentés et attendus (défauts de test/runner ou dépendance d'environnement).

---

## 4. État d'avancement

Détail par lot : [plan §5](PLAN_REFACTORISATION.md).

| Phase | Contenu | Statut |
|---|---|---|
| **0 — Filets & vert** | Porte de compilation (`compile_check`), `verify.ps1`/`fast-tests.txt`/`metrics.ps1`, build serveur réparé + chaîne de jeu TS archivée dans `server/legacy/`, 6 scripts cassés réparés ou supprimés, 3 audits + inventaire + baseline, docs réalignées | ✅ 2026-11-17 |
| **1 — Purge du code mort** | `core/` mort et périmé (ADR-002), 4 modules d'éditeur morts, 6 scripts legacy `maps/`, `simple_tileset.gd`, sonde `zz_probe_grid.gd` — **−2 639 lignes** en phase 1 (**−3 276 au total** avec les 2 moteurs cassés déjà supprimés en phase 0), risque faible | 🔄 en cours |
| **2 — Contrats & cœur client** | Tests de contrat (`session_view_model_test`, `game_data_contract_test`, `CONTRAT_EDITEUR.md`), lots `game_data.gd`, `map_data.gd`, `map_workspace.gd`, `SessionViewModel` | ⏳ |
| **3 — Éditeur de scénario** | Routeur de liens `graph_link_overlay` → `core/graph/link_router.gd`, découpage de `scenario_editor.gd` (style, graphe, transitions, docks) | ⏳ |
| **4 — Éditeur de cartes 2.5D** | 5 vagues V1 → V5 : document/terrain/options → couches 3D → construction/moteur → contrôleur → nettoyage | ⏳ |
| **5 — Serveur & contrat de données** | Dés : une seule implémentation exécutable (GDScript, ADR-005) ; validateur `data/schemas` branché ; protocole pooling figé | ⏳ |
| **6 — Industrialisation & docs** | CI GitHub Actions, consolidation des ≈ 70 docs, règle de frontière de propriété, métriques finales | ⏳ |

**Mesures de départ** (à rafraîchir avec `metrics.ps1`, chiffres datés du 2026-11-17) : 20 fichiers `.gd` > 1 000 lignes, les 7 plus gros du périmètre audité concentrent 56 % de ses lignes, `core/` vivant à 28 % avant purge, `map_complex_editor.gd` 3 253 → **5 359 l.** après regonflement, build serveur rouge pendant deux mois, 8 schémas `data/schemas/` lus par aucun code. Cibles chiffrées : [plan §9](PLAN_REFACTORISATION.md).

---

## 5. Conventions de travail (résumé de [plan §7](PLAN_REFACTORISATION.md))

- **Une phase = des commits dédiés** ; **un lot = un commit** (`refactor(<scope>): <lot> — <gain>`) ; **jamais deux god files dans le même commit**, jamais un refactor mélangé à une feature.
- **`verify.ps1` vert obligatoire avant chaque commit** (ADR-008) ; après une extraction, rejouer les tests du domaine (`-Filter <domaine>`) et comparer à la [baseline](BASELINE_TESTS.md).
- **Wrappers d'abord** : on extrait le code, on laisse une délégation d'une ligne dans le fichier d'origine ; on ne supprime un wrapper qu'en modifiant ses appelants/tests **dans le même commit**.
- **Noms privés gelés** (ADR-006) : les membres atteints par les tests sont listés dans `docs/refactor/CONTRAT_EDITEUR.md` (à produire en phase 2) ; un renommage sans mise à jour du test est une régression.
- **Mesurer avant/après** : `metrics.ps1` + `verify.ps1` + tests du domaine, consigné dans le commit.
- **Frontière de propriété** (ADR-009) : un module extrait ne reçoit plus de nouvelle responsabilité ; tout code neuf va dans un module dédié < 400 lignes ; un contrôleur final ne dépasse pas 1 000 lignes.
- **Aucune sonde dans `game/scripts/tests/`** (ADR-007) : les sondes de debug vont dans `game/scripts/debug/`, hors runner.
- **Convention d'état de carte figée** : `mapPlayState` (camelCase, ADR-003) — `map_play` est proscrit.
- **Réversibilité** : chaque lot est un commit isolé et revertable ; toute décision reportée est écrite dans le plan (ADR ou « à trancher »).
