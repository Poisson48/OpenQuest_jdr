extends Control
class_name ComplexMapEngine3D

## Moteur VTT 3D top-down — SubViewport 3D, ombres réelles, particules GPUParticles3D.

signal token_moved(token_id: String, gx: float, gy: float)
signal map_clicked(gx: float, gy: float, tool: Dictionary)
signal effect_placed(effect: Dictionary)
signal effect_trigger_requested(effect_id: String)
signal fog_revealed(cells: Array)
signal fog_hidden(cells: Array)
signal zoom_changed(zoom_level: float)
signal token_selected(token_id: String)

const MapGround3DScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const MapGrid3DScript := preload("res://scripts/maps/map_layers/map_grid_3d.gd")
const MapToken3DScript := preload("res://scripts/maps/map_layers/map_token_3d.gd")
const MapEffect3DScript := preload("res://scripts/maps/map_layers/map_effect_3d.gd")
const MapZone3DScript := preload("res://scripts/maps/map_layers/map_zone_3d.gd")
const MapFog3DScript := preload("res://scripts/maps/map_layers/map_fog_3d.gd")
const MapElevations3DScript := preload("res://scripts/maps/map_layers/map_elevations_3d.gd")

const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const DRAG_THRESHOLD := 4.0
const PAN_INERTIA_DECAY := 0.88
const PAN_INERTIA_MIN := 2.0
const CAM_HEIGHT := 48.0

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
var _map_extent: Vector2 = Vector2.ZERO
var _cell_size: float = 1.0
var _base_ortho_size: float = 10.0

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _ground: Node3D
var _elevations_layer: Node3D
var _grid_layer: Node3D
var _zones_layer: Node3D
var _tokens_layer: Node3D
var _effects_layer: Node3D
var _fog_layer: Node3D
var _sun: DirectionalLight3D
var _atmosphere: ColorRect
var _vignette: ColorRect

var _pan_dragging: bool = false
var _pending_click: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector3 = Vector3.ZERO
var _pan_velocity: Vector2 = Vector2.ZERO
var _last_pan_pos: Vector2 = Vector2.ZERO
var _token_drag: Node = null
var _token_nodes: Dictionary = {}
var _effect_nodes: Dictionary = {}
var _zone_nodes: Dictionary = {}
var _lighting_config: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)
	_build_viewport_tree()

func _build_viewport_tree() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.disable_3d = false
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.size = Vector2i(1024, 768)
	_viewport_container.add_child(_viewport)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.38, 0.48)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	_viewport.add_child(env_node)

	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.position = Vector3(0.0, CAM_HEIGHT, 0.0)
	_camera.current = true
	_world.add_child(_camera)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-58.0, 38.0, 0.0)
	_sun.light_energy = 1.15
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 120.0
	_world.add_child(_sun)

	_ground = MapGround3DScript.new()
	_ground.name = "Ground"
	_world.add_child(_ground)

	_elevations_layer = MapElevations3DScript.new()
	_elevations_layer.name = "Elevations"
	_world.add_child(_elevations_layer)

	_grid_layer = MapGrid3DScript.new()
	_grid_layer.name = "Grid"
	_world.add_child(_grid_layer)

	_zones_layer = Node3D.new()
	_zones_layer.name = "Zones"
	_world.add_child(_zones_layer)

	_tokens_layer = Node3D.new()
	_tokens_layer.name = "Tokens"
	_world.add_child(_tokens_layer)

	_effects_layer = Node3D.new()
	_effects_layer.name = "Effects"
	_world.add_child(_effects_layer)

	_fog_layer = MapFog3DScript.new()
	_fog_layer.name = "Fog"
	_world.add_child(_fog_layer)

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
	_cell_size = float(_grid_config.get("size", 70)) * 0.01
	_lighting_config = MapData.get_lighting_config(p_map)
	_loaded_map_id = new_id

	_load_ground()
	_load_elevations()
	_apply_camera_perspective()
	_apply_lighting()
	_apply_atmosphere()
	_apply_view_state(p_view_state)
	_rebuild_layers()

	if not same_map:
		call_deferred("_fit_to_view")

func set_session_tool(tool: Dictionary) -> void:
	session_tool = tool

func set_snap_to_grid(on: bool) -> void:
	snap_to_grid = on
	for node in _token_nodes.values():
		node.snap_to_grid = on

