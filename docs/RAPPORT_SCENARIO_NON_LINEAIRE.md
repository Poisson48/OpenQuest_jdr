# Compte rendu — Scénario non linéaire : où on en est RÉELLEMENT

> **Date** : 2026-11-16 · **Base** : `HEAD d616b25` (branche `feat/carte-2.5d-editeur`) · **Godot 4.7.2**
> **Méthode** : audit en lecture seule (3 volets : runtime Godot, éditeur + tests, doc/serveur), 5 tests headless relancés, sondes ad hoc d'UI (hors dépôt), vérification `tsc --noEmit`.
> Aucun fichier de code modifié pour cet audit ; seul ce rapport est ajouté.
> ⚠ Le working tree est sale et **un autre agent travaille en parallèle** (carte/qualité CS2 + `roll_dice` en fin de `game_data.gd`). Les numéros de ligne cités valent pour `d616b25` + ces éditions concurrentes.

---

## 1. Verdict en 7 lignes

1. **Le moteur de graphe, l'éditeur GraphEdit et la console MJ existent, fonctionnent et sont testés** — mais pour **un MJ humain uniquement**.
2. **En solo « MJ IA » (le mode par défaut, celui sans MJ humain), la navigation de scène est impossible** : le HUD MJ est masqué et le « MJ IA » n'est qu'un tirage de 4 phrases en dur qui n'appelle jamais la navigation.
3. **Aucun des 12 scénarios livrés ne peut se terminer avec « Scène suivante »** : la dernière scène n'a que des branches `gmOnly` ; la normalisation les transforme en chemin par défaut → boucle. La fin passe obligatoirement par le bouton « Clore l'aventure ».
4. **12 graphes sains sur le papier** (0 transition cassée, 0 orpheline, 0 inatteignable), **mais 8/12 ne sont même pas chargés par le jeu** (donnée morte) et 9 sont des graphes générés mécaniquement (« Continuer vers : X », « Sauter à la fin (MJ) »).
5. **Le serveur Node ne porte aucune part du scénario non linéaire** (contrat linéaire par index) et **ne compile plus** depuis le 30/09 (`AiGM` supprimé mais toujours importé).
6. **La couverture de tests ne prouve pas la navigation en session** : 5/5 PASS, mais aucun test ne touche le panneau de navigation, et le seul parcours bout-en-bout réel (`valbois_session_simulator.gd`) n'est **pas dans la suite automatisée**.
7. C'est une brique **figée depuis le 02/09/2026** (486 commits de cartes depuis), sans CI, et que la doc **surévalue par endroits** (dont 4 liens/fichiers faux).

**Conclusion courte : « scénario non linéaire » = prototype solide à 70 % côté outil MJ humain ; pas une fonctionnalité jouable de bout en bout pour les joueurs, et pas branchée à l'IA ni au serveur.**

---

## 2. Ce qui marche réellement (avec preuves)

