extends SceneTree

## Capture de la carte du monde de session (touche M) avec la démo 5 zones.
## Non headless : nécessite un rendu réel pour sauvegarder le PNG.

var _failed := false
var _copy_dir := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_copy_dir = ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots")
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	var saved_game: Dictionary = gd.active_game.duplicate(true)

	# Monde de démo : réutilise les zones demo-valbois existantes, sinon construit.
	var zones: Array = []
	for map_variant in md.maps:
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == "demo-valbois":
			zones.append(map_variant)
	if zones.size() < 3:
		var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
		var demo: Dictionary = boot.build_demo(md)
		if demo.is_empty():
			printerr("  FAIL build_demo")
			quit(1)
			return
		zones.clear()
		for map_variant in md.maps:
			if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == "demo-valbois":
				zones.append(map_variant)
	_assert("zones_found", zones.size() >= 3)

	var ids: Array = []
	for zone_variant in zones:
		ids.append(str((zone_variant as Dictionary).get("id", "")))
	gd.active_game = {
		"id": "shot-world-map", "status": "playing", "scenarioId": "demo-valbois",
		"mapIds": ids, "currentMapId": ids[0], "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "portrait": ""}],
		"mapPlayState": {}, "mapModeOverrides": {},
		"mapNavigation": {"view": "local", "localMapId": ids[0], "discoveredZones": ids.duplicate()},
	}
	gd.ensure_map_play_state()

	var OverlayScript: GDScript = load("res://scripts/session/world_map_overlay.gd")
	var overlay: Control = OverlayScript.new()
	get_root().add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = true
	for _i in range(3):
		await process_frame
	overlay.refresh()
	overlay.fit_view()
	overlay.queue_redraw()
	for _i in range(12):
		await process_frame

	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_assert("capture", false)
	else:
		img.convert(Image.FORMAT_RGBA8)
		var out := _copy_dir.path_join("session_carte_monde.png")
		img.save_png(out)
		print("  capture: ", out, " (", img.get_width(), "x", img.get_height(), ")")
		_assert("capture", true)
	_assert("overlay_zones", overlay.zones.size() >= 3)

	overlay.queue_free()
	await process_frame
	gd.active_game = saved_game

	if _failed:
		print("world_map_shot_test:FAIL")
		quit(1)
		return
	print("world_map_shot_test:PASS")
	quit(0)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
