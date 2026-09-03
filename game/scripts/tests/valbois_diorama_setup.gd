extends SceneTree

## Recrée Valbois + Place du Marché (vue dessus, image à l'endroit, lieu cliquable)
## et ouvre une partie jouable prête pour la session.

const StyleScript := preload("res://scripts/maps/map_render_style.gd")

const VILLAGE_PNG := "user://import_staging/valbois_village.png"
const PLACE_PNG := "user://import_staging/place_du_marche.png"
const VILLAGE_TITLE := "Valbois — Village de l'Ouest"
const PLACE_TITLE := "Place du Marché"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript

	_assert("png_village_exists", FileAccess.file_exists(VILLAGE_PNG))
	_assert("png_place_exists", FileAccess.file_exists(PLACE_PNG))
	_assert("engine_script", Engine3DScript != null)
	if _failed:
		_quit_fail()
		return

	_purge_old_valbois(md)

	# --- Carte village ---
	var cells_v: Vector2i = md.suggest_cells_from_image(VILLAGE_PNG, 70)
	var village: Dictionary = md.create_complex_map(VILLAGE_TITLE, "general", "local", cells_v.x, cells_v.y)
	var village_id: String = str(village.get("id", ""))
	_assert("village_created", not village_id.is_empty())

	var bg_v: String = md.import_background_image(village_id, ProjectSettings.globalize_path(VILLAGE_PNG))
	_assert("village_bg_imported", bg_v.begins_with("user://map_assets/") and FileAccess.file_exists(bg_v))

	village = md.get_by_id(village_id)
	# Place du Marché = centre de la clairière (fontaine + étals).
	var cx := float(cells_v.x) * 0.50
	var cy := float(cells_v.y) * 0.48
	village["areas"] = [{
		"id": "area-place-marche",
		"x": cx, "y": cy, "w": 7.0, "h": 6.0,
		"label": PLACE_TITLE,
		"category": "poi",
		"icon": "⭐",
		"showCallout": true,
		"targetMapId": "",
	}]
	village["title"] = VILLAGE_TITLE
	village["description"] = "Carte démo Valbois — vue de dessus, lieu Place du Marché cliquable."
	village["fogEnabled"] = false
	village["atmosphere"] = {"enabled": false, "tint": "#1a1410", "opacity": 0.0, "vignette": 0.0}
	var grid_v: Dictionary = md.get_grid_config(village).duplicate(true)
	grid_v["show"] = false
	village["grid"] = grid_v
	md.update_map(village)

	# --- Place enfant ---
	var place: Dictionary = md.create_child_map_for_area(village_id, "area-place-marche", cells_v.x, cells_v.y)
	var place_id: String = str(place.get("id", ""))
	_assert("place_created", not place_id.is_empty())
	_assert("place_parent", str(place.get("parentMapId", "")) == village_id)

	var cells_p: Vector2i = md.suggest_cells_from_image(PLACE_PNG, 70)
	place = md.get_by_id(place_id)
	place["width"] = cells_p.x
	place["height"] = cells_p.y
	var tiles: Array = []
	tiles.resize(cells_p.x * cells_p.y)
	tiles.fill("floor")
	place["tiles"] = tiles
	place["title"] = PLACE_TITLE
	place["description"] = "Détail Place du Marché."
	place["fogEnabled"] = false
	place["atmosphere"] = {"enabled": false, "tint": "#1a1410", "opacity": 0.0, "vignette": 0.0}
	var grid_p: Dictionary = md.get_grid_config(place).duplicate(true)
	grid_p["show"] = false
	place["grid"] = grid_p
	md.update_map(place)

	var bg_p: String = md.import_background_image(place_id, ProjectSettings.globalize_path(PLACE_PNG))
	_assert("place_bg_imported", bg_p.begins_with("user://map_assets/") and FileAccess.file_exists(bg_p))

	village = md.get_by_id(village_id)
	place = md.get_by_id(place_id)
	var area: Dictionary = md.get_area(village, "area-place-marche")
	_assert("area_linked", str(area.get("targetMapId", "")) == place_id)

	# Style illustré → vue de dessus (ortho -90°), pas l'inclinaison DD2.
	var cfg_v: Dictionary = StyleScript.config(village)
	_assert("village_topdown", not bool(cfg_v.get("perspective", true)))
	_assert("village_tilt_flat", is_equal_approx(float(cfg_v.get("tilt", 0.0)), -90.0))

	# --- Moteur : caméra + hit ---
	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	engine.size = Vector2(960, 540)
	await process_frame
	engine.configure(village, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(12):
		await process_frame
	engine.reset_zoom()
	await process_frame
	_assert("engine_ortho", engine._camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_assert("engine_topdown", is_equal_approx(engine._camera.rotation_degrees.x, -90.0))

	var hit: Dictionary = md.get_area_at(village, cx, cy)
	_assert("hit_place", str(hit.get("id", "")) == "area-place-marche")

	# Clic simulé au centre écran → doit tomber dans le lieu.
	var screen_center := engine.size * 0.5
	var grid_at: Vector2 = engine.screen_to_grid_pos(screen_center)
	var hit_screen: Dictionary = md.get_area_at(village, grid_at.x, grid_at.y)
	print("  click_grid=", grid_at, " hit=", hit_screen.get("label", ""))
	_assert("click_hits_place", str(hit_screen.get("id", "")) == "area-place-marche")

	# --- Partie jouable ---
	gd.reload_builtin_scenarios()
	var party: Array = [{
		"id": "hero-valbois-1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse",
		"hp": 12, "ac": 14, "isPlayer": true, "isHuman": true, "isBot": false,
	}]
	var game: Dictionary = gd.create_new_game("demo-couronne-fracturee", "solo", "human", "long", party, [village_id])
	gd.active_game = game
	gd.active_game["mapModeOverrides"] = {village_id: "complex", place_id: "complex"}
	gd.active_game["mapNavigation"] = {"view": "local", "localMapId": village_id}
	gd.active_game["gmName"] = "MJ Démo"
	gd.ensure_map_play_state()
	_assert("enter_place", gd.enter_area(village_id, "area-place-marche"))
	var display: Dictionary = gd.get_session_display_map(village_id)
	_assert("display_is_place", str((display.get("displayMap", {}) as Dictionary).get("id", "")) == place_id)
	_assert("exit_place", gd.exit_area())
	gd.save_active_game()

	engine.queue_free()

	print("")
	print("=== VALBOIS DEMO READY ===")
	print("village_id=", village_id)
	print("place_id=", place_id)
	print("game_id=", game.get("id", ""))
	print("cells_v=", cells_v, " cells_p=", cells_p)
	print("Lancer : scripts/play-godot.sh res://scenes/debug/valbois_demo_boot.tscn")
	print("Ou Hub → Jouer → partie Valbois (mode Complexe) → clic Place du Marché")
	print("==========================")

	if _failed:
		_quit_fail()
		return
	print("valbois_diorama_setup:PASS")
	quit(0)

func _purge_old_valbois(md) -> void:
	var remove_ids: Array = []
	for m_variant in md.maps:
		var m: Dictionary = m_variant
		var title := str(m.get("title", ""))
		var mid := str(m.get("id", ""))
		if title.begins_with("Valbois") or title == PLACE_TITLE or title.begins_with("Valbois "):
			remove_ids.append(mid)
		# Cartes enfants orphelines liées aux tests.
		elif str(m.get("parentMapId", "")) != "" and title in [PLACE_TITLE, "Taverne", "Ruelle"]:
			var parent: Dictionary = md.get_by_id(str(m.get("parentMapId", "")))
			if parent.is_empty() or str(parent.get("title", "")).begins_with("Valbois"):
				remove_ids.append(mid)
	for id_variant in remove_ids:
		var id := str(id_variant)
		if id.is_empty():
			continue
		if md.has_method("delete_map"):
			md.delete_map(id)
		else:
			for i in range(md.maps.size() - 1, -1, -1):
				if str(md.maps[i].get("id", "")) == id:
					md.maps.remove_at(i)
	if md.has_method("save_maps"):
		md.save_maps()
	print("  purged ", remove_ids.size(), " old Valbois-related maps")

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true

func _quit_fail() -> void:
	printerr("valbois_diorama_setup:FAIL")
	quit(1)
