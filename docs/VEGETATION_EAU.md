# Végétation, eau et ambiances

## Vue d'ensemble

Couches d'habillage du rendu 2.5D (mode `terrain3d`) : végétation procédurale, plan d'eau avec décor de surface, particules d'ambiance. Pilotées par des clés `map_data` et réglables depuis le panneau de l'éditeur.

## Végétation procédurale — `map_vegetation_3d.gd`

- Gated par `map_data["vegetationEnabled"]` (sinon aucune instance n'est construite).
- Quatre catégories sur les cases d'herbe : touffes d'herbe, fleurs, buissons, feuilles mortes ; cases non-herbe et cases immergées ignorées.
- Densités par case (constantes × `vegetationDensity`) : touffes 0.85, fleurs 0.18, buissons 0.16, feuilles 0.30 ; multiplicateur clampé à 0..4 dans la couche.
- Caps de performance appliqués uniformément : `MAX_TUFTS` 5000, `MAX_FLOWERS` 1800, `MAX_BUSHES` 900, `MAX_LEAVES` 3200.
- Placement 100 % déterministe (hash entier par case + sel, aucun RNG) : pas de « saut » entre deux rebuilds, instances comptables dans les tests.
- Rendu : MultiMesh de quads/sphères `unshaded`, vent doux (shader inline), couleurs d'instance variées, pas d'ombres ni de collisions ; teinte de nuit appliquée sans rebuild.

## Eau — `map_water_3d.gd`

- `map_data["waterLevel"]` : hauteur du plan d'eau en **cases** (< 0 = aucune eau) ; les creux du relief sous ce niveau forment le lac.
- Shader `water_surface.gdshader` translucide : ondulations animées, dégradé eau claire → profonde, écume de rive, teinte de nuit (`night_tint`).
- Profondeur fournie au shader par une texture (un texel par case, R = profondeur normalisée, 0 à la rive) ; accesseurs `get_depth_texture()` / `get_max_depth()`.
- Décor de surface déterministe (MultiMesh, graine `map_data["waterDecorSeed"]`) : lentilles d'eau (densité 0.26, cap 2400) et nénuphars limités aux hauts-fonds (profondeur ≤ 0.22 case, densité 0.05, cap 360) ; un nénuphar garanti sur les hauts-fonds s'il n'y en a aucun.

## Ambiance — `map_ambient_fx_3d.gd`

- `map_data["ambientFx"]` (String) : `""` (aucune), `fireflies` lucioles, `dust` poussière, `leaves` feuilles qui tombent, `rain` pluie, `snow` neige.
- Un seul émetteur de particules à la fois ; purement décoratif, aucun impact sur le gameplay. Les lucioles sont renforcées en mode nuit.

## Contrôles éditeur — `map_editor_settings_panel.gd`

- Type de sol : terrain 3D (relief, eau, objets qui suivent le sol) ou fond illustré plat.
- Niveau d'eau : SpinBox −1.0 à 8.0 (pas 0.1) ; −1 = aucune eau.
- Ambiance : liste déroulante (aucune / lucioles / poussière / feuilles / pluie / neige).
- Végétation : case à cocher + densité 0.0 à 3.0 (pas 0.1).
- Lumière : presets (`MapData.LIGHTING_PRESET_ORDER`), direction, intensité, mode nuit.

## Clés `map_data`

| Clé | Type | Défaut | Rôle |
| --- | --- | --- | --- |
| `vegetationEnabled` | bool | `false` | Active la végétation procédurale |
| `vegetationDensity` | float | `1.0` | Multiplicateur de densité (éditeur 0–3) |
| `waterLevel` | float | `-1.0` | Hauteur du plan d'eau en cases ; < 0 = désactivée |
| `waterDecorSeed` | int | `1` | Graine du décor de surface (lentilles, nénuphars) |
| `ambientFx` | String | `""` | Effet d'ambiance (`fireflies`/`dust`/`leaves`/`rain`/`snow`) |
| `groundMode` | String | — | `terrain3d` requis pour ces couches (sinon fond illustré) |
