extends SceneTree

## Tests du pont procédural : construction de base et cas dégénérés.

const BridgeScript = preload("res://scripts/maps/construction/procedural_bridge_mesh.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_basic_build()
	_test_zero_length()

	if _failed:
		quit(1)
		return
	print("procedural_bridge_mesh_test:PASS")
	quit(0)

# ===========================================================================

## Pont de 10 unités, montant de y=1 à y=2 : le mesh doit être non vide,
## avec au moins une surface et des sommets.
func _test_basic_build() -> void:
	var mesh: ArrayMesh = BridgeScript.build({
		"start": Vector3(0, 1, 0),
		"end": Vector3(10, 2, 0),
		"width": 2.0,
		"seed": 7,
		"ground_y": 0.0,
	})
	_assert("bridge_mesh_non_null", mesh != null)
	if mesh == null:
		return
	_assert("bridge_surface_count", mesh.get_surface_count() >= 1)
	if mesh.get_surface_count() < 1:
		return
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_assert("bridge_vertex_count", vertices.size() > 0)

## start == end : longueur nulle -> ArrayMesh vide, sans crash.
func _test_zero_length() -> void:
	var mesh: ArrayMesh = BridgeScript.build({
		"start": Vector3(3, 1, 3),
		"end": Vector3(3, 1, 3),
		"width": 2.0,
		"seed": 7,
		"ground_y": 0.0,
	})
	_assert("bridge_zero_length_non_null", mesh != null)
	if mesh == null:
		return
	_assert("bridge_zero_length_empty", mesh.get_surface_count() == 0)

func _assert(test_name: String, ok: bool) -> void:
	if ok:
		return
	_failed = true
	print("FAIL " + test_name)
