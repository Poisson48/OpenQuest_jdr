extends RefCounted
class_name ProceduralFloorMesh

## Dalle d'étage procédurale : un seul mesh (dessus, dessous, chants), posé
## entre deux niveaux de murs. Évite les maisons à étages « ouvertes ».

const DEFAULT_THICKNESS := 0.14
const MIN_SIZE := 0.5

static func build_from_element(elem: Dictionary) -> ArrayMesh:
	var w := maxf(MIN_SIZE, float(elem.get("w", 2.0)))
	var d := maxf(MIN_SIZE, float(elem.get("h", 2.0)))
	var thickness := maxf(0.04, float(elem.get("thickness", DEFAULT_THICKNESS)))
	return build(w, d, thickness)

static func build(w: float, d: float, thickness: float = DEFAULT_THICKNESS) -> ArrayMesh:
	var t := maxf(0.04, thickness)
	var hx := w * 0.5
	var hz := d * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Color("#9a7a55")
	var bottom := Color("#6f563c")
	var side := Color("#82684a")
	# Dessus.
	_quad(st, Vector3(-hx, t, -hz), Vector3(hx, t, -hz), Vector3(hx, t, hz), Vector3(-hx, t, hz), top)
	# Dessous.
	_quad(st, Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), bottom)
	# Chants.
	_quad(st, Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, t, -hz), Vector3(-hx, t, -hz), side)
	_quad(st, Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(-hx, t, hz), Vector3(hx, t, hz), side)
	_quad(st, Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(hx, t, hz), Vector3(hx, t, -hz), side)
	_quad(st, Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz), Vector3(-hx, t, -hz), Vector3(-hx, t, hz), side)
	st.generate_normals()
	return st.commit()

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
