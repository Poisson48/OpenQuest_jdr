# Audit OpenQuest JDR

**Dépôt** : [Poisson48/OpenQuest_jdr](https://github.com/Poisson48/OpenQuest_jdr) (checkout `main`)  
**Cible** : client Godot 4.7 (`game/`) + serveur Node pooling (`server/`)  
**Date** : 20 septembre 2026  
**Méthode** : lecture du code, des scènes, des schémas JSON, des tests et de la documentation du dépôt. Aucun binaire Godot n’était disponible dans l’environnement d’audit ; le client n’a donc pas été exécuté. Les constats d’interface déjà documentés dans `docs/AUDIT_UI_CLARTE.md` et `docs/AUDIT_CARTES.md` sont repris seulement s’ils sont encore visibles dans le code actuel.

---

## Résumé

OpenQuest est un **VTT de table JDR** (cartes, journal, dés, fiches) plus qu’un jeu aux règles fermées. Le runtime réel est **client Godot autoritaire en P2P ENet**, coordonné par un **serveur de pooling WebSocket** (salons à code 4 chiffres). Ce n’est plus le modèle « serveur Node autoritaire » décrit dans `docs/STACK.md`.

Le produit est **jouable en solo** autour de deux démos (`demo-valbois`, `demo-crypte`). Le multijoueur LAN existe, mais l’autorité de l’hôte MJ **fait confiance à l’identité envoyée par le client**, et **l’état complet de partie** (brouillard, tokens MJ, journal) est diffusé à tous les pairs. Le MJ IA du client est un **tirage de 4 phrases**, alors qu’un moteur narratif TypeScript abouti (`server/src/ai-gm.ts`, ~1 900 lignes) n’est branché que sur un serveur MCP séparé, jamais sur la session Godot.

Les règles de personnage (caractéristiques, CA, tiers simple/classique/complet) **n’influencent pas** les jets ni les actions en session.

| Gravité | Nombre |
|---------|--------|
| Critique | 3 |
| Élevé | 11 |
| Moyen | 10 |
| Faible | 6 |

---

## 1. Architecture (client / serveur)

### Ce qui tourne vraiment

```
Client Godot 4.7 (Forward+)                 Serveur Node 20+ (pooling)
┌─────────────────────────────┐             ┌──────────────────────────┐
│ Autoloads : GameData,       │  WebSocket  │ src/index.ts             │
│ MapData, MultiplayerManager │  JSON :8080 │ → pooling/server.ts      │
│ Session MJ / HUD joueur     │◄───────────►│   RoomManager (RAM)      │
│ ComplexMapEngine3D / Simple │  matchmaking│   codes 4 chiffres       │
│ ENet hôte = PC du MJ :7777  │             │   relais `signal` (stub) │
└──────────────┬──────────────┘             └──────────────────────────┘
               │
               └── P2P ENet : état, actions, dés, ops de carte
```

Preuve : `server/src/index.ts` ne démarre que `startPoolingServer`. `game/scripts/multiplayer/multiplayer_manager.gd` envoie `create_room` / `join_room` au pooling, puis `ENetMultiplayerPeer.create_server(7777)` ou `create_client`.

Le pooling **ne contient aucune logique de jeu**. Salons, codes, personnages enregistrés et adresse P2P vivent en mémoire (`server/src/lobby/rooms.ts`). Fermeture du salon si le MJ quitte.

### Divergence documentation

`docs/STACK.md` décrit encore un serveur autoritaire qui reçoit `player_input` et diffuse `state_sync` avec des positions x/y. Ce protocole n’existe plus. Le fichier vivant est `docs/MULTIPLAYER.md`, que le README signale déjà comme source de vérité — mais `STACK.md` reste présenté comme « document de référence ». `server/src/types.ts` et `state_serializer.ts` appartiennent à l’ancien protocole (`start_game`, `game_action`, `dice_roll`) et ne sont plus importés par `index.ts`.

### Deux cerveaux de jeu

| Couche | Rôle déclaré | Branché au runtime Godot ? |
|--------|----------------|----------------------------|
| `game/scripts/autoload/game_data.gd` (~3 000 lignes) | État de partie, cartes, dés, navigation | Oui — source unique en session |
| `server/src/game_session.ts` + `ai-gm.ts` + `bots.ts` + `dice.ts` | Session autoritaire, MJ IA, jets | Non — uniquement `npm run mcp` |
| `server/src/mcp/gm_server.ts` | Outils MCP (`classify_action`, `resolve_action`…) | Cursor / Claude Desktop, pas le jeu |

Conséquence : toute évolution des règles doit être faite deux fois, ou elle diverge. Aujourd’hui elle a divergé.

### Dépendances serveur fragiles

Dans `server/package.json`, `ws` et `dotenv` sont en **devDependencies**, alors que `src/index.ts` et `pooling/server.ts` les importent au runtime. Un `npm install --omit=dev` (déploiement) casse le serveur. Les scripts `test-pooling.mjs` / `test-pooling-extended.mjs` ne sont pas déclarés dans `"scripts"`.

---

## 2. Systèmes de jeu

### Boucle de session

1. Menu → setup (scénario, format, groupe, MJ humain/IA) → `GameData.create_new_game`.
2. Journal BBCode + suggestions d’actions prédéfinies.
3. Carte simple (tuiles) ou complexe 3D (diorama / VTT).
4. Navigation de scènes (graphe `QuestNavigation`) réservée au MJ.
5. Dés `NdS±M` (bornes 100d1000).
6. Tours : `turnIndex` parmi les humains ; en MJ humain, `waitingForGm` bloque les joueurs.

C’est une **table assistée**, pas un simulateur de combat. Envoyer « Je dégaine mon arme » n’inflige aucun dégât, ne jette aucun d20 contre la CA, ne consomme aucun PV. Les stats (`str`…`cha`, `simpleStats`, `ac`, `hp`) servent à l’affichage de fiche.

### MJ IA

Deux implémentations incompatibles :

- **Client** (`session.gd` `_simulate_ai_response` et copie dans `multiplayer_manager.gd` `_host_simulate_ai_response`) : 4 phrases génériques + reprise de l’action entre italiques, plus une réplique bot tirée au hasard. Aucune classification, aucun jet suggéré, aucune mémoire.
- **Serveur** (`ai-gm.ts`) : classification combat/talk/explore/stealth/support/creative, suggestion de formule + DD selon stats et tension, narration à règles, anti-répétition. Exposé via MCP seulement.

En P2P, le MJ IA tourne **uniquement sur l’hôte**, ce qui est correct architectualement — mais le contenu est le stub.

### Cartes

Dual-mode mature :

- Simple : `simple_map_renderer.gd` + `interactive_map.gd`.
- Complexe : `complex_map_engine_3d.gd` + calques (sol, props, murs, fog, tokens, lumières, zones, effets).
- Styles diorama / VTT via `map_render_style.gd`.
- Éditeur battlemap (`map_complex_editor.gd`, ~2 800 lignes) avec document, undo, outils, bibliothèque — types consommés par `preload` (correctif P0 de l’audit UI).
- Vision / portes : `map_vision.gd` + `recompute_dynamic_fog` ; filtrage `filter_map_entry_for_player` **appliqué à l’affichage local**, pas au réseau (voir sécurité).
- Ops de carte (`move_token`, `place`, `fog_*`, `door`…) : bonne intention (delta plutôt que snapshot), mais `PLAYER_ALLOWED_OPS` inclut **toutes les portes** pour n’importe quel joueur.

La caméra perspective a été **corrigée dans le code** (`_ground_span_per_pixel` par rayons, `_update_fit_base`, tests `map_camera_test.gd`). L’audit cartes de septembre qui déclarait un pan ~9× trop lent est **obsolète sur ce point**. Le README liste encore la qualité PNG Valbois et le cadrage HUD comme WIP.

### Déplacement sémantique

`try_auto_move_from_action` parse « nord / taverne / … » et déplace le token. Utile en solo ; en multi, `_get_active_human_member_id` prend **le premier humain du groupe**, pas l’auteur de l’action — un joueur peut donc déplacer le pion d’un autre.

### Persistance

Tout est local `user://` (`characters.json`, `maps.json`, `saved_games.json`, `active_game.json`, cache `map_assets`). Pas de cloud, pas de versioning de sauvegarde. Chaque `add_log_entry` réécrit **toute** la partie (`save_active_game` → `_upsert_saved_game_entry`).

---

## 3. Données et contenu

### Catalogue

Le client ne propose **que** `demo-valbois` et `demo-crypte` (`DEMO_SCENARIO_IDS` dans `game_data.gd`). Pourtant :

- `game/data/scenarios/` contient 11 JSON (enquêtes, Couronne, Kharak, train, etc.).
- `data/scenarios/` (racine, consommée par `server/src/scenario_loader.ts`) en contient 10, **sans** `demo-valbois`.
- Les cartes tuilées historiques (`demo-taverne`, `demo-quartier-serpent`…) existent en double (`data/maps/` et `game/data/maps/`).

Deux arbres de contenu non synchronisés. Le serveur MCP charge `../../data/scenarios` (racine), donc **pas** la démo phare Valbois.

Le mode Enquête a du contenu (scénarios `inv-demo-*`, roster, onglet Hub) mais l’onglet est **masqué** (`hub.gd` `set_tab_hidden`). Les JSON d’enquête restent dans le dépôt, invisibles au joueur.

### Schéma personnage

`data/schemas/character.json` (et sa copie `game/data/schemas/`) impose `stats` + `hp` + `ac`, `additionalProperties: false`. Le client a depuis ajouté `rulesetTier` (`simple` / `medium` / `complete`), `simpleStats`, `spellcasting`, portraits, etc. Le schéma n’est **validé nulle part** à l’exécution. Contrat mort.

### Kael (démo Valbois)

`_ensure_kael_character` **écrase** à chaque chargement toutes les clés de la fiche `char-kael` avec le seed. Toute édition joueur de Kael est perdue au prochain lancement. `_apply_valbois_demo` réinjecte Kael dans le groupe et force la navigation sur le village.

Tokens de démo : `scale: 1.0` (hauteur 1 case après migration). L’ancien bug « Kael = maison » (`scale` = fraction de la hauteur de carte) est **migré dans le moteur** (`scale_val < 0.5` → ancienne sémantique). Le README le liste encore comme à calibrer — à revalider en jeu, plus à traiter comme un crash d’échelle 30 cases.

### Licence

README : « À définir. » Pas de fichier LICENSE.

---

## 4. Bugs et correction

Les findings ci-dessous sont classés par gravité. Preuves = chemins et comportement observé dans le code.

### Critique

**C1 — L’hôte P2P croit l’identité déclarée par le client**  
Fichiers : `game/scripts/multiplayer/multiplayer_manager.gd` (`request_start_game` L537–552, `submit_action` L560–564, `request_dice_roll` L566–570, `gm_broadcast` L572–578).

Les RPC `any_peer` reçoivent un `sender_player_id` **choisi par l’appelant**. Sur l’hôte, `request_start_game` accepte l’appel dès que `sender_player_id == player_id` (l’UUID pooling **de l’hôte**, connu de tous via `room_update`). Un joueur peut donc :

- lancer / écraser la partie ;
- publier une action ou un jet au nom d’un autre (`submit_action` n’appelle même pas `_is_gm_peer`) ;
- forger une narration MJ (`gm_broadcast` vérifie `_is_gm_peer(sender_player_id)`, or le `gmId` est public).

Godot expose `multiplayer.get_remote_sender_id()` : il n’est pas utilisé. En LAN amical c’est de la triche ; dès qu’un pair n’est pas de confiance, c’est une prise de contrôle de table.

**C2 — Le brouillard et les secrets MJ voyagent en clair**  
`broadcast_state()` envoie `GameData.active_game.duplicate(true)` à tous (`sync_game_state`). `filter_map_entry_for_player` n’est appelé que dans `map_panel.gd` pour **l’affichage**. Un client modifié lit `mapPlayState[*].tokens` (`gmOnly`, `hidden`), `fogRevealed`, indices d’enquête. Le commentaire de `game_data.gd` L1685–1689 (« l’information n’est plus là ») est faux sur le chemin réseau. Confirmé aussi par `docs/MULTIPLAYER.md` et le README (sync fog « encore incomplet »).

**C3 — Pas d’authentification, rôle MJ auto-proclamé**  
`create_room` exige `role: "gm"` **dans le JSON client**. N’importe qui sur le WebSocket crée un salon MJ. Les codes sont 4 chiffres (`randomInt(1000, 10000)` → 9 000 valeurs) et `list_rooms` / `lobby_update` **publient codes et `p2pHost`**. Sur LAN c’est acceptable pour une table ; ce n’est pas un service Internet. Combiné à C1, un intrus LAN rejoint, usurpe le MJ, et pilote la partie.

### Élevé

**E1 — MJ IA client = 4 phrases ; moteur `ai-gm.ts` mort pour le jeu**  
`session.gd` L665–695 et `multiplayer_manager.gd` L497–521. Le MCP (`npm run mcp`) n’est jamais appelé par Godot. `.cursor/mcp.json` pointe même un chemin machine (`/home/leo/Documents/github/OpenQuest_jdr/server`).

**E2 — « Reconnexion » = nouveau joueur**  
Chaque socket pooling reçoit un `randomUUID()` (`pooling/server.ts` L294). `rejoin_room` est un alias de `join_room`. Après coupure, l’ancien `playerId` a quitté le salon ; le client revient avec un **nouvel** UUID, sans personnage, et les `clientId` du groupe ne matchent plus. La doc promet une reconnexion joueur.

**E3 — Les règles de fiche ne s’appliquent pas**  
`roll_dice` ignore stats, compétence et DD. `can_member_act` ne s’applique en multi qu’en MJ humain (`_host_process_action`). En MJ IA, n’importe qui agit à tout moment. PV/CA ne changent jamais.

**E4 — Snapshot complet + I/O disque à chaque ligne de journal**  
`add_log_entry` → `save_active_game` (JSON indenté de toute la partie, y compris `mapPlayState`) + signal UI. En P2P, `broadcast_state` renvoie le même objet à tous. Les ops de carte existent pour éviter ça, mais actions / dés / scènes ne les utilisent pas.

**E5 — Découpe de portrait sans cache, pixel par pixel en GDScript**  
`map_data.gd` `load_token_cutout` : double boucle `get_pixel` + flood-fill. Rappelé depuis `session.gd` (liste de groupe, **chaque refresh**), `player_session_hud.gd`, `map_token_3d.gd`. Portrait Kael 1024×1536. Cause documentée de saccades (`docs/AUDIT_UI_CLARTE.md`).

**E6 — Jets secrets MJ ignorés en P2P**  
`session.gd` `_roll_dice_formula` : si P2P, envoi immédiat à l’hôte **avant** le test `chk_secret_dice`. L’hôte journalise toujours (`_host_process_dice_roll`). La case « Secret » ne marche qu’en local.

**E7 — Fiche Kael réécrite à chaque lancement**  
`_ensure_kael_character` fusionne le seed par-dessus la sauvegarde. `_apply_valbois_demo` remplace aussi le membre de groupe homonyme « Kael » (y compris un bot Kael nain du fallback session).

**E8 — `user_flow_test` cassé ; pas de CI**  
Le test cherche un `InteractiveMap` (mode simple). Valbois / cartes complexes n’en ont pas → étape `05_clic_carte_token` échoue (documenté `docs/AUDIT_CARTES.md`, README). Aucun workflow GitHub Actions. `CONTRIBUTING.md` ne demande que `npm run typecheck`. Régression UI/cartes possible sans filet.

**E9 — Portes : n’importe quel joueur**  
`PLAYER_ALLOWED_OPS` = `move_token`, `door`, `select`. Seul `move_token` vérifie `_player_owns_token`. Ouvrir une porte recalcule le fog (`recompute_dynamic_fog`) — un joueur ouvre les murs du donjon.

**E10 — Déplacement auto attribué au mauvais pion**  
`try_auto_move_from_action` sans `member_id` → `_get_active_human_member_id` (premier `isHuman`). L’hôte l’appelle ainsi pour **toutes** les actions réseau.

**E11 — Deux arbres de données + serveur de jeu fantôme**  
`data/` vs `game/data/` ; `game_session.ts` / `types.ts` / `state_serializer.ts` morts pour le runtime pooling. Risque de « corriger le serveur » sans effet en jeu, et inversement.

### Moyen

**M1 — Codes 4 chiffres + lobby public.** Énumération triviale ; `p2pHost` (IP LAN:7777) exposée.

**M2 — `ws` / `dotenv` en devDependencies.** Déploiement `omit=dev` cassé.

**M3 — Injection BBCode dans le journal.** `session.gd` `_append_log_entry_bbcode` injecte `text` brut dans `RichTextLabel`. Un joueur peut casser la mise en forme ou spoof un libellé « MJ ».

**M4 — Pas de limite de taille / débit** sur les messages pooling (`signal.payload` opaque, `register_character` non validé). Relais inter-joueurs du même salon.

**M5 — `set_p2p_host` accepte n’importe quelle chaîne.** Le MJ (ou un usurpateur C1) redirige les clients ENet vers une autre IP.

**M6 — Thème sans police.** `openquest_theme.tres` colore boutons / labels / onglets, pas `default_font`. Popups `OptionButton`, tooltips, scrolls = gris Godot (audit UI, toujours vrai).

**M7 — HUD joueur recouvre la carte.** `player_session_hud.gd` : bandeau bas `offset_top = -118`, titre sans fond. README + audit UI : boulangerie / librairie Valbois masquées.

**M8 — Onglet Enquête masqué mais toujours dans le `TabContainer`.** Contenu et scénarios `inv-demo-*` orphelins.

**M9 — Schéma JSON vs fiches réelles** (`rulesetTier`, `additionalProperties: false`).

**M10 — Docs internes contradictoires.** `STACK.md` (Godot 4.4, serveur autoritaire) vs README / MULTIPLAYER (4.7, P2P). Code d’erreur pooling : `GM_ONLY` dans le serveur, `NOT_GM` dans la doc et le test (le test accepte les deux via le message).

### Faible

**F1 — Pas de licence.**  
**F2 — `tools/` vide.**  
**F3 — `generate_id` : timestamp + `randi() % 90000`.** Collision possible sous burst.  
**F4 — Session sans partie active crée un fallback Aria/Kael** (`session.gd` `_create_fallback_game`) — piège de debug en prod.  
**F5 — `.cursor/mcp.json` chemin absolu d’une machine.**  
**F6 — CODEOWNERS mentionne `server/src/types.ts` (protocole mort).**

### Correctifs déjà en place (ne pas retravailler)

- Éditeur / visionneuse : `preload` au lieu de `class_name` globaux (`map_complex_editor.gd`).
- Caméra diorama : mesure au sol + tests `map_camera_test.gd`.
- Dédoublonnage token membre (`_dedupe_member_tokens`).
- Overlay debug jaune des zones vidé (`MapAreasOverlay`).

Non vérifié visuellement ici (pas de Godot) : cadrage Valbois entier hors HUD, qualité PNG `user://map_assets`, layout éditeur de personnages en fenêtre réelle. Le `.tscn` de l’éditeur ancre désormais `FormPanel` en plein cadre (`anchors_preset = 15`) — le bug « colonne 70 px » de l’audit UI **semble corrigé dans la scène**, à confirmer à l’exécution.

---

## 5. Sécurité (auth, confiance client, triche)

| Surface | État |
|---------|------|
| Auth pooling | Aucune. Pseudo en query `?name=` ou `register_player`. UUID = session socket. |
| Auth ENet | Aucune. Connexion à l’IP:7777 publiée. |
| TLS | `ws://` uniquement. |
| Rôle MJ | Champ JSON `role: "gm"`. |
| Dés | Tirés sur l’hôte (`randi()`), bon contre un client qui ment sur le total — **sauf** C1 (usurpation) et MJ qui triche en patchant l’hôte (modèle P2P assumé). |
| Fog / secrets | Filtre cosmétique, fuite C2. |
| Validation perso | `updateCharacter` accepte l’objet tel quel (`hp: 9999`, flags `isGm`). |
| HTTP pooling | Toute requête HTTP sur :8080 renvoie `{ status, rooms: count }` sans auth. |
| MCP / LLM | Clés API dans `.env` (gitignoré). Le MCP stdio n’écoute pas 3100 malgré `MCP_PORT` dans `.env.example`. Pas de lien avec les joueurs. |

Pour une table LAN entre personnes de confiance, C1/C2 sont de la **triche de joueur**, pas une CVE Internet. Dès que le pooling est exposé hors LAN (roadmap WebRTC / VPS dans MULTIPLAYER.md), ils deviennent bloquants.

---

## 6. Performance

- **Découpe portraits** : E5, O(largeur×hauteur) GDScript, sans cache de `ImageTexture`.
- **Refresh session** : `active_game_updated` reconstruit la liste de groupe (cutouts 64 px) ; le journal est au moins court-circuité si la longueur de log n’a pas changé.
- **Réseau** : snapshot JSON de toute la partie (log croissant + `mapPlayState`) à chaque action / jet / scène. Les `sync_map_op` sont le bon modèle, sous-utilisé.
- **3D** : un `SubViewport` par carte complexe ; tokens overlay 2D en diorama (évite le z-fight). Pas de budget d’instances documenté ; max 8 pairs ENet.
- **Sauvegarde** : JSON pretty-print à chaque entrée de log — I/O disque synchrone sur le thread principal.

Pas de profiling chiffré dans cet audit (client non lancé).

---

## 7. UX

Parcours solo MJ : menu → setup → session, clair (`docs/UI_UX.md`). Parcours joueur immersif : `PlayerSessionHud` overlay, toast = dernière ligne de log (BBCode non stripé → risque d’affichage brut).

Points encore visibles dans le code / README :

- HUD bas 118 px + titre sans plaque (M7).
- Journal MJ : correctifs session appliqués (`docs/AUDIT_UI_SESSION_MJ_APPLIED.md`) — stick-to-bottom, plus d’append manuel. Non rejoué ici.
- Thème incomplet (M6).
- Catalogue réduit à 2 démos : volontaire, mais les éditeurs Hub laissent croire à une bibliothèque plus large (scénarios custom sauvés dans `user://` puis **filtrés** si l’id n’est pas dans `DEMO_SCENARIO_IDS` — un scénario créé par le joueur **disparaît du sélecteur**).
- Multijoueur : URL pooling à saisir, code 4 chiffres, attente MJ. Pas d’Internet (ENet LAN). Message d’erreur pare-feu 7777 seulement dans la doc.
- Rôle MJ/joueur dérivé du chemin `user://` (`OpenQuest_MJ` / `OpenQuest_Player`) : pratique pour deux instances Windows, opaque pour un utilisateur Linux / Flatpak.

---

## 8. Tests

| Suite | Rôle | Statut d’après le dépôt |
|-------|------|-------------------------|
| `map_camera_test`, `map_mode_test`, `map_render_style_test`, `map_vision_test`, `map_editor_test`, `map_areas_test`, `map_props_test`, `map_night_reveal_test` | Cartes | Présentes ; caméra écrite pour verrouiller le correctif P1 |
| `quest_navigation_test`, `scenario_editor_test`, `character_editor_test` | Contenu | Présentes |
| `valbois_player_hud_test`, `valbois_screenshot_test` | Démo | Présentes |
| `scene_load_test`, `layout_verify_test`, `session_layout_check` | Scènes / layout | Présentes |
| `user_flow_test` | Parcours menu→session | **Échec connu** (carte complexe) |
| `server/scripts/test-pooling*.mjs` | Salons MJ | Manuels, serveur déjà up, pas dans npm |
| CI GitHub | — | **Absente** (templates PR/issue seulement) |

Les tests cartes sont solides sur les **données**, plus faibles sur le rendu réel (sauf caméra récemment). Rien ne couvre C1 (identité RPC), C2 (filtre réseau), ni le MJ IA. Godot headless non disponible ici : les suites n’ont pas été relancées.

---

## 9. Outillage

- Scripts Windows `play-godot*.ps1` (profils MJ / joueur, boots démo) ; `play-godot.sh` / `dev-server.sh` / `setup.sh` côté Unix.
- Génération d’assets : `scripts/generate_props_gemini.py`, `generate_map_night_gemini.py` (clés API hors dépôt).
- MCP optionnel avec OpenAI / Anthropic pour **réécrire** la narration rule-based — hors jeu.
- Pas de linter GDScript, pas de `godot --headless` dans `setup.sh`, pas de task runner unique pour les 19 scripts de test.
- `game/.godot/` gitignoré (bon) : les `class_name` restent un piège si un script oublie `preload`.

---

## 10. Maintenabilité

**Forces**

- Séparation pooling / P2P clairement commentée dans `multiplayer_manager.gd`.
- Ops de carte et `MapEditDocument` (deltas, historique) bien pensés.
- Autoloads thématiques (`ThemeColors`, `UiLayout`) — `UiLayout` encore peu utilisé.
- Tests cartes nombreux ; commentaires d’architecture dans l’éditeur 3D.

**Faiblesses**

- `game_data.gd` (3 008 lignes) est un god-object : persistance, règles, cartes, fog, dés, démo Valbois, navigation.
- Duplication MJ IA client (session + manager).
- Protocole mort (`types.ts`, `STACK.md`) à côté du protocole vivant (`lobby/types.ts`).
- Contenu dupliqué `data/` ↔ `game/data/`.
- Godot 4.7 (Forward+) : version récente, deux contributeurs, pas de CI — le coût de merge est élevé.
- Branchements de features (Enquête, WebRTC `signal`, LOS) à moitié livrés.

---

## 11. Actions recommandées (ordre)

1. **Corriger l’identité RPC (C1)** — ignorer `sender_player_id` client ; mapper `multiplayer.get_remote_sender_id()` → UUID pooling côté hôte ; refuser `request_start_game` / `gm_broadcast` sauf pair MJ. Couvrir par un test de script (même headless avec mocks).
2. **Filtrer l’état réseau (C2)** — ne plus envoyer `sync_game_state` brut aux joueurs : vue par pair via `filter_map_entry_for_player`, ou n’envoyer que des `sync_map_op` + journal déjà public. Le MJ garde l’état complet en local.
3. **Brancher ou retirer le MJ IA** — soit appeler le moteur `ai-gm` (processus local / RPC hôte), soit afficher clairement « réponses d’ambiance, pas de MJ IA ». Supprimer la copie dupliquée des 4 phrases.
4. **Réparer reconnexion (E2)** — identifiant stable (code salon + nom, ou token émis à `welcome`) ; `rejoin_room` rattache le même `playerId` et le personnage.
5. **Faire jouer les fiches (E3) ou assumer le sandbox** — au minimum : jets avec modificateur de carac, PV qui bougent, tour respecté aussi en MJ IA. Sinon retirer l’illusion de système (CA affichée, suggestions « combat »).
6. **Cache cutout + I/O (E4, E5)** — mémoïser `load_token_cutout(path, size)` ; ne pas réécrire `saved_games.json` à chaque ligne (debounce, ou journal append-only).
7. **CI minimale** — `npm run typecheck` + 4–5 tests Godot headless (`scene_load_test`, `map_camera_test`, `map_vision_test`, `quest_navigation_test`) sur PR. Réparer `user_flow_test` (mode complexe / `MapPanel`).
8. **Une seule source de contenu** — `game/data/` canonique ; `data/` généré ou supprimé ; schéma perso aligné sur `rulesetTier` ; débloquer ou supprimer Enquête.
9. **Docs** — archiver `STACK.md` ou le réécrire sur le pooling ; `ws`/`dotenv` en `dependencies` ; licence.

---

*Audit en lecture seule. Aucune modification n’a été commitée dans le dépôt du jeu.*
