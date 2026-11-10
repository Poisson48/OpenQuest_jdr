extends SceneTree

## Test de structure UI v2 de l'éditeur (map_editor.tscn) — vérifie SANS load_map
## que la bibliothèque a quitté le dock droit et que les options de l'outil ont
## quitté la colonne de gauche (reparentage programmatique).

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var ed = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(ed)
	await process_frame
	await process_frame

	# 1) Bibliothèque : sortie du TabContainer droit.
	var lib = ed._library_panel
	_assert("library_exists", lib != null)
	_assert("library_not_in_right_tabs",
		lib != null and not _is_descendant(lib, ed._right_tabs))

	# 2) Options de l'outil : sorties de la colonne de gauche.
	var tool_opts = ed._tool_options
	_assert("tool_options_exists", tool_opts != null)
	_assert("tool_options_not_in_left_panel",
		tool_opts != null and not _is_descendant(tool_opts, ed._left_panel))

	# 3) Thème de la toile immersive : accent doré.
	_assert("theme_assigned", ed.theme != null)
	_assert("theme_font_pressed_color",
		ed.theme != null
		and ed.theme.get_color("font_pressed_color", "Button") == Color("#F2C46C"))

	# 4) Label FPS créé.
	_assert("fps_label_created", ed._fps_lbl != null)

	_assert("canvas_full_height", ed._viewport_frame.size.y == ed.size.y)
	_assert("options_closed_on_launch", not ed._options_bar.visible)
	ed._immersive_buttons["terrain_height"].pressed.emit()
	await process_frame
	await process_frame
	_assert("relief_opens_brush_options", ed._tool == "terrain_height" and ed._options_bar.visible)
	_assert("brush_options_above_dock", ed._options_bar.get_global_rect().end.y < ed._immersive_dock.global_position.y)
	ed._immersive_buttons["mesh"].pressed.emit()
	_assert("objects_opens_library", ed._library_dock.visible and ed._prop_category == "objects3d")
	_assert("library_hides_brush_options", not ed._options_bar.visible)
	ed._toggle_ui(false)
	_assert("tab_hides_overlays", not ed._immersive_dock.visible and not ed._library_dock.visible)
	ed._toggle_ui(false)
	_assert("tab_restores_overlays", ed._immersive_dock.visible and ed._library_dock.visible)

	ed.queue_free()
	await process_frame
	if _failed:
		print("map_editor_ui_v2_test:FAIL")
		quit(1)
		return
	print("map_editor_ui_v2_test:PASS")
	quit(0)

func _is_descendant(node: Node, ancestor: Node) -> bool:
	var cur := node.get_parent()
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
