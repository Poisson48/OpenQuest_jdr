extends Control

## Mini-carte du graphe de scénario (refonte 04 « Console de nœuds »).
##
## Composant autonome posé par défaut en bas-droite du GraphEdit : il se
## dimensionne (≈ 220 × 140), se place lui-même (marge 12) et redessine chaque
## frame une vue réduite des GraphNode et de leurs liens. Un clic recentre le
## GraphEdit sur le point cliqué (`scroll_offset`).
##
## Le fournisseur `scenario_provider` renvoie le Dictionary du scénario
## (transitions : `to`, `default`, `gmOnly`) ; les métadonnées des GraphNode
## (`is_start`, `is_terminal`, `scene_id`, `selected`) pilotent les couleurs.
##
## Le mix « Atelier » l'utilise en panneau flottant titré (« PLAN D'ENSEMBLE »)
## en bas-gauche du canevas : `set_caption()` ajoute le libellé et
## `set_placement()` choisit le coin + la marge. Les valeurs par défaut restent
## celles de la console 04 (bas-droite, sans titre) pour ne pas casser les
## tests du composant.

const PANEL_SIZE := Vector2(220.0, 140.0)
const EDGE_MARGIN := 12.0
const INNER_PADDING := 8.0
const NODE_BOUNDS_MARGIN := 24.0
const MIN_PANEL_SIZE := Vector2(80.0, 60.0)
const CAPTION_HEIGHT := 16.0
const CAPTION_FONT_SIZE := 10
const BG_COLOR := Color("1a1622")

const CORNER_BOTTOM_RIGHT := "bottom_right"
const CORNER_BOTTOM_LEFT := "bottom_left"
const CORNER_TOP_RIGHT := "top_right"
const CORNER_TOP_LEFT := "top_left"

var _graph_edit: GraphEdit = null
var _scenario_provider: Callable = Callable()
var _enabled: bool = true
var _bg_style: StyleBoxFlat = null
var _caption: String = ""
var _panel_size: Vector2 = PANEL_SIZE
var _placement: String = CORNER_BOTTOM_RIGHT
var _edge_margin: Vector2 = Vector2(EDGE_MARGIN, EDGE_MARGIN)

var _bounds: Rect2 = Rect2()
var _scale: float = 1.0
var _content_origin: Vector2 = Vector2.ZERO
var _has_content: bool = false


func setup(graph_edit: GraphEdit, scenario_provider: Callable) -> void:
	_graph_edit = graph_edit
	_scenario_provider = scenario_provider
	_bg_style = _make_bg_style()
	top_level = true
	z_index = 100
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_size()
	size = _panel_size
	# Si l'hôte ne l'a pas encore ajouté, on se greffe sur le Graphe pour être
	# au-dessus de lui et capter les clics. Sinon on respecte son parent.
	if graph_edit != null and is_instance_valid(graph_edit) \
			and not is_inside_tree() and graph_edit.is_inside_tree():
		graph_edit.add_child(self)
	_refresh_layout()
	_sync_geometry()
	queue_redraw()
	set_process(true)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	set_process(enabled)
	if enabled:
		_refresh_layout()
		_sync_geometry()
		queue_redraw()


func is_enabled() -> bool:
	return _enabled


## Libellé de panneau flottant (« PLAN D'ENSEMBLE »). Vide = pas de titre
## (comportement console 04 d'origine).
func set_caption(text: String) -> void:
	_caption = text.strip_edges()
	_apply_panel_size()
	_refresh_layout()
	_sync_geometry()
	queue_redraw()


func get_caption() -> String:
	return _caption


## Taille demandée du panneau (le contenu s'y inscrit après marges/titre).
func set_panel_size(panel_size: Vector2) -> void:
	_panel_size = Vector2(maxf(panel_size.x, MIN_PANEL_SIZE.x), maxf(panel_size.y, MIN_PANEL_SIZE.y))
	_apply_panel_size()
	_refresh_layout()
	_sync_geometry()
	queue_redraw()


