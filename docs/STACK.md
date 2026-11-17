# Rapport technique — OpenQuest JDR

> ⚠️ **Document partiellement obsolète — conservé comme historique.**
> Rédigé en septembre 2026, il décrit l'**ancien modèle « serveur autoritaire »** (le serveur Node fait autorité sur l'état du monde, protocole v0.1 `join` / `player_input`).
> Le **runtime réel** est un **hôte Godot autoritaire + serveur de pooling sans logique de jeu** ([MULTIPLAYER.md](./MULTIPLAYER.md), [SESSION_PROTOCOLE.md](./SESSION_PROTOCOLE.md)) : le serveur ne gère que salons, tickets, rate-limit et signalisation WebRTC.
> Le **moteur de jeu TypeScript et le serveur MCP (MJ IA)** sont **archivés** dans [`server/legacy/`](../server/legacy/README.md) — hors compilation, non importés (voir [AUDIT_SERVEUR.md](./refactor/AUDIT_SERVEUR.md) et le [plan de refactorisation](./refactor/PLAN_REFACTORISATION.md)).
> Ce qui reste valable ci-dessous : stack technique (Node/Godot, WebSocket), installation Godot, commandes serveur, configuration. Le contenu n'est pas supprimé pour garder l'historique des décisions.
> Dernière mise à jour du contenu : septembre 2026 · bandeau d'obsolescence ajouté le 2026-11-17.

> Document de référence pour l'environnement de développement multijoueur.

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

> **⚠️ Obsolète.** Le code ne fonctionne pas ainsi : le **serveur Node n'est qu'un serveur de pooling** (salons, matchmaking, signalisation WebRTC) et **l'hôte Godot est l'autorité** de la partie ([MULTIPLAYER.md](./MULTIPLAYER.md) §1). Le protocole `player_input` / `state_sync` décrit plus bas n'existe plus (protocole pooling v2 dans `server/src/lobby/types.ts`). Le moteur de jeu serveur correspondant est archivé dans [`server/legacy/`](../server/legacy/README.md).

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
| **Moteur** | Godot 4.7 | Open source, excellent pour 2D/3D, WebSocket intégré |
| **Langage** | GDScript | Natif Godot, courbe d'apprentissage douce |
| **Réseau** | `WebSocketPeer` | Connexion directe au serveur Node, pas de plugin |
| **Rendu** | Forward+ (2D) | Suffisant pour un JDR vue de dessus / carte |

**Structure Godot :**

```
game/
├── project.godot
├── scenes/
│   ├── main_menu.tscn  # Menu principal + hub
│   ├── session/        # Session de jeu (MJ + joueurs)
│   ├── map_editor/     # Éditeur de cartes 3D
│   └── hub/            # Hub (scénarios, personnages, cartes)
└── scripts/
    ├── core/             # Logique métier pure (persistence, rules, session, maps, navigation)
    ├── maps/editor/      # Éditeur battlemap 3D (document + contrôleurs)
    ├── session/          # UI session (SessionViewModel, panneaux)
    ├── multiplayer/      # MultiplayerManager, WebRTCP2P
    ├── ui/               # Composants UI partagés
    └── tests/            # Tests headless
```

### Protocole réseau (v0.1) — obsolète

> Conservé comme historique : ce protocole n'est plus émis par aucun client. Le protocole réel est le **pooling v2** (`server/src/lobby/types.ts` + `protocol.ts` : `create_room`, `join_room`, `signal`, `resume_session`…).

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

> **⚠️ Obsolète** : cette roadmap décrit la direction « serveur autoritaire » abandonnée (ADR-001 du [plan](./refactor/PLAN_REFACTORISATION.md)). En particulier, la v0.4 « lanceur de dés côté serveur » est **contredite par ADR-005** : l'hôte Godot calcule les dés et `game/scripts/core/rules/dice_engine.gd` est l'unique implémentation exécutable.

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
