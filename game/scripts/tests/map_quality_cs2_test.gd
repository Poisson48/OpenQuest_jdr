extends SceneTree

## Preset qualité « CS2 » de la carte 2.5D — A/B réversible, opt-in.
##
## Couvre, sans rendu réel (headless) :
##   1. Résolution du preset : `classique` par défaut (clé absente ou inconnue),
##      `cinema` opt-in, variantes d'écriture tolérées.
##   2. Config de style : le preset `classique` est STRICTEMENT identique à
##      l'historique (`CONFIGS`), `cinema` active ombres douces + matériaux
##      éclairés SANS toucher caméra/parallaxe/tilt (identité Valbois 2.5D).
##   3. Sérialisation : `map_data["qualityPreset"]` survit à `to_map_data()` et
##      à un aller-retour JSON (export/import de carte), avec undo réversible.
##   4. Calque `MapMeshes3D` : classique = cast_shadow OFF + UNSHADED comme
##      avant ; cinéma = cast_shadow ON sur les meshes importés (jamais la coque
##      `*_outline`), matériaux PBR éclairés, perspective aérienne, ombre de
##      contact atténuée.
##   5. Moteur `ComplexMapEngine3D` : bascule `set_quality_preset()` sans
##      reconstruire la carte, valeurs A/B exactement restaurées, et preset
##      relu depuis des données chargées (JSON) — le cas des cartes démo/cité.

const StyleScript := preload("res://scripts/maps/map_render_style.gd")
const Meshes3DScript := preload("res://scripts/maps/map_layers/map_meshes_3d.gd")

const REAL_GLB := "res://assets/objects3d/buildings/maison.glb"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_resolution()
	_test_classique_identical()
	_test_cinema_config()
	_test_serialization()
	await _test_meshes_layer()
	await _test_shadow_budget()
	await _test_engine_ab()
	await _test_session_preset()
	await _test_atmosphere_tilt()
	await _test_editor_ui()
	if _failed:
		quit(1)
		return
	print("map_quality_cs2_test:PASS")
	quit(0)

# ===========================================================================
# 1. Résolution
# ===========================================================================

func _test_resolution() -> void:
	_assert("default_classique", StyleScript.quality_preset({}) == StyleScript.QUALITY_CLASSIQUE)
	_assert("default_not_cinema", not StyleScript.is_cinema({}))
	_assert("explicit_classique",
		StyleScript.quality_preset({"qualityPreset": "classique"}) == StyleScript.QUALITY_CLASSIQUE)
	_assert("explicit_cinema",
		StyleScript.quality_preset({"qualityPreset": "cinema"}) == StyleScript.QUALITY_CINEMA)
	_assert("cinema_is_cinema", StyleScript.is_cinema({"qualityPreset": "cinema"}))
	_assert("cinema_accent",
		StyleScript.quality_preset({"qualityPreset": "Cinéma"}) == StyleScript.QUALITY_CINEMA)
	_assert("cinema_alias_cs2",
		StyleScript.quality_preset({"qualityPreset": " cs2 "}) == StyleScript.QUALITY_CINEMA)
	_assert("unknown_falls_back_classique",
		StyleScript.quality_preset({"qualityPreset": "ultra"}) == StyleScript.QUALITY_CLASSIQUE)
	_assert("empty_value_classique",
		StyleScript.quality_preset({"qualityPreset": ""}) == StyleScript.QUALITY_CLASSIQUE)
	_assert("presets_catalog", StyleScript.QUALITY_PRESETS.size() == 2)
	_assert("labels_present",
		not StyleScript.quality_label(StyleScript.QUALITY_CINEMA).is_empty()
		and not StyleScript.quality_hint(StyleScript.QUALITY_CINEMA).is_empty())
	_assert("cinema_label_readable",
		StyleScript.quality_label(StyleScript.QUALITY_CINEMA).contains("Cinéma"))

# ===========================================================================
# 2. Configuration du style (non-régression classique + effet cinéma)
# ===========================================================================

func _test_classique_identical() -> void:
	# Clé absente, clé classique explicite : même config, identique à CONFIGS.
	for style in [StyleScript.MAP_25D, StyleScript.DIORAMA, StyleScript.VTT, StyleScript.DD2_HYBRID]:
		var expected: Dictionary = (StyleScript.CONFIGS[style] as Dictionary).duplicate(true)
		var without_key := StyleScript.config({"renderStyle": style})
		var explicit := StyleScript.config({"renderStyle": style, "qualityPreset": "classique"})
		_assert("classique_cfg_identical_%s" % style, _same_json(without_key, expected),
			"cfg=%s attendu=%s" % [JSON.stringify(without_key), JSON.stringify(expected)])
		_assert("classique_cfg_explicit_%s" % style, _same_json(explicit, expected))
	# Le preset n'est pas un style : la résolution de style est intacte.
	var cinema_map := {"renderStyle": "2.5d", "qualityPreset": "cinema"}
	_assert("cinema_keeps_style",
		StyleScript.style_of(cinema_map) == StyleScript.MAP_25D
		and StyleScript.is_map_25d(cinema_map)
		and StyleScript.is_diorama(cinema_map))

