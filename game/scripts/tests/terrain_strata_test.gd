extends SceneTree

## FINITIONS TERRAIN CS2 — strates de falaise, variation macro 3D, transition
## neige/roche, ancrage des objets (task-9) — test headless.
##
## Vérifie que les quatre finitions du shader `terrain_splat.gdshader` sont
## présentes, A/B RÉVERSIBLES (0 = rendu exactement précédent), que l'API
## d'ancrage des objets cuit bien la texture d'AO de contact, et qu'aucun
## contrôle livré précédemment ne régresse (géométrie du heightfield, AO cuite,
## auto-matériau, triplanar, carte d'eau…).
##
## PASS = `terrain_strata_test:PASS`.

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const TERRAIN_SPLAT_SHADER := "res://shaders/terrain_splat.gdshader"

const W := 10
const H := 8
const CELL := 1.0

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_shader_uniforms()
	await _test_defaults_and_ab()
	await _test_object_occlusion()
	await _test_reconfigure_keeps_occlusion()
	await _test_flat_map_safe()
	await _test_auto_relief_gate()
	if _failed:
		print("terrain_strata_test:FAIL")
		quit(1)
		return
	print("terrain_strata_test:PASS")
	quit(0)

# ===========================================================================
# Shader : présence des uniforms et branchements
# ===========================================================================

func _test_shader_uniforms() -> void:
	_assert("shader_exists", ResourceLoader.exists(TERRAIN_SPLAT_SHADER))
	var src := FileAccess.get_file_as_string(TERRAIN_SPLAT_SHADER)
	_assert("uniform_cliff_strata",
		src.contains("uniform float cliff_strata"))
	_assert("uniform_macro_variation",
		src.contains("uniform float macro_variation"))
	_assert("uniform_snow_transition",
		src.contains("uniform float snow_transition"))
	_assert("uniform_terrain_object_ao",
		src.contains("uniform float terrain_object_ao"))
	_assert("uniform_object_ao_tex",
		src.contains("uniform sampler2D object_ao_tex"))
	# Les finitions sont toutes court-circuitées par leur flag (A/B exact).
	_assert("cliff_strata_gated", src.contains("if (strata > 0.001)"))
	_assert("macro_gated", src.contains("if (macro_var > 0.001)"))
	_assert("snow_gated", src.contains("if (snow_t > 0.001)"))
	_assert("object_ao_gated", src.contains("if (object_ao_enabled > 0.001)"))
	# Correctif « neige sur carte plate » : porte de relief ABSOLU.
	_assert("uniform_auto_min_relief",
		src.contains("uniform float auto_min_relief"))
	_assert("auto_relief_gated", src.contains("auto_min_relief * 2.25"))
	_assert("auto_relief_relative_note", src.contains("span_world"))

# ===========================================================================
# Défauts + A/B des uniforms
# ===========================================================================

func _test_defaults_and_ab() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure(ground, _ridge_heights(), [])
	_assert("splat_active", ground.is_splat_active())
	var mat: ShaderMaterial = ground._mesh_instance.material_override
	_assert("shader_material", mat is ShaderMaterial)
	if not (mat is ShaderMaterial):
		return
	_assert("default_cliff_strata", _param(mat, "cliff_strata") == 1.0)
	_assert("default_macro_variation", _param(mat, "macro_variation") == 1.0)
	_assert("default_snow_transition", _param(mat, "snow_transition") == 1.0)
	_assert("default_terrain_object_ao", _param(mat, "terrain_object_ao") == 1.0)
	_assert("default_object_ao_disabled", _param(mat, "object_ao_enabled") == 0.0)
	_assert("api_getters",
		ground.get_cliff_strata() == 1.0
		and ground.get_macro_variation() == 1.0
		and ground.get_snow_transition() == 1.0
		and ground.get_terrain_object_ao() == 1.0)
	# A/B : 0 = rendu EXACTEMENT précédent, sans reconstruction.
	ground.set_cliff_strata(0.0)
	_assert("ab_cliff_strata_off", _param(mat, "cliff_strata") == 0.0)
	ground.set_cliff_strata(1.0)
	_assert("ab_cliff_strata_on", _param(mat, "cliff_strata") == 1.0)
	ground.set_macro_variation(0.0)
	_assert("ab_macro_off", _param(mat, "macro_variation") == 0.0)
	ground.set_macro_variation(1.0)
	_assert("ab_macro_on", _param(mat, "macro_variation") == 1.0)
	ground.set_snow_transition(0.0)
	_assert("ab_snow_off", _param(mat, "snow_transition") == 0.0)
	ground.set_snow_transition(1.0)
	_assert("ab_snow_on", _param(mat, "snow_transition") == 1.0)
	# Contrôles livrés précédemment : aucun n'a bougé.
	_assert("control_cavity_bake", _param(mat, "cavity_bake") == 1.0)
	_assert("control_auto_material", _param(mat, "auto_material_strength") == 1.0)
	# `macro_strength` reste la valeur par défaut du shader (non posée par le
	# matériau) : on vérifie la valeur déclarée pour garantir l'A/B du volet
	# « macro » historique.
	var src := FileAccess.get_file_as_string(TERRAIN_SPLAT_SHADER)
	_assert("control_macro_strength_default",
		src.contains("uniform float macro_strength : hint_range(0.0, 0.4) = 0.07;"))
	_assert("control_triplanar", is_equal_approx(_param(mat, "triplanar_lo"), 0.55))
	# Passe netteté CS2 : tuile 1,75 case (au lieu de 2) + micro-détail 0,38.
	_assert("control_tile_size", is_equal_approx(_param(mat, "tile_world_size"), 1.75))
	# Géométrie du terrain inchangée (le heightfield n'est pas retouché).
	var mesh: ArrayMesh = ground._mesh_instance.mesh
	_assert("terrain_mesh_untouched", mesh != null and mesh.get_surface_count() == 1)
	if mesh != null:
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_assert("terrain_vertex_count", verts.size() == (W + 1) * (H + 1),
			"count=%d" % verts.size())

