# Annexe 1 — Le moteur de données de Let's Role : ce qui est réutilisable dans OpenQuest JDR

> ℹ️ **Analyse brute** — document factuel (mesures, chemins, licences, pièges). Il ne constitue plus un plan de reprise de code : voir [ADAPTATION.md](ADAPTATION.md) — **aucune copie**, uniquement des idées réimplémentées pour notre jeu.

> **Périmètre** : `D:\git\OpenQuest_jdr\.external\letsrole\js-engine` et `…\shared`.
> **Instantanés** : `js-engine` @ `cc432eb` (2025-07-26, v1.5.3) ; `shared` @ `4ab201a` (2026-01-11).
> Les références `chemin:ligne` sont relatives à `D:\git\OpenQuest_jdr\.external\letsrole\` (projet local : `D:\git\OpenQuest_jdr\`).
> Mesures sur disque, **sans `npm install`, sans build, sans réseau**.

## 1. Résumé exécutif

Let's Role est une plateforme de **feuilles de personnage déclaratives**, pas un moteur de règles. Deux briques utiles pour OpenQuest : (a) **`js-engine`**, interpréteur JavaScript restreint (MIT) pour les scripts de système ; (b) **`shared`** (LGPL-3.0), bibliothèque de modèles de données et de deux grammaires PEG (dés, références).

`shared` n'est ni un paquet npm ni une bibliothèque publiée : `shared/package.json:1-17` n'a ni `name`, ni `version`, ni `license` ; les hôtes l'importent en **dossier frère** (`gameserver/tsconfig.json:22`). `js-engine` est une dépendance **git** (`front/package.json:65`), pas un paquet de registre. Rien à installer ici.

Le vrai gisement pour OpenQuest est double : les **deux grammaires PEG** (`grammar.pegjs`, 605 l. ; `reference.pegjs`, 330 l.) et les **schémas de données** (dés, scène, ordre de tour, journal). Le reste (`shared/System`, 63 fichiers, 6 707 l.) est un moteur de rendu DOM inutilisable côté Godot. Côté OpenQuest, l'existant est minimal : `server/src/dice.ts:27-57` et `game/scripts/core/rules/dice.gd:10-35` ne gèrent que `NdM±K` par regex ; l'apport de Let's Role est l'**expressivité** (keep/adv/expl/reroll/tags/comparaisons pondérées) et des **contrats de données** éprouvés.

Point de vigilance : `shared` est sous LGPL v3 → copier ou traduire un fichier = œuvre dérivée (même licence, publication des sources, mention). `js-engine` est MIT (`package.json:13`, sans fichier LICENCE).

**Tableau 1 — Synthèse des briques**

| Brique | Chemin | Volume | Dépendances | Licence | Verdict |
|---|---|---|---|---|---|
| Interpréteur JS sandbox | `js-engine/index.js` + `lib/` | 9 fichiers, 1 792 l. (+ 1 330 l. de tests) | `acorn`, `hoister` | MIT | inutile pour Godot ; tel quel côté Node |
| Modèles de dés | `shared/Dice*.ts` | 351 l. | types TS seuls | LGPL-3.0 | portable, cœur du sujet |
| Grammaire des dés | `shared/grammar.pegjs` | 605 l. | RNG injecté | LGPL-3.0 | spec à porter en GDScript (M/L) |
| Grammaire des références | `shared/reference.pegjs` (+ `reference.ts` généré) | 330 l. / 2 218 l. généré | callbacks hôte | LGPL-3.0 | portable (M) |
| Données de scène / tokens | `shared/Scene/*` | 388 l. | `DrawingsData`, `Journal` | LGPL-3.0 | schéma à adapter (M) |
| Journal, tour, quickbar, médias | `shared/*.ts` | 225 l. | types seuls | LGPL-3.0 | portable (S/M) |
| Feuille de personnage (DOM) | `shared/System/` | 63 fichiers, 6 707 l. | `inversify`, DOM | LGPL-3.0 | inspirant seulement |
| Icônes | `shared/icons/` | 4 133 l. + 5 polices (~14,9 Mo) | game-icons.net | amont à vérifier | inspirant seulement |

## 2. `js-engine` — interpréteur JavaScript restreint

### 2.1 Rôle et API publique

Le dépôt évalue du JavaScript pour le compte de la plateforme (scripts de feuille). L'API tient en 6 lignes (`index.js:1-6`) :

```js
const { safeEval, FunctionFactory } = require('./evaluator');
module.exports = safeEval;
module.exports.eval = safeEval;
module.exports.FunctionFactory = FunctionFactory;
module.exports.Function = FunctionFactory();
```

`safeEval(src, parentContext)` compile puis évalue et retourne la **dernière valeur** (`lib/evaluator.js:172-180`, via `finalValue(evaluateAst(tree, context))`) ; `prepareAst` = `acorn.parse` + `hoist(tree)` (`lib/evaluator.js:145-153`) ; `FunctionFactory` construit des fonctions contrôlées (`:156-169`).

**Consommation réelle** : le *front* déclare `"js-engine": "git+https://gitlab.com/letsrole/js-engine#semver:1.3.3"` (`front/package.json:65`) et l'injecte dans `shared` via l'adaptateur `SharedAdapter.safeEval` (`shared/System/SharedAdapter.ts:1-11`, appelé en `shared/System/CodeExecutor.ts:113`). Dérive de version à noter : le clone est en `1.5.3` (`js-engine/package.json:3`) alors que `shared` journalise « JS Engine v1.3.3 » (`shared/System/CodeExecutor.ts:112`). Aucune publication npm visible.

### 2.2 Environnement d'exécution et limites

- **Aucun `vm`, aucun sous-processus** : seuls `acorn` et `hoister` sont requis (`lib/evaluator.js:1-5` ; aucun `require('vm')` dans `lib/`). L'AST est interprété **dans le processus hôte** par un `switch` maison (`lib/walker.js:14`, `88-662`).
- **JavaScript moderne** : `ecmaVersion: 2020` (`lib/evaluator.js:8-12`), *optional chaining* (`lib/walker.js:611-614`) et *spread* (`lib/functions.js:112-126`) fonctionnent — alors que la doc officielle affirme encore « No arrow function, no for...of loops… ECMAScript 2009 » (`tools/system-builder-ai-document.md:3`) : doc en retard sur le moteur.
- **Anti-pollution de prototypes** : primitives *wrappées* (`lib/primitives.js:151-167`), écritures filtrées (`lib/utils.js:37-57` : `if (property === "__proto__" || ...) return false`), `Function` neutralisé (`lib/walker.js:30-35`). 13 cas de test dédiés (`js-engine/test/sandbox.js:4-124`), dont `[].slice.constructor('return this')()`.
- **Boucles bornées** : compteur à 1 000 000 d'itérations (`lib/walker.js:12`, `lib/statements.js:4`, `lib/infinite-checker.js:12-16`) ; pas de limite CPU/mémoire ni de temps hors hôte.
- **Tolérance de re-déclaration** : pré-traitement source→AST qui transforme `let/const` redéclarés en affectations (`lib/evaluator.js:16-142`), avec repli regex `/\b(let|const)\b/g → var` (`:129-141`).

Conclusion : interpréteur **défensif**, pas un bac à sable de sécurité absolu — suffisant pour du code d'auteur, insuffisant pour du code hostile arbitraire.

### 2.3 Ce que permet un « système de feuille »

Le contexte injecté (`shared/System/CodeExecutor.ts:41-109`) définit tout le vocabulaire d'un script : `log`, `_` (traduction), `wait`, `Dice`, `DiceBuilder`, `RollBuilder`, `Bindings`, `Prompt`, `Tables`, `Math`, `each`, plus les **hooks** `init`, `initRoll`, `getCriticalHits`, `getBarAttributes`, `getReferences`, `drop`, `dropDice` (`:93-99`). La référence publique (374 l.) est `tools/system-builder-ai-document.md:118-374` : classes `Sheet`, `Dice`, `DiceBuilder`, `Bindings`, `Table`, globales `sheet`, `init`, `drop`, `initRoll`, `getReferences`, `getBarAttributes`, `getCriticalHits`.

Côté données, une feuille est un **sac de chemins pointés** dans `character.data` / `token.data` (`shared/System/CharacterSheet.ts:186-216`), persistés par événements (`:249-297`), avec des champs calculés évalués par le moteur de références (`:479-517`). C'est ce modèle « champs déclarés + formules à références croisées » qui est le plus transposable à Godot.

### 2.4 Qualité et licence

1 792 lignes de `lib/`, dont un `walker.js` monolithique de 666 l. ; `lib/expressions.js` (208 l.) et `lib/statements.js` (259 l.) exposent des *factories* de handlers (`:3`, `:6`) **qu'aucun fichier n'importe** : ~467 l. de code mort d'un refactor inachevé. Tests : 9 fichiers / 1 330 l. / 161 cas (`tape`, `package.json:7`), CI GitLab (`.gitlab-ci.yml:20-34`). Pas de TypeScript, de build ni d'ESLint. Licence **MIT** (`package.json:13` ; auteurs Matt McKegg, Jonathan Prevost `:14`) mais **aucun fichier LICENCE** : à la copie, conservez l'avis MIT vous-même.

## 3. `shared` — modèles, grammaires, moteur de feuille

### 3.1 Nature du dépôt

87 fichiers `.ts`/`.pegjs` hors sorties d'icônes, **12 501 lignes** dont 2 218 générées (`reference.ts`) → ~10 283 l. écrites à la main. Aucun test, aucun script de build, pas de métadonnées npm (`shared/package.json:1-17`) ; licence = `shared/LICENCE` = **GNU LGPL v3** (`:1-5`). Consommation par copie de dossier : `gameserver/tsconfig.json:22` mappe `"shared/*"` et exclut explicitement `shared/System/`, `shared/Konsole.ts` et `shared/reference.ts` (`:25`) — **c'est la frontière serveur/navigateur** : les modèles sont portables en Node, le moteur de feuille et le parseur de références ne le sont pas tels quels.

Le point d'architecture clé est l'**injection** : `shared` ne dépend d'aucun runtime. `SharedAdapter.ts:1-11` déclare `container`, `eventDispatcher`, `codeExecutor`, `uuid`, `pegjs`, `safeEval`, `translator`, que l'hôte remplit (`pegjs` est déclaré mais jamais utilisé : la compilation PEG se fait au build des hôtes).

### 3.2 Inventaire module par module

| Module | Fichier(s) | Lignes | Rôle | Dépendances |
|---|---|---|---|---|
| Dés (types) | `DiceData.ts` | 37 | `DiceType`, `DiceVisibility`, `SingleDiceResult`, `RawDiceResult` (arbre) | — |
| Dés (résultat) | `DiceResult.ts` | 254 | lecture paresseuse de l'arbre + `CriticalHitType` | `DiceData` |
| Dés (UI builder) | `DiceRoller.ts` | 60 | constructeur de jet : items, opérateurs, `adv/disadv/expl` | — |
| Grammaire dés | `grammar.pegjs` | 605 | parseur d'expressions de dés | RNG via `options.context.rng` |
| Grammaire références | `reference.pegjs` / `reference.ts` | 330 / 2 218 | parseur `@composant`, `$variable`, `#contexte` | callbacks hôte |
| Scène | `Scene/SceneData.ts`, `Scene/ScenePack.ts` | 358 + 30 | grille, murs, lumières, calques, tokens (aura/barres) | `DrawingsData`, `Journal` |
| Dessins | `DrawingsData.ts` | 133 | 10 outils, items typés (ligne, rect, polygone, texte, PoI…) | — |
| Journal / tour / quickbar | `Journal.ts`, `TurnOrderData.ts`, `QuickBarData.ts` | 53 + 34 + 50 = 137 | dossiers/pages/permissions ; `open/direction/items` ; 4 types d'items | `Journal` (quickbar) |
| Médias / musique | `Media.ts`, `MusicData.ts` | 88 + 3 | `Media`, tris, extensions et tailles autorisées ; `MusicProvider` | — |
| Utilisateur / erreurs | `User.ts`, `ErrorCode.ts` | 20 + 20 | `BasicUser`, `ClientRole` (4 rôles) ; codes WebSocket/upload | — |
| Icônes | `IconList.ts`, `IconPackData.ts` | 984 + 145 | ~980 noms FontAwesome + packs par défaut | `icons/out/ga-list` |
| Compétence (data) | `SkillData.ts` | 63 | mapping en dur « attribut → icône 1..56 » | — |
| Console | `Konsole.ts` | 74 | log/erreur vers le DOM | DOM |
| Markdown | `MarkdownParser.ts` | 97 | tokenizer regex → HTML (gras, titres, liens, `![icône]`) | `IconList` |
| Chemins / tableaux | `Util/ObjectPath.ts`, `Util/ArrayUtil.ts` | 111 + 27 | get/has/set/remove sur `a.b.c` ; `equals/shuffle/unique` | — |
| Feuille (DOM) | `System/**` | 63 fichiers, 6 707 | arbre de composants, rendu HTML, exécution, références, tables, i18n | `inversify`, DOM |

### 3.3 Focus 1 — le modèle de dés (`DiceData` / `DiceResult` / `DiceRoller`)

Le contrat de sortie est un **arbre récursif** (`DiceData.ts:24-37`) :

```ts
export interface RawDiceResult {
  type: DiceType;            // number | dice | comparison
  total: number; tags: string[]; children: RawDiceResult[];
  size?: number; dimension?: number; values?: number[]; discarded?: number[];
  left?: RawDiceResult; right?: RawDiceResult;
  success?: number; failure?: number;
}
```

`DiceResult` en est la façade : `total`, `tags`, `all` (tous les dés, défaussés inclus), `discarded`, `left`/`right`/`success`/`failure` pour les comparaisons, extraction paresseuse et récursive (`DiceResult.ts:49-167`, `181-241`). Couple « arbre brut + façade » **directement transposable** en GDScript (`Dictionary` + `RefCounted`). `DiceRoller` modélise le *constructeur visuel* de jet (items, côtés gauche/droite, opérateurs, `adv/disadv/expl/expladd`, `:1-60`) mais restreint les dimensions à `4|6|8|10|12|20|100` (`:60`) alors que la grammaire accepte toute valeur — divergence à trancher lors d'un portage.

### 3.4 Focus 2 — les deux grammaires PEG

`grammar.pegjs` (605 l.) est une vraie calculatrice avec historique de jet :

| Élément | Ligne | Comportement |
|---|---|---|
| Plafond de dés | `:2` | `MAX_DICE_ROLL = 500`, erreur au-delà (`:232-238`) |
| Dé `NdM` | `:305-318` | `createDice(size, dimension, tags, children)` (`:203-230`) |
| Tags `[a,b]` | `:347-358` | étiquettes propagées aux nœuds |
| Comparaison + poids | `:255-276`, `:126-201` | `>=,<=,>,<,=,!=` avec `{valeur:poids}` → `success`/`failure` |
| `keeph`/`keepl`/`adv`/`disadv` | `:378-391`, `:64-116` | tri, conservation/défausse, `discarded` |
| `remh`/`reml` | `:393-406` | suppression des extrêmes |
| `min`/`max` | `:408-468` | sélection d'un nœud, défausse des autres |
| `expl`/`expladd`/`expln`/`expladdn` | `:470-533` | dés explosifs, compteur borné |
| `mul` / `reroll`·`rerolln` / ternaire | `:535-542`, `:544-596`, `:248-253` | nombre de dés ; relances bornées ; `cond ? a : b` |

Deux points d'injection rendent la grammaire **testable et réutilisable** : le RNG est fourni par l'hôte (`randInt` → `options.context.rng(min, max)`, `:240-242`) et le compteur de dés vit dans `options.context.rolled` (`:232-238`). Exemple réel : `gameserver/src/Controller/DiceController.ts:114-122` passe `{ context: { rolled: 0, log, rng: (min,max) => randomInt(...) } }`. C'est exactement le point d'adaptation pour OpenQuest (RNG seedé Godot ou `crypto.randomInt` Node).

`reference.pegjs` (330 l.) est le **moteur des champs calculés** : `@composant`, `$variable`, `#contexte` (`:173-192`), `round/floor/ceil/avg/sum/if` (`:234-315`), concaténation de chaînes (`:129-158`) et arithmétique. L'hôte fournit trois résolveurs (`getReferenceValue`, `getVariableValue`, `getContextValue`, `:26-62`) ; l'implémentation de référence est `shared/System/Referencer.ts:70-141`, avec détection de **références circulaires** (`System/ReferenceList.ts:44-62`). Fait à connaître : `grammar.ts` est **vide (0 octet)** et `reference.ts` est **généré par `ts-pegjs`** (`reference.ts:11` : « Generated by PEG.js v. 0.10.0 (ts-pegjs plugin v. 0.2.7) ») ; la compilation est faite par les hôtes (`gameserver/package.json:53-58`, `front/package.json:27-30`). **La source de vérité est le `.pegjs`.**

### 3.5 Focus 3 — scène, tour, journal, « système de feuille »

`SceneData` couvre le vocabulaire d'un VTT cartographique : grille `square`/`hex` (`Scene/SceneData.ts:119-140`), métriques (`:30-60`), brouillard (`:62-65`), murs/lumières/portes (`:66-117`), calques (`:179-211`), items image/token/craft/journal (`:248-299`), tokens avec aura, barres 1/2 et vision (`:301-341`), `PersistedToken` (`:355-358`) ; `ScenePack` (`Scene/ScenePack.ts:3-30`) décrit le packaging de scènes publiées. `TurnOrderData` (`:1-34`) est minimal et directement exploitable : `open`, `direction`, `items{name,value,gm,character,token,avatar,color}` + valeurs par défaut. `Journal.ts:1-53` sépare `FolderData`/`PageData`, permissions `r/w/n` et partage par table ou utilisateur.

`shared/System/` (6 707 l.) est l'implémentation du « système de feuille » : `Tree` (sources de vues + fabrique de composants, `Tree.ts:9-56`, `:138-168`), `Component`/`View` (`Component/Component.ts:9-33`, `Component/View.ts:16-113`), registre de 15 widgets en 4 catégories (`Component/ComponentList.ts:20-55` : `Row, Column, Label, NumberInput, TextInput, Textarea, View, Checkbox, Choice, Container, Repeater, Tab, Avatar, Color, Icon`), `CharacterSheet` (908 l. : données, événements, persistance), `CodeExecutor` (script + hooks), `Referencer` (formules), `Translator` (i18n indexée par hash `:123-133`), `Tables`/`Table` (`Table/Table.ts:6-107`). Tout est **DOM-dépendant** (97 occurrences de `document.`/`HTMLElement` dans `shared/**/*.ts`) : à lire comme **architecture de référence**, pas comme code à porter. `SkillData.ts` est une table en dur (56 icônes) ; les icônes (`shared/icons/`) sont régénérées depuis game-icons.net par `icons/createFont.mjs:8-9`, documentées dans `shared/README.md:12-27`, **sans mention de la licence amont** — à vérifier avant réutilisation des SVG/polices.

## 4. Tableau « brique → réutilisation »

Efforts : **S** < 1 j ; **M** 1–3 j ; **L** > 3 j (développeur seul, GDScript/TS).

| Brique | (a) Tel quel côté Node | (b) Portable GDScript / Godot | (c) Inspirant seulement |
|---|---|---|---|
| `grammar.pegjs` (dés) | oui : compiler avec `ts-pegjs` (M), RNG injecté, LGPL | **M** pour `NdM±*/`, tags, keep/adv, comparaisons ; **L** pour `expl/reroll/minmax/mul/ternaire` | — |
| `reference.pegjs` (formules) | oui (M) | **M** : parser `.gd` sur le modèle des règles (`@`, `$`, `#`, `if`) | — |
| `DiceData.ts` / `RawDiceResult` | oui, 37 l. de types | **S** : `Dictionary` typé | — |
| `DiceResult.ts` | oui | **S/M** : classe `RefCounted` + getters, extraction récursive | — |
| `DiceRoller.ts` | oui | **S** : modèle du constructeur de jet (UI) | — |
| Les deux grammaires (règles) | — | — | la **spécification** (tableau §3.4) est librement réimplémentable |
| `Scene/SceneData.ts` (+ `DrawingsData`) | oui (schémas) | **M** : sous-ensemble grille/calques/items/token bars | le modèle complet murs+lumières+portes est un projet en soi |
| `TurnOrderData.ts` | oui | **S** : compléter `TurnManager` (direction, valeur affichée) | — |
| `Journal.ts` (Folder/Page) | oui | **S/M** : alimenter `story_log` + persistance JSON | — |
| `MarkdownParser.ts` | oui (sortie HTML) | **M** : réécrire vers BBCode/`RichTextLabel` | la liste des tags supportés |
| `QuickBarData`, `Media`, `MusicData`, `User`, `ErrorCode` | oui (types) | **S** chacun | — |
| `IconList.ts` / `icons/` | oui (front) | non pertinent (FontAwesome) | oui : pipeline de génération + packs |
| `SkillData.ts` | oui | possible mais **inutile** (données propres au jeu) | oui |
| `Konsole.ts` | non (DOM) | équivalent natif (`print`, `push_error`) | oui |
| `Util/ObjectPath.ts` | oui | **S** : résolution `a.b.c` sur `Dictionary` | — |
| `shared/System/**` | non (DOM) | non | **oui** : modèle « vue de composants + formules + hooks » pour la fiche OpenQuest |
| `js-engine` | oui (MIT) | non (JS) | oui : si scripting MJ/utilisateur un jour |

