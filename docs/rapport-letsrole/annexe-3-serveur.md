# Annexe 3 — Le serveur de jeu Let's Role : analyse du `gameserver` et du `starter`

> ℹ️ **Analyse brute** — document factuel (mesures, chemins, licences, pièges). Il ne constitue plus un plan de reprise de code : voir [ADAPTATION.md](ADAPTATION.md) — **aucune copie**, uniquement des idées réimplémentées pour notre jeu.

**Rapport** : quelles ressources du GitLab Let's Role sont réutilisables dans OpenQuest JDR.
**Périmètre analysé** : `.external/letsrole/gameserver` (commit `4840ce6`, 2025-06-21), `.external/letsrole/starter` (commit `f5e371b`, 2025-05-05), complétés par `.external/letsrole/front` pour le pendant client du protocole.
**Méthode** : lecture ciblée (`read` / `grep` / `glob`), comptage par script PowerShell ; aucun `npm install`, build ni test exécuté (consigne de la mission). Les chiffres sont des mesures statiques du dépôt, pas des résultats d'exécution : les « lignes » sont les lignes physiques, vides comprises.
**Date** : 2026-11-16.

### Conventions de chemins

| Alias | Chemin réel (relatif à `D:\git\OpenQuest_jdr`) |
|---|---|
| `GS/` | `.external/letsrole/gameserver/` |
| `ST/` | `.external/letsrole/starter/` |
| `FRONT/` | `.external/letsrole/front/` |
| `SHARED/` | `.external/letsrole/shared/` |
| `SRV/` | `server/` |

Toutes les citations sont de la forme `fichier:ligne` sous ces alias.

---

## 1. Résumé exécutif

Le `gameserver` de Let's Role est un serveur **WebSocket Node/TypeScript autoritaire**, mono-processus par « instance de jeu », qui porte **toute** la logique de table : salons (`table`), scènes, tokens, chat, dés, journaux, médias, musique, sons, turn-order. C'est l'exact inverse du serveur local actuel : `SRV/` ne fait que du **matchmaking + signalisation** (≈ 690 lignes), le jeu étant confié à l'hôte P2P Godot.

Le protocole est simple et **très transposable** : JSON, enveloppe `{ "c": <contrôleur>, "a": <action>, ... }`, réponses de requête via `callbackid`, notifications par diffusion ciblée (`toMe`, `toEveryone`, `toEveryoneButMe`, `toGm`…), authentification par token puis **token de reconnexion UUID**, codes de fermeture `3001–3010`.

Les vrais écarts avec `SRV/` sont ailleurs : **reconnexion**, **validation d'entrée (AJV, 184 schémas)**, **anti-spam**, **codes d'erreur normalisés**, **diffusion ciblée par rôle**, **déploiement pm2/Docker**. Ce sont ces briques — petites, autonomes, réimplémentables — qu'il faut porter, pas l'architecture complète (DI inversify, 4 bases, 209 actions, ~18 400 lignes).

| Question | Réponse courte | Preuve |
|---|---|---|
| Volume du `gameserver` | 86 fichiers `.ts`, 18 449 lignes, 18 contrôleurs concrets, 209 actions WS | §2.1 |
| Protocole | WebSocket + JSON, `{c,a}` + `callbackid`, auth par token d'URL | `GS/src/WebSocket/Message.ts:3-8`, `GS/src/WebSocketServer.ts:267-281` |
| Autorité | Serveur autoritaire : il mute son état (scènes) puis rediffuse | `GS/src/Controller/SceneController.ts:1546-1580` |
| Rooms | « tables » épinglées à une instance via `cluster_table`, expiration 180 s | `GS/src/Repository/ClusterTableRepository.ts:8-44` |
| Persistance | MariaDB (53 tables) + Cassandra + OpenSearch + Redis | `ST/init/maria.sql`, `GS/src/Infra/*` |
| Qualité | 0 test, 0 CI, `tsc` laxiste, `SceneController` de 2 860 lignes | §2.5 |
| Licence | LGPL-3.0-or-later | `GS/package.json:7`, `GS/LICENCE` |
| À porter en priorité | reconnexion, validation, anti-spam, enveloppe/diffusion, déploiement | §7 |
| À ne pas porter | code LGPL tel quel, DI inversify, pile 4 bases, monolithe de 209 actions | §6.3 |

---

## 2. Le `gameserver` : anatomie

### 2.1 Métriques (mesurées, hors `node_modules` / `dist` / `.git`)