func _load_ground() -> void:
	var tex := MapData.load_background_texture(map_data)
	if tex == null:
		tex = MapData.generate_tile_texture(map_data, _grid_config)
	var w: int = map_data.get("width", 16)
	var h: int = map_data.get("height", 12)
	if _ground.has_method("configure"):
		_ground.configure(tex, w, h, _cell_size)
	_map_extent = Vector2(float(w) * _cell_size, float(h) * _cell_size)
	_base_ortho_size = maxf(_map_extent.x, _map_extent.y) * 0.55

func _load_elevations() -> void:
	if _elevations_layer and _elevations_layer.has_method("configure"):
		_elevations_layer.configure(map_data, _cell_size)

func _apply_camera_perspective() -> void:
	var persp := MapData.get_perspective(map_data)
	match persp:
		MapData.PERSPECTIVE_ISOMETRIC:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.rotation_degrees = Vector3(-58.0, 45.0, 0.0)
			_camera.position.y = CAM_HEIGHT
		MapData.PERSPECTIVE_TILT:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.rotation_degrees = Vector3(-48.0, 0.0, 0.0)
			_camera.fov = 38.0
			_camera.position.y = CAM_HEIGHT * 0.85
		_:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			_camera.position.y = CAM_HEIGHT
	_update_ortho_size()

func _apply_lighting() -> void:
	if _lighting_config.get("enabled", false):
		var dir: String = str(_lighting_config.get("direction", "nw"))
		match dir:
			"ne":
				_sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
			"sw":
				_sun.rotation_degrees = Vector3(-55.0, -145.0, 0.0)
			"se":
				_sun.rotation_degrees = Vector3(-55.0, 145.0, 0.0)
			_:
				_sun.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
		_sun.light_energy = 0.85 + float(_lighting_config.get("intensity", 0.35))
	else:
		_sun.rotation_degrees = Vector3(-58.0, 38.0, 0.0)
		_sun.light_energy = 1.15

func _apply_atmosphere() -> void:
	var atmo: Dictionary = map_data.get("atmosphere", {}) if map_data.get("atmosphere") is Dictionary else {}
	if atmo is Dictionary and atmo.get("enabled", false):
		var tint := Color.html(str(atmo.get("tint", "#1a1410")))
		tint.a = float(atmo.get("opacity", 0.25))
		_atmosphere.color = tint
		_vignette.color = Color(0, 0, 0, float(atmo.get("vignette", 0.15)))
	else:
		_atmosphere.color = Color(0.04, 0.03, 0.06, 0.08)
		_vignette.color = Color(0, 0, 0, 0.12 if is_gm else 0.22)

func _apply_view_state(view_state: Dictionary) -> void:
	if view_state.is_empty():
		return
	zoom = clampf(float(view_state.get("zoom", zoom)), MIN_ZOOM, MAX_ZOOM)
	_camera.position.x = float(view_state.get("panX", _camera.position.x))
	_camera.position.z = float(view_state.get("panY", _camera.position.z))
	_update_ortho_size()

func get_view_state() -> Dictionary:
	return {
		"zoom": zoom,
		"panX": _camera.position.x,
		"panY": _camera.position.z,
	}

func _rebuild_layers() -> void:
	var w: int = map_data.get("width", 16)
	var h: int = map_data.get("height", 12)
	var fog_on := bool(map_data.get("fogEnabled", true))

	if _grid_layer.has_method("configure"):
		var grid_cfg := _grid_config.duplicate(true)
		if not grid_cfg.has("opacity"):
			grid_cfg["opacity"] = 0.14
		_grid_layer.configure(grid_cfg, w, h, _cell_size)

	if _fog_layer.has_method("configure"):
		_fog_layer.configure(w, h, _cell_size, _fog_revealed, is_gm, fog_on)

	_clear_children(_tokens_layer, _token_nodes)
	_token_nodes.clear()
	for tok in _tokens:
		var node = MapToken3DScript.new()
		node.setup(tok, _cell_size, _party, readonly)
		node.snap_to_grid = snap_to_grid
		node.set_selected(str(tok.get("id", "")) == _selected_token_id)
		node.drag_finished.connect(_on_token_drag_finished)
		node.selected.connect(_on_token_selected)
		_tokens_layer.add_child(node)
		_token_nodes[str(tok.get("id", ""))] = node

	_clear_children(_effects_layer, _effect_nodes)
	_effect_nodes.clear()
	for eff in _effects:
		var enode = MapEffect3DScript.new()
		enode.setup(eff, _cell_size)
		_effects_layer.add_child(enode)
		_effect_nodes[str(eff.get("id", ""))] = enode

	_clear_children(_zones_layer, _zone_nodes)
	_zone_nodes.clear()
	for zone in _zones:
		var znode = MapZone3DScript.new()
		znode.setup(zone, _cell_size)
		_zones_layer.add_child(znode)
		_zone_nodes[str(zone.get("id", ""))] = znode

