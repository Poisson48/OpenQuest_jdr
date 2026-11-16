extends Node

## DÉMO « Cité au fil de l'eau » — la vitrine qui combine tout le chantier
## « qualité Cities: Skylines II » : la cité générée en **vrais assets 3D**
## (style `cite`, `ProceduralCity`) traversée par un **canal** de ville, avec un
## **lac** en bordure, des **ponts**, l'eau CS2 (lit, berges, reflets, mousse),
## le **socle de diorama** et le **preset qualité cinéma**.
##
## La génération est PUREMENT une affaire de données de carte (aucune couche
## moteur/eau n'est modifiée) : `build_plan()` produit
## `terrainHeights` / `terrainMaterials` / `meshes` / `waterBodies` /
## `waterLevel`, et `build_map()` les emballe dans une carte complexe
## `terrain3d` 44×32. Le canal est creusé dans le terrain et rempli par la
## couche d'eau via `waterBodies` ; les berges sont peintes sable/pierre.
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/cite_eau_boot.tscn
## Graine personnalisée :
##   godot --path game res://scenes/debug/cite_eau_boot.tscn -- --seed 4242

const ProceduralCityScript := preload("res://scripts/maps/construction/procedural_city.gd")

const MONDE := "demo-cite-eau"
const MAP_NAME := "Cité au fil de l'eau"
const MAP_WIDTH := 44
const MAP_HEIGHT := 32
const DEFAULT_SEED := 20261112
const DENSITY := 1.0
const SCENE_STYLE := "cite"

## --- Plan d'eau -----------------------------------------------------------
## Niveau d'eau (cases) : sous le sol de la ville (0) → canal et lac encaissés.
const WATER_LEVEL := -0.30
## Canal nord-sud : il suit la rue verticale (x = 15,5) ; le plan d'eau occupe
## deux colonnes de cases (centres 14,5 et 15,5 → bord à x = 15,0).
const CANAL_X := 15.0
## Demi-largeur du plan d'eau du canal (cases).
const CANAL_HALF := 1.00
## Largeur du quai en pente de chaque côté (cases) : la berge descend vers l'eau.
const CANAL_BANK := 0.60
## Profondeur du lit sous la surface (cases).
const CANAL_DEPTH := 0.62
## Lac / baie de bordure (bassin) au sud-ouest de la ville : son emprise est
## rognée au bord de carte (aucune eau « flottante » hors du socle).
const LAKE_CENTER := Vector2(5.0, 30.2)
const LAKE_RADIUS := 2.20
const LAKE_BANK := 0.90
const LAKE_DEPTH := 0.58
## Pont posé aux croisements de rues (centres des rues horizontales).
const BRIDGE_ASSET := "res://assets/objects3d/props/pont.glb"
const BRIDGE_CROSSINGS := [15.5, 3.5]

## Matières du document (mêmes ids que MapData/MapGround3D).
const MATERIAL_GRASS := 0
const MATERIAL_DIRT := 1
const MATERIAL_STONE := 2
const MATERIAL_SAND := 4

var _editor: Control
var _md: Node

func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var scene_seed := _read_seed()
	var map := build_map(_md, scene_seed)
	if map.is_empty():
		push_error("[CITE EAU] Impossible de créer la carte.")
		get_tree().quit(1)
		return
	if _md != null:
		_md.preview_map_id = str(map.get("id", ""))
	DisplayServer.window_set_title("OpenQuest — %s (cité au fil de l'eau)" % MAP_NAME)
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
	await get_tree().process_frame
	_editor.load_map(map)
	await get_tree().process_frame
	if _editor._overlay != null:
		_editor._overlay.show_light_radii = false
	_editor._sync_engine()
	if _editor._engine != null:
		_editor._engine.focus_grid_rect(Rect2(0.5, 0.5,
			float(MAP_WIDTH) - 1.0, float(MAP_HEIGHT) - 1.0))
	_add_hint(scene_seed)
	print("[CITE EAU] %s prête — %d × %d, graine %d, %d élément(s), %d bassin(s) d'eau." % [
		MAP_NAME, MAP_WIDTH, MAP_HEIGHT, scene_seed,
		_editor.doc.elements_sorted().size(), _editor.doc.water_bodies().size()])

