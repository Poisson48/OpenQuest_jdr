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

const STYLES := [
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
		"tilt": -72.0,
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
	var style := str(map_data.get("renderStyle", DIORAMA))
	if style == VTT:
		return VTT
	if style == DD2_HYBRID:
		return DD2_HYBRID
	return DIORAMA

## Famille « soft » (diorama + DD2) : pas de murs volumétriques durs, fog doux.
static func is_diorama(map_data: Dictionary) -> bool:
	var style := style_of(map_data)
	return style == DIORAMA or style == DD2_HYBRID

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
	var overrides = map_data.get("renderStyleOverrides", {})
	if overrides is Dictionary:
		cfg.merge(overrides, true)
	return cfg

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
