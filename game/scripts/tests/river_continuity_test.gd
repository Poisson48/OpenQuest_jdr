extends SceneTree

## Sonde de CONTINUITÉ de rivière : construit une rivière droite sur une carte
## plate et vérifie (a) la géométrie du ruban, (b) le masque de la texture
## d'eau (couverture du lit), (c) le niveau de l'eau le long du tracé.

const WaterScript := preload("res://scripts/maps/map_layers/map_water_3d.gd")
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(0.0)
	var river := {
		"id": "riv", "kind": "river", "width": 1.2, "flow_speed": 0.4,
		"path": [[2.0, 0.06, 7.0], [10.0, 0.06, 7.0], [18.0, 0.06, 7.0]],
	}
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(20, 14, 1.0, -1.0, heights, false, 1, 1.0, [], {}, [river])
	await process_frame
	_assert("body_built", water.get_body_count() == 1, "n=%d" % water.get_body_count())
	var node: MeshInstance3D = water._body_nodes[0]
	var mesh: ArrayMesh = node.mesh
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	print("  [probe] sommets=%d surfaces=%d" % [verts.size(), mesh.get_surface_count()])
	# 1) Géométrie : les quads doivent couvrir le tracé en continu (z≈7).
	var min_x := INF
	var max_x := -INF
	for v in verts:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
	print("  [probe] emprise x=[%.2f, %.2f] (attendu ~[2, 18])" % [min_x, max_x])
	_assert("mesh_spans_path", min_x < 3.0 and max_x > 17.0,
		"x=[%.2f, %.2f]" % [min_x, max_x])
	# 2) Masque : la ligne de cases z=7 doit être couverte en continu.
	var img: Image = water.get_depth_image()
	var masked := 0
	var holes := 0
	var run := 0
	for x in range(2, 19):
		var m: float = _sample(img, 20, x, 7).g
		if m > 0.5:
			masked += 1
			run += 1
		else:
			if run > 0 and masked < 17:
				holes += 1
			run = 0
	print("  [probe] cases couvertes sur z=7 : %d/17 (trous=%d)" % [masked, holes])
	_assert("mask_continuous", masked >= 15, "couvertes=%d" % masked)
	# 3) La profondeur doit être > 0 (eau visible au-dessus du sol).
	var depth_sum := 0.0
	for x in range(2, 19):
		depth_sum += _sample(img, 20, x, 7).r
	print("  [probe] profondeur cumulée=%.3f" % depth_sum)
	_assert("depth_positive", depth_sum > 0.5, "somme=%.3f" % depth_sum)
	await _probe_wiggly_carved()
	if _failed:
		print("river_continuity_test:FAIL")
		quit(1)
		return
	print("river_continuity_test:PASS")
	quit(0)

## Cas réel : tracé SINUEUX sur carte plate + lit creusé le long du tracé
## (comme l'outil Eau → Rivière). Traque les trous de masque le long du lit.
func _probe_wiggly_carved() -> void:
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(0.0)
	var curve := [
		Vector2(2.0, 7.0), Vector2(4.0, 5.2), Vector2(6.0, 6.4),
		Vector2(8.0, 4.6), Vector2(10.0, 5.8), Vector2(12.0, 4.4),
		Vector2(14.0, 5.6), Vector2(16.0, 4.6), Vector2(18.0, 6.0),
	]
	# Creuse le lit : tampons tous les 0.3 de rayon 0.7, profondeur 0.35
	# (kernels doux comme paint_terrain_brush « lower »).
	for i in range(curve.size() - 1):
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / 0.3))
		for s in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			for cz in range(14):
				for cx in range(20):
					var d := Vector2(float(cx), float(cz)).distance_to(p) / 0.7
					if d >= 1.0:
						continue
					var k := (1.0 - d * d)
					k *= k
					var idx := cz * 20 + cx
					heights[idx] = float(heights[idx]) - 0.35 * k
	var river := {
		"id": "riv_wiggle", "kind": "river", "width": 1.2, "flow_speed": 0.4,
		"depth": 0.25,
		"path": [[2.0, 0.06, 7.0], [4.0, 0.06, 5.2], [6.0, 0.06, 6.4],
			[8.0, 0.06, 4.6], [10.0, 0.06, 5.8], [12.0, 0.06, 4.4],
			[14.0, 0.06, 5.6], [16.0, 0.06, 4.6], [18.0, 0.06, 6.0]],
	}
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(20, 14, 1.0, -1.0, heights, false, 1, 1.0, [], {}, [river])
	await process_frame
	if water.get_body_count() != 1:
		_assert("wiggle_body", false)
		return
	var img: Image = water.get_depth_image()
	# Parcours du lit : masque attendu PLEIN partout (couverture continue).
	var samples := 0
	var holes := 0
	var dry := 0
	var core_dry := 0
	var masked := 0
	var hole_at: Array = []
	for i in range(curve.size() - 1):
		var a: Vector2 = curve[i]
		var b: Vector2 = curve[i + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / 0.2))
		for s in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			var cx := clampi(roundi(p.x), 0, 19)
			var cz := clampi(roundi(p.y), 0, 13)
			# Distance du CENTRE DE CELLULE au tracé : seule la zone de
			# COURANT doit être mouillée en continu (au bord du ruban, la
			# berge peut affleurer — c'est normal).
			var cell_pos := Vector2(float(cx), float(cz))
			var near := INF
			for j in range(curve.size() - 1):
				var ca: Vector2 = curve[j]
				var cb: Vector2 = curve[j + 1]
				var cab := cb - ca
				var t := clampf((cell_pos - ca).dot(cab) / maxf(cab.length_squared(), 0.0001), 0.0, 1.0)
				near = minf(near, cell_pos.distance_to(ca + cab * t))
			samples += 1
			var col := _sample(img, 20, cx, cz)
			if col.g >= 0.5:
				masked += 1
			else:
				holes += 1
				if hole_at.size() < 8:
					hole_at.append("(%d,%d)" % [cx, cz])
			if col.g >= 0.5 and col.r <= 0.001 and near < 0.35:
				core_dry += 1
	print("  [probe] sinueux+creusé : échantillons=%d mouillés=%d berges=%d cœur_sec=%d %s" % [
		samples, masked, holes, core_dry, " ".join(hole_at)])
	# Contrat « masque par profondeur » : l'eau couvre le lit ; les berges
	# (plus hautes que la nappe) sont naturellement découpées par le terrain.
	_assert("wiggle_water_present", masked >= int(float(samples) * 0.6),
		"mouillés=%d/%d" % [masked, samples])
	_assert("wiggle_core_water_above_ground", core_dry == 0, "cœur_sec=%d" % core_dry)

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])

## Échantillonne la texture de profondeur (haute résolution : 4 texels/case)
## au CENTRE de la case demandée.
func _sample(img: Image, map_w: int, cx: int, cz: int) -> Color:
	var res: int = maxi(1, img.get_width() / map_w)
	var px := clampi(cx * res + res / 2, 0, img.get_width() - 1)
	var pz := clampi(cz * res + res / 2, 0, img.get_height() - 1)
	return img.get_pixel(px, pz)
