extends Control

@onready var opt_quest_format: OptionButton = %OptQuestFormat
@onready var opt_scenario: OptionButton = %OptScenario
@onready var opt_mode: OptionButton = %OptMode
@onready var opt_gm: OptionButton = %OptGm
@onready var opt_main_char: OptionButton = %OptMainChar
@onready var spin_party_size: SpinBox = %SpinPartySize
@onready var bots_container: VBoxContainer = %BotsContainer
@onready var scenario_preview_lbl: RichTextLabel = %ScenarioPreview
@onready var joiner_panel: PanelContainer = %JoinerPanel
@onready var opt_joiner_char: OptionButton = %OptJoinerChar
@onready var maps_container: VBoxContainer = %MapsContainer
@onready var maps_hint_lbl: Label = %MapsHint

var available_scenarios: Array = []
var available_chars: Array = []
var available_bots: Array = []
var selected_bot_ids: Array[String] = []
var selected_map_ids: Array[String] = []
var _current_scenario_id: String = ""
var _current_quest_format: String = "oneshot"
var _waiting_server_start: bool = false
var _is_joiner: bool = false
var _is_pooling_joiner: bool = false
var _is_pooling_host: bool = false

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnStartGame.pressed.connect(_on_start_game_pressed)
	%BtnJoinerRegister.pressed.connect(_on_joiner_register_pressed)

	_setup_options()

	var preselected_format := ""
	var preselected_id := ""
	if get_tree().has_meta("preselected_quest_format"):
		preselected_format = str(get_tree().get_meta("preselected_quest_format"))
		get_tree().remove_meta("preselected_quest_format")
	if get_tree().has_meta("preselected_scenario_id"):
		preselected_id = str(get_tree().get_meta("preselected_scenario_id"))
		get_tree().remove_meta("preselected_scenario_id")

	if preselected_format.is_empty() and not preselected_id.is_empty():
		preselected_format = GameData.get_quest_format_for_scenario(preselected_id)
	if preselected_format.is_empty():
		preselected_format = "oneshot"

	_set_quest_format_option(preselected_format)
	_populate_data(preselected_id)

	opt_quest_format.item_selected.connect(_on_quest_format_selected)
	_update_net_panel()
	_apply_host_joiner_ui()

	opt_scenario.item_selected.connect(_on_scenario_selected)
	spin_party_size.value_changed.connect(_on_party_size_changed)
	NetworkClient.connected.connect(func(_id, _name): _update_net_panel())
	NetworkClient.disconnected.connect(_update_net_panel)
	NetworkClient.game_started.connect(_on_game_started_from_server)
	NetworkClient.lobby_updated.connect(_on_lobby_updated)
	NetworkClient.error_received.connect(_on_server_error)

	MultiplayerManager.game_started.connect(_on_pooling_game_started)
	MultiplayerManager.p2p_error.connect(_on_pooling_error)

func _setup_options() -> void:
	opt_quest_format.clear()
	opt_quest_format.add_item("📅 Campagne longue", 0)
	opt_quest_format.set_item_metadata(0, "long")
	opt_quest_format.add_item("⚡ One-shot", 1)
	opt_quest_format.set_item_metadata(1, "oneshot")
	opt_quest_format.add_item("🔍 Mode enquête", 2)
	opt_quest_format.set_item_metadata(2, "investigation")

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

func _set_quest_format_option(quest_format: String) -> void:
	for i in range(opt_quest_format.item_count):
		if opt_quest_format.get_item_metadata(i) == quest_format:
			opt_quest_format.selected = i
			_current_quest_format = quest_format
			return
	opt_quest_format.selected = 1
	_current_quest_format = "oneshot"

func _get_quest_format() -> String:
	if opt_quest_format.selected >= 0:
		return str(opt_quest_format.get_item_metadata(opt_quest_format.selected))
	return _current_quest_format

func _populate_data(preselected_id: String = "") -> void:
	_refresh_for_quest_format(true)

	if preselected_id.is_empty():
		return

	for i in range(opt_scenario.item_count):
		if opt_scenario.get_item_metadata(i) == preselected_id:
			opt_scenario.selected = i
			_on_scenario_selected(i)
			return

