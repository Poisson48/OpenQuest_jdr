extends Control

## Overlay des liens du graphe de scénarios, dessiné **au-dessus** des scènes.
##
## GraphEdit dessine ses liens natifs *sous* les GraphNode ; dès que deux scènes
## se chevauchent ou sont proches, les branches passent derrière les cartes et
## deviennent illisibles. Cet overlay :
##  - dessine tous les liens par-dessus les cartes (halo sombre + trait contrasté) ;
##  - ROUTE chaque lien AUTOUR des cartes : A* sur une grille de navigation
##    (8 directions) construite à partir des rectangles des cartes. Une marge
##    stricte garantit qu'aucun câble ne traverse une carte, une marge de
##    confort (12–16 px) attire les câbles vers les couloirs libres. Le tracé est
##    ensuite simplifié (lignes de vue) et ses coudes arrondis : rendu « câble »
##    d'éditeur de nœuds professionnel ;
##  - sépare les liens qui partent/arrivent sur une même scène (peignes de sortie
##    et d'entrée) et pénalise les cellules déjà empruntées : les câbles ne
##    s'empilent pas les uns sur les autres ;
##  - code la sémantique des branches : or = chemin par défaut, bleu = branche,
##    violet pointillé = suggestion MJ (`gmOnly`) ;
##  - dessine DERRIÈRE les cartes les cadres pointillés des actes (tags
##    « acte-1 », « acte-2 », …) ;
##  - n'affiche les libellés que pour le lien survolé et ceux de la scène
##    sélectionnée (évite le sapin de Noël sur les gros graphes).
##
## Repli obligatoire : si le routage n'aboutit pas (graphe trop grand, port
## bouché, linkbox introuvable…), on retombe sur l'ancien tracé en courbe de
## Bézier + détours orthogonaux. Jamais de crash, jamais de lien manquant.
##
## Les liens natifs de GraphEdit sont masqués (couleurs de slots alpha 0 dans
## `graph_node.gd`) : cet overlay est l'unique rendu des branches.

## Couleurs de branche — alignées sur la légende de l'éditeur.
const COLOR_DEFAULT: Color = Color("c9a44c")      # or : chemin par défaut
const COLOR_BRANCH: Color = Color("8fd2ea")       # bleu : branche alternative
const COLOR_GM_ONLY: Color = Color("b9a0dc")      # violet : suggestion MJ
const COLOR_HALO: Color = Color("0b0912")         # halo sombre sous chaque trait
const COLOR_LABEL_BG: Color = Color("1a1622")
const COLOR_LABEL_TEXT: Color = Color("f6eeda")
const COLOR_ACT_FRAME: Color = Color("8d7fc4")    # cadre d'acte (pointillés)
const COLOR_ACT_LABEL: Color = Color("bdb1a0")

const HOVER_DISTANCE := 14.0
const LABEL_MAX_CHARS := 30

## Étendue maximale d'un peigne de port : strictement < `LinkRouter.PORT_ZONE`
## pour que les montants verticaux des peignes restent dans la zone de port
## (sinon deux liens d'un même port se superposeraient au-delà de la zone
## exclue des contrôles de collision).
const FAN_MAX_SPREAD := 20.0

## Le routage (grille, A*, constantes de coût, replis géométriques) vit dans
## `res://scripts/core/graph/` : modules purs, sans `Node` ni `GraphEdit`.
const LinkRouterScript := preload("res://scripts/core/graph/link_router.gd")
const CableGeometryScript := preload("res://scripts/core/graph/cable_geometry.gd")

var graph_edit: GraphEdit = null
var _scenario_provider: Callable = Callable()
var _selected_provider: Callable = Callable()

var _edges: Array = []
var _node_infos: Array = []
var _cache_key: String = ""
var _data_revision: int = 0
var _hover_global: Vector2 = Vector2(-1e9, -1e9)
var _hover_index: int = -1
var _hover_dirty: bool = false
var _scenario_cache: Dictionary = {}
var _tool_preview_graph: Rect2 = Rect2()
var _tool_preview_active: bool = false
var _note_font: Font = null

var _label_style: StyleBoxFlat = null

# --- Routage (grille A*) -----------------------------------------------------
## Instance de routage : porte la grille, l'`AStarGrid2D`, les cellules libérées
## et les compteurs de perf. Une instance par overlay (aucun état statique) ;
## `build_grid()` réinitialise toute la grille à chaque rebuild.
var _router: LinkRouterScript = null
var _card_rects: Array = []
var _last_rebuild_ms: float = 0.0
var _last_rebuild_stats: Dictionary = {}
var _stats_print_msec: int = 0

# --- Cadres d'actes (couche dessinée SOUS les cartes) ------------------------
var _act_layer: Control = null
var _act_frames: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	top_level = true
	z_index = 40
	set_process(true)
	_router = LinkRouterScript.new()


## Branche l'overlay sur un GraphEdit.
func setup(ge: GraphEdit, scenario_provider: Callable, selected_provider: Callable) -> void:
	graph_edit = ge
	_scenario_provider = scenario_provider
	_selected_provider = selected_provider
	_data_revision += 1


## À appeler quand le scénario change (branches, libellés, défaut, gmOnly…).
func notify_scenario_changed() -> void:
	_data_revision += 1


func set_hover_global(global_pos: Vector2) -> void:
	if _hover_global.distance_squared_to(global_pos) < 0.25:
		return
	_hover_global = global_pos
	_hover_dirty = true
	queue_redraw()


func clear_hover() -> void:
	if _hover_global.x < -1e8:
		return
	_hover_global = Vector2(-1e9, -1e9)
	_hover_index = -1
	_hover_dirty = false
	queue_redraw()


func get_hovered_edge() -> Dictionary:
	if _hover_index < 0 or _hover_index >= _edges.size():
		return {}
	return _edges[_hover_index]


