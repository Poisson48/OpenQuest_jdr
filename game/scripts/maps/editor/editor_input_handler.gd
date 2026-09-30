extends RefCounted
class_name EditorInputHandler

## Machine à états d'outils de l'éditeur de cartes.
##
## Interprète les événements souris/clavier et dispatche vers le bon handler.
## Extraite de `map_complex_editor.gd` pour isoler la logique d'interaction.

const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

# --- Modes de pression --------------------------------------------------------
const PRESS_NONE := "none"
const PRESS_PAN := "pan"
const PRESS_MOVE := "move"
const PRESS_RESIZE := "resize"
const PRESS_ROTATE := "rotate"
const PRESS_BAND := "band"
const PRESS_DRAW := "draw"
const PRESS_PAINT := "paint"

# --- État courant -------------------------------------------------------------
var press_mode: String = PRESS_NONE
var press_start_grid: Vector2 = Vector2.ZERO
var press_start_screen: Vector2 = Vector2.ZERO
var press_moved: bool = false
var space_held: bool = false

var drag_ids: Array = []
var drag_origins: Dictionary = {}
var handle_state: Dictionary = {}
var link_source: String = ""
var painted_cells: Dictionary = {}
var band_base_selection: Array = []

## Callbacks injectés par l'éditeur principal (délégation sans dépendance Node).
var on_tool_changed: Callable = Callable()
var on_status: Callable = Callable()
var on_refresh_overlay: Callable = Callable()
var on_refresh_ghost: Callable = Callable()
var on_refresh_panels: Callable = Callable()
var on_sync_engine: Callable = Callable()
var on_place_pose: Callable = Callable()
var on_place_template: Callable = Callable()
var on_finish_draw: Callable = Callable()
var on_paint_terrain: Callable = Callable()
var on_paint_fog: Callable = Callable()
var on_erase_at: Callable = Callable()
var on_handle_link_click: Callable = Callable()
var on_bucket_fill: Callable = Callable()
var on_cancel_action: Callable = Callable()
var on_close_polygon: Callable = Callable()
var on_apply_handle_resize: Callable = Callable()
var on_apply_handle_rotate: Callable = Callable()
var on_start_move_drag: Callable = Callable()
var on_begin_select: Callable = Callable()
var on_begin_pan: Callable = Callable()
var on_update_pan: Callable = Callable()
var on_end_pan: Callable = Callable()
var on_commit_live_edit: Callable = Callable()
var on_revert_live_edit: Callable = Callable()

## Interprète un appui souris et retourne `true` si l'événement est consommé.
func handle_pointer_pressed(grid: Vector2, screen: Vector2, button: int, mods: Dictionary, tool_id: String) -> bool:
	if button == MOUSE_BUTTON_RIGHT:
		_handle_right_click(grid)
		return true
	press_start_grid = grid
	press_start_screen = screen
	press_moved = false
	painted_cells.clear()

	if space_held or tool_id == ToolsScript.PAN:
		press_mode = PRESS_PAN
		on_begin_pan.call(screen)
		return true

	var wants_select := tool_id == ToolsScript.SELECT \
		or bool(mods.get("ctrl", false)) or bool(mods.get("shift", false))
	if wants_select:
		on_begin_select.call(grid, screen, mods)
		return true

	if ToolsScript.is_pose_tool(tool_id):
		on_place_pose.call(grid)
		press_mode = PRESS_NONE
		return true

	if ToolsScript.is_drag_tool(tool_id):
		press_mode = PRESS_DRAW
		return true

	if tool_id == ToolsScript.ZONE_POLY:
		press_mode = PRESS_NONE
		return true

	if tool_id == ToolsScript.PAINT:
		press_mode = PRESS_PAINT
		on_paint_terrain.call(grid)
		return true

	if tool_id == ToolsScript.BUCKET:
		on_bucket_fill.call(grid)
		press_mode = PRESS_NONE
		return true

	if tool_id == ToolsScript.FOG_REVEAL or tool_id == ToolsScript.FOG_HIDE:
		press_mode = PRESS_PAINT
		on_paint_fog.call(grid)
		return true

	if tool_id == ToolsScript.ERASE:
		on_erase_at.call(screen)
		press_mode = PRESS_NONE
		return true

	if tool_id == ToolsScript.LINK:
		on_handle_link_click.call(screen)
		press_mode = PRESS_NONE
		return true

	if tool_id == ToolsScript.TEMPLATE:
		on_place_template.call(grid)
		press_mode = PRESS_NONE
		return true

	press_mode = PRESS_NONE
	return true