func _on_quest_format_selected(_idx: int) -> void:
	_current_quest_format = _get_quest_format()
	_refresh_for_quest_format(true)

func _refresh_for_quest_format(reset_selection: bool = false) -> void:
	_current_quest_format = _get_quest_format()
	available_scenarios = GameData.get_scenarios_for_quest_format(_current_quest_format)
	available_chars = GameData.get_characters_for_quest_format(_current_quest_format)
	available_bots = GameData.get_bots_for_quest_format(_current_quest_format)

	if reset_selection:
		selected_bot_ids.clear()

	_refresh_scenario_options(reset_selection)
	_refresh_char_options()
	_refresh_bots_checkboxes()
	_refresh_maps_picker(reset_selection)

func _refresh_scenario_options(reset_selection: bool) -> void:
	var previous_id := ""
	if opt_scenario.selected >= 0:
		previous_id = str(opt_scenario.get_item_metadata(opt_scenario.selected))

	opt_scenario.clear()
	var selected_idx := 0
	for i in range(available_scenarios.size()):
		var s: Dictionary = available_scenarios[i]
		var title: String = s.get("title", "Sans titre")
		var qf: String = s.get("questFormat", "oneshot")
		var icon := "⚔️" if qf == "oneshot" else ("🏰" if qf == "long" else "🔍")
		opt_scenario.add_item("%s %s" % [icon, title], i)
		opt_scenario.set_item_metadata(i, s.get("id"))
		if s.get("id") == previous_id:
			selected_idx = i

	if available_scenarios.is_empty():
		scenario_preview_lbl.text = "[color=#9a8870]Aucun scénario pour ce format — crée-en un dans le Hub.[/color]"
		_current_scenario_id = ""
		return

	if reset_selection or previous_id.is_empty() or not _scenario_id_in_list(previous_id):
		selected_idx = 0

	opt_scenario.selected = selected_idx
	_on_scenario_selected(selected_idx)

func _scenario_id_in_list(scenario_id: String) -> bool:
	for s in available_scenarios:
		if s.get("id") == scenario_id:
			return true
	return false

func _refresh_char_options() -> void:
	var previous_id := ""
	if opt_main_char.selected >= 0 and opt_main_char.item_count > 0:
		previous_id = str(opt_main_char.get_item_metadata(opt_main_char.selected))

	opt_main_char.clear()
	opt_joiner_char.clear()
	for i in range(available_chars.size()):
		var c: Dictionary = available_chars[i]
		var prefix := "🔍 " if _current_quest_format == "investigation" else ""
		var label := "%s%s (%s %s)" % [prefix, c.get("name"), c.get("race"), c.get("class")]
		opt_main_char.add_item(label, i)
		opt_main_char.set_item_metadata(i, c.get("id"))
		opt_joiner_char.add_item(label, i)
		opt_joiner_char.set_item_metadata(i, c.get("id"))

	if available_chars.is_empty():
		opt_main_char.add_item("Aucun personnage — crée-en un dans le Hub", 0)
		opt_main_char.set_item_metadata(0, "")
		opt_main_char.selected = 0
		opt_joiner_char.add_item("Aventurier (par défaut)", 0)
		opt_joiner_char.set_item_metadata(0, "")
		opt_joiner_char.selected = 0
		return

	var selected_idx := 0
	for i in range(opt_main_char.item_count):
		if opt_main_char.get_item_metadata(i) == previous_id:
			selected_idx = i
			break
	opt_main_char.selected = selected_idx
	opt_joiner_char.selected = selected_idx


func _apply_host_joiner_ui() -> void:
	_is_pooling_host = (
		MultiplayerManager.is_in_room()
		and MultiplayerManager.is_game_master()
		and MultiplayerManager.is_p2p_active()
	)
	_is_pooling_joiner = (
		MultiplayerManager.is_in_room()
		and not MultiplayerManager.is_game_master()
		and MultiplayerManager.is_p2p_active()
	)
	_is_joiner = (NetworkClient.is_server_connected() and not NetworkClient.is_host()) or _is_pooling_joiner
	joiner_panel.visible = _is_joiner
	if _is_joiner:
		%BtnStartGame.visible = false
		opt_scenario.disabled = true
		opt_mode.disabled = true
		opt_gm.disabled = true
		spin_party_size.editable = false
		for child in bots_container.get_children():
			child.disabled = true
		if _is_pooling_joiner:
			%LblJoinerHint.text = "En attente que le MJ lance la partie (P2P)..."
		else:
			%LblJoinerHint.text = "En attente que l'hôte lance la partie. Confirmez votre personnage ci-dessous."
	elif _is_pooling_host:
		%BtnStartGame.visible = true
		%BtnStartGame.text = "🚀 Lancer l'Aventure (P2P) !"
	else:
		%BtnStartGame.visible = true
		%BtnStartGame.text = "🚀 Lancer l'Aventure !"

