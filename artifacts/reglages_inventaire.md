# Inventaire factuel des réglages de rendu — éditeur de cartes 3D « OpenQuest JDR »

**Objet** : recenser tout ce qui est *réellement* réglable au runtime dans le rendu 3D de
l'éditeur de cartes (Godot 4.7, **Forward+**), avec chemins de fichiers et numéros de ligne,
afin de préparer un menu « Paramètres » sans dupliquer l'onglet « Carte » existant.
**Aucun fichier du jeu n'a été modifié** : ce rapport est le seul livrable
(`artifacts/reglages_inventaire.md`).

**Convention de lecture**

| Colonne | Sens |
|---|---|
| **Clé / paramètre** | nom exact de la clé `map_data`, de la propriété Godot ou de la constante |
| **Lu à** | où la valeur est lue (fichier:ligne) |
| **Appliqué à** | où elle atteint le moteur de rendu (fichier:ligne) |
| **Défaut** | valeur par défaut effective (code) |
| **Plage / valeurs** | bornes ou énumération réelle |
| **Persistance** | `Carte` = sérialisée dans `map_data` (donc par carte + exports JSON) ; `Global` = constante/état de code ; `UI` = état de session non persisté |

Chemins abrégés utilisés dans les tableaux (tous sous `D:\git\OpenQuest_jdr\`) :

- `ENGINE` = `game/scripts/maps/complex_map_engine_3d.gd` (4008 lignes)
- `STYLE` = `game/scripts/maps/map_render_style.gd` (366 lignes)
- `EDITOR` = `game/scripts/maps/map_complex_editor.gd` (5094 lignes)
- `MAPDATA` = `game/scripts/autoload/map_data.gd`
- `PANEL` = `game/scripts/maps/editor/map_editor_settings_panel.gd`
- `TSCN` = `game/scenes/map_editor/panels/settings.tscn`
- `MESHES` = `game/scripts/maps/map_layers/map_meshes_3d.gd`
- `GROUND` = `game/scripts/maps/map_layers/map_ground_3d.gd`
- `WATER` = `game/scripts/maps/map_layers/map_water_3d.gd`
- `VEG` = `game/scripts/maps/map_layers/map_vegetation_3d.gd`
- `FX` = `game/scripts/maps/map_layers/map_ambient_fx_3d.gd`

---

## 0. Synthèse en douze points

1. **Un seul moteur de rendu 3D** : `ComplexMapEngine3D` (`game/scripts/maps/complex_map_engine_3d.gd`),
   utilisé par l'éditeur **et** par la session (nœud `ComplexMap` de
   `game/scenes/session/panels/map_stage.tscn`). Toute fonction d'application ajoutée là
   profite aux deux.
2. **Le SubViewport n'existe dans aucun `.tscn`** : il est créé par code dans
   `ENGINE._build_viewport_tree()` (l.352-397). C'est là que vivent **MSAA 3D, screen-space AA
   et l'échelle de rendu** (l.391-393) — et ces trois champs ne sont **jamais réappliqués**
   ensuite.
3. **Preset de qualité** : `map_data["qualityPreset"]` (`classique` par défaut, `cinema` opt-in),
   résolu par `STYLE.quality_preset()` (l.263-267), surcharges dans
   `STYLE.QUALITY_POST_OVERRIDES` (l.57-90) et `STYLE.QUALITY_SURFACE_OVERRIDES` (l.96-125).
4. **Ordre de fusion décisif** (`STYLE.config()`, l.231-254) :
   `CONFIGS[style]` → ajustements « fond illustré » → `QUALITY_POST_OVERRIDES` →
   `QUALITY_SURFACE_OVERRIDES` (seulement si pas de fond illustré) → **`renderStyleOverrides`
   de la carte gagne en dernier**. C'est le point d'accroche naturel pour des réglages par carte.
5. **Onglet « Carte » déjà très fourni** : ~25 réglages (dont terrain/eau/végétation/ambiance,
   construits par code, l.109-198 de `PANEL`). La liste exhaustive est en §15.
6. **Aucun réglage de boucle de rendu n'existe** : ni `Engine.max_fps`, ni `vsync`, ni mode
   fenêtre persistant. `DisplayServer.window_set_vsync_mode` et `Engine.max_fps` n'apparaissent
   que dans un test de benchmark (`game/scripts/tests/map_quality_cs2_shot_test.gd:127-128`).
7. **Le compteur FPS existe déjà** : `Label` créé en `EDITOR` l.611-616 (11 px, `#718087`),
   ajouté en fin de `StatusRow` (barre de statut basse), mis à jour en `EDITOR._process`
   l.503-505.
8. **Eau** : seuls `waterLevel`, `waterDecorSeed`, `waterDecorDensity`, `waterBodies` sont des
   clés de carte. **Réflexions / réfractions écran sont des uniforms de shader codés en dur**
   (`WATER` l.1795-1801, 1832-1835, 1877-1883) : aucune clé `waterRefraction` n'existe.
9. **Trois clés mortes** à ne pas exposer telles quelles : `groundTint` (jamais lue),
   `softShadows` (lue uniquement par les tests), `lighting.ambient` (jamais lue ; c'est
   `lighting.ambientColor` qui sert).
10. **Divergence d'application des ombres** : `_apply_render_quality()` (l.1042) force
    `_sun.shadow_enabled = terrain3d and not table_view`, alors que `_apply_lighting()` (l.1804)
    applique `cfg["shadows"]`. `set_ground_mode()` (l.1493-1503) et
    `set_atmospheric_fog_enabled()` (l.2019-2021) n'appellent **que** `_apply_lighting()` →
    l'état des ombres dépend du dernier appliqueur. À corriger avant d'exposer un toggle.
11. **Coût d'un changement de réglage** : le panneau écrit via `doc.set_meta_values()` →
    `changed("meta")` → `EDITOR._sync_engine()` (l.3832-3868) → `engine.configure()` complet
    (rechargement sol/eau/végétation + `_rebuild_layers()`). Le seul chemin « chaud » existant
    est `set_quality_preset()` (l.850-875).
12. **Persistance globale déjà outillée** : `game/scripts/autoload/locale_settings.gd`
    (`user://app_settings.cfg`, l.7 / 17-23 / 25-29) est le patron à réutiliser pour un
    `RenderSettings` global.

---

## 1. Chaîne de rendu — qui applique quoi

| Couche | Fichier | Rôle | Fonctions d'application |
|---|---|---|---|
| Hôte éditeur | `EDITOR` | UI, document, orchestration | `_create_engine()` l.741-752 ; `_sync_engine()` l.3832-3868 |
| Moteur 3D | `ENGINE` | SubViewport, caméra, Environment, calques | `configure()` l.526-613 (séquence d'appels l.576-614) |
| Document | `game/scripts/maps/editor/map_edit_document.gd` | vérité `map_data` + undo | `set_meta_values()` l.1073-1088 ; `to_map_data()` l.362 |
| Style/preset | `STYLE` | fusion des réglages | `config()` l.231-254 |
| Calques | `map_layers/*.gd` | sol, eau, végétation, FX, meshes, props, murs, tokens | `configure()` de chaque calque |

**Séquence appliquée par `ENGINE.configure()`** (l.576-614) — ordre important car les derniers
appelés écrasent les premiers :

```
564-569  _grid_config / _lighting_config / _quality_preset / _style_cfg
570      _read_atmospheric_fog_options()
576-581  _load_ground, _load_backdrop, _load_water, _load_ambient_fx, _load_vegetation
582      _sync_table_environment()
583      _apply_camera_perspective()
584      _apply_lighting()        ← ciel, brume, tonemap, ambiante, soleil
585      _apply_render_quality()  ← SSAO/SSIL/SSR/glow/étalonnage/ombres/DOF  (écrase 584)
586      _apply_atmosphere()      ← voile + vignette (2D, au-dessus du SubViewport)
613      _rebuild_layers()
614      _update_shadow_budget(true)
```

> Conséquence : toute surcharge « globale » appliquée **après** `configure()` doit être
> réappliquée à chaque `configure()`. Les points d'accroche sont `EDITOR._sync_engine()`
> (l.3847-3858, juste après `_engine.configure(...)`) et `map_stage.gd:100-112` (session).

---

## 2. SubViewport, MSAA, screen-space AA, échelle de rendu

### 2.1 Où se trouve la vue 3D

| Élément | Chemin / fichier | Détail |
|---|---|---|
| Hôte éditeur | `game/scenes/map_editor/map_editor.tscn:129-133` | `SplitOuter/SplitInner/CenterColumn/ViewportFrame/ViewportStack` (`Control`, `%ViewportStack`) |
| Moteur instancié | `EDITOR` l.741-752 | `ComplexMapEngineScript.new()`, `editor_mode = true`, `show_camera_diagnostics = false` (l.745), ajouté à `%ViewportStack` (l.752) |
| `SubViewportContainer` | `ENGINE` l.367-381 | créé par code, **stretch = true** (l.374), `mouse_filter = IGNORE` (l.378), `TEXTURE_FILTER_LINEAR` (l.380) |
| `SubViewport` | `ENGINE` l.383-397 | `disable_3d = false`, `transparent_bg = false`, `render_target_update_mode = UPDATE_ALWAYS` (l.388), taille initiale 1280×800 (l.396) |
| `WorldEnvironment` | `ENGINE` l.399-410 | `Environment` construite à la main (l.400-408) |
| Caméra | `ENGINE` l.416-423 | `Camera3D`, ortho par défaut (`PROJECTION_ORTHOGONAL`), `keep_aspect = KEEP_HEIGHT` |
| Soleil | `ENGINE` l.425-432 | `DirectionalLight3D` « Sun » |
| Session | `game/scenes/session/panels/map_stage.tscn:36-40` | nœud `ComplexMap` + script `complex_map_engine_3d.gd` |

> **Le nom des nœuds `SubViewportContainer` / `SubViewport` est celui par défaut** (aucun
> `name =` n'est assigné). Les rechercher par type, pas par nom.

### 2.2 Réglages d'anti-aliasing et d'échelle

| Clé / propriété | Lu à | Appliqué à | Défaut | Plage / valeurs | Persistance | API publique |
|---|---|---|---|---|---|---|
| `_viewport.msaa_3d` | — | `ENGINE` l.391 | `Viewport.MSAA_2X` | `MSAA_DISABLED` / `MSAA_2X` / `MSAA_4X` / `MSAA_8X` | **Global (code, une seule fois)** | **aucune** |
| `_viewport.screen_space_aa` | — | `ENGINE` l.392 | `SCREEN_SPACE_AA_DISABLED` | `DISABLED` / `FXAA` | Global (code) | **aucune** |
| `_viewport.scaling_3d_scale` | — | `ENGINE` l.393 | `1.0` | 0.25 – 2.0 (bornes moteur) | Global (code) | **aucune** |
| TAA (`use_taa`) | — | **jamais utilisé** | — | — | — | **n'existe pas** |
| `_viewport.size` | — | piloté par `SubViewportContainer.stretch` (l.374) | suit le Control | — | — | ne pas écrire à la main (commentaire l.370-373) |

**Points durs à connaître avant d'ajouter un menu**

- `_build_viewport_tree()` **retourne immédiatement** si `_viewport` et `_ground` sont valides
  (l.355-356) : on ne peut pas « reconstruire » le viewport pour changer le MSAA, il faut écrire
  `_viewport.msaa_3d = …` directement.
- `render_target_update_mode = UPDATE_ALWAYS` (l.388) : le SubViewport rend en continu même à
  l'arrêt. Un mode « économie » pourrait passer à `UPDATE_ONCE`.
- L'échelle de rendu doit passer par `scaling_3d_scale`, **pas** par `_viewport.size` (qui est
  écrasée par le container, cf. commentaire l.369-373).
- Aucun réglage équivalent n'existe pour le viewport racine (UI 2D) : le MSAA ne concerne que
  la carte 3D.

**Test existant à imiter** : `game/scripts/tests/map_render_quality_test.gd:196-197` vérifie
`engine._viewport.msaa_3d != Viewport.MSAA_DISABLED`.

---

## 3. Preset de qualité (`classique` / `cinema`) et surcharges

### 3.1 Clé de carte

| Clé | Lu à | Appliqué à | Défaut | Valeurs | Persistance | API publique |
|---|---|---|---|---|---|---|
| `qualityPreset` | `STYLE.quality_preset()` l.263-267 ; `ENGINE` l.568 | `STYLE.config()` l.245-249 ; `ENGINE._style_cfg` | `"classique"` (`STYLE.DEFAULT_QUALITY` l.40) | `"classique"`, `"cinema"` + tolérances `"cinéma"`, `"cinema_cs2"`, `"cs2"` (l.265), casse et espaces ignorés | **Carte** | `ENGINE.set_quality_preset(preset: String) -> void` (l.850-875) ; lecture `get_quality_preset()` (l.838-839), `is_cinema_quality()` (l.842-843) ; `STYLE.quality_preset(map_data)` / `is_cinema(map_data)` (l.269-270) ; libellés `quality_label()` l.272-276, `quality_hint()` l.278-282 |
| `cinemaQuality` (dérivé) | `ENGINE` l.843, l.937 ; `MESHES` l.168 | bascule interne des blocs « cinéma » | absent en classique, `true` en cinéma (l.59) | bool | dérivé (non saisi) | — |
| `renderStyleOverrides` | `STYLE.config()` l.251-253 | idem | `{}` | dictionnaire libre de **toutes** les clés de `CONFIGS`/surcharges | **Carte** (aucune UI : JSON/main uniquement) | — |

**Écriture par l'UI** : `PANEL._apply_quality_preset()` (l.280-297) → `doc.set_meta_values({"qualityPreset": preset}, "Qualité de rendu")` (l.292).
Le signal `quality_preset_changed` (l.19, émis l.285) **n'est connecté nulle part** dans
`EDITOR._bind_settings_tab()` (l.1290-1341) : c'est `doc.changed` qui déclenche la resynchro.
`set_quality_preset()` supprime la clé en `classique` (l.860) pour garder les cartes historiques
bit-à-bit stables.

### 3.2 `STYLE.QUALITY_POST_OVERRIDES` — post-traitement du preset `cinema` (l.57-90)

Appliqués **quel que soit le type de sol** (`STYLE.config()` l.246-247).

| Clé | Valeur cinéma | Lu / appliqué à | Effet si absente (classique) |
|---|---|---|---|
| `cinemaQuality` | `true` (l.59) | `ENGINE` l.937 (`cinema`) | absent → tous les blocs `if cinema` sont sautés |
| `tonemapWhite` | `2.4` (l.62) | `ENGINE` l.1824 (`env.tonemap_white`) | `1.0` |
| `exposureScale` | `0.99` (l.63) | `ENGINE` l.1820 (`env.tonemap_exposure = exposure * exposureScale`) | `1.0` |
| `ssaoRadius` | `1.7` (l.66) | `ENGINE` l.950 | `1.35` (l.940) |
| `ssaoIntensity` | `1.75` (l.67) | `ENGINE` l.951 | `1.35` (l.941) |
| `ssaoPower` | `1.2` (l.68) | `ENGINE` l.952 | `1.15` (l.942) |
| `ssaoDetail` | `0.9` (l.69) | `ENGINE` l.953 | `0.8` (l.943) |
| `ssaoHorizon` | `0.06` (l.70) | `ENGINE` l.954 | `0.08` (l.944) |
| `ssaoLightAffect` | `0.16` (l.71) | `ENGINE` l.955 | `0.12` (l.946) |
| `ssil` | `true` (l.74) | `ENGINE` l.1001 | absent → SSIL seulement si le preset lumière l'active (`preset["ssil"]`) |
| `ssilRadius` | `6.0` (l.75) | `ENGINE` l.1007 | `5.0` (l.1013) |
| `ssilIntensity` | `0.85` (l.76) | `ENGINE` l.1008-1010 (`max(preset.ssilIntensity, cfg.ssilIntensity)`) | `preset["ssilIntensity"]` défaut `0.9` (l.1014) |
| `glowIntensityScale` | `0.82` (l.78) | `ENGINE` l.966 (multiplicatif) | `1.0` |
| `glowStrength` | `0.85` (l.79) | `ENGINE` l.967 | `0.9` (l.960) |
| `glowBloom` | `0.012` (l.80) | `ENGINE` l.968 | `0.025` (l.961) |
| `glowHdrThreshold` | `1.12` (l.81) | `ENGINE` l.969 | `1.05` (l.962) |
| `saturationFloor` / `saturationCeil` | `1.04` / `1.08` (l.85-86) | `ENGINE` l.984-987 (`clamp`) | pas de plancher |
| `contrastFloor` / `contrastCeil` | `1.08` / `1.12` (l.87-88) | `ENGINE` l.979-982 (`clamp`) | pas de plancher |

> Le preset **ne remplace pas** l'étalonnage : il borne (`max` puis `clamp`), pour conserver
> l'identité des presets lumière déjà réglés (commentaire l.975-978).

### 3.3 `STYLE.QUALITY_SURFACE_OVERRIDES` (l.96-125)

Appliqués **uniquement si le sol n'est pas un fond illustré** (`STYLE.config()` l.248-249 ;
`has_illustrated_background()` l.284-285).

| Clé | Valeur cinéma | Lu / appliqué à | Effet si absente |
|---|---|---|---|
| `shadows` | `true` (l.99) | `ENGINE` l.1804 — **écrasé ensuite par l.1042** (cf. §5) | `false` en 2.5D/diorama/DD2, `true` en VTT (`STYLE.CONFIGS`) |
| `litProps` | `true` (l.100) | `MESHES` l.164 (`_unshaded = not litProps`), `MESHES` l.168 ; `map_props_3d.gd:246` | `false` (rendu peint non éclairé) |
| `softShadows` | `true` (l.101) | **lue uniquement par les tests** (`map_quality_cs2_test.gd:108`) — clé **sans effet moteur** | — |
| `shadowBlur` | `2.2` (l.102) | `ENGINE` l.1059 (`max` avec le preset) | `preset["shadowBlur"]` défaut `1.35` (l.1043), `tiny_glade` = `1.7` |
| `shadowAngular` | `0.0` (l.107) | `ENGINE` l.1068 (`light_angular_distance`) | `preset["shadowAngular"]` défaut `0.0`, `tiny_glade` = `1.3` |
| `shadowMaxDistance` | `190.0` (l.108) | `ENGINE` l.1069-1070 | `160.0` (l.1049) |
| `shadowSplit1/2/3` | `0.10` / `0.28` / `0.52` (l.109-111) | `ENGINE` l.1072-1074 | `0.12` / `0.30` / `0.55` (l.1052-1054) |
| `contactShadowScale` | `0.45` (l.113) | `MESHES` l.169 (`clamp 0..2`) → opacité de l'ombre de contact (l.1236) | `1.0` |
| `shadowDistance` | `70.0` (l.118) | `MESHES` l.174 → `_shadow_budget_cells` ; `ENGINE._update_shadow_budget()` l.882-900 | `-1.0` = illimité |
| `materialRoughnessMin` | `0.86` (l.120) | `MESHES` l.170-172 (`max(MIN_LIT_ROUGHNESS, cfg)`) | `0.0` |
| `depthTint` | `0.16` (l.122) | `STYLE.quality_aerial_amount()` l.339-343 → `MESHES` l.1351-1352 | `0.0` (aucune perspective aérienne) |
| `depthTintColor` | `#d9cdbc` (l.123) | `STYLE.quality_aerial_color()` l.347-350 | `#d9cdbc` |

### 3.4 `STYLE.CONFIGS` — réglages par style de rendu (l.151-203)

| Clé | 2.5D (l.152-164) | diorama (l.165-177) | VTT (l.178-189) | DD2 (l.190-202) | Lu / appliqué à |
|---|---|---|---|---|---|
| `perspective` | `true` | `true` (forcé `false` si fond illustré, l.236-241) | `false` | `true` | `ENGINE._apply_camera_perspective()` l.1744-1752 |
| `fov` | `38.0` | `34.0` | `38.0` | `36.0` | `ENGINE` l.1748 (`_camera.fov`) |
| `tilt` | `-50.0` | `-52.0` (→ `-90.0` si fond illustré) | `-90.0` (→ `-72.0` par défaut ortho l.1763) | `-48.0` | `ENGINE` l.1747 / l.1763 (`rotation_degrees.x`) |
| `shadows` | `false` | `false` | `true` | `false` | `ENGINE` l.1804 (puis l.1042) |
| `litProps` | `false` | `false` | `true` | `false` | `MESHES` l.164 / `map_props_3d.gd:246` |
| `volumetricWalls` | `false` | `false` | `true` | `false` | `ENGINE` l.633 et l.2183 ; `map_walls_3d.gd:56` |
| `parallax` | `0.5` | `0.35` | `0.0` | `0.42` | `STYLE.parallax_offset()` l.307-311 → `map_props_3d.gd:182, 199, 270` |
| `depthFade` | `0.3` | `0.45` | `0.0` | `0.28` | `STYLE.depth_tint()` l.318-325 → `map_props_3d.gd:242` (découpes 2D seulement) |
| `groundTint` | `1.0` | `1.0` | `1.0` | `1.0` | **jamais lue** (cf. `docs/archive/AUDIT_CARTES.md:198`) |
| `preferFlatProps` | `false` | `true` (+ forcé si fond illustré) | `false` | `false` (jamais forcé) | `map_props_3d.gd:53` ; helper `STYLE.prefer_flat_props()` l.288-289 |

**Helpers publics utiles au menu**

| Fonction | Ligne | Rôle |
|---|---|---|
| `STYLE.style_of(map_data)` | 209-217 | résout `renderStyle` (`2.5d`/`diorama`/`vtt`/`dd2_hybrid`, défaut `diorama` si inconnu) |
| `STYLE.is_diorama()` / `is_map_25d()` / `is_dd2()` | 221-229 | famille « soft » |
| `STYLE.config(map_data)` | 231-254 | dictionnaire fusionné (tout le rendu) |
| `STYLE.style_label()` / `style_hint()` | 291-301 | libellés UI |
| `STYLE.atmosphere_color(map_data)` | 357-366 | teinte d'ambiance (`atmosphere.tint`, défaut `#141018`) |
| `STYLE.render_priority(layer, depth01)` | 352-355 | tri des découpes (borné −128..127) |

---

## 4. Post-traitement `Environment` — inventaire complet

Toutes les écritures sont dans `ENGINE._apply_render_quality()` (l.927-1076) et
`ENGINE._apply_lighting()` (l.1767-1828). L'`Environment` est créée en l.400-408 avec des
valeurs provisoires (fond `#0f0d14`, ambiante `(0.42,0.38,0.48)` énergie `0.55`, tonemap
`LINEAR`) **remplacées** au premier `configure()`.

### 4.1 Occlusion ambiante (SSAO)

| Propriété | Défaut (classique) | Cinéma | Appliqué à |
|---|---|---|---|
| `ssao_enabled` | `terrain` (l.938) — où `terrain = groundMode == "terrain3d" or is_map_25d()` (l.934) | idem | l.938 |
| `ssao_radius` | `1.35` | `cfg.ssaoRadius` (1.7) | l.940 / l.950 |
| `ssao_intensity` | `1.35` | 1.75 | l.941 / l.951 |
| `ssao_power` | `1.15` | 1.2 | l.942 / l.952 |
| `ssao_detail` | `0.8` | 0.9 | l.943 / l.953 |
| `ssao_horizon` | `0.08` | 0.06 | l.944 / l.954 |
| `ssao_sharpness` | `0.98` (jamais surchargé) | `0.98` | l.945 |
| `ssao_light_affect` | `0.12` | 0.16 | l.946 / l.955 |

> ⚠️ `terrain` inclut **`is_map_25d()`** (l.934) : une carte 2.5D en **fond illustré** reçoit
> quand même SSAO/glow/étalonnage « terrain ». Effet de bord à connaître.

### 4.2 SSIL / SDFGI / SSR

| Propriété | Condition | Valeurs | Appliqué à |
|---|---|---|---|
| `ssil_enabled` | `terrain and not table_view and (preset.ssil or cinema)` | bool | l.1000-1002 |
| `ssil_radius` | cinéma `cfg.ssilRadius` (6.0) sinon `5.0` | — | l.1007 / l.1013 |
| `ssil_intensity` | cinéma `max(preset.ssilIntensity, cfg.ssilIntensity)` sinon `preset.ssilIntensity` (0.9) | — | l.1008-1010 / l.1014 |
| `ssil_sharpness` | `0.92` cinéma / `0.9` sinon | — | l.1011 / l.1015 |
| `ssil_normal_rejection` | `1.0` | — | l.1016 |
| `sdfgi_enabled` | `terrain and not table_view and preset.gi` | bool | l.989-990 |
| `sdfgi_cascades` / `min_cell_size` / `energy` / `max_distance` | depuis le preset (`giCascades` 3, `giMinCell` 1.0, `giEnergy` 0.9, `giMaxDistance` 70) | — | l.992-999 |
| `sdfgi_normal_bias` / `use_occlusion` / `read_sky_light` / `bounce_feedback` | `1.1` / `true` / `true` / `0.45` | — | l.995-998 |
| `ssr_enabled` | `terrain and not table_view and preset.ssr` | bool | l.1017-1018 |
| `ssr_max_steps` / `fade_in` / `fade_out` / `depth_tolerance` | `64` / `0.15` / `2.0` / `0.5` | — | l.1020-1023 |
| `reflected_light_source` | `SKY` si SSR, sinon `BG` | — | l.1024 / l.1026 |

### 4.3 Glow

| Propriété | Défaut | Cinéma | Appliqué à |
|---|---|---|---|
| `glow_enabled` | `true` (toujours) | `true` | l.958 |
| `glow_intensity` | `preset.glow` (0.28 `jour`, 0.34 repli), **× 0.6 si pas terrain** | `× cfg.glowIntensityScale` (0.82) | l.957-959 / l.966 |
| `glow_strength` | `0.9` | 0.85 | l.960 / l.967 |
| `glow_bloom` | `0.025` | 0.012 | l.961 / l.968 |
| `glow_hdr_threshold` | `1.05` | 1.12 | l.962 / l.969 |
| `glow_blend_mode` | `GLOW_BLEND_MODE_ADDITIVE` (fixe) | idem | l.963 |

### 4.4 Tonemap et étalonnage

| Propriété | Défaut | Cinéma | Appliqué à |
|---|---|---|---|
| `tonemap_mode` | `TONE_MAPPER_ACES` (l.1819) — la valeur `LINEAR` de l.407 est écrasée | ACES | l.1819 |
| `tonemap_exposure` | `lighting.exposure` ou `preset.exposure` (1.0) | `× 0.99` | l.1776 puis l.1820 |
| `tonemap_white` | `1.0` | 2.4 | l.1824 |
| `adjustment_enabled` | `true` | `true` | l.970 |
| `adjustment_brightness` | `preset.brightness` (1.05) | inchangé | l.971 |
| `adjustment_contrast` | `preset.contrast` (1.06) | `clamp(max(val, 1.08), 1.08, 1.12)` | l.972 / l.979-982 |
| `adjustment_saturation` | `preset.saturation` (1.10) si terrain, sinon `1.0` | `clamp(max(val, 1.04), 1.04, 1.08)` si terrain | l.973 / l.983-987 |

### 4.5 Profondeur de champ

| Propriété | Valeur | Appliqué à |
|---|---|---|
| Activation | `terrain and projection == PERSPECTIVE and not table_view` | `ENGINE._apply_depth_of_field()` l.800 |
| `dof_blur_far_enabled` | = activation | l.803 |
| `dof_blur_far_distance` | `58.0` | l.804 |
| `dof_blur_far_transition` | `20.0` | l.805 |
| `dof_blur_amount` | `0.035` | l.806 |
| `dof_blur_near_enabled` | `false` | l.807 |
| Report sur la caméra | `_camera.attributes = _camera_attributes if dof_on else null` | l.809 |

Lecture publique : `ENGINE.get_camera_attributes()` (l.822-825).

---

## 5. Ombres

| Paramètre | Lu à | Appliqué à | Défaut | Plage / valeurs | Persistance | API publique |
|---|---|---|---|---|---|---|
| `shadows` (style + cinéma) | `STYLE.CONFIGS` / `QUALITY_SURFACE_OVERRIDES` | `ENGINE` l.1804 **puis** l.1042 | 2.5D/diorama/DD2 : `false` ; VTT : `true` ; cinéma : `true` | bool | Carte | **aucune** (seulement via preset/style) |
| `_sun.shadow_enabled` (état effectif) | — | l.1042 (`terrain and not table_view`) ; l.1793 en vue table (`false`) | `true` dès qu'il y a un sol terrain | bool | — | — |
| `shadowBlur` | `STYLE` l.102 | `ENGINE` l.1043 puis l.1059 (`max`) | `preset.shadowBlur` (1.35) ; cinéma ≥ 2.2 | 0 – 16 (propriété moteur) | Carte | aucune |
| `shadowAngular` | `STYLE` l.107 | `ENGINE` l.1048 / l.1068 (`light_angular_distance`) | `0.0` ; `tiny_glade` = 1.3 ; **cinéma force 0.0** | 0 – 90° | Carte (via preset lumière ou surcharge) | aucune |
| `directional_shadow_mode` | — | l.1050 (`ORTHOGONAL`) / l.1058 (`PARALLEL_4_SPLITS` en cinéma) | ORTHOGONAL | `ORTHOGONAL`, `PARALLEL_2_SPLITS`, `PARALLEL_4_SPLITS` | Global (code) | aucune |
| `directional_shadow_blend_splits` | — | l.1046 | `true` (toujours) | bool | Global | — |
| `directional_shadow_max_distance` | `shadowMaxDistance` | l.1049 (160) / l.1069 (190 cinéma) | `160.0` | 0 – 16384 | Carte (cinéma) | — |
| `directional_shadow_fade_start` | — | l.1051 (0.8) / l.1071 (0.85 cinéma) | `0.8` | 0 – 1 | Global | — |
| `directional_shadow_split_1/2/3` | `shadowSplit1/2/3` | l.1052-1054 / l.1072-1074 | `0.12`/`0.30`/`0.55` ; cinéma `0.10`/`0.28`/`0.52` | croissants 0 – 1 | Carte (cinéma) | — |
| `shadow_bias` | — | l.1044 (0.04) / l.1062 (0.06 cinéma) | `0.04` | — | Global | — |
| `shadow_normal_bias` | — | l.1045 (1.0) / l.1063 (2.0 cinéma) | `1.0` | — | Global | — |
| `shadowDistance` (budget) | `STYLE` l.118 | `MESHES.update_shadow_budget()` l.215-250 ; `ENGINE._update_shadow_budget()` l.882-900 | `-1` en classique, `70.0` en cinéma | cases ; `-1` = illimité ; hystérésis `SHADOW_BUDGET_HYSTERESIS` | Carte | `ENGINE.set_shadow_budget_cells(cells)` l.910-913 ; `get_shadow_budget_cells()` l.903-906 ; `MESHES.set_shadow_budget_cells()` l.254-275 ; diagnostics `get_active_shadow_casters()` l.916-919, `get_shadow_caster_count()` l.922-925 |
| Casting des meshes 3D | `MESHES` l.1288-1300 | `GeometryInstance3D.cast_shadow` par objet | `OFF` en classique, `ON` si `_cinema_quality` **et** objet proche du point visé | `ON` / `OFF` | dérivé | `MESHES.update_shadow_budget(focus)` ; reconstruction `ENGINE.refresh_meshes_only()` l.620-633 |
| Casting du sol | — | `GROUND` l.661 (`OFF` en terrain3d) ; `GROUND` l.706 (mode illustré : `ON` sauf `unshaded`/nuit) | OFF (terrain3d) | — | code | — |
| Casting eau / végétation / FX / backdrop / brouillard | — | `WATER` l.136, 566, 603, 2018, 2023 ; `VEG` l.128-143, 436 ; `FX` l.257 ; `map_backdrop_3d.gd:123` ; `map_fog_3d.gd:67` | **toujours OFF** | — | code | — |
| Taille de la shadow map | — | **aucune écriture** dans le dépôt | défaut projet Forward+ (`rendering/lights_and_shadows/directional_shadow/size`, absent de `game/project.godot`) | 256 – 16384 | projet | **n'existe pas** |

**Divergence à corriger avant d'exposer un interrupteur d'ombres** : `_apply_lighting()` écrit
`_sun.shadow_enabled = terrain3d and cfg.shadows` (l.1804), `_apply_render_quality()` écrit
`_sun.shadow_enabled = terrain and not table_view` (l.1042) et passe **après** dans
`configure()` (l.584-585). Mais `set_ground_mode()` (l.1493-1503) et
`set_atmospheric_fog_enabled()` (l.2019-2021) n'appellent que `_apply_lighting()` : après un
changement de mode de sol, une carte 2.5D se retrouve **sans ombres** alors qu'elle en avait.
Le test `game/scripts/tests/map_render_quality_test.gd:39` attend `shadow_enabled == true` pour
une 2.5D terrain, ce qui n'est vrai qu'après `_apply_render_quality()`.

---

## 6. Brume, ciel, perspective aérienne

### 6.1 Brume atmosphérique de distance (clé `atmosphericFog`)

Variables d'instance (valeurs par défaut) : `ENGINE` l.114-127.

| Paramètre | Type | Défaut | Lu à | Appliqué à |
|---|---|---|---|---|
| `atmospheric_fog_enabled` | bool (A/B global) | `true` (l.114) | `_atmospheric_fog_active()` l.1855 | coupe toute la brume atmosphérique |
| `atmospheric_tilt_aware` | bool | `true` (l.117) (surchargeable par `atmosphericFog.tiltAware`, l.1843-1848) | `get_atmospheric_fog_height_factor()` l.1932-1938 | pondère la composante hauteur par le pitch caméra |
| `atmospheric_fog_intensity` | float 0..1 | `0.30` (l.119) | l.1870-1871 | `env.fog_density` |
| `atmospheric_fog_color` | Color | `(0.44, 0.46, 0.60, 1)` (l.122) | l.1872 | `env.fog_light_color` |
| `atmospheric_fog_height` | float | `-1.0` (l.126) | l.1886 | `env.fog_height` |
| `atmospheric_fog_height_density` | float | `0.22` (l.127) | l.1890-1892 | `env.fog_height_density` × facteur de tilt (borné 0..4) |
| Constantes de bande | — | `ATMOS_FOG_NEAR_MIN 8.0`, `BEGIN_RATIO 0.95`, `END_RATIO 1.5`, `MIN_SPAN 9.0`, `DEPTH_CURVE 1.0` | l.85-94 | `_sync_atmospheric_fog_depth()` l.1979-1997 |
| Constantes de tilt | — | `ATMOS_TILT_TOP_DEG 72`, `LOW_DEG 22`, `TOP_FACTOR 0.0` | l.107-111 | l.1936-1938 |

Clés optionnelles de carte `map_data["atmosphericFog"]` = dictionnaire
(`_atmospheric_fog_config()` l.1836-1838) :

| Sous-clé | Type | Effet | Appliqué à |
|---|---|---|---|
| `enabled` | bool | force l'activation/désactivation (prioritaire sur `preset.atmosFog`) | l.1857-1859 |
| `density` | 0..1 | densité | l.1870-1871 |
| `color` | hex | teinte | l.1873-1874 |
| `height` | float | hauteur monde de référence | l.1886 |
| `heightDensity` | float | densité de hauteur (avant facteur de tilt) | l.1890-1892, l.1950 |
| `tiltAware` | bool | A/B de la pondération par l'angle | l.1846-1847 |

API publique existante : `set_atmospheric_fog_enabled(on)` l.2019-2021,
`is_atmospheric_fog_enabled()` l.2023-2024, `set_atmospheric_tilt_aware(on)` l.1967-1971,
`is_atmospheric_tilt_aware()` l.1973-1974, `sync_atmospheric_fog()` l.2014-2016,
`get_atmospheric_fog_settings()` l.2027-2042 (dictionnaire de diagnostic),
`get_atmospheric_fog_height_factor()` l.1932-1938.
**Manque** : un setter pour `density`, `color`, `height`, `heightDensity` (aujourd'hui
uniquement par `map_data` + `configure()`).

### 6.2 Brume exponentielle historique et presets lumière

| Propriété `Environment` | Source | Appliqué à |
|---|---|---|
| `fog_mode` | `FOG_MODE_DEPTH` si brume atmosphérique (l.1877) sinon `FOG_MODE_EXPONENTIAL` (l.1899) | l.1877 / l.1899 |
| `fog_enabled` | `terrain3d and presetDensity > 0.0001` (l.1902) | l.1902 |
| `fog_density` | `lighting.fogDensity` ou `preset.fogDensity` (l.1777) | l.1904 |
| `fog_light_color` | `preset.fogColor` (défaut `#2b3445`) | l.1903 |
| `fog_light_energy` | `preset.fogLightEnergy` (1.0) | l.1881 / l.1907 |
| `fog_aerial_perspective` | `preset.aerial` (0.0 ; `tiny_glade` 0.35) | l.1884 / l.1905 |
| `fog_sun_scatter` | `preset.sunScatter` (0.0 ; `tiny_glade` 0.18) | l.1885 / l.1906 |
| `fog_sky_affect` | `preset.fogSkyAffect` (0.0 ; `tiny_glade` 0.20) | l.793 / l.773 |

### 6.3 Brume volumétrique

| Propriété | Source | Défaut | Appliqué à |
|---|---|---|---|
| `volumetric_fog_enabled` | `terrain and not table_view and preset.volumetricFog` | `false` (sauf `tiny_glade`) | l.1028-1029 |
| `volumetric_fog_density` | `preset.volumetricDensity` | `0.008` | l.1031 |
| `volumetric_fog_albedo` | `preset.volumetricColor` | `#fff1de` | l.1032 |
| `volumetric_fog_emission` / `emission_energy` | fixes | noir / `0.0` | l.1033-1034 |
| `volumetric_fog_anisotropy` / `length` / `gi_inject` / `ambient_inject` | fixes | `0.35` / `120.0` / `0.4` / `0.2` | l.1035-1038 |

### 6.4 Ciel procédural

| Paramètre | Source | Défaut | Appliqué à |
|---|---|---|---|
| `sky` (activation) | `preset.sky` **et** `terrain3d` **et** `not table_view` | `false` (sauf `tiny_glade`) | `_apply_sky()` l.767 |
| `skyTop` / `skyHorizon` / `skyGroundBottom` | preset | `#9fd0e8` / `#ffe9cf` / `#e9e2d4` | l.782-789 |
| `sunGlow` | preset | `1.2` | l.788-789 |
| `skyEnergy` | preset | `1.0` | l.792 |
| `Sky.radiance_size` | code | `RADIANCE_SIZE_256` | l.759 |
| Shader ciel (uniforms) | code | `top_color`, `horizon_color`, `ground_color`, `sun_glow` | `_ensure_sky()` l.726-759 |
| Lecture publique | — | — | `is_sky_active()` l.812-816 ; `get_sky_material()` l.818-819 |

**Aucun setter** pour les couleurs du ciel : uniquement via `map_data["lighting"]["preset"]`
(ou un `renderStyleOverrides` ne fonctionne pas ici, ce sont des clés de **preset lumière**).

### 6.5 Perspective aérienne (objets 3D)

| Paramètre | Lu à | Appliqué à | Défaut | Effet si `classique` |
|---|---|---|---|---|
| `depthTint` | `STYLE.quality_aerial_amount()` l.339-343 | `MESHES` l.1351-1352 | `0.0` | aucun |
| `depthTintColor` | `STYLE.quality_aerial_color()` l.347-350 | idem | `#d9cdbc` | — |
| `depthFade` (découpes 2D) | `STYLE.depth_tint()` l.318-325 | `map_props_3d.gd:242` | par style (0 → 0.45) | actif dans tous les presets |

---

## 7. Voile d'ambiance et vignettage (2D, par-dessus la 3D)

`ENGINE._apply_atmosphere()` l.2044-2074 ; `_set_vignette_strength()` l.2077-2081.

| Paramètre | Clé `map_data` | Défaut | Appliqué à | Plafonds appliqués |
|---|---|---|---|---|
| Activation | `atmosphere.enabled` | `false` (`MAPDATA.ensure_map_schema` l.808) / `true` (`create_complex_map` l.917) | l.2053 | — |
| Teinte | `atmosphere.tint` | `#1a1410` (schéma) / `#141018` (création) | l.2054, 2062 (`ColorRect.color`) | — |
| Opacité | `atmosphere.opacity` | `0.25` / `0.12` | l.2056-2062 | `min 0.10` si diorama (l.2058), `min 0.04` si fond illustré (l.2060) |
| Vignettage | `atmosphere.vignette` | `0.18` / `0.18` | l.2063-2064 | `min 0.08` illustré, `min 0.18` diorama, sinon valeur brute |
| Vignettage (sans ambiance) | — | — | l.2069-2074 | `0.12` diorama, `0.12` MJ / `0.20` joueur |
| Vignette (uniform shader) | — | `strength = 0.18`, `tint = (0.05,0.04,0.08)` | `_make_vignette_material()` l.709-722 | borné 0..0.6 (l.2081) |
| Lecture publique | — | — | `get_vignette_strength()` l.828-831 | — |
| **Setter public** | — | — | **absent** : `_set_vignette_strength()` est privé (l.2077) | — |

---

## 8. Eau

### 8.1 Clés de carte

| Clé | Lu à | Appliqué à | Défaut | Plage | API publique |
|---|---|---|---|---|---|
| `waterLevel` | `ENGINE._load_water()` l.1300 ; `MAPDATA.ensure_map_schema` l.839-840 | `WATER.configure()` l.1311-1313 | `-1.0` (aucune) | `-1.0` … hauteur de relief ; UI : **−1 … 8** pas 0.1 (`PANEL` l.129-132) | `ENGINE.set_water_level(level)` l.1328-1342 ; `get_water_level()` l.1345-1346 ; `WATER.set_water_level()` l.218-221 |
| `waterDecorDensity` | `ENGINE` l.1312, 1340 | `WATER.configure(decor_density)` l.167 (`clamp 0..4`) | `1.0` | `0.0` … `4.0` (UI 0..3) | via `configure()` |
| `waterDecorSeed` | `ENGINE` l.1312, 1340 | `WATER._rebuild_decor()` l.2068-2106 | `1` | `1` … `99999` (UI) | via `configure()` |
| `waterBodies` | `ENGINE` l.1313, 1341 | `WATER._rebuild_bodies()` l.683 ; `_build_lake_body()` l.828 ; `_build_river_body()` l.879 | `[]` | lacs (`level`, `area`) / rivières (`path`, `flow_speed`, …) | `WATER.set_water_bodies()` l.239-242 |
| `terrainHeights` / `terrainCarves` / `terrainSculpt` | `ENGINE` l.1436-1441 | immersion, profondeur, berges | `[]` / `{}` | — | `ENGINE.refresh_terrain()` l.1563-1634 |

### 8.2 Densités de décor (lentilles / nénuphars)

| Constante | Valeur | Ligne | Effet |
|---|---|---|---|
| `DUCKWEED_DENSITY` | `0.26` | `WATER` l.56 | probabilité par case immergée (× `_decor_density`) |
| `LILY_DENSITY` | `0.05` | l.57 | idem, limité aux hauts-fonds (`LILY_SHALLOW_DEPTH 0.22`, l.61) |
| `DUCKWEED_MAX` / `LILY_MAX` | `2400` / `360` | l.58-59 | bornes de performance |
| `DUCKWEED_COLOR` / `LILY_PAD_COLOR` | `(0.30,0.54,0.25)` / `(0.16,0.42,0.20)` | l.54-55 | couleurs |
| Compteurs | — | `get_duckweed_count()` l.2038-2039, `get_lily_count()` l.2042-2043 | diagnostic |

> Particularité déterministe : si des hauts-fonds existent mais qu'aucun nénuphar n'a été tiré,
> **un** nénuphar est posé (l.2096-2109) — sauf si `waterDecorDensity == 0`.

### 8.3 Réflexions / réfractions / qualité de l'eau

**Aucune clé de carte, aucun setter public.** Les uniforms sont posés par
`WATER._make_body_material()` (l.1757-1900), avec deux jeux de valeurs (lac vs rivière) :

| Uniform | Lac | Rivière (`edge_softness > 0`) | Ligne |
|---|---|---|---|
| `reflection_enabled` / `reflection_strength` | `1.0` / `0.35` | `1.0` / `0.32` | l.1795-1796 (valeurs), l.1877-1878 (écriture) |
| `refraction_enabled` / `refraction_strength` | `1.0` / `0.35` | `1.0` / `0.40` | l.1800-1801, l.1882-1883 ; défauts shader `1.0` / `0.35` (`game/shaders/water_surface.gdshader:136,139`) |
| `sky_reflect` | `0.24` | `0.22` | l.1791 / l.1828 |
| `depth_extinction` / `depth_bias` | `2.2` / `0.0` | `1.6` / `-0.28` | l.1784-1785 / l.1821-1822 |
| `base_alpha` / `alpha_depth` | `0.78` / `0.10` | idem | l.1849-1850 (`WATER` l.43-44) |
| `wave_strength` / `wave_speed` | `0.08` / `0.8` | `0.18` / `1.1` | l.1771-1772 / l.1810-1811 |
| `foam_strength` / `foam_width` / `foam_scale` | `0.62` / `0.05` / `1.8` | `0.75` / `0.07` / `2.4` | l.1769-1774 / l.1808-1813 |
| `glint_strength` / `caustic_strength` | `0.9` / `0.45` | `1.0` / `0.28` | l.1775-1776 / l.1814-1815 |
| `shore_texels` | `0.6` | `1.2` | l.1790 / l.1827 |
| `night_tint` | `NIGHT_TINT` si nuit | idem | l.1848 |
| `flow_visual_scale` | — | `RIVER_FLOW_VISUAL_SCALE = 0.10` | l.1869 (`WATER` l.50) |

Setters publics existants sur la couche eau (aucun ne touche réflexion/réfraction) :

| Fonction | Ligne | Rôle |
|---|---|---|
| `set_mist_enabled(on)` / `is_mist_enabled()` | 611-621 | brume de pied de cascade (`mist_enabled`, `MIST_MAX_QUADS 64` l.529) |
| `set_bed_ambient_lift(amount)` | 645-650 | éclairage double du lit (`bed_ambient_lift`, défaut `BED_AMBIENT_LIFT 1.0` l.541) |
| `set_tip_soften(amount)` | 658-661 | adoucissement des pointes (`TIP_SOFTEN_DISTANCE 1.0` l.544) |
| `set_night_mode(on)` | 246-275 | teinte de nuit sans rebuild |
| `set_terrain_carves()` / `set_terrain_heights()` | 224-236 | recalcule l'immersion |

Le patron de traversée des matériaux de surface existe déjà dans un test :
`game/scripts/tests/water_quality_shot_test.gd:302-328` (`_refraction_materials()` +
`_set_refraction()`), utilisable tel quel pour un vrai setter.

---

## 9. Terrain

### 9.1 Clés de carte et qualité

| Clé | Lu à | Appliqué à | Défaut | Plage | API publique |
|---|---|---|---|---|---|
| `groundMode` | `MAPDATA.get_ground_mode()` l.623-629 ; `ENGINE` l.1085 | `_load_ground()` l.1078-1130 ; calques | `terrain3d` (ou `illustrated` si fond illustré) | `"terrain3d"`, `"illustrated"` | `ENGINE.set_ground_mode(mode)` l.1493-1503 ; `get_ground_mode()` l.1482-1483 ; `is_terrain3d_ground()` l.1486-1487 |
| `terrainDetail` | `ENGINE` l.1121 | `GROUND._apply_config()` l.632 (`clamp 1..4`) ; résolution Marching Cubes l.472 | `1` | **1 … 4** | via `configure()` (aucun setter) |
| `terrainHeights` | `ENGINE._sync_terrain_from_map()` l.1428-1435 | `GROUND.configure()` ; `refresh_terrain()` | `[]` | floats par case (0 = plat) | `ENGINE.refresh_terrain(map)` l.1563 ; `set_terrain_materials()` l.1465-1468 |
| `terrainMaterials` | l.1436 | `GROUND.set_terrain_materials()` | `[]` | 0 herbe, 1 terre, 2 pierre, 3 neige, 4 sable (`MAPDATA` l.15-20) | `get_terrain_materials()` l.1459-1460 |
| `terrainCarves` | l.1437 | `GROUND.set_terrain_carves()` | `[]` | primitives SDF normalisées | `set_terrain_carve_preview(on)` l.1551-1555 |
| `terrainSculpt` | l.1438-1439 | `GROUND.set_terrain_sculpt()` l.424 | `{}` | grille de déplacement (voxels, `SCULPT_RES` dans `terrain_carve_field.gd:74`) | `set_terrain_sculpt()` l.309-313 |

### 9.2 Finitions « CS2 » du terrain (uniformes, A/B réversibles)

Toutes ces valeurs sont des **constantes de code**, réglables à chaud via un setter, jamais
persistées.

| Uniform | Constante / défaut | Setter public | Getter | Ligne (setter) |
|---|---|---|---|---|
| `cliff_strata` (strates) | `TERRAIN_CLIFF_STRATA = 1.0` (l.103) | `GROUND.set_cliff_strata(amount)` (0..1) | `get_cliff_strata()` | 795-800 |
| `macro_variation` | `TERRAIN_MACRO_VARIATION = 1.0` (l.105) | `set_macro_variation(amount)` (0..1) | `get_macro_variation()` | 803-808 |
| `snow_transition` (neige) | `TERRAIN_SNOW_TRANSITION = 1.0` (l.108) | `set_snow_transition(amount)` (0..1) | `get_snow_transition()` | 811-816 |
| `terrain_object_ao` (ancrage) | `TERRAIN_OBJECT_AO = 1.0` (l.111) | `set_terrain_object_ao(amount)` (0..1) | `get_terrain_object_ao()` | 819-826 |
| `auto_min_relief` | `TERRAIN_AUTO_MIN_RELIEF = 0.8` (l.90) | `set_auto_min_relief(amount)` (0..4) | `get_auto_min_relief()` | 831-836 |
| `cavity_bake` (AO de cuvettes) | `TERRAIN_CAVITY_BAKE = 1.0` (l.94) | **aucun setter** (valeur posée l.977) | — | — |
| `slab_strata` (strates du socle) | `SLAB_STRATA = 1.0` (l.156) | `set_slab_strata(amount)` (0..1) | `get_slab_strata()` | 1805-1811 |
| `bed_ambient_lift` (lit d'eau) | `TERRAIN_BED_AMBIENT_LIFT = 1.0` (l.99) | voir `WATER.set_bed_ambient_lift()` | — | `WATER` 645 |
| `object_ao_enabled` | dérivé de la présence d'empreintes | `set_object_occlusion_stamps(stamps)` ; `clear_object_occlusion()` | `has_object_occlusion()` l.858-859 | 844-856 |

Constantes de la **cavité** (non exposées) : `CAVITY_RING_RADII [1,2]` (l.117),
`CAVITY_SCALE_CELLS 0.45` (l.119), `CAVITY_DARKEN 0.32` (l.121), `CAVITY_LIGHTEN 0.06` (l.123)
→ `_compute_cavity_ao()` l.1448-1495, `_vertex_cavity_ao()` l.1495.

Constantes du **socle / falaise** (non exposées) : `CLIFF_DEPTH_CELLS 2.5` (l.134),
`CLIFF_LIP_CELLS 0.45` (l.145), `SLAB_FINITIONS 1.0` (l.154), `SLAB_LIP_CELLS 0.55` (l.158),
`SLAB_WALL_ROWS 4` (l.162), `SLAB_BASE_FLARE_CELLS 0.85` (l.164).

### 9.3 Sculpture et creusement (outils, état de session)

| Paramètre | Variable | Défaut | Plage (UI) | Ligne |
|---|---|---|---|---|
| Rayon de brosse 3D | `EDITOR._carve_radius` | `1.2` (l.81) | **0.3 … 6.0** (`map_editor_tool_options.gd:775`, raccourci `[` `]` l.3381) | 775-778 |
| Force de sculpture | `EDITOR._sculpt_strength` | `0.6` (l.85) | **0.05 … 4.0** (l.780) | 780-782 |
| Rayon du pinceau de relief | `EDITOR._relief_radius` | `1.5` (l.76) | **0.5 … 8.0** (l.881) | 881-884 |
| Intensité du relief | `EDITOR._relief_strength` | `0.35` (l.77) | **0.05 … 2.0** (l.886) | 886-889 |
| Mode de relief | `EDITOR._relief_mode` | `"raise"` (l.78) | raise / lower / flatten / smooth / carve / fill | — |
| Décalage de creusement | `EDITOR._carve_offset` | `0.4` (l.82) | — | — |
| Dégradé de brosse | `EDITOR._brush_falloff` | `0` (l.88) | 6 courbes (l.86-89) | — |
| Auto-lissage | `EDITOR._brush_auto_smooth` | `0.0` (l.89) | — | — |
| Symétrie X/Y/Z | `EDITOR._sym_x/_sym_y/_sym_z` | `false` (l.98-100) | bool | — |
| Aperçu basse résolution | `ENGINE._terrain_carve_preview` | `false` (l.161) | bool | `set_terrain_carve_preview()` l.1551 ; résolution MC l.462-472 |
| Opérations | — | 21 opérations Blender-like | `doc.sculpt_*` (`map_edit_document.gd:1559-1740`) | `EDITOR` l.2634-2700 |

> Ces valeurs sont un **état de session** : elles ne sont **pas** dans `map_data` et sont
> perdues à la fermeture de l'éditeur.

---

## 10. Végétation procédurale

| Clé / constante | Lu à | Appliqué à | Défaut | Plage | Persistance | API publique |
|---|---|---|---|---|---|---|
| `vegetationEnabled` | `ENGINE._vegetation_wanted()` l.1200 | `_load_vegetation()` l.1205-1221 | **`false`** (l.1200 ; nettoyage visuel assumé, commentaire l.1198-1199) | bool | **Carte** | via `configure()` ; aucune fonction dédiée |
| `vegetationDensity` | `ENGINE` l.1218 ; `MAPDATA.ensure_map_schema` (absent → `1.0` implicite) | `VEG.configure(density)` l.160, l.168 (`clamp 0..4`) ; multiplicateurs l.332-369 | `1.0` | `0.0` … `4.0` (UI 0..3, pas 0.1) | Carte | — |
| `TUFT_DENSITY` | `VEG` l.25 | l.332 | `0.85` | 0..1 | Global | — |
| `FLOWER_DENSITY` | l.30 | l.343 | `0.18` | 0..1 | Global | — |
| `BUSH_DENSITY` | l.32 | l.354 | `0.16` | 0..1 | Global | — |
| `LEAF_DENSITY` | l.34 | l.369 | `0.30` | 0..1 | Global | — |
| `MAX_TUFTS` / `MAX_FLOWERS` / `MAX_BUSHES` / `MAX_LEAVES` | l.36-39 | l.332-369 | `5000` / `1800` / `900` / `3200` | Global | — | — |
| Activation conditionnelle | `_vegetation_wanted()` l.1193-1202 | — | sol `terrain3d` + pas vue table + style 2.5D/diorama | — | — | — |

Diagnostics : `ENGINE.is_vegetation_active()` l.1224-1227, `get_vegetation_count()` l.1230-1235,
`get_vegetation_counts()` l.1238-1246 (`tufts`/`flowers`/`bushes`/`leaves`).
Couleurs et shader de vent : `VEG` l.44-96.

> Les fleurs ne sont **pas** une clé séparée : elles suivent `FLOWER_DENSITY × density`. Pour
> n'avoir que des touffes, il faut passer par le shader/les constantes (non exposé).

---

## 11. Particules d'ambiance, nuit, lumières révélées

### 11.1 Effet d'ambiance

| Clé / paramètre | Lu à | Appliqué à | Défaut | Valeurs | Persistance | API publique |
|---|---|---|---|---|---|---|
| `ambientFx` | `ENGINE._load_ambient_fx()` l.1365 | `FX.configure()` l.1375-1376 | `""` (`MAPDATA` l.846-847) | `""`, `fireflies`, `dust`, `leaves`, `rain`, `snow` (`FX.EFFECTS` l.28) ; toute autre valeur ignorée | **Carte** | `ENGINE.set_ambient_fx(name)` l.1380-1392 ; `get_ambient_fx()` l.1395-1396 ; `is_ambient_fx_active()` l.1399-1402 |
| Nombre de particules | `FX.EFFECT_CONFIGS[*].amount` | `_rebuild()` l.234-316 | fireflies 48, dust 64, leaves 40, rain 160, snow 90 (l.34, 52, 70, 90, 111) | entier | Global | `FX.get_particle_count()` l.195 |
| Durée de vie | `lifetime` | idem | 6 / 9 / 8 / 1.4 / 10 s | — | Global | — |
| Émission | `emission` | `_make_particle_material()` l.346-377 | 0.9 / 0.12 / 0 / 0.04 / 0.10 | — | Global | — |
| Taille | `scale_min`/`scale_max` | idem | variable par effet | — | Global | — |

Activation conditionnelle : sol `terrain3d` uniquement (`ENGINE` l.1368-1371).

### 11.2 Mode nuit

| Paramètre | Lu à | Appliqué à | Défaut | Plage | Persistance | API publique |
|---|---|---|---|---|---|---|
| `lighting.nightMode` | `MAPDATA.is_night_mode()` l.681-682 | `ENGINE._load_ground()` l.1090 ; `WATER`/`VEG`/`FX`/backdrop (teintes) | `false` (`MAPDATA` l.112) | bool | **Carte** | via `doc.set_meta_values({"lighting": …})` (EDITOR l.4575) |
| `lighting.nightAmbient` | `ENGINE` l.1106 | texture de nuit du sol illustré (`GROUND`) | `0.22` | UI **0.05 … 1.0** (`TSCN` l.469-472) | Carte | — |
| `lighting.sources` | `ENGINE` l.1107 | masque de lumière `GROUND.update_light_mask()` l.708-721 | `[]` | liste `{x, y, radius}` | Carte | `ENGINE.refresh_night_light_mask(sources, revealed)` l.2856-2863 |
| `playDefaults.lightRevealed` | `ENGINE` l.1108-1110 | masque de lumière (cases persistantes) | `[]` | liste `"x,y"` | Carte (`playDefaults`) | `doc.clear_light_reveal()` (`EDITOR` l.1312-1316) |
| Teintes de nuit par calque | `GROUND` l.129 (`TERRAIN_NIGHT_TINT`), `WATER` l.42 (`NIGHT_TINT`), `VEG` l.42, `FX` l.349-367 | uniforms `night_tint` / `albedo_tint` | constantes | — | Global | — |

> Le mode nuit n'est **pas** un simple filtre : en mode `illustrated` il bascule sur une image
> nuit (`MAPDATA.load_night_texture()` l.711-723) et un masque de lumière par case.

---

## 12. Caméra

| Paramètre | Lu à | Appliqué à | Défaut | Plage / valeurs | Persistance | API publique |
|---|---|---|---|---|---|---|
| Projection | `STYLE.CONFIGS.perspective` | `ENGINE._apply_camera_perspective()` l.1744-1765 | selon style (2.5D/diorama/DD2 : perspective ; VTT : ortho) | `PROJECTION_PERSPECTIVE` / `PROJECTION_ORTHOGONAL` | Carte (via style/fond) | **aucune** |
| `perspective` (clé carte) | `MAPDATA.get_perspective()` l.765-769 | `ENGINE` l.1756-1764 (uniquement si le style n'est pas en perspective) | `"topdown"` | `"topdown"`, `"isometric"`, `"perspective"` (`MAPDATA` l.148-150) | **Carte** | via `doc.set_meta_values` (EDITOR l.4310-4316) |
| FOV | `cfg.fov` | `ENGINE` l.1748 | 38 / 34 / 38 / 36 | 1 – 179 (moteur) | Carte (via style) | **aucune** |
| FOV vue table | `ENGINE.TABLE_FOV` l.62 | l.1740 | `50.0` | constante | Global | — |
| Tilt (pitch) | `cfg.tilt` | l.1747 (perspective) / l.1763 (ortho) | −50 / −52 / −90 / −48 | **non borné dans le code** (valeurs de style observées : −90 … −48) | Carte | **aucune** |
| Tilt isométrique | — | l.1759 (`rotation_degrees = (-58, 45, 0)`) | `-58` / `45` | constantes | Global | — |
| Hauteur caméra | `ENGINE.CAM_HEIGHT` l.60 | l.1760, 1764 ; `_style_camera_height()` l.2380-2382 | `48.0` (× 0.72 en perspective, × 0.85 sinon) | — | Global | — |
| Zoom | `ENGINE.zoom` l.129 | `_update_ortho_size()` l.2365-2377 | `1.0` | **`MIN_ZOOM 0.25` … `MAX_ZOOM 12.0`** (l.53-54) | **`playDefaults.viewState.zoom`** (sauvegardé par `EDITOR.apply_to_map_data()` l.544-547) | `zoom_in()` l.3990, `zoom_out()` l.3993, `reset_zoom()` l.3996 ; `_apply_zoom(factor, anchor)` l.2594 ; `zoom_changed` signal l.12 |
| Zoom → taille ortho | — | l.2374 (`_camera.size = _base_ortho_size / zoom`) | — | — | — | — |
| Zoom → distance (perspective) | — | l.2372 (`position.y = _base_camera_height / zoom`) | — | — | — | — |
| Échelle effective (px/case) | — | `get_effective_scale()` l.3982-3988 | — | — | — | lecture publique |
| Orbite (pas / limites) | `_update_orbit_drag()` l.3472-3483 | yaw libre, pitch **−89 … −8** (l.3477), sensibilité `0.38` / `0.28` px→deg | — | — | UI | `begin_view_pan()` l.3440, `_begin_orbit_drag()` l.3448 |
| Recadrage (« Cadrer ») | `_fit_to_view()` l.2538-2561 | `zoom = 1.0`, marge `1.06` (l.2536) / `1.08` (l.2507) | — | — | — | `request_fit_to_view()` l.646-649 ; `reset_editor_camera()` l.3486-3491 ; `focus_grid_rect()` l.2790 |
| Marges HUD (insets) | `_view_inset` l.174 | `_usable_viewport_size()` l.2353-2358 | `Vector4.ZERO` | pixels | UI (session) | `set_view_inset(l,t,r,b)` l.696-699 |
| Centrage | — | `center_on_grid()` l.2764, `center_on_grid_smooth()` l.2774, `_center_focus_on()` l.2478-2488 | — | — | — | publiques |
| Vue table — élévation | `_table_elev` l.181 | `_apply_table_camera()` ; `set_table_elevation()` l.3601-3604 | `32.0` | **`TABLE_ELEV_MIN 18` … `TABLE_ELEV_MAX 78`** (l.63-64) | `viewState.tableElev` | `set_table_elevation(deg)` |
| Vue table — place | `_table_seat` l.182 | `set_table_seat()` l.3578-3584 | `0` (sud) | 0-3 (yaw = 90 × siège) | `viewState.tableSeat` | `set_table_seat()`, `cycle_table_seat()` l.3586 |
| Vue table — yaw | `_table_yaw` l.180 | `_apply_table_camera()` | `0.0` | 0-360 | `viewState.tableYaw` | via `set_table_seat()` |
| Vue table — activation | `table_view` l.178 | `set_table_view(on)` l.3543-3569 | `false` | bool | UI/session | `set_table_view()`, `is_table_view()` |
| État de vue | — | `get_view_state()` l.2099-2111 / `_apply_view_state()` l.2083-2097 | — | — | **`map_data.playDefaults.viewState`** | publiques |
| Bornes de pan | `_clamp_camera()` l.2563-2592 | marge 5 % (l.2581) ou zone centrale 30-70 % (l.2579) | fixes | — | Global | — |
| Pulsation d'arrivée | `play_arrival_pulse()` l.1257-1283 | +6 % de zoom, 0.16 s / 0.38 s | — | — | — | `play_arrival_pulse(strength)` ; `is_arrival_pulse_playing()` |
| Inertie de pan | `PAN_INERTIA_DECAY 0.88` / `PAN_INERTIA_MIN 2.0` (l.58-59) | `_process()` l.2983-2994 | — | constantes | Global | — |

> Les valeurs `zoom`, `panX`, `panY`, `tableSeat`, `tableYaw`, `tableElev` sont **persistées par
> carte** dans `playDefaults.viewState` (écrit par `EDITOR.apply_to_map_data()` l.544-547, relu
> par `ENGINE._apply_view_state()`).
> Le `editor_view_controller.gd` (zoom 0.25–4.0, l.11-13) concerne **l'éditeur 2D simple**, pas
> la carte 3D.

---

## 13. Boucle de rendu, fenêtre, résolution

| Réglage | Existe ? | Où | Détail |
|---|---|---|---|
| `Engine.max_fps` | **non (aucun réglage applicatif)** | `game/scripts/tests/map_quality_cs2_shot_test.gd:128` (`Engine.max_fps = 0`) | uniquement dans un test de mesure |
| Vsync | **non** | `game/scripts/tests/map_quality_cs2_shot_test.gd:127` (`DisplayServer.window_set_vsync_mode(VSYNC_DISABLED)`) | aucune préférence joueur |
| Mode fenêtre / plein écran | **partiel, non persistant** | `EDITOR._toggle_fullscreen()` l.3530-3535 ; raccourci `KEY_F11` l.3468-3469 | bascule `WINDOW_MODE_FULLSCREEN` ↔ `WINDOW_MODE_WINDOWED`, **aucune sauvegarde** |
| Plein écran du panneau Monde | oui (interne) | `map_editor_world_panel.gd:486-524` (`toggle_fullscreen()`) | agrandit le panneau dans l'éditeur, pas la fenêtre OS |
| Résolution de fenêtre | **non** | `project.godot:35-42` (`1280×800` logique, `1152×720` fenêtré, min `640×400`) | aucun sélecteur ; `UiLayout._fit_windowed_to_usable_screen()` (`game/scripts/autoload/ui_layout.gd:66-91`) ajuste au démarrage |
| Stretch / aspect | **non modifiable au runtime** | `project.godot:39-40` (`canvas_items`, `expand`) | — |
| `content_scale_factor` | non exposé | utilisé seulement dans les tests de capture (ex. `game/scripts/tests/map_25d_editor_shot_test.gd:39`) | — |
| Rendu du SubViewport | `UPDATE_ALWAYS` | `ENGINE` l.388 | rend en continu |
| MSAA / AA écran / échelle de rendu | oui mais **codés en dur** | `ENGINE` l.391-393 | cf. §2 |

---

## 14. Compteur FPS existant

| Aspect | Détail |
|---|---|
| Déclaration | `EDITOR` l.450 (`var _fps_lbl: Label`) |
| Création | `EDITOR._bind_ui()` l.611-616 : `Label.new()`, texte initial `"FPS —"` |
| Style | police **11 px** (l.613), couleur **`#718087`** (l.614) ; pas d'ombre ni de contour |
| Position | ajouté comme **dernier enfant du parent de `%LblStatus`** (l.615-616), c'est-à-dire la `StatusRow` (`game/scenes/map_editor/map_editor.tscn:135-145`) → **à droite de la barre de statut, en bas du centre**, sous la vue 3D |
| Mise à jour | `EDITOR._process()` l.503-505 : `_fps_lbl.text = "FPS %d" % Engine.get_frames_per_second()` — **à chaque frame**, sans lissage ni historique |
| Condition | aucune (toujours visible) |
| Test | `game/scripts/tests/map_editor_ui_v2_test.gd:37-38` (`fps_label_created`) |
| Autre label de diagnostic | `ENGINE._update_camera_debug()` l.1703-1731 : `CanvasLayer` layer 200 + `Label` 11 px `(1, 0.95, 0.7)` avec contour 4, en bas-gauche de la vue ; **désactivé dans l'éditeur** (`show_camera_diagnostics = false`, `EDITOR` l.745), actif en debug/session |

---

## 15. Ce qui est DÉJÀ exposé dans l'onglet « Carte » (à ne pas dupliquer)

Structure : `game/scenes/map_editor/panels/settings.tscn` (nœud racine `Carte`) + script
`PANEL` (les groupes « Terrain & eau » et « Qualité de rendu » sont **construits par code**,
l.109-198 et l.245-271 : ils n'ont pas de nom de nœud stable hormis `TerrainGroup` /
`QualityGroup`).

| Section UI | Contrôle (nœud) | Déclaration | Clé `map_data` | Handler (`EDITOR`) |
|---|---|---|---|---|
| 🖼 Fond de carte | `%BtnImportBg` / `%BtnImportOverlay` / `%BtnRemoveBg` | `TSCN` 27 / 34 / 41 | `backgroundImage`, `groundMode` | 4667 / 4708 |
| 📐 Dimensions | `%SpinWidth` / `%SpinHeight` (4 → 128) | `TSCN` 75 / 95 | `width`, `height` | `_on_size_changed` 4285 |
| ⊞ Grille | `%ChkGrid`, `%SpinGridSize` (20→160), `%SpinGridOpacity` (0→1, pas 0.01), `%ClrGrid` | `TSCN` 110 / 138 / 157 / 176 | `grid.{enabled,size,opacity,color}` | `_on_grid_changed` 4291 |
| idem (piège) | le style écrit aussi **`grid.show`** | `EDITOR` 4328 | `grid.show` | lu seulement par `ENGINE._rebuild_layers()` l.2162-2163 pour **forcer `opacity = 0`** si `show == false` en style « diorama » → le slider « Opacité » paraît inopérant en 2.5D/diorama/DD2 |
| 📏 Échelle | `%SpinMeasure` (0.1→100), `%EditUnit` | `TSCN` 202 / 221 | `measure.{perCell,unit}` | `_on_measure_changed` 4302 |
| 🌫 Brouillard de guerre | `%ChkFog`, `%ChkLos`, `%BtnFogHide`, `%BtnFogReveal` | `TSCN` 232 / 239 / 255 / 262 | `fogEnabled`, `losEnabled`, `playDefaults.fogRevealed` | 1299-1302 |
| 🎨 Style de rendu | `%OptRenderStyle` | `TSCN` 274 | `renderStyle` (+ `perspective`, `grid.show`) | `_on_render_style_changed` 4318 |
| ✨ Qualité de rendu (CS2) | `QualityGroup` (code) : `OptionButton` + hint | `PANEL` 245-271 | **`qualityPreset`** | `PANEL._apply_quality_preset` 280-297 (écrit directement dans `doc`) |
| 🌍 Terrain & eau (code) | `OptionButton` sol | `PANEL` 116-124 | `groundMode` | `_on_ground_mode_changed` 4337 |
| idem | `SpinBox` niveau d'eau (**−1 … 8**, pas 0.1) | `PANEL` 128-135 | `waterLevel` | `_on_water_changed` 4348 |
| idem | `SpinBox` densité décor d'eau (**0 … 3**) | `PANEL` 139-146 | `waterDecorDensity` | idem |
| idem | `SpinBox` graine décor d'eau (**1 … 99999**) | `PANEL` 150-157 | `waterDecorSeed` | idem |
| idem | `OptionButton` ambiance (`""`, fireflies, dust, leaves, rain, snow) | `PANEL` 162-173 | `ambientFx` | `_on_ambient_fx_changed` 4363 |
| idem | `CheckBox` végétation | `PANEL` 178-182 | `vegetationEnabled` | `_on_vegetation_changed` 4377 |
| idem | `SpinBox` densité végétation (**0 … 3**) | `PANEL` 186-193 | `vegetationDensity` | idem |
| 📷 Perspective | `%OptPerspective` (topdown / isometric / perspective) | `TSCN` 302 | `perspective` | `_on_perspective_changed` 4310 |
| 🌘 Atmosphère | `%ChkAtmo`, `%ClrAtmo`, `%SpinAtmoOpacity` (0→1), `%SpinAtmoVignette` (0→1) | `TSCN` 319 / 334 / 355 / 374 | `atmosphere.*` | `_on_atmosphere_changed` 4390 |
| 💡 Éclairage global | `%OptLightPreset` (7 presets), `%ChkLight`, `%OptLightDir` (4), `%SpinLightIntensity` (0→2) | `TSCN` 394 / 398 / 404 / 431 | `lighting.{preset,enabled,direction,intensity}` + copie des clés du preset | `_on_lighting_changed` 4545 |
| 🌙 Nuit / lumières | `%ChkNight`, `%SpinNightAmbient` (0.05→1), `%BtnClearLight` | `TSCN` 445 / 465 / 484 | `lighting.nightMode`, `lighting.nightAmbient`, `playDefaults.lightRevealed` | `_on_night_mode_changed` 4569 |
| 👁 Affichage éditeur | `%ChkShowLinks`, `%ChkShowIds`, `%ChkShowVision` | `TSCN` 495 / 502 / 508 | **aucune** (overlay uniquement) | 1317-1328 |
| 💾 Sauvegarde | `%OptSavePolicy` (manuel / à chaque modif / 30 s) | `TSCN` 519 | aucune (`EDITOR._save_policy`, l.61) | 1329-1339 |
| ⬆⬇ IO | `%BtnExportJson`, `%BtnImportJson` | `TSCN` 535 / 541 | — | 1340-1341 |

**Doublon interne déjà présent (et masqué)** : `map_editor_environ_palette.gd` reconstruit dans
la colonne de gauche les mêmes 5 réglages (végétation, eau, décor, ambiance, preset lumière),
l.94-104 ; il est explicitement caché (`EDITOR` l.645-651 : `_environ_palette.visible = false`).
C'est le précédent à ne pas réitérer.

**Presets lumière disponibles** (`MAPDATA.LIGHTING_PRESET_ORDER` l.36) : `jour`, `matin`,
`coucher`, `nuit`, `donjon`, `tiny_glade`, `performance`. Chaque preset porte aussi des clés de
post-traitement (`glow`, `saturation`, `contrast`, `gi`, `ssil`, `ssr`, `volumetricFog`,
`shadowBlur`, `sky*`, `aerial`, `sunScatter`, `shadowAngular`, `fogLightEnergy`) —
voir `MAPDATA.LIGHTING_PRESETS` l.41-103. **C'est le seul levier existant pour régler
SSAO/SSIL/GI/SSR/volumétrique/ciel en dehors du preset qualité.**

---

## 16. Réglages absents, morts ou piégeux

| Constat | Preuve |
|---|---|
| `groundTint` n'est lu nulle part | `STYLE` l.161/174/187/199 (déclarations) ; aucune lecture hors tests ; déjà signalé `docs/archive/AUDIT_CARTES.md:198` |
| `softShadows` n'est lu que par les tests | `STYLE` l.101 ; `game/scripts/tests/map_quality_cs2_test.gd:108` ; aucun `get("softShadows")` dans `ENGINE` |
| `lighting.ambient` est inutilisé (c'est `ambientColor`) | `MAPDATA` l.108 ; `ENGINE` l.1773 ; aucune lecture de `get("ambient")` dans `game/scripts` |
| `grid.show` n'est pas un interrupteur : il ne sert qu'à forcer `opacity = 0` en style « diorama » | `ENGINE` l.2152-2166 ; `MapGrid3D.configure()` (`map_layers/map_grid_3d.gd:12-40`) ne lit que `enabled` / `color` / `opacity` → en 2.5D/diorama/DD2, régler l'opacité de la grille ne l'affiche pas |
| Aucune clé `waterRefraction` / `waterQuality` / `waterPreset` | recherche exhaustive : 0 occurrence ; seuls les uniforms `refraction_enabled` / `reflection_enabled` |
| Aucun réglage de TAA | `screen_space_aa` reste `DISABLED` (l.392) ; `use_taa` absent du dépôt |
| Aucune taille de shadow map | aucune écriture `directional_shadow/size` ; pas de section `[rendering]` dans `game/project.godot` |
| Aucun setter public pour le FOV, le tilt, la projection, le ciel, la brume (densité/couleur), la vignette, les réflexions/réfractions, le MSAA, l'échelle de rendu | cf. tableaux §2-§12 |
| `quality_preset_changed` n'est connecté à rien | `PANEL` l.19/285 ; absent de `EDITOR._bind_settings_tab()` l.1290-1341 |
| Ombres dépendantes du dernier appliqueur | `ENGINE` l.1042 vs l.1804 ; `set_ground_mode()` l.1493-1503 et `set_atmospheric_fog_enabled()` l.2019 n'appellent pas `_apply_render_quality()` |
| `terrain` inclut `is_map_25d()` → FX « terrain » sur fond illustré | `ENGINE` l.934 |
| Le mode cinéma annule `shadowAngular` du preset lumière (`tiny_glade` 1.3 → 0.0) | `ENGINE` l.1068 + `STYLE` l.107 |
| `atmosphericFog` en preset cinéma : non testé par les tests existants (aucun cas `cinema` + `atmosphericFog`) | `game/scripts/tests/map_quality_cs2_test.gd:427, 502` utilisent le preset par défaut |

---

## 17. RECOMMANDATIONS D'IMPLÉMENTATION

### 17.1 Principe de découpage

| Nature du réglage | Où le persister | Exemples |
|---|---|---|
| **Identité visuelle de la carte** (ce que le MJ veut partager à l'export) | **`map_data`** (par carte) — c'est déjà le cas | `qualityPreset`, `groundMode`, `waterLevel`, `waterDecor*`, `vegetation*`, `ambientFx`, `atmosphere`, `lighting`, `renderStyle`, `renderStyleOverrides`, `atmosphericFog`, `terrainDetail` |
| **Confort / performance de la machine** (ne doit pas altérer l'export) | **`user://app_settings.cfg`**, section `[rendering]` | `msaa`, `screenSpaceAA`, `renderScale`, `shadowsEnabled`, `shadowMode`, `shadowQuality`, `maxFps`, `vsync`, `fullscreen`, `waterReflections`, `waterRefractions`, `showFps`, `fpsPosition` |
| **Préférence d'outil / session** (ne rien persister) | état de l'éditeur | rayons de brosse, symétrie, mode relief, `_save_policy`, zoom courant |

Règle proposée : *tout ce qui change le rendu d'une carte pour les autres joueurs reste dans
`map_data` ; tout ce qui ne change que ma vue reste dans `app_settings.cfg`.*

### 17.2 Le patron de persistance existe déjà — le copier tel quel

`game/scripts/autoload/locale_settings.gd` :

| Élément | Ligne | À reproduire |
|---|---|---|
| `const SETTINGS_PATH := "user://app_settings.cfg"` | 7 | même fichier, section différente (`[rendering]` plutôt que `[ui]`) |
| `load_settings()` | 17-23 | `ConfigFile.load`, valeurs de repli si `!= OK` |
| `save_settings()` | 25-29 | **`cfg.load()` avant `set_value()`** pour ne pas écraser la section `[ui]` de `LocaleSettings` |
| `apply_*(value, persist := true)` | 31-38 | même signature : applique puis persiste puis émet un signal |

Recommandation : créer `game/scripts/autoload/render_settings.gd` et l'enregistrer dans
`game/project.godot` sous `[autoload]` (l.22-30), après `LocaleSettings`. API proposée :
`load_settings()`, `save_settings()`, `apply_msaa(level)`, `apply_render_scale(scale)`,
`apply_shadows(on)`, `apply_shadow_quality(preset)`, `apply_max_fps(v)`, `apply_vsync(mode)`,
`apply_to_engine(engine)` + signal `render_settings_changed`.

### 17.3 Fonctions d'application : ce qui existe vs. ce qui manque

**Existe déjà (à réutiliser, ne pas réécrire)**

| Fonction | Fichier:ligne | Réglages couverts |
|---|---|---|
| `ENGINE.set_quality_preset(preset)` | `ENGINE` 850-875 | preset complet + rebuild des meshes + ombres + brume |
| `ENGINE.set_shadow_budget_cells(cells)` | 910-913 | budget d'ombres |
| `ENGINE.set_atmospheric_fog_enabled(on)` | 2019-2021 | A/B brume |
| `ENGINE.set_atmospheric_tilt_aware(on)` | 1967-1971 | pondération par le tilt |
| `ENGINE.sync_atmospheric_fog()` | 2014-2016 | recalage manuel |
| `ENGINE.set_water_level(level)` | 1328-1342 | niveau d'eau |
| `ENGINE.set_ambient_fx(name)` | 1380-1392 | particules d'ambiance |
| `ENGINE.set_ground_mode(mode)` | 1493-1503 | sol |
| `ENGINE.set_terrain_materials(materials)` | 1465-1468 | matières peintes |
| `ENGINE.set_terrain_carve_preview(on)` | 1551-1555 | qualité d'aperçu |
| `ENGINE.refresh_terrain(map)` | 1563-1634 | relief/carves/sculpt |
| `ENGINE.set_view_inset(l,t,r,b)` | 696-699 | marges HUD |
| `ENGINE.set_table_view / set_table_seat / set_table_elevation` | 3543 / 3578 / 3601 | vue table |
| `ENGINE.zoom_in / zoom_out / reset_zoom / request_fit_to_view` | 3990 / 3993 / 3996 / 646 | caméra |
| `ENGINE._set_vignette_strength(value)` (privé) | 2077-2081 | vignette (à rendre public) |
| `GROUND.set_cliff_strata / set_macro_variation / set_snow_transition / set_terrain_object_ao / set_auto_min_relief / set_slab_strata` | 795 / 803 / 811 / 819 / 831 / 1805 | finitions terrain |
| `WATER.set_mist_enabled / set_bed_ambient_lift / set_tip_soften` | 611 / 645 / 658 | finitions eau |
| `VEG.configure(..., density, ...)` | `VEG` 151-194 | densité végétation |

**À créer (aucun équivalent aujourd'hui)**

| Fonction proposée | Fichier cible | Implémentation concrète |
|---|---|---|
| `set_msaa(level: int)` | `ENGINE` (après l.397) | `_viewport.msaa_3d = level`, borné à `Viewport.MSAA_MAX` |
| `set_screen_space_aa(mode: int)` | idem | `_viewport.screen_space_aa = mode` |
| `set_render_scale(scale: float)` | idem | `_viewport.scaling_3d_scale = clampf(scale, 0.25, 2.0)` (jamais `_viewport.size`) |
| `set_shadows_enabled(on: bool)` | `ENGINE` (près de l.1039) | écrire `_sun.shadow_enabled` **et** mémoriser un `_shadows_forced` pour que `_apply_render_quality()` (l.1042) le respecte — sinon la divergence du §5 réapparaît |
| `set_shadow_mode(mode: int)` | idem | `_sun.directional_shadow_mode` (`ORTHOGONAL` / `PARALLEL_2_SPLITS` / `PARALLEL_4_SPLITS`) + réappliquer les splits |
| `set_shadow_max_distance(d: float)` | idem | `_sun.directional_shadow_max_distance = clampf(d, 20.0, 400.0)` |
| `set_shadow_splits(a, b, c)` | idem | 3 `directional_shadow_split_*` croissants |
| `set_shadow_casters(on: bool)` | `MESHES` (près de l.1288) | `cast_shadow = ON/OFF` sur `_shadow_casters`, en neutralisant `update_shadow_budget()` (l.215-250) |
| `set_ssao(enabled, radius, intensity, power, detail)` | `ENGINE` (après l.955) | écrire les 5 propriétés `env.ssao_*` puis mémoriser pour ne pas être écrasé par `_apply_render_quality()` |
| `set_ssil(enabled, radius, intensity)` | idem (après l.1016) | `env.ssil_*` |
| `set_glow(enabled, intensity, strength, bloom, hdr)` | idem (après l.969) | `env.glow_*` |
| `set_tonemap(white, exposure_scale)` | idem (après l.1824) | `env.tonemap_white`, `env.tonemap_exposure` |
| `set_color_grade(contrast, saturation)` | idem (après l.987) | `env.adjustment_*` |
| `set_volumetric_fog(enabled, density)` | idem (après l.1038) | `env.volumetric_fog_*` |
| `set_ssr(enabled)` / `set_sdfgi(enabled)` | idem (après l.1026 / l.999) | bascules booléennes |
| `set_dof(enabled, far_distance, amount)` | `ENGINE._apply_depth_of_field()` 796-809 | rendre les 3 constantes paramétrables |
| `set_sky_enabled(on)` | `ENGINE._apply_sky()` 764-793 | forcer `want_sky` |
| `set_atmospheric_fog_params(density, color, height, height_density)` | `ENGINE` (près de l.2027) | écrire les variables d'instance l.119-127 puis `_apply_lighting()` + `sync_atmospheric_fog()` |
| `set_vignette(value)` (public) | `ENGINE` (wrapper de l.2077) | `_set_vignette_strength(clampf(value, 0.0, 0.6))` |
| `set_water_reflections(on, strength)` | `WATER` (près de l.1900) | traverser `_body_nodes` + surfaces `ArrayMesh` (patron : `game/scripts/tests/water_quality_shot_test.gd:302-328`) et écrire `reflection_enabled` / `reflection_strength` |
| `set_water_refractions(on, strength)` | idem | idem avec `refraction_enabled` / `refraction_strength` (l.1882-1883) |
| `set_vegetation_density(density)` | `ENGINE` + `VEG` | `VEG.configure(..., density, ...)` exige la matrice de matières complète : passer par `ENGINE.refresh_terrain(map_data)` en réécrivant `map_data["vegetationDensity"]` (ou ajouter `VEG.set_density(d)` qui appelle `_rebuild(_last_heights, _last_materials)`, l.282) |
| `set_max_fps(v)` / `set_vsync(mode)` | nouveau `RenderSettings` (autoload) | `Engine.max_fps = v` ; `DisplayServer.window_set_vsync_mode(mode)` |
| `set_fullscreen(on)` | `RenderSettings` + `EDITOR` | généraliser `EDITOR._toggle_fullscreen()` (l.3530-3535) et persister le mode |
| `set_fps_visible(on)` | `EDITOR` (l.611-616) | `_fps_lbl.visible = on` (le Label existe déjà, aucune création à refaire) |

### 17.4 Où brancher l'application globale (le point le plus important)

Ne **pas** écrire dans `map_data` depuis un menu global (cela polluerait les exports JSON et
déclencherait `doc.changed("meta")` → `configure()` complet, donc un rebuild de toute la carte).

Brancher plutôt **après** `configure()`, aux deux seuls endroits qui montent le moteur :

1. **Éditeur** : `EDITOR._sync_engine()` — juste après `_engine.configure(...)`
   (`EDITOR` l.3847-3858) :
   ```gdscript
   RenderSettings.apply_to_engine(_engine)   # à insérer après la ligne 3858
   ```
2. **Session** : `map_stage.gd` — après `_complex.configure(...)`
   (`game/scripts/session/panels/map_stage.gd` l.100-112) :
   ```gdscript
   RenderSettings.apply_to_engine(_complex)  # à insérer après la ligne 112
   ```

`apply_to_engine(engine)` doit être **idempotent** et ne toucher que les propriétés listées en
§17.3 (jamais `configure()`), pour rester compatible avec `set_quality_preset()` qui réapplique
`_apply_render_quality()` + `_apply_lighting()`.

Pour un aperçu « live » d'un curseur, préférer un chemin chaud :
`Editor._engine.set_xxx(...)` directement (aucun `doc.set_meta_values`), puis persister au
`drag_ended` — le précédent existe avec `doc.set_meta_live()` (`map_edit_document.gd:1091-1093`),
qui écrit `map_data` et émet `changed("meta_live")` **sans** entrer dans `_on_doc_changed`
(`meta_live` n'est pas dans les listes de `EDITOR._on_doc_changed()` l.4169-4175 : donc **aucun**
`_sync_engine()`, parfait pour un aperçu).

### 17.5 Découpage recommandé du menu « Paramètres »

| Onglet proposé | Contenu | Persistance |
|---|---|---|
| **Affichage** | Preset de qualité (`classique`/`cinema`) *lecture seule + renvoi vers l'onglet Carte* ; MSAA ; AA écran ; échelle de rendu ; FOV ; tilt ; projection ; afficher/masquer le compteur FPS | MSAA/AA/scale/FPS → global ; FOV/tilt/projection → carte (via `renderStyleOverrides`) ou global en surcharge |
| **Ombres & lumière** | Ombres on/off ; mode (ortho / 2 splits / 4 splits) ; distance max ; splits ; budget d'objets projetant ; SSAO (on, radius, intensity) ; SSIL (on, intensity) ; glow (on, intensity) ; tonemap white ; contraste/saturation | global (surcharges) ; le preset qualité reste la valeur par défaut de la carte |
| **Eau & terrain** | Réflexions / réfractions (on + force) ; brume de cascade ; éclairage double du lit ; strates ; neige ; cavité ; `terrainDetail` ; densité de décor d'eau | réflexions/cavité/strates → global ; `waterDecorDensity`, `terrainDetail` → carte |
| **Ambiance** | Brume atmosphérique (on, densité, couleur, hauteur, tiltAware) ; brume volumétrique (on, densité) ; ciel (on) ; vignette ; particules (on/off) | carte pour `atmosphericFog` ; global pour volumétrique/ciel/vignette |
| **Performances** | `max_fps` ; vsync ; échelle de rendu ; budget d'ombres ; vegetation density ; `terrainDetail` | global (sauf vegetation/terrain → carte) |
| **Fenêtre** | Plein écran (F11) ; (résolution si ajoutée) | global |

### 17.6 À NE PAS mettre dans le menu global

| Réglage | Pourquoi |
|---|---|
| `qualityPreset` | déjà dans l'onglet Carte (`PANEL` l.245-297), **persisté par carte** et exporté en JSON |
| `renderStyle`, `perspective`, `grid`, `measure`, `fogEnabled`, `losEnabled` | déjà dans l'onglet Carte, sémantique de carte |
| `lighting.preset` + copie des clés du preset | déjà dans l'onglet Carte (`EDITOR` l.4545-4567) ; un changement global écraserait le preset lumière de chaque carte |
| `waterLevel`, `waterBodies`, `vegetationEnabled/Density`, `ambientFx`, `atmosphere`, `groundMode` | ce sont des choix d'auteur, exportés avec la carte |
| Rayons/forces de brosse, symétrie, mode relief | état d'outil (session), aucun intérêt hors édition |
| `_save_policy`, `_save_interval` | déjà dans l'onglet Carte **et** dans le menu Échap (`map_editor_esc_menu.gd:46-58`) |
| Zoom / pan courants | déjà persistés dans `playDefaults.viewState` |

### 17.7 Trois correctifs à faire avant d'exposer des interrupteurs

1. **Unifier le propriétaire de `_sun.shadow_enabled`** : soit `_apply_lighting()` (l.1804) soit
   `_apply_render_quality()` (l.1042), mais pas les deux ; et faire appeler
   `_apply_render_quality()` par `set_ground_mode()` (l.1493-1503) et
   `set_atmospheric_fog_enabled()` (l.2019-2021).
2. **Rendre `_set_vignette_strength()` public** (l.2077) : c'est le seul réglage « ambiance » sans
   API, alors qu'il a déjà un getter (`get_vignette_strength()` l.828).
3. **Mémoriser les surcharges globales** dans l'engine (`_global_overrides: Dictionary`) et les
   réappliquer à la fin de `_apply_render_quality()` (après l.1074) et de `_apply_lighting()`
   (après l.1828) : sans cela, chaque `configure()` — donc chaque édition — remet le rendu aux
   valeurs de la carte.

### 17.8 Tests existants à étendre (patrons déjà écrits)

| Sujet | Fichier | Ce qu'il vérifie déjà |
|---|---|---|
| Preset qualité bout en bout | `game/scripts/tests/map_quality_cs2_test.gd` | fusion `config()`, `set_quality_preset()`, sérialisation, Environment, budget d'ombres |
| Preset qualité en captures A/B | `game/scripts/tests/map_quality_cs2_shot_test.gd` | rendu de session réel + mesures (`_world_env`) |
| Post-traitement 2.5D | `game/scripts/tests/map_render_quality_test.gd` | SSAO, glow, adjustments, tonemap ACES, MSAA (l.36-40, 196-197) |
| Brume atmosphérique | `game/scripts/tests/fog_quality_shot_test.gd` | densité, tilt, A/B |
| Eau (réflexion/réfraction) | `game/scripts/tests/water_quality_shot_test.gd` | uniforms + traversée des matériaux (l.302-328) |
| Terrain (strates/cavité/neige) | `game/scripts/tests/terrain_quality_shot_test.gd`, `slab_quality_shot_test.gd` | finitions CS2 |
| UI éditeur (FPS) | `game/scripts/tests/map_editor_ui_v2_test.gd:37-38` | existence du Label |

---

## Annexe A — Toutes les clés `map_data` qui influencent le rendu 3D

| Clé | Type | Défaut | Où elle est normalisée |
|---|---|---|---|
| `renderStyle` | String | `"2.5d"` | `MAPDATA.ensure_map_schema` l.859-867 |
| `qualityPreset` | String | absent = `classique` | pas normalisée (`STYLE.quality_preset`) |
| `renderStyleOverrides` | Dictionary | `{}` | pas normalisée |
| `perspective` | String | `"topdown"` | l.784-785 |
| `groundMode` | String | `terrain3d` / `illustrated` | l.803-806 |
| `backgroundImage` / `backgroundImageNight` | String | `""` | l.800-801 |
| `backgroundTransform` | Dictionary | `{offsetX, offsetY, scale, opacity}` | `map_edit_document.gd:157-158` |
| `atmosphere` | Dictionary | `{enabled:false, tint:"#1a1410", opacity:0.25, vignette:0.15}` | l.807-808 |
| `lighting` | Dictionary | `DEFAULT_LIGHTING_CONFIG` (l.104-114) | l.788-799 |
| `grid` | Dictionary | `{size:70, opacity:0.22, color:"#ffffff", enabled:true}` | l.780-781 |
| `measure` | Dictionary | `{unit:"m", perCell:1.5}` | l.816-817 |
| `terrainHeights` | Array | `[]` | l.829-830 |
| `terrainMaterials` | Array | `[]` | l.832-833 |
| `terrainCarves` | Array | `[]` | l.836-837 |
| `terrainSculpt` | Dictionary | `{}` | `map_edit_document.gd:153-154` |
| `terrainDetail` | int | `1` (implicite) | **non normalisée** (lue l.1121 de `ENGINE`) |
| `waterLevel` | float | `-1.0` | l.839-840 |
| `waterBodies` | Array | `[]` | l.843-844 |
| `waterDecorDensity` | float | `1.0` (implicite) | **non normalisée** |
| `waterDecorSeed` | int | `1` (implicite) | **non normalisée** |
| `vegetationEnabled` | bool | `false` (implicite) | **non normalisée** |
| `vegetationDensity` | float | `1.0` (implicite) | **non normalisée** |
| `ambientFx` | String | `""` | l.846-847 |
| `atmosphericFog` | Dictionary | absent | **non normalisée** |
| `atmosphere` | Dictionary | cf. ci-dessus | l.807-808 |
| `playDefaults.viewState` | Dictionary | `{}` | l.883-885 |
| `playDefaults.lightRevealed` | Array | `[]` | l.880-882 |
| `width` / `height` | int | 16 × 12 | — |

## Annexe B — Toutes les variables `Environment` pilotées par le code

`tonemap_mode`, `tonemap_exposure`, `tonemap_white`, `ambient_light_source`,
`ambient_light_color`, `ambient_light_energy`, `ambient_light_sky_contribution`,
`background_mode`, `background_color`, `background_energy_multiplier`, `sky`,
`ssao_enabled`, `ssao_radius`, `ssao_intensity`, `ssao_power`, `ssao_detail`, `ssao_horizon`,
`ssao_sharpness`, `ssao_light_affect`, `ssil_enabled`, `ssil_radius`, `ssil_intensity`,
`ssil_sharpness`, `ssil_normal_rejection`, `sdfgi_enabled`, `sdfgi_cascades`,
`sdfgi_min_cell_size`, `sdfgi_energy`, `sdfgi_normal_bias`, `sdfgi_use_occlusion`,
`sdfgi_read_sky_light`, `sdfgi_bounce_feedback`, `sdfgi_max_distance`, `ssr_enabled`,
`ssr_max_steps`, `ssr_fade_in`, `ssr_fade_out`, `ssr_depth_tolerance`,
`reflected_light_source`, `glow_enabled`, `glow_intensity`, `glow_strength`, `glow_bloom`,
`glow_hdr_threshold`, `glow_blend_mode`, `adjustment_enabled`, `adjustment_brightness`,
`adjustment_contrast`, `adjustment_saturation`, `volumetric_fog_enabled`,
`volumetric_fog_density`, `volumetric_fog_albedo`, `volumetric_fog_emission`,
`volumetric_fog_emission_energy`, `volumetric_fog_anisotropy`, `volumetric_fog_length`,
`volumetric_fog_gi_inject`, `volumetric_fog_ambient_inject`, `fog_enabled`, `fog_mode`,
`fog_density`, `fog_light_color`, `fog_light_energy`, `fog_aerial_perspective`,
`fog_sun_scatter`, `fog_sky_affect`, `fog_height`, `fog_height_density`, `fog_depth_curve`,
`fog_depth_begin`, `fog_depth_end`.

Références : `ENGINE` l.399-410, 764-793, 927-1076, 1767-1828, 1865-1907, 1979-1997.
