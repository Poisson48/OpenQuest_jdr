extends SceneTree

## FINITIONS CS2 eau/terrain (task-4) — test headless de NON-RÉGRESSION et de
## présence des trois finitions livrées sur le chantier « qualité CS2 » :
##
##  1. Brume/écume volumétrique au pied des cascades  → uniform `mist_enabled`,
##     nœuds de brume hors `_body_nodes` (le nombre de bassins et le nombre de
##     surfaces des maillages d'eau ne changent pas) ;
##  2. Éclairage double du lit réfracté                → uniform
##     `bed_ambient_lift` (shaders d'eau ET de terrain) ;
##  3. Adoucissement des nez de ruban vus de très haut → uniform
##     `tip_soften_distance` + masque de pointe en COLOR.b des rubans.
##
## Chaque finition est A/B réversible : la valeur 0 doit ramener EXACTEMENT
## l'état précédent (aucun autre réglage modifié), et les contrôles livrés
## précédemment (réflexion/réfraction écran, berge, AO cuite, auto-matériau)
## doivent rester intacts.
##
## PASS = `cs2_finitions_test:PASS`.

const WaterScript := preload("res://scripts/maps/map_layers/map_water_3d.gd")
const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")

const WATER_SURFACE_SHADER := "res://shaders/water_surface.gdshader"
const WATER_MIST_SHADER := "res://shaders/water_mist.gdshader"
const TERRAIN_SPLAT_SHADER := "res://shaders/terrain_splat.gdshader"

## Carte de validation : escalier 4 marches (mêmes données que le test de
## capture `staircase_cascade_shot_test`) → au moins 2 vraies chutes.
const W := 20
const H := 16
const CELL := 1.0

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_shaders_present()
	await _test_mist_and_ribbon()
	await _test_bed_ambient()
	await _test_legacy_plane_unaffected()
	if _failed:
		print("cs2_finitions_test:FAIL")
		quit(1)
		return
	print("cs2_finitions_test:PASS")
	quit(0)

# ===========================================================================
# Shaders : présence des uniforms des finitions
# ===========================================================================

func _test_shaders_present() -> void:
	_assert("shader_water_surface_exists", ResourceLoader.exists(WATER_SURFACE_SHADER))
	_assert("shader_water_mist_exists", ResourceLoader.exists(WATER_MIST_SHADER))
	_assert("shader_terrain_splat_exists", ResourceLoader.exists(TERRAIN_SPLAT_SHADER))
	var surface_src := FileAccess.get_file_as_string(WATER_SURFACE_SHADER)
	var terrain_src := FileAccess.get_file_as_string(TERRAIN_SPLAT_SHADER)
	var mist_src := FileAccess.get_file_as_string(WATER_MIST_SHADER)
	# 1. Brume de pied (A/B `mist_enabled`).
	_assert("mist_shader_has_uniform",
		mist_src.contains("uniform float mist_enabled"))
	_assert("mist_shader_dissipates_with_height",
		mist_src.contains("pow(1.0 - h"))
	# 2. Éclairage double du lit (A/B `bed_ambient_lift`) sur les DEUX shaders.
	_assert("surface_shader_has_bed_ambient_lift",
		surface_src.contains("uniform float bed_ambient_lift"))
	_assert("terrain_shader_has_bed_ambient_lift",
		terrain_src.contains("uniform float bed_ambient_lift"))
	# 3. Nez de ruban (A/B `tip_soften_distance`) + masque de pointe en COLOR.b.
	_assert("surface_shader_has_tip_soften",
		surface_src.contains("uniform float tip_soften_distance"))
	_assert("surface_shader_uses_color_b_mask",
		surface_src.contains("COLOR.b") and surface_src.contains("fwidth("))

# ===========================================================================
# Brume de pied de cascade + nez de ruban (rivière escalier)
# ===========================================================================

