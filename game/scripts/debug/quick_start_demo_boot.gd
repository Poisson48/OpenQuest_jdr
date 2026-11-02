extends Node

## Démo « Démarrage rapide » : WFC pour les plaques de sol + Marching Cubes
## pour les rochers, en un clic.

const MONDE := "demo-quick-start"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo démarrage rapide", "general", "local", 26, 18)
	if map.is_empty():
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	map["worldId"] = MONDE
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	md.update_map(map)
	md.preview_map_id = map_id

	DisplayServer.window_set_title("OpenQuest — Démarrage rapide WFC + Marching Cubes")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._overlay.show_light_radii = false
	editor._on_quick_start(0)
	for _i in range(4):
		await get_tree().process_frame
	editor.doc.clear_selection()
	editor._sync_engine()

	var hint := Label.new()
	hint.text = "DÉMARRAGE RAPIDE — un clic : village, plaques de sol WFC et rochers Marching Cubes, lumière prête à jouer."
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
	print("[QUICK START DEMO] prêt : ", map_id)
