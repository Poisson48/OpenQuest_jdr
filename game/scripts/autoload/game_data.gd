extends Node

signal characters_updated
signal scenarios_updated
signal bots_updated
signal active_game_updated

const CHARACTERS_PATH = "user://characters.json"
const SCENARIOS_PATH = "user://scenarios.json"
const BOTS_PATH = "user://bots.json"
const ACTIVE_GAME_PATH = "user://active_game.json"

var characters: Array = []
var scenarios: Array = []
var bots: Array = []
var active_game: Dictionary = {}

func _ready() -> void:
	load_all_data()

# ==============================================================================
# CHARGEMENT & SAUVEGARDE
# ==============================================================================

func load_all_data() -> void:
	load_characters()
	load_scenarios()
	load_bots()
	load_active_game()

func save_all_data() -> void:
	save_characters()
	save_scenarios()
	save_bots()
	save_active_game()

func _load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var content := file.get_as_text()
	var json := JSON.new()
	var error := json.parse(content)
	if error != OK:
		push_warning("Erreur lecture JSON (%s) : %s" % [path, json.get_error_message()])
		return null
	return json.data

func _save_json_file(path: String, data: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Impossible d'écrire le fichier : %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true

# ==============================================================================
# PERSONNAGES
# ==============================================================================

func load_characters() -> void:
	var data = _load_json_file(CHARACTERS_PATH)
	if data is Array:
		characters = data
	else:
		characters = _create_seed_characters()
		save_characters()
	characters_updated.emit()

func save_characters() -> void:
	_save_json_file(CHARACTERS_PATH, characters)
	characters_updated.emit()

func get_characters(roster: String = "") -> Array:
	if roster.is_empty():
		return characters
	var result := []
	for c in characters:
		var r = c.get("roster", "general")
		if r == roster:
			result.append(c)
	return result

func get_character_by_id(id: String) -> Dictionary:
	for c in characters:
		if c.get("id") == id:
			return c
	return {}

func save_character(char_dict: Dictionary) -> void:
	if not char_dict.has("id") or char_dict["id"].is_empty():
		char_dict["id"] = generate_id("char")
	var index := -1
	for i in range(characters.size()):
		if characters[i].get("id") == char_dict["id"]:
			index = i
			break
	if index >= 0:
		characters[index] = char_dict
	else:
		characters.append(char_dict)
	save_characters()

func delete_character(id: String) -> void:
	for i in range(characters.size() - 1, -1, -1):
		if characters[i].get("id") == id:
			characters.remove_at(i)
	save_characters()

func create_blank_character(roster: String = "general") -> Dictionary:
	return {
		"id": generate_id("char"),
		"name": "Nouveau Héros",
		"race": "Humain" if roster == "general" else "Citadin",
		"class": "Guerrier" if roster == "general" else "Détective",
		"roster": roster,
		"stats": {
			"str": 10,
			"dex": 10,
			"con": 10,
			"int": 10,
			"wis": 10,
			"cha": 10
		},
		"hp": 10,
		"ac": 10,
		"backstory": ""
	}

func _create_seed_characters() -> Array:
	return [
		{
			"id": "char-aria",
			"name": "Aria Sombrelame",
			"race": "Elfe",
			"class": "Rôdeuse",
			"roster": "general",
			"stats": { "str": 12, "dex": 16, "con": 12, "int": 10, "wis": 14, "cha": 10 },
			"hp": 12,
			"ac": 14,
			"backstory": "Traqueuse émérite des Terres Sauvages."
		},
		{
			"id": "char-brom",
			"name": "Brom Poing-d'Acier",
			"race": "Nain",
			"class": "Guerrier",
			"roster": "general",
			"stats": { "str": 16, "dex": 10, "con": 16, "int": 8, "wis": 12, "cha": 8 },
			"hp": 15,
			"ac": 16,
			"backstory": "Vétéran des guerres souterraines de Karak."
		},
		{
			"id": "char-victor",
			"name": "Inspecteur Victor",
			"race": "Humain",
			"class": "Inspecteur",
			"roster": "investigation",
			"stats": { "str": 10, "dex": 12, "con": 10, "int": 16, "wis": 14, "cha": 12 },
			"hp": 10,
			"ac": 11,
			"backstory": "Esprit affûté ne laissant aucun détail au hasard."
		}
	]

# ==============================================================================
# SCENARIOS
# ==============================================================================

func load_scenarios() -> void:
	var data = _load_json_file(SCENARIOS_PATH)
	if data is Array and not data.is_empty():
		scenarios = data
	else:
		scenarios = _load_default_scenarios()
		save_scenarios()
	scenarios_updated.emit()

func save_scenarios() -> void:
	_save_json_file(SCENARIOS_PATH, scenarios)
	scenarios_updated.emit()

func get_scenarios(quest_format: String = "", roster: String = "") -> Array:
	var result := []
	for s in scenarios:
		if not quest_format.is_empty() and s.get("questFormat", "") != quest_format:
			continue
		if not roster.is_empty() and s.get("roster", "general") != roster:
			continue
		result.append(s)
	return result

func get_scenario_by_id(id: String) -> Dictionary:
	for s in scenarios:
		if s.get("id") == id:
			return s
	return {}

func save_scenario(scenario_dict: Dictionary) -> void:
	if not scenario_dict.has("id") or scenario_dict["id"].is_empty():
		scenario_dict["id"] = generate_id("scn")
	var index := -1
	for i in range(scenarios.size()):
		if scenarios[i].get("id") == scenario_dict["id"]:
			index = i
			break
	if index >= 0:
		scenarios[index] = scenario_dict
	else:
		scenarios.append(scenario_dict)
	save_scenarios()

func delete_scenario(id: String) -> void:
	for i in range(scenarios.size() - 1, -1, -1):
		if scenarios[i].get("id") == id:
			scenarios.remove_at(i)
	save_scenarios()

func _load_default_scenarios() -> Array:
	var list := []
	var dirs_to_check := ["res://data/scenarios/", "res://../data/scenarios/"]
	for dir_path in dirs_to_check:
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while not file_name.is_empty():
				if not dir.current_is_dir() and file_name.ends_with(".json"):
					var s_data = _load_json_file(dir_path + file_name)
					if s_data is Dictionary and s_data.has("id"):
						if not s_data.has("roster"):
							s_data["roster"] = "investigation" if file_name.begins_with("inv-") else "general"
						list.append(s_data)
				file_name = dir.get_next()
			if not list.is_empty():
				return list

	# Fallback si aucun fichier n'a pu être chargé
	return [
		{
			"id": "demo-kharak",
			"questFormat": "long",
			"roster": "general",
			"title": "Les Sables de Kharak",
			"synopsis": "Une caravane a disparu dans le désert de Kharak. Les aventuriers doivent traverser dunes et ruines oubliées.",
			"setting": "Désert brûlant, ruines antiques enfouies.",
			"scenes": [
				{ "title": "L'oasis de Selim", "content": "La dernière étape avant le désert profond. Les nomades parlent d'une cité engloutie." },
				{ "title": "La tempête de sable", "content": "Visibilité nulle. Le groupe doit se lier pour ne pas se perdre." },
				{ "title": "Les ruines de Zhar-Rim", "content": "Des colonnes de pierre émergent des sables. Un puits mène aux catacombes." }
			],
			"npcs": [
				{ "name": "Yasmina", "role": "Survivante", "description": "Marchande de la caravane." }
			]
		},
		{
			"id": "demo-crypte",
			"questFormat": "oneshot",
			"roster": "general",
			"title": "La Crypte des Oubliés",
			"synopsis": "Des bruits étranges résonnent sous le cimetière du village.",
			"setting": "Crypte humide et sombre, dalles usées.",
			"scenes": [
				{ "title": "L'entrée scellée", "content": "Une lourde porte de pierre aux symboles effacés." },
				{ "title": "La salle des sarcophages", "content": "Des murmures semblent s'échapper des tombes." }
			],
			"npcs": []
		}
	]

# ==============================================================================
# BOTS
# ==============================================================================

func load_bots() -> void:
	var data = _load_json_file(BOTS_PATH)
	if data is Array and not data.is_empty():
		bots = data
	else:
		bots = _load_default_bots()
		save_bots()
	bots_updated.emit()

func save_bots() -> void:
	_save_json_file(BOTS_PATH, bots)
	bots_updated.emit()

func get_bots() -> Array:
	return bots

func get_bot_by_id(id: String) -> Dictionary:
	for b in bots:
		if b.get("id") == id:
			return b
	return {}

func _load_default_bots() -> Array:
	var data = _load_json_file("res://data/bots/archetypes.json")
	if data is Array and not data.is_empty():
		return data
	data = _load_json_file("res://../data/bots/archetypes.json")
	if data is Array and not data.is_empty():
		return data
	return [
		{
			"id": "bot-kael",
			"name": "Kael",
			"race": "Nain",
			"class": "Guerrier",
			"personality": "cautious",
			"stats": { "str": 16, "dex": 10, "con": 14, "int": 8, "wis": 12, "cha": 10 },
			"hp": 14,
			"ac": 16,
			"traits": ["protecteur", "méfiant"]
		},
		{
			"id": "bot-lyra",
			"name": "Lyra",
			"race": "Elfe",
			"class": "Mage",
			"personality": "curious",
			"stats": { "str": 8, "dex": 14, "con": 10, "int": 16, "wis": 12, "cha": 10 },
			"hp": 8,
			"ac": 12,
			"traits": ["curieuse", "analytique"]
		}
	]

# ==============================================================================
# SESSION DE JEU ACTIVE
# ==============================================================================

func load_active_game() -> void:
	var data = _load_json_file(ACTIVE_GAME_PATH)
	if data is Dictionary and data.get("status", "") == "playing":
		active_game = data
	else:
		active_game = {}
	active_game_updated.emit()

func save_active_game(state: Dictionary = {}) -> void:
	if not state.is_empty():
		active_game = state
	if active_game.is_empty() or active_game.get("status") == "ended":
		if FileAccess.file_exists(ACTIVE_GAME_PATH):
			DirAccess.remove_absolute(ACTIVE_GAME_PATH)
	else:
		_save_json_file(ACTIVE_GAME_PATH, active_game)
	active_game_updated.emit()

func has_active_game() -> bool:
	return not active_game.is_empty() and active_game.get("status") == "playing"

func create_new_game(scenario_id: String, mode: String, gm_type: String, quest_format: String, party_members: Array, map_ids: Array = []) -> Dictionary:
	var scenario := get_scenario_by_id(scenario_id)
	var resolved_map_ids: Array = map_ids if not map_ids.is_empty() else MapData.get_map_ids_for_scenario(scenario_id, quest_format)
	resolved_map_ids = expand_map_ids_with_linked_locals(resolved_map_ids)
	var new_game := {
		"id": generate_id("game"),
		"scenarioId": scenario_id,
		"scenarioTitle": scenario.get("title", "Aventure"),
		"questFormat": quest_format,
		"mode": mode, # "solo" ou "multi"
		"gmType": gm_type, # "ai" ou "human"
		"party": party_members,
		"mapIds": resolved_map_ids,
		"mapPlayState": {},
		"mapNavigation": { "view": "world", "worldMapId": null, "localMapId": null, "worldCell": null },
		"currentSceneIndex": 0,
		"turnIndex": 0,
		"log": [],
		"status": "playing",
		"startedAt": Time.get_unix_time_from_system()
	}
	
	# Message d'accueil / introduction au journal
	var welcome_text := "Bienvenue dans l'aventure [b]%s[/b] !\n" % scenario.get("title", "Aventure")
	if not scenario.get("synopsis", "").is_empty():
		welcome_text += scenario.get("synopsis") + "\n\n"
	
	var scenes: Array = scenario.get("scenes", [])
	if not scenes.is_empty():
		welcome_text += "[b]Scène 1 : %s[/b]\n%s" % [scenes[0].get("title", ""), scenes[0].get("content", "")]
	
	new_game["log"].append({
		"author": "MJ" if gm_type == "human" else "MJ (IA)",
		"type": "gm",
		"text": welcome_text,
		"time": Time.get_time_string_from_system()
	})
	
	active_game = new_game
	ensure_map_play_state()
	init_all_world_map_fog()
	save_active_game()
	return active_game

func add_log_entry(author: String, text: String, type: String = "player") -> void:
	if active_game.is_empty():
		return
	var entry := {
		"author": author,
		"type": type,
		"text": text,
		"time": Time.get_time_string_from_system()
	}
	active_game["log"].append(entry)
	save_active_game()

func advance_scene() -> bool:
	if active_game.is_empty():
		return false
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	var scenes: Array = scenario.get("scenes", [])
	var cur: int = active_game.get("currentSceneIndex", 0)
	if cur + 1 < scenes.size():
		active_game["currentSceneIndex"] = cur + 1
		var scene = scenes[cur + 1]
		add_log_entry("MJ", "[b]Nouvelle Scène : %s[/b]\n%s" % [scene.get("title", ""), scene.get("content", "")], "gm")
		_reveal_world_on_scene_advance()
		save_active_game()
		return true
	else:
		add_log_entry("Système", "[b]Fin du scénario atteint ![/b]", "system")
		active_game["status"] = "completed"
		save_active_game()
		return false

func apply_server_state(state: Dictionary) -> void:
	active_game = state.duplicate(true)
	if not active_game.has("scenarioTitle") and active_game.has("scenarioId"):
		var scn := get_scenario_by_id(active_game["scenarioId"])
		active_game["scenarioTitle"] = scn.get("title", "Aventure")
	if not active_game.has("mapIds") or active_game["mapIds"].is_empty():
		var scn_id: String = active_game.get("scenarioId", "")
		var qf: String = active_game.get("questFormat", "oneshot")
		active_game["mapIds"] = expand_map_ids_with_linked_locals(MapData.get_map_ids_for_scenario(scn_id, qf))
	if not active_game.has("mapPlayState"):
		active_game["mapPlayState"] = {}
	if not active_game.has("mapNavigation"):
		active_game["mapNavigation"] = { "view": "world", "worldMapId": null, "localMapId": null, "worldCell": null }
	ensure_map_play_state()
	init_all_world_map_fog()
	active_game["status"] = "playing" if state.get("status", "playing") == "playing" else state.get("status", "playing")
	save_active_game()

func clear_active_game() -> void:
	active_game = {}
	save_active_game()

# ==============================================================================
# CARTES INTERACTIVES (port POC js/game.js + js/maps.js)
# ==============================================================================

func ensure_map_play_state() -> void:
	if active_game.is_empty():
		return
	if not active_game.has("mapPlayState") or typeof(active_game["mapPlayState"]) != TYPE_DICTIONARY:
		active_game["mapPlayState"] = {}
	if not active_game.has("mapIds") or typeof(active_game["mapIds"]) != TYPE_ARRAY:
		active_game["mapIds"] = []
	if not active_game.has("mapNavigation") or typeof(active_game["mapNavigation"]) != TYPE_DICTIONARY:
		active_game["mapNavigation"] = { "view": "world", "worldMapId": null, "localMapId": null, "worldCell": null }

func get_map_play_entry(map_id: String) -> Dictionary:
	ensure_map_play_state()
	var mps: Dictionary = active_game["mapPlayState"]
	if not mps.has(map_id):
		mps[map_id] = { "tokens": [], "explored": [], "exploreLevel": 0 }
	var entry: Dictionary = mps[map_id]
	if not entry.has("tokens") or typeof(entry["tokens"]) != TYPE_ARRAY:
		entry["tokens"] = []
	if not entry.has("explored") or typeof(entry["explored"]) != TYPE_ARRAY:
		entry["explored"] = []
	if not entry.has("exploreLevel"):
		entry["exploreLevel"] = 0
	return entry

func get_map_play_tokens(map_id: String) -> Array:
	return get_map_play_entry(map_id)["tokens"]

func get_explored_cells(map_id: String) -> Array:
	return get_map_play_entry(map_id)["explored"]

func cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

func reveal_cell(map_id: String, x: int, y: int) -> void:
	var entry := get_map_play_entry(map_id)
	var key := cell_key(x, y)
	if not entry["explored"].has(key):
		entry["explored"].append(key)

func reveal_radius(map_id: String, map_data: Dictionary, cx: int, cy: int, radius: int) -> void:
	var w: int = map_data.get("width", 0)
	var h: int = map_data.get("height", 0)
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if x < 0 or x >= w or y < 0 or y >= h:
				continue
			if abs(x - cx) + abs(y - cy) <= radius:
				reveal_cell(map_id, x, y)

func get_world_map_ids() -> Array:
	var result: Array = []
	for map_id in active_game.get("mapIds", []):
		var m := MapData.get_by_id(map_id)
		if not m.is_empty() and MapData.is_world_map(m):
			result.append(map_id)
	return result

func get_world_map_start_point(map_data: Dictionary) -> Vector2i:
	for mk in map_data.get("markers", []):
		var t: String = mk.get("type", "")
		if t == "party" or t == "camp":
			return Vector2i(mk.get("x", 0), mk.get("y", 0))
	for tok in get_map_play_tokens(map_data.get("id", "")):
		if tok.get("kind") == "member":
			return Vector2i(tok.get("x", 0), tok.get("y", 0))
	return Vector2i(map_data.get("width", 16) / 2, map_data.get("height", 12) / 2)

func init_world_map_fog(map_id: String) -> void:
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty() or not MapData.is_world_map(map_data):
		return
	var entry := get_map_play_entry(map_id)
	if not entry["explored"].is_empty():
		return
	var start := get_world_map_start_point(map_data)
	entry["exploreAnchor"] = { "x": start.x, "y": start.y }
	entry["exploreLevel"] = 0
	reveal_radius(map_id, map_data, start.x, start.y, 2)

func init_all_world_map_fog() -> void:
	for map_id in get_world_map_ids():
		init_world_map_fog(map_id)

func reveal_world_at(map_id: String, x: int, y: int, radius: int = 2) -> void:
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty() or not MapData.is_world_map(map_data):
		return
	var entry := get_map_play_entry(map_id)
	entry["exploreAnchor"] = { "x": x, "y": y }
	reveal_radius(map_id, map_data, x, y, radius)

func expand_map_ids_with_linked_locals(map_ids: Array) -> Array:
	var expanded: Array = []
	for id in map_ids:
		if not id.is_empty() and not expanded.has(id):
			expanded.append(id)
	for id in map_ids:
		var m := MapData.get_by_id(id)
		if not m.is_empty() and MapData.is_world_map(m):
			for linked in MapData.get_linked_local_map_ids(m):
				if not expanded.has(linked):
					expanded.append(linked)
	return expanded

func enter_local_map(world_map_id: String, x: int, y: int, target_map_id: String) -> void:
	if target_map_id.is_empty():
		return
	ensure_map_play_state()
	var ids: Array = active_game["mapIds"]
	if not ids.has(target_map_id):
		ids.append(target_map_id)
	active_game["mapNavigation"] = {
		"view": "local",
		"worldMapId": world_map_id,
		"localMapId": target_map_id,
		"worldCell": { "x": x, "y": y },
	}
	save_active_game()

func exit_to_world_map() -> void:
	ensure_map_play_state()
	var nav: Dictionary = active_game["mapNavigation"]
	nav["view"] = "world"
	nav["localMapId"] = null
	active_game["mapNavigation"] = nav
	save_active_game()

func remove_map_token_at(map_id: String, x: int, y: int) -> void:
	var entry := get_map_play_entry(map_id)
	entry["tokens"] = entry["tokens"].filter(func(t): return not (t.get("x") == x and t.get("y") == y))

func remove_member_tokens(map_id: String, member_id: String) -> void:
	var entry := get_map_play_entry(map_id)
	entry["tokens"] = entry["tokens"].filter(func(t): return t.get("memberId") != member_id)

func place_member_token(map_id: String, x: int, y: int, member_id: String) -> void:
	if member_id.is_empty():
		return
	remove_member_tokens(map_id, member_id)
	remove_map_token_at(map_id, x, y)
	var member := _find_party_member(member_id)
	if member.is_empty():
		return
	var tokens: Array = get_map_play_tokens(map_id)
	tokens.append({
		"id": generate_id("tok"),
		"x": x, "y": y,
		"kind": "member",
		"memberId": member_id,
		"label": member.get("name", "Héros"),
	})
	var map_data := MapData.get_by_id(map_id)
	if MapData.is_world_map(map_data):
		reveal_world_at(map_id, x, y, 2)
	save_active_game()

func place_marker_token(map_id: String, x: int, y: int, marker_type: String) -> void:
	if marker_type.is_empty():
		return
	remove_map_token_at(map_id, x, y)
	var tokens: Array = get_map_play_tokens(map_id)
	tokens.append({
		"id": generate_id("tok"),
		"x": x, "y": y,
		"kind": "marker",
		"markerType": marker_type,
		"label": "",
	})
	save_active_game()

func apply_map_play_action(map_id: String, x: int, y: int, tool: Dictionary) -> void:
	if active_game.is_empty() or active_game.get("status") == "completed":
		return
	var mode: String = tool.get("mode", "")
	if mode == "erase":
		remove_map_token_at(map_id, x, y)
	elif mode == "member":
		place_member_token(map_id, x, y, tool.get("memberId", ""))
	elif mode == "marker":
		place_marker_token(map_id, x, y, tool.get("markerType", ""))
	save_active_game()

func _find_party_member(member_id: String) -> Dictionary:
	for m in active_game.get("party", []):
		if m.get("id") == member_id:
			return m
	return {}

func _reveal_world_on_scene_advance() -> void:
	for map_id in get_world_map_ids():
		var map_data := MapData.get_by_id(map_id)
		if map_data.is_empty():
			continue
		var entry := get_map_play_entry(map_id)
		entry["exploreLevel"] = int(entry.get("exploreLevel", 0)) + 2
		var anchor: Dictionary = entry.get("exploreAnchor", {})
		if anchor.is_empty():
			var start := get_world_map_start_point(map_data)
			anchor = { "x": start.x, "y": start.y }
		var radius := 2 + int(entry["exploreLevel"]) / 2
		reveal_radius(map_id, map_data, int(anchor.get("x", 0)), int(anchor.get("y", 0)), radius)

func get_session_display_map(active_map_id: String) -> Dictionary:
	var active_map := MapData.get_by_id(active_map_id)
	if active_map.is_empty():
		return { "displayMap": {}, "navContext": {} }
	var nav: Dictionary = active_game.get("mapNavigation", {})
	if nav.get("view") == "local" and nav.get("worldMapId") == active_map_id:
		var local_map := MapData.get_by_id(nav.get("localMapId", ""))
		if not local_map.is_empty():
			return {
				"displayMap": local_map,
				"navContext": {
					"mode": "local",
					"worldMap": active_map,
					"worldCell": nav.get("worldCell", {}),
					"localMap": local_map,
				},
			}
	return { "displayMap": active_map, "navContext": {} }

# ==============================================================================
# MOTEUR DE DÉS (CONFORME AU POC JS)
# ==============================================================================

func roll_dice(formula: String) -> Dictionary:
	var cleaned := formula.strip_edges().to_lower().replace(" ", "")
	var regex := RegEx.new()
	regex.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var match_res := regex.search(cleaned)
	
	if not match_res:
		return { "error": "Formule invalide. Exemples : 1d20, 2d6+3, 1d8-1" }
	
	var count := match_res.get_string(1).to_int()
	var sides := match_res.get_string(2).to_int()
	var mod_str := match_res.get_string(3)
	var modifier := mod_str.to_int() if not mod_str.is_empty() else 0
	
	if count < 1 or count > 100 or sides < 2 or sides > 1000:
		return { "error": "Valeurs hors limites (max 100d1000)." }
	
	var rolls: Array = []
	var sum := 0
	for i in range(count):
		var val := randi() % sides + 1
		rolls.append(val)
		sum += val
	
	var total := sum + modifier
	var mod_repr := ""
	if modifier > 0:
		mod_repr = "+%d" % modifier
	elif modifier < 0:
		mod_repr = "%d" % modifier
		
	var norm_formula := "%dd%d%s" % [count, sides, mod_repr]
	
	return {
		"formula": norm_formula,
		"rolls": rolls,
		"modifier": modifier,
		"total": total
	}

func format_dice_result(res: Dictionary) -> String:
	if res.has("error"):
		return str(res["error"])
	var text := "🎲 [b]%d[/b] (%s)" % [res.get("total", 0), res.get("formula", "")]
	var rolls: Array = res.get("rolls", [])
	var modifier: int = res.get("modifier", 0)
	if rolls.size() > 1:
		text += " — dés : " + ", ".join(rolls.map(func(v): return str(v)))
		if modifier != 0:
			text += " %s%d" % ["+" if modifier > 0 else "", modifier]
	elif modifier != 0:
		text += " — %d %s%d" % [rolls[0], "+" if modifier > 0 else "", modifier]
	elif rolls.size() == 1:
		text += " — dé : %d" % rolls[0]
	return text

# ==============================================================================
# UTILITAIRES
# ==============================================================================

func generate_id(prefix: String) -> String:
	return "%s-%d-%s" % [prefix, Time.get_unix_time_from_system(), str(randi() % 90000 + 10000)]