## Graine lue dans les arguments utilisateur (`-- --seed 4242`).
func _read_seed() -> int:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg := str(args[i])
		if arg == "--seed" and i + 1 < args.size():
			return int(str(args[i + 1]))
		if arg.begins_with("--seed="):
			return int(arg.substr("--seed=".length()))
	return DEFAULT_SEED

## Carte complète prête pour `MapData`/l'éditeur (aucune donnée moteur touchée).
static func build_map(md: Node, city_seed: int = DEFAULT_SEED) -> Dictionary:
	if md == null:
		return {}
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary \
				and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var plan := build_plan(MAP_WIDTH, MAP_HEIGHT, city_seed)
	if plan.is_empty():
		return {}
	var map: Dictionary = md.create_complex_map(MAP_NAME, "general", "local",
		MAP_WIDTH, MAP_HEIGHT)
	if map.is_empty():
		return {}
	map["worldId"] = MONDE
	map["description"] = ("Vitrine 2.5D « qualité CS2 » : cité en assets 3D "
		+ "traversée par un canal de ville et bordée d'un lac — eau CS2, ponts, "
		+ "preset cinéma et socle de diorama.")
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	# Même éclairage / brume que cite_boot (soleil jour franc, brume de distance
	# uniquement : la composante hauteur voilerait la cité en vue haute).
	map["lighting"] = {"enabled": true, "preset": "jour", "direction": "nw",
		"intensity": 0.35, "sources": []}
	map["qualityPreset"] = "cinema"
	map["atmosphericFog"] = {"enabled": true, "density": 0.04, "heightDensity": 0.0}
	map["atmosphere"] = {"enabled": false, "tint": "#1a1410", "opacity": 0.0,
		"vignette": 0.0}
	map["terrainHeights"] = plan["heights"]
	map["terrainMaterials"] = plan["materials"]
	map["meshes"] = plan["meshes"]
	map["waterLevel"] = plan["water_level"]
	map["waterBodies"] = plan["water_bodies"]
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = MAP_WIDTH
	map["zoneH"] = MAP_HEIGHT
	var grid: Dictionary = {"show": false}
	if md.has_method("get_grid_config"):
		grid = md.get_grid_config(map).duplicate(true)
		grid["show"] = false
	map["grid"] = grid
	return map

# ===========================================================================
# Plan pur (données de carte uniquement) — déterministe pour une graine
# ===========================================================================

