extends Node

signal characters_updated
signal scenarios_updated
signal bots_updated
signal active_game_updated

const CHARACTERS_PATH = "user://characters.json"
const SCENARIOS_PATH = "user://scenarios.json"
const SCENARIOS_REMOVED_PATH = "user://scenarios_removed.json"
const BOTS_PATH = "user://bots.json"
const BOTS_REMOVED_PATH = "user://bots_removed.json"
const ACTIVE_GAME_PATH = "user://active_game.json"
const SAVED_GAMES_PATH = "user://saved_games.json"

const QuestNavigation = preload("res://scripts/quest_navigation.gd")

var characters: Array = []
var scenarios: Array = []
var removed_scenario_ids: Array = []
var bots: Array = []
var removed_bot_ids: Array = []
var saved_games: Array = []
var active_game: Dictionary = {}
var editor_scenario_id: String = ""

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

func is_character_valid_for_format(char: Dictionary, quest_format: String) -> bool:
	if char.is_empty():
		return false
	var is_inv := quest_format == "investigation"
	return (char.get("roster", "general") == "investigation") == is_inv

func is_bot_valid_for_format(bot: Dictionary, quest_format: String) -> bool:
	if bot.is_empty():
		return false
	return (quest_format == "investigation") == is_investigation_bot(bot)

func get_characters_for_quest_format(quest_format: String) -> Array:
	var result: Array = []
	for c in characters:
		if is_character_valid_for_format(c, quest_format):
			result.append(c)
	return result

func is_scenario_valid_for_format(scenario: Dictionary, quest_format: String) -> bool:
	if scenario.is_empty():
		return false
	if quest_format == "investigation":
		return scenario.get("roster", "general") == "investigation"
	if scenario.get("roster", "general") == "investigation":
		return false
	if quest_format == "adventure":
		return true
	var qf: String = scenario.get("questFormat", "oneshot")
	if quest_format == "long":
		return qf == "long"
	if quest_format == "oneshot":
		return qf != "long"
	return true

func get_scenarios_for_quest_format(quest_format: String) -> Array:
	var result: Array = []
	for s in scenarios:
		var scn_id: String = s.get("id", "")
		if scn_id.is_empty() or removed_scenario_ids.has(scn_id):
			continue
		if is_scenario_valid_for_format(s, quest_format):
			result.append(s)
	return result

func get_character_by_id(id: String) -> Dictionary:
	for c in characters:
		if c.get("id") == id:
			return c
	return {}

func save_character(char_dict: Dictionary) -> void:
	var data := normalize_character(char_dict)
	if not data.has("id") or str(data["id"]).is_empty():
		data["id"] = generate_id("char")
	var index := -1
	for i in range(characters.size()):
		if characters[i].get("id") == data["id"]:
			index = i
			break
	if index >= 0:
		characters[index] = data
	else:
		characters.append(data)
	save_characters()

func delete_character(id: String) -> void:
	for i in range(characters.size() - 1, -1, -1):
		if characters[i].get("id") == id:
			characters.remove_at(i)
	save_characters()

func get_ruleset_tier(entity: Dictionary) -> String:
	var tier := str(entity.get("rulesetTier", "medium"))
	if tier in ["simple", "medium", "complete"]:
		return tier
	return "medium"

func stat_modifier(stat_value: int) -> int:
	return int(floor((stat_value - 10) / 2.0))

func format_modifier(mod: int) -> String:
	if mod >= 0:
		return "+%d" % mod
	return str(mod)

func format_character_summary(entity: Dictionary) -> String:
	var tier := get_ruleset_tier(entity)
	var name_val := str(entity.get("name", "?"))
	var race_val := str(entity.get("race", "?"))
	var class_val := str(entity.get("class", "?"))
	var hp_val := int(entity.get("hp", 10))

	if tier == "simple":
		var simple: Dictionary = entity.get("simpleStats", {})
		var trait_val := str(entity.get("trait", "")).strip_edges()
		var trait_part := " · « %s »" % trait_val if not trait_val.is_empty() else ""
		return "%s — %s %s | PV %d | FOR %d RUSE %d ROB %d CHA %d%s" % [
			name_val, race_val, class_val, hp_val,
			int(simple.get("force", 10)), int(simple.get("ruse", 10)),
			int(simple.get("robustesse", 10)), int(simple.get("charisme", 10)),
			trait_part,
		]

	if tier == "complete":
		var stats: Dictionary = entity.get("stats", {})
		var level_val := int(entity.get("level", 1))
		var align_val := str(entity.get("alignment", "")).strip_edges()
		var align_part := " · %s" % align_val if not align_val.is_empty() else ""
		var spell_part := " · ✦ sorts" if entity.get("spellcasting", false) else ""
		return "%s — %s %s niv.%d | PV %d CA %d | FOR %s DEX %s CON %s%s%s" % [
			name_val, race_val, class_val, level_val, hp_val, int(entity.get("ac", 10)),
			format_modifier(stat_modifier(int(stats.get("str", 10)))),
			format_modifier(stat_modifier(int(stats.get("dex", 10)))),
			format_modifier(stat_modifier(int(stats.get("con", 10)))),
			align_part, spell_part,
		]

	var stats: Dictionary = entity.get("stats", {})
	var perso := str(entity.get("personality", "")).strip_edges()
	var perso_part := " · %s" % perso if not perso.is_empty() else ""
	return "%s — %s %s | PV %d CA %d | FOR %d DEX %d CON %d INT %d SAG %d CHA %d%s" % [
		name_val, race_val, class_val, hp_val, int(entity.get("ac", 10)),
		int(stats.get("str", 10)), int(stats.get("dex", 10)), int(stats.get("con", 10)),
		int(stats.get("int", 10)), int(stats.get("wis", 10)), int(stats.get("cha", 10)),
		perso_part,
	]

func normalize_character(entity: Dictionary) -> Dictionary:
	var normalized: Dictionary = entity.duplicate(true)
	if not normalized.has("rulesetTier"):
		normalized["rulesetTier"] = "medium"
	var tier := get_ruleset_tier(normalized)
	if tier == "simple":
		if not normalized.has("simpleStats"):
			normalized["simpleStats"] = {
				"force": 10, "ruse": 10, "robustesse": 10, "charisme": 10,
			}
		if not normalized.has("trait"):
			normalized["trait"] = ""
	else:
		if not normalized.has("stats"):
			normalized["stats"] = {
				"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10,
			}
		if not normalized.has("ac"):
			normalized["ac"] = 10
		if tier == "medium":
			if not normalized.has("skills"):
				normalized["skills"] = ""
			if not normalized.has("personality"):
				normalized["personality"] = ""
		elif tier == "complete":
			if not normalized.has("level"):
				normalized["level"] = 1
			if not normalized.has("alignment"):
				normalized["alignment"] = ""
			if not normalized.has("proficiencies"):
				normalized["proficiencies"] = ""
			if not normalized.has("equipment"):
				normalized["equipment"] = ""
			if not normalized.has("ideals"):
				normalized["ideals"] = ""
			if not normalized.has("bonds"):
				normalized["bonds"] = ""
			if not normalized.has("flaws"):
				normalized["flaws"] = ""
			if not normalized.has("spellcasting"):
				normalized["spellcasting"] = false
			if not normalized.has("skills"):
				normalized["skills"] = ""
			if not normalized.has("personality"):
				normalized["personality"] = ""
	if not normalized.has("backstory"):
		normalized["backstory"] = ""
	if not normalized.has("hp"):
		normalized["hp"] = 10
	return normalized

func create_blank_character(
		roster: String = "general",
		tier: String = "medium",
		as_bot: bool = false,
	) -> Dictionary:
	var resolved_tier := tier if tier in ["simple", "medium", "complete"] else "medium"
	var blank := {
		"id": generate_id("bot" if as_bot else "char"),
		"name": "Nouveau Bot" if as_bot else "Nouveau Héros",
		"race": "Humain" if roster == "general" else "Citadin",
		"class": "Guerrier" if roster == "general" else "Détective",
		"roster": roster,
		"rulesetTier": resolved_tier,
		"hp": 10,
		"backstory": "",
	}
	if resolved_tier == "simple":
		blank["simpleStats"] = { "force": 12, "ruse": 10, "robustesse": 10, "charisme": 10 }
		blank["trait"] = ""
	else:
		blank["stats"] = {
			"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10,
		}
		blank["ac"] = 10
		blank["skills"] = ""
		blank["personality"] = "diplomatic" if as_bot else ""
		if resolved_tier == "complete":
			blank["level"] = 1
			blank["alignment"] = ""
			blank["proficiencies"] = ""
			blank["equipment"] = ""
			blank["ideals"] = ""
			blank["bonds"] = ""
			blank["flaws"] = ""
			blank["spellcasting"] = false
	if as_bot:
		blank["traits"] = []
	return normalize_character(blank)

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

func reload_builtin_scenarios() -> void:
	scenarios = _load_default_scenarios()
	for i in range(scenarios.size()):
		if scenarios[i] is Dictionary:
			scenarios[i] = QuestNavigation.normalize_scenario(scenarios[i])
	save_scenarios()
	scenarios_updated.emit()

func load_scenarios() -> void:
	var data = _load_json_file(SCENARIOS_PATH)
	if data is Array and not data.is_empty():
		scenarios = data
	else:
		scenarios = _load_default_scenarios()
		save_scenarios()
	for i in range(scenarios.size()):
		if scenarios[i] is Dictionary:
			scenarios[i] = QuestNavigation.normalize_scenario(scenarios[i])
	_load_removed_scenarios()
	scenarios_updated.emit()

func _load_removed_scenarios() -> void:
	var data = _load_json_file(SCENARIOS_REMOVED_PATH)
	if data is Array:
		removed_scenario_ids = data
	else:
		removed_scenario_ids = []

func _save_removed_scenarios() -> void:
	_save_json_file(SCENARIOS_REMOVED_PATH, removed_scenario_ids)

func save_scenarios() -> void:
	_save_json_file(SCENARIOS_PATH, scenarios)
	scenarios_updated.emit()

func get_scenarios(quest_format: String = "", roster: String = "") -> Array:
	var result := []
	for s in scenarios:
		var scn_id: String = s.get("id", "")
		if scn_id.is_empty() or removed_scenario_ids.has(scn_id):
			continue
		if not quest_format.is_empty() and s.get("questFormat", "") != quest_format:
			continue
		if not roster.is_empty() and s.get("roster", "general") != roster:
			continue
		result.append(s)
	return result

func get_scenario_by_id(id: String) -> Dictionary:
	for s in scenarios:
		if s.get("id") == id:
			return QuestNavigation.normalize_scenario(s)
	return {}

func sync_game_scenario_metadata(game: Dictionary) -> Dictionary:
	if game.is_empty():
		return game
	var scn_id: String = game.get("scenarioId", "")
	if scn_id.is_empty():
		return game
	var scn := get_scenario_by_id(scn_id)
	if not scn.is_empty():
		game["scenarioTitle"] = scn.get("title", "Aventure")
	return game

