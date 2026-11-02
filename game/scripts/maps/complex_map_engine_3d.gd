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
signal area_activate_requested(area: Dictionary)
## Résultat d'un lancer de dés sur la table (vue table). Règle maison : un dé
## **compte s'il finit droit** (posé sur une face) — même tombé par terre ;
## `valid` faux si un dé est resté de travers (arête / pointe).
signal table_dice_result(faces: Array, total: int, valid: bool)

const MapGround3DScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const MapBackdrop3DScript := preload("res://scripts/maps/map_layers/map_backdrop_3d.gd")
const MapWater3DScript := preload("res://scripts/maps/map_layers/map_water_3d.gd")
const MapAmbientFx3DScript := preload("res://scripts/maps/map_layers/map_ambient_fx_3d.gd")
const MapVegetation3DScript := preload("res://scripts/maps/map_layers/map_vegetation_3d.gd")
const MapGrid3DScript := preload("res://scripts/maps/map_layers/map_grid_3d.gd")
const MapToken3DScript := preload("res://scripts/maps/map_layers/map_token_3d.gd")
const MapEffect3DScript := preload("res://scripts/maps/map_layers/map_effect_3d.gd")
const MapZone3DScript := preload("res://scripts/maps/map_layers/map_zone_3d.gd")
const MapFog3DScript := preload("res://scripts/maps/map_layers/map_fog_3d.gd")
const MapElevations3DScript := preload("res://scripts/maps/map_layers/map_elevations_3d.gd")
const MapWalls3DScript := preload("res://scripts/maps/map_layers/map_walls_3d.gd")
const MapLights3DScript := preload("res://scripts/maps/map_layers/map_lights_3d.gd")
const MapProps3DScript := preload("res://scripts/maps/map_layers/map_props_3d.gd")
const MapMeshes3DScript := preload("res://scripts/maps/map_layers/map_meshes_3d.gd")
const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")
const MapAreasOverlayScript := preload("res://scripts/maps/map_areas_overlay.gd")
const TableEnvironmentScript := preload("res://scripts/maps/map_layers/table_environment_3d.gd")
const TableDice3DScript := preload("res://scripts/maps/map_layers/table_dice_3d.gd")

const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
## Seuil sous lequel une case de relief est considérée comme plate.
const TERRAIN_RELIEF_EPSILON := 0.001
const DRAG_THRESHOLD := 4.0
const PAN_INERTIA_DECAY := 0.88
const PAN_INERTIA_MIN := 2.0
const CAM_HEIGHT := 48.0
## Vue table : fov « assis à la table » et limites de l'orbite caméra.
const TABLE_FOV := 50.0
const TABLE_ELEV_MIN := 18.0
const TABLE_ELEV_MAX := 78.0

var zoom: float = 1.0
var map_data: Dictionary = {}
var is_gm: bool = false
var readonly: bool = false
var snap_to_grid: bool = true
var session_tool: Dictionary = { "mode": "select" }
var owned_member_id: String = ""
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
## Relief M6 : hauteurs par case lues dans `map_data["terrainHeights"]`
## (tableau plat de floats, en cases, index y*width + x, 0 = plat).
var _terrain_heights: Array = []
var _terrain_w: int = 0
var _terrain_h: int = 0
var _terrain_relief: bool = false
## Matières du sol (0 herbe, 1 terre, 2 pierre) : tableau plat d'ints,
## index y*width+x, fourni par `map_data["terrainMaterials"]`.
var _terrain_materials: Array = []
## Mode de sol effectif (`MapData.GROUND_TERRAIN3D` ou `GROUND_ILLUSTRATED`),
## résolu depuis `map_data["groundMode"]` (voir `MapData.get_ground_mode`).
var _ground_mode: String = "illustrated"
var _base_ortho_size: float = 10.0
var _base_camera_height: float = CAM_HEIGHT
## Marges écran (gauche, haut, droite, bas) pour cadrer la carte hors HUD.
var _view_inset: Vector4 = Vector4.ZERO

## Vue table (plateau virtuel) : la carte est posée sur une table de taverne
## (`TableEnvironment3D`) et la caméra orbite depuis une place autour de la table.
var table_view: bool = false
var _table_env: Node3D = null
var _table_yaw: float = 0.0        # degrés, 0 = place sud (haut de la carte au fond)
var _table_elev: float = 32.0      # degrés au-dessus de l'horizon
var _table_seat: int = 0
var _table_dist_base: float = 10.0 # distance pour cadrer toute la table (zoom = 1)
var _table_target: Vector2 = Vector2.ZERO  # point visé au sol (x, z)
var _table_drag_yaw: float = 0.0
var _table_drag_elev: float = 32.0
var _table_seat_labels: Array = []
## Drag en cours : false = orbite (tourner), true = pan (déplacer la caméra
## sans tourner — Shift+glisser ou molette du milieu).
var _drag_pan_mode: bool = false
var _table_drag_target_start: Vector2 = Vector2.ZERO
var _dice = null
var _dice_color := Color(0.88, 0.84, 0.74)
var _dice_sides: int = 6
## Geste de lancer (clic droit tenu) : échantillons souris pour la vitesse.
var _throw_samples: Array = []

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _world_env: WorldEnvironment
## Fond de plateau derrière la carte (créé avant le sol, mode terrain3d seulement).
var _backdrop_layer: Node3D
var _ground: Node3D
## Calque d'eau (lacs/étangs) : instancié avec le viewport, sans rendu tant que
## `map_data["waterLevel"]` < 0 ou qu'aucune case n'est immergée.
var _water_layer: Node3D
## Niveau d'eau courant, en cases (même repère que terrainHeights) ; -1 = aucune.
var _water_level: float = -1.0
## Calque d'ambiance animée (lucioles / poussière / feuilles), après l'eau.
var _ambient_fx_layer: Node3D
## Végétation procédurale (touffes d'herbe, fleurs) — terrain3d 2.5D uniquement.
var _vegetation_layer: Node3D
## Effet d'ambiance courant (`map_data["ambientFx"]`) ; "" = aucun.
var _ambient_fx: String = ""
var _elevations_layer: Node3D
var _grid_layer: Node3D
var _zones_layer: Node3D
var _tokens_layer: Node3D
var _effects_layer: Node3D
var _fog_layer: Node3D
var _props_layer: Node3D
var _meshes_layer: Node3D
var _walls_layer: Node3D
var _lights_layer: Node3D
var _sun: DirectionalLight3D
var _atmosphere: ColorRect
var _vignette: ColorRect
## Ciel procédural (terrain3d) + attributs caméra (DOF léger) réutilisés.
var _sky: Sky
var _sky_material: ShaderMaterial
var _camera_attributes: CameraAttributesPractical
var _areas_overlay: Control
var _token_overlay: Control
var _overlay_icons: Dictionary = {}

var _pan_dragging: bool = false
var _pending_click: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _pan_start: Vector3 = Vector3.ZERO
var _pan_velocity: Vector2 = Vector2.ZERO
var _last_pan_pos: Vector2 = Vector2.ZERO
## Navigation 3D de l'éditeur : orbite libre autour du point visé (clic milieu).
var _orbit_dragging: bool = false
var _orbit_enabled: bool = false
var _orbit_start: Vector2 = Vector2.ZERO
var _orbit_start_yaw: float = 0.0
var _orbit_start_pitch: float = -72.0
var _orbit_yaw: float = 0.0
var _orbit_pitch: float = -72.0
var _orbit_distance: float = 48.0
var _orbit_target: Vector3 = Vector3.ZERO
## Navigation à la souris droite : un clic simple ouvre le menu contextuel,
## un glisser orbite (Maj+glisser = déplacer la vue).
var _right_nav_down: bool = false
var _right_nav_dragging: bool = false
var _right_nav_shift: bool = false
var _right_nav_start: Vector2 = Vector2.ZERO
var _token_drag: Node = null
var _token_press_candidate: Node = null
var _token_click_candidate: Node = null
var _token_nodes: Dictionary = {}
## Clé de rendu des tokens (carte + style) : on ne réutilise les nœuds que si
## elle ne change pas, sinon on reconstruit (vue table ↔ 2.5D, autre carte…).
var _token_render_key: String = ""
## Pulsation d'arrivée (changement de zone) : état exposé aux tests/captures.
var _arrival_pulse_active: bool = false
var _arrival_tween: Tween = null
var _focus_tween: Tween = null
var _camera_debug_lbl: Label = null
var _effect_nodes: Dictionary = {}
var _zone_nodes: Dictionary = {}
var _lighting_config: Dictionary = {}
var _style_cfg: Dictionary = {}
var _hovered_area_id: String = ""
var _hovered_zone_id: String = ""
var _move_hover_layer: Control
var _move_hover_grid := Vector2(-1, -1)
var _move_hover_valid := false
var _fit_pending: bool = false
var _fit_retries: int = 0

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)
	_build_viewport_tree()
	mouse_exited.connect(_clear_area_hover)
	# Curseur de déplacement (outil Pas) dessiné au-dessus du rendu 3D.
	_move_hover_layer = Control.new()
	_move_hover_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_move_hover_layer)
	_move_hover_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_move_hover_layer.draw.connect(_draw_move_hover)

func _update_move_pointer(screen_pos: Vector2) -> void:
	var grid := _screen_to_grid(screen_pos)
	_move_hover_grid = grid
	_move_hover_valid = grid.x >= 0.0 and grid.y >= 0.0 \
		and grid.x < float(map_data.get("width", 0)) and grid.y < float(map_data.get("height", 0))
	if _move_hover_layer != null:
		_move_hover_layer.queue_redraw()

func _draw_move_hover() -> void:
	if _move_hover_layer == null or editor_mode or not _move_hover_valid:
		return
	if str(session_tool.get("mode", "")) != "move":
		return
	var screen := grid_to_screen(_move_hover_grid.x, _move_hover_grid.y, 0.02)
	if screen == Vector2.ZERO:
		return
	var color := Color(0.45, 0.95, 0.55, 0.95)
	_move_hover_layer.draw_circle(screen, 7.0, Color(0.05, 0.12, 0.06, 0.55))
	_move_hover_layer.draw_arc(screen, 7.0, 0.0, TAU, 24, color, 2.0, true)
	_move_hover_layer.draw_circle(screen, 2.0, color)

func _clear_area_hover() -> void:
	_move_hover_valid = false
	if _move_hover_layer != null:
		_move_hover_layer.queue_redraw()
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	if _hovered_area_id.is_empty() and _hovered_zone_id.is_empty():
		return
	_hovered_area_id = ""
	_hovered_zone_id = ""
	if _areas_overlay and _areas_overlay.has_method("set_hovered"):
		_areas_overlay.set_hovered("")
	if _areas_overlay and _areas_overlay.has_method("set_hovered_zone"):
		_areas_overlay.set_hovered_zone({})
	_apply_session_zone_visibility()
	area_hovered.emit({})

func _build_viewport_tree() -> void:
	# Si un preload a échoué (ex. shaders manquants), _viewport peut exister
	# sans _ground — on détruit et on reconstruit.
	if _viewport != null and is_instance_valid(_viewport) and _ground != null and is_instance_valid(_ground):
		return
	if _viewport_container != null and is_instance_valid(_viewport_container):
		_viewport_container.queue_free()
		_viewport_container = null
		_viewport = null
		_ground = null
		_backdrop_layer = null
		_water_layer = null
		_ambient_fx_layer = null
		_vegetation_layer = null
		_world = null
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# stretch=true : le container aligne le buffer sur la taille du Control et
	# force lui-même `_viewport.size` (set_size_force) — caméra, zoom, grille et
	# conversions `_viewport_pixel_scale` restent cohérents avec l'UI.
	# Ne jamais assigner `_viewport.size` à la main avec stretch=true : le moteur
	# refuse ("Can't change the size of a SubViewport…") et spamme les logs.
	_viewport_container.stretch = true
	# IGNORE : sinon le container avale les clics et le parent ne reçoit jamais
	# `_gui_input` (pan, pose, drag tokens, pointeur éditeur). Le picking 3D
	# est fait ici par raycast, pas via physics picking du SubViewport.
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Filtre neutre : le SubViewport est déjà rendu à la résolution écran.
	_viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.disable_3d = false
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.physics_object_picking = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Anti-aliasing : le low-poly + les contours d'objets gagnent beaucoup en
	# lisibilité avec du MSAA (Tiny Glade-like), sans flou type FXAA.
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.scaling_3d_scale = 1.0
	# Taille initiale (remplacée par celle du container dès le premier resize,
	# via set_size_force tant que stretch=true).
	_viewport.size = Vector2i(1280, 800)
	_viewport_container.add_child(_viewport)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.38, 0.48)
	env.ambient_light_energy = 0.55
	# LINEAR : préserve les couleurs du PNG illustré (FILMIC assombrit/adoucit).
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	_world_env = env_node
	_viewport.add_child(env_node)

	_world = Node3D.new()
	_world.name = "World"
	_viewport.add_child(_world)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
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

	_backdrop_layer = MapBackdrop3DScript.new()
	_backdrop_layer.name = "Backdrop"
	_world.add_child(_backdrop_layer)

	_ground = MapGround3DScript.new()
	_ground.name = "Ground"
	_world.add_child(_ground)

	_water_layer = MapWater3DScript.new()
	_water_layer.name = "Water"
	_world.add_child(_water_layer)

	_ambient_fx_layer = MapAmbientFx3DScript.new()
	_ambient_fx_layer.name = "AmbientFx"
	_world.add_child(_ambient_fx_layer)

	_vegetation_layer = MapVegetation3DScript.new()
	_vegetation_layer.name = "Vegetation"
	_world.add_child(_vegetation_layer)

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

	_meshes_layer = MapMeshes3DScript.new()
	_meshes_layer.name = "Meshes"
	_world.add_child(_meshes_layer)

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
	_vignette.color = Color(1, 1, 1, 1)
	_vignette.material = _make_vignette_material()
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
	if not is_node_ready():
		await ready
	if _viewport == null or _ground == null:
		_build_viewport_tree()
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
	_sync_terrain_from_map()
	_lighting_config = MapData.get_lighting_config(p_map)
	_style_cfg = MapRenderStyleScript.config(p_map)
	_loaded_map_id = new_id
	# Aimantation : libre en diorama, à la case en VTT (sauf override explicite).
	if not p_tool.has("forceSnap"):
		snap_to_grid = not MapRenderStyleScript.is_diorama(p_map)

	_load_ground()
	_load_backdrop()
	_load_water()
	_load_ambient_fx()
	_load_vegetation()
	_load_elevations()
	_sync_table_environment()
	_apply_camera_perspective()
	_apply_lighting()
	_apply_render_quality()
	_apply_atmosphere()
	_sync_areas_overlay()
	_hovered_area_id = ""
	_hovered_zone_id = ""
	# Même carte : conserver zoom/pan (y compris cartes illustrées).
	# Nouvelle carte : cadrer le PNG ou la grille entière.
	if same_map and not p_view_state.is_empty():
		_update_fit_base()
		_apply_view_state(p_view_state)
	elif same_map and _camera != null:
		var keep := get_view_state()
		_update_fit_base()
		_apply_view_state(keep)
	else:
		request_fit_to_view()
	_rebuild_layers()

