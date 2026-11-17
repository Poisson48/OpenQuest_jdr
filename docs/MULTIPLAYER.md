# Multijoueur OpenQuest JDR — Architecture P2P + Pooling

> Document de référence pour le multijoueur OpenQuest.  
> Dernière mise à jour : 2026-11-17 — protocole v2 (contrat testé, voir §3.3),
> phase 5.4 du refactor.  
> Voir aussi la feuille de route cartes interactives : [INTERACTIVE_MAPS_STRATEGY.md](./INTERACTIVE_MAPS_STRATEGY.md).

---

## 1. Vue d'ensemble

OpenQuest passe d'un **serveur autoritaire Node** (tout le jeu transite par le PC hôte) à un modèle **P2P + serveur de pooling** :

```
┌─────────────┐     WebSocket      ┌──────────────────┐     WebSocket      ┌─────────────┐
│  Joueur 1   │◄──────────────────►│ Serveur pooling  │◄──────────────────►│  Joueur 2   │
│  (Hôte P2P) │  matchmaking+ICE   │  (Node, :8080)   │  matchmaking+ICE   │  (Client)   │
└──────┬──────┘                    └──────────────────┘                    └──────┬──────┘
       │                                                                            │
       └────────── WebRTC DataChannel (STUN / TURN optionnel) ─────────────────────┘
                              État de jeu, actions, dés
         (repli LAN : ENet :7777 si p2p_transport=enet / force_loopback)
```

| Composant | Rôle |
|-----------|------|
| **Serveur pooling** | Matchmaking, salons à code 4 chiffres, signalisation WebRTC (phase 2), aucune logique de jeu |
| **Hôte P2P (Godot ENet)** | PC du **MJ** : autorité locale, sync actions/dés entre pairs |
| **Client Godot** | Connexion pooling → rejoindre salon par code → connexion ENet vers le MJ |

### Règles MJ (Maître du Jeu)

| Règle | Détail |
|-------|--------|
| **Création** | Seul le MJ peut créer une partie (`create_room` avec `role: "gm"`) |
| **Rejoindre** | Les joueurs rejoignent uniquement via le code à 4 chiffres |
| **Hôte P2P** | Le MJ = hôte ENet par défaut (pooling + port 7777 sur son PC) |
| **Départ MJ** | Si le MJ quitte ou se déconnecte → salon **fermé** pour tous (`room_closed`) |
| **Départ joueur** | Les autres joueurs reçoivent `player_left`, le salon continue |
| **Reconnexion joueur** | Un joueur déconnecté peut rejoindre à nouveau via `rejoin_room` / `join_room` avec le même code |

### Démarrage serveur

```powershell
cd server && npm run dev
```

Le serveur pooling écoute sur le port **8080** (matchmaking uniquement).

---

## 2. Phases de développement

### Phase 0 — Fondations LAN (✅ pooling)
- WebSocket JSON sur port 8080
- Lobby global, `register_character`, sync actions/dés
- Connexion LAN par IP (`ws://192.168.x.x:8080`)

### Phase 1 — Pooling v1 (✅ `server/pooling-v1`)
- Salons à code 4 chiffres (`create_room`, `join_room`, `leave_room`, `list_rooms`)
- **MJ seul créateur** — joueurs rejoignent par code
- Fermeture salon si MJ quitte (`room_closed`)
- Reconnexion joueurs (`rejoin_room`)
- `register_character` dans le contexte d'un salon
- Hôte ENet Godot sur port **7777** (PC du MJ), adresse publiée via `set_p2p_host`