## Accès de test : géométrie et sémantique des liens calculés.
func get_debug_edges() -> Array:
	var out: Array = []
	for edge in _edges:
		out.append({
			"from_id": edge.get("from_id", ""),
			"to_id": edge.get("to_id", ""),
			"label": edge.get("label", ""),
			"default": edge.get("default", false),
			"gm_only": edge.get("gm_only", false),
			"fan_out": edge.get("fan_out", 0.0),
			"fan_in": edge.get("fan_in", 0.0),
			"points": edge.get("points", PackedVector2Array()),
			"mid": edge.get("mid", Vector2.ZERO),
			"kernel": edge.get("kernel", "fallback"),
			"hits": edge.get("hits", 0),
		})
	return out


func get_debug_node_rects() -> Array:
	var out: Array = []
	for info in _node_infos:
		out.append((info as Dictionary).get("rect", Rect2()))
	return out


## Accès de test : scènes visibles avec rectangles/ports en coordonnées overlay.
func get_debug_node_infos() -> Array:
	var out: Array = []
	for info_variant in _node_infos:
		var info: Dictionary = info_variant
		out.append({
			"scene_id": str(info.get("scene_id", "")),
			"rect": info.get("rect", Rect2()),
			"out_port": info.get("out_port", Vector2.ZERO),
			"in_port": info.get("in_port", Vector2.ZERO),
		})
	return out


## Accès de test : statistiques du dernier rebuild (perf, routage).
func get_routing_stats() -> Dictionary:
	return _last_rebuild_stats.duplicate(true)


## Accès de test : cadres d'actes calculés ({rect, label, act}).
func get_debug_act_frames() -> Array:
	return _act_frames.duplicate(true)


func get_last_rebuild_ms() -> float:
	return _last_rebuild_ms


func force_rebuild() -> void:
	_cache_key = ""
	_rebuild()
	queue_redraw()


# ---------------------------------------------------------------------------
# Cycle de vie
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _is_graph_drawable():
		visible = false
		if _act_layer != null and is_instance_valid(_act_layer):
			_act_layer.visible = false
		return
	visible = true
	var ge_pos := graph_edit.get_global_position()
	if global_position.distance_squared_to(ge_pos) > 0.01:
		global_position = ge_pos
	if size != graph_edit.size:
		size = graph_edit.size
	_sync_act_layer_transform()
	var key := _compute_cache_key()
	if key != _cache_key:
		_cache_key = key
		_rebuild()
	if _hover_dirty:
		_hover_dirty = false
		_update_hover_index()
	queue_redraw()


func _is_graph_drawable() -> bool:
	return graph_edit != null and is_instance_valid(graph_edit) \
		and graph_edit.is_inside_tree() and graph_edit.is_visible_in_tree() \
		and graph_edit.size.x > 8.0 and graph_edit.size.y > 8.0


## Signature bon marché : reconstruire la géométrie seulement quand quelque
## chose bouge (déplacement de scène, zoom, pan, branche, sélection, données).
func _compute_cache_key() -> String:
	var parts := PackedStringArray()
	parts.append("%.2f|%.2f|%d|%d" % [
		graph_edit.zoom, graph_edit.scroll_offset.x, int(graph_edit.scroll_offset.y), _data_revision])
	parts.append("%d" % graph_edit.get_connection_list().size())
	parts.append("%s" % _selected_scene_id())
	for child in graph_edit.get_children():
		if child is GraphNode and is_instance_valid(child) and not (child as Node).is_queued_for_deletion():
			var gn := child as GraphNode
			parts.append("%s:%d:%d:%d:%d:%d" % [
				str(gn.get_meta("scene_id", "")),
				int(roundf(gn.position_offset.x)), int(roundf(gn.position_offset.y)),
				int(roundf(gn.size.x)), int(roundf(gn.size.y)),
				int(roundf(gn.get_global_position().y))])
	return "|".join(parts)


func _selected_scene_id() -> String:
	if _selected_provider.is_valid():
		return str(_selected_provider.call())
	return ""


