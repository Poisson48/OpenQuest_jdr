extends Node

## Démo courte — Étape 2 : relief déformable par tracé (crête, vallée,
## aplatissement), sans végétation automatique pour rester lisible.

const MONDE := "demo-terrain-spline"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo relief tracé", "general", "local", 24, 16)
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

	DisplayServer.window_set_title("OpenQuest — Démo procédurale 2 : relief tracé")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._overlay.show_light_radii = false

	var doc = editor.doc
	doc.begin_transaction()
	# Colline principale.
	doc.paint_terrain_spline(
		[Vector2(4.0, 10.0), Vector2(8.0, 7.0), Vector2(12.0, 8.0), Vector2(16.0, 6.0)],
		3.2, 1.15, "ridge", "Démo crête"
	)
	# Vallée/chemin creusé.
	doc.paint_terrain_spline(
		[Vector2(14.0, 12.5), Vector2(10.0, 13.0), Vector2(6.0, 12.0)],
		2.4, 0.75, "valley", "Démo vallée"
	)
	# Petite plateforme aplatie.
	doc.paint_terrain_spline(
		[Vector2(17.0, 12.0), Vector2(20.0, 12.0)],
		2.2, 1.0, "flatten", "Démo plateforme"
	)
	doc.commit_transaction()
	var hs: Array = doc.terrain_heights()
	var max_h := 0.0
	for v in hs:
		max_h = maxf(max_h, float(v))
	var updated: Dictionary = doc.to_map_data()
	editor.load_map(updated)
	await get_tree().process_frame
	if editor._engine != null and editor._engine.has_method("refresh_terrain"):
		editor._engine.call("refresh_terrain", updated)
	editor._sync_engine()
	# Preuve de conformité : clôture et mur procéduraux sur la colline.
	editor._proc_fence_height = 0.9
	editor._construction._build_procedural_fence([
		Vector2(4.0, 10.0), Vector2(8.0, 7.0), Vector2(12.0, 8.0), Vector2(16.0, 6.0),
	])
	editor._wall_height = 1.6
	editor._construction._build_procedural_wall([
		Vector2(5.0, 12.0), Vector2(10.0, 11.5), Vector2(15.0, 12.5),
	])
	editor.doc.clear_selection()
	editor._sync_engine()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 22.0, 13.0))

	var hint := Label.new()
	hint.text = "ÉTAPE 2 — RELIEF DÉFORMABLE : clôture et mur procéduraux posés sur la colline, ils suivent le relief sommet par sommet."
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
	print("[PROC DEMO] relief tracé prêt : ", map_id)
