extends Node

## Banc d'essai « Monde 2.5D en session » : construit le monde de démonstration
## (5 zones reliées), démarre une session et place le groupe dans le village.
##
## Lancer :
##   .\scripts\play-godot.ps1 res://scenes/debug/carte_25d_session_boot.tscn
##
## Dans la session : M = carte du monde, glisser un pion vers un bord pour
## changer de zone, figurines 3D des membres sans portrait.

func _ready() -> void:
	var md = get_tree().root.get_node("MapData")
	var gd = get_tree().root.get_node("GameData")
	var boot: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = boot.build_demo(md)
	if demo.is_empty():
		push_error("[MONDE 2.5D] Impossible de construire la démo.")
		get_tree().quit(1)
		return
	var village: Dictionary = demo.get("map", {})
	var village_id := str(village.get("id", ""))
	var ids: Array = []
	for map_variant in demo.get("world_maps", []):
		if map_variant is Dictionary:
			ids.append(str((map_variant as Dictionary).get("id", "")))
	if village_id.is_empty() or ids.size() < 2:
		push_error("[MONDE 2.5D] Monde invalide.")
		get_tree().quit(1)
		return

	var party := [
		{
			"id": "hero-aria", "name": "Aria", "race": "Humaine", "class": "Aventurière",
			"roster": "general", "hp": 12, "ac": 14, "isPlayer": true,
			"portrait": "", "image": "",
			"stats": {"str": 12, "dex": 14, "con": 12, "int": 10, "wis": 11, "cha": 13},
		},
		{
			"id": "hero-bran", "name": "Bran", "race": "Humain", "class": "Garde",
			"roster": "general", "hp": 15, "ac": 16, "isPlayer": true,
			"portrait": "", "image": "",
			"stats": {"str": 16, "dex": 10, "con": 14, "int": 9, "wis": 11, "cha": 10},
		},
		{
			"id": "hero-celia", "name": "Célia", "race": "Humaine", "class": "Marchande",
			"roster": "general", "hp": 10, "ac": 12, "isPlayer": true,
			"portrait": "", "image": "",
			"stats": {"str": 9, "dex": 13, "con": 10, "int": 14, "wis": 12, "cha": 16},
		},
	]

	# Copies de sécurité : create_new_game peut compléter ces tableaux avec le
	# scénario Valbois (personnage + cartes), on veut garder notre monde seul.
	var clean_ids: Array = ids.duplicate()
	var keep_names: Dictionary = {}
	for member_variant in party:
		keep_names[str((member_variant as Dictionary).get("name", ""))] = true
	gd.create_new_game("demo-valbois", "solo", "human", "oneshot", party.duplicate(true), ids.duplicate())
	gd.ensure_map_play_state()
	gd.active_game["currentMapId"] = village_id
	gd.active_game["mapNavigation"] = {
		"view": "local", "worldMapId": null, "localMapId": village_id, "worldCell": null,
	}
	gd.active_game["gmName"] = "MJ"
	gd.active_game["party"] = (gd.active_game.get("party", []) as Array).filter(
		func(member): return keep_names.has(str((member as Dictionary).get("name", "")))
	)
	gd.active_game["mapIds"] = clean_ids
	gd.save_active_game()
	gd.place_complex_member_token(village_id, 9.0, 7.5, "hero-aria")
	gd.place_complex_member_token(village_id, 8.2, 8.6, "hero-bran")
	gd.place_complex_member_token(village_id, 10.2, 8.2, "hero-celia")
	# Créatures : un gobelin en forêt, un squelette dans le donjon (figurines 3D).
	var forest_id := ""
	var dungeon_id := ""
	for map_variant in demo.get("world_maps", []):
		if not map_variant is Dictionary:
			continue
		var map_title := str((map_variant as Dictionary).get("title", ""))
		if map_title.contains("Forêt"):
			forest_id = str((map_variant as Dictionary).get("id", ""))
		elif map_title.contains("Donjon"):
			dungeon_id = str((map_variant as Dictionary).get("id", ""))
	_add_creature_token(gd, forest_id, "Gobelin", 7.0, 6.0)
	_add_creature_token(gd, dungeon_id, "Squelette", 5.0, 6.0)
	gd.save_map_play_and_sync()
	print("[MONDE 2.5D] Session monde prête : ", ids.size(), " zones, 3 héros dans le village.")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/session/session.tscn")

## Ajoute un token de créature (figurine 3D via le label) sur une carte.
func _add_creature_token(gd: Node, map_id: String, label: String, x: float, y: float) -> void:
	if map_id.is_empty():
		return
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	(entry["tokens"] as Array).append({
		"id": "tok-creature-%s" % label.to_lower(),
		"kind": "monster",
		"label": label,
		"x": x, "y": y,
		"hp": 7, "maxHp": 7,
	})
