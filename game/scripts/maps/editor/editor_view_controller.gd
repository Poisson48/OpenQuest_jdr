extends RefCounted
class_name EditorViewController

## Contrôleur de vue de l'éditeur : caméra, zoom, pan, projection grille↔écran.
##
## Extraite de `map_complex_editor.gd` et `complex_map_engine_3d.gd`.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

# --- Constantes ----------------------------------------------------------------
const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const ZOOM_STEP := 0.15

# --- État ----------------------------------------------------------------------
var zoom: float = 1.0
var pan_offset: Vector2 = Vector2.ZERO
var is_panning: bool = false
var pan_start_screen: Vector2 = Vector2.ZERO
var pan_start_offset: Vector2 = Vector2.ZERO

# --- Callbacks injectés ---------------------------------------------------------
var on_zoom_changed: Callable = Callable()
var on_view_changed: Callable = Callable()

## Démarre un pan à partir de la position écran.
func begin_pan(screen: Vector2) -> void:
	is_panning = true
	pan_start_screen = screen
	pan_start_offset = pan_offset

## Met à jour le pan pendant le glisser.
func update_pan(screen: Vector2) -> void:
	if not is_panning:
		return
	pan_offset = pan_start_offset + (screen - pan_start_screen) / zoom
	on_view_changed.call()

## Termine le pan.
func end_pan() -> void:
	is_panning = false

## Zoom avant centré sur un point écran (optionnel).
func zoom_in(_center: Vector2 = Vector2.ZERO) -> void:
	zoom = clampf(zoom + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	on_zoom_changed.call(zoom)
	on_view_changed.call()

## Zoom arrière centré sur un point écran (optionnel).
func zoom_out(_center: Vector2 = Vector2.ZERO) -> void:
	zoom = clampf(zoom - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	on_zoom_changed.call(zoom)
	on_view_changed.call()

## Applique un facteur de zoom (molette) centré sur un point écran.
func apply_zoom_factor(factor: float, _center: Vector2 = Vector2.ZERO) -> void:
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	on_zoom_changed.call(zoom)
	on_view_changed.call()

## Réinitialise le zoom et le pan.
func reset_view() -> void:
	zoom = 1.0
	pan_offset = Vector2.ZERO
	on_zoom_changed.call(zoom)
	on_view_changed.call()

## Recentre la vue sur une cellule grille (coordonnées fractionnaires).
func center_on_grid(gx: float, gy: float) -> void:
	pan_offset = Vector2(-gx, -gy) * zoom
	on_view_changed.call()

## Recentre la vue sur un rectangle grille (focus sélection).
func focus_grid_rect(bounds: Rect2) -> void:
	if bounds.size == Vector2.ZERO:
		reset_view()
		return
	var center := bounds.get_center()
	pan_offset = Vector2(-center.x, -center.y) * zoom
	on_view_changed.call()

## Convertit une position écran en coordonnées grille.
func screen_to_grid(screen: Vector2, viewport_size: Vector2) -> Vector2:
	var center := viewport_size * 0.5
	return (screen - center) / zoom - pan_offset

## Convertit des coordonnées grille en position écran.
func grid_to_screen(grid: Vector2, viewport_size: Vector2) -> Vector2:
	var center := viewport_size * 0.5
	return center + (grid + pan_offset) * zoom

## Applique l'aimantation à une position grille.
func snap_grid(grid: Vector2, snap_mode: String) -> Vector2:
	return ToolsScript.snap_vector(grid, snap_mode)

## Retourne `true` si la position grille est dans les bornes de la carte.
func in_bounds(grid: Vector2, map_width: float, map_height: float) -> bool:
	return grid.x >= -0.5 and grid.y >= -0.5 and grid.x <= map_width and grid.y <= map_height

## Formate le niveau de zoom pour l'affichage ("150%").
func zoom_label() -> String:
	return "%d%%" % int(zoom * 100.0)

## Retourne l'état de vue sérialisé (pour `playDefaults.viewState`).
func get_view_state() -> Dictionary:
	return {
		"zoom": zoom,
		"panOffset": {"x": pan_offset.x, "y": pan_offset.y},
	}

## Restaure l'état de vue depuis `playDefaults.viewState`.
func set_view_state(state: Dictionary) -> void:
	zoom = clampf(float(state.get("zoom", 1.0)), MIN_ZOOM, MAX_ZOOM)
	var off: Dictionary = state.get("panOffset", {}) if state.get("panOffset") is Dictionary else {}
	pan_offset = Vector2(float(off.get("x", 0.0)), float(off.get("y", 0.0)))
	on_zoom_changed.call(zoom)
	on_view_changed.call()
