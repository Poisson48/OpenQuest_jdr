extends RefCounted
class_name LinkRouter

## Routeur de liens du graphe de scénarios — logique PURE, sans `Node`, `Control`
## ni `GraphEdit`.
##
## Extrait de `scenario_editor/panels/graph_link_overlay.gd` : l'overlay lui passe
## des rectangles de cartes et des points de ports, le routeur rend des polylignes
## (coordonnées overlay). Tout l'état de routage (grille, `AStarGrid2D`, cellules
## libérées, compteurs de perf) vit dans l'instance : une instance par overlay,
## aucun statique global.
##
## Comportement identique à l'ancien code de l'overlay (mêmes constantes de coût,
## même ordre de marquage, mêmes replis) : c'est une extraction, pas une refonte.
##
## Utilisation :
##   var router := LinkRouter.new()
##   router.reset_perf()
##   router.build_grid(rects, starts, ends, zoom)   # false = routage désactivé
##   var points := router.route_edge(edge)          # vide = repli à faire
##   router.route_fallback(...)                     # tracé de secours Bézier/détours

const CableGeometryScript := preload("res://scripts/core/graph/cable_geometry.gd")

## Marge STRICTE : aucun point du câble ne descend sous cette distance (écran)
## aux cartes. Au-delà de 2 px (exigence des tests) on garde une bonne marge de
## sécurité pour les arrondis de coudes.
const CARD_HARD_MARGIN := 5.0
## Marge de confort : entrer dans cette bande coûte cher au routage ; les câbles
## la longent sans la pénétrer tant qu'un détour raisonnable existe.
const CARD_SOFT_MARGIN := 13.0
## Zone de port exclue des contrôles de collision (le câble doit sortir de la
## carte par son port, il longe donc forcément son bord).
const PORT_ZONE := 24.0

## Grille de routage : cellule adaptée au zoom (px overlay).
const ROUTE_CELL_MIN := 4.0
const ROUTE_CELL_MAX := 12.0
const ROUTE_MAX_CELLS := 16000
## Au-delà de ces seuils, le graphe est jugé trop gros : repli sur l'ancien
## tracé (le rebuild doit rester fluide pendant le drag).
const ROUTE_MAX_NODES := 70
const ROUTE_MAX_EDGES := 240
## Coûts du routage (par cellule) : confort, anti-empilement.
const SOFT_CELL_COST := 4.0
const OCCUPANCY_CELL_COST := 22.0
## Coude « inexistant » renvoyé par `_ortho_link`.
const _NO_ELBOW := Vector2(-1e30, -1e30)

## État de la grille de navigation (0 = aucune grille construite).
var enabled: bool = false
var cell: float = 8.0
var origin: Vector2 = Vector2.ZERO
var width: int = 0
var height: int = 0

# Compteurs de perf du dernier rebuild (relus par l'overlay pour son rapport).
var perf_grid_us: int = 0
var perf_route_us: int = 0
var perf_hits_us: int = 0
var perf_simplify_us: int = 0
var perf_astar_runs: int = 0
var perf_astar_expansions: int = 0
var perf_astar_fail: int = 0
var perf_astar_on_occupied: int = 0
var perf_direct: int = 0

var _blocked: PackedByteArray = PackedByteArray()
var _soft: PackedByteArray = PackedByteArray()
var _occupancy: PackedFloat32Array = PackedFloat32Array()
var _base_weight: PackedFloat32Array = PackedFloat32Array()
var _astar: AStarGrid2D = null
var _freed: PackedInt32Array = PackedInt32Array()
## Zoom du graphe au moment de la construction de la grille (arrondi des coudes).
var _zoom: float = 1.0


## Remet les compteurs de perf à zéro (appelé au début de chaque rebuild).
func reset_perf() -> void:
	perf_grid_us = 0
	perf_route_us = 0
	perf_hits_us = 0
	perf_simplify_us = 0
	perf_astar_runs = 0
	perf_astar_expansions = 0
	perf_astar_fail = 0
	perf_astar_on_occupied = 0
	perf_direct = 0


## Taille de la grille courante (`Vector2i(width, height)`).
func grid_size() -> Vector2i:
	return Vector2i(width, height)


