extends Node

## Démo chemins : tracé libre qui suit le relief, creusé et subdivisé selon la pente.

const MONDE := "demo-paths"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo chemins", "general", "local", 24, 16)
	if map.is_empty():
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["worldId"] = MONDE
	map["focusMode"] = "paths"
	map["vegetationEnabled"] = false
	map["terrainDetail"] = 2
	map["lighting"] = {"enabled": true, "preset": "tiny_glade", "sources": []}
	md.update_map(map)
	md.preview_map_id = map_id

	DisplayServer.window_set_title("OpenQuest — Démo chemins procéduraux")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._set_path_focus(true)
	await get_tree().process_frame
	editor._overlay.show_light_radii = false

	# Relief : colline à gauche, creux au centre, replat à droite.
	editor.doc.set_terrain_height(5, 7, 0.0)
	for cy in range(4, 12):
		for cx in range(3, 9):
			var d := Vector2(cx, cy).distance_to(Vector2(5.0, 7.0))
			editor.doc.set_terrain_height(cx, cy, maxf(0.0, 1.8 - d * 0.35))
	for cy in range(7, 12):
		for cx in range(11, 18):
			var d := Vector2(cx, cy).distance_to(Vector2(14.0, 9.0))
			editor.doc.set_terrain_height(cx, cy, -maxf(0.0, 0.9 - d * 0.22))
	editor.doc.set_terrain_height(6, 8, 1.9)
	editor.doc.set_terrain_height(15, 9, -0.9)
	editor._sync_engine()

	# Tracé libre : le chemin descend la colline, traverse le creux et remonte.
	editor._proc_path_width = 1.5
	editor._proc_path_depth = 0.10
	editor._proc_path_color = "#8a7654"
	editor._construction._paint_path_terrain([
		Vector2(3.0, 6.0), Vector2(5.0, 7.0), Vector2(7.0, 8.0),
		Vector2(9.5, 8.5), Vector2(12.0, 9.0), Vector2(14.5, 9.2), Vector2(17.0, 8.5),
	])
	# Deuxième chemin plus large, matière pierre, sur le replat.
	editor._proc_path_width = 2.0
	editor._proc_path_color = "#8d8a80"
	editor._construction._paint_path_terrain([
		Vector2(13.5, 5.0), Vector2(16.0, 5.5), Vector2(18.0, 7.0),
	])
	# Preuve du pipeline Blender : patch complet chemin + herbe Geometry Nodes.
	var blender_path := "res://assets/objects3d/terrain/path_generated_demo.glb"
	if ResourceLoader.exists(blender_path):
		editor.doc.add_element({
			"x": 12.0, "y": 8.0, "w": 11.0, "h": 7.0,
			"asset": blender_path, "elevation": 0.02,
			"followTerrain": false, "tiltToTerrain": false,
			"label": "Chemin + herbe Blender", "layer": 1,
			"display": {"rotation": 0.0, "scale": 2.0},
		}, "mesh", "Chemin + herbe Blender")
	editor.doc.clear_selection()
	editor._sync_engine()
	editor._engine.focus_grid_rect(Rect2(5.0, 4.0, 14.0, 10.0))

	var hint := Label.new()
	hint.text = "DÉMO CHEMINS — tracé à main levée, chemin peint dans le terrain, légèrement creusé, bords irréguliers et relief suivi."
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 42
	hint.offset_left = 240
	hint.offset_right = -440
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)
	print("[PATHS DEMO] prêt : ", map_id)