# ---------------------------------------------------------------------------
# Construction de la géométrie
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	_edges.clear()
	_node_infos.clear()
	_card_rects.clear()
	_act_frames.clear()
	# Grille invalidée pour ce rebuild (reconstruite à l'étape 5 si le graphe
	# reste routable) ; les compteurs de perf repartent de zéro.
	_router.enabled = false
	_router.reset_perf()
	_last_rebuild_stats = {
		"edges": 0, "nodes": 0, "routed": 0, "fallback": 0, "hits": 0,
		"cell": 0.0, "grid": Vector2i.ZERO, "grid_enabled": false,
	}
	if not _is_graph_drawable():
		_finish_rebuild(t0)
		return
	var scenario: Dictionary = {}
	if _scenario_provider.is_valid():
		var data: Variant = _scenario_provider.call()
		if data is Dictionary:
			scenario = data
	var transitions_by_pair := _index_transitions(scenario)
	var tags_by_id := _index_tags(scenario)
	_scenario_cache = scenario
	var inv := get_global_transform().affine_inverse()
	var zoom := graph_edit.zoom

	# 1) Scènes → rectangles et points de ports, en coordonnées overlay.
	var by_name: Dictionary = {}
	var nodes: Array = []
	for child in graph_edit.get_children():
		if not (child is GraphNode):
			continue
		var gn := child as GraphNode
		if not is_instance_valid(gn) or gn.is_queued_for_deletion() or not gn.is_visible_in_tree():
			continue
		var gt := gn.get_global_transform()
		var p0: Vector2 = inv * (gt * Vector2.ZERO)
		var p1: Vector2 = inv * (gt * gn.size)
		var rect := Rect2(p0, p1 - p0).abs()
		var out_port: Vector2 = inv * (gt * gn.get_output_port_position(0))
		var in_port: Vector2 = inv * (gt * gn.get_input_port_position(0))
		var info := {
			"node": gn,
			"scene_id": str(gn.get_meta("scene_id", "")),
			"rect": rect,
			"out_port": out_port,
			"in_port": in_port,
			"is_start": bool(gn.get_meta("is_start", false)),
			"is_terminal": bool(gn.get_meta("is_terminal", false)),
			"is_unreachable": bool(gn.get_meta("is_unreachable", false)),
		}
		by_name[gn.name] = nodes.size()
		nodes.append(info)
		_node_infos.append(info)
	if nodes.is_empty():
		_finish_rebuild(t0)
		return

	# 2) Connexions → arêtes (références vers les index de scènes).
	var raw_edges: Array = []
	for conn_variant in graph_edit.get_connection_list():
		if typeof(conn_variant) != TYPE_DICTIONARY:
			continue
		var conn: Dictionary = conn_variant
		if not by_name.has(conn.get("from_node")):
			continue
		if not by_name.has(conn.get("to_node")):
			continue
		var from_idx: int = int(by_name[conn.get("from_node")])
		var to_idx: int = int(by_name[conn.get("to_node")])
		var from_id: String = str((nodes[from_idx] as Dictionary).get("scene_id", ""))
		var to_id: String = str((nodes[to_idx] as Dictionary).get("scene_id", ""))
		var transition: Dictionary = transitions_by_pair.get("%s|%s" % [from_id, to_id], {})
		raw_edges.append({
			"from_idx": from_idx,
			"to_idx": to_idx,
			"from_id": from_id,
			"to_id": to_id,
			"label": str(transition.get("label", to_id)).strip_edges(),
			"default": bool(transition.get("default", false)),
			"gm_only": bool(transition.get("gmOnly", false)),
		})
	if raw_edges.is_empty():
		_finish_rebuild(t0)
		return

	# 3) Peignes : plusieurs branches depuis/vers une même scène sont réparties
	#    verticalement pour ne plus se superposer au départ du port.
	var out_groups: Dictionary = {}
	var in_groups: Dictionary = {}
	for i in range(raw_edges.size()):
		var e: Dictionary = raw_edges[i]
		if not out_groups.has(int(e["from_idx"])):
			out_groups[int(e["from_idx"])] = []
		(out_groups[int(e["from_idx"])] as Array).append(i)
		if not in_groups.has(int(e["to_idx"])):
			in_groups[int(e["to_idx"])] = []
		(in_groups[int(e["to_idx"])] as Array).append(i)
	for from_idx in out_groups.keys():
		var group: Array = out_groups[from_idx]
		group.sort_custom(func(a: int, b: int) -> bool:
			var ta: Dictionary = nodes[int(raw_edges[a]["to_idx"])]
			var tb: Dictionary = nodes[int(raw_edges[b]["to_idx"])]
			return (ta["rect"] as Rect2).get_center().y < (tb["rect"] as Rect2).get_center().y)
		out_groups[from_idx] = group
	for to_idx in in_groups.keys():
		var group: Array = in_groups[to_idx]
		group.sort_custom(func(a: int, b: int) -> bool:
			var ta: Dictionary = nodes[int(raw_edges[a]["from_idx"])]
			var tb: Dictionary = nodes[int(raw_edges[b]["from_idx"])]
			return (ta["rect"] as Rect2).get_center().y < (tb["rect"] as Rect2).get_center().y)
		in_groups[to_idx] = group

	# 4) Points d'entrée/sortie de chaque lien (peigne + stub) en coordonnées
	#    overlay : ils servent à dimensionner la grille de routage.
	var rects: Array = []
	for info in nodes:
		var info_rect: Rect2 = (info as Dictionary).get("rect", Rect2())
		rects.append(info_rect)
		_card_rects.append(info_rect)
	var starts: Array = []
	var ends: Array = []
	for i in range(raw_edges.size()):
		var e: Dictionary = raw_edges[i]
		var from_info: Dictionary = nodes[int(e["from_idx"])]
		var to_info: Dictionary = nodes[int(e["to_idx"])]
		var from_rect: Rect2 = from_info["rect"]
		var to_rect: Rect2 = to_info["rect"]
		var out_port: Vector2 = from_info["out_port"]
		var in_port: Vector2 = to_info["in_port"]
		# Le peigne reste dans la zone de port (< LinkRouter.PORT_ZONE) : au-delà, les
		# « montants » verticaux de deux liens se superposeraient à l'identique.
		var out_off := _fan_offset(out_groups[int(e["from_idx"])], i, zoom, FAN_MAX_SPREAD)
		var in_off := _fan_offset(in_groups[int(e["to_idx"])], i, zoom, FAN_MAX_SPREAD)
		var stub := clampf(13.0 * zoom, 10.0, 22.0)
		var start := out_port + Vector2(stub, out_off)
		var end := in_port + Vector2(-stub, in_off)
		e["out_port"] = out_port
		e["in_port"] = in_port
		e["start"] = start
		e["end"] = end
		e["fan_out"] = out_off
		e["fan_in"] = in_off
		starts.append(start)
		ends.append(end)

	# 5) Grille de navigation + routage, liens courts d'abord (ils ont le moins
	#    d'options ; les longs se faufilent ensuite dans les couloirs restants).
	var grid_t0 := Time.get_ticks_usec()
	_router.build_grid(rects, starts, ends, zoom)
	_router.perf_grid_us = Time.get_ticks_usec() - grid_t0
	var route_order: Array = []
	for i in range(raw_edges.size()):
		route_order.append(i)
	route_order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = (starts[a] as Vector2).distance_squared_to(ends[a])
		var db: float = (starts[b] as Vector2).distance_squared_to(ends[b])
		if is_equal_approx(da, db):
			return a < b
		return da < db)
	var points_by_edge: Dictionary = {}
	var kernel_by_edge: Dictionary = {}
	var hits_by_edge: Dictionary = {}
	var fallback_count := 0
	var routed_count := 0
	var hits_total := 0
	for i in route_order:
		var e: Dictionary = raw_edges[i]
		var from_idx := int(e["from_idx"])
		var to_idx := int(e["to_idx"])
		var points := PackedVector2Array()
		var kernel := "fallback"
		var route_t0 := Time.get_ticks_usec()
		if _router.enabled:
			points = _router.route_edge(e)
			if not points.is_empty():
				kernel = "grid"
		_router.perf_route_us += Time.get_ticks_usec() - route_t0
		if points.is_empty():
			points = _router.route_fallback(e["start"], e["end"], e["out_port"], e["in_port"],
				i, rects, from_idx, to_idx, zoom, true)
		var hits_t0 := Time.get_ticks_usec()
		var hits := _router.count_hits(points, rects, from_idx, to_idx, e["out_port"], e["in_port"])
		_router.perf_hits_us += Time.get_ticks_usec() - hits_t0
		if hits > 0 and kernel == "grid":
			# Le routage A* n'a pas totalement abouti (port bouché, arrondi trop
			# près d'une carte) : on compare avec l'ancien tracé et on garde le
			# meilleur — sans jamais laisser un lien traverser une carte si un
			# tracé propre existe.
			var alt := _router.route_fallback(e["start"], e["end"], e["out_port"], e["in_port"],
				i, rects, from_idx, to_idx, zoom, true)
			var alt_hits := _router.count_hits(alt, rects, from_idx, to_idx, e["out_port"], e["in_port"])
			if alt_hits < hits:
				points = alt
				hits = alt_hits
				kernel = "fallback"
		if kernel == "grid":
			routed_count += 1
			_router.mark_occupancy(points)
		else:
			fallback_count += 1
		hits_total += hits
		points_by_edge[i] = points
		kernel_by_edge[i] = kernel
		hits_by_edge[i] = hits

	# 6) Assemblage final des arêtes (ordre d'origine pour la stabilité).
	for i in range(raw_edges.size()):
		var e: Dictionary = raw_edges[i]
		var points: PackedVector2Array = points_by_edge.get(i, PackedVector2Array())
		var mid := CableGeometryScript.polyline_midpoint(points)
		e["points"] = points
		e["mid"] = mid
		e["label_pos"] = _label_anchor(points, rects, int(e["from_idx"]), int(e["to_idx"]))
		e["color"] = COLOR_DEFAULT if bool(e["default"]) else (
			COLOR_GM_ONLY if bool(e["gm_only"]) else COLOR_BRANCH)
		e["width"] = 2.9 if bool(e["default"]) else (1.9 if bool(e["gm_only"]) else 2.1)
		e["hovered"] = false
		e["kernel"] = str(kernel_by_edge.get(i, "fallback"))
		e["hits"] = int(hits_by_edge.get(i, 0))
		_edges.append(e)

	# 7) Cadres d'actes (dessinés par une couche dédiée SOUS les cartes).
	_act_frames = _compute_act_frames(nodes, tags_by_id)
	_act_frames.append_array(_editor_frames_local(zoom))
	_sync_act_layer()

	_last_rebuild_stats = {
		"edges": raw_edges.size(),
		"nodes": nodes.size(),
		"routed": routed_count,
		"fallback": fallback_count,
		"hits": hits_total,
		"cell": _router.cell,
		"grid": _router.grid_size(),
		"grid_enabled": _router.enabled,
		"grid_ms": snappedf(float(_router.perf_grid_us) / 1000.0, 0.01),
		"route_ms": snappedf(float(_router.perf_route_us) / 1000.0, 0.01),
		"simplify_ms": snappedf(float(_router.perf_simplify_us) / 1000.0, 0.01),
		"hits_ms": snappedf(float(_router.perf_hits_us) / 1000.0, 0.01),
		"astar_runs": _router.perf_astar_runs,
		"astar_expansions": _router.perf_astar_expansions,
		"astar_fail": _router.perf_astar_fail,
		"astar_on_occupied": _router.perf_astar_on_occupied,
		"direct": _router.perf_direct,
	}
	_finish_rebuild(t0)
	_update_hover_index()


