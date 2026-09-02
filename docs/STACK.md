# Rapport technique — OpenQuest JDR

> Document de référence pour l'environnement de développement multijoueur.
> Dernière mise à jour : septembre 2026

---

## Vue d'ensemble

OpenQuest JDR est un jeu multijoueur en temps réel avec une architecture **client-serveur** :

```
┌─────────────────┐     WebSocket (JSON)     ┌─────────────────┐
│  Client Godot 4 │ ◄──────────────────────► │  Serveur Node   │
│  (game/)        │      ws://host:8080       │  (server/)      │
└─────────────────┘                           └─────────────────┘
        ▲                                              ▲
        │                                              │
   Joueur 1 (toi)                              Autorité serveur
   Joueur 2 (AslanUsko)                         (état du monde)
```

Le serveur Node est l'**autorité** : il reçoit les inputs des joueurs, met à jour l'état du monde, et diffuse la position de chacun. Les clients Godot n'affichent que ce que le serveur leur envoie.

---

## Stack technique

### Serveur — Node.js + TypeScript

| Composant | Choix | Pourquoi |
|-----------|-------|----------|
| **Runtime** | Node.js 20+ | Déjà installé, écosystème riche, facile à déployer |
| **Langage** | TypeScript | Typage des messages réseau, moins d'erreurs |
| **Transport** | WebSocket (`ws`) | Natif dans Godot 4 (`WebSocketPeer`), faible latence, bidirectionnel |
| **Format messages** | JSON | Simple à déboguer, lisible, suffisant pour un JDR |
| **Dev** | `tsx watch` | Rechargement à chaud sans build manuel |
| **Config** | `.env` + `dotenv` | Port et hôte configurables |

**Dépendances npm :**

| Package | Rôle |
|---------|------|
| `ws` | Serveur WebSocket |
| `typescript` | Compilation TS → JS |
| `tsx` | Exécution TypeScript en dev |
| `@types/ws` | Types pour `ws` |
| `dotenv` | Variables d'environnement |

### Client — Godot 4

| Composant | Choix | Pourquoi |
|-----------|-------|----------|
| **Moteur** | Godot 4.4 | Open source, excellent pour 2D, WebSocket intégré |
| **Langage** | GDScript | Natif Godot, courbe d'apprentissage douce |
| **Réseau** | `WebSocketPeer` | Connexion directe au serveur Node, pas de plugin |
| **Rendu** | Forward+ (2D) | Suffisant pour un JDR vue de dessus / carte |

**Structure Godot :**

```
game/
├── project.godot
├── scenes/
│   ├── main.tscn       # Scène racine (UI + joueurs)
│   └── player.tscn     # Représentation visuelle d'un joueur
└── scripts/
    ├── main.gd           # Boucle de jeu, inputs clavier
    ├── multiplayer/
    │   └── multiplayer_manager.gd  # Autoload ENet + pooling WebSocket
    └── main_menu.gd                  # UI salon P2P (code 4 chiffres)
```

### Protocole réseau (v0.1)

Messages JSON échangés entre client et serveur.

**Client → Serveur :**

```json
{ "type": "join", "playerName": "Poisson" }
{ "type": "ping" }
{ "type": "player_input", "input": { "moveX": 1, "moveY": 0 } }
```

**Serveur → Client :**

```json
{ "type": "welcome", "playerId": "uuid", "playerName": "Poisson" }
{ "type": "pong" }
{ "type": "player_joined", "playerId": "uuid", "playerName": "Poisson" }
{ "type": "player_left", "playerId": "uuid" }
{ "type": "state_sync", "players": [{ "id": "...", "name": "...", "x": 0, "y": 0 }] }
{ "type": "error", "message": "..." }
```

---

## Pourquoi Node + Godot (et pas autre chose) ?

| Alternative | Verdict |
|-------------|---------|
| **Godot seul (ENet / MultiplayerAPI)** | Possible, mais le serveur serait aussi Godot (headless). Moins flexible pour lobby, auth, persistance. |
| **Socket.io** | Plus lourd, nécessite un plugin Godot. `ws` natif suffit. |
| **Unity + Netcode** | Propriétaire, overkill pour un petit JDR à deux. |
| **Python (FastAPI + WebSocket)** | Valide, mais Node est plus naturel pour du temps réel et tu l'as déjà. |

**Node pour le serveur** = logique métier, persistance, matchmaking futur, déploiement facile (Railway, Fly.io, VPS).
**Godot pour le client** = rendu 2D, UI, animations, tout ce qui est visuel et interactif.

---

## Workflow de développement

```bash
# Terminal 1 — Serveur
cd server && npm run dev

# Terminal 2 — Client (Godot Editor)
# Ouvrir game/ dans Godot, F5 pour lancer
# Lancer une 2e instance (Debug > Run Multiple Instances) pour tester à 2
```

### Jouer à deux (réseau local)

1. Machine hôte (MJ) : `npm run dev` dans `server/`, puis lancer Godot et créer un salon
2. Trouver l'IP locale du MJ : `ipconfig` / `ip addr` (ex. `192.168.1.42`)
3. Sur le 2e PC : lancer Godot, panneau **Salon multijoueur (P2P)**, URL `ws://192.168.1.42:8080`, rejoindre avec le code à 4 chiffres
4. Le MJ démarre la partie — connexion P2P ENet sur le port **7777** du PC MJ

---

## Roadmap technique suggérée

| Phase | Contenu |
|-------|---------|
| **v0.1** | Connexion WebSocket, déplacement basique, sync positions |
| **v0.2** | Carte / tilemap, collisions, caméra qui suit le joueur |
| **v0.3** | Chat texte, fiches de personnage synchronisées |
| **v0.4** | Lanceur de dés côté serveur (anti-triche) |
| **v0.5** | Fog of war, tokens MJ, scènes / salles |
| **v1.0** | Auth simple, sauvegarde de parties, déploiement serveur |

---

## Installation Godot (si pas encore fait)

```bash
# Option 1 — Flatpak (recommandé sur Linux)
flatpak install flathub org.godotengine.Godot

# Option 2 — Téléchargement direct
# https://godotengine.org/download/linux/
# Extraire et lancer ./Godot_v4.x.x_stable_linux.x86_64
```

---

## Commandes utiles

```bash
# Serveur
cd server
npm install          # Installer les dépendances
npm run dev          # Dev avec hot-reload
npm run build        # Compiler TypeScript
npm run typecheck    # Vérifier les types sans compiler

# Vérifier que le serveur répond
curl http://localhost:8080
```

---

## Fichiers de configuration

| Fichier | Description |
|---------|-------------|
| `server/.env` | Port, hôte (copier depuis `.env.example`) |
| `server/package.json` | Dépendances et scripts npm |
| `game/project.godot` | Configuration projet Godot |
| `game/scripts/multiplayer/multiplayer_manager.gd` | Pooling WebSocket + hôte/client ENet |
| `game/scripts/main_menu.gd` | URL serveur pooling, création/rejoindre salon |
