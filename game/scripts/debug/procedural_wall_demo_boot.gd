extends Node

## Démo courte — Étape 1 du plan procédural : un mur généré comme un seul mesh
## continu à partir d'une courbe (mitres), pas une suite de modules.
##
## Lancer :
##   .\scripts\play-godot.ps1 res://scenes/debug/procedural_wall_demo.tscn

const MONDE := "demo-procedural-wall"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo mur procédural", "general", "local", 24, 16)
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
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	md.update_map(map)
	md.preview_map_id = map_id

	DisplayServer.window_set_title("OpenQuest — Démo procédurale 1/… : mur continu")
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(editor)
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame
	editor._overlay.show_light_radii = false

	# Courbe principale : un mur organique continu.
	var curve: Array = [
		Vector2(4.0, 9.0), Vector2(6.0, 6.8), Vector2(9.0, 5.4),
		Vector2(12.0, 6.2), Vector2(14.0, 8.6),
	]
	_add_procedural_wall(editor, curve, 2.5, 0.85, "#a89d88")
	# Branche perpendiculaire : montre une jonction en T visuelle (deux meshes).
	_add_procedural_wall(editor, [Vector2(9.0, 5.4), Vector2(9.0, 2.2)], 2.5, 0.85, "#9c917d")
	# Petit muret de jardin indépendant.
	_add_procedural_wall(editor, [Vector2(15.5, 11.5), Vector2(18.5, 11.0), Vector2(19.5, 12.8)], 1.1, 0.6, "#b0a58d")

	editor.doc.clear_selection()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 22.0, 13.0))

	var hint := Label.new()
	hint.text = "ÉTAPE 1 — MUR PROCÉDURAL : une seule courbe → un seul mesh continu, avec mitres. Le prochain palier remplacera cette démo."
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
	print("[PROC DEMO] mur procédural prêt : ", map_id)

func _add_procedural_wall(editor: Control, points: Array, height: float,
		thickness: float, color: String) -> void:
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
		"asset": "procedural://wall",
		"points": local,
		"height": height, "thickness": thickness, "color": color,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": "Mur procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, "mesh", "Mur procédural")
