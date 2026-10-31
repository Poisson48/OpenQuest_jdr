extends Node

## Démo ciblée : deux maisons avec un auvent de façade correctement aimanté
## (mur avant et mur latéral). Ouvre directement l'éditeur sur cette carte.
##
## Lancer :
##   .\scripts\play-godot.ps1 res://scenes/debug/auvent_demo.tscn

const AUVENT := "res://assets/objects3d/buildings/auvent_etal.glb"
const MAISON := "res://assets/objects3d/buildings/maison_etage.glb"
const MONDE := "demo-auvent"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	# Repart propre : supprime une éventuelle démo auvent précédente.
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo auvent", "general", "local", 14, 9)
	if map.is_empty():
		push_error("[AUVENT DEMO] Carte impossible.")
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["ambientFx"] = "leaves"
	map["worldId"] = MONDE
	map["meshes"] = [
		{"id": "demo-maison-avant", "kind": "mesh", "x": 6.0, "y": 4.0,
			"w": 2.24, "h": 2.05,
			"asset": MAISON, "elevation": 0.0, "followTerrain": true,
			"label": "Maison à étage", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0}},
		# Auvent collé au mur avant (+Y local) : face à y = 5.023, dos du GLB à +0.455.
		{"id": "demo-auvent-avant", "kind": "mesh", "x": 6.0, "y": 5.478,
			"w": 2.09, "h": 1.4,
			"asset": AUVENT, "elevation": 0.0, "followTerrain": true,
			"label": "Auvent avant", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0}},
	]
	map["notes"] = [
		{"id": "note-avant", "kind": "note", "x": 6.0, "y": 7.2,
			"text": "Auvent : rotation 0°, y = face du mur + 0,455", "layer": 5},
	]
	md.update_map(map)
	md.preview_map_id = map_id

	DisplayServer.window_set_title("OpenQuest — Démo auvent de façade")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._set_tool("select")
	if editor._engine != null:
		editor._engine.focus_grid_rect(Rect2(3.0, 1.5, 7.0, 7.0))
	var hint := Label.new()
	hint.text = "DÉMO AUVENT — maison + auvent collé au nu du mur. Clique l'auvent pour inspecter ses dimensions/Échelle."
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 44
	hint.offset_left = 220
	hint.offset_right = -220
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)
	print("[AUVENT DEMO] Carte prête : ", map_id)
