extends SceneTree

## Capture de l'éditeur de cartes en mode « carte 2.5D » : la bibliothèque
## d'objets 3D est ouverte et l'outil Objet 3D est armé. Lancer SANS --headless :
##   godot --path game --script res://scripts/tests/map_25d_editor_shot_test.gd
##
## Sortie : docs/screenshots/carte_25d_editeur.png

const OUT_DIR := "user://map_25d_shots"
const COPY_DIR := "docs/screenshots"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var BootScript: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = BootScript.build_demo(md)
	if demo.is_empty():
		printerr("map_25d_editor_shot_test:FAIL (démo vide)")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var game_root := ProjectSettings.globalize_path("res://").rstrip("/")
	var copy_dir := game_root.get_base_dir().path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(copy_dir)

	DisplayServer.window_set_title("Carte 2.5D — éditeur")
	get_root().content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1920, 1200))
	get_root().size = Vector2i(1920, 1200)

	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(demo["map"])
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	await process_frame

	var assets: Array = demo.get("assets", [])
	_assert("assets_available", assets.size() >= 3)
	if not assets.is_empty():
		editor._prop_category = "objects3d"
		editor._mesh_asset = str((assets[0] as Dictionary).get("path", ""))
		editor._mesh_scale = 1.0
		editor._set_tool("mesh")
		editor._refresh_asset_library()
		editor._apply_responsive_layout()
		# Pose un objet 3D par le chemin réel de l'éditeur, pour la capture.
		editor._create_mesh(Vector2(9.0, 8.0))
		# Affiche la bibliothèque d'objets 3D (parcours « n'importe qui »).
		if editor._right_tabs and editor._right_tabs.get_tab_count() > 3:
			editor._right_tabs.current_tab = 3
	await _wait(20)
	_assert("asset_grid_filled", editor._asset_grid.get_child_count() >= 3)
	_assert("mesh_placed", editor.doc.count_of_kind("mesh") >= 4)
	print("  [layout] editor.size=", editor.size,
		" viewport_rect=", editor.get_viewport_rect().size,
		" window=", DisplayServer.window_get_size(),
		" dockL=", editor._dock_left_w, " dockR=", editor._dock_right_w,
		" split_outer=", editor._split_outer.split_offset,
		" split_inner=", editor._split_inner.split_offset,
		" right_pos=", editor._right_tabs.position, " right_size=", editor._right_tabs.size,
		" left_size=", editor._left_scroll.size)

	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_failed = true
		printerr("  FAIL capture nulle")
	else:
		img.convert(Image.FORMAT_RGBA8)
		var out := copy_dir.path_join("carte_25d_editeur.png")
		img.save_png(out)
		print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")

	if _failed:
		printerr("map_25d_editor_shot_test:FAIL")
		quit(1)
		return
	print("map_25d_editor_shot_test:PASS")
	quit(0)

func _wait(n: int) -> void:
	for _i in range(n):
		await process_frame

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
