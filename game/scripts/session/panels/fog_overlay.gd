extends Control
class_name FogOverlay

## Voile de brouillard « vision courante » par-dessus le rendu carte.
##
## Le moteur 3D gère déjà la **mémoire** d'exploration (`MapFog3D` masque les
## cases jamais vues). Ce voile ajoute la couche qui manquait, côté joueur :
## - les cases **révélées mais plus dans le champ de vision actuel** sont
##   assombries (on garde le souvenir, on perd la clarté) ;
## - le **contour des polygones de visibilité** est tracé, ce qui donne un bord
##   de brouillard lissé au lieu d'un escalier de cases.
##
## Vue MJ : rien n'est peint. Brouillard désactivé sur la carte : rien non plus.
##
## Le rendu est en espace écran : chaque case est projetée par ses 4 coins via
## `grid_to_screen` du moteur (perspective et relief compris), comme le fait
## déjà `MapAreasOverlay`. Aucune modification du moteur 3D n'est nécessaire.

## Assombrissement des cases révélées hors vision (mémoire atténuée).
const COLOR_DIM := Color(0.03, 0.03, 0.05, 0.55)

## Contour des polygones de visibilité (bord de brouillard lissé).
const COLOR_EDGE := Color(0.74, 0.82, 0.96, 0.38)

## Sentinelle renvoyée par la projection quand un point est derrière la caméra.
const BEHIND := -90000.0

var engine: Control = null

## Projecteur injectable `(gx, gy) -> Vector2` pour les tests (sinon moteur).
var projector: Callable = Callable()

var map_id: String = ""
var is_gm: bool = false
var fog_enabled: bool = true

var _revealed: Array = []
var _visible_now: Array = []
var _polygons: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Configure le voile depuis une charge utile de session.
## Clés attendues : `fog_revealed`, `visible_now`, `vision_polygons`,
## `is_gm`, `fog_enabled`, `map_id`.
func configure(p_engine: Control, payload: Dictionary) -> void:
	engine = p_engine
	map_id = str(payload.get("map_id", ""))
	is_gm = bool(payload.get("is_gm", false))
	fog_enabled = bool(payload.get("fog_enabled", true))
	_revealed = payload.get("fog_revealed", [])
	_visible_now = payload.get("visible_now", [])
	_polygons = payload.get("vision_polygons", [])
	if not _revealed is Array:
		_revealed = []
	if not _visible_now is Array:
		_visible_now = []
	if not _polygons is Array:
		_polygons = []
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

## Mise à jour d'état sans reconfigurer le moteur (tests / rafraîchissements).
func apply_state(revealed: Array, visible_now: Array, polygons: Array) -> void:
	_revealed = revealed
	_visible_now = visible_now
	_polygons = polygons
	queue_redraw()

## Cases à assombrir : révélées, mais plus dans le champ de vision actuel.
func dim_cells() -> Array:
	if not is_active():
		return []
	var visible: Dictionary = {}
	for key in _visible_now:
		visible[str(key)] = true
	var out: Array = []
	for key in _revealed:
		var k := str(key)
		if not visible.has(k):
			out.append(k)
	return out

## Vrai si le voile doit peindre quelque chose.
func is_active() -> bool:
	if is_gm or not fog_enabled:
		return false
	return (engine != null and engine.has_method("grid_to_screen")) or projector.is_valid()

## Nombre de polygones de visibilité reçus (tests / debug).
func polygon_count() -> int:
	return _polygons.size()

## Quad écran d'une case « x,y » (4 coins projetés), ou vide si derrière caméra.
func cell_quad(cell_key: String) -> PackedVector2Array:
	var parts := cell_key.split(",")
	if parts.size() != 2:
		return PackedVector2Array()
	var gx := float(parts[0])
	var gy := float(parts[1])
	return _quad(Vector2(gx, gy))

func _quad(cell: Vector2) -> PackedVector2Array:
	var quad := PackedVector2Array([
		_project(cell.x, cell.y),
		_project(cell.x + 1.0, cell.y),
		_project(cell.x + 1.0, cell.y + 1.0),
		_project(cell.x, cell.y + 1.0),
	])
	for point in quad:
		if point.x <= BEHIND or point.y <= BEHIND:
			return PackedVector2Array()
	return quad

func _project(gx: float, gy: float) -> Vector2:
	if projector.is_valid():
		return projector.call(gx, gy)
	if engine != null and engine.has_method("grid_to_screen"):
		return engine.grid_to_screen(gx, gy, 0.02)
	return Vector2(BEHIND, BEHIND)

func _draw() -> void:
	if not is_active():
		return
	for key in dim_cells():
		var quad := cell_quad(str(key))
		if quad.size() == 4:
			draw_colored_polygon(quad, COLOR_DIM)
	for polygon_variant in _polygons:
		var polygon: PackedVector2Array = polygon_variant
		if polygon.size() < 3:
			continue
		var screen := PackedVector2Array()
		var ok := true
		for point in polygon:
			var projected := _project(point.x, point.y)
			if projected.x <= BEHIND or projected.y <= BEHIND:
				ok = false
				break
			screen.append(projected)
		if not ok or screen.size() < 3:
			continue
		screen.append(screen[0])
		draw_polyline(screen, COLOR_EDGE, 1.5, true)
