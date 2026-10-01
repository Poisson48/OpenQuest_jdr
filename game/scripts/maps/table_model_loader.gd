extends RefCounted
class_name TableModelLoader

## Chargeur OBJ minimal pour le mobilier de table (modèles Meshy AI) :
## parse `v` / `vt` / `vn` / `f` (triangles ou quads) en ArrayMesh non indexé.
## Lecture brute du fichier — aucune dépendance au cache d'import Godot,
## comme `MapData._load_rgba_image` pour les PNG.
## Résultat mis en cache par chemin (une table = un parse au boot).
##
## NB perf/correctitude GDScript : les `Packed*Array` se copient au passage de
## paramètre — on travaille sur des `Array` (référence) puis on convertit.

static var _cache: Dictionary = {}

static func load_obj(path: String) -> ArrayMesh:
	if _cache.has(path):
		return _cache[path]
	var abs_path := _resolve(path)
	if abs_path.is_empty():
		return null
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return null
	var st := {
		"v": [], "vt": [], "vn": [],
		"ov": [], "ouv": [], "on": [],
	}
	# NB : `eof_reached` est une méthode en Godot 4 (pas une propriété).
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("v "):
			(st["v"] as Array).append(_vec3(line.substr(2)))
		elif line.begins_with("vt "):
			(st["vt"] as Array).append(_uv(line.substr(3)))
		elif line.begins_with("vn "):
			(st["vn"] as Array).append(_vec3(line.substr(3)))
		elif line.begins_with("f "):
			_add_face(line.substr(2), st)
	file.close()
	var out_v: Array = st["ov"]
	if out_v.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(st["ov"])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(st["ouv"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(st["on"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[path] = mesh
	return mesh

## AABB local du maillage (pour mise à l'échelle / pose sur le sol).
static func mesh_aabb(mesh: ArrayMesh) -> AABB:
	if mesh == null or mesh.get_surface_count() < 1:
		return AABB()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var aabb := AABB()
	var first := true
	for v in verts:
		if first:
			aabb = AABB(v, Vector3.ZERO)
			first = false
		else:
			aabb = aabb.expand(v)
	return aabb

## Texture diffuse (PNG lu brut, comme les fonds de carte).
static func load_texture(path: String) -> Texture2D:
	var abs_path := _resolve(path)
	if abs_path.is_empty():
		return null
	var img := Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

static func _resolve(path: String) -> String:
	var raw := path.strip_edges()
	if raw.is_empty():
		return ""
	if raw.begins_with("res://") or raw.begins_with("user://"):
		var abs_path := ProjectSettings.globalize_path(raw)
		if FileAccess.file_exists(abs_path):
			return abs_path
		# Dernier recours : fichier packagé lu via FileAccess.
		if FileAccess.file_exists(raw):
			return raw
		return ""
	return raw if FileAccess.file_exists(raw) else ""

static func _vec3(values: String) -> Vector3:
	var parts := values.split_floats(" ", false)
	return Vector3(parts[0], parts[1], parts[2])

## OBJ : V bas en haut, Godot : V haut en bas → on retourne V.
static func _uv(values: String) -> Vector2:
	var parts := values.split_floats(" ", false)
	return Vector2(parts[0], 1.0 - parts[1])

## Faces triangles ou quads (triangulation éventail : 0, i, i+1).
static func _add_face(body: String, st: Dictionary) -> void:
	var corners := body.split(" ", false)
	if corners.size() < 3:
		return
	for i in range(1, corners.size() - 1):
		_emit_corner(corners[0], st)
		_emit_corner(corners[i], st)
		_emit_corner(corners[i + 1], st)

static func _emit_corner(token: String, st: Dictionary) -> void:
	var verts: Array = st["v"]
	var uvs: Array = st["vt"]
	var normals: Array = st["vn"]
	var idx := token.split("/")
	var vi := _obj_index(idx[0], verts.size())
	(st["ov"] as Array).append(verts[vi] if vi >= 0 else Vector3.ZERO)
	if idx.size() > 1 and not idx[1].is_empty():
		var ti := _obj_index(idx[1], uvs.size())
		(st["ouv"] as Array).append(uvs[ti] if ti >= 0 else Vector2.ZERO)
	else:
		(st["ouv"] as Array).append(Vector2.ZERO)
	if idx.size() > 2 and not idx[2].is_empty():
		var ni := _obj_index(idx[2], normals.size())
		(st["on"] as Array).append(normals[ni] if ni >= 0 else Vector3.UP)
	else:
		(st["on"] as Array).append(Vector3.UP)

## Index OBJ 1-based (négatif = relatif à la fin) → index 0-based, -1 si invalide.
static func _obj_index(text: String, count: int) -> int:
	var n := text.to_int()
	if n > 0:
		return n - 1 if n <= count else -1
	if n < 0:
		var rel := count + n
		return rel if rel >= 0 else -1
	return -1