## Clôt un rebuild : mesure de perf + trace (throttlée pour ne pas spammer
## pendant un drag) + rafraîchissement des couches.
func _finish_rebuild(t0: int) -> void:
	_last_rebuild_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	_last_rebuild_stats["rebuild_ms"] = _last_rebuild_ms
	_sync_act_layer()
	queue_redraw()
	var now := Time.get_ticks_msec()
	if _last_rebuild_ms >= 8.0 or now - _stats_print_msec >= 4000:
		_stats_print_msec = now
		print("[GraphLinkOverlay] rebuild %.1f ms — %d cartes, %d liens (%d routés, %d repli, %d points sur carte) — grille %dx%d cell %.1f" % [
			_last_rebuild_ms,
			int(_last_rebuild_stats.get("nodes", 0)),
			int(_last_rebuild_stats.get("edges", 0)),
			int(_last_rebuild_stats.get("routed", 0)),
			int(_last_rebuild_stats.get("fallback", 0)),
			int(_last_rebuild_stats.get("hits", 0)),
			_router.grid_size().x, _router.grid_size().y, _router.cell])


## Décalage vertical du lien k parmi n dans un peigne de port.
func _fan_offset(group: Array, edge_index: int, zoom: float, max_spread: float) -> float:
	var n := group.size()
	if n <= 1:
		return 0.0
	var k := 0
	for idx in range(n):
		if int(group[idx]) == edge_index:
			k = idx
			break
	var gap := clampf(12.0 * zoom, 9.0, 16.0)
	if n > 1:
		gap = minf(gap, (max_spread * 2.0) / float(n - 1))
	return (float(k) - float(n - 1) * 0.5) * gap


# ---------------------------------------------------------------------------
# Cadres d'actes (couche dessinée SOUS les cartes)
# ---------------------------------------------------------------------------

