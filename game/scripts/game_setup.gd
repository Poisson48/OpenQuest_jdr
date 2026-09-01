extends Control

@onready var opt_scenario: OptionButton = %OptScenario
@onready var opt_mode: OptionButton = %OptMode
@onready var opt_gm: OptionButton = %OptGm
@onready var opt_main_char: OptionButton = %OptMainChar
@onready var spin_party_size: SpinBox = %SpinPartySize
@onready var bots_container: VBoxContainer = %BotsContainer
@onready var scenario_preview_lbl: RichTextLabel = %ScenarioPreview

var available_scenarios: Array = []
var available_chars: Array = []
var available_bots: Array = []
var selected_bot_ids: Array[String] = []
var _waiting_server_start: bool = false

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnStartGame.pressed.connect(_on_start_game_pressed)
	
	_setup_options()
	_populate_data()
	
	opt_scenario.item_selected.connect(_on_scenario_selected)
	spin_party_size.value_changed.connect(_on_party_size_changed)

func _setup_options() -> void:
	opt_mode.clear()
	opt_mode.add_item("Solo (Joueur + Bots éventuels)", 0)
	opt_mode.set_item_metadata(0, "solo")
	opt_mode.add_item("Multijoueur (Local / Réseau)", 1)
	opt_mode.set_item_metadata(1, "multi")
	
	opt_gm.clear()
	opt_gm.add_item("🤖 Maître du Jeu IA (Adaptatif)", 0)
	opt_gm.set_item_metadata(0, "ai")
	opt_gm.add_item("👤 Maître du Jeu Humain", 1)
	opt_gm.set_item_metadata(1, "human")

func _populate_data() -> void:
	available_scenarios = GameData.get_scenarios()
	available_chars = GameData.get_characters()
	available_bots = GameData.get_bots()
	
	opt_scenario.clear()
	var preselected_id: String = ""
	if get_tree().has_meta("preselected_scenario_id"):
		preselected_id = get_tree().get_meta("preselected_scenario_id")
		get_tree().remove_meta("preselected_scenario_id")
		
	var selected_idx := 0
	for i in range(available_scenarios.size()):
		var s: Dictionary = available_scenarios[i]
		var title: String = s.get("title", "Sans titre")
		var qf: String = s.get("questFormat", "oneshot")
		var icon := "⚔️" if qf == "oneshot" else ("🏰" if qf == "long" else "🔍")
		opt_scenario.add_item("%s %s" % [icon, title], i)
		opt_scenario.set_item_metadata(i, s.get("id"))
		if s.get("id") == preselected_id:
			selected_idx = i
			
	if not available_scenarios.is_empty():
		opt_scenario.selected = selected_idx
		_on_scenario_selected(selected_idx)
		
	opt_main_char.clear()
	for i in range(available_chars.size()):
		var c: Dictionary = available_chars[i]
		opt_main_char.add_item("%s (%s %s)" % [c.get("name"), c.get("race"), c.get("class")], i)
		opt_main_char.set_item_metadata(i, c.get("id"))
		
	_refresh_bots_checkboxes()

func _on_scenario_selected(idx: int) -> void:
	if idx < 0 or idx >= available_scenarios.size():
		scenario_preview_lbl.text = ""
		return
	var scn: Dictionary = available_scenarios[idx]
	var text := "[b]%s[/b]\n%s\n\n[color=#9a8870]Cadre : %s[/color]" % [
		scn.get("title", ""),
		scn.get("synopsis", ""),
		scn.get("setting", "")
	]
	scenario_preview_lbl.text = text

