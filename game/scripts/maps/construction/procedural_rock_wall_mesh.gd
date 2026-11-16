extends RefCounted
class_name ProceduralRockWallMesh

## Mur de pierres sèches entièrement procédural (ArrayMesh, 1 surface).
##
## Contrairement à un empilement de GLB, les pierres sont **taillées pour être
## posées** : chaque assise est divisée en blocs de largeur variable, avec un
## joint sombre entre eux, un léger débord en profondeur et une base stable.
## Les couleurs sont cuites dans les vertex (mode `UNSHADED` de la carte 2.5D) :
## dessus éclairé, faces avant dans la teinte de pierre, bas assombri (AO), fond
## de joint presque noir. Le résultat se lit comme de la maçonnerie sèche et non
## comme des cailloux posés côte à côte.
##
## Repère : points en cases (plan x/z), y = hauteur. L'appelant applique
## l'échelle de cellule, comme `ProceduralWallMesh`.

const MIN_HEIGHT := 0.35
const DEFAULT_HEIGHT := 1.05
const DEFAULT_THICKNESS := 0.72
## Épaisseur visée d'une assise (cases).
const COURSE_HEIGHT := 0.26
const MIN_STONE_LENGTH := 0.22
const JOINT := 0.035
## Teintes en espace LINÉAIRE (le mode UNSHADED applique la couleur telle quelle).
## Pierre chaude du village (#8c887d en sRGB ≈ 0.26 linéaire) : sans ça le mur
## ressort blanc/gris froid au milieu des toits et des enduits chauds.
const STONE_COLOR := Color(0.27, 0.255, 0.222)
const JOINT_COLOR := Color(0.045, 0.042, 0.036)


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
		int(elem.get("seed", 1))
	)


static func build(points: Array, height: float = DEFAULT_HEIGHT,
		thickness: float = DEFAULT_THICKNESS, seed: int = 1) -> ArrayMesh:
	var pts: Array = []
	for p in points:
		var v := _as_vector2(p)
		if v != Vector2.INF:
			pts.append(v)
	var mesh := ArrayMesh.new()
	if pts.size() < 2:
		return mesh
	height = maxf(MIN_HEIGHT, height)
	thickness = maxf(0.2, thickness)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Fond de joint : un volume sombre un peu en retrait, sur toute la hauteur.
	_build_wall_volume(st, pts, 0.0, height, thickness * 0.34, JOINT_COLOR, JOINT_COLOR, JOINT_COLOR)

	# Assises : le nombre d'assises découle de la hauteur demandée.
	var courses := maxi(2, int(round(height / COURSE_HEIGHT)))
	var actual_course := height / float(courses)
	for course in range(courses):
		var y0 := float(course) * actual_course
		var y1 := y0 + actual_course
		# Décalage d'un demi-joint sur les assises impaires : la maçonnerie
		# n'a jamais de joint continu sur toute la hauteur.
		var stagger := 0.5 if course % 2 == 1 else 0.0
		_build_course(st, pts, y0, y1, thickness, stagger, rng, course)
	return st.commit()


## Une assise : des pierres de longueur variable le long du mur.
static func _build_course(st: SurfaceTool, pts: Array, y0: float, y1: float,
		thickness: float, stagger: float, rng: RandomNumberGenerator, course: int) -> void:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	if total < MIN_STONE_LENGTH:
		return
	var cursor := 0.0
	var index := 0
	while cursor < total - 0.02:
		var length := rng.randf_range(0.26, 0.52)
		# Le joint décalé est simulé en décalant le départ des pierres.
		var start := cursor
		if index == 0 and stagger > 0.0:
			start = maxf(0.0, start - length * stagger)
		var end := minf(total, start + length)
		if end - start < MIN_STONE_LENGTH * 0.7:
			break
		_place_stone(st, pts, start, end, y0, y1, thickness, rng, course, index)
		cursor = end + JOINT
		index += 1


