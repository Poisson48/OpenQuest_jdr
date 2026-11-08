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
  `water_quality_*.png`, `staircase_*.png`, `fog_quality_*.png`).
- Tests de capture : lancés **sans vol de focus** (fenêtre cachée via
  `scripts/run_tests.ps1 -IncludeShots` ; en `--headless` ils sortent en `[SKIP]`).
- Non-régression : `map_terrain_materials_test`, `map_terrain_test`,
  `map_water_test`, `water_bodies_test`, `river_continuity_test`,
  `river_user_trace_test`, `map_editor_test`, `scene_load_test`,
  `map_render_quality_test`, `map_lighting_test`, `map_backdrop_test`.

## Livré (méthodes CS2)

### Terrain
| Méthode CS2 | Implémentation | Preuve |
|---|---|---|
| Projection triplanaire (pas d'étirement) | `terrain_splat.gdshader` + `stretch_fix` | `terrain_quality_cliff_uv.png` vs `terrain_quality_cliff.png` (diff mesuré) |
| Auto-matériau par pente et altitude | roche sur pentes, herbe en plaine, neige aux sommets, bruit anti-bandes, uniform `auto_material_strength` | `terrain_quality_mountain_auto0.png` vs `terrain_quality_mountain.png` |
| AO de cavités cuite | occlusion par sommet depuis le heightfield, uniform `cavity_bake` | `terrain_quality_cavity_off/on.png` |
| Micro-détail + micro-relief | bruit procédural projeté + perturbation de normale | captures de gros plan |
| Berge mouillée | texture de berge (couche d'eau) dans le shader terrain | `terrain_quality_shore_off/on.png` |

### Eau
| Méthode CS2 | Implémentation | Preuve |
|---|---|---|
| Profondeur lisible (extinction) | profondeur normalisée, absorption exponentielle | `water_quality_*` |
| Mousse de rive fine | anneau de sondes 8 directions, lacunaire, animée | `terrain_quality_shore.png` |
| Micro-vagues | deux échelles cohérentes avec `flow_dir` | captures |
| Flow map à deux phases | deux advections décalées, mélange triangle | rivières `water_quality_river.png` |
| Réflexion de ciel (Fresnel) | dégradé ciel/horizon pondéré par Fresnel | `water_quality_lake.png` |
| Réflexions écran | `hint_screen_texture`, décalage par les vagues, `reflection_enabled` | `water_reflection_ab_*.png` |
| Caustiques + absorption sous l'eau | carte d'eau (profondeur + masque) → shader terrain, voronoï animée | `water_quality_lake_wmap_off/on.png` |
| Réfraction écran du lit | `refr_uv` décalé par les vagues, `refraction_enabled` | `crop_lake_refr_off/on.png` |
| Cascades | rideau unique par ressaut, stries, écume, bourrelet fondu | `staircase_falls.png` |

### Ambiance
| Méthode CS2 | Implémentation | Preuve |
|---|---|---|
| Perspective aérienne (brume distance + hauteur) | `WorldEnvironment` isolé du monde carte, réglable, A/B | `fog_quality_distance_off/on.png` |

## Reste (pistes)
- Réflexions ray-marchées (SSR profond) — coût.
- Adoucissement des nez de ruban vus de très haut.
- Brume volumétrique au pied des cascades.
- Éclairage double du lit réfracté (approximation).
