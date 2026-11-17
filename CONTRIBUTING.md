# Contribuer à OpenQuest JDR

Merci de participer au projet ! Ce dépôt est pensé pour **deux développeurs**.

## Démarrage

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

## Workflow

1. `git pull` sur `main`
2. Branche : `game/...`, `server/...`, `docs/...` ou `fix/...`
3. Commit : `zone: description courte`
4. Push + **Pull Request** sur GitHub
5. L'autre relit et merge

Guide complet : **[docs/COLLABORATION.md](docs/COLLABORATION.md)**

## Zones du projet

| Dossier | Contenu |
|---------|---------|
| `game/` | Client Godot 4 |
| `server/` | Serveur Node.js WebSocket (pooling uniquement — la logique de jeu TypeScript est archivée dans `server/legacy/`) |
| `docs/` | Documentation et règles |
| `data/` | Données JSON partagées |

## Avant une PR — la porte de vérification

Une seule commande pour vérifier le dépôt (client + serveur + contrat de données) :

```powershell
./tools/refactor/verify.ps1            # compilation Godot + typecheck serveur + gate data/schemas + 26 tests rapides (~3 min)
./tools/refactor/verify.ps1 -Scenes    # + chargement des 85 scènes (à lancer avant une PR qui touche une scène)
./scripts/run_tests.ps1                # suite complète headless (~20 min, les captures GPU sont exclues)
```

La CI GitHub Actions (`.github/workflows/tests.yml`) exécute les mêmes portes à chaque push/PR.

## Règles de code (issues du chantier de refactorisation)

Ces règles sont la contrepartie de `docs/refactor/PLAN_REFACTORISATION.md` ; elles ne sont pas décoratives, elles sont mesurées par `tools/refactor/metrics.ps1`.

1. **Frontière de propriété (ADR-009)** : tout nouveau code va dans un module dédié de **< 400 lignes**. Un module extrait ne reçoit ensuite plus de nouvelle responsabilité. Un contrôleur de scène (god file) ne dépasse pas **1 000 lignes** après refactor.
2. **`core/` est pur** : aucune dépendance `Node`, `@onready` ou autoload — les modules `core/` sont statiques ou `RefCounted` et opèrent sur des données passées en paramètre. C'est ce qui les rend testables en headless.
3. **Les tests sont le contrat** : les membres atteints par les tests sont gelés dans [`docs/refactor/CONTRAT_EDITEUR.md`](docs/refactor/CONTRAT_EDITEUR.md) ; on ne renomme pas un membre sans mettre à jour son test **dans le même commit**.
4. **Un refactor = zéro changement de comportement** : parité prouvée par les tests, et par capture SHA256 pour le rendu. Jamais un refactor + une feature dans le même commit ; **jamais deux god files dans le même commit**.
5. **Tests** : un test headless = script `game/scripts/tests/*.gd` qui finit par `:PASS` et `quit(0)`. Les captures (GPU) s'appellent `*_shot_test.gd` et ne tournent qu'avec `-IncludeShots`. Une sonde de debug va dans `game/scripts/debug/`, jamais dans `tests/`.
6. **Dette assumée, jamais silencieuse** : un test cassé pour une raison documentée va dans [`scripts/known_broken_tests.txt`](scripts/known_broken_tests.txt) avec un TODO de réparation — on ne le supprime pas pour faire du vert.
7. **Schémas de données** : `data/schemas/` est le contrat cible ; `python tools/refactor/validate_data.py --only bot,ruleset` est le gate vert, la dérive complète est documentée dans [`docs/refactor/RAPPORT_SCHEMAS.md`](docs/refactor/RAPPORT_SCHEMAS.md).

## Avant de merger

1. `./tools/refactor/verify.ps1 -Scenes` VERT ;
2. suite complète : le nombre d'échecs ne doit pas dépasser celui de [`docs/refactor/BASELINE_TESTS.md`](docs/refactor/BASELINE_TESTS.md) (échecs connus uniquement) ;
3. si la PR touche un god file, joindre les mesures `tools/refactor/metrics.ps1` avant/après et rester dans l'ordre des vagues du plan.
