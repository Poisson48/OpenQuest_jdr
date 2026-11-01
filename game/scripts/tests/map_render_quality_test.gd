extends SceneTree

## Qualité de rendu 2.5D : AO écran, glow, contraste/couleurs et ombres douces
## activés par le moteur sur une carte terrain3d.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	var village: Dictionary = demo.get("map", {})
	var engine = (load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript).new()
	engine.size = Vector2(960, 540)
	get_root().add_child(engine)
	await process_frame
	engine.configure(village, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(8):
		await process_frame
	var env: Environment = engine._world_env.environment
	_assert("render_ssao", env.ssao_enabled)
	_assert("render_glow", env.glow_enabled and env.glow_intensity > 0.0)
	_assert("render_adjustments", env.adjustment_enabled and env.adjustment_contrast > 1.0)
	_assert("render_sun_shadows", engine._sun != null and engine._sun.shadow_enabled)
	_assert("render_tonemap_aces", env.tonemap_mode == Environment.TONE_MAPPER_ACES)
	_assert("render_sun_warm", engine._sun.light_color.r > engine._sun.light_color.b)
	_assert("render_ambient", env.ambient_light_energy > 0.2)
	# Changement de preset : nuit bleutée, ambiance plus basse.
	var night_map: Dictionary = village.duplicate(true)
	var night_light: Dictionary = md.get_lighting_config(night_map)
	night_light["preset"] = "nuit"
	night_map["lighting"] = night_light
	engine.configure(night_map, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(6):
		await process_frame
	_assert("render_night_preset", engine._sun.light_color.b > engine._sun.light_color.r)
	_assert("render_night_ambient", engine._world_env.environment.ambient_light_energy < 0.4)
	engine.queue_free()
	await process_frame
	if _failed:
		print("map_render_quality_test:FAIL")
		quit(1)
		return
	print("map_render_quality_test:PASS")
	quit(0)

var _failed := false

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
