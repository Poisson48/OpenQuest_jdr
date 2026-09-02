# OpenQuest JDR

> Créateur et session de jeu de rôle — client **Godot 4** + serveur **Node.js** (multijoueur WebSocket).

**OpenQuest** permet de créer des personnages, scénarios et cartes, puis de jouer en solo ou à plusieurs avec un MJ humain ou une **MJ IA**. Les données sont persistées localement (Godot `user://`).

| Composant | Statut | Lancement |
|-----------|--------|-----------|
| **Client Godot** | ✅ Jouable | Ouvrir `game/` dans Godot 4, F5 |
| **Serveur Node (pooling)** | ✅ Opérationnel | `cd server && npm run dev` |

---

## Fonctionnalités

### Modes de jeu
- **One-shot** — aventure courte
- **Campagne longue** — scénarios étendus + carte du monde
- **Enquête** — investigation avec roster et cartes dédiées

### Création de contenu
- **Personnages** — fiches aventure (race, classe, stats, PV, CA)
- **Enquêteurs** — roster investigation avec archétypes
- **Scénarios** — scènes, objectifs, PNJ liés
- **Bots compagnons** — archétypes IA pour compléter le groupe
- **Cartes** — éditeur de grilles :
  - scènes locales (donjons, tavernes, quartiers…)
  - **cartes du monde** (continents, villes, brouillard de guerre)
  - liens **monde → lieu** (entrée dans une ville, retour via sortie 🚪)

### Session de jeu
- Groupe jusqu'à 10 participants (humains + bots)
- **MJ IA** adaptatif ou **MJ humain**
- Journal de partie, dés intégrés, timer de session
- **Cartes interactives** en partie : placement des personnages, marqueurs, zoom, pan
- **Brouillard de guerre** sur les cartes du monde (révélation progressive)
- **PNJ IA** — génération et gestion de personnages improvisés

---

## Structure du projet

```
OpenQuest_jdr/
├── game/                   # Client Godot 4
├── server/                 # Serveur WebSocket Node.js
├── data/                   # Données JSON partagées (scénarios, bots, tuiles)
├── docs/                   # Documentation
└── scripts/                # Setup dev
```

---

## Démarrage

### Prérequis

| Outil | Version |
|-------|---------|
| Node.js | ≥ 20 |
| Godot | 4.4+ |

### Serveur

```bash
cd server
cp .env.example .env
npm install
npm run dev
```

Écoute sur `ws://0.0.0.0:8080`.

### Client Godot

1. Ouvrir `game/` dans Godot 4
2. Lancer `scenes/main.tscn` (F5)
3. Pour le multijoueur LAN : panneau **Salon multijoueur (P2P)** du menu principal (`ws://IP:8080`)

Setup initial après clone :

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
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
| [docs/INTERACTIVE_MAPS_STRATEGY.md](docs/INTERACTIVE_MAPS_STRATEGY.md) | Analyse concurrentielle VTT et feuille de route cartes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Résumé contribution |

---

## Feuille de route

- [x] Client Godot — menus, hub, persos, setup, session
- [x] Serveur Node — MJ IA (`ai-gm.ts`), bots, dés, sessions JSON
- [x] Serveur MCP — outils GM pour agents (`npm run mcp`)
- [x] Données JSON — `data/scenarios/`, `data/bots/`, `data/tiles.json`
- [ ] Éditeur de cartes Godot (aperçu basique fait)
- [ ] Multijoueur réseau à 2 PC testé bout en bout
- [ ] Synchronisation sauvegardes cloud

---

## Licence

À définir.
