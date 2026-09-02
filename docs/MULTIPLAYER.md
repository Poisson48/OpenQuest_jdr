# Multijoueur OpenQuest JDR — Architecture P2P + Pooling

> Document de référence pour le multijoueur OpenQuest.  
> Dernière mise à jour : septembre 2026 — branche `server/pooling-v1`.  
> Voir aussi la feuille de route cartes interactives : [INTERACTIVE_MAPS_STRATEGY.md](./INTERACTIVE_MAPS_STRATEGY.md).

---

## 1. Vue d'ensemble

OpenQuest passe d'un **serveur autoritaire Node** (tout le jeu transite par le PC hôte) à un modèle **P2P + serveur de pooling** :

```
┌─────────────┐     WebSocket      ┌──────────────────┐     WebSocket      ┌─────────────┐
│  Joueur 1   │◄──────────────────►│ Serveur pooling  │◄──────────────────►│  Joueur 2   │
│  (Hôte P2P) │   matchmaking only │  (Node, :8080)   │   matchmaking only │  (Client)   │
└──────┬──────┘                    └──────────────────┘                    └──────┬──────┘
       │                                                                            │
       └──────────────────── ENet P2P (port 7777) ──────────────────────────────────┘
                              État de jeu, actions, dés
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

### Phase 2 — Signalisation WebRTC (à venir)
- Messages `signal` (offer/answer/ICE) relayés par le serveur pooling
- NAT traversal pour joueurs sur Internet sans port forwarding
- Remplacement progressif d'ENet LAN par WebRTC DataChannel

### Phase 3 — Autorité P2P complète (à venir)
- État de partie synchronisé entre pairs (CRDT ou hôte autoritaire Godot)
- MJ IA locale ou hybride (un joueur = GM, les autres = PJ)
- Bots gérés par l'hôte

### Phase 4 — Production (à venir)
- Serveur pooling déployé (VPS léger, ~512 Mo RAM)
- Authentification optionnelle, modération des salons
- Reconnexion après déconnexion

---

## 3. Protocole pooling (WebSocket JSON)

Tous les messages sont du JSON UTF-8 sur `ws://host:8080`.  
Connexion initiale : `ws://127.0.0.1:8080?name=Pseudo` (optionnel).

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
| `role` | `"gm"` | — | **Obligatoire.** Seule valeur acceptée : `"gm"`. Sinon erreur `NOT_GM`. |
| `roomName` | string | `"Partie XXXX"` | Nom affiché |
| `maxPlayers` | number | 6 | 2–8 joueurs |
| `p2pHost` | string? | null | Adresse ENet (rempli par le MJ après `create_server`) |

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

`signalType` : `"offer"` | `"answer"` | `"ice"`

#### `ping`

```json
{ "type": "ping" }
```

---

### 3.2 Serveur → Client

#### `welcome`

```json
{ "type": "welcome", "playerId": "uuid", "playerName": "Aragorn" }
```

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
{ "type": "error", "message": "Salon 9999 introuvable.", "code": "JOIN_FAILED" }
```

Codes d'erreur : `CREATE_FAILED`, `JOIN_FAILED`, `NOT_GM`

#### `pong`

```json
{ "type": "pong" }
```

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
│   │   └── server.ts         # Matchmaking WebSocket (salons, codes)
│   └── lobby/
│       └── rooms.ts          # RoomManager (codes, joueurs)
│
game/
├── scripts/
│   ├── multiplayer/
│   │   └── multiplayer_manager.gd   # Autoload ENet + pooling
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

---

## 7. Limitations connues (v1)

| Limitation | Contournement |
|------------|---------------|
| ENet LAN uniquement (pas Internet) | Phase 2 WebRTC |
| MJ IA locale côté hôte (pas ai-gm.ts) | Brancher MCP / serveur IA plus tard |
| Salons volatiles (RAM, pas de persistance) | Phase 4 déploiement |
| Hôte = MJ — si MJ quitte, salon fermé pour tous | MJ recrée une partie |
| Reconnexion MJ après déconnexion | Non supportée — recréer une partie |
| Reconnexion joueur | `rejoin_room` avec le même code |
| Pare-feu Windows peut bloquer port 7777 | Autoriser Godot dans le pare-feu |

---

## 8. Références

- [Godot 4 — High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- [ENetMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html)
- `docs/COLLABORATION.md` — workflow Git entre développeurs
- `docs/MCP.md` — MJ IA via MCP (outil serveur séparé)