func _index_tags(scenario: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for scene_variant in scenario.get("scenes", []):
		if typeof(scene_variant) != TYPE_DICTIONARY:
			continue
		var scene: Dictionary = scene_variant
		var tags: Variant = scene.get("tags", [])
		if tags is Array:
			result[str(scene.get("id", ""))] = tags
	return result


## Cadres d'actes : regroupe les cartes par tag « acte-N » et renvoie les
## rectangles englobants (coordonnées overlay) + libellé. Aucun tag → aucun cadre.
func _compute_act_frames(nodes: Array, tags_by_id: Dictionary) -> Array:
	var groups: Dictionary = {}
	for info_variant in nodes:
		var info: Dictionary = info_variant
		var tags: Variant = tags_by_id.get(str(info.get("scene_id", "")), [])
		if not (tags is Array):
			continue
		for tag_variant in tags:
			var act := _parse_act_number(str(tag_variant))
			if act <= 0:
				continue
			if not groups.has(act):
				groups[act] = []
			(groups[act] as Array).append((info["rect"] as Rect2))
			break
	var frames: Array = []
	var acts: Array = groups.keys()
	acts.sort()
	for act in acts:
		var union := Rect2()
		var first := true
		for rect_variant in groups[act]:
			var rect: Rect2 = rect_variant
			if first:
				union = rect
				first = false
			else:
				union = union.merge(rect)
		union = union.grow(18.0)
		# Un peu d'air au-dessus du cadre pour le libellé d'acte.
		union.position.y -= 12.0
		union.size.y += 12.0
		frames.append({ "rect": union, "label": "ACTE " + _roman(int(act)), "act": int(act) })
	return frames


## Extrait le numéro d'un tag d'acte : « acte-1 », « acte 2 », « acte3 ».
func _parse_act_number(tag: String) -> int:
	var text := tag.strip_edges().to_lower()
	if not text.begins_with("acte"):
		return 0
	text = text.substr(4).strip_edges().lstrip("-_ ")
	if text.is_empty() or not text.is_valid_int():
		return 0
	return maxi(int(text), 0)


func _roman(value: int) -> String:
	if value <= 0 or value > 39:
		return str(value)
	var values := [10, 9, 5, 4, 1]
	var symbols := ["X", "IX", "V", "IV", "I"]
	var out := ""
	var remaining := value
	for i in range(values.size()):
		while remaining >= int(values[i]):
			out += str(symbols[i])
			remaining -= int(values[i])
	return out


## Crée/synchronise la couche de cadres d'actes, enfant de GraphEdit et placée
## en premier : elle est donc dessinée APRÈS le fond du graphe mais AVANT les
## cartes (les cadres ne masquent jamais une scène).
func _sync_act_layer() -> void:
	if graph_edit == null or not is_instance_valid(graph_edit):
		return
	if _act_layer == null or not is_instance_valid(_act_layer):
		_act_layer = ActFrameLayer.new()
		_act_layer.name = "GraphLinkActFrames"
		graph_edit.add_child(_act_layer)
		graph_edit.move_child(_act_layer, 0)
	_act_layer.set("frames", _act_frames)
	_act_layer.visible = not _act_frames.is_empty()
	_sync_act_layer_transform()
	_act_layer.queue_redraw()


func _sync_act_layer_transform() -> void:
	if _act_layer == null or not is_instance_valid(_act_layer):
		return
	if graph_edit == null or not is_instance_valid(graph_edit):
		return
	_act_layer.top_level = true
	_act_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_act_layer.clip_contents = true
	_act_layer.global_position = graph_edit.get_global_position()
	_act_layer.size = graph_edit.size


## Couche de dessin des cadres d'actes. Dessine des rectangles arrondis en
## pointillés + un petit libellé (coin haut-gauche), sans intercepter la souris.
class ActFrameLayer:
	extends Control

	const FRAME_COLOR := Color("8d7fc4")
	const LABEL_COLOR := Color("bdb1a0")

	var frames: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func _draw() -> void:
		if frames.is_empty():
			return
		var font: Font = get_theme_font(&"font", &"Label")
		for item_variant in frames:
			var item: Dictionary = item_variant
			var rect: Rect2 = item.get("rect", Rect2())
			if rect.size.x < 12.0 or rect.size.y < 12.0:
				continue
			var path := _rounded_rect_points(rect, 14.0)
			_dashed_loop(path, Color(FRAME_COLOR.r, FRAME_COLOR.g, FRAME_COLOR.b, 0.42),
				1.4, 7.0, 6.0)
			if font != null:
				draw_string(font, rect.position + Vector2(14.0, 17.0), str(item.get("label", "")),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					Color(LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b, 0.82))

	## Contour arrondi d'un rectangle (boucle fermée, coins en arcs).
	func _rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
		var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.35)
		var x0 := rect.position.x
		var y0 := rect.position.y
		var x1 := rect.position.x + rect.size.x
		var y1 := rect.position.y + rect.size.y
		var pts := PackedVector2Array()
		pts.append(Vector2(x0 + r, y0))
		pts.append(Vector2(x1 - r, y0))
		_append_arc(pts, Vector2(x1 - r, y0 + r), r, -PI * 0.5, 0.0)
		pts.append(Vector2(x1, y1 - r))
		_append_arc(pts, Vector2(x1 - r, y1 - r), r, 0.0, PI * 0.5)
		pts.append(Vector2(x0 + r, y1))
		_append_arc(pts, Vector2(x0 + r, y1 - r), r, PI * 0.5, PI)
		pts.append(Vector2(x0, y0 + r))
		_append_arc(pts, Vector2(x0 + r, y0 + r), r, PI, PI * 1.5)
		pts.append(pts[0])
		return pts

	func _append_arc(pts: PackedVector2Array, center: Vector2, radius: float,
			from_angle: float, to_angle: float) -> void:
		var steps := 6
		for s in range(1, steps + 1):
			var angle := lerpf(from_angle, to_angle, float(s) / float(steps))
			pts.append(center + Vector2(cos(angle), sin(angle)) * radius)

	## Pointillés le long d'une boucle fermée.
	func _dashed_loop(points: PackedVector2Array, color: Color, width: float,
			dash: float, gap: float) -> void:
		var period := maxf(dash + gap, 2.0)
		var phase := 0.0
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var seg_len := a.distance_to(b)
			if seg_len < 0.001:
				continue
			var dir := (b - a) / seg_len
			var walked := 0.0
			while walked < seg_len:
				var cycle_pos := fmod(phase + walked, period)
				var in_dash := cycle_pos < dash
				var next_step := period - cycle_pos
				if in_dash:
					next_step = minf(next_step, dash - cycle_pos)
				var step := maxf(minf(next_step, seg_len - walked), 0.01)
				if in_dash:
					draw_line(a + dir * walked, a + dir * (walked + step), color, width, true)
				walked += step
			phase = fmod(phase + seg_len, period)


