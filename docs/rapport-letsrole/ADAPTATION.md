# De l'inspiration à l'adaptation — ce qu'on garde de Let's Role, et comment on le réécrit pour OpenQuest

> **Règle du document** : **aucune copie**. On ne réutilise ni fichier, ni extrait, ni nom d'API de Let's Role. On retient des **décisions de conception, des structures de données, des algorithmes et des features**, puis on les **réimplémente** dans notre architecture (Godot 4.7 + serveur TS, P2P ENet + pooling, monde de zones 3D, français, projet solo).
> **Conséquence juridique** : pas d'œuvre dérivée → **aucune obligation LGPL**, pas de `THIRD_PARTY.md`, pas de dossier `vendor/`. Les idées, algorithmes et formats ne sont pas protégeables ; c'est justement ce qu'on prend.
> Les [annexes](README.md) restent des **analyses factuelles** (mesures, chemins, licences) : elles ne sont plus un plan de reprise de code.
> Format des fiches : **Leur idée** (ce qui est bon) → **Pourquoi ça marche** → **Notre version** (design + spec) → **Ce qu'on jette** → **Cible + effort + test d'acceptation**.

---

## 0. Tableau de tri

| # | Idée retenue | Ce qu'on garde | Ce qu'on jette | Notre brique | Effort |
|---|---|---|---|---|---|
| 1 | Jets de dés à expression enrichie | feature set + **arbre de résultat** typé + RNG injecté | builder visuel, `mul`/ternaire | `DiceEngine` GDScript + miroir TS | **M** |
| 2 | Visibilité par polygone | occluders = segments, balayage angulaire | rendu Konva, monde 2D plat | polygone de vision par niveau de zone | **M** |
| 3 | Session temps réel robuste | corrélation requête/réponse, ticket de session, rate-limit, codes d'erreur, diffusion par rôle | 4 bases, 209 actions, tables épinglées | protocole P2P + resync hôte | **M** |
| 4 | Modèle de table | calques, barres/aura de token, journal en pages, ordre à valeur, quickbar | médias/musique/PDF/craft | modèle de session adapté à nos lieux/roster | **M** |
| 5 | Fiches déclaratives + formules | séparation données / formules / hooks, tables de données | exécution JS dans le navigateur | `ruleset.json` + formules maison + spec pour l'IA | **L** |
| 6 | Ergonomie de session | dock, taskbar, persistance de layout, popins, raccourcis | DOM/CSS, look web | `DockManager` + au moins 5 raccourcis | **M** |
| 7 | Défauts à ne pas reproduire | — | monolithe, 0 test, config non livrée, reconnexion cassée | garde-fous dans nos lots | — |

---

## 1. Le moteur de dés

**Leur idée.** Une seule grammaire d'expression sert tous les systèmes de jeu : on y met les dés, mais aussi **les modificateurs** (garder les N meilleurs, avantage, explosifs, relances) et **les comparaisons pondérées** (`>=6 {1:2}` = chaque dé ≥ 6 compte 2 succès). Le résultat n'est pas un nombre : c'est un **arbre** qui garde chaque dé, son côté, ceux qui ont été défaussés, les tags et les succès/échecs.

**Pourquoi ça marche.** L'UI peut *raconter* le jet (« 2 dés gardés sur 4, un 6 explosé ») au lieu d'afficher un total. Et un même moteur couvre le tier simple (2d6+3) comme les systèmes à succès, sans coder un moteur par jeu.

**Notre version.** Un moteur GDScript autonome, avec **notre propre grammaire** (spécifiée en EBNF ci-dessous, écrite pour notre jeu, pas recopiée) et **notre propre schéma de résultat**. Il vit dans `game/scripts/core/rules/dice_engine.gd`, testable en headless, et un miroir TS dans `server/src/rules/dice_engine.ts` pour les bots et le MJ IA.

Spec de la grammaire (v1) :

```ebnf
expression  = comparison ;
comparison  = sum { ( ">=" | "<=" | ">" | "<" | "=" | "!=" ) sum } ;
sum         = term { ( "+" | "-" ) term } ;
term        = unary { ( "*" | "/" ) unary } ;
unary       = { "-" } primary ;
primary     = dice | integer | "(" expression ")" ;
dice        = [ integer ] "d" integer [ modifier ] { modifier } [ "[" tags "]" ] ;
modifier    = "keeph" integer | "keepl" integer | "adv" | "disadv"
            | "expl" | "reroll1" | "min" integer | "max" integer ;
tags        = ident { "," ident } ;
```

