extends SceneTree

## Contrat du mur de pierres sèches procédural (`procedural://rock_wall`) :
## géométrie fermée, assises visibles (joints sombres), hauteur stable et
## graine déterministe. C'est ce maillage qui remplace l'empilement de GLB.

const RockWallMesh := preload("res://scripts/maps/construction/procedural_rock_wall_mesh.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var points: Array = [[-3.0, 0.0], [3.0, 0.0]]
	var mesh_a: ArrayMesh = RockWallMesh.build(points, 1.05, 0.72, 42)
	var mesh_b: ArrayMesh = RockWallMesh.build(points, 1.05, 0.72, 42)
	_assert("mesh_created", mesh_a != null and mesh_a.get_surface_count() == 1)
	if mesh_a == null or mesh_a.get_surface_count() == 0:
		_finish()
		return
	var arrays_a: Array = mesh_a.surface_get_arrays(0)
	var arrays_b: Array = mesh_b.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays_a[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays_a[Mesh.ARRAY_COLOR]
	_assert("has_vertices", verts.size() > 200, "verts=%d" % verts.size())
	_assert("has_colors", colors.size() == verts.size(), "colors=%d" % colors.size())
	_assert("deterministic", (arrays_b[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == verts.size())

	# Volume : le mur occupe bien sa hauteur et son épaisseur.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	_assert("height", absf(hi.y - 1.05) < 0.08, "h=%.3f" % (hi.y - lo.y))
	_assert("base_at_floor", absf(lo.y) < 0.02, "min_y=%.3f" % lo.y)
	_assert("length", hi.x - lo.x > 5.6 and hi.x - lo.x < 6.6, "len=%.2f" % (hi.x - lo.x))
	_assert("thickness", hi.z - lo.z > 0.6 and hi.z - lo.z < 0.95, "thick=%.2f" % (hi.z - lo.z))

	# Contraste maçonnerie : il existe des joints très sombres ET des pierres
	# claires — sans ça le mur se lit comme un bloc uni (le défaut précédent).
	var darkest := 1.0
	var lightest := 0.0
	for c in colors:
		var lum := c.get_luminance()
		darkest = minf(darkest, lum)
		lightest = maxf(lightest, lum)
	_assert("has_dark_joints", darkest < 0.12, "darkest=%.3f" % darkest)
	_assert("has_lit_stones", lightest > 0.24, "lightest=%.3f" % lightest)
	_assert("stones_darker_than_pavement", lightest < 0.62, "lightest=%.3f" % lightest)

	# Un mur courbe (polyligne) doit aussi se construire.
	var curved: ArrayMesh = RockWallMesh.build(
		[[-2.0, 0.0], [0.0, -0.8], [2.0, 0.0]], 1.2, 0.7, 7)
	_assert("curved_mesh", curved != null and curved.get_surface_count() == 1)
	# Points dégénérés : pas de crash, pas de surface inutile.
	_assert("single_point_safe", RockWallMesh.build([[0.0, 0.0]], 1.0, 0.7, 1).get_surface_count() == 0)
	_finish()

func _finish() -> void:
	if _failed:
		print("rock_wall_mesh_test:FAIL")
		quit(1)
		return
	print("rock_wall_mesh_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
