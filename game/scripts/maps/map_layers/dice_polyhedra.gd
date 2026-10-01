extends RefCounted
class_name DicePolyhedra

## Solides des dés (d4, d6, d8, d10, d12, d20, d100) : sommets canoniques +
## faces par **enveloppe convexe** (toutes les faces planes, même les kites du
## d10). Le d100 est un vrai dé à 100 faces (trapézoèdre 50-gonal, 1-100).
## Les triangles coplanaires sont fusionnés en une « face de valeur ».
##
## Numérotation de dés réels : les faces opposées somment à N+1
## (d10 chiffres 0-9 : les opposés somment à 9).

static var _cache: Dictionary = {}

const PHI := 1.61803398875

## Compat : chaque type de dé a désormais son propre solide.
static func shape_sides(sides: int) -> int:
	return sides

## Sommets normalisés (rayon max = 0.5 → tient dans un cube de côté 1).
static func vertices(sides: int) -> PackedVector3Array:
	var raw: Array = []
	match shape_sides(sides):
		4:
			raw = [
				Vector3(1, 1, 1), Vector3(1, -1, -1),
				Vector3(-1, 1, -1), Vector3(-1, -1, 1),
			]
		6:
			for x: float in [-1.0, 1.0]:
				for y: float in [-1.0, 1.0]:
					for z: float in [-1.0, 1.0]:
						raw.append(Vector3(x, y, z))
		8:
			raw = [
				Vector3(1, 0, 0), Vector3(-1, 0, 0),
				Vector3(0, 1, 0), Vector3(0, -1, 0),
				Vector3(0, 0, 1), Vector3(0, 0, -1),
			]
		10:
			# Trapézoèdre pentagonal (dé à 10 faces) : 2 apex + 2 couronnes
			# décalées — les 10 kites sont construits explicitement.
			raw = _trapezohedron_verts(5)
		100:
			# Vrai d100 (type Zocchihedron) : bille à 100 faces. 52 points de
			# Fibonacci en position générale → enveloppe convexe de
			# 2V-4 = 100 faces triangulaires, quasi-uniformes sur la sphère.
			raw = _fibonacci_sphere(52)
		12:
			# Dodécaèdre : cube + deux "rubans" d'or.
			for x: float in [-1.0, 1.0]:
				for y: float in [-1.0, 1.0]:
					for z: float in [-1.0, 1.0]:
						raw.append(Vector3(x, y, z))
			var inv_p := 1.0 / PHI
			for s1: float in [-1.0, 1.0]:
				for s2: float in [-1.0, 1.0]:
					raw.append(Vector3(0, s1 * inv_p, s2 * PHI))
					raw.append(Vector3(s1 * inv_p, s2 * PHI, 0))
					raw.append(Vector3(s1 * PHI, 0, s2 * inv_p))
		_:
			# Icosaèdre (d20) : 3 rectangles d'or.
			for s1: float in [-1.0, 1.0]:
				for s2: float in [-1.0, 1.0]:
					raw.append(Vector3(0, s1, s2 * PHI))
					raw.append(Vector3(s1, s2 * PHI, 0))
					raw.append(Vector3(s1 * PHI, 0, s2))
	var max_r := 0.0
	for v: Vector3 in raw:
		max_r = maxf(max_r, v.length())
	var out := PackedVector3Array()
	for v: Vector3 in raw:
		out.append(v * (0.5 / maxf(max_r, 0.0001)))
	return out

## Points quasi-uniformes sur la sphère (suite de Fibonacci) avec un
## micro-jitter déterministe : position générale garantie (aucun quadrilatère
## coplanaire), donc l'enveloppe est 100 % triangulaire.
static func _fibonacci_sphere(count: int) -> Array:
	var pts: Array = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in range(count):
		var y := 1.0 - (float(i) / float(count - 1)) * 2.0
		var r := sqrt(maxf(0.0, 1.0 - y * y))
		var th := golden * float(i)
		var v := Vector3(cos(th) * r, y, sin(th) * r)
		var j := 1.0 + 0.002 * sin(float(i) * 12.9898)
		pts.append(v * j)
	return pts

