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
| **Socle de diorama** (jupe de falaise) | strates géologiques procédurales (`slab_base.gdshader`), arête adoucie avec débord herbeux, pied évasé + AO de contact, fond de plateau adouci — voir [`RAPPORT_SOCLE_DIORAMA.md`](RAPPORT_SOCLE_DIORAMA.md) | `slab_quality_off/on.png` (diff 0,0241) · `slab_quality_cinema.png` (stable sous preset CS2) |
| **Strates de falaise** | couches obliques (altitude + azimut de pente, ondulées par bruit), teintes sable/argile/roche, pentes fortes + roche naturelle uniquement, 0 fetch en plus — voir [`RAPPORT_TERRAIN_CS2_STRATES.md`](RAPPORT_TERRAIN_CS2_STRATES.md) | `terrain_strata_off/on.png` (diff 0,0116, plaine 0,00000) |
| **Variation macro du terrain** | grand bruit 3D monde (varie aussi en altitude) : taches sèches/vertes, patches de mousse ; réduite sur la neige | `terrain_strata_macro_off/on.png` (0,00212) |
| **Transition neige/roche/herbe** | frontière élargie et adoucie, neige dans les creux (AO cuite) et pentes faibles, roche à nu sur pentes fortes, zéro moucheture | `terrain_strata_snow_off/on.png` (0,00441 · mouchetures 0,0000) |
| **Ancrage des objets** | AO de contact cuite sous chaque objet 3D (preset cinéma) : `map_ground_3d.set_object_occlusion_stamps()` alimenté par le moteur (`_sync_object_occlusion_stamps`), 1 fetch conditionnel | `terrain_strata_object_ao_off/on.png` (0,00158) · `object_grounding_test:PASS` |

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
| Brume / écume volumétrique au pied des cascades | `water_mist.gdshader` : 2 quads par chute accumulés en un seul maillage, alpha dissipé avec la hauteur, budget `MIST_MAX_QUADS = 64` — voir [`RAPPORT_QUALITE_CS2_FINITIONS.md`](RAPPORT_QUALITE_CS2_FINITIONS.md) | `cs2_finitions_mist_off/on.png` (diff moyenne 0,0235) |
| Éclairage double du lit réfracté | lumière **directe** (caustiques sur le lit réfracté) + **ambiance/diffusion d'eau** sur les hauts-fonds (`bed_ambient_lift`, shaders eau + terrain) — fin de l'effet « fond plat » | `cs2_finitions_bed_off/on.png` (0,0190) · `cs2_finitions_terrain_bed_off/on.png` (0,0143) |
| Nez de ruban adoucis vus de très haut | masque de pointe en `COLOR.b` + détection de l'empreinte écran par `fwidth()` (`tip_soften_distance`), aucun uniform caméra, vrai en perspective et ortho | `cs2_finitions_tip_off/on.png` (signal 0,00904, bruit d'animation 0,000000) |
| Dérive du motif **dans le sens du courant** | rivières : espace de dérive du ruban (UV : u en travers, v le long du tracé) remis à l'échelle monde (`flow_ribbon`) au lieu de l'UV2 monde fixe ; vitesse visuelle calmée (`RIVER_FLOW_VISUAL_SCALE`) — le motif suit les méandres au lieu de défiler dans une direction unique à toute vitesse | `demo_riviere_s.png` / `demo_riviere_s_detail.png` (démo rivière en S) |

### Ambiance
| Méthode CS2 | Implémentation | Preuve |
|---|---|---|
| Perspective aérienne (brume distance + hauteur) | `WorldEnvironment` isolé du monde carte, réglable, A/B | `fog_quality_distance_off/on.png` |
| **Brume de hauteur adaptée au tilt** | la composante hauteur est pondérée par l'angle caméra (nulle en vue plongeante, pleine en vue rasante), profondeur inchangée, recalcul au mouvement sans reconstruction — `atmosphericFog.tiltAware` (A/B) — voir [`RAPPORT_QUALITE_CS2_PRESET.md`](RAPPORT_QUALITE_CS2_PRESET.md) §2.6 | `fog_quality_tilt_{top,default,low}_{off,on}.png` (vue carte 0,0521 → 0,0134) |
| **Preset qualité « cinéma »** (carte peuplée d'objets 3D) | opt-in `map_data["qualityPreset"] = "cinema"` : ombres portées des GLB (PCF 4 splits, jamais les coques `*_outline`), matériaux PBR éclairés + perspective aérienne, SSAO renforcée + SSIL, tonemap ACES/étalonnage, ombre de contact atténuée — orthogonal au `renderStyle`, `classique` inchangé. Voir [`RAPPORT_QUALITE_CS2_PRESET.md`](RAPPORT_QUALITE_CS2_PRESET.md) | `quality_cs2_{off,on}_{overview,close}.png` · perf 4,08 → 5,46 ms (148 meshes) |

## Reste (pistes)
- Réflexions ray-marchées (SSR profond) — coût, non retenu dans le budget actuel.
- Brume de pied de cascade **non éclairée** (choix) : éclairage de la brume par le soleil/les torches.
- Même mécanique d'adoucissement des pointes à appliquer au ruban de **chemin** (`path_ribbon.gdshader`), aujourd'hui eau seulement.
- **LOD d'ombre** au-delà du budget de distance (`shadowDistance`) : ombre de contact renforcée pour éviter le saut visuel sur les très grandes cartes.