## Construit le plan de la carte : cité générée (assets 3D) + relief de ville +
## canal + lac + ponts + eau. Aucun accès moteur : tout est données de carte.
static func build_plan(width: int = MAP_WIDTH, height: int = MAP_HEIGHT,
		city_seed: int = DEFAULT_SEED) -> Dictionary:
	var plan: Dictionary = ProceduralCityScript.generate(width, height,
		city_seed, DENSITY)
	var built: Dictionary = ProceduralCityScript.build_city_elements(plan,
		width, height)
	# --- Relief de base : cœur de ville PLAT, ceintures ondulées (comme la
	# démo de la cité : les bâtiments restent droits et lisibles).
	var heights: Array = []
	heights.resize(width * height)
	for y in range(height):
		for x in range(width):
			var in_city := x >= 2 and x <= width - 3 and y >= 2 and y <= height - 3
			var value := 0.0
			if not in_city:
				value = 0.16 * sin(float(x) * 0.52) * cos(float(y) * 0.44) \
					+ 0.06 * sin(float(x + y) * 0.85) + 0.04
			heights[y * width + x] = value
	# --- Matières de base : sol peints par le plan (rues pavées, place, terre).
	var materials: Array = []
	materials.resize(width * height)
	materials.fill(MATERIAL_GRASS)
	var terrain: Dictionary = built.get("terrain", {})
	for cell_variant in terrain.keys():
		var cell: Vector2i = cell_variant
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			continue
		materials[cell.y * width + cell.x] = clampi(
			int(terrain[cell_variant]), MATERIAL_GRASS, MATERIAL_SAND)
	# --- Creusement du canal et du lac, berges en pente douce ----------------
	for y in range(height):
		for x in range(width):
			var info := water_occupancy(x, y)
			if not bool(info.get("water", false)) and float(info.get("t", -1.0)) < 0.0:
				continue
			var idx := y * width + x
			var base := float(heights[idx])
			var bed := WATER_LEVEL - float(info.get("depth", CANAL_DEPTH))
			if bool(info.get("water", false)):
				heights[idx] = bed
				materials[idx] = MATERIAL_SAND
				continue
			# Berge : sable près de l'eau, pierre de quai au-dessus (pente douce).
			var t := clampf(float(info.get("t", 0.0)), 0.0, 1.0)
			var smooth := t * t * (3.0 - 2.0 * t)
			heights[idx] = lerpf(bed, base, smooth)
			materials[idx] = MATERIAL_SAND if t < 0.55 else MATERIAL_STONE
	# Couverture d'eau RÉELLE : toute case dont le sol visible est sous le
	# niveau (c'est exactement le masque calculé par la couche d'eau).
	var water_cells := 0
	var bank_cells := 0
	for y in range(height):
		for x in range(width):
			var idx := y * width + x
			if float(heights[idx]) < WATER_LEVEL:
				water_cells += 1
				materials[idx] = MATERIAL_SAND
			elif float(water_occupancy(x, y).get("t", -1.0)) >= 0.0:
				bank_cells += 1
				if materials[idx] == MATERIAL_GRASS:
					materials[idx] = MATERIAL_STONE
	# --- Éléments 3D : on retire tout ce qui tomberait dans l'eau/la berge ----
	var meshes := _filter_elements(built.get("elements", []), width, height,
		heights)
	# --- Ponts : traversent le canal au niveau de la ville --------------------
	var bridge_fp: Vector2 = ProceduralCityScript.asset_footprint(BRIDGE_ASSET)
	for i in range(BRIDGE_CROSSINGS.size()):
		meshes.append({
			"id": "ce-pont-%02d" % i,
			"x": CANAL_X,
			"y": float(BRIDGE_CROSSINGS[i]),
			"w": bridge_fp.x,
			"h": bridge_fp.y,
			"asset": BRIDGE_ASSET,
			"elevation": 0.02,
			# Pied au niveau de la ville (y=0), pas au fond du canal.
			"followTerrain": false,
			"tiltToTerrain": false,
			"label": "Pont du canal",
			"layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
			"hidden": false,
		})
	# --- Bassins d'eau (données de la couche eau) ----------------------------
	# Le canal est un plan d'eau de type LAC (surface plate découpée par le
	# masque de profondeur) : c'est le type qui rend une eau LISIBLE dans une
	# tranchée étroite — le ruban de rivière, à deux sommets en travers, se fond
	# dans les berges et disparaît. Son emprise est un peu plus large que l'eau
	# pour que la couche d'eau adoucisse elle-même la ligne de rive.
	var canal_poly: Array = []
	var canal_x0 := CANAL_X - CANAL_HALF - CANAL_BANK
	var canal_x1 := CANAL_X + CANAL_HALF + CANAL_BANK
	var canal_steps := 14
	for i in range(canal_steps + 1):
		var t := float(i) / float(canal_steps)
		var wy := lerpf(0.15, float(height) - 0.15, t)
		# Bords légèrement ondulés (jamais une coupe rectiligne).
		canal_poly.append([canal_x0 + sin(float(i) * 1.7) * 0.10, wy])
	for i in range(canal_steps, -1, -1):
		var t := float(i) / float(canal_steps)
		var wy := lerpf(0.15, float(height) - 0.15, t)
		canal_poly.append([canal_x1 + sin(float(i) * 1.3 + 2.1) * 0.10, wy])
	var lake_poly: Array = []
	var segments := 18
	# L'emprise du bassin couvre TOUT le bol (eau + berge) : le masque de la
	# couche eau y remplit les cases sous le niveau et laisse la berge à sec.
	# Les points sont ROGNÉS au bord de la carte (baie de bordure) : aucune
	# nappe d'eau ne déborde du socle.
	var lake_reach := LAKE_RADIUS + LAKE_BANK + 0.25
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		lake_poly.append([
			clampf(LAKE_CENTER.x + cos(angle) * lake_reach, 0.15, float(width) - 0.15),
			clampf(LAKE_CENTER.y + sin(angle) * lake_reach, 0.15, float(height) - 0.15),
		])
	var water_bodies: Array = [
		{
			"id": "canal", "kind": "lake", "level": WATER_LEVEL,
			"area": canal_poly,
		},
		{
			"id": "lac", "kind": "lake", "level": WATER_LEVEL,
			"area": lake_poly,
		},
	]
	return {
		"width": width,
		"height": height,
		"heights": heights,
		"materials": materials,
		"meshes": meshes,
		"water_bodies": water_bodies,
		"water_level": WATER_LEVEL,
		"water_cells": water_cells,
		"bank_cells": bank_cells,
		"seed": city_seed,
		"counts": built.get("counts", {}),
	}