func _test_mist_and_ribbon() -> void:
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(W, H, CELL, -1.0, _staircase_heights(), false, 1, 1.0,
		[], {}, [_staircase_river()])
	await process_frame
	_assert("mist_water_active", water.is_active())
	# NON-RÉGRESSION structurelle : un bassin, deux surfaces (eau + cascades).
	_assert("mist_body_count", water.get_body_count() == 1,
		"n=%d" % water.get_body_count())
	if water.get_body_count() != 1:
		water.queue_free()
		await process_frame
		return
	var node: MeshInstance3D = water._body_nodes[0]
	var mesh: ArrayMesh = node.mesh
	_assert("mist_surface_count_unchanged", mesh.get_surface_count() == 2,
		"surfaces=%d" % mesh.get_surface_count())
	# --- 1) BRUME : nœuds hors `_body_nodes`, quads bornés, défaut ON --------
	var falls := water.get_fall_count()
	print("  [brume] chutes=%d quads=%d nœuds=%d"
		% [falls, water.get_mist_quad_count(), water.get_mist_count()])
	_assert("mist_falls_detected", falls >= 2, "chutes=%d" % falls)
	_assert("mist_quads_built", water.get_mist_quad_count() == falls * 2,
		"quads=%d chutes=%d" % [water.get_mist_quad_count(), falls])
	_assert("mist_quad_budget",
		water.get_mist_quad_count() <= WaterScript.MIST_MAX_QUADS,
		"quads=%d" % water.get_mist_quad_count())
	_assert("mist_node_outside_bodies", water.get_mist_count() == 1,
		"n=%d" % water.get_mist_count())
	var mist_mat: ShaderMaterial = water.get_mist_material()
	_assert("mist_material_shader", mist_mat != null and mist_mat.shader != null)
	if mist_mat != null:
		_assert("mist_default_on",
			is_equal_approx(_fparam(mist_mat, "mist_enabled"), 1.0))
		_assert("mist_node_visible",
			(water._mist_nodes[0] as MeshInstance3D).visible)
		# A/B : 0 = aucune brume (discard) et nœuds masqués.
		water.set_mist_enabled(false)
		_assert("mist_off_uniform",
			is_equal_approx(_fparam(mist_mat, "mist_enabled"), 0.0))
		_assert("mist_off_node_hidden",
			not (water._mist_nodes[0] as MeshInstance3D).visible)
		_assert("mist_off_flag", not water.is_mist_enabled())
		water.set_mist_enabled(true)
		_assert("mist_restored",
			is_equal_approx(_fparam(mist_mat, "mist_enabled"), 1.0)
			and (water._mist_nodes[0] as MeshInstance3D).visible)
	# --- Contrôles livrés précédemment : NON-RÉGRESSION ---------------------
	var mat: ShaderMaterial = mesh.surface_get_material(0)
	_assert("control_river_edge_softness",
		is_equal_approx(_fparam(mat, "edge_softness"), 0.72))
	_assert("control_reflection_on",
		is_equal_approx(_fparam(mat, "reflection_enabled"), 1.0))
	_assert("control_refraction_on",
		is_equal_approx(_fparam(mat, "refraction_enabled"), 1.0))
	_assert("control_flow_dir",
		(mat.get_shader_parameter("flow_dir") as Vector2).is_equal_approx(
			Vector2(0.0, 1.0)))
	_assert("control_depth_map",
		mat.get_shader_parameter("depth_map") is Texture2D)
	# --- 2) ÉCLAIRAGE DOUBLE DU LIT : défaut ON + A/B sur les surfaces -------
	_assert("bed_default_on",
		is_equal_approx(_fparam(mat, "bed_ambient_lift"), 1.0))
	_assert("bed_layer_getter", is_equal_approx(water.get_bed_ambient_lift(), 1.0))
	water.set_bed_ambient_lift(0.0)
	_assert("bed_off_uniform",
		is_equal_approx(_fparam(mat, "bed_ambient_lift"), 0.0))
	_assert("bed_off_keeps_other_controls",
		is_equal_approx(_fparam(mat, "reflection_enabled"), 1.0)
		and is_equal_approx(_fparam(mat, "refraction_enabled"), 1.0))
	water.set_bed_ambient_lift(1.0)
	_assert("bed_restored",
		is_equal_approx(_fparam(mat, "bed_ambient_lift"), 1.0))
	# --- 3) NEZ DE RUBAN : masque COLOR.b + A/B -----------------------------
	_assert("tip_default_on",
		is_equal_approx(_fparam(mat, "tip_soften_distance"), 1.0))
	water.set_tip_soften(0.0)
	_assert("tip_off_uniform",
		is_equal_approx(_fparam(mat, "tip_soften_distance"), 0.0))
	water.set_tip_soften(1.0)
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	_assert("tip_mask_colors", colors.size() > 0)
	var max_tip := 0.0
	var min_tip := 1.0
	var max_fade := 0.0
	var min_fade := 1.0
	for c in colors:
		max_tip = maxf(max_tip, c.b)
		min_tip = minf(min_tip, c.b)
		max_fade = maxf(max_fade, c.r)
		min_fade = minf(min_fade, c.r)
	print("  [pointe] masque B=[%.2f..%.2f] fondu R=[%.2f..%.2f]"
		% [min_tip, max_tip, min_fade, max_fade])
	# Masque de pointe : plein au nez, nul au cœur du chenal.
	_assert("tip_mask_peaks_at_tips", max_tip > 0.9, "max=%.2f" % max_tip)
	_assert("tip_mask_neutral_midchannel", min_tip < 0.05, "min=%.2f" % min_tip)
	# Fondu d'alpha historique inchangé : plein au cœur, atténué aux extrémités.
	_assert("tip_keeps_alpha_fades", max_fade > 0.99 and min_fade < 0.4,
		"R=[%.2f..%.2f]" % [min_fade, max_fade])
	water.queue_free()
	await process_frame

