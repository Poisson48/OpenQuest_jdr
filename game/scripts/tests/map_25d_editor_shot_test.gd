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

	# Capture de l'outil Token en mode PNJ avec dialogue.
	editor._token_kind = "npc"
	editor._token_label = "Marchand"
	editor._token_dialogue = "Des marchandises fraîches de Valbois !"
	editor._set_tool("token")
	await _wait(10)
	var token_img: Image = get_root().get_texture().get_image()
	if token_img != null:
		token_img.convert(Image.FORMAT_RGBA8)
		var token_out := copy_dir.path_join("carte_25d_token_pnj.png")
		token_img.save_png(token_out)
		print("  capture: ", token_out)

	# Seconde capture : vue Monde (zones de tailles différentes).
	if editor._world_panel != null and editor._right_tabs != null:
		var world_tab: int = editor._right_tabs.get_tab_idx_from_control(editor._world_panel)
		if world_tab >= 0:
			editor._right_tabs.current_tab = world_tab
			await _wait(8)
			editor._world_panel.refresh()
			editor._world_panel.fit_view()
			await _wait(12)
			var world_img: Image = get_root().get_texture().get_image()
			if world_img != null:
				world_img.convert(Image.FORMAT_RGBA8)
				var world_out := copy_dir.path_join("carte_25d_monde.png")
				world_img.save_png(world_out)
				print("  capture: ", world_out, " (", world_img.get_width(), "x", world_img.get_height(), ")")
				_assert("world_zones_visible", editor._world_panel.zones.size() >= 3)

			# Plein écran de la vue Monde.
			editor._world_panel.toggle_fullscreen()
			await _wait(10)
			editor._world_panel.fit_view()
			await _wait(10)
			var full_img: Image = get_root().get_texture().get_image()
			if full_img != null:
				full_img.convert(Image.FORMAT_RGBA8)
				var full_out := copy_dir.path_join("carte_25d_monde_plein_ecran.png")
				full_img.save_png(full_out)
				print("  capture: ", full_out, " (", full_img.get_width(), "x", full_img.get_height(), ")")
			editor._world_panel.toggle_fullscreen()
			await _wait(6)

	# Second monde (thèmes Lac / plage) : capture en plein écran.
	if editor._world_panel != null and editor._world_panel._world_opt != null:
		var isles_index := -1
		var valbois_index := -1
		for i in range(editor._world_panel._world_opt.item_count):
			var world_meta := str(editor._world_panel._world_opt.get_item_metadata(i))
			if world_meta == "demo-iles":
				isles_index = i
			elif world_meta == "demo-valbois":
				valbois_index = i
		if isles_index >= 0:
			editor._world_panel._on_world_selected(isles_index)
			await _wait(8)
			var monde_tab: int = editor._right_tabs.get_tab_idx_from_control(editor._world_panel)
			if monde_tab >= 0:
				editor._right_tabs.current_tab = monde_tab
			if editor._world_panel._fullscreen:
				editor._world_panel.toggle_fullscreen()
				await _wait(6)
			editor._world_panel.toggle_fullscreen()
			await _wait(10)
			editor._world_panel.fit_view()
			await _wait(10)
			var isles_img: Image = get_root().get_texture().get_image()
			if isles_img != null:
				isles_img.convert(Image.FORMAT_RGBA8)
				var isles_out := copy_dir.path_join("carte_25d_monde_iles.png")
				isles_img.save_png(isles_out)
				print("  capture: ", isles_out)
				_assert("world_second_world", editor._world_panel.zones.size() == 2)
			editor._world_panel.toggle_fullscreen()
			await _wait(6)
		if valbois_index >= 0:
			editor._world_panel._on_world_selected(valbois_index)
			await _wait(6)

	if _failed:
		printerr("map_25d_editor_shot_test:FAIL")
		quit(1)
		return
	# Export PNG du viewport 3D (hors UI), sans passer par le dialogue.
	var export_abs := copy_dir.path_join("carte_25d_vue3d.png")
	editor._export_map_image(export_abs)
	await _wait(20)
	_assert("image_export_exists", FileAccess.file_exists(export_abs))
	if FileAccess.file_exists(export_abs):
		var f := FileAccess.open(export_abs, FileAccess.READ)
		_assert("image_export_nonempty", f != null and f.get_length() > 1000)
		if f != null:
			f.close()
		print("  capture: ", export_abs)
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
