# OpenQuest JDR — Jeu multijoueur

Jeu de rôle multijoueur : client **Godot 4** + serveur **Node.js** (WebSocket).

## Structure

```
OpenQuest_jdr/
├── game/          # Projet Godot 4 (client)
├── server/        # Serveur Node.js (WebSocket)
└── docs/          # Documentation technique
```

## Prérequis

| Outil | Version | Installation |
|-------|---------|--------------|
| **Node.js** | ≥ 20 | [nodejs.org](https://nodejs.org) |
| **Godot** | 4.4+ | [godotengine.org](https://godotengine.org/download) ou `flatpak install flathub org.godotengine.Godot` |

## Démarrage rapide

### 1. Serveur

```bash
cd server
cp .env.example .env
npm install
npm run dev
```

Le serveur écoute sur `ws://0.0.0.0:8080`.

### 2. Client Godot

1. Ouvrir le dossier `game/` dans Godot 4
2. Lancer la scène principale (`scenes/main.tscn`)
3. Flèches du clavier pour se déplacer

Pour jouer à deux sur le réseau local, modifier `server_url` dans `game/scripts/network_client.gd` avec l'IP de la machine qui héberge le serveur.

## Travailler à deux

Ce projet est fait pour **deux personnes** (client Godot + serveur Node).

```bash
# Première fois sur une machine
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

| Qui | Zone | Branches Git |
|-----|------|--------------|
| Poisson | `server/`, réseau, infra | `server/...` |
| Copine | `game/`, UI, règles JDR | `game/...` |
| Les deux | `docs/`, protocole WS | `docs/...` |

**Workflow :** branche → commit → Pull Request → merge sur `main`.

Guides :
- [docs/COLLABORATION.md](docs/COLLABORATION.md) — workflow Git, conflits Godot, routine
- [CONTRIBUTING.md](CONTRIBUTING.md) — résumé rapide

**Ajouter ta copine sur GitHub :** Settings → Collaborators → Add people (elle accepte l’invitation).

## Documentation

- [docs/STACK.md](docs/STACK.md) — architecture technique
- [docs/COLLABORATION.md](docs/COLLABORATION.md) — bosser à deux

## Licence

À définir.