# ===========================================================================
# Éclairage double du lit — volet TERRAIN (uniform + A/B)
# ===========================================================================

func _test_bed_ambient() -> void:
	var ground = GroundScript.new()
	get_root().add_child(ground)
	var materials: Array = []
	materials.resize(W * H)
	materials.fill(0)
	ground.configure(null, W, H, CELL, true, null, false, [], [], 0.22,
		_staircase_heights(), "terrain3d", materials)
	await process_frame
	_assert("bed_ground_splat_active", ground.is_splat_active())
	var mat = ground._mesh_instance.material_override
	_assert("bed_ground_shader_material", mat is ShaderMaterial)
	if not (mat is ShaderMaterial):
		ground.queue_free()
		await process_frame
		return
	# Défaut ON (finition visible dans l'éditeur)…
	_assert("bed_ground_default_on",
		is_equal_approx(_fparam(mat, "bed_ambient_lift"), 1.0))
	_assert("bed_ground_layer_getter",
		is_equal_approx(ground.get_bed_ambient_lift(), 1.0))
	# …et A/B : 0 ramène exactement l'état précédent.
	ground.set_bed_ambient_lift(0.0)
	_assert("bed_ground_off",
		is_equal_approx(_fparam(mat, "bed_ambient_lift"), 0.0)
		and is_equal_approx(ground.get_bed_ambient_lift(), 0.0))
	ground.set_bed_ambient_lift(1.0)
	_assert("bed_ground_restored",
		is_equal_approx(_fparam(mat, "bed_ambient_lift"), 1.0))
	# Contrôles livrés : les autres finitions du terrain ne bougent pas.
	_assert("control_terrain_cavity_bake",
		is_equal_approx(_fparam(mat, "cavity_bake"), 1.0))
	_assert("control_terrain_auto_material",
		is_equal_approx(_fparam(mat, "auto_material_strength"), 1.0))
	_assert("control_terrain_triplanar",
		is_equal_approx(_fparam(mat, "triplanar_lo"), 0.55))
	ground.queue_free()
	await process_frame

# ===========================================================================
# Plan d'eau historique (sans `waterBodies`) : aucune finition ne s'invite
# ===========================================================================

func _test_legacy_plane_unaffected() -> void:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(0.0)
	heights[8 * W + 10] = -0.8
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(W, H, CELL, 0.0, heights, false, 1, 1.0)
	await process_frame
	_assert("legacy_plane_active", water.is_active())
	_assert("legacy_plane_no_bodies", water.get_body_count() == 0)
	# Le plan historique ne porte AUCUNE pointe de ruban ni brume : les deux
	# finitions géométriques restent inactives par construction.
	_assert("legacy_plane_no_mist", water.get_mist_count() == 0
		and water.get_mist_quad_count() == 0)
	_assert("legacy_plane_no_falls", water.get_fall_count() == 0)
	var mat = water.get_water_material()
	_assert("legacy_plane_bed_lift",
		mat is ShaderMaterial
		and is_equal_approx(_fparam(mat, "bed_ambient_lift"), 1.0))
	if mat is ShaderMaterial:
		water.set_bed_ambient_lift(0.0)
		_assert("legacy_plane_bed_off",
			is_equal_approx(_fparam(mat, "bed_ambient_lift"), 0.0))
		water.set_bed_ambient_lift(1.0)
	water.queue_free()
	await process_frame

# ===========================================================================
# Données de validation
# ===========================================================================

## Escalier 4 marches de 4 cases (12 / 8 / 4 / 0) : chaque marche franchie par
## la rivière devient une cascade.
func _staircase_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for z in range(H):
		var step := mini(3, int(float(z) / 4.0))
		var h := 4.0 * float(3 - step)
		for x in range(W):
			heights[z * W + x] = h
	return heights

## Rivière droite nord → sud qui descend les marches (même tracé que le test
## de capture de référence des cascades).
func _staircase_river() -> Dictionary:
	return {
		"id": "riviere", "kind": "river", "width": 1.6, "flow_speed": 0.55,
		"depth": 0.35,
		"path": [[10.0, 12.0, 0.5], [10.0, 12.0, 3.4],
			[10.0, 8.0, 4.6], [10.0, 8.0, 7.4],
			[10.0, 4.0, 8.6], [10.0, 4.0, 11.4],
			[10.0, 0.0, 12.6], [10.0, 0.0, 15.2]],
	}

## Lecture SÛRE d'un paramètre de shader (null si l'uniform n'a pas été posé :
## un `float(null)` lèverait une erreur d'exécution qui masquerait le FAIL).
func _fparam(mat, param_name: String) -> float:
	if mat == null:
		return NAN
	var value = (mat as ShaderMaterial).get_shader_parameter(param_name)
	if value is float or value is int:
		return float(value)
	_assert("param_present_%s" % param_name, false, "uniform absent")
	return NAN

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