Schéma de résultat (notre format, à figer dans `data/schemas/dice_roll.json`) :

```json
{ "kind": "dice", "total": 11, "tags": ["degats"],
  "dice": { "sides": 6, "count": 4, "values": [3,5,1,6], "kept": [3,5,6], "dropped": [1] },
  "children": [], "success": 0, "failure": 0 }
```

Décisions d'adaptation :
- **RNG injecté** (`seed` paramétrable) : indispensable pour nos tests headless *et* pour que l'hôte (MJ) puisse rejouer un jet côté serveur si besoin d'anti-triche.
- **Même spec, deux implémentations** : on écrit un jeu de **cas de test partagé** (`tests/data/dice_cases.json`) ; le runner GDScript et le runner TS vérifient les mêmes attendus. Si les deux passent, les deux moteurs sont conformes — sans avoir partagé une ligne.
- **Intégration** : on garde l'interface actuelle de `server/src/dice.ts` (`Dice.roll`, `formatResult`) et on remplace son intérieur ; on étend `game/scripts/core/rules/dice.gd` (49 l. de regex) par le parseur. Le journal de session (`SessionState`) reçoit l'arbre + la visibilité (MJ/table) et le HUD joueur l'affiche.
- **Adapté à nos tiers** : tier simple → `2d6+3`, `adv` ; tier medium/complete → `1d20+mod` et comparaisons pondérées ; jets de dégâts tagués `degats` pour que le MJ IA les reconnaisse.
- **Ce qu'on jette** : `mul` (nombre de dés par un autre dé), le ternaire, `minmax` complexe au démarrage ; le constructeur visuel de jet (notre tray actuel suffit).
- **Effort** : **M** (parseur + moteur + UI de jet). **Test** : 30 cas couverts, dont `4d6keeph3`, `1d20adv`, `2d6expl`, `5d10>=6 {1:2}`, `2d6+1d8-2`.

---

## 2. Le brouillard et la ligne de vue

**Leur idée.** Les obstacles (murs, portes fermées) sont convertis en **segments 2D** ; on calcule le **polygone de visibilité** du point d'observation par balayage angulaire sur ces segments ; le brouillard est le complément de ce polygone. Un mur oblique, une porte qui s'ouvre, un couloir : tout est traité uniformément, sans grille.