| Module | Fichiers `.ts` | Lignes | Rôle |
|---|---:|---:|---|
| `GS/src/Controller/` | 19 | 8 557 | 18 contrôleurs concrets + classe abstraite ; 1 action = 1 méthode publique |
| `GS/src/Repository/` | 20 | 6 183 | accès MariaDB / Cassandra / OpenSearch ; caches mémoire |
| `GS/src/Entity/` | 20 | 1 942 | modèles Sequelize + classes métier (`Table`, `Client`, `Character`…) |
| `GS/src/WebSocketServer.ts` | 1 | 580 | handshake, registre des clients, diffusion, métriques pm2 |
| `GS/src/Validation/` | 1 (+184 JSON) | 55 | décorateur AJV + schémas par action (83,8 Ko) |
| `GS/src/Infra/` | 5 | 321 | Redis, Maria/Sequelize, Cassandra, Elastic |
| `GS/src/DependencyInjection/` | 2 | 177 | conteneur et symboles inversify |
| `GS/src/State/` | 3 | 179 | états volatils (`typing`, musique, sons) |
| `GS/src/Router.ts` | 1 | 115 | dispatch `c` → contrôleur → action |
| `GS/src/WebSocket/` | 4 | 88 | enveloppe `WsMessage`, anti-spam, utilisateur système |
| Divers racine (`app`, `Configuration`, `I18n`, `Log`, `Parameters`, `Error/` ×2, `Util/` ×2, `SqlServer/`) | 10 | 252 | amorçage, config JSON, i18n, erreurs, utilitaires |
| **Total** | **86** | **18 449** | |

Le module `GS/src/Dice/` est **vide** (`.gitkeep`) : la grammaire de dés est générée par `pegjs` depuis `SHARED/grammar.pegjs` (486 lignes) au moment du build (`GS/package.json:53-58`), et `GS/.gitignore:12` exclut le fichier généré. Conséquence : le clone ne compile pas tel quel (voir §2.6).

Aucun fichier `*.test.ts` / `*.spec.ts`, aucun `.gitlab-ci.yml` dans le `gameserver` : **0 test, 0 CI** (vérifié par énumération récursive). Le `front`, lui, a un `.gitlab-ci.yml` (build + test) et un test Jest (`FRONT/tests/Engine/Board/DynamicLighting/VisibilityPolygon.test.ts`) ; `ST/CONTRIBUTE.md:34` reconnaît d'ailleurs que l'« Automated Testing » est un chantier ouvert.

### 2.2 Points d'entrée et démarrage

- `GS/src/app.ts:1-5` : 4 lignes. Il résout simplement `WebSocketServer` dans le conteneur inversify ; le constructeur du serveur fait tout le reste (`GS/src/WebSocketServer.ts:45-83`).
- Port : `process.env.PORT` (`GS/src/WebSocketServer.ts:56`), fixé à `7500` par `GS/ecosystem.config.js:24` et `ST/docker-compose.yml:30,40`.
- Le serveur instancie `new WebSocket.Server({ port })` **sans** serveur HTTP attaché (`GS/src/WebSocketServer.ts:58-60`) : pas de route HTTP healthcheck, pas de `wss://` dans le code applicatif (le TLS est déporté sur nginx, `ST/init/nginx.conf`).
- Configuration : JSON lu au premier `get()` (`GS/src/Configuration.ts:18-34`), `./etc/config.json` en production, `./etc/config.dev.json` en développement (`GS/src/Configuration.ts:23-27`). **`GS/etc/config.json` est absent et volontairement gitignoré** (`GS/.gitignore:9`) : la config de production n'est pas livrée, seules les valeurs de dev le sont (`GS/etc/config.dev.json:1-48`).
- `GS/ecosystem.config.js` : 1 seule instance, `max_memory_restart: 3200M`, `--max-old-space-size=3072`, redémarrage cron quotidien à 09:00, logs dans `./var/` (lignes 12-28).
- `GS/Dockerfile` : 10 lignes, `FROM node:lts`, `npm install`, `COPY . .` — **ni `CMD` ni `EXPOSE`** : la commande vient de `ST/docker-compose.yml:24` (`npm run start`).
- i18n maison : `GS/src/I18n.ts:31-71`, fichiers `GS/etc/locales/{de,en,es,fr,it,pt}.json`, locale **fournie par le token** (`client.locale`, `GS/src/WebSocketServer.ts:340`) — utile à noter pour un projet francophone : le serveur parle la langue du joueur.

### 2.3 Persistance et modèle de données

Quatre magasins, chacun avec un rôle distinct :

| Magasin | Usage observé | Preuve |
|---|---|---|
| MariaDB via Sequelize + knex | source de vérité relationnelle : 53 tables créées par `ST/init/maria.sql` ; `game_table`, `cluster_table`, `character`, `system`… | `GS/src/Infra/SqlServer.ts:7-21`, `GS/src/Entity/Table.ts:158-198` |
| Cassandra | journal/événements à gros volume (`ST/init/cassandra.cql`, 5 `CREATE`) | `GS/src/Infra/Cassandra.ts` |
| OpenSearch | 10 index de recherche (`letsrole_table`, `letsrole_character`, `letsrole_media`, `letsrole_journal`…) | `GS/src/Infra/ElasticType.ts:1-12` |
| Redis | *pub/sub* inter-instances + lecture du token de session (`user_token_<token>`) | `GS/src/Infra/Redis.ts:40-56,87-101` |

Détail important pour nous : **l'état de jeu chaud est en mémoire**, la base n'est qu'un filet de sécurité. `SceneRepository` garde un cache `Map<number, Scene>` et **sauvegarde en masse toutes les 30 s** (`GS/src/Repository/SceneRepository.ts:27-41`) ; chaque mutation appelle `saveData(scene)` puis la boucle périodique écrit. Ce « write-behind » est un pattern réutilisable même sans base : chez nous, il remplacerait avantageusement une écriture disque à chaque mouvement de token.

