# Cartes interactives OpenQuest — Architecture dual-mode

> Implémenté : septembre 2026 · Branche `gestion-mj`  
> Complète [INTERACTIVE_MAPS_STRATEGY.md](./INTERACTIVE_MAPS_STRATEGY.md)  
> Côté création, voir [MAP_EDITOR.md](./MAP_EDITOR.md) (outils, undo/redo, calques, templates)

---

## 1. Vue d'ensemble

OpenQuest propose **deux modes de carte** coexistent sans régression :

| Mode | Classe | Usage |
|------|--------|-------|
| **Simple** (`simple`) | `SimpleMapRenderer` → `InteractiveMap` | Cartes pixel/tuiles, monde, enquête, Naheulbeuk-style |
| **Complexe** (`complex`) | `ComplexMapEngine3D` | VTT **3D top-down** : battlemap, tokens 3D, fog, effets particules, zones, élévations |

Le MJ choisit le mode **par carte** via le sélecteur session (persisté dans `active_game.mapModeOverrides`).

---

## 2. Architecture moteur (mode complexe — **3D top-down**)

Vue par-dessus d'une **scène Godot 3D réelle** (ARPG / XCOM / Diablo-style), pas des astuces 2D.

```
MapPanel (UI session)
├── SimpleMapRenderer     ← mode simple 2D (inchangé)
└── ComplexMapEngine      ← SubViewportContainer
        └── SubViewport (3D activé)
              ├── WorldEnvironment (SSAO, ambient)
              ├── DirectionalLight3D (ombres dynamiques)
              ├── Camera3D (orthographique top-down ~52°, ou perspective/isométrique)
              └── Scene (Node3D)
                    ├── MapGround3D         ← PlaneMesh + texture PNG battlemap
                    ├── Elevations          ← PlaneMesh surélevés (PNG overlay)
                    ├── MapZone3D           ← disques AOE au sol
                    ├── MapToken3D          ← CylinderMesh + Sprite3D portrait, ombres réelles
                    ├── MapEffect3D         ← GPUParticles3D + OmniLight3D
                    └── MapFog3D            ← dalles 3D semi-transparentes
        Atmosphere + Vignette (Control overlay UI 2D)
```

**Rendu :** sol texturé → plateformes → zones → tokens (StaticBody3D, raycast drag) → particules 3D → fog 3D → overlays UI.

### Tokens 3D (`MapToken3D`)

- **CylinderMesh** avec ombres portées (`DirectionalLight3D`)
- **Sprite3D** billboard portrait (initiale PJ)
- Anneau de sélection 3D (TorusMesh émissif)
- Drag par **raycast** sur le plan du sol (Y=0)
- Lift vertical à la sélection

### Effets 3D (`MapEffect3D`)

- **GPUParticles3D** (feu, fumée, magie, pluie) via `MapEffectPresets.create_particles_3d()`
- **OmniLight3D** sur feu/magie (éclairage volumétrique simulé)

### Caméra & navigation