## Construit la grille de navigation à partir des rectangles des cartes.
## Renvoie false si le routage est désactivé (graphe trop gros) : dans ce cas
## l'appelant retombe sur l'ancien tracé.
func build_grid(rects: Array, starts: Array, ends: Array, zoom: float) -> bool:
	enabled = false
	_zoom = zoom
	if rects.size() > ROUTE_MAX_NODES or starts.size() > ROUTE_MAX_EDGES:
		return false
	var c := clampf(10.0 * zoom, ROUTE_CELL_MIN, 11.0)
	var lo := Vector2(1e30, 1e30)
	var hi := Vector2(-1e30, -1e30)
	for r in rects:
		var rect: Rect2 = r
		lo = lo.min(rect.position)
		hi = hi.max(rect.position + rect.size)
	for p in starts:
		lo = lo.min(p)
		hi = hi.max(p)
	for p in ends:
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := CARD_SOFT_MARGIN + 10.0 * c
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)
	var area := maxf(hi.x - lo.x, 1.0) * maxf(hi.y - lo.y, 1.0)
	# Grossit la cellule tant que la grille dépasse le plafond : mieux vaut un
	# routage plus grossier qu'un rebuild qui bloque l'interface.
	var cells_est := area / (c * c)
	while cells_est > float(ROUTE_MAX_CELLS):
		c *= 1.15
		if c > ROUTE_CELL_MAX:
			return false
		cells_est = area / (c * c)
	cell = c
	origin = lo
	width = int(ceilf((hi.x - lo.x) / c)) + 1
	height = int(ceilf((hi.y - lo.y) / c)) + 1
	if width < 2 or height < 2 or width * height > ROUTE_MAX_CELLS * 2:
		return false
	var total := width * height
	_blocked.resize(total)
	_soft.resize(total)
	_occupancy.resize(total)
	_base_weight.resize(total)
	_blocked.fill(0)
	_soft.fill(0)
	_occupancy.fill(0.0)
	_base_weight.fill(1.0)
	# AStarGrid2D : A* natif (C++), bien plus rapide qu'une implémentation
	# GDScript pour une grille de quelques milliers de cellules.
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(cell, cell)
	_astar.offset = origin + Vector2(cell * 0.5, cell * 0.5)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()
	# Blocage strict (les cellules libres sont entièrement hors de la marge
	# stricte) puis bande de confort (fortement déconseillée, pas interdite).
	for r in rects:
		var rect: Rect2 = r
		_mark_grid_rect(rect.grow(CARD_HARD_MARGIN), 1)
		_mark_grid_rect(rect.grow(CARD_SOFT_MARGIN), 2)
	enabled = true
	return true


## Marque les cellules dont le centre tombe dans `rect` (mode 1 = bloquée,
## mode 2 = marge de confort, sans écraser un blocage strict).
func _mark_grid_rect(rect: Rect2, mode: int) -> void:
	var x0 := int(floorf((rect.position.x - origin.x) / cell))
	var y0 := int(floorf((rect.position.y - origin.y) / cell))
	var x1 := int(ceilf((rect.position.x + rect.size.x - origin.x) / cell))
	var y1 := int(ceilf((rect.position.y + rect.size.y - origin.y) / cell))
	x0 = clampi(x0, 0, width - 1)
	y0 = clampi(y0, 0, height - 1)
	x1 = clampi(x1, 0, width - 1)
	y1 = clampi(y1, 0, height - 1)
	for y in range(y0, y1 + 1):
		var row := y * width
		var cy := origin.y + (float(y) + 0.5) * cell
		for x in range(x0, x1 + 1):
			var idx := row + x
			if mode == 1:
				if rect.has_point(Vector2(origin.x + (float(x) + 0.5) * cell, cy)):
					_blocked[idx] = 1
					if _astar != null:
						_astar.set_point_solid(Vector2i(x, y), true)
			elif _blocked[idx] == 0 and rect.has_point(
					Vector2(origin.x + (float(x) + 0.5) * cell, cy)):
				_soft[idx] = 1
				_base_weight[idx] = 1.0 + SOFT_CELL_COST
				if _astar != null:
					_astar.set_point_weight_scale(Vector2i(x, y), _base_weight[idx])


## Index de cellule (y * width + x) d'un point, borné à la grille.
func _point_to_cell(point: Vector2) -> int:
	var x := int(floorf((point.x - origin.x) / cell))
	var y := int(floorf((point.y - origin.y) / cell))
	x = clampi(x, 0, width - 1)
	y = clampi(y, 0, height - 1)
	return y * width + x


