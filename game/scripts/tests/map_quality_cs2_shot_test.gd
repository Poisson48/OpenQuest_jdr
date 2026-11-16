extends SceneTree

## Captures A/B du **preset qualité CS2** sur une carte 2.5D peuplée d'objets 3D.
##
## Sujet : carte synthétique déterministe 40 × 30 cases (relief doux, rues de
## terre, place pavée) et **> 100 meshes 3D du catalogue** (`assets/objects3d`),
## pour juger le preset à l'échelle d'une vraie carte de jeu — le cas d'usage
## « carte cité » du chantier (même preset, mêmes assets).
##
## Pour CHAQUE cadrage (vue d'ensemble, gros plan de place), deux captures avec
## la MÊME caméra :
##   • `quality_cs2_off_*` — preset `classique` (rendu historique) ;
##   • `quality_cs2_on_*`  — preset `cinema` (ombres portées douces, AO/SSIL,
##     tonemap filmique, matériaux PBR éclairés, perspective aérienne).
##
## Vérifications : les deux images diffèrent nettement (diff moyenne), ne sont
## pas vides, et la bascule ne déplace PAS la caméra. Mesure de frame time et de
## draw calls pour les deux presets (note de perf du rapport).
##
## En `--headless` la capture est impossible : sortie `[SKIP]` (jamais de
## fenêtre qui volerait le focus pendant que quelqu'un joue).

const W := 40
const H := 30
const TARGET_MESHES := 100
## Seuils de différence moyenne (0..1) entre captures A/B.
const DIFF_MIN_OVERVIEW := 0.004
const DIFF_MIN_CLOSE := 0.006
## Cadrages.
const CLOSE_ZOOM := 2.6

const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")

