extends RefCounted
class_name ProceduralSceneGenerator

## Générateur de scène déterministe pour MJ non graphiste.
##
## Ne touche pas à la carte : renvoie un plan de placements (maisons, chemins,
## décor, rochers) que l'éditeur applique avec ses propres outils. Quatre styles :
## village, cité, forêt, camp. Une graine rend le résultat reproductible.
##
## Le style « cite » délègue à `ProceduralCity` : il compose de vrais GLB du
## catalogue (bâtiments + modules de toit/façade empilés + props + végétation +
## rochers + clôtures) au lieu des maisons procédurales.

const STYLES := ["village", "cite", "foret", "camp"]
const RockWallScript := preload("res://scripts/maps/construction/procedural_rock_wall.gd")
const ProceduralCityScript := preload("res://scripts/maps/construction/procedural_city.gd")
## Kit de rochers empilables livré dans la bibliothèque (`terrain/rocher_*.glb`).
const ROCK_WALL_MIN_ROWS := 2
const ROCK_WALL_MAX_ROWS := 3

static func style_label(style_id: String) -> String:
	match style_id:
		"cite":
			return "Cité"
		"foret":
			return "Forêt"
		"camp":
			return "Camp"
		_:
			return "Village"

## Ajoute un mur/affleurement de rochers empilés au plan.
## `rocks` reçoit des placements prêts pour `doc.add_element` (kind mesh).
## `max_stones` borne le budget : un mur de village reste lisible et léger.
static func _add_rock_wall(result: Dictionary, from: Vector2, to: Vector2,
		rows: int, rng: RandomNumberGenerator, width: int, height: int,
		max_stones: int = 18) -> void:
	var direction := to - from
	var length := direction.length()
	if length < 1.0 or rows <= 0:
		return
	# Un mur trop long est tronqué : mieux vaut un affleurement crédible qu'une
	# ceinture de pierres sur toute la carte.
	length = minf(length, float(rows) * float(max_stones) * 0.42)
	var placements := RockWallScript.build_run_cells(
		from, direction, length, clampi(rows, ROCK_WALL_MIN_ROWS, ROCK_WALL_MAX_ROWS),
		rng.randi() % 1000000
	)
	# On ajoute colonne par colonne : si le budget coupe, le mur garde sa
	# hauteur au lieu de finir en escalier.
	var columns: Dictionary = {}
	for placement_variant in placements:
		var placement: Dictionary = placement_variant
		var column := int(placement.get("slot", 0))
		if not columns.has(column):
			columns[column] = []
		(columns[column] as Array).append(placement)
	var column_keys: Array = columns.keys()
	column_keys.sort()
	for column_variant in column_keys:
		for placement_variant in columns[column_variant]:
			if result["rocks"].size() >= max_stones:
				return
			var placement: Dictionary = placement_variant
			var px := float(placement.get("x", 0.0))
			var py := float(placement.get("y", 0.0))
			# Une pierre à cheval hors carte est ignorée : le mur reste praticable.
			if px < 0.4 or py < 0.4 or px > float(width) - 0.4 or py > float(height) - 0.4:
				continue
			result["rocks"].append(placement)