### Phase 2 — Signalisation WebRTC + STUN (✅)
- Messages `signal` (`offer` / `answer` / `ice` / `meta`) relayés par le serveur pooling
- Plugin `webrtc/` (webrtc-native) + STUN publics (Google / Cloudflare)
- TURN optionnel via `TURN_URL` / `TURN_USERNAME` / `TURN_CREDENTIAL`
- Transport par défaut : **WebRTC** (`p2p_transport=auto`) ; ENet LAN si `force_loopback_p2p` ou `p2p_transport=enet`
- Adresse hôte publiée : `webrtc` (plus besoin d'IP publique pour jouer)

### Phase 3 — Autorité P2P complète (à venir)
- État de partie synchronisé entre pairs (CRDT ou hôte autoritaire Godot)
- MJ IA locale ou hybride (un joueur = GM, les autres = PJ)
- Bots gérés par l'hôte

### Phase 4 — Production (à venir)
- Serveur pooling déployé (VPS léger, ~512 Mo RAM)
- Authentification optionnelle, modération des salons
- Reconnexion après déconnexion

---

## 3. Protocole pooling (WebSocket JSON) — v2

Tous les messages sont du JSON UTF-8 sur `ws://host:8080`.  
Connexion initiale : `ws://127.0.0.1:8080?name=Pseudo` (optionnel).

**Enveloppe v2** : tout message reste **plat** (`type`), et toute requête peut
porter un `req_id` (chaîne ≤ 64 caractères) que le serveur renvoie **tel quel**
dans sa réponse ou son erreur (`withReqId()` / `extractReqId()`, voir
`server/src/lobby/protocol.ts`). Le serveur annonce `PROTOCOL_VERSION = 2` dans
`welcome.protocol`. La validation par type (zod) est décrite dans
`docs/SESSION_PROTOCOLE.md` ; le contrat complet est **testé** par
`server/scripts/test_lobby_protocol.ts` (`npm run test:protocol`, inclus dans
`npm test`). La table de référence est en [§3.3](#33-contrat-de-protocole-v2-référence).

### 3.1 Client → Serveur

#### `register_player`
Enregistre ou met à jour le pseudo du joueur.

```json
{ "type": "register_player", "playerName": "Aragorn" }
```

#### `get_lobby` / `list_rooms`
Demande la liste des salons publics.

```json
{ "type": "list_rooms" }
```

#### `create_room`
Crée une partie. **Réservé au MJ** (`role: "gm"` obligatoire). Le MJ devient hôte ENet.

```json
{
  "type": "create_room",
  "role": "gm",
  "roomName": "Aventure du vendredi",
  "maxPlayers": 4,
  "p2pHost": "192.168.0.42:7777"
}
```

| Champ | Type | Défaut | Description |
|-------|------|--------|-------------|
| `role` | `"gm"` | — | **Obligatoire.** Seule valeur acceptée : `"gm"`. Sinon erreur `INVALID_PAYLOAD` (code `GM_ONLY` si le serveur refuse un rôle non-MJ à un autre niveau). |
| `roomName` | string | `"Partie XXXX"` | Nom affiché |
| `maxPlayers` | number | 6 | 2–8 joueurs |
| `p2pHost` | string? | null | Adresse P2P publiée à la création ; en pratique le MJ la définit ensuite via `set_p2p_host` (champ conservé pour compatibilité) |

#### `join_room`
Rejoint une partie par code 4 chiffres (joueurs uniquement).

```json
{ "type": "join_room", "code": "4827" }
```

#### `rejoin_room`
Reconnexion d'un joueur après déconnexion involontaire (alias de `join_room`).

```json
{ "type": "rejoin_room", "code": "4827" }
```

#### `leave_room`
Quitte le salon actuel.

```json
{ "type": "leave_room" }
```

#### `register_character`
Enregistre le personnage du joueur **dans le salon courant**.

```json
{
  "type": "register_character",
  "character": {
    "name": "Aragorn",
    "race": "Humain",
    "class": "Guerrier",
    "stats": { "str": 16, "dex": 12, "con": 14, "int": 10, "wis": 13, "cha": 11 },
    "hp": 12,
    "ac": 16,
    "isPlayer": true,
    "isHuman": true,
    "isBot": false
  }
}
```

#### `set_p2p_host`
L'hôte publie son adresse ENet pour que les clients se connectent.

```json
{ "type": "set_p2p_host", "address": "192.168.0.42:7777" }
```

#### `signal` (Phase 2 — WebRTC)
Relais de signalisation entre deux joueurs du même salon.

```json
{
  "type": "signal",
  "targetPlayerId": "uuid-du-destinataire",
  "signalType": "offer",
  "payload": { "sdp": "..." }
}
```

`signalType` : `"offer"` | `"answer"` | `"ice"` | `"meta"` (`meta` sert à
l'annonce de présence WebRTC, payload `{ "action": "join" }` par exemple).

#### `ping`

```json
{ "type": "ping" }
```

---

### 3.2 Serveur → Client

#### `welcome`

Envoyé à la connexion **et** en réponse à `register_player`/`join` : identité
serveur, version de protocole et serveurs ICE pour le P2P WebRTC.

```json
{
  "type": "welcome",
  "playerId": "uuid",
  "playerName": "Aragorn",
  "protocol": 2,
  "iceServers": [{ "urls": ["stun:stun.l.google.com:19302"] }]
}
```

`iceServers` (optionnel) : STUN publics + TURN optionnel (`TURN_URL`,
`TURN_USERNAME`, `TURN_CREDENTIAL`). Le client le lit pour `WebRTCP2P.configure_ice()`.

#### `lobby_update`
Liste des salons disponibles.

```json
{
  "type": "lobby_update",
  "rooms": [
    {
      "code": "4827",
      "name": "Aventure du vendredi",
      "hostId": "uuid-hote",
      "hostName": "Aragorn",
      "playerCount": 2,
      "maxPlayers": 4,
      "p2pHost": "192.168.0.42:7777",
      "createdAt": 1725300000000
    }
  ]
}
```

#### `room_update`
État complet du salon (envoyé à tous les membres à chaque changement).

```json
{
  "type": "room_update",
  "room": {
    "code": "4827",
    "name": "Aventure du vendredi",
    "hostId": "uuid-mj",
    "gmId": "uuid-mj",
    "maxPlayers": 4,
    "p2pHost": "192.168.0.42:7777",
    "players": [
      {
        "playerId": "uuid-mj",
        "playerName": "Aragorn",
        "isHost": true,
        "isGm": true,
        "character": { "name": "Aragorn", "race": "Humain", "class": "Guerrier" },
        "joinedAt": 1725300000000
      },
      {
        "playerId": "uuid-player",
        "playerName": "Legolas",
        "isHost": false,
        "isGm": false,
        "character": { "name": "Legolas", "race": "Elfe", "class": "Rôdeur" },
        "joinedAt": 1725300060000
      }
    ],
    "createdAt": 1725300000000
  }
}
```

#### `host_assigned`
Confirme au MJ qu'il doit démarrer ENet.

```json
{ "type": "host_assigned", "hostId": "uuid", "p2pHost": null }
```

#### `player_joined` / `player_left`

```json
{ "type": "player_joined", "playerId": "uuid", "playerName": "Legolas", "roomCode": "4827" }
{ "type": "player_left", "playerId": "uuid", "playerName": "Legolas", "roomCode": "4827", "wasGm": false }
```

#### `room_closed`
Envoyé à **tous** les membres quand le MJ quitte ou se déconnecte. Le salon est dissous.

```json
{ "type": "room_closed", "roomCode": "4827", "reason": "gm_left" }
```

`reason` : `"gm_left"` (départ volontaire) | `"gm_disconnected"` (perte connexion WebSocket)

#### `session_ticket`

Émis à l'entrée dans un salon (`create_room`, `join_room`, `rejoin_room`,
`resume_session`) : ticket de reprise **usage unique**, TTL 2 min, à conserver
côté client (persisté dans `user://multiplayer_settings.cfg`).

```json
{ "type": "session_ticket", "ticket": "0b0d4c9e-…", "expiresAt": 1725300120000, "roomCode": "4827" }
```

#### `resumed`

Réponse à `resume_session` : même identité (`playerId`, `playerName`), place
dans le salon si celui-ci existe encore (`room` est alors l'état complet), sinon
`room: null` (identité restaurée, partie à rejoindre autrement). Un
**nouveau** `session_ticket` suit.

```json
{
  "type": "resumed",
  "playerId": "uuid",
  "playerName": "Aragorn",
  "room": { "code": "4827", "hostId": "uuid-mj", "gmId": "uuid-mj", "p2pHost": "webrtc", "maxPlayers": 4, "players": [], "name": "Aventure du vendredi", "createdAt": 1725300000000 }
}
```

#### `signal` (Phase 2)

```json
{
  "type": "signal",
  "fromPlayerId": "uuid-expediteur",
  "signalType": "answer",
  "payload": { "sdp": "..." }
}
```

#### `error`

```json
{ "type": "error", "code": "ROOM_NOT_FOUND", "message": "Salon 9999 introuvable.", "req_id": "abcd1234-3" }
```

`req_id` n'est présent que si la requête fautive en portait un (le client
l'utilise pour retirer la requête de `_pending_requests`).

Codes d'erreur **stables** (source : `server/src/lobby/protocol.ts`) :
`BAD_JSON`, `UNKNOWN_TYPE`, `INVALID_PAYLOAD`, `RATE_LIMITED`, `GM_ONLY`,
`JOIN_FAILED`, `ROOM_FULL`, `ROOM_NOT_FOUND`, `NOT_IN_ROOM`,
`TARGET_NOT_FOUND`, `TICKET_INVALID`, `TICKET_EXPIRED`, `ALREADY_IN_ROOM`,
`INTERNAL`. Le client mappe ces codes vers des textes joueur (`POOLING_ERRORS`
dans `multiplayer_manager.gd`) ; le test de contrat vérifie que les deux
ensembles sont **exactement** identiques.

#### `pong`

```json
{ "type": "pong" }
```

### 3.3 Contrat de protocole v2 (référence)

Cette table est la **référence testée** : chaque type est vérifié par
`server/scripts/test_lobby_protocol.ts` contre le schéma zod
(`src/lobby/validate.ts`) et contre ce que le client Godot
(`game/scripts/multiplayer/multiplayer_manager.gd`) envoie et lit réellement.
Toute évolution doit mettre à jour **le code, ce tableau, et le test** dans le
même commit.

#### Client → Serveur (13 types)

| `type` | Payload | Validé par | Envoyé par le client |
|---|---|---|---|
| `register_player` | `playerName?` | zod | oui (`_process`, via `_send_request`) |
| `join` | `playerName?` | zod | non (alias historique de `register_player`) |
| `get_lobby` | `{}` | zod | non (alias historique de `list_rooms`) |
| `list_rooms` | `{}` | zod | oui |
| `create_room` | `role: "gm"`, `roomName?`, `maxPlayers?` (2–8), `p2pHost?` | zod | oui (MJ uniquement) |
| `join_room` | `code` = 4 chiffres | zod | oui |
| `rejoin_room` | `code` = 4 chiffres | zod | oui |
| `resume_session` | `ticket` (8–120 car.) | zod | oui (dès `welcome` si ticket valide) |
| `leave_room` | `{}` | zod | oui (`_send`, sans `req_id`) |
| `register_character` | `character: objet` | zod (objet libre) | oui |
| `set_p2p_host` | `address` (ex. `"192.168.0.42:7777"` ou `"webrtc"`) | zod | oui (`_send`, sans `req_id`) |
| `signal` | `targetPlayerId`, `signalType` (`offer`/`answer`/`ice`/`meta`), `payload` | zod | oui (`_send`, sans `req_id`) |
| `ping` | `{}` | zod | non (le client n'envoie pas de keepalive) |

#### Serveur → Client (12 types)

| `type` | Champs principaux | Lu par le client |
|---|---|---|
| `welcome` | `playerId`, `playerName`, `protocol`, `iceServers?` | oui |
| `pong` | — | non (réponse à `ping`, que le client n'envoie pas) |
| `error` | `code`, `message`, `req_id?` | oui |
| `lobby_update` | `rooms[]` (`RoomSummary`) | oui |
| `room_update` | `room` (`RoomState`) | oui |
| `host_assigned` | `hostId`, `p2pHost` | oui |
| `player_joined` | `playerId`, `playerName`, `roomCode` | oui (déclenche `list_rooms`) |
| `player_left` | `playerId`, `playerName`, `roomCode`, `wasGm?` | oui (déclenche `list_rooms`) |
| `room_closed` | `roomCode`, `reason` (`gm_left`/`gm_disconnected`) | oui |
| `session_ticket` | `ticket`, `expiresAt`, `roomCode` | oui |
| `resumed` | `playerId`, `playerName`, `room` (`RoomState` ou `null`) | oui |
| `signal` | `fromPlayerId`, `signalType`, `payload` | oui |

Conventions communes :

- **`req_id`** : corrélation requête/réponse ; le serveur échoie via
  `withReqId()` ; le client l'extrait via `extractReqId()` et résout la requête
  en attente. Réponses de succès **et** erreurs peuvent le porter.
- **Validation** : `parseClientMessage()` (zod, `.loose()` = champs inconnus
  ignorés) ; requête invalide ⇒ `INVALID_PAYLOAD` avec le chemin du champ, sans
  toucher à l'état du salon.
- **Rate-limit** : chaque type possède une règle explicite dans
  `src/lobby/rate_limit.ts` (`signal` 240/s, `ping` 4/s, `create_room` 3/5 s,
  `join_room`/`rejoin_room`/`resume_session` 6/5 s…) ; au double seuil, la
  socket est fermée. Voir `docs/SESSION_PROTOCOLE.md`.
- **Ticket de reprise** : `session_ticket` (usage unique, TTL 2 min) →
  `resume_session` → `resumed` + nouveau ticket. Détail :
  `docs/SESSION_PROTOCOLE.md`.
- **Résolution des requêtes (dette corrigée)** : `multiplayer_manager.gd`
  résout la requête (`_resolve_request()`) à la réception de **toute** réponse
  portant un `req_id` — succès comme erreur — en tête de `_handle_message()`,
  avant le dispatch `match`. Une requête réussie ne reste donc plus dans
  `_pending_requests` : plus de faux « Pas de réponse du serveur » après
  `REQUEST_TIMEOUT = 8 s`, ni de fuite d'entrées. Couvert par
  `game/scripts/tests/pooling_client_requests_test.gd` (test client, sans
  réseau) et vérifié par le contrat ci-dessous.

Test de contrat :

```powershell
cd server
npm run test:protocol   # pur, sans port, < 1 s — inclus dans `npm test`
```

`server/scripts/test_lobby_protocol.ts` vérifie : les 13 types client→serveur
(schéma zod + payloads réels + rejets), les 12 types serveur→client (champs lus
par le client), l'égalité stricte des 14 codes d'erreur serveur/client/docs,
`PROTOCOL_VERSION = 2`, `withReqId`/`extractReqId`, la forme du ticket de
reprise, les seuils de rate-limit, l'alignement de ce document et la résolution
des requêtes corrélées côté client (appel générique avant dispatch, dette
ci-dessus corrigée).

---

## 4. Protocole ENet P2P (Godot 4)

Une fois le salon rejoint et l'adresse P2P connue, les clients Godot établissent une connexion **ENet** directe.

### 4.1 Configuration

| Paramètre | Valeur |
|-----------|--------|
| Port ENet | **7777** |
| Max peers | 8 |
| Bibliothèque | `ENetMultiplayerPeer` (Godot 4 natif) |

### 4.2 Flux de connexion

```
1. Joueur A crée salon (pooling) → reçoit code 4827
2. Joueur A : ENetMultiplayerPeer.create_server(7777)
3. Joueur A : set_p2p_host("192.168.0.42:7777") via pooling
4. Joueur B rejoint salon 4827 → reçoit p2pHost dans room_update
5. Joueur B : ENetMultiplayerPeer.create_client("192.168.0.42", 7777)
6. Connexion P2P établie — multiplayer.is_server() == true côté A
```

### 4.3 RPC Godot (Phase 3 — implémenté)

Les RPC synchronisent la session de jeu via l'hôte MJ (ENet P2P) :

| RPC | Direction | Rôle |
|-----|-----------|------|
| `request_start_game` | client → hôte | MJ lance la partie |
| `sync_game_state` | hôte → tous | État complet (`GameData.apply_server_state`) |
| `submit_action` | client → hôte | Action joueur + réponse IA hôte |
| `request_dice_roll` | client → hôte | Jet de dés autoritaire |
| `sync_dice_result` | hôte → tous | Affichage résultat dé |
| `sync_log_entry` | hôte → tous | Entrée journal (optionnel) |

Conventions :
- **`authority`** : seul l'hôte (peer 1) peut appeler les RPC de diffusion
- **`any_peer`** : n'importe quel client connecté peut envoyer au hôte
- **`call_local`** : exécuté aussi localement chez l'appelant (sync état / dé)
- **`reliable`** : garantie de livraison (TCP-like)

### 4.4 Identifiants réseau

| Concept | Valeur |
|---------|--------|
| `multiplayer.get_unique_id()` | 1 = serveur/hôte, 2+ = clients |
| `player_id` (pooling) | UUID serveur pooling — identité persistante hors P2P |
| `room_code` | Code 4 chiffres — identifiant de salon |

---

## 5. Architecture fichiers

```
server/
├── src/
│   ├── index.ts              # Point d'entrée — serveur pooling
│   ├── pooling/
│   │   └── server.ts         # Matchmaking WebSocket (salons, codes, tickets, relais signal)
│   └── lobby/
│       ├── types.ts          # Protocole v2 (messages client/serveur)
│       ├── protocol.ts       # PROTOCOL_VERSION, codes d'erreur, req_id
│       ├── validate.ts       # Validation zod par type de message
│       ├── rooms.ts          # RoomManager (codes, joueurs, GM)
│       ├── tickets.ts        # Tickets de reprise de session
│       └── rate_limit.ts     # Fenêtre glissante par (joueur, type)
├── scripts/
│   ├── test_lobby.ts               # unités lobby (81 vérif.)
│   ├── test_lobby_protocol.ts      # contrat protocole v2 (pur, 302 vérif.)
│   └── test_lobby_integration.ts   # bout en bout réseau (18 vérif.)
└── legacy/                   # moteur de jeu TS archivé (phase 5, ADR-001)
│
game/
├── scripts/
│   ├── multiplayer/
│   │   ├── multiplayer_manager.gd   # Autoload ENet + pooling (contrat client)
│   │   └── webrtc_p2p.gd            # Transport WebRTC (signal offer/answer/ice/meta)
│   └── main_menu.gd                 # UI salon P2P
└── project.godot                    # Autoload MultiplayerManager
```

---

## 6. Tester à 2 joueurs

### Prérequis
- Node.js 20+
- Godot 4.4+ (testé avec 4.7.2)
- Même réseau LAN (WiFi/Ethernet)

### Étapes

**Terminal 1 — Serveur pooling :**
```powershell
cd D:\git\OpenQuest_jdr\server
npm run dev
```

**MJ (Maître du Jeu) :**
1. Lancer Godot : `.\scripts\play-godot.ps1`
2. Menu → **Salon multijoueur (P2P)**
3. Rôle : **Maître du Jeu (MJ)**
4. Se connecter au pooling (`ws://127.0.0.1:8080` ou `ws://IP_SERVEUR:8080`)
5. Cliquer **Créer une partie (MJ)** → noter le code (ex. `4827`)
6. L'ENet démarre automatiquement sur port 7777
7. Enregistrer son personnage (optionnel)
8. Cliquer **🚀 Lancer la partie** → configurer scénario → **Lancer l'Aventure (P2P) !**

**Joueur 2 — autre PC ou 2e instance Godot :**
1. Lancer Godot
2. Rôle : **Joueur**
3. Se connecter au pooling (`ws://IP_DU_SERVEUR:8080`)
4. Entrer le code `4827` → **Rejoindre une partie**
5. Enregistrer son personnage
6. Connexion ENet automatique vers le PC du MJ
7. Affichage **En attente du MJ...** — entrée automatique en session quand le MJ lance

**En session (les deux PC) :**
- Journal synchronisé (actions, réponses MJ IA, bots)
- Chaque joueur envoie des actions via le champ texte
- Dés synchronisés (résolution côté hôte MJ)
- Badge **VOUS** sur votre personnage

**Reconnexion joueur :**
1. Joueur déconnecté → bouton **Reconnecter** (code mémorisé)
2. Ou ressaisir le code et **Rejoindre une partie**

**Vérifications :**
- Seul le MJ voit **Créer une partie** actif
- Les joueurs ne peuvent que rejoindre / reconnecter
- Code affiché chez le MJ : « Code à partager »
- Si le MJ quitte → message « salon fermé » chez les joueurs
- Départ d'un joueur → `player_left`, salon continue
- Statut P2P : « Connecté P2P (ENet) » après quelques secondes
- MJ : bouton **🚀 Lancer la partie** visible une fois ENet actif
- Joueur : **En attente du MJ...** jusqu'au lancement

**Tests automatiques :**
- `cd server && npm test` → `test:lobby` (81 vérif.), `test:protocol`
  (contrat protocole v2, pur, 309 vérif.) et `test:lobby:net`
  (bout en bout réseau, 18 vérif.) ;
- `./scripts/run_tests.ps1 -Filter 'session_protocol_test|pooling_client_requests_test'`
  (client Godot).

---

## 7. Limitations connues (v2)

| Limitation | Contournement |
|------------|---------------|
| WebRTC derrière NAT symétrique | TURN optionnel (`TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL`) |
| Repli LAN ENet si WebRTC indisponible | `p2p_transport=enet` / `force_loopback_p2p` |
| MJ IA côté hôte uniquement (moteur serveur `ai-gm.ts` archivé, ADR-001) | MJ IA locale à l'hôte ; MCP non actif |
| Salons volatiles (RAM, pas de persistance) | Phase 4 déploiement |
| Hôte = MJ — si MJ quitte, salon fermé pour tous | MJ recrée une partie |
| Reconnexion MJ après déconnexion | Non supportée — recréer une partie |
| Reconnexion joueur | `rejoin_room` avec le même code, ou `resume_session` avec le ticket |
| Pare-feu Windows peut bloquer port 7777 | Autoriser Godot dans le pare-feu |

---

## 8. Références

- [Godot 4 — High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [ENetMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html)
- `docs/SESSION_PROTOCOLE.md` — enveloppe, `req_id`, tickets, rate-limit
- `server/scripts/test_lobby_protocol.ts` — test de contrat du protocole v2
- `docs/refactor/AUDIT_SERVEUR.md` — audit serveur (dont protocole et tests)
- `docs/COLLABORATION.md` — workflow Git entre développeurs
- `docs/MCP.md` — MJ IA via MCP (archivé : `server/legacy/mcp/`)
