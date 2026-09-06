# OpenQuest JDR

Client **Godot 4.7** + serveur **Node.js** (pooling WebSocket / matchmaking P2P).

Création de personnages, scénarios et cartes, puis session solo ou à plusieurs (MJ humain ou MJ IA). Persistance locale Godot (`user://`).

| Composant | Statut | Lancement (Windows) |
|-----------|--------|---------------------|
| **Client Godot** | Jouable (démos Valbois + Crypte) | `.\scripts\play-godot.ps1` |
| **Serveur Node (pooling)** | Opérationnel (LAN) | `.\scripts\dev-server.sh` ou `cd server && npm run dev` |

> **État des lieux** : section [TODO](#todo--état-des-lieux) ci-dessous (source de vérité). Audits détaillés dans `docs/`.

---

## Ce qui marche aujourd’hui

- **Menus / hub / setup / session** — parcours solo et MJ humain
- **Deux démos catalogue** uniquement : `demo-valbois`, `demo-crypte` (autres JSON sous `game/data/scenarios/` existent mais ne sont plus proposés)
- **Cartes dual-mode** — simple (tuiles) + complexe 3D (`ComplexMapEngine3D`)
  - Style **diorama** (défaut) : fond illustré, tokens découpes, navigation lieux
  - Style **VTT** : battlemap tactique (murs, ombres, tokens cylindriques)
- **Valbois** — cartes illustrées HD (`valbois_village.png`, `place_du_marche.png`), zoom lieu → Place du Marché, personnage **Kael** (voleur + portrait)
- **HUD joueur immersif** — carte plein écran + overlay (`PlayerSessionHud`) ; vue MJ = panneau de session classique
- **Éditeur battlemap 3D** — Hub → Cartes → carte complexe → Modifier
- **Scénarios non linéaires** — graphe de scènes, navigation MJ
- **Serveur pooling** — salons + signalisation ; jeu P2P ENet en LAN (pas Internet)

---

## Démos

| Id | Titre | Carte |
|----|-------|-------|
| `demo-valbois` | Retour à Valbois | Complexe / diorama — village + Place du Marché, token Kael |
| `demo-crypte` | La Crypte Oubliée | Simple / tuiles — Brumeval |

Raccourcis de lancement :

```powershell
.\scripts\play-godot.ps1                                              # menu, profil MJ
.\scripts\play-godot-player.ps1                                       # 2e instance, profil joueur
.\scripts\play-godot-mj-demo.ps1                                      # boot session MJ
.\scripts\play-godot.ps1 res://scenes/debug/valbois_demo_boot.tscn    # Valbois direct
.\scripts\play-godot.ps1 res://scenes/debug/valbois_player_demo_boot.tscn  # Valbois HUD joueur
```

---

## Structure

```
OpenQuest_jdr/
├── game/                 # Client Godot 4.7 (Forward+)
│   ├── assets/maps/      # Illustrations Valbois HD
│   ├── assets/portraits/ # Portrait Kael
│   ├── data/scenarios/   # JSON scénarios (catalogue filtré à 2 démos)
│   ├── scenes/           # Menus, hub, session, boots debug
│   └── scripts/          # Autoloads, maps 3D, UI, tests headless
├── server/               # Pooling WebSocket (TypeScript)
├── data/                 # Jeu de données partagé (scénarios historiques, bots, tiles)
├── docs/                 # Audits, architecture, cartes, multijoueur
└── scripts/              # play-godot*.ps1 / .sh, setup, captures
```

---

## Démarrage

### Prérequis

| Outil | Version |
|-------|---------|
| Godot | **4.7.x** (pas .NET) — `project.godot` → `config/features` = `4.7` |
| Node.js | ≥ 20 (serveur / MCP) |

### Client (Windows)

```powershell
cd D:\git\OpenQuest_jdr
.\scripts\play-godot.ps1
```

Le script cherche Godot (PATH / WinGet / Downloads) et utilise le profil utilisateur **`OpenQuest_MJ`** (`%APPDATA%\Godot\app_userdata\OpenQuest_MJ`).

Linux / Flatpak : `./scripts/play-godot.sh`  
Ou ouvrir `game/` dans l’éditeur Godot → F5 (`scenes/main_menu.tscn`).

### Serveur (multijoueur LAN)

```bash
./scripts/dev-server.sh
# ou : cd server && cp -n .env.example .env && npm install && npm run dev
```

Écoute `ws://0.0.0.0:8080`. Salon depuis le menu → **Salon multijoueur (P2P)**.

### Tests headless

```bash
# Exemples (Godot dans le PATH ou Flatpak)
godot --headless --path game -s res://scripts/tests/map_camera_test.gd
godot --headless --path game -s res://scripts/tests/map_mode_test.gd
godot --headless --path game -s res://scripts/tests/quest_navigation_test.gd
godot --headless --path game -s res://scripts/tests/valbois_player_hud_test.gd
```

Suites utiles : `map_*`, `quest_navigation_test`, `scenario_editor_test`, `valbois_*`.  
`user_flow_test` est connu pour échouer (cherche encore une carte simple là où Valbois est complexe).

---

## Architecture (bref)

```
Client Godot 4.7                    Serveur Node (pooling)
├── GameData / MapData (user://)    ├── Salons + codes
├── Session MJ | HUD joueur         └── Signalisation P2P
├── ComplexMapEngine3D / Simple
└── ENet (hôte = MJ)  ◄──────────►  clients (LAN)
```

Détails : [docs/STACK.md](docs/STACK.md), [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md), [docs/INTERACTIVE_MAPS.md](docs/INTERACTIVE_MAPS.md).  
Note : `STACK.md` décrit encore en partie l’ancien modèle « serveur autoritaire » ; le runtime actuel est **P2P + pooling** (voir `MULTIPLAYER.md`).

---

## TODO / état des lieux

Priorisé. Le README reste la source de vérité ; les audits détaillent le « pourquoi ».

### Fait

- [x] Client Godot — menus, hub, persos, setup, session MJ / joueur
- [x] Catalogue réduit à **2 démos** (`demo-valbois`, `demo-crypte`)
- [x] Moteur carte complexe 3D + style diorama / VTT
- [x] Éditeur battlemap 3D (outils, calques, undo, templates)
- [x] Cartes Valbois illustrées + navigation village → Place du Marché
- [x] Portrait / fiche Kael + boot démo Valbois
- [x] HUD joueur immersif (`player_session_hud.gd`)
- [x] Navigation narrative non linéaire (graphe + tests)
- [x] Serveur pooling + docs multijoueur LAN
- [x] Suite de tests cartes (dont `map_camera_test`) — voir aussi [docs/AUDIT_CARTES.md](docs/AUDIT_CARTES.md)

### En cours / WIP récent

- [ ] **Qualité cartes Valbois HD** — fond parfois soft / cache `user://map_assets` + import Godot (`*.import`, compression 3D) ; recharger les PNG `res://assets/maps/` proprement
- [ ] **Clarté UI / bugs visuels** — audit dédié : [docs/AUDIT_UI_CLARTE.md](docs/AUDIT_UI_CLARTE.md) *(disponible — base de travail pour AslanUsko)* ; s’appuyer aussi sur [docs/UI_UX.md](docs/UI_UX.md)
- [ ] **HUD joueur vs session MJ** — divergences de layout, marges carte sous le HUD, messages d’échelle / tooltips lieux
- [ ] **Token Kael** — échelle découpe (`scale` village / place), un seul token (dédoublonnage party ↔ `playDefaults` encore fragile)
- [ ] Correctifs caméra perspective / VTT orthographique restants ([AUDIT_CARTES](docs/AUDIT_CARTES.md) P1 — partie déjà traitée dans le moteur)

### À faire (priorité)

1. **Stabiliser le rendu Valbois** (qualité PNG, pas de cache périmé, cadrage village entier hors HUD)
2. **Passer l’audit clarté UI** et corriger les bugs bloquants listés dedans
3. **Calibrer Kael** — taille lisible, un token, portrait net en diorama
4. **Navigation joueur** — clic lieu en lecture seule / messages d’échelle (P2 audit cartes)
5. **Multijoueur** — test bout-en-bout 2 PC ; sync deltas carte / fog filtré joueur encore incomplet
6. **Tests & captures** — réparer `user_flow_test` ; valider Valbois via `valbois_screenshot_test` / `valbois_player_hud_test`
7. LOS / occlusion fog par vision token + portes
8. Import UVTT / bibliothèque de décors livrée avec assets
9. WebRTC (hors LAN) / sauvegardes cloud — plus tard

---

## Documentation

| Fichier | Contenu |
|---------|---------|
| [docs/AUDIT_CARTES.md](docs/AUDIT_CARTES.md) | Audit moteur diorama / caméra / P1–P3 |
| [docs/AUDIT_UI_CLARTE.md](docs/AUDIT_UI_CLARTE.md) | Audit clarté UI *(disponible)* |
| [docs/MAP_DIORAMA_PLAN.md](docs/MAP_DIORAMA_PLAN.md) | Plan diorama 2.5D (appliqué) |
| [docs/INTERACTIVE_MAPS.md](docs/INTERACTIVE_MAPS.md) | Dual-mode simple / complexe |
| [docs/MAP_EDITOR.md](docs/MAP_EDITOR.md) | Éditeur battlemap 3D |
| [docs/QUEST_NAVIGATION.md](docs/QUEST_NAVIGATION.md) | Scénarios non linéaires |
| [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md) | P2P + pooling, limites LAN |
| [docs/UI_UX.md](docs/UI_UX.md) | Parcours et conventions UI |
| [docs/COLLABORATION.md](docs/COLLABORATION.md) | Git à deux |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution |

---

## Contributeurs

| Qui | GitHub | Rôle |
|-----|--------|------|
| **Poisson** | [@Poisson48](https://github.com/Poisson48) | Godot, serveur Node, infra |
| **AslanUsko** | [@AslanUsko](https://github.com/AslanUsko) | UI Godot, règles JDR, design, cartes |

```bash
git checkout -b game/ma-fonctionnalite   # ou server/..., docs/...
# … puis PR vers main
```

---

## Licence

À définir.
