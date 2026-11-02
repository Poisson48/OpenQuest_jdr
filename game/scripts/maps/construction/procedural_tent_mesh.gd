extends RefCounted
class_name ProceduralTentMesh

## Tente de camp procédurale : structure en A, toile beige, ouverture sombre.
## Complète le générateur de camp sans dépendre d'un GLB dédié.

const DEFAULT_WIDTH := 2.2
const DEFAULT_DEPTH := 2.6
const DEFAULT_HEIGHT := 1.8

static func build_from_element(elem: Dictionary) -> ArrayMesh:
	return build(
		float(elem.get("w", DEFAULT_WIDTH)),
		float(elem.get("h", DEFAULT_DEPTH)),
		float(elem.get("height", DEFAULT_HEIGHT))
	)

static func build(w: float, d: float, h: float = DEFAULT_HEIGHT) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var half_x := maxf(0.5, w) * 0.5
	var half_z := maxf(0.5, d) * 0.5
	var height := maxf(0.5, h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var canvas := Color("#d9c7a6")
	var canvas_dark := Color("#bfa987")
	var opening := Color("#3a2d22")
	# Deux pans de toile.
	var ridge_a := Vector3(0.0, height, -half_z)
	var ridge_b := Vector3(0.0, height, half_z)
	_quad(st, Vector3(-half_x, 0.0, -half_z), Vector3(-half_x, 0.0, half_z),
		ridge_b, ridge_a, canvas)
	_quad(st, ridge_a, ridge_b, Vector3(half_x, 0.0, half_z),
		Vector3(half_x, 0.0, -half_z), canvas_dark)
	# Pignons avant/arrière avec ouverture sombre au centre.
	_tri(st, Vector3(-half_x, 0.0, half_z), ridge_b, Vector3(half_x, 0.0, half_z), canvas)
	_tri(st, Vector3(half_x, 0.0, -half_z), ridge_a, Vector3(-half_x, 0.0, -half_z), canvas)
	# Ouverture simplifiée côté +Z.
	_tri(st, Vector3(-half_x * 0.35, 0.02, half_z + 0.01),
		Vector3(0.0, height * 0.38, half_z + 0.01),
		Vector3(half_x * 0.35, 0.02, half_z + 0.01), opening)
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
