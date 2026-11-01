extends SceneTree

## Qualité de rendu 2.5D : AO écran, glow, contraste/couleurs et ombres douces
## activés par le moteur sur une carte terrain3d.
##
## Couvre aussi les ajouts « qualité Dofus » :
##   • **végétation procédurale** déterministe (touffes/fleurs, pas d'ombre,
##     teinte de nuit) ;
##   • **marche des personnages** : réutilisation des nœuds entre deux
##     `configure`, animation de déplacement (arc + poussière de pas), arrivée
##     exacte sur la case ;
##   • **pulsation d'arrivée** de caméra (feedback de changement de zone).

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

	# --- Ambiance / render quality (existant) ---
	var env: Environment = engine._world_env.environment
	_assert("render_ssao", env.ssao_enabled)
	_assert("render_glow", env.glow_enabled and env.glow_intensity > 0.0)
	_assert("render_adjustments", env.adjustment_enabled and env.adjustment_contrast > 1.0)
	_assert("render_sun_shadows", engine._sun != null and engine._sun.shadow_enabled)
	_assert("render_tonemap_aces", env.tonemap_mode == Environment.TONE_MAPPER_ACES)
	_assert("render_sun_warm", engine._sun.light_color.r > engine._sun.light_color.b)
	_assert("render_ambient", env.ambient_light_energy > 0.2)

	# --- Végétation procédurale (nouveau) ---
	_assert("render_vegetation", engine.is_vegetation_active())
	var veg_counts: Dictionary = engine.get_vegetation_counts()
	_assert("render_vegetation_tufts", int(veg_counts.get("tufts", 0)) > 0)
	_assert("render_vegetation_total", engine.get_vegetation_count() > 40)
	var veg_layer = engine._vegetation_layer
	_assert("render_vegetation_layer", veg_layer != null)
	if veg_layer != null and veg_layer.has_method("get_vegetation_mesh_instance"):
		var veg_instance = veg_layer.get_vegetation_mesh_instance()
		_assert("render_vegetation_no_shadow",
			veg_instance != null
			and veg_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_assert("render_vegetation_multimesh",
			veg_instance != null and veg_instance.multimesh != null
			and veg_instance.multimesh.instance_count == int(veg_counts.get("tufts", 0)))
		_assert("render_vegetation_wind",
			veg_layer.get_material() != null
			and float(veg_layer.get_material().get_shader_parameter("wind_strength")) > 0.0)
	# Déterministe : reconfigurer la même carte redonne exactement le même compte.
	var veg_before: int = int(engine.get_vegetation_count())
	engine.configure(village, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(4):
		await process_frame
	_assert("render_vegetation_deterministic", engine.get_vegetation_count() == veg_before)

	# --- Marche des personnages (nouveau) ---
	var tokens := [
		{"id": "tok-a", "kind": "npc", "label": "A", "x": 3.0, "y": 3.0,
			"hp": 10, "maxHp": 10},
		{"id": "tok-b", "kind": "npc", "label": "B", "x": 6.0, "y": 4.0,
			"hp": 10, "maxHp": 10},
	]
	engine.configure(village, tokens, [], [], [], [], false, true, {"mode": "select"})
	for _i in range(4):
		await process_frame
	_assert("render_tokens_created", engine._token_nodes.size() == 2)
	var node_a = engine._token_nodes.get("tok-a")
	_assert("render_token_walk_api", node_a != null and node_a.has_method("is_walking"))
	if node_a != null:
		var instance_id := int(node_a.get_instance_id())
		_assert("render_token_idle_initially", not node_a.is_walking())
		# Même carte : le nœud doit être réutilisé (pas de clignotement).
		tokens[0]["x"] = 8.0
		tokens[0]["y"] = 6.0
		engine.configure(village, tokens, [], [], [], [], false, true, {"mode": "select"})
		_assert("render_token_reused",
			engine._token_nodes.get("tok-a") == node_a
			and int(engine._token_nodes.get("tok-a").get_instance_id()) == instance_id)
		_assert("render_token_walking", node_a.is_walking())
		_assert("render_token_step_dust", node_a._dust != null)
		# La marche se termine sur la case demandée.
		await create_timer(1.0).timeout
		_assert("render_token_walk_done", not node_a.is_walking())
		_assert("render_token_arrived",
			node_a.get_grid_position().is_equal_approx(Vector2(8.0, 6.0)),
			"grid=%s" % [str(node_a.get_grid_position())])
		_assert("render_token_terrain_y",
			absf(node_a.position.y - engine.terrain_height_at(8.0, 6.0) * engine._cell_size) < 0.35)

	# --- Pulsation d'arrivée (nouveau) ---
	var zoom_before: float = float(engine.zoom)
	engine.play_arrival_pulse()
	_assert("render_arrival_started", engine.is_arrival_pulse_playing())
	await create_timer(0.9).timeout
	_assert("render_arrival_done", not engine.is_arrival_pulse_playing())
	_assert("render_arrival_zoom_restored", is_equal_approx(engine.zoom, zoom_before),
		"zoom=%f attendu=%f" % [engine.zoom, zoom_before])

	# --- Nuit : preset bleuté + végétation teintée (existant + nouveau) ---
	var night_map: Dictionary = village.duplicate(true)
	var night_light: Dictionary = md.get_lighting_config(night_map)
	night_light["preset"] = "nuit"
	night_light["nightMode"] = true
	night_map["lighting"] = night_light
	engine.configure(night_map, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(6):
		await process_frame
	_assert("render_night_preset", engine._sun.light_color.b > engine._sun.light_color.r)
	_assert("render_night_ambient", engine._world_env.environment.ambient_light_energy < 0.4)
	if engine._vegetation_layer != null and engine._vegetation_layer.get_material() != null:
		var tint = engine._vegetation_layer.get_material().get_shader_parameter("albedo_tint")
		_assert("render_night_vegetation_tint", tint is Color
			and not (tint as Color).is_equal_approx(Color.WHITE))
	else:
		_assert("render_night_vegetation_layer", false,
			"active=%s count=%d material=%s" % [
				str(engine.is_vegetation_active()),
				int(engine.get_vegetation_count()),
				str(engine._vegetation_layer.get_material() if engine._vegetation_layer != null else null),
			])

	# --- Tiny Glade : ciel pastel, preset lumineux, végétation dense, DOF/vignette ---
	var tg_map: Dictionary = village.duplicate(true)
	var tg_light: Dictionary = md.get_lighting_config(tg_map)
	tg_light["preset"] = "tiny_glade"
	tg_light["enabled"] = false
	tg_map["lighting"] = tg_light
	engine.configure(tg_map, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(8):
		await process_frame
	var tg_env: Environment = engine._world_env.environment
	_assert("tiny_glade_sky_active", engine.is_sky_active())
	_assert("tiny_glade_bg_sky", tg_env.background_mode == Environment.BG_SKY)
	var sky_mat: ShaderMaterial = engine.get_sky_material()
	_assert("tiny_glade_sky_material",
		sky_mat != null and sky_mat.shader != null
		and sky_mat.shader.code.contains("shader_type sky"))
	if sky_mat != null:
		_assert("tiny_glade_sky_pastel",
			sky_mat.get_shader_parameter("top_color") is Color
			and sky_mat.get_shader_parameter("horizon_color") is Color)
	_assert("tiny_glade_sun_warm_strong",
		engine._sun.light_color.r > engine._sun.light_color.b
		and engine._sun.light_energy > 1.2)
	_assert("tiny_glade_ambient_pastel", tg_env.ambient_light_energy > 0.5)
	_assert("tiny_glade_fog_depth",
		tg_env.fog_enabled and tg_env.fog_density > 0.0 and tg_env.fog_density < 0.01)
	_assert("tiny_glade_glow_soft",
		tg_env.glow_enabled and tg_env.glow_intensity >= 0.4)
	_assert("tiny_glade_saturation",
		tg_env.adjustment_enabled and tg_env.adjustment_saturation > 1.12)
	# Végétation dense : touffes + fleurs + buissons, plus denses qu'avant.
	var tg_counts: Dictionary = engine.get_vegetation_counts()
	_assert("tiny_glade_vegetation_dense",
		int(tg_counts.get("tufts", 0)) > 100,
		"tufts=%d" % int(tg_counts.get("tufts", 0)))
	_assert("tiny_glade_flowers",
		int(tg_counts.get("flowers", 0)) > 10,
		"flowers=%d" % int(tg_counts.get("flowers", 0)))
	_assert("tiny_glade_bushes", int(tg_counts.get("bushes", 0)) > 0,
		"bushes=%d" % int(tg_counts.get("bushes", 0)))
	# Profondeur : vignettage doux + DOF léger en perspective.
	_assert("tiny_glade_vignette", engine.get_vignette_strength() > 0.0)
	var attrs: CameraAttributes = engine.get_camera_attributes()
	_assert("tiny_glade_dof", attrs is CameraAttributesPractical
		and (attrs as CameraAttributesPractical).dof_blur_far_enabled)
	# Nuit (preset sans ciel) : on revient à un fond uni, pas de ciel résiduel.
	engine.configure(night_map, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(4):
		await process_frame
	_assert("render_night_no_sky", not engine.is_sky_active())
	_assert("render_night_bg_color",
		engine._world_env.environment.background_mode == Environment.BG_COLOR)

	engine.queue_free()
	await process_frame
	if _failed:
		print("map_render_quality_test:FAIL")
		quit(1)
		return
	print("map_render_quality_test:PASS")
	quit(0)

var _failed := false

func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label + ("" if detail.is_empty() else " (" + detail + ")"))
