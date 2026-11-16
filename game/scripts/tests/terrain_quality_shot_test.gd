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
##     contreforts, neige au sommet, frontières bruitées irrégulières ;
##   • BERGE MOUILLÉE : un lac de plaine (cuvette à berges ASYMÉTRIQUES —
##     raide côté −x, douce côté +x) alimente la chaîne
##     `MapWater3D.get_shore_texture() → ground.set_shore_texture()` ; un A/B
##     `shore_enabled` 1/0 (eau masquée pour rester déterministe) vérifie que
##     la terre est assombrie/brunie AU BORD de l'eau, sur une bande plus
##     large côté faible pente.
##
## Chaque brique est capturée deux fois avec la MÊME caméra (A/B) puis vérifiée
## par diff d'image : les zones concernées doivent changer nettement, les zones
## peintes ou plates doivent rester identiques.
##
## FINITIONS TERRAIN (task-1/2/3) :
##   • AO DE CUVETTES Cuites : A/B `cavity_bake` (0 = historique, 1 = AO par
##     sommet cuite depuis le heightfield) — le relief change nettement, la
##     plaine plate reste identique (règle d'or) ;
##   • LIGNE DE NEIGE : gros plan sur la frontière neige/roche, ratio de
##     mouchetures sombres mesuré (doit rester sous `SNOW_SPECKLE_MAX`) ;
##   • PENTES INTERMÉDIARES : capture de référence du dédoublement de motif
##     triplanar (`terrain_quality_slope`).
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
## La roche de falaise doit différer nettement du dallage historique dans la
## bande abrupte, sans toucher aux zones plates.
const DIFF_MIN_CLIFF_MATERIAL := 0.008
## Montagne : mesurée sur la zone utile de l'image (hors fond noir), la
## montagne elle-même ne couvrant qu'une partie de la carte. Seuil tenu bas
## volontairement : le nettoyage anti-bandes de l'auto-matériau (frontières
## bruitées, pas de micro-taches) réduit le diff moyen, alors que l'effet
## qualitatif (roche/neige/terre vs herbe seule) reste massif.
const DIFF_MIN_MOUNTAIN := 0.005
## Tolérance sur les zones qui doivent rester identiques (plaine, paroi peinte).
const SAME_MAX := 0.004
## CARTE B — lac de plaine pour la BERGE MOUILLÉE : cuvette à fond plat
## circulaire puis berges ASYMÉTRIQUES (raide côté −x, douce côté +x), pour
## vérifier « plus large côté faible pente ».
const POND_X := 5.5
const POND_Z := 5.5
const POND_LEVEL := 0.45
const MOUNTAIN_PLAIN_H := 0.55
const POND_BED_R := 1.0
const POND_RISE_STEEP := 0.9
const POND_RISE_GENTLE := 3.4
## Seuils de la berge mouillée (diff A/B par pixel et en moyenne).
const SHORE_DIFF_MIN := 0.006
const SHORE_PIXEL_THR := 0.008
## Marge minimale en pixels (garde-fou) : la berge douce doit rester plus
## large que la raide, sans dépendre d un écart absolu calibré sur l ancien
## pipeline de textures (mipmaps/1024/anisotrope/densité de tuile).
const SHORE_SLOPE_MARGIN_PX := 24.0
## Ratio minimal doux/raide : invariant plus robuste que la marge en pixels
## absolus quand le pipeline de textures change (mipmaps, 1024, anisotrope,
## densité de tuile) — la berge doit rester nettement plus large en pente douce.
const SHORE_GENTLE_RATIO_MIN := 1.12
## FINITIONS TERRAIN — AO de cuvettes cuites (task-1) : diff A/B minimale sur
## le relief (les cuvettes s'assombrissent, les crêtes s'éclaircissent).
const CAVITY_DIFF_MIN := 0.002
## FINITIONS TERRAIN — ligne de neige (task-2) : ratio maximal de pixels
## « mouchetures sombres » (très plus sombres que leur voisinage local) toléré
## sur le gros plan de la frontière neige/roche.
const SNOW_SPECKLE_MAX := 0.012
## FINITIONS EAU/TERRAIN (task-4) — éclairage double du lit (`bed_ambient_lift`)
## vu du terrain : le lit des hauts-fonds s'éclaircit par diffusion d'eau.
const BED_TERRAIN_DIFF_MIN := 0.0015
## FINITIONS TERRAIN CS2 (task-9) — strates de falaise (couches obliques).
const STRATA_DIFF_MIN := 0.0020
## Variation macro 3D (taches sèches/vertes à grande échelle).
const MACRO_DIFF_MIN := 0.0008
## Transition neige adoucie (+ neige des creux), à mouchetures constantes.
const SNOW_DIFF_MIN := 0.0005
## Ancrage des objets : AO de contact sous les objets posés.
const OBJECT_AO_DIFF_MIN := 0.0008

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
	# ISOLATION : les captures historiques de la falaise mesurent la PROJECTION
	# (triplanar) et la PRIORITÉ des splats peints, pas la finition strates.
	# On coupe donc `cliff_strata` pour ces captures (l'A/B dédié aux strates
	# suit plus bas) : les seuils d'origine restent mesurés sur leur objet.
	mat.set_shader_parameter("cliff_strata", 0.0)
	mat.set_shader_parameter("cliff_material_strength", 1.0)
	var cliff: Image = await _shot(engine, "terrain_quality_cliff")
	# A/B de la matière : la falaise naturelle remplace explicitement le pavage
	# uniquement là où la pente l'exige ; les zones praticables restent stables.
	mat.set_shader_parameter("cliff_material_strength", 0.0)
	var cliff_paving: Image = await _shot(engine, "terrain_quality_cliff_paving")
	mat.set_shader_parameter("cliff_material_strength", 1.0)
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
	if cliff != null and cliff_paving != null:
		var cliff_material_d := _mean_diff(_band(cliff, 0.28, 0.72), _band(cliff_paving, 0.28, 0.72))
		print("  [diff] roche falaise/pavage = %.4f" % cliff_material_d)
		_assert("cliff_material_visible", cliff_material_d > DIFF_MIN_CLIFF_MATERIAL,
			"diff=%.4f" % cliff_material_d)
		var flat_material_d := _mean_diff(_band(cliff, 0.84, 1.0), _band(cliff_paving, 0.84, 1.0))
		_assert("cliff_material_keeps_flats", flat_material_d < SAME_MAX,
			"diff=%.4f" % flat_material_d)

	# --- STRATES DE FALAISE (task-9) : A/B `cliff_strata` (0 = roche lisse) --
	# Même caméra que le gros plan falaise : les couches obliques doivent se
	# lire sur la paroi et ne PAS repeindre la plaine (règle d'or).
	_set_strata(mat, 0.0)
	var strata_off: Image = await _shot(engine, "terrain_strata_off")
	_set_strata(mat, 1.0)
	var strata_on: Image = await _shot(engine, "terrain_strata_on")
	if strata_off != null and strata_on != null:
		_assert("strata_off_not_blank", not _is_blank(strata_off))
		_assert("strata_on_not_blank", not _is_blank(strata_on))
		var strata_d := _mean_diff(
			_band(strata_off, 0.26, 0.72), _band(strata_on, 0.26, 0.72))
		print("  [diff] strates falaise off/on = %.4f" % strata_d)
		_assert("strata_visible", strata_d > STRATA_DIFF_MIN,
			"diff=%.4f" % strata_d)
		var strata_flat := _mean_diff(
			_band(strata_off, 0.84, 1.0), _band(strata_on, 0.84, 1.0))
		print("  [diff] strates plaine off/on = %.5f" % strata_flat)
		_assert("strata_keeps_flats", strata_flat < SAME_MAX,
			"diff=%.5f" % strata_flat)
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

	# --- AO DE CUVETTES Cuites (task-1) : A/B `cavity_bake` (0 = historique).
	# Les creux/valons (pied de la falaise, plis du plateau) s'assombrissent,
	# les crêtes s'éclaircissent — la PLAINE PLATE reste EXACTEMENT identique
	# (règle d'or : l'AO cuite y vaut 1.0).
	_set_cavity_bake(mat, 1.0)
	var cliff_cav_on: Image = await _shot(engine, "terrain_quality_cliff_cavity_on")
	_set_cavity_bake(mat, 0.0)
	var cliff_cav_off: Image = await _shot(engine, "terrain_quality_cliff_cavity_off")
	_set_cavity_bake(mat, 1.0)
	if cliff_cav_on != null and cliff_cav_off != null:
		_assert("cavity_on_not_blank", not _is_blank(cliff_cav_on))
		var cav_d := _mean_diff(_band(cliff_cav_on, 0.25, 0.75), _band(cliff_cav_off, 0.25, 0.75))
		print("  [diff] cavity bake on/off (relief) = %.4f" % cav_d)
		_assert("cavity_bake_visible", cav_d > CAVITY_DIFF_MIN, "diff=%.4f" % cav_d)
		var cav_flat := _mean_diff(_band(cliff_cav_on, 0.82, 1.0), _band(cliff_cav_off, 0.82, 1.0))
		print("  [diff] cavity bake on/off (plaine) = %.5f" % cav_flat)
		_assert("cavity_plain_neutral", cav_flat < SAME_MAX, "diff=%.5f" % cav_flat)

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
	# Non-régression du CORRECTIF « neige sur carte plate » : une vraie
	# montagne est au-dessus du plein effet de la porte `auto_min_relief`
	# (×2,25) → l'auto-matériau y reste strictement identique.
	var mountain_span := absf(float(mat_b.get_shader_parameter("terrain_max_height"))
		- float(mat_b.get_shader_parameter("terrain_min_height")))
	print("  [auto] montagne : relief absolu = %.2f u" % mountain_span)
	_assert("auto_mountain_above_gate", mountain_span >= 1.8,
		"span=%.2f" % mountain_span)
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

	# --- VARIATION MACRO 3D (task-9) : A/B `macro_variation` ----------------
	# Même caméra montagne : taches de sol plus sèches/vertes à grande échelle,
	# non répétitives, sans repeindre la neige (elle doit rester propre).
	_set_macro_variation(mat_b, 0.0)
	var macro_off: Image = await _shot(engine, "terrain_strata_macro_off")
	_set_macro_variation(mat_b, 1.0)
	var macro_on: Image = await _shot(engine, "terrain_strata_macro_on")
	if macro_off != null and macro_on != null:
		_assert("macro_off_not_blank", not _is_blank(macro_off))
		var macro_d := _mean_diff(
			_crop(macro_off, 0.10, 0.15, 0.90, 0.92),
			_crop(macro_on, 0.10, 0.15, 0.90, 0.92))
		print("  [diff] variation macro off/on = %.5f" % macro_d)
		_assert("macro_variation_visible", macro_d > MACRO_DIFF_MIN,
			"diff=%.5f" % macro_d)
	# Coût indicatif (fenêtre cachée) : strates + variation macro (ALU shader).
	_set_strata(mat_b, 0.0)
	_set_macro_variation(mat_b, 0.0)
	var t_off := Time.get_ticks_usec()
	for _i in range(24):
		await process_frame
	var ms_off := float(Time.get_ticks_usec() - t_off) / 24000.0
	_set_strata(mat_b, 1.0)
	_set_macro_variation(mat_b, 1.0)
	var t_on := Time.get_ticks_usec()
	for _i in range(24):
		await process_frame
	var ms_on := float(Time.get_ticks_usec() - t_on) / 24000.0
	print("  [perf] temps de frame finitions off=%.2f ms on=%.2f ms (indicatif)"
		% [ms_off, ms_on])

	# =====================================================================
	# BERGE MOUILLÉE : lac de plaine (carte B) — la terre doit s'assombrir
	# et brunir AU BORD de l'eau, en dégradé progressif, avec un bord
	# ondulé, et sur une bande plus large côté faible pente.
	# =====================================================================
	var water = engine._water_layer
	_assert("shore_water_layer", water != null)
	_assert("shore_texture_built", water != null and water.get_shore_texture() != null)
	_assert("shore_enabled_uniform",
		is_equal_approx(float(mat_b.get_shader_parameter("shore_enabled")), 1.0))
	# Cadrage : le lac au centre (même méthode géométrique que la montagne).
	var pond_target := Vector2(POND_X * cell, POND_Z * cell)
	var shore_cam_y := 8.0
	engine._camera.size = 2.6
	engine._camera.position = Vector3(
		pond_target.x, shore_cam_y,
		pond_target.y + (shore_cam_y / maxf(0.001, -sin(rot_x))) * cos(rot_x))
	for _i in range(8):
		await process_frame
	# A/B DÉTERMINISTE : on masque l'eau (shader animé) pour que le diff ne
	# mesure QUE la berge mouillée du terrain.
	if water != null:
		water.visible = false
	for _i in range(3):
		await process_frame
	_set_shore(mat_b, 1.0)
	var shore_on: Image = await _shot(engine, "terrain_quality_shore_on")
	_set_shore(mat_b, 0.0)
	var shore_off: Image = await _shot(engine, "terrain_quality_shore_off")
	_set_shore(mat_b, 1.0)
	if water != null:
		water.visible = true
	for _i in range(3):
		await process_frame
	var shore: Image = await _shot(engine, "terrain_quality_shore")
	if shore_on != null and shore_off != null:
		_assert("shore_on_not_blank", not _is_blank(shore_on))
		var sd := _mean_diff(shore_on, shore_off)
		print("  [diff] berge mouillée on/off = %.4f" % sd)
		_assert("shore_effect_visible", sd > SHORE_DIFF_MIN, "diff=%.4f" % sd)
		var bands := _shore_band_widths(shore_on, shore_off, engine._camera, cell)
		print("  [shore] bande mouillée : douce=%.0f px, raide=%.0f px" % [bands.x, bands.y])
		_assert("shore_band_hugs_shoreline", bands.x > 0.0 and bands.y > 0.0,
			"doux=%.0f raide=%.0f" % [bands.x, bands.y])
		_assert("shore_wider_on_gentle_slope",
			bands.x > bands.y * SHORE_GENTLE_RATIO_MIN
			and bands.x > bands.y + SHORE_SLOPE_MARGIN_PX,
			"doux=%.0f raide=%.0f" % [bands.x, bands.y])

	# =====================================================================
	# ÉCLAIRAGE DOUBLE DU LIT (finition CS2 task-4) — A/B `bed_ambient_lift`
	# VU DU TERRAIN : le lit sous l'eau reçoit l'ambiance/diffusion de la lame
	# en plus des caustiques directes (fin de l'effet « fond plat »). L'eau est
	# masquée pour ne mesurer QUE le lit ; la caméra est celle du lac (même
	# cadrage que la berge mouillée).
	# =====================================================================
	if water != null:
		water.visible = false
	for _i in range(3):
		await process_frame
	_assert("bed_terrain_water_map_on",
		is_equal_approx(float(mat_b.get_shader_parameter("water_map_enabled")), 1.0))
	_set_bed_terrain(mat_b, 0.0)
	var bed_terrain_off: Image = await _shot(engine, "cs2_finitions_terrain_bed_off")
	_set_bed_terrain(mat_b, 1.0)
	var bed_terrain_on: Image = await _shot(engine, "cs2_finitions_terrain_bed_on")
	if water != null:
		water.visible = true
	for _i in range(3):
		await process_frame
	if bed_terrain_off != null and bed_terrain_on != null:
		_assert("bed_terrain_off_not_blank", not _is_blank(bed_terrain_off))
		# Centre de l'image = le lit du lac (hauts-fonds).
		var bed_d := _mean_diff(
			_crop(bed_terrain_off, 0.20, 0.20, 0.80, 0.80),
			_crop(bed_terrain_on, 0.20, 0.20, 0.80, 0.80))
		print("  [diff] éclairage double du lit (terrain) off/on = %.5f" % bed_d)
		_assert("bed_terrain_visible", bed_d > BED_TERRAIN_DIFF_MIN,
			"diff=%.5f" % bed_d)
	_assert("bed_terrain_restored",
		is_equal_approx(float(mat_b.get_shader_parameter("bed_ambient_lift")), 1.0))

	# =====================================================================
	# FINITIONS TERRAIN (carte B) — AO de cuvettes sur relief bruité,
	# ligne de neige propre, pentes intermédiaires sans dédoublement.
	# =====================================================================
	# --- AO DE CUVETTES : A/B `cavity_bake` sur le flanc de la montagne
	# (le bruit de relief y creuse de vraies cuvettes, visibles en gros plan).
	var cav_cam := Vector2((HILL_X + 2.6) * cell, (HILL_Z + 1.4) * cell)
	_set_cavity_bake(mat_b, 1.0)
	var cav_on: Image = await _frame_and_shoot(
		engine, cav_cam, 7.0, "terrain_quality_cavity_on")
	_set_cavity_bake(mat_b, 0.0)
	var cav_off: Image = await _frame_and_shoot(
		engine, cav_cam, 7.0, "terrain_quality_cavity_off")
	_set_cavity_bake(mat_b, 1.0)
	if cav_on != null and cav_off != null:
		_assert("cavity_mountain_on_not_blank", not _is_blank(cav_on))
		var mcd := _mean_diff(cav_on, cav_off)
		print("  [diff] cavity bake on/off (montagne) = %.4f" % mcd)
		_assert("cavity_mountain_differs", mcd > CAVITY_DIFF_MIN, "diff=%.4f" % mcd)

	# --- LIGNE DE NEIGE (task-2) : gros plan sur le manteau neigeux et sa
	# frontière neige/roche — aucune moucheture sombre ne doit rester (la
	# frontière reste basse fréquence : bruit long, pas de speckles).
	var snow_cam := Vector2(HILL_X * cell, (HILL_Z + 1.2) * cell)
	var snowline: Image = await _frame_and_shoot(
		engine, snow_cam, 6.0, "terrain_quality_snowline")
	if snowline != null:
		_assert("snowline_not_blank", not _is_blank(snowline))
		var speck := _dark_speckle_ratio(snowline, 0.15, 0.15, 0.85, 0.85)
		print("  [neige] mouchetures sombres = %.4f" % speck)
		_assert("snowline_no_dark_speckles", speck < SNOW_SPECKLE_MAX,
			"ratio=%.4f" % speck)

	# --- PENTES INTERMÉDIAIRES (task-3) : capture de référence du
	# dédoublement de motif — le motif doit rester d'un seul tenant sur le
	# flanc (pas de double image en traînées).
	var slope: Image = await _frame_and_shoot(
		engine, Vector2((HILL_X + 2.2) * cell, (HILL_Z + 1.8) * cell),
		5.5, "terrain_quality_slope")
	_assert("slope_capture_ok", slope != null and not _is_blank(slope))

	# --- TRANSITION NEIGE/ROCHE (task-9) : A/B `snow_transition` -------------
	# Même cadrage que la ligne de neige : la frontière doit rester PROPRE (le
	# test de mouchetures reste vert) tout en devenant plus douce et en tenant
	# mieux dans les creux. On mesure le gain ET l'absence de mouchetures.
	_set_snow_transition(mat_b, 0.0)
	var snow_off: Image = await _frame_and_shoot(
		engine, snow_cam, 6.0, "terrain_strata_snow_off")
	_set_snow_transition(mat_b, 1.0)
	var snow_on: Image = await _frame_and_shoot(
		engine, snow_cam, 6.0, "terrain_strata_snow_on")
	if snow_off != null and snow_on != null:
		_assert("snow_transition_off_not_blank", not _is_blank(snow_off))
		var snow_d := _mean_diff(snow_off, snow_on)
		print("  [diff] transition neige off/on = %.5f" % snow_d)
		_assert("snow_transition_visible", snow_d > SNOW_DIFF_MIN,
			"diff=%.5f" % snow_d)
		var snow_speck := _dark_speckle_ratio(snow_on, 0.15, 0.15, 0.85, 0.85)
		print("  [neige] mouchetures (transition active) = %.4f" % snow_speck)
		_assert("snow_transition_keeps_clean", snow_speck < SNOW_SPECKLE_MAX,
			"ratio=%.4f" % snow_speck)

	# =====================================================================
	# CORRECTIF « NEIGE SUR CARTE PLATE » : porte de relief ABSOLU de
	# l'auto-matériau (`auto_min_relief`). Sur une carte de ville quasi plate
	# (buttes de bord seulement), l'auto-matériau (roche/terre/neige) ne doit
	# plus rien changer ; la même capture avec la porte à 0 (comportement
	# historique) montre les taches blanches d'origine.
	# =====================================================================
	var flat_map: Dictionary = _make_flat_city_map(md)
	engine.configure(flat_map, [], [], [], [], [], false, true,
		{"mode": "select"}, {}, "")
	for _i in range(14):
		await process_frame
	var ground_flat = engine._ground
	var mat_flat = ground_flat._mesh_instance.material_override
	_assert("auto_flat_material", mat_flat is ShaderMaterial)
	if mat_flat is ShaderMaterial:
		var flat_span := absf(float(mat_flat.get_shader_parameter("terrain_max_height"))
			- float(mat_flat.get_shader_parameter("terrain_min_height")))
		print("  [auto] carte ville : relief absolu = %.3f u" % flat_span)
		_assert("auto_flat_below_gate", flat_span < 0.8, "span=%.3f" % flat_span)
		_assert("auto_flat_gate_default",
			is_equal_approx(float(mat_flat.get_shader_parameter("auto_min_relief")),
				0.8))
		# Caméra rasant les buttes de bord (là où les taches apparaissaient).
		var ext_flat: Vector2 = engine._map_extent
		engine._camera.position = Vector3(ext_flat.x * 0.5, 3.2,
			ext_flat.y * 0.5 + 7.5)
		engine._camera.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
		for _i in range(8):
			await process_frame
		var flat_on: Image = await _shot(engine, "terrain_auto_flat_on")
		# Comportement HISTORIQUE : porte coupée → neige/terre automatiques.
		ground_flat.set_auto_min_relief(0.0)
		var flat_legacy: Image = await _shot(engine, "terrain_auto_flat_off")
		# Référence : auto-matériau totalement coupé (rendu peint pur).
		ground_flat.set_auto_min_relief(0.8)
		mat_flat.set_shader_parameter("auto_material_strength", 0.0)
		var flat_none: Image = await _shot(engine, "terrain_auto_flat_none")
		mat_flat.set_shader_parameter("auto_material_strength", 1.0)
		if flat_on != null and flat_none != null and flat_legacy != null:
			_assert("auto_flat_on_not_blank", not _is_blank(flat_on))
			var neutral := _mean_diff(
				_crop(flat_on, 0.05, 0.10, 0.95, 0.98),
				_crop(flat_none, 0.05, 0.10, 0.95, 0.98))
			print("  [diff] carte plate : porte ON vs auto coupé = %.5f" % neutral)
			_assert("auto_flat_neutral", neutral < SAME_MAX,
				"diff=%.5f" % neutral)
			var legacy := _mean_diff(
				_crop(flat_legacy, 0.05, 0.10, 0.95, 0.98),
				_crop(flat_none, 0.05, 0.10, 0.95, 0.98))
			print("  [diff] carte plate : porte OFF (historique) vs auto coupé = %.4f"
				% legacy)
			_assert("auto_flat_legacy_artifacts", legacy > 0.002,
				"diff=%.4f" % legacy)

	# --- ANCRAGE DES OBJETS (task-9) : A/B `terrain_object_ao` --------------
	# Sur la carte de DÉMONSTRATION (village réel) : les empreintes des objets
	# posés au sol cuisent une AO de contact qui « assoit » le terrain sous les
	# bâtiments/props. Preuve : diff mesuré avec/sans les empreintes.
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	if boot != null:
		var demo: Dictionary = boot.build_demo(md)
		var village: Dictionary = demo.get("map", {})
		engine.configure(village, [], [], [], [], [], false, true,
			{"mode": "select"}, {}, "")
		for _i in range(14):
			await process_frame
		var ground_b = engine._ground
		var ext: Vector2 = engine._map_extent
		engine._camera.position = Vector3(ext.x * 0.5, 7.5, ext.y * 0.5 + 9.0)
		engine._camera.rotation_degrees = Vector3(-42.0, 0.0, 0.0)
		for _i in range(10):
			await process_frame
		ground_b.clear_object_occlusion()
		var obj_off: Image = await _shot(engine, "terrain_strata_object_ao_off")
		var stamps := _object_stamps(village)
		print("  [ancrage] %d empreintes d'objets" % stamps.size())
		ground_b.set_object_occlusion_stamps(stamps)
		_assert("object_ao_texture", ground_b.has_object_occlusion())
		var obj_on: Image = await _shot(engine, "terrain_strata_object_ao_on")
		_assert("object_ao_default_on",
			is_equal_approx(ground_b.get_terrain_object_ao(), 1.0))
		# A/B : 0 = terrain strictement inchangé.
		ground_b.set_terrain_object_ao(0.0)
		var obj_zero: Image = await _shot(engine, "terrain_strata_object_ao_zero")
		ground_b.clear_object_occlusion()
		ground_b.set_terrain_object_ao(1.0)
		if obj_off != null and obj_on != null:
			_assert("object_ao_off_not_blank", not _is_blank(obj_off))
			var oa_d := _mean_diff(
				_crop(obj_off, 0.05, 0.15, 0.95, 0.95),
				_crop(obj_on, 0.05, 0.15, 0.95, 0.95))
			print("  [diff] ancrage objets off/on = %.5f" % oa_d)
			_assert("object_ao_visible", oa_d > OBJECT_AO_DIFF_MIN,
				"diff=%.5f" % oa_d)
			if obj_zero != null:
				var zero_d := _mean_diff(
					_crop(obj_off, 0.05, 0.15, 0.95, 0.95),
					_crop(obj_zero, 0.05, 0.15, 0.95, 0.95))
				print("  [diff] ancrage objets force=0 vs off = %.5f" % zero_d)
				_assert("object_ao_zero_neutral", zero_d < SAME_MAX,
					"diff=%.5f" % zero_d)
	_assert("strata_restored",
		is_equal_approx(float(mat_b.get_shader_parameter("cliff_strata")), 1.0))

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

