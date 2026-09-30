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
│   │   │   ├── editor_input_handler.gd    # Dispatch souris/clavier
│   │   │   ├── editor_save_controller.gd  # Politiques de sauvegarde
│   │   │   ├── editor_tool_handlers.gd    # Création d'éléments par outil
│   │   │   └── editor_view_controller.gd  # Zoom/pan/projection
│   │   ├── session/               # UI session (view-model, panneaux)
│   │   ├── multiplayer/           # MultiplayerManager, WebRTCP2P
│   │   └── tests/                 # Tests headless
│   ├── scenes/                    # Scènes Godot (.tscn)
│   ├── data/                      # JSON scénarios, cartes, props
│   └── assets/                    # Illustrations, portraits
├── server/                        # Serveur Node.js (TypeScript)
│   └── src/
│       ├── pooling/               # Serveur WebSocket (matchmaking)
│       ├── lobby/                 # RoomManager, types
│       ├── mcp/                   # Serveur MCP (MJ IA)
│       ├── narrative/             # PhrasePools, ActionResolution, WorldState, QuestManager
│       └── ai-gm.ts               # Façade MJ IA (< 400 lignes)
├── data/
│   └── schemas/                   # Contrat de données partagé (JSON Schema)
│       ├── character.json
│       ├── scenario.json
│       ├── map.json
│       └── bot.json
├── tools/                         # Scripts d'outillage (generate_*, capture_*, etc.)
├── scripts/                       # Scripts de lancement (play-godot*, run_tests, etc.)
└── docs/
    ├── ARCHITECTURE.md            # Ce document
    ├── STACK.md                   # Stack technique
    └── archive/                   # Audits ponctuels archivés
```

## Diagramme des dépendances

```
┌─────────────────────────────────────────────────────┐
│                    UI / Scènes                       │
│  session_shell, map_complex_editor, hub, panels...   │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              SessionViewModel                        │
│         (diff/signaux, pont état → UI)               │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              game/scripts/core/                      │
│  ┌─────────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ persistence │ │  rules   │ │     session      │  │
│  │  JsonStore  │ │   Dice   │ │  SessionState    │  │
│  │  Repos      │ │  Stats   │ │  TurnManager     │  │
│  └─────────────┘ └──────────┘ │  Inventory       │  │
│                               └──────────────────┘  │
│  ┌─────────────┐ ┌──────────────────────────────┐   │
│  │    maps     │ │        navigation            │   │
│  │  MapFog     │ │  SemanticMove, Investigation │   │
│  │  MapVision  │ │  QuestNavigation, SceneGraph │   │
│  └─────────────┘ └──────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              data/schemas/ (contrat)                 │
│        character.json, scenario.json, map.json       │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│              server/src/ (Node.js)                   │
│  ┌─────────┐ ┌───────┐ ┌─────┐ ┌─────────────────┐  │
│  │ pooling │ │ lobby │ │ mcp │ │    narrative     │  │
│  │  WS     │ │ rooms │ │ LLM │ │ PhrasePools      │  │
│  │         │ │       │ │     │ │ ActionResolution │  │
│  └─────────┘ └───────┘ └─────┘ │ WorldState       │  │
│                                │ QuestManager     │  │
│                                └─────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Principes directeurs

1. **`core/` est pur** : aucune dépendance `Node`, `@onready`, ou autoload. Tout est testable isolément.
2. **Un seul contrat** : `data/schemas/` est la source de vérité pour les structures partagées client/serveur.
3. **Façades minimales** : les autoloads (`GameData`, `MapData`) ne font que déléguer aux modules `core/`.
4. **Fichiers < 400 lignes** : un fichier = une responsabilité.
5. **Signaux pour l'UI** : `SessionViewModel` émet uniquement ce qui a changé (pas de rebuild complet).

## Règles de migration

- Quand vous extrayez une fonction de `game_data.gd` vers `core/`, laissez une délégation d'un ligne dans la façade.
- Les modules `core/session/`, `core/maps/`, `core/navigation/` sont **statiques** : ils opèrent sur un `game: Dictionary` passé en paramètre.
- Les repositories sont instanciables avec un signal `changed` pour notifier l'UI.