func _refresh_bots_checkboxes() -> void:
	for child in bots_container.get_children():
		child.queue_free()
		
	for b in available_bots:
		var check := CheckBox.new()
		check.text = "🤖 %s (%s %s) - %s" % [
			b.get("name", "Bot"),
			b.get("race", ""),
			b.get("class", ""),
			b.get("personality", "")
		]
		var bot_id: String = b.get("id", "")
		check.toggled.connect(func(toggled: bool):
			if toggled and not selected_bot_ids.has(bot_id):
				selected_bot_ids.append(bot_id)
			elif not toggled and selected_bot_ids.has(bot_id):
				selected_bot_ids.erase(bot_id)
		)
		bots_container.add_child(check)

func _on_party_size_changed(_val: float) -> void:
	pass

func _on_start_game_pressed() -> void:
	if available_scenarios.is_empty():
		return
	
	var scn_idx := opt_scenario.selected
	var scn_id: String = opt_scenario.get_item_metadata(scn_idx)
	var scn := GameData.get_scenario_by_id(scn_id)
	
	var mode_idx := opt_mode.selected
	var mode_val: String = opt_mode.get_item_metadata(mode_idx)
	
	var gm_idx := opt_gm.selected
	var gm_val: String = opt_gm.get_item_metadata(gm_idx)
	
	var party: Array = []
	
	# Ajout du personnage principal
	if not available_chars.is_empty() and opt_main_char.selected >= 0:
		var char_id: String = opt_main_char.get_item_metadata(opt_main_char.selected)
		var main_char := GameData.get_character_by_id(char_id)
		if not main_char.is_empty():
			var member := main_char.duplicate(true)
			member["isPlayer"] = true
			member["isHuman"] = true
			member["isBot"] = false
			party.append(member)
	else:
		# Personnage par défaut si aucun n'est créé
		var default_char := GameData.create_blank_character()
		default_char["name"] = "Aventurier"
		default_char["isPlayer"] = true
		default_char["isHuman"] = true
		default_char["isBot"] = false
		party.append(default_char)
		
	# Ajout des bots sélectionnés
	for bot_id in selected_bot_ids:
		var bot := GameData.get_bot_by_id(bot_id)
		if not bot.is_empty():
			var bot_member := bot.duplicate(true)
			bot_member["isPlayer"] = false
			bot_member["isHuman"] = false
			bot_member["isBot"] = true
			party.append(bot_member)
			
	var quest_format: String = scn.get("questFormat", "oneshot")
	var party_size := int(spin_party_size.value)
	var map_ids: Array = MapData.get_map_ids_for_scenario(scn_id, quest_format)
	map_ids = GameData.expand_map_ids_with_linked_locals(map_ids)
	
	if NetworkClient.is_server_connected():
		_waiting_server_start = true
		%BtnStartGame.disabled = true
		%BtnStartGame.text = "⏳ Lancement via serveur..."
		if not NetworkClient.game_started.is_connected(_on_server_game_started):
			NetworkClient.game_started.connect(_on_server_game_started, CONNECT_ONE_SHOT)
		if not NetworkClient.error_received.is_connected(_on_server_error):
			NetworkClient.error_received.connect(_on_server_error, CONNECT_ONE_SHOT)
		NetworkClient.start_game(scn_id, party, mode_val, gm_val, quest_format, party_size, map_ids)
		return
	
	_start_local_game(scn_id, mode_val, gm_val, quest_format, party, map_ids)

func _start_local_game(scn_id: String, mode_val: String, gm_val: String, quest_format: String, party: Array, map_ids: Array = []) -> void:
	GameData.create_new_game(scn_id, mode_val, gm_val, quest_format, party, map_ids)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _on_server_game_started(_game_id: String, state: Dictionary) -> void:
	_waiting_server_start = false
	%BtnStartGame.disabled = false
	%BtnStartGame.text = "🚀 Lancer l'Aventure !"
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _on_server_error(msg: String) -> void:
	if not _waiting_server_start:
		return
	_waiting_server_start = false
	%BtnStartGame.disabled = false
	%BtnStartGame.text = "🚀 Lancer l'Aventure !"
	push_warning("Serveur : %s — démarrage local" % msg)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
