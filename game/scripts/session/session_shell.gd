extends Control

## Coquille de la session de jeu.
##
## Elle ne dessine rien : `scenes/session/session.tscn` porte la structure et
## instancie les panneaux. Ce script se contente de brancher les panneaux sur
## le `SessionViewModel`, de router leurs signaux et de déléguer la géométrie à
## `SessionLayout`.

const PlayerHudScene = preload("res://scenes/session/panels/player_hud.tscn")
const CharacterSheetScene = preload("res://scenes/session/panels/character_sheet.tscn")

@onready var _margins: MarginContainer = %Margins
@onready var _header: SessionHeaderPanel = %SessionHeader
@onready var _body: HSplitContainer = %Body
@onready var _inner: HSplitContainer = %InnerSplit
@onready var _left_dock: VBoxContainer = %LeftDock
@onready var _right_dock: VBoxContainer = %RightDock
@onready var _party: PartyDockPanel = %PartyDock
@onready var _gm_tabs: TabContainer = %GmTabs
@onready var _console: GmConsolePanel = %Console
@onready var _notes: GmNotesPanel = %Notes
@onready var _map: MapWorkspacePanel = %MapWorkspace
@onready var _log: StoryLogPanel = %StoryLog
@onready var _dice: DiceTrayPanel = %DiceTray
@onready var _action: ActionBarPanel = %ActionBar
@onready var _confirm: ConfirmationDialog = %ConfirmDialog
@onready var _character_sheet: CharacterSheet = %CharacterSheet
@onready var _player_hud_node: PlayerSessionHud = %PlayerHud
@onready var _speaker_dialogue: Node = get_node_or_null("%SpeakerDialogue")

var model: SessionViewModel = null
var layout: SessionLayout = null

var _player_hud: PlayerSessionHud = null
var _started_msec: int = 0
var _elapsed: int = -1
var _preview_player_view: bool = false

func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	if not GameData.has_active_game():
		_create_fallback_game()

	layout = SessionLayout.new()
	layout.configure(self, _margins, _header, _body, _inner, _left_dock, _map, _right_dock)

	model = SessionViewModel.new()
	_connect_model()
	_connect_panels()
	model.bind()
	model.refresh(true)

func _exit_tree() -> void:
	if model != null:
		model.unbind()

func _process(_delta: float) -> void:
	var seconds := int((Time.get_ticks_msec() - _started_msec) / 1000.0)
	if seconds != _elapsed:
		_elapsed = seconds
		_header.set_elapsed(seconds)

# ---------------------------------------------------------------------------
# Branchements
# ---------------------------------------------------------------------------

func _connect_model() -> void:
	model.header_changed.connect(_header.set_header)
	model.party_changed.connect(_on_party_changed)
	model.turn_changed.connect(_on_turn_changed)
	model.net_changed.connect(_header.set_net)
	model.log_reset.connect(_on_log_reset)
	model.log_appended.connect(_on_log_appended)
	model.navigation_changed.connect(_on_navigation_changed)
	model.map_changed.connect(_on_map_changed)
	model.role_changed.connect(_on_role_changed)
	model.dice_result.connect(_dice.set_result)
	model.notes_changed.connect(_notes.set_text)

func _connect_panels() -> void:
	_header.leave_pressed.connect(_on_leave_pressed)
	_header.docks_toggled.connect(func(shown: bool): layout.set_left_dock_visible(shown))
	_header.preview_toggled.connect(_on_preview_toggled)

	_party.member_activated.connect(_open_character_sheet)

	_console.narrate_requested.connect(func(text: String): model.narrate(text))
	_console.npc_line_requested.connect(func(npc: String, text: String): model.npc_line(npc, text))
	_console.scene_requested.connect(func(scene_id: String): model.go_to_scene(scene_id))
	_console.turn_advance_requested.connect(func(): model.advance_turn())
	_console.advance_requested.connect(func(): model.advance_scene())
	_console.complete_requested.connect(_on_complete_pressed)

	_notes.notes_changed.connect(func(text: String): model.set_notes(text))

	_dice.roll_requested.connect(func(formula: String, secret: bool): model.roll(formula, secret))
	_action.action_submitted.connect(func(text: String): model.submit_action(text))
	if _map.has_signal("speaker_focus_requested"):
		_map.speaker_focus_requested.connect(func(npc: String): _console.select_npc(npc))

	if _player_hud_node != null:
		_player_hud = _player_hud_node
		_player_hud.visible = false
		_player_hud.leave_pressed.connect(_on_leave_pressed)
		_player_hud.open_character.connect(_open_character_sheet)
		_player_hud.action_submitted.connect(func(text: String): model.submit_action(text))
		_player_hud.roll_requested.connect(func(formula: String): model.roll(formula, false))

