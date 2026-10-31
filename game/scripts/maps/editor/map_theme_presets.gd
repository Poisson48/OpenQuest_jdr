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
	{"id": "lake", "label": "Lac"},
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

## Courte description affichée dans le dialogue de création de zone.
static func description_for(theme_id: String) -> String:
	match theme_id:
		"village": return "Chemins en croix, place pavée et puits de départ."
		"forest": return "Sentier de terre, arbres, rochers et lucioles."
		"ruins": return "Dallage central, murs brisés, pluie et rochers."
		"snow": return "Neige et congères aux coins, chute de neige, rochers."
		"beach": return "Moitié sable, moitié herbe, quelques rochers."
		"lake": return "Étang central, rive de sable, arbre et rocher."
		_: return "Carte vierge en herbe, sans décor."

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
		"lake":
			var lake_center := Vector2(w * 0.5, h * 0.5)
			for y in range(h):
				for x in range(w):
					var idx := y * w + x
					var d := Vector2(x, y).distance_to(lake_center)
					if d < 2.8:
						heights[idx] = -0.9 * (1.0 - d / 2.8)
					if d >= 2.8 and d < 4.0:
						materials[idx] = SAND
			map["waterLevel"] = -0.25
			ambient = "fireflies"
		_:
			ambient = ""
	map["terrainMaterials"] = materials
	map["terrainHeights"] = heights
	map["ambientFx"] = ambient
	# Quelques décors de départ pour que la zone ne soit pas vide.
	var starters := _starter_meshes(theme_id, w, h)
	if not starters.is_empty():
		var existing = map.get("meshes", [])
		if not existing is Array:
			existing = []
		(existing as Array).append_array(starters)
		map["meshes"] = existing

static func _starter_meshes(theme_id: String, w: int, h: int) -> Array:
	var out: Array = []
	var arbre := "res://assets/objects3d/vegetation/arbre.glb"
	var arbre_auto := "res://assets/objects3d/vegetation/arbre_automne.glb"
	var rocher := "res://assets/objects3d/terrain/rocher.glb"
	var mur := "res://assets/objects3d/buildings/mur.glb"
	var puits := "res://assets/objects3d/props/puits.glb"
	var specs: Array = []
	match theme_id:
		"village":
			specs = [[puits, w * 0.5, h * 0.5, 1.2, 1.0, 0.0, false]]
		"forest":
			specs = [
				[arbre, 2.0, 2.0, 1.0, 1.0, 20.0, true],
				[arbre_auto, w - 3.0, 2.5, 1.0, 1.0, 140.0, true],
				[arbre, 2.5, h - 3.0, 1.0, 1.0, 70.0, true],
				[arbre_auto, w - 2.5, h - 2.5, 1.0, 1.0, 200.0, true],
				[rocher, w * 0.5, h - 2.0, 1.0, 1.0, 0.0, true],
			]
		"ruins":
			specs = [
				[mur, 2.0, h * 0.5 - 1.0, 1.5, 1.0, 0.0, false],
				[mur, 4.5, h * 0.5 - 1.0, 1.5, 1.0, 0.0, false],
				[mur, w - 3.0, h * 0.5, 1.5, 1.0, 90.0, false],
				[rocher, w - 2.5, 2.5, 1.0, 1.0, 0.0, true],
			]
		"snow":
			specs = [
				[rocher, 2.0, 2.0, 1.0, 1.0, 0.0, true],
				[rocher, w - 2.5, h - 2.5, 1.0, 1.0, 0.0, true],
			]
		"beach":
			specs = [[rocher, w - 2.5, h - 2.0, 1.0, 1.0, 0.0, true]]
		"lake":
			specs = [
				[rocher, 2.2, h * 0.5, 1.0, 1.0, 0.0, true],
				[arbre, w - 2.2, h * 0.5, 1.0, 1.0, 30.0, true],
			]
	for i in range(specs.size()):
		var s: Array = specs[i]
		out.append({
			"id": "theme-%s-%d" % [theme_id, i],
			"kind": "mesh",
			"x": clampf(float(s[1]), 0.5, float(w) - 0.5),
			"y": clampf(float(s[2]), 0.5, float(h) - 0.5),
			"w": float(s[3]), "h": float(s[4]),
			"asset": str(s[0]),
			"elevation": 0.0,
			"followTerrain": true,
			"tiltToTerrain": bool(s[6]),
			"label": str(s[0]).get_file().get_basename().capitalize(),
			"layer": 1,
			"display": {"rotation": float(s[5]), "scale": 1.0},
		})
	return out
