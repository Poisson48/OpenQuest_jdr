extends SceneTree

## Validation VISUELLE de la BRUME ATMOSPHÉRIQUE (distance + hauteur),
## méthode Cities: Skylines II : les objets lointains se fondent doucement
## dans une brume colorée (perspective aérienne), sans écraser la lisibilité
## en vue de dessus.
##
## A/B RÉVERSIBLE : chaque vue est capturée brume OFF puis ON avec la MÊME
## caméra (`set_atmospheric_fog_enabled`) :
##   • la zone proche (< 8 unités caméra) ne reçoit AUCUNE brume de
##     profondeur (`fog_depth_begin ≥ 8`) — seul subsiste le minime voile de
##     la brume de hauteur (brume de creux, < ~3 %) ;
##   • la zone lointaine (bord du plateau, montagne, fond de plateau) doit se
##     voiler nettement sans blanchir le centre de la carte.
##
## Scènes :
##   1. `fog_quality_overview_*`  — vue d'ensemble inclinée (montagne au fond,
##      lac au milieu) ;
##   2. `fog_quality_distance_*`  — plongée rasante : c'est LA lecture de
##      profondeur (proche net → loin voilé) ;
##   3. `fog_quality_closeup_*`   — gros plan (< 8 unités) : proche net,
##      voile de creux minimal, lecture de profondeur intacte ;
##   4. `fog_quality_sky_*`       — preset Tiny Glade + brume forcée par
##      `map_data["atmosphericFog"]` : le ciel, le fond de plateau et l'eau
##      profitent aussi de la brume.
##
## Les captures sont écrites à la RACINE du dépôt (`docs/screenshots/`) : le
## projet Godot vit dans `game/`, d'où `res://..` plutôt que `res://`.
##
## PASS = `fog_quality_shot_test:PASS`.

