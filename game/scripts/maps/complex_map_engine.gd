extends Control
class_name ComplexMapEngine

## Moteur VTT mode complexe — SubViewport 3D, vue top-down type ARPG/XCOM.

signal token_moved(token_id: String, gx: float, gy: float)
signal map_clicked(gx: float, gy: float, tool: Dictionary)
signal effect_placed(effect: Dictionary)
signal effect_trigger_requested(effect_id: String)
signal fog_revealed(cells: Array)
signal zoom_changed(zoom_level: float)
signal token_selected(token_id: String)

const MapGround3DScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const MapToken3DScript := preload("res://scripts/maps/map_layers/map_token_3d.gd")
const MapEffect3DScript := preload("res://scripts/maps/map_layers/map_effect_3d.gd")
const MapFog3DScript := preload("res://scripts/maps/map_layers/map_fog_3d.gd")
const MapZone3DScript := preload("res://scripts/maps/map_layers/map_zone_3d.gd")

const MIN_ZOOM := 0.35
const MAX_ZOOM := 4.0
const DRAG_THRESHOLD := 4.0
const PAN_INERTIA_DECAY := 0.88
const PAN_INERTIA_MIN := 2.0
const CAMERA_ANGLE := 52.0

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
var _lighting_config: Dictionary = {}
var _map_width: int = 16
var _map_height: int = 12
var _cell_size: float = 1.0
var _map_extent: Vector2 = Vector2.ZERO
var _base_ortho_size: float = 10.0

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _scene_root: Node3D
var _ground: Node3D
var _elevations: Node3D
var _tokens_root: Node3D
var _effects_root: Node3D
var _zones_root: Node3D
var _fog_root: Node3D
var _sun: DirectionalLight3D
var _atmosphere: ColorRect
var _vignette: ColorRect

var _pan_dragging: bool = false
var _pending_click: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector3 = Vector3.ZERO
var _pan_velocity: Vector2 = Vector2.ZERO
var _last_pan_pos: Vector2 = Vector2.ZERO
var _dragging_token: MapToken3D = null
var _token_nodes: Dictionary = {}
var _effect_nodes: Dictionary = {}
var _zone_nodes: Dictionary = {}

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
	# Voir complex_map_engine_3d.gd : le parent doit recevoir `_gui_input`.
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.disable_3d = false
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.use_own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_viewport)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.25, 0.32)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 0.8
	world_env.environment = env
	_viewport.add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, -35, 0)
	_sun.light_color = Color(1.0, 0.94, 0.82)
	_sun.light_energy = 1.15
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 80.0
	_viewport.add_child(_sun)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation_degrees = Vector3(-CAMERA_ANGLE, 0, 0)
	_camera.current = true
	_camera.near = 0.05
	_camera.far = 500.0
	_viewport.add_child(_camera)

	_scene_root = Node3D.new()
	_scene_root.name = "Scene"
	_viewport.add_child(_scene_root)

	_ground = MapGround3DScript.new()
	_ground.name = "Ground"
	_scene_root.add_child(_ground)

	_elevations = Node3D.new()
	_elevations.name = "Elevations"
	_scene_root.add_child(_elevations)

	_zones_root = Node3D.new()
	_zones_root.name = "Zones"
	_scene_root.add_child(_zones_root)

	_tokens_root = Node3D.new()
	_tokens_root.name = "Tokens"
	_scene_root.add_child(_tokens_root)

	_effects_root = Node3D.new()
	_effects_root.name = "Effects"
	_scene_root.add_child(_effects_root)

	_fog_root = MapFog3DScript.new()
	_fog_root.name = "Fog"
	_scene_root.add_child(_fog_root)

	_atmosphere = ColorRect.new()
	_atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atmosphere.color = Color(0.05, 0.04, 0.08, 0.0)
	_atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_atmosphere)

	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.color = Color(0, 0, 0, 0.15)
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
	_lighting_config = MapData.get_lighting_config(p_map)
	_map_width = int(p_map.get("width", 16))
	_map_height = int(p_map.get("height", 12))
	_cell_size = float(_grid_config.get("size", 70)) * 0.1
	_loaded_map_id = new_id

	_load_ground()
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
	if _ground.has_method("configure"):
		_ground.configure(tex, _map_width, _map_height, _cell_size)
	_map_extent = Vector2(_map_width * _cell_size, _map_height * _cell_size)
	_base_ortho_size = maxf(_map_extent.x, _map_extent.y) * 0.55

func _apply_camera_perspective() -> void:
	var persp := MapData.get_perspective(map_data)
	match persp:
		"isometric":
			_camera.rotation_degrees = Vector3(-58, 45, 0)
		"perspective":
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.rotation_degrees = Vector3(-48, 0, 0)
			_camera.fov = 38.0
		_:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.rotation_degrees = Vector3(-CAMERA_ANGLE, 0, 0)

