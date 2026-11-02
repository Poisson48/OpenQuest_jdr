extends RefCounted
class_name ProceduralFenceMesh

## Clôture procédurale : poteaux + lisses le long d'une courbe, en un seul mesh.
## Remplace la répétition de modules GLB pour les tracés organiques.

const DEFAULT_HEIGHT := 0.9
const DEFAULT_SPACING := 1.1
const POST_WIDTH := 0.12
const RAIL_THICKNESS := 0.08
const RAIL_SUBDIV := 0.45
const MIN_POINTS := 2

static func build_from_element(elem: Dictionary) -> ArrayMesh:
	var points: Array = []
	for p in elem.get("points", []):
		var v := _as_vector2(p)
		if v != Vector2.INF:
			points.append(v)
	return build(
		points,
		float(elem.get("height", DEFAULT_HEIGHT)),
		float(elem.get("spacing", DEFAULT_SPACING)),
		str(elem.get("fenceTone", "bois"))
	)

static func build(points: Array, height: float = DEFAULT_HEIGHT,
		spacing: float = DEFAULT_SPACING, tone: String = "bois") -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < MIN_POINTS:
		return mesh
	var h := maxf(0.3, height)
	var step := maxf(0.35, spacing)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var color_post := Color("#6d4b32")
	var color_rail := Color("#8a6242")
	match tone:
		"bois_clair":
			color_post = Color("#8a6242")
			color_rail = Color("#a07a52")
		"bois_fonce":
			color_post = Color("#4a3222")
			color_rail = Color("#5d3f2a")
		"pierre":
			color_post = Color("#7e786d")
			color_rail = Color("#9a9488")
	# Poteaux le long de la courbe.
	for i in range(points.size()):
		var p: Vector2 = points[i]
		_box(st, Vector3(p.x, 0.0, p.y), Vector3(POST_WIDTH, h, POST_WIDTH), color_post)
	# Lisses entre les poteaux, approximées par segments de la courbe.
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		for level in [0.35, 0.72]:
			_rail_segmented(st, a, b, h * level, color_rail)
	# Poteaux intermédiaires pour les longs segments.
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length := a.distance_to(b)
		var count := int(floor(length / step))
		if count <= 0:
			continue
		for k in range(1, count):
			var p := a.lerp(b, float(k) / float(count))
			_box(st, Vector3(p.x, 0.0, p.y), Vector3(POST_WIDTH * 0.85, h, POST_WIDTH * 0.85), color_post)
	st.generate_normals()
	return st.commit()

static func _rail_segmented(st: SurfaceTool, a: Vector2, b: Vector2,
		y: float, color: Color) -> void:
	# Découpe les lisses pour qu'elles épousent le relief : sinon une longue
	# lisse reste une corde droite au-dessus/en travers de la colline.
	var length := a.distance_to(b)
	var pieces := maxi(1, ceili(length / RAIL_SUBDIV))
	for i in range(pieces):
		var pa := a.lerp(b, float(i) / float(pieces))
		var pb := a.lerp(b, float(i + 1) / float(pieces))
		_rail(st, pa, pb, y, color)

static func _rail(st: SurfaceTool, a: Vector2, b: Vector2, y: float, color: Color) -> void:
	var dir := (b - a)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var normal := Vector2(-dir.y, dir.x) * RAIL_THICKNESS
	var half := dir * 0.0
	var p0 := Vector2(a.x + normal.x, a.y + normal.y)
	var p1 := Vector2(b.x + normal.x, b.y + normal.y)
	var p2 := Vector2(b.x - normal.x, b.y - normal.y)
	var p3 := Vector2(a.x - normal.x, a.y - normal.y)
	_box_between(st, p0, p1, p2, p3, y, color)

static func _box_between(st: SurfaceTool, p0: Vector2, p1: Vector2,
		p2: Vector2, p3: Vector2, y: float, color: Color) -> void:
	var top := y + RAIL_THICKNESS
	var bottom := y - RAIL_THICKNESS
	_quad(st, Vector3(p0.x, top, p0.y), Vector3(p1.x, top, p1.y),
		Vector3(p2.x, top, p2.y), Vector3(p3.x, top, p3.y), color)
	_quad(st, Vector3(p3.x, bottom, p3.y), Vector3(p2.x, bottom, p2.y),
		Vector3(p1.x, bottom, p1.y), Vector3(p0.x, bottom, p0.y), color)

static func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := center.y
	var y1 := center.y + size.y
	_quad(st, Vector3(center.x - hx, y1, center.z - hz), Vector3(center.x + hx, y1, center.z - hz),
		Vector3(center.x + hx, y1, center.z + hz), Vector3(center.x - hx, y1, center.z + hz), color)
	_quad(st, Vector3(center.x - hx, y0, center.z + hz), Vector3(center.x + hx, y0, center.z + hz),
		Vector3(center.x + hx, y0, center.z - hz), Vector3(center.x - hx, y0, center.z - hz), color)
	_quad(st, Vector3(center.x - hx, y0, center.z - hz), Vector3(center.x + hx, y0, center.z - hz),
		Vector3(center.x + hx, y1, center.z - hz), Vector3(center.x - hx, y1, center.z - hz), color)
	_quad(st, Vector3(center.x + hx, y0, center.z + hz), Vector3(center.x - hx, y0, center.z + hz),
		Vector3(center.x - hx, y1, center.z + hz), Vector3(center.x + hx, y1, center.z + hz), color)
	_quad(st, Vector3(center.x + hx, y0, center.z - hz), Vector3(center.x + hx, y0, center.z + hz),
		Vector3(center.x + hx, y1, center.z + hz), Vector3(center.x + hx, y1, center.z - hz), color)
	_quad(st, Vector3(center.x - hx, y0, center.z + hz), Vector3(center.x - hx, y0, center.z - hz),
		Vector3(center.x - hx, y1, center.z - hz), Vector3(center.x - hx, y1, center.z + hz), color)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)

static func _as_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.INF
