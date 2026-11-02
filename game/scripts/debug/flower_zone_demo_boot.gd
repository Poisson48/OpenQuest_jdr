extends Node

## Démo courte — Étape 3 : zones fleuries au pinceau, avec type de fleur choisi.
## Aucune végétation automatique : seules les zones dessinées apparaissent.

const MONDE := "demo-flower-zones"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo zones fleuries", "general", "local", 22, 14)
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

	DisplayServer.window_set_title("OpenQuest — Démo procédurale 3 : zones fleuries")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._overlay.show_light_radii = false

	# Trois zones de types différents.
	_add_flower_zone(editor, [
		Vector2(3.0, 4.5), Vector2(7.0, 3.5), Vector2(9.0, 6.0), Vector2(6.0, 8.0), Vector2(3.0, 7.0),
	], "marguerite", 4.5)
	_add_flower_zone(editor, [
		Vector2(11.0, 3.0), Vector2(15.0, 2.8), Vector2(16.5, 5.0), Vector2(13.0, 6.2), Vector2(10.5, 5.2),
	], "coquelicot", 5.0)
	_add_flower_zone(editor, [
		Vector2(6.0, 10.0), Vector2(11.0, 9.2), Vector2(14.0, 11.0), Vector2(9.0, 12.2),
	], "lavande", 5.5)
	editor.doc.clear_selection()
	editor._sync_engine()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 20.0, 12.0))

	var hint := Label.new()
	hint.text = "ÉTAPE 3 — ZONES FLEURIES : dessin de zone + type de fleur (marguerites, coquelicots, lavande). Aucune herbe automatique. La prochaine étape remplacera cette démo."
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
	print("[PROC DEMO] zones fleuries prêtes : ", map_id)

func _add_flower_zone(editor: Control, points: Array, type_id: String, density: float) -> void:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p_variant in points:
		var p: Vector2 = p_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for p_variant in points:
		var p: Vector2 = (p_variant as Vector2) - center
		local.append([p.x, p.y])
	editor.doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://flower_zone",
		"points": local, "flowerType": type_id,
		"density": density, "size": 0.5, "seed": 1234,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": "Zone fleurie", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, "mesh", "Zone fleurie")
