extends RefCounted
class_name ProceduralCampfireMesh

## Feu de camp procédural : bûches croisées + flamme low-poly orangée.

const SIZE := 0.8
const FLAME_HEIGHT := 0.9

static func build_from_element(_elem: Dictionary) -> ArrayMesh:
	return build()

static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color("#5a3b26")
	# Bûches croisées.
	for angle in [0.0, PI * 0.5]:
		var dir := Vector2(cos(angle), sin(angle))
		var normal := Vector2(-dir.y, dir.x)
		var half := dir * SIZE * 0.5
		var width := normal * 0.09
		_box_flat(st,
			Vector3(-half.x - width.x, 0.06, -half.y - width.y),
			Vector3(half.x - width.x, 0.06, half.y - width.y),
			Vector3(half.x + width.x, 0.06, half.y + width.y),
			Vector3(-half.x + width.x, 0.06, -half.y + width.y),
			0.12, wood)
	# Flamme : pyramide.
	var tip := Vector3(0.0, FLAME_HEIGHT, 0.0)
	var base := [
		Vector3(-0.22, 0.15, -0.22), Vector3(0.22, 0.15, -0.22),
		Vector3(0.22, 0.15, 0.22), Vector3(-0.22, 0.15, 0.22),
	]
	var flame := Color("#e07a2f")
	var flame_light := Color("#f2b24a")
	for i in range(4):
		_tri(st, base[i], base[(i + 1) % 4], tip, flame_light if i % 2 == 0 else flame)
	st.generate_normals()
	return st.commit()

static func _box_flat(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		height: float, color: Color) -> void:
	var up := Vector3(0.0, height, 0.0)
	# Dessus.
	_quad(st, a + up, b + up, c + up, d + up, color)
	# Côtés.
	_quad(st, a, b, b + up, a + up, color.darkened(0.12))
	_quad(st, b, c, c + up, b + up, color.darkened(0.12))
	_quad(st, c, d, d + up, c + up, color.darkened(0.12))
	_quad(st, d, a, a + up, d + up, color.darkened(0.12))

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
