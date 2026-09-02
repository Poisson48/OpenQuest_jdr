extends SceneTree

const SCREENSHOT_DIR := "user://flow_test_screenshots"
const REPORT_PATH := "user://flow_test_report.json"

var _steps: Array = []
var _failed := false
var _gd: Node
var _md: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_gd = get_root().get_node("GameData")
	_md = get_root().get_node("MapData")
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	_gd.clear_all_saved_games()
	await process_frame

	await _step("01_menu_accueil", func():
		change_scene_to_file("res://scenes/main_menu.tscn")
		await _wait_scene("MainMenu")
		return await _click("%BtnPlay")
	)

	await _step("02_configuration", func():
		await _wait_scene("GameSetup")
		var setup := current_scene
		var opt: OptionButton = setup.get_node("%OptScenario")
		var target_idx := _find_scenario_index(opt, "demo-couronne-fracturee")
		if target_idx < 0:
			target_idx = 0
		opt.select(target_idx)
		opt.item_selected.emit(target_idx)
		await process_frame
		return { "scenario": opt.get_item_text(target_idx) }
	)

	await _step("03_lancer_partie", func():
		var setup := current_scene
		var btn: Button = setup.get_node("%BtnStartGame")
		btn.pressed.emit()
		await _wait_scene("Session")
		return { "has_active_game": _gd.has_active_game() }
	)

	await _step("04_session_carte", func():
		var session := current_scene
		var map_panel: PanelContainer = session.get_node("%MapPanel")
		await process_frame
		await process_frame
		map_panel.refresh()
		await process_frame
		var map_ids: Array = _gd.active_game.get("mapIds", [])
		return {
			"map_panel_visible": map_panel.visible,
			"map_ids": map_ids,
			"map_count": map_ids.size(),
		}
	)

	await _step("05_clic_carte_token", func():
		var session := current_scene
		var map_panel: PanelContainer = session.get_node("%MapPanel")
		if not map_panel.visible:
			return { "skipped": true, "reason": "no maps" }
		var imap: Control = _find_interactive_map(map_panel)
		if imap == null:
			return { "error": "InteractiveMap introuvable" }
		var map_ids: Array = _gd.active_game.get("mapIds", [])
		var active_id: String = map_ids[0] if not map_ids.is_empty() else ""
		var ctx: Dictionary = _gd.get_session_display_map(active_id)
		var display_map: Dictionary = ctx.get("displayMap", {})
		var cx := int(display_map.get("width", 10) / 2)
		var cy := int(display_map.get("height", 10) / 2)
		if _md.is_world_map(display_map):
			var start: Vector2i = _gd.get_world_map_start_point(display_map)
			cx = start.x
			cy = start.y
		var map_id: String = display_map.get("id", "")
		var before: int = _gd.get_map_play_tokens(map_id).size()
		imap._handle_cell_click(cx, cy)
		await process_frame
		map_panel.refresh()
		await process_frame
		var after: int = _gd.get_map_play_tokens(map_id).size()
		return { "cell": [cx, cy], "tokens_before": before, "tokens_after": after, "placed": after > before }
	)

	await _step("06_navigation_monde", func():
		var map_ids: Array = _gd.active_game.get("mapIds", [])
		var world_id := ""
		for id in map_ids:
			var m: Dictionary = _md.get_by_id(id)
			if _md.is_world_map(m):
				world_id = id
				break
		if world_id.is_empty():
			return { "skipped": true, "reason": "pas de carte monde" }
		var world: Dictionary = _md.get_by_id(world_id)
		var links: Array = world.get("locationLinks", [])
		if links.is_empty():
			return { "skipped": true, "reason": "pas de lien" }
		var link: Dictionary = links[0]
		_gd.enter_local_map(world_id, int(link.get("x", 0)), int(link.get("y", 0)), str(link.get("targetMapId", "")))
		await process_frame
		var session := current_scene
		var map_panel: PanelContainer = session.get_node("%MapPanel")
		map_panel.refresh()
		await process_frame
		var nav: Dictionary = _gd.active_game.get("mapNavigation", {})
		return {
			"view": nav.get("view"),
			"local_map": nav.get("localMapId"),
			"entered": nav.get("view") == "local",
		}
	)

	await _step("07_retour_monde", func():
		_gd.exit_to_world_map()
		await process_frame
		var session := current_scene
		session.get_node("%MapPanel").refresh()
		await process_frame
		var nav: Dictionary = _gd.active_game.get("mapNavigation", {})
		return { "view": nav.get("view"), "back_to_world": nav.get("view") == "world" }
	)

	await _step("08_action_joueur", func():
		var session := current_scene
		var input: LineEdit = session.get_node("%InputAction")
		input.text = "J'explore la salle principale."
		session.get_node("%BtnSendAction").pressed.emit()
		await process_frame
		var log: Array = _gd.active_game.get("log", [])
		var last_type := ""
		if not log.is_empty():
			last_type = log.back().get("type", "")
		return { "log_entries": log.size(), "last_type": last_type }
	)

	_write_report()
	quit(0 if not _failed else 1)

func _step(name: String, action: Callable) -> void:
	print("[FLOW] ", name, "...")
	var result: Variant = await action.call()
	await _screenshot(name)
	var ok := not _has_error(result)
	_steps.append({ "step": name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[FLOW] FAIL ", name, " -> ", result)
	else:
		print("[FLOW] OK   ", name, " -> ", result)

func _has_error(result: Variant) -> bool:
	if result is Dictionary:
		if result.has("error"):
			return true
		if result.get("placed", true) == false and not result.has("skipped"):
			return false
		if result.get("entered", true) == false and not result.has("skipped"):
			return true
		if result.get("back_to_world", true) == false:
			return true
		if result.get("map_panel_visible", true) == false and not result.has("skipped"):
			return true
		if result.get("has_active_game", true) == false:
			return true
	return false

func _click(unique_name: String) -> Dictionary:
	var node := current_scene.get_node(unique_name)
	if node is BaseButton:
		node.pressed.emit()
		await process_frame
		return { "clicked": unique_name }
	return { "error": "Bouton introuvable: " + unique_name }

func _wait_scene(root_name: String, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			await process_frame
			return
	push_warning("Timeout scène: " + root_name)

func _find_scenario_index(opt: OptionButton, scenario_id: String) -> int:
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == scenario_id:
			return i
	return -1

func _find_interactive_map(root: Node) -> Control:
	for child in root.get_children():
		if child.get_script() and str(child.get_script().resource_path).ends_with("interactive_map.gd"):
			return child as Control
		var found := _find_interactive_map(child)
		if found:
			return found
	return null

func _screenshot(name: String) -> void:
	await process_frame
	await process_frame
	var root := get_root()
	if root == null:
		return
	var tex := root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img:
		img.save_png(SCREENSHOT_DIR.path_join(name + ".png"))

func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT PARCOURS UTILISATEUR ===")
	print(JSON.stringify(report, "\t"))