### 2.4 Autorité, permissions, erreurs

- **Rôles** : `player`, `gm`, `observer`, `builder` (`SHARED/User.ts:15-20`). `Client.isGm()` considère `gm` **et** `builder` comme MJ (`GS/src/Entity/Client.ts:66-72`) ; 55 appels `isGm()` dans les contrôleurs servent de garde (`Select-String` sur `GS/src/Controller/*.ts`).
- **Autorité serveur** : le serveur applique la mutation sur *sa* copie puis diffuse l'état résultant. Exemple canonique, `moveItem` : lecture de la scène, écriture `item.x = x`, `toEveryoneButMe(...)`, `saveData` (`GS/src/Controller/SceneController.ts:1546-1580`). Le client n'est jamais cru sur l'état final : il propose un delta, le serveur l'applique.
- **Autorité des dés** : l'expression est parsée **côté serveur** par la grammaire pegjs avec un RNG injecté (`GS/src/Controller/DiceController.ts:111-127`) ; le client ne reçoit que le résultat (`GS/src/Controller/DiceController.ts:129-166`). Il y a même un `dice/random` (mélange de deck) résolu côté serveur (`GS/src/Controller/DiceController.ts:33-62`).
- **Erreurs** : `UserError` (message destiné au joueur) est interceptée par `Router.onError` et **réinjectée dans le chat** sous forme de faux message système (`from: "error"`), `GS/src/Router.ts:97-110`. `AccessDeniedError` est déclarée et gérée (`GS/src/Router.ts:103`) mais **jamais levée** dans le code actuel : dette à ignorer.
- **Codes de fermeture** : `SHARED/ErrorCode.ts:1-20` — `3001 InitClosed` … `3010 ReconnectTokenAuth`, plus `4505-4508` pour les uploads. Très bon modèle à copier : un client Godot peut afficher un message précis selon le code reçu.

### 2.5 Qualité et dette technique

Points forts : séparation contrôleur / repository / entité, schémas JSON *contract-first* par action (184 fichiers, 83,8 Ko), i18n, constante de temps centralisée (`SqlServer.now()` en secondes epoch, `GS/src/Infra/SqlServer.ts:42-44`), logs pm2.

Points faibles (tous vérifiés) :

| Constat | Preuve |
|---|---|
| `tsc` laxiste : `strictNullChecks: false`, `noImplicitAny: false`, `suppressExcessPropertyErrors`, `suppressImplicitAnyIndexErrors` | `GS/tsconfig.json:9-14` |
| Monolithe : `SceneController.ts` = 2 860 lignes / 63 actions | §2.1 |
| DI partiellement périmée : symboles `Encyclopedia*` enregistrés mais fichiers inexistants | `GS/src/DependencyInjection/Services.ts:24-25` |
| Script mort : `cluster:serve` pointe `dist/src/cluster.js`, or `src/cluster.ts` n'existe pas | `GS/package.json:56` |
| Curiosités de `package.json` : `node` et `npm` déclarés en `dependencies` | `GS/package.json:22-24` |
| Aucune validation de schéma sur certaines actions (seules celles décorées `@Validator` le sont) | `GS/src/Validation/Validator.ts:21-55` |

### 2.6 Le clone est incomplet pour compiler (à savoir avant tout essai)

`GS/.gitignore:4` exclut `shared`, et `GS/tsconfig.json:22` mappe `shared/*`. **Il n'y a pas de dossier `GS/shared/`** : les imports `../../shared/...` (ex. `GS/src/WebSocketServer.ts:22,29`) ne se résolvent pas. `ST/docker-compose.yml:27` monte `./../shared` dans `/usr/app/shared`, et `ST/INSTALL.md:24-29` demande de copier le dossier `shared` dans `front/` et `gameserver/`. Dans notre clone, `SHARED/` existe à côté, mais il faut le copier/li­er pour compiler, puis lancer `npm run compile` (pegjs) — deux opérations que la mission interdisait. **Ne pas conclure « ça ne compile pas » : c'est un clone volontairement amputé de ses artefacts générés.**

---

## 3. Protocole réseau détaillé

### 3.1 Enveloppe, transport, handshake

- Transport : WebSocket texte, **JSON uniquement** (`JSON.stringify` / `JSON.parse`, aucun binaire, aucun MessagePack) — `GS/src/WebSocketServer.ts:161-168,480-493`.
- Enveloppe : `{ c: string, a: string, client: Client, [extra: string]: any }` (`GS/src/WebSocket/Message.ts:3-8`). Le champ `client` est **injecté par le serveur**, jamais accepté du client.
- Requête/réponse : ajout de `callbackid` (UUID v4 côté client, `FRONT/src/Client/WebSocketClient.ts:40-59`), réponse renvoyée avec le même `callbackid` (`GS/src/WebSocketServer.ts:256-265`).
- Connexion : l'URL porte le token. `ws://host:7500/?token=<token>` pour une première connexion (`GS/src/WebSocketServer.ts:307-311,267-281`), `ws://host:7500/?reconnect=<uuid>` pour une reprise (`GS/src/WebSocketServer.ts:391-409,283-299`).
- Séquence d'amorçage (5 étapes, `GS/src/WebSocketServer.ts:322-389`) : token Redis → `User.findByPk` → vérification du rôle vs `game_table` → chargement de la `table` → chargement du `system` → `onJoin` → `initClient`.
- Le serveur répond toujours en premier par `user/auth` contenant `{ initialized, reconnectToken, isReconnect }` (`GS/src/WebSocketServer.ts:507-511`). Le client stocke le token et envoie ensuite `client/init` ou `client/reconnect` (`FRONT/src/Controller/UserController.ts:23-32`).