func _on_lobby_updated(_host_id: String, _players: Array) -> void:
	_apply_host_joiner_ui()
	_update_net_panel()

func _on_scenario_selected(idx: int) -> void:
	if idx < 0 or idx >= available_scenarios.size():
		scenario_preview_lbl.text = ""
		_refresh_maps_picker(true)
		return
	var scn: Dictionary = available_scenarios[idx]
	var scn_id: String = scn.get("id", "")
	var reset_maps := scn_id != _current_scenario_id
	_current_scenario_id = scn_id
	var text := "[b]%s[/b]\n%s\n\n[color=#9a8870]Cadre : %s[/color]" % [
		scn.get("title", ""),
		scn.get("synopsis", ""),
		scn.get("setting", "")
	]
	scenario_preview_lbl.text = text
	_refresh_maps_picker(reset_maps)

func _refresh_maps_picker(reset_selection: bool = false) -> void:
	for child in maps_container.get_children():
		child.queue_free()

	if opt_scenario.selected < 0 or available_scenarios.is_empty():
		maps_hint_lbl.text = "Choisis d'abord un scénario."
		return

	var scn_id: String = opt_scenario.get_item_metadata(opt_scenario.selected)
	var quest_format: String = _get_quest_format()

	if reset_selection or selected_map_ids.is_empty():
		selected_map_ids.clear()
		for map_id in MapData.get_default_selected_map_ids(scn_id, quest_format):
			selected_map_ids.append(str(map_id))

	var pool: Array = MapData.get_setup_map_pool(scn_id, quest_format)
	if pool.is_empty():
		maps_hint_lbl.text = "Aucune carte pour ce mode et ce scénario — crée-en une dans le Hub (onglet Cartes)."
		return

	maps_hint_lbl.text = "Cartes compatibles avec ce mode et ce scénario uniquement."

	var world_maps: Array = []
	var local_maps: Array = []
	for m in pool:
		if MapData.is_world_map(m):
			world_maps.append(m)
		else:
			local_maps.append(m)

	if not world_maps.is_empty():
		_add_map_group("🌍 Cartes du monde", world_maps, scn_id)
	if not local_maps.is_empty():
		var group_title := "🔍 Scènes enquête" if quest_format == "investigation" else "⚔️ Scènes locales"
		_add_map_group(group_title, local_maps, scn_id)

	var valid_ids: Array = pool.map(func(m): return m.get("id", ""))
	selected_map_ids = selected_map_ids.filter(func(id): return valid_ids.has(id))

func _add_map_group(title: String, map_list: Array, scenario_id: String) -> void:
	var header := Label.new()
	header.text = title
	header.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	header.add_theme_font_size_override("font_size", 13)
	maps_container.add_child(header)

	for m in map_list:
		var map_id: String = m.get("id", "")
		var check := CheckBox.new()
		var tag := "🌍" if MapData.is_world_map(m) else ("🔍" if m.get("roster") == "investigation" else "⚔️")
		var linked := " · liée au scénario" if m.get("scenarioId", "") == scenario_id else ""
		check.text = "%s %s (%d×%d%s)" % [
			tag,
			m.get("title", map_id),
			int(m.get("width", 0)),
			int(m.get("height", 0)),
			linked,
		]
		check.button_pressed = selected_map_ids.has(map_id)
		check.toggled.connect(func(toggled: bool):
			if toggled and not selected_map_ids.has(map_id):
				selected_map_ids.append(map_id)
			elif not toggled and selected_map_ids.has(map_id):
				selected_map_ids.erase(map_id)
		)
		maps_container.add_child(check)