var _failed: bool = false
var Engine3DScript: GDScript

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
	# Fenêtre plus large pour des captures lisibles (fenêtre cachée : no focus).
	get_root().size = Vector2i(1600, 900)
	await process_frame
	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(1600, 900)
	await process_frame

	var map: Dictionary = _build_map(md)
	var mesh_count := (map.get("meshes", []) as Array).size()
	print("  carte de test : %d × %d cases, %d meshes 3D" % [W, H, mesh_count])
	_assert("map_has_more_than_100_meshes", mesh_count >= TARGET_MESHES, "count=%d" % mesh_count)

	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(14):
		await process_frame
	_assert("preset_classique_default",
		engine.get_quality_preset() == MapRenderStyleScript.QUALITY_CLASSIQUE)

	# --- Cadrage 1 : vue d'ensemble déterministe --------------------------
	engine._fit_to_view()
	for _i in range(10):
		await process_frame
	_center_village(engine)
	for _i in range(8):
		await process_frame
	var cam_overview: Transform3D = engine._camera.transform
	var off_overview: Image = await _shot(engine, "quality_cs2_off_overview")
	# Bascule cinéma SANS toucher à la caméra.
	engine.set_quality_preset("cinema")
	for _i in range(14):
		await process_frame
	_assert("cinema_active", engine.is_cinema_quality())
	_assert("camera_unchanged_overview",
		engine._camera.transform.is_equal_approx(cam_overview))
	var on_overview: Image = await _shot(engine, "quality_cs2_on_overview")

	# --- Brume de hauteur adaptée au tilt (cas des captures « cité ») ------
	# Reproduit la config des cartes de démo : densité de distance légère 0,06,
	# composante hauteur par défaut (0,22). Ancien comportement = voile lavé ;
	# tilt-aware = carte nette en vue haute, brume conservée en vue rasante.
	engine.map_data["atmosphericFog"] = {"enabled": true, "density": 0.06}
	engine._apply_lighting()
	for _i in range(6):
		await process_frame
	var atmo_cam: Transform3D = engine._camera.transform
	var atmo_off: Image = await _tilt_aware_shot(engine, false, "quality_cs2_atmo_off")
	var atmo_on: Image = await _tilt_aware_shot(engine, true, "quality_cs2_atmo_on")
	var atmo_ref: Image = await _height_ref_shot(engine, "quality_cs2_atmo_ref")
	if atmo_off != null and atmo_on != null and atmo_ref != null:
		var d_off_on := _mean_diff(atmo_off, atmo_on)
		var d_off_ref := _mean_diff(atmo_off, atmo_ref)
		var d_on_ref := _mean_diff(atmo_on, atmo_ref)
		print("  [diff] atmo carte peuplée : OFF/ON %.4f | OFF↔référence claire %.4f | ON↔référence claire %.4f" % [
			d_off_on, d_off_ref, d_on_ref])
		_assert("atmo_veil_changes_image", d_off_on > 0.003, "diff=%.4f" % d_off_on)
		_assert("atmo_tilt_aware_clearer", d_on_ref < d_off_ref * 0.85,
			"on_ref=%.4f off_ref=%.4f" % [d_on_ref, d_off_ref])
	# Vue rasante héroïque : la brume de hauteur reste PLEINE (A/B identique).
	engine._camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	engine.sync_atmospheric_fog()
	for _i in range(6):
		await process_frame
	var atmo_low_off: Image = await _tilt_aware_shot(engine, false, "quality_cs2_atmo_low_off")
	var atmo_low_on: Image = await _tilt_aware_shot(engine, true, "quality_cs2_atmo_low_on")
	if atmo_low_off != null and atmo_low_on != null:
		var d_low := _mean_diff(atmo_low_off, atmo_low_on)
		print("  [diff] atmo vue rasante OFF/ON = %.4f (identique attendu)" % d_low)
		_assert("atmo_low_unchanged", d_low < 0.002, "diff=%.4f" % d_low)
	# Restaure la carte/caméra d'origine avant la suite (perf et captures).
	engine._camera.transform = atmo_cam
	engine.map_data.erase("atmosphericFog")
	engine._apply_lighting()
	engine.set_atmospheric_tilt_aware(true)
	for _i in range(6):
		await process_frame

	# --- Perf A/B sur ce cadrage (VSync coupé, 90 frames) -----------------
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var caster_total: int = engine.get_shadow_caster_count()
	var perf_on := await _measure(engine, 90)
	# Budget d'ombres réduit (10 cases autour du point visé) : moins d'ombres
	# projetées, donc moins de draw calls et un frame time plus bas.
	engine.set_shadow_budget_cells(10.0)
	for _i in range(6):
		await process_frame
	var active_budget: int = engine.get_active_shadow_casters()
	var budget_shot: Image = await _shot(engine, "quality_cs2_shadow_budget_serre")
	var perf_budget := await _measure(engine, 90)
	# Vue déplacée : avec le budget serré, les ombres suivent la zone regardée
	# (aucune reconstruction des objets ; hystérésis = pas de clignotement).
	engine.zoom = 1.45
	engine._update_ortho_size()
	engine._center_focus_on(Vector2(float(W) * 0.24 * engine._cell_size,
		float(H) * 0.26 * engine._cell_size))
	for _i in range(8):
		await process_frame
	var budget_moved_shot: Image = await _shot(engine, "quality_cs2_shadow_budget_deplace")
	engine.set_shadow_budget_cells(70.0)
	engine.zoom = 1.0
	engine._update_ortho_size()
	engine._fit_to_view()
	for _i in range(8):
		await process_frame
	engine.set_quality_preset("classique")
	for _i in range(10):
		await process_frame
	var perf_off := await _measure(engine, 90)
	print("  [perf] overview 1600×900, %d meshes : classique %.2f ms (%.0f fps, %d draw calls) / cinéma %.2f ms (%.0f fps, %d draw calls) — surcoût %+.1f%%" % [
		mesh_count,
		float(perf_off["frame_ms"]), float(perf_off["fps"]), int(perf_off["draw_calls"]),
		float(perf_on["frame_ms"]), float(perf_on["fps"]), int(perf_on["draw_calls"]),
		(float(perf_on["frame_ms"]) / maxf(0.01, float(perf_off["frame_ms"])) - 1.0) * 100.0,
	])
	print("  [perf] budget d'ombres 10 cases : cinéma %.2f ms (%.0f fps, %d draw calls) — casters %d/%d, draw calls %+.1f%% vs cinéma plein" % [
		float(perf_budget["frame_ms"]), float(perf_budget["fps"]), int(perf_budget["draw_calls"]),
		active_budget, caster_total,
		(float(perf_budget["draw_calls"]) / maxf(1.0, float(perf_on["draw_calls"])) - 1.0) * 100.0,
	])
	_assert("shadow_budget_some_casters", caster_total > 0)
	_assert("shadow_budget_reduces_active", active_budget < caster_total,
		"actifs=%d / %d" % [active_budget, caster_total])
	_assert("shadow_budget_reduces_draw_calls",
		int(perf_budget["draw_calls"]) < int(perf_on["draw_calls"]),
		"%d vs %d" % [int(perf_budget["draw_calls"]), int(perf_on["draw_calls"])])
	_assert("shadow_budget_capture_not_blank", not _is_blank(budget_shot))
	_assert("shadow_budget_moved_capture_not_blank", not _is_blank(budget_moved_shot))

	# --- Cadrage 2 : gros plan de la place (A/B même caméra) ---------------
	engine.zoom = CLOSE_ZOOM
	engine._update_ortho_size()
	_center_village(engine)
	for _i in range(10):
		await process_frame
	var cam_close: Transform3D = engine._camera.transform
	var off_close: Image = await _shot(engine, "quality_cs2_off_close")
	engine.set_quality_preset("cinema")
	for _i in range(14):
		await process_frame
	_assert("camera_unchanged_close", engine._camera.transform.is_equal_approx(cam_close))
	var on_close: Image = await _shot(engine, "quality_cs2_on_close")

	# --- Étalonnage : avant / après (même caméra, roofline au centre) ------
	# « Avant » = réglages du premier jet (saturation 1,10 / contraste 1,12 /
	# SSIL 1,0 / exposition ×0,97) ; « après » = planchers/plafonds adoucis
	# (saturation bornée à 1,08, contraste à 1,08, SSIL 0,85, exposition ×0,99).
	var eq_env: Environment = engine._world_env.environment
	var grade_contrast: float = eq_env.adjustment_contrast
	var grade_saturation: float = eq_env.adjustment_saturation
	var grade_exposure: float = eq_env.tonemap_exposure
	var grade_ssil: float = eq_env.ssil_intensity
	eq_env.adjustment_contrast = 1.12
	eq_env.adjustment_saturation = 1.10
	eq_env.tonemap_exposure = 0.97
	eq_env.ssil_intensity = 1.0
	var etal_avant: Image = await _shot(engine, "quality_cs2_etalonnage_avant")
	eq_env.adjustment_contrast = grade_contrast
	eq_env.adjustment_saturation = grade_saturation
	eq_env.tonemap_exposure = grade_exposure
	eq_env.ssil_intensity = grade_ssil
	var etal_apres: Image = await _shot(engine, "quality_cs2_etalonnage_apres")
	if etal_avant != null and etal_apres != null:
		var dgrade := _mean_diff(etal_avant, etal_apres)
		print("  [diff] étalonnage avant/après = %.4f (contraste %.2f / saturation %.2f)" % [
			dgrade, grade_contrast, grade_saturation])
		_assert("etalonnage_changes_image", dgrade > 0.0015, "diff=%.4f" % dgrade)
		_assert("etalonnage_avant_not_blank", not _is_blank(etal_avant))
		_assert("etalonnage_apres_not_blank", not _is_blank(etal_apres))

	# --- Diff A/B (preuves) -----------------------------------------------
	if off_overview != null and on_overview != null:
		var d := _mean_diff(off_overview, on_overview)
		print("  [diff] overview classique/cinéma = %.4f" % d)
		_assert("off_overview_not_blank", not _is_blank(off_overview))
		_assert("on_overview_not_blank", not _is_blank(on_overview))
		_assert("overview_differs", d > DIFF_MIN_OVERVIEW, "diff=%.4f" % d)
	if off_close != null and on_close != null:
		var d := _mean_diff(off_close, on_close)
		print("  [diff] close classique/cinéma = %.4f" % d)
		_assert("close_differs", d > DIFF_MIN_CLOSE, "diff=%.4f" % d)

	# --- Session de jeu : mêmes réglages que l'éditeur (2 captures A/B) ----
	# La session instancie un SECOND moteur 3D : les SubViewports partagent le
	# World3D racine (own_world_3d = false), donc on libère le moteur éditeur
	# avant de capturer la session — sinon la scène rendue contient deux copies
	# de la carte et deux soleils (artefact de banc d'essai, pas de jeu).
	engine.queue_free()
	for _i in range(5):
		await process_frame
	await _session_shots(map, cam_overview, on_overview)

	if _failed:
		print("map_quality_cs2_shot_test:FAIL")
		quit(1)
		return
	print("map_quality_cs2_shot_test:PASS")
	quit(0)