# ---------------------------------------------------------------------------
# Réactions au modèle
# ---------------------------------------------------------------------------

func _on_log_reset(entries: Array) -> void:
	_log.reset(entries)
	if _player_hud != null and _player_hud.visible and _player_hud.has_method("reset_log"):
		_player_hud.reset_log(entries)

func _on_log_appended(entry: Dictionary) -> void:
	_log.append(entry)
	if _player_hud != null and _player_hud.visible and _player_hud.has_method("append_log"):
		_player_hud.append_log(entry)
	_maybe_show_speech(entry)

func _on_party_changed(members: Array, active_id: String) -> void:
	_party.set_party(members, active_id)
	_refresh_player_hud_identity(members)

func _on_turn_changed(turn: Dictionary) -> void:
	_action.set_turn(turn)
	if _player_hud != null and _player_hud.visible and _player_hud.has_method("set_turn"):
		_player_hud.set_turn(turn)

func _refresh_player_hud_identity(members: Array = []) -> void:
	if _player_hud == null or not _player_hud.visible:
		return
	var party: Array = members
	if party.is_empty():
		party = GameData.active_game.get("party", [])
	var me := MultiplayerManager.get_my_party_member(GameData.active_game)
	if me.is_empty():
		# Solo / fallback : premier humain local
		for m in party:
			if typeof(m) == TYPE_DICTIONARY and (m.get("isHuman", false) or m.get("isPlayer", false)):
				me = m
				break
	var my_id := str(me.get("id", ""))
	_player_hud.set_me(me)
	_player_hud.set_party(party, my_id)

func _on_navigation_changed(nav: Dictionary) -> void:
	_console.set_npcs(nav.get("npcs", []))
	_console.set_navigation(nav)
	_console.set_waiting(bool(nav.get("waiting", false)))

func _on_map_changed() -> void:
	_map.refresh()

func _on_role_changed(role: SessionRoleView) -> void:
	var gm_view := role.kind == SessionRoleView.KIND_GM

	_header.set_role(role)
	_party.set_context(role.client_id, role.human_gm)
	_gm_tabs.visible = gm_view
	_console.set_enabled(role.can_narrate)
	_notes.set_scene_label(str(GameData.get_current_scene().get("title", "")))
	_dice.set_enabled(role.can_roll)
	_dice.set_secret_available(role.can_roll_secret)
	var proxy := bool(GameData.active_game.get("allowGmProxyActions", false))
	_action.set_player_controls_visible((not gm_view or proxy) and not role.completed)
	_action.set_enabled(role.can_submit_action)
	if _player_hud != null and _player_hud.has_method("set_enabled"):
		_player_hud.set_enabled(role.can_submit_action)
	_map.set_gm_view(role.can_see_hidden_map)

	_apply_immersive(role.immersive)
	if role.immersive and _player_hud != null:
		_refresh_player_hud_identity()
	if not role.immersive:
		_header.set_docks_shown(layout.left_visible_pref)

func _apply_immersive(immersive: bool) -> void:
	layout.apply_preset(
		SessionLayout.PRESET_IMMERSIVE if immersive else SessionLayout.PRESET_GM
	)
	_map.set_immersive(immersive)
	# Le HUD joueur porte son propre journal : on masque le dock GM.
	if immersive:
		_right_dock.visible = false
		_action.visible = false
	else:
		_right_dock.visible = true
		_action.visible = true
	if immersive:
		_ensure_player_hud()
	if _player_hud != null:
		_player_hud.visible = immersive
		if immersive:
			_player_hud.set_title(GameData.get_scenario_display_title())
			_refresh_player_hud_identity()
			if _player_hud.has_method("reset_log"):
				_player_hud.reset_log(GameData.active_game.get("log", []))
			if model != null and _player_hud.has_method("set_turn"):
				# Rejoue le dernier état de tour via refresh partiel
				pass

