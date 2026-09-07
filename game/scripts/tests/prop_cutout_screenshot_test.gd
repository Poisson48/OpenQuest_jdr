extends SceneTree

## Détourage props + captures (lancer SANS --headless pour les PNG).

const LibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const Props3DScript := preload("res://scripts/maps/map_layers/map_props_3d.gd")
const StyleScript := preload("res://scripts/maps/map_render_style.gd")

const OUT_USER := "user://prop_cutout_shots"
const OUT_DOCS := "res://../docs/screenshots"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_USER))
	LibraryScript.clear_caches()

	_test_shipped_props_have_alpha()
	_test_load_texture_knockout()
	_test_plan_flat_props()
	await _shot_simple_brumeval_session()

	if _failed:
		print("prop_cutout_screenshot_test:FAIL")
		quit(1)
		return
	print("prop_cutout_screenshot_test:PASS")
	quit(0)

func _assert(label: String, ok: bool) -> void:
	print(("OK " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _alpha_ratio(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var img := tex.get_image()
	if img == null:
		return 0.0
	var clear := 0
	var total := img.get_width() * img.get_height()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a < 0.05:
				clear += 1
	return float(clear) / float(maxi(total, 1))

func _test_shipped_props_have_alpha() -> void:
	var samples := [
		"res://data/props/nature/arbre.png",
		"res://data/props/buildings/maison.png",
		"res://data/props/objects/porte_bois.png",
		"res://data/props/characters/villageois.png",
		"res://data/props/nature/tas_foin.png",
		"res://data/props/nature/fleurs_sauvages.png",
	]
	for path in samples:
		LibraryScript.clear_caches()
		var tex := LibraryScript.load_texture(path)
		var ratio := _alpha_ratio(tex)
		_assert("alpha_%s" % path.get_file(), ratio >= 0.12)
		print("  ", path.get_file(), " clear=", snapped(ratio * 100.0, 0.1), "%")

func _test_load_texture_knockout() -> void:
	var path := "user://test-knockout-bg.png"
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.95, 0.95, 0.95, 1.0))
	for y in range(20, 44):
		for x in range(20, 44):
			img.set_pixel(x, y, Color(0.45, 0.28, 0.12, 1.0))
	img.save_png(path)
	LibraryScript.clear_caches()
	var tex := LibraryScript.load_texture(path)
	_assert("runtime_knockout", _alpha_ratio(tex) >= 0.40)
	DirAccess.remove_absolute(path)

func _test_plan_flat_props() -> void:
	var path := "res://data/props/nature/arbre.png"
	var layer := Props3DScript.new()
	get_root().add_child(layer)
	var map_data := {
		"renderStyle": "diorama",
		"backgroundImage": "res://assets/maps/valbois_village.png",
		"height": 12,
		"width": 16,
	}
	_assert("plan_flat_flag", StyleScript.prefer_flat_props(map_data))
	layer.configure([
		{"id": "p1", "asset": path, "x": 4.0, "y": 4.0, "w": 2.0, "h": 2.0, "standing": true, "layer": 1},
		{"id": "p2", "asset": "res://data/props/buildings/maison.png", "x": 8.0, "y": 5.0, "w": 3.0, "h": 3.0, "standing": true, "layer": 1},
	], 1.0, map_data)
	var flat_count := 0
	for child in layer.get_children():
		if bool(child.get_meta("flat", false)):
			flat_count += 1
	_assert("plan_props_flat", flat_count >= 2)
	layer.queue_free()

func _shot_simple_brumeval_session() -> void:
	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")
	var mm = get_root().get_node("MultiplayerManager")
	var party: Array = [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14,
			"isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "h2", "name": "Thorin", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16,
			"isPlayer": true, "isHuman": true, "clientId": "j2"},
	]
	gd.reload_builtin_scenarios()
	var scenario_id := "demo-kharak"
	if gd.get_scenario_by_id(scenario_id).is_empty():
		scenario_id = "demo-crypte"
	gd.create_new_game(scenario_id, "multi", "human", "long", party)
	gd.active_game["waitingForGm"] = true
	mm.player_role = "gm"
	mm.player_name = "MJ"
	mm.is_gm = true

	var map_id := str(gd.active_game.get("currentMapId", gd.active_game.get("mapId", "")))
	var map: Dictionary = md.get_by_id(map_id) if not map_id.is_empty() else {}
	if map.is_empty():
		map = md.get_by_id("demo-crypte-brumeval")
	_assert("session_map_is_simple", map.is_empty() or not md.is_complex_map(map))
	print("session_map_id=", map.get("id", "?"), " renderMode=", map.get("renderMode", "?"))

	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(120):
		await process_frame

	_save_root_shot("simple_brumeval_session_2d")

	var shell: Node = current_scene
	if shell != null and shell.has_method("describe"):
		var desc: Dictionary = shell.describe()
		var map_info: Dictionary = desc.get("map", {})
		print("map_describe=", map_info)
		_assert("map_stage_present", float(map_info.get("stage_size", Vector2.ZERO).x) > 100.0)
	if shell != null and shell.has_method("get_panel"):
		var stage = shell.get_panel("map")
		if stage is Control:
			await _save_control_shot("simple_brumeval_map_stage", stage as Control)

func _save_root_shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("skip_shot_headless=", name)
		return
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_assert("shot_%s" % name, false)
		return
	_write_shot(name, img)

func _save_control_shot(name: String, control: Control) -> void:
	if DisplayServer.get_name() == "headless":
		print("skip_shot_headless=", name)
		return
	await process_frame
	await process_frame
	var img: Image = control.get_viewport().get_texture().get_image()
	if img == null:
		_assert("shot_ctrl_%s" % name, false)
		return
	_write_shot(name, img)

func _write_shot(name: String, img: Image) -> void:
	var user_path := "%s/%s.png" % [OUT_USER, name]
	img.save_png(user_path)
	var docs := ProjectSettings.globalize_path(OUT_DOCS)
	DirAccess.make_dir_recursive_absolute(docs)
	var docs_path := "%s/%s.png" % [docs, name]
	img.save_png(docs_path)
	print("screenshot=", ProjectSettings.globalize_path(user_path))
	print("screenshot_docs=", docs_path)
	_assert("shot_%s" % name, true)
