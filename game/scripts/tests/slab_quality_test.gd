extends SceneTree

## SOCLE DE DIORAMA (finitions « qualité CS2 », task-5) — test headless.
##
## Vérifie que le socle remplace la jupe historique de façon A/B RÉVERSIBLE,
## que sa géométrie est BORNÉE et sans régression, et que le fond de plateau
## (backdrop) gagne son dégradé doux + halo de contact :
##
##  1. flag maître `slab_finitions` (1 = nouveau socle, 0 = rendu EXACT de la
##     jupe legacy) + uniform `slab_strata` (option strates) ;
##  2. géométrie : une surface, sommets = formule BORNÉE, normales/colors
##     cohérents, arête qui suit les hauteurs de bord, pied qui rejoint le fond,
##     masques herbe/AO/terre présents ;
##  3. matériau ÉCLAIRÉ (spatial, pas unshaded), palette + teinte de nuit,
##     A/B des uniforms ;
##  4. robustesse : carte plate, relief surélevé, creusements (carves),
##     reconstruction, mode illustré, nuit ;
##  5. fond de plateau : matériau ShaderMaterial, `slab_soften` + `map_half_frac`
##     + halo de contact, A/B 0/1, rendu historique exact quand 0.
##
## PASS = `slab_quality_test:PASS`.

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const BackdropScript := preload("res://scripts/maps/map_layers/map_backdrop_3d.gd")

const W := 8
const H := 8
const CELL := 1.0
const DEPTH := 2.5
const OUTSET := 0.02
const LIP := 0.45

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _test_flat_slab()
	await _test_slab_ab_flag()
	await _test_raised_border()
	await _test_rebuild_and_carves()
	await _test_illustrated()
	await _test_night()
	await _test_backdrop()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)
	if _failed:
		print("slab_quality_test:FAIL")
		quit(1)
		return
	print("slab_quality_test:PASS")
	quit(0)

# ===========================================================================
# Socle plat : géométrie, matériau, API
# ===========================================================================

