extends SceneTree

## Test de l'occlusion : un mur situé entre la caméra et le personnage devient
## transparent, puis redevient opaque quand il n'est plus sur le segment.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var layer = (load("res://scripts/maps/map_layers/map_meshes_3d.gd") as GDScript).new()
	get_root().add_child(layer)
	await process_frame
	layer.configure([
		{
			"id": "wall1", "x": 5.0, "y": 5.0, "w": 2.0, "h": 0.7,
			"sizeX": 2.0, "sizeY": 1.3, "sizeZ": 0.7,
			"asset": "res://assets/objects3d/buildings/mur.glb",
			"elevation": 0.0, "followTerrain": false,
			"label": "Mur", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
		},
	], 1.0, {})
	await process_frame
	var root = layer._nodes.get("wall1", null)
	_assert("occlusion_wall_built", root != null)
	# Mur entre caméra et personnage.
	layer.set_occlusion_fade(Vector3(5.5, 0.5, 0.0), Vector3(5.5, 0.5, 10.0))
	_assert("occlusion_faded", _max_transparency(root) > 0.2, "alpha=%s" % _max_transparency(root))
	# Mur derrière la caméra.
	layer.set_occlusion_fade(Vector3(5.5, 0.5, 10.0), Vector3(5.5, 0.5, 20.0))
	_assert("occlusion_restored", _max_transparency(root) < 0.05, "alpha=%s" % _max_transparency(root))

	if _failed:
		print("map_occlusion_test:FAIL")
		quit(1)
		return
	print("map_occlusion_test:PASS")
	quit(0)

func _max_transparency(node: Node) -> float:
	var best := 0.0
	if node is GeometryInstance3D:
		best = maxf(best, (node as GeometryInstance3D).transparency)
	for child in node.get_children():
		best = maxf(best, _max_transparency(child))
	return best

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
