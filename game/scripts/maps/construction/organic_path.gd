extends RefCounted
class_name OrganicPath

## Tracé organique « freehand » façon Tiny Glade.
##
## Pipeline pur (aucune dépendance à l'éditeur, testable headless) :
##   1. `smooth_points()` lisse les points souris avec une spline **Catmull-Rom**
##      (les extrémités sont dupliquées pour que la courbe passe par elles) ;
##   2. `resample()` ré-échantillonne la courbe à pas constant le long de l'arc,
##      en couvrant exactement le début et la fin ;
##   3. `build_chain()` transforme chaque tronçon en module orienté sur la
##      **tangente** (rotation = direction du tronçon), avec un léger
##      recouvrement aux jointures pour ne jamais laisser de trou dans les
##      virages (les modules se chevauchent de `overlap` à chaque extrémité).
##
## Le résultat est une liste de `{x, y, rotation, length, chord, direction,
## start, end}` à convertir en éléments mesh par l'éditeur.

const DEFAULT_SMOOTHING := 4
const DEFAULT_NOMINAL_LENGTH := 2.363
const DEFAULT_NOMINAL_DEPTH := 0.697
const MIN_CHORD := 0.05

## Lissage Catmull-Rom des points bruts. `subdivisions` = échantillons par
## segment (1 = polyligne brute, 4-6 = courbe douce).
static func smooth_points(points: Array, subdivisions: int = DEFAULT_SMOOTHING) -> Array:
	var count := points.size()
	if count < 2:
		return points.duplicate()
	var sub := clampi(subdivisions, 1, 16)
	var out: Array = []
	for i in range(count - 1):
		var p0: Vector2 = points[maxi(0, i - 1)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(count - 1, i + 2)]
		for k in range(sub):
			var t := float(k) / float(sub)
			out.append(_catmull_rom(p0, p1, p2, p3, t))
	out.append(points[count - 1])
	return out

## Longueur totale d'une polyligne.
static func total_length(points: Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += ((points[i] as Vector2) - (points[i - 1] as Vector2)).length()
	return total

## Ré-échantillonnage à pas constant. Couvre exactement le premier et le
## dernier point (le pas effectif vaut `longueur / nombre_de_pas`).
static func resample(points: Array, spacing: float) -> Array:
	var count := points.size()
	if count < 2:
		return points.duplicate()
	var step := maxf(0.05, spacing)
	var total := total_length(points)
	if total <= 0.001:
		return [points[0]]
	var pieces := maxi(1, int(round(total / step)))
	var exact := total / float(pieces)
	var out: Array = []
	for k in range(pieces):
		out.append(_point_at_distance(points, exact * float(k)))
	out.append(points[count - 1])
	return out

## Courbe lissée puis ré-échantillonnée (utile pour l'aperçu éditeur).
static func path_points(raw_points: Array, options: Dictionary = {}) -> Array:
	var smoothing := int(options.get("smoothing", DEFAULT_SMOOTHING))
	var spacing := float(options.get("spacing", 0.0))
	if spacing <= 0.0:
		spacing = maxf(0.4, float(options.get("nominal_length", DEFAULT_NOMINAL_LENGTH)))
	return resample(smooth_points(raw_points, smoothing), spacing)

## Construit les modules orientés tangente.
## Options : `smoothing`, `spacing` (0 = longueur nominale), `nominal_length`,
## `nominal_depth`, `overlap` (< 0 = automatique ≈ 40 % de l'épaisseur, max 0,3).
static func build_chain(raw_points: Array, options: Dictionary = {}) -> Array:
	var chain: Array = []
	if raw_points.size() < 2:
		return chain
	var sampled := path_points(raw_points, options)
	if sampled.size() < 2:
		return chain
	var overlap := float(options.get("overlap", -1.0))
	if overlap < 0.0:
		overlap = minf(0.3, maxf(0.06,
			float(options.get("nominal_depth", DEFAULT_NOMINAL_DEPTH)) * 0.4))
	for i in range(sampled.size() - 1):
		var a: Vector2 = sampled[i]
		var b: Vector2 = sampled[i + 1]
		var direction := b - a
		var chord := direction.length()
		if chord < MIN_CHORD:
			continue
		direction = direction.normalized()
		chain.append({
			"x": (a.x + b.x) * 0.5,
			"y": (a.y + b.y) * 0.5,
			"rotation": rad_to_deg(atan2(direction.y, direction.x)),
			"length": chord + overlap * 2.0,
			"chord": chord,
			"direction": direction,
			"start": a,
			"end": b,
		})
	return chain

## Extrémités monde `[a, b]` d'un module construit par `build_chain`.
static func module_endpoints(module: Dictionary) -> Array:
	var center := Vector2(float(module.get("x", 0.0)), float(module.get("y", 0.0)))
	var rad := deg_to_rad(float(module.get("rotation", 0.0)))
	var axis := Vector2(cos(rad), sin(rad))
	var half := float(module.get("length", 0.0)) * 0.5
	return [center - axis * half, center + axis * half]

## Point situé à `distance` le long de la polyligne (départ inclus).
static func _point_at_distance(points: Array, distance: float) -> Vector2:
	var remaining := maxf(0.0, distance)
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var segment := (b - a).length()
		if segment <= 0.0001:
			continue
		if remaining <= segment:
			return a.lerp(b, remaining / segment)
		remaining -= segment
	return points[points.size() - 1]

## Interpolation Catmull-Rom (p1 → p2, p0/p3 = voisins de contrôle).
static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