## Occupation d'une case par l'eau : `water` = plein d'eau, sinon `t` en 0..1
## = position dans la berge (0 au bord de l'eau, 1 en haut de la berge) ;
## `depth` = profondeur du lit sous la surface. Canal prioritaire sur le lac.
static func water_occupancy(cx: int, cy: int) -> Dictionary:
	var px := float(cx) + 0.5
	var py := float(cy) + 0.5
	var dx := absf(px - CANAL_X)
	if dx <= CANAL_HALF:
		return {"water": true, "t": 0.0, "depth": CANAL_DEPTH, "kind": "canal"}
	if dx <= CANAL_HALF + CANAL_BANK:
		return {"water": false,
			"t": clampf((dx - CANAL_HALF) / CANAL_BANK, 0.0, 1.0),
			"depth": CANAL_DEPTH, "kind": "canal"}
	var d := Vector2(px - LAKE_CENTER.x, py - LAKE_CENTER.y).length()
	if d <= LAKE_RADIUS:
		return {"water": true, "t": 0.0, "depth": LAKE_DEPTH, "kind": "lake"}
	if d <= LAKE_RADIUS + LAKE_BANK:
		return {"water": false,
			"t": clampf((d - LAKE_RADIUS) / LAKE_BANK, 0.0, 1.0),
			"depth": LAKE_DEPTH, "kind": "lake"}
	return {"water": false, "t": -1.0, "depth": 0.0, "kind": ""}

## Filtre les éléments 3D générés : on conserve la cité et ses décors, mais on
## retire tout ce qui tomberait dans l'eau ou sur la berge (aucun bâti noyé ni
## prop flottant). Les toitures/façades suivent le sort de leur bâtiment (groupes
## consécutifs produits par `build_city_elements`).
static func _filter_elements(entries: Array, width: int, height: int,
		heights: Array) -> Array:
	var out: Array = []
	var drop_group := false
	var index := 0
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var raw_variant = entry.get("elem", {})
		if not (raw_variant is Dictionary):
			continue
		var raw: Dictionary = (raw_variant as Dictionary).duplicate(true)
		if raw.is_empty():
			continue
		var note := str(entry.get("note", ""))
		var is_building := note.contains("Bâtiment")
		var is_child := note.contains("Toiture") or note.contains("Façade")
		if is_building:
			drop_group = _element_touches_water(raw, width, height, heights)
		if drop_group and (is_building or is_child):
			continue
		if not is_building and not is_child:
			if _element_touches_water(raw, width, height, heights):
				continue
		raw["id"] = "ce-%04d" % index
		raw["hidden"] = false
		index += 1
		out.append(raw)
	return out

## Vrai si l'empreinte d'un élément touche une case sous l'eau (sol visible sous
## le niveau) ou une case de berge : on ne pose ni bâtiment ni prop mouillé.
static func _element_touches_water(raw: Dictionary, width: int, height: int,
		heights: Array) -> bool:
	var x := float(raw.get("x", 0.0))
	var y := float(raw.get("y", 0.0))
	var w := maxf(0.1, float(raw.get("w", 1.0)))
	var h := maxf(0.1, float(raw.get("h", 1.0)))
	var x0 := maxi(0, int(floorf(x - w * 0.5)))
	var x1 := mini(width - 1, int(ceili(x + w * 0.5)))
	var y0 := maxi(0, int(floorf(y - h * 0.5)))
	var y1 := mini(height - 1, int(ceili(y + h * 0.5)))
	for cz in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if float(heights[cz * width + cx]) < WATER_LEVEL:
				return true
			if float(water_occupancy(cx, cz).get("t", -1.0)) >= 0.0:
				return true
	return false

## Petite aide affichée en mode démo.
func _add_hint(_scene_seed: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var label := Label.new()
	label.text = "%s — cité 3D + canal + lac (preset cinéma).  Eau : glisser la caméra le long du canal." % MAP_NAME
	label.position = Vector2(16.0, 16.0)
	label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
