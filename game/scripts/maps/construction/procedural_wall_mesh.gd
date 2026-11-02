extends RefCounted
class_name ProceduralWallMesh

## Générateur de mur continu et organique.
##
## Le mur est construit à partir d'une polyligne (en cases, repère local au
## centre de l'élément) : les côtés sont décalés avec des **mitres** aux angles,
## puis les faces latérales et la face supérieure sont générées dans un seul
## ArrayMesh. Contrairement aux modules GLB, il n'y a donc ni micro-segments ni
## marches d'escalier aux virages.
##
## Le mesh est en unités « cases » ; MapMeshes3D applique ensuite l'échelle de
## la cellule et positionne la racine.

const MIN_POINTS := 2
const MIN_HEIGHT := 0.2
const MIN_THICKNESS := 0.15
const DEFAULT_HEIGHT := 2.2
const DEFAULT_THICKNESS := 0.7

## Construit un ArrayMesh à partir d'un élément de carte `mesh`.
## Champs attendus : `points` (Array de Vector2/Array [x,y] ou dictionnaires),
## `height`, `thickness`, `bevel` optionnel.
static func build_from_element(elem: Dictionary) -> ArrayMesh:
	var raw_points = elem.get("points", [])
	var points: Array = []
	if raw_points is Array:
		for p in raw_points:
			var v := _as_vector2(p)
			if v != Vector2.INF:
				points.append(v)
	return build(
		points,
		float(elem.get("height", DEFAULT_HEIGHT)),
		float(elem.get("thickness", DEFAULT_THICKNESS)),
		float(elem.get("bevel", 0.0))
	)

## Construit le mesh. `points` est une polyligne en cases, dans le repère local.
static func build(points: Array, height: float = DEFAULT_HEIGHT,
		thickness: float = DEFAULT_THICKNESS, bevel: float = 0.0) -> ArrayMesh:
	var pts: Array = []
	for p in points:
		var v := _as_vector2(p)
		if v != Vector2.INF:
			pts.append(v)
	var mesh := ArrayMesh.new()
	if pts.size() < MIN_POINTS:
		return mesh
	height = maxf(MIN_HEIGHT, height)
	thickness = maxf(MIN_THICKNESS, thickness)
	bevel = clampf(bevel, 0.0, thickness * 0.45)

	# Sections : gauche/droite avec mitre. On garde aussi la position de base
	# pour les faces d'extrémité et une crête biseautée.
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	var inner_left: Array[Vector2] = []
	var inner_right: Array[Vector2] = []
	var bevel_amount := minf(bevel, thickness * 0.4)
	for i in range(pts.size()):
		var dir := _segment_dirs(pts, i)
		var n_left := Vector2(-dir.y, dir.x)
		var half := thickness * 0.5
		var left_pt: Vector2 = pts[i] + n_left * half
		var right_pt: Vector2 = pts[i] - n_left * half
		if i > 0 and i < pts.size() - 1:
			var prev_dir := _segment_dirs(pts, i - 1)
			var prev_left := Vector2(-prev_dir.y, prev_dir.x)
			var miter := (prev_left + n_left)
			if miter.length() > 0.001:
				miter = miter.normalized()
				var denom := maxf(0.25, absf(miter.dot(prev_left)))
				var offset := miter * (half / denom)
				left_pt = pts[i] + offset
				right_pt = pts[i] - offset
		left.append(left_pt)
		right.append(right_pt)
		var inward := (right_pt - left_pt).normalized() * bevel_amount
		inner_left.append(left_pt + inward)
		inner_right.append(right_pt - inward)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var distance := 0.0
	var side_top := maxf(0.05, height - bevel_amount)
	for i in range(pts.size()):
		if i > 0:
			distance += pts[i].distance_to(pts[i - 1])
		var u := distance / maxf(0.5, thickness * 2.0)
		var top := height
		var lb := Vector3(left[i].x, 0.0, left[i].y)
		var rb := Vector3(right[i].x, 0.0, right[i].y)
		var lt := Vector3(left[i].x, side_top, left[i].y)
		var rt := Vector3(right[i].x, side_top, right[i].y)
		# Faces latérales.
		if i < pts.size() - 1:
			var j := i + 1
			var lb2 := Vector3(left[j].x, 0.0, left[j].y)
			var rb2 := Vector3(right[j].x, 0.0, right[j].y)
			var lt2 := Vector3(left[j].x, side_top, left[j].y)
			var rt2 := Vector3(right[j].x, side_top, right[j].y)
			_quad(st, lb, lt, lt2, lb2, u, _u(j, pts, thickness), 0.0, side_top)
			_quad(st, rb2, rt2, rt, rb, _u(j, pts, thickness), u, 0.0, side_top)
			if bevel_amount > 0.01:
				var il := Vector3(inner_left[i].x, top, inner_left[i].y)
				var ir := Vector3(inner_right[i].x, top, inner_right[i].y)
				var il2 := Vector3(inner_left[j].x, top, inner_left[j].y)
				var ir2 := Vector3(inner_right[j].x, top, inner_right[j].y)
				_quad(st, lt, lt2, il2, il, u, _u(j, pts, thickness), side_top, top)
				_quad(st, ir2, ir, rt, rt2, _u(j, pts, thickness), u, side_top, top)
				_quad(st, il, il2, ir2, ir, u, _u(j, pts, thickness), top, top)
			else:
				_quad(st, lt, lt2, rt2, rt, u, _u(j, pts, thickness), side_top, side_top)
	# Faces d'extrémité.
	var last := pts.size() - 1
	_end_face(st, left[0], right[0], height, true)
	_end_face(st, left[last], right[last], height, false)
	st.generate_normals()
	return st.commit()

static func _segment_dirs(pts: Array, index: int) -> Vector2:
	var a: Vector2
	var b: Vector2
	if index <= 0:
		a = pts[0]
		b = pts[1]
	elif index >= pts.size() - 1:
		a = pts[pts.size() - 2]
		b = pts[pts.size() - 1]
	else:
		a = pts[index - 1]
		b = pts[index + 1]
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT

static func _u(index: int, pts: Array, thickness: float) -> float:
	var d := 0.0
	for i in range(1, index + 1):
		d += pts[i].distance_to(pts[i - 1])
	return d / maxf(0.5, thickness * 2.0)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		u0: float, u1: float, v0: float, v1: float) -> void:
	# Deux triangles, dans l'ordre a-b-c puis a-c-d.
	st.set_uv(Vector2(u0, v0))
	st.add_vertex(a)
	st.set_uv(Vector2(u1, v0))
	st.add_vertex(b)
	st.set_uv(Vector2(u1, v1))
	st.add_vertex(c)
	st.set_uv(Vector2(u0, v0))
	st.add_vertex(a)
	st.set_uv(Vector2(u1, v1))
	st.add_vertex(c)
	st.set_uv(Vector2(u0, v1))
	st.add_vertex(d)

static func _end_face(st: SurfaceTool, left: Vector2, right: Vector2,
		height: float, front: bool) -> void:
	var lb := Vector3(left.x, 0.0, left.y)
	var rb := Vector3(right.x, 0.0, right.y)
	var lt := Vector3(left.x, height, left.y)
	var rt := Vector3(right.x, height, right.y)
	if front:
		_quad(st, rb, rt, lt, lb, 0.0, 1.0, 0.0, height)
	else:
		_quad(st, lb, lt, rt, rb, 0.0, 1.0, 0.0, height)

static func _as_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.INF