func _get_selected_map_ids() -> Array:
	return selected_map_ids.duplicate()

func _refresh_bots_checkboxes() -> void:
	for child in bots_container.get_children():
		child.queue_free()

	var valid_bot_ids: Array = available_bots.map(func(b): return b.get("id", ""))
	selected_bot_ids = selected_bot_ids.filter(func(id): return valid_bot_ids.has(id))

	for b in available_bots:
		var check := CheckBox.new()
		var prefix := "🔍🤖 " if _current_quest_format == "investigation" else "🤖 "
		check.text = "%s%s (%s %s) - %s" % [
			prefix,
			b.get("name", "Bot"),
			b.get("race", ""),
			b.get("class", ""),
			b.get("personality", "")
		]
		var bot_id: String = b.get("id", "")
		check.button_pressed = selected_bot_ids.has(bot_id)
		check.toggled.connect(func(toggled: bool):
			if toggled and not selected_bot_ids.has(bot_id):
				selected_bot_ids.append(bot_id)
			elif not toggled and selected_bot_ids.has(bot_id):
				selected_bot_ids.erase(bot_id)
		)
		bots_container.add_child(check)

func _on_party_size_changed(_val: float) -> void:
	pass

func _build_character_from_option(opt: OptionButton) -> Dictionary:
	if opt.item_count == 0 or opt.selected < 0:
		var blank := GameData.create_blank_character()
		if MultiplayerManager.is_in_room():
			blank["name"] = MultiplayerManager.player_name
		elif NetworkClient.is_server_connected():
			blank["name"] = NetworkClient.player_name
		else:
			blank["name"] = "Aventurier"
		blank["isPlayer"] = true
		blank["isHuman"] = true
		blank["isBot"] = false
		if MultiplayerManager.is_in_room():
			blank["clientId"] = MultiplayerManager.player_id
		return blank
	var char_id: String = opt.get_item_metadata(opt.selected)
	var main_char := GameData.get_character_by_id(char_id)
	if main_char.is_empty():
		return _build_character_from_option(OptionButton.new())
	var member := main_char.duplicate(true)
	member["isPlayer"] = true
	member["isHuman"] = true
	member["isBot"] = false
	if MultiplayerManager.is_in_room():
		member["clientId"] = MultiplayerManager.player_id
	return member

func _on_joiner_register_pressed() -> void:
	if not NetworkClient.is_server_connected():
		return
	NetworkClient.register_character(_build_character_from_option(opt_joiner_char))
	%LblJoinerHint.text = "✓ Personnage enregistré — en attente du lancement par l'hôte."

