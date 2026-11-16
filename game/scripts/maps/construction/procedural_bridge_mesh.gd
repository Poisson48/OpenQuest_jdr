extends RefCounted
class_name ProceduralBridgeMesh

## Pont procédural : tablier en lattes, garde-corps et piles, le tout dans une
## SEULE surface triangulaire (SurfaceTool.generate_normals + commit).
##
## params :
##   'start'   : Vector3 (x, hauteur_y, z) en unités monde — départ du tablier.
##   'end'     : Vector3 — arrivée du tablier.
##   'width'   : float — largeur monde du tablier.
##   'seed'    : int   — graine des variations de teinte des lattes.
##   'ground_y': float — hauteur monde du sol, où s'arrêtent les piles.
##
## Le tablier suit l'interpolation linéaire des hauteurs entre start.y et end.y.
## start == end (longueur nulle) renvoie un ArrayMesh vide, sans crash.

const DECK_THICKNESS := 0.09
const PLANK_SPACING := 0.19
const RAIL_POST_SPACING := 0.72
const RAIL_HEIGHT := 0.48
const RAIL_HALF_LAT := 0.055
const RAIL_HALF_VERT := 0.035
const POST_HALF := 0.05
const PILE_SPACING := 3.0
const PILE_HALF := 0.08
const PILE_BASE_HALF := 0.19
const PILE_BASE_HEIGHT := 0.14
const MIN_LENGTH := 0.0001
const ASSET := "procedural://bridge"
const CATALOG_ASSET := "res://assets/objects3d/props/pont.glb"

## Les extrémités sont sérialisées en coordonnées absolues de la grille.
static func move_entry(entry: Dictionary, gx: float, gy: float) -> void:
	if str(entry.get("asset", "")) == ASSET:
		var dx := gx - float(entry.get("x", 0.0))
		var dy := gy - float(entry.get("y", 0.0))
		for key in ["start", "end"]:
			if entry.get(key) is Dictionary:
				var point: Dictionary = entry[key].duplicate()
				point["x"] = float(point.get("x", 0.0)) + dx
				point["y"] = float(point.get("y", 0.0)) + dy
				entry[key] = point
	entry["x"] = gx
	entry["y"] = gy

# Palette du pont de référence, convertie en linéaire pour le maillage.
const COLOR_PLANK_DARK := Color("#7e5734")
const COLOR_PLANK_LIGHT := Color("#b38a55")
const COLOR_POST := Color("#87613c")
const COLOR_RAIL := Color("#a47b4c")
const COLOR_PILE := Color("#5d3d28")
const COLOR_BASE := Color("#8e897e")

