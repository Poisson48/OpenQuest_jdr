extends RefCounted
class_name ProceduralRockMesh

## Rocher procédural via Marching Cubes : un champ SDF bruité est polygonisé en
## un maillage continu, puis posé sur le terrain par MapMeshes3D.
##
## Le bruit donne une silhouette irrégulière ; le bas du rocher est aplati par
## la forme du champ pour éviter une boule flottante.

const MarchingCubesScript := preload("res://scripts/maps/construction/marching_cubes.gd")

static func build(seed: int = 1, detail: int = 14) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.7
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var field := func(p: Vector3) -> float:
		var q := p
		# Demi-ellipsoïde aplati : base large, sommet irrégulier.
		var r := sqrt(q.x * q.x + q.z * q.z)
		var dome := 1.0 - sqrt(r * r * 1.35 + q.y * q.y * 2.2)
		var n := noise.get_noise_3dv(p * 2.2)
		return dome + n * 0.32 + q.y * 0.18
	var cells := maxi(8, detail)
	var mesh: ArrayMesh = MarchingCubesScript.polygonize(
		field,
		Vector3(-1.15, -0.15, -1.15),
		Vector3(1.15, 1.05, 1.15),
		Vector3i(cells, maxi(5, cells / 2), cells),
		0.0
	)
	if mesh.get_surface_count() == 0:
		return mesh
	# Le maillage est centré autour de l'origine : on le remonte pour que sa
	# base repose sur y=0 (la racine est ensuite posée à la hauteur du terrain).
	var aabb := mesh.get_aabb()
	if aabb.position.y < 0.0:
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var shift := -aabb.position.y
		for i in range(verts.size()):
			verts[i].y += shift
		arrays[Mesh.ARRAY_VERTEX] = verts
		var shifted := ArrayMesh.new()
		shifted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return shifted
	return mesh
