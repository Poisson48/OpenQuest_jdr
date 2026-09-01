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

func create_new_game(scenario_id: String, mode: String, gm_type: String, quest_format: String, party_members: Array) -> Dictionary:
	var scenario := get_scenario_by_id(scenario_id)
	var new_game := {
		"id": generate_id("game"),
		"scenarioId": scenario_id,
		"scenarioTitle": scenario.get("title", "Aventure"),
		"questFormat": quest_format,
		"mode": mode, # "solo" ou "multi"
		"gmType": gm_type, # "ai" ou "human"
		"party": party_members,
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
	active_game["status"] = "playing" if state.get("status", "playing") == "playing" else state.get("status", "playing")
	save_active_game()

func clear_active_game() -> void:
	active_game = {}
	save_active_game()

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
