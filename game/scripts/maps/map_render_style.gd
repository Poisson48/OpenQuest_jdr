extends RefCounted
class_name MapRenderStyle

## Style de rendu d'une carte.
##
## **Diorama** — fond peint + découpes. Sans fond : caméra inclinée. Avec fond
## illustré : ortho top-down + props à plat (lisibilité du plan).
##
## **VTT** — battlemap tactique : murs volumétriques, ombres, éclairage.
##
## **DD2 hybrid** — vue « Darkest Dungeon 2 » : fond illustré + caméra inclinée
## perspective + tokens/props dressés face caméra + parallaxe (mélange 2D/3D).

const DIORAMA := "diorama"
const VTT := "vtt"
const DD2_HYBRID := "dd2_hybrid"
## Carte 2.5D par défaut : décor peint, caméra en perspective, objets 2D/3D
## mélangés (type League of Legends / Warhammer).
const MAP_25D := "2.5d"

## Style par défaut des nouvelles cartes.
const DEFAULT_STYLE := MAP_25D

# ===========================================================================
# Preset de qualité (opt-in, A/B réversible)
# ===========================================================================
#
# Dimension **orthogonale** au style de rendu : le style décide de la mise en
# scène (caméra, props plats/dressés, murs volumétriques) ; le preset décide du
# **cran de qualité** du rendu 3D. `classique` = rendu historique, strictement
# inchangé (clé absente ou inconnue). `cinema` = rendu « Cities: Skylines II »
# pour une carte 2.5D peuplée d'objets 3D : ombres portées réelles des mesh
# importés, ombres douces PCF 4 splits, SSAO/SSIL renforcés, tonemap filmique,
# étalonnage Valbois, matériaux PBR éclairés et légère perspective aérienne.
#
# La valeur est persistée dans les données de carte (`map_data["qualityPreset"]`)
# et voyage donc telle quelle dans les exports/imports JSON.
const QUALITY_CLASSIQUE := "classique"
const QUALITY_CINEMA := "cinema"
const DEFAULT_QUALITY := QUALITY_CLASSIQUE

const QUALITY_PRESETS := [
	{
		"id": QUALITY_CLASSIQUE,
		"label": "Classique (défaut)",
		"hint": "Rendu historique : objets 3D non éclairés (couleurs cuites), ombres de contact peintes, post-traitement actuel.",
	},
	{
		"id": QUALITY_CINEMA,
		"label": "✨ Cinéma (CS2)",
		"hint": "Cran qualité CS2 (Cities: Skylines II) : ombres portées douces, AO/SSIL renforcés, tonemap filmique, matériaux PBR éclairés et perspective aérienne. Réservé aux cartes terrain 3D.",
	},
]

## Réglages de POST-TRAITEMENT du preset `cinema` (appliqués quel que soit le
## type de sol : tonemap, AO/SSIL, glow, étalonnage).
const QUALITY_POST_OVERRIDES := {
	QUALITY_CINEMA: {
		"cinemaQuality": true,
		# Tonemap filmique : plus de marge dans les hautes lumières (ciel,
		# soleil, lanternes) sans brûler les façades claires.
		"tonemapWhite": 2.4,
		"exposureScale": 0.99,
		# AO écran renforcée : les bâtiments s'assoient sur le sol, les recoins
		# des modules de toiture/façade se lisent.
		"ssaoRadius": 1.7,
		"ssaoIntensity": 1.75,
		"ssaoPower": 1.2,
		"ssaoDetail": 0.9,
		"ssaoHorizon": 0.06,
		"ssaoLightAffect": 0.16,
		# SSIL : lumière indirecte écran, la lumière chaude rebondit sur les
		# murs et le sol (pas de « boîtes » posées sur un décor).
		"ssil": true,
		"ssilRadius": 6.0,
		"ssilIntensity": 0.85,
		# Glow maîtrisé (lanternes/fenêtres discrètes, pas de voile).
		"glowIntensityScale": 0.82,
		"glowStrength": 0.85,
		"glowBloom": 0.012,
		"glowHdrThreshold": 1.12,
		# Étalonnage Valbois : planchers/plafonds modestes (saturation bornée
		# à 1,04–1,08, contraste à 1,08–1,12) — les toits en tuiles rouges
		# étaient trop saturés/brûlés avec les valeurs précédentes (1,10/1,12).
		"saturationFloor": 1.04,
		"saturationCeil": 1.08,
		"contrastFloor": 1.08,
		"contrastCeil": 1.12,
	},
}

