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

const MAP_BACKGROUND := "res://assets/maps/valbois_village.png"

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
	hint.text = "CARTE 2.5D — Biblio → 🧊 Objets 3D : cliquez un objet puis la carte. R pivote · molette = zoom (Ctrl) · Échap = menu."
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
	map["backgroundImage"] = MAP_BACKGROUND
	map["renderStyle"] = "dd2_hybrid"
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
		by_name[str(asset.get("name", "")).to_lower()] = str(asset.get("path", ""))

	var placements := [
		{"name": "maison", "x": 8.0, "y": 7.0, "rotation": 0.0, "scale": 1.0},
		{"name": "tour", "x": 13.0, "y": 6.0, "rotation": 90.0, "scale": 1.0},
		{"name": "arbre", "x": 5.5, "y": 10.0, "rotation": 0.0, "scale": 1.0},
		{"name": "rocher", "x": 15.0, "y": 10.0, "rotation": 45.0, "scale": 1.0},
		{"name": "puits", "x": 10.5, "y": 9.5, "rotation": 0.0, "scale": 1.0},
		{"name": "caisse", "x": 7.0, "y": 6.0, "rotation": 30.0, "scale": 1.0},
	]
	var meshes: Array = []
	for entry in placements:
		var asset_path := str(by_name.get(str(entry["name"]), ""))
		if asset_path.is_empty():
			continue
		meshes.append({
			"id": "mesh-demo-%s" % str(entry["name"]),
			"kind": "mesh",
			"x": float(entry["x"]), "y": float(entry["y"]),
			"w": 1.0, "h": 1.0,
			"asset": asset_path,
			"elevation": 0.0,
			"label": str(entry["name"]).capitalize(),
			"layer": 1,
			"display": {"rotation": float(entry["rotation"]), "scale": float(entry["scale"])},
		})
	map["meshes"] = meshes
	md.update_map(map)
	map = md.get_by_id(map_id)

	return {"map": map, "assets": assets, "cells": Vector2i(int(map.get("width", 24)), int(map.get("height", 16)))} 

## Les autoloads ne sont pas des identifiants globaux à la compilation en
## mode `--script` : les scripts qui référencent MapData sont chargés à
## l'exécution via `load()`.
