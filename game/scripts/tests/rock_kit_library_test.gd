extends SceneTree

## Verifie que le kit de cailloux proceduraux et les rochers decoratifs issus de
## Tripo3D sont bien livres dans la bibliotheque 3D et que chaque GLB se charge
## avec un mesh et un materiau.
##
## Deux familles sont livrees :
##   • `caillou_*` : galets proceduraux (kit empilable, sans texture) ;
##   • `bloc_rocheux_*` : les 4 rochers generes par Tripo3D, retravailles par
##     `tools/blender/build_tripo_rocks.py` en **affleurements decoratifs**.
##     Ils ne sont pas empilables (trop plats), n'ont pas de coque d'encre et
##     doivent rester sous 1500 triangles. Les murs de pierre empiles passent
##     toujours par le maillage `procedural://rock_wall` / le kit du projet.

const AssetLibrary := preload("res://scripts/maps/map_asset_library.gd")
const PEBBLES := [
	"caillou_galet_rond", "caillou_galet_ovale", "caillou_eclat_plat", "caillou_gravier",
]
## Rochers Tripo3D retravailles : decor / affleurement, non empilables.
const TRIPO_ROCKS := [
	"bloc_rocheux_socle", "bloc_rocheux_bloc", "bloc_rocheux_coin", "bloc_rocheux_couronne",
]
const TRIANGLE_BUDGET := 1500
## Emprise visee des affleurements : ~1,4 a 2,1 cases de large.
const ROCK_MIN_WIDTH := 1.2
const ROCK_MAX_WIDTH := 2.6
const ROCK_MIN_HEIGHT := 0.3
const ROCK_MAX_HEIGHT := 1.8
const POSITION_TOLERANCE := 0.03

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var listed: Dictionary = {}
	for entry_variant in AssetLibrary.list_object3d_assets():
		var entry: Dictionary = entry_variant
		listed[str(entry.get("path", ""))] = entry
	for name in PEBBLES:
		var path := _asset_path(name)
		var entry: Dictionary = listed.get(path, {})
		_assert("listed_%s" % name, not entry.is_empty())
		if entry.is_empty():
			continue
		_assert("category_%s" % name, str(entry.get("category", "")) == "terrain")
		_assert("has_thumb_%s" % name, not str(entry.get("thumb", "")).is_empty())
		var packed := ResourceLoader.load(path)
		_assert("loads_%s" % name, packed != null)
		if packed == null:
			continue
		var scene := (packed as PackedScene).instantiate()
		var mesh_instance := _first_mesh_instance(scene)
		_assert("mesh_%s" % name, mesh_instance != null and mesh_instance.mesh != null)
		if mesh_instance != null and mesh_instance.mesh != null:
			_assert("surface_%s" % name, mesh_instance.mesh.get_surface_count() > 0)
			_assert("material_%s" % name, mesh_instance.get_active_material(0) != null)
			var box: AABB = mesh_instance.mesh.get_aabb()
			_assert("size_%s" % name, box.size.x > 0.05 and box.size.x < 1.2,
				"width=%.3f" % box.size.x)
			_assert("base_%s" % name, absf(box.position.y) < 0.02, "min_y=%.3f" % box.position.y)
		scene.free()

	for name in TRIPO_ROCKS:
		_test_tripo_rock(name, listed)
	if _failed:
		print("rock_kit_library_test:FAIL")
		quit(1)
		return
	print("rock_kit_library_test:PASS")
	quit(0)

