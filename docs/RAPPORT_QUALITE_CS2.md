# Qualité terrain & eau — objectif « niveau Cities: Skylines II »

Chantier en cours. Chaque critère est vérifiable sur capture et couvert par un test.

## Référence / critères de qualité (CS2)

D'après la documentation publique des réglages graphiques de Cities: Skylines II
([Options menu/Graphics](https://cs2.paradoxwikis.com/Options_menu/Graphics)) et
les techniques de rendu d'eau usuelles (flow maps, mousse de contact, profondeur
lisible, reflets, occlusion) :

### Terrain
1. **Projection triplanaire** des matières : aucune texture étirée sur les
   pentes/falaises (le mapping UV classique est le défaut n°1 en jeu).
2. **Micro-détail** haute fréquence pour casser la répétition des textures.
3. **Occlusion / cavités** : assombrissement léger des creux (approximation
   par pente/courbure acceptable, pas de SSAO obligatoire).
4. Ombrage lissé (normales par sommet) et variation macro de teinte.

### Eau
1. **Profondeur lisible** : couleur/opacité dépendantes de la profondeur
   (hauts-fonds clairs et transparents, fosses profondes et foncées).
2. **Mousse de contact/rive** fine et animée sur les faibles profondeurs.
3. **Micro-vagues** à deux échelles cohérentes avec le courant (`flow_dir`),
   scintillement solaire structuré (sans bandes régulières).
4. **Cascades** : rideaux d'eau striés, écume de crête et de pied.
5. Berge mouillée (terre assombrie/brunie au contact de l'eau).

## Répartition du travail (délégation MiMo)

| Chantier | Teammate | Périmètre fichiers |
|---|---|---|
| Terrain triplanar + micro-détail + occlusion | `terrain-cs2-mimo` | `terrain_splat.gdshader`, `map_ground_3d.gd` (uniforms), nouveau `terrain_quality_shot_test.gd` |
| Eau : mousse de rive, micro-vagues, profondeur | `water-cs2-mimo` | `water_surface.gdshader`, `_make_body_material` de `map_water_3d.gd`, nouveau `water_quality_shot_test.gd` |
| Cascades (livré) | `cascades-mimo` | `water_fall.gdshader`, section cascade de `_build_river_body`, `staircase_cascade_shot_test.gd` |
| Supervision, terrain de validation, non-régression | Lead | `staircase_cascade_shot_test.gd`, tests, revue |

Règles de cohabitation : fichiers **disjoints**, un seul Godot à la fois
(verrou `.godot.lock`), captures à la racine (`docs/screenshots/`), PASS =
sortie littérale `:PASS`.

## Validation

- Capture avant/après par chantier (`docs/screenshots/terrain_quality_*.png`,
  `water_quality_*.png`, `staircase_*.png`).
- Non-régression : `map_terrain_materials_test`, `map_terrain_test`,
  `map_water_test`, `water_bodies_test`, `river_continuity_test`,
  `river_user_trace_test`, `map_editor_test`, `scene_load_test`.
