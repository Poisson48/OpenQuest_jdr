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
	var map: Dictionary = md.create_complex_map("Démo 2.5D — objets 3D", "general", "local", 24, 16)
	if map.is_empty():
		return {}
	var map_id := str(map.get("id", ""))
	# Vrai terrain 3D simple (pas de fond peint déformé).
	map["backgroundImage"] = ""
	map["groundMode"] = "terrain3d"
	map["renderStyle"] = "2.5d"
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
			"elevation": 0.0,
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
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = w
	map["zoneH"] = h
	md.update_map(map)
	map = md.get_by_id(map_id)

	# --- Monde de démonstration : 3 zones adjacentes de tailles différentes ---
	var WorldZonesScript: GDScript = load("res://scripts/maps/world/world_zones.gd")
	var world_maps: Array = [map]
	var extra_specs := [
		{
			"title": "Place du Marché", "w": 14, "h": 12, "x": 25, "y": 0,
			"meshes": [
				{"name": "puits", "x": 4.0, "y": 5.0},
				{"name": "caisse", "x": 7.0, "y": 7.0},
				{"name": "arbre", "x": 9.5, "y": 3.0},
			],
		},
		{
			"title": "Forêt de l'Ouest", "w": 12, "h": 12, "x": 0, "y": 17,
			"meshes": [
				{"name": "arbre", "x": 3.0, "y": 3.0},
				{"name": "arbre_automne", "x": 8.0, "y": 6.0},
				{"name": "rocher", "x": 5.0, "y": 8.0},
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
		var sub_meshes: Array = []
		for m_variant in spec.get("meshes", []):
			var m: Dictionary = m_variant
			var path := str(by_name.get(str(m.get("name", "")).to_lower(), ""))
			if path.is_empty():
				continue
			sub_meshes.append({
				"id": "mesh-%s-%s" % [sub_id, str(m.get("name", ""))],
				"kind": "mesh",
				"x": float(m.get("x", 0.0)), "y": float(m.get("y", 0.0)),
				"w": 1.0, "h": 1.0,
				"asset": path,
				"elevation": 0.0,
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

	return {"map": map, "assets": assets, "cells": Vector2i(int(map.get("width", 24)), int(map.get("height", 16)))} 

## Les autoloads ne sont pas des identifiants globaux à la compilation en
## mode `--script` : les scripts qui référencent MapData sont chargés à
## l'exécution via `load()`.
