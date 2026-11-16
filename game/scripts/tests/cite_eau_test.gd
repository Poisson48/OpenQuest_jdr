extends SceneTree

## VITRINE « Cité au fil de l'eau » — test headless.
##
## Vérifie que la démo est une carte VALIDE et déterministe : cité générée en
## assets 3D (≥ 100 meshes, assets existants), eau cohérente (≥ 1 bassin, lit
## creusé sous le niveau, aucun bâti sous l'eau ni sur la berge), canal de ville
## et lac présents, ponts posés au-dessus du canal, rues pavées conservées,
## génération rapide (< 2 s) et carte `MapData` complète (cinéma, lumière jour,
## brume de distance, données d'eau).
##
## PASS = `cite_eau_test:PASS`.

const BootScript := preload("res://scripts/debug/cite_eau_boot.gd")
const WATER_LEVEL: float = BootScript.WATER_LEVEL

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	_assert("map_data_autoload", md != null)
	if md == null:
		_finish()
		return
	# --- Génération : déterministe et rapide ------------------------------
	var t0 := Time.get_ticks_msec()
	var plan_a: Dictionary = BootScript.build_plan(
		BootScript.MAP_WIDTH, BootScript.MAP_HEIGHT, BootScript.DEFAULT_SEED)
	var gen_ms := Time.get_ticks_msec() - t0
	var plan_b: Dictionary = BootScript.build_plan(
		BootScript.MAP_WIDTH, BootScript.MAP_HEIGHT, BootScript.DEFAULT_SEED)
	print("  [gen] plan en %d ms" % gen_ms)
	_assert("generation_fast", gen_ms < 2000, "%d ms" % gen_ms)
	_assert("generation_deterministic", str(plan_a) == str(plan_b))
	_assert("plan_sizes", (plan_a["heights"] as Array).size()
		== BootScript.MAP_WIDTH * BootScript.MAP_HEIGHT
		and (plan_a["materials"] as Array).size()
			== BootScript.MAP_WIDTH * BootScript.MAP_HEIGHT)

	# --- Eau : bassins, lit creusé, berges ---------------------------------
	var bodies: Array = plan_a["water_bodies"]
	_assert("water_bodies_present", bodies.size() >= 2, "n=%d" % bodies.size())
	var ids: Dictionary = {}
	var kinds: Dictionary = {}
	for body_variant in bodies:
		if body_variant is Dictionary:
			ids[str((body_variant as Dictionary).get("id", ""))] = true
			kinds[str((body_variant as Dictionary).get("kind", ""))] = true
	_assert("water_body_canal", ids.has("canal"))
	_assert("water_body_lake", ids.has("lac"))
	_assert("water_bodies_are_flat_lakes", kinds.size() == 1 and kinds.has("lake"))
	# Aucune nappe ne déborde du socle : tous les points des emprises sont dans
	# la carte (sinon l'eau « flotte » hors du plateau).
	var outside_points := 0
	for body_variant in bodies:
		if not (body_variant is Dictionary):
			continue
		for p_variant in (body_variant as Dictionary).get("area", []):
			if not (p_variant is Array) or (p_variant as Array).size() < 2:
				continue
			var px := float((p_variant as Array)[0])
			var py := float((p_variant as Array)[1])
			if px < 0.0 or py < 0.0 \
					or px > float(BootScript.MAP_WIDTH) \
					or py > float(BootScript.MAP_HEIGHT):
				outside_points += 1
	_assert("water_bodies_inside_map", outside_points == 0,
		"points hors carte=%d" % outside_points)
	var water_cells := int(plan_a["water_cells"])
	var bank_cells := int(plan_a["bank_cells"])
	print("  [eau] %d cases d'eau, %d cases de berge, niveau %.2f"
		% [water_cells, bank_cells, WATER_LEVEL])
	_assert("water_cells_present", water_cells > 80, "n=%d" % water_cells)
	_assert("bank_cells_present", bank_cells > 40, "n=%d" % bank_cells)
	# Cohérence : chaque case d'eau est SOUS le niveau (lit réellement creusé),
	# et les berges remontent au-dessus de l'eau.
	var heights: Array = plan_a["heights"]
	var below := 0
	var above := 0
	for value in heights:
		if float(value) < WATER_LEVEL:
			below += 1
		elif float(value) > WATER_LEVEL + 0.05:
			above += 1
	_assert("water_level_coherent", below == water_cells and above > water_cells,
		"below=%d water=%d above=%d" % [below, water_cells, above])

	# --- Cité : meshes, assets, rues --------------------------------------
	var meshes: Array = plan_a["meshes"]
	print("  [cité] %d éléments 3D  (plan : %s)"
		% [meshes.size(), str(plan_a.get("counts", {}))])
	_assert("city_meshes_count", meshes.size() >= 100, "n=%d" % meshes.size())
	var missing_asset := 0
	var bridge_count := 0
	var over_map := 0
	for mesh_variant in meshes:
		if not (mesh_variant is Dictionary):
			continue
		var mesh: Dictionary = mesh_variant
		var asset := str(mesh.get("asset", ""))
		if asset.is_empty() or not ResourceLoader.exists(asset):
			missing_asset += 1
		if asset == BootScript.BRIDGE_ASSET:
			bridge_count += 1
		var x := float(mesh.get("x", 0.0))
		var y := float(mesh.get("y", 0.0))
		if x < -0.5 or y < -0.5 or x > float(BootScript.MAP_WIDTH) + 0.5 \
				or y > float(BootScript.MAP_HEIGHT) + 0.5:
			over_map += 1
	_assert("city_assets_exist", missing_asset == 0, "manquants=%d" % missing_asset)
	_assert("city_bridges", bridge_count >= 1, "n=%d" % bridge_count)
	_assert("city_inside_map", over_map == 0, "hors carte=%d" % over_map)
	var stone_cells := 0
	var sand_cells := 0
	for value in plan_a["materials"]:
		if int(value) == BootScript.MATERIAL_STONE:
			stone_cells += 1
		elif int(value) == BootScript.MATERIAL_SAND:
			sand_cells += 1
	print("  [sols] %d cases pavées, %d cases de sable (berges)"
		% [stone_cells, sand_cells])
	_assert("streets_preserved", stone_cells > 80, "n=%d" % stone_cells)
	_assert("banks_painted", sand_cells > 40, "n=%d" % sand_cells)

	# --- Aucun bâti sous l'eau (ni sur la berge) --------------------------
	var wet_buildings := 0
	for mesh_variant in meshes:
		if not (mesh_variant is Dictionary):
			continue
		var mesh: Dictionary = mesh_variant
		var label := str(mesh.get("label", ""))
		var is_built := label.contains("Bâtiment") or label.contains("Toiture") \
			or label.contains("Façade")
		if not is_built:
			continue
		if _footprint_touches_water(mesh, height_check(heights)):
			wet_buildings += 1
	_assert("no_building_under_water", wet_buildings == 0,
		"bâtis mouillés=%d" % wet_buildings)

	# --- Carte MapData complète (éditeur / session) -----------------------
	var map: Dictionary = BootScript.build_map(md, BootScript.DEFAULT_SEED)
	_assert("map_built", not map.is_empty())
	if map.is_empty():
		_finish()
		return
	_assert("map_size", int(map.get("width", 0)) == BootScript.MAP_WIDTH
		and int(map.get("height", 0)) == BootScript.MAP_HEIGHT)
	_assert("map_terrain3d", str(map.get("groundMode", "")) == "terrain3d")
	_assert("map_style", str(map.get("renderStyle", "")) == "2.5d")
	_assert("map_cinema", str(map.get("qualityPreset", "")) == "cinema")
	var lighting: Dictionary = map.get("lighting", {})
	_assert("map_lighting", bool(lighting.get("enabled", false))
		and str(lighting.get("preset", "")) == "jour")
	var fog: Dictionary = map.get("atmosphericFog", {})
	_assert("map_fog", absf(float(fog.get("density", -1.0)) - 0.04) < 0.001
		and absf(float(fog.get("heightDensity", -1.0))) < 0.001)
	_assert("map_heights", (map.get("terrainHeights", []) as Array).size()
		== BootScript.MAP_WIDTH * BootScript.MAP_HEIGHT)
	_assert("map_materials", (map.get("terrainMaterials", []) as Array).size()
		== BootScript.MAP_WIDTH * BootScript.MAP_HEIGHT)
	_assert("map_water_level",
		is_equal_approx(float(map.get("waterLevel", 0.0)), WATER_LEVEL))
	var map_bodies: Array = map.get("waterBodies", [])
	_assert("map_water_bodies", map_bodies.size() >= 2, "n=%d" % map_bodies.size())
	_assert("map_meshes", (map.get("meshes", []) as Array).size() >= 100,
		"n=%d" % (map.get("meshes", []) as Array).size())
	_assert("map_world_id", str(map.get("worldId", "")) == BootScript.MONDE)
	_assert("map_in_catalog", md.get_by_id(str(map.get("id", ""))) != null)

	_finish()

