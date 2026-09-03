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

## Signaux bas niveau consommés par l'éditeur (`editor_mode = true`).
## Le moteur ne décide plus rien : il traduit l'entrée souris en coordonnées
## grille et laisse l'éditeur appliquer l'outil courant.
signal editor_pointer_pressed(grid_pos: Vector2, screen_pos: Vector2, button: int, mods: Dictionary)
signal editor_pointer_moved(grid_pos: Vector2, screen_pos: Vector2, mods: Dictionary)
signal editor_pointer_released(grid_pos: Vector2, screen_pos: Vector2, button: int, mods: Dictionary)
signal view_changed()
signal area_hovered(area: Dictionary)
signal area_clicked(area: Dictionary)

const MapGround3DScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const MapGrid3DScript := preload("res://scripts/maps/map_layers/map_grid_3d.gd")
const MapToken3DScript := preload("res://scripts/maps/map_layers/map_token_3d.gd")
const MapEffect3DScript := preload("res://scripts/maps/map_layers/map_effect_3d.gd")
const MapZone3DScript := preload("res://scripts/maps/map_layers/map_zone_3d.gd")
const MapFog3DScript := preload("res://scripts/maps/map_layers/map_fog_3d.gd")
const MapElevations3DScript := preload("res://scripts/maps/map_layers/map_elevations_3d.gd")
const MapWalls3DScript := preload("res://scripts/maps/map_layers/map_walls_3d.gd")
const MapLights3DScript := preload("res://scripts/maps/map_layers/map_lights_3d.gd")
const MapProps3DScript := preload("res://scripts/maps/map_layers/map_props_3d.gd")
const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")
const MapAreasOverlayScript := preload("res://scripts/maps/map_areas_overlay.gd")

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
## Quand vrai, l'entrée souris est relayée à l'éditeur au lieu d'être
## interprétée par le moteur (drag de token, clic outil…).
var editor_mode: bool = false

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
var _base_camera_height: float = CAM_HEIGHT

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
var _props_layer: Node3D
var _walls_layer: Node3D
var _lights_layer: Node3D
var _sun: DirectionalLight3D
var _atmosphere: ColorRect
var _vignette: ColorRect
var _areas_overlay: Control
var _token_overlay: Control
var _overlay_icons: Dictionary = {}

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
var _style_cfg: Dictionary = {}
var _hovered_area_id: String = ""

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)
	_build_viewport_tree()
	mouse_exited.connect(_clear_area_hover)

func _clear_area_hover() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	if _hovered_area_id.is_empty():
		return
	_hovered_area_id = ""
	if _areas_overlay and _areas_overlay.has_method("set_hovered"):
		_areas_overlay.set_hovered("")
	area_hovered.emit({})

func _build_viewport_tree() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	# IGNORE : sinon le container avale les clics et le parent ne reçoit jamais
	# `_gui_input` (pan, pose, drag tokens, pointeur éditeur). Le picking 3D
	# est fait ici par raycast, pas via physics picking du SubViewport.
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.disable_3d = false
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.physics_object_picking = false
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

	_effects_layer = Node3D.new()
	_effects_layer.name = "Effects"
	_world.add_child(_effects_layer)

	_props_layer = MapProps3DScript.new()
	_props_layer.name = "Props"
	_world.add_child(_props_layer)

	_walls_layer = MapWalls3DScript.new()
	_walls_layer.name = "Walls"
	_world.add_child(_walls_layer)

	_lights_layer = MapLights3DScript.new()
	_lights_layer.name = "Lights"
	_world.add_child(_lights_layer)

	_fog_layer = MapFog3DScript.new()
	_fog_layer.name = "Fog"
	_world.add_child(_fog_layer)

	# Tokens en dernier calque 3D : personnages toujours au-dessus de la carte.
	_tokens_layer = Node3D.new()
	_tokens_layer.name = "Tokens"
	_world.add_child(_tokens_layer)

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

	_areas_overlay = MapAreasOverlayScript.new()
	_areas_overlay.name = "AreasOverlay"
	add_child(_areas_overlay)
	view_changed.connect(func():
		if _areas_overlay:
			_areas_overlay.queue_redraw()
	)

	# Calque 2D des personnages : toujours au-dessus de la carte illustrée.
	_token_overlay = Control.new()
	_token_overlay.name = "TokenOverlay"
	_token_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_token_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_token_overlay.z_index = 30
	add_child(_token_overlay)

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
	_style_cfg = MapRenderStyleScript.config(p_map)
	_loaded_map_id = new_id
	# Aimantation : libre en diorama, à la case en VTT (sauf override explicite).
	if not p_tool.has("forceSnap"):
		snap_to_grid = not MapRenderStyleScript.is_diorama(p_map)

	_load_ground()
	_load_elevations()
	_apply_camera_perspective()
	_apply_lighting()
	_apply_atmosphere()
	if _areas_overlay and _areas_overlay.has_method("configure"):
		# En éditeur, l'overlay dédié de l'éditeur dessine déjà les lieux.
		if editor_mode:
			_areas_overlay.configure(null, {})
		else:
			_areas_overlay.configure(self, map_data)
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
	var unshaded := MapRenderStyleScript.is_diorama(map_data)
	if _ground.has_method("configure"):
		_ground.configure(tex, w, h, _cell_size, unshaded)
	_map_extent = Vector2(float(w) * _cell_size, float(h) * _cell_size)
	_base_ortho_size = maxf(_map_extent.x, _map_extent.y) * 0.55