func request_fit_to_view() -> void:
	_fit_pending = true
	_fit_retries = 0
	call_deferred("_fit_to_view_when_ready")

func _fit_to_view_when_ready() -> void:
	if not _fit_pending:
		return
	var vp := _effective_viewport_size()
	if vp.x < 32.0 or vp.y < 32.0:
		_fit_retries += 1
		if _fit_retries < 30:
			call_deferred("_fit_to_view_when_ready")
		else:
			_fit_pending = false
		return
	_fit_pending = false
	_fit_to_view()

func set_session_tool(tool: Dictionary) -> void:
	session_tool = tool
	if _move_hover_layer != null:
		_move_hover_layer.queue_redraw()

func set_move_policy(p_is_gm: bool, p_owned_member_id: String = "") -> void:
	is_gm = p_is_gm
	owned_member_id = p_owned_member_id

func _token_is_movable(node: Node) -> bool:
	if node == null or readonly:
		return false
	if is_gm:
		return true
	var data: Dictionary = {}
	if "token_data" in node and node.token_data is Dictionary:
		data = node.token_data
	return str(data.get("kind", "")) == "member" and str(data.get("memberId", "")) == owned_member_id

func _token_node_id(node: Node) -> String:
	if node == null:
		return ""
	if "token_data" in node and node.token_data is Dictionary:
		return str(node.token_data.get("id", ""))
	return ""

func set_snap_to_grid(on: bool) -> void:
	snap_to_grid = on
	for node in _token_nodes.values():
		node.snap_to_grid = on

func set_view_inset(left: float, top: float, right: float, bottom: float) -> void:
	_view_inset = Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))
	if _camera != null and _map_extent != Vector2.ZERO:
		request_fit_to_view()

## Qualité de rendu « Dofus » : AO écran pour asseoir les bâtiments, glow doux
## sur les lumières, contraste/couleurs légèrement relevés. Réservé au 2.5D
## terrain pour ne pas dégrader les fonds illustrés.
## Matériau du vignettage doux (radial) — remplace un aplat noir uniforme.
func _make_vignette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.18;
uniform vec4 tint : source_color = vec4(0.05, 0.04, 0.08, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv * vec2(1.0, 0.82));
	float v = smoothstep(0.30, 1.15, dist) * strength;
	COLOR = vec4(tint.rgb, v);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("strength", 0.18)
	mat.set_shader_parameter("tint", Color(0.05, 0.04, 0.08))
	return mat

## Crée (une fois) le ciel procédural réutilisable (shader de ciel pastel).
func _ensure_sky() -> void:
	if _sky != null and _sky_material != null:
		return
	var shader := Shader.new()
	shader.code = """
shader_type sky;
render_mode use_debanding;

uniform vec4 top_color : source_color = vec4(0.62, 0.80, 0.92, 1.0);
uniform vec4 horizon_color : source_color = vec4(1.0, 0.90, 0.76, 1.0);
uniform vec4 ground_color : source_color = vec4(0.92, 0.88, 0.80, 1.0);
uniform float sun_glow : hint_range(0.0, 4.0) = 1.2;

void sky() {
	float y = EYEDIR.y;
	// Dégradé vertical doux : sol pastel → horizon crème → haut bleu pâle.
	vec3 col = mix(horizon_color.rgb, top_color.rgb, clamp(y * 1.35 + 0.05, 0.0, 1.0));
	col = mix(ground_color.rgb, col, smoothstep(-0.38, 0.02, y));
	// Disque solaire discret + halo chaud (facultatif, jamais écrasant).
	float sun = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	col += LIGHT0_COLOR.rgb * pow(sun, 420.0) * sun_glow * LIGHT0_ENERGY;
	col += LIGHT0_COLOR.rgb * pow(sun, 8.0) * 0.06 * sun_glow * LIGHT0_ENERGY;
	COLOR = col;
}
"""
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = shader
	_sky_material.set_shader_parameter("top_color", Color(0.62, 0.80, 0.92))
	_sky_material.set_shader_parameter("horizon_color", Color(1.0, 0.90, 0.76))
	_sky_material.set_shader_parameter("ground_color", Color(0.92, 0.88, 0.80))
	_sky_material.set_shader_parameter("sun_glow", 1.2)
	_sky = Sky.new()
	_sky.sky_material = _sky_material
	_sky.radiance_size = Sky.RADIANCE_SIZE_256

## Applique le ciel (ou revient au fond uni) selon le preset / le mode de sol.
## Les cartes illustrées et la vue table gardent le fond uni : rien ne change
## pour elles. Fallback silencieux si le ciel n'est pas disponible.
func _apply_sky(env: Environment, terrain3d: bool, preset: Dictionary) -> void:
	if env == null:
		return
	var want_sky := terrain3d and not table_view and bool(preset.get("sky", false))
	if not want_sky:
		if env.sky != null:
			env.sky = null
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.html(str(preset.get("background", "#10151c")))
		env.fog_sky_affect = 0.0
		return
	_ensure_sky()
	if _sky == null or _sky_material == null:
		# Fallback : dégradé de couleur uni pastel.
		env.sky = null
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.html(str(preset.get("skyHorizon", "#ffe9cf")))
		return
	_sky_material.set_shader_parameter(
		"top_color", Color.html(str(preset.get("skyTop", "#9fd0e8"))))
	_sky_material.set_shader_parameter(
		"horizon_color", Color.html(str(preset.get("skyHorizon", "#ffe9cf"))))
	_sky_material.set_shader_parameter(
		"ground_color", Color.html(str(preset.get("skyGroundBottom", "#e9e2d4"))))
	_sky_material.set_shader_parameter(
		"sun_glow", float(preset.get("sunGlow", 1.2)))
	env.sky = _sky
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = float(preset.get("skyEnergy", 1.0))
	env.fog_sky_affect = float(preset.get("fogSkyAffect", 0.0))

## DOF très léger (profondeur) — uniquement en perspective sur un vrai terrain.
func _apply_depth_of_field(env: Environment, terrain: bool) -> void:
	if env == null or _camera == null:
		return
	var perspective := _camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	var dof_on := terrain and perspective and not table_view
	if _camera_attributes == null:
		_camera_attributes = CameraAttributesPractical.new()
	_camera_attributes.dof_blur_far_enabled = dof_on
	_camera_attributes.dof_blur_far_distance = 58.0
	_camera_attributes.dof_blur_far_transition = 20.0
	_camera_attributes.dof_blur_amount = 0.035
	_camera_attributes.dof_blur_near_enabled = false
	# Godot 4 : les attributs de profondeur de champ vivent sur la Camera3D.
	_camera.attributes = _camera_attributes if dof_on else null

## Vrai si le ciel procédural est actuellement rendu.
func is_sky_active() -> bool:
	if _world_env == null or _world_env.environment == null:
		return false
	return _world_env.environment.sky != null \
		and _world_env.environment.background_mode == Environment.BG_SKY

func get_sky_material() -> ShaderMaterial:
	return _sky_material

## Attributs caméra (DOF) courants, null si désactivés.
func get_camera_attributes() -> CameraAttributes:
	if _camera == null:
		return null
	return _camera.attributes

## Force de vignettage courante (0..1) — tests/captures.
func get_vignette_strength() -> float:
	if _vignette == null or _vignette.material is not ShaderMaterial:
		return 0.0
	return float((_vignette.material as ShaderMaterial).get_shader_parameter("strength"))

func _apply_render_quality() -> void:
	if _world_env == null:
		return
	var env: Environment = _world_env.environment
	if env == null:
		return
	var terrain := _ground_mode == "terrain3d" or MapRenderStyleScript.is_map_25d(map_data)
	env.ssao_enabled = terrain
	if terrain:
		env.ssao_radius = 1.35
		env.ssao_intensity = 1.35
		env.ssao_power = 1.15
		env.ssao_detail = 0.8
		env.ssao_horizon = 0.08
		env.ssao_sharpness = 0.98
		env.ssao_light_affect = 0.12
	var preset: Dictionary = MapData.get_lighting_preset(str(_lighting_config.get("preset", "jour")))
	var preset_glow := float(preset.get("glow", 0.34))
	env.glow_enabled = true
	env.glow_intensity = preset_glow if terrain else preset_glow * 0.6
	env.glow_strength = 0.9
	env.glow_bloom = 0.025
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_brightness = float(preset.get("brightness", 1.05))
	env.adjustment_contrast = float(preset.get("contrast", 1.06))
	env.adjustment_saturation = float(preset.get("saturation", 1.10)) if terrain else 1.0
	# --- Éclairage indirect / réflexions (palliatif aux assets low-poly) ---
	var gi_on := terrain and not table_view and bool(preset.get("gi", false))
	env.sdfgi_enabled = gi_on
	if gi_on:
		env.sdfgi_cascades = int(preset.get("giCascades", 3))
		env.sdfgi_min_cell_size = float(preset.get("giMinCell", 1.0))
		env.sdfgi_energy = float(preset.get("giEnergy", 0.9))
		env.sdfgi_normal_bias = 1.1
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = true
		env.sdfgi_bounce_feedback = 0.45
		env.sdfgi_max_distance = float(preset.get("giMaxDistance", 70.0))
	var ssil_on := terrain and not table_view and bool(preset.get("ssil", false))
	env.ssil_enabled = ssil_on
	if ssil_on:
		env.ssil_radius = 5.0
		env.ssil_intensity = float(preset.get("ssilIntensity", 0.9))
		env.ssil_sharpness = 0.9
		env.ssil_normal_rejection = 1.0
	var ssr_on := terrain and not table_view and bool(preset.get("ssr", false))
	env.ssr_enabled = ssr_on
	if ssr_on:
		env.ssr_max_steps = 64
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.5
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	# --- Brume volumétrique douce (profondeur + god rays discrets) ---
	var vol_on := terrain and not table_view and bool(preset.get("volumetricFog", false))
	env.volumetric_fog_enabled = vol_on
	if vol_on:
		env.volumetric_fog_density = float(preset.get("volumetricDensity", 0.008))
		env.volumetric_fog_albedo = Color.html(str(preset.get("volumetricColor", "#fff1de")))
		env.volumetric_fog_emission = Color(0, 0, 0, 1)
		env.volumetric_fog_emission_energy = 0.0
		env.volumetric_fog_anisotropy = 0.35
		env.volumetric_fog_length = 120.0
		env.volumetric_fog_gi_inject = 0.4
		env.volumetric_fog_ambient_inject = 0.2
	if _sun != null:
		# Le style 2.5D coupe les ombres par défaut ; sur un vrai terrain 3D on les
		# réactive pour asseoir les constructions (qualité Dofus).
		_sun.shadow_enabled = terrain and not table_view
		_sun.shadow_blur = float(preset.get("shadowBlur", 1.35))
		_sun.shadow_bias = 0.04
		_sun.directional_shadow_blend_splits = true
		# Taille angulaire du soleil : ombres à pénombres douces (Tiny Glade).
		_sun.light_angular_distance = float(preset.get("shadowAngular", 0.0))
		_sun.directional_shadow_max_distance = 160.0
		_sun.directional_shadow_split_1 = 0.12
		_sun.directional_shadow_split_2 = 0.30
		_sun.directional_shadow_split_3 = 0.55
	# DOF très léger : donne de la profondeur au fond sans flouter la carte.
	_apply_depth_of_field(env, terrain)

func _load_ground(p_ground_mode: String = "") -> void:
	if _ground == null:
		push_warning("[ComplexMap] ground missing — rebuild viewport")
		if _viewport == null:
			_build_viewport_tree()
		if _ground == null:
			return
	_ground_mode = p_ground_mode if not p_ground_mode.is_empty() else MapData.get_ground_mode(map_data)
	var terrain3d := _ground_mode == MapData.GROUND_TERRAIN3D
	var w: int = map_data.get("width", 16)
	var h: int = map_data.get("height", 12)
	var unshaded := MapRenderStyleScript.is_diorama(map_data)
	var night_mode := MapData.is_night_mode(map_data)
	# Le terrain 3D n'a besoin ni du PNG de fond ni du masque de nuit : en nuit,
	# le moteur teinte simplement son albédo. On évite donc de charger/générer
	# une texture inutile dans ce mode.
	var tex: Texture2D = null
	var night_tex: Texture2D = null
	var sources: Array = []
	var light_revealed: Array = []
	var night_ambient := 0.22
	if not terrain3d:
		tex = MapData.load_background_texture(map_data)
		if tex == null:
			tex = MapData.generate_tile_texture(map_data, _grid_config)
		if night_mode and not str(map_data.get("backgroundImage", "")).strip_edges().is_empty():
			night_tex = MapData.load_night_texture(map_data)
			var light_cfg: Dictionary = _lighting_config
			night_ambient = float(light_cfg.get("nightAmbient", 0.22))
			sources = light_cfg.get("sources", []) if light_cfg.get("sources") is Array else []
			var pd = map_data.get("playDefaults", {})
			if pd is Dictionary and pd.get("lightRevealed") is Array:
				light_revealed = pd["lightRevealed"]
	if _ground.has_method("configure"):
		_ground.configure(
			tex, w, h, _cell_size, unshaded,
			night_tex, night_mode,
			sources if sources is Array else [],
			light_revealed,
			night_ambient,
			_terrain_heights,
			_ground_mode,
			_terrain_materials
		)
	if _ground.has_method("get_map_extent"):
		_map_extent = _ground.get_map_extent()
	else:
		_map_extent = Vector2(float(w) * _cell_size, float(h) * _cell_size)
	var aspect := maxf(_viewport_aspect(), 0.1)
	_base_ortho_size = maxf(_map_extent.y, _map_extent.x / aspect) * 1.06

