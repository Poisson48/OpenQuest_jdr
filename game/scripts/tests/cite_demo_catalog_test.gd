extends SceneTree

## Test headless d'intégration produit (task-10) : la carte démo « Cité des
## Saules » est dans le catalogue `MapData` (donc dans le Hub → Cartes), pointe
## vers de vrais assets GLB, est déterministe, et s'ouvre dans l'éditeur.
##
## Lancement :
##   godot --headless --path game --script res://scripts/tests/cite_demo_catalog_test.gd

const CITE_ID := "demo-cite-skyline"
const MAP_W := 44
const MAP_H := 32
const SEED := 20261112
const MIN_MESHES := 100
## Budget du convertisseur pur (plan → éléments), caches GLB chauds (la carte du
## catalogue est déjà construite au démarrage). Cible < 300 ms, marge CI.
const BUILD_BUDGET_MS := 1500

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	await process_frame

	# --- Présence dans le catalogue (Hub → Cartes) --------------------------
	var demo: Dictionary = md.get_by_id(CITE_ID)
	_assert("demo_exists", not demo.is_empty(), "introuvable dans MapData.maps")
	if demo.is_empty():
		_finish()
		return
	_assert("demo_title", str(demo.get("title", "")).contains("Cité des Saules"),
		str(demo.get("title", "")))
	_assert("demo_complex", md.is_complex_map(demo))
	_assert("demo_catalog", md.is_catalog_map(demo), "statut non publié")
	var adventure: Array = md.get_maps_by_category("adventure", "catalog")
	var in_hub := false
	for map_variant in adventure:
		if str((map_variant as Dictionary).get("id", "")) == CITE_ID:
			in_hub = true
			break
	_assert("demo_in_hub_catalog", in_hub, "absente de la catégorie Aventure du catalogue")
	_assert("demo_quality_preset", str(demo.get("qualityPreset", "")) == "cinema",
		str(demo.get("qualityPreset", "")))
	_assert("demo_ground_terrain", str(demo.get("groundMode", "")) == "terrain3d")
	_assert("demo_render_style", str(demo.get("renderStyle", "")) == "2.5d")
	_assert("demo_size", int(demo.get("width", 0)) == MAP_W
		and int(demo.get("height", 0)) == MAP_H)
	var light: Dictionary = demo.get("lighting", {})
	_assert("demo_lighting", bool(light.get("enabled", false))
		and str(light.get("preset", "")) == "jour", str(light))
	var fog: Dictionary = demo.get("atmosphericFog", {})
	_assert("demo_fog", not fog.is_empty()
		and is_equal_approx(float(fog.get("heightDensity", -1.0)), 0.0), str(fog))

	# --- Contenu : éléments, sols, relief, assets --------------------------
	var meshes: Array = demo.get("meshes", [])
	_assert("demo_mesh_budget", meshes.size() >= MIN_MESHES, "mesh=%d" % meshes.size())
	var materials: Array = demo.get("terrainMaterials", [])
	_assert("demo_materials", materials.size() == MAP_W * MAP_H,
		"materials=%d" % materials.size())
	var stone := 0
	var dirt := 0
	for value in materials:
		if int(value) == 2:
			stone += 1
		elif int(value) == 1:
			dirt += 1
	_assert("demo_streets_paved", stone > 100, "pierre=%d" % stone)
	_assert("demo_approaches_dirt", dirt > 0, "terre=%d" % dirt)
	var heights: Array = demo.get("terrainHeights", [])
	_assert("demo_relief", heights.size() == MAP_W * MAP_H)
	var bad_assets := 0
	var out_of_bounds := 0
	var buildings := 0
	var roofs := 0
	var walls := 0
	for mesh_variant in meshes:
		var mesh: Dictionary = mesh_variant
		var asset := str(mesh.get("asset", ""))
		if not asset.begins_with("procedural://") and not ResourceLoader.exists(asset):
			bad_assets += 1
		match str(mesh.get("label", "")):
			"Bâtiment de cité":
				buildings += 1
			"Toiture de cité":
				roofs += 1
			"Façade de cité":
				walls += 1
		var x := float(mesh.get("x", 0.0))
		var y := float(mesh.get("y", 0.0))
		if x < -0.55 or y < -0.55 or x > MAP_W + 0.5 or y > MAP_H + 0.5:
			out_of_bounds += 1
	_assert("demo_assets_exist", bad_assets == 0, "assets_manquants=%d" % bad_assets)
	_assert("demo_buildings", buildings >= 18, "batiments=%d" % buildings)
	_assert("demo_roofs", roofs >= 3, "toits=%d" % roofs)
	_assert("demo_walls", walls >= 3, "façades=%d" % walls)
	_assert("demo_in_bounds", out_of_bounds == 0, "hors_carte=%d" % out_of_bounds)

	# --- Déterminisme + budget du convertisseur pur partagé ----------------
	var t0 := Time.get_ticks_msec()
	var plan_a: Dictionary = ProceduralCity.generate(MAP_W, MAP_H, SEED, 1.0)
	var built_a: Dictionary = ProceduralCity.build_city_elements(plan_a, MAP_W, MAP_H)
	var elapsed := Time.get_ticks_msec() - t0
	_assert("demo_generation_budget", elapsed < BUILD_BUDGET_MS, "elapsed=%d ms" % elapsed)
	var plan_b: Dictionary = ProceduralCity.generate(MAP_W, MAP_H, SEED, 1.0)
	var built_b: Dictionary = ProceduralCity.build_city_elements(plan_b, MAP_W, MAP_H)
	_assert("demo_deterministic", var_to_str(built_a) == var_to_str(built_b))
	_assert("demo_matches_catalog_count",
		(built_a.get("elements", []) as Array).size() == meshes.size(),
		"convertisseur=%d catalogue=%d" % [
			(built_a.get("elements", []) as Array).size(), meshes.size()])
	print("  cité Hub : %d éléments (%d bâtiments, %d toits, %d façades), convertisseur %d ms" % [
		meshes.size(), buildings, roofs, walls, elapsed])

	# --- Ouverture réelle dans l'éditeur -----------------------------------
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(demo)
	await process_frame
	var doc_meshes: int = editor.doc.elements_of_kind("mesh").size()
	_assert("demo_editor_opens", doc_meshes >= MIN_MESHES, "editor_meshes=%d" % doc_meshes)
	_assert("demo_editor_preset",
		str(editor.doc.map_data.get("qualityPreset", "")) == "cinema")
	_assert("demo_editor_terrain",
		(editor.doc.map_data.get("terrainMaterials", []) as Array).size() == MAP_W * MAP_H)
	# Régénération éditeur depuis le même plan (une seule étape d'undo).
	editor._scene_style = "cite"
	editor._scene_seed = SEED
	editor._scene_density = 1.0
	var before: int = editor.doc.elements_of_kind("mesh").size()
	editor._construction._generate_scene(Vector2(float(MAP_W) * 0.5, float(MAP_H) * 0.5))
	await process_frame
	var after: int = editor.doc.elements_of_kind("mesh").size()
	_assert("demo_editor_regenerate", after > before + MIN_MESHES,
		"avant=%d après=%d" % [before, after])

	# --- Non-régression : les 3 cartes démo historiques existent -----------
	for legacy_id in ["demo-valbois-village", "demo-valbois-place", "demo-crypte-brumeval"]:
		var legacy: Dictionary = md.get_by_id(str(legacy_id))
		_assert("legacy_demo_%s" % legacy_id, not legacy.is_empty())
		_assert("legacy_published_%s" % legacy_id,
			str(legacy.get("status", "")) == "published", str(legacy.get("status", "")))

	_finish()

func _finish() -> void:
	if _failed:
		print("cite_demo_catalog_test:FAIL")
		quit(1)
		return
	print("cite_demo_catalog_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