## Réglages de SURFACE du preset `cinema` : ombres portées, atténuation de
## l'ombre de contact, matériaux PBR et perspective aérienne. Appliqués
## uniquement quand le sol est un vrai terrain 3D (sur un fond illustré, on
## garde l'identité peinte : les objets restent « dessinés »).
const QUALITY_SURFACE_OVERRIDES := {
	QUALITY_CINEMA: {
		# Ombres portées réelles (le style 2.5D les coupe par défaut).
		"shadows": true,
		"litProps": true,
		"softShadows": true,
		"shadowBlur": 2.2,
		# Pénombre obtenue par le BLUR (PCF 4 splits), pas par la taille
		# angulaire du soleil : le filtre angulaire du moteur dithère la
		# pénombre (mouchetures très visibles sur les petits objets de près),
		# ce qui casse la propreté « diorama peint » attendue.
		"shadowAngular": 0.0,
		"shadowMaxDistance": 190.0,
		"shadowSplit1": 0.10,
		"shadowSplit2": 0.28,
		"shadowSplit3": 0.52,
		# Ombre de contact peinte atténuée : le soleil fait le vrai travail.
		"contactShadowScale": 0.45,
		# BUDGET D'OMBRES : seuls les objets à moins de N cases du point visé
		# projettent une ombre (les objets lointains n'en projettent pas : la
		# passe d'ombre ne couvre pas toute la carte sur les cartes denses).
		# -1 = illimité (tous les objets projettent, comportement d'origine).
		"shadowDistance": 70.0,
		# Matériaux importés : PBR éclairé, mats (palette Valbois).
		"materialRoughnessMin": 0.86,
		# Perspective aérienne légère sur les objets lointains (fond de carte).
		"depthTint": 0.16,
		"depthTintColor": "#d9cdbc",
	},
}

const STYLES := [
	{
		"id": MAP_25D,
		"label": "Carte 2.5D (défaut)",
		"hint": "Décor peint en perspective, découpes 2D et objets 3D mélangés. Le style des cartes de jeu.",
	},
	{
		"id": DIORAMA,
		"label": "Diorama 2.5D",
		"hint": "Fond peint + découpes. Avec fond illustré : vue de dessus (props à plat).",
	},
	{
		"id": VTT,
		"label": "VTT 3D",
		"hint": "Battlemap tactique : murs volumétriques, ombres, props dressés.",
	},
	{
		"id": DD2_HYBRID,
		"label": "Hybride DD2",
		"hint": "Fond illustré + caméra inclinée + personnages/décors dressés (mélange 2D/3D).",
	},
]