## Coin d'ancrage dans le GraphEdit + marge appliquée.
func set_placement(corner: String, margin: Vector2 = Vector2(EDGE_MARGIN, EDGE_MARGIN)) -> void:
	match corner:
		CORNER_BOTTOM_LEFT, CORNER_TOP_RIGHT, CORNER_TOP_LEFT, CORNER_BOTTOM_RIGHT:
			_placement = corner
		_:
			_placement = CORNER_BOTTOM_RIGHT
	_edge_margin = margin
	_sync_geometry()
	queue_redraw()


## Rect local où la mini-carte est dessinée (sous le titre éventuel).
func get_content_rect() -> Rect2:
	return _content_rect()


func force_redraw() -> void:
	_refresh_layout()
	_sync_geometry()
	queue_redraw()


# ---------------------------------------------------------------------------
# API de test / intégration
# ---------------------------------------------------------------------------

## Convertit un point local du mini-plan en coordonnées graphe.
func pick(local_point: Vector2) -> Vector2:
	if _scale <= 0.0:
		return Vector2.ZERO
	return (local_point - _content_origin) / _scale


## Convertit un point graphe en point local du mini-plan.
func local_point_for_graph(graph_point: Vector2) -> Vector2:
	return graph_point * _scale + _content_origin


## Centre la vue du GraphEdit sur `graph_pos` (coordonnées graphe).
func center_at(graph_pos: Vector2) -> void:
	if _graph_edit == null or not is_instance_valid(_graph_edit):
		return
	var zoom: float = maxf(_graph_edit.zoom, 0.001)
	_graph_edit.scroll_offset = graph_pos * zoom - _graph_edit.size * 0.5


func get_debug_state() -> Dictionary:
	return {
		"scale": _scale,
		"origin": _content_origin,
		"bounds": _bounds,
		"has_content": _has_content,
		"node_count": _collect_nodes().size(),
	}


# ---------------------------------------------------------------------------
# Cycle de vie
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _enabled:
		return
	_refresh_layout()
	_sync_geometry()
	queue_redraw()


# ---------------------------------------------------------------------------
# Géométrie
# ---------------------------------------------------------------------------

func _sync_geometry() -> void:
	if _graph_edit == null or not is_instance_valid(_graph_edit):
		return
	var graph_rect: Rect2 = _graph_edit.get_global_rect()
	var panel_w := minf(_panel_size.x, maxf(graph_rect.size.x - 2.0 * _edge_margin.x,
		MIN_PANEL_SIZE.x))
	var panel_h := minf(_panel_size.y, maxf(graph_rect.size.y - 2.0 * _edge_margin.y,
		MIN_PANEL_SIZE.y))
	var panel_size := Vector2(panel_w, panel_h)
	if size != panel_size:
		size = panel_size
	var pos := graph_rect.position
	match _placement:
		CORNER_BOTTOM_LEFT:
			pos += Vector2(_edge_margin.x,
				graph_rect.size.y - panel_size.y - _edge_margin.y)
		CORNER_TOP_LEFT:
			pos += _edge_margin
		CORNER_TOP_RIGHT:
			pos += Vector2(graph_rect.size.x - panel_size.x - _edge_margin.x, _edge_margin.y)
		_:
			pos += Vector2(
				graph_rect.size.x - panel_size.x - _edge_margin.x,
				graph_rect.size.y - panel_size.y - _edge_margin.y)
	global_position = pos


## Taille minimale cohérente avec le titre éventuel (le panneau doit pouvoir
## afficher la carte sous le libellé).
func _apply_panel_size() -> void:
	custom_minimum_size = _panel_size


