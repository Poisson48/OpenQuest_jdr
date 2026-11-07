extends RefCounted
class_name TerrainCarveChunks

## Clusters de creusement + maillage Marching Cubes (Voie B).
##
## Chaque groupe de primitives SDF proches forme un **cluster** ; ce cluster est
## polygonisé en Marching Cubes (décomposition tétraédrique, table
## `MarchingCubes.TETRAHEDRA`) à partir du champ `TerrainCarveField`. Le champ
## inclut le heightfield de base : le maillage du cluster remplace le maillage
## heightfield sur son emprise (les quads heightfield correspondants sont
## découpés par `MapGround3D`), et **raccorde au bord** avec lui :
##   • les bords de cluster sont alignés sur les frontières de cases ;
##   • le long d'une frontière de case, la surface heightfield est linéaire
##     (interpolation bilinéaire du maillage) et le champ MC l'échantillonne
##     exactement aux mêmes points → les deux maillages partagent la même ligne
##     de bord ;
##   • des « **fences** » verticales (bandes sombres décalées de quelques mm
##     vers l'intérieur) couvrent les micro-fuites résiduelles (cordes MC vs
##     polylinée heightfield) : une fissure éventuelle montre la fence, jamais
##     le vide.
##
## Toutes les coordonnées de champ sont **en cases** ; les sommets produits sont
## en unités monde (`cell_size`). Le maillage sortant porte UV (tuilage matière,
## 1 répétition toutes `tile_cells` cases), UV2 (0..1 sur la carte, splat) et
## vertex colors (même palette que le heightfield, via `color_fn`).

const MarchingCubesScript := preload("res://scripts/maps/construction/marching_cubes.gd")
## Préchargement explicite (fiable en headless, indépendant du cache `class_name`).
const CarveFieldScript := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
## Décalage horizontal des fences vers l'intérieur du cluster (cases).
const FENCE_INSET := 0.004
## Profondeur des fences sous le point le plus bas de leur bord (cases).
const FENCE_DEPTH := 1.2
## Résolution mini du maillage MC (voxels par case).
const MIN_RESOLUTION := 3
## Aire minimale d'un triangle (cases²) : en dessous, c'est une « mouche » —
## lambeau dégénéré des zones de tangence (lèvres de creusement) qui rend
## comme un éclat clair/sombre parasite. Les vrais triangles utiles sont
## typiquement > 10× ce seuil.
const SLIVER_MIN_AREA := 0.0003

# ===========================================================================
# Clusters
# ===========================================================================