func _test_cinema_config() -> void:
	var base := {"renderStyle": "2.5d", "groundMode": "terrain3d"}
	var classique := StyleScript.config(base)
	var cinema := StyleScript.config({
		"renderStyle": "2.5d", "groundMode": "terrain3d", "qualityPreset": "cinema"})
	# Identité de mise en scène : caméra, parallaxe et profondeur inchangées.
	for key in ["perspective", "fov", "tilt", "parallax", "depthFade", "preferFlatProps",
			"volumetricWalls", "groundTint"]:
		_assert("cinema_keeps_%s" % key, cinema.get(key) == classique.get(key),
			"%s cinéma=%s classique=%s" % [key, cinema.get(key), classique.get(key)])
	# Ombres portées réelles du soleil + ombres douces.
	_assert("cinema_shadows", bool(cinema.get("shadows", false)))
	_assert("cinema_soft_shadows", bool(cinema.get("softShadows", false)))
	_assert("cinema_shadow_blur", float(cinema.get("shadowBlur", 0.0)) >= 2.0)
	# Pénombre par le blur, pas par la taille angulaire (évite le dithering).
	_assert("cinema_shadow_angular_zero",
		is_zero_approx(float(cinema.get("shadowAngular", 1.0))))
	# Matériaux importés en PBR éclairé + perspective aérienne.
	_assert("cinema_lit_props", bool(cinema.get("litProps", false)))
	_assert("cinema_depth_tint", float(cinema.get("depthTint", 0.0)) > 0.0)
	_assert("cinema_contact_shadow_attenuated",
		float(cinema.get("contactShadowScale", 1.0)) < 0.8)
	# Post-traitement : AO/SSIL renforcés, glow maîtrisé, tonemap filmique.
	_assert("cinema_cinema_quality", bool(cinema.get("cinemaQuality", false)))
	_assert("cinema_ssil", bool(cinema.get("ssil", false)))
	_assert("cinema_ssao_boost",
		float(cinema.get("ssaoIntensity", 0.0)) > float(classique.get("ssaoIntensity", 0.0)) + 0.2
		or float(classique.get("ssaoIntensity", 0.0)) == 0.0)
	_assert("cinema_glow_controlled", float(cinema.get("glowIntensityScale", 1.0)) < 1.0)
	_assert("cinema_tonemap_white", float(cinema.get("tonemapWhite", 1.0)) > 1.0)
	_assert("cinema_contrast_floor", float(cinema.get("contrastFloor", 1.0)) >= 1.08)
	_assert("cinema_shadow_budget", float(cinema.get("shadowDistance", -1.0)) > 0.0)
	_assert("classique_has_no_quality_keys",
		not classique.has("cinemaQuality") and not classique.has("softShadows"))
	# Perspective aérienne : loin teinté, premier plan intact.
	var near_tint := StyleScript.quality_aerial_tint(1.0, cinema)
	var far_tint := StyleScript.quality_aerial_tint(0.0, cinema)
	_assert("aerial_near_intact", near_tint.is_equal_approx(Color.WHITE))
	_assert("aerial_far_tinted", not far_tint.is_equal_approx(Color.WHITE) and far_tint.r > 0.5)
	_assert("aerial_classique_none",
		StyleScript.quality_aerial_tint(0.0, classique).is_equal_approx(Color.WHITE))
	# Fond illustré : la carte garde ses objets « dessinés » (pas d'ombres, pas
	# de PBR) mais gagne le post-traitement cinéma.
	var illustrated := StyleScript.config({
		"renderStyle": "2.5d", "backgroundImage": "res://fake.png",
		"qualityPreset": "cinema"})
	_assert("illustrated_cinema_no_shadows", not bool(illustrated.get("shadows", true)))
	_assert("illustrated_cinema_no_lit", not bool(illustrated.get("litProps", true)))
	_assert("illustrated_cinema_post", bool(illustrated.get("cinemaQuality", false))
		and float(illustrated.get("tonemapWhite", 1.0)) > 1.0)
	# Surcharges explicites de la carte : priorité absolue (A/B manuel).
	var overridden := StyleScript.config({
		"renderStyle": "2.5d", "qualityPreset": "cinema",
		"renderStyleOverrides": {"shadows": false, "shadowBlur": 0.5}})
	_assert("override_wins_over_cinema",
		not bool(overridden.get("shadows", true))
		and is_equal_approx(float(overridden.get("shadowBlur", 0.0)), 0.5))

# ===========================================================================
# 3. Sérialisation (données de carte + JSON)
# ===========================================================================

func _test_serialization() -> void:
	var Doc = load("res://scripts/maps/editor/map_edit_document.gd")
	var doc = Doc.new()
	doc.load_map({"id": "quality-test", "name": "Qualité", "width": 12, "height": 10})
	_assert("doc_default_classique",
		StyleScript.quality_preset(doc.map_data) == StyleScript.QUALITY_CLASSIQUE)
	# Bascule documentée : delta d'historique → undo réversible.
	doc.set_meta_values({"qualityPreset": "cinema"}, "Qualité de rendu")
	_assert("doc_write_cinema",
		str(doc.map_data.get("qualityPreset", "")) == "cinema"
		and StyleScript.is_cinema(doc.map_data))
	_assert("doc_history_reversible", doc.can_undo())
	var snapshot: Dictionary = doc.to_map_data()
	_assert("doc_to_map_data_keeps_key", str(snapshot.get("qualityPreset", "")) == "cinema")
	# Aller-retour JSON : c'est le format d'export/import des cartes.
	var json := JSON.stringify(snapshot)
	var parsed = JSON.parse_string(json)
	_assert("json_parse_ok", parsed is Dictionary)
	if parsed is Dictionary:
		_assert("json_keeps_quality",
			str((parsed as Dictionary).get("qualityPreset", "")) == "cinema")
		var doc2 = Doc.new()
		doc2.load_map(parsed)
		_assert("json_reload_cinema",
			StyleScript.quality_preset(doc2.map_data) == StyleScript.QUALITY_CINEMA)
	# Retour au classique = rendu d'origine (clé conservée mais résolue classique).
	doc.set_meta_values({"qualityPreset": "classique"}, "Qualité de rendu")
	_assert("doc_back_to_classique",
		StyleScript.quality_preset(doc.map_data) == StyleScript.QUALITY_CLASSIQUE)
	# Undo : le preset revient à l'état précédent sans casser le document.
	_assert("doc_undo", doc.undo())
	_assert("doc_undo_restores_cinema", StyleScript.is_cinema(doc.map_data))

# ===========================================================================
# 4. Calque des objets 3D (ombres + matériaux)
# ===========================================================================