func _load_elevations() -> void:
	if _elevations_layer and _elevations_layer.has_method("configure"):
		_elevations_layer.configure(map_data, _cell_size)

func _apply_camera_perspective() -> void:
	var cfg := _style_cfg if not _style_cfg.is_empty() else MapRenderStyleScript.config(map_data)
	if bool(cfg.get("perspective", false)):
		# Diorama : caméra perspective inclinée → parallaxe au pan.
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.rotation_degrees = Vector3(float(cfg.get("tilt", -52.0)), 0.0, 0.0)
		_camera.fov = float(cfg.get("fov", 34.0))
		_camera.position.y = _style_camera_height()
		_base_camera_height = _camera.position.y
		_update_ortho_size()
		return
	# VTT : vue tactique orthographique. On ignore le tilt historique (beaucoup
	# de cartes l'ont reçu par défaut à la création) pour que VTT ≠ diorama.
	var persp := MapData.get_perspective(map_data)
	if persp == MapData.PERSPECTIVE_ISOMETRIC:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.rotation_degrees = Vector3(-58.0, 45.0, 0.0)
		_camera.position.y = CAM_HEIGHT
	else:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_camera.position.y = CAM_HEIGHT
	_update_ortho_size()

func _apply_lighting() -> void:
	var cfg := _style_cfg if not _style_cfg.is_empty() else MapRenderStyleScript.config(map_data)
	if not bool(cfg.get("shadows", true)):
		# Diorama : pas d'ombres portées. Soft fill pour ne pas noircir les
		# matériaux encore éclairés (lumières ponctuelles, tokens VTT…).
		_sun.visible = true
		_sun.shadow_enabled = false
		_sun.light_energy = 0.55
		_sun.rotation_degrees = Vector3(-62.0, 25.0, 0.0)
		return
	_sun.visible = true
	_sun.shadow_enabled = true
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
	var is_diorama := MapRenderStyleScript.is_diorama(map_data)
	var illustrated := not str(map_data.get("backgroundImage", "")).strip_edges().is_empty()
	if atmo is Dictionary and atmo.get("enabled", false):
		var tint := Color.html(str(atmo.get("tint", "#1a1410")))
		# En diorama, plafonner le voile pour ne pas noyer l'illustration.
		var opacity := float(atmo.get("opacity", 0.25))
		if is_diorama:
			opacity = minf(opacity, 0.10)
		if illustrated:
			opacity = minf(opacity, 0.04)
		tint.a = opacity
		_atmosphere.color = tint
		var vig := float(atmo.get("vignette", 0.15))
		_vignette.color = Color(0, 0, 0, minf(vig, 0.08) if illustrated else (minf(vig, 0.18) if is_diorama else vig))
	elif illustrated:
		# Fond peint : pas de voile — on lit l'image telle quelle.
		_atmosphere.color = Color(0, 0, 0, 0.0)
		_vignette.color = Color(0, 0, 0, 0.04)
	elif is_diorama:
		_atmosphere.color = Color(0.08, 0.06, 0.10, 0.06)
		_vignette.color = Color(0, 0, 0, 0.12)
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
	var is_diorama := MapRenderStyleScript.is_diorama(map_data)
	var cfg := _style_cfg if not _style_cfg.is_empty() else MapRenderStyleScript.config(map_data)

	if _grid_layer.has_method("configure"):
		var grid_cfg := _grid_config.duplicate(true)
		# Grille masquée par défaut en diorama (sauf si explicitement affichée).
		if is_diorama and not bool(grid_cfg.get("show", false)):
			grid_cfg["opacity"] = 0.0
		elif not grid_cfg.has("opacity"):
			grid_cfg["opacity"] = 0.14
		_grid_layer.configure(grid_cfg, w, h, _cell_size)

	if _fog_layer.has_method("configure"):
		_fog_layer.configure(w, h, _cell_size, _fog_revealed, is_gm, fog_on, is_diorama)

	if _props_layer and _props_layer.has_method("configure"):
		var props = map_data.get("props", [])
		_props_layer.configure(props if props is Array else [], _cell_size, map_data)

	if _walls_layer and _walls_layer.has_method("configure"):
		var walls = map_data.get("walls", [])
		var show_walls := bool(cfg.get("volumetricWalls", true))
		_walls_layer.configure(walls if walls is Array else [], _cell_size, show_walls)

	if _lights_layer and _lights_layer.has_method("configure"):
		var sources = _lighting_config.get("sources", [])
		_lights_layer.configure(sources if sources is Array else [], _cell_size)
		# En diorama : lumières douces sans ombres.
		if is_diorama and _lights_layer.has_method("set_shadows_enabled"):
			_lights_layer.set_shadows_enabled(false)

	var elevations_ok := not is_diorama
	if _elevations_layer:
		_elevations_layer.visible = elevations_ok

	_clear_children(_tokens_layer, _token_nodes)
	_token_nodes.clear()
	for tok in _tokens:
		if bool(tok.get("hidden", false)):
			continue
		var node = MapToken3DScript.new()
		# Portrait / silhouette en pied dès qu'une image est dispo.
		# Billboard caméra : visible même en vue de dessus.
		var has_image := not str(tok.get("image", "")).strip_edges().is_empty()
		if not has_image and str(tok.get("kind", "")) == "member":
			var mid := str(tok.get("memberId", ""))
			for m_variant in _party:
				if str((m_variant as Dictionary).get("id", "")) == mid:
					has_image = not str((m_variant as Dictionary).get("portrait", (m_variant as Dictionary).get("image", ""))).strip_edges().is_empty()
					break
		var use_cutout := has_image or (is_diorama and str(map_data.get("backgroundImage", "")).strip_edges().is_empty())
		node.setup(tok, _cell_size, _party, readonly, use_cutout)
		node.snap_to_grid = snap_to_grid
		node.set_selected(str(tok.get("id", "")) == _selected_token_id)
		node.drag_finished.connect(_on_token_drag_finished)
		node.selected.connect(_on_token_selected)
		_tokens_layer.add_child(node)
		_token_nodes[str(tok.get("id", ""))] = node

	_rebuild_token_overlay()

	_clear_children(_effects_layer, _effect_nodes)
	_effect_nodes.clear()
	for eff in _effects:
		if bool(eff.get("hidden", false)):
			continue
		var enode = MapEffect3DScript.new()
		enode.setup(eff, _cell_size)
		_effects_layer.add_child(enode)
		_effect_nodes[str(eff.get("id", ""))] = enode

	_clear_children(_zones_layer, _zone_nodes)
	_zone_nodes.clear()
	for zone in _zones:
		if bool(zone.get("hidden", false)):
			continue
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
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		# En perspective, le zoom rapproche / éloigne la caméra du sol.
		_camera.position.y = maxf(0.5, _base_camera_height / maxf(zoom, 0.001))
	else:
		_camera.size = _base_ortho_size / zoom
	view_changed.emit()

