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
	# de haut ; plongeante, on voit la rive NORD, la mousse de contact ET le
	# haut-fond où la réfraction du lit doit dominer).
	engine._camera.position = Vector3(7.0, 2.5, 6.7)
	engine._camera.rotation_degrees = Vector3(-38.0, 0.0, 0.0)
	for _i in range(3):
		await process_frame
	var lake_img: Image = await _shot(engine, SHOT_NAMES[0])
	if lake_img != null:
		_assert("lake_not_blank", not _is_blank(lake_img))

	# --- A/B RÉFRACTION ÉCRAN (même caméra, lac) ----------------------------
	# 0 = état exact précédent (lit jamais déformé), 1 = lit réfracté dans les
	# hauts-fonds. On capture dans les deux sens pour juger le gain visuel.
	var refr_mats := _refraction_materials(water)
	_assert("refraction_materials", refr_mats.size() >= 2,
		"n=%d" % refr_mats.size())
	_set_refraction(refr_mats, 0.0)
	var lake_refr_off: Image = await _shot(engine, "water_quality_lake_refr_off")
	_set_refraction(refr_mats, 1.0)
	var lake_refr_on: Image = await _shot(engine, "water_quality_lake_refr_on")
	if lake_refr_off != null:
		_assert("lake_refr_off_not_blank", not _is_blank(lake_refr_off))
	if lake_refr_on != null:
		_assert("lake_refr_on_not_blank", not _is_blank(lake_refr_on))
	_assert("refraction_restored",
		refr_mats.size() > 0 and is_equal_approx(
			float((refr_mats[0] as ShaderMaterial)
				.get_shader_parameter("refraction_enabled")), 1.0))

	# Plan rapproché 2 : rivière (lit creusé, courant vers l'aval, rives du
	# ruban) — caméra en aval du bief rectiligne, léger quart pour voir les rives.
	engine._camera.position = Vector3(12.2, 1.3, 3.4)
	engine._camera.rotation_degrees = Vector3(-30.0, 12.0, 0.0)
	for _i in range(3):
		await process_frame
	var river_img: Image = await _shot(engine, SHOT_NAMES[1])
	if river_img != null:
		_assert("river_not_blank", not _is_blank(river_img))

	# --- A/B RÉFRACTION ÉCRAN (même caméra, rivière) ------------------------
	_set_refraction(refr_mats, 0.0)
	var river_refr_off: Image = await _shot(engine, "water_quality_river_refr_off")
	_set_refraction(refr_mats, 1.0)
	var river_refr_on: Image = await _shot(engine, "water_quality_river_refr_on")
	if river_refr_off != null:
		_assert("river_refr_off_not_blank", not _is_blank(river_refr_off))
	if river_refr_on != null:
		_assert("river_refr_on_not_blank", not _is_blank(river_refr_on))

	# =====================================================================
	# FINITIONS CS2 (task-4) — ces sections ÉTENDENT la validation visuelle
	# existante sans la modifier : chaque finition est capturée off/on et le
	# gain est mesuré (diff moyenne sur une zone utile), pas seulement regardé.
	# =====================================================================

	# --- 2) ÉCLAIRAGE DOUBLE DU LIT RÉFRACTÉ : A/B `bed_ambient_lift` ------
	# Retour au plan rapproché du lac (hauts-fonds où le lit réfracté domine).
	engine._camera.position = Vector3(7.0, 2.5, 6.7)
	engine._camera.rotation_degrees = Vector3(-38.0, 0.0, 0.0)
	for _i in range(3):
		await process_frame
	var bed_mats := _bed_materials(water, engine)
	_assert("bed_materials_water_and_terrain", bed_mats.size() >= 2,
		"n=%d" % bed_mats.size())
	_set_bed(bed_mats, 0.0)
	var bed_off: Image = await _shot(engine, "cs2_finitions_bed_off")
	_set_bed(bed_mats, 1.0)
	var bed_on: Image = await _shot(engine, "cs2_finitions_bed_on")
	if bed_off != null and bed_on != null:
		_assert("bed_off_not_blank", not _is_blank(bed_off))
		# Zone du lac (le fond plat à corriger) : bande centrale de l'image.
		var bed_d := _mean_diff(
			_crop(bed_off, 0.10, 0.30, 0.90, 0.92),
			_crop(bed_on, 0.10, 0.30, 0.90, 0.92))
		print("  [diff] éclairage double du lit off/on = %.5f" % bed_d)
		_assert("bed_double_light_visible", bed_d > BED_DIFF_MIN,
			"diff=%.5f" % bed_d)
	_assert("bed_restored",
		_all_bed(bed_mats, 1.0))

	# =====================================================================
	# 1) BRUME DE PIED DE CASCADE : A/B `mist_enabled` (priorité 1)
	# =====================================================================
	# Carte ESCALIER dédiée (mêmes données que le référentiel des cascades :
	# 3 chutes) : la brume se juge sur le pied d'un ressaut.
	engine.configure(_make_staircase_map(md), [], [], [], [], [], false, true,
		{"mode": "select"}, {}, "")
	for _i in range(12):
		await process_frame
	engine._fit_to_view()
	for _i in range(8):
		await process_frame
	var cascade = engine._water_layer
	_assert("mist_cascade_water", cascade != null and cascade.is_active())
	_assert("mist_cascade_falls",
		cascade != null and cascade.get_fall_count() >= 2,
		"chutes=%d" % (cascade.get_fall_count() if cascade != null else -1))
	_assert("mist_cascade_nodes",
		cascade != null and cascade.get_mist_count() >= 1,
		"n=%d" % (cascade.get_mist_count() if cascade != null else -1))
	if cascade != null and cascade.get_mist_count() >= 1:
		# Pied de la chute du milieu, cadré de face depuis l'aval (même point
		# de vue que `staircase_cascade_shot_test`).
		engine._camera.position = Vector3(7.0, 5.0, 12.2)
		engine._camera.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		for _i in range(4):
			await process_frame
		cascade.set_mist_enabled(false)
		var mist_off: Image = await _shot(engine, "cs2_finitions_mist_off")
		cascade.set_mist_enabled(true)
		var mist_on: Image = await _shot(engine, "cs2_finitions_mist_on")
		if mist_off != null and mist_on != null:
			_assert("mist_off_not_blank", not _is_blank(mist_off))
			# La brume s'accroche au pied de la chute : bande basse de l'image.
			var mist_d := _mean_diff(
				_crop(mist_off, 0.05, 0.45, 0.95, 0.98),
				_crop(mist_on, 0.05, 0.45, 0.95, 0.98))
			print("  [diff] brume de pied off/on = %.5f" % mist_d)
			_assert("mist_visible", mist_d > MIST_DIFF_MIN,
				"diff=%.5f" % mist_d)
			# Budget borné : 2 quads par chute, un seul draw call de brume.
			print("  [perf] brume : %d chutes, %d quads, %d nœud(s), 1 draw call"
				% [cascade.get_fall_count(), cascade.get_mist_quad_count(),
					cascade.get_mist_count()])
			# Temps de frame INDICATIF avec/sans brume (fenêtre cachée : la
			# mesure peut être bornée par la vsync — on la publie telle quelle,
			# sans assertion de performance).
			cascade.set_mist_enabled(false)
			var t0 := Time.get_ticks_usec()
			for _i in range(24):
				await process_frame
			var ms_off := float(Time.get_ticks_usec() - t0) / 24000.0
			cascade.set_mist_enabled(true)
			t0 = Time.get_ticks_usec()
			for _i in range(24):
				await process_frame
			var ms_on := float(Time.get_ticks_usec() - t0) / 24000.0
			print("  [perf] temps de frame brume off=%.2f ms on=%.2f ms (indicatif)"
				% [ms_off, ms_on])
		# --- 3) NEZ DE RUBAN VUS DE TRÈS HAUT : A/B `tip_soften_distance` --
		# Même carte, vue TRÈS HAUTE (dézoom fort) : l'empreinte écran d'un
		# pixel devient grande, les pointes du ruban s'éteignent. On capture
		# un état « off » DEUX fois pour mesurer le bruit d'animation et
		# prouver que le signal du flag le dépasse.
		# Caméra remise dans l'axe du style (tilt plongeant) AVANT le dézoom :
		# la vue « de très haut » est une vue plongeante, pas un plan rasant.
		# Zoom minimal du moteur (0.25) = carte entière vue de très haut.
		engine._camera.rotation_degrees = Vector3(-50.0, 0.0, 0.0)
		engine.zoom = 0.25
		engine._update_ortho_size()
		engine._center_focus_on(Vector2(10.0 * float(engine._cell_size),
			8.0 * float(engine._cell_size)))
		for _i in range(8):
			await process_frame
		# La brume est une AUTRE finition : on la coupe pendant l'A/B des
		# pointes pour que le bruit mesuré ne soit que l'animation de l'eau.
		# `Engine.time_scale = 0` fige l'animation (TIME des shaders) : le
		# bruit d'animation tombe et le signal du flag devient mesurable.
		Engine.time_scale = 0.0
		cascade.set_mist_enabled(false)
		cascade.set_tip_soften(0.0)
		var tip_off_a: Image = await _shot(engine, "cs2_finitions_tip_off")
		var tip_off_b: Image = await _shot(engine, "cs2_finitions_tip_off_bis")
		cascade.set_tip_soften(1.0)
		var tip_on: Image = await _shot(engine, "cs2_finitions_tip_on")
		cascade.set_mist_enabled(true)
		cascade.set_tip_soften(1.0)
		Engine.time_scale = 1.0
		if tip_off_a != null and tip_off_b != null and tip_on != null:
			# Zones des DEUX nez du ruban (début nord, fin sud du tracé),
			# projetées à l'écran pour ne mesurer que la pointe.
			var nose_rects := _nose_crops(engine, tip_off_a)
			print("  [pointe] crops=%s" % str(nose_rects))
			var noise := 0.0
			var tip_signal := 0.0
			for r in nose_rects:
				var n_one := _mean_diff(
					tip_off_a.get_region(r), tip_off_b.get_region(r))
				var s_one := _mean_diff(
					tip_off_a.get_region(r), tip_on.get_region(r))
				print("  [pointe] nez %s : bruit=%.5f signal=%.5f"
					% [str(r), n_one, s_one])
				noise = maxf(noise, n_one)
				tip_signal = maxf(tip_signal, s_one)
			print("  [diff] nez de ruban (bruit=%.5f, off/on=%.5f)"
				% [noise, tip_signal])
			_assert("tip_effect_beats_noise",
				tip_signal > noise * 1.6 + 0.0008,
				"bruit=%.5f signal=%.5f" % [noise, tip_signal])
			_assert("tip_effect_measurable", tip_signal > 0.004,
				"signal=%.5f" % tip_signal)

	if _failed:
		print("water_quality_shot_test:FAIL")
		quit(1)
		return
	print("water_quality_shot_test:PASS")
	quit(0)