func _make_map(quality: String) -> Dictionary:
	var map := {
		"id": "quality-meshes-%s" % quality,
		"name": "Qualité meshes",
		"width": 12,
		"height": 10,
		"renderStyle": "2.5d",
		"groundMode": "terrain3d",
		"backgroundImage": "",
		"atmosphere": {"enabled": false, "tint": "#141018", "opacity": 0.0, "vignette": 0.0},
		"meshes": [
			# Fond de carte (y petit = lointain) : doit être teinté.
			{"id": "far", "kind": "mesh", "asset": "", "x": 2.0, "y": 0.0},
			# Premier plan (y grand) : teinte nulle.
			{"id": "near", "kind": "mesh", "asset": "", "x": 2.0, "y": 9.0},
		],
	}
	if quality == "cinema":
		map["qualityPreset"] = "cinema"
	return map

func _find_child_with_meta(node: Node, meta_name: String) -> Node:
	if node == null:
		return null
	for child in node.get_children():
		if child.has_meta(meta_name):
			return child
		var nested := _find_child_with_meta(child, meta_name)
		if nested != null:
			return nested
	return null

func _test_meshes_layer() -> void:
	for quality in ["classique", "cinema"]:
		var layer: Node3D = Meshes3DScript.new()
		get_root().add_child(layer)
		var map := _make_map(quality)
		layer.configure(map["meshes"], 1.0, map)
		_assert("layer_built_%s" % quality, layer.has_mesh("far") and layer.has_mesh("near"))
		var far_root: Node3D = layer._nodes.get("far")
		var near_root: Node3D = layer._nodes.get("near")
		var far_visual := _find_child_with_meta(far_root, "fallback") as MeshInstance3D
		var near_visual := _find_child_with_meta(near_root, "fallback") as MeshInstance3D
		if far_visual == null or near_visual == null:
			_assert("layer_visual_%s" % quality, false)
			layer.queue_free()
			continue
		var far_mat := far_visual.material_override as StandardMaterial3D
		var near_mat := near_visual.material_override as StandardMaterial3D
		_assert("layer_material_%s" % quality, far_mat != null and near_mat != null)
		if quality == "classique":
			# Rend historique strictement inchangé : pas d'ombre, non éclairé.
			_assert("classique_no_cast_shadow",
				far_visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			_assert("classique_unshaded",
				far_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
			# Ombre de contact pleine (0.25 au centre).
			var shadow := _find_child_with_meta(far_root, "contact_shadow") as MeshInstance3D
			var shadow_mat: StandardMaterial3D = null
			if shadow != null and shadow.material_override is StandardMaterial3D:
				shadow_mat = shadow.material_override as StandardMaterial3D
			if shadow_mat != null and shadow_mat.albedo_texture is GradientTexture2D:
				var alpha: float = (shadow_mat.albedo_texture as GradientTexture2D).gradient.get_color(0).a
				_assert("classique_contact_shadow_full", alpha >= 0.20)
			else:
				_assert("classique_contact_shadow_full", false)
		else:
			# Cinéma : ombres portées réelles + matériaux PBR éclairés.
			_assert("cinema_cast_shadow",
				far_visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			_assert("cinema_lit_material",
				far_mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)
			_assert("cinema_vertex_colors", far_mat.vertex_color_use_as_albedo)
			_assert("cinema_matte", far_mat.roughness >= 0.85 and is_zero_approx(far_mat.metallic))
			# Perspective aérienne : le fond est plus clair que le premier plan.
			_assert("cinema_aerial_depth",
				far_mat.albedo_color.get_luminance() > near_mat.albedo_color.get_luminance() + 0.01,
				"far=%s near=%s" % [str(far_mat.albedo_color), str(near_mat.albedo_color)])
			var shadow := _find_child_with_meta(far_root, "contact_shadow") as MeshInstance3D
			var shadow_mat: StandardMaterial3D = null
			if shadow != null and shadow.material_override is StandardMaterial3D:
				shadow_mat = shadow.material_override as StandardMaterial3D
			if shadow_mat != null and shadow_mat.albedo_texture is GradientTexture2D:
				var alpha: float = (shadow_mat.albedo_texture as GradientTexture2D).gradient.get_color(0).a
				_assert("cinema_contact_shadow_attenuated", alpha <= 0.16,
					"alpha=%f" % alpha)
			else:
				_assert("cinema_contact_shadow_attenuated", false)
			# La coque d'encre ne projette jamais d'ombre : vérifié sur un vrai
			# GLB quand il est importé (sinon fallback, test ignoré proprement).
			_check_outline_shadows()
		layer.queue_free()
		await process_frame

func _check_outline_shadows() -> void:
	if not ResourceLoader.exists(REAL_GLB):
		print("  (outline: GLB non importé, vérification ignorée)")
		return
	var layer: Node3D = Meshes3DScript.new()
	get_root().add_child(layer)
	var map := _make_map("cinema")
	map["meshes"] = [{"id": "real", "kind": "mesh", "asset": REAL_GLB,
		"x": 5.0, "y": 5.0, "w": 2.0, "h": 2.0, "sizeX": 2.0, "sizeZ": 2.0}]
	layer.configure(map["meshes"], 1.0, map)
	var root: Node3D = layer._nodes.get("real")
	_assert("outline_real_loaded", root != null and not layer.is_fallback("real"))
	var meshes := _collect_mesh_instances(root)
	if meshes.is_empty():
		print("  (outline: aucun MeshInstance3D, vérification ignorée)")
		layer.queue_free()
		return
	var outlines := 0
	var casters := 0
	for mesh_instance in meshes:
		if str((mesh_instance as Node).name).to_lower().contains("outline"):
			outlines += 1
			_assert("outline_never_casts",
				(mesh_instance as GeometryInstance3D).cast_shadow
					== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		else:
			casters += 1
			_assert("imported_mesh_casts",
				(mesh_instance as GeometryInstance3D).cast_shadow
					== GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	# Le GLB maison contient bien la coque d'encre + le mesh principal.
	_assert("outline_present", outlines >= 1)
	_assert("caster_present", casters >= 1)
	layer.queue_free()

func _visual_casts(root: Node) -> bool:
	var visual := _find_child_with_meta(root, "fallback") as GeometryInstance3D
	if visual == null:
		var meshes := _collect_mesh_instances(root)
		if meshes.is_empty():
			return false
		visual = meshes[0] as GeometryInstance3D
	return visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# ===========================================================================
# 5 bis. Session de jeu : même rendu, clé de preset conservée
# ===========================================================================

func _test_session_preset() -> void:
	var stage_scene = load("res://scenes/session/panels/map_stage.tscn")
	_assert("session_stage_scene", stage_scene != null)
	if stage_scene == null:
		return
	var stage: Control = stage_scene.instantiate()
	get_root().add_child(stage)
	stage.size = Vector2(1280, 720)
	await _wait_frames(4)
	_assert("session_stage_ready", stage._complex != null)
	if stage._complex == null:
		stage.queue_free()
		return
	var map := _make_engine_map("cinema")
	var payload := {
		"map": map, "mode": "complex", "tokens": [], "party": [],
		"effects": [], "zones": [], "fog_revealed": [],
		"readonly": false, "is_gm": true, "tool": {"mode": "select"},
		"view_state": {}, "selected_token": "", "quest_format": "oneshot",
	}
	stage.configure(payload)
	await _wait_frames(10)
	var session_engine = stage._complex
	_assert("session_preset_cinema",
		session_engine.get_quality_preset() == StyleScript.QUALITY_CINEMA
		and session_engine.is_cinema_quality())
	var session_env: Environment = session_engine._world_env.environment
	_assert("session_cinema_ssil", session_env.ssil_enabled)
	_assert("session_cinema_shadow_mode",
		session_engine._sun.directional_shadow_mode
			== DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_assert("session_cinema_mesh_lit", _session_mesh_lit(session_engine))
	_assert("session_quality_key_preserved",
		str(map.get("qualityPreset", "")) == StyleScript.QUALITY_CINEMA)
	# Les rafraîchissements de session (mouvement, refresh UI) rejouent
	# `configure` : le preset ne doit pas être perdu ni écrasé.
	for _i in range(3):
		stage.configure(payload)
		await _wait_frames(3)
	_assert("session_refresh_keeps_cinema",
		session_engine.get_quality_preset() == StyleScript.QUALITY_CINEMA
		and session_engine.is_cinema_quality())
	# Chemin de session réel : lumière de session appliquée à la carte.
	var gd = get_root().get_node("GameData")
	var session_map = gd.call("apply_session_lighting_to_map", map)
	_assert("session_apply_lighting_keeps_quality",
		session_map is Dictionary and StyleScript.is_cinema(session_map))
	# Nuit de session : la carte est dupliquée/éclairée, le preset survit.
	var night_map: Dictionary = map.duplicate(true)
	night_map["lighting"] = {"enabled": false, "preset": "nuit",
		"sources": [], "nightMode": true, "nightAmbient": 0.22}
	stage.configure({
		"map": night_map, "mode": "complex", "tokens": [], "party": [],
		"effects": [], "zones": [], "fog_revealed": [],
		"readonly": false, "is_gm": true, "tool": {"mode": "select"},
		"view_state": {}, "selected_token": "", "quest_format": "oneshot",
	})
	await _wait_frames(8)
	_assert("session_night_keeps_cinema",
		session_engine.get_quality_preset() == StyleScript.QUALITY_CINEMA)
	# Ancienne carte sans clé : session en classique, aucune régression.
	var legacy := _make_engine_map("classique")
	var legacy_payload := payload.duplicate(true)
	legacy_payload["map"] = legacy
	stage.configure(legacy_payload)
	await _wait_frames(8)
	_assert("session_legacy_classique",
		session_engine.get_quality_preset() == StyleScript.QUALITY_CLASSIQUE
		and not session_engine.is_cinema_quality())
	stage.queue_free()
	await _wait_frames(2)

func _session_mesh_lit(session_engine) -> bool:
	var layer = session_engine._meshes_layer
	if layer == null:
		return false
	var root = layer._nodes.get("e-far")
	var visual := _find_child_with_meta(root, "fallback") as MeshInstance3D
	return visual != null \
		and (visual.material_override as StandardMaterial3D).shading_mode \
			== BaseMaterial3D.SHADING_MODE_PER_PIXEL

# ===========================================================================
# 5 ter. Brume atmosphérique adaptée au tilt (vue de dessus ↔ rasante)
# ===========================================================================

## Carte minimale avec brume atmosphérique activée (densité de démo 0,06,
## hauteur par défaut) : terrain3d + quelques objets.
func _fog_map(quality: String = "cinema") -> Dictionary:
	var map := _make_engine_map(quality)
	map["atmosphericFog"] = {"enabled": true, "density": 0.06}
	return map

func _test_atmosphere_tilt() -> void:
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = Engine3DScript.new()
	engine.size = Vector2(640, 360)
	get_root().add_child(engine)
	await _wait_frames(2)
	engine.configure(_fog_map(), [], [], [], [], [], false, true, {"mode": "select"})
	await _wait_frames(8)
	var env: Environment = engine._world_env.environment
	_assert("atmo_depth_mode", env.fog_mode == Environment.FOG_MODE_DEPTH)
	_assert("atmo_depth_density", is_equal_approx(env.fog_density, 0.06),
		"density=%.3f" % env.fog_density)
	var settings: Dictionary = engine.get_atmospheric_fog_settings()
	_assert("atmo_tilt_aware_default", bool(settings.get("tiltAware", false)))
	# Vue 2.5D par défaut (tilt -50) : hauteur pondérée (~0,35–0,55).
	var factor_25d: float = engine.get_atmospheric_fog_height_factor()
	_assert("atmo_factor_25d",
		factor_25d > 0.25 and factor_25d < 0.65, "factor=%.2f" % factor_25d)
	_assert("atmo_height_25d_effective",
		env.fog_height_density < 0.12 and env.fog_height_density > 0.02,
		"heightDensity=%.3f" % env.fog_height_density)
	# --- Vue de dessus (pitch -85) : hauteur quasi nulle, profondeur intacte.
	engine._camera.rotation_degrees = Vector3(-85.0, 0.0, 0.0)
	engine.sync_atmospheric_fog()
	await _wait_frames(2)
	var depth_begin_top_down: float = env.fog_depth_begin
	var depth_end_top_down: float = env.fog_depth_end
	_assert("atmo_factor_top_down",
		engine.get_atmospheric_fog_height_factor() < 0.02,
		"factor=%.3f" % engine.get_atmospheric_fog_height_factor())
	_assert("atmo_height_top_down_off",
		env.fog_height_density < 0.01,
		"heightDensity=%.4f" % env.fog_height_density)
	_assert("atmo_depth_band_visible",
		env.fog_depth_end > env.fog_depth_begin
		and env.fog_depth_begin >= 8.0)
	# --- Vue rasante (pitch -18) : hauteur pleine (brume héroïque conservée).
	engine._camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	engine.sync_atmospheric_fog()
	await _wait_frames(2)
	_assert("atmo_factor_grazing",
		engine.get_atmospheric_fog_height_factor() > 0.98,
		"factor=%.3f" % engine.get_atmospheric_fog_height_factor())
	_assert("atmo_height_grazing_full",
		is_equal_approx(env.fog_height_density, 0.22),
		"heightDensity=%.3f" % env.fog_height_density)
	# --- A/B réversible : off = ancien comportement exact (hauteur pleine).
	engine.set_atmospheric_tilt_aware(false)
	await _wait_frames(2)
	_assert("atmo_ab_off_tiltAware",
		not bool(engine.get_atmospheric_fog_settings().get("tiltAware", true)))
	_assert("atmo_ab_off_grazing_unchanged",
		is_equal_approx(env.fog_height_density, 0.22),
		"heightDensity=%.3f" % env.fog_height_density)
	engine._camera.rotation_degrees = Vector3(-85.0, 0.0, 0.0)
	engine.sync_atmospheric_fog()
	await _wait_frames(2)
	_assert("atmo_ab_off_top_down_height_full",
		is_equal_approx(env.fog_height_density, 0.22),
		"heightDensity=%.3f" % env.fog_height_density)
	# La profondeur (bande relative) n'est pas modifiée par l'A/B : seule la
	# composante hauteur change.
	_assert("atmo_ab_only_height_changes",
		is_equal_approx(env.fog_depth_begin, depth_begin_top_down)
		and is_equal_approx(env.fog_depth_end, depth_end_top_down))
	engine.set_atmospheric_tilt_aware(true)
	await _wait_frames(2)
	_assert("atmo_ab_on_top_down_height_zero",
		env.fog_height_density < 0.01,
		"heightDensity=%.4f" % env.fog_height_density)
	# --- Données de carte : `atmosphericFog.tiltAware = false` respecté.
	var off_map := _fog_map()
	off_map["atmosphericFog"] = {"enabled": true, "density": 0.06, "tiltAware": false}
	engine.configure(off_map, [], [], [], [], [], false, true, {"mode": "select"})
	await _wait_frames(8)
	engine._camera.rotation_degrees = Vector3(-85.0, 0.0, 0.0)
	engine.sync_atmospheric_fog()
	await _wait_frames(2)
	_assert("atmo_map_data_ab_off",
		not engine.is_atmospheric_tilt_aware()
		and engine._world_env.environment.fog_height_density > 0.2)
	var on_map := _fog_map()
	on_map["atmosphericFog"] = {"enabled": true, "density": 0.06, "tiltAware": true}
	engine.configure(on_map, [], [], [], [], [], false, true, {"mode": "select"})
	await _wait_frames(8)
	_assert("atmo_map_data_ab_on", engine.is_atmospheric_tilt_aware())
	# --- Brume globale OFF : rendu d'origine (aucune hauteur), tilt-aware no-op.
	engine.set_atmospheric_fog_enabled(false)
	await _wait_frames(2)
	_assert("atmo_global_off_no_height",
		engine._world_env.environment.fog_mode == Environment.FOG_MODE_EXPONENTIAL
		and is_zero_approx(engine._world_env.environment.fog_height_density))
	engine.set_atmospheric_fog_enabled(true)
	await _wait_frames(2)
	engine.queue_free()
	await _wait_frames(2)

func _collect_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is MeshInstance3D and not node.has_meta("contact_shadow"):
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_mesh_instances(child))
	return out

# ===========================================================================
# 4 bis. Budget d'ombres par distance (perf cartes denses)
# ===========================================================================

## Carte 30 × 30 sans relief, trois objets : proche (2,2), centre (15,15),
## fond (2,28). Budget en cases, hystérésis, réévaluation, réversibilité.
func _shadow_budget_map(quality: String) -> Dictionary:
	var map := {
		"id": "quality-budget-%s" % quality,
		"name": "Budget d'ombres",
		"width": 30,
		"height": 30,
		"renderStyle": "2.5d",
		"groundMode": "terrain3d",
		"backgroundImage": "",
		"atmosphere": {"enabled": false, "tint": "#141018", "opacity": 0.0, "vignette": 0.0},
		"meshes": [
			{"id": "proche", "kind": "mesh", "asset": "", "x": 2.0, "y": 2.0},
			{"id": "centre", "kind": "mesh", "asset": "", "x": 15.0, "y": 15.0},
			{"id": "fond", "kind": "mesh", "asset": "", "x": 2.0, "y": 28.0},
		],
	}
	if quality == "cinema":
		map["qualityPreset"] = "cinema"
	return map

func _caster_on(layer, id: String) -> bool:
	var root: Node3D = layer._nodes.get(id) as Node3D
	if root == null:
		return false
	var casters: Array = layer._shadow_casters.get(id, [])
	if casters.is_empty():
		return false
	return (casters[0] as GeometryInstance3D).cast_shadow \
		== GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _test_shadow_budget() -> void:
	# --- Calque seul : budget, hystérésis, réévaluation -------------------
	var layer: Node3D = Meshes3DScript.new()
	get_root().add_child(layer)
	var cinema_map := _shadow_budget_map("cinema")
	layer.configure(cinema_map["meshes"], 1.0, cinema_map)
	_assert("budget_casters_count", layer.get_shadow_caster_count() == 3)
	_assert("budget_default_value",
		is_equal_approx(layer.get_shadow_budget_cells(), 70.0),
		"budget=%f" % layer.get_shadow_budget_cells())
	_assert("budget_all_on_initially",
		layer.get_active_shadow_casters() == 3
		and _caster_on(layer, "proche") and _caster_on(layer, "fond"))
	# Budget serré (8 cases) autour de l'objet proche : seuls les proches castent.
	layer.set_shadow_budget_cells(8.0)
	layer.update_shadow_budget(Vector2(2.0, 2.0))
	_assert("budget_near_cast", _caster_on(layer, "proche"))
	_assert("budget_center_off", not _caster_on(layer, "centre"),
		"distance centre ≈ 18")
	_assert("budget_far_off", not _caster_on(layer, "fond"),
		"distance fond ≈ 26")
	_assert("budget_active_count", layer.get_active_shadow_casters() == 1)
	# Réévaluation au « mouvement caméra » : focus au fond → l'autre objet caste.
	layer.update_shadow_budget(Vector2(2.0, 28.0))
	_assert("budget_move_camera_far_cast", _caster_on(layer, "fond"))
	_assert("budget_move_camera_near_off", not _caster_on(layer, "proche"))
	_assert("budget_move_camera_center_off", not _caster_on(layer, "centre"))
	# Hystérésis : objet rallumé de près, puis vue qui s'éloigne à 8,5 cases
	# (entre budget 8 et budget ×1,15 = 9,2) → il doit rester allumé.
	layer.update_shadow_budget(Vector2(2.0, 2.0))
	_assert("budget_hysteresis_relit", _caster_on(layer, "proche"))
	layer.update_shadow_budget(Vector2(10.5, 2.0))
	_assert("budget_hysteresis_holds", _caster_on(layer, "proche"))
	# Au-delà de 9,2 cases : extinction (l'objet est au centre de case, +0,5).
	layer.update_shadow_budget(Vector2(12.0, 2.0))
	_assert("budget_beyond_hysteresis_off", not _caster_on(layer, "proche"))
	# Budget illimité : tout se rallume (réversibilité A/B).
	layer.set_shadow_budget_cells(-1.0)
	_assert("budget_unlimited_all_on",
		layer.get_active_shadow_casters() == 3
		and _caster_on(layer, "proche") and _caster_on(layer, "centre")
		and _caster_on(layer, "fond"))
	layer.queue_free()
	await process_frame
	# --- Classique : budget inactif, aucun cast (rendu historique) ---------
	var classique_layer: Node3D = Meshes3DScript.new()
	get_root().add_child(classique_layer)
	var classique_map := _shadow_budget_map("classique")
	classique_layer.configure(classique_map["meshes"], 1.0, classique_map)
	_assert("budget_classique_no_casters",
		classique_layer.get_shadow_caster_count() == 0
		and classique_layer.get_active_shadow_casters() == 0)
	_assert("budget_classique_no_caster_built",
		not _caster_on(classique_layer, "proche"))
	classique_layer.update_shadow_budget(Vector2.ZERO)
	_assert("budget_classique_noop", not _caster_on(classique_layer, "proche"))
	classique_layer.queue_free()
	await process_frame

# ===========================================================================
# 5. Moteur 3D : bascule A/B + preset lu depuis les données
# ===========================================================================

func _make_engine_map(quality: String) -> Dictionary:
	var map := {
		"id": "quality-engine-%s" % quality,
		"name": "Qualité moteur",
		"width": 12,
		"height": 10,
		"renderMode": "complex",
		"renderStyle": "2.5d",
		"groundMode": "terrain3d",
		"backgroundImage": "",
		"fogEnabled": false,
		"grid": {"size": 70},
		"lighting": {"enabled": false, "preset": "jour", "sources": []},
		"atmosphere": {"enabled": false, "tint": "#141018", "opacity": 0.0, "vignette": 0.0},
		"meshes": [
			{"id": "e-far", "kind": "mesh", "asset": "", "x": 2.0, "y": 1.0},
			{"id": "e-near", "kind": "mesh", "asset": "", "x": 8.0, "y": 8.0},
		],
		"terrainHeights": [],
		"terrainMaterials": [],
	}
	if quality == "cinema":
		map["qualityPreset"] = "cinema"
	return map

## Instantané des réglages A/B (Environment + soleil + calque meshes).
func _quality_snapshot(engine) -> Dictionary:
	var env: Environment = engine._world_env.environment
	return {
		"ssao_enabled": env.ssao_enabled,
		"ssao_radius": env.ssao_radius,
		"ssao_intensity": env.ssao_intensity,
		"ssil_enabled": env.ssil_enabled,
		"glow_intensity": env.glow_intensity,
		"glow_strength": env.glow_strength,
		"glow_bloom": env.glow_bloom,
		"glow_hdr_threshold": env.glow_hdr_threshold,
		"contrast": env.adjustment_contrast,
		"saturation": env.adjustment_saturation,
		"brightness": env.adjustment_brightness,
		"tonemap_mode": env.tonemap_mode,
		"tonemap_white": env.tonemap_white,
		"tonemap_exposure": env.tonemap_exposure,
		"sun_shadow": engine._sun.shadow_enabled,
		"sun_mode": engine._sun.directional_shadow_mode,
		"sun_blur": engine._sun.shadow_blur,
		"sun_bias": engine._sun.shadow_bias,
		"sun_normal_bias": engine._sun.shadow_normal_bias,
		"sun_angular": engine._sun.light_angular_distance,
		"sun_max_distance": engine._sun.directional_shadow_max_distance,
		"sun_split_1": engine._sun.directional_shadow_split_1,
		"sun_split_2": engine._sun.directional_shadow_split_2,
		"sun_split_3": engine._sun.directional_shadow_split_3,
		"sun_fade_start": engine._sun.directional_shadow_fade_start,
	}

func _test_engine_ab() -> void:
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var engine: Control = Engine3DScript.new()
	engine.size = Vector2(640, 360)
	get_root().add_child(engine)
	await _wait_frames(2)
	var classique_map := _make_engine_map("classique")
	engine.configure(classique_map, [], [], [], [], [], false, true, {"mode": "select"})
	await _wait_frames(8)
	_assert("engine_classique_preset",
		engine.get_quality_preset() == StyleScript.QUALITY_CLASSIQUE)
	_assert("engine_classique_not_cinema", not engine.is_cinema_quality())
	var env: Environment = engine._world_env.environment
	# Le sol/terrain est un récepteur d'ombre (matériau éclairé, pas unshaded) :
	# les ombres portées des objets s'y projettent réellement.
	var ground_mat = engine._ground._mesh_instance.material_override
	var ground_receives := false
	if ground_mat is ShaderMaterial:
		ground_receives = true
	elif ground_mat is StandardMaterial3D:
		ground_receives = (ground_mat as StandardMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
			and not (ground_mat as StandardMaterial3D).disable_receive_shadows
	_assert("engine_ground_receives_shadows", ground_receives)
	# Valeurs historiques (post-traitement Dofus + soleil terrain3d).
	_assert("engine_classique_ssao", env.ssao_enabled and is_equal_approx(env.ssao_intensity, 1.35))
	_assert("engine_classique_no_ssil", not env.ssil_enabled)
	_assert("engine_classique_tonemap_default", is_equal_approx(env.tonemap_white, 1.0))
	_assert("engine_classique_shadow_mode",
		engine._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL)
	_assert("engine_classique_shadow_angular",
		is_equal_approx(engine._sun.light_angular_distance, 0.0))
	_assert("engine_classique_glow", is_equal_approx(env.glow_intensity, 0.28),
		"glow=%.3f" % env.glow_intensity)
	_assert("engine_classique_contrast", is_equal_approx(env.adjustment_contrast, 1.06))
	# Matériaux/ombres du calque en classique.
	var layer = engine._meshes_layer
	var far_root: Node3D = layer._nodes.get("e-far")
	var far_visual := _find_child_with_meta(far_root, "fallback") as MeshInstance3D
	_assert("engine_classique_mesh_unshaded",
		far_visual != null
		and (far_visual.material_override as StandardMaterial3D).shading_mode
			== BaseMaterial3D.SHADING_MODE_UNSHADED)
	_assert("engine_classique_mesh_no_shadow",
		far_visual != null
		and far_visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var baseline := _quality_snapshot(engine)

	# --- Bascule A/B : cinéma, sans reconstruire ni bouger la caméra ----------
	var cam_before: Transform3D = engine._camera.transform
	engine.set_quality_preset("cinema")
	await _wait_frames(6)
	_assert("engine_after_toggle_preset",
		engine.get_quality_preset() == StyleScript.QUALITY_CINEMA)
	_assert("engine_after_toggle_cinema", engine.is_cinema_quality())
	_assert("engine_camera_untouched", engine._camera.transform.is_equal_approx(cam_before))
	_assert("engine_map_data_key",
		str(engine.map_data.get("qualityPreset", "")) == "cinema")
	var cinema_env: Environment = engine._world_env.environment
	_assert("engine_cinema_ssao_boost",
		cinema_env.ssao_intensity > float(baseline["ssao_intensity"]) + 0.2)
	_assert("engine_cinema_ssao_radius", cinema_env.ssao_radius > 1.35)
	_assert("engine_cinema_ssil", cinema_env.ssil_enabled)
	_assert("engine_cinema_glow_controlled",
		cinema_env.glow_intensity < float(baseline["glow_intensity"]))
	_assert("engine_cinema_tonemap_white", cinema_env.tonemap_white > 2.0)
	_assert("engine_cinema_contrast",
		cinema_env.adjustment_contrast >= 1.0799
		and cinema_env.adjustment_contrast <= 1.1201)
	_assert("engine_cinema_saturation",
		cinema_env.adjustment_saturation >= 1.0399
		and cinema_env.adjustment_saturation <= 1.0801,
		"sat=%.3f" % cinema_env.adjustment_saturation)
	_assert("engine_cinema_shadow_mode",
		engine._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_assert("engine_cinema_shadow_angular_clean",
		is_zero_approx(engine._sun.light_angular_distance))
	_assert("engine_cinema_shadow_blur", engine._sun.shadow_blur >= 2.0)
	_assert("engine_cinema_shadow_distance",
		engine._sun.directional_shadow_max_distance >= 190.0)
	_assert("engine_cinema_shadows_on", engine._sun.shadow_enabled)
	far_visual = _find_child_with_meta(layer._nodes.get("e-far"), "fallback") as MeshInstance3D
	_assert("engine_cinema_mesh_lit",
		far_visual != null
		and (far_visual.material_override as StandardMaterial3D).shading_mode
			== BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	_assert("engine_cinema_mesh_casts",
		far_visual != null
		and far_visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)

	# --- Budget d'ombres : API moteur + réévaluation au mouvement caméra ---
	_assert("engine_cinema_shadow_budget",
		is_equal_approx(engine.get_shadow_budget_cells(), 70.0),
		"budget=%f" % engine.get_shadow_budget_cells())
	var caster_count: int = engine.get_shadow_caster_count()
	_assert("engine_cinema_shadow_casters", caster_count >= 2)
	_assert("engine_cinema_shadow_active_bounded",
		engine.get_active_shadow_casters() > 0
		and engine.get_active_shadow_casters() <= caster_count)
	var budget_far_root = engine._meshes_layer._nodes.get("e-far")
	var budget_near_root = engine._meshes_layer._nodes.get("e-near")
	var cell: float = float(engine._cell_size)
	# Budget très serré centré sur l'objet du fond : lui seul projette.
	engine._center_focus_on(Vector2(2.0 * cell + cell * 0.5, 1.0 * cell + cell * 0.5))
	engine.set_shadow_budget_cells(2.0)
	await _wait_frames(4)
	_assert("engine_budget_reduces_active",
		engine.get_active_shadow_casters() >= 1
		and engine.get_active_shadow_casters() < caster_count,
		"actifs=%d / %d" % [engine.get_active_shadow_casters(), caster_count])
	_assert("engine_budget_far_casts", _visual_casts(budget_far_root))
	_assert("engine_budget_near_off", not _visual_casts(budget_near_root))
	# Déplacement de la vue vers l'autre objet : réévaluation SANS reconstruction.
	engine._center_focus_on(Vector2(8.0 * cell + cell * 0.5, 8.0 * cell + cell * 0.5))
	engine._update_shadow_budget(true)
	await _wait_frames(2)
	_assert("engine_budget_reevaluated",
		not _visual_casts(budget_far_root) and _visual_casts(budget_near_root))
	# Budget par défaut restauré : tout se rallume.
	engine.set_shadow_budget_cells(70.0)
	_assert("engine_budget_restored",
		_visual_casts(budget_far_root) and _visual_casts(budget_near_root))

	# --- Retour classique : rendu d'origine strictement restauré --------------
	engine.set_quality_preset("classique")
	await _wait_frames(6)
	_assert("engine_back_classique_preset",
		engine.get_quality_preset() == StyleScript.QUALITY_CLASSIQUE)
	_assert("engine_back_map_data_key", not engine.map_data.has("qualityPreset"))
	var restored := _quality_snapshot(engine)
	_assert("engine_ab_exact_restore", _same_json(restored, baseline),
		"restauré=%s baseline=%s" % [JSON.stringify(restored), JSON.stringify(baseline)])

	# --- Preset relu depuis des DONNÉES chargées (JSON) : cas carte cité -----
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(_make_engine_map("cinema")))
	engine.configure(loaded, [], [], [], [], [], false, true, {"mode": "select"})
	await _wait_frames(8)
	_assert("engine_loaded_preset_cinema",
		engine.get_quality_preset() == StyleScript.QUALITY_CINEMA
		and engine.is_cinema_quality())
	_assert("engine_loaded_shadows",
		engine._sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_assert("engine_loaded_ssil", engine._world_env.environment.ssil_enabled)
	# Carte SANS la clé (ancienne carte) : classique, aucun crash.
	engine.configure(_make_engine_map("classique"), [], [], [], [], [], false, true,
		{"mode": "select"})
	await _wait_frames(6)
	_assert("engine_legacy_map_classique",
		engine.get_quality_preset() == StyleScript.QUALITY_CLASSIQUE)
	# Données minimales : pas de crash.
	engine.configure({"id": "min", "width": 4, "height": 4}, [], [], [], [], [], false, true)
	await _wait_frames(4)
	_assert("engine_minimal_map_no_crash", engine.get_quality_preset() != "")
	engine.queue_free()
	await _wait_frames(2)

# ===========================================================================
# 6. Éditeur réel : bascule UI, persistance, undo
# ===========================================================================

func _test_editor_ui() -> void:
	var editor: Control = load("res://scenes/map_editor/map_editor.tscn").instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await _wait_frames(2)
	editor.load_map({
		"id": "quality-ui", "name": "Qualité UI", "width": 12, "height": 10,
		"renderMode": "complex", "renderStyle": "2.5d", "groundMode": "terrain3d",
		"backgroundImage": "", "fogEnabled": false, "grid": {"size": 70},
		"lighting": {"enabled": false, "preset": "jour", "sources": []},
	})
	await _wait_frames(8)
	var panel = editor._settings_panel
	_assert("ui_panel_present", panel != null)
	if panel == null:
		editor.queue_free()
		return
	var widget: OptionButton = panel.widgets.get("quality_preset")
	_assert("ui_quality_widget", widget != null and widget.item_count == 2)
	if widget == null:
		editor.queue_free()
		return
	_assert("ui_quality_hint_label",
		panel._quality_hint != null and panel._quality_hint.text.contains("historique"))
	_assert("ui_quality_default_classique",
		str(widget.get_item_metadata(widget.selected)) == StyleScript.QUALITY_CLASSIQUE)
	_assert("ui_engine_default_classique",
		editor._engine.get_quality_preset() == StyleScript.QUALITY_CLASSIQUE)
	# Bascule « cinéma » depuis l'UI : écriture document + moteur immédiat.
	widget.select(1)
	panel._apply_quality_preset()
	await _wait_frames(10)
	_assert("ui_writes_document",
		str(editor.doc.map_data.get("qualityPreset", "")) == StyleScript.QUALITY_CINEMA)
	_assert("ui_engine_switches",
		editor._engine.get_quality_preset() == StyleScript.QUALITY_CINEMA)
	_assert("ui_engine_cinema_ssil", editor._engine._world_env.environment.ssil_enabled)
	# Qualité d'image : MSAA renforcé en cinéma (détails/arêtes nets).
	_assert("ui_engine_cinema_msaa",
		editor._engine._viewport.msaa_3d == Viewport.MSAA_4X,
		"msaa=%d" % editor._engine._viewport.msaa_3d)
	# Undo : le panneau se resynchronise depuis la carte (undo/redo/import).
	editor.doc.undo()
	await _wait_frames(10)
	_assert("ui_undo_resyncs_widget",
		str(widget.get_item_metadata(widget.selected)) == StyleScript.QUALITY_CLASSIQUE)
	_assert("ui_undo_engine",
		editor._engine.get_quality_preset() == StyleScript.QUALITY_CLASSIQUE)
	_assert("ui_engine_classic_msaa",
		editor._engine._viewport.msaa_3d == Viewport.MSAA_2X,
		"msaa=%d" % editor._engine._viewport.msaa_3d)
	editor.queue_free()
	await _wait_frames(2)

# ===========================================================================
# Helpers
# ===========================================================================

func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame

func _same_json(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  OK  ", assert_name)
	else:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
