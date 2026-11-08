extends SceneTree

## Capture de **qualité du terrain** — deux cartes, trois briques du rendu « CS2 ».
##
## CARTE A (falaise) :
##   • `triplanar_amount` (task-2) : 0 = projection UV historique, 1 = triplanar ;
##   • PRIORITÉ DES SPLATS PEINTS : la paroi peinte en pierre ne doit pas être
##     recolorée par l'auto-matériau ;
##   • la plaine (herbe + chemin de terre peints) reste identique (règle d'or).
##
## CARTE B (montagne) :
##   • `auto_material_strength` (task-4) : 0 = rendu précédent, 1 = auto-matériau
##     par pente et altitude — roche sur les flancs raides, terre sur les
##     contreforts, neige au sommet, frontières bruitées irrégulières.
##
## Chaque brique est capturée deux fois avec la MÊME caméra (A/B) puis vérifiée
## par diff d'image : les zones concernées doivent changer nettement, les zones
## peintes ou plates doivent rester identiques.
##
## Les PNG sont copiés à la RACINE du dépôt : `docs/screenshots/`.

## Chargé par `load()` : le moteur référence l'autoload MapData, indisponible
## au moment de la compilation d'un `preload`.
var Engine3DScript: GDScript
## Résolution des grilles de capture.
const W := 26
const H := 18
## CARTE A — plateau au fond (z petit), falaise ≈ 75° puis plaine devant.
const PLATEAU_H := 4.60
const PLAIN_H := 0.15
const CLIFF_Z0 := 5.0
const CLIFF_Z1 := 6.2
## CARTE B — montagne sur la plaine, au premier plan (cône large : les bandes
## de matière suivent l'altitude, frontières bruitées).
const HILL_X := 13.0
const HILL_Z := 12.0
const HILL_H := 6.50
const HILL_SLOPE := 0.95
## Seuils de différence moyenne (0..1) entre deux captures.
## Vue d'ensemble : la falaise n'occupe qu'une partie de l'image.
const DIFF_MIN_OVERVIEW := 0.003
const DIFF_MIN_CLIFF := 0.010
## Montagne : mesurée sur la zone utile de l'image (hors fond noir), la
## montagne elle-même ne couvrant qu'une partie de la carte. Seuil tenu bas
## volontairement : le nettoyage anti-bandes de l'auto-matériau (frontières
## bruitées, pas de micro-taches) réduit le diff moyen, alors que l'effet
## qualitatif (roche/neige/terre vs herbe seule) reste massif.
const DIFF_MIN_MOUNTAIN := 0.005
## Tolérance sur les zones qui doivent rester identiques (plaine, paroi peinte).
const SAME_MAX := 0.004

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")

	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame

	# =====================================================================
	# CARTE A : falaise — triplanar + priorité des splats peints
	# =====================================================================
	var map_a: Dictionary = _make_cliff_map(md)
	engine.configure(map_a, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(12):
		await process_frame
	var ground = engine._ground
	_assert("ground_present", ground != null)
	if ground == null:
		print("terrain_quality_shot_test:FAIL")
		quit(1)
		return
	_assert("ground_terrain3d", ground.is_terrain3d())
	_assert("ground_splat_active", ground.is_splat_active())
	_assert("ground_relief", ground.has_terrain_relief())
	var mat = ground._mesh_instance.material_override
	_assert("ground_splat_material", mat is ShaderMaterial)
	if not (mat is ShaderMaterial):
		print("terrain_quality_shot_test:FAIL")
		quit(1)
		return

	engine._fit_to_view()
	for _i in range(8):
		await process_frame

	# --- Vue d'ensemble ---------------------------------------------------
	_set_triplanar(mat, 1.0)
	_set_auto(mat, 1.0)
	var overview: Image = await _shot(engine, "terrain_quality_overview")
	_set_triplanar(mat, 0.0)
	var overview_uv: Image = await _shot(engine, "terrain_quality_overview_uv")
	_set_triplanar(mat, 1.0)
	if overview != null and overview_uv != null:
		_assert("overview_not_blank", not _is_blank(overview))
		var d := _mean_diff(overview, overview_uv)
		print("  [diff] overview triplanar on/off = %.4f" % d)
		_assert("overview_triplanar_differs", d > DIFF_MIN_OVERVIEW, "diff=%.4f" % d)

	# --- Falaise : gros plan (triplanar + auto + priorité peinte) ---------
	var cell := float(engine._cell_size)
	var cliff_x := float(W) * cell * 0.5
	engine.zoom = 1.20
	engine._update_ortho_size()
	engine._center_focus_on(Vector2(cliff_x, (CLIFF_Z1 + 0.6) * cell))
	for _i in range(8):
		await process_frame

	_set_triplanar(mat, 1.0)
	_set_auto(mat, 1.0)
	var cliff: Image = await _shot(engine, "terrain_quality_cliff")
	_set_triplanar(mat, 0.0)
	var cliff_uv: Image = await _shot(engine, "terrain_quality_cliff_uv")
	_set_triplanar(mat, 1.0)
	_set_auto(mat, 0.0)
	var cliff_auto0: Image = await _shot(engine, "terrain_quality_cliff_auto0")
	_set_auto(mat, 1.0)
	if cliff != null and cliff_uv != null:
		_assert("cliff_not_blank", not _is_blank(cliff))
		var d := _mean_diff(cliff, cliff_uv)
		print("  [diff] cliff triplanar on/off = %.4f" % d)
		_assert("cliff_triplanar_differs", d > DIFF_MIN_CLIFF, "diff=%.4f" % d)
		# Règle d'or : le bas de l'image est la plaine horizontale — elle doit
		# rester strictement identique au rendu UV historique.
		var flat_d := _mean_diff(_band(cliff, 0.82, 1.0), _band(cliff_uv, 0.82, 1.0))
		print("  [diff] plaine triplanar on/off = %.5f" % flat_d)
		_assert("flat_terrain_unchanged", flat_d < SAME_MAX, "diff=%.5f" % flat_d)
	if cliff != null and cliff_auto0 != null:
		# PRIORITÉ DES SPLATS PEINTS : la paroi peinte en pierre (bande
		# centrale de l'image) ne bouge pas quand l'auto-matériau s'active.
		var painted_d := _mean_diff(_band(cliff, 0.40, 0.62), _band(cliff_auto0, 0.40, 0.62))
		print("  [diff] paroi peinte auto on/off = %.5f" % painted_d)
		_assert("painted_splat_priority", painted_d < SAME_MAX, "diff=%.5f" % painted_d)
		# Plaine (peinte) inchangée par l'auto-matériau : l'auto y redonne de
		# l'herbe et n'écrase jamais les splats peints.
		var plain_d := _mean_diff(_band(cliff, 0.86, 1.0), _band(cliff_auto0, 0.86, 1.0))
		print("  [diff] plaine auto on/off = %.5f" % plain_d)
		_assert("plain_unchanged_by_auto", plain_d < SAME_MAX, "diff=%.5f" % plain_d)

	# =====================================================================
	# CARTE B : montagne — auto-matériau par pente et altitude
	# =====================================================================
	var map_b: Dictionary = _make_mountain_map(md)
	engine.configure(map_b, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(12):
		await process_frame
	engine._fit_to_view()
	for _i in range(8):
		await process_frame
	var mat_b = engine._ground._mesh_instance.material_override
	_assert("mountain_splat_material", mat_b is ShaderMaterial)
	if not (mat_b is ShaderMaterial):
		print("terrain_quality_shot_test:FAIL")
		quit(1)
		return
	# Cadrage : la montagne au centre-bas, la plaine lointaine au-dessus.
	# La caméra est positionnée géométriquement (ortho, on connaît son angle) :
	# après un 2e `configure`, les helpers de cadrage différés du moteur peuvent
	# encore bouger la vue pendant quelques frames.
	await process_frame
	await process_frame
	var rot_x := deg_to_rad(float(engine._camera.rotation_degrees.x))
	var cam_y := 20.0
	var ray_t := cam_y / maxf(0.001, -sin(rot_x))
	# Cadrage : la montagne au centre (caméra ortho : `size` est la demi-hauteur
	# de la vue, d'où une valeur petite pour un gros plan).
	var target := Vector2(HILL_X * cell, HILL_Z * cell)
	engine._camera.size = 3.0
	engine._camera.position = Vector3(
		target.x, cam_y, target.y + ray_t * cos(rot_x))
	for _i in range(8):
		await process_frame
	print("  [cam] montagne size=%.2f rot=%.1f pos=%s" % [
		engine._camera.size, engine._camera.rotation_degrees.x,
		str(engine._camera.position)])

	_set_triplanar(mat_b, 1.0)
	_set_auto(mat_b, 1.0)
	var mountain: Image = await _shot(engine, "terrain_quality_mountain")
	_set_auto(mat_b, 0.0)
	var mountain_auto0: Image = await _shot(engine, "terrain_quality_mountain_auto0")
	_set_auto(mat_b, 1.0)
	if mountain != null and mountain_auto0 != null:
		_assert("mountain_not_blank", not _is_blank(mountain))
		# Zone utile de l'image (le fond noir hors carte diluerait le diff).
		var d := _mean_diff(
			_crop(mountain, 0.10, 0.15, 0.90, 0.92),
			_crop(mountain_auto0, 0.10, 0.15, 0.90, 0.92))
		print("  [diff] mountain auto on/off = %.4f" % d)
		_assert("mountain_auto_differs", d > DIFF_MIN_MOUNTAIN, "diff=%.4f" % d)

	if _failed:
		print("terrain_quality_shot_test:FAIL")
		quit(1)
		return
	print("terrain_quality_shot_test:PASS")
	quit(0)

## Fondu A/B du triplanar (0 = projection UV historique).
func _set_triplanar(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("triplanar_amount", amount)

## Fondu A/B de l'auto-matériau (0 = rendu précédent, sans auto).
func _set_auto(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("auto_material_strength", amount)

# ===========================================================================
# Carte A — falaise
# ===========================================================================

## Carte avec falaise : plateau, paroi ≈ 75° (UV écrasés) et plaine.
func _make_cliff_map(md) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Qualité terrain falaise", "general", "local", W, H)
	map["vegetationDensity"] = 0.0
	map["waterBodies"] = []
	map["terrainHeights"] = _cliff_heights()
	map["terrainMaterials"] = _cliff_materials()
	return map

func _cliff_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for z in range(H):
		var fz := float(z)
		for x in range(W):
			var h := PLAIN_H
			if fz < CLIFF_Z0:
				h = PLATEAU_H + sin(float(x) * 0.55) * 0.12 + cos(fz * 0.7) * 0.08
			elif fz < CLIFF_Z1:
				h = lerpf(PLATEAU_H, PLAIN_H, (fz - CLIFF_Z0) / (CLIFF_Z1 - CLIFF_Z0))
			heights[z * W + x] = maxf(0.0, h)
	return heights

## Matières : paroi peinte en PIERRE (prioritaire), terre au pied en TACHES
## irrégulières (jamais une bande peinte continue — le « strate peinte » du
## rapport), herbe neutre ailleurs, coin de sable peint à bords organiques.
func _cliff_materials() -> Array:
	var materials: Array = []
	materials.resize(W * H)
	for z in range(H):
		for x in range(W):
			var m := 0
			if z >= int(CLIFF_Z0) and z <= int(CLIFF_Z1):
				m = 2
			elif z == int(CLIFF_Z1) + 1:
				# Terre au pied de la falaise : taches le long de la ligne,
				# frontières ondulées (bruit doux, pas d'angles droits).
				if _soft_noise(float(x) * 0.9, float(z) * 0.7) > -0.55:
					m = 1
			elif x > W - 5 and z > H - 5:
				# Coin de sable : bord diagonal ondulé au lieu d'un rectangle.
				var edge := (float(x) + float(z)) - (float(W) + float(H) - 8.5)
				if edge + _soft_noise(float(x) * 0.8, float(z) * 0.8) * 2.2 > 0.0:
					m = 4
			materials[z * W + x] = m
	return materials

## Bruit doux déterministe (-1..1) : sert à donner des bords organiques aux
## zones peintes du jeu de test (pas de rectangles ni de bandes pleines).
func _soft_noise(x: float, z: float) -> float:
	return 0.6 * sin(x * 0.9 + z * 0.4) + 0.4 * sin(x * 2.3 - z * 1.1 + 1.7)

# ===========================================================================
# Carte B — montagne (toute en herbe neutre : l'auto-matériau fait le reste)
# ===========================================================================

func _make_mountain_map(md) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Qualité terrain montagne", "general", "local", W, H)
	map["vegetationDensity"] = 0.0
	map["waterBodies"] = []
	map["terrainHeights"] = _mountain_heights()
	map["terrainMaterials"] = _mountain_materials()
	return map

func _mountain_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for z in range(H):
		for x in range(W):
			var dx := float(x) - HILL_X
			var dz := float(z) - HILL_Z
			var d := sqrt(dx * dx + dz * dz)
			var cone := maxf(0.0, HILL_H - d * HILL_SLOPE)
			# Relief irrégulier : le bruit ne s'applique qu'au cône (la plaine
			# reste parfaitement plate, donc inchangée par l'auto-matériau).
			var rough := _noise2(float(x) * 0.6, float(z) * 0.6) * 1.1 \
				+ _noise2(float(x) * 1.3 + 7.0, float(z) * 1.3) * 0.45
			var h := PLAIN_H + cone + rough * smoothstep(0.0, 2.0, cone)
			heights[z * W + x] = maxf(0.0, h)
	return heights

## Bruit de valeur déterministe (-0.5..0.5) pour des flancs naturels.
func _noise2(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return (v - floorf(v)) - 0.5

## Matières : herbe neutre partout (matière par défaut → l'auto-matériau
## s'applique), sauf un chemin de terre PEINT sinueux au premier plan et un
## coin de sable peint à bords organiques (doivent rester inchangés).
func _mountain_materials() -> Array:
	var materials: Array = []
	materials.resize(W * H)
	for z in range(H):
		for x in range(W):
			var m := 0
			# Chemin de terre sinueux (une à deux cases, frontières ondulées).
			if absf(float(z) - float(H - 2) + _soft_noise(float(x) * 0.7, 0.0) * 1.2) < 0.75:
				m = 1
			elif x > W - 5 and z > H - 5:
				var edge := (float(x) + float(z)) - (float(W) + float(H) - 8.5)
				if edge + _soft_noise(float(x) * 0.8, float(z) * 0.8) > 0.0:
					m = 4
			materials[z * W + x] = m
	return materials

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

## Bande verticale d'une image (fractions 0..1 de la hauteur).
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
