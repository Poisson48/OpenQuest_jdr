extends RefCounted
class_name ProceduralPathMesh

## Chemin organique : ruban continu le long d'une courbe, avec largeur variable,
## bords irréguliers, biseau et subdivisions adaptatives.
##
## `detail` est fourni par MapMeshes3D selon la rugosité du terrain sous le
## chemin : 1 sur du plat (peu de triangles), 3–4 sur une pente ou un creux.

const DEFAULT_WIDTH := 1.2
const MIN_WIDTH := 0.3
const THICKNESS := 0.045
const EDGE_VARIATION := 0.11

static func build_from_element(elem: Dictionary, detail: int = 1) -> ArrayMesh:
	var points: Array = []
	for p in elem.get("points", []):
		var v := _as_vector2(p)
		if v != Vector2.INF:
			points.append(v)
	return build(
		points,
		float(elem.get("width", DEFAULT_WIDTH)),
		Color.html(str(elem.get("color", "#8a7654"))),
		detail,
		int(elem.get("seed", 1))
	)

static func build(points: Array, width: float = DEFAULT_WIDTH,
		color: Color = Color("#8a7654"), detail: int = 1, seed: int = 1) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if points.size() < 2:
		return mesh
	var w := maxf(MIN_WIDTH, width)
	var subdiv := clampi(detail, 1, 5)
	var samples: Array[Vector2] = []
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		for k in range(subdiv):
			samples.append(a.lerp(b, float(k) / float(subdiv)))
	samples.append(points[points.size() - 1])
	if samples.size() < 2:
		return mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	for i in range(samples.size()):
		var dir := _dir_at(samples, i)
		var normal := Vector2(-dir.y, dir.x)
		# Largeur gauche/droite indépendantes : le bord n'est jamais une copie
		# exacte du centre ni du bord opposé.
		var t := float(i) / float(maxi(1, samples.size() - 1))
		var wobble_l := 1.0 + EDGE_VARIATION * sin(t * 18.0 + float(seed) * 0.7)
		var wobble_r := 1.0 + EDGE_VARIATION * sin(t * 23.0 + 1.9 + float(seed) * 0.5)
		left.append(samples[i] + normal * (w * 0.5) * wobble_l)
		right.append(samples[i] - normal * (w * 0.5) * wobble_r)
	var top := THICKNESS
	var edge := color.darkened(0.24)
	var center_color := color.lightened(0.035)
	for i in range(samples.size() - 1):
		var j := i + 1
		var c_mid := center_color.lerp(edge, 0.18 if i % 3 == 0 else 0.07)
		_quad(st, Vector3(left[i].x, top, left[i].y), Vector3(left[j].x, top, left[j].y),
			Vector3(right[j].x, top, right[j].y), Vector3(right[i].x, top, right[i].y), c_mid)
		# Chants légèrement sous le terrain : donne l'impression d'un chemin tassé.
		_quad(st, Vector3(left[i].x, -0.04, left[i].y), Vector3(left[j].x, -0.04, left[j].y),
			Vector3(left[j].x, top, left[j].y), Vector3(left[i].x, top, left[i].y), edge)
		_quad(st, Vector3(right[j].x, -0.04, right[j].y), Vector3(right[i].x, -0.04, right[i].y),
			Vector3(right[i].x, top, right[i].y), Vector3(right[j].x, top, right[j].y), edge)
	# Embouts.
	_quad(st, Vector3(left[0].x, -0.04, left[0].y), Vector3(right[0].x, -0.04, right[0].y),
		Vector3(right[0].x, top, right[0].y), Vector3(left[0].x, top, left[0].y), edge)
	var last := samples.size() - 1
	_quad(st, Vector3(right[last].x, -0.04, right[last].y), Vector3(left[last].x, -0.04, left[last].y),
		Vector3(left[last].x, top, left[last].y), Vector3(right[last].x, top, right[last].y), edge)
	st.generate_normals()
	return st.commit()

static func _dir_at(points: Array, index: int) -> Vector2:
	var a: Vector2
	var b: Vector2
	if index <= 0:
		a = points[0]
		b = points[1]
	elif index >= points.size() - 1:
		a = points[points.size() - 2]
		b = points[points.size() - 1]
	else:
		a = points[index - 1]
		b = points[index + 1]
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT

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
