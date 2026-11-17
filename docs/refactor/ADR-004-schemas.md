# ADR-004 — `data/schemas/` : décision sur les schémas en dérive

> **Statut : décidé** le 2026-11-17 (phase 5.5) · étend l'ADR-004 du [plan de refactorisation](PLAN_REFACTORISATION.md) (« contrat cible, non bloquant »).
> **Contexte mesuré** : [RAPPORT_SCHEMAS.md](RAPPORT_SCHEMAS.md) (phase 5.3), validateur [`tools/refactor/validate_data.py`](../../tools/refactor/validate_data.py).
> **Portée de ce lot** : documentation uniquement — **aucun schéma, aucune donnée, aucun code modifié**.

---

## 1. Contexte et état mesuré

Les 8 schémas de `data/schemas/` sont le **contrat cible** du projet ([ARCHITECTURE.md](../ARCHITECTURE.md) §5) mais, jusqu'à la phase 5.3, aucun code ne les lisait. La phase 5.3 a outillé un **validateur sans dépendance** (`validate_data.py`, 27 auto-tests, `$ref` résolus) et l'a branché dans [`verify.ps1`](../../tools/refactor/verify.ps1) et dans la CI ([`.github/workflows/tests.yml`](../../.github/workflows/tests.yml), job `data`).

État réel après la phase 5.3 : **4/8 schémas ont des données versionnées, 2/8 sont conformes, 2/8 dérivent, 4/8 n'ont aucune donnée** (666 erreurs au total, dont 348 hors miroirs `data/` ↔ `game/data/`).

