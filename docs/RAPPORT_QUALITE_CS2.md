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

### Netteté des textures & confort de navigation

| Amélioration | Implémentation | Preuve |
|---|---|---|
| **Mipmaps** sur les textures importées (sol + textures extraites des GLB) | `[importer_defaults] texture={"mipmaps/generate": true}` dans `game/project.godot` ; réimport des textures de terrain et des `*_surface.png` — fini le scintillement/moquette au loin et le flou en vue rasante | `texture_quality_test` (mipmaps présents sur 6 textures de sol + albédo GLB) |
| **Textures de sol en 1024²** | régénération procédurale seamless (`tools/blender/make_terrain_textures.py --size 1024`) : herbe/terre/pierre/falaise/neige/sable + vignettes + planche | captures `terrain_quality_*`, `cite_*` (pavés/détails nets) |
| **Filtrage anisotrope 8×** | `rendering/textures/default_filters/anisotropic_filtering_level=3` | `texture_quality_test` |
| **MSAA 4× en preset cinéma** (2× en classique) | `_apply_render_quality()` : `_viewport.msaa_3d` suit le preset — arêtes de toits/coques d'encre nettes | `map_quality_cs2_test` (`ui_engine_cinema_msaa` / `ui_engine_classic_msaa`) |
| **Navigation 1:1 au clic droit** | pan ancré au point de sol saisi (`_screen_point_on_plane`) : le décor reste collé au curseur, quel que soit l'angle/perspective ; orbite sur `Maj`+clic droit / clic milieu | `pan_cursor_tracking_test`, `camera_navigation_test` |

## Chantiers qualité des assets (A → B → C)

**A — Végétation en cartouches alpha (livré)** : `tools/blender/build_vegetation_cards.py`
+ `vegetation_cards.json` regénèrent roseaux, buisson, haie, nénuphars et bosquet
depuis les planches IA (alpha découpé, atlas 1024/2048, double face) : 4 à 6 tris
au lieu de 1 400–2 418, et **la silhouette peinte est retrouvée**. Le moteur
(`map_meshes_3d.gd`) détecte le matériau alpha-scissor et applique
`shaders/vegetation_card*.gdshader` (vent par sommet, variantes éclairée /
non éclairée) au lieu du matériau standard qui forçait le cull back. Test :
`vegetation_cards_test`.

**B — Rochers PBR d'origine (livré)** : les GLB Tripo3D bruts
(`artifacts/tripo-review/rock-kit/recolored_1024/`) ont la **même géométrie**
(973–1 036 tris) que les `bloc_rocheux_*` livrés, mais des textures PBR plus
fines. Régénération par `tools/blender/build_tripo_rocks.py --texture-size 1024` :
albédo **1024²** (au lieu de 512²) + **normale 1024²**, palette Valbois, AO et
mottling en vertex colors, vignettes et manifeste à jour. GLB : 258–469 Ko
(contre 164–230 Ko). Test : `rock_pbr_test` ; captures :
`rochers_formation_*.png`.

**C — Bâti/décors HD + LOD (à faire)** : régénérer depuis les planches avec
`SIZE 160–256`, budget 6 000–12 000 tris, atlas 1024–2048 et contour conservé,
puis LOD (HD près / niveau actuel au loin). Le kit complet ne pèse que
191 072 tris aujourd'hui : la marge de performance est large.

## Reste (pistes)
- Réflexions ray-marchées (SSR profond) — coût, non retenu dans le budget actuel.
- Brume de pied de cascade **non éclairée** (choix) : éclairage de la brume par le soleil/les torches.
- Même mécanique d'adoucissement des pointes à appliquer au ruban de **chemin** (`path_ribbon.gdshader`), aujourd'hui eau seulement.
- **LOD d'ombre** au-delà du budget de distance (`shadowDistance`) : ombre de contact renforcée pour éviter le saut visuel sur les très grandes cartes.