static func build(params: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var start := _as_vector3(params.get("start", Vector3.ZERO))
	var end := _as_vector3(params.get("end", Vector3.ZERO))
	var width := float(params.get("width", 2.0))
	var ground_y := float(params.get("ground_y", 0.0))

	# Cas dégénéré : aucune longueur -> mesh vide, sans crash.
	var length := Vector2(end.x - start.x, end.z - start.z).length()
	if length < MIN_LENGTH or width <= 0.0:
		return mesh

	var dir := (end - start) / length
	# Direction horizontale du pont : les poteaux et piles restent verticaux
	# même quand le tablier est en pente.
	var h := _flat(dir)
	var side := Vector3(-h.z, 0.0, h.x)
	var half_width := width * 0.5

	var rng := RandomNumberGenerator.new()
	rng.seed = int(params.get("seed", 0))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_deck(st, start, dir, side, half_width, length, rng)
	_build_beams(st, start, end, side, half_width)
	_build_railings(st, start, dir, side, half_width, length)
	_build_piles(st, start, dir, side, half_width, length, ground_y, params.get("ground_height", Callable()))
	st.generate_normals()
	return st.commit()

# ===========================================================================
# Tablier

## Tablier : une latte (planche) tous les PLANK_SPACING, épaisseur constante,
## teinte légèrement variée par latte via la couleur de sommet (pas de texture).
static func _build_deck(st: SurfaceTool, start: Vector3, dir: Vector3, side: Vector3,
		half_width: float, length: float, rng: RandomNumberGenerator) -> void:
	var d := 0.0
	while d < length - MIN_LENGTH:
		var d_next := minf(d + PLANK_SPACING, length)
		var p0 := start + dir * d
		var p1 := start + dir * d_next
		var top := (p0 + p1) * 0.5
		var color := COLOR_PLANK_DARK.lerp(COLOR_PLANK_LIGHT, rng.randf())
		# o = centre de la face inférieure de la latte.
		var o := top - Vector3.UP * DECK_THICKNESS
		_box(st, o,
			dir * ((d_next - d) * 0.5),
			Vector3.UP * (DECK_THICKNESS * 0.5),
			side * half_width,
			color)
		d = d_next

static func _build_beams(st: SurfaceTool, start: Vector3, end: Vector3,
		side: Vector3, half_width: float) -> void:
	var middle := (start + end) * 0.5 - Vector3.UP * (DECK_THICKNESS + 0.10)
	for sign_value in [-1.0, 1.0]:
		_box(st, middle + side * (half_width * 0.64 * sign_value),
			(end - start) * 0.5, Vector3.UP * 0.065, side * 0.068, COLOR_PILE)

# ===========================================================================
# Garde-corps

## Deux rangées de poteaux (tous les RAIL_POST_SPACING, des deux côtés)
## surmontées d'une lisse supérieure à RAIL_HEIGHT au-dessus du tablier.
static func _build_railings(st: SurfaceTool, start: Vector3, dir: Vector3, side: Vector3,
		half_width: float, length: float) -> void:
	var h := _flat(dir)
	var stations := _stations(length, RAIL_POST_SPACING)
	for sgn in [-1.0, 1.0]:
		var lateral := side * (maxf(0.0, half_width - POST_HALF) * float(sgn))
		# Poteaux, du tablier jusqu'à la lisse.
		for d in stations:
			var p := start + dir * float(d) + lateral
			_box(st, p,
				h * POST_HALF,
				Vector3.UP * (RAIL_HEIGHT * 0.5),
				side * POST_HALF,
				COLOR_POST)
		# Lisse supérieure, par segments entre poteaux (suit la pente).
		for i in range(stations.size() - 1):
			var a := start + dir * float(stations[i]) + lateral + Vector3.UP * RAIL_HEIGHT
			var b := start + dir * float(stations[i + 1]) + lateral + Vector3.UP * RAIL_HEIGHT
			var o := (a + b) * 0.5 - Vector3.UP * RAIL_HALF_VERT
			_box(st, o,
				(b - a) * 0.5,
				Vector3.UP * RAIL_HALF_VERT,
				side * RAIL_HALF_LAT,
				COLOR_RAIL)

# ===========================================================================
# Piles

## Tous les PILE_SPACING le long du pont : deux poteaux verticaux de chaque
## côté du tablier, descendant jusqu'à ground_y, chacun sur une petite base
## élargie posée au sol.
static func _build_piles(st: SurfaceTool, start: Vector3, dir: Vector3, side: Vector3,
		half_width: float, length: float, ground_y: float, ground_height: Callable) -> void:
	var h := _flat(dir)
	var stations := _stations(length, PILE_SPACING)
	for d in stations:
		var p := start + dir * float(d)
		for sgn in [-1.0, 1.0]:
			var foot := p + side * (half_width * 0.64 * float(sgn))
			var base := float(ground_height.call(foot.x, foot.z)) if ground_height.is_valid() else ground_y
			var pile_height := p.y - DECK_THICKNESS - base
			if pile_height <= 0.02:
				continue
			var ground := Vector3(foot.x, base, foot.z)
			var stone_height := minf(pile_height, PILE_BASE_HEIGHT)
			_box(st, ground, h * PILE_BASE_HALF, Vector3.UP * (stone_height * 0.5),
				side * PILE_BASE_HALF, COLOR_BASE)
			if pile_height > stone_height + 0.01:
				_box(st, ground + Vector3.UP * stone_height, h * PILE_HALF,
					Vector3.UP * ((pile_height - stone_height) * 0.5), side * PILE_HALF, COLOR_PILE)

## Hauteur exacte du tablier au-dessus d'un point monde. -INF hors du pont.
static func deck_height_at(params: Dictionary, world: Vector2) -> float:
	var start: Vector3 = params["start"]
	var end: Vector3 = params["end"]
	var a := Vector2(start.x, start.z)
	var axis := Vector2(end.x, end.z) - a
	var length := axis.length()
	if length < MIN_LENGTH:
		return -INF
	var along := (world - a).dot(axis) / axis.length_squared()
	var lateral := absf((world - a).cross(axis)) / length
	if along < -0.0001 or along > 1.0001 or lateral > float(params["width"]) * 0.5:
		return -INF
	return lerpf(start.y, end.y, clampf(along, 0.0, 1.0))

static func raycast_deck(params: Dictionary, origin: Vector3, direction: Vector3) -> Vector3:
	var a: Vector3 = params["start"]
	var b: Vector3 = params["end"]
	var axis := b - a
	var side := Vector3(-axis.z, 0.0, axis.x)
	if side.length_squared() < MIN_LENGTH * MIN_LENGTH:
		return Vector3.INF
	var normal := side.cross(axis).normalized()
	var denom := normal.dot(direction)
	if absf(denom) < MIN_LENGTH:
		return Vector3.INF
	var distance := normal.dot(a - origin) / denom
	if distance < 0.0:
		return Vector3.INF
	var hit := origin + direction * distance
	return hit if deck_height_at(params, Vector2(hit.x, hit.z)) > -INF else Vector3.INF

# ===========================================================================
# Outils

## Projection horizontale normalisée de dir (vecteur de repli si le pont est
## strictement vertical).
static func _flat(dir: Vector3) -> Vector3:
	var h := Vector3(dir.x, 0.0, dir.z)
	if h.length_squared() < MIN_LENGTH * MIN_LENGTH:
		return Vector3(0.0, 0.0, 1.0)
	return h.normalized()

## Positions (distance depuis start) réparties tous les `spacing` le long du
## pont, en imposant les deux extrémités.
static func _stations(length: float, spacing: float) -> Array:
	var count := maxi(1, ceili(length / spacing))
	var out: Array = []
	for i in range(count + 1):
		out.append(length * float(i) / float(count))
	return out

## Boîte orientée : o = centre de la face inférieure, ax/ay/az = demi-axes
## (ax × ay doit pointer dans le sens de az pour un éclairage correct).
static func _box(st: SurfaceTool, o: Vector3, ax: Vector3, ay: Vector3, az: Vector3,
		color: Color) -> void:
	var b0 := o - ax - az
	var b1 := o + ax - az
	var b2 := o + ax + az
	var b3 := o - ax + az
	var up := ay + ay
	var t0 := b0 + up
	var t1 := b1 + up
	var t2 := b2 + up
	var t3 := b3 + up
	_quad(st, t3, t2, t1, t0, color)  # dessus
	_quad(st, b0, b1, b2, b3, color.darkened(0.32))  # dessous
	_quad(st, b3, b2, t2, t3, color.darkened(0.16))  # côté az+
	_quad(st, b1, b0, t0, t1, color.darkened(0.16))  # côté az-
	_quad(st, b2, b1, t1, t2, color.darkened(0.09))  # côté ax+
	_quad(st, b0, b3, t3, t0, color.darkened(0.09))  # côté ax-

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	_tri(st, a, b, c, color)
	_tri(st, a, c, d, color)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color.srgb_to_linear())
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _as_vector3(value) -> Vector3:
	if value is Vector3:
		return value
	if value is Vector3i:
		return Vector3(value)
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)),
			float(value.get("z", 0.0)))
	return Vector3.ZERO