## Réglages par style. Ils pilotent la caméra, l'éclairage et la profondeur.
const CONFIGS := {
	MAP_25D: {
		"perspective": true,
		"fov": 38.0,
		"tilt": -50.0,
		"shadows": false,
		"litProps": false,
		"volumetricWalls": false,
		"parallax": 0.5,
		"depthFade": 0.3,
		"groundTint": 1.0,
		# Découpes dressées et meshes 3D sur le fond peint.
		"preferFlatProps": false,
	},
	DIORAMA: {
		"perspective": true,
		"fov": 34.0,
		"tilt": -52.0,
		"shadows": false,
		"litProps": false,
		"volumetricWalls": false,
		"parallax": 0.35,
		"depthFade": 0.45,
		"groundTint": 1.0,
		# Hors fond illustré : props à plat (vue plan), pas des cartes dressées.
		"preferFlatProps": true,
	},
	VTT: {
		"perspective": false,
		"fov": 38.0,
		"tilt": -90.0,
		"shadows": true,
		"litProps": true,
		"volumetricWalls": true,
		"parallax": 0.0,
		"depthFade": 0.0,
		"groundTint": 1.0,
		"preferFlatProps": false,
	},
	DD2_HYBRID: {
		"perspective": true,
		"fov": 36.0,
		"tilt": -48.0,
		"shadows": false,
		"litProps": false,
		"volumetricWalls": false,
		"parallax": 0.42,
		"depthFade": 0.28,
		"groundTint": 1.0,
		# Ne jamais forcer le plat : les découpes restent dressées sur le fond.
		"preferFlatProps": false,
	},
}

# ===========================================================================
# Résolution
# ===========================================================================

static func style_of(map_data: Dictionary) -> String:
	var style := str(map_data.get("renderStyle", DEFAULT_STYLE))
	if style == VTT:
		return VTT
	if style == DD2_HYBRID:
		return DD2_HYBRID
	if style == MAP_25D:
		return MAP_25D
	return DIORAMA

## Famille « soft » (2.5D + diorama + DD2) : pas de murs volumétriques durs,
## fog doux, objets non éclairés.
static func is_diorama(map_data: Dictionary) -> bool:
	var style := style_of(map_data)
	return style == DIORAMA or style == DD2_HYBRID or style == MAP_25D

static func is_map_25d(map_data: Dictionary) -> bool:
	return style_of(map_data) == MAP_25D

static func is_dd2(map_data: Dictionary) -> bool:
	return style_of(map_data) == DD2_HYBRID

static func config(map_data: Dictionary) -> Dictionary:
	var style := style_of(map_data)
	var cfg: Dictionary = (CONFIGS[style] as Dictionary).duplicate(true)
	# Diorama + fond illustré uniquement : ortho top-down + props à plat.
	# DD2 garde tilt/perspective même avec fond peint.
	if style == DIORAMA and has_illustrated_background(map_data):
		cfg["perspective"] = false
		cfg["tilt"] = -90.0
		cfg["parallax"] = 0.0
		cfg["depthFade"] = 0.0
		cfg["preferFlatProps"] = true
	# Preset de qualité : post-traitement toujours, réglages de surface
	# seulement sur un vrai terrain 3D (un fond illustré garde ses objets
	# « dessinés », non éclairés).
	var quality := quality_preset(map_data)
	if quality != QUALITY_CLASSIQUE:
		cfg.merge(QUALITY_POST_OVERRIDES.get(quality, {}), true)
		if not has_illustrated_background(map_data):
			cfg.merge(QUALITY_SURFACE_OVERRIDES.get(quality, {}), true)
	# Les surcharges explicites de la carte gagnent toujours (A/B manuel).
	var overrides = map_data.get("renderStyleOverrides", {})
	if overrides is Dictionary:
		cfg.merge(overrides, true)
	return cfg

# ===========================================================================
# Preset de qualité — résolution
# ===========================================================================

## Preset de qualité effectif : `cinema` (opt-in) ou `classique` (défaut).
## Tolère les variantes d'écriture (`Cinéma`, `cinema_cs2`, espaces) pour que
## les cartes éditées à la main ou importées restent lisibles.
static func quality_preset(map_data: Dictionary) -> String:
	var raw := str(map_data.get("qualityPreset", DEFAULT_QUALITY)).strip_edges().to_lower()
	if raw == QUALITY_CINEMA or raw == "cinéma" or raw == "cinema_cs2" or raw == "cs2":
		return QUALITY_CINEMA
	return QUALITY_CLASSIQUE

static func is_cinema(map_data: Dictionary) -> bool:
	return quality_preset(map_data) == QUALITY_CINEMA

