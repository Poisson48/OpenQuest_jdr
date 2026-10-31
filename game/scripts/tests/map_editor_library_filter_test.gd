extends SceneTree

## Tests des filtres/recherche de la bibliothèque 3D (80 objets).

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test biblio 3D", "general", "local", 12, 10)
	var map_id := str(map.get("id", ""))
	md.update_map(map)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	editor.load_map(md.get_by_id(map_id))
	await process_frame
	editor._prop_category = "objects3d"
	editor._object3d_filter = "all"
	editor._object3d_search = ""
	editor._refresh_asset_library()
	await process_frame

	_assert("filters_built", editor._asset_filter_row.get_child_count() == 7)
	_assert("search_visible", editor._asset_search.visible)
	# Le bouton import est dans la grille : 1 + N assets filtrés.
	print("  ..   all=", _asset_buttons(editor))
	_assert("all_assets_count", _asset_buttons(editor) >= 80)

	editor._object3d_filter = "characters"
	editor._refresh_asset_library()
	await process_frame
	print("  ..   characters=", _asset_buttons(editor))
	_assert("characters_count", _asset_buttons(editor) == 10)

	editor._object3d_filter = "roofs"
	editor._refresh_asset_library()
	await process_frame
	print("  ..   roofs=", _asset_buttons(editor))
	_assert("roofs_count", _asset_buttons(editor) == 13)

	editor._object3d_filter = "all"
	editor._object3d_search = "mage"
	editor._refresh_asset_library()
	await process_frame
	_assert("search_mage", _asset_buttons(editor) == 1)

	editor._object3d_search = ""
	editor._object3d_filter = "all"
	editor._refresh_asset_library()
	await process_frame

	editor.queue_free()
	await process_frame
	md.delete_map(map_id)

	if _failed:
		print("map_editor_library_filter_test:FAIL")
		quit(1)
		return
	print("map_editor_library_filter_test:PASS")
	quit(0)

func _asset_buttons(editor: Control) -> int:
	# Grille : bouton import + un bouton par asset filtré.
	return editor._asset_grid.get_child_count() - 1

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