### 3.2 Catalogue des messages

**Sens client → serveur** = « actions » publiques des contrôleurs ; **sens serveur → client** = appels `toMe` / `toEveryone` / `toEveryoneButMe` / `toGm` / `callback`. Chaque contrôleur déclare son nom (`public readonly Name`) qui sert de `c`.

| `c` | Actions entrantes (nombre) | Événements sortants principaux |
|---|---|---|
| `client` (4) | `ping`, `init`, `reconnect`, `exit` | `user/pong`, `user/initialized` |
| `user` (2) | `everyone`, `load` | — |
| `chat` (8) | `whoIsTyping`, `clearTyping`, `typing`, `clear`, `xcard`, `history`, `gm`, `all` | `chat/typing`, `chat/clear`, `chat/say`, `chat/xcard`, `chat/load` |
| `dice` (3) | `random`, `clear`, `roll` | `dice/roll`, `dice/clear`, `dice/load`, `dice/history` |
| `scene` (63) | `create`, `load`, `display`, `addItem`, `moveItem`, `transformItem`, `deleteItem`, `addToken`, `addWall`, `addDoor`, `addLight`, `updateFog`, `updateGrid`, `giveControl`… | `scene/display`, `scene/addItem`, `scene/moveItem`, `scene/deleteItem`, `scene/updateFog`, `scene/lockDoors` |
| `character` (7) | `load`, `all`, `persist`, `multiPersist`, `skin`, `kick`, `updateAvatar` | `character/all`, `character/join`, `character/leave`, `character/updated`, `character/me` |
| `turn-order` (10) | `next`, `sort`, `load`, `add`, `remove`, `setValue`… | `turn-order/update`, `turn-order/updateItem` |
| `journal` (23), `media` (16), `craft` (12), `book` (4), `pdf` (4) | CRUD de contenus | `journal/show`, `journal/refresh`, `craft/reload`… |
| `music` (18), `sound` (21), `drawing` (8), `ruler` (2), `quickbar` (3), `ping` (1) | lecture/multijoueur d'ambiance | `music/play`, `music/pause`, `sound/play`, `drawing/addItem`, `ruler/share`, `ping/ping` |
| **Total** | **209 actions** (dont 63 pour `scene`) | |

Payloads représentatifs, à comparer aux nôtres :

- Ping de carte : entrant `{c:"ping",a:"ping",position,color}`, sortant `{c:"ping",a:"ping",position,user,color}` (`GS/src/Controller/PingController.ts:12-20`).
- Jet de dé : entrant `{c:"dice",a:"roll",expression,rollId,title,cid,visibility,icon}` avec `callbackid` ; sortant `{rollId,dice,title,visibility,formula,diceSkinId,icon,user}` (`GS/src/Controller/DiceController.ts:81-166`, schéma `GS/src/Validation/dice/roll.json:1-44`).
- Chat : `{c:"chat",a:"all",message,bindings,toId?,me?}` → `{c:"chat",a:"say",from,fromId,message,bindings,character,me}` ; message tronqué à 1 024 caractères (`GS/src/Controller/ChatController.ts:148-189`).
- Historique : `chat/history` ne renvoie que les 20 derniers messages privés (`GS/src/Controller/ChatController.ts:119-130`) ; à l'init, 35 messages publics (`GS/src/Controller/ClientController.ts:123-129`).
- Mouvement de token : `{c:"scene",a:"moveItem",sceneId,key,x,y,layer}` → rediffusé aux autres + `saveData` (`GS/src/Controller/SceneController.ts:1546-1580`).

### 3.3 Cycle de vie des « rooms » (tables)

- Une *table* = un salon persistant identifié par `game_table.id` (`GS/src/Entity/Table.ts:158-198`). Les clients connectés sont tenus dans **deux registres statiques** : `Map<tableId, Client[]>` et `Map<reconnectToken, Client>` (`GS/src/WebSocketServer.ts:39-43`), avec ajout/retrait en `514-556`.
- Une table est **épinglée à une instance** (un process nommé `quetzalcoatl`, `GS/etc/config.dev.json:3`) via la table SQL `cluster_table` : `incrementUsers`/`decrementUsers` à l'entrée/sortie, `ping` toutes les 30 s (`GS/src/WebSocketServer.ts:117-133`), et détachement des tables **vides et sans ping depuis 180 s** (`GS/src/Repository/ClusterTableRepository.ts:8-44`, boucle `cleanTables` toutes les 120 s, `GS/src/WebSocketServer.ts:122-150`). Au démarrage, l'instance purge ses propres tables (`GS/src/WebSocketServer.ts:113-115`).
- Diffusion : `toTable` itère `getClients(tableId)` (`GS/src/WebSocketServer.ts:180-199`) ; `toGmAtTable` filtre sur `client.isGm()` (`GS/src/WebSocketServer.ts:201-222`). Toute socket non `OPEN` est `terminate()` avant envoi — pas de file d'attente par client.
- Le « burst » d'initialisation est **une seule action** qui envoie ~20 messages (user/me, table/load, chat/load, character/all, dice/load, dice/history, book/init, quickbar/load, scene/display, turn-order/update, music/init…) : `GS/src/Controller/ClientController.ts:48-255`. Utile comme *checklist* de ce qu'un client doit savoir reconstruire.

