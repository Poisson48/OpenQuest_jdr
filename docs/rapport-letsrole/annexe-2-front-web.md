# Annexe 2 — Le front web de Let's Role (`front` + `website`) : ce qui est transposable dans OpenQuest

> ℹ️ **Analyse brute** — document factuel (mesures, chemins, licences, pièges). Il ne constitue plus un plan de reprise de code : voir [ADAPTATION.md](ADAPTATION.md) — **aucune copie**, uniquement des idées réimplémentées pour notre jeu.

**Rapport** : quelles ressources du GitLab Let's Role sont réutilisables dans OpenQuest JDR.
**Périmètre analysé** : `.external/letsrole/front` (commit `d633fbe`, 2025-12-21) et `.external/letsrole/website` (commit `69e6b77`, 2025-03-03), complétés par `.external/letsrole/shared` (commit `4ab201a`, 2026-01-11) et `.external/letsrole/starter` pour le modèle de scène et les règles de licence.
**Méthode** : `Get-ChildItem`/`grep`/`read` ciblés, comptage par script PowerShell ; **aucun `npm install`, build ni test exécuté** (consigne de mission). Les chiffres sont des mesures statiques du dépôt, pas des résultats d'exécution.
**Date** : 2026-11-16.

### Conventions de chemins

| Alias | Chemin réel (relatif à `D:\git\OpenQuest_jdr`) |
|---|---|
| `FRONT/` | `.external/letsrole/front/` |
| `WEB/` | `.external/letsrole/website/` |
| `SHARED/` | `.external/letsrole/shared/` |
| `ST/` | `.external/letsrole/starter/` |
| `game/` | `game/` (client Godot 4.7 local) |

Toutes les citations sont de la forme `fichier:ligne`. Volumes = lignes **totales** (lignes vides comprises), hors `node_modules`/`.git`.

---

## 1. Résumé exécutif

Le `front` de Let's Role est une **SPA TypeScript vanilla** (pas de framework : jQuery + Konva + templates Nunjucks précompilés, injection de dépendances `inversify`), de **193 fichiers et 50 680 lignes** dans `FRONT/src`, complétée par **183 templates** (4 156 l.) et **66 fichiers SCSS** (9 956 l.). Elle n'est **pas autonome** : `/shared` est gitignoré (`FRONT/.gitignore:2`) et 156 imports pointent vers `../../shared/…` (ex. `FRONT/src/View/GmView.ts:10`).

L'écran de table est une **coquille HTML fixe** (`WEB/views/play.html.njk:12-88`) — colonnes gauche/droite, conteneur de carte, barre d'actions, popins — remplie par ~26 vues (`FRONT/src/DependencyInjection/Views.ts:1-28`). C'est cette **structure de panneaux**, pas son DOM/CSS, qui est transposable : le client local possède déjà 17 panneaux dans `game/scenes/session/panels/` mais **sans dock/minimisation/persistance de layout**.

Ce qui se reprend vraiment : les **workflows MJ** (panneaux dockables + taskbar, quickbar, ordre de tour), les **structures de données de scène** (`SHARED/Scene/SceneData.ts`, 358 l. : couches, grille, fog, éclairage, auras/barres de token), la **grammaire de dés** (`SHARED/grammar.pegjs`, 605 l.), la **math hexagonale** (`HexLib.ts`, 261 l.) et la **visibilité/éclairage** (`VisibilityPolygon.ts`, 733 l.). Ce qui ne se reprend pas : la pile CKEditor/jQuery/Bootstrap/three.js, le moteur de feuilles de personnage (code JS exécuté côté client, `SHARED/System/CodeExecutor.ts`), et **tous les assets de production** (absents des dépôts).

La qualité est inégale : **un seul fichier de test** (2 assertions, `FRONT/tests/…/VisibilityPolygon.test.ts:3-23`), des God-objects (`JournalView.ts` 2 745 l., `MediaView.ts` 2 159 l.), et une licence **LGPL-3.0-or-later** qui contamine toute adaptation collée dans le binaire Godot.