## Regroupe les primitives et les régions sculptées en clusters. Deux éléments
## sont dans le même cluster si leurs emprises élargies se rencontrent
## (l'élargissement couvre le lissage `smooth` + 1 case de marge, pour qu'aucun
## élément n'influence le champ sur les bords du cluster — condition de
## raccord). Renvoie [{rect: Rect2i (cases, fin exclusive), y0: float,
## y1: float, ids: Array[String]}].
static func compute_clusters(carves: Array, sculpt_regions: Array = []) -> Array:
	var boxes: Array = []
	for entry in carves:
		if not (entry is Dictionary):
			continue
		var b: Dictionary = CarveFieldScript.bounds_of(entry)
		var expand := 1.0 + clampf(float(entry.get("smooth", CarveFieldScript.DEFAULT_SMOOTH)), 0.0, 2.0)
		boxes.append({
			"x0": float(b["x0"]) - expand, "x1": float(b["x1"]) + expand,
			"y0": float(b["y0"]) - expand, "y1": float(b["y1"]) + expand,
			"z0": float(b["z0"]) - expand, "z1": float(b["z1"]) + expand,
			"ids": [str(entry.get("id", ""))],
		})
	# Régions sculptées (déplacement lissé) : légère marge de raccord.
	for i in range(sculpt_regions.size()):
		var r: Dictionary = sculpt_regions[i]
		boxes.append({
			"x0": float(r["x0"]) - 0.25, "x1": float(r["x1"]) + 0.25,
			"y0": float(r["y0"]) - 0.25, "y1": float(r["y1"]) + 0.25,
			"z0": float(r["z0"]) - 0.25, "z1": float(r["z1"]) + 0.25,
			"ids": ["sculpt:%.2f_%.2f_%.2f" % [float(r["x0"]), float(r["y0"]), float(r["z0"])]],
		})
	# Fusion itérative des emprises qui se recouvrent.
	var merged := true
	while merged:
		merged = false
		for i in range(boxes.size()):
			for j in range(i + 1, boxes.size()):
				if _boxes_overlap(boxes[i], boxes[j]):
					boxes[i] = _merge_boxes(boxes[i], boxes[j])
					boxes.remove_at(j)
					merged = true
					break
			if merged:
				break
	var clusters: Array = []
	for box in boxes:
		var cx0 := floori(float(box["x0"]))
		var cz0 := floori(float(box["z0"]))
		var cx1 := ceili(float(box["x1"]))
		var cz1 := ceili(float(box["z1"]))
		cx1 = maxi(cx1, cx0 + 1)
		cz1 = maxi(cz1, cz0 + 1)
		clusters.append({
			"rect": Rect2i(Vector2i(cx0, cz0), Vector2i(cx1 - cx0, cz1 - cz0)),
			"y0": float(box["y0"]),
			"y1": float(box["y1"]),
			"ids": box["ids"],
		})
	return clusters

static func _boxes_overlap(a: Dictionary, b: Dictionary) -> bool:
	return a["x0"] < b["x1"] and b["x0"] < a["x1"] \
		and a["y0"] < b["y1"] and b["y0"] < a["y1"] \
		and a["z0"] < b["z1"] and b["z0"] < a["z1"]

static func _merge_boxes(a: Dictionary, b: Dictionary) -> Dictionary:
	var ids: Array = []
	ids.append_array(a["ids"])
	for id in b["ids"]:
		if not ids.has(id):
			ids.append(id)
	return {
		"x0": minf(a["x0"], b["x0"]), "x1": maxf(a["x1"], b["x1"]),
		"y0": minf(a["y0"], b["y0"]), "y1": maxf(a["y1"], b["y1"]),
		"z0": minf(a["z0"], b["z0"]), "z1": maxf(a["z1"], b["z1"]),
		"ids": ids,
	}

## Empreinte 2D (cases, fin exclusive) d'un cluster — sert à découper le
## maillage heightfield.
static func cluster_footprint(cluster: Dictionary) -> Rect2i:
	return cluster.get("rect", Rect2i())

# ===========================================================================
# Polygonisation
# ===========================================================================