func _test_flat_slab() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())
	_assert("flat_cliff_legacy_active", ground.is_cliff_skirt_active())
	_assert("flat_slab_active", ground.is_slab_active())
	_assert("flat_slab_flag", ground.is_slab_finitions()
		and is_equal_approx(ground.get_slab_finitions(), 1.0))
	# A/B : le socle remplace le RENDU de la jupe, mais la jupe legacy reste
	# construite (API/tests + retour exact) et simplement masquée.
	_assert("flat_legacy_mesh_intact",
		ground.get_cliff_mesh() != null
		and ground.get_cliff_vertex_count() == _legacy_vertex_count())
	_assert("flat_legacy_hidden", not ground.get_cliff_mesh_instance().visible)
	_assert("flat_slab_instance_visible",
		ground.get_slab_instance() != null and ground.get_slab_instance().visible)

	var mesh: ArrayMesh = ground.get_slab_mesh()
	_assert("flat_slab_mesh", mesh is ArrayMesh)
	if not (mesh is ArrayMesh):
		return
	_assert("flat_slab_surfaces", mesh.get_surface_count() == 1,
		"surfaces=%d" % mesh.get_surface_count())
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Géométrie BORNÉE : un profil de `get_slab_row_count()` lignes par côté,
	# échantillons de bord + 3 (débordement de coin) — même formule que la
	# jupe, aucune croissance non maîtrisée.
	var expected: int = (2 * W + 2 * H + 12) * int(ground.get_slab_row_count())
	print("  [socle] sommets=%d (attendu=%d, %d rangées)"
		% [verts.size(), expected, ground.get_slab_row_count()])
	_assert("flat_slab_vertex_count", verts.size() == expected,
		"count=%d attendu=%d" % [verts.size(), expected])
	_assert("flat_slab_vertex_bound", verts.size() <= 4096,
		"count=%d" % verts.size())
	_assert("flat_slab_normals_count", normals.size() == verts.size())
	_assert("flat_slab_colors_count", colors.size() == verts.size())
	_assert("flat_slab_indices", indices.size() % 3 == 0 and indices.size() > 0)

	# Sommets valides + AABB : sommet = hauteurs de bord (0), et le pied rejoint
	# le FOND du décor (sous l'ancienne profondeur de jupe) → contact visuel.
	var aabb := mesh.get_aabb()
	_assert("flat_slab_top", is_zero_approx(aabb.end.y), "max_y=%f" % aabb.end.y)
	var expected_bottom := -DEPTH - GroundScript.SLAB_BASE_DROP_CELLS * CELL
	_assert("flat_slab_bottom_reaches_ground",
		is_equal_approx(aabb.position.y, expected_bottom)
		and aabb.position.y < -DEPTH - 0.4,
		"min_y=%f attendu=%f" % [aabb.position.y, expected_bottom])
	var valid := true
	var unit_normals := true
	for i in range(verts.size()):
		var v := verts[i]
		if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
			valid = false
		var n := normals[i]
		if absf(n.length() - 1.0) > 0.01:
			unit_normals = false
	_assert("flat_slab_vertices_finite", valid)
	_assert("flat_slab_normals_unit", unit_normals)

	# Normales : débord vers le HAUT (arête) et paroi horizontale (4 directions
	# possibles) — le profil arrondi produit les deux familles.
	var up_normals := 0
	var wall_normals := 0
	var sides: Dictionary = {}
	for i in range(verts.size()):
		var n := normals[i]
		if n.y > 0.55:
			up_normals += 1
		elif absf(n.y) <= 0.35:
			wall_normals += 1
		if absf(n.y) <= 0.35:
			sides["%d,%d" % [roundi(n.x), roundi(n.z)]] = true
	_assert("flat_slab_lip_normals", up_normals > 0, "n=%d" % up_normals)
	_assert("flat_slab_wall_normals", wall_normals > 0, "n=%d" % wall_normals)

	# Masques de sommet : herbe (R) sur l'arête, terre/contact (A) au pied,
	# AO (B) entre 0 et 1 avec des valeurs franchement ombrées.
	var has_grass := false
	var has_dirt := false
	var has_shadow := false
	var ao_in_range := true
	for c in colors:
		if c.r > 0.9:
			has_grass = true
		if c.a > 0.9:
			has_dirt = true
		if c.b < 0.45:
			has_shadow = true
		if c.b < -0.001 or c.b > 1.001:
			ao_in_range = false
	_assert("flat_slab_grass_mask", has_grass)
	_assert("flat_slab_dirt_mask", has_dirt)
	_assert("flat_slab_ao_mask", has_shadow and ao_in_range)

	# Matériau ÉCLAIRÉ (le preset qualité CS2 doit pouvoir moduler le socle).
	var mat: ShaderMaterial = ground.get_slab_material()
	_assert("flat_slab_material", mat is ShaderMaterial and mat.shader != null)
	if mat != null and mat.shader != null:
		var code := mat.shader.code
		_assert("slab_shader_spatial", code.contains("shader_type spatial"))
		_assert("slab_shader_lit", not code.contains("unshaded"))
		_assert("slab_shader_strata", code.contains("slab_strata"))
		_assert("slab_shader_ao", code.contains("slab_ao_strength"))
		_assert("slab_shader_contact", code.contains("slab_contact_strength"))
	_assert("flat_slab_strata_uniform",
		_param(mat, "slab_strata") > 0.99)
	_assert("flat_slab_cell_uniform",
		is_equal_approx(_param(mat, "slab_cell_size"), CELL))
	_assert("flat_slab_night_day",
		(mat.get_shader_parameter("night_tint") as Color).is_equal_approx(Color.WHITE))
	_assert("flat_slab_no_shadow",
		ground.get_slab_instance().cast_shadow
			== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	# A/B de l'option strates.
	ground.set_slab_strata(0.0)
	_assert("strata_off", is_equal_approx(_param(mat, "slab_strata"), 0.0)
		and is_equal_approx(ground.get_slab_strata(), 0.0))
	ground.set_slab_strata(1.0)
	_assert("strata_restored", is_equal_approx(_param(mat, "slab_strata"), 1.0))

# ===========================================================================
# Flag maître A/B : retour EXACT à la jupe historique
# ===========================================================================

func _test_slab_ab_flag() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())
	_assert("ab_initial_slab", ground.is_slab_active())
	var legacy_mesh: ArrayMesh = ground.get_cliff_mesh()
	ground.set_slab_finitions(false)
	_assert("ab_off_flag", not ground.is_slab_finitions()
		and is_zero_approx(ground.get_slab_finitions()))
	_assert("ab_off_slab_hidden", not ground.is_slab_active()
		and ground.get_slab_mesh() == null
		and not ground.get_slab_instance().visible)
	# Rendu EXACT précédent : la jupe legacy est réaffichée, mesh inchangé.
	_assert("ab_off_legacy_visible", ground.get_cliff_mesh_instance().visible)
	_assert("ab_off_legacy_same_mesh", ground.get_cliff_mesh() == legacy_mesh)
	ground.set_slab_finitions(true)
	_assert("ab_on_slab", ground.is_slab_active()
		and ground.get_slab_mesh() != null
		and ground.get_slab_instance().visible)
	_assert("ab_on_legacy_hidden", not ground.get_cliff_mesh_instance().visible)
	_assert("ab_on_flag", ground.is_slab_finitions())