### 3.4 Reconnexion

C'est la brique la plus intéressante pour nous. Le **principe** est complet ; l'implémentation du snapshot OSS, elle, a une faille précise à connaître (point 7) :

1. À chaque connexion, le serveur génère `reconnectToken = crypto.randomUUID()` et l'indexe (`GS/src/Entity/Client.ts:33-43`), puis l'envoie dans `user/auth`.
2. Le client mémorise le token (`FRONT/src/Controller/UserController.ts:24-25`).
3. En cas de coupure, le client rouvre une socket avec `?reconnect=<token>` (`FRONT/src/Client/WebSocketClient.ts:89-109`) ; le serveur retrouve **l'objet `Client` existant** (pas un nouveau), remplace juste `client.socket` et relance `initClient(client, true)` (`GS/src/WebSocketServer.ts:391-409`). Aucun état de jeu à rejouer côté serveur : il est déjà en mémoire.
4. Le client envoie `client/reconnect` au lieu de `client/init` (`FRONT/src/Controller/UserController.ts:27-31`) ; le serveur renvoie le strict minimum (scène + `user/initialized`, `GS/src/Controller/ClientController.ts:36-46`).
5. Garde-fous côté client : timeout de connexion 10 s, ping toutes les 12 s, reconnexion si pas de `pong` en 5 s, rechargement de page si la reprise échoue en 3 s (`FRONT/src/Client/WebSocketClient.ts:15-19,209-224`). À noter : **la file de messages hors-ligne est commentée** (`FRONT/src/Client/WebSocketClient.ts:157-166`) — les messages émis pendant la coupure sont perdus.
6. À la déconnexion propre, `client/exit` diffuse `character/leave` + un message système « X a quitté la table », retire le client de la table et supprime le token de reconnexion (`GS/src/Controller/ClientController.ts:257-286`, puis `GS/src/WebSocketServer.ts:541-556`).
7. **Défaut vérifié** : le drapeau `Client.isReconnecting` est déclaré (`GS/src/Entity/Client.ts:18`) et lu (`GS/src/WebSocketServer.ts:496`) mais **n'est jamais mis à `true`** dans le `gameserver` (grep exhaustif : 2 occurrences, aucune affectation). Conséquence : à chaque fermeture de socket, `client/exit` est dispatché, la table perd le client et le token est effacé avant que `?reconnect` ne puisse aboutir — la reprise n'est fiable que si la nouvelle socket arrive avant le traitement du `close` de l'ancienne. **C'est un principe à réimplémenter proprement (TTL de session explicite + `exit` différé), pas une implémentation à copier.**

### 3.5 Validation, anti-spam, sérialisation

- Validation : décorateur `@Validator(schemaJson)` qui compile le schéma AJV **au chargement du module** et rejette silencieusement (log) un message invalide (`GS/src/Validation/Validator.ts:10-55`). `removeAdditional: true` supprime les champs non déclarés — un client ne peut pas injecter d'état arbitraire dans les objets validés (ligne 11).
- Anti-spam : fenêtre glissante par clé `c:a:userId`, `iterations`/`duration` par action ; au-delà de 2× le seuil, la socket est fermée (`GS/src/WebSocket/SpamProtector.ts:23-65`, `GS/src/Controller/Controller.ts:34-55`). Exemples de seuils : `scene/moveItem` = 60 en 1 s (`GS/src/Controller/SceneController.ts:1548`), `chat/all` = 10 en 6 s (`GS/src/Controller/ChatController.ts:150`), `dice/roll` = 5 en 5 s (`GS/src/Controller/DiceController.ts:83`).
- Troncature/limites : message de chat ≤ 1 024 caractères (`GS/src/Controller/ChatController.ts:161-163`), expression de dé ≤ 255 (`GS/src/Validation/dice/roll.json:7-10`), `rollId` 8–32 caractères.

### 3.6 Réutilisation dans OpenQuest — ce qui est transposable à un client Godot (GDScript)