## Hauteur de caméra imposée par le style, avant tout recadrage.
func _style_camera_height() -> float:
	var cfg := _style_cfg if not _style_cfg.is_empty() else MapRenderStyleScript.config(map_data)
	return CAM_HEIGHT * (0.72 if bool(cfg.get("perspective", false)) else 0.85)

# ===========================================================================
# Géométrie de vue
# ===========================================================================
#
# Toute la navigation (déplacement, zoom, cadrage, mini-carte) a besoin de
# savoir **combien de monde couvre un pixel au niveau du sol**. En
# orthographique, `Camera3D.size` suffisait. En perspective il ne veut plus
# rien dire, et l'inclinaison étire le sol dans la profondeur.
#
# Plutôt que de refaire la trigonométrie pour chaque projection et chaque
# inclinaison, on **mesure** : deux lancers de rayon sur le plan du sol
# donnent la réponse exacte, en orthographique comme en perspective.

const _GROUND_PROBE_PX := 100.0

## Estimation analytique (fallback si les rayons échouent — viewport pas prêt).
## En perspective, `Camera3D.size` vaut ~1.0 et ne doit JAMAIS servir d'échelle.
func _estimate_ground_span_per_pixel() -> Vector2:
	var vp := _effective_viewport_size()
	var px_h := maxf(vp.y, 1.0)
	var px_w := maxf(vp.x, 1.0)
	if _camera != null and _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var world_h := 2.0 * maxf(_camera.position.y, 0.5) * tan(deg_to_rad(_camera.fov * 0.5))
		# Inclinaison : le sol est plus « long » dans la profondeur que le FOV
		# vertical pur — on élargit un peu pour rester du bon ordre de grandeur.
		var tilt_abs := absf(_camera.rotation_degrees.x)
		if tilt_abs < 89.0:
			world_h /= maxf(sin(deg_to_rad(tilt_abs)), 0.35)
		return Vector2(world_h * (px_w / px_h) / px_w, world_h / px_h)
	var ortho_h := (_camera.size if _camera else 1.0) * 2.0
	return Vector2(ortho_h * (px_w / px_h) / px_w, ortho_h / px_h)

