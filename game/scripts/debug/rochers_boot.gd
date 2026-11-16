extends Node

## Démo « Rochers — formations Tripo3D » : carte plate 30 × 20 ouverte dans
## l'éditeur, avec **trois formations rocheuses générées** par
## `procedural_rock_formation.gd` :
##   • un affleurement (crête de `bloc_rocheux_*` avec 2–3 assises et éboulis) ;
##   • un éboulis (cône de cailloux `caillou_*`) ;
##   • une carrière (front de taille `falaise`/`gros_rocher` + banquette arrière).
##
## La carte utilise le preset qualité `cinema` : les rochers projettent leurs
## ombres et reçoivent les matériaux PBR éclairés (voir task-1/task-6).
## La bibliothèque d'objets 3D est ouverte sur `bloc_rocheux_socle` pour
## prolonger la formation à la main.
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/rochers_boot.tscn

const Formation := preload("res://scripts/maps/construction/procedural_rock_formation.gd")

## Valeur de `MapEditDocument.KIND_MESH` (évite de précharger le document, qui
## dépend de l'autoload `MapData` : la démo doit rester chargeable hors session).
const KIND_MESH := "mesh"

const MONDE := "demo-rochers-formation"
const MAP_NAME := "Rochers — formations Tripo3D"
const MAP_WIDTH := 30
const MAP_HEIGHT := 20
## Une seule graine globale : changer ces valeurs change la démo (et les captures).
const DEMO_SEED := 20261112
const QUALITY_PRESET := "cinema"

## Recettes de démo : 2 affleurements + 1 éboulis + 1 carrière.
## (kinds en clair pour rester un initialiseur constant ; cf. Formation.KIND_*).
const DEMO_FORMATIONS := [
	{
		"kind": "affleurement",
		"origin": Vector2(5.0, 6.0),
		"direction": Vector2(1.0, 0.28),
		"length": 8.0,
		"seed_offset": 0,
		"density": 1.15,
	},
	{
		"kind": "affleurement",
		"origin": Vector2(14.0, 3.5),
		"direction": Vector2(0.35, 1.0),
		"length": 6.0,
		"seed_offset": 101,
		"density": 0.95,
	},
	{
		"kind": "eboulis",
		"origin": Vector2(23.5, 6.5),
		"direction": Vector2(-0.4, 1.0),
		"length": 7.0,
		"seed_offset": 211,
		"density": 1.5,
	},
	{
		"kind": "carriere",
		"origin": Vector2(7.0, 14.0),
		"direction": Vector2(1.0, 0.22),
		"length": 9.0,
		"seed_offset": 331,
		"density": 1.1,
	},
]

var _editor: Control
var _md: Node


func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var map := build_map(_md)
	if map.is_empty():
		push_error("[ROCHERS DEMO] Impossible de créer la carte.")
		get_tree().quit(1)
		return
	var map_id := str(map.get("id", ""))
	if _md != null:
		_md.preview_map_id = map_id
	DisplayServer.window_set_title("OpenQuest — %s" % MAP_NAME)
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
	await get_tree().process_frame
	_editor.load_map(map)
	await get_tree().process_frame
	var placed := apply_formations(_editor.doc, generate_plans(MAP_WIDTH, MAP_HEIGHT))
	_editor.doc.clear_selection()
	_editor._sync_engine()
	if _editor._engine != null:
		_editor._engine.focus_grid_rect(
			Rect2(0.5, 0.5, float(MAP_WIDTH) - 1.0, float(MAP_HEIGHT) - 1.0))
	# Bibliothèque ouverte sur les rochers Tripo3D, outil 3D armé.
	_editor._prop_category = "objects3d"
	_editor._mesh_asset = Formation.asset_path(Formation.TRIPO_SOCLE)
	_editor._set_tool("mesh")
	_editor._refresh_asset_library()
	_editor._set_status(
		"%d éléments de formation rocheuse (Tripo3D + cailloux + kit) — "
		% placed
		+ "clic sur la carte pour ajouter le rocher armé, R pivote, Ctrl+Z annule la génération.")
	_add_hint(placed)
	print("[ROCHERS DEMO] %s prête — %d × %d, preset=%s, %d élément(s) de formation." % [
		MAP_NAME, MAP_WIDTH, MAP_HEIGHT, QUALITY_PRESET, placed])


# ===========================================================================
# Carte et plans (réutilisés par le test de capture)
# ===========================================================================