func _clear_children(layer: Node, registry: Dictionary) -> void:
	for child in layer.get_children():
		child.queue_free()
	registry.clear()

func _viewport_aspect() -> float:
	var vp := _effective_viewport_size()
	return vp.x / maxf(vp.y, 1.0)

func _effective_viewport_size() -> Vector2:
	if size.x > 16 and size.y > 16:
		return size
	return Vector2(_viewport.size)

func _update_ortho_size() -> void:
	_camera.size = _base_ortho_size / zoom

func _fit_to_view() -> void:
	if _map_extent == Vector2.ZERO:
		return
	var aspect := _viewport_aspect()
	var fit_size := maxf(_map_extent.y * 0.5, _map_extent.x / (aspect * 2.0)) * 1.05
	_base_ortho_size = fit_size
	zoom = 1.0
	_update_ortho_size()
	_camera.position = Vector3(_map_extent.x * 0.5, CAM_HEIGHT, _map_extent.y * 0.5)
	_clamp_camera()
	zoom_changed.emit(zoom)

func _clamp_camera() -> void:
	var aspect := _viewport_aspect()
	var vis_w := _camera.size * 2.0 * aspect
	var vis_h := _camera.size * 2.0
	var cx := _camera.position.x
	var cz := _camera.position.z
	if vis_w >= _map_extent.x:
		cx = _map_extent.x * 0.5
	else:
		var min_x := vis_w * 0.5
		var max_x := _map_extent.x - vis_w * 0.5
		cx = clampf(cx, min_x, max_x)
	if vis_h >= _map_extent.y:
		cz = _map_extent.y * 0.5
	else:
		var min_z := vis_h * 0.5
		var max_z := _map_extent.y - vis_h * 0.5
		cz = clampf(cz, min_z, max_z)
	_camera.position.x = cx
	_camera.position.z = cz

func _apply_zoom(factor: float, anchor: Vector2) -> void:
	var old_zoom := zoom
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var world_before := _raycast_ground(_control_to_viewport(anchor))
	zoom = new_zoom
	_update_ortho_size()
	if world_before != Vector3.INF:
		var after_screen := _camera.unproject_position(world_before)
		var vp_anchor := _control_to_viewport(anchor)
		var delta := vp_anchor - after_screen
		_camera.position.x -= delta.x * _camera.size * 2.0 * _viewport_aspect() / _effective_viewport_size().x
		_camera.position.z -= delta.y * _camera.size * 2.0 / _effective_viewport_size().y
	_clamp_camera()
	zoom_changed.emit(zoom)

func _control_to_viewport(pos: Vector2) -> Vector2:
	var container_size := _viewport_container.size
	if container_size.x <= 1.0 or container_size.y <= 1.0:
		return pos
	var vp_size := Vector2(_viewport.size)
	return pos * (vp_size / container_size)