**Pourquoi ça marche.** Complexité O(N log N), bords lisses (pas d'escalier), et le polygone sert aussi bien au rendu qu'à la logique (« ce PNJ est-il visible ? »).

**Notre version — et pourquoi elle est très proche.** Nous avons déjà les briques de départ : `game/scripts/maps/map_vision.gd` (228 l.) décrit les murs par segments (`segment_of`, `blocksSight`, portes `isDoor/open`) et `game/scripts/autoload/game_data.gd` gère un brouillard par **cases révélées** (`fogRevealed`, `reveal_fog_cells`, `recompute_dynamic_fog`, opération réseau `fog_reveal`). Ce qui manque, c'est la *forme* du brouillard : aujourd'hui c'est rayon-par-case.

Design adapté :
1. **`OccluderSource`** : réutilise `MapVision.wall_segments()` (déjà écrit chez nous) comme entrée. Rien à copier.
2. **`VisibilityPolygon`** : balayage angulaire maison — trier les angles des extrémités de segments vus depuis l'observateur, lancer un rayon par sommet (+ un epsilon de chaque côté), couper au plus proche segment, dédupliquer. ~150 l. testables seules.
3. **Deux couches de brouillard, à garder séparées** : (a) *exploration* persistante en cases (déjà là, sauvegardée dans `fogRevealed`) ; (b) *vision courante* polygonale, recalculée quand un token bouge ou qu'une porte s'ouvre.
4. **Adaptation à notre monde 3D** : un polygone **par niveau** (étage / zone), les occluders projetés au sol ; la hauteur ne joue que pour choisir le niveau. C'est la vraie différence avec leur battlemap 2D : chez nous l'occlusion est multi-niveaux, et le brouillard doit suivre le changement de zone du joueur (`world_navigation.gd`).
5. **Réseau (P2P)** : le calcul de visibilité se fait **côté hôte** (le MJ), qui envoie les zones révélées et/ou le polygone courant ; jamais le client ne décide de sa visibilité (sinon triche). On étend l'opération `fog_reveal` existante (déjà autorisée MJ) sans changer le protocole.
6. **Rendu** : masque polygonal dans une `SubViewport`/`CanvasLayer` projeté pour la carte 3D, filtre sur la minimap.

**Ce qu'on jette** : le rendu Konva, la gestion 2D « une scène = un écran », les portes animées (nous avons déjà nos portes 3D).
**Effort** : **M** (polygone + intégration niveaux). **Test** : pièce fermée → aucun pixel hors pièce ; porte ouverte → le couloir apparaît ; 200 segments → < 2 ms.

---

## 3. La session temps réel

**Leur idée.** Trois mécanismes séparés qui, ensemble, donnent une session « solide » :
1. **Corrélation** : chaque requête client porte un identifiant, la réponse revient avec le même (on sait à quoi elle répond) ;
2. **Ticket de session** : à la connexion, le serveur remet un jeton avec une durée de vie ; une coupure réseau se répare en présentant le ticket, sans perdre l'état ;
3. **Garde-fous** : validation des messages entrants, limite de fréquence **par action**, codes d'erreur contractuels, et diffusion **filtrée par rôle** (le MJ reçoit des choses que les joueurs ne reçoivent pas).

**Pourquoi ça marche.** Ce sont les quatre causes réelles de « partie cassée » : réponse perdue, reconnexion impossible, client qui spamme, fuite d'info MJ. Et chaque mécanisme est petit et testable.

**Notre version — inversion d'autorité obligatoire.** Chez nous, **l'hôte Godot (MJ) est l'autorité**, pas le serveur. Donc :
- **Pooling = annuaire + signalisation + ticket** : le serveur attribue un `session_ticket` (code de salon + TTL + identité), utile pour retrouver une room. On ajoute `req_id` et `err_code` à nos messages plats (déjà typés dans `server/src/lobby/types.ts`) au lieu d'adopter leur enveloppe `{c,a}`.
- **Reconnexion = resync par l'hôte** : notre `server/src/state_serializer.ts` produit déjà `ClientGameState`. On l'utilise comme **snapshot de resynchronisation** : à la reconnexion, le client demande `sync_request`, l'hôte renvoie snapshot + dernière opération ; puis le client réapplique les deltas. Pas besoin de ticket côté serveur pour ça — un ticket local (adresse hôte + code) suffit en LAN.
- **Rate-limit côté hôte** : un client peut noyer l'hôte en `move_token`/`signal` ; on limite par (action, joueur) et on ferme au-delà du double du seuil. Le serveur ne limite que l'inscription et le `ping`.
- **Diffusion par rôle** : notre modèle « joueur soumet → MJ valide → rediffusion de l'opération seule » (`submit_map_op`, `PLAYER_ALLOWED_OPS`) est déjà le bon ; on ajoute un filtre explicite : `to_table`, `to_player(id)`, `to_gm` — le serveur/hôte ne diffuse jamais un état complet aux joueurs.
- **Contrat d'erreurs** : on définit nos codes (refus de rôle, room pleine, hôte parti, ticket expiré) et le client Godot affiche un message précis au lieu d'un timeout.

**Ce qu'on jette** : les 4 bases, les tables épinglées à une instance, les 209 actions, l'authentification par token d'URL.
**Effort** : **M**. **Test** : couper le réseau 5 s pendant une partie → le client resynchronise sans perdre les positions ; spam de 200 `move_token`/s → fermeture propre.

---

## 4. Le modèle de session

**Leur idée.** Une table est décrite par un modèle riche mais générique : **calques** (visibles/MJ/verrouillés), **tokens** avec aura et deux barres liées à des valeurs, **journal** en dossiers/pages avec permissions, **ordre de tour** à valeur (ouvert/fermé, sens), **quickbar** configurable par personnage.

**Pourquoi ça marche.** Les mêmes structures servent tous les jeux : une barre de token n'est pas « les PV de D&D », c'est « une jauge liée à une valeur de fiche » ; un ordre de tour n'est pas « l'initiative », c'est une liste ordonnée avec valeur.

**Notre version — adaptée à notre jeu, qui n'est pas une battlemap.**
- **Lieux et zones au lieu de scènes** : un « lieu » = une zone de notre monde 3D (diorama) ; le modèle doit décrire ses entrées, ses PNJ, ses objets interactifs, son ambiance. On garde l'idée de **calques** uniquement pour l'**éditeur** (déjà présent : outliner/inspector) et le mode **VTT** ; pas pour la carte diorama.
- **Tokens = figurines + entrées de roster** : on garde l'idée **barres liées** (PV, mana, stress) et **aura** (effet de sort, zone d'effet) — chez nous l'aura devient une **décalque 3D** au sol, pas un cercle 2D. Le lien barre ↔ fiche est la vraie bonne idée.
- **Journal = journal de campagne** : on garde la séparation *fil de session* (ce qui s'est dit) / *pages MJ* (notes structurées, partageables par joueur), sans l'éditeur riche ni les PDF. C'est le manque le plus visible aujourd'hui (`gm_notes.tscn` = 64 l. sans structure).
- **Ordre de tour** : on garde la structure « liste ordonnée avec valeur et sens », mais notre jeu est **narratif** : on l'utilise en **option combat/initiative** greffée sur `core/session/turn_manager.gd` (qui connaît aujourd'hui un simple index de membre). Le mode narratif reste le défaut.
- **Quickbar** : on garde l'idée de **slots persistés par personnage** (titre, action, visibilité MJ/table, icône), mais les actions disponibles restent nos actions de jeu (pas de formules de fiche dans l'UI au départ).

