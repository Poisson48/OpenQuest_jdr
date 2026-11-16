extends SceneTree

## Capture A/B du SOCLE DE DIORAMA (finitions « qualité CS2 », task-5).
##
## Vues de validation (fenêtre cachée, GPU réel) :
##  • `slab_quality_off/on` : flag maître — jupe historique vs nouveau socle
##    (strates, arête herbeuse arrondie, raccord terre/AO en pied) ;
##  • `slab_quality_strata_off/on` : option `slab_strata` seule (gros plan) ;
##  • `slab_quality_backdrop_off/on` : fond de plateau (dégradé doux + halo de
##    contact sous l'emprise du socle) ;
##  • `slab_quality_sun_front/back` : le socle RÉAGIT à l'éclairage (deux
##    orientations de soleil) — le preset qualité CS2 en profitera ;
##  • `slab_quality_diorama` / `slab_quality_overview` : vraie carte de démo.
##
## Chaque A/B est mesuré (diff moyenne sur une zone utile), pas seulement
## regardé. PASS = `slab_quality_shot_test:PASS`.

const OUT_DIR := "user://slab_shots"
const COPY_DIR := "docs/screenshots"
const W := 20
const H := 14

## Diff minimale attendue entre jupe legacy et socle (bande de la jupe).
const SLAB_DIFF_MIN := 0.006
## Diff minimale de l'option strates seule.
const STRATA_DIFF_MIN := 0.002
## Diff minimale du fond de plateau (halo + dégradé élargi).
const BACKDROP_DIFF_MIN := 0.0015
## Diff minimale entre deux orientations de soleil (réaction à l'éclairage).
const SUN_DIFF_MIN := 0.0015

## Soleil de validation : rasant depuis le sud-est pour éclairer la paroi du
## socle visible dans les cadrages (et projeter une ombre derrière le plateau).
const SUN_YAW_LIT := 150.0
const SUN_ANGLE := -38.0

