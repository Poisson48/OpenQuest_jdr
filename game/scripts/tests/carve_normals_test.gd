extends SceneTree

## Tests des **invariants géométriques** du maillage Marching Cubes des
## clusters (Voie B) — deux pièges historiques verrouillés ici :
##   • normales d'ombrage vers l'extérieur (jamais de triangles assombris) ;
##   • winding à la convention **Godot** : face avant = sens horaire → le
##     produit vectoriel (b-a)×(c-a) pointe vers la matière, et la normale
##     d'ombrage vers le vide. À l'envers, le shader `cull_disabled` rend des
##     faces arrière à la normale retournée : le cluster entier paraît sombre.
## Autonome : uniquement TerrainCarveField / TerrainCarveChunks.

const FieldScript := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
const ChunksScript := preload("res://scripts/maps/terrain/terrain_carve_chunks.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var W := 12
	var H := 10
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(0.5)
	var carve := {
		"id": "c", "op": "subtract", "shape": "sphere",
		"center": [5.0, -0.5, 4.0], "radius": 1.6, "smooth": 0.3,
	}
	var field = FieldScript.new(heights, W, H, [carve])
	var clusters: Array = ChunksScript.compute_clusters([carve])
	_assert("clusters_count", clusters.size() == 1)
	var white := func(_hv, _n, _i, _j): return Color.WHITE
	var mesh: ArrayMesh = ChunksScript.build_cluster_mesh(
		field, clusters[0], W, H, 2.0, 1.0, white, 2)
	_assert("mesh_surface", mesh.get_surface_count() == 1)
	if mesh.get_surface_count() == 0:
		_finish()
		return
	var arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_assert("mesh_verts", verts.size() > 24, "n=%d" % verts.size())
	_assert("mesh_normals", normals.size() == verts.size())

	var flat_tris := 0
	var flat_norm_up := 0
	var winding_ok := 0
	var down_count := 0
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var centroid := (a + b + c) / 3.0
		var n := ((normals[idx[t]] + normals[idx[t + 1]] + normals[idx[t + 2]]) / 3.0).normalized()
		if n.y < -0.7:
			down_count += 1
		# Zone plate : loin de la sphère creusée (centre 5,-0.5,4 r 1.6).
		if Vector2(centroid.x - 5.0, centroid.z - 4.0).length() > 3.0 \
				and absf(centroid.y - 0.5) < 0.2:
			flat_tris += 1
			if n.y > 0.9:
				flat_norm_up += 1
			var geo := (b - a).cross(c - a)
			if geo.y < 0.0 and n.y > 0.0:
				winding_ok += 1
	_assert("normals_none_down", down_count == 0, "n=%d" % down_count)
	_assert("flat_tris_found", flat_tris > 16, "n=%d" % flat_tris)
	_assert("flat_normals_up", flat_norm_up == flat_tris,
		"up=%d / %d" % [flat_norm_up, flat_tris])
	_assert("godot_winding", winding_ok == flat_tris,
		"ok=%d / %d" % [winding_ok, flat_tris])
	_finish()

func _finish() -> void:
	if _failed:
		print("carve_normals_test:FAIL")
		quit(1)
		return
	print("carve_normals_test:PASS")
	quit(0)

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
