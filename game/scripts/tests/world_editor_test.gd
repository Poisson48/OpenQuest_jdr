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
		panel.create_zone(10, 8, "Clairière test", "snow")
		await process_frame
		_assert("world_create_zone", panel.zones.size() == before + 1)
		if panel.zones.size() == before + 1:
			var created_id := str(panel.selected_id)
			_created_maps.append(created_id)
			var created: Dictionary = md.get_by_id(created_id)
			_assert("world_created_map", not created.is_empty())
			_assert("world_created_title", str(created.get("title", "")) == "Clairière test")
			_assert("world_created_terrain3d", str(created.get("groundMode", "")) == "terrain3d")
			_assert("world_created_theme", str(created.get("ambientFx", "")) == "snow"
				and (created.get("terrainMaterials", []) as Array).has(3))
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
			# Lien de bord manuel (éditeur « Lier… »).
			var other_id := str((maps[1] as Dictionary).get("id", ""))
			_assert("world_manual_link", md.set_zone_edge(created_id, "north", other_id, 2))
			var linked_map: Dictionary = md.get_by_id(created_id)
			var north: Dictionary = (linked_map.get("edges", {}) as Dictionary).get("north", {})
			_assert("world_manual_link_target", str(north.get("target", "")) == other_id)
			_assert("world_manual_link_offset", int(north.get("offset", -99)) == 2)
			_assert("world_manual_unlink", md.set_zone_edge(created_id, "north", ""))
			var unlinked: Dictionary = md.get_by_id(created_id)
			_assert("world_manual_unlink_effect",
				not (unlinked.get("edges", {}) as Dictionary).has("north"))

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

		# Plein écran : la vue Monde sort de l'onglet puis y revient.
		panel.toggle_fullscreen()
		await process_frame
		_assert("world_fullscreen_on", panel.is_fullscreen() and panel.get_parent() == editor)
		panel.toggle_fullscreen()
		await process_frame
		_assert("world_fullscreen_off", not panel.is_fullscreen()
			and panel.get_parent() == editor._right_tabs)

		# Session de test lancée depuis la vue Monde (sans changement de scène).
		var gd = get_root().get_node("GameData")
		var saved_game: Dictionary = gd.active_game.duplicate(true)
		var play_ids: Array = []
		for zone_variant in panel.zones:
			play_ids.append(str((zone_variant as Dictionary).get("id", "")))
		_assert("world_playtest_start", gd.start_world_playtest(play_ids, str(play_ids[0]), false))
		_assert("world_playtest_current", str(gd.active_game.get("currentMapId", "")) == str(play_ids[0]))
		_assert("world_playtest_party", (gd.active_game.get("party", []) as Array).size() >= 2)
		_assert("world_playtest_tokens",
			gd.get_map_play_tokens(str(play_ids[0])).size() >= 2)
		gd.active_game = saved_game

		# Thème « Lac » : dépression, eau et rive de sable.
		var lake_sample := {"width": 10, "height": 8}
		MapThemePresets.apply(lake_sample, "lake")
		_assert("world_theme_lake_water", float(lake_sample.get("waterLevel", -1.0)) > -1.0)
		_assert("world_theme_lake_depth",
			(lake_sample.get("terrainHeights", []) as Array).any(func(v): return float(v) < -0.1))
		_assert("world_theme_lake_sand",
			(lake_sample.get("terrainMaterials", []) as Array).has(4))
		_assert("world_theme_lake_starters",
			not (lake_sample.get("meshes", []) as Array).is_empty())

		# Tous les thèmes produisent une carte valide et cohérente.
		_assert("world_theme_count", MapThemePresets.THEMES.size() >= 7)
		for theme_variant in MapThemePresets.THEMES:
			var theme: Dictionary = theme_variant
			var theme_id := str(theme.get("id", ""))
			var sample := {"width": 12, "height": 9}
			MapThemePresets.apply(sample, theme_id)
			_assert("world_theme_%s_materials" % theme_id,
				(sample.get("terrainMaterials", []) as Array).size() == 12 * 9)
			_assert("world_theme_%s_heights" % theme_id,
				(sample.get("terrainHeights", []) as Array).size() == 12 * 9)
			_assert("world_theme_%s_ambient" % theme_id,
				str(sample.get("ambientFx", "")) in ["", "leaves", "fireflies", "rain", "snow", "dust"])

		# Assigner une carte existante (hors monde) comme nouvelle zone.
		var free_map: Dictionary = md.create_complex_map("Carte libre", "general", "local", 11, 7)
		var free_id := str(free_map.get("id", ""))
		_created_maps.append(free_id)
		_assert("world_assign_map", md.assign_map_to_world(free_id, "test-world", 40, 40))
		var assigned: Dictionary = md.get_by_id(free_id)
		_assert("world_assign_world", str(assigned.get("worldId", "")) == "test-world")
		_assert("world_assign_size", int(assigned.get("zoneW", 0)) == 11
			and int(assigned.get("zoneH", 0)) == 7)
		_assert("world_assign_position", int(assigned.get("zoneX", -1)) == 40
			and int(assigned.get("zoneY", -1)) == 40)
		panel.refresh()
		_assert("world_assign_panel", not panel._zone_by_id(free_id).is_empty())

		# Sélecteur de monde : crée un second monde et vérifie le basculement.
		var other_map: Dictionary = md.create_complex_map("Autre monde", "general", "local", 9, 7)
		var other_id := str(other_map.get("id", ""))
		_created_maps.append(other_id)
		md.assign_map_to_world(other_id, "other-world", 0, 0)
		_assert("world_title_set", md.set_world_title("other-world", "Îles Perdues")
			and md.get_world_title("other-world") == "Îles Perdues")
		panel.refresh()
		var titled_label := ""
		for i in range(panel._world_opt.item_count):
			if str(panel._world_opt.get_item_metadata(i)) == "other-world":
				titled_label = panel._world_opt.get_item_text(i)
				break
		_assert("world_title_selector", titled_label.begins_with("Îles Perdues"))
		_assert("world_selector_multi", panel._world_opt != null and panel._world_opt.item_count >= 2)
		var other_index := -1
		for i in range(panel._world_opt.item_count):
			if str(panel._world_opt.get_item_metadata(i)) == "other-world":
				other_index = i
				break
		_assert("world_selector_has_other", other_index >= 0)
		if other_index >= 0:
			panel._on_world_selected(other_index)
			_assert("world_selector_switches", panel._view_world_id == "other-world"
				and panel.zones.size() == 1)
			panel._on_world_selected(0)

		# Création d'un nouveau monde depuis le sélecteur.
		var new_world_index := -1
		for i in range(panel._world_opt.item_count):
			if str(panel._world_opt.get_item_metadata(i)) == "__new__":
				new_world_index = i
				break
		_assert("world_selector_has_new", new_world_index >= 0)
		if new_world_index >= 0:
			panel._on_world_selected(new_world_index)
			_assert("world_new_created", not panel._view_world_id.is_empty()
				and panel.zones.size() == 1)
			if not panel.selected_id.is_empty():
				_created_maps.append(str(panel.selected_id))
			panel._on_world_selected(0)

		# Export / import d'un monde complet (zones + liens remappés).
		var bundle_a: Dictionary = md.create_complex_map("Bundle A", "general", "local", 10, 7)
		var bundle_b: Dictionary = md.create_complex_map("Bundle B", "general", "local", 8, 6)
		var bundle_a_id := str(bundle_a.get("id", ""))
		var bundle_b_id := str(bundle_b.get("id", ""))
		_created_maps.append(bundle_a_id)
		_created_maps.append(bundle_b_id)
		md.assign_map_to_world(bundle_a_id, "bundle-src", 0, 0)
		md.assign_map_to_world(bundle_b_id, "bundle-src", 11, 0)
		md.set_zone_edge(bundle_a_id, "east", bundle_b_id)
		md.set_world_title("bundle-src", "Monde Source")
		var bundle: Dictionary = md.export_world_bundle("bundle-src")
		_assert("world_export_zones", (bundle.get("zones", []) as Array).size() == 2)
		_assert("world_export_title", str(bundle.get("worldTitle", "")) == "Monde Source")
		var imported: Dictionary = md.import_world_bundle(bundle, "bundle-dst")
		var imported_ids: Array = imported.get("mapIds", [])
		_assert("world_import_count", imported_ids.size() == 2)
		if imported_ids.size() == 2:
			for imported_id_variant in imported_ids:
				_created_maps.append(str(imported_id_variant))
			var first: Dictionary = md.get_by_id(str(imported_ids[0]))
			var second: Dictionary = md.get_by_id(str(imported_ids[1]))
			_assert("world_import_world", str(first.get("worldId", "")) == "bundle-dst"
				and str(second.get("worldId", "")) == "bundle-dst")
			_assert("world_import_new_ids", str(imported_ids[0]) != bundle_a_id
				and str(imported_ids[1]) != bundle_b_id)
			_assert("world_import_title", md.get_world_title("bundle-dst") == "Monde Source")
			var first_edges: Dictionary = first.get("edges", {})
			_assert("world_import_edges", str((first_edges.get("east", {}) as Dictionary).get("target", ""))
				== str(imported_ids[1]))

		# Suppression d'un monde depuis le sélecteur (nettoie les liens orphelins).
		var link_src: Dictionary = md.create_complex_map("Lien vers autre monde", "general", "local", 6, 6)
		var link_src_id := str(link_src.get("id", ""))
		_created_maps.append(link_src_id)
		md.assign_map_to_world(link_src_id, "test-world", 60, 60)
		md.set_zone_edge(link_src_id, "east", other_id)
		panel._view_world_id = "other-world"
		panel.refresh()
		panel._apply_delete_world()
		_assert("world_delete", md.get_by_id(other_id).is_empty())
		var cleaned_edges: Dictionary = md.get_by_id(link_src_id).get("edges", {})
		_assert("world_delete_cleans_links", cleaned_edges.is_empty())

		# Import via l'UI comme nouveau monde indépendant (fichier JSON réel).
		var tmp_bundle: String = ProjectSettings.globalize_path("user://test_import_new_world.json")
		var bundle_file := FileAccess.open(tmp_bundle, FileAccess.WRITE)
		if bundle_file != null:
			bundle_file.store_string(JSON.stringify(bundle))
			bundle_file.close()
			panel._import_as_new_world = true
			panel._on_world_import_selected(tmp_bundle)
			var new_world: String = panel._view_world_id
			var imported_first: Dictionary = md.get_by_id(panel.selected_id)
			_assert("world_import_ui_new", not new_world.is_empty()
				and new_world != "bundle-src" and new_world != "bundle-dst")
			_assert("world_import_ui_world", str(imported_first.get("worldId", "")) == new_world)
			for map_variant in md.maps.duplicate():
				if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == new_world:
					md.delete_map(str((map_variant as Dictionary).get("id", "")))
			DirAccess.remove_absolute(tmp_bundle)

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