func _load_elevations() -> void:
	if _elevations_layer and _elevations_layer.has_method("configure"):
		_elevations_layer.configure(map_data, _cell_size)

# ===========================================================================
# Fond de plateau (backdrop) — derrière la carte 2.5D
# ===========================================================================
#
# Grand plan procédural unshaded sous la jupe de falaise : évite le vide noir
# autour de l'îlot. Visible uniquement en mode `terrain3d` (retiré en
# illustrated). Aucune donnée de carte : dimensions + teinte de nuit suffisent.

## Configure (ou retire) le fond de plateau selon le mode de sol.
func _load_backdrop() -> void:
	if _backdrop_layer == null or not is_instance_valid(_backdrop_layer):
		return
	if _ground_mode != MapData.GROUND_TERRAIN3D:
		# Mode illustré : pas de terrain 3D, donc pas de fond de plateau.
		_backdrop_layer.clear()
		return
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	# Palette de fond « prairie pastel » portée par certains presets lumineux
	# (Tiny Glade) : elle remplace le brun sombre qui masquerait le ciel.
	var preset: Dictionary = MapData.get_lighting_preset(
		str(_lighting_config.get("preset", "jour")))
	var palette: Dictionary = {}
	if preset.has("backdropCenter"):
		palette = {
			"center": Color.html(str(preset.get("backdropCenter", "#cfe0a8"))),
			"mid": Color.html(str(preset.get("backdropMid", "#b9d0a8"))),
			"edge": Color.html(str(preset.get("backdropEdge", "#f0ead8"))),
		}
	if _backdrop_layer.has_method("configure"):
		_backdrop_layer.configure(
			w, h, _cell_size, MapData.is_night_mode(map_data), palette)

## Vrai si le fond de plateau est rendu.
func is_backdrop_active() -> bool:
	if _backdrop_layer == null or not is_instance_valid(_backdrop_layer):
		return false
	return _backdrop_layer.has_method("is_active") and _backdrop_layer.is_active()

## Matériau (ShaderMaterial procédural) du fond, null s'il n'est pas rendu.
func get_backdrop_material() -> ShaderMaterial:
	if _backdrop_layer == null or not is_instance_valid(_backdrop_layer):
		return null
	if not _backdrop_layer.has_method("get_material") or not _backdrop_layer.is_active():
		return null
	return _backdrop_layer.get_material() as ShaderMaterial

# ===========================================================================
# Végétation procédurale — touffes d'herbe et fleurs (terrain3d 2.5D)
# ===========================================================================
#
# Semis déterministe sur les cases d'herbe (pas dans l'eau, pas sur terre/pierre) :
# touffes croisées avec vent doux + petites fleurs. Purement visuel (aucune
# collision, aucune ombre) ; retiré en mode `illustrated` et hors style 2.5D.
# Donne au sol la lisibilité « Dofus » : la carte ne paraît plus nue.

## Vrai si le style de rendu courant doit recevoir de la végétation.
func _vegetation_wanted() -> bool:
	if _ground_mode != MapData.GROUND_TERRAIN3D:
		return false
	if table_view:
		return false
	# Nettoyage visuel : pas d'herbes/fleurs/buissons procéduraux par défaut.
	# La végétation est peinte explicitement par zones (fleurs choisies).
	if not bool(map_data.get("vegetationEnabled", false)):
		return false
	return MapRenderStyleScript.is_map_25d(map_data) or MapRenderStyleScript.is_diorama(map_data)

## Configure (ou retire) le calque de végétation.
func _load_vegetation() -> void:
	if _vegetation_layer == null or not is_instance_valid(_vegetation_layer):
		return
	if not _vegetation_wanted():
		_vegetation_layer.clear()
		return
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	var water_level := float(map_data.get("waterLevel", -1.0))
	if _vegetation_layer.has_method("configure"):
		_vegetation_layer.configure(
			w, h, _cell_size, _terrain_heights, _terrain_materials,
			water_level, MapData.is_night_mode(map_data), true
		)

## Vrai si de la végétation est rendue.
func is_vegetation_active() -> bool:
	if _vegetation_layer == null or not is_instance_valid(_vegetation_layer):
		return false
	return _vegetation_layer.has_method("is_active") and _vegetation_layer.is_active()

## Nombre d'instances de végétation (touffes + fleurs).
func get_vegetation_count() -> int:
	if _vegetation_layer == null or not is_instance_valid(_vegetation_layer):
		return 0
	if not _vegetation_layer.has_method("get_vegetation_count"):
		return 0
	return int(_vegetation_layer.get_vegetation_count())

## Détail (tests/captures) : touffes, fleurs et buissons séparément.
func get_vegetation_counts() -> Dictionary:
	if _vegetation_layer == null or not is_instance_valid(_vegetation_layer):
		return {"tufts": 0, "flowers": 0, "bushes": 0}
	return {
		"tufts": int(_vegetation_layer.get_tuft_count()) if _vegetation_layer.has_method("get_tuft_count") else 0,
		"flowers": int(_vegetation_layer.get_flower_count()) if _vegetation_layer.has_method("get_flower_count") else 0,
		"bushes": int(_vegetation_layer.get_bush_count()) if _vegetation_layer.has_method("get_bush_count") else 0,
	}

# ===========================================================================
# Pulsation d'arrivée (changement de zone) — feedback de cadrage
# ===========================================================================
#
# À l'arrivée sur une carte (fondu de zone, voyage rapide), un léger « breathe »
# de zoom (rentre puis revient) donne un feedback doux façon Dofus. Purement
# caméra : aucun état de jeu modifié, le zoom final est exactement l'initial.