func _apply_lighting() -> void:
	if not _lighting_config.get("enabled", false):
		return
	var dir: String = str(_lighting_config.get("direction", "nw"))
	match dir:
		"ne":
			_sun.rotation_degrees = Vector3(-55, 35, 0)
		"sw":
			_sun.rotation_degrees = Vector3(-55, -145, 0)
		"se":
			_sun.rotation_degrees = Vector3(-55, 145, 0)
		_:
			_sun.rotation_degrees = Vector3(-55, -35, 0)
	_sun.light_energy = 0.85 + float(_lighting_config.get("intensity", 0.35))

func _apply_atmosphere() -> void:
	var atmo: Dictionary = map_data.get("atmosphere", {}) if map_data.get("atmosphere") is Dictionary else {}
	if atmo is Dictionary and atmo.get("enabled", false):
		var tint := Color.html(str(atmo.get("tint", "#1a1410")))
		tint.a = float(atmo.get("opacity", 0.25))
		_atmosphere.color = tint
		_vignette.color = Color(0, 0, 0, float(atmo.get("vignette", 0.15)))
	else:
		_atmosphere.color = Color(0.04, 0.03, 0.06, 0.06)
		_vignette.color = Color(0, 0, 0, 0.12 if is_gm else 0.2)

func _apply_view_state(view_state: Dictionary) -> void:
	if view_state.is_empty():
		return
	zoom = clampf(float(view_state.get("zoom", zoom)), MIN_ZOOM, MAX_ZOOM)
	var cx := _map_extent.x * 0.5
	var cz := _map_extent.y * 0.5
	_camera.position = Vector3(
		cx + float(view_state.get("panX", 0)),
		_camera.position.y if _camera.position.y > 0.1 else _camera_height(),
		cz + float(view_state.get("panY", 0))
	)
	_apply_camera_zoom()

func get_view_state() -> Dictionary:
	var cx := _map_extent.x * 0.5
	var cz := _map_extent.y * 0.5
	return {
		"zoom": zoom,
		"panX": _camera.position.x - cx,
		"panY": _camera.position.z - cz,
	}

func _rebuild_layers() -> void:
	var fog_on := bool(map_data.get("fogEnabled", true))
	_rebuild_elevations()
	if _fog_root.has_method("configure"):
		_fog_root.configure(_map_width, _map_height, _cell_size, _fog_revealed, is_gm, fog_on)

	_clear_children(_tokens_root, _token_nodes)
	_token_nodes.clear()
	for tok in _tokens:
		var node: MapToken3D = MapToken3DScript.new()
		node.setup(tok, _cell_size, _party, readonly)
		node.snap_to_grid = snap_to_grid
		node.set_selected(str(tok.get("id", "")) == _selected_token_id)
		node.drag_finished.connect(_on_token_drag_finished)
		node.selected.connect(_on_token_selected)
		_tokens_root.add_child(node)
		_token_nodes[str(tok.get("id", ""))] = node

	_clear_children(_effects_root, _effect_nodes)
	_effect_nodes.clear()
	for eff in _effects:
		var enode: MapEffect3D = MapEffect3DScript.new()
		enode.setup(eff, _cell_size)
		_effects_root.add_child(enode)
		_effect_nodes[str(eff.get("id", ""))] = enode

	_clear_children(_zones_root, _zone_nodes)
	_zone_nodes.clear()
	for zone in _zones:
		var znode: MapZone3D = MapZone3DScript.new()
		znode.setup(zone, _cell_size)
		_zones_root.add_child(znode)
		_zone_nodes[str(zone.get("id", ""))] = znode

func _rebuild_elevations() -> void:
	for child in _elevations.get_children():
		child.queue_free()
	var layers: Array = MapData.get_elevation_layers(map_data)
	for layer_def in layers:
		if not layer_def is Dictionary:
			continue
		var path: String = str(layer_def.get("image", "")).strip_edges()
		if path.is_empty():
			continue
		var tex := MapData.load_background_texture({"backgroundImage": path})
		if tex == null:
			continue
		var plane := PlaneMesh.new()
		var w := _map_extent.x
		var h := _map_extent.y
		plane.size = Vector2(w, h)
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		var elev_y := float(layer_def.get("elevation", 0.15)) * _cell_size * 3.0
		mi.position = Vector3(w * 0.5, elev_y, h * 0.5)
		mi.rotation_degrees = Vector3(-90, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, float(layer_def.get("opacity", 0.92)))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_elevations.add_child(mi)

func _clear_children(layer: Node, registry: Dictionary) -> void:
	for child in layer.get_children():
		child.queue_free()
	registry.clear()

