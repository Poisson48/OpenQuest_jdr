# Rapport de dérive `data/schemas/` — validate_data.py (phase 5.3 / ADR-004)

> **Statut** : constat de dérive, READ-ONLY côté données. Aucun fichier JSON de données
> n'a été modifié, aucun schéma n'a été corrigé (les 8 schémas sont syntaxiquement sains ;
> la dérive est un écart de **format cible**, pas un bug de schéma — voir §7).
> Aucun commit (le Lead s'en charge).
>
> Outil créé : [`tools/refactor/validate_data.py`](../../tools/refactor/validate_data.py) —
> validateur JSON Schema **sans dépendance externe** (stdlib Python uniquement).
> Contexte : `docs/refactor/AUDIT_SERVEUR.md` §4 (8 schémas jamais lus, dérive
> `save_game`/`scenario`/`map`), ADR-004 du plan de refactorisation.

---

## 1. Ce que fait le validateur

`python tools/refactor/validate_data.py` (testé sous Python 3.10.0, aucune dépendance) :

- charge les **8 schémas** de `data/schemas/`, vérifie que **tous les `$ref` se résolvent** et
  signale les mots-clés JSON Schema non supportés (aujourd'hui : **0**) ;
- exécute un **auto-test intégré de 27 cas** (un cas valide + un cas invalide par mot-clé) :
  si un objet invalide passe ou qu'un objet valide échoue, le script sort en erreur ;
- valide les **couples schéma↔données réels** déclarés dans sa table `MAPPINGS` ;
  affiche par fichier les erreurs `chemin JSON + message` (ex. `$.scenes[0].transitions`) ;
- distingue les **miroirs** `data/**` ↔ `game/data/**` par SHA-256 pour ne pas compter deux
  fois les mêmes erreurs (les deux totaux sont affichés) ;
- code retour **0** si aucune dérive, **1** si dérive ou auto-test en échec (usage CI) ;
- options : `--json` (rapport machine sur stdout), `--json-output FICHIER` (écrit le JSON en
  UTF-8 sans passer par la console), `--list` (matrice seule), `--only bot,ruleset`
  (sous-ensemble), `--schema/--data/--mode` (paire ad hoc), `--max-per-file N`,
  `--skip-self-test`, `--root DIR` (racine déduite du script par défaut).

**Sous-ensemble JSON Schema supporté** : `type`, `properties`, `required`,
`additionalProperties` (booléen ou schéma), `items`, `enum`, `const`, `pattern`,
`minLength`/`maxLength`, `minimum`/`maximum`/`exclusive*`, `minItems`/`maxItems`,
`uniqueItems`, `minProperties`/`maxProperties`, `propertyNames`, `$ref` local (`#`,
`#/$defs/X`), `$defs`, `allOf`, `anyOf`, `oneOf`, `not`, `if`/`then`/`else`, schémas
booléens `true`/`false`. Annotations ignorées (`$schema`, `$id`, `title`, `description`,
`default`, `examples`…). Ce sous-ensemble couvre **100 % des mots-clés effectivement
présents dans les 8 schémas** (vérifié : `unsupported_keywords = []`).

Limites assumées (ce n'est pas un validateur JSON Schema complet) : pas de `$ref` distant,
pas de `format`, `unevaluatedProperties`, `patternProperties`, `dependentSchemas`, ni
métacontrôle de la validité du schéma lui-même.

---

## 2. Auto-test et chargement des schémas (résultat du run)

Le run par défaut exécute d'abord l'auto-test, puis la validation complète :

```
$ python tools/refactor/validate_data.py
auto-test : 27/27 cas OK
...
Schémas chargés : 8/8 ; $ref non résolus : 0
...
Code retour : 1 (dérive détectée)
```

Exemple de rejet volontaire (paire ad hoc incohérente, reproduit le comportement
« objet invalide rejeté ») :

```
$ python tools/refactor/validate_data.py --schema data/schemas/bot.json --data data/maps/demo-taverne.json
data/maps/demo-taverne.json vs bot : 18 erreur(s)
  $: propriété requise manquante : 'name'
  $: propriété requise manquante : 'race'
  ...
$ echo $LASTEXITCODE     # 1
```

Et un cas valide (utilisé comme gate possible dès maintenant) :

```
$ python tools/refactor/validate_data.py --only bot,ruleset
Code retour : 0 (aucune dérive)
```

---

## 3. Matrice schéma × données

| Schéma | Mode de validation | Fichiers de données | Erreurs uniques | Statut |
|---|---|---|---:|---|
| `scenario.json` | objet | `data/scenarios/*.json` (11) + `game/data/scenarios/*.json` (12) = **23** (dont 11 miroirs) | **306** (582 avec miroirs) | ❌ **en dérive — 0/12 fichier canonique valide** |
| `map.json` | objet | `data/maps/*.json` (3) + `game/data/maps/*.json` (3) = **6** (dont 3 miroirs) | **42** (84 avec miroirs) | ❌ **en dérive — 0/3 fichier canonique valide** |
| `bot.json` | tableau → items | `data/bots/archetypes.json` + `game/data/bots/archetypes.json` (2 fichiers, **7 items** chacun) | **0** | ✅ **conforme** |
| `ruleset.json` | objet | `game/data/rulesets/*.json` (**2**) | **0** | ✅ **conforme** |
| `character.json` | objet | **aucun** fichier versionné (`user://characters.json`) | — | ⚪ **non couvert** |
| `dice_roll.json` | objet | **aucun** (résultat produit à l'exécution) | — | ⚪ **non couvert** |
| `save_game.json` | objet | **aucun** fichier versionné (`user://saved_games.json`) | — | ⚪ **non couvert** |
| `session_model.json` | objet | **aucun** (sous-structures embarquées) | — | ⚪ **non couvert** |

**Totaux du run** : `33` validations (dont `15` miroirs identiques → **18 fichiers uniques**),
**`666` erreurs dont `348` hors miroirs** ; **4/8** schémas ont des données réelles,
**2/8** sont conformes, **2/8** en dérive, **4/8** sans données versionnées.

Commandes reproductibles :

```powershell
python tools/refactor/validate_data.py                    # rapport texte + code retour
python tools/refactor/validate_data.py --json-output rapport.json   # rapport machine UTF-8
python tools/refactor/validate_data.py --list             # matrice seule
```

---

## 4. Dérive n°1 — `scenario.json` (582 erreurs, 306 uniques)

Le schéma décrit un format **snake_case** avec transitions **au niveau scénario** ;
les données (format réellement lu par `GameData`) sont en **camelCase** avec transitions
**par scène** et des champs d'éditeur graphique.

Requêtes manquantes (23 fichiers, 100 %) : `quest_format` ×23, `start_scene_id` ×23,
`transitions` ×23, `maps` ×23, `roster` ×8.

Propriétés refusées (`additionalProperties: false`) — top 6 :

| Cause | Occurrences | Exemple |
|---|---:|---|
| `scenes[].transitions` non autorisée | 203 | `$.scenes[0].transitions` |
| `npcs[].scenes` non autorisée | 85 | `$.npcs[0].scenes` |
| `npcs[].emoji` non autorisée | 70 | `$.npcs[0].emoji` |
| `scenes[].graphPos` non autorisée | 26 | `$.scenes[0].graphPos` |
| `scenes[].graphSize` non autorisée | 26 | `$.scenes[0].graphSize` |
| `scenes[].mapIds` non autorisée (snake_case attendu `map_ids`) | 26 | `$.scenes[0].mapIds` |
| `questFormat` non autorisé (camelCase) | 23 | `$.questFormat` |
| `startSceneId` non autorisé | 23 | `$.startSceneId` |

Répartition par fichier canonique (`game/data/scenarios/`, 0/12 valide) :
`demo-couronne-fracturee` 25, `demo-crypte` 49, `demo-kharak` 47, `demo-manoir` 13,
`demo-valbois` 30, `inv-demo-alchimiste` 12, `inv-demo-bal-masque` 12, `inv-demo-brumeval` 12,
`inv-demo-oracle` 12, `inv-demo-scenario-demo` 58, `inv-demo-serpent-noir` 24,
`inv-demo-train` 12.

Autres refus relevés : `id`/`tags` de scène sont acceptés par le schéma (pas d'erreur) ;
`npcs[].scenes`/`emoji` et `graphPos`/`graphSize` sont des champs ajoutés par l'éditeur de
scénario et absents du schéma.

---

## 5. Dérive n°2 — `map.json` (84 erreurs, 42 uniques)

Le schéma décrit un format de **battlemap VTT futur** (`grid_cells`, `props`, `walls`,
`areas`, `links`, `render_mode`) ; les 3 cartes réelles utilisent le format
`mapKind`/`width`/`height`/`tiles`/`markers`/`locationLinks`.

Manquent dans les données (**dans les 6 fichiers**) : `map_kind`, `grid_cells`, `props`,
`walls`, `areas`, `links`, `render_mode` (7 × 6 = 42 erreurs).

Refusées (**7 × 6 = 42 erreurs**) : `description`, `roster`, `mapKind`, `scenarioId`,
`width`, `height`, `locationLinks`.

Fichiers : `game/data/maps/demo-monde-couronne.json`, `demo-quartier-serpent.json`,
`demo-taverne.json` — **14 erreurs chacun** (0/3 valide).

À noter : le **modèle runtime de carte** du client (`MapData.ensure_map_schema`, figé par le
nouveau test `game/scripts/tests/map_schema_contract_test.gd`) est un **troisième format**
encore différent (`schemaVersion`, `renderMode`, `grid`, `fogEnabled`, `playDefaults`…).
`map.json` n'est donc aligné ni sur les fichiers démo versionnés, ni sur le runtime : le
schéma est un document cible non réalisé, ce qui renforce le verdict « réaligner ou
archiver » ci-dessous.

---

## 6. Ce qui est conforme et ce qui n'est pas vérifiable

- **`bot.json` : conforme** — 2 fichiers miroirs (`data/bots/archetypes.json` ==
  `game/data/bots/archetypes.json`), 7 archétypes chacun, **0 erreur**. Le schéma peut être
  branché tel quel (validation à l'import ou en CI).
- **`ruleset.json` : conforme** — `dnd_complete.json` et `naheulbeuk_simple.json`,
  **0 erreur**. Complète utilement `Ruleset.validate()` côté GDScript (qui ne contrôle que
  la sémantique des formules, pas la forme JSON).
- **`character.json` / `save_game.json` / `session_model.json` / `dice_roll.json` :
  non couverts** — aucune donnée versionnée :
  - personnages et sauvegardes vivent dans `user://` (`game/scripts/autoload/game_data.gd:8,13-14`) ;
  - `dice_roll` est un résultat d'exécution (contrat de sérialisation, pas un fichier) ;
  - `session_model` est embarqué dans `active_game`/`save_game` (journal, ordre de tour,
    quickbars) ;
  - l'échantillon versionné `data/sessions/game-*.json` (gitignoré à l'origine) est un
    `SessionRecord {state, scenario}` de l'*ancien serveur autoritaire* : il ne correspond
    **à aucun** des deux schémas candidats (`save_game.json` ni `session_model.json`).
- **Fichiers JSON hors contrat (4)** :
  `data/tiles.json` et `game/data/tiles.json` (catalogue de tuiles, aucun schéma),
  `data/sessions/game-1788371990086-2st4h.json` (échantillon runtime),
  `game/data/tests/dice_cases.json` (fixture de test du moteur de dés = spec, pas une donnée).

### Doublons / miroirs

- **15 paires `data/**` ↔ `game/data/**` byte-identiques** (SHA-256) : 11 scénarios,
  3 cartes, 1 bots. Le dossier racine `data/` est un **miroir non maintenu** : 12 scénarios
  côté client, 11 côté racine — `game/data/scenarios/demo-valbois.json` n'a pas de miroir.
  Le client charge `res://data/` = `game/data/` ; les seuls consommateurs de `data/` racine
  sont deux fichiers **archivés** (`server/legacy/scenario_loader.ts:7`,
  `server/legacy/game_session.ts:28`).
- `data/schemas/character.json` est dupliqué **à l'identique** dans
  `game/data/schemas/character.json` (même SHA-256) : une seule source à terme.

---

## 7. Corrections apportées : aucune (et pourquoi)

Aucun fichier de données n'a été modifié (les données sont la référence d'exécution, ADR-004).
**Aucun schéma n'a été corrigé** non plus : les 8 schémas sont syntaxiquement valides, leurs
`$ref` se résolvent et aucun mot-clé non supporté n'est utilisé. Les écarts constatés sont des
**choix de format cible non réalisés** (snake_case, structures VTT, `required` non produits),
pas des erreurs de schéma isolées. Corriger le schéma sans décision de format reviendrait à
réécrire le contrat cible en silence — ce que l'ADR-004 interdit à ce stade.

---

## 8. Recommandations (décision requise, ADR-004)

| Schéma | Verdict | Action recommandée | Effort | Risque |
|---|---|---|---|---|
| `scenario.json` | **réaligner (P1)** | Décider le format canonique : soit réaligner le schéma sur le format réellement lu (`camelCase`, `transitions` par scène, `startSceneId`, champs éditeur `graphPos`/`graphSize`/`emoji`/`npcs[].scenes`), soit planifier une migration des données. Le réalignement du schéma est nettement moins risqué (12 fichiers produits par l'éditeur). | M | Migration de données = L, élevé |
| `map.json` | **réaligner ou archiver (P1)** | Séparer le contrat « carte actuelle » (`mapKind`/`width`/`height`/`tiles`/`markers`/`locationLinks`) du format VTT cible (`grid_cells`/`props`/`walls`/`areas`/`render_mode`). Aujourd'hui le schéma ne décrit aucune carte du dépôt. | M | Faible |
| `bot.json` | **brancher (P2)** | 0 erreur : valider `data/bots/archetypes.json` à l'import (client) et/ou en CI (`--only bot`). | S | Très faible |
| `ruleset.json` | **brancher (P2)** | Compléter `Ruleset.validate()` par ce schéma dans le pipeline de contenu (ou en CI) ; les 2 rulesets sont conformes. | S | Très faible |
| `character.json` | **réaligner (P3)** | Aligner sur la fiche réellement sauvegardée dans `user://characters.json` puis valider à la sauvegarde ; sinon archiver le schéma. Nécessite des fixtures versionnées pour être testable en CI. | M | Moyen |
| `save_game.json` | **archiver ou réaligner (P2)** | Aucune donnée ne correspond (client = `active_game` camelCase, serveur = `SessionRecord`) : soit réaligner sur le format réel, soit archiver et assumer que la sauvegarde reste hors contrat jusqu'à une phase dédiée. | S/M | Faible |
| `session_model.json` | **brancher via tests (P3)** | Schéma utile (journal/ordre de tour/quickbars) mais aucune donnée versionnée : générer des fixtures depuis les tests client (`session_model_test.gd`) et les valider en CI. | S | Faible |
| `dice_roll.json` | **brancher via test de contrat (P3)** | Aucune donnée par nature : valider des sorties d'exemple du moteur GDScript (golden file) en CI, ou assumer le schéma comme documentation du sérialisé. | S | Faible |

Mesure transverse recommandée (phase suivante) : **un seul emplacement canonique** pour les
données (`game/data/`, chargé via `res://data/`) et suppression du miroir racine `data/`
quand les derniers consommateurs archivés (`server/legacy/*`) disparaissent ; idem pour le
doublon `game/data/schemas/character.json`.

Intégration CI possible **dès maintenant** sans bloquer sur la dérive connue (le workflow
existant [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) exécute déjà
`npm run typecheck`/`npm test` côté serveur et la porte Godot ; il suffit d'y ajouter un step
Python) :

```powershell
# gate vert (schémas déjà alignés)
python tools/refactor/validate_data.py --only bot,ruleset
# rapport de dérive complet en artefact (code 1 attendu tant que scenario/map dérivent)
python tools/refactor/validate_data.py --json-output schemas_report.json
```

---

## 9. Limites du constat

- Le validateur implémente un **sous-ensemble** de JSON Schema (voir §1) ; il couvre 100 %
  des mots-clés réellement utilisés mais ne vaut pas certification de conformité.
- Les compteurs incluent les **miroirs** `data/`↔`game/data/` (les totaux « hors miroirs »
  sont fournis) ; 15 paires identiques sur 18 fichiers uniques.
- Aucune donnée n'a été modifiée pour « faire passer » un schéma ; aucun fichier sous
  `game/` n'a été touché.
- `save_game`/`session_model`/`character` restent **non mesurables en CI** sans fixtures
  versionnées : leur statut « non couvert » est un constat, pas une validation.