## Activation A/B de la berge mouillée (0 = aucun effet sur le terrain).
func _set_shore(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("shore_enabled", amount)

## Activation A/B de l'éclairage double du lit sous l'eau (0 = état précédent).
func _set_bed_terrain(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("bed_ambient_lift", amount)

## Activation A/B des strates de falaise (0 = roche lisse précédente).
func _set_strata(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("cliff_strata", amount)

## Activation A/B de la variation macro 3D (0 = inchangé).
func _set_macro_variation(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("macro_variation", amount)

## Activation A/B de la transition neige adoucie (0 = état précédent).
func _set_snow_transition(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("snow_transition", amount)

## Empreintes d'objets au sol pour l'AO de contact du terrain : dérivées des
## `meshes` de la carte de démonstration (chaque empreinte = rayon selon
## l'emprise de l'objet).
func _object_stamps(map: Dictionary) -> Array:
	var stamps: Array = []
	var meshes = map.get("meshes", [])
	if not (meshes is Array):
		return stamps
	for entry in (meshes as Array):
		if not (entry is Dictionary):
			continue
		var span := maxf(float((entry as Dictionary).get("w", 1.0)),
			float((entry as Dictionary).get("h", 1.0)))
		stamps.append({
			"x": float((entry as Dictionary).get("x", 0.0)),
			"y": float((entry as Dictionary).get("y", 0.0)),
			"radius": clampf(span * 0.55, 0.45, 1.4),
			"strength": 0.50,
		})
	return stamps

## Fondu A/B de l'AO de cuvettes cuite (0 = rendu historique, 1 = AO cuite).
func _set_cavity_bake(mat: ShaderMaterial, amount: float) -> void:
	mat.set_shader_parameter("cavity_bake", amount)

## Cadre un gros plan de façon DÉTERMINISTE puis capture. Caméra POSÉE À LA
## MAIN (même méthode géométrique que la montagne et la berge) : la carte B
## est en projection perspective — `Camera3D.size` n'a aucun effet, c'est la
## hauteur `cam_y` qui règle l'échelle du plan (rayon de visée re-calé sur le
## point visé, au sol). On repose la position à chaque frame de l'attente.
func _frame_and_shoot(
	engine: Control, target: Vector2, cam_y: float, shot_name: String
) -> Image:
	var rot_x := deg_to_rad(float(engine._camera.rotation_degrees.x))
	var ray_t := cam_y / maxf(0.001, -sin(rot_x))
	for _i in range(6):
		engine._camera.position = Vector3(
			target.x, cam_y, target.y + ray_t * cos(rot_x))
		await process_frame
	print("  [cam] %s pos=%s" % [shot_name, str(engine._camera.position)])
	return await _shot(engine, shot_name)

## Ratio de « mouchetures sombres » dans une zone (fractions 0..1) : fraction
## d'échantillons dont la luminance est très inférieure à la moyenne locale
## (fenêtre ~13 px). Des points sombres ISOLÉS font exploser ce ratio ; une
## frontière de matière douce et basse fréquence reste proche de 0.
func _dark_speckle_ratio(
	img: Image, x0f: float, y0f: float, x1f: float, y1f: float
) -> float:
	var crop := _crop(img, x0f, y0f, x1f, y1f)
	var w := crop.get_width()
	var h := crop.get_height()
	var dark := 0
	var count := 0
	for y in range(6, h - 6, 6):
		for x in range(6, w - 6, 6):
			var lum := _pixel_luma(crop.get_pixel(x, y))
			var local := 0.0
			for oy in range(-6, 7, 3):
				for ox in range(-6, 7, 3):
					local += _pixel_luma(crop.get_pixel(x + ox, y + oy))
			local /= 25.0
			count += 1
			if lum < local - 0.09:
				dark += 1
	return float(dark) / float(maxi(1, count))

## Luminance perceptuelle d'un pixel (0..1).
func _pixel_luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

## Largeurs (px) des bandes mouillées à gauche (berge RAIDE) et à droite
## (berge DOUCE) du lac, le long de la ligne passant par le centre du lac :
## longueur de la course de pixels touchés par la berge dans le diff A/B,
## d'où l'on retire la position analytique de la ligne de rive.
func _shore_band_widths(on: Image, off: Image, cam: Camera3D, cell: float) -> Vector2:
	if on == null or off == null or cam == null:
		return Vector2.ZERO
	var water_y := POND_LEVEL * cell
	var wl_right := POND_BED_R + (POND_LEVEL / MOUNTAIN_PLAIN_H) * POND_RISE_GENTLE
	var wl_left := POND_BED_R + (POND_LEVEL / MOUNTAIN_PLAIN_H) * POND_RISE_STEEP
	# `unproject_position` renvoie des coordonnées LOGIQUES de viewport ; la
	# capture est en pixels PHYSIQUES (HiDPI) — on recale par le rapport des
	# tailles, 1 dans les deux sens selon la plateforme.
	var vis := cam.get_viewport().get_visible_rect().size
	var k := Vector2(
		float(on.get_width()) / maxf(vis.x, 1.0),
		float(on.get_height()) / maxf(vis.y, 1.0))
	var center := cam.unproject_position(Vector3(POND_X * cell, water_y, POND_Z * cell)) * k
	var pr := cam.unproject_position(Vector3((POND_X + wl_right) * cell, water_y, POND_Z * cell)) * k
	var pl := cam.unproject_position(Vector3((POND_X - wl_left) * cell, water_y, POND_Z * cell)) * k
	var row := clampi(int(center.y), 0, on.get_height() - 1)
	var x0 := clampi(int(center.x), 0, on.get_width() - 1)
	var right := float(_wet_run(on, off, row, x0, 1))
	var left := float(_wet_run(on, off, row, x0, -1))
	return Vector2(
		maxf(right - absf(pr.x - center.x), 0.0),
		maxf(left - absf(pl.x - center.x), 0.0))

## Longueur (px) de pixels « mouillés » (diff A/B > seuil) depuis `x0`, dans
## le sens `dir` ; s'arrête après 8 pixels secs consécutifs.
func _wet_run(on: Image, off: Image, row: int, x0: int, dir: int) -> int:
	var w := on.get_width()
	var x := x0
	var dry := 0
	while x >= 0 and x < w and dry < 8:
		if _pixel_diff(on.get_pixel(x, row), off.get_pixel(x, row)) > SHORE_PIXEL_THR:
			dry = 0
		else:
			dry += 1
		x += dir
	return absi(x - x0) - 8

## Différence RGB moyenne (0..1) entre deux pixels.
func _pixel_diff(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0

# ===========================================================================
# Carte A — falaise
# ===========================================================================

## Carte type VILLE : quasi plate (relief absolu ~0,35 u), seules les cases de
## bord portent de petites buttes ondulées — le cas exact où l'auto-matériau
## par altitude relative déclenchait neige/terre sur des bosses de quelques
## centimètres (correctif `auto_min_relief`).
func _make_flat_city_map(md) -> Dictionary:
	var cw := 24
	var ch := 18
	var map: Dictionary = md.create_complex_map("Terrain ville plate", "general",
		"local", cw, ch)
	map["vegetationDensity"] = 0.0
	map["waterBodies"] = []
	map["fogEnabled"] = false
	var heights: Array = []
	heights.resize(cw * ch)
	var mats: Array = []
	mats.resize(cw * ch)
	mats.fill(0)
	for y in range(ch):
		for x in range(cw):
			var border := x < 2 or y < 2 or x > cw - 3 or y > ch - 3
			var value := 0.0
			if border:
				value = 0.16 * sin(float(x) * 0.52) * cos(float(y) * 0.44) \
					+ 0.06 * sin(float(x + y) * 0.85) + 0.04
			heights[y * cw + x] = value
			# Une bande de terre peinte pour juger le rendu « ville ».
			if y >= ch / 2 - 1 and y <= ch / 2:
				mats[y * cw + x] = 1
	map["terrainHeights"] = heights
	map["terrainMaterials"] = mats
	return map

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
	# Lac de plaine : la chaîne de berge (MapWater3D → terrain) est active.
	map["waterBodies"] = [
		{"id": "lac_plaine", "kind": "lake", "level": POND_LEVEL,
			"area": [[3.0, 2.0], [10.0, 2.0], [10.0, 9.0], [3.0, 9.0]]},
	]
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
			var h := MOUNTAIN_PLAIN_H + cone + rough * smoothstep(0.0, 2.0, cone)
			# Cuvette du lac de plaine (berge mouillée) : la plaine doit rester
			# AU-DESSUS du niveau d'eau partout ailleurs, sinon la texture de
			# berge couvrirait toute la carte.
			var pond := _pond_height(float(x), float(z))
			if pond < MOUNTAIN_PLAIN_H:
				h = minf(h, pond)
			heights[z * W + x] = maxf(0.0, h)
	return heights

## Cuvette du lac de plaine : fond plat circulaire (`POND_BED_R` cases) puis
## remontée des berges — RAIDE côté −x (`POND_RISE_STEEP` cases) et DOUCE
## côté +x (`POND_RISE_GENTLE` cases) — pour vérifier que la bande de berge
## mouillée est bien plus large côté faible pente.
func _pond_height(x: float, z: float) -> float:
	var px := x - POND_X
	var pz := z - POND_Z
	var pd := sqrt(px * px + pz * pz)
	if pd <= POND_BED_R:
		return 0.0
	var dir := px / maxf(pd, 0.001)
	var rise := lerpf(POND_RISE_STEEP, POND_RISE_GENTLE, dir * 0.5 + 0.5)
	return clampf((pd - POND_BED_R) / rise, 0.0, 1.0) * MOUNTAIN_PLAIN_H

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
