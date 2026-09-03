# OpenQuest JDR

> Créateur et session de jeu de rôle — client **Godot 4** + serveur **Node.js** (multijoueur WebSocket).

**OpenQuest** permet de créer des personnages, scénarios et cartes, puis de jouer en solo ou à plusieurs avec un MJ humain ou une **MJ IA**. Les données sont persistées localement (Godot `user://`).

| Composant | Statut | Lancement |
|-----------|--------|-----------|
| **Client Godot** | ✅ Jouable | `./scripts/play-godot.sh` (ou ouvrir `game/` dans Godot 4, F5) |
| **Serveur Node (pooling)** | ✅ Opérationnel | `./scripts/dev-server.sh` ou `cd server && npm run dev` |

---

## Fonctionnalités

### Modes de jeu
- **One-shot** — aventure courte
- **Campagne longue** — scénarios étendus + carte du monde
- **Enquête** — investigation avec roster et cartes dédiées

### Création de contenu
- **Personnages** — fiches aventure / enquête (tiers simple → complet), PC ou bots
- **Scénarios non linéaires** — éditeur de **graphe de scènes** (branches, retours MJ, auto-layout, validation)
- **Bots compagnons** — archétypes IA pour compléter le groupe
- **Cartes dual-mode** :
  - **Simple** — grilles de tuiles, cartes du monde, brouillard cellulaire, liens monde → lieu
  - **Complexe (3D)** — battlemap PNG, tokens 3D, fog, effets, zones, murs, lumières

### Éditeur de battlemap 3D
Hub → Cartes → carte en mode **Complexe** → **✏️ Modifier** :
- Outils : tokens, marqueurs, effets, zones, plateformes, murs, notes MJ, lumières, terrain, fog, liens, mesure, templates
- Undo/redo par deltas, calques, mini-carte, aimantation, raccourcis
- Import PNG (Dungeon Alchemist / Dungeondraft…), perspectives top-down / iso / perspective

### Session de jeu
- Groupe jusqu'à 10 participants (humains + bots)
- **MJ IA** adaptatif ou **MJ humain**
- **Navigation narrative** — saut libre entre scènes, branches, clôture manuelle
- Journal de partie, dés intégrés, timer de session
- Cartes interactives en partie (placement, zoom, pan, fog)
- **PNJ IA** — génération et gestion de personnages improvisés

---

## Structure du projet

```
OpenQuest_jdr/
├── game/                   # Client Godot 4
│   ├── scenes/             # Menus, hub, session, éditeurs
│   ├── scripts/maps/       # Moteur 3D + éditeur battlemap
│   └── scripts/tests/      # Tests headless
├── server/                 # Serveur WebSocket Node.js
├── data/                   # Données JSON partagées (scénarios, bots, tuiles)
├── docs/                   # Documentation
└── scripts/                # Setup & lancement
```

---

## Démarrage

### Prérequis

| Outil | Version |
|-------|---------|
| Node.js | ≥ 20 |
| Godot | 4.4+ (Flatpak `org.godotengine.Godot` recommandé) |

Setup initial après clone :

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

### Serveur

```bash
./scripts/dev-server.sh
# équivalent : cd server && cp -n .env.example .env && npm install && npm run dev
```

Écoute sur `ws://0.0.0.0:8080`.

### Client Godot

```bash
./scripts/play-godot.sh
```

Ou : ouvrir `game/` dans Godot 4 → scène principale `scenes/main_menu.tscn` (F5).

Multijoueur LAN : panneau **Salon multijoueur (P2P)** du menu (`ws://IP:8080`).

### Tests headless (Godot)

```bash
flatpak run org.godotengine.Godot --headless --path game -s res://scripts/tests/map_editor_test.gd
flatpak run org.godotengine.Godot --headless --path game -s res://scripts/tests/quest_navigation_test.gd
flatpak run org.godotengine.Godot --headless --path game -s res://scripts/tests/scenario_editor_test.gd
flatpak run org.godotengine.Godot --headless --path game -s res://scripts/tests/map_mode_test.gd
```

---

## Contributeurs

| Qui | GitHub | Rôle |
|-----|--------|------|
| **Poisson** | [@Poisson48](https://github.com/Poisson48) | Godot, serveur Node, infra |
| **AslanUsko** | [@AslanUsko](https://github.com/AslanUsko) | UI Godot, règles JDR, design, cartes |

### Workflow Git

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
git checkout -b game/ma-fonctionnalite   # ou server/..., docs/...
# … modifications …
git commit -m "Description claire"
git push origin game/ma-fonctionnalite
# → Pull Request sur main
```

| Zone | Fichiers | Qui |
|------|----------|-----|
| Jeu Godot | `game/` | Les deux |
| Serveur réseau | `server/` | Poisson |
| Documentation | `docs/` | Les deux |

---

## Documentation

| Fichier | Contenu |
|---------|---------|
| [docs/COLLABORATION.md](docs/COLLABORATION.md) | Git, branches, conflits, routine à deux |
| [docs/STACK.md](docs/STACK.md) | Architecture technique |
| [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md) | Multijoueur P2P + pooling |
| [docs/QUEST_NAVIGATION.md](docs/QUEST_NAVIGATION.md) | Scénarios non linéaires (graphe de scènes) |
| [docs/INTERACTIVE_MAPS.md](docs/INTERACTIVE_MAPS.md) | Moteur cartes dual-mode (simple / 3D) |
| [docs/MAP_EDITOR.md](docs/MAP_EDITOR.md) | Éditeur battlemap 3D (outils, undo, templates) |
| [docs/INTERACTIVE_MAPS_STRATEGY.md](docs/INTERACTIVE_MAPS_STRATEGY.md) | Analyse concurrentielle VTT et feuille de route |
| [docs/UI_UX.md](docs/UI_UX.md) | Parcours utilisateur et conventions UI |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Résumé contribution |

---

## Feuille de route

- [x] Client Godot — menus, hub, persos, setup, session
- [x] Serveur Node — MJ IA (`ai-gm.ts`), bots, dés, sessions JSON
- [x] Serveur MCP — outils GM pour agents (`npm run mcp`)
- [x] Données JSON — `data/scenarios/`, `data/bots/`, `data/tiles.json`
- [x] Éditeur de scénarios non linéaires (graphe + validation + tests)
- [x] Éditeur de battlemap 3D (outils, calques, murs, lumières, templates)
- [ ] LOS / occlusion fog par vision token + portes
- [ ] Sync carte réseau (deltas, autorité MJ, fog filtré joueur)
- [ ] Tokens image (avatars PNG) + import UVTT
- [ ] Multijoueur réseau à 2 PC testé bout en bout
- [ ] Synchronisation sauvegardes cloud

---

## Licence

À définir.