static func quality_label(preset_id: String) -> String:
	for entry in QUALITY_PRESETS:
		if str(entry["id"]) == preset_id:
			return str(entry["label"])
	return preset_id

static func quality_hint(preset_id: String) -> String:
	for entry in QUALITY_PRESETS:
		if str(entry["id"]) == preset_id:
			return str(entry["hint"])
	return ""

static func has_illustrated_background(map_data: Dictionary) -> bool:
	return not str(map_data.get("backgroundImage", "")).strip_edges().is_empty()

## True si les props doivent être posés/rendus à plat (carte illustrée top-down).
static func prefer_flat_props(map_data: Dictionary) -> bool:
	return bool(config(map_data).get("preferFlatProps", false))

static func style_label(style_id: String) -> String:
	for entry in STYLES:
		if entry["id"] == style_id:
			return str(entry["label"])
	return style_id

static func style_hint(style_id: String) -> String:
	for entry in STYLES:
		if entry["id"] == style_id:
			return str(entry["hint"])
	return ""

# ===========================================================================
# Profondeur
# ===========================================================================

static func parallax_offset(layer: int, cfg: Dictionary) -> float:
	var strength := float(cfg.get("parallax", 0.0))
	if strength <= 0.0:
		return 0.0
	return float(layer - 3) * strength

static func depth_ratio(gy: float, map_height: float) -> float:
	if map_height <= 0.0:
		return 0.5
	return clampf(gy / map_height, 0.0, 1.0)

static func depth_tint(base: Color, depth01: float, atmosphere: Color, cfg: Dictionary) -> Color:
	var fade := float(cfg.get("depthFade", 0.0))
	if fade <= 0.0:
		return base
	var amount := clampf((1.0 - depth01) * fade, 0.0, 1.0)
	var faded := base.lerp(atmosphere, amount)
	faded.a = base.a
	return faded

## Perspective aérienne du preset qualité : couleur de brume (proche du blanc,
## chaude) vers laquelle tend l'albédo des matériaux **importés** des objets 3D.
## `depth01` = 1 au premier plan, 0 au fond de carte (comme `depth_ratio`).
## Renvoie `Color.WHITE` (aucun effet) en preset classique.
static func quality_aerial_tint(depth01: float, cfg: Dictionary) -> Color:
	var amount := quality_aerial_amount(depth01, cfg)
	if amount <= 0.001:
		return Color.WHITE
	return Color.WHITE.lerp(quality_aerial_color(cfg), amount)

## Poids (0..0.5) de la perspective aérienne pour un objet à cette profondeur :
## nul au premier plan, maximal au fond de carte. 0 en preset classique.
static func quality_aerial_amount(depth01: float, cfg: Dictionary) -> float:
	var amount := float(cfg.get("depthTint", 0.0))
	if amount <= 0.001:
		return 0.0
	return clampf((1.0 - clampf(depth01, 0.0, 1.0)) * amount, 0.0, 0.5)

## Couleur de brume chaude vers laquelle tendent les objets lointains (palette
## Valbois : crème/pierre chaude, pas un gris froid).
static func quality_aerial_color(cfg: Dictionary) -> Color:
	var tint := Color.html(str(cfg.get("depthTintColor", "#d9cdbc")))
	tint.a = 1.0
	return tint

static func render_priority(layer: int, depth01: float) -> int:
	var layer_band := clampi(layer, 0, 9) * 12
	var depth_band := int(round(clampf(depth01, 0.0, 1.0) * 11.0))
	return clampi(layer_band + depth_band - 60, -128, 127)

static func atmosphere_color(map_data: Dictionary) -> Color:
	var atmo = map_data.get("atmosphere", {})
	if not atmo is Dictionary:
		return Color(0.10, 0.10, 0.14)
	var hex := str((atmo as Dictionary).get("tint", "#141018")).strip_edges()
	if hex.is_empty():
		return Color(0.10, 0.10, 0.14)
	var color := Color.html(hex)
	color.a = 1.0
	return color