## Unités monde couvertes par un pixel écran, au niveau du sol (x, z).
func _ground_span_per_pixel() -> Vector2:
	var fallback := _estimate_ground_span_per_pixel()
	if _camera == null:
		return fallback
	var vp := _effective_viewport_size()
	if vp.x < 8.0 or vp.y < 8.0:
		return fallback
	var center := vp * 0.5
	var origin := _raycast_ground(_control_to_viewport(center))
	var right := _raycast_ground(_control_to_viewport(center + Vector2(_GROUND_PROBE_PX, 0.0)))
	var down := _raycast_ground(_control_to_viewport(center + Vector2(0.0, _GROUND_PROBE_PX)))
	if origin == Vector3.INF or right == Vector3.INF or down == Vector3.INF:
		return fallback
	var span := Vector2(
		absf(right.x - origin.x) / _GROUND_PROBE_PX,
		absf(down.z - origin.z) / _GROUND_PROBE_PX
	)
	if span.x < 0.00001 or span.y < 0.00001:
		return fallback
	return span

## Étendue de sol visible à l'écran, en unités monde.
func _visible_ground_size() -> Vector2:
	var vp := _effective_viewport_size()
	var span := _ground_span_per_pixel()
	return Vector2(span.x * vp.x, span.y * vp.y)

## Point du sol visé au centre de l'écran.
##
## Sous une caméra inclinée ce n'est **pas** la position de la caméra : c'est
## ce point-là qu'il faut recentrer et borner, pas la caméra elle-même.
func _ground_focus() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	var world := _raycast_ground(_control_to_viewport(_effective_viewport_size() * 0.5))
	if world == Vector3.INF:
		return Vector2(_camera.position.x, _camera.position.z)
	return Vector2(world.x, world.z)

## Déplace la caméra pour que le centre de l'écran vise ce point du sol.
func _center_focus_on(target: Vector2) -> void:
	if _camera == null:
		return
	var focus := _ground_focus()
	_camera.position.x += target.x - focus.x
	_camera.position.z += target.y - focus.y