- **Orthographique** par défaut (`perspective: topdown`) — zoom = `Camera3D.size`
- `isometric` : rotation Y 45° + angle 58°
- `perspective` : caméra perspective FOV 38° (battlemaps pré-rendered)
- Pan = déplacement Camera3D sur XZ, molette = zoom ortho / dolly
- Inertie légère au relâchement

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
  "perspective": "topdown | isometric | perspective",
  "grid": { "size": 70, "opacity": 0.14, "color": "#ffffff", "enabled": true },
  "atmosphere": { "enabled": true, "tint": "#141018", "opacity": 0.12, "vignette": 0.18 },
  "lighting": {
    "enabled": true,
    "direction": "nw | ne | sw | se",
    "intensity": 0.35,
    "ambient": "#121018",
    "sources": [{ "x": 8, "y": 5, "radius": 4, "color": "#ffaa55", "intensity": 0.6 }]
  },
  "elevationLayers": [
    { "image": "user://map_assets/map-xxx-platform.png", "opacity": 0.92, "offset": { "x": 0, "y": 0 } },
    {
      "elevation": 1,
      "opacity": 0.35,
      "tint": "#8a7a60",
      "platform": { "x": 4, "y": 3, "w": 6, "h": 4 }
    }
  ],
  "playDefaults": {
    "tokens": [{ "id", "x", "y", "label", "kind", "memberId", "memberIndex", "emoji", "color" }],
    "effects": [{ "id", "type", "preset", "x", "y", "radius", "triggered", "label" }],
    "zones": [{ "id", "shape", "x", "y", "radius", "label", "color" }],
    "fogRevealed": ["3,4"],
    "viewState": { "zoom", "panX", "panY" }
  }
}
```

### Configuration via Gestion des cartes

1. **Mode complexe** — sélecteur « ⚙️ Complexe » en édition (persisté dans `maps.json`).
2. **Éditeur 3D intégré** — Hub → Cartes → Modifier une carte en mode complexe :
   - Import battlemap PNG (Dungeon Alchemist, Dungeondraft…) + **calques overlay** (ponts, étages)
   - **Auto-dimensionnement** de la grille depuis les pixels de l'image importée
   - Taille grille, réglages grille / brouillard (pinceau réglable)
   - Perspective (top-down / isométrique / perspective), atmosphère (teinte + opacité), éclairage directionnel
   - **Plateformes surélevées 3D** (tool 🟫) + rendu `MapElevations3D`
   - Outils : sélection 👆, tokens, marqueurs PNJ, effets 🔥💨✨🌧️, zones AOE, brouillard, gomme
   - Rayons effet/zone configurables, aimantation grille, test ▶ des effets particules
   - Liste des éléments placés avec suppression
   - Disposition par défaut (`playDefaults`) enregistrée dans la carte et copiée en session au premier accès
3. **Création rapide** — Hub → Cartes → **+ Battlemap 3D** (ou enquête 3D)
4. **Perspective** — champ JSON `perspective` ou sélecteur éditeur :
   - `topdown` : Camera3D orthographique ~52° (défaut)
   - `isometric` : ortho + rotation Y 45°
   - `perspective` : Camera3D perspective FOV 38° (maps Dungeon Alchemist / Dungeondraft)
5. **Éclairage** — `DirectionalLight3D` + bloc `lighting` JSON (`direction`, `intensity`).
6. **Élévation** — `elevationLayers` : PNG overlay sur PlaneMesh surélevé.
7. **Atmosphère** — `atmosphere.enabled` + teinte/vignette pour ambiance scène.

> L'éditeur 3D (`MapComplexEditor`) couvre l'essentiel de la configuration ; édition JSON directe dans `user://maps.json` reste possible pour champs avancés. pour l’instant ; UI dédiée roadmap Phase 3.

### État session (`mapPlayState[mapId]`)

```json
{
  "tokens": [{ "id", "x", "y", "kind", "memberId", "label", "hp", "maxHp", "elevation" }],
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

### Mode complexe (3D)
1. En session, sélecteur **⚙️ Complexe**.
2. Placer un token PJ — cylindre 3D + portrait billboard, **ombre portée réelle**.
3. Sélectionner : anneau émissif + lift vertical.
4. Effets 🔥 : **GPUParticles3D** + lumière ponctuelle ; **▶ Déclencher**.
5. Fog 🌫️ : dalles 3D (MJ voit tout).
6. Pan molette / glisser (inertie) / snap grille.
7. Battlemap PNG + `perspective` / `lighting` dans `maps.json`.

### Import PNG (Hub)
- `MapData.import_background_image(map_id, path)` — copie vers `user://map_assets/`.

---

## 7. Positionnement concurrentiel (honest)

### ✅ Implémenté (fondation crédible)

| Feature | Roll20 | Foundry | Owlbear | **OpenQuest** |
|---------|--------|---------|---------|---------------|
| Battlemap image | ✅ | ✅ | ✅ | ✅ (import PNG) |
| Grille configurable | ✅ | ✅ | ✅ | ✅ |
| Tokens 3D + ombres réelles | ✅ | ✅ | ✅ | ✅ (complex) |
| Particules GPUParticles3D | ⚠️ | ✅ | ❌ | ✅ |
| Éclairage DirectionalLight3D | ✅ | ✅ | ❌ | ✅ |
| Calques élévation 3D | ✅ | ✅ | ⚠️ | ✅ |
| Caméra top-down / isométrique | ⚠️ | ✅ | ⚠️ | ✅ (Camera3D) |
| Fog MJ/joueur | ✅ | ✅ | ✅ | ✅ (cellulaire) |
| Particules / FX | ⚠️ | ✅ | ❌ | ✅ (3 presets + trigger) |
| Zones AOE | ✅ | ✅ | ⚠️ | ✅ (foundation) |
| Carte monde campagne | ❌ | ⚠️ | ❌ | ✅★ (mode simple) |
| P2P sans serveur jeu | ❌ | ❌ | ❌ | ✅ (sync état complet) |
| Mode enquête | ❌ | ❌ | ❌ | ✅★ |

### ❌ Manquant (roadmap Phases 2–6)

- Éclairage dynamique temps réel / LOS / murs (vraie occlusion)
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