## Construit le maillage d'un cluster (unités monde). `color_fn` est appelé
## `color_fn.call(hauteur_cases, normale, i, j)` par sommet (même convention
## que `MapGround3D`), `tile_cells` le tuilage UV de la texture de détail.
## Renvoie un `ArrayMesh` (vide si le cluster ne coupe rien).
static func build_cluster_mesh(
	field: CarveFieldScript,
	cluster: Dictionary,
	map_w: int,
	map_h: int,
	tile_cells: float,
	cell_size: float,
	color_fn: Callable,
	resolution: int = MIN_RESOLUTION,
	with_fences: bool = true
) -> ArrayMesh:
	# La résolution est choisie par l'appelant (aperçu rapide vs qualité
	# finale) : simple contrainte de plage ici, pas de plancher caché.
	var res := clampi(resolution, 1, 6)
	var rect: Rect2i = cluster.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return ArrayMesh.new()
	var x0 := float(rect.position.x)
	var z0 := float(rect.position.y)
	var x1 := float(rect.end.x)
	var z1 := float(rect.end.y)
	var y0 := floorf(float(cluster.get("y0", -2.0))) - 1.0
	var y1 := ceilf(float(cluster.get("y1", 2.0))) + 1.0
	var nx := rect.size.x * res
	var nz := rect.size.y * res
	var ny := maxi(1, int(ceil((y1 - y0) * float(res))))
	var sx := (x1 - x0) / float(nx)
	var sy := (y1 - y0) / float(ny)
	var sz := (z1 - z0) / float(nz)

	# Valeurs du champ aux sommets de la grille (un seul échantillonnage partagé).
	var gx_count := nx + 1
	var gy_count := ny + 1
	var gz_count := nz + 1
	var values := PackedFloat32Array()
	values.resize(gx_count * gy_count * gz_count)
	for iz in range(gz_count):
		var pz := z0 + float(iz) * sz
		for iy in range(gy_count):
			var py := y0 + float(iy) * sy
			var row := (iz * gy_count + iy) * gx_count
			for ix in range(gx_count):
				values[row + ix] = field.sample(Vector3(x0 + float(ix) * sx, py, pz))

	# Polygonisation tétraédrique (même table que MarchingCubes).
	var tris: Array[Vector3] = []
	var corners: Array[Vector3] = []
	var vals: Array[float] = []
	corners.resize(8)
	vals.resize(8)
	for iz in range(nz):
		for iy in range(ny):
			for ix in range(nx):
				var base := (iz * gy_count + iy) * gx_count + ix
				# Coins du cube dans l'ordre de MarchingCubes.CORNERS.
				vals[0] = values[base]
				vals[1] = values[base + 1]
				vals[2] = values[base + gx_count + 1]
				vals[3] = values[base + gx_count]
				vals[4] = values[base + gx_count * gy_count]
				vals[5] = values[base + gx_count * gy_count + 1]
				vals[6] = values[base + gx_count * gy_count + gx_count + 1]
				vals[7] = values[base + gx_count * gy_count + gx_count]
				var any_in := false
				var any_out := false
				for k in range(8):
					if vals[k] >= 0.0:
						any_in = true
					else:
						any_out = true
				if not (any_in and any_out):
					continue
				var px := x0 + float(ix) * sx
				var py := y0 + float(iy) * sy
				var pz := z0 + float(iz) * sz
				corners[0] = Vector3(px, py, pz)
				corners[1] = Vector3(px + sx, py, pz)
				corners[2] = Vector3(px + sx, py + sy, pz)
				corners[3] = Vector3(px, py + sy, pz)
				corners[4] = Vector3(px, py, pz + sz)
				corners[5] = Vector3(px + sx, py, pz + sz)
				corners[6] = Vector3(px + sx, py + sy, pz + sz)
				corners[7] = Vector3(px, py + sy, pz + sz)
				for tet in MarchingCubesScript.TETRAHEDRA:
					_emit_tetrahedron(tris, corners, vals, tet)

	return _build_mesh(tris, field, cluster, map_w, map_h, tile_cells, cell_size, color_fn,
		with_fences, values, Vector3(x0, y0, z0), Vector3(sx, sy, sz),
		Vector3i(gx_count, gy_count, gz_count))

