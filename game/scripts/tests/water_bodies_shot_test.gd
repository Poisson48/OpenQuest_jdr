extends SceneTree

## Capture du système d'eau : lac dans une cuvette sculptée (il ne remplit
## que les creux) + rivière dont le sens du tracé anime le courant, avec une
## cascade sur le dénivelé.

const OUT_DIR := "user://water_shots"
const COPY_DIR := "docs/screenshots"

var Engine3DScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Eau", "general", "local", 20, 14)

	# Terrain : plateau amont (z < 3) à 2.2, plaine à 1.1, cuvette centrale.
	var heights: Array = []
	heights.resize(20 * 14)
	for y in range(14):
		for x in range(20):
			var h := 1.1
			if y < 3:
				h = 2.2
			if x >= 5 and x <= 15 and y >= 4 and y <= 10:
				h = 0.1 + absf(float(x) - 10.0) * 0.05 + absf(float(y) - 7.0) * 0.05
			heights[y * 20 + x] = h
	map["terrainHeights"] = heights
	map["vegetationDensity"] = 0.4
	# Creuse le LIT le long du tracé (comme le fait l'outil Eau → Rivière) :
	# la nappe doit remplir un vrai canal, pas flotter sur la pente.
	var bed_path: Array = [[17, 1.5], [17, 2.8], [17, 3.8], [16, 5.0], [14.5, 6.2]]
	for i in range(bed_path.size() - 1):
		var ba := Vector2(float(bed_path[i][0]), float(bed_path[i][1]))
		var bb := Vector2(float(bed_path[i + 1][0]), float(bed_path[i + 1][1]))
		var bsteps := maxi(1, ceili(ba.distance_to(bb) * 4.0))
		for s in range(bsteps + 1):
			var bp: Vector2 = ba.lerp(bb, float(s) / float(bsteps))
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var gx: int = int(round(bp.x)) + dx
					var gz: int = int(round(bp.y)) + dz
					if gx >= 0 and gx < 20 and gz >= 0 and gz < 14:
						var idx := gz * 20 + gx
						heights[idx] = maxf(0.02, float(heights[idx]) - 0.4)

	# Le lac ne remplit QUE la cuvette (niveau 0.6 < plaine à 1.1) ; la
	# rivière descend du plateau — le dénivelé devient une cascade.
	map["waterBodies"] = [
		{"id": "lac", "kind": "lake", "level": 0.6,
			"area": [[5, 4], [15, 4], [15, 10], [5, 10]]},
		{"id": "riviere", "kind": "river", "width": 1.3, "flow_speed": 0.5,
			"path": [[17, 2.26, 1.5], [17, 2.26, 2.8], [17, 0.66, 3.8],
				[16, 0.35, 5.0], [14.5, 0.2, 6.2]]},
	]

	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	# Le moteur doit calculer pour le VRAI viewport de rendu : sinon le cadrage
	# est établi pour une taille qui n'est pas celle du raster (d'où les
	# débordements « erratiques » malgré un fit correct).
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(10):
		await process_frame
	# Cadrage : fit SYNCHRONE + vérifié (le fit du moteur garantit désormais la
	# carte entièrement visible, axe vertical compris).
	engine._fit_to_view()
	for _i in range(8):
		await process_frame
	print("  [cam] pos=%s visible=%s extent=%s size=%s" % [
		str(engine._camera.position), str(engine._visible_ground_size()),
		str(engine._map_extent), str(engine.size)])

	var water = engine._water_layer
	_assert("shot_two_bodies", water != null and water.get_body_count() == 2,
		"n=%d" % (water.get_body_count() if water != null else -1))
	_assert("shot_active", water != null and water.is_active())

	var img: Image = await _shot(engine, "water_bodies")
	if img != null:
		_assert("shot_not_blank", not _is_blank(img))
	# Deuxième vue : gros plan sur la cascade (validation du shader de chute).
	# La caméra regarde vers −Z : on se place en z POSITIF pour viser la chute
	# (monde ≈ (11.9, 1.05, 2.3)).
	engine._camera.position = Vector3(11.9, 2.6, 5.8)
	engine._camera.rotation_degrees = Vector3(-38.0, 0.0, 0.0)
	await process_frame
	await process_frame
	var fall_img: Image = await _shot(engine, "water_fall")
	if fall_img != null:
		_assert("fall_not_blank", not _is_blank(fall_img))
	if _failed:
		print("water_bodies_shot_test:FAIL")
		quit(1)
		return
	print("water_bodies_shot_test:PASS")
	quit(0)

func _shot(engine: Control, name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = engine.get_viewport().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % name, false)
		return null
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	DirAccess.make_dir_recursive_absolute(COPY_DIR)
	var from := "%s/%s.png" % [OUT_DIR, name]
	var to := "%s/%s.png" % [ProjectSettings.globalize_path(COPY_DIR), name]
	var abs_from := ProjectSettings.globalize_path(from)
	DirAccess.copy_absolute(abs_from, to)
	print("  capture: %s" % to)
	return img

func _is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(w / 2, h / 2)
	for pt in [Vector2i(w / 4, h / 4), Vector2i(3 * w / 4, h / 2), Vector2i(w / 2, 3 * h / 4)]:
		if img.get_pixelv(pt) != first:
			return false
	return true

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
