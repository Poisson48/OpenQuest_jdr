extends Control
class_name PlayerSessionHud

## HUD joueur par-dessus la carte plein écran.
## Structure dans `scenes/session/panels/player_hud.tscn`.
##
## Uniquement l'essentiel : quitter, personnage, action, dés, dernier message.

signal leave_pressed
signal open_character(member: Dictionary)
signal action_submitted(text: String)
signal roll_requested(formula: String)

const TOAST_HOLD := 4.5
const TOAST_FADE := 0.8

@onready var _title: Label = %LblTitle
@onready var _toast: Label = %LblToast
@onready var _party_row: HBoxContainer = %PartyRow
@onready var _action: LineEdit = %ActionInput

func _ready() -> void:
	%BtnLeave.pressed.connect(func(): leave_pressed.emit())
	%BtnSend.pressed.connect(func(): _submit(_action.text))
	%BtnD6.pressed.connect(func(): roll_requested.emit("1d6"))
	%BtnD20.pressed.connect(func(): roll_requested.emit("1d20"))
	_action.text_submitted.connect(func(text: String): _submit(text))

func set_title(text: String) -> void:
	_title.text = text

func set_party(party: Array) -> void:
	for child in _party_row.get_children():
		_party_row.remove_child(child)
		child.queue_free()
	for member_variant in party:
		var member: Dictionary = member_variant
		if not (member.get("isPlayer", false) or member.get("isHuman", false)):
			continue
		var member_name := str(member.get("name", "?"))
		var btn := SessionStyle.button(" %s" % member_name, "Fiche de %s" % member_name)
		btn.custom_minimum_size = Vector2(0, 40)
		var path := str(member.get("portrait", member.get("image", ""))).strip_edges()
		if not path.is_empty():
			var texture := MapData.load_token_cutout(path, 64)
			if texture != null:
				btn.icon = texture
				btn.expand_icon = true
		var captured: Dictionary = member.duplicate(true)
		btn.pressed.connect(func(): open_character.emit(captured))
		_party_row.add_child(btn)

func show_toast(text: String) -> void:
	var body := text.strip_edges()
	if body.is_empty():
		_toast.visible = false
		return
	_toast.text = body
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(TOAST_HOLD)
	tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE)
	tween.tween_callback(func(): _toast.visible = false)

func _submit(text: String) -> void:
	var action := text.strip_edges()
	if action.is_empty():
		return
	_action.text = ""
	action_submitted.emit(action)
