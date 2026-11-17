# Audit serveur Node/TypeScript + contrat de données

> Audit **READ-ONLY** — aucun fichier existant modifié, aucun commit.
> Périmètre : `server/src/**`, `server/scripts/**`, `server/package.json`, `server/tsconfig.json`,
> `data/schemas/**`, `docs/{STACK,MULTIPLAYER,MOTEUR_DES,SESSION_PROTOCOLE,SPEC_RULESET_IA,MCP,ARCHITECTURE}.md`,
> et comparaison avec le client `game/scripts/core/rules/*.gd`, `game/scripts/multiplayer/`, `game/data/tests/dice_cases.json`.

| Fait | Valeur |
|---|---|
| Date | 2026-11-17 |
| HEAD audité | `4514c61` (branche locale, état Lead commité/poussé) |
| Environnement | Windows, Node `v24.19.0`, npm `11.17.0`, TypeScript installé `7.0.2` |
| Volumétrie serveur | **26 fichiers TS, 4 863 lignes, 155 Ko** (`(Get-Content).Count` ; `tools/refactor/metrics.ps1` affiche +26 lignes car il compte la ligne finale) |
| Godot | **indisponible dans cet environnement** (`GODOT_BIN` vide, `godot` absent du PATH) : le test GDScript `dice_engine_test` n'a pas pu être rejoué ici ; la comparaison des dés est statique + côté TS |

---

## 0. Résumé exécutif