## Zone utile du panneau : sous le titre quand il y en a un.
func _content_rect() -> Rect2:
	if _caption.is_empty():
		return Rect2(
			Vector2(INNER_PADDING, INNER_PADDING),
			size - Vector2(INNER_PADDING * 2.0, INNER_PADDING * 2.0))
	return Rect2(
		Vector2(INNER_PADDING, CAPTION_HEIGHT),
		Vector2(size.x - INNER_PADDING * 2.0,
			size.y - CAPTION_HEIGHT - INNER_PADDING))


func _refresh_layout() -> void:
	if _graph_edit == null or not is_instance_valid(_graph_edit):
		_has_content = false
		return
	var nodes := _collect_nodes()
	_has_content = not nodes.is_empty()
	if not _has_content:
		_bounds = Rect2(Vector2.ZERO, size)
		_scale = 1.0
		_content_origin = Vector2.ZERO
		return
	_bounds = _compute_bounds(nodes)
	var inner := _content_rect()
	var safe_bounds := Vector2(maxf(_bounds.size.x, 1.0), maxf(_bounds.size.y, 1.0))
	_scale = minf(inner.size.x / safe_bounds.x, inner.size.y / safe_bounds.y)
	if _scale <= 0.0:
		_scale = 1.0
	var drawn_size := safe_bounds * _scale
	_content_origin = inner.position + (inner.size - drawn_size) * 0.5 \
		- _bounds.position * _scale


func _collect_nodes() -> Array:
	var nodes: Array = []
	if _graph_edit == null or not is_instance_valid(_graph_edit):
		return nodes
	for child in _graph_edit.get_children():
		if child is GraphNode and is_instance_valid(child) \
				and not child.is_queued_for_deletion():
			nodes.append(child)
	return nodes


func _compute_bounds(nodes: Array) -> Rect2:
	var bounds := Rect2()
	var first := true
	for node in nodes:
		var graph_node := node as GraphNode
		var node_pos: Vector2 = graph_node.position_offset
		var node_size := _node_size(graph_node)
		var rect := Rect2(node_pos, node_size)
		if first:
			bounds = rect
			first = false
		else:
			bounds = bounds.merge(rect)
	if first:
		return Rect2(Vector2.ZERO, Vector2(800.0, 600.0))
	bounds = bounds.grow(NODE_BOUNDS_MARGIN)
	var safe_size := bounds.size
	safe_size.x = maxf(safe_size.x, 1.0)
	safe_size.y = maxf(safe_size.y, 1.0)
	bounds.size = safe_size
	return bounds


func _node_size(node: GraphNode) -> Vector2:
	var sz: Vector2 = node.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = node.custom_minimum_size
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = Vector2(220.0, 120.0)
	return sz


# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------

func _make_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.93)
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = ThemeColors.BORDER
	return style


func _draw() -> void:
	if _bg_style == null:
		_bg_style = _make_bg_style()
	draw_style_box(_bg_style, Rect2(Vector2.ZERO, size))
	_draw_caption()

	var nodes := _collect_nodes()
	if nodes.is_empty():
		return
	var scenario := _scenario_dictionary()
	var by_id: Dictionary = {}
	for node in nodes:
		by_id[str((node as GraphNode).get_meta("scene_id", ""))] = node

	_draw_links(nodes, by_id, scenario)
	_draw_view_rect()
	_draw_nodes(nodes)


## Titre de panneau flottant (« PLAN D'ENSEMBLE »), en petites capitales.
func _draw_caption() -> void:
	if _caption.is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := CAPTION_FONT_SIZE
	draw_string(font, Vector2(INNER_PADDING, CAPTION_HEIGHT - 4.0),
		_caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		ThemeColors.TEXT_MUTED)
	# Filet discret sous le titre, dans la teinte des bordures.
	draw_line(Vector2(INNER_PADDING, CAPTION_HEIGHT - 2.0),
		Vector2(size.x - INNER_PADDING, CAPTION_HEIGHT - 2.0),
		ThemeColors.BORDER, 1.0)


