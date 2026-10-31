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

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	var demo := build_demo(md)
	if demo.is_empty():
		push_error("[CARTE 2.5D] Impossible de construire la carte de démonstration.")
		get_tree().quit(1)
		return

	DisplayServer.window_set_title("OpenQuest — Carte 2.5D (éditeur de démonstration)")
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
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
	md.update_map(map)
	map = md.get_by_id(map_id)

	return {"map": map, "assets": assets, "cells": Vector2i(int(map.get("width", 24)), int(map.get("height", 16)))} 

## Les autoloads ne sont pas des identifiants globaux à la compilation en
## mode `--script` : les scripts qui référencent MapData sont chargés à
## l'exécution via `load()`.