## Joue la pulsation d'arrivée (sans effet si la caméra n'est pas prête).
func play_arrival_pulse(strength: float = 1.0) -> void:
	if _camera == null or table_view:
		return
	var start := zoom
	var peak := clampf(start * (1.0 + 0.06 * maxf(strength, 0.0)), MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(peak, start):
		return
	_arrival_pulse_active = true
	if _arrival_tween != null and _arrival_tween.is_valid():
		_arrival_tween.kill()
	_arrival_tween = create_tween()
	_arrival_tween.set_trans(Tween.TRANS_SINE)
	_arrival_tween.set_ease(Tween.EASE_OUT)
	_arrival_tween.tween_method(func(z: float) -> void:
		zoom = z
		_update_ortho_size()
	, start, peak, 0.16)
	_arrival_tween.set_ease(Tween.EASE_IN_OUT)
	_arrival_tween.tween_method(func(z: float) -> void:
		zoom = z
		_update_ortho_size()
	, peak, start, 0.38)
	_arrival_tween.tween_callback(func() -> void:
		zoom = start
		_update_ortho_size()
		_arrival_pulse_active = false
	)

## Vrai pendant la pulsation d'arrivée (tests/captures).
func is_arrival_pulse_playing() -> bool:
	return _arrival_pulse_active

# ===========================================================================
# Eau (lacs, étangs, douves) — `map_data["waterLevel"]`
# ===========================================================================
#
# Contrat de données : `map_data["waterLevel"]` = float en **cases**, même
# repère que `terrainHeights`. `-1.0` (défaut) = pas d'eau ; toute valeur >= 0
# affiche un plan d'eau si au moins une case de terrain est sous ce niveau.
# Le calque n'est rendu qu'en mode `terrain3d` ; en `illustrated` il est retiré.

## Lit `waterLevel` et configure (ou retire) le calque d'eau.
func _load_water() -> void:
	_water_level = float(map_data.get("waterLevel", -1.0))
	if _water_layer == null or not is_instance_valid(_water_layer):
		return
	if _ground_mode != MapData.GROUND_TERRAIN3D:
		# Mode illustré : pas de vrai terrain, donc pas d'eau 3D.
		_water_layer.clear()
		return
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	var night_mode := MapData.is_night_mode(map_data)
	if _water_layer.has_method("configure"):
		_water_layer.configure(w, h, _cell_size, _water_level, _terrain_heights, night_mode)

## Change le niveau d'eau **sans toucher au document** (outils/tests ; l'éditeur
## passera par `refresh_terrain(map_data)`). Niveau en cases ; < 0 retire l'eau.
func set_water_level(level: float) -> void:
	_water_level = float(level)
	if _water_layer == null or not is_instance_valid(_water_layer):
		return
	if map_data.is_empty() or _ground_mode != MapData.GROUND_TERRAIN3D:
		_water_layer.clear()
		return
	if _water_layer.has_method("configure"):
		var w: int = int(map_data.get("width", 16))
		var h: int = int(map_data.get("height", 12))
		_water_layer.configure(
			w, h, _cell_size, _water_level, _terrain_heights, MapData.is_night_mode(map_data)
		)

## Niveau d'eau courant, en cases (-1 = pas d'eau).
func get_water_level() -> float:
	return _water_level

## Vrai si un plan d'eau est effectivement rendu.
func is_water_active() -> bool:
	if _water_layer == null or not is_instance_valid(_water_layer):
		return false
	return _water_layer.has_method("is_active") and _water_layer.is_active()

# ===========================================================================
# Ambiances animées — `map_data["ambientFx"]`
# ===========================================================================
#
# Contrat de données : `map_data["ambientFx"]` = String, "" par défaut (aucune).
# Valeurs supportées : "fireflies", "dust", "leaves" ; toute autre valeur est
# ignorée. Le calque n'est rendu qu'en mode `terrain3d` (retiré en illustrated).

## Lit `ambientFx` et configure (ou retire) le calque d'ambiance.
func _load_ambient_fx() -> void:
	_ambient_fx = str(map_data.get("ambientFx", "")).strip_edges().to_lower()
	if _ambient_fx_layer == null or not is_instance_valid(_ambient_fx_layer):
		return
	if _ground_mode != MapData.GROUND_TERRAIN3D:
		# Mode illustré : pas d'ambiance 3D.
		_ambient_fx_layer.clear()
		return
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	var night_mode := MapData.is_night_mode(map_data)
	if _ambient_fx_layer.has_method("configure"):
		_ambient_fx_layer.configure(w, h, _cell_size, _ambient_fx, night_mode)

## Change l'effet d'ambiance **sans toucher au document** (outils/tests ;
## l'éditeur passera par `refresh_terrain(map_data)`). Nom vide/inconnu → aucun.
func set_ambient_fx(name: String) -> void:
	_ambient_fx = name.strip_edges().to_lower()
	if _ambient_fx_layer == null or not is_instance_valid(_ambient_fx_layer):
		return
	if map_data.is_empty() or _ground_mode != MapData.GROUND_TERRAIN3D:
		_ambient_fx_layer.clear()
		return
	if _ambient_fx_layer.has_method("configure"):
		var w: int = int(map_data.get("width", 16))
		var h: int = int(map_data.get("height", 12))
		_ambient_fx_layer.configure(
			w, h, _cell_size, _ambient_fx, MapData.is_night_mode(map_data)
		)

## Effet d'ambiance courant ("" = aucun).
func get_ambient_fx() -> String:
	return _ambient_fx

## Vrai si une ambiance animée est effectivement rendue.
func is_ambient_fx_active() -> bool:
	if _ambient_fx_layer == null or not is_instance_valid(_ambient_fx_layer):
		return false
	return _ambient_fx_layer.has_method("is_active") and _ambient_fx_layer.is_active()

# ===========================================================================
# Relief de terrain (M6) — adaptation des constructions au sol
# ===========================================================================
#
# Contrat de données (fourni par le document / l'éditeur) :
#   map_data["terrainHeights"] = tableau plat de floats, une hauteur **par
#   case**, en unités « cases » (0 = plat), longueur width*height,
#   index y*width + x.
#
# Convention de coordonnées : **grille centrée case**, la même que toutes les
# autres coordonnées grille du moteur (`grid_to_screen`, `screen_to_grid_pos`,
# `editor_pointer_*`) : `terrain_height_at(3, 4)` lit la hauteur de la case
# (3,4) = terrainHeights[4*width + 3], et l'interpolation se fait entre
# centres de cases. Hors des bords de la carte → 0.

## Relit et valide `map_data["terrainHeights"]` et `map_data["terrainMaterials"]`
## (appelé par `configure` et `refresh_terrain`). Tableau absent ou mal
## dimensionné = terrain plat / matériau de repli.
func _sync_terrain_from_map() -> void:
	_terrain_w = maxi(0, int(map_data.get("width", 0)))
	_terrain_h = maxi(0, int(map_data.get("height", 0)))
	_terrain_heights = []
	_terrain_relief = false
	_terrain_materials = []
	var raw = map_data.get("terrainHeights", [])
	if raw is Array and _terrain_w > 0 and _terrain_h > 0 \
			and (raw as Array).size() == _terrain_w * _terrain_h:
		_terrain_heights = raw
		for value in _terrain_heights:
			if absf(float(value)) > TERRAIN_RELIEF_EPSILON:
				_terrain_relief = true
				break
	_terrain_materials = _normalize_terrain_materials(map_data.get("terrainMaterials", []))

## Matières normalisées (0..4 : herbe, terre, pierre, neige, sable),
## dimensionnées width*height ; vide si la carte n'en fournit pas (matériau de
## repli du sol).
func _normalize_terrain_materials(raw: Variant) -> Array:
	var materials: Array = []
	if _terrain_w <= 0 or _terrain_h <= 0:
		return materials
	var expected: int = _terrain_w * _terrain_h
	if not (raw is Array) or (raw as Array).size() != expected:
		return materials
	materials.resize(expected)
	for i in range(expected):
		materials[i] = clampi(int((raw as Array)[i]), MapData.MATERIAL_GRASS, MapData.MATERIAL_SAND)
	return materials

## Copie des matières du sol ([]) si absentes.
func get_terrain_materials() -> Array:
	return _terrain_materials.duplicate()

## Met à jour les matières du sol **sans toucher au document** (API directe pour
## outils/tests ; l'éditeur passe par `refresh_terrain(map_data)` qui relit le
## document). Met à jour le splat du sol de façon fluide.
func set_terrain_materials(materials: Array) -> void:
	_terrain_materials = _normalize_terrain_materials(materials)
	if _ground != null and is_instance_valid(_ground) and _ground.has_method("set_terrain_materials"):
		_ground.set_terrain_materials(_terrain_materials)

## Vrai si le sol affiche le shader de matières (splat herbe/terre/pierre).
func is_terrain_splat_active() -> bool:
	if _ground == null or not is_instance_valid(_ground):
		return false
	return _ground.has_method("is_splat_active") and _ground.is_splat_active()

## Vrai si la carte a un relief non nul (au moins une case ≠ 0).
func terrain_has_relief() -> bool:
	return _terrain_relief

## Mode de sol effectif : `terrain3d` (heightfield réel) ou `illustrated`
## (fond peint plat, aucun relief rendu).
func get_ground_mode() -> String:
	return _ground_mode

## Vrai si le sol rendu est le vrai terrain 3D.
func is_terrain3d_ground() -> bool:
	return _ground_mode == MapData.GROUND_TERRAIN3D

## Change le mode de sol à chaud **sans toucher au document** (le mode fait foi
## pour le rendu courant ; `configure`/`refresh_terrain` le relisent depuis
## `map_data["groundMode"]`). Équivalent visuel à `_sync_engine(true)` côté
## éditeur, mais utilisable directement (tests, outils).
func set_ground_mode(mode: String = "") -> void:
	var resolved := mode.strip_edges().to_lower()
	if resolved != MapData.GROUND_TERRAIN3D and resolved != MapData.GROUND_ILLUSTRATED:
		resolved = MapData.get_ground_mode(map_data)
	_ground_mode = resolved
	_load_ground(_ground_mode)
	_load_backdrop()
	_load_vegetation()
	_apply_camera_perspective()
	_apply_atmosphere()
	_apply_lighting()

## Hauteur du terrain à des coordonnées grille (centrées case), en cases.
## Interpolation bilinéaire entre les centres des cases ; 0 hors carte / sans
## relief.
func terrain_height_at(gx: float, gy: float) -> float:
	if not _terrain_relief or _terrain_heights.is_empty():
		return 0.0
	# Bords de la carte, en coordonnées grille : -0.5 … width-0.5.
	if gx < -0.5 or gy < -0.5 or gx > float(_terrain_w) - 0.5 or gy > float(_terrain_h) - 0.5:
		return 0.0
	var sx := clampf(gx, 0.0, float(_terrain_w - 1))
	var sy := clampf(gy, 0.0, float(_terrain_h - 1))
	var x0 := floori(sx)
	var y0 := floori(sy)
	var x1 := mini(x0 + 1, _terrain_w - 1)
	var y1 := mini(y0 + 1, _terrain_h - 1)
	var fx := sx - float(x0)
	var fy := sy - float(y0)
	var h00 := float(_terrain_heights[y0 * _terrain_w + x0])
	var h10 := float(_terrain_heights[y0 * _terrain_w + x1])
	var h01 := float(_terrain_heights[y1 * _terrain_w + x0])
	var h11 := float(_terrain_heights[y1 * _terrain_w + x1])
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

## Normale du terrain aux coordonnées grille : dérivées des hauteurs
## échantillonnées à ±0.5 case → `Vector3(-dh/dx, 1, -dh/dz).normalized()`.
## `Vector3.UP` sur terrain plat / hors relief.
func terrain_normal_at(gx: float, gy: float) -> Vector3:
	if not _terrain_relief:
		return Vector3.UP
	const STEP := 0.5
	var dhdx := (terrain_height_at(gx + STEP, gy) - terrain_height_at(gx - STEP, gy)) / (2.0 * STEP)
	var dhdz := (terrain_height_at(gx, gy + STEP) - terrain_height_at(gx, gy - STEP)) / (2.0 * STEP)
	if absf(dhdx) < TERRAIN_RELIEF_EPSILON and absf(dhdz) < TERRAIN_RELIEF_EPSILON:
		return Vector3.UP
	return Vector3(-dhdx, 1.0, -dhdz).normalized()

## Met à jour le relief **sans reconstruire le viewport** (retour visuel du
## pinceau de relief de l'éditeur, appelé à chaque mouvement de souris).
## `p_map` est le `map_data` du document (avec `terrainHeights` à jour) ; sans
## argument, relit le `map_data` courant. Reconfigure le sol puis repose les
## meshes, décors et tokens sur les nouvelles hauteurs. Caméra, cadrage,
## brouillard et grille ne sont pas touchés (pas de saut de vue au pinceau).
func refresh_terrain(p_map: Dictionary = {}) -> void:
	if not p_map.is_empty():
		map_data = p_map
	_sync_terrain_from_map()
	var resolved_mode := MapData.get_ground_mode(map_data)
	var mode_changed := resolved_mode != _ground_mode
	if mode_changed:
		_ground_mode = resolved_mode
	if mode_changed or _ground == null or not is_instance_valid(_ground):
		_load_ground()
		if mode_changed:
			_apply_camera_perspective()
		_apply_atmosphere()
	elif _ground.has_method("set_terrain_heights"):
		# Mode inchangé : on ne reconstruit que ce qui a bougé. Matières peintes
		# (splat) et relief sont indépendants ; chaque setter ignore l'inchangé.
		if _ground.has_method("set_terrain_materials"):
			_ground.set_terrain_materials(_terrain_materials)
		_ground.set_terrain_heights(_terrain_heights)
	elif _ground.has_method("configure"):
		_load_ground()
	# Fond de plateau : dépend des dimensions, du mode de sol et de la nuit.
	_load_backdrop()
	# Eau : dépend du niveau (`waterLevel`), des hauteurs et du mode de sol.
	_load_water()
	# Ambiance animée : dépend de `ambientFx`, du mode de sol et de la nuit.
	_load_ambient_fx()
	# Végétation : dépend des matières peintes, des hauteurs et de l'eau.
	_load_vegetation()
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	var map_size := Vector2i(w, h)
	# Pinceau de relief : on repose les nœuds existants au lieu de reconstruire
	# les calques (pas de rechargement de textures ni de réinstanciation des GLB).
	if _props_layer and _props_layer.has_method("set_terrain_heights"):
		_props_layer.set_terrain_heights(_terrain_heights, map_size)
	elif _props_layer and _props_layer.has_method("configure"):
		var props = map_data.get("props", [])
		_props_layer.configure(props if props is Array else [], _cell_size, map_data)
	if _meshes_layer and _meshes_layer.has_method("set_terrain_heights"):
		_meshes_layer.set_terrain_heights(_terrain_heights, map_size)
	elif _meshes_layer and _meshes_layer.has_method("configure"):
		var meshes = map_data.get("meshes", [])
		_meshes_layer.configure(meshes if meshes is Array else [], _cell_size, map_data)
	for tid in _token_nodes:
		var node = _token_nodes[tid]
		if node != null and is_instance_valid(node) and node.has_method("set_terrain_heights"):
			node.set_terrain_heights(_terrain_heights, map_size)
	if _ground != null and _ground.has_method("get_map_extent"):
		_map_extent = _ground.get_map_extent()
	_ensure_camera_above_terrain()

## Si le relief monte sous la caméra, on la remonte pour éviter une vue noire
## (caméra enterrée dans la colline).
func _ensure_camera_above_terrain() -> void:
	if _camera == null or table_view:
		return
	var focus := _ground_focus()
	var ground := terrain_height_at(focus.x, focus.y) * _cell_size
	var min_y := ground + maxf(2.0, _style_camera_height() * 0.6)
	if _camera.position.y < min_y:
		_camera.position.y = min_y
		_clamp_camera()

func _update_camera_debug() -> void:
	if _camera == null:
		return
	if not editor_mode and not OS.is_debug_build():
		return
	if _camera_debug_lbl == null:
		var layer := CanvasLayer.new()
		layer.layer = 200
		add_child(layer)
		_camera_debug_lbl = Label.new()
		_camera_debug_lbl.position = Vector2(12, 74)
		_camera_debug_lbl.z_index = 100
		_camera_debug_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_camera_debug_lbl.add_theme_font_size_override("font_size", 11)
		_camera_debug_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
		_camera_debug_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_camera_debug_lbl.add_theme_constant_override("outline_size", 4)
		layer.add_child(_camera_debug_lbl)
	# Placé dans le coin bas-gauche de la vue 3D, pas dans le bandeau de l'éditeur.
	var view_rect := get_global_rect()
	_camera_debug_lbl.position = view_rect.position + Vector2(14.0, maxf(14.0, view_rect.size.y - 28.0))
	var focus := _ground_focus()
	var ground := terrain_height_at(focus.x, focus.y) * _cell_size
	var span := _ground_span_per_pixel()
	_camera_debug_lbl.text = "CAM  pos %.2f / %.2f / %.2f   rot %.1f°   focus %.1f / %.1f   sol %.2f   span %.3f" % [
		_camera.position.x, _camera.position.y, _camera.position.z,
		_camera.rotation_degrees.x, focus.x, focus.y, ground, span.x,
	]

func _apply_camera_perspective() -> void:
	_orbit_dragging = false
	_orbit_enabled = false
	var cfg := _style_cfg if not _style_cfg.is_empty() else MapRenderStyleScript.config(map_data)
	if table_view:
		# Vue table : perspective « assis à la table », cadrage piloté par l'orbite.
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = TABLE_FOV
		_update_fit_base()
		_update_ortho_size()
		return
	if bool(cfg.get("perspective", false)):
		# Diorama : caméra perspective inclinée → parallaxe au pan.
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.rotation_degrees = Vector3(float(cfg.get("tilt", -52.0)), 0.0, 0.0)
		_camera.fov = float(cfg.get("fov", 34.0))
		_camera.position.y = _style_camera_height()
		_base_camera_height = _camera.position.y
		_update_ortho_size()
		return
	# VTT / ortho : tilt depuis le style (défaut ~-72) pour voir les props
	# dressés. Isométrique reste un angle fixe. Fond illustré diorama force
	# -90 via MapRenderStyle.config (preferFlatProps).
	var persp := MapData.get_perspective(map_data)
	if persp == MapData.PERSPECTIVE_ISOMETRIC:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.rotation_degrees = Vector3(-58.0, 45.0, 0.0)
		_camera.position.y = CAM_HEIGHT
	else:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.rotation_degrees = Vector3(float(cfg.get("tilt", -72.0)), 0.0, 0.0)
		_camera.position.y = CAM_HEIGHT
	_update_ortho_size()

func _apply_lighting() -> void:
	var cfg := _style_cfg if not _style_cfg.is_empty() else MapRenderStyleScript.config(map_data)
	var terrain3d := _ground_mode == MapData.GROUND_TERRAIN3D
	var preset_id := str(_lighting_config.get("preset", "jour"))
	var preset: Dictionary = MapData.get_lighting_preset(preset_id)
	var sun_color := Color.html(str(_lighting_config.get("sunColor", preset.get("sunColor", "#fff1d8"))))
	var ambient_color := Color.html(str(_lighting_config.get("ambientColor", preset.get("ambientColor", "#9fb4d4"))))
	var sun_energy := float(_lighting_config.get("sunEnergy", preset.get("sunEnergy", 1.25)))
	var ambient_energy := float(_lighting_config.get("ambientEnergy", preset.get("ambientEnergy", 0.58)))
	var exposure := float(_lighting_config.get("exposure", preset.get("exposure", 1.0)))
	var fog_density := float(_lighting_config.get("fogDensity", preset.get("fogDensity", 0.0)))
	var yaw := float(_lighting_config.get("sunYaw", preset.get("sunYaw", 38.0)))
	var pitch := float(_lighting_config.get("sunAngle", preset.get("sunAngle", -58.0)))
	if bool(_lighting_config.get("enabled", false)):
		match str(_lighting_config.get("direction", "nw")):
			"ne": yaw = 35.0
			"sw": yaw = -145.0
			"se": yaw = 145.0
			_: yaw = -35.0
		sun_energy *= clampf(0.75 + float(_lighting_config.get("intensity", 0.35)) * 0.6, 0.7, 1.5)
	if _sun == null:
		return
	if table_view:
		# Salle intérieure : le soleil devient un fill doux, la suspension
		# de la table éclaire le plateau (TableEnvironment3D).
		_sun.visible = true
		_sun.shadow_enabled = false
		_sun.light_energy = 0.35
		_sun.light_color = Color(1.0, 0.88, 0.72)
		_sun.rotation_degrees = Vector3(-62.0, 25.0, 0.0)
		return
	_sun.visible = true
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.rotation_degrees = Vector3(pitch, yaw, 0.0)
	# Le style 2.5D coupait les ombres ; sur un vrai terrain 3D on les garde pour
	# asseoir les constructions. Les cartes illustrées restent sans ombres.
	_sun.shadow_enabled = terrain3d and bool(cfg.get("shadows", false))
	if _world_env != null and _world_env.environment != null:
		var env: Environment = _world_env.environment
		# Ambiante : ciel si le preset le permet (lumière pastel venant de la
		# voûte, plus « Tiny Glade » qu'une couleur plate), sinon couleur.
		var ambient_sky := terrain3d and bool(preset.get("sky", false)) \
			and bool(preset.get("ambientFromSky", false))
		if ambient_sky:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_sky_contribution = float(preset.get("skyContribution", 0.7))
		else:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_sky_contribution = 0.0
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = ambient_energy
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = exposure
		env.fog_enabled = terrain3d and fog_density > 0.0001
		env.fog_light_color = Color.html(str(preset.get("fogColor", "#2b3445")))
		env.fog_density = fog_density
		# Profondeur atmosphérique : brume qui prend la couleur du ciel au loin
		# et diffusion chaude autour du soleil (god rays doux).
		env.fog_aerial_perspective = float(preset.get("aerial", 0.0)) if terrain3d else 0.0
		env.fog_sun_scatter = float(preset.get("sunScatter", 0.0)) if terrain3d else 0.0
		env.fog_light_energy = float(preset.get("fogLightEnergy", 1.0))
		_apply_sky(env, terrain3d, preset)

func _apply_atmosphere() -> void:
	if _atmosphere == null or _vignette == null:
		return
	var atmo: Dictionary = map_data.get("atmosphere", {}) if map_data.get("atmosphere") is Dictionary else {}
	var is_diorama := MapRenderStyleScript.is_diorama(map_data)
	# Un terrain3d n'est pas un fond peint : on garde un léger voile d'ambiance
	# (profondeur) au lieu de désactiver l'atmosphère comme sur une illustration.
	var illustrated := _ground_mode != MapData.GROUND_TERRAIN3D \
		and not str(map_data.get("backgroundImage", "")).strip_edges().is_empty()
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
		_set_vignette_strength(minf(vig, 0.08) if illustrated else (minf(vig, 0.18) if is_diorama else vig))
	elif illustrated:
		# Fond peint : pas de voile — on lit l'image telle quelle.
		_atmosphere.color = Color(0, 0, 0, 0.0)
		_set_vignette_strength(0.0)
	elif is_diorama:
		_atmosphere.color = Color(0.08, 0.06, 0.10, 0.06)
		_set_vignette_strength(0.12)
	else:
		_atmosphere.color = Color(0.04, 0.03, 0.06, 0.08)
		_set_vignette_strength(0.12 if is_gm else 0.20)

## Applique la force du vignettage radial (0 = aucun).
func _set_vignette_strength(value: float) -> void:
	if _vignette == null or not (_vignette.material is ShaderMaterial):
		return
	var mat: ShaderMaterial = _vignette.material
	mat.set_shader_parameter("strength", clampf(value, 0.0, 0.6))

func _apply_view_state(view_state: Dictionary) -> void:
	if view_state.is_empty():
		return
	zoom = clampf(float(view_state.get("zoom", zoom)), MIN_ZOOM, MAX_ZOOM)
	if table_view:
		_table_seat = int(view_state.get("tableSeat", _table_seat))
		_table_yaw = float(view_state.get("tableYaw", _table_yaw))
		_table_elev = clampf(float(view_state.get("tableElev", _table_elev)), TABLE_ELEV_MIN, TABLE_ELEV_MAX)
		if _table_env != null and _table_env.has_method("set_active_seat"):
			_table_env.set_active_seat(_table_seat)
		_update_ortho_size()
		return
	_camera.position.x = float(view_state.get("panX", _camera.position.x))
	_camera.position.z = float(view_state.get("panY", _camera.position.z))
	_update_ortho_size()

func get_view_state() -> Dictionary:
	if table_view:
		return {
			"zoom": zoom,
			"tableSeat": _table_seat,
			"tableYaw": _table_yaw,
			"tableElev": _table_elev,
		}
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

	if _meshes_layer and _meshes_layer.has_method("configure"):
		var meshes = map_data.get("meshes", [])
		_meshes_layer.configure(meshes if meshes is Array else [], _cell_size, map_data)

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

	# Tokens : on **réutilise** les nœuds existants quand la carte et le style de
	# rendu n'ont pas changé. Deux bénéfices façon Dofus : pas de clignotement au
	# refresh, et la marche peut s'animer depuis la position courante (au lieu
	# d'un saut sec vers la case d'arrivée).
	var render_key := "%s|%s|%s" % [_loaded_map_id, str(table_view), str(is_diorama)]
	if render_key != _token_render_key:
		_token_render_key = render_key
		_clear_children(_tokens_layer, _token_nodes)
		_token_nodes.clear()
	var seen_tokens := {}
	for tok in _tokens:
		if bool(tok.get("hidden", false)):
			continue
		var token_id := str(tok.get("id", ""))
		if token_id.is_empty():
			continue
		var node = _token_nodes.get(token_id)
		var reused := node != null and is_instance_valid(node)
		if not reused:
			node = _create_token_node(tok, w, h)
			_tokens_layer.add_child(node)
			_token_nodes[token_id] = node
		else:
			if node.has_method("update_token"):
				node.update_token(tok)
			node.snap_to_grid = snap_to_grid
			node.set_selected(token_id == _selected_token_id)
			if node.has_method("set_terrain_heights"):
				# `repose = false` : ne pas téléporter le token sur la nouvelle
				# case avant l'animation de marche (c'est move_to_grid qui gère).
				node.set_terrain_heights(_terrain_heights, Vector2i(w, h), false)
			if node.has_method("move_to_grid"):
				node.move_to_grid(
					float(tok.get("x", 0.0)), float(tok.get("y", 0.0)), true)
		seen_tokens[token_id] = true
	for tid in _token_nodes.keys().duplicate():
		if seen_tokens.has(tid):
			continue
		var stale = _token_nodes[tid]
		if stale != null and is_instance_valid(stale):
			stale.queue_free()
		_token_nodes.erase(tid)

	_rebuild_token_overlay()

## Construit un nœud de token complet (visuel, relief, figurine, sélection).
func _create_token_node(tok: Dictionary, w: int, h: int) -> Node:
	var node = MapToken3DScript.new()
	var is_diorama := MapRenderStyleScript.is_diorama(map_data)
	# Portrait / silhouette en pied dès qu'une image est dispo.
	# Billboard caméra : visible même en vue de dessus.
	var has_image := not str(tok.get("image", "")).strip_edges().is_empty()
	if not has_image and str(tok.get("kind", "")) == "member":
		var mid := str(tok.get("memberId", ""))
		for m_variant in _party:
			if str((m_variant as Dictionary).get("id", "")) == mid:
				has_image = not str((m_variant as Dictionary).get("portrait", (m_variant as Dictionary).get("image", ""))).strip_edges().is_empty()
				break
	var use_cutout := has_image \
		or MapRenderStyleScript.is_dd2(map_data) \
		or MapRenderStyleScript.is_map_25d(map_data) \
		or (is_diorama and str(map_data.get("backgroundImage", "")).strip_edges().is_empty())
	# Vue table : des **pions** 3D posés sur le plateau, pas des découpes.
	if table_view:
		use_cutout = false
	node.setup(tok, _cell_size, _party, readonly, use_cutout, _terrain_heights, Vector2i(w, h))
	if table_view and node.has_method("set_pawn_mode"):
		node.set_pawn_mode(true)
	# En carte 2.5D, les membres sans portrait deviennent des figurines 3D
	# choisies d'après leur classe / nom (kit v6), avec repli par hash.
	if not table_view and not has_image and MapRenderStyleScript.is_map_25d(map_data) \
			and node.has_method("set_figurine_asset"):
		var figurine := _figurine_asset_for_token(tok)
		if not figurine.is_empty():
			node.set_figurine_asset(figurine)
	if use_cutout and node.has_method("set_overlay_height"):
		# `scale` = hauteur en **cases** (créature Medium = 1). Les anciennes
		# valeurs fractionnaires (0.07 / 0.14 = % hauteur de carte) sont migrées.
		var scale_val := float(tok.get("scale", 1.0))
		var height_cells := scale_val
		if scale_val <= 0.001:
			height_cells = 1.0
		elif scale_val < 0.5:
			height_cells = maxf(1.0, scale_val * float(map_data.get("height", 12)))
		node.set_overlay_height(_cell_size * height_cells)
	node.snap_to_grid = snap_to_grid
	node.set_selected(str(tok.get("id", "")) == _selected_token_id)
	node.drag_finished.connect(_on_token_drag_finished)
	node.selected.connect(_on_token_selected)
	return node

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
		if znode.has_method("set_hover_only"):
			znode.set_hover_only(not editor_mode)
		_zones_layer.add_child(znode)
		_zone_nodes[str(zone.get("id", ""))] = znode
	_apply_session_zone_visibility()
	# Matières du sol : re-synchronisées à chaque rebuild (no-op si inchangées)
	# pour couvrir les cas où seules les données de carte ont bougé.
	if _ground != null and is_instance_valid(_ground) and _ground.has_method("set_terrain_materials"):
		_ground.set_terrain_materials(_terrain_materials)
	# Eau : même logique (niveau/hauteurs lus dans map_data, no-op si inchangés).
	_load_water()
	# Ambiance : même logique (clé `ambientFx`).
	_load_ambient_fx()
	# Végétation : matières/hauteurs/eau (no-op si inchangés).
	_load_vegetation()
	# Fond de plateau : dimensions/mode/nuit (no-op si inchangés).
	_load_backdrop()

func _clear_children(layer: Node, registry: Dictionary) -> void:
	for child in layer.get_children():
		child.queue_free()
	registry.clear()

func _viewport_aspect() -> float:
	var vp := _usable_viewport_size()
	return vp.x / maxf(vp.y, 1.0)

func _effective_viewport_size() -> Vector2:
	# Taille de la zone d'affichage, en pixels Control. Ne pas confondre avec
	# `_viewport.size` (buffer en résolution écran, utile pour les conversions
	# de pixels) : la géométrie de caméra/grille doit rester en pixels Control.
	if size.x > 16.0 and size.y > 16.0:
		return size
	if _viewport_container != null and _viewport_container.size.x > 16.0 and _viewport_container.size.y > 16.0:
		return _viewport_container.size
	if _viewport != null and _viewport.size.x > 16.0 and _viewport.size.y > 16.0:
		return Vector2(_viewport.size)
	return Vector2(maxf(size.x, 8.0), maxf(size.y, 8.0))

func _usable_viewport_size() -> Vector2:
	var vp := _effective_viewport_size()
	return Vector2(
		maxf(vp.x - _view_inset.x - _view_inset.z, 8.0),
		maxf(vp.y - _view_inset.y - _view_inset.w, 8.0)
	)

func _focus_screen_pos() -> Vector2:
	var vp := _effective_viewport_size()
	var usable := _usable_viewport_size()
	return Vector2(_view_inset.x + usable.x * 0.5, _view_inset.y + usable.y * 0.5)

func _update_ortho_size() -> void:
	if table_view:
		_apply_table_camera()
		view_changed.emit()
		return
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
	var ortho_h := _camera.size if _camera else 1.0
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
	var vp := _usable_viewport_size()
	var span := _ground_span_per_pixel()
	return Vector2(span.x * vp.x, span.y * vp.y)

## Point du sol visé au centre de la zone utile (hors HUD).
func _ground_focus() -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	if editor_mode and _orbit_enabled:
		return Vector2(_orbit_target.x, _orbit_target.z)
	var world := _raycast_ground(_control_to_viewport(_focus_screen_pos()))
	if world == Vector3.INF:
		return Vector2(_camera.position.x, _camera.position.z)
	return Vector2(world.x, world.z)

## Déplace la caméra pour que le centre de l'écran vise ce point du sol.
func _center_focus_on(target: Vector2) -> void:
	if _camera == null:
		return
	if table_view:
		# Orbite : on déplace le point visé, la caméra reste sur son cercle.
		_table_target = target
		_update_ortho_size()
		return
	var focus := _ground_focus()
	_camera.position.x += target.x - focus.x
	_camera.position.z += target.y - focus.y

## Met à jour `_base_ortho_size` / `_base_camera_height` pour que zoom=1
## montre toute la carte dans la zone utile (hors insets HUD).
func _update_fit_base() -> void:
	if _map_extent == Vector2.ZERO or _camera == null:
		return
	if table_view:
		_update_table_fit()
		return
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var saved_zoom := zoom
		var saved_pos := _camera.position
		zoom = 1.0
		_camera.position.y = maxf(_style_camera_height(), 1.0)
		_center_focus_on(_map_extent * 0.5)
		var visible := _visible_ground_size()
		if visible.x > 0.001 and visible.y > 0.001:
			var needed := maxf(_map_extent.x / visible.x, _map_extent.y / visible.y)
			_camera.position.y *= maxf(needed, 0.01) * 1.08
		else:
			var aspect := maxf(_viewport_aspect(), 0.1)
			var target_h := maxf(_map_extent.y, _map_extent.x / aspect) * 1.08
			var half := tan(deg_to_rad(_camera.fov * 0.5))
			var tilt_abs := absf(_camera.rotation_degrees.x)
			var denom := half * maxf(sin(deg_to_rad(tilt_abs)), 0.35)
			_camera.position.y = target_h / maxf(denom * 2.0, 0.01)
		_base_camera_height = _camera.position.y
		zoom = saved_zoom
		_camera.position = saved_pos
		_update_ortho_size()
	else:
		var vp := _effective_viewport_size()
		var usable := _usable_viewport_size()
		var aspect := maxf(usable.x / maxf(usable.y, 1.0), 0.1)
		var needed_h := maxf(_map_extent.y, _map_extent.x / aspect)
		# Marge légère pour cartouche / légende hors bord.
		_base_ortho_size = needed_h * (vp.y / maxf(usable.y, 1.0)) * 1.06

func _fit_to_view() -> void:
	if _map_extent == Vector2.ZERO or _camera == null:
		return
	var vp := _effective_viewport_size()
	if vp.x < 32.0 or vp.y < 32.0:
		request_fit_to_view()
		return
	if table_view:
		# « Cadrer » en vue table : toute la table visible depuis la place active.
		zoom = 1.0
		_table_target = _map_extent * 0.5
		_update_fit_base()
		_update_ortho_size()
		zoom_changed.emit(zoom)
		return
	zoom = 1.0
	_update_fit_base()
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		_camera.position.y = _base_camera_height
	else:
		_camera.size = _base_ortho_size
	_center_focus_on(_map_extent * 0.5)
	_clamp_camera()
	zoom_changed.emit(zoom)

func _clamp_camera() -> void:
	if table_view:
		# L'orbite est bornée par ses propres limites (yaw libre, elev bornée).
		return
	if _map_extent == Vector2.ZERO:
		return
	var visible := _visible_ground_size()
	var focus := _ground_focus()
	# Si toute la carte tient à l'écran, on laisse l'utilisateur déplacer la vue
	# librement (sinon un pan est annulé et on croit que la caméra est bloquée).
	if visible.x >= _map_extent.x and visible.y >= _map_extent.y:
		return
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
	if table_view:
		# Zoom = distance à la table (autour du point visé).
		zoom = new_zoom
		_update_ortho_size()
		zoom_changed.emit(zoom)
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

func _viewport_pixel_scale() -> Vector2:
	# Échelle pixel Control → pixel viewport (buffer en résolution écran).
	# Avec stretch=true, le container fait coïncider le buffer avec la zone du
	# Control, donc l'échelle vaut résolution_écran / taille_Control (~1.0 ici).
	var vp_size := Vector2(_viewport.size) if _viewport != null else Vector2.ZERO
	var ctrl := _effective_viewport_size()
	if vp_size.x > 1.0 and vp_size.y > 1.0 and ctrl.x > 1.0 and ctrl.y > 1.0:
		return vp_size / ctrl
	var root_vp := get_viewport()
	if root_vp != null:
		var st := root_vp.get_stretch_transform().get_scale()
		if absf(st.x) > 0.0001 and absf(st.y) > 0.0001:
			return Vector2(maxf(absf(st.x), 1.0), maxf(absf(st.y), 1.0))
	return Vector2.ONE

func _control_to_viewport(pos: Vector2) -> Vector2:
	return pos * _viewport_pixel_scale()

func _raycast_ground(viewport_pos: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(viewport_pos)
	var direction := _camera.project_ray_normal(viewport_pos)
	if absf(direction.y) < 0.0001:
		return Vector3.INF
	var t := -origin.y / direction.y
	if t < 0.0:
		return Vector3.INF
	var world := origin + direction * t
	if not _terrain_relief:
		return world
	# Relief : le rayon coupe d'abord le plan y=0 ; on lit la hauteur de la case
	# touchée puis on reprojette le rayon sur le plan horizontal à cette
	# hauteur. Deux itérations suffisent pour les pentes de carte et convergent
	# vers la surface (sur terrain plat, la hauteur vaut 0 → aucun changement).
	for _iteration in range(2):
		var gx := (world.x - _cell_size * 0.5) / _cell_size
		var gy := (world.z - _cell_size * 0.5) / _cell_size
		var surface_y := terrain_height_at(gx, gy) * _cell_size
		if absf(surface_y - world.y) < 0.001:
			break
		var t_surface := (surface_y - origin.y) / direction.y
		if t_surface < 0.0:
			break
		world = origin + direction * t_surface
	return world

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
## La hauteur du terrain (en cases) s'ajoute à `height` : les overlays et les
## poignées tombent juste sur une pente, et `height` reste une hauteur
## **relative au sol** (élévation d'un objet, hauteur d'un mur…).
func grid_to_screen(gx: float, gy: float, height: float = 0.0) -> Vector2:
	if _camera == null:
		return Vector2.ZERO
	var world := Vector3(
		gx * _cell_size + _cell_size * 0.5,
		(height + terrain_height_at(gx, gy)) * _cell_size,
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
	return pos / _viewport_pixel_scale()

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

## Recadrage doux sur une case (caméra qui suit un personnage).
func center_on_grid_smooth(gx: float, gy: float, duration: float = 0.32) -> void:
	if _camera == null:
		return
	var before := _camera.position
	center_on_grid(gx, gy)
	var after := _camera.position
	if after.distance_to(before) < 0.01:
		return
	_camera.position = before
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_camera, "position", after, duration)

## Recadre la caméra sur un rectangle exprimé en cases.
func focus_grid_rect(rect: Rect2, margin: float = 1.6) -> void:
	if _camera == null or rect.size == Vector2.ZERO:
		return
	if table_view:
		# Vue table : recentre le point visé (la distance suit le zoom courant).
		_table_target = Vector2(
			rect.get_center().x * _cell_size,
			rect.get_center().y * _cell_size
		)
		_update_ortho_size()
		zoom_changed.emit(zoom)
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
		var needed := maxf(extent.y, extent.x / aspect)
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
		if _meshes_layer and _meshes_layer.has_method("set_mesh_position"):
			_meshes_layer.set_mesh_position(element_id, gx, gy)
		if _lights_layer and _lights_layer.has_method("set_light_position"):
			_lights_layer.set_light_position(element_id, gx, gy)
		return
	node.position.x = gx * _cell_size + _cell_size * 0.5
	node.position.z = gy * _cell_size + _cell_size * 0.5
	if node.has_method("apply_terrain_y"):
		node.apply_terrain_y()
	if node.has_method("get_token_id"):
		node.token_data["x"] = gx
		node.token_data["y"] = gy

func set_element_light_radius(element_id: String, radius_cells: float) -> void:
	if _lights_layer and _lights_layer.has_method("set_light_radius"):
		_lights_layer.set_light_radius(element_id, radius_cells)

## Met à jour le masque nuit/jour sans recharger le sol (déplacement de lumières).
func refresh_night_light_mask(light_sources: Array, light_revealed: Array = []) -> void:
	if _ground == null or not _ground.has_method("update_light_mask"):
		return
	if _ground.has_method("is_night_active") and not _ground.is_night_active():
		return
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	_ground.update_light_mask(w, h, light_sources, light_revealed)

func has_element_node(element_id: String) -> bool:
	if _props_layer and _props_layer.has_method("has_prop") and _props_layer.has_prop(element_id):
		return true
	if _meshes_layer and _meshes_layer.has_method("has_mesh") and _meshes_layer.has_mesh(element_id):
		return true
	return _token_nodes.has(element_id) or _effect_nodes.has(element_id) or _zone_nodes.has(element_id)

func set_editor_mode(on: bool) -> void:
	editor_mode = on
	if on:
		_token_drag = null
		_token_press_candidate = null
		_pending_click = false
		_clear_area_hover()
	_sync_areas_overlay()
	_apply_session_zone_visibility()

func _sync_areas_overlay() -> void:
	if _areas_overlay == null or not _areas_overlay.has_method("configure"):
		return
	# En éditeur, l'overlay dédié de l'éditeur dessine déjà les lieux / zones.
	if editor_mode:
		_areas_overlay.configure(null, {}, [])
	else:
		_areas_overlay.configure(self, map_data, _zones)

func _apply_session_zone_visibility() -> void:
	for zid in _zone_nodes:
		var node = _zone_nodes[zid]
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("set_hover_only"):
			node.set_hover_only(not editor_mode)
		if node.has_method("set_highlighted"):
			# En session le disque 3D reste éteint : l'overlay 2D peint le survol.
			node.set_highlighted(editor_mode)

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
	return node != null and node.get_script() == MapToken3DScript

func _process(delta: float) -> void:
	_update_camera_debug()
	_update_occlusion_fade()
	_sync_token_overlay_positions()
	if _token_drag:
		var world := _raycast_ground(_control_to_viewport(get_local_mouse_position()))
		if world != Vector3.INF:
			_token_drag.update_drag_world(world)
		return
	if _pan_velocity.length() < PAN_INERTIA_MIN:
		return
	if table_view:
		# Pas d'inertie de translation en orbite : on retombe simplement.
		_pan_velocity = Vector2.ZERO
		return
	_camera.position.x += _pan_velocity.x * delta
	_camera.position.z += _pan_velocity.y * delta
	_pan_velocity *= pow(PAN_INERTIA_DECAY, delta * 60.0)
	_clamp_camera()
	if not editor_mode and _pan_velocity.length() < PAN_INERTIA_MIN:
		_update_area_hover(get_local_mouse_position())

func _update_occlusion_fade() -> void:
	if _camera == null or _meshes_layer == null or not is_instance_valid(_meshes_layer):
		return
	if not _meshes_layer.has_method("set_occlusion_fade"):
		return
	var token_id := _selected_token_id
	if token_id.is_empty() or not _token_nodes.has(token_id):
		if _token_nodes.is_empty():
			return
		token_id = str(_token_nodes.keys()[0])
	var node = _token_nodes.get(token_id)
	if node == null or not is_instance_valid(node):
		return
	_meshes_layer.set_occlusion_fade(_camera.global_position, node.global_position)

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
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# Ombre/contour 2D derrière le perso pour le détacher du fond illustré.
		var night := MapData.is_night_mode(map_data)
		var outline := TextureRect.new()
		outline.texture = tex
		outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		outline.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.modulate = Color(1.0, 0.78, 0.32, 0.82) if night else Color(0, 0, 0, 0.9)
		outline.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var name_lbl := Label.new()
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.98, 0.93, 0.78, 1.0))
		name_lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.0, 0.92))
		name_lbl.add_theme_constant_override("outline_size", 5 if night else 3)
		name_lbl.text = _overlay_token_label(node)
		name_lbl.visible = not name_lbl.text.is_empty()
		_token_overlay.add_child(outline)
		_token_overlay.add_child(icon)
		_token_overlay.add_child(name_lbl)
		_overlay_icons[tid] = {"icon": icon, "outline": outline, "name": name_lbl, "night": night}
	_sync_token_overlay_positions()