1. **Le serveur ne compile plus.** `npm run typecheck` et `npm run build` échouent avec 5 erreurs TS, toutes dues à un seul événement : le commit `8ecbfe2` « refactor: split ai-gm.ts into narrative/ modules (Phase 5) » (2026-09-30) a supprimé **1 812 lignes** de `server/src/ai-gm.ts` (dont l'objet exporté `AiGM`) sans mettre à jour `game_session.ts` et `mcp/gm_server.ts`. 18 fonctions autrefois exposées n'existent plus nulle part.
2. **Deux points d'entrée sur trois sont cassés au runtime**, pas seulement au typecheck : l'import ESM de `game_session` et de `mcp/gm_server` échoue réellement (`does not provide an export named 'AiGM'`). Seul `src/index.ts` (pooling WebSocket) fonctionne, et c'est le seul couvert par des tests.
3. **Environ la moitié du code serveur (≈ 2 435 lignes / 4 863) n'est atteignable par aucun point d'entrée fonctionnel** : moteur narratif (`game_session`, `bots`, `ai-gm`, `narrative/*`, `mcp/*`) + modules orphelins (`types.ts`, `state_serializer.ts`, `scenario_loader.ts`, `mcp/llm.ts`). Les tests ne les importent pas, donc la CI (inexistante) et `npm test` ne voient pas la casse.
4. **Le moteur de dés existe en 4 fichiers** (2 moteurs + 2 façades) et 3 formats/langages adjacents ; les cas partagés passent côté TS mais la parité n'est pas garantie sur le RNG seedé, le formatage et la forme des résultats de façade.
5. **Les 8 schémas `data/schemas/*.json` ne sont lus par aucun code** (aucun validateur JSON Schema, aucun `ajv` ; seul `zod` est utilisé, à la main, pour le protocole de pooling). Trois schémas au moins sont en dérive totale avec les données réelles (`save_game`, `scenario`, `map`).
6. **La documentation décrit une architecture qui n'existe plus** : `STACK.md` décrit un serveur autoritaire de jeu, `MULTIPLAYER.md`/`SESSION_PROTOCOLE.md` décrivent un hôte Godot autoritaire et un serveur de pooling sans logique de jeu. C'est le second modèle qui est codé.

---

## 1. Inventaire `server/src` (26 fichiers)

Comptage exact (`(Get-Content fichier).Count`). Fichiers > 400 l. en gras (le principe `docs/ARCHITECTURE.md:102` « fichiers < 400 lignes » est violé 4 fois).

| Fichier | Lignes | Responsabilité réelle |
|---|---:|---|
| **`bots.ts`** | **787** | Archétypes de compagnons (7 + 5 enquête), profils par format de quête, construction du pool d'actions par scène, choix pondéré. Port d'un ancien `js/bots.js`. |
| **`rules/dice_engine.ts`** | **762** | Moteur de dés complet : lexer, parser descendant, évaluation AST, comparateur, RNG injectable (scripté/seedé/aléatoire), formatage Markdown. Miroir déclaré de `dice_engine.gd`. |
| **`pooling/server.ts`** | **487** | **Seul serveur réellement lancé** (`index.ts`) : WebSocket `ws`, salons, tickets, rate-limit, relais de signalisation WebRTC, STUN/TURN, `req_id`, arrêt propre. |
| **`mcp/gm_server.ts`** | **411** | Serveur MCP stdio : 4 outils (`classify_action`, `suggest_roll`, `opening_narration`, `resolve_action`), schémas zod, enrichissement LLM OpenAI/Anthropic **dupliqué en interne**. |
| `game_session.ts` | 332 | État de partie serveur, tours, bots, persistance JSON `data/sessions/`, façade dés. **Import cassé (AiGM).** |
| `game_types.ts` | 299 | Types de données du moteur de jeu (contrat supposé aligné sur `data/` + client Godot). |
| `lobby/rooms.ts` | 230 | `RoomManager` : codes 4 chiffres, GM/hôte, capacité, dissolution, P2P host, personnages. |
| `narrative/world_state.ts` | 163 | Faits du monde, chronique, relations PNJ, dynamique d'équipe. **2 erreurs TS + usage de champs inexistants.** |
| `ai-gm.ts` | 157 | Façade MJ IA réduite à des ré-exports + `getQuestFormat*` ; **ne ré-exporte plus `AiGM`**. |
| `lobby/tickets.ts` | 119 | Tickets de reprise de session (TTL 2 min, usage unique, capacité 2 000). |
| `lobby/types.ts` | 119 | Types du protocole pooling v2 (client/serveur). |
| `party_utils.ts` | 105 | Conversions `ClientPartyMember → PartyMember` ; **fonctions jamais appelées hors du fichier**. |
| `lobby/validate.ts` | 104 | Validation zod par type de message, écho de `req_id`, `sanitizeText`. |
| `lobby/rate_limit.ts` | 100 | Fenêtre glissante par (joueur, type), seuils + double seuil → fermeture. |
| `narrative/quest_manager.ts` | 96 | Offres de quêtes secondaires, spawn probabiliste. |
| `state_serializer.ts` | 91 | `serializeGameState`/`scenarioToClient` ; **jamais appelé**. |
| `narrative/action_resolution.ts` | 91 | `classifyAction` (regex FR), `suggestRoll`, `computeDC`, styles de joueur. |
| `dice.ts` | 83 | Façade historique `Dice.roll/formatResult` au-dessus de `rules/dice_engine.ts`. |
| `lobby/protocol.ts` | 75 | `PROTOCOL_VERSION = 2`, codes d'erreur, `withReqId`, `fail`, `extractReqId`. |
| `mcp/llm.ts` | 70 | Enrichissement LLM OpenAI/Anthropic ; **jamais importé** (doublon de `gm_server.ts:67-135`). |
| `types.ts` | 60 | Ancien protocole « serveur autoritaire » v0.1 (`join`, `start_game`, `player_input`…) ; **jamais importé hors type**. |
| `narrative/phrase_pools.ts` | 39 | `applyVars`, `pick` anti-répétition, `MAX_MEMORY`. |
| `mcp/run.ts` | 28 | Entrée `npm run mcp` (stdio) ; échoue à l'import de `gm_server`. |
| `scenario_loader.ts` | 27 | Chargement JSON des scénarios depuis `data/scenarios/` ; **jamais appelé**. |
| `lan_utils.ts` | 21 | Adresses IPv4 LAN pour les logs du pooling. |
| `index.ts` | 7 | Entrée : `dotenv` + `startPoolingServer`. |

`server/scripts` (5 fichiers) : `test_dice_engine.ts` (189), `test_lobby.ts` (300), `test_lobby_integration.ts` (192), plus deux tests E2E en `.mjs` **non branchés** sur npm (`test-pooling.mjs` 112, `test-pooling-extended.mjs` 142).

---

## 2. État réel du typecheck, du build et des tests

### 2.1 `cd server; npm run typecheck` → échec

```
> openquest-server@0.1.0 typecheck
> tsc --noEmit

src/game_session.ts(9,10): error TS2305: Module '"./ai-gm.js"' has no exported member 'AiGM'.
src/mcp/gm_server.ts(16,10): error TS2305: Module '"../ai-gm.js"' has no exported member 'AiGM'.
src/narrative/world_state.ts(58,28): error TS2353: Object literal may only specify known properties, and 'category' does not exist in type 'WorldFact'.
src/narrative/world_state.ts(58,50): error TS2339: Property 'turn' does not exist on type 'AiState'.
src/narrative/world_state.ts(65,22): error TS7015: Element implicitly has an 'any' type because index expression is not of type 'number'.
[exit code: 1]
```

Deux causes distinctes :
- **Cause A (pipeline cassé)** : `game_session.ts:9` et `mcp/gm_server.ts:16` importent `{ AiGM }` d'une façade (`ai-gm.ts:1-157`) qui ne l'exporte pas. `ai-gm.ts` n'exporte plus que des fonctions libres (`classifyAction`, `suggestRoll`, `ensureWorld`, `addWorldFact`…) et des types.
- **Cause B (dérive de type)** : `narrative/world_state.ts:58` pousse `{ text, category, turn }` alors que `WorldFact` (`game_types.ts:145-152`) déclare `{ id, text, sceneIndex, actorName, actionType, flag }` et que `AiState` (`game_types.ts:217-237`) n'a pas de champ `turn`. `world_state.ts:63-66` indexe `Record<number, string[]>` avec une `string`.

### 2.2 `cd server; npm run build` → échec, mais émet quand même `dist/`

```
> openquest-server@0.1.0 build
> tsc

src/game_session.ts(9,10): error TS2305: ...
src/mcp/gm_server.ts(16,10): error TS2305: ...
src/narrative/world_state.ts(58,28): error TS2353: ...
src/narrative/world_state.ts(58,50): error TS2339: ...
src/narrative/world_state.ts(65,22): error TS7015: ...
[exit code: 2]
```

`tsconfig.json:1-16` ne définit pas `noEmitOnError` : `tsc` écrit `dist/` malgré l'échec (25 fichiers `.js`). `dist/` est gitignoré (`.gitignore`), donc un clone propre + `npm start` sans build échoue, et un build raté laisse des artefacts **qui semblent valides** — `dist/index.js` fonctionne (pooling) mais `dist/game_session.js` est inutilisable.

### 2.3 Preuve de rupture runtime (pas seulement typage)

```
npx tsx -e "import('./src/game_session.ts')..."
GAME_SESSION_IMPORT_FAIL: The requested module './ai-gm.js' does not provide an export named 'AiGM'

npx tsx -e "import('./src/mcp/gm_server.ts')..."
GM_SERVER_IMPORT_FAIL: The requested module './ai-gm.js' does not provide an export named 'AiGM'
```

Conséquence : `npm run mcp` (`.cursor/mcp.json`) **ne démarre pas** ; `GameSession`, les bots et le moteur narratif sont inutilisables.

### 2.4 `cd server; npm test` → **vert** (0 exit code)

```
> npm run test:dice && npm run test:lobby && npm run test:lobby:net
dice_engine_test:PASS 112 vérifications
lobby_test:PASS 81 vérifications
lobby_integration:PASS 18 vérifications
[exit code: 0]
```

Le test d'intégration démarre son propre serveur pooling (`test_lobby_integration.ts:106`, port fixe **7891**, ligne 32) et se termine. Extraction des logs serveur de ce run :

```
[pool +] Joueur (7ea84b98)
[pool -] MJ (7ea84b98)
lobby_integration:PASS 18 vérifications
```

**Mais ce vert est trompeur** : `npm test` ne lance **ni typecheck ni build**, et les trois suites n'importent que `rules/dice_engine.ts`, `dice.ts` et `lobby/*` + `pooling/server.ts`. **Aucun test n'importe** `game_session.ts`, `ai-gm.ts`, `bots.ts`, `narrative/*`, `mcp/*`. La casse du §2.1 est donc invisible pour le « filet » actuel.

---

## 3. Duplication du moteur de dés — 4 implémentations + 3 satellites

| # | Fichier | Lignes | Rôle | Atteignable ? |
|---|---|---:|---|---|
| 1 | `game/scripts/core/rules/dice_engine.gd` | 610 | Moteur GDScript complet (client/hôte) | **Oui** — `game_data.gd:4575`, `multiplayer_manager.gd:857`, session UI |
| 2 | `game/scripts/core/rules/dice.gd` | 20 | Façade `Dice.roll/format` → délègue à (1) | Oui (compat) |
| 3 | `server/src/rules/dice_engine.ts` | 762 | Moteur TS « miroir » de (1) | **Non** — seulement via `dice.ts`/`game_session`/MCP, tous cassés |
| 4 | `server/src/dice.ts` | 83 | Façade `Dice.roll/formatResult` → délègue à (3) | Non |
| + | `game/scripts/core/rules/formula.gd` | 560 | **Autre langage** (fiches déclaratives) mais produit des formules de dés via `ruleset.gd:167 expand_roll` | Oui |
| + | `game/scripts/core/rules/ruleset.gd` | 288 | Valide/build les rulesets, étend `1d20 + @mod_str` → formule de dés | Oui |
| + | `game/scripts/session/panels/dice_tray.gd:44-49` | 72 | Mini-normalisation UI `d20 → 1d20` (pas un parseur) | Oui |

### 3.1 Ce qui est identique (volontairement)

Même grammaire EBNF documentée dans les deux en-têtes (`dice_engine.gd:7-25` ≡ `dice_engine.ts:8-21`), mêmes constantes de limites (`dice_engine.gd:27-33` ≡ `dice_engine.ts:23-29`), même arbre `kind ∈ {number,dice,comparison}`, même ordre d'application des modificateurs (expl → reroll → min/max → keep), mêmes messages d'erreur, mêmes cas partagés `game/data/tests/dice_cases.json` (**29 cas**) consommés par les deux tests (`server/scripts/test_dice_engine.ts:22-23` et `game/scripts/tests/dice_engine_test.gd:13`).

### 3.2 Divergences réelles constatées (à corriger ou à documenter)

1. **Formatage non partagé** : le serveur produit du **Markdown** (`dice_engine.ts:163` `🎲 **N succès**`, `:167` `(${formula})`), le client du **BBCode Godot** (`dice_engine.gd:92` `🎲 [b]%d succès[/b]`, `:108`). Toute bascule d'autorité de dés change le rendu/journal.
2. **RNG seedé non compatible inter-langages** : TS utilise mulberry32 (`dice_engine.ts:715-725`), GD utilise `RandomNumberGenerator` seedé (`dice_engine.gd:553-559`). Les tests ne vérifient que la reproductibilité **dans** chaque langage, jamais l'égalité inter-langages ; `seed: 4242` ne donne donc pas la même séquence en GDScript et en TS. `docs/MOTEUR_DES.md:76-87` laisse croire à un contrat RNG commun.
3. **Façades non équivalentes** : la façade TS (`dice.ts:12-25`) ne conserve pas `ok`, `sides`, `count`, `left`, `right`, `children`, `weights`, et son erreur est `{ error }` sans `ok:false` ni `formula` (`dice.ts:27-35, 46`). Or `data/schemas/dice_roll.json:7` **exige `ok` et `formula`** : le résultat de la façade TS ne valide pas le contrat de son propre schéma.
4. **Façades non symétriques** : `Dice.format(result)` côté GD accepte le dictionnaire complet (`dice.gd:19-20`), `Dice.formatResult` côté TS reconstruit un objet partiel (`dice.ts:63-82`).
5. **Comportements permissifs identiques mais non spécifiés** : les poids `{face:poids}` sont silencieusement ignorés quand la comparaison porte sur une somme (`1d20+5>=15{6:2}` → `total=15`, poids perdus), et les modificateurs doivent être collés au dé (`1d20advkeeph1` → erreur de lexer) — vérifié à l'exécution sur le moteur TS, les deux moteurs partageant la même structure.
6. **Le contrat « deux implémentations, un contrat » (`docs/MOTEUR_DES.md:8-18`) n'est pas testé de bout en bout** : aucun cas partagé ne couvre le seed inter-langages, le formatage, l'avantage+désavantage combinés, ni les erreurs de forme.

### 3.3 Recommandation : source unique de vérité

**Décision recommandée : une seule implémentation exécutable, le moteur GDScript ; `dice_cases.json` + `dice_roll.json` restent la spécification. Supprimer (ou archiver) la chaîne TS de jeu.**

Justification (alignée sur l'architecture réellement codée) : `docs/MULTIPLAYER.md:24-28` et `docs/SESSION_PROTOCOLE.md:10-14` déclarent l'**hôte Godot autoritaire** et le serveur de pooling **sans logique de jeu** ; `src/index.ts:6` ne démarre que le pooling ; le moteur TS n'est plus atteignable que par des modules cassés. Faire du TS la référence obligerait à ressusciter `AiGM` + `game_session` + `bots` et à réimplémenter un serveur autoritaire, ce que `STACK.md:10-23` décrit mais que le code a abandonné.

Plan de migration proposé :

1. **Trancher l'architecture** (1 décision, pas de code) : « hôte P2P autoritaire » (état actuel) **ou** « serveur autoritaire anti-triche » (roadmap `STACK.md:144`). Les deux cibles ne peuvent pas coexister avec un moteur de dés dupliqué.
2. Si « hôte P2P autoritaire » : supprimer `server/src/dice.ts`, `server/src/rules/dice_engine.ts` et les appelants morts (`game_session.ts`, `mcp/*`, `bots.ts`, `narrative/*`) ; conserver `dice_cases.json` comme **golden file** exécuté uniquement par `dice_engine_test.gd`.
3. Si « serveur autoritaire » ou « MCP conservé » : restaurer/écrire une **façade `AiGM` unique** (`ai-gm.ts`), supprimer `server/src/dice.ts` (appeler directement `rollDice`), et ajouter un **test de contrat inter-langages** qui exécute `dice_cases.json` avec `seed` et compare les séquences après normalisation — ou qui interdit formellement le seed côté serveur (RNG imposé).
4. Dans les deux cas : un seul formateur (le formatage serveur Markdown de `dice_engine.ts:155-181` est inutilisé ; le client impose le BBCode), et ajouter un cas « comparaison avec poids sur une somme » au fichier partagé pour figer le comportement permissif.

À noter : `data/schemas/dice_roll.json` est un bon contrat de résultat mais n'est pas branché (cf. §4). Il devrait être la référence unique des champs sérialisés réseau/journal, indépendamment du langage.

---

## 4. Contrat `data/schemas` — couverture et validation effective

### 4.1 Constat central : 8 schémas, **zéro validateur**

- Aucune dépendance JSON Schema (`server/package.json:21-31` : `ws`, `dotenv`, `typescript`, `tsx`, `@types/ws`, `zod`, SDK MCP ; pas d'`ajv`).
- Aucun fichier de code ne lit `data/schemas/*` : seul `ruleset.gd:10` le mentionne en commentaire. Les seules validations réelles sont :
  - `server/src/lobby/validate.ts:32-59` : zod **manuel** pour les 13 types du protocole pooling uniquement ;
  - `server/src/mcp/gm_server.ts:31-61` : zod pour les entrées d'outils MCP (sous-ensemble des types serveur, pas des schémas) ;
  - `game/scripts/core/rules/ruleset.gd:17` : validation maison des rulesets (client uniquement).
- `data/schemas/character.json` existe **en double** : `data/schemas/character.json` et `game/data/schemas/character.json`.

**Conclusion : les schémas sont de la documentation, pas un contrat vérifié.** Le principe `docs/ARCHITECTURE.md:100` (« `data/schemas/` est la source de vérité ») n'est pas implémenté.

### 4.2 Dérives déjà matérialisées (données réelles vs schéma)

| Schéma | Exige (extrait) | Données/code réels | Verdict |
|---|---|---|---|
| `save_game.json:8-19` | `game_id`, `scenario_id`, `party_members`, `current_scene_id`, `map_play_state`, `created_at` (snake_case) | Client : `id`, `scenarioId`, `party`, `currentSceneIndex`, `mapPlayState`, `startedAt` (`game_data.gd:1232-1258`) ; serveur : `SessionRecord {state, scenario}` avec `GameState` camelCase (`game_session.ts:31-34`, `game_types.ts:244-270`) | **Aucune des deux implémentations ne produit ce document** |
| `scenario.json:8-18` | `quest_format`, `roster`, `start_scene_id`, `transitions`, `maps` en snake_case, transitions top-level | `data/scenarios/*.json` : `questFormat` camelCase, transitions **par scène** (`data/scenarios/demo-couronne-fracturee.json:2` et `:17`), pas de `maps`/`start_scene_id` ; type serveur `Scenario` (`game_types.ts:95-105`) sans transitions | Incompatible |
| `map.json:10-18` | `map_kind`, `grid_cells`, `props`, `walls`, `areas`, `links`, `render_mode` | Cartes réelles : `mapKind`, `width`, `height`, `tiles`, `markers`, `locationLinks` (`data/maps/demo-monde-couronne.json`) ; type serveur `MapData` (`game_types.ts:133-143`) : `mapKind`, `width`, `height` | Incompatible |
| `character.json:7-16` | `roster` et `backstory` **requis**, `additionalProperties:false` | `ClientPartyMember` (`party_utils.ts:4-20`) : `isHuman`, `isPlayer`, `clientId`… non couverts ; `Character` serveur (`game_types.ts:22-32`) : `roster?`, `backstory?` optionnels | Dérive |
| `bot.json:7-18` | 10 champs requis | Données identiques dans `data/bots/archetypes.json` (lu par **le client** `game_data.gd:1029`) **et** recopiées en dur dans `bots.ts:68-153` (serveur) → deux sources, pas de validation | Duplication |
| `dice_roll.json:7` | `ok` + `formula` requis ; `kind/total/tags/rolls/modifier` si `ok` | Moteur TS conforme, **façade `dice.ts` non conforme** (§3.2-3) ; aucune validation au réseau | Contrat non appliqué |
| `session_model.json` | `journal`, `turnOrder`, `quickbars` (camelCase) | Implémenté côté client (documenté `docs/ARCHITECTURE.md`), inconnu du serveur | Client-only |
| `ruleset.json` | champs/dérivés/jets/tables | Implémenté côté client uniquement (`ruleset.gd:17`, `formula.gd`) ; aucun équivalent serveur/MCP | Client-only |

### 4.3 Champs non validés / risques

- `register_character` n'est validé que comme `z.record(z.string(), z.unknown())` (`lobby/validate.ts:49`) : **aucune limite de taille**, aucun contrôle des 6 stats, du `hp`/`ac`, ni des champs inconnus. Le personnage est stocké puis **rediffusé à tous les joueurs du salon** (`lobby/rooms.ts:165-176`, `pooling/server.ts:361-371`) : surface d'injection/DoS (payload `ws` par défaut jusqu'à 100 Mio).
- `signal.payload` est `z.unknown()` (`validate.ts:51-58`) : relayé tel quel, sans contrôle de taille autre que la socket.
- `get_game_state`/`start_game`/`dice_roll` de `types.ts:16-36` n'existent plus dans le protocole réel : un client v0.1 obtiendrait `UNKNOWN_TYPE`.

---

## 5. Code mort, dettes et zones sans tests

### 5.1 Modules jamais atteignables (mesuré par recherche d'imports)

| Module | Lignes | Preuve |
|---|---:|---|
| `types.ts` | 60 | importé en type seulement par `party_utils.ts:2` ; aucun usage runtime |
| `state_serializer.ts` | 91 | `serializeGameState`/`scenarioToClient` appelés nulle part (seul import : `types.ts:4`) |
| `scenario_loader.ts` | 27 | `loadAllScenarios`/`loadScenario` appelés nulle part |
| `mcp/llm.ts` | 70 | jamais importé ; doublon de `gm_server.ts:67-135`, avec **modèles par défaut divergents** (`llm.ts:57` `claude-sonnet-4-20250514` vs `gm_server.ts:109` `claude-3-5-haiku`) |
| `party_utils.ts` (fonctions de conversion) | ~80 | `clientPartyToMembers`/`clientCharacterToMember`/`buildMultiplayerParty` ne sont utilisés qu'entre eux |
| Chaîne moteur narratif | ≈ 2 187 | `game_session.ts` (332) + `bots.ts` (787) + `ai-gm.ts` (157) + `narrative/*` (389) + `dice.ts` (83) + `mcp/gm_server.ts` (411) + `mcp/run.ts` (28) : accessible seulement via MCP, lui-même cassé à l'import |

**≈ 50 % des lignes serveur ne sont atteignables par aucun point d'entrée fonctionnel.** Aucun `TODO/FIXME/HACK` dans `server/src` (0 occurrence) : la dette n'est pas tracée.

### 5.2 Le trou du refactor Phase 5 (preuve par historique)

`git show --numstat 8ecbfe2` : `ai-gm.ts` **+82 / −1 812** ; `narrative/` +389 lignes nettes (91+39+96+163). Fonctions perdues (vérifiées absentes aujourd'hui) : `createInitialState`, `resolveAction`, `openingNarration`, `humanGmOpening`, `initWorld`, `initQuestFormat`, `getSceneHooks`, `getLivingSceneContent`, `buildSceneBridge`, `formatSceneTransition`, `ensureSceneGoal`, `getSceneGoal`, `computeSceneGoal`, `resetSceneMemory`, `getPartyMoodLabel`, `getWorldSummary`, `addChronicleEntry`, `narrateOutcome`. Seules les fonctions « feuilles » ont survécu ; **l'orchestrateur `AiGM` a disparu** alors que `ARCHITECTURE.md:37` le décrit comme façade < 400 lignes censée rester le point d'entrée.

### 5.3 Documentation divergente

| Doc | Affirmation | Réalité |
|---|---|---|
| `STACK.md:10-23` | « Le serveur Node est l'autorité », protocole `join`/`player_input` | Serveur = pooling ; protocole v2 sans `player_input` (`lobby/types.ts:42-61`) |
| `MULTIPLAYER.md:24-28` | hôte Godot autoritaire, serveur sans logique de jeu | Conforme au code — contredit `STACK.md` |
| `SESSION_PROTOCOLE.md:12-14` | serveur « autorité limitée » | Conforme (`pooling/server.ts`) |
| `MCP.md:15-21` | 5 outils dont `roll_dice` | `roll_dice` **n'existe pas** (`gm_server.ts:187,209,249,332` : 4 outils) ; MCP ne démarre pas |
| `MOTEUR_DES.md:8-18, 105-106` | deux implémentations validées par les cas partagés | Le test TS passe, mais le moteur TS n'est plus atteignable par aucun flux de jeu et le test GDScript n'est pas exécutable ici |
| `ARCHITECTURE.md:35-37` | `mcp/` + `narrative/` + façade `ai-gm.ts` opérationnels | `mcp/run.ts` casse à l'import ; façade sans `AiGM` |
| `MULTIPLAYER.md:186` | `signalType` = offer/answer/ice | `types.ts:57` + `validate.ts:54` acceptent aussi `meta` |
| `SESSION_PROTOCOLE.md:45-50` | rate-limit documenté | Conforme, mais le client n'envoie jamais `ping` (aucun usage dans `multiplayer_manager.gd`) — seuil `ping` 4/s inutilisé |

### 5.4 Packaging / CI

- `server/package.json:21-24` place `ws` et `dotenv` en **devDependencies**, alors qu'ils sont importés au runtime (`pooling/server.ts:14`, `types.ts:59`, `index.ts:1`, `mcp/run.ts:9`). `npm ci --omit=dev && npm start` échoue.
- `server/package.json:15` : `test` ne lance pas `typecheck` ; **aucun workflow GitHub** (`.github/workflows/` inexistant) → le build cassé depuis le 2026-09-30 n'a jamais été bloqué.
- `server/scripts/test-pooling.mjs` et `test-pooling-extended.mjs` ne sont **pas dans `package.json`**, exigent un serveur lancé sur 8080, et sont **périmés** : ils attendent `code: "NOT_GM"` et un `create_room` avec `role: "player"` que `validate.ts:39` rejette en `INVALID_PAYLOAD`.
- `test_lobby_integration.ts:32` fige le port 7891 (pas de port éphémère) → échec si occupé ; pas de `server.close()` en cas d'exception.
- `game_session.ts:28` persiste dans `data/sessions/` à la racine du dépôt (gitignoré), contrairement au commentaire « server/data/sessions » (`game_session.ts:303`).
- `.env.example` déclare `MCP_PORT=3100` : **absent du code** (aucun `MCP_PORT` dans `src/`).

### 5.5 Zones sans aucun test

Aucune suite ne couvre : `game_session`, `bots` (787 l. de génération de texte et choix d'actions), `ai-gm`/`narrative/*` (orchestration narrative), `mcp/*`, `state_serializer`, `types`, `party_utils`, `scenario_loader`, `lan_utils`, ni les handlers `resume_session`/`signal`/`set_p2p_host`/`leave_room` de `pooling/server.ts` au-delà de ce que fait l'intégration (18 vérifications).

---

## 6. Top 8 des cibles priorisées

| # | Problème | Action | Risque si non traité | Effort | Test de protection |
|---|---|---|---|---|---|
| 1 | `typecheck`/`build`/`mcp` cassés depuis `8ecbfe2` (5 erreurs) | Trancher : restaurer `AiGM` complet **ou** supprimer `game_session.ts`+`mcp/*`+`bots.ts`. Corriger `world_state.ts:58-66` (champs `category`/`turn`/clé `sceneId`). | Impossible de livrer un serveur compilé ; MCP mort ; confiance dans le dépôt | M (restaurer ≈ 1 800 l.) / S (supprimer) | Ajouter `npm run typecheck` en pré-requis de `npm test` + un test d'import de **chaque** point d'entrée |
| 2 | 4 implémentations de dés + 3 satellites, parité non testée | Décision §3.3 : GDScript seule implémentation exécutable ; TS supprimé ou « référence MCP » ; un seul formateur | Divergence silencieuse de résultats/format entre solo, hôte et MCP | M | Étendre `dice_cases.json` (seed, format, poids) et faire échouer le build si les deux suites ne lisent pas le même fichier |
| 3 | `data/schemas/` = documentation morte, 3 schémas déjà faux | Choisir : (a) contract-as-code → `ajv`/zod généré + validation au chargement et sur `register_character` ; (b) documentation → archiver dans `docs/` et retirer le mot « source de vérité » | Faux sentiment de contrat ; données invalides acceptées en réseau | M | Test de contrat qui valide **un exemple réel** de chaque `data/` contre son schéma |
| 4 | ~50 % du code serveur est mort et non compilable | Supprimer ou isoler (package `experimental/` non compilé) : `types.ts`, `state_serializer.ts`, `scenario_loader.ts`, `mcp/llm.ts`, chaîne moteur si #1 tranche « pooling seul » | Coût de maintenance, faux positifs d'audit, surface d'attaque | S (suppression) | `tsc --noEmit` + grep d'imports dans la CI ; `depcheck` |
| 5 | `ws`/`dotenv` en devDependencies ; pas de `noEmitOnError` | Déplacer en `dependencies` ; ajouter `noEmitOnError: true` (ou nettoyer `dist/` avant build) | `npm start` casse en prod ; artefacts périmés « valides » | S | Job CI `npm ci --omit=dev && npm run build && node -e "import('./dist/index.js')"` (sans écouter) |
| 6 | Aucune CI, tests verts malgré un build cassé | Workflow GitHub : `typecheck` → `build` → `test` (+ `dice_engine_test` Godot en job séparé) | Régression silencieuse (celle-ci a tenu 6 semaines) | S | Le workflow lui-même + un smoke test d'import des entrées |
| 7 | Protocole v2 non couvert (resume, signal, leave, gm_disconnected) et scripts `.mjs` périmés | Compléter `test_lobby_integration.ts` (signal relay, `set_p2p_host`, fermeture MJ), supprimer/remettre à jour les `.mjs`, port éphémère | Casse de la reprise de session en LAN, non détectée | S/M | Tests d'intégration existants + cas `room_closed`/`resumed` |
| 8 | Documentation contradictoire (STACK vs MULTIPLAYER, MCP `roll_dice`) | Réécrire `STACK.md` (rôle pooling), corriger `MCP.md` (4 outils, état cassé), marquer `MOTEUR_DES.md` « dépende de la décision #2 » | Décisions de refactor prises sur une doc fausse | S | Revue de doc dans la PR de refactor |

**Top 3 à attaquer en premier** : #1 (débloquer le build/MCP), #2 (trancher les dés), #3+#4 (contrat réel + suppression du mort). #5/#6 sont des prérequis de sécurité de tout le plan.

---

## 7. Méthode et limites

- Commandes exécutées depuis `server/` : `node --version`, `npm --version`, `npm run typecheck`, `npm run build`, `npm test`, `npx tsx -e "import(...)"` (imports sans écoute réseau). Tests réseau auto-hébergés (port 7891) autorisés par la mission, serveur arrêté en fin de test.
- Comptage des lignes : `(Get-Content <fichier>).Count` ; écart de +1/fichier avec `tools/refactor/metrics.ps1` (ligne finale comptée).
- Recherche d'imports : `Select-String`/`grep` sur `server/src`, `server/scripts`, `game/scripts`.
- **Limites** : Godot indisponible (`GODOT_BIN` vide) → le test `dice_engine_test.gd` n'a pas été rejoué ici (le baseline Godot est couvert par un autre agent) ; aucune donnée de production n'a été modifiée ; un fichier `data/sessions/game-*.json` préexistant (gitignoré) atteste d'un ancien run de `game_session`, il n'a pas été touché.
- Aucun commit, aucun fichier existant modifié ; seul livrable écrit : ce fichier.