## Émet les triangles d'un tétraèdre (iso 0, intérieur = valeur >= 0).
## Variante de `MarchingCubes._add_tetrahedron`, **sans allocation interne** :
## le hot path est appelé des dizaines de milliers de fois par rebuild.
static func _emit_tetrahedron(tris: Array[Vector3], corners: Array[Vector3],
		vals: Array[float], tet: Array) -> void:
	var i0: int = tet[0]
	var i1: int = tet[1]
	var i2: int = tet[2]
	var i3: int = tet[3]
	var in0 := vals[i0] >= 0.0
	var in1 := vals[i1] >= 0.0
	var in2 := vals[i2] >= 0.0
	var in3 := vals[i3] >= 0.0
	if in0 == in1 and in0 == in2 and in0 == in3:
		return
	var count := (1 if in0 else 0) + (1 if in1 else 0) + (1 if in2 else 0) + (1 if in3 else 0)
	if count == 2:
		# 2 dedans / 2 dehors : deux triangles (4 points d'arête).
		var in_a := -1
		var in_b := -1
		var out_a := -1
		var out_b := -1
		for ti in tet:
			if vals[ti] >= 0.0:
				if in_a < 0:
					in_a = ti
				else:
					in_b = ti
			else:
				if out_a < 0:
					out_a = ti
				else:
					out_b = ti
		var pa := corners[in_a]
		var va := vals[in_a]
		var pb := corners[in_b]
		var vb := vals[in_b]
		var pc := corners[out_a]
		var vc := vals[out_a]
		var pd := corners[out_b]
		var vd := vals[out_b]
		var ac := _edge_point(pa, va, pc, vc)
		var ad := _edge_point(pa, va, pd, vd)
		var bc := _edge_point(pb, vb, pc, vc)
		var bd := _edge_point(pb, vb, pd, vd)
		tris.append(ac)
		tris.append(ad)
		tris.append(bd)
		tris.append(ac)
		tris.append(bd)
		tris.append(bc)
		return
	# count == 1 ou 3 : un sommet isolé (in si count == 1, out sinon), un
	# triangle contre ses trois arêtes.
	var iso_in := count == 1
	var iso := i0
	var iso_v := vals[i0]
	if in0 != iso_in:
		if in1 == iso_in:
			iso = i1
			iso_v = vals[i1]
		elif in2 == iso_in:
			iso = i2
			iso_v = vals[i2]
		else:
			iso = i3
			iso_v = vals[i3]
	var p_iso := corners[iso]
	var e1 := Vector3.ZERO
	var e2 := Vector3.ZERO
	var emitted := 0
	for ti in tet:
		if ti == iso:
			continue
		var ep := _edge_point(p_iso, iso_v, corners[ti], vals[ti])
		if emitted == 0:
			e1 = ep
		elif emitted == 1:
			e2 = ep
		else:
			tris.append(e1)
			tris.append(e2)
			tris.append(ep)
		emitted += 1

static func _edge_point(a: Vector3, va: float, b: Vector3, vb: float) -> Vector3:
	var denom := vb - va
	if absf(denom) < 0.000001:
		return a
	var t := clampf(-va / denom, 0.0, 1.0)
	return a.lerp(b, t)

## Échantillonnage trilinéaire de la grille de champ déjà calculée (évite de
## ré-appeler `field.sample` pour l'orientation des triangles). Les bords sont
## clampés : suffisant pour le test de winding près des limites du cluster.
static func _grid_sample(values: PackedFloat32Array, dims: Vector3i,
		origin: Vector3, step: Vector3, p: Vector3) -> float:
	if dims.x < 2 or dims.y < 2 or dims.z < 2:
		return 0.0
	var fx := (p.x - origin.x) / step.x
	var fy := (p.y - origin.y) / step.y
	var fz := (p.z - origin.z) / step.z
	var x0 := clampi(floori(fx), 0, dims.x - 2)
	var y0 := clampi(floori(fy), 0, dims.y - 2)
	var z0 := clampi(floori(fz), 0, dims.z - 2)
	var tx := clampf(fx - float(x0), 0.0, 1.0)
	var ty := clampf(fy - float(y0), 0.0, 1.0)
	var tz := clampf(fz - float(z0), 0.0, 1.0)
	var stride_x := 1
	var stride_y := dims.x
	var stride_z := dims.x * dims.y
	var base := x0 + y0 * stride_y + z0 * stride_z
	var c000 := values[base]
	var c100 := values[base + stride_x]
	var c010 := values[base + stride_y]
	var c110 := values[base + stride_y + stride_x]
	var c001 := values[base + stride_z]
	var c101 := values[base + stride_z + stride_x]
	var c011 := values[base + stride_z + stride_y]
	var c111 := values[base + stride_z + stride_y + stride_x]
	var c00 := lerpf(c000, c100, tx)
	var c10 := lerpf(c010, c110, tx)
	var c01 := lerpf(c001, c101, tx)
	var c11 := lerpf(c011, c111, tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)