# ===========================================================================
# Bord surélevé : l'arête suit les hauteurs de bord
# ===========================================================================

func _test_raised_border() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights(1.0))
	var mesh: ArrayMesh = ground.get_slab_mesh()
	_assert("raised_slab_mesh", mesh != null)
	if mesh == null:
		return
	var aabb := mesh.get_aabb()
	_assert("raised_slab_top_follows_border",
		is_equal_approx(aabb.end.y, 1.0 * CELL), "max_y=%f" % aabb.end.y)
	_assert("raised_slab_bottom",
		is_equal_approx(aabb.position.y, -DEPTH
			- GroundScript.SLAB_BASE_DROP_CELLS * CELL),
		"min_y=%f" % aabb.position.y)

# ===========================================================================
# Reconstruction (relief) + creusements (carves) : pas de crash, socle à jour
# ===========================================================================

func _test_rebuild_and_carves() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())
	var before: ArrayMesh = ground.get_slab_mesh()
	ground.set_terrain_heights(_make_heights(2.0))
	var after: ArrayMesh = ground.get_slab_mesh()
	_assert("rebuild_mesh_replaced", after != null and after != before)
	_assert("rebuild_top_follows", after != null
		and is_equal_approx(after.get_aabb().end.y, 2.0 * CELL),
		"max_y=%f" % (after.get_aabb().end.y if after != null else NAN))
	_assert("rebuild_still_active", ground.is_slab_active())
	# Strata coupées avant reconstruction : le choix est conservé.
	ground.set_slab_strata(0.0)
	ground.set_terrain_heights(_make_heights())
	_assert("rebuild_keeps_option",
		is_equal_approx(_param(ground.get_slab_material(), "slab_strata"), 0.0))
	ground.set_slab_strata(1.0)

	# Creusements : la jupe/socle sont bâtis sur les hauteurs de bord, donc
	# stables ; le test vérifie surtout qu'il n'y a NI erreur NI socle vide.
	var carve := {
		"id": "carve_slab", "op": "subtract", "shape": "sphere",
		"center": Vector3(4.0, 0.0, 4.0), "radius": 1.2, "smooth": 0.4,
	}
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(), "terrain3d", [], 1, [carve], {}
	)
	await _wait_frames(2)
	_assert("carves_slab_active", ground.is_slab_active())
	_assert("carves_slab_bounded",
		ground.get_slab_vertex_count() > 0 and ground.get_slab_vertex_count() <= 4096,
		"count=%d" % ground.get_slab_vertex_count())

# ===========================================================================
# Mode illustré : ni jupe ni socle
# ===========================================================================

func _test_illustrated() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(), "illustrated", []
	)
	_assert("illustrated_no_slab", not ground.is_slab_active()
		and ground.get_slab_mesh() == null
		and not ground.get_slab_instance().visible)
	_assert("illustrated_no_legacy_cliff",
		not ground.is_cliff_skirt_active() and ground.get_cliff_mesh() == null)

