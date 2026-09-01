# OpenQuest JDR

> Créateur et session de jeu de rôle — **POC HTML jouable** + prototype multijoueur Godot en cours.

**OpenQuest** permet de créer des personnages, scénarios et cartes, puis de jouer en solo ou à plusieurs (local) avec un MJ humain ou une **MJ IA**. Les données sont sauvegardées dans le navigateur (`localStorage`).

| Version | Statut | Lancement |
|---------|--------|-----------|
| **POC HTML** | ✅ Jouable | Double-clic sur `index.html` ou `./ouvrir-openquest.sh` |
| **Client Godot + serveur Node** | 🚧 Prototype | Voir [Démarrage technique](#démarrage-technique-godot--serveur) |

---

## Fonctionnalités du POC HTML

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

### Aucune installation requise
Le POC tourne entièrement dans le navigateur. Aucun Node, npm ou Godot nécessaire pour jouer.

---

## Lancer le POC HTML

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./ouvrir-openquest.sh
```

Ou ouvrir directement **`index.html`** dans Chrome / Firefox / Edge.

> Les sauvegardes restent sur la machine locale (navigateur). Pour repartir de zéro : vider les données du site dans les paramètres du navigateur.

---

## Structure du projet

```
OpenQuest_jdr/
├── index.html              # Point d'entrée du POC
├── ouvrir-openquest.sh     # Lance le POC dans le navigateur
├── css/
│   └── style.css           # Thèmes, cartes, session de jeu
├── js/
│   ├── app.js              # Navigation, onglets
│   ├── storage.js          # Persistance localStorage
│   ├── characters.js       # Fiches personnages
│   ├── adventure-roster.js # Roster aventure
│   ├── investigation-roster.js
│   ├── scenarios.js        # Scénarios et scènes
│   ├── bots.js             # Compagnons IA
│   ├── maps.js             # Éditeur et cartes en session
│   ├── dice.js             # Lanceur de dés
│   ├── ai-gm.js            # MJ IA
│   ├── npc-ai.js           # PNJ IA
│   └── game.js             # Session de jeu
├── game/                   # Client Godot 4 (prototype)
├── server/                 # Serveur WebSocket Node.js
├── docs/                   # Documentation
├── scripts/                # Setup dev
└── poc/                    # Références / exports
```

---

## Démarrage technique (Godot + serveur)

> Optionnel — pour le prototype multijoueur réseau, pas pour le POC HTML.

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
2. Lancer `scenes/main.tscn`
3. Flèches clavier pour se déplacer

Pour le réseau local, adapter `server_url` dans `game/scripts/network_client.gd`.

---

## Contributeurs

| Qui | GitHub | Rôle |
|-----|--------|------|
| **Poisson** | [@Poisson48](https://github.com/Poisson48) | Godot, serveur Node, infra |
| **AslanUsko** | [@AslanUsko](https://github.com/AslanUsko) | POC HTML, règles JDR, design, cartes |

### Workflow Git

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
git checkout -b poc/ma-fonctionnalite   # ou game/..., docs/...
# … modifications …
git commit -m "Description claire"
git push origin poc/ma-fonctionnalite
# → Pull Request sur main
```

| Zone | Fichiers | Qui |
|------|----------|-----|
| POC HTML | `index.html`, `css/`, `js/` | AslanUsko |
| Jeu réseau | `game/`, `server/` | Poisson |
| Documentation | `docs/` | Les deux |

---

## Documentation

| Fichier | Contenu |
|---------|---------|
| [docs/COLLABORATION.md](docs/COLLABORATION.md) | Git, branches, conflits, routine à deux |
| [docs/STACK.md](docs/STACK.md) | Architecture technique |
| [docs/IA_POUR_ASLANUSKO.md](docs/IA_POUR_ASLANUSKO.md) | Guide IA pour le POC HTML |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Résumé contribution |

---

## Feuille de route

- [x] POC HTML jouable (personnages, scénarios, bots, cartes, MJ IA)
- [x] Mode enquête + cartes investigation
- [x] Carte du monde, brouillard de guerre, navigation monde ↔ lieux
- [ ] Portage des règles du POC dans Godot
- [ ] Multijoueur réseau complet
- [ ] Synchronisation sauvegardes (hors localStorage)

---

## Licence

À définir.
