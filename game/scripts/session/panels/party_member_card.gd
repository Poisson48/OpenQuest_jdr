extends PanelContainer
class_name PartyMemberCard

## Une ligne du dock de groupe. Structure dans
## `scenes/session/panels/party_member_card.tscn`.

signal activated(member: Dictionary)

const PORTRAIT_PX := 64

@onready var _portrait: TextureRect = %Portrait
@onready var _initial: Label = %Initial
@onready var _name: Label = %LblName
@onready var _stats: Label = %LblStats
@onready var _hp_bar: ProgressBar = %HpBar
@onready var _badge: Label = %LblBadge

var _member: Dictionary = {}

func _ready() -> void:
	gui_input.connect(_on_gui_input)

func setup(member: Dictionary, is_active_turn: bool, local_client_id: String) -> void:
	_member = member.duplicate(true)
	if not is_node_ready():
		await ready
	theme_type_variation = &"AlertPanel" if is_active_turn else &"InsetPanel"
	var member_name := str(member.get("name", "Aventurier"))
	_name.text = member_name
	var inv_bits: Array[String] = []
	for it_variant in member.get("inventory", []):
		if typeof(it_variant) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_variant
		var qty := int(it.get("qty", 1))
		var iname := str(it.get("name", it.get("id", "?")))
		inv_bits.append(iname if qty <= 1 else "%s×%d" % [iname, qty])
	var hp := SessionStyle.member_hp(member)
	var ac := int(member.get("ac", 0))
	if inv_bits.is_empty():
		_stats.text = "PV %d · CA %d" % [hp, ac]
	else:
		var shown := ", ".join(inv_bits)
		if shown.length() > 42:
			shown = shown.substr(0, 40) + "…"
		_stats.text = "PV %d · CA %d · %s" % [hp, ac, shown]
	if _hp_bar != null:
		SessionStyle.style_hp_bar(_hp_bar, member)
	tooltip_text = "Ouvrir la fiche de %s" % member_name
	_apply_portrait(member, member_name)
	_apply_badge(member, is_active_turn, local_client_id)

func _apply_portrait(member: Dictionary, member_name: String) -> void:
	var path := str(member.get("portrait", member.get("image", ""))).strip_edges()
	var cutout: Texture2D = null
	if not path.is_empty():
		cutout = MapData.load_token_cutout(path, PORTRAIT_PX)
	_portrait.texture = cutout
	_portrait.visible = cutout != null
	_initial.visible = cutout == null
	_initial.text = member_name.substr(0, 1).to_upper()

func _apply_badge(member: Dictionary, is_active_turn: bool, local_client_id: String) -> void:
	if is_active_turn:
		_set_badge("TOUR", ThemeColors.ALERT)
	elif not local_client_id.is_empty() and str(member.get("clientId", "")) == local_client_id:
		_set_badge("VOUS", ThemeColors.ACCENT)
	elif bool(member.get("isBot", false)):
		_set_badge("PNJ", ThemeColors.BOT_ACCENT)
	else:
		_badge.visible = false

func _set_badge(text: String, color: Color) -> void:
	_badge.visible = true
	_badge.text = text
	_badge.add_theme_color_override("font_color", color)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(_member)