## Route un lien par A* : renvoie le tracé complet (port → peigne → tracé
## orthogonal → peigne → port) ou un tableau vide si le routage échoue (→ repli).
func route_edge(edge: Dictionary) -> PackedVector2Array:
	if not enabled:
		return PackedVector2Array()
	var start: Vector2 = edge["start"]
	var end: Vector2 = edge["end"]
	var out_port: Vector2 = edge["out_port"]
	var in_port: Vector2 = edge["in_port"]
	var full := PackedVector2Array()
	full.append(start)
	# Chemin direct orthogonal (L) : aucun obstacle entre les deux stubs et un
	# coude dégagé → pas besoin d'A*.
	var direct_elbow := _NO_ELBOW
	if _direct_route_clear(start, end):
		direct_elbow = _ortho_link(start, end)
	if direct_elbow.x > -1e28:
		perf_direct += 1
		full.append(end)
	else:
		_freed.clear()
		var start_cell := _free_port_corridor(out_port, start)
		var end_cell := _free_port_corridor(in_port, end)
		if start_cell < 0 or end_cell < 0:
			_restore_freed()
			return PackedVector2Array()
		var path := _astar_points(start_cell, end_cell)
		_restore_freed()
		if path.size() < 2:
			perf_astar_fail += 1
			return PackedVector2Array()
		for i in range(path.size()):
			full.append(path[i])
		full.append(end)
	var route := _simplify_orthogonal(full)
	if route.size() < 2:
		return PackedVector2Array()
	return _assemble_routed(edge, route)


## Assemble le tracé final : stubs de port + tracé orthogonal simplifié, le tout
## lissé en « câble » à coins arrondis.
func _assemble_routed(edge: Dictionary, route: PackedVector2Array) -> PackedVector2Array:
	var out_port: Vector2 = edge["out_port"]
	var in_port: Vector2 = edge["in_port"]
	var start: Vector2 = edge["start"]
	var end: Vector2 = edge["end"]
	var raw := PackedVector2Array()
	raw.append(out_port)
	raw.append(Vector2(start.x, out_port.y))
	for i in range(route.size()):
		raw.append(route[i])
	raw.append(Vector2(end.x, in_port.y))
	raw.append(in_port)
	var smooth := CableGeometryScript.smooth_cable(raw, _zoom)
	if smooth.size() < 2:
		return PackedVector2Array()
	return smooth