| Capacité | État | Preuve |
|---|---|---|
| Normalisation tolérante du graphe (ids auto, ids uniques, cibles invalides retirées, `startSceneId` réparé, rétrocompat linéaire) | ✅ | `game/scripts/quest_navigation.gd:13-63,412-464` |
| Analyse de graphe (branches, terminales, atteignabilité, orphelines, self-loops, layout BFS) | ✅ code, ⚠ uniquement utilisé par l'éditeur | `quest_navigation.gd:167-379` ; appelé par `scenario_editor.gd:320,349,449,1175` |
| `advance_scene` / `go_to_scene` / `complete_scenario` | ✅ | `game/scripts/autoload/game_data.gd:1498-1512,1514-1567,1614-1625` |
| Effets de bord d'entrée de scène : journal MJ (titre+contenu), `visitedSceneIds`, `sceneHistory` fermé/appendé, brouillard, indices enquête, autosave | ✅ | `game_data.gd:1526-1566,1700-1709` |
| Reprise de partie : `currentSceneId/currentSceneIndex/visitedSceneIds/sceneHistory` persistés et restaurés | ✅ | `game_data.gd:1243-1251,1110-1124,1064-1088,1679-1698` |
| Console MJ : sélecteur de toutes les scènes (▶ courante / ✓ visitée / ○ non visitée), un bouton par branche avec ★ sur le défaut, « Scène suivante », « Clore l'aventure » | ✅ | `game/scripts/session/panels/gm_console.gd:71-108` ; `game/scenes/session/panels/gm_console.tscn:107-153` |
| Sécurité : un joueur ne peut pas naviguer (aucun RPC scène ; seuls l'hôte/MJ appellent la navigation) | ✅ | `multiplayer_manager.gd:356-372` ; `game/scripts/session/session_role.gd:60-62` |
| Éditeur : scènes (+/−/départ), transitions (drag, right-disconnect, label/default/gmOnly/suppression), tags, PNJ, `graphPos/graphSize`, auto-layout, fit, minimap, popup, validation, garde-fou modifications | ✅ | `game/scripts/scenario_editor.gd` (1290 l.) ; `game/scripts/scenario_editor/panels/*` |
| 12/12 JSON branchés (transitions sur 100 % des scènes) | ✅ | `game/data/scenarios/*.json` |
| Parcours réel MJ humain (solo et P2P) : branche, défaut, saut, clôture | ✅ vérifié par sonde UI 4/4 | sonde ad hoc (picker 6 items → clic branche → `ruines-zhar-rim` ; « Scène suivante » → `catacombes-fraiches` ; saut → `tribunal-seigneur` ; clôture → `status=completed`) |
| Parcours bout-en-bout de **9 scènes Valbois** piloté via la vraie UI | ✅ mais **manuel** (hors CI) | `game/scripts/debug/valbois_session_simulator.gd:120-195` ; lancé par `scripts/play-godot-valbois-sim.ps1` |

---

## 3. Les constats qui comptent (P0 / P1 / P2)

### P0 — bloque la promesse « scénario non linéaire »

**P0-1. Le solo « MJ IA » ne fait pas avancer l'histoire.**
`gmType="ai"` → rôle `KIND_SOLO` → `can_navigate_scenes=false`, console MJ masquée (`session_role.gd:56-62` ; `session_shell.gd:197-215`). Or rien d'autre n'appelle `advance_scene` : le « MJ IA » est un stub de 4 répliques aléatoires (`session_view_model.gd:399-435`). Le chemin de démarrage par défaut crée exactement ce cas (`session_shell.gd:43-44,389-397` → `create_new_game(..., "solo","ai",...)`).
→ **Conséquence : un joueur seul reste sur la scène de départ indéfiniment ; le graphe n'est jamais utilisé.**

**P0-2. Le serveur Node ne compile pas (déjà livré sur `main`).**
`tsc --noEmit` → 5 erreurs : `AiGM` importé mais supprimé (`game_session.ts:9` ; `mcp/gm_server.ts:16` ; commit `8ecbfe2`), `world_state.ts:58,65`. Seul un `server/dist/` gitignoré du 02/09 masque la casse en local. `src/index.ts:6-7` ne démarre que le lobby WebSocket : GameSession/AiGM/bots/MCP sont du code mort.

### P1 — à corriger avant de dire « livré »

**P1-1. Aucun scénario ne se termine par le chemin par défaut (boucle sur la dernière scène).**
`_sanitize_transitions` force `default=true` sur la 1ʳᵉ transition quand aucune n'est `default` (`quest_navigation.gd:462-463`). Les 11 derniers scènes de scénario n'ont que des branches `gmOnly` → leur « Revenir à… »/« Sauter… » devient le défaut. Simulation du chemin par défaut : **11/12 fichiers bouclent** (ex. `demo-crypte` : `sanctuaire-interdit → fosse-mortsvivants → sanctuaire-interdit` ; `demo-valbois` : `denouement → place-du-marche → piste-bijou`). Le 12ᵉ (`inv-demo-scenario-demo`, terminal `scene-9`) ne clôt pas non plus : `advance_scene` retombe sur `index+1` (`game_data.gd:1507-1511`) et saute à `scene-10` au lieu de terminer.
→ **En pratique, 0/12 scénario ne s'achève via « Scène suivante » ; seule la clôture manuelle du MJ termine une partie.**

**P1-2. 8 des 12 scénarios sont de la donnée morte.**
Seuls `demo-valbois`, `demo-crypte`, `inv-demo-scenario-demo` (démos) et `demo-kharak` (`EXTRA`) sont chargés (`game_data.gd:15-19,818-835`). Les 8 autres (`demo-couronne-fracturee`, `demo-manoir`, 5 enquêtes, `inv-demo-serpent-noir`, `inv-demo-train`) existent, sont branchés (6–18 scènes) mais **n'apparaissent ni au Hub ni dans l'éditeur**. Le catalogue réel contient donc **4 scénarios** (2 aventures courtes + 1 aventure longue + 1 enquête), pas « 2 démos ».

**P1-3. Éditer une démo est un piège : succès affiché, modification perdue.**
L'éditeur autorise « Modifier » une démo (`scenario_card.gd:61-64`) et affiche « Scénario enregistré ✓ » (`scenario_editor.gd:1230-1243`), mais `load_scenarios` ignore toute entrée dont l'id est builtin (`game_data.gd:568`) → au redémarrage la démo d'origine revient. Prouvé par sonde (titre modifié → reload → titre d'origine).