func _overlay_token_label(node) -> String:
	if node == null or not ("token_data" in node) or not (node.token_data is Dictionary):
		return ""
	var data: Dictionary = node.token_data
	var label := str(data.get("label", data.get("name", ""))).strip_edges()
	if not label.is_empty():
		return label
	if str(data.get("kind", "")) != "member":
		return ""
	var mid := str(data.get("memberId", ""))
	for member_variant in _party:
		if typeof(member_variant) != TYPE_DICTIONARY:
			continue
		if str(member_variant.get("id", "")) == mid:
			return str(member_variant.get("name", "")).strip_edges()
	return ""

func _sync_token_overlay_positions() -> void:
	if _token_overlay == null or _camera == null or _overlay_icons.is_empty():
		return
	var vp_size := Vector2(_viewport.size)
	if vp_size.x < 1.0 or vp_size.y < 1.0:
		return
	var scale := Vector2.ONE / _viewport_pixel_scale() # px viewport → unités Control
	var origin_vp: Vector2 = _camera.unproject_position(Vector3.ZERO)
	var cell_vp: Vector2 = _camera.unproject_position(Vector3(_cell_size, 0.0, 0.0))
	var px_per_cell := absf((cell_vp.x - origin_vp.x) * scale.x)
	if px_per_cell < 4.0:
		px_per_cell = 48.0
	for tid in _overlay_icons:
		var entry = _overlay_icons[tid]
		var icon: TextureRect = entry["icon"] if entry is Dictionary else entry
		var outline: TextureRect = entry["outline"] if entry is Dictionary else null
		var name_lbl: Label = entry["name"] if entry is Dictionary else null
		var night := bool(entry.get("night", false)) if entry is Dictionary else false
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
			var grow := 5.0 if night else 3.0
			outline.size = Vector2(px_w + grow * 2.0, px_h + grow * 2.0)
			outline.position = pos - Vector2(grow, grow)
		if name_lbl != null:
			name_lbl.reset_size()
			var nsz := name_lbl.get_combined_minimum_size()
			name_lbl.size = Vector2(maxf(nsz.x, px_w), nsz.y)
			name_lbl.position = Vector2(feet_px.x - name_lbl.size.x * 0.5, pos.y + px_h + 2.0)