var Engine3DScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")

	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	await _configure(engine, _make_map(md))
	var ground = engine._ground
	_assert("slab_ground", ground != null)
	_assert("slab_active", ground != null and ground.is_slab_active())
	var slab_mat: ShaderMaterial = ground.get_slab_material() if ground != null else null
	_assert("slab_material", slab_mat is ShaderMaterial and slab_mat.shader != null)
	if ground == null:
		print("slab_quality_shot_test:FAIL")
		quit(1)
		return
	if slab_mat != null and slab_mat.shader != null:
		_assert("slab_lighting_receives",
			not slab_mat.shader.code.contains("unshaded"))
	var tris := 0
	var slab_mesh: ArrayMesh = ground.get_slab_mesh()
	if slab_mesh != null:
		var arrays := slab_mesh.surface_get_arrays(0)
		tris = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("  [socle] %d sommets, %d triangles, 1 draw call"
		% [ground.get_slab_vertex_count(), tris])

	# --- Vue RASANTE depuis l'extérieur : la jupe/socle occupe le bas de
	# l'image (paroi, pied, ombre du débord et fond derrière).
	await _frame(engine, Vector3(10.0, 3.4, 21.5), Vector3(-13.0, 0.0, 0.0))

	# --- A/B MAÎTRE : jupe historique vs socle -----------------------------
	ground.set_slab_finitions(false)
	var off_img: Image = await _shot(engine, "slab_quality_off")
	ground.set_slab_finitions(true)
	var on_img: Image = await _shot(engine, "slab_quality_on")
	if off_img != null and on_img != null:
		_assert("slab_off_not_blank", not _is_blank(off_img))
		_assert("slab_on_not_blank", not _is_blank(on_img))
		var d := _mean_diff(
			_crop(off_img, 0.02, 0.40, 0.98, 0.98),
			_crop(on_img, 0.02, 0.40, 0.98, 0.98))
		print("  [diff] socle off/on (jupe) = %.5f" % d)
		_assert("slab_visible", d > SLAB_DIFF_MIN, "diff=%.5f" % d)
	# Coût indicatif (fenêtre cachée) : la jupe legacy (1 mesh, 2 matériaux de
	# vertex colors) vs le socle (1 mesh, 1 draw call, 1 368 triangles).
	ground.set_slab_finitions(false)
	var t0 := Time.get_ticks_usec()
	for _i in range(24):
		await process_frame
	var ms_off := float(Time.get_ticks_usec() - t0) / 24000.0
	ground.set_slab_finitions(true)
	t0 = Time.get_ticks_usec()
	for _i in range(24):
		await process_frame
	var ms_on := float(Time.get_ticks_usec() - t0) / 24000.0
	print("  [perf] temps de frame socle off=%.2f ms on=%.2f ms (indicatif)"
		% [ms_off, ms_on])

	# --- A/B OPTION STRATES (gros plan sur la paroi) -----------------------
	await _frame(engine, Vector3(10.0, 1.6, 18.6), Vector3(-6.0, 0.0, 0.0))
	ground.set_slab_strata(0.0)
	var strata_off: Image = await _shot(engine, "slab_quality_strata_off")
	ground.set_slab_strata(1.0)
	var strata_on: Image = await _shot(engine, "slab_quality_strata_on")
	if strata_off != null and strata_on != null:
		_assert("strata_off_not_blank", not _is_blank(strata_off))
		var sd := _mean_diff(
			_crop(strata_off, 0.05, 0.30, 0.95, 0.98),
			_crop(strata_on, 0.05, 0.30, 0.95, 0.98))
		print("  [diff] option strates off/on = %.5f" % sd)
		_assert("strata_visible", sd > STRATA_DIFF_MIN, "diff=%.5f" % sd)

	# --- A/B FOND DE PLATEAU : contact + dégradé doux ----------------------
	# Caméra haute et en recul : le fond (plan sous la dalle) occupe la moitié
	# de l'image et le halo de contact fait le tour de l'emprise du socle.
	# Les ombres du soleil sont coupées UNIQUEMENT ici pour isoler la finition
	# de fond (A/B déterministe, aucun autre réglage de scène modifié).
	var sun = engine._sun
	var shadows_were: bool = false
	if sun != null:
		shadows_were = bool(sun.shadow_enabled)
	if sun != null:
		sun.shadow_enabled = false
	await _frame(engine, Vector3(10.0, 15.0, 25.0), Vector3(-32.0, 0.0, 0.0))
	var backdrop = engine._backdrop_layer
	_assert("backdrop_layer", backdrop != null)
	if backdrop != null:
		backdrop.set_slab_soften(0.0)
		var bd_off: Image = await _shot(engine, "slab_quality_backdrop_off")
		backdrop.set_slab_soften(1.0)
		var bd_on: Image = await _shot(engine, "slab_quality_backdrop_on")
		if bd_off != null and bd_on != null:
			_assert("backdrop_off_not_blank", not _is_blank(bd_off))
			# Toute la zone utile : le fond et son halo de contact.
			var bd := _mean_diff(
				_crop(bd_off, 0.02, 0.06, 0.98, 0.98),
				_crop(bd_on, 0.02, 0.06, 0.98, 0.98))
			print("  [diff] fond de plateau off/on = %.5f" % bd)
			_assert("backdrop_visible", bd > BACKDROP_DIFF_MIN, "diff=%.5f" % bd)
	if sun != null:
		sun.shadow_enabled = shadows_were

	# --- RÉACTION À L'ÉCLAIRAGE : deux orientations de soleil --------------
	# Le socle est ÉCLAIRÉ (spatial) : paroi face au soleil vs paroi à dos ne
	# rendent pas la même chose — c'est ce que le preset qualité CS2 exploite.
	var front_map: Dictionary = _make_map(md)
	front_map["lighting"] = {"sunYaw": SUN_YAW_LIT, "sunAngle": SUN_ANGLE}
	await _configure(engine, front_map)
	await _frame(engine, Vector3(10.0, 2.2, 19.0), Vector3(-9.0, 0.0, 0.0))
	var sun_front: Image = await _shot(engine, "slab_quality_sun_front")
	var back_map: Dictionary = _make_map(md)
	back_map["lighting"] = {"sunYaw": SUN_YAW_LIT - 180.0, "sunAngle": SUN_ANGLE}
	await _configure(engine, back_map)
	await _frame(engine, Vector3(10.0, 2.2, 19.0), Vector3(-9.0, 0.0, 0.0))
	var sun_back: Image = await _shot(engine, "slab_quality_sun_back")
	if sun_front != null and sun_back != null:
		var light_d := _mean_diff(
			_crop(sun_front, 0.05, 0.35, 0.95, 0.98),
			_crop(sun_back, 0.05, 0.35, 0.95, 0.98))
		print("  [diff] socle éclairé (soleil face/dos) = %.5f" % light_d)
		_assert("slab_reacts_to_light", light_d > SUN_DIFF_MIN,
			"diff=%.5f" % light_d)

	# --- PRESET QUALITÉ CS2 (cinema) : le socle y réagit (ombres/AO) -------
	# Même scène, même caméra que le A/B soleil, mais avec le preset qualité
	# opt-in du chantier CS2 : le socle est ÉCLAIRÉ (spatial), il reçoit donc
	# les ombres douces et l'AO de la scène — la finition ne le fige pas.
	var cinema_map: Dictionary = _make_map(md)
	cinema_map["qualityPreset"] = "cinema"
	await _configure(engine, cinema_map)
	await _frame(engine, Vector3(10.0, 2.2, 19.0), Vector3(-9.0, 0.0, 0.0))
	var cinema: Image = await _shot(engine, "slab_quality_cinema")
	if cinema != null:
		_assert("cinema_not_blank", not _is_blank(cinema))
		if sun_front != null:
			var cd := _mean_diff(
				_crop(cinema, 0.02, 0.20, 0.98, 0.98),
				_crop(sun_front, 0.02, 0.20, 0.98, 0.98))
			print("  [diff] preset classique/cinema (socle éclairé) = %.5f" % cd)
			_assert("slab_stable_with_quality_preset", cd > 0.0005,
				"diff=%.5f" % cd)

	# --- CARTE RÉELLE DE DÉMONSTRATION (diorama) ---------------------------
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	_assert("diorama_boot", boot != null)
	if boot != null:
		var demo: Dictionary = boot.build_demo(md)
		var village: Dictionary = demo.get("map", {})
		# Même soleil rasant que la scène de validation : la paroi du socle
		# est lisible sur la carte réelle (les autres réglages de la démo sont
		# conservés).
		village["lighting"] = {"sunYaw": 160.0, "sunAngle": -32.0}
		await _configure(engine, village)
		var ext: Vector2 = engine._map_extent
		# Vue « bord de diorama » : la rangée sud du village + le socle.
		await _frame(engine, Vector3(ext.x * 0.5, 9.0, ext.y + 8.0),
			Vector3(-20.0, 0.0, 0.0), 12)
		var diorama: Image = await _shot(engine, "slab_quality_diorama")
		if diorama != null:
			_assert("diorama_not_blank", not _is_blank(diorama))
		# Vue d'ensemble en recul : le plateau entier, son arête et son socle.
		await _frame(engine, Vector3(ext.x * 0.5, 15.0, ext.y + 18.0),
			Vector3(-24.0, 0.0, 0.0), 10)
		var overview: Image = await _shot(engine, "slab_quality_overview")
		if overview != null:
			_assert("overview_not_blank", not _is_blank(overview))

	if _failed:
		print("slab_quality_shot_test:FAIL")
		quit(1)
		return
	print("slab_quality_shot_test:PASS")
	quit(0)