| Question | Réponse courte | Preuve |
|---|---|---|
| Volume du `front` | 193 fichiers / 50 680 l. (`src`) + 183 templates + 66 SCSS | §2.1 |
| Framework | Aucun : TS vanilla + jQuery + Konva, DI inversify, Nunjucks précompilé | `FRONT/src/app.ts:1-107` |
| Autonome ? | Non : `shared/` doit être copié dans `FRONT/shared`, 156 imports | `FRONT/.gitignore:2`, `ST/INSTALL.md` |
| Écran de table | Coquille HTML statique à 12 zones + canvas Konva | `WEB/views/play.html.njk:12-88` |
| Rôle du `website` | Serveur Express **de développement** (rend la coquille, injecte le token) | `WEB/README.md:3`, `WEB/src/app.ts:48-51` |
| i18n | JSON plat, clé = phrase anglaise source, 6 langues, **~569 clés** | `FRONT/i18next-scanner.config.js:18-31` |
| Tests / build | 1 test (2 assertions) ; 18 configs webpack + `sass` | `FRONT/jest.config.js:1-7`, `FRONT/webpack/` |
| Assets libres ? | Polices/icônes tierces oui (OFL/Apache/CC-BY) ; **0 son**, images = placeholders basse résolution | §6 |
| Licence | LGPL-3.0-or-later ; « only the game engine is open-sourced » | `FRONT/package.json:41`, `ST/README.md:5,11` |
| À reprendre en priorité | panneaux dockables, modèle de scène, grammaire de dés, quickbar, ordre de tour + raccourcis | §8 |

---

## 2. Le `front` : anatomie

### 2.1 Métriques (mesurées)

