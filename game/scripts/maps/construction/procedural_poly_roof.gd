extends RefCounted
class_name ProceduralPolyRoof

## Toit sur emprise libre : polygone dessiné au pinceau, sommet surélevé au
## centre et pans triangulés vers les bords. Permet de couvrir des formes
## irrégulières (L, U, courbes) sans passer par des rectangles.

const DEFAULT_HEIGHT := 1.2
const MIN_POINTS := 3

static func build_from_element(elem: Dictionary) -> ArrayMesh:
	var points: Array = []
	for p in elem.get("points", []):
		var v := _as_vector2(p)
		if v != Vector2.INF:
			points.append(v)
	return build(points, float(elem.get("height", DEFAULT_HEIGHT)),
		Color.html(str(elem.get("color", "#a84f3f"))))

static func build(points: Array, height: float = DEFAULT_HEIGHT,
		color: Color = Color("#a84f3f")) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < MIN_POINTS:
		return mesh
	var h := maxf(0.2, height)
	var center := Vector2.ZERO
	for p_variant in points:
		center += p_variant as Vector2
	center /= float(points.size())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(center.x, h, center.y)
	var darker := color.darkened(0.12)
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		_tri(st, apex, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.0, b.y),
			color if i % 2 == 0 else darker)
		# Petit chant vertical.
		_tri(st, Vector3(a.x, 0.0, a.y), Vector3(a.x, -0.18, a.y),
			Vector3(b.x, -0.18, b.y), Color("#7a3a2e"))
		_tri(st, Vector3(a.x, 0.0, a.y), Vector3(b.x, -0.18, b.y),
			Vector3(b.x, 0.0, b.y), Color("#7a3a2e"))
	st.generate_normals()
	return st.commit()

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