# ===========================================================================
# Mise en scène
# ===========================================================================

func _configure(engine: Control, map: Dictionary) -> void:
	engine.configure(map, [], [], [], [], [], false, true,
		{"mode": "select"}, {}, "")
	for _i in range(16):
		await process_frame

## Pose la caméra APRÈS les cadrages différés du moteur (sinon le fit automatique
## écrase la position) puis laisse le rendu se stabiliser.
func _frame(engine: Control, pos: Vector3, rot: Vector3, settle: int = 8) -> void:
	engine._camera.position = pos
	engine._camera.rotation_degrees = rot
	for _i in range(settle):
		await process_frame

# ===========================================================================
# Données de validation : carte de diorama avec relief et matières
# ===========================================================================

func _make_map(md) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Socle diorama", "general", "local", W, H)
	map["vegetationDensity"] = 0.0
	map["fogEnabled"] = false
	map["waterBodies"] = []
	map["lighting"] = {"sunYaw": SUN_YAW_LIT, "sunAngle": SUN_ANGLE}
	var heights: Array = []
	heights.resize(W * H)
	var mats: Array = []
	mats.resize(W * H)
	for z in range(H):
		for x in range(W):
			var h := 0.75
			# Colline douce au nord-ouest + dépression au sud-est : la jupe
			# suit le bord et le socle offre un profil varié.
			var dx := float(x) - 7.0
			var dz := float(z) - 5.5
			var hill := maxf(0.0, 2.6 - sqrt(dx * dx + dz * dz) * 0.62)
			h += hill
			var dx2 := float(x) - 14.5
			var dz2 := float(z) - 9.5
			var dip := maxf(0.0, 1.3 - sqrt(dx2 * dx2 + dz2 * dz2) * 0.55)
			h -= dip
			heights[z * W + x] = maxf(0.0, h)
			# Matières : herbe par défaut, roche sur la colline, terre autour.
			var m := 0
			if hill > 1.1:
				m = 2
			elif hill > 0.35 and hill <= 1.1:
				m = 1
			mats[z * W + x] = m
	map["terrainHeights"] = heights
	map["terrainMaterials"] = mats
	return map

# ===========================================================================
# Captures et mesures (patron commun des tests de capture du chantier)
# ===========================================================================

func _shot(engine: Control, name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = engine.get_viewport().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % name, false)
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var abs_from := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(abs_from)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var to := copy_dir.path_join("%s.png" % name)
	DirAccess.copy_absolute(abs_from, to)
	print("  capture: %s" % to)
	return img

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
	var step := maxi(1, int(float(w) / 140.0))
	var total := 0.0
	var count := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / float(maxi(1, count))

func _is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(w / 2, h / 2)
	for pt in [Vector2i(w / 4, h / 4), Vector2i(3 * w / 4, h / 2),
			Vector2i(w / 2, 3 * h / 4)]:
		if img.get_pixelv(pt) != first:
			return false
	return true

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
