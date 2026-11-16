# Finitions « qualité CS2 » — brume de cascade, éclairage double du lit, nez de ruban

Chantier « qualité terrain & eau — niveau Cities: Skylines II », suite du
rapport [`RAPPORT_QUALITE_CS2.md`](RAPPORT_QUALITE_CS2.md) § « Reste (pistes) ».
Cette note documente les **finitions restantes** livrées : méthode, flag A/B,
preuves de capture et coût. La section « Livré (méthodes CS2) » du rapport
principal est volontairement laissée au Lead (voir § Prochaine étape).

## Convention A/B

Chaque finition suit la **même convention que `reflection_enabled` /
`refraction_enabled`** livrés dans le chantier précédent :

- **valeur par défaut = 1.0 (finition ACTIVE)** : elle est visible dans
  l'éditeur sans réglage supplémentaire ;
- **valeur 0 = retour EXACT à l'état précédent** : le bloc de code est
  entièrement court-circuité (`if (flag > 0.001)`, ou `discard` pour la brume),
  aucun autre réglage n'est modifié ;
- bascule **sans reconstruction** (uniform de `ShaderMaterial`) et **sans
  rechargement de scène** ;
- chaque état est capturé et le gain est **mesuré** (différence moyenne RGB sur
  une zone utile), pas seulement regardé.

Pour `Engine.time_scale = 0.0`, l'animation (`TIME` des shaders) est figée : la
capture « off » répétée donne un bruit d'animation **nul**, ce qui rend la
preuve du flag des pointes strictement déterministe.

## Tableau récapitulatif

| # | Finition | Méthode | Flag / uniform | Défaut | Fichiers |
|---|---|---|---|---|---|
| 1 | **Brume/écume volumétrique au pied des cascades** | 2 quads par chute (voile vertical + nappe horizontale basse) accumulés en **un seul maillage**, shader non éclairé `mist` procédural ; alpha = `(1 − hauteur)^1.75 × bruit animé`, dissipation avec la hauteur, bords fondus | `mist_enabled` (shader `water_mist.gdshader`) + API `MapWater3D.set_mist_enabled()` / `is_mist_enabled()` | `1.0` | `game/shaders/water_mist.gdshader` (nouveau), `game/scripts/maps/map_layers/map_water_3d.gd` |
| 2 | **Éclairage double du lit réfracté** | (a) lumière **directe** : réseau de caustiques projeté sur le lit réfracté ; (b) **ambiance/diffusion** d'eau (lumière du ciel diffusée par la lame) sur le lit, d'autant plus forte que l'eau est mince — fin de l'effet « fond plat » des hauts-fonds | `bed_ambient_lift` (shaders `water_surface` **et** `terrain_splat`) + API `MapWater3D.set_bed_ambient_lift()` / `MapGround3D.set_bed_ambient_lift()` | `1.0` | `game/shaders/water_surface.gdshader`, `game/shaders/terrain_splat.gdshader`, `game/scripts/maps/map_layers/map_water_3d.gd`, `game/scripts/maps/map_layers/map_ground_3d.gd` |
| 3 | **Adoucissement des nez de ruban vus de très haut** | masque de pointe posé par sommet dans `COLOR.b` du ruban (1 au nez → 0 au cœur du chenal, sur 4,5 cases) ; le shader détecte la vue haute **sans uniform caméra** via `fwidth()` de la position monde (empreinte écran, vraie en perspective **et** en orthographique) et éteint progressivement l'alpha des pointes | `tip_soften_distance` (+ `tip_soften_lo`, `tip_soften_hi`) + API `MapWater3D.set_tip_soften()` | `1.0` | `game/shaders/water_surface.gdshader`, `game/scripts/maps/map_layers/map_water_3d.gd` |
| 4 | *(optionnel)* SSR plus profond | **non retenu** — voir § « Piste 4 » | — | — | — |

## Preuves

### Captures (dans `docs/screenshots/`)

