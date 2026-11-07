extends SceneTree

## Reproduit le geste RÉEL de l'utilisateur : tracé d'une rivière SINUEUSE sur
## sol PLAT dans l'éditeur (creusement du lit + création), puis capture.
## Sert de test de vérité — si cette capture montre des trous, le bug est réel.

const OUT_DIR := "user://river_shots"
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Riviere plat", "general", "local", 24, 16)
	var heights: Array = []
	heights.resize(24 * 16)
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
	editor._tool = ToolsScript.WATER_PAINT
	editor._water_mode = "river"
	editor._water_river_width = 1.2
	editor._water_river_bed = 0.35
	editor._water_river_depth = 0.25
	await process_frame
	var curve := [
		Vector2(2.0, 8.0), Vector2(4.0, 6.0), Vector2(6.0, 7.2),
		Vector2(8.0, 5.4), Vector2(10.0, 6.6), Vector2(12.0, 5.0),
		Vector2(14.0, 6.2), Vector2(16.0, 5.2), Vector2(18.0, 6.8),
		Vector2(20.0, 6.0),
	]
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var start: Vector2 = curve[0]
	editor._on_pointer_pressed(start,
		editor._engine.grid_to_screen(start.x, start.y), MOUSE_BUTTON_LEFT, mods)
	# Mouvements fins le long de la courbe (comme une souris qui glisse).
	for i in range(curve.size() - 1):
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i + 1]
		var steps := maxi(2, ceili(a.distance_to(b) / 0.25))
		for s in range(1, steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			editor._on_pointer_moved(p,
				editor._engine.grid_to_screen(p.x, p.y), mods)
	await process_frame
	var last: Vector2 = curve[curve.size() - 1]
	editor._on_pointer_released(last,
		editor._engine.grid_to_screen(last.x, last.y), MOUSE_BUTTON_LEFT, mods)
	await process_frame
	await process_frame
	print("  [river] corps d'eau=%d press_mode=%s" % [
		editor.doc.map_data.get("waterBodies", []).size(), str(editor._press_mode)])
	var bodies: Array = editor.doc.map_data.get("waterBodies", [])
	if bodies.is_empty():
		print("  [FAIL] river_created")
		_failed = true
		print("river_live_shot_test:FAIL")
		quit(1)
		return
	# Recadre la caméra sur la carte puis capture.
	editor._engine.request_fit_to_view()
	for _i in range(8):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		print("  [FAIL] capture")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/river_live.png" % OUT_DIR)
	DirAccess.make_dir_recursive_absolute("docs/screenshots")
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("%s/river_live.png" % OUT_DIR),
		ProjectSettings.globalize_path("docs/screenshots") + "/river_live.png")
	print("  capture: docs/screenshots/river_live.png")
	print("river_live_shot_test:PASS")
	quit(0)
