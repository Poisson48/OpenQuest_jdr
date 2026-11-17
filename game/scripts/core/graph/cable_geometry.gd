extends RefCounted
class_name CableGeometry

## Géométrie PURE des câbles du graphe de scénarios.
##
## Extraite de `scenario_editor/panels/graph_link_overlay.gd` : tout ce qui ne
## dépend ni d'un `Node`/`Control`, ni d'une grille de routage, ni d'un état
## mutable. Uniquement des `PackedVector2Array` et des `Rect2` en entrée/sortie,
## ce qui la rend testable en headless.
##
## Rôles : arrondi des coudes (look « câble »), courbes de Bézier du repli,
## détours orthogonaux, mesure des points qui traversent une carte.

## Rayon d'arrondi des coudes (px écran) : look « câble ».
const CORNER_RADIUS := 10.0


## Retire les points consécutifs confondus (tolérance 0,5 px).
static func dedupe_points(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pt in points:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(pt) > 0.25:
			out.append(pt)
	return out


## Ajoute un point s'il n'est pas déjà le dernier (tolérance 0,5 px).
## Les `PackedVector2Array` sont passés par référence : l'appelant est muté.
static func append_unique(points: PackedVector2Array, pt: Vector2) -> void:
	if points.is_empty() or points[points.size() - 1].distance_squared_to(pt) > 0.25:
		points.append(pt)


## Arrondit les angles d'une polyligne (quadratiques) : look « câble » propre.
static func round_polyline(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array()
	out.append(points[0])
	for i in range(1, points.size() - 1):
		var prev := points[i - 1]
		var cur := points[i]
		var next := points[i + 1]
		var v1 := cur - prev
		var v2 := next - cur
		var l1 := v1.length()
		var l2 := v2.length()
		if l1 < 0.001 or l2 < 0.001:
			append_unique(out, cur)
			continue
		var r := minf(radius, minf(l1, l2) * 0.45)
		var a := cur - (v1 / l1) * r
		var b := cur + (v2 / l2) * r
		append_unique(out, a)
		var steps := 4
		for s in range(1, steps):
			var t := float(s) / float(steps)
			var u := 1.0 - t
			append_unique(out, a * (u * u) + cur * (2.0 * u * t) + b * (t * t))
		append_unique(out, b)
	append_unique(out, points[points.size() - 1])
	return out


## Retire les points alignés puis arrondit tous les coudes : look « câble ».
## `zoom` est le zoom du graphe (l'arrondi ne doit pas devenir énorme en zoom
## arrière ni invisible en zoom avant).
static func smooth_cable(raw: PackedVector2Array, zoom: float) -> PackedVector2Array:
	var points := dedupe_points(raw)
	if points.size() < 3:
		return points
	var cleaned := PackedVector2Array()
	cleaned.append(points[0])
	for i in range(1, points.size() - 1):
		var prev := cleaned[cleaned.size() - 1]
		var cur := points[i]
		var next := points[i + 1]
		var v1 := cur - prev
		var v2 := next - cur
		if v1.length_squared() < 0.25 or v2.length_squared() < 0.25:
			continue
		if absf(v1.normalized().dot(v2.normalized())) > 0.9998:
			continue
		cleaned.append(cur)
	cleaned.append(points[points.size() - 1])
	var radius := clampf(CORNER_RADIUS * clampf(zoom, 0.55, 1.35), 6.0, 14.0)
	return round_polyline(cleaned, radius)


## Milieu de la polyligne, mesuré en longueur d'arc (et non en nombre de points).
static func polyline_midpoint(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var target := total * 0.5
	var walked := 0.0
	for i in range(1, points.size()):
		var seg := points[i - 1].distance_to(points[i])
		if walked + seg >= target and seg > 0.001:
			var t := (target - walked) / seg
			return points[i - 1].lerp(points[i], t)
		walked += seg
	return points[points.size() - 1]


## Points d'une courbe de Bézier cubique horizontale (repli sans routage).
## `bow` décale verticalement les deux points de contrôle.
static func curve_points(start: Vector2, end: Vector2, bow: float) -> PackedVector2Array:
	var dx := end.x - start.x
	var control := maxf(56.0, absf(dx) * 0.55)
	var c1 := Vector2(start.x + control, start.y + bow)
	var c2 := Vector2(end.x - control, end.y + bow)
	var steps := 20
	var out := PackedVector2Array()
	for i in range(1, steps):
		var t := float(i) / float(steps)
		out.append(bezier_point(start, c1, c2, end, t))
	return out


static func bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Assemble port → stub → courbe → stub → port, sans doublons.
static func assemble_edge(out_port: Vector2, out_mid: Vector2, start_port: Vector2,
		curve: PackedVector2Array, end_port: Vector2, in_mid: Vector2,
		in_port: Vector2) -> PackedVector2Array:
	var full := PackedVector2Array()
	full.append(out_port)
	full.append(out_mid)
	full.append(start_port)
	for pt in curve:
		full.append(pt)
	full.append(end_port)
	full.append(in_mid)
	full.append(in_port)
	return dedupe_points(full)


## Cartes traversées par une courbe (hors scènes source/cible).
static func offending_rects(points_before: Array, curve: PackedVector2Array, points_after: Array,
		rects: Array, from_idx: int, to_idx: int) -> Array:
	var full := PackedVector2Array()
	for pt in points_before:
		full.append(pt)
	for pt in curve:
		full.append(pt)
	for pt in points_after:
		full.append(pt)
	var result: Array = []
	for i in range(0, full.size(), 2):
		var pt := full[i]
		for r in range(rects.size()):
			if r == from_idx or r == to_idx or result.has(r):
				continue
			if (rects[r] as Rect2).grow(3.0).has_point(pt):
				result.append(r)
	return result


## Nombre de points du tracé situés dans une AUTRE carte (rect gonflé de 3 px).
static func count_node_hits(points: PackedVector2Array, rects: Array, from_idx: int, to_idx: int) -> int:
	var hits := 0
	for i in range(points.size()):
		var pt := points[i]
		for r in range(rects.size()):
			if r == from_idx or r == to_idx:
				continue
			var rect := (rects[r] as Rect2).grow(3.0)
			if rect.has_point(pt):
				hits += 1
				break
	return hits


## Voies horizontales libres candidates, triées par proximité du tracé direct.
static func detour_lanes(offenders: Array, rects: Array, start_port: Vector2, end_port: Vector2) -> Array:
	var lanes: Array = []
	for r in offenders:
		var rect: Rect2 = rects[r]
		lanes.append(rect.position.y - 18.0)
		lanes.append(rect.position.y + rect.size.y + 18.0)
	var top := 1e9
	var bottom := -1e9
	for r in range(rects.size()):
		var rect: Rect2 = rects[r]
		top = minf(top, rect.position.y)
		bottom = maxf(bottom, rect.position.y + rect.size.y)
	lanes.append(top - 26.0)
	lanes.append(bottom + 26.0)
	var unique: Array = []
	for lane in lanes:
		var exists := false
		for other in unique:
			if absf(float(lane) - float(other)) < 4.0:
				exists = true
				break
		if not exists:
			unique.append(lane)
	var mid_y := (start_port.y + end_port.y) * 0.5
	unique.sort_custom(func(a: float, b: float) -> bool: return absf(a - mid_y) < absf(b - mid_y))
	return unique


## Détour orthogonal arrondi passant par la voie `lane_y`.
static func detour_path(out_port: Vector2, out_mid: Vector2, start_port: Vector2,
		end_port: Vector2, in_mid: Vector2, in_port: Vector2,
		lane_y: float) -> PackedVector2Array:
	var raw := PackedVector2Array()
	raw.append(out_port)
	raw.append(out_mid)
	raw.append(start_port)
	var overshoot := 16.0
	raw.append(Vector2(start_port.x + overshoot, lane_y))
	raw.append(Vector2(end_port.x - overshoot, lane_y))
	raw.append(end_port)
	raw.append(in_mid)
	raw.append(in_port)
	return round_polyline(dedupe_points(raw), 10.0)
