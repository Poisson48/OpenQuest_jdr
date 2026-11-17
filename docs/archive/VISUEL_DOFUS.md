# Visuel « Dofus » — carte 2.5D (task-28)

Branche `feat/carte-2.5d-editeur`. Objectif : rapprocher le rendu de Dofus
(personnages qui marchent, terrain vivant, transitions de zone lisibles) sans
toucher à la logique de construction de l'éditeur ni aux données de jeu.

## Avant / après

| Axe | Avant | Après |
|---|---|---|
| **Personnages** | Un clic / une flèche téléportait le token : `refresh()` reconstruisait tous les nœuds (`_clear_children`) → saut sec, clignotement, animation d'inactivité relancée. | Les nœuds de token sont **réutilisés** tant que la carte et le style ne changent pas ; le déplacement joue une **marche animée** (interpolation douce, petit arc, orientation vers la direction, **poussière de pas** one-shot) puis se cale exactement sur la case et la hauteur du terrain. |
| **Terrain** | Sol splat + relief + eau, mais cases d'herbe nues en vue de dessus : aspect « plat de texture ». | **Végétation procédurale** : touffes d'herbe croisées (vent doux animé par shader, couleurs d'instance variées) + petites fleurs, semées de façon **déterministe** sur les cases d'herbe, hors eau ; aucune collision, aucune ombre. |
| **Passages de zone** | Fondu linéaire court, titre de zone, puis retour sec au jeu. | Fondu **asymétrique adouci** (`TRANS_SINE`/`EASE_IN_OUT`, 0.22 s entrée / 0.30 s sortie), titre inchangé, puis **pulsation d'arrivée** de caméra (léger « breathe » de zoom qui revient exactement au zoom initial). |
| **Ambiance** | SSAO, glow, ACES, fog, lumières (déjà en place). | La végétation reçoit la **teinte de nuit** comme le sol ; la pulsation d'arrivée renforce le feedback de chargement sans changer l'état de jeu. |

## Ce qui a été ajouté (API)

### `map_layers/map_vegetation_3d.gd` (nouveau, `MapVegetation3D`)
- `configure(w, h, cell_size, heights, materials, water_level, night_mode, enabled)` — no-op si rien ne change.
- `clear()`, `is_active()`, `get_vegetation_count()`, `get_tuft_count()`, `get_flower_count()`, `get_tuft_multimesh()`, `get_flower_multimesh()`, `get_material()`, `set_night_mode(on)`.
- Constantes : `TUFT_DENSITY = 0.55`, `FLOWER_DENSITY = 0.10`, `MAX_TUFTS = 3000`, `MAX_FLOWERS = 700`, `NIGHT_TINT`, palettes `TUFT_COLORS`/`FLOWER_COLORS`.
- Rendu : 2 × `MultiMeshInstance3D`, mesh quads croisés à dégradé de vertex colors, shader inline **unshaded + vent** (`wind_strength`, `wind_speed`), `cast_shadow = OFF`.

### `complex_map_engine_3d.gd`
- Calque `_vegetation_layer` instancié avec le viewport (après `AmbientFx`, avant `Elevations`), rechargé dans `configure`, `refresh_terrain`, `_rebuild_layers` et `set_ground_mode`.
- `is_vegetation_active()`, `get_vegetation_count()`, `get_vegetation_counts() -> {tufts, flowers}`.
- `play_arrival_pulse(strength := 1.0)`, `is_arrival_pulse_playing()` — pulsation caméra de changement de zone.
- Tokens : `_token_render_key` (carte + style) → **réutilisation** des nœuds ; création factorisée dans `_create_token_node()`.
- `_create_token_node()` calcule localement `is_diorama` (correctif de compilation signalé par l'agent construction).

### `map_layers/map_token_3d.gd`
- `update_token(data)` : met à jour les données sans reconstruire le visuel.
- `move_to_grid(gx, gy, animated := true)` : tween `TRANS_SINE`/`EASE_IN_OUT`, durée bornée (0.10–0.42 s ∝ distance), arc vertical `sin(t·π)·0.16·cell`, orientation vers la direction, poussière de pas au départ et à l'arrivée, calage final exact (terrain + surélévation de sélection).
- `is_walking()`, `get_grid_position()`, `stop_walking()`, `_play_step_dust()`.
- `set_terrain_heights(..., repose := true)` : les refresh de marche passent `repose = false` pour ne pas téléporter avant l'animation.
- Poussière : `CPUParticles3D` one-shot (`StepDust`), texture ronde générée, matériau unshaded transparent, pas d'ombre.

### `session/panels/map_workspace.gd`
- Constantes `FADE_IN_SECONDS = 0.22`, `FADE_OUT_SECONDS = 0.30`, `ARRIVAL_PULSE_STRENGTH = 1.0`.
- `_fade_to()` : courbe douce + durée asymétrique (les deux transitions de zone l'utilisent).
- `_play_arrival_feedback()` : demande la pulsation à la scène après le fondu de retour.
- `is_transitioning()` : état public (tests, captures, entrées).

### `session/panels/map_stage.gd`
- `play_arrival_pulse(strength := 1.0)` et `is_arrival_pulse_playing()` : relais vers le moteur carte actif.

## Tests

- `game/scripts/tests/map_render_quality_test.gd` étendu :
  - ambiance existante (SSAO, glow, ACES, ombres, soleil chaud, nuit bleutée) ;
  - **végétation** : active, > 40 instances, `MultiMesh` cohérent, pas d'ombre, vent > 0, **déterministe** entre deux `configure`, teinte de nuit non blanche ;
  - **marche** : nœuds créés, API, réutilisation du même nœud (`instance_id`), `is_walking()` vrai après changement de case, poussière créée, fin d'animation, arrivée exacte `(8,6)`, hauteur de terrain respectée ;
  - **pulsation d'arrivée** : démarre, se termine, zoom restauré à l'identique.
- `game/scripts/tests/session_move_tool_test.gd` étendu : marche réelle après clic de l'outil Déplacer (nœud animé + poussière + fin), `_fade_to` (écran noir / retour), `is_transitioning()`, `_play_arrival_feedback()` → `is_arrival_pulse_playing()`.

Commande de vérification :

```powershell
$env:GODOT_BIN = "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
.\scripts\run_tests.ps1 -Filter '^map_render_quality_test$|^map_camera_test$|^session_' -TimeoutSeconds 180
```

## Limites / points à vérifier par le Lead

- La marche est **visuelle** : la position logique (`GameData`) est mise à jour immédiatement au clic, l'animation ne fait que rattraper la case (pas de file d'attente de pas façon Dofus, pas de coût en PA).
- La végétation est **statique en placement** (seul le vent est animé), semée uniquement sur les cases de matière herbe ; pas sur terre/pierre, pas dans l'eau, désactivée en vue table et en mode illustré.
- La poussière de pas est volontairement discrète (8 particules, 0.45 s) pour ne pas surcharger les cartes chargées.
- La pulsation d'arrivée est purement caméra (zoom ×1.06 puis retour) : aucun impact sur le cadrage enregistré (`get_view_state()` n'est pas modifié).
- Captures conseillées : `game/scripts/tests/valbois_screenshot_test.gd`, `token_figurine_shot_test.gd`, `cliff_shot_test.gd`, `session_monde_shot_test.gd` (fenêtrées, sans `--quit`), et une capture d'un déplacement de token (la marche dure < 0.5 s : lancer la capture pendant `is_walking()`).

## Fichiers

- `game/scripts/maps/complex_map_engine_3d.gd`
- `game/scripts/maps/map_layers/map_vegetation_3d.gd` (nouveau)
- `game/scripts/maps/map_layers/map_token_3d.gd`
- `game/scripts/session/panels/map_workspace.gd`
- `game/scripts/session/panels/map_stage.gd`
- `game/scripts/tests/map_render_quality_test.gd`
- `game/scripts/tests/session_move_tool_test.gd`
- `docs/VISUEL_DOFUS.md` (ce document)