| Schéma | Données réelles | Verdict mesuré | Décision de ce lot |
|---|---|---|---|
| `bot.json` | `data/bots/archetypes.json` + miroir (7 items) | ✅ conforme (0 erreur) | **Gate CI bloquant** (déjà branché : `--only bot,ruleset`) |
| `ruleset.json` | `game/data/rulesets/*.json` (2) | ✅ conforme (0 erreur) | **Gate CI bloquant** |
| `scenario.json` | 12 scénarios canoniques (+11 miroirs) | ❌ dérive : 582 erreurs, **0/12 valide** (format snake_case cible ≠ camelCase réel, transitions par scène, champs éditeur) | **Dérive connue, informative en CI** ; réalignement planifié (P1) |
| `map.json` | 3 cartes canoniques (+3 miroirs) | ❌ dérive : 84 erreurs, **0/3 valide** (format battlemap VTT futur ; un 3ᵉ format existe au runtime via `map_schema_contract_test`) | **Dérive connue, informative en CI** ; réalignement ou archivage à décider (P1) |
| `character.json` | aucune (`user://characters.json`) | ⚪ non couvert | **Contrat cible, non branché** (P3) |
| `save_game.json` | aucune (`user://saved_games.json`) | ⚪ non couvert | **Contrat cible, non branché** (P2/P3) |
| `session_model.json` | aucune (embarqué dans `active_game`) | ⚪ non couvert | **Contrat cible, non branché** (P3, branchable via fixtures de tests) |
| `dice_roll.json` | aucune (résultat d'exécution) | ⚪ non couvert | **Contrat cible, non branché** (P3, branchable via golden file du moteur GDScript) |

Autres constats utiles à la décision : 15 paires `data/**` ↔ `game/data/**` sont byte-identiques (miroir racine non maintenu), `data/schemas/character.json` est dupliqué à l'identique dans `game/data/schemas/character.json`, et un échantillon `data/sessions/game-*.json` de l'ancien serveur autoritaire ne correspond à aucun schéma.

---

## 2. Décision

1. **Les 8 schémas restent en place** ; aucun fichier de schéma n'est archivé, corrigé ni déplacé dans ce lot. Chaque schéma reçoit un **statut explicite** (tableau §1) au lieu d'être implicitement présenté comme valide.
2. **Gate CI bloquant limité aux schémas conformes** (`bot`, `ruleset`). La validation complète reste **informative** (`continue-on-error`) tant que `scenario`/`map` dérivent : une CI durablement rouge serait ignorée et ne protégerait plus rien.
3. **Aucune migration de données à ce stade** : les données versionnées sont la référence d'exécution (ADR-002/ADR-004 du plan) ; on ne les plie pas à un schéma cible non réalisé.
4. **Réalignement préféré du schéma, pas des données** pour `scenario` (P1) : adopter le format réellement lu (`camelCase`, `startSceneId`, transitions **par scène**, champs éditeur `graphPos`/`graphSize`/`emoji`, `npcs[].scenes`), puis brancher la validation. Même logique pour `map` (P1) : **séparer** le contrat « carte actuelle » (`mapKind`/`width`/`height`/`tiles`/`markers`/`locationLinks`) du format VTT cible (`grid_cells`/`props`/`walls`/`areas`/`links`/`render_mode`), et aligner sur le modèle runtime gelé par `map_schema_contract_test`.
5. **Les 4 schémas sans données restent des contrats cibles** avec la mention « non branché » : ne pas les archiver maintenant (ils gardent une valeur de spec — `dice_roll` comme golden file, `session_model` via fixtures de tests, `save_game`/`character` comme cible de format), mais **ne pas les présenter comme validés**. Leur branchement (fixtures versionnées) ou leur archivage explicite est planifié en P3.
6. **Un seul emplacement canonique à terme** : `game/data/` chargé via `res://data/` ; suppression du miroir racine `data/` quand les derniers consommateurs archivés (`server/legacy/*`) auront disparu, et du doublon `game/data/schemas/character.json`.

---

## 3. Options évaluées

| Option | Contenu | Effort | Risque | Verdict |
|---|---|---|---|---|
| A — statu quo implicite | Ne rien décider, garder 8 schémas sans statut | 0 | **Élevé** (faux sentiment de contrat) | Rejetée |
| B — tout réaligner maintenant | Corriger `scenario`, `map` et les 4 autres immédiatement | M/L | **Élevé** (12 scénarios + 3 cartes + éditeur ; migration de format non décidée) | Rejetée pour ce lot, cible différée |
| C — tout brancher en gate CI | Valider les 8 schémas en bloquant | S | **Élevé** (CI rouge permanente sur 3 schémas faux) | Rejetée |
| D — archiver les 4 sans données | Déplacer `character`/`save_game`/`session_model`/`dice_roll` | S | Moyen (perte de spec utile, décision produit non prise) | Rejetée à ce stade, réévaluée en P3 |
| **E — statut explicite + gate sur conformes + réalignement planifié** | Tableau de statuts, gate `bot`+`ruleset`, P1 `scenario`/`map`, P3 les 4 autres, source unique | **S maintenant** (+M ensuite) | **Faible** | **Retenue** |

---

## 4. Conséquences

**Positives** : la CI est verte et **utile** (elle bloque une régression sur `bot`/`ruleset`) ; la dérive est mesurée, publiée et rejouable ; aucun schéma ne peut plus être cru valide par défaut ; la décision de format de `scenario`/`map` devient un lot explicite au lieu d'être noyée dans un refactor.

**Négatives / limites** : `scenario` et `map` restent faux tant que P1 n'est pas fait ; les 4 schémas sans données ne sont pas testés ; le validateur est un sous-ensemble JSON Schema (pas de `$ref` distant, `format`, `patternProperties`) — il couvre 100 % des mots-clés réellement utilisés mais n'est pas une certification.

### Critères de sortie (checklist de clôture de l'ADR)

- [x] Validateur outillé, auto-testé et rejouable (`python tools/refactor/validate_data.py`).
- [x] Gate CI bloquant sur `bot` + `ruleset` (job `data`).
- [x] Dérive mesurée et publiée ([RAPPORT_SCHEMAS.md](RAPPORT_SCHEMAS.md)).
- [x] Statut explicite des 8 schémas (tableau §1 + [index docs](../README.md)).
- [ ] **P1 — `scenario`** : format canonique adopté, schéma réaligné, 12/12 fichiers canoniques valides, validation branchée (0 erreur).
- [ ] **P1 — `map`** : contrat « carte actuelle » séparé du VTT cible, aligné sur `map_schema_contract_test`, 3/3 cartes valides.
- [ ] **P2/P3 — 4 schémas sans données** : fixtures versionnées et branchées (`session_model`, `dice_roll`) ou décision d'archivage écrite (`character`, `save_game`).
- [ ] **Source unique** : miroir racine `data/` et doublon `character.json` traités.
- [ ] **Gate élargi** : quand P1 est fait, étendre le gate CI aux 6 schémas avec données et retirer `continue-on-error`.

---

## 5. Références

- [PLAN_REFACTORISATION.md](PLAN_REFACTORISATION.md) — ADR-004 d'origine, phase 5.3 et phase 5.5.
- [RAPPORT_SCHEMAS.md](RAPPORT_SCHEMAS.md) — constat détaillé (matrice, erreurs par fichier, miroirs).
- [`tools/refactor/validate_data.py`](../../tools/refactor/validate_data.py) — validateur et auto-tests.
- [`tools/refactor/verify.ps1`](../../tools/refactor/verify.ps1) — porte locale (étape « Contrat data/schemas »).
- [`tests.yml`](../../.github/workflows/tests.yml) — CI, job `data`.
- [ARCHITECTURE.md](../ARCHITECTURE.md) §5 — contrat de données, état réel.
- [AUDIT_SERVEUR.md](AUDIT_SERVEUR.md) §4 — audit d'origine (8 schémas jamais lus, dérive).
- [Index de la documentation](../README.md) — statuts des documents.