func _fit_to_view() -> void:
	if _map_extent == Vector2.ZERO or _camera == null:
		return
	zoom = 1.0
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		# Hauteur ∝ étendue de carte : une carte 96×96 doit être plus haute
		# qu'une 20×14. On part d'une hauteur de style, on mesure, on scale.
		_camera.position.y = maxf(_style_camera_height(), 1.0)
		_center_focus_on(_map_extent * 0.5)
		var visible := _visible_ground_size()
		if visible.x > 0.001 and visible.y > 0.001:
			var needed := maxf(_map_extent.x / visible.x, _map_extent.y / visible.y)
			_camera.position.y *= maxf(needed, 0.01) * 1.08
		else:
			# Viewport pas prêt : estimation FOV directe.
			var aspect := maxf(_viewport_aspect(), 0.1)
			var target_h := maxf(_map_extent.y, _map_extent.x / aspect) * 1.08
			var half := tan(deg_to_rad(_camera.fov * 0.5))
			var tilt_abs := absf(_camera.rotation_degrees.x)
			var denom := half * maxf(sin(deg_to_rad(tilt_abs)), 0.35)
			_camera.position.y = target_h / maxf(denom * 2.0, 0.01)
		_base_camera_height = _camera.position.y
	else:
		var aspect := _viewport_aspect()
		_base_ortho_size = maxf(_map_extent.y * 0.5, _map_extent.x / (aspect * 2.0)) * 1.05
		_camera.size = _base_ortho_size
	_center_focus_on(_map_extent * 0.5)
	_clamp_camera()
	zoom_changed.emit(zoom)

func _clamp_camera() -> void:
	if _map_extent == Vector2.ZERO:
		return
	var visible := _visible_ground_size()
	var focus := _ground_focus()
	# L'écart caméra ↔ point visé est constant : on borne le point visé puis on
	# reporte l'écart, ce qui reste juste même avec une caméra inclinée.
	var offset := Vector2(_camera.position.x, _camera.position.z) - focus
	var target := focus
	if visible.x >= _map_extent.x:
		target.x = _map_extent.x * 0.5
	else:
		target.x = clampf(target.x, visible.x * 0.5, _map_extent.x - visible.x * 0.5)
	if visible.y >= _map_extent.y:
		target.y = _map_extent.y * 0.5
	else:
		target.y = clampf(target.y, visible.y * 0.5, _map_extent.y - visible.y * 0.5)
	_camera.position.x = target.x + offset.x
	_camera.position.z = target.y + offset.y
	view_changed.emit()

func _apply_zoom(factor: float, anchor: Vector2) -> void:
	var old_zoom := zoom
	var new_zoom := clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var world_before := _raycast_ground(_control_to_viewport(anchor))
	zoom = new_zoom
	_update_ortho_size()
	# On replace la caméra pour que le point du sol sous le curseur y reste.
	if world_before != Vector3.INF:
		var world_after := _raycast_ground(_control_to_viewport(anchor))
		if world_after != Vector3.INF:
			_camera.position.x += world_before.x - world_after.x
			_camera.position.z += world_before.z - world_after.z
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

# ===========================================================================
# API publique de projection — utilisée par l'overlay 2D de l'éditeur
# ===========================================================================

func get_cell_size() -> float:
	return _cell_size

func get_map_extent() -> Vector2:
	return _map_extent

## Coordonnées grille → position en pixels dans ce Control.
func grid_to_screen(gx: float, gy: float, height: float = 0.0) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	var world := Vector3(
		gx * _cell_size + _cell_size * 0.5,
		height * _cell_size,
		gy * _cell_size + _cell_size * 0.5
	)
	if _camera.is_position_behind(world):
		return Vector2(-100000.0, -100000.0)
	return _viewport_to_control(_camera.unproject_position(world))

## Position en pixels dans ce Control → coordonnées grille (float).
func screen_to_grid_pos(pos: Vector2) -> Vector2:
	return _screen_to_grid(pos)

func _viewport_to_control(pos: Vector2) -> Vector2:
	if _viewport == null or _viewport_container == null:
		return pos
	var vp_size := Vector2(_viewport.size)
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		return pos
	var container_size := _viewport_container.size
	if container_size.x <= 1.0 or container_size.y <= 1.0:
		return pos
	return pos * (container_size / vp_size)

