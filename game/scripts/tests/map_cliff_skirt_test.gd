extends SceneTree

## Tests de la **jupe de falaise** autour du terrain 2.5D (îlot façon Dofus) :
##   • aucune jupe en mode illustré ;
##   • jupe présente en mode terrain3d (mesh séparé, anneau de 4 bandes, AABB qui
##     descend de `CLIFF_DEPTH_CELLS` cases sous le bord) ;
##   • sommet aligné sur les hauteurs des sommets de bord (carte plate et carte
##     surélevée) ;
##   • reconstruction après changement de relief (`set_terrain_heights`) ;
##   • normales vers l'extérieur, vertex colors de strates, matériau roche
##     éclairé, cast_shadow OFF, nuit teintée ;
##   • le maillage du terrain lui-même reste inchangé (pas de régression).
##
## Autonome : seule la classe MapGround3D est utilisée (aucun autoload).

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")

const W := 8
const H := 8
const CELL := 1.0
const DEPTH := 2.5
const OUTSET := 0.02

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await _test_illustrated()
	await _test_terrain3d_flat()
	await _test_raised_border()
	await _test_rebuild_on_relief_change()
	await _test_night()
	await _test_switch_back_to_illustrated()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		quit(1)
		return
	print("map_cliff_skirt_test:PASS")
	quit(0)

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

func _cliff_arrays(ground) -> Array:
	var mesh: ArrayMesh = ground.get_cliff_mesh()
	if mesh == null or mesh.get_surface_count() == 0:
		return []
	return mesh.surface_get_arrays(0)

func _cliff_aabb(ground) -> AABB:
	var mesh: ArrayMesh = ground.get_cliff_mesh()
	if mesh == null:
		return AABB()
	return mesh.get_aabb()

func _expected_vertex_count() -> int:
	# 4 bandes : (W+3) échantillons horizontaux, (H+3) verticaux, 2 sommets chacun.
	return 2 * ((W + 3) + (H + 3)) * 2

# ===========================================================================
# Mode illustré : aucune jupe
# ===========================================================================

func _test_illustrated() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(), "illustrated", []
	)
	_assert("illustrated_not_cliff", not ground.is_cliff_skirt_active())
	_assert("illustrated_no_cliff_mesh", ground.get_cliff_mesh() == null)
	_assert("illustrated_cliff_instance_hidden",
		ground.get_cliff_mesh_instance() != null
		and not ground.get_cliff_mesh_instance().visible)

# ===========================================================================
# Terrain3d plat : jupe présente, profondeur 2.5 cases, sommet à 0
# ===========================================================================