func _raycast_ground(viewport_pos: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(viewport_pos)
	var direction := _camera.project_ray_normal(viewport_pos)
	if absf(direction.y) < 0.0001:
		return Vector3.INF
	var t := -origin.y / direction.y
	if t < 0.0:
		return Vector3.INF
	return origin + direction * t

func _screen_to_grid(screen_pos: Vector2) -> Vector2:
	var world := _raycast_ground(_control_to_viewport(screen_pos))
	if world == Vector3.INF:
		return Vector2(-1, -1)
	return Vector2(
		(world.x - _cell_size * 0.5) / _cell_size,
		(world.z - _cell_size * 0.5) / _cell_size
	)

func _pick_token(screen_pos: Vector2) -> Node:
	var space := _world.get_world_3d().direct_space_state
	var vp_pos := _control_to_viewport(screen_pos)
	var from := _camera.project_ray_origin(vp_pos)
	var to := from + _camera.project_ray_normal(vp_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider is Node and _is_token_node(collider as Node):
		return collider as Node
	if collider is Node:
		var parent := (collider as Node).get_parent()
		if parent and _is_token_node(parent):
			return parent
	return null

func _is_token_node(node: Node) -> bool:
	return node.get_script() == MapToken3DScript

func _process(delta: float) -> void:
	if _token_drag:
		var world := _raycast_ground(_control_to_viewport(get_local_mouse_position()))
		if world != Vector3.INF:
			_token_drag.update_drag_world(world)
		return
	if _pan_velocity.length() < PAN_INERTIA_MIN:
		return
	_camera.position.x += _pan_velocity.x * delta
	_camera.position.z += _pan_velocity.y * delta
	_pan_velocity *= pow(PAN_INERTIA_DECAY, delta * 60.0)
	_clamp_camera()

func _on_token_drag_finished(token_id: String, gx: float, gy: float) -> void:
	token_moved.emit(token_id, gx, gy)

func _on_token_selected(token_id: String) -> void:
	_selected_token_id = token_id
	for tid in _token_nodes:
		var node = _token_nodes[tid]
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
				var picked: Node = _pick_token(mb.position)
				if picked and not readonly:
					_token_drag = picked
					picked.begin_drag()
					_pending_click = false
					_pan_dragging = false
				else:
					_pending_click = true
					_pan_dragging = false
					_pan_velocity = Vector2.ZERO
					_drag_start = mb.position
					_pan_start = _camera.position
					_last_pan_pos = mb.position
				accept_event()
			else:
				if _token_drag:
					_token_drag.end_drag()
					_token_drag = null
				elif _pending_click and not _pan_dragging:
					_handle_map_click(mb.position)
				_pan_dragging = false
				_pending_click = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = mb.pressed
			_pending_click = false
			_token_drag = null
			_pan_velocity = Vector2.ZERO
			if mb.pressed:
				_drag_start = mb.position
				_pan_start = _camera.position
				_last_pan_pos = mb.position
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _token_drag:
			var world := _raycast_ground(_control_to_viewport(motion.position))
			if world != Vector3.INF:
				_token_drag.update_drag_world(world)
			accept_event()
			return
		if _pending_click and not _pan_dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_pan_dragging = true
				_pending_click = false
		if _pan_dragging:
			var delta_pos := motion.position - _drag_start
			var aspect := _viewport_aspect()
			var vp := _effective_viewport_size()
			var world_dx := delta_pos.x * _camera.size * 2.0 * aspect / maxf(vp.x, 1.0)
			var world_dz := delta_pos.y * _camera.size * 2.0 / maxf(vp.y, 1.0)
			_camera.position.x = _pan_start.x - world_dx
			_camera.position.z = _pan_start.z - world_dz
			_pan_velocity = Vector2(
				-(motion.position.x - _last_pan_pos.x) * _camera.size * 2.0 * aspect / maxf(vp.x, 1.0),
				-(motion.position.y - _last_pan_pos.y) * _camera.size * 2.0 / maxf(vp.y, 1.0)
			) / maxf(get_process_delta_time(), 0.001)
			_last_pan_pos = motion.position
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
		var brush: int = maxi(0, int(session_tool.get("fogRadius", 1)))
		fog_revealed.emit(_fog_brush_cells(int(gx), int(gy), brush))
		return
	if mode == "fog_hide" and is_gm:
		var brush_h: int = maxi(0, int(session_tool.get("fogRadius", 1)))
		fog_hidden.emit(_fog_brush_cells(int(gx), int(gy), brush_h))
		return
	if mode in ["select", "pan"]:
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
		var node = _effect_nodes[effect_id]
		node.trigger()
	effect_trigger_requested.emit(effect_id)

func zoom_in() -> void:
	_apply_zoom(1.15, size * 0.5)

func zoom_out() -> void:
	_apply_zoom(1.0 / 1.15, size * 0.5)

func reset_zoom() -> void:
	_fit_to_view()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _viewport:
			_viewport.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
		if not map_data.is_empty():
			_clamp_camera()
