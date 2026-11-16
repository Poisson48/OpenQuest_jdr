extends Node

## Démo « Cité des Saules » — carte 44 × 32 ouverte dans l'éditeur, avec le style
## de scène **« Cité »** généré à graine fixe : le générateur compose de vrais
## GLB du catalogue `game/assets/objects3d/` (bâtiments + modules de toit/façade
## empilés + props + végétation + rochers + clôtures), pas des maisons
## procédurales.
##
## Tout reste retouchable : la génération est une seule étape d'undo, puis chaque
## bâtiment, toit, façade ou décor est un élément normal du document.
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/cite_boot.tscn
## Graine personnalisée :
##   godot --path game res://scenes/debug/cite_boot.tscn -- --seed 4242

const MONDE := "demo-cite-skyline"
const MAP_NAME := "Cité des Saules"
const MAP_WIDTH := 44
const MAP_HEIGHT := 32
const DEFAULT_SEED := 20261112
const SCENE_STYLE := "cite"
const DENSITY := 1.0

var _editor: Control
var _md: Node


func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var scene_seed := _read_seed()
	var map := _build_map(_md, scene_seed)
	if map.is_empty():
		push_error("[CITE DEMO] Impossible de créer la carte.")
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	if _md != null:
		_md.preview_map_id = map_id
	DisplayServer.window_set_title("OpenQuest — %s (cité générée)" % MAP_NAME)
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
	await get_tree().process_frame
	_editor.load_map(map)
	await get_tree().process_frame
	if _editor._overlay != null:
		_editor._overlay.show_light_radii = false
	_editor._scene_style = SCENE_STYLE
	_editor._scene_seed = scene_seed
	_editor._scene_density = DENSITY
	# Une seule génération = une seule étape d'undo (voir _apply_scene_plan).
	_editor._construction._generate_scene(Vector2(float(MAP_WIDTH) * 0.5, float(MAP_HEIGHT) * 0.5))
	_editor.doc.clear_selection()
	_editor._sync_engine()
	if _editor._engine != null:
		_editor._engine.focus_grid_rect(Rect2(0.5, 0.5, float(MAP_WIDTH) - 1.0, float(MAP_HEIGHT) - 1.0))
	_add_hint(scene_seed)
	print("[CITE DEMO] %s prête — %d × %d, graine %d, style=%s, %d élément(s)." % [
		MAP_NAME, MAP_WIDTH, MAP_HEIGHT, scene_seed, SCENE_STYLE,
		_editor.doc.elements_sorted().size()])


## Graine lue dans les arguments utilisateur (`-- --seed 4242` ou `--seed=4242`).
func _read_seed() -> int:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg := str(args[i])
		if arg == "--seed" and i + 1 < args.size():
			return int(str(args[i + 1]))
		if arg.begins_with("--seed="):
			return int(arg.substr("--seed=".length()))
	return DEFAULT_SEED


## Carte de démonstration : 44 × 32, sol plat au cœur de la cité, relief doux
## dans les marges (la cité reste droite et lisible), herbe par défaut.
static func _build_map(md: Node, scene_seed: int) -> Dictionary:
	if md == null:
		return {}
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map(MAP_NAME, "general", "local",
		MAP_WIDTH, MAP_HEIGHT)
	if map.is_empty():
		return {}
	var heights: Array = []
	heights.resize(MAP_WIDTH * MAP_HEIGHT)
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var in_city := x >= 2 and x <= MAP_WIDTH - 3 and y >= 2 and y <= MAP_HEIGHT - 3
			var value := 0.0
			if not in_city and scene_seed >= 0:
				# Relief très doux des marges : buttes d'herbe sous la ceinture.
				value = 0.16 * sin(float(x) * 0.52) * cos(float(y) * 0.44) \
					+ 0.06 * sin(float(x + y) * 0.85) + 0.04
			heights[y * MAP_WIDTH + x] = value
	var materials: Array = []
	materials.resize(MAP_WIDTH * MAP_HEIGHT)
	materials.fill(0)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	# Lumière du jour franche (soleil chaud + ambiante froide) : le preset
	# `tiny_glade` (pastel, ciel très lumineux) lavait la cité en vue haute ; on
	# veut ici le contraste CS2 (ombres portées nettes, couleurs tenues).
	map["lighting"] = {"enabled": true, "preset": "jour", "direction": "nw",
		"intensity": 0.35, "sources": []}
	# Preset qualité « cinéma » (ombres soleil, AO, étalonnage) : opt-in porté par
	# les données de carte. Les versions antérieures ignorent simplement la clé.
	map["qualityPreset"] = "cinema"
	# Brume fine de distance seulement : la composante **hauteur** de la brume
	# atmosphérique (heightDensity, défaut 0,22) voile toute la cité en caméra
	# haute ; on la neutralise et on ne garde que la profondeur lointaine.
	map["atmosphericFog"] = {"enabled": true, "density": 0.06, "heightDensity": 0.0}
	map["terrainHeights"] = heights
	map["terrainMaterials"] = materials
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = MAP_WIDTH
	map["zoneH"] = MAP_HEIGHT
	map["worldId"] = MONDE
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))


func _add_hint(scene_seed: int) -> void:
	var hint := Label.new()
	hint.text = "CITÉ DES SAULES — style « Cité » (graine %d) : %d bâtiments 3D du catalogue, toits et façades empilés, place, rues, clôtures. Une seule étape d'undo. Tout est retouchable (Sélection / Objets 3D)." % [
		scene_seed, _count_buildings()]
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 4
	hint.offset_left = 200
	hint.offset_right = -420
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)


func _count_buildings() -> int:
	var count := 0
	if _editor == null or _editor.doc == null:
		return count
	for elem_variant in _editor.doc.elements_of_kind("mesh"):
		if str((elem_variant as Dictionary).get("label", "")) == "Bâtiment de cité":
			count += 1
	return count
