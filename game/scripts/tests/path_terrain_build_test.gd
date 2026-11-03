extends SceneTree

## Vérifie que la conformation au terrain préserve les couleurs du chemin.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var map := {
		"width": 16, "height": 12,
		"terrainHeights": [],
	}
	var heights: Array = []
	for y in range(12):
		for x in range(16):
			heights.append(sin(float(x) * 0.7) * 0.8 + cos(float(y) * 0.5) * 0.4)
	map["terrainHeights"] = heights
	var layer: Node3D = (load("res://scripts/maps/map_layers/map_meshes_3d.gd") as GDScript).new()
	get_root().add_child(layer)
	layer.configure([{
		"id": "p1", "kind": "mesh", "x": 8.0, "y": 6.0, "w": 8.0, "h": 4.0,
		"asset": "procedural://path",
		"points": [[-3.0, 0.0], [-1.0, 0.4], [1.0, -0.3], [3.0, 0.2]],
		"width": 1.4, "color": "#8a7654", "seed": 3,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"display": {"rotation": 0.0, "scale": 1.0},
	}], 1.0, map)
	await process_frame
	var mi := _find_mesh(layer)
	_assert("path_node", mi != null)
	if mi != null:
		var arrays = mi.mesh.surface_get_arrays(0)
		var colors = arrays[Mesh.ARRAY_COLOR]
		_assert("path_colors_after_terrain", colors is PackedColorArray and (colors as PackedColorArray).size() > 0)
		if colors is PackedColorArray and (colors as PackedColorArray).size() > 0:
			var c: Color = (colors as PackedColorArray)[0]
			_assert("path_not_white", c.r < 0.95 or c.g < 0.95 or c.b < 0.95, "c=%s" % c)
	if _failed:
		print("path_terrain_build_test:FAIL")
		quit(1)
		return
	print("path_terrain_build_test:PASS")
	quit(0)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