# ===========================================================================
# Ancrage des objets : cuisson de l'AO de contact
# ===========================================================================

func _test_object_occlusion() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure(ground, _ridge_heights(), [])
	var mat: ShaderMaterial = ground._mesh_instance.material_override
	_assert("occlusion_initial_none", not ground.has_object_occlusion())
	ground.set_object_occlusion_stamps([
		{"x": 2.5, "y": 2.5, "radius": 1.2},
		{"x": 6.0, "y": 5.5, "radius": 1.6, "strength": 0.8},
	])
	_assert("occlusion_present", ground.has_object_occlusion())
	var img: Image = ground.get_object_occlusion_image()
	_assert("occlusion_image", img != null
		and img.get_width() == W and img.get_height() == H)
	if img != null:
		var center: float = img.get_pixel(2, 2).r
		var far: float = img.get_pixel(9, 0).r
		print("  [ancrage] AO centre=%.3f coin=%.3f" % [center, far])
		_assert("occlusion_center_dark", center > 0.35, "r=%.3f" % center)
		_assert("occlusion_far_clear", far < 0.02, "r=%.3f" % far)
	_assert("occlusion_uniform_on", _param(mat, "object_ao_enabled") == 1.0
		and mat.get_shader_parameter("object_ao_tex") is Texture2D)
	# A/B : force 0 = terrain inchangé (texture conservée mais neutre).
	ground.set_terrain_object_ao(0.0)
	_assert("ab_object_ao_off", _param(mat, "terrain_object_ao") == 0.0)
	ground.set_terrain_object_ao(1.0)
	_assert("ab_object_ao_on", _param(mat, "terrain_object_ao") == 1.0)
	# Effacement : uniform éteint, texture libérée.
	ground.clear_object_occlusion()
	_assert("occlusion_cleared", not ground.has_object_occlusion()
		and ground.get_object_occlusion_texture() == null
		and _param(mat, "object_ao_enabled") == 0.0)

# ===========================================================================
# Reconfiguration : les empreintes sont recuites à la nouvelle taille
# ===========================================================================

func _test_reconfigure_keeps_occlusion() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	ground.set_object_occlusion_stamps([
		{"x": 3.0, "y": 3.0, "radius": 1.0},
	])
	_configure(ground, _ridge_heights(), [])
	_assert("reconfig_occlusion_rebuilt", ground.has_object_occlusion())
	var img: Image = ground.get_object_occlusion_image()
	_assert("reconfig_occlusion_size", img != null
		and img.get_width() == W and img.get_height() == H)
	var mat: ShaderMaterial = ground._mesh_instance.material_override
	_assert("reconfig_uniform_on", _param(mat, "object_ao_enabled") == 1.0)
	# Creusements volumétriques : configure ne casse ni le socle ni l'AO.
	_configure(ground, _ridge_heights(), [
		{"id": "c1", "op": "subtract", "shape": "sphere",
			"center": Vector3(5.0, 0.0, 4.0), "radius": 1.2, "smooth": 0.4},
	])
	_assert("carves_keep_occlusion", ground.has_object_occlusion())
	_assert("carves_material", ground._mesh_instance.material_override
		is ShaderMaterial)

# ===========================================================================
# Carte plate : aucun crash, uniforms présents (aucune finition forcée)
# ===========================================================================

func _test_flat_map_safe() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	var flat: Array = []
	flat.resize(W * H)
	flat.fill(0.0)
	_configure(ground, flat, [])
	var mat: ShaderMaterial = ground._mesh_instance.material_override
	_assert("flat_material", mat is ShaderMaterial)
	_assert("flat_finitions_default",
		_param(mat, "cliff_strata") == 1.0
		and _param(mat, "macro_variation") == 1.0
		and _param(mat, "snow_transition") == 1.0)
	_assert("flat_no_occlusion", not ground.has_object_occlusion())

