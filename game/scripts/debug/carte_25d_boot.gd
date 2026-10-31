extends Node

## Banc d'essai « carte 2.5D » : ouvre l'éditeur de cartes directement sur une
## carte de démonstration (fond Valbois, style 2.5D, objets 3D déjà posés), pour
## tester la pose de bâtiments 3D par n'importe qui.
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/carte_25d_boot.tscn
##
## Dans l'éditeur : onglet **Biblio → 🧊 Objets 3D**, cliquer un objet, puis
## cliquer la carte. `R` pivote, l'échelle est dans les options de l'outil.


var _editor: Control
var _md: Node

func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var demo := build_demo(_md)
	if demo.is_empty():
		push_error("[CARTE 2.5D] Impossible de construire la carte de démonstration.")
		get_tree().quit(1)
		return

	DisplayServer.window_set_title("OpenQuest — Carte 2.5D (éditeur de démonstration)")
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
	_editor.open_map_requested.connect(_on_open_map_requested)
	await get_tree().process_frame
	_editor.load_map(demo["map"])
	await get_tree().process_frame
	# Ouvre la bibliothèque sur les objets 3D et arme l'outil avec le 1er mesh.
	var assets: Array = demo.get("assets", [])
	if not assets.is_empty():
		_editor._prop_category = "objects3d"
		_editor._mesh_asset = str((assets[0] as Dictionary).get("path", ""))
		_editor._set_tool("mesh")
		_editor._refresh_asset_library()
		_editor._set_status("Objets 3D : cliquez un modèle dans Biblio, puis cliquez la carte (R pivote).")

	var hint := Label.new()
	hint.text = "CARTE 2.5D — Biblio → 🧊 Objets 3D (ou ＋ Importer un GLB) · outil ⛰ Relief (U) pour sculpter le sol · les objets s'adaptent au terrain · Échap = menu."
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 4
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)
	print("[CARTE 2.5D] Éditeur de démonstration prêt — ", assets.size(), " objet(s) 3D dans la biblio.")

## Ouvre une autre zone du monde dans l'éditeur autonome (vue Monde → Ouvrir).
func _on_open_map_requested(map_id: String) -> void:
	if _md == null or map_id.is_empty():
		return
	var map: Dictionary = _md.get_by_id(map_id)
	if map.is_empty():
		return
	_md.preview_map_id = map_id
	_editor.load_map(map)