## Sommets d'un trapézoèdre n-gonal : 2 apex + 2 couronnes décalées de n points.
## n=5 → dé à 10 faces (d10).
static func _trapezohedron_verts(n: int) -> Array:
	var hy := 0.32 if n <= 5 else 0.55
	var r := 0.82
	var pts: Array = [Vector3(0, 1.0, 0), Vector3(0, -1.0, 0)]
	for i in range(n):
		var a := TAU * float(i) / float(n)
		pts.append(Vector3(cos(a) * r, hy, sin(a) * r))
	for i in range(n):
		var a := TAU * (float(i) + 0.5) / float(n)
		pts.append(Vector3(cos(a) * r, -hy, sin(a) * r))
	return pts

## Kites du trapézoèdre n-gonal : 2n faces (haut i : T,U_i,L_i,U_{i+1}…).
## Indices : 0=T, 1=B, 2..2+n-1=U_i, 2+n..2+2n-1=L_i.
static func _trapezohedron_tris(n: int, verts: PackedVector3Array) -> Array:
	var idx_tris: Array = []
	for i in range(n):
		var u0 := 2 + i
		var u1 := 2 + ((i + 1) % n)
		var l0 := 2 + n + i
		var l1 := 2 + n + ((i + 1) % n)
		idx_tris.append([0, u0, l0])
		idx_tris.append([0, l0, u1])
		idx_tris.append([1, l0, u1])
		idx_tris.append([1, l1, l0])
	return _oriented(verts, idx_tris)

## Faces de valeur du trapézoèdre : d10 (n=5) chiffres 0-9 (opposés = 9).
static func _trapezohedron_faces(n: int, verts: PackedVector3Array) -> Array:
	var base := 0
	var top := 2 * n - 1
	var out: Array = []
	for i in range(n):
		var u0 := 2 + i
		var u1 := 2 + ((i + 1) % n)
		var l0 := 2 + n + i
		var l1 := 2 + n + ((i + 1) % n)
		var c_up := (verts[0] + verts[u0] + verts[l0] + verts[u1]) / 4.0
		var n_up := ((verts[u0] - verts[0]).cross(verts[u1] - verts[0])).normalized()
		if n_up.dot(c_up) < 0.0:
			n_up = -n_up
		out.append({"normal": n_up, "center": c_up, "value": base + i})
		var c_dn := (verts[1] + verts[l0] + verts[u1] + verts[l1]) / 4.0
		var n_dn := ((verts[u1] - verts[1]).cross(verts[l1] - verts[1])).normalized()
		if n_dn.dot(c_dn) < 0.0:
			n_dn = -n_dn
		out.append({"normal": n_dn, "center": c_dn, "value": top - i})
	return out

## Faces triangulaires (enveloppe convexe), normales sortantes.
## Exception d10/d100 : les kites du trapézoèdre sont construits explicitement
## (l'enveloppe cassait les kites non strictement planaires).
static func hull_triangles(sides: int) -> Array:
	var key := "tris_%d" % sides
	if _cache.has(key):
		return _cache[key]
	var verts := vertices(sides)
	if sides == 10:
		_cache[key] = _trapezohedron_tris(5, verts)
		return _cache[key]
	var tris: Array = []
	var n := verts.size()
	for i in range(n):
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var a := verts[i]
				var b := verts[j]
				var c := verts[k]
				var nrm := (b - a).cross(c - a)
				if nrm.length_squared() < 1e-10:
					continue
				nrm = nrm.normalized()
				var pos_ok := false
				var neg_ok := false
				for m in range(n):
					if m == i or m == j or m == k:
						continue
					var d := nrm.dot(verts[m] - a)
					if d > 1e-7:
						pos_ok = true
					elif d < -1e-7:
						neg_ok = true
					if pos_ok and neg_ok:
						break
				if pos_ok and neg_ok:
					continue
				var center := (a + b + c) / 3.0
				if nrm.dot(center) < 0.0:
					tris.append(PackedInt32Array([i, k, j]))
				else:
					tris.append(PackedInt32Array([i, j, k]))
	_cache[key] = tris
	return tris

## Oriente chaque triangle vers l'extérieur (normale opposée au centre).
static func _oriented(verts: PackedVector3Array, idx_tris: Array) -> Array:
	var out: Array = []
	for idx: Array in idx_tris:
		var a := verts[idx[0]]
		var b := verts[idx[1]]
		var c := verts[idx[2]]
		var nrm := (b - a).cross(c - a)
		var center := (a + b + c) / 3.0
		if nrm.dot(center) < 0.0:
			out.append(PackedInt32Array([idx[0], idx[2], idx[1]]))
		else:
			out.append(PackedInt32Array([idx[0], idx[1], idx[2]]))
	return out