## Rectangle de la carte actuellement visible, en coordonnées grille.
func visible_grid_rect() -> Rect2:
	if _camera == null or _cell_size <= 0.0:
		return Rect2()
	var visible := _visible_ground_size()
	var focus := _ground_focus()
	var origin := (focus - visible * 0.5) / _cell_size
	return Rect2(origin, visible / _cell_size)

func center_on_grid(gx: float, gy: float) -> void:
	if _camera == null:
		return
	_center_focus_on(Vector2(
		gx * _cell_size + _cell_size * 0.5,
		gy * _cell_size + _cell_size * 0.5
	))
	_clamp_camera()

## Recadre la caméra sur un rectangle exprimé en cases.
func focus_grid_rect(rect: Rect2, margin: float = 1.6) -> void:
	if _camera == null or rect.size == Vector2.ZERO:
		return
	var extent := rect.size * _cell_size * margin
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		# Même logique que _fit_to_view, à l'échelle du rectangle.
		_camera.position.y = maxf(_style_camera_height(), 1.0)
		_center_focus_on(Vector2(
			(rect.get_center().x) * _cell_size,
			(rect.get_center().y) * _cell_size
		))
		var visible := _visible_ground_size()
		if visible.x > 0.001 and visible.y > 0.001:
			var needed := maxf(extent.x / visible.x, extent.y / visible.y)
			_camera.position.y *= maxf(needed, 0.01)
			_base_camera_height = _camera.position.y
			zoom = 1.0
	else:
		var aspect := maxf(_viewport_aspect(), 0.1)
		var needed := maxf(extent.y * 0.5, extent.x / (aspect * 2.0))
		if needed > 0.0 and _base_ortho_size > 0.0:
			zoom = clampf(_base_ortho_size / needed, MIN_ZOOM, MAX_ZOOM)
			_update_ortho_size()
	center_on_grid(rect.get_center().x - 0.5, rect.get_center().y - 0.5)
	zoom_changed.emit(zoom)
	view_changed.emit()

## Repositionne le nœud 3D d'un élément sans reconstruire la scène (drag live).
func set_element_position(element_id: String, gx: float, gy: float) -> void:
	var node: Node3D = null
	if _token_nodes.has(element_id):
		node = _token_nodes[element_id]
	elif _effect_nodes.has(element_id):
		node = _effect_nodes[element_id]
	elif _zone_nodes.has(element_id):
		node = _zone_nodes[element_id]
	if node == null:
		if _props_layer and _props_layer.has_method("set_prop_position"):
			_props_layer.set_prop_position(element_id, gx, gy)
		return
	node.position.x = gx * _cell_size + _cell_size * 0.5
	node.position.z = gy * _cell_size + _cell_size * 0.5
	if node.has_method("get_token_id"):
		node.token_data["x"] = gx
		node.token_data["y"] = gy

func has_element_node(element_id: String) -> bool:
	if _props_layer and _props_layer.has_method("has_prop") and _props_layer.has_prop(element_id):
		return true
	return _token_nodes.has(element_id) or _effect_nodes.has(element_id) or _zone_nodes.has(element_id)

func set_editor_mode(on: bool) -> void:
	editor_mode = on
	if on:
		_token_drag = null
		_pending_click = false
	if _areas_overlay and _areas_overlay.has_method("configure"):
		if on:
			_areas_overlay.configure(null, {})
		else:
			_areas_overlay.configure(self, map_data)

static func _mods(event: InputEvent) -> Dictionary:
	return {
		"shift": event.is_shift_pressed(),
		"ctrl": event.is_ctrl_pressed(),
		"alt": event.is_alt_pressed(),
	}

func _pick_token(screen_pos: Vector2) -> Node:
	# Calque 2D d'abord : la silhouette à l'écran, pas la petite capsule 3D au sol.
	var overlay_hit := _pick_token_from_overlay(screen_pos)
	if overlay_hit != null:
		return overlay_hit
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

