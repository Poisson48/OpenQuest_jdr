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
	model.party_changed.connect(_party.set_party)
	model.turn_changed.connect(_action.set_turn)
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
	_push_toast()

func _on_log_appended(entry: Dictionary) -> void:
	_log.append(entry)
	_push_toast()
	_maybe_show_speech(entry)

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
	_action.set_player_controls_visible(not gm_view and not role.completed)
	_action.set_enabled(role.can_submit_action)
	_map.set_gm_view(role.can_see_hidden_map)

	_apply_immersive(role.immersive)
	if not role.immersive:
		_header.set_docks_shown(layout.left_visible_pref)

func _apply_immersive(immersive: bool) -> void:
	layout.apply_preset(
		SessionLayout.PRESET_IMMERSIVE if immersive else SessionLayout.PRESET_GM
	)
	_map.set_immersive(immersive)
	if immersive:
		_ensure_player_hud()
	if _player_hud != null:
		_player_hud.visible = immersive
		if immersive:
			_player_hud.set_title(GameData.get_scenario_display_title())
			_player_hud.set_party(GameData.active_game.get("party", []))
			_push_toast()

func _push_toast() -> void:
	if _player_hud != null and _player_hud.visible:
		_player_hud.show_toast(_log.latest_line())

func _maybe_show_speech(entry: Dictionary) -> void:
	if str(entry.get("type", "")) != "npc":
		return
	var speaker := str(entry.get("author", entry.get("speaker", "PNJ")))
	var text := str(entry.get("text", ""))
	_map.show_npc_speech(speaker, text)

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
	if _character_sheet == null:
		_character_sheet = CharacterSheetScene.instantiate()
		add_child(_character_sheet)
	_character_sheet.open(member)

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
