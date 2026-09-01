# OpenQuest JDR — Jeu multijoueur

> **🚧 Travaux en cours — jeu en développement**  
> POC HTML jouable + prototype serveur Godot en parallèle.

Jeu de rôle multijoueur : **POC HTML** (jouable tout de suite) + client **Godot 4** + serveur **Node.js** (WebSocket).

## État actuel

| Phase | Statut | Détail |
|-------|--------|--------|
| **POC HTML** | ✅ Jouable | `index.html` — aventures, enquête, cartes, MJ IA |
| Setup technique | ✅ Fait | Serveur WebSocket, squelette Godot, doc collaboration |
| Gameplay Godot | ⏳ À venir | Portage des règles du POC |
| Multijoueur complet | ⏳ À venir | Après intégration des règles du POC |

## POC HTML — lancer sans installation

```bash
# Ouvrir directement dans le navigateur
./ouvrir-openquest.sh
# ou double-clic sur index.html
```

Fonctionnalités : création de personnages, scénarios, bots, cartes interactives (monde + lieux), mode enquête, session de jeu avec MJ IA ou humain.

## Structure

```
OpenQuest_jdr/
├── index.html     # POC HTML — point d'entrée
├── css/           # Styles du POC
├── js/            # Logique du POC
├── game/          # Projet Godot 4 (client)
├── server/        # Serveur Node.js (WebSocket)
├── poc/           # Références / exports POC
├── docs/          # Documentation
└── scripts/       # Setup et lancement rapide
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

Ce projet est fait pour **deux personnes**.

```bash
# Première fois sur une machine (Poisson / machine de dev)
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

| Qui | Zone | Branches Git | Phase actuelle |
|-----|------|--------------|----------------|
| Poisson | `server/`, `game/`, infra | `server/...`, `game/...` | Dev technique |
| **AslanUsko** | POC HTML, règles JDR, design | `index.html`, `css/`, `js/`, `docs/...` | POC HTML jouable |
| Les deux | `docs/`, protocole WS | `docs/...` | — |

**Workflow :** branche → commit → Pull Request → merge sur `main`.

Guides :
- [docs/COLLABORATION.md](docs/COLLABORATION.md) — workflow Git, conflits Godot, routine
- [docs/IA_POUR_ASLANUSKO.md](docs/IA_POUR_ASLANUSKO.md) — guide pour l'IA qui accompagne AslanUsko (phase POC)
- [CONTRIBUTING.md](CONTRIBUTING.md) — résumé rapide

**Collaborateur GitHub :** @AslanUsko — POC HTML et documentation.

## Documentation

- [docs/STACK.md](docs/STACK.md) — architecture technique
- [docs/COLLABORATION.md](docs/COLLABORATION.md) — bosser à deux
- [docs/IA_POUR_ASLANUSKO.md](docs/IA_POUR_ASLANUSKO.md) — accompagnement IA (POC HTML)

## Licence

À définir.