func sync_active_game_scenario_metadata() -> void:
	if active_game.is_empty():
		return
	active_game = sync_game_scenario_metadata(active_game)
	_ensure_navigation_state()

func get_scenario_display_title(scenario_id: String = "") -> String:
	var scn_id := scenario_id
	if scn_id.is_empty() and not active_game.is_empty():
		scn_id = active_game.get("scenarioId", "")
	var scn := get_scenario_by_id(scn_id)
	if not scn.is_empty():
		return scn.get("title", "Aventure")
	if not active_game.is_empty():
		return active_game.get("scenarioTitle", "Aventure")
	return "Aventure"

func get_quest_format_for_scenario(scenario_id: String) -> String:
	var scn := get_scenario_by_id(scenario_id)
	if scn.is_empty():
		return "oneshot"
	if scn.get("roster", "general") == "investigation":
		return "investigation"
	if scn.get("questFormat", "oneshot") == "long":
		return "long"
	return "oneshot"

func go_to_game_setup(quest_format: String = "", scenario_id: String = "") -> void:
	var fmt := quest_format
	if fmt.is_empty() and not scenario_id.is_empty():
		fmt = get_quest_format_for_scenario(scenario_id)
	if not fmt.is_empty():
		get_tree().set_meta("preselected_quest_format", fmt)
	if not scenario_id.is_empty():
		get_tree().set_meta("preselected_scenario_id", scenario_id)
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")

func go_to_character_editor(roster: String = "", entity_type: String = "") -> void:
	if roster == "general" or roster == "investigation":
		get_tree().set_meta("preselected_roster", roster)
	if entity_type == "bot" or entity_type == "player":
		get_tree().set_meta("preselected_entity_type", entity_type)
	get_tree().change_scene_to_file("res://scenes/character_editor.tscn")

func go_to_scenario_list(mode: String = "") -> void:
	if not mode.is_empty():
		get_tree().set_meta("preselected_scenario_mode", mode)
	get_tree().change_scene_to_file("res://scenes/scenario_list.tscn")

func go_to_scenario_editor(scenario_id: String = "", roster: String = "", quest_format: String = "") -> void:
	editor_scenario_id = scenario_id
	if not roster.is_empty():
		get_tree().set_meta("preselected_scenario_roster", roster)
	if not quest_format.is_empty():
		get_tree().set_meta("preselected_quest_format", quest_format)
	get_tree().change_scene_to_file("res://scenes/scenario_editor.tscn")

func create_blank_scenario(roster: String = "general", quest_format: String = "oneshot") -> Dictionary:
	var start_id := "scene-debut"
	var blank := {
		"id": generate_id("scn"),
		"title": "Nouveau scénario",
		"synopsis": "",
		"setting": "",
		"questFormat": quest_format,
		"roster": roster,
		"startSceneId": start_id,
		"scenes": [{
			"id": start_id,
			"title": "Scène de départ",
			"content": "Décrivez le point d'entrée de l'aventure...",
			"tags": ["debut"],
			"transitions": [],
			"graphPos": { "x": 48, "y": 48 },
		}],
		"npcs": [],
	}
	if roster == "investigation":
		blank["mystery"] = "Quelle est l'énigme centrale ?"
	return QuestNavigation.normalize_scenario(blank)

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

func delete_scenario(id: String) -> bool:
	if id.is_empty() or removed_scenario_ids.has(id):
		return false
	for i in range(scenarios.size() - 1, -1, -1):
		if scenarios[i].get("id") == id:
			scenarios.remove_at(i)
			save_scenarios()
			break
	removed_scenario_ids.append(id)
	_save_removed_scenarios()
	scenarios_updated.emit()
	return true

func get_scenario_mode_label(scenario: Dictionary) -> String:
	if scenario.get("roster", "general") == "investigation":
		return "investigation"
	if scenario.get("questFormat", "oneshot") == "long":
		return "long"
	return "oneshot"

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
	_load_removed_bots()
	bots_updated.emit()

func _load_removed_bots() -> void:
	var data = _load_json_file(BOTS_REMOVED_PATH)
	if data is Array:
		removed_bot_ids = data
	else:
		removed_bot_ids = []

func _save_removed_bots() -> void:
	_save_json_file(BOTS_REMOVED_PATH, removed_bot_ids)

func save_bots() -> void:
	_save_json_file(BOTS_PATH, bots)
	bots_updated.emit()

func get_bots() -> Array:
	var result: Array = []
	for b in bots:
		var bot_id: String = b.get("id", "")
		if not bot_id.is_empty() and not removed_bot_ids.has(bot_id):
			result.append(b)
	for b in _get_builtin_investigation_bots():
		var bot_id: String = b.get("id", "")
		if not bot_id.is_empty() and not removed_bot_ids.has(bot_id):
			result.append(b)
	return result

func save_bot(bot_dict: Dictionary) -> void:
	var data := normalize_character(bot_dict)
	if not data.has("id") or str(data["id"]).is_empty():
		data["id"] = generate_id("bot")
	if not data.has("traits") or typeof(data["traits"]) != TYPE_ARRAY:
		data["traits"] = []
	var index := -1
	for i in range(bots.size()):
		if bots[i].get("id") == data["id"]:
			index = i
			break
	if index >= 0:
		bots[index] = data
	else:
		bots.append(data)
	save_bots()

func get_editable_bots(roster: String = "") -> Array:
	var result: Array = []
	for b in bots:
		var bot_id: String = b.get("id", "")
		if bot_id.is_empty() or removed_bot_ids.has(bot_id):
			continue
		if not roster.is_empty() and b.get("roster", "general") != roster:
			continue
		result.append(b)
	return result

func is_editable_bot(id: String) -> bool:
	for b in bots:
		if b.get("id") == id:
			return true
	return false

func get_bot_from_storage(id: String) -> Dictionary:
	for b in bots:
		if b.get("id") == id:
			return b
	return {}

func delete_bot(id: String) -> bool:
	if id.is_empty() or removed_bot_ids.has(id):
		return false
	for i in range(bots.size() - 1, -1, -1):
		if bots[i].get("id") == id:
			bots.remove_at(i)
			save_bots()
			break
	removed_bot_ids.append(id)
	_save_removed_bots()
	bots_updated.emit()
	return true

func is_investigation_bot(bot: Dictionary) -> bool:
	var bot_id: String = bot.get("id", "")
	return bot.get("roster", "") == "investigation" or bot_id.begins_with("bot-inv")

func get_bots_for_quest_format(quest_format: String) -> Array:
	var result: Array = []
	for b in get_bots():
		if is_bot_valid_for_format(b, quest_format):
			result.append(b)
	return result

func get_bot_by_id(id: String) -> Dictionary:
	for b in get_bots():
		if b.get("id") == id:
			return b
	return {}

func _get_builtin_investigation_bots() -> Array:
	return [
		{
			"id": "bot-inv-elise",
			"name": "Élise",
			"race": "Humaine",
			"class": "Inspectrice",
			"personality": "diplomatic",
			"roster": "investigation",
			"stats": { "str": 10, "dex": 12, "con": 10, "int": 16, "wis": 14, "cha": 12 },
			"hp": 10,
			"ac": 11,
			"traits": ["méthodique", "perspicace"]
		},
		{
			"id": "bot-inv-noah",
			"name": "Noah",
			"race": "Nain",
			"class": "Expert légiste",
			"personality": "curious",
			"roster": "investigation",
			"stats": { "str": 12, "dex": 10, "con": 14, "int": 16, "wis": 12, "cha": 8 },
			"hp": 12,
			"ac": 12,
			"traits": ["rigoureux", "patient"]
		},
		{
			"id": "bot-inv-jade",
			"name": "Jade",
			"race": "Tieffeline",
			"class": "Interrogatrice",
			"personality": "bold",
			"roster": "investigation",
			"stats": { "str": 8, "dex": 14, "con": 10, "int": 14, "wis": 12, "cha": 16 },
			"hp": 9,
			"ac": 12,
			"traits": ["charismatique", "tenace"]
		},
		{
			"id": "bot-inv-oscar",
			"name": "Oscar",
			"race": "Humain",
			"class": "Profiler",
			"personality": "mystic",
			"roster": "investigation",
			"stats": { "str": 10, "dex": 12, "con": 10, "int": 16, "wis": 16, "cha": 10 },
			"hp": 10,
			"ac": 11,
			"traits": ["analytique", "discret"]
		},
		{
			"id": "bot-inv-luna",
			"name": "Luna",
			"race": "Elfe",
			"class": "Photographe de scène",
			"personality": "cheerful",
			"roster": "investigation",
			"stats": { "str": 8, "dex": 16, "con": 10, "int": 12, "wis": 14, "cha": 12 },
			"hp": 9,
			"ac": 13,
			"traits": ["observatrice", "réactive"]
		},
	]

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
# SESSION DE JEU ACTIVE (registre multi-parties)
# ==============================================================================

func load_active_game() -> void:
	_migrate_legacy_active_game()
	var data = _load_json_file(SAVED_GAMES_PATH)
	if data is Array:
		saved_games = _normalize_saved_games_list(data)
	else:
		saved_games = []
	active_game = {}
	active_game_updated.emit()

func _migrate_legacy_active_game() -> void:
	if not FileAccess.file_exists(ACTIVE_GAME_PATH):
		return
	var legacy = _load_json_file(ACTIVE_GAME_PATH)
	if legacy is Dictionary and legacy.get("status", "") == "playing":
		if not legacy.has("id") or str(legacy["id"]).is_empty():
			legacy["id"] = generate_id("game")
		_upsert_saved_game_entry(legacy, false)
	DirAccess.remove_absolute(ACTIVE_GAME_PATH)

func _normalize_saved_games_list(games: Array) -> Array:
	var result: Array = []
	for g in games:
		if g is Dictionary and g.get("status", "") == "playing":
			result.append(g)
	return result

func _persist_saved_games() -> void:
	_save_json_file(SAVED_GAMES_PATH, saved_games)

func _upsert_saved_game_entry(game: Dictionary, emit_signal: bool = true) -> void:
	var game_id: String = game.get("id", "")
	if game_id.is_empty():
		return
	for i in range(saved_games.size()):
		if saved_games[i].get("id") == game_id:
			saved_games[i] = game
			_persist_saved_games()
			if emit_signal:
				active_game_updated.emit()
			return
	saved_games.append(game)
	_persist_saved_games()
	if emit_signal:
		active_game_updated.emit()

func save_active_game(state: Dictionary = {}) -> void:
	if not state.is_empty():
		active_game = state
	if active_game.is_empty():
		active_game_updated.emit()
		return
	var status: String = active_game.get("status", "playing")
	if status == "ended":
		delete_game(active_game.get("id", ""))
		return
	if status == "playing" or status == "completed":
		sync_active_game_scenario_metadata()
		active_game["updatedAt"] = Time.get_unix_time_from_system()
		_upsert_saved_game_entry(active_game.duplicate(true))
	else:
		active_game_updated.emit()