**P1-4. Fuite des notes privées MJ et de l'historique en P2P.**
`broadcast_state` duplique **tout** `active_game` (`multiplayer_manager.gd:403-407`) donc `gmNotes` (notes privées, `game_data.gd:1647-1662`), `sceneHistory` et `visitedSceneIds` partent chez tous les pairs. Le panneau affirme pourtant « Privé : rien de ce qui est écrit ici n'est envoyé aux joueurs » (`gm_notes.tscn:49`). Le filtrage existe… pour les cartes seulement (`game_data.gd:2545`).

**P1-5. Aucune resynchronisation à la connexion/reconnexion P2P.**
`_on_peer_connected` n'envoie rien (`multiplayer_manager.gd:516-517`), `"player_joined"` = `pass` (:484-487), `rejoin_room` ne restaure aucun état (:295-299). Un joueur qui rejoint après le lancement a une partie vide jusqu'à la prochaine action du MJ.

**P1-6. « Campagne longue » impossible à créer depuis l'UI.**
La bibliothèque force `roster=general / format=oneshot` (`scenario_list.gd:465-472`) et l'éditeur verrouille alors le format (`scenario_editor.gd:167,224-225`). Le seul scénario long (`demo-kharak`, format `long`) n'est jouable que comme contenu fourni, pas comme modèle créable.

### P2 — dette / incohérences