# ===========================================================================
# Correctif « neige sur carte plate » : porte de relief ABSOLU de l'auto-matériau
# ===========================================================================

func _test_auto_relief_gate() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	# Carte type VILLE : quasi plate, seules quelques buttes de bord (0,26).
	_configure(ground, _city_heights(), [])
	var mat: ShaderMaterial = ground._mesh_instance.material_override
	_assert("auto_relief_material", mat is ShaderMaterial)
	if not (mat is ShaderMaterial):
		return
	_assert("auto_relief_default", is_equal_approx(_param(mat, "auto_min_relief"),
		GroundScript.TERRAIN_AUTO_MIN_RELIEF))
	_assert("auto_relief_api",
		is_equal_approx(ground.get_auto_min_relief(),
			GroundScript.TERRAIN_AUTO_MIN_RELIEF))
	var span_flat := _span(mat)
	print("  [auto] carte ville : relief absolu = %.3f u (porte %.2f → %.2f)"
		% [span_flat, GroundScript.TERRAIN_AUTO_MIN_RELIEF,
			GroundScript.TERRAIN_AUTO_MIN_RELIEF * 2.25])
	# La carte ville est SOUS la porte : l'auto-matériau y est éteint (aucune
	# neige/terre automatique possible sur une butte de quelques centimètres).
	_assert("auto_relief_flat_below_gate",
		span_flat < GroundScript.TERRAIN_AUTO_MIN_RELIEF,
		"span=%.3f" % span_flat)
	# A/B : 0 = comportement historique exact (les taches revenaient).
	ground.set_auto_min_relief(0.0)
	_assert("auto_relief_off", _param(mat, "auto_min_relief") == 0.0)
	ground.set_auto_min_relief(GroundScript.TERRAIN_AUTO_MIN_RELIEF)
	_assert("auto_relief_on",
		is_equal_approx(_param(mat, "auto_min_relief"),
			GroundScript.TERRAIN_AUTO_MIN_RELIEF))
	# Contre-épreuve : une vraie montagne est AU-DESSUS du plein effet (×2,25)
	# → le rendu montagne reste strictement identique (auto actif).
	var mountain = _make_ground()
	await _wait_frames(2)
	_configure(mountain, _ridge_heights(), [])
	var mat_m: ShaderMaterial = mountain._mesh_instance.material_override
	var span_mountain := _span(mat_m)
	print("  [auto] montagne : relief absolu = %.3f u" % span_mountain)
	_assert("auto_relief_mountain_above_gate",
		span_mountain >= GroundScript.TERRAIN_AUTO_MIN_RELIEF * 2.25,
		"span=%.3f" % span_mountain)

## Amplitude de relief absolue lue sur les uniforms d'altitude du matériau.
func _span(mat: ShaderMaterial) -> float:
	return absf(_param(mat, "terrain_max_height")
		- _param(mat, "terrain_min_height"))

## Carte type VILLE : cœur plat (0) + petites buttes de bord (±0,2) — même
## amplitude que `cite_boot`/`cite_eau_boot` (~0,43 u).
func _city_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for y in range(H):
		for x in range(W):
			var border := x < 2 or y < 2 or x > W - 3 or y > H - 3
			var value := 0.0
			if border:
				value = 0.16 * sin(float(x) * 0.52) * cos(float(y) * 0.44) \
					+ 0.06 * sin(float(x + y) * 0.85) + 0.04
			heights[y * W + x] = value
	return heights

# ===========================================================================
# Données / utilitaires
# ===========================================================================

## Relief en crête : une arête centrale (pentes fortes → strates) et des
## contreforts (pentes moyennes, neige/roche selon l'altitude).
func _ridge_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for y in range(H):
		for x in range(W):
			var dx := float(x) - 5.0
			var ridge := maxf(0.0, 3.2 - absf(dx) * 0.85)
			var bump := maxf(0.0, 1.2 - Vector2(float(x) - 8.0,
				float(y) - 2.0).length() * 0.5)
			heights[y * W + x] = ridge + bump
	return heights

func _make_ground() -> Node3D:
	var ground = GroundScript.new()
	get_root().add_child(ground)
	_nodes.append(ground)
	return ground

func _configure(ground, heights: Array, carves: Array) -> void:
	var materials: Array = []
	materials.resize(W * H)
	materials.fill(0)
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		heights, "terrain3d", materials, 1, carves, {}
	)

func _param(mat, param_name: String) -> float:
	if mat == null:
		return NAN
	var value = (mat as ShaderMaterial).get_shader_parameter(param_name)
	if value is float or value is int:
		return float(value)
	_assert("param_present_%s" % param_name, false, "uniform absent")
	return NAN

func _wait_frames(n: int = 2) -> void:
	for _i in range(n):
		await process_frame

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