## Carte plate 30 × 20 en herbe, preset qualité « cinéma » (ombres + PBR).
static func build_map(md: Node) -> Dictionary:
	if md == null:
		return {}
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary \
				and str((map_variant as Dictionary).get("worldId", "")) == MONDE:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map(MAP_NAME, "general", "local",
		MAP_WIDTH, MAP_HEIGHT)
	if map.is_empty():
		return {}
	var heights: Array = []
	heights.resize(MAP_WIDTH * MAP_HEIGHT)
	heights.fill(0.0)
	var materials: Array = []
	materials.resize(MAP_WIDTH * MAP_HEIGHT)
	materials.fill(0)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	# Lumière du jour franche (soleil chaud + ambiante froide) : le preset
	# `tiny_glade` (pastel, ciel très lumineux) lavait les rochers en vue haute.
	map["lighting"] = {"enabled": true, "preset": "jour", "direction": "nw",
		"intensity": 0.35, "sources": []}
	# Brume atmosphérique fine, SANS composante hauteur : la valeur par défaut
	# (`heightDensity` 0,22) voile toute la carte en caméra haute et lave les
	# rochers. On garde juste un léger voile de distance.
	map["atmosphericFog"] = {"enabled": true, "density": 0.04, "heightDensity": 0.0}
	# Opt-in : ombres soleil, AO, étalonnage et matériaux PBR (preset CS2).
	map["qualityPreset"] = QUALITY_PRESET
	map["terrainHeights"] = heights
	map["terrainMaterials"] = materials
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = MAP_WIDTH
	map["zoneH"] = MAP_HEIGHT
	map["worldId"] = MONDE
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))


## Plans des formations de démo (déterministes pour `DEMO_SEED`).
static func generate_plans(map_width: int, map_height: int) -> Array:
	var plans: Array = []
	var options := {"map_width": map_width, "map_height": map_height}
	for recipe_variant in DEMO_FORMATIONS:
		var recipe: Dictionary = recipe_variant
		var origin: Vector2 = recipe["origin"]
		var direction: Vector2 = recipe["direction"]
		var plan: Dictionary = Formation.generate(
			str(recipe["kind"]),
			origin,
			direction,
			float(recipe["length"]),
			DEMO_SEED + int(recipe["seed_offset"]),
			float(recipe["density"]),
			options
		)
		plan["demo_recipe"] = recipe
		plans.append(plan)
	return plans


## Crée les éléments mesh du plan dans un document d'éditeur. Renvoie le nombre
## d'éléments posés. Les appels `add_element` sont groupés en une seule étape
## d'annulation par l'appelant (`doc.begin_transaction()`).
static func apply_formations(doc: Variant, plans: Array) -> int:
	if doc == null:
		return 0
	var placed := 0
	doc.begin_transaction()
	for plan_variant in plans:
		var plan: Dictionary = plan_variant
		for element_variant in plan.get("elements", []):
			var element: Dictionary = element_variant
			var elevation := maxf(0.0, float(element.get("elevation", 0.0)))
			var id: String = doc.add_element({
				"x": float(element.get("x", 0.0)),
				"y": float(element.get("y", 0.0)),
				"w": maxf(0.2, float(element.get("w", 1.0))),
				"h": maxf(0.2, float(element.get("h", 1.0))),
				"asset": str(element.get("asset", "")),
				"elevation": elevation,
				# Le socle suit le relief ; les assises hautes gardent leur hauteur.
				"followTerrain": elevation <= 0.001,
				"tiltToTerrain": false,
				"label": str(element.get("label", "Rocher de formation")),
				"layer": 1,
				"display": {
					"rotation": float(element.get("rotation", 0.0)),
					"scale": float(element.get("scale", 1.0)),
				},
			}, KIND_MESH, "Formation rocheuse")
			if not id.is_empty():
				placed += 1
	doc.commit_transaction()
	return placed


# ===========================================================================
# Habillage de démo
# ===========================================================================

func _add_hint(placed: int) -> void:
	var hint := Label.new()
	hint.text = ("ROCHERS TRIPO3D — 2 affleurements, 1 éboulis, 1 carrière (%d éléments) "
		+ "et ombres du preset « cinéma ». Biblio → 🧊 Objets 3D pour ajouter "
		+ "bloc_rocheux_socle à la main · R pivote · Ctrl+Z annule la génération.") % placed
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 4
	hint.offset_left = 200
	hint.offset_right = -420
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)
