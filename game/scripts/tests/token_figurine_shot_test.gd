extends SceneTree

## Capture des figurines 3D de tokens en carte 2.5D (village).
## Non headless : nécessite un rendu réel.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var copy_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var village: Dictionary = demo.get("map", {})
	if village.is_empty():
		printerr("  FAIL village")
		quit(1)
		return
	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = EngineScript.new()
	get_root().add_child(engine)
	engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var party := [
		{"id": "hero-1", "name": "Aria", "class": "Archère"},
		{"id": "hero-2", "name": "Bran", "class": "Mage"},
		{"id": "hero-3", "name": "Célia", "class": "Garde"},
	]
	var tokens := [
		{"id": "tok-aria", "kind": "member", "memberId": "hero-1", "label": "Aria", "x": 9.0, "y": 7.0, "hp": 12, "maxHp": 12},
		{"id": "tok-bran", "kind": "member", "memberId": "hero-2", "label": "Bran", "x": 8.0, "y": 8.0, "hp": 12, "maxHp": 12},
		{"id": "tok-celia", "kind": "member", "memberId": "hero-3", "label": "Célia", "x": 10.2, "y": 7.8, "hp": 12, "maxHp": 12},
	]
	engine.configure(village, tokens, party, [], [], [], false, true)
	await process_frame
	if engine.has_method("fit"):
		engine.fit()
	if engine.has_method("focus_grid_rect"):
		engine.focus_grid_rect(Rect2(6.5, 5.0, 7.0, 5.0))
	if engine.has_method("reset_zoom"):
		engine.reset_zoom()
	for _i in range(24):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("  FAIL capture")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := copy_dir.path_join("carte_25d_figurines.png")
	img.save_png(out)
	print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
	engine.queue_free()
	await process_frame
	print("token_figurine_shot_test:PASS")
	quit(0)
