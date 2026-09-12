extends Control
class_name PlayerSessionHud

## HUD joueur : journal lisible, fiche, inventaire, actions.
## Structure dans `scenes/session/panels/player_hud.tscn`.

signal leave_pressed
signal open_character(member: Dictionary)
signal action_submitted(text: String)
signal roll_requested(formula: String)

const META_FONT_SIZE := 12

@onready var _title: Label = %LblTitle
@onready var _turn: Label = %LblTurn
@onready var _log_text: RichTextLabel = %LogText
@onready var _log_scroll: ScrollContainer = %LogScroll
@onready var _party_row: HBoxContainer = %PartyRow
@onready var _action: LineEdit = %ActionInput
@onready var _portrait: TextureRect = %Portrait
@onready var _hero_name: Label = %LblHeroName
@onready var _hero_sub: Label = %LblHeroSub
@onready var _hero_hp: Label = %LblHeroHp
@onready var _inv_preview: Label = %LblInventoryPreview
@onready var _inv_panel: PanelContainer = %InventoryPanel
@onready var _inv_list: VBoxContainer = %InvList

var _me: Dictionary = {}
var _entries: Array = []
var _my_turn := false

func _ready() -> void:
	%BtnLeave.pressed.connect(func(): leave_pressed.emit())
	%BtnSend.pressed.connect(func(): _submit(_action.text))
	%BtnD6.pressed.connect(func(): roll_requested.emit("1d6"))
	%BtnD20.pressed.connect(func(): roll_requested.emit("1d20"))
	_action.text_submitted.connect(func(text: String): _submit(text))
	%BtnMySheet.pressed.connect(_on_my_sheet)
	%BtnInventory.pressed.connect(_toggle_inventory)
	%BtnCloseInv.pressed.connect(func(): _inv_panel.visible = false)

func set_title(text: String) -> void:
	_title.text = text

func set_turn(turn: Dictionary) -> void:
	var headline := str(turn.get("headline", "En attente…"))
	_turn.text = headline
	_my_turn = str(turn.get("tone", "")) == "active" or headline.to_lower().contains("votre tour")
	var color := ThemeColors.TEXT_MUTED
	match str(turn.get("tone", "idle")):
		"alert":
			color = ThemeColors.ALERT
		"active":
			color = ThemeColors.SUCCESS
		"muted":
			color = ThemeColors.TEXT_MUTED
		_:
			color = ThemeColors.ACCENT_LIGHT
	_turn.add_theme_color_override("font_color", color)
	if _my_turn:
		_action.placeholder_text = "C'est votre tour — que faites-vous ?"
	else:
		_action.placeholder_text = "En attente de votre tour…"

func set_me(member: Dictionary) -> void:
	_me = member.duplicate(true) if not member.is_empty() else {}
	if _me.is_empty():
		_hero_name.text = "—"
		_hero_sub.text = ""
		_hero_hp.text = "PV —"
		_inv_preview.text = "Aucun personnage"
		_portrait.texture = null
		return
	_hero_name.text = str(_me.get("name", "Aventurier"))
	_hero_sub.text = "%s · %s" % [_me.get("race", "?"), _me.get("class", "?")]
	_hero_hp.text = "PV %d   ·   CA %d" % [int(_me.get("hp", 0)), int(_me.get("ac", 0))]
	_inv_preview.text = _inventory_preview_text(_me)
	_load_portrait(_me)
	if _inv_panel.visible:
		_fill_inventory_list()

func set_party(party: Array, my_id: String = "") -> void:
	for child in _party_row.get_children():
		_party_row.remove_child(child)
		child.queue_free()
	for member_variant in party:
		if typeof(member_variant) != TYPE_DICTIONARY:
			continue
		var member: Dictionary = member_variant
		if not (member.get("isPlayer", false) or member.get("isHuman", false)):
			continue
		var mid := str(member.get("id", ""))
		var member_name := str(member.get("name", "?"))
		var label := member_name
		if not my_id.is_empty() and mid == my_id:
			label = "★ %s" % member_name
		var btn := SessionStyle.button(" %s" % label, "Ouvrir la fiche de %s" % member_name)
		btn.custom_minimum_size = Vector2(0, 36)
		var path := str(member.get("portrait", member.get("image", ""))).strip_edges()
		if not path.is_empty():
			var texture := MapData.load_token_cutout(path, 48)
			if texture != null:
				btn.icon = texture
				btn.expand_icon = true
		var captured: Dictionary = member.duplicate(true)
		btn.pressed.connect(func(): open_character.emit(captured))
		_party_row.add_child(btn)