## 5. Contraintes LGPL v3 — ce que cela implique

**Faits.** `shared` porte le texte intégral LGPL v3 (`shared/LICENCE:1-5`), et le projet *starter* l'énonce sans ambiguïté : « you can use these projects commercially, but **you must publicly release any changes made, with the same licence** » (`starter/README.md:5-6`). Les hôtes déclarent `"license": "LGPL-3.0-or-later"` (`gameserver/package.json:7`, `front`, `website`). Exception : **`js-engine` est MIT** (`js-engine/package.json:13`), donc plus permissif.

**Copier / adapter / traduire = œuvre dérivée.** Copier `DiceResult.ts` dans `game/scripts/core/rules/` ou traduire `grammar.pegjs` en GDScript en suivant sa structure ligne à ligne produit un fichier soumis à la LGPL v3 : distribution sous LGPL-3.0-or-later, sources fournies, mention du projet d'origine et des modifications, sans restriction supplémentaire. La LGPL autorise en revanche à **lier** ces fichiers à du code propriétaire (c'est son intérêt face à la GPL) : le reste d'OpenQuest n'a pas à passer en LGPL.

**Ce qui reste libre.** Idées, algorithmes, formats d'échange et noms de champs d'un schéma ne sont pas protégeables en tant que tels : réécrire un schéma JSON (`dice_roll.json`) ou un parseur « à la manière de » est licite. Mais **copier un fichier d'interfaces TypeScript** (`DiceData.ts`, `TurnOrderData.ts`…) est une copie littérale, donc dérivée. Frontière pratique : *recopier un fichier → LGPL ; réimplémenter depuis une spec rédigée par vous → votre licence*.