func _maybe_show_speech(entry: Dictionary) -> void:
	var kind := str(entry.get("type", "player"))
	if kind == "system" or kind == "dice":
		return
	var speaker := str(entry.get("author", entry.get("speaker", "")))
	var text := str(entry.get("text", ""))
	if speaker.is_empty() or text.strip_edges().is_empty():
		return
	# Bulle sur la carte (PNJ surtout).
	if kind == "npc":
		_map.show_npc_speech(speaker, text)
	# Dialogue cinématique pour tous les locuteurs parlants.
	if _speaker_dialogue != null and _speaker_dialogue.has_method("enqueue"):
		var art := GameData.resolve_speaker_art(speaker, kind)
		_speaker_dialogue.enqueue(speaker, text, kind, art)
	# Centre la caméra sur le locuteur si possible.
	if _map.has_method("focus_speaker"):
		_map.focus_speaker(speaker)

# ---------------------------------------------------------------------------
# Actions de la coquille
# ---------------------------------------------------------------------------

func _on_preview_toggled(active: bool) -> void:
	_preview_player_view = active
	_map.set_player_preview(active)

func _on_complete_pressed() -> void:
	_ask_confirm(
		"Clore l'aventure ?",
		"Cette action est définitive : la session passera en statut terminé.",
		func(): model.complete_scenario()
	)

func _on_leave_pressed() -> void:
	_ask_confirm(
		"Quitter la session ?",
		"Vous quittez la table et retournez au hub.",
		func():
			_notes.flush_now()
			get_tree().change_scene_to_file("res://scenes/hub.tscn")
	)

func _ask_confirm(title: String, body: String, on_ok: Callable) -> void:
	for connection in _confirm.confirmed.get_connections():
		_confirm.confirmed.disconnect(connection.callable)
	_confirm.title = title
	_confirm.dialog_text = body
	_confirm.confirmed.connect(on_ok, CONNECT_ONE_SHOT)
	_confirm.popup_centered()

func _open_character_sheet(member: Dictionary) -> void:
	# Toujours la fiche à jour (inventaire sync réseau).
	var fresh := member.duplicate(true)
	var mid := str(member.get("id", ""))
	if not mid.is_empty():
		for m in GameData.active_game.get("party", []):
			if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) == mid:
				fresh = m.duplicate(true)
				break
	if _character_sheet == null:
		_character_sheet = CharacterSheetScene.instantiate()
		add_child(_character_sheet)
	_character_sheet.open(fresh)
	if _character_sheet.get_parent() == self:
		_character_sheet.move_to_front()

func _ensure_player_hud() -> void:
	if _player_hud != null:
		return
	_player_hud = _player_hud_node
	if _player_hud == null:
		_player_hud = PlayerHudScene.instantiate()
		add_child(_player_hud)
		_player_hud.leave_pressed.connect(_on_leave_pressed)
		_player_hud.open_character.connect(_open_character_sheet)
		_player_hud.action_submitted.connect(func(text: String): model.submit_action(text))
		_player_hud.roll_requested.connect(func(formula: String): model.roll(formula, false))

func _create_fallback_game() -> void:
	var scenarios: Array = GameData.get_scenarios()
	var scenario_id: String = str(scenarios[0].get("id", "demo-crypte")) if not scenarios.is_empty() else "demo-crypte"
	GameData.create_new_game(scenario_id, "solo", "ai", "oneshot", [
		{ "id": "char-fallback-1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse",
			"hp": 12, "ac": 14, "isPlayer": true, "isBot": false },
		{ "id": "bot-fallback-1", "name": "Kael", "race": "Nain", "class": "Guerrier",
			"hp": 14, "ac": 16, "isPlayer": false, "isBot": true },
	])

# ---------------------------------------------------------------------------
# Surface de test — les tests interrogent l'état par ici, jamais par des
# chemins de nœuds.
# ---------------------------------------------------------------------------

func is_immersive() -> bool:
	return layout != null and layout.is_immersive()