const BED_DIFF_MIN := 0.0015
const MIST_DIFF_MIN := 0.0010


## Matériaux de SURFACE d'eau portant la réfraction écran (`refraction_enabled`)
## — les matériaux de chute n'ont pas l'uniform et sont ignorés.
func _refraction_materials(water) -> Array:
	var mats: Array = []
	if water == null:
		return mats
	for node in water._body_nodes:
		if node == null or not is_instance_valid(node):
			continue
		var candidates: Array = []
		if node.material_override is ShaderMaterial:
			candidates.append(node.material_override)
		if node.mesh is ArrayMesh:
			for si in range((node.mesh as ArrayMesh).get_surface_count()):
				var sm = (node.mesh as ArrayMesh).surface_get_material(si)
				if sm is ShaderMaterial:
					candidates.append(sm)
		for m in candidates:
			if (m as ShaderMaterial).get_shader_parameter("refraction_enabled") != null \
					and not mats.has(m):
				mats.append(m)
	return mats

## Bascule A/B de la réfraction écran (0 = état exact précédent, 1 = activée).
func _set_refraction(mats: Array, on: float) -> void:
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("refraction_enabled", on)

## Matériaux portant l'éclairage double du lit : matériaux de surface d'eau
## (`bed_ambient_lift`) + matériau de TERRAIN (le lit lui-même, reçu par
## réfraction écran). Les matériaux de chute (sans l'uniform) sont ignorés.
func _bed_materials(water, engine: Control) -> Array:
	var mats: Array = []
	if water != null:
		for m in _refraction_materials(water):
			if (m as ShaderMaterial).get_shader_parameter("bed_ambient_lift") != null:
				mats.append(m)
	var ground_mat = engine._ground._mesh_instance.material_override
	if ground_mat is ShaderMaterial \
			and (ground_mat as ShaderMaterial).get_shader_parameter("bed_ambient_lift") != null:
		mats.append(ground_mat)
	return mats

