extends SceneTree

## Rejoue le tracé réel et capture DEUX images : (1) la nappe seule (terrain
## masqué) pour vérifier la continuité du maillage, (2) le rendu complet.
## Permet de distinguer un trou de MAILLAGE d'une simple occlusion par le sol.

const OUT_DIR := "user://river_shots"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var f := FileAccess.open("user://last_river_trace.json", FileAccess.READ)
	if f == null:
		print("  [trace] aucun tracé")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var w: int = int(data.get("mapW", 24))
	var h: int = int(data.get("mapH", 16))
	var path: Array = data.get("path", [])
	var bed: float = float(data.get("bed", 0.35))
	var depth: float = float(data.get("depth", 0.25))
	var width: float = float(data.get("width", 1.2))
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Trace utilisateur", "general", "local", w, h)
	var heights: Array = []
	heights.resize(w * h)
	heights.fill(0.0)
	map["terrainHeights"] = heights
	var scene: PackedScene = load("res://scenes/map_editor/map_editor.tscn")
	var editor: Control = scene.instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	editor.load_map(map)
	editor.set_editable(true)
	await process_frame
	editor._water_river_bed = bed
	editor._water_river_depth = depth
	editor._water_river_width = width
	editor._carve_river_bed(path)
	editor.doc.add_water_body({
		"kind": "river", "width": width, "flow_speed": 0.35,
		"depth": depth, "path": path,
	}, "Rivière")
	editor._engine.refresh_terrain(editor.doc.map_data)
	editor._engine.request_fit_to_view()
	for _i in range(10):
		await process_frame
	# (1) Nappe SEULE : terrain masqué.
	var ground = editor._engine._ground
	if ground != null:
		ground.visible = false
	for _i in range(4):
		await process_frame
	var img1: Image = get_root().get_texture().get_image()
	_save(img1, "river_water_only")
	if ground != null:
		ground.visible = true
	for _i in range(4):
		await process_frame
	var img2: Image = get_root().get_texture().get_image()
	_save(img2, "river_with_terrain")
	print("river_user_trace_shot_test:PASS")
	quit(0)

func _save(img: Image, name: String) -> void:
	if img == null:
		print("  [FAIL] capture %s" % name)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	DirAccess.make_dir_recursive_absolute("user://river_shots/copy")
	var dst := ProjectSettings.globalize_path("user://river_shots") + "/" + name + ".png"
	print("  capture: %s" % dst)
	DirAccess.copy_absolute(dst, "D:/git/OpenQuest_jdr/docs/screenshots/" + name + ".png")