## Renvoie {houses, paths, props, fences, flowerZones, rocks, buildings}.
## `buildings` n'est rempli que par le style « cite » : chaque entrée porte
## l'asset GLB, la rotation et les modules de toit (`roofs`, élevés) / façade
## (`walls`) qui l'habillent.
static func generate(style_id: String, width: int, height: int, seed: int,
		density: float = 1.0, origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var result := _empty_plan(style_id)
	if width < 8 or height < 8:
		return result
	match style_id:
		"cite":
			result = ProceduralCityScript.generate(width, height, seed, density)
		"foret":
			_generate_forest(result, width, height, rng, density)
		"camp":
			_generate_camp(result, width, height, rng, density)
		_:
			_generate_village(result, width, height, rng, density)
	_offset_plan(result, origin)
	return result

static func _empty_plan(style_id: String) -> Dictionary:
	return {"houses": [], "paths": [], "props": [], "fences": [], "flowerZones": [],
		"rocks": [], "buildings": [], "style": style_id}

## Génère une scène complète à l'intérieur d'une zone dessinée par le MJ.
static func generate_in_area(style_id: String, map_width: int, map_height: int,
		area: Rect2, seed: int, density: float = 1.0) -> Dictionary:
	var clipped := area.intersection(Rect2(0, 0, float(map_width), float(map_height)))
	var w := int(round(clipped.size.x))
	var h := int(round(clipped.size.y))
	if w < 8 or h < 8:
		return _empty_plan(style_id)
	return generate(style_id, w, h, seed, density, clipped.position)

static func _offset_plan(result: Dictionary, origin: Vector2) -> void:
	if origin == Vector2.ZERO:
		return
	var houses: Array = result.get("houses", [])
	for i in range(houses.size()):
		var rect: Rect2 = houses[i]
		houses[i] = Rect2(rect.position + origin, rect.size)
	for path_variant in result.get("paths", []):
		var path: Dictionary = path_variant
		if path.has("rect"):
			var path_rect: Rect2 = path["rect"]
			path["rect"] = Rect2(path_rect.position + origin, path_rect.size)
		else:
			path["from"] = (path.get("from", Vector2.ZERO) as Vector2) + origin
			path["to"] = (path.get("to", Vector2.ZERO) as Vector2) + origin
	for prop_variant in result.get("props", []):
		var prop: Dictionary = prop_variant
		prop["x"] = float(prop.get("x", 0.0)) + origin.x
		prop["y"] = float(prop.get("y", 0.0)) + origin.y
	for fence_variant in result.get("fences", []):
		var points: Array = fence_variant
		for i in range(points.size()):
			points[i] = (points[i] as Vector2) + origin
	for zone_variant in result.get("flowerZones", []):
		var zone: Dictionary = zone_variant
		var rect: Rect2 = zone.get("rect", Rect2())
		zone["rect"] = Rect2(rect.position + origin, rect.size)
	for rock_variant in result.get("rocks", []):
		var rock: Dictionary = rock_variant
		rock["x"] = float(rock.get("x", 0.0)) + origin.x
		rock["y"] = float(rock.get("y", 0.0)) + origin.y
	_offset_buildings_plan(result, origin)

## Décale les bâtiments GLB de la cité et leurs modules (toits, façades) :
## les positions sont stockées dans le repère local du plan.
static func _offset_buildings_plan(result: Dictionary, origin: Vector2) -> void:
	for building_variant in result.get("buildings", []):
		var building: Dictionary = building_variant
		building["x"] = float(building.get("x", 0.0)) + origin.x
		building["y"] = float(building.get("y", 0.0)) + origin.y
		for roof_variant in building.get("roofs", []):
			var roof: Dictionary = roof_variant
			roof["x"] = float(roof.get("x", 0.0)) + origin.x
			roof["y"] = float(roof.get("y", 0.0)) + origin.y
		for wall_variant in building.get("walls", []):
			var wall: Dictionary = wall_variant
			wall["x"] = float(wall.get("x", 0.0)) + origin.x
			wall["y"] = float(wall.get("y", 0.0)) + origin.y

static func _generate_village(result: Dictionary, width: int, height: int,
		rng: RandomNumberGenerator, density: float) -> void:
	var road_y := height / 2
	result["paths"].append({"from": Vector2(2, road_y), "to": Vector2(width - 2, road_y), "width": 1})
	# Petite place centrale : puits + fontaine + arbres.
	var plaza := Vector2(width * 0.5, road_y - 1.2)
	result["paths"].append({"from": Vector2(plaza.x, road_y), "to": plaza, "width": 1})
	result["props"].append({
		"asset": "res://assets/objects3d/props/puits_couvert.glb",
		"x": plaza.x - 1.0, "y": clampf(plaza.y, 1.0, float(height) - 1.0), "scale": 1.0,
	})
	if rng.randf() < 0.7:
		result["props"].append({
			"asset": "res://assets/objects3d/props/fontaine.glb",
			"x": plaza.x + 1.3, "y": clampf(plaza.y + 0.6, 1.0, float(height) - 1.0), "scale": 0.9,
		})
	for i in range(2):
		result["props"].append({
			"asset": "res://assets/objects3d/vegetation/arbre.glb",
			"x": clampf(plaza.x + (-3.5 if i == 0 else 3.5), 1.0, float(width) - 1.0),
			"y": clampf(plaza.y - 1.5, 1.0, float(height) - 1.0),
			"scale": rng.randf_range(0.9, 1.2),
		})
	var slots: int = clampi(int(round(float(width - 8) / 4.0 * density)), 1, 6)
	for i in range(slots):
		var cx := 4.0 + (float(width - 8) * (float(i) + 0.5) / float(slots))
		for side in [-1.0, 1.0]:
			if rng.randf() > 0.72:
				continue
			var w := rng.randf_range(2.5, 4.0)
			var h := rng.randf_range(2.0, 3.2)
			var y: float = road_y + side * rng.randf_range(2.0, 3.2) - (h if side > 0.0 else 0.0)
			var rect := Rect2(cx - w * 0.5, y, w, h)
			rect = _clamp_rect(rect, width, height)
			if _overlaps_any(rect, result["houses"]):
				continue
			result["houses"].append(rect)
			result["props"].append({
				"asset": "res://assets/objects3d/vegetation/buisson.glb",
				"x": cx + rng.randf_range(-1.0, 1.0),
				"y": road_y + side * rng.randf_range(3.8, 5.0),
				"scale": rng.randf_range(0.8, 1.2),
			})
			# Petite clôture basse devant la façade côté route.
			result["fences"].append([
				Vector2(rect.position.x + 0.3, rect.end.y + 0.5),
				Vector2(rect.end.x - 0.3, rect.end.y + 0.5),
			])
			result["flowerZones"].append({
				"rect": Rect2(rect.position.x + 0.5, rect.end.y + 0.9, maxf(1.0, rect.size.x - 1.0), 0.8),
				"type": ["marguerite", "coquelicot", "lavande"][rng.randi() % 3],
				"density": 4.0,
			})
	# Mur de soutènement en pierres sèches sur la bordure haute du village :
	# il ferme la scène sans bloquer la route centrale.
	var top_y := 1.2
	var wall_from := Vector2(1.2, top_y)
	var wall_to := Vector2(minf(float(width) - 1.2, 11.2), top_y + rng.randf_range(-0.6, 0.6))
	_add_rock_wall(result, wall_from, wall_to, 2, rng, width, height, 14)

static func _generate_forest(result: Dictionary, width: int, height: int,
		rng: RandomNumberGenerator, density: float) -> void:
	var center := Vector2(width * 0.5, height * 0.5)
	result["paths"].append({"from": center, "to": Vector2(width - 2, center.y), "width": 1})
	var count: int = clampi(int(round(float(width * height) * 0.035 * density)), 4, 80)
	for _i in range(count):
		var pos := Vector2(rng.randf_range(1.5, width - 1.5), rng.randf_range(1.5, height - 1.5))
		if pos.distance_to(center) < 3.0:
			continue
		var clear := false
		for h in result["houses"]:
			if (h as Rect2).grow(0.8).has_point(pos):
				clear = true
				break
		if clear:
			continue
		result["props"].append({
			"asset": "res://assets/objects3d/vegetation/arbre.glb" if rng.randf() < 0.55
				else "res://assets/objects3d/vegetation/buisson.glb",
			"x": pos.x, "y": pos.y, "scale": rng.randf_range(0.7, 1.35),
		})
	# Clairière : quelques rochers Marching Cubes, encadrés d'un affleurement.
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3)
		result["props"].append({
			"asset": "res://assets/objects3d/terrain/rocher.glb",
			"x": center.x + cos(angle) * 2.6, "y": center.y + sin(angle) * 2.6,
			"scale": rng.randf_range(0.7, 1.1),
		})
	# Deux affleurements de rochers empilés en lisière de clairière.
	var clearance := 5.2
	_add_rock_wall(result,
		Vector2(center.x - clearance, center.y - clearance * 0.7),
		Vector2(center.x + clearance * 0.2, center.y - clearance),
		3, rng, width, height, 14)
	_add_rock_wall(result,
		Vector2(center.x + clearance * 0.4, center.y + clearance),
		Vector2(center.x + clearance, center.y - clearance * 0.2),
		2, rng, width, height, 10)

