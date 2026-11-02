extends RefCounted
class_name ProceduralRoofMesh

## Toit procédural à deux pans, généré depuis l'emprise réellement dessinée.
## Fini les rangées de tuiles GLB à recaler : un seul mesh, avec débord et
## pignons, s'adapte à la largeur/profondeur de la pièce.

const DEFAULT_HEIGHT := 1.1
const DEFAULT_OVERHANG := 0.35
const MIN_SIZE := 0.5

static func build_from_element(elem: Dictionary) -> ArrayMesh:
	var w := maxf(MIN_SIZE, float(elem.get("w", 2.0)))
	var d := maxf(MIN_SIZE, float(elem.get("h", 2.0)))
	var height := maxf(0.2, float(elem.get("roofHeight", DEFAULT_HEIGHT)))
	var overhang := maxf(0.0, float(elem.get("overhang", DEFAULT_OVERHANG)))
	return build(w, d, height, overhang)

## Construit le toit en unités « cases », centré sur l'origine.
static func build(w: float, d: float, height: float = DEFAULT_HEIGHT,
		overhang: float = DEFAULT_OVERHANG) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var span_x := maxf(MIN_SIZE, w) + overhang * 2.0
	var span_z := maxf(MIN_SIZE, d) + overhang * 2.0
	var half_x := span_x * 0.5
	var half_z := span_z * 0.5
	var h := maxf(0.2, height)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope_a := Color("#b85a45")
	var slope_b := Color("#cf7058")
	var gable := Color("#8f4738")
	if span_x >= span_z:
		# Faîtage le long de X, pans vers ±Z, en rangs de tuiles.
		var ridge_a := Vector3(-half_x, h, 0.0)
		var ridge_b := Vector3(half_x, h, 0.0)
		var eave_a1 := Vector3(-half_x, 0.0, -half_z)
		var eave_b1 := Vector3(half_x, 0.0, -half_z)
		var eave_a2 := Vector3(-half_x, 0.0, half_z)
		var eave_b2 := Vector3(half_x, 0.0, half_z)
		var rows := 6
		for row in range(rows):
			var t0 := float(row) / float(rows)
			var t1 := float(row + 1) / float(rows)
			var y0 := h * t0
			var y1 := h * t1
			var z0 := half_z * (1.0 - t0)
			var z1 := half_z * (1.0 - t1)
			var color := slope_a if row % 2 == 0 else slope_b
			# Pan -Z.
			_quad(st, Vector3(-half_x, y0, -z0), Vector3(half_x, y0, -z0),
				Vector3(half_x, y1, -z1), Vector3(-half_x, y1, -z1), color)
			# Pan +Z.
			_quad(st, Vector3(half_x, y0, z0), Vector3(-half_x, y0, z0),
				Vector3(-half_x, y1, z1), Vector3(half_x, y1, z1), color)
		# Faîtage sombre.
		_quad(st, ridge_a, ridge_b, ridge_b + Vector3(0, 0.02, 0.12),
			ridge_a + Vector3(0, 0.02, 0.12), Color("#7a3a2e"))
		# Pignons verticaux.
		_tri(st, eave_a2, ridge_a, eave_a1, gable)
		_tri(st, eave_b1, ridge_b, eave_b2, gable)
	else:
		# Faîtage le long de Z, pans vers ±X, en rangs de tuiles.
		var ridge_a := Vector3(0.0, h, -half_z)
		var ridge_b := Vector3(0.0, h, half_z)
		var eave_a1 := Vector3(-half_x, 0.0, -half_z)
		var eave_b1 := Vector3(-half_x, 0.0, half_z)
		var eave_a2 := Vector3(half_x, 0.0, -half_z)
		var eave_b2 := Vector3(half_x, 0.0, half_z)
		var rows := 6
		for row in range(rows):
			var t0 := float(row) / float(rows)
			var t1 := float(row + 1) / float(rows)
			var y0 := h * t0
			var y1 := h * t1
			var x0 := half_x * (1.0 - t0)
			var x1 := half_x * (1.0 - t1)
			var color := slope_a if row % 2 == 0 else slope_b
			_quad(st, Vector3(-x0, y0, -half_z), Vector3(-x0, y0, half_z),
				Vector3(-x1, y1, half_z), Vector3(-x1, y1, -half_z), color)
			_quad(st, Vector3(x0, y0, half_z), Vector3(x0, y0, -half_z),
				Vector3(x1, y1, -half_z), Vector3(x1, y1, half_z), color)
		_quad(st, ridge_a, ridge_b, ridge_b + Vector3(0.12, 0.02, 0),
			ridge_a + Vector3(0.12, 0.02, 0), Color("#7a3a2e"))
		_tri(st, eave_a1, ridge_a, eave_b1, gable)
		_tri(st, eave_a2, eave_b2, ridge_b, gable)
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
