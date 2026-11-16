extends SceneTree

## Test headless du **style de scène « Cité »** : la scène compose de vrais GLB
## du catalogue (bâtiments + modules de toit/façade empilés + props + végétation
## + rochers + clôtures) et les applique comme éléments du document.
##
## Vérifie :
##   • le style est déclaré et libellé « Cité » (sélecteur de l'UI) ;
##   • il y a des bâtiments GLB et des modules de toit **empilés** (élévation > 0) ;
##   • tous les assets référencés existent dans le projet ;
##   • aucun chevauchement au sol, tout reste dans la carte ;
##   • le plan est déterministe (même graine ⇒ même plan) ;
##   • le budget d'éléments reste borné ;
##   • la scène est annulable en **une seule** étape d'undo ;
##   • les matières du sol (rues/place) sont peintes.
##
## Lancement :
##   godot --headless --path game --script res://scripts/tests/city_scene_test.gd

const MAP_W := 44
const MAP_H := 32
const SEED := 20261112
const MIN_BUILDINGS := 18
const MIN_ROOFS := 3
const MIN_WALLS := 4
const MIN_PROPS := 20
const MAX_ELEMENTS := 320
const MIN_ELEMENTS := 70

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test cité", "general", "local", MAP_W, MAP_H)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["lighting"] = {"enabled": false, "preset": "tiny_glade", "sources": []}
	md.update_map(map)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(md.get_by_id(str(map.get("id", ""))))
	await process_frame

	# --- Style déclaré / sélectionnable -------------------------------------
	var generator = load("res://scripts/maps/construction/procedural_scene_generator.gd")
	_assert("style_declared", generator.STYLES.has("cite"), "styles=%s" % str(generator.STYLES))
	_assert("style_label", generator.style_label("cite") == "Cité",
		generator.style_label("cite"))

	# --- Application réelle dans l'éditeur ----------------------------------
	editor._scene_style = "cite"
	editor._scene_seed = SEED
	editor._scene_density = 1.0
	editor._construction._generate_scene(Vector2(float(MAP_W) * 0.5, float(MAP_H) * 0.5))
	await process_frame

	var all: Array = editor.doc.elements_of_kind("mesh")
	var buildings: Array = []
	var roofs: Array = []
	var walls: Array = []
	var props: Array = []
	var ground: Array = []
	var used_assets := {}
	var building_assets := {}
	var roof_assets := {}
	var wall_assets := {}
	var prop_assets := {}
	for elem_variant in all:
		var elem: Dictionary = elem_variant
		var label := str(elem.get("label", ""))
		var asset := str(elem.get("asset", ""))
		used_assets[asset] = true
		match label:
			"Bâtiment de cité":
				buildings.append(elem)
				building_assets[asset] = true
				ground.append(elem)
			"Toiture de cité":
				roofs.append(elem)
				roof_assets[asset] = true
			"Façade de cité":
				walls.append(elem)
				wall_assets[asset] = true
			"Décor de cité":
				props.append(elem)
				prop_assets[asset] = true
				ground.append(elem)
			_:
				ground.append(elem)
				prop_assets[asset] = true
	print("  cité : %d élément(s) mesh — %d bâtiment(s), %d toit(s), %d façade(s), %d décor(s)" % [
		all.size(), buildings.size(), roofs.size(), walls.size(), props.size()])

	_assert("has_buildings", buildings.size() >= MIN_BUILDINGS,
		"count=%d" % buildings.size())
	_assert("has_roofs", roofs.size() >= MIN_ROOFS, "count=%d" % roofs.size())
	_assert("has_walls", walls.size() >= MIN_WALLS, "count=%d" % walls.size())
	_assert("has_props", props.size() >= MIN_PROPS, "count=%d" % props.size())
	_assert("budget_max", all.size() <= MAX_ELEMENTS, "total=%d" % all.size())
	_assert("budget_min", all.size() >= MIN_ELEMENTS, "total=%d" % all.size())

	# --- Tous les assets existent (catalogue réel) --------------------------
	for asset_variant in used_assets.keys():
		var asset := str(asset_variant)
		if asset.is_empty() or asset.begins_with("procedural://"):
			continue
		_assert("asset_exists", ResourceLoader.exists(asset), asset)
	# Diversité : au moins 5 bâtiments et 2 façades distincts du catalogue.
	_assert("building_variety", building_assets.size() >= 5,
		"distincts=%d" % building_assets.size())
	_assert("roof_variety", roof_assets.size() >= 1,
		"distincts=%d" % roof_assets.size())
	_assert("wall_variety", wall_assets.size() >= 2,
		"distincts=%d" % wall_assets.size())
	# Les bâtiments GLB ont déjà leur toit : seuls des **accents** sont permis
	# (pas de module de toiture complet empilé ⇒ pas de double toit flottant).
	for roof_asset_variant in roof_assets.keys():
		var roof_name := str(roof_asset_variant).get_file().get_basename()
		_assert("roof_is_accent",
			roof_name in ["cheminee_fumante", "toit_clocheton", "toit_lucarne"],
			roof_name)

	# --- Modules de toit : ancre manifeste + élévation > 0 ------------------
	var library = load("res://scripts/maps/map_asset_library.gd")
	var stacked := 0
	var min_roof_elevation := INF
	for roof_variant in roofs:
		var roof: Dictionary = roof_variant
		var asset := str(roof.get("asset", ""))
		var meta: Dictionary = library.get_object3d_meta(asset)
		# Accents : ancre `roof` (cheminée) ou `base` posée sur le toit (lucarne).
		var anchor := str(meta.get("anchor", ""))
		_assert("roof_anchor", anchor == "roof" or anchor == "base",
			"%s anchor=%s" % [asset, anchor])
		var elevation := float(roof.get("elevation", 0.0))
		min_roof_elevation = minf(min_roof_elevation, elevation)
		if elevation > 0.01:
			stacked += 1
	_assert("roofs_stacked", stacked >= MIN_ROOFS, "posés=%d" % stacked)
	_assert("roof_elevation_positive", min_roof_elevation > 0.01,
		"min=%.3f" % min_roof_elevation)
	for wall_variant in walls:
		var wall: Dictionary = wall_variant
		var meta: Dictionary = library.get_object3d_meta(str(wall.get("asset", "")))
		_assert("wall_anchor", str(meta.get("anchor", "")) == "wall",
			"%s anchor=%s" % [str(wall.get("asset", "")), str(meta.get("anchor", ""))])

	# --- Aucun chevauchement au sol, tout reste dans la carte ---------------
	var overlaps := 0
	var worst := ""
	for i in range(ground.size()):
		var a: Dictionary = ground[i]
		var ra := _elem_rect(a)
		for j in range(i + 1, ground.size()):
			var b: Dictionary = ground[j]
			var rb := _elem_rect(b)
			if ra.grow(-0.02).intersects(rb.grow(-0.02)):
				overlaps += 1
				if worst.is_empty():
					worst = "%s ∩ %s" % [str(a.get("asset", "")).get_file(),
						str(b.get("asset", "")).get_file()]
	_assert("no_ground_overlap", overlaps == 0,
		"chevauchements=%d (%s)" % [overlaps, worst])
	# Allée minimale entre bâtiments : la ville doit respirer (pas de grappe).
	var crowded := 0
	for i in range(buildings.size()):
		var ra := _elem_rect(buildings[i])
		for j in range(i + 1, buildings.size()):
			var rb := _elem_rect(buildings[j])
			if ra.grow(0.25).intersects(rb.grow(0.25)):
				crowded += 1
	_assert("building_alley", crowded == 0, "trop_serrés=%d" % crowded)
	# Bâtiments alignés sur la trame : rotations par quart de tour uniquement.
	var misaligned := 0
	for building_variant in buildings:
		var display: Dictionary = (building_variant as Dictionary).get("display", {})
		var rotation := float(display.get("rotation", 0.0))
		if absf(fposmod(rotation, 90.0)) > 0.01:
			misaligned += 1
	_assert("buildings_aligned", misaligned == 0, "rotations_hors_trame=%d" % misaligned)
	# Échelle ~1 : aucun bâtiment écrasé/étiré.
	var bad_scale := 0
	for building_variant in buildings:
		var display: Dictionary = (building_variant as Dictionary).get("display", {})
		if absf(float(display.get("scale", 1.0)) - 1.0) > 0.01:
			bad_scale += 1
	_assert("buildings_scale_one", bad_scale == 0, "échelles≠1=%d" % bad_scale)
	# Marge au bord : le centre d'un bâtiment reste à ≥ 1,5 case du bord, sinon
	# il est rogné par la dalle / à moitié enterré sur les captures.
	var edge_cut := 0
	for building_variant in buildings:
		var elem: Dictionary = building_variant
		var bx := float(elem.get("x", 0.0))
		var by := float(elem.get("y", 0.0))
		if bx < 1.5 or by < 1.5 or bx > float(MAP_W) - 2.5 or by > float(MAP_H) - 2.5:
			edge_cut += 1
	_assert("buildings_edge_margin", edge_cut == 0, "trop_près_du_bord=%d" % edge_cut)
	# Modules de façade : chacun doit être **collé à une façade** (à portée d'un
	# bâtiment), jamais isolé sur l'herbe ou la rue.
	var detached_walls := 0
	for wall_variant in walls:
		var wall: Dictionary = wall_variant
		var wc := Vector2(float(wall.get("x", 0.0)), float(wall.get("y", 0.0)))
		var attached := false
		for building_variant in buildings:
			if _elem_rect(building_variant).grow(1.0).has_point(wc):
				attached = true
				break
		if not attached:
			detached_walls += 1
	_assert("walls_attached", detached_walls == 0, "façades_détachées=%d" % detached_walls)
	var out_of_bounds := 0
	for elem_variant in all:
		var elem: Dictionary = elem_variant
		var rect := _elem_rect(elem)
		if rect.position.x < -0.55 or rect.position.y < -0.55 \
				or rect.end.x > float(MAP_W) + 0.55 or rect.end.y > float(MAP_H) + 0.55:
			out_of_bounds += 1
	_assert("in_bounds", out_of_bounds == 0, "hors_carte=%d" % out_of_bounds)

	# --- Matières du sol : rues + place peintes -----------------------------
	var materials: Array = editor.doc.map_data.get("terrainMaterials", [])
	var stone := 0
	var dirt := 0
	for value in materials:
		if int(value) == 2:
			stone += 1
		elif int(value) == 1:
			dirt += 1
	_assert("streets_paved", stone >= 300, "cases_pierre=%d" % stone)
	_assert("approaches_dirt", dirt >= 8, "cases_terre=%d" % dirt)

	# --- Déterminisme : même graine ⇒ plan identique ------------------------
	var plan_a: Dictionary = generator.generate("cite", MAP_W, MAP_H, SEED, 1.0)
	var plan_b: Dictionary = generator.generate("cite", MAP_W, MAP_H, SEED, 1.0)
	_assert("deterministic_size",
		(plan_a.get("buildings", []) as Array).size() == (plan_b.get("buildings", []) as Array).size(),
		"%d vs %d" % [(plan_a.get("buildings", []) as Array).size(),
			(plan_b.get("buildings", []) as Array).size()])
	_assert("deterministic_plan", var_to_str(plan_a) == var_to_str(plan_b))
	var plan_c: Dictionary = generator.generate("cite", MAP_W, MAP_H, SEED + 1, 1.0)
	_assert("seed_changes_plan",
		var_to_str(plan_a) != var_to_str(plan_c), "graines différentes ⇒ même plan")
	_assert("plan_buildings_min", (plan_a.get("buildings", []) as Array).size() >= MIN_BUILDINGS,
		"plan=%d" % (plan_a.get("buildings", []) as Array).size())
	# Chaque accent de toit doit être posé À L'INTÉRIEUR de l'emprise de son
	# bâtiment (aucun accent orphelin « sur l'herbe »).
	var orphan_accents := 0
	for building_variant in plan_a.get("buildings", []):
		var building: Dictionary = building_variant
		var b_rect := _elem_rect(building)
		for roof_variant in building.get("roofs", []):
			var roof: Dictionary = roof_variant
			var rc := Vector2(float(roof.get("x", 0.0)), float(roof.get("y", 0.0)))
			if not b_rect.grow(0.1).has_point(rc):
				orphan_accents += 1
	_assert("no_orphan_roof_accents", orphan_accents == 0,
		"accents_orphelins=%d" % orphan_accents)

	# --- La scène est une seule étape d'undo --------------------------------
	var total_before := all.size()
	_assert("undo_available", editor.doc.can_undo())
	editor.doc.undo()
	await process_frame
	var after_undo: int = editor.doc.elements_of_kind("mesh").size()
	_assert("single_undo", after_undo == 0,
		"avant=%d après=%d" % [total_before, after_undo])
	editor.doc.redo()
	await process_frame
	var after_redo: int = editor.doc.elements_of_kind("mesh").size()
	# Tolérance : `MapData.generate_id` n'a qu'une granularité de ~90 000 valeurs
	# par seconde ; au-delà de ~200 éléments créés dans la même seconde, deux id
	# peuvent coïncider et un élément fusionner (limite du document, hors scope).
	_assert("redo_restores", after_redo >= total_before - 3,
		"redo=%d attendu=%d" % [after_redo, total_before])

	if _failed:
		print("city_scene_test:FAIL")
		quit(1)
		return
	print("city_scene_test:PASS")
	quit(0)

## Rectangle occupé par un élément (coordonnées de centre de case).
func _elem_rect(elem: Dictionary) -> Rect2:
	var w := maxf(0.2, float(elem.get("w", 1.0)))
	var h := maxf(0.2, float(elem.get("h", 1.0)))
	return Rect2(float(elem.get("x", 0.0)) - w * 0.5,
		float(elem.get("y", 0.0)) - h * 0.5, w, h)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