static func _generate_camp(result: Dictionary, width: int, height: int,
		rng: RandomNumberGenerator, density: float) -> void:
	var center := Vector2(width * 0.5, height * 0.5)
	result["paths"].append({"from": Vector2(2, center.y), "to": Vector2(width - 2, center.y), "width": 1})
	# Feu central et réserve.
	result["props"].append({"asset": "procedural://campfire", "x": center.x, "y": center.y, "scale": 1.0})
	for offset in [Vector2(-2.0, 0.8), Vector2(2.1, 0.6), Vector2(0.8, 2.2), Vector2(-0.7, -2.2)]:
		result["props"].append({
			"asset": "res://assets/objects3d/props/tonneau.glb",
			"x": center.x + offset.x, "y": center.y + offset.y, "scale": 0.85,
		})
	result["props"].append({
		"asset": "res://assets/objects3d/props/banniere.glb",
		"x": center.x - 2.8, "y": center.y - 2.0, "scale": 1.0,
	})
	result["props"].append({
		"asset": "res://assets/objects3d/props/charrette.glb",
		"x": center.x + 3.2, "y": center.y - 2.2, "scale": 0.9,
	})
	var tents: int = clampi(int(round(3.0 * density)), 1, 6)
	for i in range(tents):
		var angle := TAU * float(i) / float(tents)
		var pos := center + Vector2(cos(angle), sin(angle)) * 3.2
		result["props"].append({
			"asset": "procedural://tent",
			"x": pos.x, "y": pos.y, "scale": 0.75,
		})
		result["props"].append({
			"asset": "res://assets/objects3d/props/caisse.glb",
			"x": pos.x + rng.randf_range(-1.2, 1.2),
			"y": pos.y + rng.randf_range(-1.2, 1.2),
			"scale": 0.8,
		})
	# Enclos rocheux côté nord : deux assises de pierres empilées.
	var north := maxf(1.2, center.y - 4.6)
	_add_rock_wall(result,
		Vector2(maxf(1.0, center.x - 4.4), north),
		Vector2(minf(float(width) - 1.0, center.x + 4.4), north),
		2, rng, width, height)

static func _clamp_rect(rect: Rect2, width: int, height: int) -> Rect2:
	var x := clampf(rect.position.x, 0.5, float(width) - rect.size.x - 0.5)
	var y := clampf(rect.position.y, 0.5, float(height) - rect.size.y - 0.5)
	return Rect2(x, y, minf(rect.size.x, float(width) - 1.0), minf(rect.size.y, float(height) - 1.0))

static func _overlaps_any(rect: Rect2, rects: Array) -> bool:
	for other_variant in rects:
		if (other_variant as Rect2).grow(0.6).intersects(rect):
			return true
	return false
