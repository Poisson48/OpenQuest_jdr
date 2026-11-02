extends Node

## Démo courte — Étape 4 : toits procéduraux adaptés à l'emprise.
## Un seul mesh par toit (deux pans, débord, pignons), posé sur une pièce.

const MONDE := "demo-proc-roof"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo toits procéduraux", "general", "local", 22, 14)
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

	DisplayServer.window_set_title("OpenQuest — Démo procédurale 4 : toits adaptatifs")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._overlay.show_light_radii = false
	editor._roof_height = 1.3
	editor._proc_roof_height = 1.2
	editor._proc_roof_overhang = 0.35

	# Deux pièces + leurs toits procéduraux.
	editor._create_mesh_room(Vector2(3.5, 5.0), Vector2(8.0, 8.5))
	editor._construction._create_procedural_roof(Vector2(3.5, 5.0), Vector2(8.0, 8.5))
	editor._create_mesh_room(Vector2(11.0, 4.0), Vector2(16.5, 8.0))
	editor._construction._create_procedural_roof(Vector2(11.0, 4.0), Vector2(16.5, 8.0))
	# Maison à étage : murs du niveau supérieur + dalle.
	editor._wall_height = 1.3
	editor._house_floors = 2
	editor._create_mesh_house(Vector2(8.0, 10.0), Vector2(13.0, 13.0))
	editor.doc.clear_selection()
	editor._sync_engine()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 20.0, 12.0))

	var hint := Label.new()
	hint.text = "ÉTAPE 4 — TOITS PROCÉDURAUX : un seul mesh à deux pans, débord et pignons, adapté à chaque emprise. La prochaine étape remplacera cette démo."
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
	print("[PROC DEMO] toits procéduraux prêts : ", map_id)