func _test_tripo_rock(name: String, listed: Dictionary) -> void:
	var path := _asset_path(name)
	var entry: Dictionary = listed.get(path, {})
	_assert("listed_%s" % name, not entry.is_empty())
	if entry.is_empty():
		return
	_assert("category_%s" % name, str(entry.get("category", "")) == "terrain")
	_assert("has_thumb_%s" % name, not str(entry.get("thumb", "")).is_empty())
	_assert("thumb_exists_%s" % name, ResourceLoader.exists(str(entry.get("thumb", ""))))

	# Metadonnees du manifeste : ancre au sol, budget, dimensions coherentes.
	var meta: Dictionary = AssetLibrary.get_object3d_meta(path)
	_assert("manifest_%s" % name, not meta.is_empty())
	if not meta.is_empty():
		_assert("manifest_anchor_%s" % name, str(meta.get("anchor", "")) == "base")
		_assert("manifest_outline_%s" % name, not bool(meta.get("outline", true)))
		_assert("manifest_tris_%s" % name, int(meta.get("triangles", 99999)) <= TRIANGLE_BUDGET,
			"tris=%s" % str(meta.get("triangles", -1)))
		var dims: Array = meta.get("dimensions_cells", [])
		_assert("manifest_dims_%s" % name, dims.size() == 3)
		if dims.size() == 3:
			_assert("manifest_width_%s" % name,
				float(dims[0]) >= ROCK_MIN_WIDTH and float(dims[0]) <= ROCK_MAX_WIDTH,
				"width=%.3f" % float(dims[0]))
			_assert("manifest_height_%s" % name,
				float(dims[2]) >= ROCK_MIN_HEIGHT and float(dims[2]) <= ROCK_MAX_HEIGHT,
				"height=%.3f" % float(dims[2]))

	var packed := ResourceLoader.load(path)
	_assert("loads_%s" % name, packed != null)
	if packed == null:
		return
	var scene := (packed as PackedScene).instantiate()
	var mesh_instance := _first_mesh_instance(scene)
	_assert("mesh_%s" % name, mesh_instance != null and mesh_instance.mesh != null)
	if mesh_instance != null and mesh_instance.mesh != null:
		_test_tripo_mesh(name, mesh_instance)
	# Les rochers Tripo ne sont pas des rochers empiles du kit : pas de contour
	# encre dans le GLB (il doublerait le budget de triangles).
	_assert("no_outline_%s" % name, _count_outline_nodes(scene) == 0)
	scene.free()

func _test_tripo_mesh(name: String, mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	_assert("surface_%s" % name, mesh.get_surface_count() > 0)
	_assert("material_%s" % name, mesh_instance.get_active_material(0) != null)
	var triangles := mesh.get_faces().size() / 3
	_assert("budget_%s" % name, triangles > 0 and triangles <= TRIANGLE_BUDGET,
		"tris=%d" % triangles)
	# COLOR_0 du GLB : AO + mottling + mousse. Godot l'importe dans le mesh ;
	# le moteur l'active comme albedo au rendu (map_meshes_3d.gd), le materiau
	# importé garde donc son flag par défaut. On verifie les donnees elles-memes.
	var arrays: Array = mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_assert("vertex_colors_%s" % name, colors.size() > 0 and colors.size() == positions.size())
	if colors.size() > 0:
		var min_luminance := 2.0
		var mossy := 0
		for color in colors:
			min_luminance = minf(min_luminance, color.get_luminance())
			if color.g > color.r * 1.03 and color.g > color.b * 1.03:
				mossy += 1
		_assert("ao_vertex_colors_%s" % name, min_luminance < 0.9,
			"min_lum=%.3f" % min_luminance)
		_assert("moss_vertex_colors_%s" % name, mossy > 0, "mossy=%d" % mossy)
	var material := mesh_instance.get_active_material(0)
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		_assert("albedo_texture_%s" % name, standard.albedo_texture != null)
		_assert("matte_%s" % name, standard.roughness >= 0.85 and not standard.transparency)
	var box: AABB = mesh.get_aabb()
	_assert("size_%s" % name,
		box.size.x >= ROCK_MIN_WIDTH and box.size.x <= ROCK_MAX_WIDTH,
		"width=%.3f" % box.size.x)
	_assert("height_%s" % name,
		box.size.y >= ROCK_MIN_HEIGHT and box.size.y <= ROCK_MAX_HEIGHT,
		"height=%.3f" % box.size.y)
	# Origine au centre de la base : min Y au sol, X/Z centres.
	_assert("base_%s" % name, absf(box.position.y) < POSITION_TOLERANCE,
		"min_y=%.3f" % box.position.y)
	_assert("centered_x_%s" % name,
		absf(box.position.x + box.size.x * 0.5) < POSITION_TOLERANCE,
		"center_x=%.3f" % (box.position.x + box.size.x * 0.5))
	_assert("centered_z_%s" % name,
		absf(box.position.z + box.size.z * 0.5) < POSITION_TOLERANCE,
		"center_z=%.3f" % (box.position.z + box.size.z * 0.5))

func _asset_path(name: String) -> String:
	return "res://assets/objects3d/terrain/%s.glb" % name

func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null

func _count_outline_nodes(node: Node) -> int:
	var total := 1 if node.name.ends_with("_outline") else 0
	for child in node.get_children():
		total += _count_outline_nodes(child)
	return total

func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [label, detail])