## Point d'ancrage du libellé : le plus proche du milieu du tracé qui ne tombe
## pas sur une carte (sinon la pastille masque une scène).
func _label_anchor(points: PackedVector2Array, rects: Array, from_idx: int, to_idx: int) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var mid_index := int(points.size() / 2)
	var probe := Rect2(Vector2.ZERO, Vector2(150.0, 28.0))
	var order: Array = []
	for offset in range(points.size()):
		for dir in [1, -1]:
			var idx: int = mid_index + offset * int(dir)
			if idx >= 0 and idx < points.size() and not order.has(idx):
				order.append(idx)
		if order.size() >= points.size():
			break
	for idx in order:
		var pt: Vector2 = points[idx]
		probe.position = pt - probe.size * 0.5
		var clear := true
		for r in range(rects.size()):
			if r == from_idx or r == to_idx:
				continue
			if (rects[r] as Rect2).grow(2.0).intersects(probe):
				clear = false
				break
		if clear:
			return pt
	return points[mid_index]


func _index_transitions(scenario: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for scene_variant in scenario.get("scenes", []):
		if typeof(scene_variant) != TYPE_DICTIONARY:
			continue
		var scene: Dictionary = scene_variant
		var from_id := str(scene.get("id", ""))
		for transition_variant in scene.get("transitions", []):
			if typeof(transition_variant) != TYPE_DICTIONARY:
				continue
			var transition: Dictionary = transition_variant
			var to_id := str(transition.get("to", ""))
			if to_id.is_empty():
				continue
			result["%s|%s" % [from_id, to_id]] = transition
	return result


# ---------------------------------------------------------------------------
# Survol
# ---------------------------------------------------------------------------

func _update_hover_index() -> void:
	_hover_index = -1
	if _hover_global.x < -1e8 or _edges.is_empty():
		return
	var local := get_global_transform().affine_inverse() * _hover_global
	# Survoler une carte ne doit pas surligner un lien qui passerait dessous.
	for info in _node_infos:
		if (info as Dictionary).get("rect", Rect2()).has_point(local):
			return
	var best := HOVER_DISTANCE
	var best_index := -1
	for i in range(_edges.size()):
		var edge: Dictionary = _edges[i]
		var points: PackedVector2Array = edge.get("points", PackedVector2Array())
		var dist := _distance_to_polyline(local, points)
		if dist < best:
			best = dist
			best_index = i
	_hover_index = best_index


static func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.size() < 2:
		return 1e9
	var best := 1e9
	for i in range(1, points.size()):
		var d := _distance_point_segment(point, points[i - 1], points[i])
		if d < best:
			best = d
	return best


static func _distance_point_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)


# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _edges.is_empty() and _node_infos.is_empty():
		return
	var selected_id := _selected_scene_id()
	for i in range(_edges.size()):
		_edges[i]["hovered"] = (i == _hover_index)
	var normal_edges: Array = []
	var active_edges: Array = []
	for i in range(_edges.size()):
		var edge: Dictionary = _edges[i]
		if _is_edge_active(edge, selected_id):
			active_edges.append(i)
		else:
			normal_edges.append(i)
	for i in normal_edges:
		_draw_edge(_edges[i], 0.22)
	for i in active_edges:
		_draw_edge(_edges[i], 1.0)
	_draw_ports()
	_draw_labels(selected_id)
	_draw_notes()
	_draw_tool_preview()


func _is_edge_active(edge: Dictionary, selected_id: String) -> bool:
	if bool(edge.get("hovered", false)):
		return true
	if selected_id.is_empty():
		return true
	return str(edge.get("from_id", "")) == selected_id or str(edge.get("to_id", "")) == selected_id


func _draw_edge(edge: Dictionary, alpha: float) -> void:
	var points: PackedVector2Array = edge.get("points", PackedVector2Array())
	if points.size() < 2:
		return
	var base_color: Color = edge.get("color", COLOR_BRANCH)
	var hovered := bool(edge.get("hovered", false))
	var zoom := graph_edit.zoom
	var width: float = float(edge.get("width", 2.0)) * clampf(zoom, 0.7, 1.45)
	if hovered:
		width += 1.0
	var color := Color(base_color.r, base_color.g, base_color.b, alpha)
	var halo := Color(COLOR_HALO.r, COLOR_HALO.g, COLOR_HALO.b, alpha * 0.92)
	draw_polyline(points, halo, width + 4.0, true)
	if bool(edge.get("gm_only", false)):
		_draw_dashed_polyline(points, color, width, 7.0 * clampf(zoom, 0.7, 1.2), 5.0)
	else:
		draw_polyline(points, color, width, true)
	_draw_arrow_head(points, color, width, zoom)
	if hovered:
		var mid: Vector2 = edge.get("mid", Vector2.ZERO)
		draw_circle(mid, 3.5, Color(COLOR_LABEL_TEXT.r, COLOR_LABEL_TEXT.g, COLOR_LABEL_TEXT.b, alpha))


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float,
		dash: float, gap: float) -> void:
	var period := maxf(dash + gap, 2.0)
	var phase := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg_len := a.distance_to(b)
		if seg_len < 0.001:
			continue
		var dir := (b - a) / seg_len
		var walked := 0.0
		while walked < seg_len:
			var in_dash := fmod(phase + walked, period) < dash
			var next_step := period - fmod(phase + walked, period)
			if in_dash:
				next_step = minf(next_step, dash - fmod(phase + walked, period))
			var step := maxf(minf(next_step, seg_len - walked), 0.01)
			if in_dash:
				draw_line(a + dir * walked, a + dir * (walked + step), color, width, true)
			walked += step
		phase = fmod(phase + seg_len, period)