- **P2-1. `gmOnly` est purement décoratif** : conservé par la normalisation (`quest_navigation.gd:455`) mais jamais lu au runtime (seulement dans l'éditeur). Combiné à P1-1, une branche « suggestion MJ » devient le chemin par défaut.
- **P2-2. Validation de graphe fantôme** : les cibles inconnues sont supprimées par `_sanitize_transitions` (`quest_navigation.gd:445`) **avant** `analyze_graph`, donc `brokenTransitions` est toujours vide et « Branche invalide » (`validate_scenario_graph:289-292`) ne peut jamais s'afficher.
- **P2-3. `analyze_graph` classe « orpheline » toute scène sans entrée, y compris une fin légitime** ; double branche redondante `if in_n==0 and out_n==0 … elif in_n==0` (`quest_navigation.gd:213-218`).
- **P2-4. `sceneHistory` écrit, fermé, persisté… jamais relu** : aucun consommateur de `exitedAt`, aucune UI d'historique. La promesse « rejouer / auditer la session » (QUEST_NAVIGATION.md:142) n'est pas implémentée.
- **P2-5. Notes MJ perdues au saut de scène** : debounce 0,8 s (`gm_notes.tscn:61-63`) sans flush avant navigation (`session_shell.gd:185-189`) → le texte tapé juste avant un saut est écrasé par la nouvelle scène.
- **P2-6. Brouillard/indices non corrélés à la scène** : chaque transition révèle +2 `exploreLevel` sur **toutes** les cartes monde (`game_data.gd:4098-4110`) et 1 indice sur **toutes** les cartes d'enquête (:4092-4096). C'est une cloche globale, pas une révélation par scène.
- **P2-7. Lien scène↔carte jamais exercé** : `_apply_scene_map_links` (`game_data.gd:1569-1612`) est codé mais **0 `mapIds` dans les 12 JSON** ; l'éditeur écrit de plus le lien dans `MapData` immédiatement, même si l'édition est abandonnée (`scenario_editor.gd:802-811`).
- **P2-8. PNJ non filtrés par scène** : `npcs[].scenes` existe dans `demo-valbois/kharak/crypte`, mais `list_session_npcs` renvoie **tous** les PNJ de **toutes** les cartes (`game_data.gd:1370-1414`) ; l'éditeur ne gère pas ce champ. Phase 4 = non faite.
- **P2-9. Conditions de transition absentes** : aucun `requiresFlag`/`condition` dans le code Godot (seul le schéma `data/schemas/scenario.json:155-158` les décrit, schéma que personne ne lit). Phase 2 = non faite.
- **P2-10. Parties terminées perdues au redémarrage** : `save_active_game` persiste `status=completed` (`game_data.gd:1119-1122`) mais `load_active_game` ne garde que `playing` (:1064-1088).
- **P2-11. Éditeur sans undo/redo, sans duplication de scène, sans suppression clavier, sans aperçu/jouer** ; « Valider » marque le document dirty à tort (`scenario_editor.gd:1172-1174`) ; `ensure_graph_positions` écrase **toutes** les positions dès qu'une scène n'a pas de `graphPos` (`quest_navigation.gd:397-410`).
- **P2-12. Coût** : `get_scenario_by_id` re-normalise (2 `duplicate(true)` par appel, `quest_navigation.gd:16,168`) à chaque rafraîchissement de la session (`session_view_model.gd:69`) ; `save_active_game` réécrit tout `saved_games.json` à chaque entrée de journal.

---

## 4. Données : 12 graphes techniquement sains, mais peu habités

| Fichier | Chargé | Scènes | Trans. | Carrefours | Cassées | Terminales | gmOnly | Auteurs |
|---|---|---|---|---|---|---|---|---|
| demo-valbois | ✅ | 9 | 27 | 8 | 0 | 0 | 8 | main |
| demo-crypte | ✅ | 6 | 13 | 5 | 0 | 0 | 8 | main |
| demo-kharak | ✅ (EXTRA) | 6 | 16 | 6 | 0 | 0 | 11 | main |
| inv-demo-scenario-demo | ✅ | 13 | 26 | 9 | 0 | 2 | 0 | éditeur |
| demo-couronne-fracturee | ❌ | 18 | 113 | 18 | 0 | 0 | 96 | migration |
| demo-manoir | ❌ | 6 | 23 | 6 | 0 | 0 | 18 | migration |
| inv-demo-alchimiste | ❌ | 6 | 16 | 6 | 0 | 0 | 11 | migration |
| inv-demo-bal-masque | ❌ | 6 | 18 | 6 | 0 | 0 | 13 | migration |
| inv-demo-brumeval | ❌ | 6 | 21 | 6 | 0 | 0 | 16 | migration |
| inv-demo-oracle | ❌ | 6 | 18 | 6 | 0 | 0 | 13 | migration |
| inv-demo-serpent-noir | ❌ | 18 | 114 | 18 | 0 | 0 | 97 | migration |
| inv-demo-train | ❌ | 6 | 22 | 6 | 0 | 0 | 17 | migration |
| **Total** | **4/12** | **106** | **427** | **100** | **0** | **2** | **308** | |

Lecture :
- Graphes **structurellement propres** : 0 transition cassée, 0 auto-boucle, 0 doublon d'id, 0 inatteignable, 0 orpheline.
- **8/12 fichiers inertes** côté Godot (le serveur, lui, en lit 11 dans `data/scenarios/`, sans `demo-valbois`).
- **308/427 transitions sont `gmOnly`** (72 %) : les 9 « autres » scénarios ont été générés mécaniquement, leurs « branches » sont « Continuer vers X », « Revenir à X », « Sauter à la scène finale (MJ) » → **non-linéarité technique, pas éditoriale**.
- **2 terminales seulement** (dans le seul fichier éditeur) et **0 `mapIds`**.
- **Duplication `data/scenarios/` ↔ `game/data/scenarios/`** : 11 fichiers identiques octet pour octet (cause : `tools/migrate_scenarios_navigation.py:12` écrit dans les deux) ; le client lit `game/data` (4 fichiers nommés), le serveur lit `data/` (11) → deux sources de vérité.

---

## 5. Tests : 5/5 PASS, mais que prouvent-ils ?

Commande (reproductible) :
```powershell
$env:GODOT_BIN='C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe'
.\scripts\run_tests.ps1 -Filter 'quest_navigation_test|scenario_editor_test|scenario_library_draft_test|session_story_log_test|session_turn_test'
# → Tests exécutés : 5 · Échecs : 0 · exit 0   (2,2 / 3,6 / 3,0 / 10,8 / 13,9 s)
```

| Test | Prouve | **Ne prouve pas** |
|---|---|---|
| `quest_navigation_test` (10 étapes) | normalisation, sanitisation, reachability, layout, validation, `GameData.go_to_scene/advance_scene/summary` sur fixture | l'UI session, la persistance disque réelle, les 12 JSON, `sceneHistory/visitedSceneIds`, la bascule carte |
| `scenario_editor_test` (12 étapes) | chargement scène, +Scène/+branche, champs, tags, lien carte, auto-layout, save/reload **en mémoire**, suppression, start, popup | le **vrai** glisser-déposer (les handlers internes sont appelés), l'édition label/default/gmOnly (`TransitionRow`), `ConfirmDiscard`, l'édition d'un builtin, `graphPos` après reload disque |
| `scenario_library_draft_test` | helpers brouillons/catalogue + persistance `user://` | l'éditeur lui-même |
| `session_story_log_test` | journal, narration, PNJ, bulle de dialogue | **toute navigation** |
| `session_turn_test` | tour MJ / tour non avancé par action | `go_to_scene` est appelé (`:76`) mais **ni le retour ni la scène cible ne sont assertés** (`:74-79`) |

- **Aucun test automatisé ne touche le panneau de navigation en session** : 0 occurrence de `ScenePicker/BtnGoto/BtnAdvance/BtnComplete/TransitionList` dans `game/scripts/tests/`.
- La navigation en session n'a été vérifiée que par **sonde ad hoc** (4/4) et par le **simulateur Valbois** (`debug/valbois_session_simulator.gd`, 9 scènes, vraie UI) — hors CI.
- `run_tests.ps1:88-100` valide sur la simple présence de « PASS » + exit 0 (ExitCode nul forcé à 0) : garde-fou faible.
- **Aucune CI** : `.github/` ne contient que CODEOWNERS, template PR, template issue.
- `session_state` dans le filtre ne correspond à aucun fichier (script mort, cf. §6).

---

## 6. Ce qui est mort (à supprimer ou réactiver explicitement)

| Élément | Constat | Preuve |
|---|---|---|
| `core/session/session_state.gd` (98 l.) + `core/session/turn_manager.gd` | **0 appelant** ; modèle incompatible (`current_scene_id`/`scene_notes` en snake_case vs `currentSceneId`/`gmNotes` ; `transitions[0]` sans `default`). `docs/ARCHITECTURE.md:14` les présente comme la couche active. | grep `SessionState\.`/`TurnManager\.` = 0 hors eux-mêmes |
| `server/src/game_session.ts`, `ai-gm.ts` (façade 157 l.), `narrative/*`, `bots.ts`, `mcp/*`, `scenario_loader.ts`, `state_serializer.ts` | code mort non compilable ; `index.ts` ne démarre que le pooling | `tsc --noEmit` (5 erreurs), `src/index.ts:6-7` |
| Messages WS legacy `list_scenarios`/`advance_scene` etc. | déclarés, aucun serveur ne les monte | `server/src/types.ts:16-36` |
| `sceneHistory` | jamais relu | grep `sceneHistory` = game_data uniquement |
| `data/schemas/scenario.json` | contrat incomplet/incompatible (snake_case, transitions top-level, `condition`) et **lu par aucun code** | `data/schemas/scenario.json:7-18,133-161` |
| Panneau « Navigation narrative » (doc) | n'existe pas : c'est une section « Scène » de la Console MJ | `session.tscn:76-88` |
| `game/scripts/session.gd` (doc) | fichier inexistant | `docs/QUEST_NAVIGATION.md:131` |

---

## 7. Documentation vs réalité (écarts à corriger)

| Affirmation | Verdict | Corriger |
|---|---|---|
| « Navigation narrative non linéaire (graphe + tests) » = fait (README) | **partiel** : vrai pour un MJ humain, faux pour l'IA/le serveur, tests partiels | préciser le périmètre |
| « 8 autres scénarios restent linéaires jusqu'à migration manuelle » (QUEST_NAVIGATION.md:97) | **faux** : 12/12 branchés, et 8/12 non chargés | remplacer par « 8 fichiers branchés mais non chargés par le client » |
| « Deux démos catalogue uniquement » (README:19,157) | **faux** : 4 scénarios au catalogue | corriger la liste |
| Phase 2 (conditions), phase 4 (PNJ/scène), phase 5 (serveur + IA graphe) | **non faites** | cocher/corriger les tableaux |
| Phase 3 (liaison scène↔carte ✅) | **partiel** : code présent, 0 donnée, 0 test | décocher la coche |
| `docs/STACK.md` (serveur autoritaire, `player_input`/`state_sync`) | **obsolète** | bandeau obsolète |
| `docs/MCP.md` : `roll_dice` listé, `npm run mcp` | **faux / ne démarre pas** | corriger |
| `docs/ARCHITECTURE.md` (`core/navigation/SceneGraph`, « autoloads délèguent à core », « <400 l. ») | **faux** | réécrire |
| Liens README vers `docs/AUDIT_CARTES.md`, `docs/AUDIT_UI_CLARTE.md` ; `game/scenes/main.tscn` | **cassés** | corriger vers `docs/archive/` |
| COLLABORATION.md:40 « main ne casse jamais » + checklist typecheck | **contredit** : le typecheck serveur échoue sur `main` | corriger |

---

## 8. Travail en cours / contexte de dépôt

- Branches scénario `feat/quest-navigation-nonlineaire` et `feat/scenario-editor` : **déjà contenues dans `HEAD`** (commit `ea8dc7d` du 02/09), upstream supprimé. `git stash` : vide. **Rien en cours ailleurs sur le scénario.**
- Depuis `ea8dc7d` : **486 commits**, essentiellement cartes 3D / qualité CS2 / éditeur de carte. Dernières retouches scénario : 12–13/09 (moteur) puis 01/11 (migration `AppTopBar`).
- Working tree : travail non commité sur cartes/CS2 (autre chantier). Un autre agent écrit dans `game_data.gd` (dice) — **coordonner avant toute modification du fichier**.
- Pas de CI, pas de `TODO/FIXME` dans les fichiers scénario, pas de doc « intention » pour cette partie.

---

## 9. Plan proposé (à valider)

### Chantier A — « Rendre l'existant honnête et finissable » (≈ 2–3 j)
1. **Fin de scénario** : ne plus forcer `default` sur une branche `gmOnly` ; `advance_scene` doit clore quand aucune transition *jouable* ne subsiste ; ajouter un marqueur de fin explicite aux 12 JSON (`isEnding`/dernière scène terminale). (S)
2. **Édition builtin** : soit persister l'override (préfixe user, statut « published modifié »), soit interdire « Modifier » une démo. (S)
3. **Charger ou archiver les 8 scénarios inertes** : décider (catalogue + brouillons) et dédoublonner `data/scenarios` (le serveur doit lire la même source que le client). (S)
4. **Campagne longue** : débloquer le format dans `scenario_list.gd` (le hub a déjà les sections courtes/longues). (S)
5. **Documentation honnête** : corriger README / QUEST_NAVIGATION / ARCHITECTURE / MCP / STACK (tableau §7). (S)

### Chantier B — « Rendre la non-linéarité vivante » (≈ 1–2 sem.)
6. **Solo MJ IA minimal** : auto-avance proposée (le jeu présente les branches au joueur, il choisit ; sinon « continuer »), ou mode MJ humain par défaut. (M)
7. **Conditions de branches** (phase 2) : `requiresFlag`/objet/indice, évaluées par le moteur et l'éditeur, refusées en P2P côté hôte uniquement. (M)
8. **PNJ par scène** (phase 4) : filtre `npcs[].scenes` dans `list_session_npcs` + éditeur. (S)
9. **P2P** : resync à la connexion, filtrage `gmNotes`/`sceneHistory` par rôle, flush des notes avant saut. (M)
10. **Historique de session** : UI journal `sceneHistory` (rejouer/auditer). (S/M)

### Chantier C — « Serveur / IA » (décision produit requise, ≈ 1 sem.)
11. Rétablir `AiGM` et le build (`tsc`) ; MCP à nouveau démarrable ; puis brancher une IA sur le **graphe** (phase 5) ou acter que le serveur reste un simple lobby. (M/L)

**Recommandation** : traiter **A en premier** (peu cher, rend la démo présentable et la doc crédible), puis **B6** (le vrai trou fonctionnel), et décider **C** séparément.

---

## 10. Reproductibilité

- Tests : commande §5 (`run_tests.ps1`, Godot 4.7.2 headless).
- Santé des graphes : simulation du chemin par défaut sur les 12 JSON (script ad hoc hors dépôt) ; aucune écriture.
- Serveur : `node server/node_modules/typescript/bin/tsc --noEmit -p server/tsconfig.json` → 5 erreurs.
- Parcours réel : `.\scripts\play-godot-valbois-sim.ps1` (simulateur UI, non automatisé) ; ou `.\scripts\play-godot.ps1` → Hub → Scénarios.

---

## 11. Mise à jour — lisibilité des liens de l'éditeur (2026-11-16, soir)

**Demande** : les branches existent mais passent sous les cartes / sont entremêlées ;
elles doivent rester séparées et visibles même quand on déplace les éléments.

**Corrigé** :
1. **Liens dessinés AU-DESSUS des cartes** par un overlay dédié
   (`game/scripts/scenario_editor/panels/graph_link_overlay.gd`) ; les liens/ports
   natifs de `GraphEdit` sont masqués (`set_slot(..., Color(0,0,0,0), ...)`).
2. **Séparation au port** : peigne vertical par scène (chaque branche sort/entre à un
   point distinct) ; plus de paquet de courbes confondues.
3. **Sémantique** : or = chemin par défaut, bleu = branche, pointillé violet = `gmOnly` ;
   libellé au survol, et pour les branches sortantes de la scène sélectionnée
   (pastilles décalées pour ne pas se recouvrir).
4. **Détours** : une courbe qui traverse une autre carte passe par une voie libre
   (au-dessus/en dessous) au lieu de filer dessous — recalculé à chaque frame de
   déplacement/zoom/pan ; désactivé en vue d'ensemble (zoom < 0,6) pour éviter de
   longs câbles de contournement.
5. **Carte fantôme corrigée** : sans `graphSize`, la hauteur des cartes explosait
   (jusqu'à 2700 px, hauteur pilotée par l'aperçu de texte) et masquait le graphe.
   Hauteur bornée (`max_lines_visible` + `DEFAULT_NODE_HEIGHT = 190`) et espacement
   d'auto-layout porté à 210 px (`quest_navigation.gd`).
6. **Clic droit sur un lien visible** = retirer la branche (le hit-test natif ne
   correspond plus au rendu) ; légende de l'éditeur mise à jour.

**Preuves** : captures A/B dans `docs/screenshots/scenario_graph_links_*.png`
(`_avant` = rendu natif sous les cartes, `_valbois`/`_zoom` = overlay, `_dense` =
peignes + carte au milieu d'un lien, `_moved` = re-routage après déplacement).
Tests : `scenario_graph_links_test.gd` (headless, 9 étapes) +
`scenario_graph_links_shot_test.gd` (captures fenêtre cachée) ; les 6 tests
scénario passent (`run_tests.ps1 -Filter 'quest_navigation|scenario_editor|scenario_library|scenario_graph_links|session_story_log|session_turn'` → 6/6).

