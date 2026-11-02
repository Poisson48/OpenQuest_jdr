extends RefCounted
class_name ProceduralSceneGenerator

## Générateur de scène déterministe pour MJ non graphiste.
##
## Ne touche pas à la carte : renvoie un plan de placements (maisons, chemins,
## décor) que l'éditeur applique avec ses propres outils. Trois styles :
## village, forêt, camp. Une graine rend le résultat reproductible.

const STYLES := ["village", "foret", "camp"]

static func style_label(style_id: String) -> String:
	match style_id:
		"foret":
			return "Forêt"
		"camp":
			return "Camp"
		_:
			return "Village"

## Renvoie {houses: Array[Rect2], paths: Array[Dictionary], props: Array[Dictionary]}.
static func generate(style_id: String, width: int, height: int, seed: int,
		density: float = 1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var result := {"houses": [], "paths": [], "props": [], "fences": [], "style": style_id}
	if width < 8 or height < 8:
		return result
	match style_id:
		"foret":
			_generate_forest(result, width, height, rng, density)
		"camp":
			_generate_camp(result, width, height, rng, density)
		_:
			_generate_village(result, width, height, rng, density)
	return result

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
	# Clairière : quelques rochers et fleurs autour du centre.
	for i in range(4):
		var angle := TAU * float(i) / 4.0 + rng.randf_range(-0.3, 0.3)
		result["props"].append({
			"asset": "res://assets/objects3d/terrain/rocher.glb",
			"x": center.x + cos(angle) * 2.6, "y": center.y + sin(angle) * 2.6,
			"scale": rng.randf_range(0.7, 1.1),
		})

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

static func _clamp_rect(rect: Rect2, width: int, height: int) -> Rect2:
	var x := clampf(rect.position.x, 0.5, float(width) - rect.size.x - 0.5)
	var y := clampf(rect.position.y, 0.5, float(height) - rect.size.y - 0.5)
	return Rect2(x, y, minf(rect.size.x, float(width) - 1.0), minf(rect.size.y, float(height) - 1.0))

static func _overlaps_any(rect: Rect2, rects: Array) -> bool:
	for other_variant in rects:
		if (other_variant as Rect2).grow(0.6).intersects(rect):
			return true
	return false
