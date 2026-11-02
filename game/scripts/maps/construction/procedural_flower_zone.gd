extends RefCounted
class_name ProceduralFlowerZone

## Fleurs procédurales dans une zone dessinée au pinceau.
##
## L'élément de carte porte un polygone local (`points`, en cases relatives au
## centre), un type de fleur, une densité, une taille et une graine. Le mesh est
## un seul ArrayMesh : de petites fleurs en croix, colorées par type, avec des
## variations déterministes. La végétation automatique reste désactivée ; seules
## les zones explicitement peintes apparaissent.

const FLOWER_TYPES := [
	{"id": "coquelicot", "label": "Coquelicots", "colors": ["#d9472e", "#e35a35", "#b83324"]},
	{"id": "marguerite", "label": "Marguerites", "colors": ["#f5f0df", "#fff7e8", "#e8dfc5"]},
	{"id": "lavande", "label": "Lavande", "colors": ["#8d6bb5", "#a184c7", "#74559f"]},
	{"id": "bleue", "label": "Fleurs bleues", "colors": ["#5d8fd0", "#77a5df", "#4b78b7"]},
	{"id": "mix", "label": "Mélange sauvage", "colors": ["#f5f0df", "#d9472e", "#8d6bb5", "#e4c34c"]},
]
const DEFAULT_TYPE := "marguerite"
const DEFAULT_DENSITY := 3.0
const DEFAULT_SIZE := 0.36
const MAX_FLOWERS := 4000

static func type_label(type_id: String) -> String:
	for entry_variant in FLOWER_TYPES:
		var entry: Dictionary = entry_variant
		if str(entry["id"]) == type_id:
			return str(entry["label"])
	return "Fleurs"

static func build_from_element(elem: Dictionary) -> ArrayMesh:
	var points: Array = []
	var raw = elem.get("points", [])
	if raw is Array:
		for p in raw:
			var v := _as_vector2(p)
			if v != Vector2.INF:
				points.append(v)
	var type_id := str(elem.get("flowerType", DEFAULT_TYPE))
	var density := maxf(0.1, float(elem.get("density", DEFAULT_DENSITY)))
	var size := maxf(0.05, float(elem.get("size", DEFAULT_SIZE)))
	var seed := int(elem.get("seed", 1))
	return build(points, type_id, density, size, seed)

## Construit les fleurs d'un polygone local.
static func build(points: Array, type_id: String, density: float,
		size: float, seed: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 3:
		return mesh
	var area := absf(_polygon_area(points))
	if area < 0.01:
		return mesh
	var palette := _palette(type_id)
	var count := clampi(int(round(area * density)), 1, MAX_FLOWERS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 8:
		attempts += 1
		var p := _random_point_in_polygon(points, rng)
		var color := Color.html(str(palette[rng.randi() % palette.size()]))
		var scale := size * rng.randf_range(0.65, 1.35)
		var angle := rng.randf_range(0.0, TAU)
		_add_flower(st, p, scale, angle, color)
		placed += 1
	if placed == 0:
		return mesh
	st.generate_normals()
	return st.commit()

static func _palette(type_id: String) -> Array:
	for entry_variant in FLOWER_TYPES:
		var entry: Dictionary = entry_variant
		if str(entry["id"]) == type_id:
			return entry["colors"]
	return FLOWER_TYPES[1]["colors"]

static func _add_flower(st: SurfaceTool, p: Vector2, size: float,
		angle: float, color: Color) -> void:
	# Deux quads croisés, en éventail autour du centre, très bas.
	var h := size * 0.65
	for i in range(2):
		var a := angle + float(i) * PI * 0.5
		var dir := Vector2(cos(a), sin(a)) * size
		var side := Vector2(-dir.y, dir.x) * size * 0.45
		var base := Vector3(p.x, 0.01, p.y)
		var top := Vector3(p.x, h, p.y)
		var left := Vector3(p.x + side.x, h * 0.65, p.y + side.y)
		var right := Vector3(p.x - side.x, h * 0.65, p.y - side.y)
		_tri(st, base, top, left, color)
		_tri(st, base, right, top, color)
	# Centre jaune/clair.
	var c := Vector3(p.x, h * 0.72, p.y)
	var s := size * 0.22
	_tri(st, c + Vector3(s, 0.0, 0.0), c + Vector3(0.0, 0.0, s), c + Vector3(-s, 0.0, 0.0), Color(1.0, 0.87, 0.38))
	_tri(st, c + Vector3(-s, 0.0, 0.0), c + Vector3(0.0, 0.0, -s), c + Vector3(s, 0.0, 0.0), Color(1.0, 0.87, 0.38))

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)

static func _polygon_area(points: Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5

static func _random_point_in_polygon(points: Array, rng: RandomNumberGenerator) -> Vector2:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p_variant in points:
		var p: Vector2 = p_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	for _i in range(64):
		var candidate := Vector2(
			rng.randf_range(min_p.x, max_p.x),
			rng.randf_range(min_p.y, max_p.y)
		)
		if _point_in_polygon(candidate, points):
			return candidate
	return (min_p + max_p) * 0.5

static func _point_in_polygon(p: Vector2, points: Array) -> bool:
	var inside := false
	var j := points.size() - 1
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[j]
		if ((a.y > p.y) != (b.y > p.y)) \
				and (p.x < (b.x - a.x) * (p.y - a.y) / maxf(0.000001, b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside

static func _as_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.INF