func _camera_height() -> float:
	return maxf(_map_extent.x, _map_extent.y) * 0.85

func _apply_camera_zoom() -> void:
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera.size = _base_ortho_size / zoom
	else:
		var dist := _camera_height() / zoom
		_camera.position.y = dist

func _fit_to_view() -> void:
	if _map_extent == Vector2.ZERO:
		return
	zoom = 1.0
	_camera.position = Vector3(_map_extent.x * 0.5, _camera_height(), _map_extent.y * 0.5 + _map_extent.y * 0.08)
	_apply_camera_zoom()
	_clamp_camera()
	zoom_changed.emit(zoom)

func _clamp_camera() -> void:
	if _map_extent == Vector2.ZERO:
		return
	var margin := _base_ortho_size / zoom * 0.35
	var min_x := -margin
	var min_z := -margin
	var max_x := _map_extent.x + margin
	var max_z := _map_extent.y + margin
	_camera.position.x = clampf(_camera.position.x, min_x, max_x)
	_camera.position.z = clampf(_camera.position.z, min_z, max_z)

func _apply_zoom(factor: float, anchor: Vector2) -> void:
	var old_zoom := zoom
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var world_before := _screen_to_world(anchor)
	zoom = new_zoom
	_apply_camera_zoom()
	var world_after := _screen_to_world(anchor)
	var delta := world_before - world_after
	_camera.position.x += delta.x
	_camera.position.z += delta.z
	_clamp_camera()
	zoom_changed.emit(zoom)

func _to_viewport_pos(screen_pos: Vector2) -> Vector2:
	var vp := Vector2(_viewport.size)
	var ctrl := size
	if ctrl.x < 1.0 or ctrl.y < 1.0 or vp.x < 1.0 or vp.y < 1.0:
		return screen_pos
	return screen_pos * (vp / ctrl)

func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var vp_pos := _to_viewport_pos(screen_pos)
	var from := _camera.project_ray_origin(vp_pos)
	var dir := _camera.project_ray_normal(vp_pos)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	var t := -from.y / dir.y
	if t < 0:
		t = 0.0
	return from + dir * t

func _screen_to_grid(screen_pos: Vector2) -> Vector2:
	var world := _screen_to_world(screen_pos)
	return Vector2(
		world.x / _cell_size - 0.5,
		world.z / _cell_size - 0.5
	)

func _raycast_token(screen_pos: Vector2) -> MapToken3D:
	var space := _viewport.world_3d.direct_space_state
	var vp_pos := _to_viewport_pos(screen_pos)
	var from := _camera.project_ray_origin(vp_pos)
	var to := from + _camera.project_ray_normal(vp_pos) * 200.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider is MapToken3D:
		return collider as MapToken3D
	if collider is CollisionShape3D and collider.get_parent() is MapToken3D:
		return collider.get_parent() as MapToken3D
	return null

func _process(delta: float) -> void:
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
				var tok := _raycast_token(mb.position)
				if tok and not readonly:
					_dragging_token = tok
					tok.begin_drag()
					_pending_click = false
					_pan_dragging = false
				else:
					_dragging_token = null
					_pending_click = true
					_pan_dragging = false
					_pan_velocity = Vector2.ZERO
					_drag_start = mb.position
					_pan_start = _camera.position
					_last_pan_pos = mb.position
				accept_event()
			else:
				if _dragging_token:
					_dragging_token.end_drag()
					_dragging_token = null
				elif _pending_click and not _pan_dragging:
					_handle_map_click(mb.position)
				_pan_dragging = false
				_pending_click = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = mb.pressed
			_pending_click = false
			_dragging_token = null
			_pan_velocity = Vector2.ZERO
			if mb.pressed:
				_drag_start = mb.position
				_pan_start = _camera.position
				_last_pan_pos = mb.position
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging_token:
			var world := _screen_to_world(motion.position)
			_dragging_token.update_drag_world(world)
			accept_event()
			return
		if _pending_click and not _pan_dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_pan_dragging = true
				_pending_click = false
		if _pan_dragging:
			var delta_pos := motion.position - _drag_start
			_camera.position = _pan_start + Vector3(delta_pos.x * -0.015 / zoom, 0, delta_pos.y * -0.015 / zoom)
			_pan_velocity = (motion.position - _last_pan_pos) * Vector2(-0.015, -0.015) / zoom
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
	if gx < 0 or gy < 0 or gx >= _map_width or gy >= _map_height:
		return

	var mode: String = session_tool.get("mode", "member")
	if mode == "fog" and is_gm:
		fog_revealed.emit(_fog_brush_cells(int(gx), int(gy), 1))
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
		_effect_nodes[effect_id].trigger()
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