## Résolution de la grille de capture (comme les shots terrain).
const W := 26
const H := 18
## Relief : plaine douce, plateau lointain (z petit) et montagne au fond.
const PLAIN_H := 0.45
const PLATEAU_H := 2.2
const PLATEAU_Z := 3.5
const MOUNTAIN_X := 16.0
const MOUNTAIN_Z := 4.0
const MOUNTAIN_H := 6.2
const MOUNTAIN_SLOPE := 1.15
## Lac de plaine (montre l'eau dans la brume).
const LAKE_AREA := [[4.0, 6.5], [10.0, 6.5], [10.0, 10.5], [4.0, 10.5]]
const LAKE_LEVEL := 0.5
## Seuils de différence moyenne (0..1) A/B par zone.
const DIFF_MIN_FAR := 0.004     # zone lointaine : la brume doit se voir
## Zone proche (< 8 unités) : AUCUNE brume de profondeur (fog_depth_begin ≥ 8,
## vérifié sur les propriétés) — seul subsiste le minime voile de la brume de
## HAUTEUR (~2 %, brume de creux, composante demandée par la spec). On exige
## donc un diff faible ET très inférieur au lointain de la même vue.
const SAME_MAX_NEAR := 0.012
const NEAR_FAR_RATIO := 0.35

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

	var map: Dictionary = _make_fog_map(md)
	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(12):
		await process_frame

	# --- Configuration de la brume (réglages du moteur) --------------------
	var env: Environment = engine._world_env.environment
	_assert("fog_env_present", env != null)
	if env == null:
		print("fog_quality_shot_test:FAIL")
		quit(1)
		return
	_assert("fog_enabled", env.fog_enabled)
	_assert("fog_depth_mode", env.fog_mode == Environment.FOG_MODE_DEPTH)
	_assert("fog_density_intensity",
		env.fog_density > 0.0 and env.fog_density <= 1.0,
		"density=%f" % env.fog_density)
	_assert("fog_depth_begin_min", env.fog_depth_begin >= 8.0,
		"begin=%f" % env.fog_depth_begin)
	_assert("fog_depth_band", env.fog_depth_end > env.fog_depth_begin,
		"begin=%f end=%f" % [env.fog_depth_begin, env.fog_depth_end])
	_assert("fog_height_active", absf(env.fog_height_density) >= 0.0001,
		"height=%f heightDensity=%f" % [env.fog_height, env.fog_height_density])
	# Isolation : le WorldEnvironment vit dans le monde 3D de la CARTE
	# (SubViewport dédié), jamais à la racine — hub/session non affectés.
	_assert("fog_world_env_isolated",
		engine._world_env.get_parent() == engine._viewport
		and engine._world_env.get_parent() != get_root())

	# --- A/B réVERSIBLE (propriétés) : off = rendu d'origine strict --------
	engine.set_atmospheric_fog_enabled(false)
	var env_off: Environment = engine._world_env.environment
	_assert("ab_off_exponential",
		env_off.fog_mode == Environment.FOG_MODE_EXPONENTIAL)
	_assert("ab_off_no_height", env_off.fog_height_density == 0.0)
	_assert("ab_off_preset_fog", not env_off.fog_enabled,
		"density=%f" % env_off.fog_density)
	engine.set_atmospheric_fog_enabled(true)
	var env_on: Environment = engine._world_env.environment
	_assert("ab_on_restored",
		env_on.fog_enabled and env_on.fog_mode == Environment.FOG_MODE_DEPTH)

	# --- 1. Vue d'ensemble inclinée ---------------------------------------
	engine._fit_to_view()
	for _i in range(8):
		await process_frame
	engine.sync_atmospheric_fog()
	var overview_off: Image = await _shot_ab(engine, false, "fog_quality_overview_off")
	var overview_on: Image = await _shot_ab(engine, true, "fog_quality_overview_on")
	if overview_off != null and overview_on != null:
		_assert("overview_not_blank", not _is_blank(overview_on))
		var d_far := _mean_diff(
			_band(overview_off, 0.0, 0.35), _band(overview_on, 0.0, 0.35))
		print("  [diff] overview lointain A/B = %.4f" % d_far)
		_assert("overview_far_hazed", d_far > DIFF_MIN_FAR, "diff=%.4f" % d_far)

	# --- 2. Plongée rasante (lecture de profondeur) ------------------------
	engine._camera.position = Vector3(9.0, 3.0, 13.5)
	engine._camera.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	engine.zoom = 2.2
	engine._update_ortho_size()
	for _i in range(8):
		await process_frame
	var distance_off: Image = await _shot_ab(engine, false, "fog_quality_distance_off")
	var distance_on: Image = await _shot_ab(engine, true, "fog_quality_distance_on")
	if distance_off != null and distance_on != null:
		_assert("distance_not_blank", not _is_blank(distance_on))
		var d_far := _mean_diff(
			_band(distance_off, 0.0, 0.40), _band(distance_on, 0.0, 0.40))
		print("  [diff] distance lointain A/B = %.4f" % d_far)
		_assert("distance_far_hazed", d_far > DIFF_MIN_FAR, "diff=%.4f" % d_far)

	# --- 3. Gros plan < 8 unités : proche net, lointain voilé --------------
	# Caméra posée sur la plaine AVANT (hors cuvette du lac : pas d'eau
	# animée dans le cadre), montagne lointaine dans le haut du cadre :
	# le bas du cadre (< 8 unités) ne doit pas bouger d'un pixel.
	engine._camera.position = Vector3(16.5, 2.2, 14.0)
	engine._camera.rotation_degrees = Vector3(-28.0, 0.0, 0.0)
	engine.zoom = 3.2
	engine._update_ortho_size()
	for _i in range(8):
		await process_frame
	var closeup_off: Image = await _shot_ab(engine, false, "fog_quality_closeup_off")
	var closeup_on: Image = await _shot_ab(engine, true, "fog_quality_closeup_on")
	if closeup_off != null and closeup_on != null:
		_assert("closeup_not_blank", not _is_blank(closeup_on))
		# Zone proche = herbe du coin bas-gauche (2-6 unités caméra, hors
		# bord de carte/fond de plateau qui, lui, se voile LÉGITIMEMENT en
		# profondeur) : aucun voile de profondeur ne doit y apparaître.
		var d_near := _mean_diff(
			_crop(closeup_off, 0.05, 0.70, 0.55, 1.0),
			_crop(closeup_on, 0.05, 0.70, 0.55, 1.0))
		var d_far := _mean_diff(
			_band(closeup_off, 0.0, 0.30), _band(closeup_on, 0.0, 0.30))
		print("  [diff] closeup proche A/B = %.4f  lointain = %.4f" % [d_near, d_far])
		_assert("closeup_near_clear", d_near < SAME_MAX_NEAR, "diff=%.4f" % d_near)
		_assert("closeup_reads_depth", d_far > DIFF_MIN_FAR and d_near < d_far * NEAR_FAR_RATIO,
			"near=%.4f far=%.4f" % [d_near, d_far])

	# --- 4. Ciel + fond de plateau + eau (Tiny Glade, brume forcée) --------
	var sky_map: Dictionary = _make_fog_map(md)
	var sky_light: Dictionary = md.get_lighting_config(sky_map)
	sky_light["preset"] = "tiny_glade"
	sky_map["lighting"] = sky_light
	# Tiny Glade garde sa brume réglée à la main par défaut : la brume
	# atmosphérique est forcée ici pour vérifier ciel/backdrop/eau.
	sky_map["atmosphericFog"] = {"enabled": true}
	engine.configure(sky_map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(10):
		await process_frame
	_assert("sky_active", engine.is_sky_active())
	engine._fit_to_view()
	for _i in range(6):
		await process_frame
	engine.sync_atmospheric_fog()
	var sky_off: Image = await _shot_ab(engine, false, "fog_quality_sky_off")
	var sky_on: Image = await _shot_ab(engine, true, "fog_quality_sky_on")
	if sky_off != null and sky_on != null:
		_assert("sky_not_blank", not _is_blank(sky_on))
		var d_far := _mean_diff(
			_band(sky_off, 0.0, 0.35), _band(sky_on, 0.0, 0.35))
		print("  [diff] ciel/backdrop A/B = %.4f" % d_far)
		_assert("sky_far_hazed", d_far > DIFF_MIN_FAR, "diff=%.4f" % d_far)

	if _failed:
		print("fog_quality_shot_test:FAIL")
		quit(1)
		return
	print("fog_quality_shot_test:PASS")
	quit(0)

# ===========================================================================
# Scène de capture
# ===========================================================================

## Carte de brume : plaine douce, plateau LOINTAIN (z petit) et montagne au
## fond, un lac de plaine au milieu — la profondeur se lit d'un coup d'œil.
func _make_fog_map(md) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Brume atmosphérique", "general", "local", W, H)
	map["vegetationDensity"] = 0.0
	map["waterBodies"] = [
		{"id": "lac_brume", "kind": "lake", "level": LAKE_LEVEL, "area": LAKE_AREA},
	]
	map["terrainHeights"] = _fog_heights()
	return map

func _fog_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for z in range(H):
		for x in range(W):
			var h := PLAIN_H
			# Plateau lointain (bord haut de l'écran), frontière ondulée.
			var plateau_edge := PLATEAU_Z + _noise2(float(x) * 0.5, 0.0) * 1.2
			if float(z) < plateau_edge:
				h = PLATEAU_H + _noise2(float(x) * 0.8, float(z) * 0.8) * 0.3
			# Montagne au fond (sur le plateau) : cône irrégulier.
			var dx := float(x) - MOUNTAIN_X
			var dz := float(z) - MOUNTAIN_Z
			var d := sqrt(dx * dx + dz * dz)
			var cone := maxf(0.0, MOUNTAIN_H - d * MOUNTAIN_SLOPE)
			var rough := _noise2(float(x) * 0.6, float(z) * 0.6) * 0.9 \
				+ _noise2(float(x) * 1.3 + 7.0, float(z) * 1.3) * 0.4
			h = maxf(h, PLATEAU_H + cone + rough * smoothstep(0.0, 2.0, cone))
			# Cuvette du lac de plaine (berges douces).
			var lake := _lake_depth(float(x), float(z))
			if lake < h:
				h = maxf(0.0, lake)
			heights[z * W + x] = maxf(0.0, h)
	return heights

## Cuve du lac : fond plat au centre, remontée douce vers les berges.
## Hors du lac : aucune contrainte (le relief est conservé tel quel).
func _lake_depth(x: float, z: float) -> float:
	var cx := (LAKE_AREA[0][0] + LAKE_AREA[2][0]) * 0.5
	var cz := (LAKE_AREA[0][1] + LAKE_AREA[2][1]) * 0.5
	var rx := (LAKE_AREA[2][0] - LAKE_AREA[0][0]) * 0.5
	var rz := (LAKE_AREA[2][1] - LAKE_AREA[0][1]) * 0.5
	var ex := absf(x - cx) / maxf(rx, 0.001)
	var ez := absf(z - cz) / maxf(rz, 0.001)
	var r := maxf(ex, ez)
	if r >= 1.0:
		return 1000.0
	return LAKE_LEVEL - 0.55 + smoothstep(0.75, 1.0, r) * 0.65

## Bruit de valeur déterministe (-0.5..0.5) pour des frontières organiques.
func _noise2(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return (v - floorf(v)) - 0.5

# ===========================================================================
# Captures A/B
# ===========================================================================

## Capture avec la brume dans l'état demandé, puis RESTAURE la brume active
## (les captures finissent toujours en configuration normale).
func _shot_ab(engine: Control, atmos_on: bool, shot_name: String) -> Image:
	engine.set_atmospheric_fog_enabled(atmos_on)
	for _i in range(4):
		await process_frame
	return await _shot(engine, shot_name)

func _shot(engine: Control, shot_name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = engine.get_viewport().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % shot_name, false)
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s.png" % shot_name)
	img.save_png(out)
	print("  capture: %s" % out)
	return img

## Bande horizontale d'une image (fractions 0..1 de la hauteur).
func _band(img: Image, from_fraction: float, to_fraction: float) -> Image:
	var y0 := clampi(int(float(img.get_height()) * from_fraction), 0, img.get_height() - 1)
	var y1 := clampi(int(float(img.get_height()) * to_fraction), y0 + 1, img.get_height())
	return img.get_region(Rect2i(0, y0, img.get_width(), y1 - y0))

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
	var step := maxi(1, int(float(w) / 160.0))
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
	for pt in [Vector2i(w / 4, h / 4), Vector2i(3 * w / 4, h / 2), Vector2i(w / 2, 3 * h / 4)]:
		if img.get_pixelv(pt) != first:
			return false
	return true

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
