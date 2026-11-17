# OpenQuest JDR

Client **Godot 4.7** + serveur **Node.js** (pooling WebSocket / matchmaking P2P).

Création de personnages, scénarios et cartes, puis session solo ou à plusieurs (MJ humain ou MJ IA). Persistance locale Godot (`user://`).

| Composant | Statut | Lancement (Windows) |
|-----------|--------|---------------------|
| **Client Godot** | Jouable (démos Valbois + Crypte) | `.\scripts\play-godot.ps1` |
| **Serveur Node (pooling)** | Opérationnel (LAN) | `.\scripts\dev-server.sh` ou `cd server && npm run dev` |

> **État des lieux** : section [TODO](#todo--état-des-lieux) ci-dessous (source de vérité). Index et statuts de la documentation : [docs/README.md](docs/README.md).
> **Chantier de refactorisation en cours** (lancé le 2026-11-17) : phase 0 livrée, phase 1 en cours — index, plan, audits, baseline et outillage dans [docs/refactor/README.md](docs/refactor/README.md).

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
- **Carte 2.5D & monde de zones (façon Dofus)** — terrain 3D simple (relief, 5 matières de sol dont neige/sable, eau, ambiances), 80 objets 3D (bâtiments, intérieurs, PNJ, toits/façades) avec import GLB, **onglet Monde multi-mondes** (zones de tailles différentes et thèmes habités, liens de bords, création/nommage/suppression/export d'un monde, Tester en session), figurines 3D de tokens, session avec **déplacement au clic (Pas/D)**, **mini-carte (C)** et carte du monde nommée (M). **Construction façon Sims / Tiny Glade** : murs 3D (hauteur) connectés (coins L, T), **tracé organique freehand** (Catmull-Rom), pièces + coins, dallage, toits, portes/fenêtres avec ouvertures réelles, maison rapide, escaliers, clôtures, chemins, mobilier et **végétation au pinceau** — avec collisions RPG et **intérieurs liés de taille indépendante** (outil 🚪 Intérieur). **Éclairage** : presets Jour/Matin/Coucher/Nuit/Donjon, soleil coloré + ombres, torches/lanternes vacillantes et fog de profondeur. **Navigation 3D éditeur** : orbite au clic milieu, pan Maj+clic milieu, zoom molette. Guide : [`docs/GUIDE_CARTE_25D.md`](docs/GUIDE_CARTE_25D.md).
- **Scénarios non linéaires** — graphe de scènes, navigation MJ
- **Serveur pooling** — salons + signalisation ; jeu P2P ENet en LAN (pas Internet)

> **Archivé (2026-11-17)** : le **moteur de jeu TypeScript** et le **serveur MCP (MJ IA)** sont archivés dans [`server/legacy/`](server/legacy/README.md) — hors compilation et hors imports. Le serveur Node ne fait plus que du pooling ; toute la logique de jeu est côté hôte Godot. Voir aussi [docs/MCP.md](docs/MCP.md) (bandeau d'archive) et [docs/refactor/AUDIT_SERVEUR.md](docs/refactor/AUDIT_SERVEUR.md).

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

# Carte 2.5D / monde de zones
.\scripts\play-godot.ps1 res://scenes/debug/carte_25d_boot.tscn          # éditeur + monde de démo
.\scripts\play-godot.ps1 res://scenes/debug/carte_25d_session_boot.tscn  # session sur le monde de démo
.\scripts\play-godot.ps1 res://scenes/debug/construction_demo.tscn      # démo construction (maisons, toits, clôtures)
.\scripts\play-godot.ps1 res://scenes/debug/auvent_demo.tscn           # démo auvent de façade
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
├── server/               # Pooling WebSocket (TypeScript) — moteur de jeu TS archivé dans server/legacy/
├── data/                 # Jeu de données partagé (scénarios historiques, bots, tiles)
├── docs/                 # Audits, architecture, cartes, multijoueur, chantier refactor (docs/refactor/)
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

> Le serveur ne fait que **pooling + matchmaking + signalisation** : aucune logique de jeu. Le moteur de jeu TypeScript (état de partie, bots, MJ IA, MCP) est **archivé** dans [`server/legacy/`](server/legacy/README.md) et n'est plus compilé ni importé (voir [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md)).

### Tests headless

```bash
# Runner complet (sans --quit : les tests asynchrones doivent finir leurs assertions)
GODOT_BIN=/chemin/vers/godot ./scripts/run_tests.ps1
./scripts/run_tests.ps1 -Filter '^(map_|world_|session_)'   # sous-ensemble
./scripts/run_tests.ps1 -IncludeShots                      # captures d'écran (fenêtré)
```

Le runner applique un timeout par test, vérifie la sortie `PASS`/`FAIL` et
**ignore par défaut les tests de capture** (qui nécessitent une fenêtre).

```bash
# Exemples directs (Godot dans le PATH ou Flatpak)
godot --headless --path game -s res://scripts/tests/map_camera_test.gd
godot --headless --path game -s res://scripts/tests/map_mode_test.gd
godot --headless --path game -s res://scripts/tests/quest_navigation_test.gd
godot --headless --path game -s res://scripts/tests/valbois_player_hud_test.gd
```

Suites utiles : `map_*`, `world_*`, `session_*`, `quest_navigation_test`,
`scenario_editor_test`, `valbois_*`.
Le runner reconnaît les tests historiques qui écrivent un JSON (`"ok": true`) ou
`ALL_OK=true`.

**Échec connu, hors parcours carte 2.5D** :
- `webrtc_pooling_e2e_test` : nécessite le serveur de pooling LAN (sinon timeout de connexion).

---

## Architecture (bref)

```
Client Godot 4.7                    Serveur Node (pooling)
├── GameData / MapData (user://)    ├── Salons + codes
├── Session MJ | HUD joueur         └── Signalisation P2P
├── ComplexMapEngine3D / Simple
└── ENet (hôte = MJ)  ◄──────────►  clients (LAN)
```

Détails : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md), [docs/INTERACTIVE_MAPS.md](docs/INTERACTIVE_MAPS.md).  
Note : `docs/STACK.md` est un **document historique** (bandeau en tête) qui décrit l'ancien modèle « serveur autoritaire » ; le runtime réel est **hôte Godot autoritaire + pooling**, et le moteur de jeu TS est archivé dans `server/legacy/`.

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
- [x] Suite de tests cartes (dont `map_camera_test`) — voir aussi [docs/archive/AUDIT_CARTES.md](docs/archive/AUDIT_CARTES.md)

### Chantier de refactorisation (lancé le 2026-11-17)

Suivi détaillé : [docs/refactor/README.md](docs/refactor/README.md) · plan et ADR : [docs/refactor/PLAN_REFACTORISATION.md](docs/refactor/PLAN_REFACTORISATION.md).

- [x] **Phase 0 — filets & vert** : porte de compilation client (scripts + scènes, 0 échec), `tools/refactor/verify.ps1` (4 étapes) + `metrics.ps1` + socle rapide de 27 tests, build serveur réparé, 13 fichiers TS morts archivés, 6 scripts cassés réparés ou supprimés, 3 audits + inventaire + baseline, docs réalignées
- [x] **Phase 1 — purge du code mort** : `core/` mort, 4 modules d'éditeur morts, 6 scripts legacy de `maps/`, sonde `zz_probe_grid.gd` — −3 276 lignes au total
- [x] **Phase 2 — contrats & cœur client** : tests de contrat (SessionViewModel 30, GameData 40, contrat éditeur gelé), `game_data.gd` 4 586 → 4 199 l. (session_model, game_storage, turn_flow, roster), `map_data.gd` 2 287 → 1 954 l. (image + schéma) ; reste 2.8c cartes de démo
- [x] **Phase 3 (partielle)** — éditeur de scénario : routeur de liens pur dans `core/graph/`, style et contrôleur de graphe sortis, `scenario_editor.gd` 3 204 → 2 386 l. ; reste panneaux (3.4-3.5)
- [x] **Phase 4 (partielle, perf)** — synchro incrémentale : couches sales + `MapMeshes3D.sync()` diff-based → commit d'édition **1 506 → 45 ms** (−97 %), release −50 % (garde-fou `editor_commit_perf_test`) ; reste 4d-4f et les vagues d'extraction
- [x] **Phase 5 (partielle)** — serveur : une seule implémentation de dés (TS archivé), validateur `data/schemas` (gate bot/ruleset) + rapport de dérive, contrat de protocole pooling v2 (302 vérifications) ; reste l'alignement des schémas en dérive
- [x] **Phase 6 (partielle)** — CI GitHub Actions (serveur + Godot + data), index `docs/README.md` (27 rapports archivés, 422 liens vérifiés), règles de refactor dans `CONTRIBUTING.md` ; reste métriques finales

### En cours / WIP récent

- [ ] **Qualité cartes Valbois HD** — fond parfois soft / cache `user://map_assets` + import Godot (`*.import`, compression 3D) ; recharger les PNG `res://assets/maps/` proprement
- [ ] **Clarté UI / bugs visuels** — audit dédié : [docs/archive/AUDIT_UI_CLARTE.md](docs/archive/AUDIT_UI_CLARTE.md) *(disponible — base de travail pour AslanUsko)* ; s’appuyer aussi sur [docs/UI_UX.md](docs/UI_UX.md)
- [ ] **HUD joueur vs session MJ** — divergences de layout, marges carte sous le HUD, messages d’échelle / tooltips lieux
- [ ] **Token Kael** — échelle découpe (`scale` village / place), un seul token (dédoublonnage party ↔ `playDefaults` encore fragile)
- [ ] Correctifs caméra perspective / VTT orthographique restants ([AUDIT_CARTES](docs/archive/AUDIT_CARTES.md) P1 — partie déjà traitée dans le moteur)

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
| [docs/README.md](docs/README.md) | **Index complet de la documentation** — catégories et statuts (à jour / historique / obsolète) |
| [docs/refactor/README.md](docs/refactor/README.md) | **Chantier de refactorisation** — index, plan, audits, baseline, outillage |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Architecture réelle + cible (runtime hôte Godot autoritaire + pooling) |
| [docs/archive/AUDIT_CARTES.md](docs/archive/AUDIT_CARTES.md) | Audit moteur diorama / caméra / P1–P3 *(archivé)* |
| [docs/archive/AUDIT_UI_CLARTE.md](docs/archive/AUDIT_UI_CLARTE.md) | Audit clarté UI *(archivé, disponible)* |
| [docs/archive/MAP_DIORAMA_PLAN.md](docs/archive/MAP_DIORAMA_PLAN.md) | Plan diorama 2.5D *(archivé — appliqué)* |
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