## Bascule A/B de l'éclairage double du lit (0 = état exact précédent).
func _set_bed(mats: Array, amount: float) -> void:
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("bed_ambient_lift", amount)

func _all_bed(mats: Array, expected: float) -> bool:
	if mats.is_empty():
		return false
	for m in mats:
		if not is_equal_approx(
				float((m as ShaderMaterial).get_shader_parameter("bed_ambient_lift")),
				expected):
			return false
	return true

## Rectangle d'une image donné en fractions (0..1) de sa taille.
func _crop(img: Image, x0f: float, y0f: float, x1f: float, y1f: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := clampi(int(float(w) * x0f), 0, w - 1)
	var y0 := clampi(int(float(h) * y0f), 0, h - 1)
	var x1 := clampi(int(float(w) * x1f), x0 + 1, w)
	var y1 := clampi(int(float(h) * y1f), y0 + 1, h)
	return img.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))

## Différence moyenne RGB (0..1) entre deux images de même taille.
func _mean_diff(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 1.0
	if a.get_size() != b.get_size():
		return 1.0
	var w := a.get_width()
	var h := a.get_height()
	var step := maxi(1, int(float(w) / 120.0))
	var total := 0.0
	var count := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(maxi(1, count))

## Rectangles écran des DEUX nez du ruban de l'escalier (début nord / fin sud)
## pour ne mesurer le flag `tip_soften_distance` que sur les pointes.
func _nose_crops(engine: Control, img: Image) -> Array:
	var cell := float(engine._cell_size)
	var cam: Camera3D = engine._camera
	var vis := cam.get_viewport().get_visible_rect().size
	var k := Vector2(
		float(img.get_width()) / maxf(vis.x, 1.0),
		float(img.get_height()) / maxf(vis.y, 1.0))
	var rects: Array = []
	# Hauteur d'eau aux extrémités (cellules) : haut de l'escalier / bas.
	var noses: Array = [
		Vector3(10.0 * cell, 12.6 * cell, 0.5 * cell),
		Vector3(10.0 * cell, 0.4 * cell, 15.2 * cell),
	]
	var half := Vector2i(int(float(img.get_width()) * 0.022),
		int(float(img.get_height()) * 0.048))
	for wp in noses:
		var p: Vector2 = cam.unproject_position(wp) * k
		var cx := clampi(int(p.x), 0, img.get_width() - 1)
		var cy := clampi(int(p.y), 0, img.get_height() - 1)
		var x0 := clampi(cx - half.x, 0, img.get_width() - 1)
		var y0 := clampi(cy - half.y, 0, img.get_height() - 1)
		var x1 := clampi(cx + half.x, x0 + 1, img.get_width())
		var y1 := clampi(cy + half.y, y0 + 1, img.get_height())
		rects.append(Rect2i(x0, y0, x1 - x0, y1 - y0))
	return rects

## Carte ESCALIER de validation des cascades (mêmes données que
## `staircase_cascade_shot_test`) : 4 marches de 4 cases, rivière droite.
func _make_staircase_map(md) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Finitions cascades", "general", "local", 20, 16)
	var heights: Array = []
	heights.resize(20 * 16)
	for z in range(16):
		var step := mini(3, int(float(z) / 4.0))
		var h := 4.0 * float(3 - step)
		for x in range(20):
			heights[z * 20 + x] = h
	map["terrainHeights"] = heights
	map["vegetationDensity"] = 0.25
	map["waterBodies"] = [
		{"id": "riviere", "kind": "river", "width": 1.6, "flow_speed": 0.55,
			"depth": 0.35,
			"path": [[10.0, 12.0, 0.5], [10.0, 12.0, 3.4],
				[10.0, 8.0, 4.6], [10.0, 8.0, 7.4],
				[10.0, 4.0, 8.6], [10.0, 4.0, 11.4],
				[10.0, 0.0, 12.6], [10.0, 0.0, 15.2]]},
	]
	return map

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