## Tableau de hauteur sous forme de Callable(px, py) pour le test d'humidité.
func height_check(heights: Array) -> Callable:
	return func(px: int, py: int) -> float:
		if px < 0 or py < 0 or px >= BootScript.MAP_WIDTH or py >= BootScript.MAP_HEIGHT:
			return 999.0
		return float(heights[py * BootScript.MAP_WIDTH + px])

## Vrai si l'empreinte d'un élément touche une case d'eau (hauteur < niveau).
func _footprint_touches_water(mesh: Dictionary, height_at: Callable) -> bool:
	var x := float(mesh.get("x", 0.0))
	var y := float(mesh.get("y", 0.0))
	var w := maxf(0.1, float(mesh.get("w", 1.0)))
	var h := maxf(0.1, float(mesh.get("h", 1.0)))
	var x0 := int(floorf(x - w * 0.5))
	var x1 := int(ceili(x + w * 0.5))
	var y0 := int(floorf(y - h * 0.5))
	var y1 := int(ceili(y + h * 0.5))
	for cz in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if float(height_at.call(cx, cz)) < WATER_LEVEL - 0.001:
				return true
	return false

func _finish() -> void:
	if _failed:
		print("cite_eau_test:FAIL")
		quit(1)
		return
	print("cite_eau_test:PASS")
	quit(0)

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
