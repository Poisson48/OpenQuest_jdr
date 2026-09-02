# Cartes interactives OpenQuest — Architecture dual-mode

> Implémenté : septembre 2026 · Branche `gestion-mj`  
> Complète [INTERACTIVE_MAPS_STRATEGY.md](./INTERACTIVE_MAPS_STRATEGY.md)

---

## 1. Vue d'ensemble

OpenQuest propose **deux modes de carte** coexistent sans régression :

| Mode | Classe | Usage |
|------|--------|-------|
| **Simple** (`simple`) | `SimpleMapRenderer` → `InteractiveMap` | Cartes pixel/tuiles, monde, enquête, Naheulbeuk-style |
| **Complexe** (`complex`) | `ComplexMapEngine` | VTT battlemap : image, tokens, grille, fog, effets, zones |

Le MJ choisit le mode **par carte** via le sélecteur session (persisté dans `active_game.mapModeOverrides`).

---

## 2. Architecture moteur (mode complexe)

```
MapPanel (UI session)
├── SimpleMapRenderer     ← mode simple (inchangé)
└── ComplexMapEngine      ← SubViewportContainer
        └── SubViewport
              └── Camera (Node2D — pan/zoom)
                    ├── Background (Sprite2D — PNG ou tuiles générées)
                    ├── GridLayer
                    ├── ZonesLayer      ← cercles/rects animés
                    ├── TokensLayer       ← MapTokenNode (Area2D draggable)
                    ├── EffectsLayer      ← MapEffectInstance (GPUParticles2D + aura)
                    └── FogLayer          ← masque cellulaire (MJ voit tout)
        Atmosphere + Vignette (Control overlay)
```

**Ordre de rendu :** fond → grille → zones → tokens → effets → fog → UI.

### Extensibilité

- **Effets** : presets JSON dans `MapEffectPresets` (`fire`, `smoke`, `magic`, `rain`) — ajouter une entrée + factory.
- **Zones** : `{ shape, x, y, radius, label, color }` dans `mapPlayState.zones`.
- **Triggers** : `effect.triggered` bool + bouton « ▶ Déclencher » (stub timeline future).
- **Plugins futurs** : brancher sur `EffectsLayer` / `ZonesLayer` sans toucher `SimpleMapRenderer`.

---

## 3. Schéma données

### Carte (`maps.json`)

```json
{
  "schemaVersion": 2,
  "renderMode": "simple | complex",
  "backgroundImage": "user://map_assets/map-xxx.png",
  "fogEnabled": true,
  "grid": { "size": 70, "opacity": 0.22, "color": "#ffffff", "enabled": true },
  "atmosphere": { "enabled": false, "tint": "#1a1410", "opacity": 0.25, "vignette": 0.15 }
}
```

### État session (`mapPlayState[mapId]`)

```json
{
  "tokens": [{ "id", "x", "y", "kind", "memberId", "label", "hp", "maxHp" }],
  "fogRevealed": ["3,4", "4,4"],
  "effects": [{ "id", "type", "preset", "x", "y", "radius", "triggered", "label" }],
  "zones": [{ "id", "shape", "x", "y", "radius", "label", "color" }],
  "viewState": { "zoom", "panX", "panY" },
  "selectedTokenId": ""
}
```

---

## 4. Multijoueur

- `GameData.save_map_play_and_sync()` sauvegarde + `MultiplayerManager.broadcast_state()` si hôte MJ P2P.
- État complet `mapPlayState` inclus dans `active_game` synchronisé.
- **Gap restant :** deltas optimisés (`map_delta`), validation autorité MJ sur moves joueur, resync partiel à la reconnexion.

---

## 5. Tests

```powershell
D:\git\OpenQuest_jdr\scripts\play-godot.ps1 --headless --script res://scripts/tests/map_mode_test.gd
```

---

## 6. Test manuel

### Mode simple
1. Lancer Godot → nouvelle partie avec `demo-taverne`.
2. Vérifier grille tuiles, placement tokens, navigation monde (si applicable).
3. Badge **▦ Simple** affiché.

### Mode complexe
1. En session, sélecteur **⚙️ Complexe**.
2. Placer un token PJ (toolbar ⚔️).
3. Placer effets 🔥 💨 ✨ ; cliquer **▶ Déclencher**.
4. Outil 🌫️ : révéler fog (MJ voit tout, simuler joueur via `is_gm_view_for_map`).
5. Zone ⭕ : marqueur de sort.
6. Pan molette / glisser / snap grille.

### Import PNG (Hub)
- `MapData.import_background_image(map_id, path)` — copie vers `user://map_assets/`.

---

## 7. Positionnement concurrentiel (honest)

### ✅ Implémenté (fondation crédible)

| Feature | Roll20 | Foundry | Owlbear | **OpenQuest** |
|---------|--------|---------|---------|---------------|
| Battlemap image | ✅ | ✅ | ✅ | ✅ (import PNG) |
| Grille configurable | ✅ | ✅ | ✅ | ✅ |
| Tokens drag | ✅ | ✅ | ✅ | ✅ (complex) |
| Fog MJ/joueur | ✅ | ✅ | ✅ | ✅ (cellulaire) |
| Particules / FX | ⚠️ | ✅ | ❌ | ✅ (3 presets + trigger) |
| Zones AOE | ✅ | ✅ | ⚠️ | ✅ (foundation) |
| Carte monde campagne | ❌ | ⚠️ | ❌ | ✅★ (mode simple) |
| P2P sans serveur jeu | ❌ | ❌ | ❌ | ✅ (sync état complet) |
| Mode enquête | ❌ | ❌ | ❌ | ✅★ |

### ❌ Manquant (roadmap Phases 2–6)

- Éclairage dynamique / LOS / murs
- Import Universal VTT (.dd2vtt)
- Règle de mesure, ping, dessin éphémère
- Tokens image (avatars PNG)
- Initiative overlay carte
- Deltas réseau optimisés + permission joueur
- Marketplace / modules
- Hex grid, audio spatial

### 🎯 Différenciateur OpenQuest

Monde ↔ scènes + enquête progressive + intégration scénario/MJ IA + P2P — **unique** vs VTT generalistes. Le mode complexe ferme l'écart **battlemap** ; le mode simple préserve la force **campagne**.

---

*OpenQuest JDR — dual-mode cartes interactives.*