| Finition | Captures | Mesure |
|---|---|---|
| Brume de pied de cascade | `cs2_finitions_mist_off.png` / `cs2_finitions_mist_on.png` | diff moyenne **0,0235** (bande basse de l'image, 3 chutes) |
| Éclairage double du lit — eau | `cs2_finitions_bed_off.png` / `cs2_finitions_bed_on.png` | diff moyenne **0,0190** (zone du lac, hauts-fonds) |
| Éclairage double du lit — terrain (lit vu du sol, eau masquée) | `cs2_finitions_terrain_bed_off.png` / `cs2_finitions_terrain_bed_on.png` | diff moyenne **0,0143** (centre de l'image = lit du lac) |
| Nez de ruban vus de très haut | `cs2_finitions_tip_off.png` / `cs2_finitions_tip_off_bis.png` / `cs2_finitions_tip_on.png` | bruit d'animation (TIME figé) **0,00000** ; signal flag **0,00904** max sur les deux nez (nord 0,00437 / sud 0,00904) |

Les captures existantes `water_quality_*` (lac, rivière, réfraction A/B) et
`terrain_quality_*` ont été **régénérées** par les tests étendus : elles
illustrent désormais le rendu par défaut (finitions actives) sans changer le
sens des preuves précédentes. Les captures de référence des cascades
(`staircase_overview.png`, `staircase_falls.png`) montrent la brume de pied.

### Tests headless (sortie littérale)

| Test | Résultat |
|---|---|
| `cs2_finitions_test` (nouveau) | `cs2_finitions_test:PASS` |
| `water_bodies_test` | `water_bodies_test:PASS` |
| `map_water_test` | `map_water_test:PASS` |
| `river_continuity_test` | `river_continuity_test:PASS` |
| `river_user_trace_test` | `river_user_trace_test:PASS` |
| `map_terrain_test` | `map_terrain_test:PASS` |
| `map_terrain_materials_test` | `map_terrain_materials_test:PASS` |
| `map_render_quality_test` | `map_render_quality_test:PASS` |

### Tests de capture (fenêtre cachée, GPU réel — RX 5600 XT)

| Test | Résultat |
|---|---|
| `water_quality_shot_test` (étendu : finitions off/on) | `water_quality_shot_test:PASS` |
| `terrain_quality_shot_test` (étendu : lit off/on) | `terrain_quality_shot_test:PASS` |
| `staircase_cascade_shot_test` (non-régression des cascades) | `staircase_cascade_shot_test:PASS` |

### Ce que vérifie `cs2_finitions_test` (headless)

- présence des uniforms dans les trois shaders (`mist_enabled`,
  `bed_ambient_lift` sur eau **et** terrain, `tip_soften_distance`) ;
- brume : 3 chutes détectées → **6 quads** de brume, **1 nœud** de brume
  (hors `_body_nodes`, donc `get_body_count()` et le nombre de surfaces des
  maillages d'eau sont **inchangés** : 2 surfaces), budget ≤ `MIST_MAX_QUADS` ;
  A/B `mist_enabled` 1 → 0 → 1 avec nœuds masqués/restaurés ;
- éclairage double : défaut 1, A/B 0 → 1 sur les surfaces d'eau et sur le
  terrain, `reflection_enabled` / `refraction_enabled` / `cavity_bake` /
  `auto_material_strength` / `triplanar_lo` restent intacts ;
- nez de ruban : masque `COLOR.b` présent (`max > 0.9` au nez, `min < 0.05` au
  cœur du chenal), ancien fondu d'alpha `COLOR.r` conservé (`max > 0.99`,
  `min < 0.4`), A/B `tip_soften_distance` ;
- plan d'eau historique (sans `waterBodies`) : aucune brume, aucune pointe,
  aucun changement de comportement (hors uniform `bed_ambient_lift` à 0/1).

## Coût

- **Brume** : 2 quads (4 triangles) par chute, **un seul draw call par bassin
  de rivière** (tous les quads dans le même maillage), shader **unshaded** sans
  écriture de profondeur ; budget dur **`MIST_MAX_QUADS = 64`** quads/carte ;
  **aucun système de particules, aucun asset**. Mesure indicative en fenêtre
  cachée (scène de validation 20×16, 3 chutes) : **5,39 ms → 5,58 ms**
  (~+0,19 ms, ~+3,5 %) — mesure non bornée par la vsync sur cette machine.
- **Éclairage double** : quelques ALU ajoutées par fragment (un motif de bruit,
  un mix d'ambiance) sur le terrain sous l'eau et sur le lit réfracté ; aucun
  échantillonnage de texture supplémentaire, aucun passage de rendu.
- **Pointes** : une varying (`world_pos`) et deux `fwidth()` par fragment de
  ruban uniquement (garde `edge_softness > 0` — les lacs n'exécutent rien) ;
  rien quand `tip_soften_distance = 0`.

## Procédure A/B (reproductible)

Chaque finition se bascule **à chaud**, sans reconstruction :

```gdscript
# 1) brume de pied de cascade
water_layer.set_mist_enabled(false)   # 0 / rendu exact précédent
water_layer.set_mist_enabled(true)    # défaut

# 2) éclairage double du lit (eau + terrain, même flag)
water_layer.set_bed_ambient_lift(0.0)
ground_layer.set_bed_ambient_lift(0.0)
water_layer.set_bed_ambient_lift(1.0)
ground_layer.set_bed_ambient_lift(1.0)

# 3) nez de ruban vus de très haut
water_layer.set_tip_soften(0.0)
water_layer.set_tip_soften(1.0)
```

Seuils de la vue « très haute » (`tip_soften_lo = 0.025`,
`tip_soften_hi = 0.075` unités monde par pixel) : calibrés sur la caméra réelle
du moteur (sonde : `fwidth` ≈ 0,0197 u/px au cadrage « carte entière » d'une
carte 20×16 → **aucun effet** ; ≈ 0,068 u/px au zoom minimal 0,25 → extinction
quasi totale des pointes). Ils sont réglables par uniform si un style de caméra
différent le nécessite.

## Limites / risques

- **Pointes** : la finition ne couvre que le **ruban d'eau** (rivières) ; le
  ruban de **chemin** utilise `path_ribbon.gdshader`, hors du périmètre de
  cette tâche — le même masque/shader pourra y être branché ensuite.
- **Brume** : rendu non éclairé (volontaire : elle reste blanche à l'ombre) ;
  à très forte densité de cascades le budget borne le nombre de quads
  (les chutes au-delà de 64 quads n'ont pas de brume). La brume est portée par
  un nœud séparé, non sérialisé dans les données de carte (reconstruite à
  chaque `rebuild`).
- **Éclairage double** : approximation (pas de vraie diffusion volumétrique) ;
  la part « directe » utilise le même réseau procédural de caustiques que le
  terrain, sans alignement physique exact avec lui.
- **Seuils de vue haute** dépendants de l'échelle de carte : sur une très
  grande carte, le cadrage « carte entière » correspond déjà à une empreinte
  écran plus grande → les pointes y sont légèrement adoucies dès le cadrage
  complet (comportement jugé souhaitable : grande carte = vue de haut).

## Piste 4 — SSR plus profond : non retenu

Non implémenté dans cette passe : le rendu actuel combine déjà
réflexion écran (décalage UV par la normale des micro-vagues) et réfraction
écran ; un vrai ray-march SSR profond ajouterait des échantillons par pixel
sur une carte entière sans preuve de gain abordable sur RX 5600 XT dans le
budget de cette session. Piste conservée pour une passe dédiée avec mesure
GPU (GPU timer/RenderDoc) et comparaison A/B.

## Prochaine étape côté Lead

Mettre à jour la section « Livré (méthodes CS2) » de
[`RAPPORT_QUALITE_CS2.md`](RAPPORT_QUALITE_CS2.md) avec les 3 lignes du tableau
ci-dessus, et retirer les 3 pistes correspondantes de « Reste (pistes) »
(laisser SSR profond).