func _test_terrain3d_flat() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())

	_assert("terrain3d_cliff_active", ground.is_cliff_skirt_active())
	var mesh: ArrayMesh = ground.get_cliff_mesh()
	_assert("terrain3d_cliff_mesh", mesh is ArrayMesh)
	if mesh is ArrayMesh:
		_assert("terrain3d_cliff_surfaces", mesh.get_surface_count() == 1)
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_assert("cliff_vertex_count", verts.size() == _expected_vertex_count(),
			"count=%d attendu=%d" % [verts.size(), _expected_vertex_count()])
		_assert("cliff_normals_count", normals.size() == verts.size())
		_assert("cliff_colors_count", colors.size() == verts.size())

		# AABB : sommet à 0 (carte plate), paroi à -2.5 cases.
		var aabb := mesh.get_aabb()
		_assert("cliff_aabb_depth", is_equal_approx(aabb.position.y, -DEPTH),
			"min_y=%f" % aabb.position.y)
		_assert("cliff_aabb_top", is_equal_approx(aabb.end.y, 0.0),
			"max_y=%f" % aabb.end.y)

		# Normales horizontales et orientées vers l'extérieur (4 directions).
		var normals_seen: Dictionary = {}
		var all_horizontal := true
		for n in normals:
			if absf(n.y) > 0.001:
				all_horizontal = false
			normals_seen["%d,%d,%d" % [roundi(n.x), roundi(n.y), roundi(n.z)]] = true
		_assert("cliff_normals_horizontal", all_horizontal)
		_assert("cliff_normals_four_sides", normals_seen.size() == 4,
			"sides=%d" % normals_seen.size())
		_assert("cliff_outward_south", normals_seen.has("0,0,1"))
		_assert("cliff_outward_north", normals_seen.has("0,0,-1"))
		_assert("cliff_outward_east", normals_seen.has("1,0,0"))
		_assert("cliff_outward_west", normals_seen.has("-1,0,0"))

		# Vertex colors : roche brun-gris (r >= g >= b), opaques, strates variées,
		# sommet plus clair que la base.
		var opaque := true
		var brownish := true
		var distinct: Dictionary = {}
		var top_lum := 0.0
		var top_count := 0
		var bottom_lum := 0.0
		var bottom_count := 0
		for i in range(verts.size()):
			var c := colors[i]
			if not is_equal_approx(c.a, 1.0):
				opaque = false
			if c.r < c.g - 0.001 or c.g < c.b - 0.001:
				brownish = false
			distinct["%0.2f,%0.2f,%0.2f" % [c.r, c.g, c.b]] = true
			if verts[i].y > -0.01:
				top_lum += c.get_luminance()
				top_count += 1
			elif verts[i].y < -DEPTH + 0.01:
				bottom_lum += c.get_luminance()
				bottom_count += 1
		_assert("cliff_colors_opaque", opaque)
		_assert("cliff_colors_brownish", brownish)
		_assert("cliff_colors_strata", distinct.size() > 3,
			"distinct=%d" % distinct.size())
		_assert("cliff_colors_depth_darker",
			top_count > 0 and bottom_count > 0
			and (top_lum / float(top_count)) > (bottom_lum / float(bottom_count)),
			"top=%f bottom=%f" % [
				top_lum / float(maxi(1, top_count)),
				bottom_lum / float(maxi(1, bottom_count)),
			])

		# Sommet aligné sur les hauteurs de bord (carte plate → 0 partout).
		var max_top := -INF
		for v in verts:
			if v.y > -0.01:
				max_top = maxf(max_top, v.y)
		_assert("cliff_flat_top", is_zero_approx(max_top), "max_top=%f" % max_top)

	# Géométrie séparée : le maillage du terrain reste le heightfield standard.
	var terrain_mesh: ArrayMesh = ground._mesh_instance.mesh
	_assert("terrain_mesh_untouched", terrain_mesh != null
		and terrain_mesh.get_surface_count() == 1)
	if terrain_mesh != null:
		var terrain_arrays: Array = terrain_mesh.surface_get_arrays(0)
		var terrain_verts: PackedVector3Array = terrain_arrays[Mesh.ARRAY_VERTEX]
		_assert("terrain_vertex_count", terrain_verts.size() == (W + 1) * (H + 1),
			"count=%d" % terrain_verts.size())

	# Matériau roche éclairé, cull désactivé, pas d'ombre portée.
	var mat = ground.get_cliff_material()
	_assert("cliff_material", mat is StandardMaterial3D)
	if mat is StandardMaterial3D:
		var standard: StandardMaterial3D = mat
		_assert("cliff_lit", standard.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)
		_assert("cliff_roughness", is_equal_approx(standard.roughness, 1.0))
		_assert("cliff_cull_disabled", standard.cull_mode == BaseMaterial3D.CULL_DISABLED)
		_assert("cliff_vertex_colors", standard.vertex_color_use_as_albedo)
		_assert("cliff_day_tint", standard.albedo_color.is_equal_approx(Color.WHITE))
	_assert("cliff_no_shadow",
		ground.get_cliff_mesh_instance().cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_assert("cliff_depth_api", is_equal_approx(ground.get_cliff_depth(), DEPTH))
	_assert("cliff_depth_world", is_equal_approx(ground.get_cliff_depth_world(), DEPTH * CELL))
	_assert("cliff_vertex_count_api", ground.get_cliff_vertex_count() == _expected_vertex_count())

	# Décalage anti z-fighting : les sommets ne sont pas exactement sur le bord.
	var aabb_flat := mesh.get_aabb()
	_assert("cliff_outset",
		is_equal_approx(aabb_flat.position.z, -OUTSET)
		and is_equal_approx(aabb_flat.end.z, float(H) * CELL + OUTSET),
		"z=[%f..%f]" % [aabb_flat.position.z, aabb_flat.end.z])

# ===========================================================================
# Bord surélevé : le sommet de la jupe suit les hauteurs de bord
# ===========================================================================

func _test_raised_border() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights(1.0))

	_assert("raised_cliff_active", ground.is_cliff_skirt_active())
	var arrays := _cliff_arrays(ground)
	_assert("raised_arrays", not arrays.is_empty())
	if not arrays.is_empty():
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var max_y := -INF
		var top_at_one := 0
		for v in verts:
			max_y = maxf(max_y, v.y)
			if is_equal_approx(v.y, 1.0 * CELL):
				top_at_one += 1
		_assert("raised_top_follows_border", is_equal_approx(max_y, 1.0 * CELL),
			"max_y=%f" % max_y)
		_assert("raised_top_vertices", top_at_one > 0,
			"count=%d" % top_at_one)
		# AABB : le point bas reste 2.5 cases sous le niveau bas (0 côté sud).
		var aabb := _cliff_aabb(ground)
		_assert("raised_aabb_bottom", is_equal_approx(aabb.position.y, -DEPTH),
			"min_y=%f" % aabb.position.y)
		_assert("raised_aabb_top", is_equal_approx(aabb.end.y, 1.0 * CELL),
			"max_y=%f" % aabb.end.y)

