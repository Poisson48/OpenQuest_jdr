extends SceneTree

## Validation VISUELLE de la qualité de l'eau (objectif « Cities: Skylines II ») :
## lac dans une cuvette + rivière au lit creusé, cadrés en plan RAPPROCHÉ pour
## juger mousse de rive, micro-vagues et lisibilité du lit.
##
## Les captures sont écrites à la RACINE du dépôt (`docs/screenshots/`) : le
## projet Godot vit dans `game/`, d'où `res://..` plutôt que `res://`.
##
## PASS = `water_quality_shot_test:PASS`.

const OUT_DIR := "user://water_shots"
## Dossier de copie, résolu depuis la racine du dépôt (un niveau au-dessus de
## `res://`, qui pointe sur `game/`).
const COPY_DIR := "docs/screenshots"
const SHOT_NAMES: Array = ["water_quality_lake", "water_quality_river"]

var Engine3DScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		# Capture impossible sans rendu réel : on sort proprement (jamais de
		# fenêtre qui volerait le focus pendant que quelqu'un joue sur le PC).
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Eau qualité", "general", "local", 20, 14)

	# Terrain : plateau amont (z < 3) à 2.2, plaine à 1.1, cuvette du lac.
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
	map["vegetationDensity"] = 0.25
	# Lit de rivière creusé (comme l'outil Eau → Rivière) : la nappe remplit un
	# vrai canal, avec de vraies rives là où le terrain la découpe.
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

	map["waterBodies"] = [
		# Lac : emprise dans la cuvette (la profondeur/la rive viennent du
		# terrain, le maillage est découpé par le masque d'eau).
		{"id": "lac", "kind": "lake", "level": 0.6,
			"area": [[5, 4], [15, 4], [15, 10], [5, 10]]},
		{"id": "riviere", "kind": "river", "width": 1.3, "flow_speed": 0.5,
			"path": [[17, 2.26, 1.5], [17, 2.26, 2.8], [17, 0.66, 3.8],
				[16, 0.35, 5.0], [14.5, 0.2, 6.2]]},
	]

	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(10):
		await process_frame
	engine._fit_to_view()
	for _i in range(8):
		await process_frame

	var water = engine._water_layer
	_assert("quality_water_layer", water != null)
	_assert("quality_two_bodies", water != null and water.get_body_count() == 2,
		"n=%d" % (water.get_body_count() if water != null else -1))
	_assert("quality_active", water != null and water.is_active())
	if water == null:
		print("water_quality_shot_test:FAIL")
		quit(1)
		return

	# Plan rapproché 1 : rive du lac (la caméra regarde vers −Z, l'eau à 0.42
	# de haut ; rasante, on vise la rive NORD pour voir la mousse de contact).
	engine._camera.position = Vector3(7.0, 2.0, 6.6)
	engine._camera.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	for _i in range(3):
		await process_frame
	var lake_img: Image = await _shot(engine, SHOT_NAMES[0])
	if lake_img != null:
		_assert("lake_not_blank", not _is_blank(lake_img))

	# Plan rapproché 2 : rivière (lit creusé, courant vers l'aval, rives du
	# ruban) — caméra en aval du bief rectiligne, léger quart pour voir les rives.
	engine._camera.position = Vector3(12.2, 1.3, 3.4)
	engine._camera.rotation_degrees = Vector3(-30.0, 12.0, 0.0)
	for _i in range(3):
		await process_frame
	var river_img: Image = await _shot(engine, SHOT_NAMES[1])
	if river_img != null:
		_assert("river_not_blank", not _is_blank(river_img))

	if _failed:
		print("water_quality_shot_test:FAIL")
		quit(1)
		return
	print("water_quality_shot_test:PASS")
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
	# Racine du dépôt : `res://` = `game/`, donc `res://..`.
	var root_dir := ProjectSettings.globalize_path("res://..").path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(root_dir)
	var abs_from := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var to := root_dir.path_join("%s.png" % name)
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
