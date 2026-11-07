extends SceneTree

## Test de non-régression : la découpe des quads heightfield (cellules rendues
## par un cluster MC) fonctionne à **tous** les niveaux de détail, pas seulement
## au détail 1 — les captures de terrain creusé utilisent terrainDetail=2.

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")
const ChunksScript := preload("res://scripts/maps/terrain/terrain_carve_chunks.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var W := 12
	var H := 10
	for detail in [1, 2, 3]:
		var heights: Array = []
		heights.resize(W * H)
		heights.fill(0.3)
		var carve := {
			"id": "c", "op": "subtract", "shape": "sphere",
			"center": [5.0, -0.5, 4.0], "radius": 1.6, "smooth": 0.3,
		}
		var ground = GroundScript.new()
		get_root().add_child(ground)
		ground.configure(null, W, H, 1.0, true, null, false, [], [], 0.22,
			heights, "terrain3d", [], detail, [carve])
		var mesh = ground._mesh_instance.mesh
		var idx: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		var clusters: Array = ChunksScript.compute_clusters([carve])
		var cut_cells: int = clusters[0]["rect"].size.x * clusters[0]["rect"].size.y
		var expected: int = (W * H - cut_cells) * 6 * detail * detail
		if idx.size() != expected:
			_failed = true
			print("  [FAIL] cut_detail_%d indices=%d attendu=%d" % [detail, idx.size(), expected])
		ground.queue_free()
	await process_frame
	if _failed:
		print("carve_cut_detail_test:FAIL")
		quit(1)
		return
	print("carve_cut_detail_test:PASS")
	quit(0)