## Hit-test sur les TextureRect du calque perso (coordonnées locales du moteur).
func _pick_token_from_overlay(screen_pos: Vector2) -> Node:
	if _overlay_icons.is_empty():
		return null
	var best: Node = null
	var best_area := INF
	for tid in _overlay_icons:
		var entry = _overlay_icons[tid]
		var icon: TextureRect = entry["icon"] if entry is Dictionary else entry
		var node = _token_nodes.get(tid)
		if icon == null or node == null:
			continue
		var rect := Rect2(icon.position, icon.size)
		if not rect.has_point(screen_pos):
			continue
		# Ignore les pixels vraiment transparents du détourage.
		if icon.texture != null and icon.size.x > 1.0 and icon.size.y > 1.0:
			var img: Image = icon.texture.get_image()
			if img != null:
				var u := clampf((screen_pos.x - rect.position.x) / rect.size.x, 0.0, 1.0)
				var v := clampf((screen_pos.y - rect.position.y) / rect.size.y, 0.0, 1.0)
				var px := clampi(int(u * float(img.get_width())), 0, img.get_width() - 1)
				var py := clampi(int(v * float(img.get_height())), 0, img.get_height() - 1)
				if img.get_pixel(px, py).a < 0.25:
					continue
		var area := rect.get_area()
		if area < best_area:
			best_area = area
			best = node
	return best

func _is_token_node(node: Node) -> bool:
	return node is MapToken3D or node.get_script() == MapToken3DScript

func _process(delta: float) -> void:
	_sync_token_overlay_positions()
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

func _rebuild_token_overlay() -> void:
	if _token_overlay == null:
		return
	for child in _token_overlay.get_children():
		child.queue_free()
	_overlay_icons.clear()
	move_child(_token_overlay, get_child_count() - 1)
	# Texture déjà alpha durci : pas de material shader (évite les fantômes).
	for tid in _token_nodes:
		var node = _token_nodes[tid]
		if node == null or not node.has_method("uses_overlay_layer") or not node.uses_overlay_layer():
			continue
		var tex: Texture2D = node.get_overlay_texture()
		if tex == null:
			continue
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.modulate = Color(1, 1, 1, 1)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Ombre/contour 2D derrière le perso pour le détacher du fond illustré.
		var outline := TextureRect.new()
		outline.texture = tex
		outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		outline.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.modulate = Color(0, 0, 0, 0.9)
		outline.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_token_overlay.add_child(outline)
		_token_overlay.add_child(icon)
		_overlay_icons[tid] = {"icon": icon, "outline": outline}
	_sync_token_overlay_positions()

func _sync_token_overlay_positions() -> void:
	if _token_overlay == null or _camera == null or _overlay_icons.is_empty():
		return
	var vp_size := Vector2(_viewport.size)
	if vp_size.x < 1.0 or vp_size.y < 1.0 or size.x < 1.0 or size.y < 1.0:
		return
	var scale := size / vp_size
	var origin_vp: Vector2 = _camera.unproject_position(Vector3.ZERO)
	var cell_vp: Vector2 = _camera.unproject_position(Vector3(_cell_size, 0.0, 0.0))
	var px_per_cell := absf((cell_vp.x - origin_vp.x) * scale.x)
	if px_per_cell < 4.0:
		px_per_cell = 48.0
	for tid in _overlay_icons:
		var entry = _overlay_icons[tid]
		var icon: TextureRect = entry["icon"] if entry is Dictionary else entry
		var outline: TextureRect = entry["outline"] if entry is Dictionary else null
		var node = _token_nodes.get(tid)
		if icon == null or node == null or icon.texture == null:
			continue
		var feet: Vector3 = node.get_overlay_anchor_world()
		var height: float = float(node.get_overlay_height())
		var feet_px: Vector2 = _camera.unproject_position(feet) * scale
		var px_h := px_per_cell * (height / maxf(_cell_size, 0.01)) * 1.08
		var aspect := float(icon.texture.get_width()) / float(maxi(1, icon.texture.get_height()))
		var px_w := px_h * aspect
		var pos := Vector2(feet_px.x - px_w * 0.5, feet_px.y - px_h)
		icon.size = Vector2(px_w, px_h)
		icon.position = pos
		if outline != null:
			var grow := 3.0
			outline.size = Vector2(px_w + grow * 2.0, px_h + grow * 2.0)
			outline.position = pos - Vector2(grow, grow)

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
	if editor_mode:
		_editor_gui_input(event)
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
					_pan_velocity = Vector2.ZERO
					mouse_default_cursor_shape = Control.CURSOR_DRAG
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
					mouse_default_cursor_shape = Control.CURSOR_ARROW
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
			_pan_from_motion(motion)
			accept_event()
		else:
			_update_area_hover(motion.position)

