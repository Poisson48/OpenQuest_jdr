extends RefCounted
class_name MapThemePresets
## Thèmes de départ pour les nouvelles zones : peignent une base de sols,
## quelques reliefs et une ambiance animée, pour ne pas partir d'une carte vide.

## IDs alignés sur MapData.MATERIAL_* (0 herbe, 1 terre, 2 pierre, 3 neige, 4 sable).
const GRASS := 0
const DIRT := 1
const STONE := 2
const SNOW := 3
const SAND := 4

const THEMES := [
	{"id": "empty", "label": "Vide (herbe)"},
	{"id": "village", "label": "Village"},
	{"id": "forest", "label": "Forêt"},
	{"id": "ruins", "label": "Ruines"},
	{"id": "snow", "label": "Camp enneigé"},
	{"id": "beach", "label": "Bord de mer"},
]

static func theme_ids() -> Array:
	var ids: Array = []
	for theme in THEMES:
		ids.append(str(theme.get("id", "")))
	return ids

static func label_for(theme_id: String) -> String:
	for theme in THEMES:
		if str(theme.get("id", "")) == theme_id:
			return str(theme.get("label", theme_id))
	return theme_id

## Applique le thème à `map` (modifie terrainMaterials/Heights/ambientFx).
static func apply(map: Dictionary, theme_id: String) -> void:
	var w := int(map.get("width", 12))
	var h := int(map.get("height", 9))
	if w <= 0 or h <= 0:
		return
	var materials: Array = []
	materials.resize(w * h)
	materials.fill(GRASS)
	var heights: Array = []
	heights.resize(w * h)
	heights.fill(0.0)
	var ambient := ""
	match theme_id:
		"village":
			for y in range(h):
				for x in range(w):
					var idx := y * w + x
					if x == int(w / 2) or y == int(h / 2):
						materials[idx] = DIRT
					if absi(x - int(w / 2)) <= 1 and absi(y - int(h / 2)) <= 1:
						materials[idx] = STONE
			ambient = "leaves"
		"forest":
			for y in range(h):
				for x in range(w):
					var path_x := 1 + int(y * 0.7)
					if absi(x - path_x) == 0:
						materials[y * w + x] = DIRT
			ambient = "fireflies"
		"ruins":
			for y in range(h):
				for x in range(w):
					var idx := y * w + x
					var dx := absi(x - int(w / 2))
					var dy := absi(y - int(h / 2))
					if dx <= maxi(2, int(w / 4)) and dy <= maxi(1, int(h / 4)):
						materials[idx] = STONE
					elif (x + y) % 7 == 0:
						materials[idx] = DIRT
			ambient = "rain"
		"snow":
			var centers := [
				Vector2(1.6, 1.6), Vector2(w - 1.6, 1.6),
				Vector2(1.6, h - 1.6), Vector2(w - 1.6, h - 1.6),
			]
			for y in range(h):
				for x in range(w):
					var idx := y * w + x
					if x == int(w / 2) or y == int(h / 2):
						materials[idx] = DIRT
					for center_variant in centers:
						var d: float = Vector2(x, y).distance_to(center_variant)
						if d < 2.3:
							materials[idx] = SNOW
							heights[idx] = maxf(float(heights[idx]), 0.16 * (1.0 - d / 2.3))
							break
			ambient = "snow"
		"beach":
			var shore := int(h * 0.55)
			for y in range(h):
				for x in range(w):
					var idx := y * w + x
					if y >= shore:
						materials[idx] = SAND
					elif y == shore - 1 and (x % 3) != 0:
						materials[idx] = SAND
			ambient = "leaves"
		_:
			ambient = ""
	map["terrainMaterials"] = materials
	map["terrainHeights"] = heights
	map["ambientFx"] = ambient