func _draw_arrow_head(points: PackedVector2Array, color: Color, width: float, zoom: float) -> void:
	if points.size() < 2:
		return
	var tip := points[points.size() - 1]
	var before := points[points.size() - 2]
	for i in range(points.size() - 2, -1, -1):
		if points[i].distance_to(tip) > 2.0:
			before = points[i]
			break
	var dir := (tip - before).normalized()
	if dir.length_squared() < 0.5:
		return
	var size := clampf(7.5 * zoom, 5.0, 11.0)
	var side := Vector2(-dir.y, dir.x) * size * 0.55
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * size + side, tip - dir * size - side]), color)


func _draw_ports() -> void:
	var zoom := graph_edit.zoom
	var radius := clampf(3.6 * zoom, 2.4, 5.6)
	for info in _node_infos:
		var node: Dictionary = info
		var color := Color(ThemeColors.GOLD_LIGHT.r, ThemeColors.GOLD_LIGHT.g, ThemeColors.GOLD_LIGHT.b, 0.95)
		if bool(node.get("is_start", false)):
			color = Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g, ThemeColors.GOLD.b, 1.0)
		elif bool(node.get("is_terminal", false)):
			color = Color(ThemeColors.SUCCESS.r, ThemeColors.SUCCESS.g, ThemeColors.SUCCESS.b, 1.0)
		elif bool(node.get("is_unreachable", false)):
			color = Color(ThemeColors.DANGER.r, ThemeColors.DANGER.g, ThemeColors.DANGER.b, 1.0)
		var dark := Color(COLOR_HALO.r, COLOR_HALO.g, COLOR_HALO.b, 0.9)
		draw_circle(node["out_port"], radius, color)
		draw_circle(node["out_port"], radius * 0.45, dark)
		draw_circle(node["in_port"], radius, Color(color.r, color.g, color.b, 0.75))
		draw_circle(node["in_port"], radius * 0.45, dark)


func _draw_labels(selected_id: String) -> void:
	var font: Font = get_theme_font(&"font", &"Label")
	if font == null:
		return
	var zoom := graph_edit.zoom
	var base_size: int = int(get_theme_font_size(&"font_size", &"Label"))
	var font_size := int(round(float(base_size) * clampf(zoom, 0.85, 1.1)))
	# Canevas ouvert (mix Atelier) : les libellés s'affichent AU SURVOL uniquement.
	# Les branches sortantes restaient affichées en permanence et formaient des
	# pastilles flottantes qui masquaient les cartes ; les infos restent dans
	# l'inspecteur (onglet Branches).
	var allow_selected := false
	var selected_outgoing := 0
	if not selected_id.is_empty():
		for edge in _edges:
			if str(edge.get("from_id", "")) == selected_id:
				selected_outgoing += 1
	if selected_outgoing > 5:
		allow_selected = false
	var shown: Array = []
	for edge in _edges:
		var hovered := bool(edge.get("hovered", false))
		var show := hovered or (allow_selected and not selected_id.is_empty()
			and str(edge.get("from_id", "")) == selected_id)
		if not show:
			continue
		var label := _label_text(edge)
		if label.is_empty():
			continue
		shown.append({ "edge": edge, "label": label, "hovered": hovered })
	# Les libellés les plus hauts d'abord : la pastille suivante est décalée
	# verticalement pour ne jamais recouvrir une autre pastille.
	shown.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = (a["edge"] as Dictionary).get("label_pos", Vector2.ZERO)
		var pb: Vector2 = (b["edge"] as Dictionary).get("label_pos", Vector2.ZERO)
		return pa.y < pb.y)
	var occupied: Array = []
	for item in shown:
		var edge: Dictionary = item["edge"]
		var label: String = item["label"]
		var hovered := bool(item.get("hovered", false))
		var base: Vector2 = edge.get("label_pos", edge.get("mid", Vector2.ZERO))
		var rect_size := _label_rect_size(font, font_size, label)
		# En vue d'ensemble, une pastille ne doit pas masquer une carte : on la
		# décale verticalement jusqu'à trouver un emplacement libre (les cartes
		# sont le support de lecture principal du canevas ouvert).
		var placed := _find_free_label_rect(base, rect_size, occupied,
			[] if hovered else _card_rects)
		occupied.append(placed)
		_draw_label_pill(font, font_size, placed.get_center(), label,
			edge.get("color", COLOR_BRANCH))


func _label_rect_size(font: Font, font_size: int, text: String) -> Vector2:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return text_size + Vector2(14.0, 6.0)


## Cherche la meilleure position pour la pastille : on évite les autres
## pastilles, et on minimise le recouvrement des cartes de scène (les cartes
## sont le support de lecture principal du canevas ouvert). Un décalage trop
## grand coûte légèrement plus cher, ce qui garde la pastille près de son lien.
func _find_free_label_rect(center: Vector2, sz: Vector2, occupied: Array,
		obstacles: Array = []) -> Rect2:
	var candidates: Array = []
	for dy in [0.0, 18.0, -18.0, 36.0, -36.0, 54.0, -54.0, 72.0, -72.0,
			92.0, -92.0, 112.0, -112.0]:
		candidates.append(Vector2(0.0, float(dy)))
	for dx in [26.0, -26.0, 52.0, -52.0, 78.0, -78.0]:
		candidates.append(Vector2(float(dx), 0.0))
	var best := Rect2(center - sz * 0.5, sz)
	var best_score := INF
	for offset_variant in candidates:
		var offset: Vector2 = offset_variant
		var rect := Rect2(center + offset - sz * 0.5, sz)
		if _label_rect_hits_labels(rect, occupied):
			continue
		var score := _label_rect_card_overlap(rect, obstacles) + offset.length() * 0.02
		if score < best_score:
			best_score = score
			best = rect
			if obstacles.is_empty() or score <= 0.01:
				break
	return best