# ===========================================================================
# Nuit : socle actif, matériau teinté froid (comme le terrain/jupe)
# ===========================================================================

func _test_night() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights(), true)
	_assert("night_slab_active", ground.is_slab_active())
	var mat: ShaderMaterial = ground.get_slab_material()
	_assert("night_slab_material", mat is ShaderMaterial)
	if mat != null:
		var tint = mat.get_shader_parameter("night_tint")
		_assert("night_slab_tinted",
			tint is Color and not (tint as Color).is_equal_approx(Color.WHITE)
			and (tint as Color).get_luminance() < 0.6,
			"tint=%s" % str(tint))

# ===========================================================================
# Fond de plateau : dégradé doux + halo de contact (A/B `slab_soften`)
# ===========================================================================

func _test_backdrop() -> void:
	var layer = BackdropScript.new()
	get_root().add_child(layer)
	_nodes.append(layer)
	await _wait_frames(2)
	layer.configure(W, H, CELL, false)
	_assert("backdrop_active", layer.is_active())
	var mat: ShaderMaterial = layer.get_material()
	_assert("backdrop_material", mat is ShaderMaterial and mat.shader != null)
	if mat == null or mat.shader == null:
		return
	var code := mat.shader.code
	_assert("backdrop_no_texture",
		not code.contains("sampler2D") and not code.contains("texture("))
	_assert("backdrop_unshaded", code.contains("unshaded"))
	# FINITION : uniformes présents et valeurs par défaut.
	_assert("backdrop_soften_default",
		is_equal_approx(_param(mat, "slab_soften"), 1.0))
	var half_frac = mat.get_shader_parameter("map_half_frac")
	var expected_half := Vector2(
		float(W) * CELL / (2.0 * float(W) * CELL * BackdropScript.SIZE_FACTOR),
		float(H) * CELL / (2.0 * float(W) * CELL * BackdropScript.SIZE_FACTOR))
	_assert("backdrop_map_half_frac",
		half_frac is Vector2 and (half_frac as Vector2).is_equal_approx(expected_half),
		"frac=%s attendu=%s" % [str(half_frac), str(expected_half)])
	_assert("backdrop_contact_uniforms",
		mat.get_shader_parameter("contact_color") is Color
		and _param(mat, "contact_strength") > 0.0)
	_assert("backdrop_priority", mat.render_priority <= -50)
	# A/B : 0 = rendu EXACTEMENT précédent (ancien dégradé), 1 = finition.
	layer.set_slab_soften(0.0)
	_assert("backdrop_soften_off",
		is_equal_approx(_param(mat, "slab_soften"), 0.0)
		and is_zero_approx(layer.get_slab_soften()))
	layer.set_slab_soften(1.0)
	_assert("backdrop_soften_restored",
		is_equal_approx(_param(mat, "slab_soften"), 1.0))
	# Nuit : teinte froide toujours appliquée.
	layer.set_night_mode(true)
	var tint = mat.get_shader_parameter("night_tint")
	_assert("backdrop_night_tint",
		tint is Color and (tint as Color).get_luminance() < 0.6)

# ===========================================================================
# Données de test
# ===========================================================================

func _make_heights(raised_north: float = 0.0) -> Array:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(0.0)
	if raised_north != 0.0:
		for x in range(W):
			heights[0 * W + x] = raised_north
	return heights

func _make_ground() -> Node3D:
	var ground = GroundScript.new()
	get_root().add_child(ground)
	_nodes.append(ground)
	return ground

func _configure_terrain3d(ground, heights: Array, night_mode: bool = false) -> void:
	ground.configure(
		null, W, H, CELL, true, null, night_mode, [], [], 0.22,
		heights, "terrain3d", []
	)

## Nombre de sommets de la jupe legacy (formule du test historique) : la
## finition socle ne doit PAS changer cette géométrie (non-régression).
func _legacy_vertex_count() -> int:
	var wall := 2 * ((W + 3) + (H + 3)) * 2
	var lip := 2 * ((W + 1) + (H + 1)) * 2
	return wall + lip

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