## Faces de valeur : {normal, center, value} — triangles coplanaires fusionnés,
## valeurs opposées sommant à N+1 (d10 : 0-9, somme 9).
static func face_data(sides: int) -> Array:
	var key := "faces_%d" % sides
	if _cache.has(key):
		return _cache[key]
	var verts := vertices(sides)
	if sides == 10:
		var d10 := _trapezohedron_faces(5, verts)
		_cache[key] = d10
		return d10
	var groups: Array = []  # {normal, center_sum, count}
	for tri_variant in hull_triangles(sides):
		var tri: PackedInt32Array = tri_variant
		var a := verts[tri[0]]
		var b := verts[tri[1]]
		var c := verts[tri[2]]
		var nrm := ((b - a).cross(c - a)).normalized()
		var found := -1
		for g in range(groups.size()):
			# Fusion des triangles d'une même face plane (ex. cube = 2 triangles).
			# Epsilon serré : sur une bille, deux faces voisines ne doivent JAMAIS
			# fusionner, même avec des normales proches.
			if (groups[g]["normal"] as Vector3).dot(nrm) > 0.99999:
				found = g
				break
		if found < 0:
			groups.append({"normal": nrm, "center_sum": a + b + c, "count": 3.0})
		else:
			var grp: Dictionary = groups[found]
			grp["center_sum"] = (grp["center_sum"] as Vector3) + a + b + c
			grp["count"] = float(grp["count"]) + 3.0
	# Paires de faces opposées → numérotation de dé réel.
	var n_faces := groups.size()
	var values := PackedInt32Array()
	values.resize(n_faces)
	var v_lo := 1
	var v_hi := n_faces
	var assigned := PackedByteArray()
	assigned.resize(n_faces)
	var next_lo := v_lo
	var next_hi := v_hi
	for i in range(n_faces):
		if assigned[i] != 0:
			continue
		assigned[i] = 1
		values[i] = next_lo
		var partner := -1
		for j in range(n_faces):
			if assigned[j] != 0:
				continue
			if (groups[i]["normal"] as Vector3).dot(groups[j]["normal"] as Vector3) < -0.999:
				partner = j
				break
		if partner >= 0:
			assigned[partner] = 1
			values[partner] = next_hi
		next_lo += 1
		next_hi -= 1
	var out: Array = []
	for i in range(n_faces):
		var grp: Dictionary = groups[i]
		out.append({
			"normal": (grp["normal"] as Vector3).normalized(),
			"center": (grp["center_sum"] as Vector3) / float(grp["count"]),
			"value": int(values[i]),
		})
	_cache[key] = out
	return out

## Maillage plat (une normale par triangle), taille = côté du cube enveloppe.
static func build_mesh(sides: int, size: float) -> ArrayMesh:
	var verts := vertices(sides)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri_variant in hull_triangles(sides):
		var tri: PackedInt32Array = tri_variant
		var a := verts[tri[0]] * size
		var b := verts[tri[1]] * size
		var c := verts[tri[2]] * size
		var nrm := ((b - a).cross(c - a)).normalized()
		for v: Vector3 in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(v)
	return st.commit()

## Sommets pour la collision (ConvexPolygonShape3D).
static func collision_points(sides: int, size: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in vertices(sides):
		out.append(v * size)
	return out

## Face du dessus : {value, upness} — `upness` = alignement avec +Y (1.0 = le dé
## est bien **droit**, posé sur une face ; bas = posé sur une arête/pointe).
static func top_face_info(sides: int, basis: Basis) -> Dictionary:
	var best := {"value": 1, "upness": -2.0}
	for f: Dictionary in face_data(sides):
		var world_n: Vector3 = (basis * (f["normal"] as Vector3)).normalized()
		var d := world_n.dot(Vector3.UP)
		if d > float(best["upness"]):
			best = {"value": int(f["value"]), "upness": d}
	return best

## Valeur de la face du dessus (normale la plus alignée avec +Y).
static func top_face_value(sides: int, basis: Basis) -> int:
	return int(top_face_info(sides, basis)["value"])