## Interprète un mouvement souris et retourne `true` si l'événement est consommé.
func handle_pointer_moved(grid: Vector2, screen: Vector2, mods: Dictionary, tool_id: String) -> bool:
	match press_mode:
		PRESS_PAN:
			on_update_pan.call(screen)
		PRESS_BAND:
			press_moved = true
		PRESS_MOVE:
			press_moved = true
		PRESS_RESIZE:
			press_moved = true
			on_apply_handle_resize.call(grid)
		PRESS_ROTATE:
			press_moved = true
			on_apply_handle_rotate.call(grid)
		PRESS_DRAW:
			press_moved = true
		PRESS_PAINT:
			pass
	return true

## Interprète un relâchement souris et retourne `true` si l'événement est consommé.
func handle_pointer_released(grid: Vector2, screen: Vector2, button: int, mods: Dictionary, tool_id: String) -> bool:
	if button != MOUSE_BUTTON_LEFT:
		return false
	var was_live := press_mode in [PRESS_MOVE, PRESS_RESIZE, PRESS_ROTATE]
	match press_mode:
		PRESS_PAN:
			on_end_pan.call()
		PRESS_BAND:
			band_base_selection.clear()
		PRESS_MOVE:
			if press_moved:
				on_commit_live_edit.call(drag_ids, "Déplacement")
			drag_ids.clear()
			drag_origins.clear()
		PRESS_RESIZE:
			if press_moved:
				on_commit_live_edit.call(drag_ids, "Redimensionnement")
			drag_ids.clear()
			handle_state.clear()
		PRESS_ROTATE:
			if press_moved:
				on_commit_live_edit.call(drag_ids, "Rotation")
			drag_ids.clear()
			handle_state.clear()
		PRESS_DRAW:
			on_finish_draw.call(grid)
		PRESS_PAINT:
			painted_cells.clear()
	press_mode = PRESS_NONE
	return was_live

## Annule l'action en cours (drag, tracé, lien).
func cancel_action() -> void:
	if press_mode in [PRESS_MOVE, PRESS_RESIZE, PRESS_ROTATE] and not drag_ids.is_empty():
		on_revert_live_edit.call(drag_ids)
	press_mode = PRESS_NONE
	drag_ids.clear()
	drag_origins.clear()
	handle_state.clear()
	link_source = ""

## Interprète un clic droit (fermeture polygone, annulation, info).
func _handle_right_click(grid: Vector2) -> void:
	if press_mode != PRESS_NONE:
		on_cancel_action.call()
		return

## Démarre un glisser de sélection (drag_ids pré-remplis).
func start_move_drag(ids: Array) -> void:
	press_mode = PRESS_MOVE
	drag_ids = ids.duplicate()
	drag_origins.clear()

## Démarre un glisser de poignée (resize/rotate).
func start_handle_drag(id: String, kind: String, state: Dictionary) -> void:
	press_mode = kind
	drag_ids = [id]
	handle_state = state

## Démarre un rectangle de sélection (band).
func start_band(base_selection: Array) -> void:
	press_mode = PRESS_BAND
	band_base_selection = base_selection.duplicate() if base_selection else []

## Retourne `true` si un geste est en cours.
func is_gesturing() -> bool:
	return press_mode != PRESS_NONE

## Retourne les IDs en cours de drag.
func get_drag_ids() -> Array:
	return drag_ids
