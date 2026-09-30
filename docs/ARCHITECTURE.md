# Architecture OpenQuest JDR

Document de référence de l'architecture cible après refactoring (`refactor/st-refacto`).

## Vue d'ensemble

```
OpenQuest_jdr/
├── game/                          # Client Godot 4.7 (Forward+)
│   ├── scripts/
│   │   ├── core/                  # Logique métier pure (pas de Node, testable)
│   │   │   ├── persistence/       # JsonStore, repositories
│   │   │   ├── rules/             # Dice, Stats, CharacterRules
│   │   │   ├── session/           # SessionState, TurnManager, Inventory
│   │   │   ├── maps/              # MapRepository, MapFog, MapVision, Investigation
│   │   │   └── navigation/        # QuestNavigation, SceneGraph, SemanticMove
│   │   ├── maps/editor/           # Éditeur battlemap 3D (document + contrôleurs)
│   │   │   ├── map_edit_document.gd   # Modèle + historique undo/redo par deltas
│   │   │   ├── map_editor_tools.gd    # Machine à états des outils
│   │   │   ├── map_editor_overlay.gd  # Rendu 2D sélection/aperçus
│   │   │   └── panels/                # Inspector, Outliner, Library, History, Settings
│   │   ├── session/               # UI session de jeu (view-model + panneaux)
│   │   ├── multiplayer/           # MultiplayerManager, WebRTCP2P
│   │   └── autoload/              # Façades (GameData, MapData, ThemeColors, …)
│   ├── scenes/                    # Scènes .tscn
│   ├── data/                      # JSON scénarios, cartes, props, schemas
│   └── assets/                    # Illustrations, portraits
├── server/                        # Node.js + TypeScript
│   └── src/
│       ├── pooling/               # Serveur WebSocket, matchmaking par salons
│       ├── lobby/                 # RoomManager, types
│       ├── mcp/                   # GM server LLM
│       ├── narrative/             # Pools de phrases, mémoire anti-répétition
│       ├── resolution/            # Résolution d'actions
│       └── ai-gm.ts               # Moteur narratif (en cours de découpage)
├── data/schemas/                  # Contrat de données partagé client ↔ serveur
├── scripts/                       # Scripts de lancement et de test
│   ├── play-godot*.ps1            # Lancement instances Godot
│   ├── run_tests.ps1              # Runner unique tests Godot
│   ├── dev-server.sh              # Lancement serveur Node
│   ├── setup.sh                   # Installation environnement
│   └── ensure-webrtc-native.ps1   # Téléchargement extension WebRTC
├── tools/                         # Outils ponctuels (génération, capture, migration)
└── docs/                          # Documentation et audits
    └── archive/                   # Rapports ponctuels archivés
```

## Diagramme de dépendances

```
┌─────────────────────────────────────────────────────────────┐
│                    UI / Scènes Godot                        │
│  session/panels  hub/panels  maps/editor/panels  ui/        │
└─────────────────┬───────────────────────────────────────────┘
                  │ signaux / view-models
┌─────────────────▼───────────────────────────────────────────┐
│                  Autoloads (façades)                         │
│   GameData  MapData  MultiplayerManager  ThemeColors         │
└─────────────────┬───────────────────────────────────────────┘
                  │ délègue
┌─────────────────▼───────────────────────────────────────────┐
│                  game/scripts/core/                          │
│  persistence/  rules/  session/  maps/  navigation/          │
└─────────────────┬───────────────────────────────────────────┘
                  │ JsonStore
┌─────────────────▼───────────────────────────────────────────┐
│              Persistance locale (user://)                    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                  Client Godot                                │
└─────────────────┬───────────────────────────────────────────┘
                  │ WebSocket JSON (pooling)
┌─────────────────▼───────────────────────────────────────────┐
│                  server/src/                                 │
│  pooling/  lobby/  mcp/  narrative/  resolution/             │
└─────────────────────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│              data/schemas/ (contrat unique)                  │
└─────────────────────────────────────────────────────────────┘
```

## Principes

1. **Logique métier isolée** : `game/scripts/core/` ne dépend pas de Node ni de rendu.
2. **Façades autoload** : `GameData` et `MapData` délèguent aux modules `core/`.
3. **Contrat de données unique** : `data/schemas/` est la source de vérité pour les JSON échangés.
4. **Éditeur découplé** : `MapEditDocument` porte le modèle, les contrôleurs pilotent, l'overlay rend.
5. **Tests automatisés** : `scripts/run_tests.ps1` exécute les 30 tests Godot headless.
