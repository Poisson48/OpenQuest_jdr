extends SceneTree

## Tests de la vue Monde de l'éditeur (zones de tailles différentes, façons Dofus) :
## présence de l'onglet, chargement des zones, création, liens de bords, validation
## et ouverture d'une zone.

var _failed := false
var _created_maps: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var WorldZonesScript: GDScript = load("res://scripts/maps/world/world_zones.gd")

	# Trois zones adjacentes de tailles différentes.
	var specs := [
		{"title": "Zone test A", "w": 12, "h": 9, "x": 0, "y": 0},
		{"title": "Zone test B", "w": 9, "h": 9, "x": 12, "y": 0},
		{"title": "Zone test C", "w": 15, "h": 12, "x": 0, "y": 9},
	]
	var maps: Array = []
	for spec_variant in specs:
		var spec: Dictionary = spec_variant
		var map: Dictionary = md.create_complex_map(str(spec["title"]), "general", "local",
			int(spec["w"]), int(spec["h"]))
		var map_id := str(map.get("id", ""))
		if map_id.is_empty():
			continue
		map["renderStyle"] = "2.5d"
		map["groundMode"] = "terrain3d"
		map["backgroundImage"] = ""
		map["zoneX"] = int(spec["x"])
		map["zoneY"] = int(spec["y"])
		map["zoneW"] = int(spec["w"])
		map["zoneH"] = int(spec["h"])
		map["worldId"] = "test-world"
		md.update_map(map)
		_created_maps.append(map_id)
		maps.append(md.get_by_id(map_id))
	_assert("maps_created", maps.size() == 3)
	if not maps.is_empty():
		md.preview_map_id = str(maps[0].get("id", ""))

	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1440, 900)
	await process_frame
	editor.load_map(maps[0])
	await process_frame

	var panel = editor._world_panel
	_assert("world_panel_bound", panel != null)
	_assert("world_zone_count", panel != null and panel.zones.size() >= 3)
	_assert("world_tab_exists", editor._right_tabs != null and editor._right_tabs.get_tab_count() >= 6)

	# Ouvrir l'onglet Monde et rafraîchir.
	var tab_index: int = editor._right_tabs.get_tab_idx_from_control(panel)
	_assert("world_tab_index", tab_index >= 0)
	if tab_index >= 0:
		editor._right_tabs.current_tab = tab_index
		await process_frame
		_assert("world_tab_visible", panel.visible)
		_assert("world_tab_title", editor._right_tabs.get_tab_title(tab_index).to_lower().contains("monde"))

	# Liens automatiques : chaque zone doit avoir au moins un bord relié.
	if panel != null:
		panel.auto_link()
		var linked := 0
		for map_variant in maps:
			var stored: Dictionary = md.get_by_id(str((map_variant as Dictionary).get("id", "")))
			var edges: Dictionary = stored.get("edges", {}) if stored.get("edges") is Dictionary else {}
			for side in edges:
				if not str((edges[side] as Dictionary).get("target", "")).is_empty():
					linked += 1
		_assert("world_auto_links", linked >= 2)

		# Validation : monde valide.
		panel.validate_world()
		_assert("world_valid", panel._error_lbl == null or panel._error_lbl.text.is_empty())

		# Création d'une zone via le panneau.
		var before: int = panel.zones.size()
		panel.create_zone(10, 8)
		await process_frame
		_assert("world_create_zone", panel.zones.size() == before + 1)
		if panel.zones.size() == before + 1:
			var created_id := str(panel.selected_id)
			_created_maps.append(created_id)
			var created: Dictionary = md.get_by_id(created_id)
			_assert("world_created_map", not created.is_empty())
			_assert("world_created_terrain3d", str(created.get("groundMode", "")) == "terrain3d")
			_assert("world_created_zoneW", int(created.get("zoneW", 0)) == 10)
			# Redimensionnement de la zone (taille libre façon Dofus).
			var resized_ok: bool = md.resize_complex_map(created_id, 14, 11)
			_assert("world_resize_ok", resized_ok)
			var resized: Dictionary = md.get_by_id(created_id)
			_assert("world_resize_width", int(resized.get("width", 0)) == 14)
			_assert("world_resize_height", int(resized.get("height", 0)) == 11)
			_assert("world_resize_zone", int(resized.get("zoneW", 0)) == 14 and int(resized.get("zoneH", 0)) == 11)
			_assert("world_resize_materials", (resized.get("terrainMaterials", []) as Array).size() == 14 * 11)
			panel.refresh()
			var resized_zone: Dictionary = panel._zone_by_id(created_id)
			_assert("world_resize_panel", not resized_zone.is_empty()
				and int(resized_zone.get("w", 0)) == 14 and int(resized_zone.get("h", 0)) == 11)
			# Duplication de la zone (contenu conservé, position décalée).
			var dup: Dictionary = md.duplicate_complex_map(created_id, "", 0, 12)
			_assert("world_duplicate_ok", not dup.is_empty())
			if not dup.is_empty():
				var dup_id := str(dup.get("id", ""))
				_created_maps.append(dup_id)
				_assert("world_duplicate_new_id", dup_id != created_id)
				_assert("world_duplicate_content",
					(dup.get("terrainMaterials", []) as Array).size() == 14 * 11)
				_assert("world_duplicate_zone_pos",
					int(dup.get("zoneY", 0)) == int(resized.get("zoneY", 0)) + 12)
				_assert("world_duplicate_edges", (dup.get("edges", {}) as Dictionary).is_empty())
				panel.refresh()
				_assert("world_duplicate_panel", panel.zones.size() >= before + 2)

		# Ouvrir la zone sélectionnée émet open_map_requested.
		var opened := {"map_id": ""}
		editor.open_map_requested.connect(func(id): opened["map_id"] = id)
		panel.selected_id = str(panel.zones[0].get("id", ""))
		panel.open_selected()
		await process_frame
		_assert("world_open_signal", not str(opened["map_id"]).is_empty())

		# fit_view ne doit pas planter et zoomer dans des bornes raisonnables.
		panel.fit_view()
		_assert("world_fit_zoom", panel.zoom > 0.0 and panel.zoom <= 2.0)

	editor.queue_free()
	await process_frame
	for map_id in _created_maps:
		md.delete_map(str(map_id))

	if _failed:
		print("world_editor_test:FAIL")
		quit(1)
		return
	print("world_editor_test:PASS")
	quit(0)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