## Sens de croissance du champ le long de `n` autour de `centroid` :
## `1` si le champ augmente vers +n (la normale pointe vers la matière),
## `-1` sinon. Un seul appel par triangle (indexation partagée) — c'est le
## test de winding « convention Godot ».
static func _grid_side(values: PackedFloat32Array, dims: Vector3i,
		origin: Vector3, step: Vector3, centroid: Vector3, n: Vector3) -> int:
	if dims.x < 2 or dims.y < 2 or dims.z < 2:
		return -1
	var n_len := n.length()
	if n_len < 0.0000001:
		return -1
	var probe := n * (0.02 / n_len)
	var fx := (centroid.x - origin.x) / step.x
	var fy := (centroid.y - origin.y) / step.y
	var fz := (centroid.z - origin.z) / step.z
	var x0 := clampi(floori(fx), 0, dims.x - 2)
	var y0 := clampi(floori(fy), 0, dims.y - 2)
	var z0 := clampi(floori(fz), 0, dims.z - 2)
	var stride_x := 1
	var stride_y := dims.x
	var stride_z := dims.x * dims.y
	var base := x0 + y0 * stride_y + z0 * stride_z
	var c000 := values[base]
	var c100 := values[base + stride_x]
	var c010 := values[base + stride_y]
	var c110 := values[base + stride_y + stride_x]
	var c001 := values[base + stride_z]
	var c101 := values[base + stride_z + stride_x]
	var c011 := values[base + stride_z + stride_y]
	var c111 := values[base + stride_z + stride_y + stride_x]
	# Les deux sondes partagent la même cellule (offset << taille de voxel) :
	# une seule indexation, deux évaluations trilinéaires.
	var base_x := float(x0)
	var base_y := float(y0)
	var base_z := float(z0)
	var t1x := clampf((fx + probe.x / step.x) - base_x, 0.0, 1.0)
	var t1y := clampf((fy + probe.y / step.y) - base_y, 0.0, 1.0)
	var t1z := clampf((fz + probe.z / step.z) - base_z, 0.0, 1.0)
	var t2x := clampf((fx - probe.x / step.x) - base_x, 0.0, 1.0)
	var t2y := clampf((fy - probe.y / step.y) - base_y, 0.0, 1.0)
	var t2z := clampf((fz - probe.z / step.z) - base_z, 0.0, 1.0)
	var v_plus := _tri_lerp(c000, c100, c010, c110, c001, c101, c011, c111, t1x, t1y, t1z)
	var v_minus := _tri_lerp(c000, c100, c010, c110, c001, c101, c011, c111, t2x, t2y, t2z)
	return 1 if v_plus > v_minus else -1

static func _tri_lerp(c000: float, c100: float, c010: float, c110: float,
		c001: float, c101: float, c011: float, c111: float,
		tx: float, ty: float, tz: float) -> float:
	var c00 := lerpf(c000, c100, tx)
	var c10 := lerpf(c010, c110, tx)
	var c01 := lerpf(c001, c101, tx)
	var c11 := lerpf(c011, c111, tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)

# ===========================================================================
# Construction du maillage (sommets soudés, normales lissées, UV, couleurs)
# ===========================================================================