## Choix de la figurine 3D d'un token en carte 2.5D (kit v6) :
## classe du personnage, nom/label (créatures), puis repli par hash.
func _figurine_asset_for_token(tok: Dictionary) -> String:
	var kind := str(tok.get("kind", "token"))
	if kind in ["marker", "object", "area", "light"]:
		return ""
	var member: Dictionary = {}
	var member_id := str(tok.get("memberId", ""))
	if not member_id.is_empty():
		for member_variant in _party:
			if str((member_variant as Dictionary).get("id", "")) == member_id:
				member = member_variant
				break
	var text := "%s %s %s" % [
		str(member.get("class", "")), str(tok.get("label", "")), str(tok.get("name", ""))
	]
	text = text.to_lower()
	var root := "res://assets/objects3d/props/"
	# Créatures d'abord (nom explicite).
	var creature_keywords := [
		["gobelin", "pnj_gobelin"], ["squelet", "pnj_squelette"],
	]
	for pair in creature_keywords:
		if text.find(str(pair[0])) >= 0:
			return root + str(pair[1]) + ".glb"
	# Classes / rôles.
	var class_keywords := [
		["arch", "pnj_archere"], ["archer", "pnj_archere"],
		["mage", "pnj_mage"], ["magicien", "pnj_mage"], ["sorcier", "pnj_mage"],
		["voleu", "pnj_voleuse"], ["roubl", "pnj_voleuse"], ["assassin", "pnj_voleuse"],
		["pretr", "pnj_pretresse"], ["clerc", "pnj_pretresse"], ["prêtre", "pnj_pretresse"],
		["garde", "pnj_garde"], ["guerrier", "pnj_garde"], ["paladin", "pnj_garde"],
		["march", "pnj_marchand"], ["village", "pnj_villageois"], ["paysan", "pnj_villageois"],
		["aventur", "pnj_aventurier"], ["héro", "pnj_aventurier"], ["hero", "pnj_aventurier"],
	]
	for pair in class_keywords:
		if text.find(str(pair[0])) >= 0:
			return root + str(pair[1]) + ".glb"
	# Repli : variété déterministe parmi les humanoïdes.
	var humans := [
		"pnj_aventurier", "pnj_archere", "pnj_mage", "pnj_voleuse",
		"pnj_pretresse", "pnj_garde", "pnj_marchand", "pnj_villageois",
	]
	var key := str(tok.get("memberId", tok.get("label", "héros")))
	var idx: int = abs(int(key.hash())) % humans.size()
	return root + humans[idx] + ".glb"

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
			if not mb.ctrl_pressed:
				return
			_apply_zoom(1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.ctrl_pressed:
				return
			_apply_zoom(1.0 / 1.1, mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var picked := null if readonly else _pick_token(mb.position)
				_token_click_candidate = picked
				_token_press_candidate = picked if _token_is_movable(picked) else null
				_token_drag = null
				_pending_click = true
				_pan_dragging = false
				_pan_velocity = Vector2.ZERO
				# Shift + glisser = déplacer la caméra sans tourner.
				_begin_view_drag(mb.position, mb.shift_pressed)
				accept_event()
			else:
				if _token_drag:
					_token_drag.end_drag()
					_token_drag = null
					mouse_default_cursor_shape = Control.CURSOR_ARROW
				elif _pending_click and not _pan_dragging:
					if _token_click_candidate != null:
						_on_token_selected(_token_node_id(_token_click_candidate))
					else:
						_handle_map_click(mb.position, mb.double_click)
				_token_press_candidate = null
				_token_click_candidate = null
				_pan_dragging = false
				_pending_click = false
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_dragging = mb.pressed
			_pending_click = false
			_token_drag = null
			_pan_velocity = Vector2.ZERO
			if mb.pressed:
				# Molette du milieu = déplacer la caméra sans tourner.
				_begin_view_drag(mb.position, true)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# Geste de lancer (vue table) : le dé apparaît au clic pressé et suit
			# la souris ; le LÂCHER le relâche avec la vitesse du geste.
			if table_view:
				if mb.pressed:
					var world := _raycast_ground(_control_to_viewport(mb.position))
					if world != Vector3.INF:
						begin_dice_throw(world, mb.position)
					accept_event()
				else:
					end_dice_throw(mb.position)
					accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _token_press_candidate != null and _token_drag == null:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_token_drag = _token_press_candidate
				_token_drag.begin_drag()
				_pending_click = false
				_pan_dragging = false
				_token_press_candidate = null
				mouse_default_cursor_shape = Control.CURSOR_DRAG
		if _token_drag:
			var world := _raycast_ground(_control_to_viewport(motion.position))
			if world != Vector3.INF:
				_token_drag.update_drag_world(world)
			accept_event()
			return
		if _dice != null and is_instance_valid(_dice) and _dice.held_count() > 0:
			# Dé tenu par le clic droit : il suit la souris (visée avant lancer).
			update_dice_throw(motion.position)
			accept_event()
			return
		if _pending_click and not _pan_dragging:
			if _drag_start.distance_to(motion.position) >= DRAG_THRESHOLD:
				_pan_dragging = true
				_pending_click = false
				_token_press_candidate = null
		if _pan_dragging:
			_pan_from_motion(motion)
			accept_event()
		else:
			_update_area_hover(motion.position)
			_update_move_pointer(motion.position)

## Applique le déplacement de vue correspondant à un mouvement souris.
func _pan_from_motion(motion: InputEventMouseMotion) -> void:
	if table_view:
		_table_orbit_from_motion(motion.position)
		return
	var delta_pos := motion.position - _drag_start
	var span := _ground_span_per_pixel()
	# Sécurité : une mesure de span aberrante ne doit pas téléporter la vue.
	span.x = clampf(span.x, 0.002, 0.35)
	span.y = clampf(span.y, 0.002, 0.35)
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
## Annule tout état de navigation en cours (changement d'outil, clic gauche).
func cancel_navigation_drag() -> void:
	_right_nav_down = false
	_right_nav_dragging = false
	_orbit_dragging = false
	_pan_dragging = false
	_pan_velocity = Vector2.ZERO

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
				_pan_velocity = Vector2.ZERO
				if mb.pressed:
					if mb.shift_pressed:
						# Maj + clic milieu : déplacer la vue (pan).
						_pan_dragging = true
						_orbit_dragging = false
						_begin_view_drag(mb.position, true)
					else:
						# Clic milieu : orbiter librement autour du point visé.
						_pan_dragging = false
						_begin_orbit_drag(mb.position)
				else:
					_orbit_dragging = false
					_pan_dragging = false
				accept_event()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					# Un clic gauche est une action d'édition : on ne doit jamais
					# laisser un état de pan/orbite d'un clic droit précédent.
					cancel_navigation_drag()
					grab_focus()
					editor_pointer_pressed.emit(_screen_to_grid(mb.position), mb.position, mb.button_index, _mods(mb))
				else:
					editor_pointer_released.emit(_screen_to_grid(mb.position), mb.position, mb.button_index, _mods(mb))
				accept_event()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					# Clic droit : glisser pour naviguer en 3D ; un simple clic
					# (sans déplacement) ouvrira le menu contextuel au relâchement.
					grab_focus()
					_right_nav_down = true
					_right_nav_dragging = false
					_right_nav_shift = mb.shift_pressed
					_right_nav_start = mb.position
					_orbit_dragging = false
					_pan_dragging = false
					accept_event()
				else:
					var was_dragging := _right_nav_dragging
					_right_nav_down = false
					_right_nav_dragging = false
					_orbit_dragging = false
					_pan_dragging = false
					if not was_dragging:
						# Menu contextuel habituel conservé pour un vrai clic.
						editor_pointer_pressed.emit(_screen_to_grid(mb.position), mb.position, MOUSE_BUTTON_RIGHT, _mods(mb))
						editor_pointer_released.emit(_screen_to_grid(mb.position), mb.position, MOUSE_BUTTON_RIGHT, _mods(mb))
					accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _right_nav_down:
			if not _right_nav_dragging \
					and motion.position.distance_to(_right_nav_start) >= 4.0:
				_right_nav_dragging = true
				if _right_nav_shift:
					# Maj + clic droit : orbite.
					_pan_dragging = false
					_begin_orbit_drag(_right_nav_start)
				else:
					# Clic droit glissé : déplacer la vue (pan).
					_pan_dragging = true
					_orbit_dragging = false
					_begin_view_drag(_right_nav_start, true)
			if _right_nav_dragging:
				if _right_nav_shift:
					_update_orbit_drag(motion.position)
				else:
					_pan_from_motion(motion)
				accept_event()
				return
			if not _right_nav_dragging:
				accept_event()
				return
		if _orbit_dragging:
			_update_orbit_drag(motion.position)
			accept_event()
			return
		if _pan_dragging:
			_pan_from_motion(motion)
			accept_event()
			return
		editor_pointer_moved.emit(_screen_to_grid(motion.position), motion.position, _mods(motion))

## Déplacement de vue piloté par l'éditeur (outil « main », espace maintenu) —
## c'est un pan : déplacer la caméra sans la tourner.
func begin_view_pan(screen_pos: Vector2, pan_mode: bool = true) -> void:
	_orbit_dragging = false
	_orbit_enabled = false
	_pan_dragging = true
	_pan_velocity = Vector2.ZERO
	_begin_view_drag(screen_pos, pan_mode)

## Démarre une orbite 3D autour du point visé (clic milieu, mode éditeur).
func _begin_orbit_drag(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	_orbit_dragging = true
	_orbit_enabled = true
	_pan_dragging = false
	var center := size * 0.5
	var world := _raycast_ground(_control_to_viewport(center))
	if world == Vector3.INF:
		world = Vector3(_camera.position.x, 0.0, _camera.position.z)
	_orbit_target = world
	_orbit_distance = maxf(12.0, _camera.position.distance_to(world))
	_orbit_start = screen_pos
	_orbit_start_yaw = _camera.rotation_degrees.y
	_orbit_start_pitch = _camera.rotation_degrees.x
	_orbit_yaw = _orbit_start_yaw
	_orbit_pitch = _orbit_start_pitch

func _update_orbit_drag(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var delta := screen_pos - _orbit_start
	_orbit_yaw = _orbit_start_yaw - delta.x * 0.38
	_orbit_pitch = clampf(_orbit_start_pitch - delta.y * 0.28, -89.0, -8.0)
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(_orbit_pitch), deg_to_rad(_orbit_yaw), 0.0))
	var forward := -basis.z
	var cam_pos := _orbit_target - forward * _orbit_distance
	_camera.global_transform = Transform3D(basis, cam_pos)
	view_changed.emit()

## Réinitialise la caméra d'édition sur l'angle du style courant.
func reset_editor_camera() -> void:
	_orbit_dragging = false
	_orbit_enabled = false
	_apply_camera_perspective()
	request_fit_to_view()
	view_changed.emit()

func update_view_pan(screen_pos: Vector2) -> void:
	if not _pan_dragging or _camera == null:
		return
	if table_view:
		_table_orbit_from_motion(screen_pos)
		view_changed.emit()
		return
	var delta_pos := screen_pos - _drag_start
	var span := _ground_span_per_pixel()
	span.x = clampf(span.x, 0.002, 0.35)
	span.y = clampf(span.y, 0.002, 0.35)
	_camera.position.x = _pan_start.x - delta_pos.x * span.x
	_camera.position.z = _pan_start.z - delta_pos.y * span.y
	_clamp_camera()
	view_changed.emit()

func end_view_pan() -> void:
	_pan_dragging = false
	_pan_velocity = Vector2.ZERO
	if not editor_mode:
		_update_area_hover(get_local_mouse_position())

## Mémorise l'état de départ d'un drag de vue (pan OU orbite table).
## `pan_mode` : true = déplacer la caméra sans tourner (Shift+glisser).
func _begin_view_drag(screen_pos: Vector2, pan_mode: bool = false) -> void:
	_drag_start = screen_pos
	_pan_start = _camera.position if _camera != null else Vector3.ZERO
	_last_pan_pos = screen_pos
	_table_drag_yaw = _table_yaw
	_table_drag_elev = _table_elev
	_drag_pan_mode = pan_mode
	_table_drag_target_start = _table_target

# ===========================================================================
# Vue table (plateau virtuel)
# ===========================================================================
#
# La carte devient le plan de jeu posé sur une table de taverne ; la caméra
# orbite depuis une des quatre places autour de la table (drag = tourner autour
# du plateau, molette = s'approcher / s'éloigner, « Cadrer » = table entière).

func set_table_view(on: bool) -> void:
	if not is_node_ready():
		await ready
	if table_view == on:
		if on:
			_sync_table_environment()
		return
	table_view = on
	if on:
		_sync_table_environment()
		if _table_env != null and _table_env.has_method("set_active_seat"):
			_table_env.set_active_seat(_table_seat)
		_table_target = _map_extent * 0.5
		_apply_ambient_for_table()
	else:
		if _table_env != null and is_instance_valid(_table_env):
			_table_env.queue_free()
		_table_env = null
		_apply_ambient_for_table()
	_apply_camera_perspective()
	_apply_lighting()
	# Les tokens changent de style en basculant (pions sur la table).
	if not map_data.is_empty():
		_rebuild_layers()
	if not table_view:
		request_fit_to_view()
	view_changed.emit()

func is_table_view() -> bool:
	return table_view

## Place occupée autour de la table : 0=sud, 1=est, 2=nord, 3=ouest.
func get_table_seat() -> int:
	return _table_seat

func set_table_seat(index: int) -> void:
	_table_seat = wrapi(index, 0, 4)
	_table_yaw = float(_table_seat * 90)
	if _table_env != null and _table_env.has_method("set_active_seat"):
		_table_env.set_active_seat(_table_seat)
	_update_ortho_size()
	zoom_changed.emit(zoom)

func cycle_table_seat(direction: int = 1) -> void:
	set_table_seat(_table_seat + direction)

func table_seat_label(index: int = -1) -> String:
	if _table_env != null and _table_env.has_method("seat_label"):
		return str(_table_env.seat_label(_table_seat if index < 0 else index))
	return ""

## Libellés des places autour de la table (joueurs + MJ), 0..3.
func set_table_seat_labels(labels: Array) -> void:
	_table_seat_labels = labels.duplicate()
	if _table_env != null and _table_env.has_method("set_seat_labels"):
		_table_env.set_seat_labels(_table_seat_labels)

## Inclinaison de vue par place (ex. MJ plus haut pour tout voir).
func set_table_elevation(deg: float) -> void:
	_table_elev = clampf(deg, TABLE_ELEV_MIN, TABLE_ELEV_MAX)
	_table_drag_elev = _table_elev
	_update_ortho_size()

## Couleur des dés du joueur courant.
func set_table_dice_color(color: Color) -> void:
	_dice_color = color

## Type de dé à lancer : 4, 6, 8, 10, 12, 20 ou 100 (vrai dé à 100 faces).
func set_table_dice_sides(sides: int) -> void:
	_dice_sides = sides if sides in [4, 6, 8, 10, 12, 20, 100] else 6

func get_table_dice_sides() -> int:
	return _dice_sides

## Lancer de dés à un point du plateau (clic droit = « où l'on veut »).
## **Un clic = un seul dé**, quel que soit son type (d100 = vrai dé 100 faces).
## Les dés s'accumulent sur la table. Le verdict d'atterrissage arrive via
## `table_dice_result`.
func roll_table_dice_at(world: Vector3, count: int = -1) -> void:
	if not table_view or _table_env == null:
		return
	_ensure_dice()
	var n := count
	if n <= 0:
		n = 1
	if _dice.has_method("roll"):
		_dice.roll(n, world, _dice_color, _dice_sides)

func _ensure_dice() -> void:
	if _dice == null or not is_instance_valid(_dice):
		_dice = TableDice3DScript.new()
		_dice.name = "TableDice"
		_world.add_child(_dice)
		_dice.dice_settled.connect(_on_dice_settled)

# --------------------------------------------------------------------------
# Geste de lancer (clic droit) : le dé APPARAÎT au clic et suit la souris,
# le LÂCHER du clic le relâche avec la vitesse calculée du geste de souris.
# --------------------------------------------------------------------------

func begin_dice_throw(world: Vector3, screen_pos: Vector2) -> void:
	if not table_view or _table_env == null:
		return
	_ensure_dice()
	if _dice.held_count() > 0:
		_dice.release_held(Vector3.ZERO, Vector3(0.0, 1.0, 0.0))
	_dice.hold_die(world, _dice_color, _dice_sides)
	_throw_samples.clear()
	_throw_samples.append({"pos": screen_pos, "t": Time.get_ticks_msec()})

func update_dice_throw(screen_pos: Vector2) -> void:
	if _dice == null or not is_instance_valid(_dice) or _dice.held_count() == 0:
		return
	var world := _raycast_ground(_control_to_viewport(screen_pos))
	if world != Vector3.INF:
		_dice.move_held(world)
	_record_throw_sample(screen_pos)

func end_dice_throw(screen_pos: Vector2) -> void:
	if _dice == null or not is_instance_valid(_dice) or _dice.held_count() == 0:
		return
	_record_throw_sample(screen_pos)
	_dice.release_held(_throw_velocity_world(), _throw_spin())
	_throw_samples.clear()

func _record_throw_sample(screen_pos: Vector2) -> void:
	_throw_samples.append({"pos": screen_pos, "t": Time.get_ticks_msec()})
	while _throw_samples.size() > 2 \
		and Time.get_ticks_msec() - int(_throw_samples[0]["t"]) > 220:
		_throw_samples.pop_front()

## Vitesse du dé = mouvement de la souris au moment du lancer (fenêtre ~150 ms),
## converti px/s → unités monde (plan du sol) et projeté sur les axes caméra.
func _throw_velocity_world() -> Vector3:
	if _throw_samples.size() < 2:
		return Vector3(0.0, 0.4, 0.0)
	var first: Dictionary = _throw_samples[0]
	for s_variant in _throw_samples:
		var s: Dictionary = s_variant
		if int(s["t"]) >= Time.get_ticks_msec() - 150:
			first = s
			break
	var last: Dictionary = _throw_samples[_throw_samples.size() - 1]
	var dt := maxf(float(int(last["t"]) - int(first["t"])) / 1000.0, 0.016)
	var delta: Vector2 = (last["pos"] as Vector2) - (first["pos"] as Vector2)
	var px_per_s := delta / dt
	var span := _ground_span_per_pixel()
	var right := Vector3.RIGHT
	var fwd := Vector3(0.0, 0.0, -1.0)
	if _camera != null:
		var basis := _camera.global_transform.basis
		var r := Vector3(basis.x.x, 0.0, basis.x.z)
		var f := Vector3(-basis.z.x, 0.0, -basis.z.z)
		if r.length_squared() > 0.0001:
			right = r.normalized()
		if f.length_squared() > 0.0001:
			fwd = f.normalized()
	var vel := right * (px_per_s.x * span.x) + fwd * (-px_per_s.y * span.y)
	var flat := Vector3(vel.x, 0.0, vel.z)
	var max_speed := 7.0
	if flat.length() > max_speed:
		flat = flat.normalized() * max_speed
	# Petit lob : plus le geste est vif, plus le dé part vers le haut.
	flat.y = clampf(flat.length() * 0.3 + 0.3, 0.3, 3.0)
	return flat

func _throw_spin() -> Vector3:
	return Vector3(
		randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)
	)

func _on_dice_settled(faces: Array, positions: Array, droit: PackedByteArray) -> void:
	# Règle maison : ça compte si le dé finit **droit**, où qu'il soit tombé.
	var valid := positions.size() > 0
	for d in droit:
		if d == 0:
			valid = false
	var total := 0
	if _dice_sides == 100:
		# Vrai dé à 100 faces : la face du dessus est le résultat (1-100).
		total = int(faces[0]) if faces.size() > 0 else 0
	elif _dice_sides == 10:
		# d10 chiffres 0-9 : le 0 vaut 10.
		for f_variant in faces:
			var v := int(f_variant)
			total += 10 if v == 0 else v
	else:
		for f_variant in faces:
			total += int(f_variant)
	table_dice_result.emit(faces, total, valid)

func _sync_table_environment() -> void:
	if not table_view or _world == null:
		return
	if _table_env == null or not is_instance_valid(_table_env):
		_table_env = TableEnvironmentScript.new()
		_table_env.name = "TableEnv"
		_world.add_child(_table_env)
		_world.move_child(_table_env, 0)
	if _map_extent != Vector2.ZERO and _table_env.has_method("configure"):
		_table_env.configure(_map_extent)
	if not _table_seat_labels.is_empty() and _table_env.has_method("set_seat_labels"):
		_table_env.set_seat_labels(_table_seat_labels)

## Ambiance salle : fond sombre chaud, lumière ambiante tamisée (la table
## est éclairée par sa propre suspension — cf. TableEnvironment3D).
func _apply_ambient_for_table() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env := _world_env.environment
	if table_view:
		env.background_color = Color(0.04, 0.03, 0.03)
		env.ambient_light_color = Color(0.42, 0.33, 0.24)
		env.ambient_light_energy = 0.32
	else:
		env.background_color = Color(0.06, 0.05, 0.08)
		env.ambient_light_color = Color(0.42, 0.38, 0.48)
		env.ambient_light_energy = 0.55

## Point visé au sol (x, z), centré sur la table sauf recentrage demandé.
func _table_target_point() -> Vector3:
	var t := _table_target
	if _map_extent != Vector2.ZERO:
		t = Vector2(
			clampf(t.x, 0.0, _map_extent.x),
			clampf(t.y, 0.0, _map_extent.y)
		)
	return Vector3(t.x, 0.45, t.y)

## Distance caméra bornée pour ne jamais traverser le plateau ni partir trop loin.
func _table_dist_limits() -> Vector2:
	var size_t: Vector2 = _table_env.table_size_with_margin() \
		if _table_env != null and _table_env.has_method("table_size_with_margin") else _map_extent
	var ref := maxf(maxf(size_t.x, size_t.y), 1.0)
	return Vector2(ref * 0.3, ref * 2.2)

## Distance (zoom=1) cadrant toute la table depuis la place active.
## Ajustée par projection réelle des coins de la table : en perspective
## inclinée le sol visible est un trapèze, les estimations « span × pixels »
## dérapent vite aux faibles angles (et comptent mal les échelles DPI).
func _update_table_fit() -> void:
	if _camera == null or _map_extent == Vector2.ZERO:
		return
	var size_t: Vector2 = _table_env.table_size_with_margin() \
		if _table_env != null and _table_env.has_method("table_size_with_margin") \
		else _map_extent + Vector2(1.2, 1.2) * 2.0
	var target := _table_target_point()
	var elev_r := deg_to_rad(_table_elev)
	var yaw_r := deg_to_rad(_table_yaw)
	var back := Vector3(sin(yaw_r) * cos(elev_r), sin(elev_r), cos(yaw_r) * cos(elev_r))
	var aspect := maxf(_viewport_aspect(), 0.4)
	var fov_y := deg_to_rad(TABLE_FOV)
	var fov_x := 2.0 * atan(tan(fov_y * 0.5) * aspect)
	var d_w := (size_t.x * 0.5) / tan(fov_x * 0.5)
	var d_h := (size_t.y * 0.5) / maxf(tan(fov_y * 0.5) * sin(elev_r), 0.15)
	var dist := maxf(d_w, d_h) * 1.05
	var limits := _table_dist_limits()
	var corners := _table_corner_worlds(size_t)
	for _pass in range(8):
		dist = clampf(dist, limits.x, limits.y)
		_camera.position = target + back * dist
		_camera.look_at(target)
		var factor := _table_frame_factor(corners)
		if factor <= 0.0:
			break
		if absf(factor - 1.0) < 0.02:
			break
		dist *= clampf(factor, 0.4, 2.5) * 1.01
	_table_dist_base = clampf(dist, limits.x, limits.y)

## Coins monde (y=0) du plateau à cadrer (plan de jeu + marge).
func _table_corner_worlds(size_t: Vector2) -> PackedVector3Array:
	var c := Vector3(_map_extent.x * 0.5, 0.0, _map_extent.y * 0.5)
	var hx := size_t.x * 0.5
	var hz := size_t.y * 0.5
	return PackedVector3Array([
		Vector3(c.x - hx, 0.0, c.z - hz),
		Vector3(c.x + hx, 0.0, c.z - hz),
		Vector3(c.x - hx, 0.0, c.z + hz),
		Vector3(c.x + hx, 0.0, c.z + hz),
	])

## Facteur d'échelle pour que le cadre des coins remplisse la zone utile :
## 1.0 = parfaitement cadré, >1 = encore trop grand (faut reculer), 0 = N/A.
func _table_frame_factor(corners: PackedVector3Array) -> float:
	if _camera == null or corners.size() < 4:
		return 0.0
	var usable := _usable_viewport_size()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for corner in corners:
		if _camera.is_position_behind(corner):
			return 2.5
		var p := _viewport_to_control(_camera.unproject_position(corner))
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var need := max_p - min_p
	if need.x <= 0.0 or need.y <= 0.0:
		return 0.0
	return maxf(need.x / maxf(usable.x, 1.0), need.y / maxf(usable.y, 1.0))

## Place la caméra à la place active : orbite autour du point visé.
func _apply_table_camera() -> void:
	if _camera == null or not table_view:
		return
	var target := _table_target_point()
	var elev_r := deg_to_rad(clampf(_table_elev, TABLE_ELEV_MIN, TABLE_ELEV_MAX))
	var yaw_r := deg_to_rad(_table_yaw)
	var back := Vector3(sin(yaw_r) * cos(elev_r), sin(elev_r), cos(yaw_r) * cos(elev_r))
	var limits := _table_dist_limits()
	var dist := clampf(_table_dist_base / maxf(zoom, 0.001), limits.x, limits.y)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = TABLE_FOV
	_camera.position = target + back * dist
	if _camera.position.distance_to(target) > 0.01:
		_camera.look_at(target)

## Drag de vue en cours sur la table : Shift/molette du milieu = pan (déplacer
## sans tourner), sinon = orbite (tourner autour du plateau).
func _table_orbit_from_motion(screen_pos: Vector2) -> void:
	if _drag_pan_mode:
		_table_pan_from_motion(screen_pos)
		return
	var delta_pos := screen_pos - _drag_start
	_table_yaw = _table_drag_yaw - delta_pos.x * 0.32
	_table_elev = clampf(_table_drag_elev + delta_pos.y * 0.18, TABLE_ELEV_MIN, TABLE_ELEV_MAX)
	_update_ortho_size()

## Déplacement latéral de la caméra (axe/yaw/inclinaison inchangés) : la scène
## suit le curseur. Le point visé glisse dans le plan du sol.
func _table_pan_from_motion(screen_pos: Vector2) -> void:
	if _camera == null:
		return
	var delta := screen_pos - _drag_start
	var span := _ground_span_per_pixel()
	var k := (span.x + span.y) * 0.5
	var basis := _camera.global_transform.basis
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	var fwd := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if right.length_squared() > 0.0001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
	else:
		fwd = Vector3(0, 0, -1)
	var move := -right * delta.x * k + fwd * delta.y * k
	_table_target = _table_drag_target_start + Vector2(move.x, move.z)
	_update_ortho_size()

func _handle_map_click(screen_pos: Vector2, double_click: bool = false) -> void:
	var grid := _screen_to_grid(screen_pos)
	var gx := grid.x
	var gy := grid.y
	# Navigation d'échelle : coords flottantes (le snap casserait le hit-test du lieu).
	if not editor_mode:
		var area := MapData.get_area_at(map_data, gx, gy)
		if not area.is_empty() and not str(area.get("targetMapId", "")).is_empty():
			if double_click:
				area_activate_requested.emit(area)
			else:
				area_clicked.emit(area)
			return
	if snap_to_grid:
		gx = roundf(gx)
		gy = roundf(gy)
	var w: int = map_data.get("width", 16)
	var h: int = map_data.get("height", 12)
	if gx < 0 or gy < 0 or gx >= w or gy >= h:
		return

	if readonly and not is_gm:
		return

	var mode: String = session_tool.get("mode", "select")
	if mode == "fog" and is_gm:
		var brush: int = maxi(0, int(session_tool.get("fogRadius", 1)))
		fog_revealed.emit(_fog_brush_cells(int(gx), int(gy), brush))
		return
	if mode == "fog_hide" and is_gm:
		var brush_h: int = maxi(0, int(session_tool.get("fogRadius", 1)))
		fog_hidden.emit(_fog_brush_cells(int(gx), int(gy), brush_h))
		return
	if mode in ["select", "pan", ""]:
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
	if editor_mode:
		return
	var grid := _screen_to_grid(screen_pos)
	var area := MapData.get_area_at(map_data, grid.x, grid.y)
	var zone: Dictionary = MapZone3DScript.pick_at(_zones, grid.x, grid.y)
	var aid := str(area.get("id", ""))
	var zid := str(zone.get("id", ""))
	var linked := not aid.is_empty() and not str(area.get("targetMapId", "")).is_empty()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if linked else Control.CURSOR_ARROW
	if aid == _hovered_area_id and zid == _hovered_zone_id:
		return
	_hovered_area_id = aid
	_hovered_zone_id = zid
	if _areas_overlay and _areas_overlay.has_method("set_hovered"):
		_areas_overlay.set_hovered(aid)
	if _areas_overlay and _areas_overlay.has_method("set_hovered_zone"):
		_areas_overlay.set_hovered_zone(zone)
	_apply_session_zone_visibility()
	if not area.is_empty():
		area_hovered.emit(area)
	elif not zone.is_empty():
		area_hovered.emit(zone)
	else:
		area_hovered.emit({})

func trigger_effect(effect_id: String) -> void:
	if _effect_nodes.has(effect_id):
		var node = _effect_nodes[effect_id]
		node.trigger()
	effect_trigger_requested.emit(effect_id)

## Échelle réellement affichée : pixels écran par case de grille.
##
## `zoom` est relatif au cadrage « carte entière » : l'afficher en pourcentage
## ment (zoom=1 sur une carte de 60 cases n'a rien à voir avec zoom=1 sur une
## carte de 10 cases). On mesure donc la projection au sol.
func get_effective_scale() -> float:
	if _camera == null or _cell_size <= 0.0:
		return 0.0
	var span := _ground_span_per_pixel()
	if span.y < 0.000001:
		return 0.0
	return _cell_size / span.y

func zoom_in() -> void:
	_apply_zoom(1.15, size * 0.5)

func zoom_out() -> void:
	_apply_zoom(1.0 / 1.15, size * 0.5)

func reset_zoom() -> void:
	_fit_to_view()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if map_data.is_empty() or _camera == null or _map_extent == Vector2.ZERO:
			return
		# Les docks/options changent la taille utile : on recalcule les bases de
		# zoom mais on ne touche JAMAIS à la position de la caméra (sinon un
		# simple clic d'outil la téléporte).
		var saved_position := _camera.position
		_update_fit_base()
		_camera.position = saved_position
