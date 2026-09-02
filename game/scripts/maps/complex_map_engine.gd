extends Control
class_name ComplexMapEngine

## Moteur VTT mode complexe — SubViewport, calques, particules, fog, zones.

signal token_moved(token_id: String, gx: float, gy: float)
signal map_clicked(gx: float, gy: float, tool: Dictionary)
signal effect_placed(effect: Dictionary)
signal effect_trigger_requested(effect_id: String)
signal fog_revealed(cells: Array)
signal zoom_changed(zoom_level: float)
signal token_selected(token_id: String)

const MapGridLayerScript := preload("res://scripts/maps/map_layers/map_grid_layer.gd")
const MapFogLayerScript := preload("res://scripts/maps/map_layers/map_fog_layer.gd")
const MapTokenNodeScript := preload("res://scripts/maps/map_layers/map_token_node.gd")
const MapZoneNodeScript := preload("res://scripts/maps/map_layers/map_zone_node.gd")
const MapEffectInstanceScript := preload("res://scripts/maps/map_layers/map_effect_instance.gd")

const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const DRAG_THRESHOLD := 4.0

var zoom: float = 1.0
var map_data: Dictionary = {}
var is_gm: bool = false
var readonly: bool = false
var snap_to_grid: bool = true
var session_tool: Dictionary = { "mode": "member" }

var _loaded_map_id: String = ""
var _party: Array = []
var _tokens: Array = []
var _effects: Array = []
var _zones: Array = []
var _fog_revealed: Array = []
var _selected_token_id: String = ""
var _grid_config: Dictionary = {}
var _map_pixel_size: Vector2 = Vector2.ZERO

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Node2D
var _background: Sprite2D
var _grid_layer: Node2D
var _zones_layer: Node2D
var _tokens_layer: Node2D
var _effects_layer: Node2D
var _fog_layer: Node2D
var _atmosphere: ColorRect
var _vignette: ColorRect

var _pan_dragging: bool = false
var _pending_click: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector2 = Vector2.ZERO
var _token_nodes: Dictionary = {}
var _effect_nodes: Dictionary = {}
var _zone_nodes: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build_viewport_tree()

func _build_viewport_tree() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = true
	_viewport_container.add_child(_viewport)

	_camera = Node2D.new()
	_camera.name = "Camera"
	_viewport.add_child(_camera)

	_background = Sprite2D.new()
	_background.name = "Background"
	_background.centered = false
	_camera.add_child(_background)

	_grid_layer = MapGridLayerScript.new()
	_grid_layer.name = "Grid"
	_camera.add_child(_grid_layer)

	_zones_layer = Node2D.new()
	_zones_layer.name = "Zones"
	_camera.add_child(_zones_layer)

	_tokens_layer = Node2D.new()
	_tokens_layer.name = "Tokens"
	_camera.add_child(_tokens_layer)

	_effects_layer = Node2D.new()
	_effects_layer.name = "Effects"
	_camera.add_child(_effects_layer)

	_fog_layer = MapFogLayerScript.new()
	_fog_layer.name = "Fog"
	_camera.add_child(_fog_layer)

	_atmosphere = ColorRect.new()
	_atmosphere.name = "Atmosphere"
	_atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmosphere.color = Color(0.05, 0.04, 0.08, 0.0)
	_atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_atmosphere)

	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0, 0, 0, 0.18)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_vignette)

func configure(
	p_map: Dictionary,
	p_tokens: Array,
	p_party: Array,
	p_effects: Array,
	p_zones: Array,
	p_fog_revealed: Array,
	p_readonly: bool,
	p_is_gm: bool,
	p_tool: Dictionary = {},
	p_view_state: Dictionary = {},
	p_selected_token: String = ""
) -> void:
	var new_id: String = p_map.get("id", "")
	var same_map := not new_id.is_empty() and new_id == _loaded_map_id

	map_data = p_map
	_tokens = p_tokens
	_party = p_party
	_effects = p_effects
	_zones = p_zones
	_fog_revealed = p_fog_revealed
	readonly = p_readonly
	is_gm = p_is_gm
	session_tool = p_tool if not p_tool.is_empty() else session_tool
	_selected_token_id = p_selected_token
	_grid_config = MapData.get_grid_config(p_map)
	_loaded_map_id = new_id

	_load_background()
	_apply_view_state(p_view_state)
	_rebuild_layers()

	if not same_map:
		call_deferred("_fit_to_view")

