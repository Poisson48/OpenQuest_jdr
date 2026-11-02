extends RefCounted
class_name MarchingCubes

## Marching Cubes — variante à décomposition tétraédrique.
##
## Chaque cube est découpé en 6 tétraèdres. Chaque tétraèdre est polygonisé
## selon le signe de ses 4 coins par rapport à l'iso-level : 0, 1 ou 2 triangles.
## Cette variante évite les ambiguïtés du Marching Cubes classique et ne dépend
## d'aucune table de 256 cas ; elle produit un maillage continu, lissé par les
## normales générées.
##
## Références :
## - https://medium.com/dream-harvesters-team/marching-cubes-as-i-understand-e4687ebe3340
## - https://paulbourke.net/geometry/polygonise/

const CORNERS := [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0),
	Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1),
]

const TETRAHEDRA := [
	[0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6],
	[0, 7, 4, 6], [0, 4, 5, 6], [0, 5, 1, 6],
]

## `field` reçoit un Vector3 et renvoie un scalaire. Le côté « intérieur » est
## `field(p) >= iso`.
static func polygonize(field: Callable, bounds_min: Vector3, bounds_max: Vector3,
		cells: Vector3i, iso: float = 0.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if cells.x <= 0 or cells.y <= 0 or cells.z <= 0:
		return mesh
	var step := (bounds_max - bounds_min) / Vector3(cells)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cz in range(cells.z):
		for cy in range(cells.y):
			for cx in range(cells.x):
				var base := bounds_min + Vector3(float(cx), float(cy), float(cz)) * step
				var positions: Array[Vector3] = []
				var values: Array[float] = []
				for corner in CORNERS:
					var p: Vector3 = base + Vector3(corner.x * step.x, corner.y * step.y, corner.z * step.z)
					positions.append(p)
					values.append(float(field.call(p)))
				for tet in TETRAHEDRA:
					_add_tetrahedron(st, positions, values, tet, iso)
	if st == null:
		return mesh
	st.generate_normals()
	st.commit(mesh)
	if mesh.get_surface_count() == 0:
		return ArrayMesh.new()
	return mesh

static func _add_tetrahedron(st: SurfaceTool, positions: Array[Vector3],
		values: Array[float], tet: Array, iso: float) -> void:
	var inside: Array[int] = []
	var outside: Array[int] = []
	for i in tet:
		if values[i] >= iso:
			inside.append(i)
		else:
			outside.append(i)
	if inside.is_empty() or outside.is_empty():
		return
	if inside.size() == 1:
		var a := inside[0]
		_add_tri(st,
			_edge_point(positions[a], values[a], positions[outside[0]], values[outside[0]], iso),
			_edge_point(positions[a], values[a], positions[outside[1]], values[outside[1]], iso),
			_edge_point(positions[a], values[a], positions[outside[2]], values[outside[2]], iso))
	elif inside.size() == 3:
		var c := outside[0]
		_add_tri(st,
			_edge_point(positions[c], values[c], positions[inside[0]], values[inside[0]], iso),
			_edge_point(positions[c], values[c], positions[inside[1]], values[inside[1]], iso),
			_edge_point(positions[c], values[c], positions[inside[2]], values[inside[2]], iso))
	else:
		var a := inside[0]
		var b := inside[1]
		var c := outside[0]
		var d := outside[1]
		var ac := _edge_point(positions[a], values[a], positions[c], values[c], iso)
		var ad := _edge_point(positions[a], values[a], positions[d], values[d], iso)
		var bc := _edge_point(positions[b], values[b], positions[c], values[c], iso)
		var bd := _edge_point(positions[b], values[b], positions[d], values[d], iso)
		_add_tri(st, ac, ad, bd)
		_add_tri(st, ac, bd, bc)

static func _edge_point(a: Vector3, va: float, b: Vector3, vb: float, iso: float) -> Vector3:
	var denom := vb - va
	if absf(denom) < 0.000001:
		return a
	var t := clampf((iso - va) / denom, 0.0, 1.0)
	return a.lerp(b, t)

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if a.distance_squared_to(b) < 0.0000001 \
			or b.distance_squared_to(c) < 0.0000001 \
			or a.distance_squared_to(c) < 0.0000001:
		return
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