func has_active_game() -> bool:
	return not active_game.is_empty() and active_game.get("status") == "playing"

func get_playing_games() -> Array:
	var result: Array = []
	for g in saved_games:
		if g.get("status", "") == "playing":
			result.append(g)
	return result

func load_game_by_id(game_id: String) -> bool:
	for g in saved_games:
		if g.get("id") == game_id:
			active_game = sync_game_scenario_metadata(g.duplicate(true))
			_ensure_navigation_state()
			ensure_map_play_state()
			init_all_world_map_fog()
			_ensure_party_tokens_on_world_maps()
			active_game_updated.emit()
			return true
	return false

func delete_game(game_id: String) -> void:
	if game_id.is_empty():
		return
	for i in range(saved_games.size() - 1, -1, -1):
		if saved_games[i].get("id") == game_id:
			saved_games.remove_at(i)
	_persist_saved_games()
	if active_game.get("id") == game_id:
		active_game = {}
	active_game_updated.emit()

func clear_active_game() -> void:
	delete_game(active_game.get("id", ""))

func clear_all_saved_games() -> void:
	saved_games.clear()
	active_game = {}
	_persist_saved_games()
	if FileAccess.file_exists(ACTIVE_GAME_PATH):
		DirAccess.remove_absolute(ACTIVE_GAME_PATH)
	active_game_updated.emit()

func get_game_party_summary(game: Dictionary) -> String:
	var party: Array = game.get("party", [])
	if party.is_empty():
		return "Groupe vide"
	var names: Array = []
	for m in party:
		names.append(m.get("name", "?"))
	if names.size() <= 3:
		return ", ".join(names)
	return "%s + %d autres" % [names[0], names.size() - 1]

func create_new_game(scenario_id: String, mode: String, gm_type: String, quest_format: String, party_members: Array, map_ids: Array = []) -> Dictionary:
	var scenario := get_scenario_by_id(scenario_id)
	var resolved_map_ids: Array = map_ids if not map_ids.is_empty() else MapData.get_map_ids_for_scenario(scenario_id, quest_format)
	resolved_map_ids = expand_map_ids_with_linked_locals(resolved_map_ids)
	var start_scene_id := str(scenario.get("startSceneId", ""))
	if start_scene_id.is_empty():
		start_scene_id = QuestNavigation.get_scene_id_at_index(scenario, 0)
	var start_scene := QuestNavigation.get_scene_by_id(scenario, start_scene_id)
	var start_index := QuestNavigation.get_scene_index(scenario, start_scene_id)
	var now := Time.get_unix_time_from_system()
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
		"currentSceneId": start_scene_id,
		"currentSceneIndex": maxi(0, start_index),
		"visitedSceneIds": [start_scene_id] if not start_scene_id.is_empty() else [],
		"sceneHistory": [{
			"sceneId": start_scene_id,
			"enteredAt": now,
			"fromSceneId": "",
			"reason": "Début de l'aventure",
		}] if not start_scene_id.is_empty() else [],
		"turnIndex": 0,
		"waitingForGm": false,
		"gmName": "MJ",
		"log": [],
		"status": "playing",
		"startedAt": now
	}
	
	# Message d'accueil / introduction au journal
	var welcome_text := "Bienvenue dans l'aventure [b]%s[/b] !\n" % scenario.get("title", "Aventure")
	if not scenario.get("synopsis", "").is_empty():
		welcome_text += scenario.get("synopsis") + "\n\n"
	
	if not start_scene.is_empty():
		welcome_text += "[b]%s[/b]\n%s" % [start_scene.get("title", ""), start_scene.get("content", "")]
	
	new_game["log"].append({
		"author": "MJ" if gm_type == "human" else "MJ (IA)",
		"type": "gm",
		"text": welcome_text,
		"time": Time.get_time_string_from_system()
	})
	
	active_game = new_game
	ensure_map_play_state()
	init_all_world_map_fog()
	init_investigation_clues_for_game()
	_ensure_party_tokens_on_world_maps()
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

func get_playable_members() -> Array:
	if active_game.is_empty():
		return []
	var party: Array = active_game.get("party", [])
	var humans: Array = []
	for member in party:
		if member.get("isHuman", false):
			humans.append(member)
	if humans.is_empty():
		return party.duplicate()
	return humans

func get_active_member() -> Dictionary:
	var party: Array = active_game.get("party", [])
	if party.is_empty():
		return {}
	var playable := get_playable_members()
	var mode: String = active_game.get("mode", "solo")
	if mode == "solo":
		for member in playable:
			if member.get("isHuman", false):
				return member
		if not playable.is_empty():
			return playable[0]
		return party[0]
	var turn_idx: int = int(active_game.get("turnIndex", 0))
	if playable.is_empty():
		return party[turn_idx % party.size()]
	return playable[turn_idx % playable.size()]

func next_turn() -> void:
	if active_game.is_empty():
		return
	var playable := get_playable_members()
	if playable.size() <= 1:
		return
	var idx: int = int(active_game.get("turnIndex", 0))
	active_game["turnIndex"] = (idx + 1) % playable.size()
	save_active_game()

func set_waiting_for_gm(waiting: bool) -> void:
	if active_game.is_empty():
		return
	active_game["waitingForGm"] = waiting
	save_active_game()

func is_waiting_for_gm() -> bool:
	if active_game.is_empty():
		return false
	return bool(active_game.get("waitingForGm", false))

func get_scenario_npcs() -> Array:
	if active_game.is_empty():
		return []
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	return scenario.get("npcs", [])

func can_member_act(client_id: String) -> bool:
	if active_game.is_empty() or active_game.get("status") == "completed":
		return false
	if is_waiting_for_gm():
		return false
	if active_game.get("gmType", "ai") == "ai":
		return true
	var actor := get_active_member()
	if actor.is_empty():
		return true
	var actor_client: String = str(actor.get("clientId", ""))
	if actor_client.is_empty():
		return client_id.is_empty()
	return actor_client == client_id

func get_gm_display_name() -> String:
	if active_game.is_empty():
		return "MJ"
	return str(active_game.get("gmName", "MJ"))

func advance_scene() -> bool:
	if active_game.is_empty():
		return false
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	var current_id := QuestNavigation.resolve_current_scene_id(active_game, scenario)
	var transitions := QuestNavigation.get_available_transitions(scenario, current_id)
	var default_transition := QuestNavigation.get_default_transition(transitions)
	if not default_transition.is_empty():
		return go_to_scene(str(default_transition.get("to", "")), str(default_transition.get("label", "Suite de l'aventure")))
	var cur: int = int(active_game.get("currentSceneIndex", 0))
	var scenes: Array = scenario.get("scenes", [])
	if cur + 1 < scenes.size():
		var next_id := QuestNavigation.get_scene_id_at_index(scenario, cur + 1)
		return go_to_scene(next_id, "Scène suivante")
	return complete_scenario()

func go_to_scene(scene_id: String, reason: String = "") -> bool:
	if active_game.is_empty() or active_game.get("status") == "completed":
		return false
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	var target_id := str(scene_id).strip_edges()
	var target_scene := QuestNavigation.get_scene_by_id(scenario, target_id)
	if target_scene.is_empty():
		return false
	var current_id := QuestNavigation.resolve_current_scene_id(active_game, scenario)
	if current_id == target_id:
		return false

	_close_current_scene_history_entry()

	active_game["currentSceneId"] = target_id
	active_game["currentSceneIndex"] = maxi(0, QuestNavigation.get_scene_index(scenario, target_id))
	active_game["waitingForGm"] = false

	var visited: Array = active_game.get("visitedSceneIds", [])
	if typeof(visited) != TYPE_ARRAY:
		visited = []
	if not visited.has(target_id):
		visited.append(target_id)
	active_game["visitedSceneIds"] = visited

	var history: Array = active_game.get("sceneHistory", [])
	if typeof(history) != TYPE_ARRAY:
		history = []
	history.append({
		"sceneId": target_id,
		"enteredAt": Time.get_unix_time_from_system(),
		"fromSceneId": current_id,
		"reason": reason,
	})
	active_game["sceneHistory"] = history

	var gm_author := get_gm_display_name() if active_game.get("gmType", "ai") == "human" else "MJ"
	var transition_note := ""
	if not reason.is_empty():
		transition_note = "\n[i](%s)[/i]" % reason
	add_log_entry(
		gm_author,
		"[b]Nouvelle scène : %s[/b]%s\n%s" % [
			target_scene.get("title", ""),
			transition_note,
			target_scene.get("content", ""),
		],
		"gm"
	)
	_reveal_world_on_scene_advance()
	_reveal_investigation_on_scene_advance()
	save_active_game()
	return true

func complete_scenario(reason: String = "") -> bool:
	if active_game.is_empty():
		return false
	_close_current_scene_history_entry()
	var suffix := ""
	if not reason.is_empty():
		suffix = " %s" % reason
	add_log_entry("Système", "[b]Fin du scénario atteinte ![/b]%s" % suffix, "system")
	active_game["status"] = "completed"
	active_game["waitingForGm"] = false
	save_active_game()
	return false

func get_current_scene() -> Dictionary:
	if active_game.is_empty():
		return {}
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	var current_id := QuestNavigation.resolve_current_scene_id(active_game, scenario)
	return QuestNavigation.get_scene_by_id(scenario, current_id)

func get_scene_navigation_summary() -> Dictionary:
	if active_game.is_empty():
		return {}
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	var current_id := QuestNavigation.resolve_current_scene_id(active_game, scenario)
	return {
		"currentSceneId": current_id,
		"currentScene": QuestNavigation.get_scene_by_id(scenario, current_id),
		"transitions": QuestNavigation.get_available_transitions(scenario, current_id),
		"visitedSceneIds": active_game.get("visitedSceneIds", []),
		"sceneHistory": active_game.get("sceneHistory", []),
		"progressLabel": QuestNavigation.format_progress_label(scenario, active_game),
		"isTerminal": QuestNavigation.is_terminal_scene(scenario, current_id),
	}

func _ensure_navigation_state() -> void:
	if active_game.is_empty():
		return
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	if scenario.is_empty():
		return
	var current_id := QuestNavigation.resolve_current_scene_id(active_game, scenario)
	active_game["currentSceneId"] = current_id
	active_game["currentSceneIndex"] = maxi(0, QuestNavigation.get_scene_index(scenario, current_id))
	if not active_game.has("visitedSceneIds") or typeof(active_game["visitedSceneIds"]) != TYPE_ARRAY:
		active_game["visitedSceneIds"] = [current_id] if not current_id.is_empty() else []
	elif not current_id.is_empty() and not active_game["visitedSceneIds"].has(current_id):
		active_game["visitedSceneIds"].append(current_id)
	if not active_game.has("sceneHistory") or typeof(active_game["sceneHistory"]) != TYPE_ARRAY or active_game["sceneHistory"].is_empty():
		active_game["sceneHistory"] = [{
			"sceneId": current_id,
			"enteredAt": active_game.get("startedAt", Time.get_unix_time_from_system()),
			"fromSceneId": "",
			"reason": "Reprise de partie",
		}] if not current_id.is_empty() else []