# ===========================================================================
# Reconstruction après changement de relief
# ===========================================================================

func _test_rebuild_on_relief_change() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())
	var mesh_before: ArrayMesh = ground.get_cliff_mesh()
	var aabb_before := _cliff_aabb(ground)
	_assert("rebuild_initial_active", ground.is_cliff_skirt_active())
	_assert("rebuild_initial_flat", is_zero_approx(aabb_before.end.y))

	# Relief surélevé au nord (2.0) : la jupe est reconstruite et son sommet suit.
	ground.set_terrain_heights(_make_heights(2.0))
	_assert("rebuild_mesh_replaced", ground.get_cliff_mesh() != mesh_before)
	var aabb_after := _cliff_aabb(ground)
	_assert("rebuild_top_follows", is_equal_approx(aabb_after.end.y, 2.0 * CELL),
		"max_y=%f" % aabb_after.end.y)
	# Les autres côtés restent au niveau bas : le point bas est toujours -2.5.
	_assert("rebuild_depth_kept", is_equal_approx(aabb_after.position.y, -DEPTH),
		"min_y=%f" % aabb_after.position.y)

	# Retour au plat : le sommet redescend à 0.
	ground.set_terrain_heights(_make_heights())
	_assert("rebuild_back_flat", is_zero_approx(_cliff_aabb(ground).end.y))
	_assert("rebuild_still_active", ground.is_cliff_skirt_active())

# ===========================================================================
# Nuit : jupe active avec matériau teinté sombre
# ===========================================================================

func _test_night() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights(), true)
	_assert("night_cliff_active", ground.is_cliff_skirt_active())
	var mat = ground.get_cliff_material()
	_assert("night_cliff_material", mat is StandardMaterial3D)
	if mat is StandardMaterial3D:
		var standard: StandardMaterial3D = mat
		_assert("night_cliff_tinted",
			not standard.albedo_color.is_equal_approx(Color.WHITE)
			and standard.albedo_color.get_luminance() < 0.6,
			"tint=%s" % [str(standard.albedo_color)])
		_assert("night_cliff_lit",
			standard.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)

# ===========================================================================
# Retour en mode illustré : la jupe disparaît
# ===========================================================================

func _test_switch_back_to_illustrated() -> void:
	var ground = _make_ground()
	await _wait_frames(2)
	_configure_terrain3d(ground, _make_heights())
	_assert("switch_initial_active", ground.is_cliff_skirt_active())
	ground.configure(
		null, W, H, CELL, true, null, false, [], [], 0.22,
		_make_heights(), "illustrated", []
	)
	_assert("switch_illustrated_inactive", not ground.is_cliff_skirt_active())
	_assert("switch_illustrated_mesh", ground.get_cliff_mesh() == null)
	_assert("switch_illustrated_hidden",
		not ground.get_cliff_mesh_instance().visible)

# ===========================================================================
# Utilitaires
# ===========================================================================

func _wait_frames(n: int = 2) -> void:
	for _i in range(n):
		await process_frame

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		return
	var suffix := "" if detail.is_empty() else " (%s)" % detail
	print("map_cliff_skirt_test:FAIL at ", name, suffix)
	_failed = true