func _draw_links(nodes: Array, by_id: Dictionary, scenario: Dictionary) -> void:
	if scenario.is_empty():
		return
	var scenes: Variant = scenario.get("scenes", [])
	if typeof(scenes) != TYPE_ARRAY:
		return
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_id := str((scene as Dictionary).get("id", ""))
		if not by_id.has(from_id):
			continue
		var transitions: Variant = (scene as Dictionary).get("transitions", [])
		if typeof(transitions) != TYPE_ARRAY:
			continue
		for transition in transitions:
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str((transition as Dictionary).get("to", ""))
			if not by_id.has(to_id):
				continue
			var color := _link_color(transition as Dictionary)
			var from_node := by_id[from_id] as GraphNode
			var to_node := by_id[to_id] as GraphNode
			var from_center := local_point_for_graph(
				from_node.position_offset + _node_size(from_node) * 0.5)
			var to_center := local_point_for_graph(
				to_node.position_offset + _node_size(to_node) * 0.5)
			draw_line(from_center, to_center, color, 1.0)


func _draw_view_rect() -> void:
	if _graph_edit == null or not is_instance_valid(_graph_edit):
		return
	var zoom: float = maxf(_graph_edit.zoom, 0.001)
	var visible_graph_rect := Rect2(_graph_edit.scroll_offset / zoom,
		_graph_edit.size / zoom)
	var local_rect := Rect2(
		local_point_for_graph(visible_graph_rect.position),
		visible_graph_rect.size * _scale)
	draw_rect(local_rect, Color(ThemeColors.GOLD_LIGHT.r, ThemeColors.GOLD_LIGHT.g,
		ThemeColors.GOLD_LIGHT.b, 0.22), false, 1.0)


func _draw_nodes(nodes: Array) -> void:
	for node in nodes:
		var graph_node := node as GraphNode
		var local_pos := local_point_for_graph(graph_node.position_offset)
		var local_size := _node_size(graph_node) * _scale
		local_size.x = maxf(local_size.x, 3.0)
		local_size.y = maxf(local_size.y, 3.0)
		var rect := Rect2(local_pos, local_size)
		var border := _node_color(graph_node)
		# Fond sombre : la mini-carte doit rester un plan lisible, pas un aplat
		# de couleur claire (TEXT_MUTED servait de remplissage → rendu beige).
		var fill := Color(0.16, 0.14, 0.21, 0.95)
		if _is_node_selected(graph_node):
			fill = Color(0.95, 0.85, 0.55, 0.95)
		elif bool(graph_node.get_meta("is_start", false)):
			fill = Color(0.35, 0.28, 0.12, 0.95)
		elif bool(graph_node.get_meta("is_terminal", false)):
			fill = Color(0.15, 0.30, 0.26, 0.95)
		draw_rect(rect, fill, true)
		draw_rect(rect, border, false, 1.0)


func _node_color(node: GraphNode) -> Color:
	if _is_node_selected(node):
		return ThemeColors.GOLD_LIGHT
	if bool(node.get_meta("is_start", false)):
		return ThemeColors.GOLD
	if bool(node.get_meta("is_terminal", false)):
		return ThemeColors.SUCCESS
	return ThemeColors.TEXT_MUTED


func _is_node_selected(node: GraphNode) -> bool:
	if node.has_meta("is_selected"):
		return bool(node.get_meta("is_selected"))
	var value: Variant = node.get("selected")
	if value == null:
		return false
	return bool(value)


func _link_color(transition: Dictionary) -> Color:
	if bool(transition.get("default", false)):
		return ThemeColors.GOLD
	if bool(transition.get("gmOnly", false)):
		return ThemeColors.LOG_NPC
	return ThemeColors.INVESTIGATION_ACCENT


func _scenario_dictionary() -> Dictionary:
	if not _scenario_provider.is_valid():
		return {}
	var value: Variant = _scenario_provider.call()
	if value is Dictionary:
		return value
	return {}


# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		center_at(pick(event.position))
		accept_event()