func _close_current_scene_history_entry() -> void:
	var history: Array = active_game.get("sceneHistory", [])
	if typeof(history) != TYPE_ARRAY or history.is_empty():
		return
	var last_entry: Dictionary = history[history.size() - 1]
	if last_entry.has("exitedAt"):
		return
	last_entry["exitedAt"] = Time.get_unix_time_from_system()
	history[history.size() - 1] = last_entry
	active_game["sceneHistory"] = history

func apply_server_state(state: Dictionary) -> void:
	active_game = sync_game_scenario_metadata(state.duplicate(true))
	_ensure_navigation_state()
	if not active_game.has("mapIds") or active_game["mapIds"].is_empty():
		var scn_id: String = active_game.get("scenarioId", "")
		var qf: String = active_game.get("questFormat", "oneshot")
		active_game["mapIds"] = expand_map_ids_with_linked_locals(MapData.get_map_ids_for_scenario(scn_id, qf))
	if not active_game.has("mapPlayState"):
		active_game["mapPlayState"] = {}
	if not active_game.has("mapNavigation"):
		active_game["mapNavigation"] = { "view": "world", "worldMapId": null, "localMapId": null, "worldCell": null }
	if not active_game.has("waitingForGm"):
		active_game["waitingForGm"] = false
	if not active_game.has("gmName"):
		active_game["gmName"] = "MJ"
	ensure_map_play_state()
	init_all_world_map_fog()
	if active_game.get("questFormat", "") == "investigation":
		for map_id in active_game.get("mapIds", []):
			if get_revealed_markers(str(map_id)).is_empty():
				init_investigation_clues(str(map_id))
	active_game["status"] = "playing" if state.get("status", "playing") == "playing" else state.get("status", "playing")
	save_active_game()

# ==============================================================================
# CARTES INTERACTIVES
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
	if not active_game.has("mapModeOverrides") or typeof(active_game["mapModeOverrides"]) != TYPE_DICTIONARY:
		active_game["mapModeOverrides"] = {}

func get_effective_render_mode(map_id: String) -> String:
	if active_game.is_empty():
		return MapData.RENDER_MODE_SIMPLE
	var overrides: Dictionary = active_game.get("mapModeOverrides", {})
	if overrides.has(map_id):
		return MapData.RENDER_MODE_COMPLEX if overrides[map_id] == MapData.RENDER_MODE_COMPLEX else MapData.RENDER_MODE_SIMPLE
	var map_data := MapData.get_by_id(map_id)
	return MapData.get_render_mode(map_data)

func set_map_render_mode_override(map_id: String, mode: String) -> void:
	ensure_map_play_state()
	var overrides: Dictionary = active_game.get("mapModeOverrides", {})
	overrides[map_id] = MapData.RENDER_MODE_COMPLEX if mode == MapData.RENDER_MODE_COMPLEX else MapData.RENDER_MODE_SIMPLE
	active_game["mapModeOverrides"] = overrides
	save_map_play_and_sync()

func save_map_play_and_sync() -> void:
	save_active_game()
	if MultiplayerManager.is_p2p_host() and MultiplayerManager.is_p2p_active():
		MultiplayerManager.broadcast_state()

func get_map_play_entry(map_id: String) -> Dictionary:
	ensure_map_play_state()
	var mps: Dictionary = active_game["mapPlayState"]
	if not mps.has(map_id):
		mps[map_id] = {
			"tokens": [], "explored": [], "exploreLevel": 0,
			"revealedMarkers": [], "revealedLinks": [],
			"fogRevealed": [], "effects": [], "zones": [],
			"viewState": {}, "selectedTokenId": "",
		}
	var entry: Dictionary = mps[map_id]
	if not entry.has("tokens") or typeof(entry["tokens"]) != TYPE_ARRAY:
		entry["tokens"] = []
	if not entry.has("explored") or typeof(entry["explored"]) != TYPE_ARRAY:
		entry["explored"] = []
	if not entry.has("exploreLevel"):
		entry["exploreLevel"] = 0
	if not entry.has("revealedMarkers") or typeof(entry["revealedMarkers"]) != TYPE_ARRAY:
		entry["revealedMarkers"] = []
	if not entry.has("revealedLinks") or typeof(entry["revealedLinks"]) != TYPE_ARRAY:
		entry["revealedLinks"] = []
	if not entry.has("fogRevealed") or typeof(entry["fogRevealed"]) != TYPE_ARRAY:
		entry["fogRevealed"] = []
	if not entry.has("effects") or typeof(entry["effects"]) != TYPE_ARRAY:
		entry["effects"] = []
	if not entry.has("zones") or typeof(entry["zones"]) != TYPE_ARRAY:
		entry["zones"] = []
	if not entry.has("viewState") or typeof(entry["viewState"]) != TYPE_DICTIONARY:
		entry["viewState"] = {}
	if not entry.has("selectedTokenId"):
		entry["selectedTokenId"] = ""
	if not entry.has("doorStates") or typeof(entry["doorStates"]) != TYPE_DICTIONARY:
		entry["doorStates"] = {}
	if not entry.has("visibleNow") or typeof(entry["visibleNow"]) != TYPE_ARRAY:
		entry["visibleNow"] = []
	_seed_play_defaults_from_map(map_id, entry)
	return entry

func _seed_play_defaults_from_map(map_id: String, entry: Dictionary) -> void:
	var map_def := MapData.get_by_id(map_id)
	if map_def.is_empty():
		return
	var pd := MapData.ensure_play_defaults(map_def)
	if entry["tokens"].is_empty() and pd.get("tokens", []).size() > 0:
		entry["tokens"] = pd["tokens"].duplicate(true)
	if entry["effects"].is_empty() and pd.get("effects", []).size() > 0:
		entry["effects"] = pd["effects"].duplicate(true)
	if entry["zones"].is_empty() and pd.get("zones", []).size() > 0:
		entry["zones"] = pd["zones"].duplicate(true)
	if entry["fogRevealed"].is_empty() and pd.get("fogRevealed", []).size() > 0:
		entry["fogRevealed"] = pd["fogRevealed"].duplicate(true)
	if entry["viewState"].is_empty() and not pd.get("viewState", {}).is_empty():
		entry["viewState"] = pd["viewState"].duplicate(true)

func get_fog_revealed_cells(map_id: String) -> Array:
	return get_map_play_entry(map_id)["fogRevealed"]

func get_map_effects(map_id: String) -> Array:
	return get_map_play_entry(map_id)["effects"]

func get_map_zones(map_id: String) -> Array:
	return get_map_play_entry(map_id)["zones"]

func get_map_view_state(map_id: String) -> Dictionary:
	return get_map_play_entry(map_id)["viewState"]

func get_selected_token_id(map_id: String) -> String:
	return str(get_map_play_entry(map_id).get("selectedTokenId", ""))

func set_selected_token_id(map_id: String, token_id: String) -> void:
	get_map_play_entry(map_id)["selectedTokenId"] = token_id
	save_map_play_and_sync()

func reveal_fog_cells(map_id: String, cells: Array) -> void:
	var entry := get_map_play_entry(map_id)
	for key in cells:
		var k := str(key)
		if not entry["fogRevealed"].has(k):
			entry["fogRevealed"].append(k)
	save_map_play_and_sync()

func place_map_effect(map_id: String, preset: String, gx: float, gy: float, radius: float = 1.0) -> Dictionary:
	var entry := get_map_play_entry(map_id)
	var effect := {
		"id": generate_id("fx"),
		"type": "particles",
		"preset": preset,
		"x": gx, "y": gy,
		"radius": radius,
		"triggered": false,
		"label": preset,
	}
	entry["effects"].append(effect)
	save_map_play_and_sync()
	return effect

func trigger_map_effect(map_id: String, effect_id: String) -> void:
	var entry := get_map_play_entry(map_id)
	for eff in entry["effects"]:
		if str(eff.get("id", "")) == effect_id:
			eff["triggered"] = true
			break
	save_map_play_and_sync()

func stop_map_effect(map_id: String, effect_id: String) -> void:
	var entry := get_map_play_entry(map_id)
	for eff in entry["effects"]:
		if str(eff.get("id", "")) == effect_id:
			eff["triggered"] = false
			break
	save_map_play_and_sync()

func place_map_zone(map_id: String, gx: float, gy: float, shape: String = "circle", radius: float = 1.5, label: String = "") -> Dictionary:
	var entry := get_map_play_entry(map_id)
	var zone := {
		"id": generate_id("zone"),
		"shape": shape,
		"x": gx, "y": gy,
		"radius": radius,
		"width": radius * 2,
		"height": radius * 2,
		"label": label,
		"color": "#c9a227",
	}
	entry["zones"].append(zone)
	save_map_play_and_sync()
	return zone

func move_complex_token(map_id: String, token_id: String, gx: float, gy: float) -> void:
	var entry := get_map_play_entry(map_id)
	for tok in entry["tokens"]:
		if str(tok.get("id", "")) == token_id:
			tok["x"] = gx
			tok["y"] = gy
			break
	recompute_dynamic_fog(map_id)
	save_map_play_and_sync()

# ===========================================================================
# Opérations de carte synchronisées
# ===========================================================================
#
# Plutôt que rediffuser tout `active_game` à chaque geste, les modifications de
# carte passent par de petites opérations. Le MJ fait autorité : un joueur
# soumet, le MJ valide, applique et rediffuse l'opération seule.

const MAP_OP_MOVE_TOKEN := "move_token"
const MAP_OP_PLACE := "place"
const MAP_OP_ERASE := "erase"
const MAP_OP_FOG_REVEAL := "fog_reveal"
const MAP_OP_FOG_HIDE := "fog_hide"
const MAP_OP_DOOR := "door"
const MAP_OP_EFFECT_TRIGGER := "effect_trigger"
const MAP_OP_SELECT := "select"

## Opérations qu'un joueur non-MJ peut demander de son propre chef.
const PLAYER_ALLOWED_OPS := [MAP_OP_MOVE_TOKEN, MAP_OP_DOOR, MAP_OP_SELECT]

## Point d'entrée unique de l'UI. En P2P côté joueur, l'opération part au MJ ;
## sinon elle est appliquée localement puis rediffusée si l'on est hôte.
func submit_map_op(map_id: String, op: Dictionary) -> bool:
	if MultiplayerManager.is_p2p_active() and not MultiplayerManager.is_p2p_host():
		MultiplayerManager.client_request_map_op(map_id, op)
		return true
	if not can_apply_map_op(map_id, op, MultiplayerManager.player_id):
		return false
	if not apply_map_op(map_id, op):
		return false
	save_active_game()
	MultiplayerManager.host_broadcast_map_op(map_id, op)
	return true