func set_session_tool(tool: Dictionary) -> void:
	session_tool = tool

func set_snap_to_grid(on: bool) -> void:
	snap_to_grid = on
	for node in _token_nodes.values():
		if node is MapTokenNode:
			node.snap_to_grid = on

func _load_background() -> void:
	var tex := MapData.load_background_texture(map_data)
	if tex == null:
		tex = MapData.generate_tile_texture(map_data, _grid_config)
	_background.texture = tex
	if tex:
		_map_pixel_size = tex.get_size()
	else:
		var gs := int(_grid_config.get("size", 70))
		_map_pixel_size = Vector2(map_data.get("width", 16) * gs, map_data.get("height", 12) * gs)

	var atmo := map_data.get("atmosphere", {})
	if atmo is Dictionary and atmo.get("enabled", false):
		var tint := Color.html(str(atmo.get("tint", "#1a1410")))
		tint.a = float(atmo.get("opacity", 0.25))
		_atmosphere.color = tint
		_vignette.color = Color(0, 0, 0, float(atmo.get("vignette", 0.15)))
	else:
		_atmosphere.color = Color(0, 0, 0, 0)
		_vignette.color = Color(0, 0, 0, 0.12 if is_gm else 0.2)

func _apply_view_state(view_state: Dictionary) -> void:
	if view_state.is_empty():
		return
	zoom = clampf(float(view_state.get("zoom", zoom)), MIN_ZOOM, MAX_ZOOM)
	_camera.position = Vector2(float(view_state.get("panX", 0)), float(view_state.get("panY", 0)))
	_camera.scale = Vector2.ONE * zoom

func get_view_state() -> Dictionary:
	return {
		"zoom": zoom,
		"panX": _camera.position.x,
		"panY": _camera.position.y,
	}

func _rebuild_layers() -> void:
	var gs := int(_grid_config.get("size", 70))
	var w: int = map_data.get("width", 16)
	var h: int = map_data.get("height", 12)
	var fog_on := bool(map_data.get("fogEnabled", true))

	if _grid_layer.has_method("configure"):
		_grid_layer.configure(_grid_config, w, h)
	if _fog_layer.has_method("configure"):
		_fog_layer.configure(w, h, gs, _fog_revealed, is_gm, fog_on)

	_clear_children(_tokens_layer, _token_nodes)
	_token_nodes.clear()
	for tok in _tokens:
		var node: MapTokenNode = MapTokenNodeScript.new()
		node.setup(tok, gs, _party, readonly)
		node.snap_to_grid = snap_to_grid
		node.set_selected(str(tok.get("id", "")) == _selected_token_id)
		node.drag_finished.connect(_on_token_drag_finished)
		node.selected.connect(_on_token_selected)
		_tokens_layer.add_child(node)
		_token_nodes[str(tok.get("id", ""))] = node

	_clear_children(_effects_layer, _effect_nodes)
	_effect_nodes.clear()
	for eff in _effects:
		var enode: MapEffectInstance = MapEffectInstanceScript.new()
		enode.setup(eff, gs)
		_effects_layer.add_child(enode)
		_effect_nodes[str(eff.get("id", ""))] = enode

	_clear_children(_zones_layer, _zone_nodes)
	_zone_nodes.clear()
	for zone in _zones:
		var znode: MapZoneNode = MapZoneNodeScript.new()
		znode.setup(zone, gs)
		_zones_layer.add_child(znode)
		_zone_nodes[str(zone.get("id", ""))] = znode

func _clear_children(layer: Node, registry: Dictionary) -> void:
	for child in layer.get_children():
		child.queue_free()
	registry.clear()

func _grid_size() -> int:
	return int(_grid_config.get("size", 70))