| Élément | Transposition | Effort |
|---|---|---|
| Enveloppe `{c,a}` | dictionnaire JSON unique + `match msg.get("a")` après dispatch par `c` ; miroir direct de l'existant `MultiplayerManager` | S |
| `callbackid` | `request_id` généré en GDScript, table `id → Callable`, purge sur timeout | S |
| `user/auth` + `reconnectToken` | remplacer `rejoin_room` (qui ne restaure rien) par un vrai token de session | M |
| Codes de fermeture `3001-3010` | `WebSocketPeer.close_code` → écran d'erreur explicite | S |
| Diffusions ciblées (`toMe`/`toGm`) | garde applicative côté serveur : ne pas envoyer à tous puis filtrer côté client (fuite d'info MJ) | S |
| `Validator` AJV | schémas **zod** (déjà présent, `SRV/package.json:19`) côté serveur, validation légère côté client | S |
| `SpamProtector` | ~50 lignes à réécrire, aucun couplage | S |
| Mouvement autoritaire (`moveItem`) | chez nous, l'hôte Godot doit appliquer puis relayer (pas de serveur autoritaire) ; garder la forme « delta + état résultant » | M |

---

## 4. Comparaison avec `server/` et plan de portage

### 4.1 Ce que fait le serveur local (mesuré)

`SRV/` : 21 fichiers `.ts` (3 546 lignes au total, dont 2 648 hors chemins MJ IA / MCP / narration), et le cœur réseau réellement déployé ne pèse que **687 lignes** : `pooling/server.ts` (371) + `lobby/rooms.ts` (230) + `lobby/types.ts` (86). Dépendances runtime : `@modelcontextprotocol/sdk` et `zod` uniquement (`SRV/package.json:17-20`), `ws` et `dotenv` étant déclarés en `devDependencies` (`SRV/package.json:21-27`) **alors que `ws` est importé au runtime** (`SRV/src/pooling/server.ts:7`) — à corriger sous peine de panne en déploiement `npm ci --omit=dev`.

Le protocole local est plat et discriminé par `type` (pas d'enveloppe `c`/`a`) : 12 types client→serveur et 10 types serveur→client (`SRV/src/lobby/types.ts:36-77`), diffués par `send` (`SRV/src/pooling/server.ts:50-54`), avec diffusion lobby (`60-71`), diffusion room (`73-85`), relais `signal` (`277-290`). Salons en RAM (`Map` dans `RoomManager`, `SRV/src/lobby/rooms.ts:27`), code à 4 chiffres (`29-37`), fermeture si le MJ part (`109-143`), `set_p2p_host` réservé au MJ (`153-163`).

### 4.2 Tableau de comparaison

| Sujet | Let's Role (`GS/`) | OpenQuest (`SRV/`) | Écart | À porter | Effort |
|---|---|---|---|---|---|
| Enveloppe message | `{c,a,callbackid?}` typée | `{type,...}` à plat, union TypeScript | convention différente, pas d'ID de requête | oui : `{c,a}` ou au minimum `callbackid`/`request_id` | M |
| Identité | token en query, Redis, rôle vérifié en base | UUID généré à la connexion, `?name=` optionnel | aucune authentification | oui (token de session, pas forcément Redis) | M |
| Reconnexion | token UUID + reprise de l'objet `Client` | `rejoin_room` = re-join, **aucun état restauré** | fonction manquante | **oui, priorité 1** | S–M |
| Validation d'entrée | AJV, 184 schémas, `removeAdditional` | `JSON.parse` + `switch`, aucune validation | risque d'erreur/injection | oui, via `zod` | S |
| Anti-spam | fenêtre par action, fermeture socket | absent | DoS trivial | oui | S |
| Codes d'erreur | enum 3001-3010 + `error.code` | chaînes (`GM_ONLY`, `JOIN_FAILED`) | pas de contrat stable | oui, enum partagé | S |
| Rooms | tables persistantes + épinglage instance + expiration 180 s | salons volatils en RAM | voulu pour un déploiement mono-processus | non (sauf TTL de session) | L |
| Autorité de jeu | serveur autoritaire (scènes, dés) | aucune logique de jeu ; autorité = hôte P2P Godot | architectural, assumé | non (mais patterns de delta) | L |
| Persistance | MariaDB + Cassandra + OpenSearch | dossiers `data/sessions` (JSON, hors WS) | hors périmètre WS | non | L |
| Diffusion ciblée | `toMe`, `toEveryone`, `toGm`, `toTable` | `send` + boucles ad hoc | duplication de code | oui : 4 helpers nommés | S |
| Chat | messages + privé + typage + historique + troncature | absent du WS (géré côté Godot) | non prioritaire | plus tard | M |
| Dés | expression parsée serveur, visibilité MJ/joueur | `SRV/src/dice.ts` existe mais **n'est pas branché** sur le WS | deux moteurs séparés | décider : dés côté hôte Godot | M |
| Déploiement | pm2 + Docker + nginx + logs `var/` | `npm run dev` / `node dist`, rien d'autre | pas prêt pour un VPS | oui : `Dockerfile` + healthcheck | S |
| Observabilité | métriques pm2 (`userCountMetric`, `tableCountMetric`) | `console.log` | minimal | oui (compteurs + `/health`) | S |
| Tests | 0 | 2 scripts `scripts/test-pooling*.mjs` (bout-en-bout, hors `npm test`) | aucun cadre | oui, cadre minimal **côté local** | M |

### 4.3 Plan de portage réaliste (4 lots, sans réécriture)

1. **Lot A — robustesse du protocole existant** (≈ 1 j) : ajouter `zod` aux frontières (`SRV/src/pooling/server.ts:137-145`), un `ErrorCode` partagé (`SRV/src/lobby/types.ts:57-77`), un anti-spam calqué sur `GS/src/WebSocket/SpamProtector.ts`, et 4 helpers de diffusion nommés à la place des boucles de `handleMessage`. Cible : `SRV/src/pooling/server.ts`, `SRV/src/lobby/types.ts`.
2. **Lot B — sessions/reconnexion** (≈ 1–2 j) : remplacer `rejoin_room` par un vrai `resume_token` remis au `welcome` (modèle : `user/auth` + `Client.reconnectToken`), TTL sur les salons vides, gestion `close` idempotente (`SRV/src/lobby/rooms.ts:109-143`). Cible : `SRV/src/lobby/rooms.ts`, `SRV/src/pooling/server.ts`.
3. **Lot C — passage à l'échelle/côté jeu si besoin** : *seulement si* on quitte le tout-P2P. Sinon, porter les patterns, pas l'architecture (pas d'inversify, pas de 4 bases, pas de 209 actions).
4. **Lot D — déploiement** (≈ 0,5 j) : `SRV/Dockerfile` multi-stage (build TS → runtime), `ecosystem.config.js` pm2 (mémoire max, logs), config JSON versionnée à la place de `.env` pour les valeurs non secrètes, endpoint HTTP `/health` (déjà un handler HTTP minimal, `SRV/src/pooling/server.ts:307-317`).

**Effort total réaliste** : 2 à 4 jours pour les lots A + B + D, sans traiter C. Aucun besoin de copier du code Let's Role : toutes les briques listées sont < 100 lignes et se réimplémentent proprement.

---

## 5. `starter` : intérêt pour le développement et le déploiement

`ST/` ne contient **aucun code applicatif** : 7 entrées à la racine (`docker-compose.yml` 3 157 o, `INSTALL.md`, `CONTRIBUTE.md`, `README.md`, `LICENCE`, `.gitignore`, `.git/`) + le dossier `init/`. C'est un *mode d'emploi de déploiement*, et c'est là sa valeur pour nous.

- **`ST/docker-compose.yml`** décrit l'empilement complet : 8 services — `letsrolewebsite` :8080, `letsrolegameserver` :7500 (volume `./../gameserver` + `./../shared` monté en `/usr/app/shared`, ligne 27), `letsrolemaria` :3307, `letsrolecassandra` :9042 + job `cassandra-load-keyspace` (sleep 180 avant `cqlsh`, ligne 76), `letsroleopensearch` :9200/9600, `letsroleredis` :6379, `letsrolenginx` :80. Les volumes nommés (`data-maria`, `data-cassandra`, …) sont en lignes 124-128. **Ici, rien à réutiliser tel quel** (4 datastores pour un projet solo = surdimensionné), mais la *forme* est bonne : un service applicatif, un reverse-proxy, des volumes de logs.
- **`ST/init/`** : `maria.sql` (3 113 lignes, 53 tables), `cassandra.cql` (76 lignes), `nginx.conf` (34 lignes, proxy WebSocket). C'est une **documentation implicite du modèle de données** de Let's Role : utile à lire, pas à importer.
- **`ST/INSTALL.md`** : prérequis (Docker, Node LTS, **16 Go de RAM recommandés**, lignes 7-11) ; il faut cloner 5 dépôts et **recopier `shared` dans `front/` et `gameserver/`** (24-29) ; `/etc/hosts` à modifier (31-35) ; **Windows : « Help welcome! »** (68-69) — donc pas de procédure Windows officielle. Pour un projet francophone sur Windows, cela confirme qu'il ne faut pas s'appuyer sur ce starter.
- **`ST/CONTRIBUTE.md`** : attendus de qualité (« clean, typed code », « minimal comments », Prettier), niveaux de difficulté, et aveu explicite que les tests automatisés manquent (ligne 34). Utile comme **gabarit de conventions** si on veut aligner la qualité de `SRV/`.
- **`ST/README.md:5`** : formulation officielle des obligations LGPL (« you must publicly release any changes made, with the same licence ») — voir §6. Limites connues : font awesome pro absent (icônes manquantes) et uploads vidéo probablement HS (README:29-31), c'est-à-dire **des assets non libres dans l'écosystème Let's Role** : ne jamais copier les assets.

---

## 6. Licence LGPL v3 : ce qu'on peut faire, ce qu'on doit publier

### 6.1 Faits

- `GS/package.json:7` : `"license": "LGPL-3.0-or-later"` ; `GS/LICENCE` est le texte de la **GNU LGPL v3** (7 817 octets). `ST/README.md:5` et `ST/LICENCE` confirment le périmètre « code » de l'open source partiel (2025).
- Les deux dépôts sont des clones Git à historique complet ; **aucun CLA** n'apparaît dans le clone, les contributions se font sous la même licence (`ST/CONTRIBUTE.md`).
- `SHARED/` est aussi sous LGPL v3 (`SHARED/LICENCE`, même taille).

### 6.2 Obligations concrètes selon l'usage

| Usage envisagé | Statut | Obligation |
|---|---|---|
| Lire le code pour en comprendre les patterns | autorisé | aucune (lecture) |
| Réimplémenter le protocole dans `SRV/` et dans Godot | autorisé | aucune : une idée, un format de message, un nom d'événement ne sont pas des œuvres protégeables ; un client qui parle à un serveur par socket n'est pas un « work based on the Library » |
| Copier/coller un fichier du `gameserver` (ou l'adapter) dans `SRV/` | dérivé | le fichier devient sous LGPL v3 : conserver l'en-tête/notice, **publier les sources modifiées sous LGPL v3**, permettre la reliaison |
| Distribuer un binaire compilé contenant du code Let's Role | dérivé | fournir les sources correspondantes (offre écrite ou accompagnement) |
| Usage strictement privé, non distribué | dérivé non distribué | pas d'obligation de publication (LGPL n'impose que sur distribution) ; garder la trace de l'origine |

### 6.3 Recommandation pour OpenQuest

Le projet est solo, francophone, et vise un serveur de pooling léger : **ne pas importer de code du `gameserver`**. Toutes les briques intéressantes (§3.6) représentent moins de 300 lignes cumulées et se réécrivent sans risque juridique. Si une réutilisation de code devenait nécessaire, placer les fichiers copiés dans un dossier `SRV/third_party/letsrole/` avec un `NOTICE` (origine, commit, licence) et le lien de publication des modifications — plus simple à assumer qu'une contamination diffuse de `SRV/src`.

Attention également aux **assets** (icônes, dés, skins, polices) : l'open source ne couvre que le code ; `ST/README.md:29-31` documente déjà des dépendances non libres côté front.

---

## 7. Top 5 priorisé (effort S < 1 j, M 1–3 j, L > 3 j)

| # | À récupérer | Pourquoi | Source de référence | Cible | Effort |
|---|---|---|---|---|---|
| 1 | **Reconnexion par token** (`user/auth` + `reconnectToken` + reprise de la session) — le *principe*, pas le code (cf. §3.4 point 7) | le point faible actuel : `rejoin_room` ne restaure aucun état ; grande amélioration perçue par les joueurs | `GS/src/WebSocketServer.ts:391-409,507-511` ; `GS/src/Entity/Client.ts:33-43` ; `FRONT/src/Client/WebSocketClient.ts:89-109` | `SRV/src/lobby/rooms.ts`, `SRV/src/pooling/server.ts`, `game/scripts/multiplayer/multiplayer_manager.gd` | S–M |
| 2 | **Validation d'entrée + codes d'erreur** (zod + enum partagé + message d'erreur structuré) | protège un serveur aujourd'hui exposé (`JSON.parse` puis `switch` sans contrôle) | `GS/src/Validation/Validator.ts:10-55` ; `SHARED/ErrorCode.ts:1-20` | `SRV/src/lobby/types.ts`, `SRV/src/pooling/server.ts` | S |
| 3 | **Anti-spam / rate-limit par socket et par action** | ~50 lignes, empêche le spam de `signal`/`ping` et le DoS trivial | `GS/src/WebSocket/SpamProtector.ts:23-65` ; seuils `GS/src/Controller/Controller.ts:34-55` | nouveau `SRV/src/pooling/rate_limit.ts` | S |
| 4 | **Diffusion ciblée nommée + `callbackid`** (`toMe`/`toEveryone`/`toGm`/`toTable`, requête→réponse corrélée) | supprime les boucles dupliquées ; indispensable dès qu'on ajoutera du jeu côté serveur | `GS/src/WebSocketServer.ts:152-265` | `SRV/src/pooling/server.ts` | M |
| 5 | **Packaging/déploiement** (`Dockerfile` multi-stage, `ecosystem.config.js`, config JSON, `/health`, logs) | le serveur n'a aujourd'hui que `npm run dev`/`node dist` ; condition d'un VPS à 512 Mo | `GS/Dockerfile:1-10` ; `GS/ecosystem.config.js:1-31` ; `GS/src/Configuration.ts:18-34` | `SRV/Dockerfile`, `SRV/ecosystem.config.js` | S |

**Hors top 5 volontairement** : autorité serveur du jeu (§4.2), pile de persistance 4 bases, chat/journaux/médias/sons, grammaire de dés pegjs (le portage en GDScript est coûteux et le moteur de dés local existe déjà, `SRV/src/dice.ts`).

---

## 8. Limites de cette analyse (à ne pas surinterpréter)

- Aucun build, test ni exécution : tout est statique. Les performances, les fuites mémoire et le comportement réseau réel du `gameserver` n'ont pas été observés.
- Le clone du `gameserver` est **incomplet** : `GS/shared/` absent, `GS/src/Dice/grammar.ts` non généré, `GS/etc/config.json` absent (§2.6). Impossible donc d'affirmer que le serveur compile ou démarre en l'état.
- Le protocole exact des **messages de jeu** dépend de `SHARED/Scene/SceneData.ts`, `SHARED/DiceResult.ts`, etc. : ces types ne sont que partiellement détaillés ici ; voir l'annexe 1 (`shared`, `js-engine`) et l'annexe 2 (`front`).
- Les payloads listés au §3.2 sont ceux des actions les plus structurantes ; les 209 actions ne sont pas toutes décrites exhaustivement. La liste complète s'obtient par `grep -n 'public async' GS/src/Controller/*.ts`.
- Le nombre de 209 inclut les méthodes publiques prenant un `WsMessage`/`WsCallbackMessage` ; quelques méthodes internes nommées de la même façon pourraient gonfler le compte de ±1.
