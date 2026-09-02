# Plan d'action — POC HTML → Jeu Godot

> Analyse du POC poussé par AslanUsko (commit `92d976a`).  
> Objectif : porter progressivement le jeu jouable HTML vers Godot + serveur Node, sans tout réécrire d'un coup.

---

## Inventaire du POC actuel

Le POC est **à la racine du repo** (pas dans `poc/`) :

| Fichier | Lignes | Rôle |
|---------|--------|------|
| `index.html` | ~1 600 | Structure UI (accueil, onglets, formulaires, session) |
| `css/style.css` | ~4 000 | Thème fantasy (or `#c9a227`, fond sombre, cartes, session) |
| `js/dice.js` | 57 | Moteur de dés (`2d6+3`, `1d20`) |
| `js/storage.js` | 34 | Persistance `localStorage` |
| `js/characters.js` | 190 | CRUD fiches personnages |
| `js/adventure-roster.js` | 107 | Roster aventure |
| `js/investigation-roster.js` | 533 | Roster enquête |
| `js/scenarios.js` | 1 142 | Scénarios, scènes, PNJ, démos intégrées |
| `js/bots.js` | 1 090 | Compagnons bots + archétypes |
| `js/npc-ai.js` | 325 | PNJ improvisés |
| `js/ai-gm.js` | 1 831 | MJ IA (moteur narratif par règles, **pas d'API externe**) |
| `js/maps.js` | 1 872 | Éditeur + cartes session (monde, local, fog, zoom) |
| `js/game.js` | 1 601 | Session de jeu (tours, journal, setup, fin de partie) |
| `js/app.js` | 216 | Navigation entre vues |

### Fonctionnalités POC à préserver

- 3 modes : **one-shot**, **campagne longue**, **enquête**
- Création : personnages, scénarios, bots, cartes (local + monde)
- Session : groupe jusqu'à 10, MJ humain ou **MJ IA**, journal, timer, dés
- Cartes en partie : tokens, marqueurs, brouillard de guerre, navigation monde ↔ lieu
- Sauvegarde locale navigateur

### État Godot actuel

- Squelette minimal : carrés qui bougent via WebSocket
- Aucune règle JDR, aucune UI du POC

---

## Principe de migration

```
POC HTML (référence permanente, AslanUsko continue dessus)
        │
        ▼
  data/ JSON partagé  ←── schémas extraits du JS
        │
   ┌────┴────┐
   ▼         ▼
 Godot      Node
 (affichage, (autorité multijoueur,
  inputs)     dés, sauvegardes, MJ IA)
```

**Règle d'or :** ne pas porter fichier par fichier. Extraire d'abord les **données** et les **règles**, puis reconstruire l'UI en Godot.

Le POC HTML reste la **référence visuelle et gameplay** tant que Godot n'a pas rattrapé une feature.

---

## Architecture cible

```
game/                          server/
├── scenes/                    ├── src/
│   ├── main_menu.tscn         │   ├── index.ts          (WebSocket)
│   ├── character_editor.tscn  │   ├── game_session.ts   (état partie)
│   ├── scenario_picker.tscn   │   ├── dice.ts           (lancer côté serveur)
│   ├── session/               │   ├── ai_gm.ts          (port ai-gm.js)
│   │   ├── session.tscn       │   └── storage.ts        (fichiers JSON / DB)
│   └── maps/                  └── data/                   (sync avec game/data/)
│       ├── map_editor.tscn
│       └── map_view.tscn
├── scripts/
│   ├── data/                  # Charge les JSON
│   ├── dice.gd                # Affichage seulement en solo local
│   ├── multiplayer/
│   │   └── multiplayer_manager.gd   # Pooling + ENet P2P
│   └── main_menu.gd
└── data/                      # Schémas partagés
    ├── characters.schema.json
    ├── scenarios/
    └── tilesets/
```

---

## Phases de développement

### Phase 0 — Fondations (Poisson, ~2-3 jours) ⬅ **COMMENCER ICI**

**But :** poser les briques communes avant toute UI Godot.

| Tâche | Détail | Source POC |
|-------|--------|------------|
| Extraire les schémas JSON | Personnage, scénario, carte, état de partie | `characters.js`, `scenarios.js`, `maps.js`, `game.js` L983 |
| Créer `shared/` ou `data/` | Fichiers JSON + JSON Schema | Démos dans `scenarios.js` |
| Porter `dice.js` → `server/src/dice.ts` | Identique, tests unitaires | `js/dice.js` |
| Porter `dice.js` → `game/scripts/dice.gd` | Pour mode solo offline futur | `js/dice.js` |
| Définir `GameState` TypeScript | Miroir de `game.js` state | `game.js` |
| Étendre protocole WebSocket | `dice_roll`, `game_action`, `state_sync` | `server/src/types.ts` |
| Thème Godot | Couleurs CSS → Theme resource | `css/style.css` `:root` |

**Livrable :** données de démo jouables en JSON + dés fonctionnels côté serveur.

---

### Phase 1 — Menu + fiches personnages (Poisson Godot, ~1 semaine)

**But :** première UI Godot utile, la plus simple du POC.

| POC | Godot |
|-----|-------|
| `home-view` | `scenes/main_menu.tscn` |
| `characters.js` | `scenes/character_editor.tscn` + `scripts/character_data.gd` |
| Onglet personnages | Liste + formulaire (nom, race, classe, 6 stats, PV, CA) |

**Hors scope :** cartes, session, IA.

**Test :** créer un perso, le sauver en JSON local (`user://`).

---

### Phase 2 — Scénarios + lancement de partie (Poisson, ~1-2 semaines)

| POC | Godot |
|-----|-------|
| `scenarios.js` | `data/scenarios/*.json` + `scenario_picker.tscn` |
| Setup partie (`game.js` setup) | `scenes/session/setup.tscn` |
| Import démos intégrées | Extraire `DEMO_SCENARIOS` / `INVESTIGATION_SCENARIOS` en JSON |

**Mode initial :** solo + **MJ humain uniquement** (pas d'IA encore).

| POC | Godot |
|-----|-------|
| Journal de partie | `RichTextLabel` + log array |
| Saisie d'action | `LineEdit` + bouton envoyer |
| Timer session | `Timer` node |
| Lanceur de dés | Boutons d4–d20 → message WS `dice_roll` |

**Test :** lancer une partie one-shot, écrire dans le journal, lancer un d20.

---

### Phase 3 — Cartes (Poisson, ~2-3 semaines) ⚠️ gros morceau

Le module `maps.js` (1 872 lignes) est le **plus complexe** visuellement.

**Découpage :**

| Sous-phase | Contenu | Difficulté |
|------------|---------|------------|
| 3a | Affichage carte locale (TileMap, tiles du POC) | Moyenne |
| 3b | Placement tokens en session | Moyenne |
| 3c | Zoom + pan | Facile |
| 3d | Carte du monde + tuiles WORLD_TILES | Haute |
| 3e | Brouillard de guerre (`explored[]`, `revealRadius`) | Haute |
| 3f | Liens monde → lieu (`locationLinks`, 🚪) | Haute |
| 3g | Éditeur de cartes | Très haute (peut rester HTML au début) |

**Recommandation :** garder l'**éditeur de cartes dans le POC HTML** pendant un temps. Godot ne fait que **lire et afficher** les cartes JSON exportées depuis le navigateur.

**Structure carte (depuis `maps.js`) :**
```json
{
  "id": "map-...",
  "name": "Taverne",
  "mapKind": "local",
  "roster": "general",
  "width": 16,
  "height": 12,
  "tiles": ["grass", "floor", ...],
  "markers": [{ "type": "party", "x": 4, "y": 6 }],
  "locationLinks": []
}
```

---

### Phase 4 — MJ IA + bots (Poisson serveur, ~2 semaines)

Le MJ IA du POC est **100 % local par règles** (`ai-gm.js`, `bots.js`) — pas d'OpenAI. C'est portables.

| Module | Où porter | Priorité |
|--------|-----------|----------|
| `ai-gm.js` | `server/src/ai_gm.ts` | Haute — logique pure |
| `bots.js` | `server/src/bots.ts` | Moyenne |
| `npc-ai.js` | `server/src/npc_ai.ts` | Basse |

**Pourquoi côté serveur :** anti-triche, sync multijoueur, un seul état narratif.

**Godot reçoit :** messages `gm_narration`, `bot_action`, `suggest_roll` via WebSocket.

**Ordre :**
1. Porter `classifyAction` + `suggestRoll` + `computeDC`
2. Porter pools de narration (`openingNarration`, `resolveAction`)
3. Brancher les bots compagnons

---

### Phase 5 — Multijoueur réel (Poisson, ~1-2 semaines)

Remplacer le multijoueur **local** du POC (plusieurs humains sur un écran) par le réseau.

| Événement WS | Direction | Contenu |
|--------------|-----------|---------|
| `join_game` | C→S | roomId, playerId, characterId |
| `game_state` | S→C | état complet de la partie |
| `player_action` | C→S | texte d'action |
| `dice_roll` | C→S / S→C | formule + résultat (serveur autoritaire) |
| `map_token_move` | C→S | mapId, tokenId, x, y |
| `chat` | C→S / S→C | message journal |

**Le POC HTML** reste jouable en solo local pendant ce temps.

---

### Phase 6 — Mode enquête + polish (les deux, ~2 semaines)

| POC | Action |
|-----|--------|
| `investigation-roster.js` | Filtre roster `investigation` dans l'éditeur perso |
| Tuiles / marqueurs enquête | Tileset séparé (`INVESTIGATION_TILES`) |
| Scénarios enquête démo | JSON `inv-demo-serpent-noir` etc. |
| Export résumé de partie | PDF ou markdown (était dans `game.js`) |

**AslanUsko :** valider le rendu visuel, ajuster textes, scénarios démo.  
**Poisson :** implémentation Godot.

---

## Mapping module par module

| Module JS | Difficulté | Destination | Phase |
|-----------|------------|-------------|-------|
| `storage.js` | ★ | `server/` persistance + `user://` Godot | 0 |
| `dice.js` | ★ | `server/dice.ts` + `game/dice.gd` | 0 |
| `characters.js` | ★★ | Godot UI + JSON | 1 |
| `app.js` | ★★ | Scènes Godot (pas de port 1:1) | 1 |
| `adventure-roster.js` | ★★ | Godot liste perso/scénario | 1-2 |
| `scenarios.js` | ★★★ | JSON + Godot picker | 2 |
| `game.js` (setup) | ★★★ | Godot setup session | 2 |
| `game.js` (session) | ★★★★ | Godot session + WS | 2-5 |
| `npc-ai.js` | ★★★ | `server/npc_ai.ts` | 4 |
| `bots.js` | ★★★★ | `server/bots.ts` | 4 |
| `ai-gm.js` | ★★★★★ | `server/ai_gm.ts` | 4 |
| `maps.js` (lecture) | ★★★★ | Godot TileMap | 3 |
| `maps.js` (éditeur) | ★★★★★ | Garder HTML ou Godot tardif | 3g / 6 |
| `investigation-roster.js` | ★★★ | Extension phase 6 | 6 |
| `css/style.css` | ★★ | Godot Theme | 0-1 |

---

## Schémas de données à extraire en priorité

### Personnage (`characters.js`)
```json
{
  "id": "char-...",
  "name": "Aria",
  "race": "Humaine",
  "class": "Guerrière",
  "roster": "general",
  "stats": { "str": 14, "dex": 12, "con": 13, "int": 10, "wis": 11, "cha": 9 },
  "hp": 12,
  "ac": 15,
  "backstory": "..."
}
```

### État de partie (`game.js` L983)
```json
{
  "id": "game-...",
  "scenarioId": "demo-kharak",
  "mapIds": ["map-..."],
  "mode": "solo",
  "gmType": "human",
  "questFormat": "oneshot",
  "party": [],
  "currentSceneIndex": 0,
  "turnIndex": 0,
  "log": [],
  "status": "playing"
}
```

### Scénario (`scenarios.js`)
```json
{
  "id": "demo-kharak",
  "title": "...",
  "questFormat": "long",
  "roster": "general",
  "scenes": [{ "title": "...", "content": "..." }],
  "npcs": [{ "name": "...", "description": "..." }]
}
```

---

## Répartition Poisson / AslanUsko

| Poisson | AslanUsko |
|---------|-----------|
| Extraction JSON, serveur, Godot | Continuer le POC HTML (éditeur cartes, scénarios) |
| Phases 0 → 5 technique | Valider que le Godot « ressemble » au POC |
| Protocole réseau | Écrire / tester les scénarios démo |
| Tests perf Godot | Feedback gameplay (« le MJ IA répond bien ? ») |

**Workflow recommandé :** AslanUsko crée contenu dans le HTML → export JSON → Poisson importe dans `data/`.

---

## Premier sprint (cette semaine)

### Poisson — 3 tâches concrètes

1. **Extraire les scénarios démo en JSON**
   - Script Node one-shot qui lit `scenarios.js` ou copie manuelle des `DEMO_SCENARIOS`
   - Sortie : `data/scenarios/demo-kharak.json`, etc.

2. **Porter `dice.js` côté serveur**
   - `server/src/dice.ts` + test
   - Message WS `{ type: "dice_roll", formula: "1d20+3" }` → `{ type: "dice_result", ... }`

3. **Thème Godot + menu vide**
   - `game/theme/openquest_theme.tres` avec couleurs du CSS
   - `scenes/main_menu.tscn` : titre + 2 boutons (placeholder)

### AslanUsko — en parallèle

- Jouer au POC, noter ce qui est **indispensable** vs **nice to have**
- Exporter 1 scénario + 1 carte + 2 persos qu'elle a créés (même copier depuis localStorage)

---

## Ce qu'on ne porte PAS tout de suite

| Feature | Pourquoi attendre |
|---------|-------------------|
| Éditeur de cartes Godot | Très complexe — le HTML le fait déjà |
| MJ IA | Besoin de session + dés d'abord |
| Multijoueur réseau | Besoin d'état de partie stable |
| Mode enquête complet | Extension du mode aventure |
| Export PDF résumé | Cosmétique, fin de phase |

---

## Risques

| Risque | Mitigation |
|--------|------------|
| `maps.js` trop gros | Lecture seule Godot + éditeur HTML |
| `ai-gm.js` 1800 lignes | Port par fonctions, tests unitaires par action type |
| Divergence POC / Godot | `data/` JSON comme contrat unique |
| Conflits Git (AslanUsko sur HTML, Poisson sur game/) | Zones séparées, branches distinctes |
| PC lent AslanUsko | Elle reste sur le HTML navigateur |

---

## Critères de « POC porté » (Definition of Done)

- [ ] Créer un personnage dans Godot
- [ ] Choisir un scénario démo et lancer une partie solo
- [ ] Journal + dés fonctionnels
- [ ] Afficher une carte locale avec tokens
- [ ] MJ IA répond à une action (même qualité que HTML)
- [ ] 2 joueurs sur 2 PC via WebSocket
- [ ] Sauvegarde / reprise de partie

---

## Prochaine action immédiate

**Poisson :** Phase 0 — créer `data/` avec les JSON de démo + `server/src/dice.ts`.

**AslanUsko :** Liste des 5 features sans lesquelles le jeu n'est pas « son jeu ».