| Module | Fichiers | Lignes | Rôle |
|---|---:|---:|---|
| `FRONT/src/View/` | 65 | 26 491 | les écrans : chat, journal, médias, musique, sons, scène, dés, tokens… |
| `FRONT/src/Engine/` | 44 | 10 461 | plateau Konva, couches, grille, éclairage dynamique, dessins |
| `FRONT/src/Website/` | 10 | 6 913 | widgets autonomes (dice-tester, feuille embarquée, dés mobile) |
| `FRONT/src/Controller/` | 19 | 1 726 | glue vue ↔ client WebSocket |
| `FRONT/src/Emitter/` | 9 | 1 198 | émetteurs (dés, tokens, scène…) |
| `FRONT/src/State/` | 15 | 718 | états volatils (outil courant, shift/alt, layout, tour) |
| `FRONT/src/DependencyInjection/` | 8 | 509 | conteneur/symboles `inversify` |
| `FRONT/src/Client/`, `Entity/`, `Event/`, `Loader/`, `Math/`, `Repository/` | 19 | 1 323 | transport WS, modèles, bus d'événements, maths |
| **`FRONT/src` (total)** | **193** | **50 680** | dont `grammar.ts` généré (3 388 l.) dans `src/Website/` |
| `FRONT/views/` | 183 | 4 156 | 21 dossiers de templates `.html.njk` |
| `FRONT/sass/` | 66 | 9 956 | 8 peaux + 8 peaux de table + `journal.scss` 818 l. |
| `FRONT/locales/` | 6 | 3 504 | 6 langues, ~569 clés chacune |
| `FRONT/webpack/` | 18 | 900 | une config par point d'entrée (dev + prod) |
| `FRONT/tests/` | 1 | 23 | un seul test |
| `FRONT/src/token-editor.ts` | 1 | 1 079 | éditeur de token autonome (2ᵉ point d'entrée) |

Dépendances : **41 runtime** + **28 dev** (`FRONT/package.json:42-114`). Notables : `konva` (canvas), `three` ~0.122 + `cannon` (dés 3D), `@ckeditor/*` (éditeur du journal), `bootstrap` 4 + `jquery` (UI), `nunjucks` (templates), `pegjs`/`ts-pegjs` (grammaire de dés), `polybooljs` + `martinez-polygon-clipping` (géométrie fog/murs), `tunajs` + `lamejs` (effets audio, encodage WAV), `inversify`, `js-engine` (git).

### 2.2 Architecture et points d'entrée

- **Amorçage** : `FRONT/src/app.ts:27-105` — construit `Stage` sur `#map` (`app.ts:98-104`), initialise `ViewManager` (`app.ts:53`), injecte `window.system` / `window.locale` (`app.ts:65-89`), puis connecte le cluster WebSocket (`app.ts:93-95`).
- **Vues** : registre de 26 symboles (`FRONT/src/DependencyInjection/Views.ts:1-28`) — `Chat`, `Character`, `Dice`, `Gm`, `Scene`, `Ruler`, `TurnOrder`, `TaskBar`, `QuickBar`, `Token`, `Music`, `Sound`, `Media`, `Journal`, `Pdf`, `DynamicLighting`…
- **Mise en page** : coquille unique `WEB/views/play.html.njk:12-88` ; tout le reste est injecté par JS dans des conteneurs connus (`#left-column`, `#right-column`, `#quickbar`, `#popin-container`, `#dice`, `#contextual`…).
- **Non-autonome** : `shared/` est gitignoré (`FRONT/.gitignore:2`), `tsconfig.json:24` inclut `["src","shared"]` et l'installation officielle copie le dépôt voisin (`ST/INSTALL.md`, étape 2). Toute lecture de `FRONT/src` sans `SHARED/` casse 156 imports.
- **Multi-cibles** : `npm run dev` (table), `token-editor`, `website:sheet`, `website:embed`, `website:dice-tester`, `website:mobile-dice-roller`, `website:live-dice-demo` (`FRONT/package.json:7-33`) ; les bundles sont recopiés dans `../website/public/js/` (`FRONT/webpack/webpack.config.dev.js:10-21`).

### 2.3 Découpage fonctionnel (preuves)

| Fonction | Fichiers principaux (lignes) | Templates |
|---|---|---|
| Chat (onglets, chuchotements, emojis, X-card) | `View/ChatView.ts` 1 045 · `View/Chat/ChatTabs.ts` 276 · `Chat/Emojis.ts` 1 536 | `views/chat/` 6 fichiers, 65 l. |
| Journal MJ (arborescence, partage, éditeur riche, PDF) | `View/JournalView.ts` 2 745 · `Journal/EditorManager.ts` 171 · `View/PdfView.ts` 517 | `views/journal/` 23 fichiers, 535 l. · `views/pdf/` 187 l. |
| Dés 3D (three.js + cannon) | `View/DiceView.ts` 640 · `View/Dice/DiceBox.ts` 1 172 · `Dice/` 7 fichiers 1 755 l. | `views/dice/` 7 fichiers, 260 l. |
| Formules de dés | `SHARED/grammar.pegjs` 605 · `View/Dice/DiceUtil.ts` 125 · `DiceExpressionHelper.ts` 115 | — |
| Feuille de personnage | `View/CharacterView.ts` 583 · `SHARED/System/CharacterSheet.ts` 908 · 24 composants (3 155 l.) · `CodeExecutor.ts` 299 | `views/character/` 39 l. + `sass/sheet.scss` 438 l. |
| Tokens (aura, barres, extras, éditeur) | `View/TokenView.ts` 745 · `token-editor.ts` 1 079 | `views/token/` 5 fichiers, 227 l. |
| Scène / couches / fog / grille | `View/GmView.ts` 1 239 · `View/Scene/SceneBrowser.ts` 504 · `View/SceneView.ts` 518 | `views/gm/` 21 fichiers, 619 l. · `views/scene/` |
| Éclairage dynamique | `Engine/Board/DynamicLighting.ts` 954 · `VisibilityPolygon.ts` 733 · `Collision.ts` 273 · `Door.ts` 243 | `views/lighting/` 139 l. |
| Quickbar (actions configurables) | `View/QuickBarView.ts` 1 124 · `SHARED/QuickBarData.ts` 50 | `views/quickbar/` 11 fichiers, 95 l. |
| Ordre de tour | `View/TurnOrderView.ts` 310 · `SHARED/TurnOrderData.ts` 34 | `views/turn-order/` 4 fichiers, 37 l. |
| Médias (dossiers, upload, quota, packs) | `View/MediaView.ts` 2 159 · `Media/MediaValidation.ts` 108 | `views/media/` 22 fichiers, 416 l. |
| Musique (playlists, YouTube) | `View/MusicView.ts` 1 470 | `views/music/` 216 l. |
| Sons (bibliothèque, soundboard, enregistrement micro) | `View/SoundView.ts` 1 114 · `View/Sound/` 5 fichiers | `views/sound/` 294 l. |
| Dessins / règles / zoom / popins | `DrawingsView.ts` 500 · `RulerView.ts` 711 · `ZoomView.ts` 236 · `Popin/Popin.ts` 664 | `views/drawings/` 255 l. · `views/ruler/` 59 l. |
| Compendium (« book ») et objets (« craft ») | `View/BookView.ts` 360 · `View/CraftView.ts` 692 | `views/book/` 85 l. · `views/craft/` 129 l. |

### 2.4 Build, tests, qualité

- **Build** : 18 configurations webpack (dev/prod par cible) + `sass` pour deux feuilles (`FRONT/package.json:7-33`) ; `npm run prod` enchaîne 12 builds en parallèle (`package.json:22`). Les skins CSS sont séparés (`compile-skin.sh`, `compile-table-skin*.sh`).
- **Tests** : `jest.config.js` (ts-jest, `testEnvironment: "node"`) mais **un seul fichier de test** : `FRONT/tests/Engine/Board/DynamicLighting/VisibilityPolygon.test.ts` (2 assertions sur l'intersection de segments). La CI `.gitlab-ci.yml:20-34` publie une couverture… de ce seul fichier. **Aucune valeur de garantie** : ne pas traiter ce dépôt comme « testé ».
- **Lint** : `.eslintrc.cjs` actif, mais `no-explicit-any` en `warn` (`.eslintrc.cjs:15`) et `tsconfig.json` sans `strict` (aucune option `strict*`).
- **Dette** : classes-vues géantes (2 745 l. pour `JournalView`), templates Nunjucks en chaînes (`Template.render(...)`, `GmView.ts:102`), état dispersé (`State/` à 15 fichiers), `any` omniprésent. Côté utile : la séparation `View` / `Controller` / `State` / `Emitter` est claire et **transposable comme découpage** dans `game/scripts/session/`.

---

## 3. Le `website` : rôle et parties réutilisables

Serveur **Express de développement**, pas le site de production (`WEB/README.md:3` : *« This LGPL project is used for development purpose only »*). 21 fichiers TS, 1 083 lignes, 5 templates (190 l.), 122 fichiers statiques (25,5 Mo).

| Aspect | Constat | Preuve |
|---|---|---|
| Stack | Express 4 + Nunjucks + `express-fileupload` + `cors` + `morgan` ; TS via `ts-node`, Docker `node:lts-alpine` + `ffmpeg` | `WEB/src/app.ts:1-9,31-46`, `WEB/Dockerfile:1-11` |
| Dépendances lourdes | MariaDB, Cassandra, Redis, OpenSearch (4 bases) | `WEB/package.json:22,23,28,31` |
| Routes | `/` (dev), `/table` (créer une table), `/play/:tableId/:role` (rendre la coquille), `/cdn` (proxy média) | `WEB/src/app.ts:48-51` |
| Statique | `public` + alias `/assets` + `/medias` | `WEB/src/app.ts:38-40` |
| Injection | `window.architect` (WS), `window.configuration.cdnUrl`, `window.system`, `window.translations` | `WEB/views/play.html.njk:90-127` |

**Réutilisable** : (1) la **coquille de table** `WEB/views/play.html.njk:12-88` — c'est le seul document qui décrit l'ergonomie complète d'un écran de jeu (12 zones) et c'est une bonne checklist pour `game/scenes/session/session.tscn` ; (2) `WEB/public/` : Bootstrap 4, jQuery slim, polices, images, modèle de dé `dice/default.gltf` (1 Mo) ; (3) `WEB/locales/app/*.json` — **copie générée** depuis `FRONT/locales` (`FRONT/webpack/webpack.config.dev.js:17`), donc pas une source indépendante.

**Non réutilisable** : repositories/services adossés aux 4 bases (`gameTableRepository.ts` 209 l., `searchService.ts` 203 l.), génération de token de jeu (`playService.ts`, dépend du `gameserver`), tout le modèle « tables multi-locataires » du cloud. À noter : le dépôt `website` ne contient qu'**un commit** (`69e6b77`, « Initial commit ») → aucun historique exploitable.

---

## 4. Cartographie UI Let's Role → Godot

Légende « Transposable » : **UI/UX** = structure de zones/états/workflow rejouable en `Control`/`.tscn` ; **Algo** = logique portable par réécriture GDScript (aucun code copiable tel quel) ; **Non** = dépend d'une techno sans équivalent (DOM/CSS, JS sandboxé, WebAudio, three.js). Effort solo : **S** ≤ 1 j, **M** 2–5 j, **L** ≥ 1–2 semaines.

### 4.1 Écrans de jeu

| Écran / fonction Let's Role (preuve) | Équivalent OpenQuest actuel | Transposable | Effort |
|---|---|---|---|
| Coquille de table : colonnes gauche/droite, carte plein cadre, popins, zoom (`WEB/views/play.html.njk:12-88`) | `game/scenes/session/session.tscn` (140 l., 11 `PackedScene` de panneaux) | UI/UX oui · CSS non | M |
| Chat : onglets, chuchotements, drawer emoji, X-card, historique ↑/↓ (`View/ChatView.ts` 1 045 ; `Chat/ChatTabs.ts` 276 ; `Chat/Emojis.ts` 1 536 ; `ChatView.ts:234-242`) | `panels/story_log.tscn` (46 l.) + `speaker_dialogue_overlay` (93 l. + 266 l. GD) | UI/UX oui (fil + onglets) | M |
| Journal MJ : arborescence, partage ciblé, recherche, PDF, éditeur CKEditor (`View/JournalView.ts` 2 745 ; `views/journal/` 23 templates ; `View/PdfView.ts` 517) | `panels/gm_notes.tscn` (64 l.) — pas d'arborescence ni de partage | Partiel : structure oui, CKEditor/PDF non | L |
| Feuille de personnage pilotée par données JS (`View/CharacterView.ts` 583 ; `SHARED/System/CharacterSheet.ts` 908 ; 24 composants 3 155 l. ; `CodeExecutor.ts` 299) | `scripts/ui/character_sheet.gd` (226 l.) + `panels/character_sheet.tscn` (285 l.) + `scenes/character_editor.tscn` | Non (moteur JS) · concept de « skin » oui | L |
| Dés 3D physiques (`View/DiceView.ts` 640 ; `Dice/DiceBox.ts` 1 172, `:38` d4→d100 ; `three` + `cannon`) | `panels/dice_tray.tscn` (118 l.) + `panels/dice_tray.gd` (72 l.) | Rendu : non · journal de jets : UI/UX oui | M |
| Grammaire de dés : garder/relancer, avantage, explosifs, tags (`SHARED/grammar.pegjs` 605 ; `View/Dice/DiceUtil.ts` 125) | `game/scripts/core/rules/dice.gd` (49 l., regex `NdM+K` seulement) ; `game/scripts/autoload/game_data.gd:4150` (`roll_dice`) | **Algo oui** (réécriture du parseur) | M |
| Ordre de tour / initiative (`View/TurnOrderView.ts` 310 ; `SHARED/TurnOrderData.ts` 34 ; `views/turn-order/` 37 l.) | **absent** : aucun `turn_order`/`initiative` hors `core/session/turn_manager.gd` (tours narratifs) | UI/UX + modèle oui | S |
| Quickbar : 10 emplacements, titre, formule, visibilité MJ, lien journal/son (`View/QuickBarView.ts` 1 124 ; `SHARED/QuickBarData.ts` 50 ; `views/quickbar/` 95 l.) | `panels/action_bar.tscn` (90 l.) + `action_bar.gd` (77 l.) : boutons de suggestions figés en scène | UI/UX oui (barre configurable) | M |
| Tokens : aura, 2 barres liées, extras, menu contextuel (`View/TokenView.ts` 745 ; `views/token/` 227 l. ; `token-editor.ts` 1 079) | `panels/map_workspace.gd` (1 319 l.) + `party_member_card.tscn` | UI/UX oui · éditeur DOM non | M |
| Scène : couches verrouillées/visibles/GM, grille, métriques, fond, playlist (`View/GmView.ts` 1 239 ; `views/gm/` 21 templates 619 l. ; `SHARED/Scene/SceneData.ts` 358) | `game/scenes/map_editor/` (8 tscn dont `outliner.tscn`, `inspector.tscn`) + `map_workspace.tscn` | **Modèle de données oui** | M |
| Brouillard + éclairage : murs, portes, lumières, polygone de visibilité (`Engine/Board/DynamicLighting.ts` 954 ; `VisibilityPolygon.ts` 733 ; `Collision.ts` 273 ; `Door.ts` 243) | `scripts/interactive_map.gd` (1 103 l. ; `fog_enabled` `:45`) ; `map_viewer.gd:88` annonce déjà murs/ombres/fog 3D | **Algo oui** (§8) | L |
| Grille carrée **et hexagonale** + accroche (`Engine/Board/Grid/` 6 fichiers, 868 l. dont `HexLib.ts` 261 : coordonnées cubiques q/r/s, distance, lerp) | `panels/map_stage.gd` (312 l.) — grille carrée seulement | **Algo oui** | S |
| Médias : dossiers, upload, quota, packs, vignettes (`View/MediaView.ts` 2 159 ; `views/media/` 22 templates 416 l.) | `game/scenes/map_editor/library.tscn`, `map_viewer/library.tscn` | UI/UX oui (arbre + grille) | M |
| Musique (playlists, YouTube) et sons (soundboard, enregistrement micro) (`View/MusicView.ts` 1 470 ; `View/SoundView.ts` 1 114, `:311` ; `View/Sound/` 5 fichiers) | **absent** (aucun `AudioStreamPlayer` de session) | Non (WebAudio + CDN) · UX de playlists oui | L |
| Compendium / objets (recherche, lookup, clonage) (`View/BookView.ts` 360 ; `View/CraftView.ts` 692) | `scenes/scenario_editor.tscn` + `graph_node.tscn` | Partiel (workflow de recherche) | M |
| Dessins et règles (mètre, cône, ligne, texte) (`DrawingsView.ts` 500 ; `RulerView.ts` 711 ; `views/drawings/` 255 l.) | outil « measure » de `scripts/debug/palette_v2_demo_boot.gd:67` | UI/UX oui | M |

### 4.2 Chrome, panneaux et raccourcis (les gains les plus rapides)

| Élément (preuve) | Équivalent OpenQuest | Transposable | Effort |
|---|---|---|---|
| Panneaux **dockables** : `popin` / `dock-left` / `dock-right`, minimiser/maximiser, en-tête (`View/DockableView.ts` 658, enum `:32-36`) | `session_shell.gd` (534 l.) + 17 panneaux **fixes** ; aucun dock | **UI/UX oui** (cible : `game/scripts/ui/dock_manager.gd`) | M |
| Barre de tâches par catégories : `main / tool / content / audio / other` (`View/MenuView.ts:38-62` ; `TaskBar/TaskBarItem.ts` 258) | `panels/session_header.tscn` (96 l.) + boutons d'onglet | UI/UX oui | S |
| Persistance de la disposition (`State/PersistedState.ts` 40 ; `localStorage`) | `scripts/autoload/ui_layout.gd` (91 l.) = constantes seulement | UI/UX oui (`ConfigFile`/`user://`) | S |
| Modales/popins empilés (`View/Popin/` 2 fichiers, 753 l. ; `PopinManager` gère la pile) | `debug/*_boot.tscn` + `hub` | UI/UX oui | S |
| Raccourcis : `p` = ping, `m` = carte entière, `Ctrl+Z` = annuler, `Suppr` = supprimer, `Ctrl+C/X/V` = presse-papier (`SceneView.ts:259,269,278` ; `GmView.ts:652-680`) | `scripts/shared/ui_shortcuts.gd` (37 l.) = seulement Échap / Ctrl+Entrée / Ctrl+S | **Oui, à compléter** | S |
| `Échap` annule l'outil courant (`State/ToolState.ts:18-22`) | `session_shell.gd:55-56` (`is_cancel`) | Oui, déjà amorcé | S |
| Zoom/pan et « fit map » (`ZoomView.ts` 236) | `map_workspace.gd` (zoom/pan) + `world_navigation.gd` (151 l.) | Oui, déjà là | S |

**Lecture d'ensemble** : sur 15 fonctions de jeu, 4 sont réellement bloquées par la techno (feuille JS, dés 3D, audio Web, CKEditor/PDF) ; **11 se transposent en UI/UX ou en algorithme**. Les 3 manques les plus visibles côté local : **dock/persistance des panneaux**, **ordre de tour**, **raccourcis étendus**.

---

## 5. i18n : format, volume, intérêt pour `game/locale`

**Format Let's Role** : JSON **plat**, une clé = une phrase **anglaise** source, une valeur = la traduction ; `keySeparator: false`, `defaultValue: ""`, interpolation `{{ }}`, 6 langues (`en, fr, de, it, pt, es`) — `FRONT/i18next-scanner.config.js:18-34`. Les clés sont extraites de `__('...')` en TS et de `{{ __('...') }}` en Nunjucks (`i18next-scanner.config.js:2-13`), ex. `views/quickbar/custom.html.njk:3,15-17`.

**Volume mesuré** : 569 clés. `fr.json` en remplit 550, `de/es/it/pt` 533–536, `en.json` seulement **41** (c'est le **gabarit d'extraction**, l'anglais venant de la clé elle-même). Échantillon (`FRONT/locales/fr.json`) :

```json
"GM": "MJ",                                  // :284
"Chat": "Chat",                              // :11
"Scene": "Scène",                            // :194
"Quick Bar": "Raccourcis",                   // :201
"Turn order": "Ordre des tours",             // :202
"Fog of War": "Brouillard de guerre",        // :227
"Dice formula": "Formule de dés",            // :54
"Quick Bar Slot #%{index}": "Raccourcis #%{index}"  // :208
```

**Format local** : `game/locale/ui.csv` — **106 lignes**, en-tête `keys,en`, clés = **phrases françaises** sources, une seule colonne de traduction (`game/locale/ui.csv:1-3`), importé en `ui.en.translation`.

| Critère | Let's Role | OpenQuest |
|---|---|---|
| Format | JSON plat | CSV Godot (`keys,en`) |
| Langue source | anglais (clé = phrase EN) | français (clé = phrase FR) |
| Langues | 6 (dont FR complet) | 2 (FR source + EN) |
| Volume | ~569 clés | ~105 clés |
| Interpolation | `{{ }}` (config) et `%{…}` (usage) | `%s` / `%d` Godot |
| Outillage | `i18next-scanner` (extraction auto) | import CSV → `.translation` |

**Intérêt réel** : (1) la convention « la clé EST la phrase source » est **identique** — la conversion JSON → CSV est un script de ~20 lignes et permettrait de récupérer tout le vocabulaire VTT bilingue FR/EN (MJ/GM, jet/roll, pion/token, ordre des tours/turn order, brouillard de guerre/fog of war) pour **enrichir la colonne EN** de `ui.csv` ; (2) en revanche **ne pas** réutiliser `fr.json` comme source de français : le projet local est déjà francophone natif, et les tournures Let's Role (« Raccourcis » pour *Quick Bar*, « Ordre des tours ») ne collent pas à l'UX voulue ; (3) `en.json` à 41 valeurs est inutilisable comme traduction anglaise. Qualité des 4 autres langues **non vérifiée** (impossible sans exécution).

---

## 6. Assets : inventaire et statut de licence

Aucun fichier de licence par asset dans les dépôts (`glob` sur `LICEN*/OFL/NOTICE` : seuls les `LICENCE` racine et `FRONT/src/Engine/Util/SuperGif/LICENSE` MIT). Les statuts ci-dessous sont donc **déduits des noms de fichiers, du `package.json` et de la documentation amont** — à reconfirmer avant redistribution.

| Groupe | Chemin | Volume | Licence constatée | Reprenable ? |
|---|---|---|---|---|
| Police d'icônes `game-icons` | `WEB/public/fonts/game-icons.{ttf,woff,woff2,eot,svg}` | 5 fichiers, ~15 Mo (dont `game-icons.svg` 10,4 Mo) | **game-icons.net (CC BY 3.0)**, générée par `SHARED/icons/createFont.mjs:7-8` | Oui, avec attribution ; garder `ttf`/`woff2`, jeter le SVG |
| Font Awesome **Free** 5 | `WEB/public/fonts/fa-{solid,regular,brands}-*` | 14 fichiers, ~2,1 Mo | FA Free 5 : polices **OFL 1.1**, icônes **CC BY 4.0**, code MIT (`FRONT/package.json:54`) | Oui, avec attribution ; la version **Pro** est absente (`ST/README.md:30`) |
| Polices texte | `WEB/public/fonts/` : OpenSans, Bitter, Lato, PlayfairDisplay, Audiowide, Electrolize | 19 fichiers, ~2,4 Mo | Apache 2.0 (OpenSans) / OFL (les autres) — **non rappelé dans le dépôt** | Oui, avec les licences amont |
| Polices des peaux | déclarées dans `FRONT/sass/skin/*.scss` (`NotoSerif`, `SpecialElite`, `kindergarten`, `IMFellEnglish`, `Saira`) | **0 fichier livré** | introuvables dans le clone → polices servies par le CDN de production | Non (à re-télécharger, licences à vérifier) |
| Peau « fateforge » | `FRONT/sass/skin/fateforge.scss`, `sass/tableskin/fateforge/` | absents | **explicitement exclus** : `# Proprietary files` (`FRONT/.gitignore:11-13`) | Non |
| Images d'UI | `WEB/public/img/` (56 fichiers) | 678 Ko | dépôt LGPL (pas de mention tierce) | Oui mais **placeholders** : décorations 16×16 à 400×400, `journal-bottom.png` 100×137, `playmat15.jpg` 1920×1080 |
| Modèle de dé 3D | `WEB/public/dice/default.gltf` | 1 Mo | export Blender, **aucun champ `copyright`** (`default.gltf:2-5`) | À vérifier avant import Godot (glTF lisible directement) |
| Avatars/tokens par défaut | `WEB/medias/static/default-{avatar,token}.png` | 22 Ko | dépôt LGPL | Oui (placeholders) |
| **Sons / musiques** | — | **0 fichier** (`*.mp3|ogg|wav|m4a` = 0 résultat) | bibliothèque sonore côté serveur/CDN | **Non : rien à récupérer** |
| Logo / favicon | `WEB/public/logo.svg`, `favicon.ico` | 2 fichiers | marque Let's Role | Non (droit des marques) |
| Feuilles de style compilées | `WEB/public/css/` (Bootstrap 4 + `website.css` 5 l.) | 7 fichiers | Bootstrap MIT ; `play.css`/`sheet.css` **générés** par le `front` | Non (le CSS ne survit pas au passage Godot) |

**Conclusion assets** : le dépôt ne contient **aucune illustration ni aucun son de production** — cohérent avec `ST/README.md:11` (« Only the game engine is open-sourced »). Le seul gisement réellement exploitable est **typographique et iconographique** (game-icons + FA Free + 6 polices), plus le modèle de dé `.gltf`.

---

## 7. Contraintes LGPL v3 pour l'UI et les assets

Licence déclarée : `LGPL-3.0-or-later` (`FRONT/package.json:41`, `WEB/package.json:20`, fichier `LICENCE`). La présentation officielle est explicite : *« you must publicly release any changes made, with the same licence »* (`ST/README.md:5`).

| Point | Conséquence pratique pour OpenQuest |
|---|---|
| Nature du code | Front = **bibliothèque applicative** (pas une lib liée dynamiquement) ; coller/porter du code dans un binaire Godot exporté statiquement rend le §4(d) (« relink ») **inapplicable en pratique** |
| Portage GDScript | Une **traduction fidèle** (structure + noms + logique) est un travail dérivé → le fichier porté doit rester LGPL-3.0-or-later, avec en-tête de licence et mention de l'œuvre d'origine |
| Réimplémentation | Réécrire à partir des **concepts** (workflow, structure de données, algorithme) sans copier le code évite le sujet — c'est la voie recommandée pour l'UI |
| Notice obligatoire | Si du code LGPL est repris : notice visible « utilise Let's Role (LGPL-3.0-or-later) », copie des textes GPL+LGPL, et publication des modifications |
| Isolation | Garder `.external/letsrole/` **hors du build** et hors du dépôt distribué : aucun fichier du front ne doit être importé par `game/` |
| Assets | La LGPL du dépôt ne s'applique pas aux polices/icônes tierces : leurs licences (OFL, Apache 2.0, CC BY) **s'appliquent séparément**, avec attribution ; FA Pro et « fateforge » sont exclus de l'open source |
| Marque | « Let's Role » et son logo ne sont pas couverts par la LGPL : à ne pas réutiliser |

Recommandation : un fichier `docs/LICENSE-LETSROLE.md` (ou section du rapport) listant chaque élément repris, sa licence et son attribution, plus un en-tête SPDX dans tout fichier porté.

---

## 8. Top 5 priorisé

| # | Quoi reprendre | Cible dans OpenQuest | Pourquoi maintenant | Effort |
|---|---|---|---|---|
| 1 | **Panneaux dockables + taskbar + persistance de layout** (`View/DockableView.ts` 658, enum `:32-36` ; `View/MenuView.ts` 245 ; `State/PersistedState.ts` 40) | nouveau `game/scripts/ui/dock_manager.gd` ; refonte de `session_shell.gd` (534 l.) et des 17 `panels/*.tscn` | les panneaux locaux sont figés dans `session.tscn` (11 `PackedScene`) ; c'est le levier UX le plus large (MJ comme joueur) | M |
| 2 | **Modèle de scène/couches/tokens** (`SHARED/Scene/SceneData.ts` 358 : `SceneLayer`, `LayerItem`, `TokenBars`, `TokenAura`, `SceneGrid`, `SceneMetrics`) | `Resource` GDScript (`game/scripts/maps/…`) + sérialisation JSON ; alimente `map_workspace.gd` (1 319 l.) et `outliner.tscn` | le modèle local est implicite dans `MapData` ; un schéma explicite simplifie sauvegarde, undo et réseau | M |
| 3 | **Grammaire de dés** (`SHARED/grammar.pegjs` 605 : `keeph/keepl/adv/disadv`, `expl`, `rerolln`, `round/floor/ceil/minmax`, tags `:347`) | `game/scripts/core/rules/dice.gd` (49 l. aujourd'hui, regex `NdM+K`) | débloque avantage/dés explosifs/relances sans toucher au protocole (`client_request_dice_roll`, `multiplayer_manager.gd:348`) | M |
| 4 | **Quickbar d'actions** (10 slots : titre, formule + visibilité `visible/gm/gmonly`, lien journal, son — `views/quickbar/custom.html.njk` ; `View/QuickBarView.ts` 1 124) | `panels/action_bar.tscn` (90 l.) + `action_bar.gd` (77 l.) → barre configurable persistée | gros gain de fluidité en session ; réutilise les boutons-suggestions déjà présents | M |
| 5 | **Ordre de tour + raccourcis étendus** (`View/TurnOrderView.ts` 310 ; `SHARED/TurnOrderData.ts` 34 ; `SceneView.ts:259,269,278`) | `panels/` + `scripts/shared/ui_shortcuts.gd` (37 l.) : ajouter `p` ping, `m` fit, `Ctrl+Z`, `Suppr`, presse-papier | l'ordre de tour est **absent** du client ; les raccourcis sont le meilleur ratio gain/coût (S) | S |

**Hors top 5 mais à garder en réserve** : algorithme de visibilité/éclairage (`VisibilityPolygon.ts` 733 + `Collision.ts` 273 + `Door.ts` 243) et math hexagonale (`HexLib.ts` 261) — gros potentiel pour la battlemap 3D, mais effort L et dépendance à la géométrie locale ; build webpack multi-cibles à ignorer ; feuille de personnage JS et 3D dés à éviter.

---

## 9. Ce que cette annexe ne prouve pas

- **Aucune exécution** : ni `npm install`, ni build, ni tests (consigne). Les volumes sont des mesures statiques (script PowerShell sur les fichiers), à ±0 ligne.
- **`FRONT/shared/` est absent du clone** (gitignoré) : l'analyse du modèle de scène s'appuie sur `SHARED/` ; 156 imports du front ne sont pas résolubles en l'état.
- **`FRONT/src/Website/`** (6 913 l. : dice-tester, feuille embarquée, dés mobile) n'est traité que comme point d'entrée secondaire, non analysé ligne à ligne.
- **Licences d'assets déduites** (aucun fichier OFL/LICENSE à côté des polices) : à reconfirmer sur les sites amont avant toute redistribution.
- **Efforts S/M/L** = estimation d'auteur pour un développement solo, hors tests et hors intégration réseau.
- `gameserver`, `js-engine`, `starter` (protocole, exécution JS, déploiement) sont traités par l'annexe 3.
