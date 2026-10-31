extends Node

## Démo « construction Sims » : deux maisons, fenêtres, clôture et chemin,
## générées avec les outils de l'éditeur. Ouvre directement l'éditeur.
##
## Lancer :
##   .\scripts\play-godot.ps1 res://scenes/debug/construction_demo.tscn

const MONDE := "demo-construction"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo construction", "general", "local", 20, 14)
	if map.is_empty():
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["ambientFx"] = "leaves"
	map["worldId"] = MONDE
	md.update_map(map)
	md.preview_map_id = map_id

	DisplayServer.window_set_title("OpenQuest — Démo construction façon Sims")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame

	# Maison 1 : murs hauts, dallage pierre, toit tuiles.
	editor._wall_height = 2.2
	editor._floor_material = 2
	editor._floor_flatten = true
	editor._roof_asset = "res://assets/objects3d/buildings/toit_2pentes.glb"
	editor._create_mesh_house(Vector2(3.0, 3.0), Vector2(9.0, 7.0))
	editor._insert_window(Vector2(4.6, 7.0))
	editor._insert_window(Vector2(7.4, 7.0))
	editor._insert_window(Vector2(9.0, 5.0))

	# Maison 2 : plus basse, dallage terre, toit chaume.
	editor._wall_height = 2.0
	editor._floor_material = 1
	editor._roof_asset = "res://assets/objects3d/buildings/toit_chaume.glb"
	editor._create_mesh_house(Vector2(12.0, 3.0), Vector2(17.0, 7.0))
	editor._insert_window(Vector2(17.0, 5.0))
	editor._insert_window(Vector2(14.5, 7.0))

	# Clôture et chemin.
	editor._fence_asset = "res://assets/objects3d/props/barriere.glb"
	editor._create_mesh_fence(Vector2(2.0, 9.0), Vector2(10.0, 9.0))
	editor._create_mesh_fence(Vector2(10.0, 9.0), Vector2(10.0, 12.0))
	editor._path_width = 2
	editor._path_material = 1
	editor._create_path(Vector2(6.0, 7.0), Vector2(6.0, 13.0))
	editor._create_path(Vector2(6.0, 10.0), Vector2(15.0, 10.0))
	editor.doc.clear_selection()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 16.0, 11.0))

	var hint := Label.new()
	hint.text = "DÉMO CONSTRUCTION — deux maisons, fenêtres, clôture, chemins. Sélectionne un objet pour voir dimensions/Échelle."
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
	print("[CONSTRUCTION DEMO] Carte prête : ", map_id)
