extends SceneTree

const MapModeScript := preload("res://scripts/maps/map_mode.gd")
const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")
	var map_id := ""

	_assert("mode_const", MapModeScript.SIMPLE == "simple")
	_assert("is_complex", MapModeScript.is_complex(MapModeScript.COMPLEX))

	var blank: Dictionary = md.create_blank_map("Test Simple", "general", "local")
	_assert("blank_mode", md.get_render_mode(blank) == MapModeScript.SIMPLE)

	var complex_map: Dictionary = md.create_complex_map("Test VTT", "general", "local", 12, 8)
	map_id = complex_map.get("id", "")
	_assert("complex_map", md.is_complex_map(complex_map))
	_assert("eff_mode_complex", md.get_render_mode(complex_map) == MapModeScript.COMPLEX)
	_assert("schema", int(complex_map.get("schemaVersion", 0)) >= 2)

	var grid: Dictionary = md.get_grid_config(complex_map)
	_assert("grid", int(grid.get("size", 0)) == 70)
	_assert("tex", md.generate_tile_texture(complex_map) != null)

	var fire: Dictionary = MapEffectPresetsScript.get_preset("fire")
	_assert("fire", fire.get("type") == "particles")
	_assert("presets", MapEffectPresetsScript.PRESET_IDS.has("magic"))

	gd.active_game = {
		"id": "test-map-mode", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [map_id],
		"party": [{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true}],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	_assert("eff_mode_override", gd.get_effective_render_mode(map_id) == MapModeScript.COMPLEX or md.get_render_mode(complex_map) == MapModeScript.COMPLEX)

	gd.set_map_render_mode_override(map_id, MapModeScript.SIMPLE)
	_assert("override_simple", gd.get_effective_render_mode(map_id) == MapModeScript.SIMPLE)
	gd.set_map_render_mode_override(map_id, MapModeScript.COMPLEX)

	md.set_render_mode(map_id, MapModeScript.SIMPLE)
	_assert("persist_simple", md.get_render_mode(md.get_by_id(map_id)) == MapModeScript.SIMPLE)
	md.set_render_mode(map_id, MapModeScript.COMPLEX)
	_assert("persist_complex", md.get_render_mode(md.get_by_id(map_id)) == MapModeScript.COMPLEX)

	gd.apply_complex_map_click(map_id, 3.0, 4.0, {"mode": "member", "memberId": "hero-1"})
	_assert("token", gd.get_map_play_tokens(map_id).size() == 1)

	var fx: Dictionary = gd.place_map_effect(map_id, "fire", 5.0, 5.0, 1.2)
	_assert("fx", not fx.is_empty() and gd.get_map_effects(map_id).size() == 1)

	gd.trigger_map_effect(map_id, str(fx.get("id", "")))
	_assert("fx_trigger", bool(gd.get_map_effects(map_id)[0].get("triggered", false)))

	gd.reveal_fog_cells(map_id, ["0,0", "1,0", "0,1"])
	_assert("fog", gd.get_fog_revealed_cells(map_id).size() >= 3)

	gd.place_map_zone(map_id, 6.0, 6.0, "circle", 2.0, "Sort")
	_assert("zone", gd.get_map_zones(map_id).size() == 1)

	gd.move_complex_token(map_id, str(gd.get_map_play_tokens(map_id)[0].get("id", "")), 7.0, 2.0)
	_assert("move", float(gd.get_map_play_tokens(map_id)[0].get("x", 0)) == 7.0)

	print("map_mode_test:PASS")
	quit(0)

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("map_mode_test:FAIL at ", name)
		quit(1)
		return