func _fit_to_view() -> void:
	if _map_pixel_size == Vector2.ZERO:
		return
	var vp := size if size.x > 16 and size.y > 16 else Vector2(640, 400)
	var fit_x := vp.x / _map_pixel_size.x
	var fit_y := vp.y / _map_pixel_size.y
	zoom = clampf(mini(fit_x, fit_y) * 0.95, MIN_ZOOM, MAX_ZOOM)
	_camera.scale = Vector2.ONE * zoom
	_camera.position = (vp - _map_pixel_size * zoom) * 0.5
	_clamp_camera()
	zoom_changed.emit(zoom)

func _clamp_camera() -> void:
	var vp := size if size.x > 16 and size.y > 16 else Vector2(640, 400)
	var scaled := _map_pixel_size * zoom
	var min_x := mini(0.0, vp.x - scaled.x)
	var min_y := mini(0.0, vp.y - scaled.y)
	_camera.position.x = clampf(_camera.position.x, min_x, 0.0)
	_camera.position.y = clampf(_camera.position.y, min_y, 0.0)

func _apply_zoom(factor: float, anchor: Vector2) -> void:
	var old_zoom := zoom
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var world_before := (anchor - _camera.position) / old_zoom
	zoom = new_zoom
	_camera.scale = Vector2.ONE * zoom
	_camera.position = anchor - world_before * zoom
	_clamp_camera()
	zoom_changed.emit(zoom)

func _screen_to_grid(pos: Vector2) -> Vector2:
	var gs := float(_grid_size())
	var world := (pos - _camera.position) / zoom
	return Vector2(world.x / gs, world.y / gs)

func _on_token_drag_finished(token_id: String, gx: float, gy: float) -> void:
	token_moved.emit(token_id, gx, gy)

func _on_token_selected(token_id: String) -> void:
	_selected_token_id = token_id
	for tid in _token_nodes:
		var node: MapTokenNode = _token_nodes[tid]
		node.set_selected(tid == token_id)
	token_selected.emit(token_id)

func _gui_input(event: InputEvent) -> void:
	if map_data.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(1.0 / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pending_click = true
				_pan_dragging = false
				_drag_start = mb.position
				_pan_start = _camera.position
				accept_event()
			else:
				if _pending_click and not _pan_dragging:
					_handle_map_click(mb.position)
				_pan_dragging = false
				_pending_click = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = mb.pressed
			_pending_click = false
			if mb.pressed:
				_drag_start = mb.position
				_pan_start = _camera.position
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pending_click and not _pan_dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_pan_dragging = true
				_pending_click = false
		if _pan_dragging:
			_camera.position = _pan_start + (motion.position - _drag_start)
			_clamp_camera()
			accept_event()

func _handle_map_click(screen_pos: Vector2) -> void:
	if readonly and not is_gm:
		return
	var grid := _screen_to_grid(screen_pos)
	var gx := grid.x
	var gy := grid.y
	if snap_to_grid:
		gx = roundf(gx)
		gy = roundf(gy)
	var w: int = map_data.get("width", 16)
	var h: int = map_data.get("height", 12)
	if gx < 0 or gy < 0 or gx >= w or gy >= h:
		return

	var mode: String = session_tool.get("mode", "member")
	if mode == "fog" and is_gm:
		var cells := _fog_brush_cells(int(gx), int(gy), 1)
		fog_revealed.emit(cells)
		return

	map_clicked.emit(gx, gy, session_tool.duplicate(true))

func _fog_brush_cells(cx: int, cy: int, radius: int) -> Array:
	var cells: Array = []
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if abs(x - cx) + abs(y - cy) <= radius:
				cells.append("%d,%d" % [x, y])
	return cells

func trigger_effect(effect_id: String) -> void:
	if _effect_nodes.has(effect_id):
		var node: MapEffectInstance = _effect_nodes[effect_id]
		node.trigger()
	effect_trigger_requested.emit(effect_id)

func zoom_in() -> void:
	_apply_zoom(1.15, size * 0.5)

func zoom_out() -> void:
	_apply_zoom(1.0 / 1.15, size * 0.5)

func reset_zoom() -> void:
	_fit_to_view()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not map_data.is_empty():
		_clamp_camera()