## Construit une carte 2.5D de démonstration avec quelques objets 3D posés.
## Réutilisé par les tests de capture.
static func build_demo(md: Node) -> Dictionary:
	if md == null:
		return {}
	# Repart d'un monde de démo propre : les captures/tests ne doivent pas
	# empiler des copies de zones à chaque exécution.
	for existing_variant in md.maps.duplicate():
		if not existing_variant is Dictionary:
			continue
		var existing_world := str((existing_variant as Dictionary).get("worldId", ""))
		if existing_world == "demo-valbois" or existing_world == "demo-iles":
			md.delete_map(str((existing_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map("Démo 2.5D — objets 3D", "general", "local", 24, 16)
	if map.is_empty():
		return {}
	var map_id := str(map.get("id", ""))
	# Vrai terrain 3D simple (pas de fond peint déformé).
	map["backgroundImage"] = ""
	map["groundMode"] = "terrain3d"
	map["renderStyle"] = "2.5d"
	map["ambientFx"] = "leaves"
	map["fogEnabled"] = false
	map["worldId"] = "demo-valbois"
	md.update_map(map)
	map = md.get_by_id(map_id)
	if map.is_empty():
		return {}

	var assets: Array = []
	var AssetLibraryScript: GDScript = load("res://scripts/maps/map_asset_library.gd")
	assets = AssetLibraryScript.list_object3d_assets()
	var by_name: Dictionary = {}
	for asset_variant in assets:
		var asset: Dictionary = asset_variant
		var key := str(asset.get("name", "")).to_lower().replace("_", " ").replace("-", " ")
		by_name[key] = str(asset.get("path", ""))

	var placements := [
		{"name": "maison", "x": 7.0, "y": 6.0, "rotation": 0.0, "w": 2.0, "h": 2.0},
		{"name": "maison_petite", "x": 5.0, "y": 9.0, "rotation": 30.0, "w": 1.5, "h": 1.5},
		{"name": "maison_grande", "x": 11.0, "y": 5.0, "rotation": 90.0, "w": 2.3, "h": 2.1},
		{"name": "tour", "x": 14.5, "y": 6.5, "rotation": 0.0, "w": 1.5, "h": 1.5},
		{"name": "tour_grande", "x": 17.0, "y": 9.0, "rotation": 45.0, "w": 1.7, "h": 1.7},
		{"name": "puits", "x": 9.5, "y": 8.5, "rotation": 0.0, "w": 1.2, "h": 1.0},
		{"name": "caisse", "x": 10.5, "y": 9.8, "rotation": 30.0, "w": 1.0, "h": 1.0},
		{"name": "caisse_grande", "x": 7.5, "y": 10.5, "rotation": 0.0, "w": 1.3, "h": 1.3},
		{"name": "palissade", "x": 12.0, "y": 10.5, "rotation": 0.0, "w": 2.2, "h": 0.6},
		{"name": "pont", "x": 13.0, "y": 8.0, "rotation": 0.0, "w": 2.6, "h": 1.3},
		{"name": "arbre", "x": 4.5, "y": 7.5, "rotation": 0.0, "w": 1.0, "h": 1.0},
		{"name": "arbre_automne", "x": 15.5, "y": 11.0, "rotation": 0.0, "w": 1.0, "h": 1.0},
		{"name": "rocher", "x": 16.5, "y": 6.0, "rotation": 45.0, "w": 1.4, "h": 1.2},
		# Kit 2 : vie du village (étal, tonneau, lanterne, mobilier, charrette).
		{"name": "etal_marche", "x": 9.0, "y": 7.0, "rotation": 15.0, "w": 1.8, "h": 1.0},
		{"name": "tonneau", "x": 10.6, "y": 7.4, "rotation": 0.0, "w": 0.8, "h": 0.8},
		{"name": "lanterne", "x": 8.2, "y": 8.6, "rotation": 0.0, "w": 0.6, "h": 0.6},
		{"name": "banc", "x": 11.8, "y": 6.8, "rotation": 90.0, "w": 1.4, "h": 0.6},
		{"name": "panneau", "x": 6.2, "y": 5.4, "rotation": 0.0, "w": 0.7, "h": 0.7},
		{"name": "charrette", "x": 13.6, "y": 10.0, "rotation": 30.0, "w": 1.8, "h": 1.2},
		{"name": "botte_foin", "x": 14.6, "y": 10.6, "rotation": 0.0, "w": 1.0, "h": 1.0},
		{"name": "barriere", "x": 5.0, "y": 11.0, "rotation": 0.0, "w": 2.0, "h": 0.5},
		{"name": "mur", "x": 11.0, "y": 11.2, "rotation": 0.0, "w": 2.0, "h": 0.5},
		{"name": "mur_coin", "x": 13.0, "y": 11.2, "rotation": 0.0, "w": 1.0, "h": 1.0},
		{"name": "enseigne", "x": 8.6, "y": 5.2, "rotation": 0.0, "w": 1.0, "h": 1.0},
		{"name": "buisson", "x": 4.2, "y": 9.6, "rotation": 0.0, "w": 1.2, "h": 1.0},
		# Kit 4 : bâtiments variés et figurines PNJ.
		{"name": "chapelle", "x": 3.0, "y": 3.0, "rotation": 0.0, "w": 2.6, "h": 2.6},
		{"name": "forge", "x": 18.6, "y": 12.6, "rotation": 0.0, "w": 2.4, "h": 2.2},
		{"name": "maison_etage", "x": 20.2, "y": 4.4, "rotation": 0.0, "w": 2.2, "h": 2.0},
		{"name": "grange", "x": 2.4, "y": 12.8, "rotation": 0.0, "w": 2.9, "h": 3.2},
		{"name": "fontaine", "x": 11.4, "y": 7.2, "rotation": 0.0, "w": 2.1, "h": 2.3},
		{"name": "pnj_marchand", "x": 10.2, "y": 8.2, "rotation": 0.0, "w": 0.8, "h": 0.8},
		{"name": "pnj_aventurier", "x": 7.6, "y": 7.6, "rotation": 0.0, "w": 0.8, "h": 0.8},
		{"name": "pnj_garde", "x": 13.6, "y": 6.4, "rotation": 0.0, "w": 0.9, "h": 0.8},
		# Kit 5 : environnement et habillage.
		{"name": "banniere", "x": 5.0, "y": 2.2, "rotation": 0.0, "w": 1.3, "h": 0.9},
		{"name": "gros_rocher", "x": 21.6, "y": 2.0, "rotation": 20.0, "w": 2.1, "h": 1.9},
		{"name": "haie", "x": 6.2, "y": 13.2, "rotation": 0.0, "w": 2.5, "h": 0.9},
		{"name": "tas_de_bois", "x": 16.6, "y": 10.8, "rotation": 0.0, "w": 1.4, "h": 1.0},
		{"name": "cloture_basse", "x": 20.4, "y": 8.8, "rotation": 0.0, "w": 2.2, "h": 0.4},
		# Kit 7 : accent de toiture posé sur la chapelle.
		{"name": "toit_clocheton", "x": 3.0, "y": 3.0, "rotation": 0.0, "w": 0.7, "h": 0.7, "elevation": 3.0},
		# Modules de façade accentués (aimantation reproduite à la main pour la démo).
		{"name": "porte_auvent", "x": 7.0, "y": 7.27, "rotation": 0.0, "w": 1.37, "h": 0.74},
		{"name": "fenetre_volets", "x": 9.83, "y": 5.0, "rotation": 90.0, "w": 1.58, "h": 0.24},
	]
	var meshes: Array = []
	for entry in placements:
		var lookup := str(entry["name"]).to_lower().replace("_", " ").replace("-", " ")
		var asset_path := str(by_name.get(lookup, ""))
		if asset_path.is_empty():
			continue
		var asset_name := str(entry["name"])
		var tilts := asset_name.begins_with("arbre") or asset_name == "rocher"
		meshes.append({
			"id": "mesh-demo-%s" % asset_name,
			"kind": "mesh",
			"x": float(entry["x"]), "y": float(entry["y"]),
			"w": float(entry.get("w", 1.0)), "h": float(entry.get("h", 1.0)),
			"asset": asset_path,
			"elevation": float(entry.get("elevation", 0.0)),
			"followTerrain": true,
			"tiltToTerrain": tilts,
			"label": asset_name.capitalize(),
			"layer": 1,
			"display": {"rotation": float(entry["rotation"]), "scale": 1.0},
		})
	map["meshes"] = meshes

	# Relief de démonstration : une butte douce au centre-ouest, pour voir les
	# objets 3D s'adapter au sol (hauteur par case, en cases).
	var w := int(map.get("width", 24))
	var h := int(map.get("height", 16))
	var heights: Array = []
	heights.resize(w * h)
	heights.fill(0.0)
	for cy in range(h):
		for cx in range(w):
			var d := Vector2(cx, cy).distance_to(Vector2(9.5, 7.5))
			var hill := maxf(0.0, 1.4 * (1.0 - d / 6.5))
			heights[cy * w + cx] = hill
	map["terrainHeights"] = heights
	map["terrainMaterials"] = _demo_materials(w, h, "village")
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = w
	map["zoneH"] = h
	md.update_map(map)
	map = md.get_by_id(map_id)

	# --- Monde de démonstration : 5 zones adjacentes de tailles différentes ---
	var WorldZonesScript: GDScript = load("res://scripts/maps/world/world_zones.gd")
	var world_maps: Array = [map]
	var extra_specs := [
		{
			"title": "Place du Marché", "w": 14, "h": 12, "x": 25, "y": 0,
			"meshes": [
				{"name": "puits", "x": 4.0, "y": 5.0},
				{"name": "caisse", "x": 7.0, "y": 7.0},
				{"name": "arbre", "x": 9.5, "y": 3.0},
				{"name": "etal_marche", "x": 10.0, "y": 7.0},
				{"name": "tonneau", "x": 8.0, "y": 8.5},
				{"name": "banc", "x": 3.0, "y": 8.0},
				{"name": "lanterne", "x": 6.0, "y": 4.0},
				{"name": "enseigne", "x": 8.5, "y": 4.5},
				{"name": "buisson", "x": 11.0, "y": 9.5},
				{"name": "buisson", "x": 2.0, "y": 2.5},
				{"name": "marche_couvert", "x": 10.5, "y": 8.8},
				{"name": "fontaine", "x": 6.5, "y": 5.5},
				{"name": "pnj_marchand", "x": 5.0, "y": 7.5},
				{"name": "pnj_garde", "x": 9.0, "y": 3.5},
			],
		},
		{
			"title": "Forêt de l'Ouest", "w": 12, "h": 12, "x": 0, "y": 17,
			"meshes": [
				{"name": "arbre", "x": 3.0, "y": 3.0},
				{"name": "arbre_automne", "x": 8.0, "y": 6.0},
				{"name": "rocher", "x": 5.0, "y": 8.0},
				{"name": "arbre", "x": 9.0, "y": 9.0},
				{"name": "botte_foin", "x": 2.5, "y": 6.0},
				{"name": "buisson", "x": 2.0, "y": 2.0},
				{"name": "buisson", "x": 7.0, "y": 10.0},
				{"name": "tour_guet_bois", "x": 9.5, "y": 3.0},
				# Kit 5 : environnement de forêt et d'étang.
				{"name": "arbre_majestueux", "x": 10.3, "y": 6.4, "w": 2.5, "h": 2.3},
				{"name": "bosquet", "x": 4.0, "y": 2.0, "w": 2.4, "h": 2.4},
				{"name": "falaise", "x": 9.4, "y": 10.2, "w": 2.3, "h": 2.3},
				{"name": "roseaux", "x": 4.2, "y": 6.6, "w": 1.4, "h": 1.2},
				{"name": "ponton", "x": 3.8, "y": 7.6, "w": 2.3, "h": 0.9, "elevation": 0.28},
				{"name": "barque", "x": 2.4, "y": 8.8, "rotation": 30.0, "w": 1.9, "h": 1.0, "elevation": 0.52},
				{"name": "nenuphars", "x": 1.2, "y": 8.3, "w": 1.3, "h": 1.0, "elevation": 0.16},
				{"name": "nenuphars", "x": 3.0, "y": 9.6, "w": 1.3, "h": 1.0, "elevation": 0.21},
			],
		},
		{
			"title": "Taverne du Corbeau", "w": 10, "h": 8, "x": 39, "y": 0,
			"meshes": [
				{"name": "mur", "x": 1.5, "y": 0.0},
				{"name": "mur", "x": 4.0, "y": 0.0},
				{"name": "mur", "x": 6.5, "y": 0.0},
				{"name": "mur_coin", "x": 9.0, "y": 0.0},
				{"name": "table_tabourets", "x": 4.5, "y": 4.0},
				{"name": "comptoir", "x": 7.8, "y": 1.6},
				{"name": "tonneau_couche", "x": 1.4, "y": 6.6},
				{"name": "tapis", "x": 2.6, "y": 3.2},
				{"name": "lit", "x": 8.4, "y": 6.6},
				{"name": "lanterne", "x": 4.5, "y": 1.2},
				{"name": "pnj_aventurier", "x": 2.8, "y": 5.4},
				{"name": "pnj_marchand", "x": 6.2, "y": 5.4},
			],
		},
		{
			"title": "Donjon de Valbois", "w": 9, "h": 9, "x": 25, "y": 12,
			"meshes": [
				{"name": "mur", "x": 1.5, "y": 0.6},
				{"name": "mur", "x": 4.0, "y": 0.6},
				{"name": "mur", "x": 6.5, "y": 0.6},
				{"name": "mur_coin", "x": 8.0, "y": 0.6},
				{"name": "lanterne", "x": 4.5, "y": 1.5},
				{"name": "lanterne", "x": 2.5, "y": 5.0},
				{"name": "lanterne", "x": 6.8, "y": 5.0},
				{"name": "rocher", "x": 7.0, "y": 7.0},
				{"name": "sarcophage", "x": 4.0, "y": 4.5},
				{"name": "pile_os", "x": 2.0, "y": 6.5},
				{"name": "herse", "x": 4.5, "y": 7.6},
			],
		},
		{
			"title": "Camp des Bûcherons", "w": 10, "h": 8, "x": 39, "y": 8,
			"meshes": [
				{"name": "grange", "x": 2.5, "y": 2.5},
				{"name": "tas_de_bois", "x": 6.8, "y": 2.8},
				{"name": "botte_foin", "x": 4.6, "y": 5.0},
				{"name": "tonneau", "x": 6.4, "y": 5.4},
				{"name": "banc", "x": 3.4, "y": 5.6},
				{"name": "lanterne", "x": 5.0, "y": 2.2},
				{"name": "pnj_villageois", "x": 4.2, "y": 3.8},
				{"name": "cloture_basse", "x": 7.4, "y": 6.4},
			],
		},
		{
			"title": "Ruines de l'Ouest", "w": 12, "h": 10, "x": 13, "y": 16,
			"meshes": [
				{"name": "mur", "x": 2.5, "y": 3.0},
				{"name": "mur_coin", "x": 5.5, "y": 3.0},
				{"name": "mur", "x": 8.5, "y": 3.0},
				{"name": "herse", "x": 6.0, "y": 6.5},
				{"name": "sarcophage", "x": 8.0, "y": 7.0},
				{"name": "pile_os", "x": 3.0, "y": 7.0},
				{"name": "gros_rocher", "x": 10.0, "y": 8.0},
				{"name": "falaise", "x": 10.0, "y": 2.0},
				{"name": "buisson", "x": 2.0, "y": 8.0},
			],
		},
	]
	for spec_variant in extra_specs:
		var spec: Dictionary = spec_variant
		var sub: Dictionary = md.create_complex_map(str(spec["title"]), "general", "local",
			int(spec["w"]), int(spec["h"]))
		var sub_id := str(sub.get("id", ""))
		if sub_id.is_empty():
			continue
		sub["renderStyle"] = "2.5d"
		sub["groundMode"] = "terrain3d"
		sub["backgroundImage"] = ""
		sub["fogEnabled"] = false
		sub["worldId"] = "demo-valbois"
		sub["zoneX"] = int(spec["x"])
		sub["zoneY"] = int(spec["y"])
		sub["zoneW"] = int(spec["w"])
		sub["zoneH"] = int(spec["h"])
		var style := "place" if str(spec["title"]).contains("Place") else "forest"
		if str(spec["title"]).contains("Taverne"):
			style = "tavern"
		elif str(spec["title"]).contains("Donjon"):
			style = "dungeon"
		elif str(spec["title"]).contains("Camp"):
			style = "camp"
		elif str(spec["title"]).contains("Ruines"):
			style = "ruins"
		sub["terrainMaterials"] = _demo_materials(int(spec["w"]), int(spec["h"]), style)
		# Ambiances animées par type de zone.
		if style == "forest":
			sub["ambientFx"] = "fireflies"
		elif style == "tavern" or style == "dungeon":
			sub["ambientFx"] = "dust"
		elif style == "place" or style == "camp":
			sub["ambientFx"] = "leaves"
		elif style == "ruins":
			sub["ambientFx"] = "rain"
		# Camp d'hiver : plaques de neige aux coins + congères douces + neige.
		if style == "camp":
			var w_camp := int(spec["w"])
			var h_camp := int(spec["h"])
			var camp_mats: Array = sub.get("terrainMaterials", [])
			var camp_heights: Array = []
			camp_heights.resize(w_camp * h_camp)
			camp_heights.fill(0.0)
			var snow_centers := [
				Vector2(1.6, 1.6), Vector2(w_camp - 1.6, 1.6),
				Vector2(1.6, h_camp - 1.6), Vector2(w_camp - 1.6, h_camp - 1.6),
			]
			for cy_c in range(h_camp):
				for cx_c in range(w_camp):
					var idx_c := cy_c * w_camp + cx_c
					if idx_c >= camp_mats.size():
						continue
					for center_variant in snow_centers:
						var d_c := Vector2(cx_c, cy_c).distance_to(center_variant)
						if d_c < 2.3:
							camp_mats[idx_c] = MapData.MATERIAL_SNOW
							camp_heights[idx_c] = 0.16 * (1.0 - d_c / 2.3)
							break
			sub["terrainMaterials"] = camp_mats
			sub["terrainHeights"] = camp_heights
			sub["ambientFx"] = "snow"
		# Donjon en ambiance nocturne : lanternes et torches ressortent.
		if style == "dungeon":
			sub["lighting"] = {
				"enabled": true, "direction": "nw", "intensity": 0.15,
				"nightMode": true, "nightAmbient": 0.45,
			}
		# Étang en forêt : dépression douce + plan d'eau.
		if style == "forest":
			var w_sub := int(spec["w"])
			var h_sub := int(spec["h"])
			var pond_center := Vector2(2.2, 9.0)
			var pond := []
			pond.resize(w_sub * h_sub)
			pond.fill(0.0)
			for cy in range(h_sub):
				for cx in range(w_sub):
					var dp := Vector2(cx, cy).distance_to(pond_center)
					if dp < 2.6:
						pond[cy * w_sub + cx] = -0.75 * (1.0 - dp / 2.6)
			sub["terrainHeights"] = pond
			sub["waterLevel"] = -0.25
			# Plage de sable autour de l'étang (matière ID 4).
			var forest_mats: Array = sub.get("terrainMaterials", [])
			for cy_f in range(h_sub):
				for cx_f in range(w_sub):
					var idx_f := cy_f * w_sub + cx_f
					if idx_f >= forest_mats.size():
						continue
					var shore := Vector2(cx_f, cy_f).distance_to(pond_center)
					if shore >= 2.3 and shore < 3.5:
						forest_mats[idx_f] = MapData.MATERIAL_SAND
			sub["terrainMaterials"] = forest_mats
		var sub_meshes: Array = []
		for m_variant in spec.get("meshes", []):
			var m: Dictionary = m_variant
			var lookup := str(m.get("name", "")).to_lower().replace("_", " ").replace("-", " ")
			var path := str(by_name.get(lookup, ""))
			if path.is_empty():
				continue
			sub_meshes.append({
				"id": "mesh-%s-%s" % [sub_id, str(m.get("name", ""))],
				"kind": "mesh",
				"x": float(m.get("x", 0.0)), "y": float(m.get("y", 0.0)),
				"w": 1.0, "h": 1.0,
				"asset": path,
				"elevation": float(m.get("elevation", 0.0)),
				"followTerrain": true,
				"tiltToTerrain": str(m.get("name", "")).begins_with("arbre") or str(m.get("name", "")) == "rocher",
				"label": str(m.get("name", "")).capitalize(),
				"layer": 1,
				"display": {"rotation": 0.0, "scale": 1.0},
			})
		sub["meshes"] = sub_meshes
		md.update_map(sub)
		world_maps.append(md.get_by_id(sub_id))

	# Auto-détection des bords (zones de tailles différentes) et écriture des liens.
	var zones: Array = []
	for m_variant in world_maps:
		if m_variant is Dictionary and not (m_variant as Dictionary).is_empty():
			zones.append(WorldZonesScript.zone_from_map(m_variant))
	var links: Dictionary = WorldZonesScript.auto_detect_edges(zones)
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var zone_map: Dictionary = md.get_by_id(str(zone.get("id", "")))
		if zone_map.is_empty():
			continue
		zone_map["zoneX"] = int(zone.get("x", 0))
		zone_map["zoneY"] = int(zone.get("y", 0))
		zone_map["zoneW"] = int(zone.get("w", 0))
		zone_map["zoneH"] = int(zone.get("h", 0))
		zone_map["edges"] = links.get(str(zone.get("id", "")), {})
		md.update_map(zone_map)
	map = md.get_by_id(map_id)
	md.preview_map_id = map_id

	# Second monde de démonstration (thèmes Lac et Bord de mer) pour montrer le
	# sélecteur de mondes de la vue Monde.
	var islands: Array = []
	var isle_specs := [
		{"title": "Île du Lac", "theme": "lake", "x": 0, "y": 0, "w": 10, "h": 8},
		{"title": "Plage des Brumes", "theme": "beach", "x": 11, "y": 0, "w": 10, "h": 8},
	]
	for isle_spec_variant in isle_specs:
		var isle_spec: Dictionary = isle_spec_variant
		var isle: Dictionary = md.create_complex_map(str(isle_spec["title"]), "general", "local",
			int(isle_spec["w"]), int(isle_spec["h"]))
		if isle.is_empty():
			continue
		var isle_id := str(isle.get("id", ""))
		isle["renderStyle"] = "2.5d"
		isle["groundMode"] = "terrain3d"
		isle["backgroundImage"] = ""
		isle["fogEnabled"] = false
		isle["worldId"] = "demo-iles"
		isle["zoneX"] = int(isle_spec["x"])
		isle["zoneY"] = int(isle_spec["y"])
		isle["zoneW"] = int(isle_spec["w"])
		isle["zoneH"] = int(isle_spec["h"])
		isle["edges"] = {}
		MapThemePresets.apply(isle, str(isle_spec["theme"]))
		md.update_map(isle)
		islands.append(md.get_by_id(isle_id))
	if islands.size() == 2:
		md.set_zone_edge(str((islands[0] as Dictionary).get("id", "")), "east",
			str((islands[1] as Dictionary).get("id", "")))
	md.set_world_title("demo-valbois", "Valbois")
	md.set_world_title("demo-iles", "Îles de Brume")

	return {
		"map": map,
		"assets": assets,
		"world_maps": world_maps,
		"second_world_maps": islands,
		"cells": Vector2i(int(map.get("width", 24)), int(map.get("height", 16))),
	} 

## Matières de sol de démonstration (0 herbe, 1 terre/chemin, 2 pierre/pavé).
static func _demo_materials(w: int, h: int, style: String) -> Array:
	var materials: Array = []
	materials.resize(w * h)
	materials.fill(0)
	var center := Vector2(float(w) * 0.5, float(h) * 0.5)
	for cy in range(h):
		for cx in range(w):
			var pos := Vector2(float(cx), float(cy))
			var mat := 0
			match style:
				"village":
					var d := pos.distance_to(Vector2(9.5, 7.5))
					if d < 2.4:
						mat = 2
					elif d < 3.4:
						mat = 1
					elif absf(float(cx) - 9.5) < 1.1 or absf(float(cy) - 7.5) < 1.1:
						mat = 1
				"place":
					var dp := pos.distance_to(center)
					if dp < 2.8:
						mat = 2
					elif dp < 4.0:
						mat = 1
					elif absf(float(cx) - center.x) < 1.0 or absf(float(cy) - center.y) < 1.0:
						mat = 1
				"forest":
					if absf(float(cx) - float(cy)) < 1.2 and cy > 2 and cy < h - 2:
						mat = 1
				"tavern":
					mat = 1
					if pos.distance_to(center) < 1.6:
						mat = 2
				"dungeon":
					mat = 2
					if absf(float(cx) - center.x) < 1.0 or absf(float(cy) - center.y) < 1.0:
						mat = 1
				"camp":
					mat = 0
					if pos.distance_to(center) < 3.2:
						mat = 1
					elif absf(float(cx) - 5.0) < 1.0:
						mat = 1
				"ruins":
					mat = 0
					if pos.distance_to(center) < 4.6:
						mat = 2
					elif absf(float(cx) - center.x) < 1.2:
						mat = 1
			materials[cy * w + cx] = mat
	return materials

## Les autoloads ne sont pas des identifiants globaux à la compilation en
## mode `--script` : les scripts qui référencent MapData sont chargés à
## l'exécution via `load()`.