func _on_start_game_pressed() -> void:
	if _is_joiner:
		return
	if available_scenarios.is_empty():
		return

	var scn_idx := opt_scenario.selected
	var scn_id: String = opt_scenario.get_item_metadata(scn_idx)

	var mode_idx := opt_mode.selected
	var mode_val: String = opt_mode.get_item_metadata(mode_idx)

	var gm_idx := opt_gm.selected
	var gm_val: String = opt_gm.get_item_metadata(gm_idx)

	var quest_format: String = _get_quest_format()
	var valid_bot_ids: Array = available_bots.map(func(b): return b.get("id", ""))

	var party: Array = []

	if not available_chars.is_empty() and opt_main_char.selected >= 0:
		var char_id: String = opt_main_char.get_item_metadata(opt_main_char.selected)
		if not char_id.is_empty():
			var main_char := GameData.get_character_by_id(char_id)
			if not main_char.is_empty() and GameData.is_character_valid_for_format(main_char, quest_format):
				var member := main_char.duplicate(true)
				member["isPlayer"] = true
				member["isHuman"] = true
				member["isBot"] = false
				if MultiplayerManager.is_in_room():
					member["clientId"] = MultiplayerManager.player_id
				party.append(member)
	if party.is_empty():
		party.append(_build_character_from_option(opt_main_char))

	for bot_id in selected_bot_ids:
		if not valid_bot_ids.has(bot_id):
			continue
		var bot := GameData.get_bot_by_id(bot_id)
		if bot.is_empty() or not GameData.is_bot_valid_for_format(bot, quest_format):
			continue
		var bot_member := bot.duplicate(true)
		bot_member["isPlayer"] = false
		bot_member["isHuman"] = false
		bot_member["isBot"] = true
		party.append(bot_member)

	var party_size := int(spin_party_size.value)

	var map_ids: Array = _get_selected_map_ids()
	var valid_map_pool: Array = MapData.get_setup_map_pool(scn_id, quest_format).map(func(m): return m.get("id", ""))
	map_ids = map_ids.filter(func(id): return valid_map_pool.has(id))
	if map_ids.is_empty():
		map_ids = MapData.get_default_selected_map_ids(scn_id, quest_format)
	map_ids = GameData.expand_map_ids_with_linked_locals(map_ids)

	if _is_pooling_host or (MultiplayerManager.is_p2p_host() and get_tree().has_meta("pooling_p2p_host")):
		get_tree().remove_meta("pooling_p2p_host")
		party[0]["clientId"] = MultiplayerManager.player_id
		MultiplayerManager.register_character(party[0])
		_waiting_server_start = true
		%BtnStartGame.disabled = true
		%BtnStartGame.text = "⏳ Lancement P2P..."
		MultiplayerManager.client_request_start_game(scn_id, party, mode_val, gm_val, quest_format, party_size, map_ids)
		return


	if NetworkClient.is_server_connected():
		NetworkClient.register_character(party[0])
		_waiting_server_start = true
		%BtnStartGame.disabled = true
		%BtnStartGame.text = "⏳ Lancement via serveur..."
		if not NetworkClient.game_started.is_connected(_on_game_started_from_server):
			NetworkClient.game_started.connect(_on_game_started_from_server, CONNECT_ONE_SHOT)
		if not NetworkClient.error_received.is_connected(_on_server_error):
			NetworkClient.error_received.connect(_on_server_error, CONNECT_ONE_SHOT)
		NetworkClient.start_game(scn_id, party, mode_val, gm_val, quest_format, party_size, map_ids)
		return

	_start_local_game(scn_id, mode_val, gm_val, quest_format, party, map_ids)

func _start_local_game(scn_id: String, mode_val: String, gm_val: String, quest_format: String, party: Array, map_ids: Array = []) -> void:
	GameData.create_new_game(scn_id, mode_val, gm_val, quest_format, party, map_ids)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _update_net_panel() -> void:
	if not has_node("%NetStatusLabel"):
		return
	if MultiplayerManager.is_p2p_active() and MultiplayerManager.is_in_room():
		var role := "MJ (hôte P2P)" if MultiplayerManager.is_p2p_host() else "joueur P2P"
		%NetStatusLabel.text = "● Pooling P2P — salon %s (%s)" % [MultiplayerManager.room_code, role]
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	elif NetworkClient.is_server_connected():
		var role := "hôte" if NetworkClient.is_host() else "invité"
		%NetStatusLabel.text = "● Serveur (%s) : %s" % [role, NetworkClient.server_url]
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		%NetStatusLabel.text = "○ Serveur non connecté — configurez l'URL depuis le menu principal"
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)

func _on_game_started_from_server(_game_id: String, state: Dictionary) -> void:
	_waiting_server_start = false
	%BtnStartGame.disabled = false
	%BtnStartGame.text = "🚀 Lancer l'Aventure !"
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _on_pooling_game_started(_game_id: String, state: Dictionary) -> void:
	_waiting_server_start = false
	%BtnStartGame.disabled = false
	%BtnStartGame.text = "🚀 Lancer l'Aventure (P2P) !"
	GameData.apply_server_state(state)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _on_pooling_error(message: String) -> void:
	if _waiting_server_start:
		_waiting_server_start = false
		%BtnStartGame.disabled = false
		%BtnStartGame.text = "🚀 Lancer l'Aventure (P2P) !"
	net_status_lbl_fallback(message)

func _on_server_error(msg: String) -> void:
	if _waiting_server_start:
		_waiting_server_start = false
		%BtnStartGame.disabled = false
		%BtnStartGame.text = "🚀 Lancer l'Aventure !"
	net_status_lbl_fallback(msg)

func net_status_lbl_fallback(msg: String) -> void:
	if has_node("%NetStatusLabel"):
		%NetStatusLabel.text = msg
		%NetStatusLabel.add_theme_color_override("font_color", ThemeColors.DANGER)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