## Autorité : le MJ peut tout, un joueur ne touche qu'à son propre token
## (plus les portes et sa sélection).
func can_apply_map_op(map_id: String, op: Dictionary, player_id: String) -> bool:
	if not MultiplayerManager.is_p2p_active():
		return true
	if MultiplayerManager.is_gm_peer(player_id):
		return true
	var type := str(op.get("type", ""))
	if not PLAYER_ALLOWED_OPS.has(type):
		return false
	if type == MAP_OP_MOVE_TOKEN:
		return _player_owns_token(map_id, str(op.get("tokenId", "")), player_id)
	return true

func _player_owns_token(map_id: String, token_id: String, player_id: String) -> bool:
	if token_id.is_empty() or player_id.is_empty():
		return false
	var entry := get_map_play_entry(map_id)
	var member_id := ""
	for token_variant in entry["tokens"]:
		var token: Dictionary = token_variant
		if str(token.get("id", "")) == token_id:
			member_id = str(token.get("memberId", ""))
			break
	if member_id.is_empty():
		return false
	for member_variant in active_game.get("party", []):
		var member: Dictionary = member_variant
		if str(member.get("id", "")) == member_id:
			return str(member.get("clientId", "")) == player_id
	return false

## Applique une opération déjà autorisée. Ne diffuse rien : l'appelant décide.
func apply_map_op(map_id: String, op: Dictionary) -> bool:
	if active_game.is_empty() or map_id.is_empty():
		return false
	var entry := get_map_play_entry(map_id)
	var type := str(op.get("type", ""))
	match type:
		MAP_OP_MOVE_TOKEN:
			var token_id := str(op.get("tokenId", ""))
			var found := false
			for token_variant in entry["tokens"]:
				var token: Dictionary = token_variant
				if str(token.get("id", "")) == token_id:
					token["x"] = float(op.get("x", token.get("x", 0)))
					token["y"] = float(op.get("y", token.get("y", 0)))
					found = true
					break
			if not found:
				return false
			recompute_dynamic_fog(map_id)
		MAP_OP_PLACE:
			apply_complex_map_click_local(map_id, float(op.get("x", 0)), float(op.get("y", 0)), op.get("tool", {}))
		MAP_OP_ERASE:
			remove_map_token_at(map_id, int(roundf(float(op.get("x", 0)))), int(roundf(float(op.get("y", 0)))))
			_remove_token_near(map_id, float(op.get("x", 0)), float(op.get("y", 0)))
		MAP_OP_FOG_REVEAL:
			for key in op.get("cells", []):
				if not entry["fogRevealed"].has(str(key)):
					entry["fogRevealed"].append(str(key))
		MAP_OP_FOG_HIDE:
			for key in op.get("cells", []):
				entry["fogRevealed"].erase(str(key))
		MAP_OP_DOOR:
			var door_id := str(op.get("doorId", ""))
			if door_id.is_empty():
				return false
			var states: Dictionary = entry.get("doorStates", {})
			states[door_id] = bool(op.get("open", not is_door_open(map_id, door_id)))
			entry["doorStates"] = states
			recompute_dynamic_fog(map_id)
		MAP_OP_EFFECT_TRIGGER:
			var effect_id := str(op.get("effectId", ""))
			for effect_variant in entry["effects"]:
				var effect: Dictionary = effect_variant
				if str(effect.get("id", "")) == effect_id:
					effect["triggered"] = bool(op.get("triggered", true))
					break
		MAP_OP_SELECT:
			entry["selectedTokenId"] = str(op.get("tokenId", ""))
		_:
			return false
	return true

## Variante locale de `apply_complex_map_click` sans diffusion d'état complet.
func apply_complex_map_click_local(map_id: String, gx: float, gy: float, tool: Dictionary) -> void:
	var mode: String = tool.get("mode", "")
	match mode:
		"member":
			place_complex_member_token(map_id, gx, gy, tool.get("memberId", ""))
		"marker":
			place_complex_marker_token(map_id, gx, gy, tool.get("markerType", ""))
		"effect":
			place_map_effect(map_id, tool.get("preset", "fire"), gx, gy, float(tool.get("radius", 1.0)))
		"zone":
			place_map_zone(map_id, gx, gy, "circle", float(tool.get("radius", 1.5)), tool.get("label", ""))

# ===========================================================================
# Vue filtrée pour les joueurs
# ===========================================================================

## État de carte tel qu'un joueur a le droit de le voir.
##
## Le MJ reçoit tout. Un joueur ne reçoit ni les éléments marqués MJ, ni les
## tokens tapis dans une case que le groupe ne voit pas : le brouillard cesse
## d'être un simple calque graphique, l'information n'est plus là.
func filter_map_entry_for_player(map_id: String, viewer_is_gm: bool) -> Dictionary:
	var entry := get_map_play_entry(map_id)
	if viewer_is_gm:
		return entry.duplicate(true)
	var filtered: Dictionary = entry.duplicate(true)
	var map_def := MapData.get_by_id(map_id)
	var fog_on := bool(map_def.get("fogEnabled", true))
	var los_on := bool(map_def.get("losEnabled", false))
	var visible: Dictionary = {}
	if los_on:
		for key in entry.get("visibleNow", []):
			visible[str(key)] = true
	var revealed: Dictionary = {}
	for key in entry.get("fogRevealed", []):
		revealed[str(key)] = true

	filtered["tokens"] = (entry["tokens"] as Array).filter(func(token):
		if bool(token.get("gmOnly", false)) or bool(token.get("hidden", false)):
			return false
		if not fog_on:
			return true
		# Un token du groupe reste toujours visible pour ses joueurs.
		if not str(token.get("memberId", "")).is_empty():
			return true
		var key := "%d,%d" % [int(roundf(float(token.get("x", 0)))), int(roundf(float(token.get("y", 0))))]
		if los_on:
			return visible.has(key)
		return revealed.has(key)
	)
	filtered["effects"] = (entry["effects"] as Array).filter(func(effect):
		return not bool(effect.get("gmOnly", false)) and not bool(effect.get("hidden", false))
	)
	filtered["zones"] = (entry["zones"] as Array).filter(func(zone):
		return not bool(zone.get("gmOnly", false)) and not bool(zone.get("hidden", false))
	)
	return filtered

# ===========================================================================
# Ligne de vue et brouillard dynamique
# ===========================================================================

## Carte de session avec l'état d'ouverture des portes appliqué.
## Les portes appartiennent à la carte, leur ouverture est un fait de partie.
func get_map_with_door_states(map_id: String) -> Dictionary:
	var map_def := MapData.get_by_id(map_id)
	if map_def.is_empty():
		return {}
	var entry := get_map_play_entry(map_id)
	var states: Dictionary = entry.get("doorStates", {})
	return MapVision.apply_door_states(map_def, states if states is Dictionary else {})

func is_los_enabled(map_id: String) -> bool:
	var map_def := MapData.get_by_id(map_id)
	if map_def.is_empty():
		return false
	return bool(map_def.get("losEnabled", false))

## Cases actuellement dans le champ de vision des tokens de la partie.
func get_visible_now_cells(map_id: String) -> Array:
	var entry := get_map_play_entry(map_id)
	var cells = entry.get("visibleNow", [])
	return cells if cells is Array else []

## Recalcule le champ de vision et l'ajoute au brouillard déjà révélé.
##
## `fogRevealed` est la **mémoire** de la partie : une case vue une fois le
## reste (exploration). `visibleNow` est ce qui est éclairé à l'instant t, pour
## que le rendu puisse assombrir le souvenir sans le masquer.
func recompute_dynamic_fog(map_id: String) -> Array:
	if not is_los_enabled(map_id):
		return []
	var map_def := get_map_with_door_states(map_id)
	if map_def.is_empty():
		return []
	var entry := get_map_play_entry(map_id)
	var sources: Array = MapVision.vision_sources_from_tokens(entry.get("tokens", []))
	sources.append_array(MapVision.vision_sources_from_lights(map_def))
	var visible: Array = MapVision.visible_cells_multi(map_def, sources)
	entry["visibleNow"] = visible
	var fog: Array = entry["fogRevealed"]
	for key in visible:
		if not fog.has(key):
			fog.append(key)
	entry["fogRevealed"] = fog
	return visible

## Ouvre / ferme une porte et met à jour le champ de vision.
func toggle_map_door(map_id: String, door_id: String) -> bool:
	if door_id.is_empty():
		return false
	var entry := get_map_play_entry(map_id)
	var states: Dictionary = entry.get("doorStates", {})
	if not states is Dictionary:
		states = {}
	var map_def := MapData.get_by_id(map_id)
	var was_open := false
	for door_variant in MapVision.doors(map_def):
		var door: Dictionary = door_variant
		if str(door.get("id", "")) == door_id:
			was_open = bool(states.get(door_id, door.get("open", false)))
			break
	states[door_id] = not was_open
	entry["doorStates"] = states
	recompute_dynamic_fog(map_id)
	save_map_play_and_sync()
	return not was_open

func is_door_open(map_id: String, door_id: String) -> bool:
	var entry := get_map_play_entry(map_id)
	var states: Dictionary = entry.get("doorStates", {})
	if states is Dictionary and states.has(door_id):
		return bool(states[door_id])
	for door_variant in MapVision.doors(MapData.get_by_id(map_id)):
		var door: Dictionary = door_variant
		if str(door.get("id", "")) == door_id:
			return bool(door.get("open", false))
	return false

## Ligne de vue entre deux positions grille, portes de session comprises.
func has_line_of_sight(map_id: String, from: Vector2, to: Vector2) -> bool:
	var map_def := get_map_with_door_states(map_id)
	if map_def.is_empty():
		return true
	return MapVision.has_line_of_sight(map_def, from, to)

func apply_complex_map_click(map_id: String, gx: float, gy: float, tool: Dictionary) -> void:
	if active_game.is_empty() or active_game.get("status") == "completed":
		return
	var mode: String = tool.get("mode", "")
	var ix := int(roundf(gx))
	var iy := int(roundf(gy))
	match mode:
		"erase":
			remove_map_token_at(map_id, ix, iy)
			_remove_token_near(map_id, gx, gy)
		"member":
			place_complex_member_token(map_id, gx, gy, tool.get("memberId", ""))
		"marker":
			place_complex_marker_token(map_id, gx, gy, tool.get("markerType", ""))
		"effect":
			place_map_effect(map_id, tool.get("preset", "fire"), gx, gy, float(tool.get("radius", 1.0)))
		"zone":
			place_map_zone(map_id, gx, gy, "circle", float(tool.get("radius", 1.5)), tool.get("label", ""))
	save_map_play_and_sync()

func place_complex_member_token(map_id: String, gx: float, gy: float, member_id: String) -> void:
	if member_id.is_empty():
		return
	remove_member_tokens(map_id, member_id)
	var member := _find_party_member(member_id)
	if member.is_empty():
		return
	var entry := get_map_play_entry(map_id)
	entry["tokens"].append({
		"id": generate_id("tok"),
		"x": gx, "y": gy,
		"kind": "member",
		"memberId": member_id,
		"label": member.get("name", "Héros"),
		"hp": member.get("hp", 0),
		"maxHp": member.get("hp", 0),
	})
	if is_los_enabled(map_id):
		# Avec la ligne de vue, le brouillard découle des murs, pas d'un disque.
		recompute_dynamic_fog(map_id)
	elif is_gm_view_for_map(map_id):
		reveal_fog_cells(map_id, _cells_around(int(roundf(gx)), int(roundf(gy)), 2))