func _label_rect_hits_labels(rect: Rect2, occupied: Array) -> bool:
	for other in occupied:
		if (other as Rect2).grow(3.0).intersects(rect):
			return true
	return false


## Aire de recouvrement avec les cartes (0 = pastille entièrement libre).
func _label_rect_card_overlap(rect: Rect2, obstacles: Array) -> float:
	var overlap := 0.0
	for obstacle in obstacles:
		var card: Rect2 = obstacle
		var inter := card.grow(2.0).intersection(rect)
		if inter.size.x > 0.0 and inter.size.y > 0.0:
			overlap += inter.size.x * inter.size.y
	return overlap


func _label_text(edge: Dictionary) -> String:
	var text := str(edge.get("label", "")).strip_edges()
	if text.is_empty():
		text = str(edge.get("to_id", ""))
	if bool(edge.get("gm_only", false)):
		text = "MJ · " + text
	elif bool(edge.get("default", false)):
		text = "★ " + text
	if text.length() > LABEL_MAX_CHARS:
		text = text.substr(0, LABEL_MAX_CHARS - 1) + "…"
	return text


func _draw_label_pill(font: Font, font_size: int, center: Vector2, text: String, accent: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(7.0, 3.0)
	var rect := Rect2(center - (text_size + pad * 2.0) * 0.5, text_size + pad * 2.0)
	# Garde la pastille entièrement dans le canevas (sinon un libellé au bord
	# gauche/droit apparaît tronqué, comme une carte coupée).
	var inner := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	if inner.size.x > rect.size.x:
		rect.position.x = clampf(rect.position.x, inner.position.x, inner.end.x - rect.size.x)
	if inner.size.y > rect.size.y:
		rect.position.y = clampf(rect.position.y, inner.position.y, inner.end.y - rect.size.y)
	if _label_style == null:
		_label_style = StyleBoxFlat.new()
	_label_style.bg_color = Color(COLOR_LABEL_BG.r, COLOR_LABEL_BG.g, COLOR_LABEL_BG.b, 0.94)
	_label_style.set_corner_radius_all(5)
	_label_style.set_border_width_all(1)
	_label_style.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	draw_style_box(_label_style, rect)
	var baseline := center + Vector2(-text_size.x * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_LABEL_TEXT)


# ---------------------------------------------------------------------------
# Annotations du plan : notes, cadres libres et aperçu d'outil
# ---------------------------------------------------------------------------

## Coordonnées graphe (position_offset) → coordonnées overlay.
func _graph_to_local(point: Vector2) -> Vector2:
	return point * graph_edit.zoom - graph_edit.scroll_offset


## Cadres créés à la main dans l'éditeur (outil Cadre), convertis en overlay.
func _editor_frames_local(zoom: float) -> Array:
	var result: Array = []
	var raw: Variant = _scenario_cache.get("editorFrames", [])
	if not (raw is Array):
		return result
	for frame_variant in raw:
		if typeof(frame_variant) != TYPE_DICTIONARY:
			continue
		var frame: Dictionary = frame_variant
		var pos := _graph_to_local(Vector2(float(frame.get("x", 0.0)), float(frame.get("y", 0.0))))
		var size := Vector2(float(frame.get("w", 0.0)), float(frame.get("h", 0.0))) * zoom
		if size.x < 24.0 or size.y < 18.0:
			continue
		result.append({
			"rect": Rect2(pos, size),
			"label": str(frame.get("label", "CADRE")),
			"act": 0,
		})
	return result


func set_tool_preview_graph(rect: Rect2) -> void:
	_tool_preview_graph = rect
	_tool_preview_active = true
	queue_redraw()


func clear_tool_preview() -> void:
	_tool_preview_active = false
	queue_redraw()


func _draw_tool_preview() -> void:
	if not _tool_preview_active:
		return
	var pos := _graph_to_local(_tool_preview_graph.position)
	var size := _tool_preview_graph.size * graph_edit.zoom
	var rect := Rect2(pos, size)
	if rect.size.x < 4.0 and rect.size.y < 4.0:
		return
	draw_rect(rect, Color(COLOR_DEFAULT.r, COLOR_DEFAULT.g, COLOR_DEFAULT.b, 0.12), true)
	draw_rect(rect, Color(COLOR_DEFAULT.r, COLOR_DEFAULT.g, COLOR_DEFAULT.b, 0.9), false, 1.6)


## Notes du plan : petites étiquettes (texte édité via l'outil Note).
func _draw_notes() -> void:
	var raw: Variant = _scenario_cache.get("editorNotes", [])
	if not (raw is Array) or (raw as Array).is_empty():
		return
	var font: Font = get_theme_font(&"font", &"Label")
	if font == null:
		return
	_note_font = font
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.91, 0.84, 0.62, 0.94)
	style.border_color = Color(0.63, 0.48, 0.2, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	var box_size := Vector2(190, 64)
	for note_variant in raw:
		if typeof(note_variant) != TYPE_DICTIONARY:
			continue
		var note: Dictionary = note_variant
		var anchor := _graph_to_local(Vector2(float(note.get("x", 0.0)), float(note.get("y", 0.0))))
		var rect := Rect2(anchor, box_size)
		draw_style_box(style, rect)
		var text := str(note.get("text", "")).strip_edges()
		if text.is_empty():
			text = "Note"
		var max_chars := 26
		var first := text.substr(0, max_chars)
		draw_string(font, rect.position + Vector2(10, 20), first,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.16, 0.13, 0.08))
		if text.length() > max_chars:
			draw_string(font, rect.position + Vector2(10, 38), text.substr(max_chars, max_chars),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.16, 0.13, 0.08))
		if text.length() > max_chars * 2:
			draw_string(font, rect.position + Vector2(10, 56), "…",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.16, 0.13, 0.08))