func reset_log(entries: Array) -> void:
	_entries = entries.duplicate()
	_rebuild_log()

func append_log(entry: Dictionary) -> void:
	_entries.append(entry)
	_rebuild_log()

## Compat : ancien toast → append dans le journal si besoin.
func show_toast(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	# Le journal est la source de vérité ; toast ignoré si déjà synchronisé.

func set_enabled(enabled: bool) -> void:
	_action.editable = enabled
	%BtnSend.disabled = not enabled
	%BtnD6.disabled = not enabled
	%BtnD20.disabled = not enabled

func submit_action_text(text: String) -> void:
	if not _action.editable:
		return
	_action.text = text
	_submit(text)

func _on_my_sheet() -> void:
	if _me.is_empty():
		return
	open_character.emit(_me.duplicate(true))

func _toggle_inventory() -> void:
	_inv_panel.visible = not _inv_panel.visible
	if _inv_panel.visible:
		_fill_inventory_list()

func _fill_inventory_list() -> void:
	for child in _inv_list.get_children():
		_inv_list.remove_child(child)
		child.queue_free()
	var items: Array = _me.get("inventory", []) if _me.get("inventory") is Array else []
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Votre sac est vide."
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inv_list.add_child(empty)
		return
	for it_variant in items:
		if typeof(it_variant) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_variant
		var qty := int(it.get("qty", 1))
		var iname := str(it.get("name", it.get("id", "?")))
		var row := Label.new()
		row.text = "• %s" % (iname if qty <= 1 else "%s  ×%d" % [iname, qty])
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_theme_font_size_override("font_size", 14)
		_inv_list.add_child(row)

func _inventory_preview_text(member: Dictionary) -> String:
	var items: Array = member.get("inventory", []) if member.get("inventory") is Array else []
	if items.is_empty():
		return "Sac vide"
	var bits: PackedStringArray = PackedStringArray()
	for it_variant in items:
		if typeof(it_variant) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_variant
		var qty := int(it.get("qty", 1))
		var iname := str(it.get("name", it.get("id", "?")))
		bits.append(iname if qty <= 1 else "%s×%d" % [iname, qty])
		if bits.size() >= 4:
			break
	var more := items.size() - bits.size()
	var preview := ", ".join(bits)
	if more > 0:
		preview += " (+%d)" % more
	return preview

func _load_portrait(member: Dictionary) -> void:
	_portrait.texture = null
	var path := str(member.get("portrait", member.get("image", ""))).strip_edges()
	if path.is_empty():
		return
	var texture := MapData.load_token_cutout(path, 96)
	if texture != null:
		_portrait.texture = texture

func _rebuild_log() -> void:
	if not is_node_ready():
		return
	_log_text.clear()
	for entry_variant in _entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		_write_log_entry(entry_variant)
	_scroll_log_end()

func _write_log_entry(entry: Dictionary) -> void:
	var author := str(entry.get("author", entry.get("speaker", "Inconnu")))
	var entry_type := str(entry.get("type", "player"))
	var body := str(entry.get("text", ""))
	var time := str(entry.get("time", ""))
	var author_hex := ThemeColors.get_bbcode_color(ThemeColors.log_color(entry_type))
	var meta_hex := ThemeColors.get_bbcode_color(ThemeColors.TEXT_MUTED)
	_log_text.append_text(
		"[color=#%s][b]%s[/b][/color]  [color=#%s][font_size=%d]%s[/font_size][/color]\n[font_size=16]%s[/font_size]\n\n" % [
			author_hex, author, meta_hex, META_FONT_SIZE, time, body
		]
	)

func _scroll_log_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(_log_text):
		return
	var bar := _log_scroll.get_v_scroll_bar()
	if bar != null:
		_log_scroll.scroll_vertical = int(bar.max_value)

func _submit(text: String) -> void:
	var action := text.strip_edges()
	if action.is_empty():
		return
	_action.text = ""
	action_submitted.emit(action)
