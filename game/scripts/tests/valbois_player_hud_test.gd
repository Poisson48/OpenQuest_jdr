extends SceneTree

## Valide la vue joueur immersive : carte plein écran + HUD.
## Lancer SANS --headless.

const OUT_DIR := "user://valbois_screenshots"
const COPY_DIR := "/home/leo/Documents/GitHub/OpenQuest_jdr/docs/screenshots"
const PORTRAIT_RES := "res://assets/portraits/voleur_kael.png"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(COPY_DIR)

	var village := _find_valbois(md)
	_assert("village", not village.is_empty())
	if _failed:
		quit(1)
		return

	var village_id := str(village.get("id", ""))
	var portrait := PORTRAIT_RES if ResourceLoader.exists(PORTRAIT_RES) else ""
	var party: Array = [{
		"id": "hero-kael-voleur",
		"name": "Kael",
		"race": "Humain",
		"class": "Voleur",
		"hp": 11,
		"ac": 14,
		"isPlayer": true,
		"isHuman": true,
		"portrait": portrait,
		"image": portrait,
		"stats": {"str": 10, "dex": 16, "con": 12, "int": 11, "wis": 13, "cha": 9},
	}]

	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-couronne-fracturee", "solo", "human", "long", party, [village_id])
	gd.active_game["waitingForGm"] = false
	gd.active_game["forcePlayerView"] = true
	gd.active_game["mapModeOverrides"] = {village_id: "complex"}
	gd.active_game["mapNavigation"] = {
		"view": "local",
		"localMapId": village_id,
		"worldMapId": null,
		"worldCell": null,
		"areaStack": [],
	}
	gd.ensure_map_play_state()
	var w: int = int(village.get("width", 20))
	var h: int = int(village.get("height", 16))
	gd.place_member_token(village_id, int(w * 0.5), int(h * 0.58), "hero-kael-voleur")
	gd.add_log_entry("Kael", "Test HUD immersif.", "player")
	gd.save_active_game()

	mm.player_role = "player"
	mm.player_name = "Kael"
	mm.is_gm = false

	DisplayServer.window_set_title("Valbois player HUD")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	get_root().size = Vector2i(1280, 720)

	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(90):
		await process_frame

	var session: Node = current_scene
	_assert("session", session != null and session.has_method("_is_player_view"))
	if session == null:
		quit(1)
		return

	var immersive: bool = bool(session.get("_immersive_player"))
	var hud: Control = session.get("_player_hud") as Control
	_assert("immersive_flag", immersive)
	_assert("hud_present", hud != null and hud.visible)
	_assert("player_view", bool(session.call("_is_player_view")))

	var header: Control = session.get_node_or_null("MainLayout/HeaderBar") as Control
	_assert("header_hidden", header == null or not header.visible)

	var split: Node = session.get_node_or_null("MainLayout/ContentSplit")
	if split and split.get_child_count() > 0:
		var side_child: Control = split.get_child(0) as Control
		_assert("sidebar_hidden", side_child == null or not side_child.visible)

	var map_panel: Control = session.get("map_panel") as Control
	_assert("map_panel", map_panel != null)
	if map_panel:
		_assert("map_immersive", bool(map_panel.get("_immersive")))
		var map_h := map_panel.size.y
		_assert("map_tall", map_h >= 500.0)
		print("  map_size=", map_panel.size)
		var engine = map_panel.get("_complex_engine")
		if engine:
			var overlay: Control = engine.get("_token_overlay") as Control
			var icons: Dictionary = engine.get("_overlay_icons")
			print("  overlay_children=", overlay.get_child_count() if overlay else -1, " icons=", icons.size() if icons else -1)
			_assert("token_overlay", overlay != null and icons != null and icons.size() >= 1)
			for tid in icons:
				var entry = icons[tid]
				var icon = entry["icon"] if entry is Dictionary else entry
				if icon is TextureRect and icon.texture != null:
					var img: Image = icon.texture.get_image()
					if img:
						var semi := 0
						var opq := 0
						for y in range(img.get_height()):
							for x in range(img.get_width()):
								var a := img.get_pixel(x, y).a
								if a >= 0.95:
									opq += 1
								elif a > 0.05:
									semi += 1
						print("  tex_alpha opaque=", opq, " semi=", semi, " mat=", icon.material != null)
						img.save_png("/home/leo/Documents/GitHub/OpenQuest_jdr/docs/screenshots/kael_overlay_tex.png")
				print("  icon_modulate=", icon.modulate if icon else null, " visible=", icon.visible if icon else null)

	await _shot("05_valbois_player_hud")

	if _failed:
		print("[VALBOIS PLAYER HUD] FAIL")
		quit(1)
	else:
		print("[VALBOIS PLAYER HUD] PASS")
		quit(0)

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	var user_path := "%s/%s.png" % [OUT_DIR, name]
	var abs_user := ProjectSettings.globalize_path(user_path)
	img.save_png(abs_user)
	var copy_path := "%s/%s.png" % [COPY_DIR, name]
	img.save_png(copy_path)
	print("[SHOT] ", copy_path, " ", img.get_width(), "x", img.get_height())

func _find_valbois(md) -> Dictionary:
	var best: Dictionary = {}
	for m_variant in md.maps:
		var m: Dictionary = m_variant
		if not str(m.get("title", "")).begins_with("Valbois — Village"):
			continue
		if str(m.get("backgroundImage", "")).is_empty():
			continue
		best = m
	return best

func _assert(label: String, ok: bool) -> void:
	if ok:
		print("  OK  ", label)
	else:
		print("  FAIL ", label)
		_failed = true
