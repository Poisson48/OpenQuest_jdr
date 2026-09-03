extends RefCounted
class_name MapRenderStyle

## Style de rendu d'une carte.
##
## **Diorama (défaut)** — l'approche Darkest Dungeon 2 : un fond peint, des
## découpes 2D dressées dedans, une caméra légèrement inclinée qui donne du
## parallaxe, et de la profondeur atmosphérique. Rien n'est modélisé en 3D :
## la 3D ne sert qu'à disposer des images dans l'espace. Pas d'ombres portées,
## pas d'éclairage sur les décors — l'illustration porte déjà les siennes.
##
## **VTT** — l'ancien mode battlemap tactique : murs volumétriques, ombres
## réelles, éclairage directionnel. Conservé pour les cartes de combat qui en
## profitent, mais ce n'est plus le mode par défaut.

const DIORAMA := "diorama"
const VTT := "vtt"

const STYLES := [
	{
		"id": DIORAMA,
		"label": "Diorama 2.5D",
		"hint": "Fond peint + découpes dressées, caméra inclinée, parallaxe et profondeur atmosphérique. Le style « Darkest Dungeon ».",
	},
	{
		"id": VTT,
		"label": "VTT 3D",
		"hint": "Battlemap tactique : murs volumétriques, ombres portées, éclairage directionnel.",
	},
]

## Réglages par style. Ils pilotent la caméra, l'éclairage et la profondeur.
const CONFIGS := {
	DIORAMA: {
		"perspective": true,      # caméra perspective → parallaxe au déplacement
		"fov": 34.0,
		"tilt": -52.0,            # inclinaison : on voit le sol et la face des décors
		"shadows": false,         # les illustrations portent leurs propres ombres
		"litProps": false,
		"volumetricWalls": false, # les murs ne servent plus qu'à la ligne de vue
		"parallax": 0.35,         # écart de profondeur entre calques, en cases
		"depthFade": 0.45,        # fondu atmosphérique du lointain
		"groundTint": 1.0,
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
	},
}

# ===========================================================================
# Résolution
# ===========================================================================

static func style_of(map_data: Dictionary) -> String:
	var style := str(map_data.get("renderStyle", DIORAMA))
	return VTT if style == VTT else DIORAMA

static func is_diorama(map_data: Dictionary) -> bool:
	return style_of(map_data) == DIORAMA

static func config(map_data: Dictionary) -> Dictionary:
	var cfg: Dictionary = (CONFIGS[style_of(map_data)] as Dictionary).duplicate(true)
	# Carte illustrée (fond peint) : vue de dessus orthographique pour lire
	# le plan à l'endroit. L'inclinaison DD2 reste pour les dioramas sans fond.
	if style_of(map_data) == DIORAMA and not str(map_data.get("backgroundImage", "")).strip_edges().is_empty():
		cfg["perspective"] = false
		cfg["tilt"] = -90.0
		cfg["parallax"] = 0.0
	# La carte peut affiner les réglages du style qu'elle a choisi.
	var overrides = map_data.get("renderStyleOverrides", {})
	if overrides is Dictionary:
		cfg.merge(overrides, true)
	return cfg

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

## Décalage de profondeur d'un calque, en cases.
##
## Les calques bas (fond, décor lointain) reculent, les calques hauts
## (tokens, avant-plan) avancent. C'est ce petit écart qui, sous une caméra
## perspective, produit le parallaxe quand on déplace la vue.
static func parallax_offset(layer: int, cfg: Dictionary) -> float:
	var strength := float(cfg.get("parallax", 0.0))
	if strength <= 0.0:
		return 0.0
	# Le calque 3 (zones & effets) sert de plan de référence.
	return float(layer - 3) * strength

## Profondeur normalisée d'une position dans la carte : 0 au fond, 1 devant.
static func depth_ratio(gy: float, map_height: float) -> float:
	if map_height <= 0.0:
		return 0.5
	return clampf(gy / map_height, 0.0, 1.0)

## Teinte atmosphérique appliquée à un décor selon son éloignement.
##
## Le lointain se fond dans l'ambiance de la scène ; le premier plan garde ses
## couleurs. C'est ce qui donne l'impression de profondeur sans brouillard 3D.
static func depth_tint(base: Color, depth01: float, atmosphere: Color, cfg: Dictionary) -> Color:
	var fade := float(cfg.get("depthFade", 0.0))
	if fade <= 0.0:
		return base
	var amount := clampf((1.0 - depth01) * fade, 0.0, 1.0)
	var faded := base.lerp(atmosphere, amount)
	faded.a = base.a
	return faded

## Ordre de dessin d'un décor : plus il est proche, plus il passe devant.
## Godot borne la priorité de rendu à [-128, 127].
static func render_priority(layer: int, depth01: float) -> int:
	var layer_band := clampi(layer, 0, 9) * 12
	var depth_band := int(round(clampf(depth01, 0.0, 1.0) * 11.0))
	return clampi(layer_band + depth_band - 60, -128, 127)

## Couleur d'ambiance de la carte, utilisée pour le fondu de profondeur.
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