## Soudage des sommets (clé quantifiée 1e-4 case), normales moyennées pondérées
## par l'aire des faces, puis couleurs de sommet via `color_fn`, fences, et
## assemblage de l'`ArrayMesh` (unités monde).
static func _build_mesh(tris: Array[Vector3], field: CarveFieldScript,
		cluster: Dictionary, map_w: int, map_h: int, tile_cells: float,
		cell_size: float, color_fn: Callable, with_fences: bool = true,
		grid_values: PackedFloat32Array = PackedFloat32Array(),
		grid_origin: Vector3 = Vector3.ZERO, grid_step: Vector3 = Vector3.ONE,
		grid_dims: Vector3i = Vector3i.ZERO) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var index_of := {}
	var verts: Array[Vector3] = []
	var normals_acc: Array[Vector3] = []
	var indices := PackedInt32Array()
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var n := (b - a).cross(c - a)
		# Anti-« mouches » : les triangles d'aire quasi nulle (zones de tangence
		# des lèvres) sont des lambeaux parasites — on les écarte avant tout.
		if n.length() * 0.5 < SLIVER_MIN_AREA:
			continue
		# Orienter le triangle selon la convention **Godot** : la face avant est
		# le sens horaire, donc le produit vectoriel (b-a)×(c-a) doit pointer
		# VERS LA MATIÈRE (intérieur du champ >= 0), et la normale d'ombrage
		# vers le vide. Même convention que le maillage heightfield (dont le
		# produit vectoriel pointe vers le bas = dans la terre). À l'envers, les
		# triangles seraient des faces arrière : normale retournée, surface
		# assombrie. Le test lit la grille déjà échantillonnée (trilinéaire) —
		# pas de ré-échantillonnage du champ par triangle.
		var centroid := (a + b + c) / 3.0
		var side: int
		if grid_dims.x > 0:
			side = _grid_side(grid_values, grid_dims, grid_origin, grid_step, centroid, n)
		else:
			var n_dir := n.normalized()
			side = 1 if field.sample(centroid + n_dir * 0.02) > field.sample(centroid - n_dir * 0.02) else -1
		if side < 0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		# Normale d'ombrage = l'inverse du produit vectoriel du winding final
		# (comme le maillage heightfield : produit vectoriel vers le bas = dans
		# la matière, normale d'ombrage vers le haut = vers le vide).
		n = -n
		var ia := _weld_index(a, index_of, verts, normals_acc)
		var ib := _weld_index(b, index_of, verts, normals_acc)
		var ic := _weld_index(c, index_of, verts, normals_acc)
		normals_acc[ia] += n
		normals_acc[ib] += n
		normals_acc[ic] += n
		indices.append(ia)
		indices.append(ib)
		indices.append(ic)
	# Fences verticales aux bords du cluster (anti-fuites de raccord).
	var fence_tris: Array[Vector3] = []
	if with_fences:
		fence_tris = _build_fences(field, cluster)

	var total := verts.size() + fence_tris.size()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	positions.resize(total)
	normals.resize(total)
	uvs.resize(total)
	uv2s.resize(total)
	colors.resize(total)
	var map_w_safe := maxf(1.0, float(map_w))
	var map_h_safe := maxf(1.0, float(map_h))
	for vi in range(verts.size()):
		var v := verts[vi]
		var n := normals_acc[vi]
		if n.length_squared() < 0.000000000001:
			n = Vector3.UP
		else:
			n = n.normalized()
		positions[vi] = v * cell_size
		normals[vi] = n
		uvs[vi] = Vector2(v.x / tile_cells, v.z / tile_cells)
		uv2s[vi] = Vector2(v.x / map_w_safe, v.z / map_h_safe)
		var col: Color = color_fn.call(v.y, n, floori(v.x), floori(v.z))
		colors[vi] = col
	var base := verts.size()
	for fi in range(fence_tris.size()):
		var v2 := fence_tris[fi]
		positions[base + fi] = v2 * cell_size
		normals[base + fi] = Vector3.UP
		uvs[base + fi] = Vector2(v2.x / tile_cells, v2.z / tile_cells)
		uv2s[base + fi] = Vector2(v2.x / map_w_safe, v2.z / map_h_safe)
		colors[base + fi] = FENCE_COLOR
	# Normales des fences : par face (bandes verticales), bien meilleures que
	# `UP` pour l'éclairage des parois de raccord. Convention Godot : la normale
	# d'ombrage est l'inverse du produit vectoriel du winding.
	for fi in range(0, fence_tris.size() - 2, 3):
		var fa := fence_tris[fi]
		var fb := fence_tris[fi + 1]
		var fc := fence_tris[fi + 2]
		var fn := (fb - fa).cross(fc - fa)
		if fn.length_squared() < 0.000000000001:
			continue
		fn = -fn.normalized()
		normals[base + fi] = fn
		normals[base + fi + 1] = fn
		normals[base + fi + 2] = fn
	for fi in range(0, fence_tris.size() - 2, 3):
		indices.append(base + fi)
		indices.append(base + fi + 1)
		indices.append(base + fi + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Soudage d'un sommet : renvoie son index (crée si nouveau). Quantification à
## 5e-4 case : fusionne les sommets quasi coïncidents des lèvres de creusement
## (sinon micro-fissures et normales hérissées).
static func _weld_index(p: Vector3, index_of: Dictionary, verts: Array[Vector3],
		normals_acc: Array[Vector3]) -> int:
	var key := Vector3i(roundi(p.x * 2000.0), roundi(p.y * 2000.0), roundi(p.z * 2000.0))
	if index_of.has(key):
		return int(index_of[key])
	var idx := verts.size()
	verts.append(p)
	normals_acc.append(Vector3.ZERO)
	index_of[key] = idx
	return idx

const FENCE_COLOR := Color(0.28, 0.25, 0.22)

## Bandes verticales le long des 4 bords du cluster : le haut suit exactement
## la ligne de bord du maillage heightfield (`height_at`), le bas descend sous
## le cluster ; décalées de `FENCE_INSET` vers l'intérieur pour ne jamais
## z-fighter avec les maillages voisins. Renvoie des triangles plats (cases).
static func _build_fences(field: CarveFieldScript, cluster: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rect: Rect2i = cluster.get("rect", Rect2i())
	if rect.size.x <= 0 or rect.size.y <= 0:
		return out
	var x0 := float(rect.position.x)
	var z0 := float(rect.position.y)
	var x1 := float(rect.end.x)
	var z1 := float(rect.end.y)
	var inset := FENCE_INSET
	# Bords : deux verticaux (x fixe, on longe z) et deux horizontaux (z fixe).
	var sides := [
		{"px": x0 + inset, "pz": 0.0, "from": z0, "to": z1, "along_x": false},
		{"px": x1 - inset, "pz": 0.0, "from": z0, "to": z1, "along_x": false},
		{"px": 0.0, "pz": z0 + inset, "from": x0, "to": x1, "along_x": true},
		{"px": 0.0, "pz": z1 - inset, "from": x0, "to": x1, "along_x": true},
	]
	for side in sides:
		var is_x_side := bool(side["along_x"])
		var from := float(side["from"])
		var to := float(side["to"])
		# Échantillonnage à 0.5 case : plus fin que les voxels MC aux bords.
		var steps := maxi(2, int(ceil(absf(to - from) * 2.0)))
		var tops: Array[Vector3] = []
		var top_min := INF
		for s in range(steps + 1):
			var t := lerpf(from, to, float(s) / float(steps))
			var px := float(side["px"]) if is_x_side else t
			var pz := t if is_x_side else float(side["pz"])
			var top := field.height_at(px, pz)
			top_min = minf(top_min, top)
			tops.append(Vector3(px, top, pz))
		var bottom_y := top_min - FENCE_DEPTH
		for s in range(steps):
			var a_top := tops[s]
			var b_top := tops[s + 1]
			var a_bot := Vector3(a_top.x, bottom_y, a_top.z)
			var b_bot := Vector3(b_top.x, bottom_y, b_top.z)
			out.append(a_top)
			out.append(b_top)
			out.append(b_bot)
			out.append(a_top)
			out.append(b_bot)
			out.append(a_bot)
	return out
