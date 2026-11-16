extends Node

## Banc d'essai « sol plat » : ouvre l'éditeur de cartes sur une carte VIERGE et
## parfaitement plate, avec tous les outils classiques disponibles.
##
## Aucun décor, aucun rocher, aucune génération automatique : la carte ne
## contient que du sol d'herbe. Le but est de laisser le MJ placer lui-même ses
## objets 3D (Biblio → 🧊 Objets 3D) et ses reliefs (⛰ Relief).
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/sol_plat_boot.tscn

const MAP_WIDTH := 30
const MAP_HEIGHT := 20

var _editor: Control
var _md: Node


func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var map := _build_flat_map(_md)
	if map.is_empty():
		push_error("[SOL PLAT] Impossible de créer la carte.")
		get_tree().quit(1)
		return
	DisplayServer.window_set_title("OpenQuest — Sol plat (pose libre)")
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
	_editor.open_map_requested.connect(_on_open_map_requested)
	await get_tree().process_frame
	_editor.load_map(map)
	await get_tree().process_frame
	# Outil de sélection par défaut : rien n'est armé, la carte est libre.
	_editor._set_tool("select")
	# Cadrage : toute la carte visible pour poser tranquillement les objets.
	if _editor._engine != null:
		_editor._engine.reset_editor_camera()
	_editor._set_status("Sol plat — 30 × 20 cases. Pose tes objets via Biblio → 🧊 Objets 3D, sculpte avec ⛰ Relief.")
	_add_hint()
	print("[SOL PLAT] Carte vierge prête — %d × %d cases." % [MAP_WIDTH, MAP_HEIGHT])


## Carte 30 × 20, sol plat (hauteur 0 partout), herbe uniforme.
static func _build_flat_map(md: Node) -> Dictionary:
	if md == null:
		return {}
	var map: Dictionary = md.create_complex_map("Sol plat", "general", "local", MAP_WIDTH, MAP_HEIGHT)
	var heights: Array = []
	heights.resize(MAP_WIDTH * MAP_HEIGHT)
	heights.fill(0.0)
	var materials: Array = []
	materials.resize(MAP_WIDTH * MAP_HEIGHT)
	materials.fill(0)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	map["terrainHeights"] = heights
	map["terrainMaterials"] = materials
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = MAP_WIDTH
	map["zoneH"] = MAP_HEIGHT
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))


func _add_hint() -> void:
	var hint := Label.new()
	hint.text = "SOL PLAT — Biblio → 🧊 Objets 3D pour poser les rochers · ⛰ Relief (U) pour sculpter · R pivote · Échap = menu"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 4
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)


func _on_open_map_requested(map_id: String) -> void:
	if _md == null or map_id.is_empty():
		return
	var map: Dictionary = _md.get_by_id(map_id)
	if map.is_empty():
		return
	_md.preview_map_id = map_id
	_editor.load_map(map)