## Pose une pierre entre les distances `start` et `end` le long de la polyligne.
static func _place_stone(st: SurfaceTool, pts: Array, start: float, end: float,
		y0: float, y1: float, thickness: float, rng: RandomNumberGenerator,
		course: int, index: int) -> void:
	var front := _point_at_distance(pts, start)
	var back := _point_at_distance(pts, end)
	if front == Vector2.INF or back == Vector2.INF:
		return
	var axis := (back - front)
	var length := axis.length()
	if length < 0.02:
		return
	axis = axis / length
	var normal := Vector2(-axis.y, axis.x)
	# Débord léger et irrégulier : la face avant n'est pas un plan parfait.
	var bulge := thickness * 0.5 + rng.randf_range(0.0, 0.035)
	var top := y1 - rng.randf_range(0.0, 0.022)
	var bottom := y0 + rng.randf_range(0.0, 0.012)
	if top - bottom < 0.05:
		return
	var corners: Array[Vector3] = []
	var inset := rng.randf_range(0.008, 0.02)
	var half := length * 0.5
	var mid := (front + back) * 0.5
	for sign_side in [-1.0, 1.0]:
		for sign_along in [-1.0, 1.0]:
			var p: Vector2 = mid + axis * (half * sign_along) + normal * (bulge * sign_side)
			corners.append(Vector3(p.x, 0.0, p.y))
	# Sommets : 8 coins (4 bas, 4 hauts) ; le dessus est très légèrement rentré.
	var bottom_slab: Array[Vector3] = []
	var top_slab: Array[Vector3] = []
	for corner in corners:
		bottom_slab.append(Vector3(corner.x, bottom, corner.z))
		var toward_mid := (mid - Vector2(corner.x, corner.z))
		if toward_mid.length() > 0.001:
			toward_mid = toward_mid.normalized() * inset
		top_slab.append(Vector3(corner.x + toward_mid.x, top, corner.z + toward_mid.y))
	# Teintes : haut éclairé, faces de la teinte de pierre, bas sombre (AO).
	var top_color := STONE_COLOR.lightened(0.10 + rng.randf_range(0.0, 0.04))
	var side_color := STONE_COLOR.darkened(0.05 + rng.randf_range(0.0, 0.05))
	var low_color := STONE_COLOR.darkened(0.28)
	# Quatre faces latérales + dessus (le dessous ne se voit jamais).
	for i in range(4):
		var j := (i + 1) % 4
		_quad(st,
			bottom_slab[i], bottom_slab[j], top_slab[j], top_slab[i],
			low_color, low_color, side_color, side_color)
	_quad(st, top_slab[0], top_slab[1], top_slab[2], top_slab[3],
		top_color, top_color, top_color, top_color)


## Volume sombre continu (fond de joint) : évite les trous entre les pierres.
static func _build_wall_volume(st: SurfaceTool, pts: Array, y0: float, y1: float,
		half_thickness: float, bottom_color: Color, side_color: Color,
		top_color: Color) -> void:
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var axis: Vector2 = b - a
		if axis.length() < 0.001:
			continue
		axis = axis.normalized()
		var normal := Vector2(-axis.y, axis.x) * half_thickness
		var a0 := Vector3(a.x + normal.x, y0, a.y + normal.y)
		var a1 := Vector3(a.x - normal.x, y0, a.y - normal.y)
		var b0 := Vector3(b.x + normal.x, y0, b.y + normal.y)
		var b1 := Vector3(b.x - normal.x, y0, b.y - normal.y)
		var a0t := Vector3(a0.x, y1, a0.z)
		var a1t := Vector3(a1.x, y1, a1.z)
		var b0t := Vector3(b0.x, y1, b0.z)
		var b1t := Vector3(b1.x, y1, b1.z)
		_quad(st, a0, b0, b0t, a0t, bottom_color, bottom_color, side_color, side_color)
		_quad(st, a1t, b1t, b1, a1, side_color, side_color, bottom_color, bottom_color)
		_quad(st, a0t, b0t, b1t, a1t, top_color, top_color, top_color, top_color)


static func _point_at_distance(pts: Array, distance: float) -> Vector2:
	if distance <= 0.0:
		return pts[0]
	var travelled := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var segment := a.distance_to(b)
		if travelled + segment >= distance:
			var t := (distance - travelled) / maxf(segment, 0.0001)
			return a.lerp(b, t)
		travelled += segment
	return pts[pts.size() - 1]


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(cd)
	st.add_vertex(d)


static func _as_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.INF
