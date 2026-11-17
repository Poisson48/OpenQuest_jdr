extends RefCounted
class_name VisibilityPolygon

## Polygone de visibilité — géométrie pure, sans dépendance au rendu ni au jeu.
##
## Représentation : la zone visible depuis un point est **étoilée** (tout point
## visible est relié à l'observateur par un segment visible), donc on la décrit
## par une **fonction de rayon** r(θ) échantillonnée, puis on referme le polygone.
## Pour chaque angle on garde la distance du premier segment occultant rencontré
## (ou le rayon de vision).
##
## Échantillonnage : pas angulaire régulier (≈7,5° par défaut) **plus** l'angle
## exact de chaque extrémité de segment (± un petit epsilon) — c'est ce qui donne
## des coins nets et un bord de mur exact, sans payer un rayon par degré.
##
## Ce module sert au **rendu** (masque de brouillard lissé) et aux tests
## géométriques. Le calcul des cases révélées, lui, reste le test rayon-par-case
## de `MapVision` : plus rapide en GDScript pour nos tailles de carte (mesuré :
## 1,5 ms contre 13 ms pour 40 murs sur 32×32).
##
## Toutes les coordonnées sont en **unités grille** (comme `MapVision`).

## Pas angulaire par défaut (~7,5°).
const DEFAULT_ANGLE_STEP := TAU / 48.0

## Décalage angulaire de part et d'autre d'une extrémité de segment (coins).
const CORNER_EPSILON := 0.004

## Distance maximale d'un rayon si aucun rayon de vision n'est fourni.
const UNBOUNDED_DISTANCE := 100000.0

# ===========================================================================
# API
# ===========================================================================

## Polygone de visibilité depuis `origin`.
## `segments` : [{ "a": Vector2, "b": Vector2 }, …] (cf. `MapVision.wall_segments`).
## `radius` : portée de vision ; <= 0 → non borné (déconseillé en jeu).
## `angle_step` : pas angulaire de base en radians (plus petit = plus lisse).
static func compute(
	origin: Vector2,
	segments: Array,
	radius: float = 0.0,
	angle_step: float = DEFAULT_ANGLE_STEP
) -> PackedVector2Array:
	var max_distance := radius if radius > 0.0 else UNBOUNDED_DISTANCE
	var angles := _collect_angles(origin, segments, angle_step)
	if angles.is_empty():
		return PackedVector2Array()

	var polygon := PackedVector2Array()
	polygon.resize(angles.size())
	for i in angles.size():
		var direction := Vector2.from_angle(angles[i])
		var distance := _cast_ray(origin, direction, segments, max_distance)
		polygon[i] = origin + direction * distance
	return polygon

## Vrai si `point` est à l'intérieur du polygone (test de parité géométrique).
static func contains(polygon: PackedVector2Array, point: Vector2) -> bool:
	if polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, polygon)

## Vrai si le point est dans au moins un des polygones.
static func contains_any(polygons: Array, point: Vector2) -> bool:
	for polygon_variant in polygons:
		if contains(polygon_variant as PackedVector2Array, point):
			return true
	return false

## Boîte englobante d'un polygone (utile pour limiter les boucles de cases).
static func bounding_box(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var rect := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		rect = rect.expand(point)
	return rect

# ===========================================================================
# Interne
# ===========================================================================

## Angles à échantillonner : cercle régulier + extrémités de segments (±epsilon).
## Renvoie des angles triés dans [0, 2π).
static func _collect_angles(origin: Vector2, segments: Array, angle_step: float) -> Array[float]:
	var step := maxf(angle_step, 0.02)
	var count := maxi(8, int(ceil(TAU / step)))
	var raw: Array[float] = []
	for i in count:
		raw.append(TAU * float(i) / float(count))

	for segment_variant in segments:
		if not segment_variant is Dictionary:
			continue
		var segment: Dictionary = segment_variant
		var a: Vector2 = segment.get("a", Vector2.ZERO)
		var b: Vector2 = segment.get("b", Vector2.ZERO)
		for endpoint in [a, b]:
			var angle := fposmod((endpoint - origin).angle(), TAU)
			raw.append(angle - CORNER_EPSILON)
			raw.append(angle)
			raw.append(angle + CORNER_EPSILON)

	var normalized: Array[float] = []
	normalized.resize(raw.size())
	for i in raw.size():
		normalized[i] = fposmod(raw[i], TAU)
	normalized.sort()

	var unique: Array[float] = []
	for angle in normalized:
		if unique.is_empty() or angle - unique[unique.size() - 1] > 0.0001:
			unique.append(angle)

	# Fusion du tour complet : le premier et le dernier angle peuvent être les
	# deux côtés du même rayon (0 / 2π).
	if unique.size() > 1 and (TAU - unique[unique.size() - 1] + unique[0]) < 0.0001:
		unique.remove_at(unique.size() - 1)
	return unique

## Distance du premier segment rencontré le long de `direction` (ou `max_distance`).
static func _cast_ray(origin: Vector2, direction: Vector2, segments: Array, max_distance: float) -> float:
	var best := max_distance
	for segment_variant in segments:
		if not segment_variant is Dictionary:
			continue
		var segment: Dictionary = segment_variant
		var a: Vector2 = segment.get("a", Vector2.ZERO)
		var b: Vector2 = segment.get("b", Vector2.ZERO)
		var edge := b - a
		var denominator := direction.cross(edge)
		if absf(denominator) < 0.000000001:
			continue
		var to_a := a - origin
		var distance_along_ray := to_a.cross(edge) / denominator
		if distance_along_ray <= 0.000001 or distance_along_ray >= best:
			continue
		var segment_parameter := to_a.cross(direction) / denominator
		if segment_parameter < -0.000001 or segment_parameter > 1.000001:
			continue
		best = distance_along_ray
	return best
