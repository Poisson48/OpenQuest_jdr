extends Control
class_name SpeakerDialogueOverlay

## Dialogue cinématique : portrait à droite + boîte parchemin à gauche.
## Style OpenQuest (or / parchemin) — pas de look Pokémon.

signal dismissed

const HOLD_SEC := 4.8
const FADE_SEC := 0.35

@onready var _dim: ColorRect = %Dim
@onready var _art: TextureRect = %SpeakerArt
@onready var _box: PanelContainer = %DialogueBox
@onready var _name: Label = %LblSpeaker
@onready var _line: RichTextLabel = %LblLine
@onready var _continue: Label = %LblContinue

var _queue: Array = []
var _busy := false
var _tween: Tween
var _hold_gen := 0

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 70
	_dim.gui_input.connect(_on_dim_input)
	_box.gui_input.connect(_on_dim_input)

func enqueue(speaker: String, text: String, kind: String = "npc", art_path: String = "") -> void:
	var body := _plain(text)
	var who := speaker.strip_edges()
	if who.is_empty() or body.is_empty():
		return
	if _busy and visible and _name.text == who:
		_show_now(who, body, kind, art_path)
		return
	for i in range(_queue.size()):
		var q: Dictionary = _queue[i]
		if str(q.get("speaker", "")) == who:
			_queue[i] = {"speaker": who, "text": body, "kind": kind, "art": art_path}
			return
	_queue.append({"speaker": who, "text": body, "kind": kind, "art": art_path})
	_pump()

func clear() -> void:
	_queue.clear()
	_busy = false
	_hold_gen += 1
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false

func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	_show_now(
		str(next.get("speaker", "")),
		str(next.get("text", "")),
		str(next.get("kind", "npc")),
		str(next.get("art", ""))
	)

func _show_now(speaker: String, text: String, kind: String, art_path: String) -> void:
	_busy = true
	_hold_gen += 1
	var gen := _hold_gen
	_name.text = speaker
	_line.bbcode_enabled = true
	_line.text = text
	_style_for_kind(kind)
	_load_art(art_path, speaker, kind)
	visible = true
	modulate.a = 0.0
	_art.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.22)
	_tween.tween_property(_art, "modulate:a", 1.0, 0.4)
	_arm_auto_hide(gen)

func _arm_auto_hide(gen: int) -> void:
	await get_tree().create_timer(HOLD_SEC).timeout
	if gen != _hold_gen or not visible:
		return
	_dismiss()

func _dismiss() -> void:
	if not visible:
		_busy = false
		_pump()
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SEC)
	_tween.tween_callback(func():
		visible = false
		_busy = false
		dismissed.emit()
		_pump()
	)

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dismiss()

func _style_for_kind(kind: String) -> void:
	var accent := ThemeColors.LOG_NPC
	match kind:
		"gm":
			accent = ThemeColors.LOG_GM
		"player", "bot":
			accent = ThemeColors.LOG_PLAYER
		"system":
			accent = ThemeColors.LOG_SYSTEM
		_:
			accent = ThemeColors.LOG_NPC
	_name.add_theme_color_override("font_color", accent)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.14, 0.10, 0.07, 0.94)
	box.border_color = ThemeColors.GOLD
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	box.shadow_color = Color(0, 0, 0, 0.55)
	box.shadow_size = 10
	box.shadow_offset = Vector2(0, 4)
	_box.add_theme_stylebox_override("panel", box)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.18, 0.13, 0.08, 1.0)
	plate.border_color = accent
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(8)
	plate.content_margin_left = 12
	plate.content_margin_right = 12
	plate.content_margin_top = 4
	plate.content_margin_bottom = 4
	%NamePlate.add_theme_stylebox_override("panel", plate)

func _load_art(art_path: String, speaker: String, kind: String) -> void:
	_art.texture = null
	_art.visible = true
	var path := art_path.strip_edges()
	if path.is_empty():
		path = GameData.resolve_speaker_art(speaker, kind)
	if path.is_empty():
		_art.visible = false
		return
	var tex: Texture2D = MapData.load_token_cutout(path, 720)
	if tex == null and ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res
	if tex == null:
		_art.visible = false
		return
	_art.texture = tex

static func _plain(text: String) -> String:
	var body := text.strip_edges()
	if body.begins_with("«"):
		body = body.substr(1).strip_edges()
	if body.ends_with("»"):
		body = body.substr(0, body.length() - 1).strip_edges()
	return body
