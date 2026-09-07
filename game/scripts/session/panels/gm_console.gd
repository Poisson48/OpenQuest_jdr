extends PanelContainer
class_name GmConsolePanel

## Console du MJ : parler, faire parler, avancer l'histoire.
## Structure dans `scenes/session/panels/gm_console.tscn` — les commandes de fin
## de scène y sont ancrées hors zone de défilement pour rester atteignables.

signal narrate_requested(text: String)
signal npc_line_requested(npc_name: String, text: String)
signal scene_requested(scene_id: String)
signal turn_advance_requested
signal advance_requested
signal complete_requested

const CUSTOM_NPC := "__custom__"

@onready var _alert: PanelContainer = %AlertBanner
@onready var _btn_next_turn: Button = %BtnNextTurn
@onready var _narration: TextEdit = %NarrationInput
@onready var _btn_narrate: Button = %BtnNarrate
@onready var _npc_picker: OptionButton = %NpcPicker
@onready var _npc_line: TextEdit = %NpcInput
@onready var _btn_npc: Button = %BtnNpc
@onready var _scene_picker: OptionButton = %ScenePicker
@onready var _btn_goto: Button = %BtnGoto
@onready var _transitions: VBoxContainer = %TransitionList
@onready var _btn_advance: Button = %BtnAdvance
@onready var _btn_complete: Button = %BtnComplete

var _enabled: bool = true

func _ready() -> void:
	_narration.gui_input.connect(_on_narration_input)
	_npc_line.gui_input.connect(_on_npc_input)
	_btn_narrate.pressed.connect(_emit_narration)
	_btn_npc.pressed.connect(_emit_npc_line)
	_btn_goto.pressed.connect(_emit_scene)
	_btn_next_turn.pressed.connect(func(): turn_advance_requested.emit())
	_btn_advance.pressed.connect(func(): advance_requested.emit())
	_btn_complete.pressed.connect(func(): complete_requested.emit())

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func set_waiting(waiting: bool) -> void:
	_alert.visible = waiting

func set_npcs(npcs: Array) -> void:
	var previous := _selected_npc()
	_npc_picker.fit_to_longest_item = false
	_npc_picker.clip_text = true
	_npc_picker.clear()
	_npc_picker.add_item("— Choisir un PNJ —")
	_npc_picker.set_item_metadata(0, "")
	for npc_variant in npcs:
		var npc: Dictionary = npc_variant
		var npc_name := str(npc.get("name", "PNJ"))
		var role := str(npc.get("role", ""))
		var emoji := str(npc.get("emoji", "")).strip_edges()
		var shown := npc_name if role.is_empty() else "%s (%s)" % [npc_name, role]
		if not emoji.is_empty():
			shown = "%s %s" % [emoji, shown]
		_npc_picker.add_item(_dock_label(shown))
		_npc_picker.set_item_metadata(_npc_picker.item_count - 1, npc_name)
		_npc_picker.set_item_tooltip(_npc_picker.item_count - 1, shown)
	_npc_picker.add_item("PNJ improvisé…")
	_npc_picker.set_item_metadata(_npc_picker.item_count - 1, CUSTOM_NPC)
	_reselect(_npc_picker, previous)

func set_navigation(nav: Dictionary) -> void:
	_scene_picker.fit_to_longest_item = false
	_scene_picker.clip_text = true
	_scene_picker.clear()
	for scene_variant in nav.get("scenes", []):
		var scene: Dictionary = scene_variant
		var full := str(scene.get("label", scene.get("id", "")))
		_scene_picker.add_item(_dock_label(full))
		var idx := _scene_picker.item_count - 1
		_scene_picker.set_item_metadata(idx, str(scene.get("id", "")))
		_scene_picker.set_item_tooltip(idx, full)
		if bool(scene.get("current", false)):
			_scene_picker.select(idx)

	for child in _transitions.get_children():
		_transitions.remove_child(child)
		child.queue_free()
	var transitions: Array = nav.get("transitions", [])
	for transition_variant in transitions:
		if typeof(transition_variant) != TYPE_DICTIONARY:
			continue
		var transition: Dictionary = transition_variant
		var to_id := str(transition.get("to", ""))
		if to_id.is_empty():
			continue
		var label := str(transition.get("label", to_id))
		if bool(transition.get("default", false)):
			label += " ★"
		var full := "→ %s" % label
		var btn := SessionStyle.button(_dock_label(full, 24), full)
		btn.clip_text = true
		btn.pressed.connect(func(): scene_requested.emit(to_id))
		_transitions.add_child(btn)
	if transitions.is_empty():
		_transitions.add_child(SessionStyle.caption(
			"Scène terminale — clore l'aventure ou sauter ailleurs."
		))

func select_npc(npc_name: String) -> void:
	var needle := npc_name.strip_edges()
	if needle.is_empty() or _npc_picker == null:
		return
	var lower := needle.to_lower()
	for i in range(_npc_picker.item_count):
		var meta := str(_npc_picker.get_item_metadata(i))
		if meta.is_empty() or meta == CUSTOM_NPC:
			continue
		var meta_l := meta.to_lower()
		if meta_l == lower or meta_l.begins_with(lower) or lower.begins_with(meta_l):
			_npc_picker.select(i)
			return
		if meta_l.contains(lower) or lower.contains(meta_l):
			_npc_picker.select(i)
			return

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_narration.editable = enabled
	_npc_line.editable = enabled
	for btn in [_btn_next_turn, _btn_narrate, _btn_npc, _btn_goto, _btn_advance, _btn_complete]:
		btn.disabled = not enabled
	_npc_picker.disabled = not enabled
	_scene_picker.disabled = not enabled

# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------

func _on_narration_input(event: InputEvent) -> void:
	if _is_send_shortcut(event):
		_emit_narration()
		_narration.accept_event()

func _on_npc_input(event: InputEvent) -> void:
	if _is_send_shortcut(event):
		_emit_npc_line()
		_npc_line.accept_event()

static func _is_send_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	return event.ctrl_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)

func _emit_narration() -> void:
	if not _enabled:
		return
	var text := _narration.text.strip_edges()
	if text.is_empty():
		return
	_narration.text = ""
	narrate_requested.emit(text)

func _emit_npc_line() -> void:
	if not _enabled:
		return
	var meta := _selected_npc()
	var text := _npc_line.text.strip_edges()
	if text.is_empty():
		return
	var npc_name := meta
	if meta.is_empty() or meta == CUSTOM_NPC:
		if text.contains(":"):
			var parts := text.split(":", false, 1)
			npc_name = parts[0].strip_edges()
			text = parts[1].strip_edges()
		elif meta == CUSTOM_NPC:
			return
		else:
			# Placeholder « Choisir un PNJ » : on publie quand même.
			npc_name = "PNJ"
		if npc_name.is_empty() or text.is_empty():
			return
	_npc_line.text = ""
	npc_line_requested.emit(npc_name, text)

func _emit_scene() -> void:
	if not _enabled or _scene_picker.selected < 0:
		return
	scene_requested.emit(str(_scene_picker.get_item_metadata(_scene_picker.selected)))

func _selected_npc() -> String:
	if _npc_picker == null or _npc_picker.selected < 0:
		return ""
	return str(_npc_picker.get_item_metadata(_npc_picker.selected))

static func _dock_label(text: String, limit: int = 28) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit - 1) + "…"

static func _reselect(picker: OptionButton, value: String) -> void:
	if value.is_empty():
		return
	for i in range(picker.item_count):
		if str(picker.get_item_metadata(i)) == value:
			picker.select(i)
			return