func place_complex_marker_token(map_id: String, gx: float, gy: float, marker_type: String) -> void:
	if marker_type.is_empty():
		return
	_remove_token_near(map_id, gx, gy)
	var entry := get_map_play_entry(map_id)
	entry["tokens"].append({
		"id": generate_id("tok"),
		"x": gx, "y": gy,
		"kind": "marker",
		"markerType": marker_type,
		"label": MapData.get_marker_label(marker_type),
	})

func _remove_token_near(map_id: String, gx: float, gy: float, threshold: float = 0.45) -> void:
	var entry := get_map_play_entry(map_id)
	entry["tokens"] = entry["tokens"].filter(func(t):
		var dx: float = abs(float(t.get("x", 0)) - gx)
		var dy: float = abs(float(t.get("y", 0)) - gy)
		return dx > threshold or dy > threshold
	)

func _cells_around(cx: int, cy: int, radius: int) -> Array:
	var cells: Array = []
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if abs(x - cx) + abs(y - cy) <= radius:
				cells.append("%d,%d" % [x, y])
	return cells

func is_gm_view_for_map(_map_id: String) -> bool:
	if active_game.get("gmType", "ai") != "human":
		return true
	if MultiplayerManager.is_p2p_active():
		return MultiplayerManager.is_p2p_host() and MultiplayerManager.is_mj()
	return true

func save_map_view_state(map_id: String, view_state: Dictionary) -> void:
	get_map_play_entry(map_id)["viewState"] = view_state.duplicate(true)
	save_map_play_and_sync()

func get_revealed_markers(map_id: String) -> Array:
	return get_map_play_entry(map_id)["revealedMarkers"]

func get_revealed_links(map_id: String) -> Array:
	return get_map_play_entry(map_id)["revealedLinks"]

func is_marker_revealed(map_id: String, x: int, y: int) -> bool:
	return get_revealed_markers(map_id).has(cell_key(x, y))

func is_link_revealed(map_id: String, x: int, y: int) -> bool:
	return get_revealed_links(map_id).has(cell_key(x, y))

func reveal_map_marker(map_id: String, x: int, y: int) -> bool:
	var key := cell_key(x, y)
	var entry := get_map_play_entry(map_id)
	if entry["revealedMarkers"].has(key):
		return false
	entry["revealedMarkers"].append(key)
	return true

func reveal_map_link(map_id: String, x: int, y: int) -> bool:
	var key := cell_key(x, y)
	var entry := get_map_play_entry(map_id)
	if entry["revealedLinks"].has(key):
		return false
	entry["revealedLinks"].append(key)
	return true

func init_investigation_clues_for_game() -> void:
	if active_game.is_empty():
		return
	if active_game.get("questFormat", "") != "investigation":
		return
	for map_id in active_game.get("mapIds", []):
		init_investigation_clues(str(map_id))

func init_investigation_clues(map_id: String) -> void:
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return
	var quest_format: String = active_game.get("questFormat", "oneshot")
	if not MapData.is_investigation_map_context(map_data, quest_format):
		return
	var entry := get_map_play_entry(map_id)
	var revealed: Array = []
	for mk in map_data.get("markers", []):
		var mk_type: String = str(mk.get("type", ""))
		if MapData.is_investigation_hidden_marker(mk_type, map_data, quest_format):
			continue
		var key := cell_key(int(mk.get("x", 0)), int(mk.get("y", 0)))
		if not revealed.has(key):
			revealed.append(key)
	entry["revealedMarkers"] = revealed
	entry["revealedLinks"] = []

func reveal_investigation_near(map_id: String, cx: int, cy: int, radius: int = 1) -> int:
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty() or active_game.is_empty():
		return 0
	var quest_format: String = active_game.get("questFormat", "oneshot")
	if not MapData.is_investigation_map_context(map_data, quest_format):
		return 0
	var count := 0
	for mk in map_data.get("markers", []):
		var mx: int = int(mk.get("x", 0))
		var my: int = int(mk.get("y", 0))
		var mk_type: String = str(mk.get("type", ""))
		if not MapData.is_investigation_hidden_marker(mk_type, map_data, quest_format):
			continue
		if abs(mx - cx) + abs(my - cy) > radius:
			continue
		if reveal_map_marker(map_id, mx, my):
			count += 1
	if MapData.is_world_map(map_data):
		for link in map_data.get("locationLinks", []):
			var lx: int = int(link.get("x", 0))
			var ly: int = int(link.get("y", 0))
			if abs(lx - cx) + abs(ly - cy) > radius:
				continue
			if reveal_map_link(map_id, lx, ly):
				count += 1
	return count

func reveal_next_investigation_clues(map_id: String, count: int = 1) -> int:
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty() or active_game.is_empty():
		return 0
	var quest_format: String = active_game.get("questFormat", "oneshot")
	if not MapData.is_investigation_map_context(map_data, quest_format):
		return 0
	var hidden: Array = []
	for mk in map_data.get("markers", []):
		var mx: int = int(mk.get("x", 0))
		var my: int = int(mk.get("y", 0))
		var mk_type: String = str(mk.get("type", ""))
		if not MapData.is_investigation_hidden_marker(mk_type, map_data, quest_format):
			continue
		if is_marker_revealed(map_id, mx, my):
			continue
		hidden.append({ "x": mx, "y": my, "dist": _investigation_clue_distance(map_id, mx, my) })
	if MapData.is_world_map(map_data):
		for link in map_data.get("locationLinks", []):
			var lx: int = int(link.get("x", 0))
			var ly: int = int(link.get("y", 0))
			if is_link_revealed(map_id, lx, ly):
				continue
			hidden.append({ "x": lx, "y": ly, "dist": _investigation_clue_distance(map_id, lx, ly), "link": true })
	if hidden.is_empty():
		return 0
	hidden.sort_custom(func(a, b): return a.get("dist", 999) < b.get("dist", 999))
	var revealed := 0
	for i in range(mini(count, hidden.size())):
		var item: Dictionary = hidden[i]
		if item.get("link", false):
			if reveal_map_link(map_id, int(item["x"]), int(item["y"])):
				revealed += 1
		elif reveal_map_marker(map_id, int(item["x"]), int(item["y"])):
			revealed += 1
	return revealed

func _investigation_clue_distance(map_id: String, x: int, y: int) -> int:
	var best := 9999
	for tok in get_map_play_tokens(map_id):
		if tok.get("kind") != "member":
			continue
		best = mini(best, abs(int(tok.get("x", 0)) - x) + abs(int(tok.get("y", 0)) - y))
	if best < 9999:
		return best
	var map_data := MapData.get_by_id(map_id)
	if not map_data.is_empty():
		var start := get_world_map_start_point(map_data)
		return abs(start.x - x) + abs(start.y - y)
	return 9999

func maybe_reveal_investigation_from_action(action_text: String) -> void:
	if active_game.is_empty() or active_game.get("questFormat", "") != "investigation":
		return
	var text := _normalize_action_text(action_text)
	var investigative := [
		"fouill", "examin", "inspect", "explor", "cherch", "regard", "interroge",
		"parl", "question", "indice", "enquêt", "analys", "deduis", "recouvr",
	]
	var matched := false
	for kw in investigative:
		if text.contains(kw):
			matched = true
			break
	if not matched:
		return
	var map_id := get_active_play_map_id()
	if map_id.is_empty():
		return
	var member_id := ""
	for m in active_game.get("party", []):
		if m.get("isPlayer", false):
			member_id = str(m.get("id", ""))
			break
	var pos := get_member_token_position(map_id, member_id)
	if pos.x < 0:
		var map_data := MapData.get_by_id(map_id)
		if not map_data.is_empty():
			pos = get_world_map_start_point(map_data)
	reveal_investigation_near(map_id, pos.x, pos.y, 2)
	reveal_next_investigation_clues(map_id, 1)
	save_active_game()

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

# ===========================================================================
# Navigation entre échelles de carte
# ===========================================================================
#
# Une carte de village porte des lieux ; entrer dans un lieu empile sa carte.
# La pile permet une profondeur libre : village → place du marché → taverne.

func get_area_stack() -> Array:
	ensure_map_play_state()
	var nav: Dictionary = active_game["mapNavigation"]
	var stack = nav.get("areaStack", [])
	if not stack is Array:
		stack = []
		nav["areaStack"] = stack
	return stack

## Carte réellement affichée compte tenu de la pile de lieux.
func get_current_area_map_id(root_map_id: String) -> String:
	var stack := get_area_stack()
	if stack.is_empty():
		return root_map_id
	var top: Dictionary = stack[stack.size() - 1]
	if str(top.get("rootMapId", "")) != root_map_id:
		return root_map_id
	return str(top.get("mapId", root_map_id))

## Entre dans le lieu `area_id` de `map_id` : sa carte devient la vue courante.
func enter_area(map_id: String, area_id: String) -> bool:
	var map_def := MapData.get_by_id(map_id)
	if map_def.is_empty():
		return false
	var area := MapData.get_area(map_def, area_id)
	var target_id := str(area.get("targetMapId", ""))
	if target_id.is_empty() or MapData.get_by_id(target_id).is_empty():
		return false
	ensure_map_play_state()
	var stack := get_area_stack()
	var root_id: String = str(stack[0].get("rootMapId", map_id)) if not stack.is_empty() else map_id
	stack.append({
		"rootMapId": root_id,
		"fromMapId": map_id,
		"areaId": area_id,
		"mapId": target_id,
		"label": str(area.get("label", "Lieu")),
	})
	active_game["mapNavigation"]["areaStack"] = stack
	var ids: Array = active_game["mapIds"]
	if not ids.has(target_id):
		ids.append(target_id)
	save_map_play_and_sync()
	return true

## Remonte d'un cran dans la pile de lieux.
func exit_area() -> bool:
	var stack := get_area_stack()
	if stack.is_empty():
		return false
	stack.pop_back()
	active_game["mapNavigation"]["areaStack"] = stack
	save_map_play_and_sync()
	return true

func clear_area_stack() -> void:
	ensure_map_play_state()
	active_game["mapNavigation"]["areaStack"] = []
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
	var quest_format: String = active_game.get("questFormat", "oneshot") if not active_game.is_empty() else "oneshot"
	if MapData.is_world_map(map_data):
		reveal_world_at(map_id, x, y, 2)
	elif MapData.is_investigation_map_context(map_data, quest_format):
		reveal_investigation_near(map_id, x, y, 1)
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