## Applique le déplacement de vue correspondant à un mouvement souris.
func _pan_from_motion(motion: InputEventMouseMotion) -> void:
	var delta_pos := motion.position - _drag_start
	var span := _ground_span_per_pixel()
	_camera.position.x = _pan_start.x - delta_pos.x * span.x
	_camera.position.z = _pan_start.z - delta_pos.y * span.y
	_pan_velocity = Vector2(
		-(motion.position.x - _last_pan_pos.x) * span.x,
		-(motion.position.y - _last_pan_pos.y) * span.y
	) / maxf(get_process_delta_time(), 0.001)
	_last_pan_pos = motion.position
	_clamp_camera()

## Entrée souris en mode éditeur : zoom et pan restent internes, tout le reste
## est relayé à l'éditeur sous forme de coordonnées grille.
func _editor_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(1.1, mb.position)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(1.0 / 1.1, mb.position)
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_pan_dragging = mb.pressed
				_pan_velocity = Vector2.ZERO
				if mb.pressed:
					_drag_start = mb.position
					_pan_start = _camera.position
					_last_pan_pos = mb.position
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					grab_focus()
					editor_pointer_pressed.emit(_screen_to_grid(mb.position), mb.position, mb.button_index, _mods(mb))
				else:
					editor_pointer_released.emit(_screen_to_grid(mb.position), mb.position, mb.button_index, _mods(mb))
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pan_dragging:
			_pan_from_motion(motion)
			accept_event()
			return
		editor_pointer_moved.emit(_screen_to_grid(motion.position), motion.position, _mods(motion))

## Déplacement de vue piloté par l'éditeur (outil « main », espace maintenu).
func begin_view_pan(screen_pos: Vector2) -> void:
	_pan_dragging = true
	_pan_velocity = Vector2.ZERO
	_drag_start = screen_pos
	_pan_start = _camera.position
	_last_pan_pos = screen_pos

func update_view_pan(screen_pos: Vector2) -> void:
	if not _pan_dragging or _camera == null:
		return
	var delta_pos := screen_pos - _drag_start
	var span := _ground_span_per_pixel()
	_camera.position.x = _pan_start.x - delta_pos.x * span.x
	_camera.position.z = _pan_start.z - delta_pos.y * span.y
	_clamp_camera()
	view_changed.emit()

func end_view_pan() -> void:
	_pan_dragging = false
	_pan_velocity = Vector2.ZERO

func _handle_map_click(screen_pos: Vector2) -> void:
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

	# Navigation d'échelle : autorisée même en lecture seule (non destructif).
	if not editor_mode:
		var area := MapData.get_area_at(map_data, gx, gy)
		if not area.is_empty() and not str(area.get("targetMapId", "")).is_empty():
			area_clicked.emit(area)
			return

	if readonly and not is_gm:
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

func _update_area_hover(screen_pos: Vector2) -> void:
	var grid := _screen_to_grid(screen_pos)
	var area := MapData.get_area_at(map_data, grid.x, grid.y)
	var aid := str(area.get("id", ""))
	var linked := not aid.is_empty() and not str(area.get("targetMapId", "")).is_empty()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if linked else Control.CURSOR_ARROW
	if aid == _hovered_area_id:
		return
	_hovered_area_id = aid
	if _areas_overlay and _areas_overlay.has_method("set_hovered"):
		_areas_overlay.set_hovered(aid)
	area_hovered.emit(area)

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
		# `SubViewportContainer.stretch` redimensionne déjà le SubViewport :
		# le faire à la main déclenche un avertissement et n'a aucun effet.
		if _viewport and _viewport_container and not _viewport_container.stretch:
			_viewport.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
		if not map_data.is_empty():
			_clamp_camera()