**Ce qu'on jette** : médias, musique, sons, PDF, craft, book — hors périmètre de notre jeu pour l'instant.
**Effort** : **M** (modèles + migration `active_game`). **Test** : sauvegarde/rechargement d'une session avec barres liées, journal à pages et ordre de tour optionnel.

---

## 5. Les fiches déclaratives, les formules et le MJ IA

**Leur idée — la plus inspirante du lot.** Une fiche n'est pas du code : c'est un **arbre de composants** (rangées, colonnes, champs, répéteurs, onglets) + des **variables liées** + des **formules à références croisées** (`@caractéristique`, `$variable`, `#contexte`, `if/round/avg/sum`) + des **hooks** (initialisation, mise à jour, jet, drop) + des **tables de données** (listes d'armes, sorts) éditables par le créateur du système.

**Pourquoi ça marche.** Un créateur peut brancher un nouveau jeu sans développeur ; et les formules sont **déclaratives** (pas de script à exécuter dans un navigateur).

**Notre version — sans JavaScript, et adaptée à nos 3 tiers.**
- Nos tiers (`simple`, `medium`, `complete`, cf. `docs/CHARACTER_EDITOR.md`) restent des **presets** codés — c'est notre force (un joueur clique et joue).
- On ajoute **au-dessus** un format déclaratif `data/schemas/ruleset.json` : description des champs, valeurs dérivées, jets standard, tables. Un MJ peut alors créer un « tier custom » sans toucher au code.
- Les **formules** sont réimplémentées en GDScript : petit parseur d'expressions avec références `@champ`, `$variable`, `if(...)`, `round/floor/ceil/min/max/sum/avg`, résolution avec **détection de cycles**. Pas d'interpréteur JS embarqué, pas de `vm`.
- Les **hooks** sont des signaux Godot (`on_roll_requested`, `on_damage_applied`) déclenchés par le code du jeu ; au début, seule une bibliothèque d'effets prédéfinis est exposée (pas de scripting utilisateur).
- **Le vrai levier IA** : écrire **notre propre document de spec** (équivalent de leur doc destiné aux IA, mais pour notre schéma) et le donner au MCP / au MJ IA (`server/src/mcp/`, `server/src/ai-gm.ts`). L'IA pourra proposer des fiches, des règles maison et des jets valides — c'est l'idée la plus rentable à long terme, et elle ne demande **aucune ligne** de Let's Role.

**Ce qu'on jette** : l'exécution JS côté client, les 15 composants DOM, l'éditeur de fiche web.
**Effort** : **L** (format + parseur + éditeur + spec IA). **Test** : deux rulesets différents (Naheulbeuk-like et D&D-like) définis **sans code**, joués dans une session.

---

## 6. L'ergonomie de session

**Leur idée.** L'écran de jeu est une **grille de zones** (colonnes gauche/droite, carte plein cadre, barre de tâches par catégories, popins empilés), les panneaux peuvent être **détachés/attachés/minimisés**, la disposition est **persistée**, et des **raccourcis** couvrent les gestes fréquents.

**Pourquoi ça marche.** Un MJ manipule 5 à 8 outils très différents ; sans dock, l'écran devient une pile de fenêtres. Et la persistance évite de tout replacer à chaque session.

**Notre version.** `game/session/session_shell.gd` monte aujourd'hui **17 panneaux fixes** : on introduit un `DockManager` (Godot `Control`) avec 3 emplacements (gauche/droite/popin), un **layout déclaratif par rôle** (MJ/joueur), et une sauvegarde `user://ui_layout.json`. La barre de tâches reprend nos panneaux et les groupe (carte / narration / personnage / outils). Les popins empilés deviennent un `PopinStack`. Raccourcis à ajouter : `P` ping, `M` carte du monde, `C` minimap, `Ctrl+Z` undo éditeur, `Suppr`, `Ctrl+C/X/V` presse-papier.

**Ce qu'on jette** : DOM/CSS, thèmes web, positionnement jQuery.
**Effort** : **M**. **Test** : layout MJ ≠ layout joueur, restauré au redémarrage ; ouverture/fermeture de chaque panneau.

---

## 7. Les défauts qu'on ne reproduit pas

| Défaut constaté | Leçon pour nous |
|---|---|
| Monolithe de 209 actions, contrôleur de 2 860 l. | découper par domaine (`rules/`, `scene/`, `chat/`) dès le départ |
| 0 test alors que c'est un moteur | nos tests headless existants sont un avantage : toute idée adaptée arrive avec son test |
| Config de production non livrée, artefact généré non compilable | notre `data/schemas/` + `scripts/` doivent suffire à reproduire un build |
| Reconnexion déclarée mais cassée | toute feature réseau testée par une coupure réelle |
| 4 bases de données pour un jeu de table | nos `user://` + JSON suffisent ; on n'ajoute une base que si nécessaire |
| Bus factor 1, historique tronqué | on documente nos décisions (ce doc) et on garde nos tests |
| Assets propriétaires mélangés au code libre | nos assets restent séparés et licenciés explicitement |

---

## 8. Plan d'adaptation en 5 lots

| Lot | Idée adaptée | Fichiers cibles (créés/modifiés) | Effort | Critère d'acceptation |
|---|---|---|---|---|
| **1** | **Dés** : grammaire + arbre de résultat + cas de test partagés | `game/scripts/core/rules/dice_engine.gd` (nouveau), `dice.gd` (remplacé), `server/src/rules/dice_engine.ts`, `data/schemas/dice_roll.json`, `tests/data/dice_cases.json` | M | 30 cas verts en GDScript **et** en TS ; `ai-gm.ts`/`game_session.ts` inchangés |
| **2** | **Vision** : polygone par niveau, brouillard lissé | `game/scripts/core/los/visibility_polygon.gd`, `map_vision.gd` (étendu), `interactive_map.gd` (rendu) | M | pièce fermée / porte / couloir corrects ; MJ autoritaire |
| **3** | **Session** : `req_id`, ticket, resync, rate-limit, filtres | `server/src/lobby/types.ts`, `lobby/rooms.ts`, `game/scripts/multiplayer/multiplayer_manager.gd`, `state_serializer.ts` | M | coupure 5 s → resync sans perte ; spam → fermeture |
| **4** | **Modèle de session** : barres/aura, journal en pages, ordre optionnel, quickbar | `data/schemas/`, `core/session/`, `panels/` | M | session sauvegardée/rechargée fidèlement |
| **5** | **Fiches déclaratives + spec IA** | `data/schemas/ruleset.json`, `core/rules/formula.gd`, `docs/SPEC_RULESET_IA.md` | L | 2 rulesets sans code, générés/proposés par l'IA |

Ordre conseillé : **1 → 2 → 3 → 4 → 5**. Les lots 1 et 2 transforment immédiatement l'expérience (jets riches, brouillard propre) ; le lot 5 est un investissement pour la suite.

---

## 9. Ce qui reste vrai des annexes

Les [annexes 1](annexe-1-moteur-donnees.md), [2](annexe-2-front-web.md) et [3](annexe-3-serveur.md) gardent leur valeur **documentaire** : mesures, chemins, inventaire des modèles, protocole observé, licences et pièges. Elles ne servent plus de plan de copie — elles répondent à « qu'est-ce qui existe, comment c'est fait, qu'est-ce qui est bon ». Le présent document répond à « qu'est-ce qu'on en fait, chez nous ».

Un seul point pratique subsiste : **si** un jour on veut réutiliser un asset tiers (icônes, polices), il faut le sourcer **directement à sa source** (ex. game-icons.net, CC BY 3.0, attribution) et non via un dépôt Let's Role — mais aucun asset de jeu n'est nécessaire à l'adaptation des idées ci-dessus.

---

## 10. Avancement

| Lot | État | Preuves |
|---|---|---|
| **1 — Dés** | ✅ **fait (2026-11-16)** | `game/scripts/core/rules/dice_engine.gd`, `server/src/rules/dice_engine.ts`, `data/schemas/dice_roll.json`, cas partagés `game/data/tests/dice_cases.json` ; tests : `dice_engine_test` (GDScript) et `npm run test:dice` (TS) verts ; doc [`docs/MOTEUR_DES.md`](../MOTEUR_DES.md) ; façades `Dice.roll/format` conservées, `ai-gm.ts`/`game_session.ts` inchangés |
| **2 — Vision** | ✅ **fait (2026-11-16)** | `game/scripts/core/los/visibility_polygon.gd` (polygone radial : 48 rayons + angles de coins), `MapVision.visibility_polygons` / `is_point_visible`, `GameData.get_map_visibility_polygons` ; **rendu** `session/panels/fog_overlay.gd` (cases révélées hors vision assombries + contour lissé, projeté par `grid_to_screen`), câblé dans `map_workspace.gd` / `map_stage.gd` ; tests `visibility_polygon_test` + `fog_overlay_test` verts, `map_vision_test` inchangé ; doc [`docs/BROUILLARD_VISION.md`](../BROUILLARD_VISION.md) ; décision mesurée : cases = rayon/case (1,5 ms / 40 murs), polygone = rendu (48 rayons) |
| **3 — Session** | ✅ **fait (2026-11-16)** | serveur : `lobby/protocol.ts` (codes + `req_id`), `validate.ts` (zod), `rate_limit.ts` (fenêtre glissante), `tickets.ts` (reprise, TTL 2 min), `pooling/server.ts` v2 ; client : `multiplayer_manager.gd` (`_send_request`, tickets persistés, erreurs typées, `request_state_resync` après (re)connexion P2P) ; tests `server/scripts/test_lobby.ts` (81 vérif.), `test_lobby_integration.ts` (18 vérif. réseau), `session_protocol_test.gd` ; doc [`docs/SESSION_PROTOCOLE.md`](../SESSION_PROTOCOLE.md) |
| **4 — Modèle de session** | ✅ **fait (2026-11-16)** | `game_data.gd` section « Modèle de session » : barres liées à la fiche + sync (`set_token_bar`, `sync_token_bars_from_party`), aura bornée, journal dossiers/pages avec visibilité `table`/`gm` et filtre joueur, ordre de tour optionnel (`open`, `direction`, `sort`, `next`), quickbar 10 slots assainis et filtrés ; opérations réseau `set_bar`/`set_aura` (barres de son token autorisées au joueur) ; contrat [`data/schemas/session_model.json`](../../data/schemas/session_model.json), `save_game.json` étendu ; test `session_model_test` ; doc [`docs/MODELE_SESSION.md`](../MODELE_SESSION.md) |
| **5 — Fiches déclaratives** | ✅ **fait (2026-11-16)** | `game/scripts/core/rules/formula.gd` (langage de formules maison : `@champ`, `$var`, `if/round/floor/ceil/abs/min/max/sum/avg`, comparaisons/logique, erreurs typées), `ruleset.gd` (validation, défauts, dérivés avec dépendances + détection de cycles, `expand_roll` vers le moteur de dés) ; exemples sans code `game/data/rulesets/naheulbeuk_simple.json` + `dnd_complete.json` ; contrat [`data/schemas/ruleset.json`](../../data/schemas/ruleset.json) ; spec IA [`docs/SPEC_RULESET_IA.md`](../SPEC_RULESET_IA.md) ; test `ruleset_test` |

**Bilan des 5 lots** (2026-11-16) : ~2 900 lignes de modules nouveaux (dés GDScript+TS, vision, protocole serveur, formules/ruleset), 9 suites de tests nouvelles (GDScript et Node, dont un test réseau de bout en bout), 5 documents de spécification, 3 schémas JSON + 2 rulesets d'exemple. Suite headless complète : **106/111** — les 5 échecs observés (`map_editor_snap_test`, `map_editor_v2_palette_test`, `scene_load_test`, `terrain_strata_test`, `webrtc_pooling_e2e_test`) sont **hors périmètre** : éditeur/terrain en cours de modification par un autre intervenant (fichiers modifiés pendant la session), `scene_load_test` passe seul, et le test WebRTC nécessite le serveur de pooling LAN. Tous les tests du plan passent (`dice_engine_test`, `visibility_polygon_test`, `fog_overlay_test`, `session_protocol_test`, `session_model_test`, `ruleset_test`, `map_vision_test`, `session_*`).