## Captures A/B via le VRAI hôte de rendu de session (`map_stage.tscn`), avec
## le chemin de données de session (`apply_session_lighting_to_map`) : le preset
## doit rendre pareil qu'en éditeur (mêmes ombres, mêmes matériaux).
func _session_shots(map: Dictionary, cam_reference: Transform3D, editor_cinema_shot: Image) -> void:
	var scene = load("res://scenes/session/panels/map_stage.tscn")
	_assert("session_scene_loaded", scene != null)
	if scene == null:
		return
	var stage: Control = scene.instantiate()
	get_root().add_child(stage)
	stage.size = Vector2(1600, 900)
	# Le moteur de session démarre caché (taille 0×0) : on lui donne tout de
	# suite une taille de rendu valide, sinon les buffers d'écran (SSIL/SSAO)
	# sont créés en 0×0 et le renderer spamme des erreurs pendant 2 frames.
	if stage._complex != null:
		stage._complex.size = Vector2(1600, 900)
		stage._complex.visible = true
	for _i in range(6):
		await process_frame
	var gd = get_root().get_node("GameData")
	_assert("session_stage_engine", stage._complex != null)
	if stage._complex == null:
		stage.queue_free()
		return
	# --- OFF : carte classique (sans clé) ---
	var off_map: Dictionary = map.duplicate(true)
	off_map.erase("qualityPreset")
	stage.configure(_session_payload(gd.call("apply_session_lighting_to_map", off_map)))
	for _i in range(14):
		await process_frame
	var session_engine = stage._complex
	_assert("session_off_classique",
		session_engine.get_quality_preset() == MapRenderStyleScript.QUALITY_CLASSIQUE)
	session_engine._fit_to_view()
	for _i in range(10):
		await process_frame
	var cell: float = float(session_engine._cell_size)
	session_engine._center_focus_on(Vector2(float(W) * 0.5 * cell, float(H) * 0.5 * cell))
	for _i in range(8):
		await process_frame
	# Caméra IDENTIQUE à la capture éditeur (comparaison directe des rendus).
	# On laisse d'abord le cadrage différé de la session se stabiliser, puis on
	# annule tout recadrage en attente avant d'imposer la caméra de référence.
	for _i in range(24):
		await process_frame
	session_engine._fit_pending = false
	session_engine._camera.transform = cam_reference
	for _i in range(10):
		await process_frame
	session_engine._fit_pending = false
	session_engine._camera.transform = cam_reference
	await process_frame
	_assert("session_camera_reference",
		session_engine._camera.transform.is_equal_approx(cam_reference))
	var session_cam: Transform3D = session_engine._camera.transform
	var off_shot: Image = await _shot(session_engine, "quality_cs2_session_off")
	# --- ON : la clé `qualityPreset` de la carte est relue par la session ---
	var on_map: Dictionary = map.duplicate(true)
	on_map["qualityPreset"] = MapRenderStyleScript.QUALITY_CINEMA
	stage.configure(_session_payload(gd.call("apply_session_lighting_to_map", on_map)))
	for _i in range(16):
		await process_frame
	_assert("session_on_cinema", session_engine.is_cinema_quality())
	_assert("session_on_ssil", session_engine._world_env.environment.ssil_enabled)
	_assert("session_on_shadows",
		session_engine._sun.directional_shadow_mode
			== DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_assert("session_camera_preserved",
		session_engine._camera.transform.is_equal_approx(session_cam))
	var session_env: Environment = session_engine._world_env.environment
	print("  [session] env tonemap_white=%.2f exposure=%.2f ssao=%.2f ssil=%s glow=%.3f contrast=%.2f sat=%.2f sun_shadow=%s mode=%d dof=%s ground=%s" % [
		session_env.tonemap_white, session_env.tonemap_exposure,
		session_env.ssao_intensity, str(session_env.ssil_enabled),
		session_env.glow_intensity, session_env.adjustment_contrast,
		session_env.adjustment_saturation, str(session_engine._sun.shadow_enabled),
		session_engine._sun.directional_shadow_mode,
		str(session_engine.get_camera_attributes() != null),
		session_engine.get_ground_mode(),
	])
	var on_shot: Image = await _shot(session_engine, "quality_cs2_session_on")
	if off_shot != null and on_shot != null:
		var d := _mean_diff(off_shot, on_shot)
		print("  [diff] session classique/cinéma = %.4f" % d)
		_assert("session_off_not_blank", not _is_blank(off_shot))
		_assert("session_on_not_blank", not _is_blank(on_shot))
		_assert("session_differs", d > DIFF_MIN_OVERVIEW, "diff=%.4f" % d)
		if editor_cinema_shot != null:
			var de := _mean_diff(on_shot, editor_cinema_shot)
			print("  [diff] session cinéma vs éditeur cinéma (même caméra) = %.4f" % de)
			_assert("session_matches_editor", de < 0.03, "diff=%.4f" % de)
	stage.queue_free()
	for _i in range(3):
		await process_frame

func _session_payload(display_map: Dictionary) -> Dictionary:
	return {
		"map": display_map,
		"mode": "complex",
		"tokens": [],
		"party": [],
		"effects": [],
		"zones": [],
		"fog_revealed": [],
		"readonly": false,
		"is_gm": true,
		"tool": {"mode": "select"},
		"view_state": {},
		"selected_token": "",
		"quest_format": "oneshot",
	}

# ===========================================================================
# Carte de test : diorama 40 × 30 peuplé
# ===========================================================================

func _build_map(md) -> Dictionary:
	var map := {
		"id": "quality-cs2-shot-map",
		"name": "Valbois — carte démo qualité CS2",
		"width": W,
		"height": H,
		"renderMode": "complex",
		"renderStyle": "2.5d",
		"groundMode": "terrain3d",
		"backgroundImage": "",
		"fogEnabled": false,
		"grid": {"size": 70, "show": false},
		"lighting": {"enabled": false, "preset": "jour", "sources": [], "nightMode": false},
		"atmosphere": {"enabled": false, "tint": "#1a1410", "opacity": 0.0, "vignette": 0.0},
		"ambientFx": "",
		"vegetationEnabled": false,
		"meshes": [],
		"walls": [],
		"props": [],
		"terrainHeights": [],
		"terrainMaterials": [],
	}
	map["terrainHeights"] = _make_heights()
	map["terrainMaterials"] = _make_materials()
	map["meshes"] = _make_meshes()
	return map

## Relief doux : collines basses autour d'une place centrale aplatie (0.0).
func _make_heights() -> Array:
	var heights: Array = []
	heights.resize(W * H)
	for y in range(H):
		for x in range(W):
			var h := 0.34 * sin(float(x) * 0.33) * cos(float(y) * 0.27)
			h += 0.18 * sin(float(x + y) * 0.55)
			# Place centrale aplatie (la caméra de gros plan s'y pose).
			var d := Vector2(x, y).distance_to(Vector2(W * 0.5, H * 0.5))
			if d < 7.0:
				h = lerpf(0.0, h, clampf((d - 4.5) / 2.5, 0.0, 1.0))
			# Lisière plus vallonnée : le fond de carte respire.
			if y < 3 or y > H - 4 or x < 3 or x > W - 4:
				h += 0.45 * (0.5 + 0.5 * sin(float(x) * 0.7 + float(y) * 0.9))
			heights[y * W + x] = h
	return heights

## Matières : herbe partout, deux rues de terre croisées, place pavée.
func _make_materials() -> Array:
	var materials: Array = []
	materials.resize(W * H)
	materials.fill(0)
	var cx := W * 0.5
	var cy := H * 0.5
	for y in range(H):
		for x in range(W):
			var idx := y * W + x
			var road := absf(float(x) - 13.0) < 1.2 or absf(float(x) - 27.0) < 1.2 \
				or absf(float(y) - 10.0) < 1.2 or absf(float(y) - 21.0) < 1.2
			var d := Vector2(x, y).distance_to(Vector2(cx, cy))
			if d < 3.6:
				materials[idx] = 2   # place pavée
			elif d < 5.2 or road:
				materials[idx] = 1   # terre / chemin
	return materials

## Placement déterministe : bâtiments en îlots, végétation et props en bordure.
func _make_meshes() -> Array:
	var library = load("res://scripts/maps/map_asset_library.gd")
	var assets: Array = library.list_object3d_assets()
	var by_name: Dictionary = {}
	for asset_variant in assets:
		var asset: Dictionary = asset_variant
		var key := str(asset.get("name", "")).to_lower().replace("_", " ").replace("-", " ")
		by_name[key] = str(asset.get("path", ""))
	var buildings := ["maison", "maison_petite", "maison_grande", "maison_etage",
		"manoir", "forge", "chapelle", "grange", "ecurie", "tour", "tour_grande",
		"tour_guet_bois", "marche_couvert"]
	var nature := ["arbre", "arbre_automne", "arbre_majestueux", "buisson", "bosquet",
		"haie", "roseaux", "rocher", "gros_rocher", "falaise", "galets_de_rive"]
	var props := ["puits", "fontaine", "charrette", "tonneau", "banc", "lanterne",
		"etal_marche", "banniere", "caisse", "caisse_grande", "palissade", "barriere",
		"cloture_basse", "tas_de_bois", "botte_foin", "panneau", "enseigne", "ponton",
		"barque", "nenuphars"]
	var meshes: Array = []
	var cx := W * 0.5
	var cy := H * 0.5
	var index := 0
	for gy in range(2, H - 2, 3):
		for gx in range(2, W - 2, 3):
			# Rues et place : on laisse respirer (props posés plus bas).
			var on_road := absf(float(gx) - 13.0) < 2.0 or absf(float(gx) - 27.0) < 2.0 \
				or absf(float(gy) - 10.0) < 2.0 or absf(float(gy) - 21.0) < 2.0
			var d_center := Vector2(gx, gy).distance_to(Vector2(cx, cy))
			if on_road or d_center < 4.2:
				continue
			var pool: Array = buildings if d_center < 13.0 else nature
			var pick := str(pool[(gx * 7 + gy * 13) % pool.size()])
			_add_mesh(meshes, by_name, pick, gx, gy, index,
				pick in nature, 0.0)
			index += 1
	# Props le long des rues et sur la place (vie du village).
	var prop_rows := [
		[9.0, 2, 37, 5], [22.0, 2, 37, 5],
	]
	for row in prop_rows:
		var y := float(row[0])
		var x := float(row[1])
		while x < float(row[2]):
			var pick := str(props[(int(x) + int(y)) % props.size()])
			_add_mesh(meshes, by_name, pick, x, y, index, false, 0.0)
			index += 1
			x += 3.5
	var around := [[13.0, 3, 5], [13.0, 27, 5], [27.0, 3, 5], [27.0, 27, 5],
		[8.0, 10.0, 3], [32.0, 21.0, 3]]
	for spec in around:
		var pick := str(props[(int(spec[0]) + int(spec[1])) % props.size()])
		_add_mesh(meshes, by_name, pick, spec[0], spec[1], index, false, 0.0)
		index += 1
	# Lisière boisée : cadre végétal du diorama (dense mais hors des îlots).
	for x in range(1, W - 1, 2):
		var pick := "arbre" if (x / 2) % 2 == 0 else "buisson"
		_add_mesh(meshes, by_name, pick, float(x), 1.0, index, true, 0.0)
		index += 1
		pick = "arbre_automne" if (x / 2) % 2 == 0 else "bosquet"
		_add_mesh(meshes, by_name, pick, float(x), float(H - 2), index, true, 0.0)
		index += 1
	# Couronne de props autour de la place (marché, mobilier, végétation).
	var ring_assets := ["lanterne", "banc", "tonneau", "caisse", "banniere",
		"charrette", "etal_marche", "buisson", "rocher", "haie"]
	for i in range(10):
		var angle := float(i) * TAU / 10.0
		var rx := cx + 5.4 * cos(angle)
		var ry := cy + 5.4 * sin(angle)
		_add_mesh(meshes, by_name, str(ring_assets[i]), rx, ry, index,
			ring_assets[i] in ["buisson", "rocher", "haie"], 0.0)
		index += 1
	# Fontaine au centre de la place (point de mire des captures).
	_add_mesh(meshes, by_name, "fontaine", cx, cy, index, false, 0.0)
	index += 1
	# Personnages : une petite foule sur la place.
	var people := ["pnj_marchand", "pnj_villageois", "pnj_garde", "pnj_aventurier",
		"pnj_archere", "pnj_mage", "pnj_voleuse", "pnj_pretresse", "pnj_gobelin"]
	var pi := 0
	for p in people:
		var px := cx + 2.4 * cos(float(pi) * 0.7)
		var py := cy + 2.4 * sin(float(pi) * 0.7)
		_add_mesh(meshes, by_name, p, px, py, index, false, 0.0)
		index += 1
		pi += 1
	return meshes

func _add_mesh(meshes: Array, by_name: Dictionary, asset_name: String,
		gx: float, gy: float, index: int, tilt: bool, elevation: float) -> void:
	var key := asset_name.to_lower().replace("_", " ").replace("-", " ")
	var path := str(by_name.get(key, ""))
	if path.is_empty():
		return
	meshes.append({
		"id": "cs2-%s-%d" % [asset_name, index],
		"kind": "mesh",
		"asset": path,
		"x": gx,
		"y": gy,
		"w": maxf(1.0, 1.5 if asset_name.begins_with("maison") or asset_name == "manoir" else 1.0),
		"h": maxf(1.0, 1.5 if asset_name.begins_with("maison") or asset_name == "manoir" else 1.0),
		"elevation": elevation,
		"followTerrain": true,
		"tiltToTerrain": tilt,
		"label": asset_name.capitalize(),
		"layer": 1,
		"display": {"rotation": float((index * 37) % 4) * 90.0, "scale": 1.0},
	})

## Cadre la place centrale (sans dépendre du pointeur souris).
func _center_village(engine: Control) -> void:
	var cell: float = engine._cell_size
	engine._center_focus_on(Vector2(float(W) * 0.5 * cell, float(H) * 0.5 * cell))

# ===========================================================================
# Captures et mesures
# ===========================================================================

func _shot(engine: Control, shot_name: String) -> Image:
	for _i in range(5):
		await process_frame
	# Capture DIRECTE du SubViewport du moteur (pas de la fenêtre hôte : en
	# session le moteur est embarqué dans un panneau et le rendu écran peut être
	# réutilisé tel quel d'une frame à l'autre).
	var viewport = engine.get("_viewport")
	if viewport == null:
		viewport = engine.get_viewport()
	var tex = viewport.get_texture() if viewport != null else null
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		# GPU partagé : une deuxième chance après 5 s.
		await create_timer(5.0).timeout
		tex = viewport.get_texture() if viewport != null else null
		img = tex.get_image() if tex != null else null
	if img == null:
		_assert("capture_%s" % shot_name, false, "texture indisponible")
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s.png" % shot_name)
	img.save_png(out)
	print("  capture: %s (%d×%d)" % [out, img.get_width(), img.get_height()])
	_assert("capture_%s_not_blank" % shot_name, not _is_blank(img))
	return img

## Capture avec pondération de hauteur de brume dans l'état demandé, puis
## restaure le tilt-aware actif (les captures finissent en config normale).
func _tilt_aware_shot(engine: Control, tilt_aware: bool, shot_name: String) -> Image:
	engine.set_atmospheric_tilt_aware(tilt_aware)
	for _i in range(4):
		await process_frame
	var env = engine._world_env.environment
	print("  [atmo] aware=%s factor=%.2f heightDensity=%.3f fog_density=%.3f" % [
		str(tilt_aware), engine.get_atmospheric_fog_height_factor(),
		env.fog_height_density, env.fog_density])
	return await _shot(engine, shot_name)

## Capture de référence « claire » : composante hauteur forcée à 0, puis carte
## restaurée (montre à quel point le tilt-aware se rapproche du rendu net).
func _height_ref_shot(engine: Control, shot_name: String) -> Image:
	var saved = engine.map_data.get("atmosphericFog")
	var ref_cfg: Dictionary = (saved as Dictionary).duplicate(true) \
		if saved is Dictionary else {}
	ref_cfg["enabled"] = true
	ref_cfg["density"] = 0.06
	ref_cfg["heightDensity"] = 0.0
	engine.map_data["atmosphericFog"] = ref_cfg
	engine._apply_lighting()
	for _i in range(4):
		await process_frame
	var img: Image = await _shot(engine, shot_name)
	engine.map_data["atmosphericFog"] = saved
	engine._apply_lighting()
	engine.set_atmospheric_tilt_aware(true)
	for _i in range(3):
		await process_frame
	return img

func _measure(engine: Control, frames: int) -> Dictionary:
	for _i in range(4):
		await process_frame
	var t0 := Time.get_ticks_usec()
	for _i in range(frames):
		await process_frame
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var frame_ms := elapsed_ms / float(maxi(1, frames))
	return {
		"frame_ms": frame_ms,
		"fps": 1000.0 / maxf(0.01, frame_ms),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}

func _mean_diff(a: Image, b: Image) -> float:

	if a == null or b == null or a.get_size() != b.get_size():
		return 1.0
	var w := a.get_width()
	var h := a.get_height()
	var step := maxi(1, int(float(w) / 200.0))
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
	if img == null or img.get_width() <= 0:
		return true
	var step := maxi(1, int(float(img.get_width()) / 40.0))
	var first := img.get_pixel(0, 0)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if not c.is_equal_approx(first):
				return false
	return true

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  OK  ", assert_name)
	else:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