func get_active_play_map_id() -> String:
	if active_game.is_empty():
		return ""
	var map_ids: Array = active_game.get("mapIds", [])
	if map_ids.is_empty():
		return ""
	var nav: Dictionary = active_game.get("mapNavigation", {})
	if nav.get("view") == "local":
		var local_id: String = nav.get("localMapId", "")
		if not local_id.is_empty():
			return local_id
	for map_id in map_ids:
		var map_data := MapData.get_by_id(map_id)
		if not map_data.is_empty() and MapData.is_world_map(map_data):
			return map_id
	return map_ids[0]

func get_member_token_position(map_id: String, member_id: String) -> Vector2i:
	for tok in get_map_play_tokens(map_id):
		if tok.get("kind") == "member" and tok.get("memberId") == member_id:
			return Vector2i(int(tok.get("x", 0)), int(tok.get("y", 0)))
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return Vector2i(-1, -1)
	return get_world_map_start_point(map_data)

func _normalize_action_text(action_text: String) -> String:
	var text := action_text.strip_edges().to_lower()
	text = text.replace("à", "a").replace("â", "a").replace("ä", "a")
	text = text.replace("é", "e").replace("è", "e").replace("ê", "e").replace("ë", "e")
	text = text.replace("î", "i").replace("ï", "i")
	text = text.replace("ô", "o").replace("ö", "o")
	text = text.replace("ù", "u").replace("û", "u").replace("ü", "u")
	text = text.replace("ç", "c")
	text = text.replace("'", " ").replace("'", " ").replace("-", " ")
	for glued in ["jecoute", "jevais", "jemarche", "jeme", "jedirige", "jerends", "jsuis"]:
		if text.contains(glued):
			text = text.replace(glued, "j " + glued.substr(1))
	while text.contains("  "):
		text = text.replace("  ", " ")
	return text.strip_edges()

func _semantic_place_keywords() -> Array:
	return [
		"foret", "bois", "auberge", "taverne", "capitale", "capital", "ville",
		"port", "ruine", "donjon", "forteresse", "mine", "quete", "campement",
		"cave", "tavernier", "entree", "sortie", "hostellerie", "bosquet",
		"palais", "cite", "bourg", "ruines", "pics", "valdris",
	]

func _has_semantic_destination_intent(text: String) -> bool:
	for kw in _semantic_place_keywords():
		if text.contains(kw):
			return true
	for mk in _get_scenario_map_markers_for_active_game():
		var label := _normalize_action_text(mk.get("label", ""))
		if label.length() >= 3 and text.contains(label):
			return true
	return false

func _has_explicit_cardinal_direction(text: String) -> bool:
	var explicit := [
		"nord-est", "nord est", "nord-ouest", "nord ouest",
		"sud-est", "sud est", "sud-ouest", "sud ouest",
		"vers le nord", "vers le sud", "vers l ouest", "vers l est",
		"au nord", "au sud", "a l ouest", "a l est",
		"direction nord", "direction sud", "direction ouest", "direction est",
		" vers nord", " vers sud", " vers ouest", " vers est",
		"cap au nord", "cap au sud", "cap a l est", "cap a l ouest",
	]
	for phrase in explicit:
		if text.contains(phrase):
			return true
	if text.ends_with(" nord") or text.ends_with(" sud") or text.ends_with(" ouest"):
		return true
	if text.ends_with(" est") and not text.ends_with(" forest") and not text.ends_with(" ouest"):
		return true
	return false

func _npc_location_keywords() -> Dictionary:
	return {
		"torval": ["fort", "brume", "dungeon", "donjon", "pics"],
		"elwen": ["garde", "muraille", "fortin"],
		"oldra": ["village", "hameau", "sans nom"],
		"thrain": ["keldorm", "nain", "mine"],
		"alaric": ["cathedrale", "cathédrale", "temple", "valdris", "capitale"],
		"sylka": ["nord", "brume"],
		"harald": ["guerre", "bataille", "cendre"],
	}

func _find_npc_mentioned_in_text(text: String) -> Dictionary:
	var scenario := get_scenario_by_id(active_game.get("scenarioId", ""))
	for npc in scenario.get("npcs", []):
		var full_name := _normalize_action_text(npc.get("name", ""))
		if full_name.length() >= 4 and text.contains(full_name):
			return npc
		for part in full_name.split(" ", false):
			if part.length() >= 4 and text.contains(part):
				return npc
	return {}

func _ensure_party_tokens_on_world_maps() -> void:
	if active_game.is_empty():
		return
	for map_id in get_world_map_ids():
		var map_data := MapData.get_by_id(map_id)
		if map_data.is_empty():
			continue
		var start := get_world_map_start_point(map_data)
		for member in active_game.get("party", []):
			if not (member.get("isHuman", false) or member.get("isPlayer", false)):
				continue
			var mid: String = member.get("id", "")
			if mid.is_empty():
				continue
			var has_token := false
			for tok in get_map_play_tokens(map_id):
				if tok.get("kind") == "member" and tok.get("memberId") == mid:
					has_token = true
					break
			if not has_token:
				place_member_token(map_id, start.x, start.y, mid)
		break

func _looks_like_movement_action(text: String) -> bool:
	var verbs := [
		"vais", "va ", " marche", "deplace", "deplac", "avance", "avancer",
		"cours", "direction", "vers le", "vers la", "vers un", "vers l",
		"me dirige", "me rends", "aller ", "chemin vers", "cap sur", "cap au", "cap a",
		"ecoute", "indications", "conseils", "suiv", "me rends",
		"dans l", "dans la", "dans le", "jusqu",
	]
	for verb in verbs:
		if text.contains(verb):
			return true
	if text.contains("nord") or text.contains("sud") or text.contains("ouest"):
		return true
	if text.contains("l'est") or text.contains("l est") or text.contains(" vers est"):
		return true
	var places := [
		"foret", "bois", "auberge", "taverne", "capitale", "capital", "ville",
		"port", "ruine", "donjon", "forteresse", "mine", "quete", "campement",
		"cave", "tavernier", "entree", "sortie",
	]
	for place in places:
		if text.contains(place):
			return true
	for mk in _get_scenario_map_markers_for_active_game():
		var label := _normalize_action_text(mk.get("label", ""))
		if label.length() >= 4 and text.contains(label):
			return true
	return false

