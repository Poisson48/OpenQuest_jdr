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

const DECK_THICKNESS := 0.18
const PLANK_SPACING := 0.4
const RAIL_POST_SPACING := 1.5
const RAIL_HEIGHT := 0.9
const RAIL_HALF_LAT := 0.055
const RAIL_HALF_VERT := 0.07
const POST_HALF := 0.05
const PILE_SPACING := 3.0
const PILE_PAIR_OFFSET := 0.22
const PILE_HALF := 0.08
const PILE_BASE_HALF := 0.19
const PILE_BASE_HEIGHT := 0.14
const MIN_LENGTH := 0.0001

# Teintes de bois (valeurs RGB linéaires approx. des hex indiqués).
const COLOR_PLANK_DARK := Color(0.427, 0.294, 0.196)   # ~ #6d4b32
const COLOR_PLANK_LIGHT := Color(0.639, 0.482, 0.322)  # ~ #a37b52
const COLOR_POST := Color(0.365, 0.247, 0.165)         # ~ #5d3f2a
const COLOR_RAIL := Color(0.541, 0.384, 0.259)         # ~ #8a6242
const COLOR_PILE := Color(0.290, 0.196, 0.133)         # ~ #4a3222
const COLOR_BASE := Color(0.494, 0.471, 0.427)         # ~ #7e786d

static func build(params: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var start := _as_vector3(params.get("start", Vector3.ZERO))
	var end := _as_vector3(params.get("end", Vector3.ZERO))
	var width := float(params.get("width", 2.0))
	var ground_y := float(params.get("ground_y", 0.0))

	# Cas dégénéré : aucune longueur -> mesh vide, sans crash.
	var length := start.distance_to(end)
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
	_build_railings(st, start, dir, side, half_width, length)
	_build_piles(st, start, dir, side, half_width, length, ground_y)
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

# ===========================================================================
# Garde-corps

## Deux rangées de poteaux (tous les RAIL_POST_SPACING, des deux côtés)
## surmontées d'une lisse supérieure à RAIL_HEIGHT au-dessus du tablier.
static func _build_railings(st: SurfaceTool, start: Vector3, dir: Vector3, side: Vector3,
		half_width: float, length: float) -> void:
	var h := _flat(dir)
	var stations := _stations(length, RAIL_POST_SPACING)
	for sgn in [-1.0, 1.0]:
		var lateral := side * (half_width * float(sgn))
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
		half_width: float, length: float, ground_y: float) -> void:
	var h := _flat(dir)
	var stations := _stations(length, PILE_SPACING)
	for d in stations:
		var p := start + dir * float(d)
		var pile_height := (p.y - DECK_THICKNESS) - ground_y
		if pile_height <= PILE_BASE_HEIGHT:
			# Le tablier est trop près du sol : pas de pile ici.
			continue
		for sgn in [-1.0, 1.0]:
			var lateral := side * (half_width * float(sgn))
			for offset in [-PILE_PAIR_OFFSET, PILE_PAIR_OFFSET]:
				var foot := p + lateral + h * float(offset)
				var ground := Vector3(foot.x, ground_y, foot.z)
				# Petite base élargie au sol.
				_box(st, ground,
					h * PILE_BASE_HALF,
					Vector3.UP * (PILE_BASE_HEIGHT * 0.5),
					side * PILE_BASE_HALF,
					COLOR_BASE)
				# Poteau jusqu'à la sous-face du tablier.
				_box(st, ground + Vector3.UP * PILE_BASE_HEIGHT,
					h * PILE_HALF,
					Vector3.UP * ((pile_height - PILE_BASE_HEIGHT) * 0.5),
					side * PILE_HALF,
					COLOR_PILE)

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
	var out: Array = [0.0]
	var d := spacing
	while d < length - MIN_LENGTH:
		out.append(d)
		d += spacing
	out.append(length)
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
	_quad(st, b0, b1, b2, b3, color)  # dessous
	_quad(st, b3, b2, t2, t3, color)  # côté az+
	_quad(st, b1, b0, t0, t1, color)  # côté az-
	_quad(st, b2, b1, t1, t2, color)  # côté ax+
	_quad(st, b0, b3, t3, t0, color)  # côté ax-

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
