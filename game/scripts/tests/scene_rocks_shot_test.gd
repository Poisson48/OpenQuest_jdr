extends SceneTree

## Capture d'écran : scène de village générée avec son mur de rochers empilés.
##
## Vérifie que le paramétrique produit bien des pierres du kit dans l'éditeur,
## puis sauvegarde le rendu complet de l'interface dans `docs/screenshots/`.

const ROW_STEP := 0.48
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Rochers générés", "general", "local", 30, 22)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	md.update_map(map)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1440, 900)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(md.get_by_id(str(map.get("id", ""))))
	await process_frame

	editor._scene_style = "village"
	editor._scene_seed = 20261111
	editor._scene_density = 1.0
	editor._construction._generate_scene(Vector2(15.0, 11.0))
	await process_frame

	var rocks: Array = []
	for elem_variant in editor.doc.elements_of_kind("mesh"):
		var elem: Dictionary = elem_variant
		if str(elem.get("label", "")) == "Rocher généré":
			rocks.append(elem)
	_assert("generated_rocks", rocks.size() >= 6, "count=%d" % rocks.size())
	if not rocks.is_empty():
		var max_elevation := 0.0
		for rock_variant in rocks:
			max_elevation = maxf(max_elevation, float((rock_variant as Dictionary).get("elevation", 0.0)))
		_assert("rocks_stacked", max_elevation >= ROW_STEP, "max=%.2f" % max_elevation)

	# Recentrage sur la carte puis capture de l'éditeur complet.
	if editor._engine != null:
		editor._engine.reset_editor_camera()
	for _i in range(10):
		await process_frame
	await _shot(editor, "scene_rocks_village")

	# Gros plan sur le mur : on cadre la zone générée.
	if editor._engine != null:
		editor._engine.zoom = 1.6
		editor._engine._update_ortho_size()
		editor._engine._center_focus_on(Vector2(6.0, 2.0))
	for _i in range(10):
		await process_frame
	await _shot(editor, "scene_rocks_closeup")

	if _failed:
		print("scene_rocks_shot_test:FAIL")
		quit(1)
		return
	print("scene_rocks_shot_test:PASS")
	quit(0)

func _shot(control: Control, shot_name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = control.get_viewport().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % shot_name, false)
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s.png" % shot_name)
	img.save_png(out)
	print("  capture: %s" % out)
	return img

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
