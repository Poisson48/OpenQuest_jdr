extends Node

## Démo courte — Forêt générée avec clairière et chemin.

const MONDE := "demo-generated-forest"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Forêt générée", "general", "local", 24, 18)
	if map.is_empty():
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	map["worldId"] = MONDE
	md.update_map(map)
	md.preview_map_id = map_id

	DisplayServer.window_set_title("OpenQuest — Démo procédurale 10 : forêt générée")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._overlay.show_light_radii = false
	editor._scene_style = "foret"
	editor._scene_seed = 11
	editor._scene_density = 1.6
	editor._construction._generate_scene(Vector2(12.0, 9.0))
	editor.doc.clear_selection()
	editor._sync_engine()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 22.0, 16.0))

	var hint := Label.new()
	hint.text = "ÉTAPE 10 — FORÊT GÉNÉRÉE : clairière, chemin, rochers et arbres procéduraux. La prochaine étape remplacera cette démo."
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
	print("[PROC DEMO] forêt générée prête : ", map_id)