func get_panel(id: String) -> Control:
	match id:
		"header": return _header
		"party": return _party
		"console": return _console
		"notes": return _notes
		"map": return _map
		"log": return _log
		"dice": return _dice
		"action": return _action
		"left_dock": return _left_dock
		"right_dock": return _right_dock
		_: return null

func get_player_hud() -> Control:
	return _player_hud

func describe() -> Dictionary:
	var report := layout.describe()
	report["role"] = model.role.kind if model != null and model.role != null else ""
	report["gm_tabs_visible"] = _gm_tabs.visible
	report["log_size"] = _log.size
	report["dice_size"] = _dice.size
	report["action_size"] = _action.size
	report["party_size"] = _party.size
	report["hud_visible"] = _player_hud != null and _player_hud.visible
	report["preview_player_view"] = _preview_player_view
	report["map"] = _map.describe()
	report["waiting_for_gm"] = GameData.is_waiting_for_gm()
	report["turn_index"] = int(GameData.active_game.get("turnIndex", 0))
	report["turn_headline"] = _action.get_node("%LblTurn").text if _action != null else ""
	report["next_turn_visible"] = _console.get_node("%BtnNextTurn").visible if _console != null else false
	return report

# ---------------------------------------------------------------------------
# Pilotage UI (simulateur) — clique les vrais contrôles
# ---------------------------------------------------------------------------

func ui_fill_action(text: String) -> void:
	_action.set_player_controls_visible(true)
	_action.set_enabled(true)
	_action.fill(text)

func ui_send_action() -> void:
	_action.get_node("%BtnSend").pressed.emit()

func ui_narrate(text: String) -> void:
	_console.get_node("%NarrationInput").text = text
	_console.get_node("%BtnNarrate").pressed.emit()

func ui_npc_line(npc_name: String, text: String) -> void:
	_console.select_npc(npc_name)
	_console.get_node("%NpcInput").text = text
	_console.get_node("%BtnNpc").pressed.emit()

func ui_next_turn() -> void:
	_console.get_node("%BtnNextTurn").pressed.emit()

func ui_goto_scene(scene_id: String) -> void:
	var picker: OptionButton = _console.get_node("%ScenePicker")
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i)) == scene_id:
			picker.select(i)
			break
	_console.get_node("%BtnGoto").pressed.emit()

func ui_press_transition(to_scene_id: String) -> bool:
	var list: VBoxContainer = _console.get_node("%TransitionList")
	for child in list.get_children():
		if not (child is Button):
			continue
		var btn: Button = child
		var tip := ("%s %s" % [btn.tooltip_text, btn.text]).to_lower()
		if tip.contains(to_scene_id.to_lower()):
			btn.pressed.emit()
			return true
	_console.scene_requested.emit(to_scene_id)
	return true

func ui_roll_d20() -> void:
	var row: HBoxContainer = _dice.get_node("%QuickRow")
	for child in row.get_children():
		if child is Button and str(child.text).to_lower().contains("d20"):
			(child as Button).pressed.emit()
			return
	_dice.get_node("%FormulaInput").text = "1d20"
	_dice.get_node("%BtnRoll").pressed.emit()

func ui_open_member_sheet(member_id: String) -> void:
	for member_variant in GameData.active_game.get("party", []):
		if typeof(member_variant) != TYPE_DICTIONARY:
			continue
		var member: Dictionary = member_variant
		if str(member.get("id", "")) == member_id:
			_open_character_sheet(member)
			return

func ui_close_sheet() -> void:
	if _character_sheet != null and _character_sheet.visible:
		_character_sheet.close()

func ui_confirm_if_open() -> void:
	if _confirm == null:
		return
	if not (_confirm.visible or _confirm.is_visible_in_tree()):
		return
	var ok := _confirm.get_ok_button()
	if ok != null:
		ok.pressed.emit()
	else:
		_confirm.confirmed.emit()

func ui_complete() -> void:
	_console.get_node("%BtnComplete").pressed.emit()
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	ui_confirm_if_open()
	await get_tree().create_timer(0.25).timeout
	ui_confirm_if_open()

func ui_set_night(enabled: bool, ambient: float = 0.14) -> void:
	GameData.set_session_night(enabled, ambient)
	if model != null:
		model.refresh(true)
	var map = get_panel("map")
	if map != null and map.has_method("refresh"):
		map.refresh()