**Recommandation pour un projet solo** (la plus simple à tenir) :
1. Isoler tout code dérivé dans un dossier explicite — p. ex. `server/src/rules/letsrole/` et `game/scripts/core/rules/letsrole/` — avec un en-tête SPDX `LGPL-3.0-or-later` + provenance (dépôt, commit `cc432eb`/`4ab201a`, fichier source, « modifié pour OpenQuest ») ;
2. Ne pas mélanger : les fichiers OpenQuest qui *appellent* ces modules gardent la licence du projet ;
3. Ajouter `THIRD_PARTY.md` + copie de `shared/LICENCE` (et de l'avis MIT de `js-engine` si utilisé) à la racine, plus une phrase de mention dans le `README.md` ;
4. Alternative « zéro contamination » recommandée pour les dés : garder les `.pegjs` comme **spécification de référence** et écrire les parseurs GDScript/TS à partir des tableaux §3.4 — même effort, dette juridique nulle ;
5. Ne pas committer `shared/icons/out/webfonts/` : licence amont non documentée, ~14,9 Mo, aucun besoin pour Godot.

## 6. Top 5 priorisé des choses à récupérer d'abord

1. **La grammaire des dés (`grammar.pegjs`)** — cible serveur `server/src/rules/dice_grammar.ts` (compile `ts-pegjs`, **S**), en remplacement/complément de la regex `server/src/dice.ts:27-57` ; cible Godot `game/scripts/core/rules/dice_grammar.gd` (port **M** pour `NdM±*/`, tags, keep/adv, comparaisons ; **L** pour le reste), appelé depuis `GameData.roll_dice` (`game/scripts/autoload/game_data.gd:4150`) et le réseau P2P (`game/scripts/multiplayer/multiplayer_manager.gd:348`, `:696-706`). Gain fonctionnel le plus visible pour le moins d'effort.
2. **Le modèle de résultat (`DiceData.ts` + `DiceResult.ts`)** — cible `data/schemas/dice_roll.json`, `game/scripts/core/rules/dice_result.gd`, `server/src/rules/dice_result.ts` (**S/M**). Sans lui, un port de la grammaire n'a nulle part où stocker `discarded`/`tags`/`success`/`children`.
3. **`TurnOrderData`** — cible `game/scripts/core/session/turn_manager.gd` (ajouter `direction`, `value`, `color`, `token`) et `server/src/game_types.ts` (**S**). Le `TurnManager` actuel ne connaît qu'un index de membre ; l'ordre à valeur (initiative triée, ouvert/fermé) est un besoin direct du hub MJ/joueur.
4. **Le sous-ensemble scène/token de `SceneData`** — cible `game/scripts/autoload/map_data.gd`, `data/schemas/map.json`, `server/src/game_types.ts` (**M**) : grille carrée/hex + snapping, calques (visibilité MJ, verrou), items image/token, barres 1-2 et aura. À laisser : murs/lumières/portes 3D (le rendu Godot existe).
5. **`Journal.ts` + `MarkdownParser.ts`** — cible `game/scripts/session/panels/story_log.gd`, `game/scripts/core/session/session_state.gd`, `game/scripts/core/persistence/json_store.gd` (**S/M**). Le journal actuel est une liste plate `{author,text,type,ts}` (`turn_manager.gd:52-60`) ; `FolderData`/`PageData` + permissions donnent la structure « dossiers/pages/partage MJ ».

**Hors top 5 mais en réserve** : `reference.pegjs` (**M**) si OpenQuest veut des caractéristiques dérivées calculées (le schéma `data/schemas/character.json:1-71` n'a **aucun champ calculé** : `hp`, `ac`, modificateurs sont saisis, pas dérivés) ; `js-engine` (**S** côté Node, **inutile** côté Godot) si un scripting utilisateur/MJ est envisagé ; `shared/System/**` comme **inspiration** pour une fiche déclarative (composants + formules + hooks), pas comme code.

## 7. Méthode, limites et points non vérifiables

- Mesures : comptages de fichiers/lignes sur disque, `grep` outillé, lecture directe des sources citées ; **aucun** `npm install`, build ou test exécuté (comme demandé).
- `js-engine` : 19 fichiers JS (`index` + 9 `lib` + 9 `test`), **3 128 lignes** au total, 161 cas de test, dépendances runtime `acorn` + `hoister`.
- `shared` : 87 fichiers `.ts`/`.pegjs` (hors `icons/out`), **12 501 lignes** dont 2 218 générées, 0 test.
- **Non vérifiable depuis les clones** : existence d'un registre npm privé ; licence des SVG game-icons.net ; historique des versions intermédiaires de `js-engine` (dérive 1.3.3 ↔ 1.5.3). Les dossiers `front/`, `gameserver/`, `tools/`, `starter/`, `website/` n'ont été lus **que** pour établir la consommation de `shared`/`js-engine` (`front/package.json:65`, `gameserver/package.json:53-58`, `gameserver/tsconfig.json:22-25`, `tools/system-builder-ai-document.md`) ; leur analyse détaillée relève des autres annexes.