func _get_scenario_map_markers_for_active_game() -> Array:
	var result: Array = []
	for map_id in active_game.get("mapIds", []):
		var map_data := MapData.get_by_id(map_id)
		for mk in map_data.get("markers", []):
			result.append(mk)
	return result

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _pick_nearest(from: Vector2i, candidates: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 999999
	for c in candidates:
		if c is Vector2i:
			var d := _manhattan(from, c)
			if d < best_dist:
				best_dist = d
				best = c
	return best

func _step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	if from == to:
		return from
	var dx := clampi(signi(to.x - from.x), -1, 1)
	var dy := clampi(signi(to.y - from.y), -1, 1)
	return from + Vector2i(dx, dy)

func _get_tile_id_at(map_data: Dictionary, x: int, y: int) -> String:
	var w: int = map_data.get("width", 0)
	var tiles: Array = map_data.get("tiles", [])
	var idx := y * w + x
	if idx < 0 or idx >= tiles.size():
		return ""
	return str(tiles[idx])

func _find_forest_cells(map_data: Dictionary) -> Array:
	var result: Array = []
	var w: int = map_data.get("width", 0)
	var h: int = map_data.get("height", 0)
	for y in range(h):
		for x in range(w):
			var tile := _get_tile_id_at(map_data, x, y)
			if tile.contains("forest") or tile.contains("tree") or tile == "woods":
				result.append(Vector2i(x, y))
	return result

func _find_forest_cells_near_explored(map_id: String, map_data: Dictionary) -> Array:
	var result: Array = []
	var explored: Array = get_explored_cells(map_id)
	if explored.is_empty():
		return result
	var explored_set := {}
	for key in explored:
		explored_set[key] = true
	var w: int = map_data.get("width", 0)
	var h: int = map_data.get("height", 0)
	for y in range(h):
		for x in range(w):
			var tile := _get_tile_id_at(map_data, x, y)
			if not (tile.contains("forest") or tile.contains("tree") or tile == "woods"):
				continue
			var key := cell_key(x, y)
			if explored_set.has(key):
				result.append(Vector2i(x, y))
				continue
			for ox in [-1, 0, 1]:
				for oy in [-1, 0, 1]:
					if ox == 0 and oy == 0:
						continue
					if explored_set.has(cell_key(x + ox, y + oy)):
						result.append(Vector2i(x, y))
						break
	return result

func _is_tile_walkable(map_data: Dictionary, x: int, y: int) -> bool:
	var tile := _get_tile_id_at(map_data, x, y)
	if tile.is_empty():
		return false
	if tile.contains("ocean") or tile.contains("water") or tile == "wall" or tile.contains("mountain"):
		return false
	return true

func _is_cell_walkable_for_move(map_id: String, x: int, y: int) -> bool:
	if not _is_cell_accessible_for_move(map_id, x, y):
		return false
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return false
	return _is_tile_walkable(map_data, x, y)

func _pick_best_step_towards(map_id: String, from: Vector2i, goal: Vector2i) -> Vector2i:
	if from == goal:
		return from
	var map_data := MapData.get_by_id(map_id)
	var ordered: Array = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := from + Vector2i(dx, dy)
			if map_data.is_empty() or not _is_tile_walkable(map_data, n.x, n.y):
				continue
			ordered.append({ "pos": n, "dist": _manhattan(n, goal) })
	ordered.sort_custom(func(a, b): return a["dist"] < b["dist"])
	for item in ordered:
		var n: Vector2i = item["pos"]
		if _prepare_cell_for_move(map_id, n.x, n.y) and _is_cell_walkable_for_move(map_id, n.x, n.y):
			return n
	return Vector2i(-1, -1)

func _find_anchor_position(map_data: Dictionary, text: String) -> Vector2i:
	var proximity_prefixes := [
		"pres de la ", "pres du ", "pres de ", "proche de la ", "proche du ", "proche de ",
		"a cote de la ", "a cote du ", "a cote de ", "aux alentours de la ", "aux alentours du ",
		"autour de la ", "autour du ", "autour de ",
	]
	for prefix in proximity_prefixes:
		var idx := text.find(prefix)
		if idx >= 0:
			var rest: String = text.substr(idx + prefix.length()).strip_edges()
			for mk in map_data.get("markers", []):
				var label := _normalize_action_text(mk.get("label", ""))
				if label.length() >= 3 and (rest.begins_with(label) or rest.contains(" " + label)):
					return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
			if rest.begins_with("capitale") or rest.begins_with("capital") or rest.contains(" capitale"):
				for mk in map_data.get("markers", []):
					if mk.get("type") == "capital":
						return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
			if rest.begins_with("port") or rest.contains(" port"):
				for mk in map_data.get("markers", []):
					var label := _normalize_action_text(mk.get("label", ""))
					if label.contains("port"):
						return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
	if text.contains("capitale") or text.contains("capital") or text.contains("palais") or text.contains("valdris"):
		for mk in map_data.get("markers", []):
			if mk.get("type") == "capital":
				return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
			var label := _normalize_action_text(mk.get("label", ""))
			if label.contains("capitale"):
				return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
	if text.contains("port"):
		for mk in map_data.get("markers", []):
			var label := _normalize_action_text(mk.get("label", ""))
			if label.contains("port"):
				return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
		for link in map_data.get("locationLinks", []):
			var link_label := _normalize_action_text(link.get("label", ""))
			if link_label.contains("port"):
				return Vector2i(int(link.get("x", 0)), int(link.get("y", 0)))
	if text.contains("mine"):
		for mk in map_data.get("markers", []):
			var label := _normalize_action_text(mk.get("label", ""))
			if label.contains("mine"):
				return Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
	return Vector2i(-1, -1)

func _map_title_matches_keywords(map_id: String, keywords: Array) -> bool:
	var title := _normalize_action_text(MapData.get_by_id(map_id).get("title", ""))
	for kw in keywords:
		if title.contains(kw):
			return true
	return false

func _collect_semantic_candidates(map_id: String, map_data: Dictionary, text: String) -> Array:
	var candidates: Array = []
	var anchor := _find_anchor_position(map_data, text)

	var wants_tavern := text.contains("auberge") or text.contains("taverne") or text.contains("hostellerie") or text.contains("tavernier")
	var wants_forest := text.contains("foret") or text.contains("bois") or text.contains("bosquet")
	var wants_capital := text.contains("capitale") or text.contains("capital") or text.contains("valdris")
	var wants_city := text.contains("ville") or text.contains("cite") or text.contains("bourg")
	var wants_ruin := text.contains("ruine")
	var wants_dungeon := text.contains("donjon") or text.contains("forteresse") or text.contains("chateau") or text.contains("pics")
	var wants_quest := text.contains("quete") or text.contains("mission")
	var wants_cave := text.contains("cave") or text.contains("cellier")
	var wants_exit := text.contains("sortie") or text.contains("exterieur")

	if wants_tavern:
		for link in map_data.get("locationLinks", []):
			var target_id: String = link.get("targetMapId", "")
			if _map_title_matches_keywords(target_id, ["taverne", "auberge", "hostellerie", "port"]):
				candidates.append(Vector2i(int(link.get("x", 0)), int(link.get("y", 0))))
		for mk in map_data.get("markers", []):
			var label := _normalize_action_text(mk.get("label", ""))
			if label.contains("tavernier") or label.contains("auberge") or label.contains("taverne"):
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_forest:
		var near_forest := _find_forest_cells_near_explored(map_id, map_data)
		if not near_forest.is_empty():
			for cell in near_forest:
				candidates.append(cell)
		else:
			for cell in _find_forest_cells(map_data):
				candidates.append(cell)

	if wants_capital and not wants_tavern:
		for mk in map_data.get("markers", []):
			if mk.get("type") == "capital":
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_city or (text.contains("port") and not wants_tavern):
		for mk in map_data.get("markers", []):
			if mk.get("type") == "city":
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_ruin:
		for mk in map_data.get("markers", []):
			if mk.get("type") == "ruin" or _normalize_action_text(mk.get("label", "")).contains("ruine"):
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_dungeon:
		for mk in map_data.get("markers", []):
			if mk.get("type") == "dungeon":
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_quest:
		for mk in map_data.get("markers", []):
			if mk.get("type") == "quest":
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_cave:
		for mk in map_data.get("markers", []):
			var label := _normalize_action_text(mk.get("label", ""))
			if label.contains("cave") or mk.get("type") == "poi" and label.contains("cave"):
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	if wants_exit:
		for mk in map_data.get("markers", []):
			if mk.get("type") == "exit":
				candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	for mk in map_data.get("markers", []):
		var label := _normalize_action_text(mk.get("label", ""))
		if label.length() >= 3 and text.contains(label):
			candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	for link in map_data.get("locationLinks", []):
		var link_label := _normalize_action_text(link.get("label", ""))
		if link_label.length() >= 3 and text.contains(link_label):
			candidates.append(Vector2i(int(link.get("x", 0)), int(link.get("y", 0))))

	var has_place_intent := wants_tavern or wants_forest or wants_capital or wants_city or wants_ruin or wants_dungeon or wants_quest or wants_cave or wants_exit
	if not has_place_intent:
		var npc := _find_npc_mentioned_in_text(text)
		if not npc.is_empty() and (text.contains("ecoute") or text.contains("indications") or text.contains("conseils") or text.contains("suiv")):
			var keywords: Dictionary = _npc_location_keywords()
			for part in _normalize_action_text(npc.get("name", "")).split(" ", false):
				if not keywords.has(part):
					continue
				for kw in keywords[part]:
					for mk in map_data.get("markers", []):
						var label := _normalize_action_text(mk.get("label", ""))
						var mtype: String = mk.get("type", "")
						if label.contains(kw) or mtype == kw or (kw == "donjon" and mtype == "dungeon"):
							candidates.append(Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0))))

	var unique: Array = []
	for c in candidates:
		if c not in unique:
			unique.append(c)
	candidates = unique

	if anchor.x >= 0 and not candidates.is_empty():
		if wants_tavern:
			var tavern_only: Array = []
			for link in map_data.get("locationLinks", []):
				var pos := Vector2i(int(link.get("x", 0)), int(link.get("y", 0)))
				if pos in candidates:
					tavern_only.append(pos)
			for mk in map_data.get("markers", []):
				var label := _normalize_action_text(mk.get("label", ""))
				if label.contains("tavernier") or label.contains("auberge") or label.contains("taverne"):
					var pos := Vector2i(int(mk.get("x", 0)), int(mk.get("y", 0)))
					if pos in candidates:
						tavern_only.append(pos)
			if not tavern_only.is_empty():
				return [_pick_nearest(anchor, tavern_only)]
		return [_pick_nearest(anchor, candidates)]

	return candidates

func resolve_semantic_destination(action_text: String, map_id: String, from_pos: Vector2i) -> Vector2i:
	var text := _normalize_action_text(action_text)
	if not _looks_like_movement_action(text):
		return Vector2i(-1, -1)
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return Vector2i(-1, -1)

	var candidates := _collect_semantic_candidates(map_id, map_data, text)
	if candidates.is_empty():
		return Vector2i(-1, -1)

	if candidates.size() == 1 and candidates[0] is Vector2i:
		return candidates[0]

	return _pick_nearest(from_pos, candidates)

func _prepare_cell_for_move(map_id: String, x: int, y: int) -> bool:
	if _is_cell_accessible_for_move(map_id, x, y):
		return true
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty() or not MapData.is_world_map(map_data):
		return false
	var explored: Array = get_explored_cells(map_id)
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			if ox == 0 and oy == 0:
				continue
			var nk := cell_key(x + ox, y + oy)
			if explored.has(nk):
				reveal_cell(map_id, x, y)
				reveal_world_at(map_id, x, y, 1)
				return _is_cell_accessible_for_move(map_id, x, y)
	return false

func parse_movement_delta(action_text: String) -> Vector2i:
	var text := _normalize_action_text(action_text)
	if not _looks_like_movement_action(text):
		return Vector2i.ZERO
	if _has_semantic_destination_intent(text) and not _has_explicit_cardinal_direction(text):
		return Vector2i.ZERO

	if text.contains("nord-est") or text.contains("nord est"):
		return Vector2i(1, -1)
	if text.contains("nord-ouest") or text.contains("nord ouest"):
		return Vector2i(-1, -1)
	if text.contains("sud-est") or text.contains("sud est"):
		return Vector2i(1, 1)
	if text.contains("sud-ouest") or text.contains("sud ouest"):
		return Vector2i(-1, 1)
	if text.contains("nord") or text.contains("north"):
		return Vector2i(0, -1)
	if text.contains("sud") or text.contains("south"):
		return Vector2i(0, 1)
	if text.contains("ouest") or text.contains("west"):
		return Vector2i(-1, 0)
	if text.contains("l est") or text.contains(" vers est") or text.contains(" a l est") or text.contains(" au est") or text.contains(" east"):
		return Vector2i(1, 0)
	return Vector2i.ZERO

func _is_cell_accessible_for_move(map_id: String, x: int, y: int) -> bool:
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return false
	if x < 0 or y < 0 or x >= map_data.get("width", 0) or y >= map_data.get("height", 0):
		return false
	if not MapData.is_world_map(map_data):
		return true
	var nav: Dictionary = active_game.get("mapNavigation", {})
	if nav.get("view") == "local":
		return true
	if active_game.get("status") == "completed":
		return true
	return get_explored_cells(map_id).has(cell_key(x, y))

func _get_active_human_member_id() -> String:
	for member in active_game.get("party", []):
		if member.get("isHuman", false) or member.get("isPlayer", false):
			return member.get("id", "")
	var party: Array = active_game.get("party", [])
	if not party.is_empty():
		return party[0].get("id", "")
	return ""

func try_auto_move_from_action(action_text: String, member_id: String = "") -> bool:
	if active_game.is_empty() or active_game.get("status") == "completed":
		return false
	var text := _normalize_action_text(action_text)
	if not _looks_like_movement_action(text):
		return false
	if member_id.is_empty():
		member_id = _get_active_human_member_id()
	if member_id.is_empty():
		return false

	var map_id := get_active_play_map_id()
	if map_id.is_empty():
		return false

	var pos := get_member_token_position(map_id, member_id)
	if pos.x < 0:
		return false

	var target := Vector2i(-1, -1)
	var delta := parse_movement_delta(action_text)
	if delta != Vector2i.ZERO:
		target = Vector2i(pos.x + delta.x, pos.y + delta.y)
		if not _prepare_cell_for_move(map_id, target.x, target.y):
			target = Vector2i(-1, -1)
		elif not _is_cell_walkable_for_move(map_id, target.x, target.y):
			target = Vector2i(-1, -1)
	else:
		var destination := resolve_semantic_destination(action_text, map_id, pos)
		if destination.x >= 0:
			target = _pick_best_step_towards(map_id, pos, destination)

	if target.x < 0 or target == pos:
		return false

	place_member_token(map_id, target.x, target.y, member_id)
	return true

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
	save_map_play_and_sync()

func _find_party_member(member_id: String) -> Dictionary:
	for m in active_game.get("party", []):
		if m.get("id") == member_id:
			return m
	return {}

func _reveal_investigation_on_scene_advance() -> void:
	if active_game.get("questFormat", "") != "investigation":
		return
	for map_id in active_game.get("mapIds", []):
		reveal_next_investigation_clues(str(map_id), 1)

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
	# La pile de lieux prime : elle décrit l'échelle à laquelle on joue.
	var area_map_id := get_current_area_map_id(active_map_id)
	if area_map_id != active_map_id:
		var area_map := MapData.get_by_id(area_map_id)
		if not area_map.is_empty():
			var stack := get_area_stack()
			return {
				"displayMap": area_map,
				"navContext": {
					"mode": "area",
					"rootMap": active_map,
					"areaStack": stack,
					"areaLabel": str((stack[stack.size() - 1] as Dictionary).get("label", "")),
				},
			}
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
# MOTEUR DE DÉS
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
