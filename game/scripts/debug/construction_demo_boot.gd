extends Node

## Démo « construction à la Sims » : deux maisons finies, une maison en
## chantier et une maison sans toit pour voir l'intérieur meublé.
## Tout est généré avec les outils de l'éditeur, puis l'éditeur est ouvert.
##
## Lancer :
##   .\scripts\play-godot.ps1 res://scenes/debug/construction_demo.tscn

const MONDE := "demo-construction"

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo construction", "general", "local", 24, 18)
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

	# --- 1. Maison finie, toit tuiles, dallage pierre -------------------------
	editor._wall_height = 2.2
	editor._floor_material = 2
	editor._floor_flatten = true
	editor._roof_asset = "res://assets/objects3d/buildings/toit_2pentes.glb"
	editor._create_mesh_house(Vector2(3.0, 3.0), Vector2(9.0, 7.0))
	editor._insert_window(Vector2(4.6, 7.0))
	editor._insert_window(Vector2(7.4, 7.0))
	editor._insert_window(Vector2(9.0, 5.0))

	# --- 2. Maison finie, toit chaume, dallage terre --------------------------
	editor._wall_height = 2.0
	editor._floor_material = 1
	editor._roof_asset = "res://assets/objects3d/buildings/toit_chaume.glb"
	editor._create_mesh_house(Vector2(12.0, 3.0), Vector2(17.0, 7.0))
	editor._insert_window(Vector2(17.0, 5.0))
	editor._insert_window(Vector2(14.5, 7.0))

	# --- 3. Maison sans toit : l'intérieur meublé est visible -----------------
	editor._wall_height = 2.2
	editor._floor_material = 2
	editor._roof_asset = "res://assets/objects3d/buildings/toit_2pentes.glb"
	editor._create_mesh_house(Vector2(12.0, 10.0), Vector2(18.0, 14.0))
	# On retire le toit de cette maison pour la visite (uniquement ses tuiles).
	var cutaway_roof_ids: Array = []
	for elem_variant in editor.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if not str(elem.get("asset", "")).begins_with("res://assets/objects3d/buildings/toit_"):
			continue
		var ex := float(elem.get("x", 0.0))
		var ey := float(elem.get("y", 0.0))
		if ex >= 12.0 and ex <= 18.0 and ey >= 10.0 and ey <= 14.0:
			cutaway_roof_ids.append(str(elem.get("id", "")))
	for roof_id in cutaway_roof_ids:
		editor.doc.remove_element(roof_id)
	editor._insert_window(Vector2(13.5, 14.0))
	editor._insert_window(Vector2(16.5, 14.0))
	editor._furnish_preset = "salle"
	editor._insert_furniture(Vector2(15.0, 12.0))
	editor._furnish_preset = "chambre"
	editor._insert_furniture(Vector2(16.6, 12.8))

	# --- 4. Chantier : deux murs, matériaux, remorque -------------------------
	editor._wall_height = 1.4
	editor._floor_material = 1
	editor._floor_flatten = true
	editor._create_floor(Vector2(3.0, 10.0), Vector2(9.0, 14.0))
	editor._create_mesh_wall_chain(Vector2(3.0, 10.0), Vector2(9.0, 10.0))
	editor._create_mesh_wall_chain(Vector2(3.0, 10.0), Vector2(3.0, 14.0))

	# --- Clôture, chemin, matériaux de chantier -------------------------------
	editor._fence_asset = "res://assets/objects3d/props/barriere.glb"
	editor._create_mesh_fence(Vector2(2.0, 15.5), Vector2(9.0, 15.5))
	editor._create_mesh_fence(Vector2(2.0, 12.0), Vector2(2.0, 15.5))
	editor._path_width = 2
	editor._path_material = 1
	editor._create_path(Vector2(6.0, 7.0), Vector2(6.0, 9.5))
	editor._create_path(Vector2(6.0, 8.5), Vector2(15.0, 8.5))
	editor._create_path(Vector2(15.0, 8.5), Vector2(15.0, 10.0))
	editor._create_path(Vector2(10.0, 12.0), Vector2(12.0, 12.0))

	_place_prop(editor, "caisse", 4.2, 11.6, 12.0)
	_place_prop(editor, "caisse_grande", 5.4, 12.2, -8.0)
	_place_prop(editor, "charrette", 7.2, 12.6, 70.0)
	_place_prop(editor, "tonneau", 8.1, 11.2, 0.0)
	_place_prop(editor, "botte_foin", 4.2, 13.3, 20.0)
	_place_prop(editor, "caisse", 10.2, 11.0, 0.0)
	_place_prop(editor, "caisse", 10.2, 10.1, 18.0)
	_place_prop(editor, "puits", 20.5, 9.0, 0.0)
	_place_prop(editor, "banc", 20.3, 10.2, 90.0)

	# Lieu + carte intérieure liés à la porte de la première maison.
	editor._create_interior_at(Vector2(6.0, 7.0))
	await get_tree().process_frame
	editor.load_map(md.get_by_id(map_id))
	await get_tree().process_frame

	editor.doc.clear_selection()
	editor._engine.focus_grid_rect(Rect2(1.0, 1.0, 21.0, 16.0))

	var hint := Label.new()
	hint.text = "DÉMO CONSTRUCTION À LA SIMS — 2 maisons finies · 1 maison sans toit meublée · 1 chantier · 1 intérieur lié (porte de la maison de gauche, à tester en session). Palette « Placer » à gauche."
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 44
	hint.offset_left = 240
	hint.offset_right = -440
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)
	print("[CONSTRUCTION DEMO] Carte prête : ", map_id)

func _place_prop(editor: Control, asset_name: String, x: float, y: float, rotation: float) -> void:
	var path := "res://assets/objects3d/props/%s.glb" % asset_name
	if not ResourceLoader.exists(path):
		return
	var bounds: Vector2 = Vector2(editor._mesh_bounds_cells(path, 1.0).x, editor._mesh_bounds_cells(path, 1.0).z)
	editor.doc.add_element({
		"x": x, "y": y,
		"w": maxf(0.4, bounds.x), "h": maxf(0.4, bounds.y),
		"asset": path, "elevation": 0.0,
		"followTerrain": true, "tiltToTerrain": false,
		"label": asset_name.capitalize(), "layer": 1,
		"display": {"rotation": rotation, "scale": 1.0},
	}, "mesh", asset_name)
