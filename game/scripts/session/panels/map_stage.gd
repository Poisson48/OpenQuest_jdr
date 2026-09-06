extends PanelContainer
class_name MapStagePanel

## Hôte des moteurs de carte — et rien d'autre.
## Structure dans `scenes/session/panels/map_stage.tscn` : les deux moteurs y
## sont de vrais nœuds, visibles et déplaçables dans l'éditeur Godot.
##
## Ne lit jamais l'état de partie : il reçoit une charge utile déjà constituée
## et renvoie les interactions brutes. La logique de jeu vit un cran au-dessus,
## dans `map_workspace.gd`.

signal cell_clicked(x: int, y: int)
signal grid_clicked(gx: float, gy: float, tool: Dictionary)
signal token_moved(token_id: String, gx: float, gy: float)
signal fog_revealed(cells: Array)
signal fog_hidden(cells: Array)
signal token_selected(token_id: String)
signal effect_trigger_requested(effect_id: String)
signal area_clicked(area: Dictionary)
signal area_hovered(area: Dictionary)
signal navigation_requested(action: String, data: Dictionary)
signal view_changed

## Insets laissés au HUD joueur en vue immersive (gauche, haut, droite, bas).
const IMMERSIVE_INSET := Vector4(8.0, 56.0, 8.0, 128.0)

@onready var _simple: Control = %SimpleMap
@onready var _complex: Control = %ComplexMap

var _mode: String = MapMode.SIMPLE
var _immersive: bool = false
var _loaded_map_id: String = ""
## Cadrage en attente d'une taille utilisable : voir `_arm_fit()`.
var _pending_fit: bool = false
var _fit_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_theme_stylebox_override("panel", SessionStyle.flat_stylebox(ThemeColors.SURFACE_DEEP, 4))
	_simple.cell_clicked.connect(func(x: int, y: int): cell_clicked.emit(x, y))
	_simple.navigation_requested.connect(func(a: String, d: Dictionary): navigation_requested.emit(a, d))
	_simple.zoom_changed.connect(func(_z: float): view_changed.emit())

	_complex.map_clicked.connect(func(gx: float, gy: float, tool: Dictionary): grid_clicked.emit(gx, gy, tool))
	_complex.token_moved.connect(func(id: String, gx: float, gy: float): token_moved.emit(id, gx, gy))
	_complex.fog_revealed.connect(func(cells: Array): fog_revealed.emit(cells))
	_complex.fog_hidden.connect(func(cells: Array): fog_hidden.emit(cells))
	_complex.token_selected.connect(func(id: String): token_selected.emit(id))
	_complex.effect_trigger_requested.connect(func(id: String): effect_trigger_requested.emit(id))
	_complex.area_clicked.connect(func(area: Dictionary): area_clicked.emit(area))
	_complex.area_hovered.connect(func(area: Dictionary): area_hovered.emit(area))
	_complex.zoom_changed.connect(func(_z: float): view_changed.emit())
	resized.connect(_on_resized)

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------

func configure(payload: Dictionary) -> void:
	if not is_node_ready():
		await ready
	var display_map: Dictionary = payload.get("map", {})
	if display_map.is_empty():
		return
	_mode = str(payload.get("mode", MapMode.SIMPLE))
	var complex_mode := MapMode.is_complex(_mode)
	_simple.visible = not complex_mode
	_complex.visible = complex_mode

	var map_id := str(display_map.get("id", ""))
	if map_id != _loaded_map_id:
		_loaded_map_id = map_id
		_arm_fit()

	if complex_mode:
		_complex.configure(
			display_map,
			payload.get("tokens", []),
			payload.get("party", []),
			payload.get("effects", []),
			payload.get("zones", []),
			payload.get("fog_revealed", []),
			bool(payload.get("readonly", false)),
			bool(payload.get("is_gm", false)),
			payload.get("tool", {}),
			payload.get("view_state", {}),
			str(payload.get("selected_token", "")),
		)
		_complex.set_session_tool(payload.get("tool", {}))
	else:
		_simple.configure(
			display_map,
			payload.get("tokens", []),
			payload.get("party", []),
			payload.get("explored", []),
			str(payload.get("quest_format", "oneshot")),
			bool(payload.get("readonly", false)),
			payload.get("nav_context", {}),
			payload.get("revealed_markers", []),
			payload.get("revealed_links", []),
		)
		var tool: Dictionary = payload.get("tool", {})
		_simple.set_session_tool(str(tool.get("mode", "member")), tool)

	call_deferred("_flush_fit")
	view_changed.emit()

func set_immersive(on: bool) -> void:
	if not is_node_ready():
		await ready
	if _immersive == on:
		return
	_immersive = on
	if _complex.has_method("set_view_inset"):
		if on:
			_complex.set_view_inset(
				IMMERSIVE_INSET.x, IMMERSIVE_INSET.y, IMMERSIVE_INSET.z, IMMERSIVE_INSET.w
			)
		else:
			_complex.set_view_inset(0.0, 0.0, 0.0, 0.0)
	add_theme_stylebox_override("panel", SessionStyle.flat_stylebox(
		ThemeColors.SURFACE_DEEP, 0 if on else 4
	))
	_arm_fit()

# ---------------------------------------------------------------------------
# Navigation de vue
# ---------------------------------------------------------------------------

func active_renderer() -> Control:
	return _complex if MapMode.is_complex(_mode) else _simple

func zoom_in() -> void:
	active_renderer().zoom_in()

func zoom_out() -> void:
	active_renderer().zoom_out()

## Recadrage immédiat, demandé par le MJ (bouton « Cadrer »).
func fit() -> void:
	_pending_fit = false
	_fit_size = size
	var renderer := active_renderer()
	if renderer.has_method("request_fit_to_view"):
		renderer.call_deferred("request_fit_to_view")
	else:
		renderer.call_deferred("reset_zoom")

## Pixels écran par case — l'échelle réellement affichée, pas le facteur interne.
func get_effective_scale() -> float:
	var renderer := active_renderer()
	if renderer.has_method("get_effective_scale"):
		return float(renderer.get_effective_scale())
	return 0.0

func get_view_state() -> Dictionary:
	if MapMode.is_complex(_mode) and _complex.has_method("get_view_state"):
		return _complex.get_view_state()
	return {}

func set_snap_to_grid(on: bool) -> void:
	if _complex.has_method("set_snap_to_grid"):
		_complex.set_snap_to_grid(on)

func play_effect(effect_id: String) -> void:
	if _complex.has_method("trigger_effect"):
		_complex.trigger_effect(effect_id)

func _on_resized() -> void:
	if _pending_fit:
		call_deferred("_flush_fit")

## Arme un cadrage qui n'aura lieu qu'une fois la taille définitive connue.
## Basculer en mode immersif change la géométrie une frame plus tard : cadrer
## tout de suite reviendrait à cadrer sur l'ancienne taille, et la carte
## resterait plantée dans un coin.
func _arm_fit() -> void:
	_pending_fit = true
	call_deferred("_flush_fit")

func _flush_fit() -> void:
	if not _pending_fit or size.x < 32.0 or size.y < 32.0:
		return
	if size.is_equal_approx(_fit_size):
		return
	fit()
