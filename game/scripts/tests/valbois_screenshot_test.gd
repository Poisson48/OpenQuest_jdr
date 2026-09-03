extends SceneTree

## Capture écran Valbois (village → place) pour validation visuelle diorama.
## Lancer SANS --headless (le SubViewport 3D doit rendre).

const StyleScript := preload("res://scripts/maps/map_render_style.gd")
const OUT_DIR := "user://valbois_screenshots"
const COPY_DIR := "/home/leo/Documents/GitHub/OpenQuest_jdr/docs/screenshots"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript
	_assert("engine", Engine3DScript != null)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(COPY_DIR)

	var village := _find_or_create_valbois(md)
	var village_id := str(village.get("id", ""))
	var area: Dictionary = md.get_area(village, "area-place-marche")
	if area.is_empty() and village.get("areas") is Array and not (village["areas"] as Array).is_empty():
		area = village["areas"][0]
	var place_id := str(area.get("targetMapId", ""))
	var place: Dictionary = md.get_by_id(place_id)
	_assert("village_ok", not village_id.is_empty() and not str(village.get("backgroundImage", "")).is_empty())
	_assert("place_ok", not place.is_empty() and not str(place.get("backgroundImage", "")).is_empty())
	_assert("diorama", StyleScript.is_diorama(village))
	var cfg: Dictionary = StyleScript.config(village)
	_assert("illustrated_topdown", not bool(cfg.get("perspective", true)))
	_assert("illustrated_tilt", is_equal_approx(float(cfg.get("tilt", 0.0)), -90.0))
	if _failed:
		quit(1)
		return

	DisplayServer.window_set_title("Valbois demo validation")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_root().size = Vector2i(1280, 720)

	var engine: Control = Engine3DScript.new()
	engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine.size = Vector2(1280, 720)
	get_root().add_child(engine)
	await process_frame

	# --- Village ---
	engine.configure(
		village, [], [], [], [], [],
		false, true, {"mode": "select"}, {}, ""
	)
	for _i in range(45):
		await process_frame
	engine.reset_zoom()
	for _i in range(10):
		await process_frame
	_assert("cam_ortho", engine._camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_assert("cam_topdown", is_equal_approx(engine._camera.rotation_degrees.x, -90.0))
	await _shot("01_valbois_village")

	# Hit + navigation au centre (Place du Marché)
	var ax := float(area.get("x", 10))
	var ay := float(area.get("y", 8))
	var hit: Dictionary = md.get_area_at(village, ax, ay)
	_assert("hit_area", not hit.is_empty())
	var grid_center: Vector2 = engine.screen_to_grid_pos(engine.size * 0.5)
	var hit_center: Dictionary = md.get_area_at(village, grid_center.x, grid_center.y)
	_assert("center_hits_place", str(hit_center.get("id", "")) == str(area.get("id", "")))

	gd.active_game = {
		"id": "shot-valbois",
		"status": "playing",
		"scenarioId": "demo-couronne-fracturee",
		"mapIds": [village_id],
		"gmType": "human",
		"party": [{"id": "hero-1", "name": "Test", "hp": 10, "isPlayer": true}],
		"mapPlayState": {},
		"mapNavigation": {"view": "world"},
		"mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	_assert("enter", gd.enter_area(village_id, str(area.get("id", ""))))

	# --- Place ---
	place = md.get_by_id(place_id)
	engine.configure(
		place, [], [], [], [], [],
		false, true, {"mode": "member"}, {}, ""
	)
	for _i in range(45):
		await process_frame
	await _shot("02_place_du_marche")
	_assert("exit", gd.exit_area())

	# --- Session réelle (MapPanel) ---
	engine.queue_free()
	await process_frame
	gd.active_game = {
		"id": "shot-valbois-session",
		"status": "playing",
		"scenarioId": "demo-couronne-fracturee",
		"mapIds": [village_id],
		"gmType": "human",
		"party": [{"id": "hero-1", "name": "Test", "hp": 10, "isPlayer": true}],
		"mapPlayState": {},
		"mapNavigation": {"view": "local", "localMapId": village_id},
		"mapModeOverrides": {village_id: "complex"},
	}
	gd.ensure_map_play_state()
	gd.save_active_game()
	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(90):
		await process_frame
		if current_scene and current_scene.name == "Session":
			break
	_assert("session", current_scene != null and current_scene.name == "Session")
	if current_scene:
		var map_panel = current_scene.get_node_or_null("%MapPanel")
		if map_panel:
			if map_panel.has_method("_on_session_mode_pressed"):
				map_panel._on_session_mode_pressed("complex")
			if map_panel.has_method("refresh"):
				map_panel.refresh()
			for _j in range(20):
				await process_frame
			# Deux passes de sync : le layout session met du temps à se stabiliser.
			for _pass in range(3):
				if map_panel.has_method("_sync_map_viewport_size"):
					map_panel._sync_map_viewport_size()
				for _j in range(25):
					await process_frame
	await _shot("03_session_village")

	if current_scene and gd.enter_area(village_id, str(area.get("id", ""))):
		var map_panel2 = current_scene.get_node_or_null("%MapPanel")
		if map_panel2 and map_panel2.has_method("refresh"):
			map_panel2.refresh()
		for _k in range(15):
			await process_frame
		for _pass2 in range(3):
			if map_panel2 and map_panel2.has_method("_sync_map_viewport_size"):
				map_panel2._sync_map_viewport_size()
			for _k in range(25):
				await process_frame
		await _shot("04_session_place")

	print("")
	print("=== VALBOIS SCREENSHOTS ===")
	print("village_id=", village_id)
	print("place_id=", place_id)
	print("out=", OUT_DIR)
	print("copy=", COPY_DIR)
	if _failed:
		print("valbois_screenshot_test:FAIL")
		quit(1)
		return
	print("valbois_screenshot_test:PASS")
	quit(0)

func _find_or_create_valbois(md) -> Dictionary:
	var best: Dictionary = {}
	for m_variant in md.maps:
		var m: Dictionary = m_variant
		if str(m.get("title", "")).begins_with("Valbois — Village") and not str(m.get("backgroundImage", "")).is_empty():
			best = m
	if not best.is_empty():
		return best
	# Fallback : recréer via staging
	var village_png := "user://import_staging/valbois_village.png"
	var place_png := "user://import_staging/place_du_marche.png"
	if not FileAccess.file_exists(village_png) or not FileAccess.file_exists(place_png):
		return {}
	var cells: Vector2i = md.suggest_cells_from_image(village_png, 70)
	var village: Dictionary = md.create_complex_map("Valbois — Village de l'Ouest", "general", "local", cells.x, cells.y)
	var vid := str(village.get("id", ""))
	md.import_background_image(vid, ProjectSettings.globalize_path(village_png))
	village = md.get_by_id(vid)
	village["areas"] = [{
		"id": "area-place-marche",
		"x": float(cells.x) * 0.5, "y": float(cells.y) * 0.48,
		"w": 6.0, "h": 5.0,
		"label": "Place du Marché", "category": "poi", "icon": "⭐",
		"showCallout": true, "targetMapId": "",
	}]
	md.update_map(village)
	var place: Dictionary = md.create_child_map_for_area(vid, "area-place-marche", cells.x, cells.y)
	var pid := str(place.get("id", ""))
	var cells_p: Vector2i = md.suggest_cells_from_image(place_png, 70)
	place = md.get_by_id(pid)
	place["width"] = cells_p.x
	place["height"] = cells_p.y
	var tiles: Array = []
	tiles.resize(cells_p.x * cells_p.y)
	tiles.fill("floor")
	place["tiles"] = tiles
	place["title"] = "Place du Marché"
	md.update_map(place)
	md.import_background_image(pid, ProjectSettings.globalize_path(place_png))
	return md.get_by_id(vid)

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var tex := get_root().get_texture()
	if tex == null:
		_assert("shot_tex_" + name, false)
		return
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 10:
		_assert("shot_img_" + name, false)
		return
	var user_path := OUT_DIR.path_join(name + ".png")
	var err := img.save_png(user_path)
	_assert("shot_save_" + name, err == OK)
	var abs_user := ProjectSettings.globalize_path(user_path)
	var copy_path := COPY_DIR.path_join(name + ".png")
	var src := FileAccess.open(abs_user, FileAccess.READ)
	var dst := FileAccess.open(copy_path, FileAccess.WRITE)
	if src and dst:
		dst.store_buffer(src.get_buffer(src.get_length()))
		print("  shot ", name, " → ", copy_path, " (", img.get_width(), "x", img.get_height(), ")")
	else:
		# Fallback shell-less: try DirAccess.copy
		DirAccess.copy_absolute(abs_user, copy_path)
		print("  shot ", name, " → ", copy_path)

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true