## Vrai si le segment direct entre les deux stubs ne traverse aucune cellule
## bloquée ni déjà empruntée (les marges de confort, elles, sont tolérées : le
## lien file droit entre deux couloirs).
func _direct_route_clear(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	if dist < 0.5:
		return true
	var steps := maxi(2, int(ceilf(dist / maxf(cell * 0.4, 1.5))))
	for s in range(1, steps):
		var idx := _point_to_cell(a.lerp(b, float(s) / float(steps)))
		if _blocked[idx] == 1 or _occupancy[idx] > 0.01:
			return false
	return true


## Libère les cellules du couloir port → stub : un lien doit pouvoir SORTIR de
## sa propre carte (elle n'est pas un obstacle pour lui), puis l'A* reprend.
func _free_port_corridor(port_pos: Vector2, stub_point: Vector2) -> int:
	var idx := _point_to_cell(stub_point)
	var steps := maxi(2, int(ceilf(port_pos.distance_to(stub_point) / maxf(cell * 0.5, 1.0))))
	for s in range(steps + 1):
		_free_cell(_point_to_cell(port_pos.lerp(stub_point, float(s) / float(steps))))
	_free_cell(idx)
	return idx


func _free_cell(idx: int) -> void:
	if idx < 0 or idx >= _blocked.size():
		return
	if _blocked[idx] == 1:
		_blocked[idx] = 0
		if _astar != null:
			_astar.set_point_solid(Vector2i(idx % width, idx / width), false)
		_freed.append(idx)


func _restore_freed() -> void:
	for idx in _freed:
		_blocked[idx] = 1
		if _astar != null:
			_astar.set_point_solid(Vector2i(idx % width, idx / width), true)
	_freed.clear()


## A* natif (AStarGrid2D, en C++) : renvoie les points (centres de cellules) du
## chemin, ou vide si aucune route.
func _astar_points(start_idx: int, goal_idx: int) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()
	perf_astar_runs += 1
	var pts := _astar.get_point_path(
		Vector2i(start_idx % width, start_idx / width),
		Vector2i(goal_idx % width, goal_idx / width))
	if pts.size() < 2:
		perf_astar_expansions += 0
		return PackedVector2Array()
	perf_astar_expansions += pts.size()
	for pt in pts:
		if _occupancy[_point_to_cell(pt)] > 0.01:
			perf_astar_on_occupied += 1
	return pts


## Simplification ORTHOGONALE : on garde le minimum de points de virage, en
## reliant deux points par un L (segment horizontal + segment vertical) dès que
## c'est dégagé. Tracé « circuit » propre, croisements à 90°.
func _simplify_orthogonal(points: PackedVector2Array) -> PackedVector2Array:
	var t0 := Time.get_ticks_usec()
	var pts := CableGeometryScript.dedupe_points(points)
	var n := pts.size()
	if n < 2:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	var i := 0
	while i < n - 1:
		var best := i + 1
		var best_elbow := _NO_ELBOW
		var limit := mini(n - 1, i + 16)
		for j in range(limit, i + 1, -1):
			var elbow := _ortho_link(pts[i], pts[j])
			if elbow.x > -1e28:
				best = j
				best_elbow = elbow
				break
		if best == i + 1:
			# Pas de saut : relie au moins le point suivant en L (évite un
			# segment en diagonale entre le stub et le premier centre de cellule).
			var elbow := _ortho_link(pts[i], pts[i + 1])
			if elbow.x > -1e28 and elbow.distance_to(pts[i]) > 0.5 \
					and elbow.distance_to(pts[i + 1]) > 0.5:
				CableGeometryScript.append_unique(out, elbow)
			CableGeometryScript.append_unique(out, pts[i + 1])
		else:
			if best_elbow.distance_to(pts[i]) > 0.5 and best_elbow.distance_to(pts[best]) > 0.5:
				CableGeometryScript.append_unique(out, best_elbow)
			CableGeometryScript.append_unique(out, pts[best])
		i = best
	perf_simplify_us += Time.get_ticks_usec() - t0
	return out


## Relie deux points par un L orthogonal si les deux segments sont dégagés.
## Renvoie le coude, `a` si les points sont déjà alignés, ou _NO_ELBOW.
func _ortho_link(a: Vector2, b: Vector2) -> Vector2:
	if a.distance_to(b) < 0.5:
		return a
	if absf(a.x - b.x) < 0.01 or absf(a.y - b.y) < 0.01:
		if _los_clear(a, b):
			return a
		return _NO_ELBOW
	# Deux coudes orthogonaux possibles : on préfère celui qui part dans le sens
	# naturel du flux (horizontal d'abord). Un coude ne doit pas tomber dans une
	# cellule bloquée (la ligne de vue ignore les extrémités).
	var e1 := Vector2(b.x, a.y)
	if _blocked[_point_to_cell(e1)] == 0 and _los_clear(a, e1) and _los_clear(e1, b):
		return e1
	var e2 := Vector2(a.x, b.y)
	if _blocked[_point_to_cell(e2)] == 0 and _los_clear(a, e2) and _los_clear(e2, b):
		return e2
	return _NO_ELBOW


## Vrai si le segment ne traverse aucune cellule bloquée et ne réutilise pas un
## couloir déjà emprunté (quelques cellules occupées = simple croisement toléré).
func _los_clear(a: Vector2, b: Vector2) -> bool:
	var seg := a.distance_to(b)
	var steps := maxi(1, int(ceilf(seg / maxf(cell * 0.55, 1.6))))
	var occupied := 0
	for s in range(1, steps):
		var idx := _point_to_cell(a.lerp(b, float(s) / float(steps)))
		if _blocked[idx] == 1:
			return false
		if _occupancy[idx] > 0.01:
			occupied += 1
			if occupied > 2:
				return false
	return true


## Enregistre le tracé dans la grille d'occupation (anti-empilement des câbles).
## Les zones de port sont ignorées (les peignes gèrent déjà la séparation).
func mark_occupancy(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	if total < 1.0:
		return
	var step_len := maxf(cell * 0.7, 2.0)
	var walked := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var t := 0.0
		while t < seg:
			var dist := walked + t
			if dist >= PORT_ZONE and (total - dist) >= PORT_ZONE:
				var idx := _point_to_cell(a.lerp(b, t / seg))
				if _occupancy[idx] < 6.0:
					_occupancy[idx] += 1.0
					_apply_cell_weight(idx)
			t += step_len
		walked += seg


## Applique le poids d'une cellule à l'AStarGrid2D (marge de confort + occupation).
func _apply_cell_weight(idx: int) -> void:
	if _astar == null:
		return
	_astar.set_point_weight_scale(Vector2i(idx % width, idx / width),
		_base_weight[idx] + _occupancy[idx] * OCCUPANCY_CELL_COST)


## Nombre de points du tracé (hors zone de port) situés dans une AUTRE carte
## (rect gonflé de 2 px, l'exigence des tests). Sert de garde-fou : si > 0, le
## tracé A* est remplacé par le repli s'il fait mieux.
func count_hits(points: PackedVector2Array, rects: Array, from_idx: int, to_idx: int,
		out_port: Vector2, in_port: Vector2) -> int:
	if points.size() < 2:
		return 0
	var hits := 0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		var steps := maxi(1, int(ceilf(seg / 3.0)))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			if p.distance_to(out_port) < PORT_ZONE or p.distance_to(in_port) < PORT_ZONE:
				continue
			for r in range(rects.size()):
				if r == from_idx or r == to_idx:
					continue
				if (rects[r] as Rect2).grow(2.0).has_point(p):
					hits += 1
					break
	return hits


## REPLI (ancien tracé) : peigne de sortie + courbe de Bézier + peigne d'entrée.
## Si la courbe traverse une autre carte, on essaie des courbes bombées puis un
## DÉTOUR orthogonal par une voie libre (au-dessus / au-dessous de la carte).
## Utilisé si le routage A* échoue ou si le graphe est trop gros.
func route_fallback(start_port: Vector2, end_port: Vector2, out_port: Vector2, in_port: Vector2,
		seed: int, rects: Array, from_idx: int, to_idx: int, zoom: float,
		obstacle_checks: bool) -> PackedVector2Array:
	var out_mid := Vector2(start_port.x, out_port.y)
	var in_mid := Vector2(end_port.x, in_port.y)
	var candidates: Array = [{ "kind": "bow", "bow": 0.0, "cost": 0.0 }]
	if obstacle_checks:
		var base_band := clampf(56.0 * zoom, 40.0, 96.0)
		if end_port.x < start_port.x + 24.0:
			base_band *= 1.35
		var side := 1.0 if float(seed % 2) == 0.0 else -1.0
		candidates.append({ "kind": "bow", "bow": side * base_band, "cost": base_band })
		candidates.append({ "kind": "bow", "bow": -side * base_band, "cost": base_band })
		candidates.append({ "kind": "bow", "bow": side * base_band * 2.0, "cost": base_band * 2.0 })
		candidates.append({ "kind": "bow", "bow": -side * base_band * 2.0, "cost": base_band * 2.0 })
		# Détours orthogonaux : on part des cartes réellement traversées.
		var zero_curve := CableGeometryScript.curve_points(start_port, end_port, 0.0)
		var offenders := CableGeometryScript.offending_rects([out_port, out_mid, start_port],
			zero_curve, [end_port, in_mid, in_port], rects, from_idx, to_idx)
		if not offenders.is_empty():
			for lane in CableGeometryScript.detour_lanes(offenders, rects, start_port, end_port):
				var lane_cost := absf(float(lane) - start_port.y) + absf(float(lane) - end_port.y)
				candidates.append({ "kind": "lane", "lane": lane, "cost": lane_cost })
	var best: PackedVector2Array = PackedVector2Array()
	var best_hits := 1 << 30
	var best_cost := 1e12
	for candidate in candidates:
		var cand: Dictionary = candidate
		var full: PackedVector2Array
		if str(cand.get("kind", "bow")) == "lane":
			full = CableGeometryScript.detour_path(out_port, out_mid, start_port, end_port,
				in_mid, in_port, float(cand.get("lane", 0.0)))
		else:
			full = CableGeometryScript.assemble_edge(out_port, out_mid, start_port,
				CableGeometryScript.curve_points(start_port, end_port, float(cand.get("bow", 0.0))),
				end_port, in_mid, in_port)
		var hits := 0
		if obstacle_checks:
			hits = CableGeometryScript.count_node_hits(full, rects, from_idx, to_idx)
		var cost := float(cand.get("cost", 0.0))
		if hits < best_hits or (hits == best_hits and cost < best_cost):
			best_hits = hits
			best_cost = cost
			best = full
	if best.is_empty():
		best = CableGeometryScript.assemble_edge(out_port, out_mid, start_port,
			CableGeometryScript.curve_points(start_port, end_port, 0.0), end_port, in_mid, in_port)
	return best
