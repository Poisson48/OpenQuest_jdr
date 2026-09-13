extends Control
class_name PlayerSessionHud

## HUD joueur : journal lisible, fiche, inventaire, actions.
## Structure dans `scenes/session/panels/player_hud.tscn`.

signal leave_pressed
signal open_character(member: Dictionary)
signal action_submitted(text: String)
signal roll_requested(formula: String)
signal zoom_in_requested
signal zoom_out_requested
signal fit_requested
signal chrome_changed

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
@onready var _hero_hp_bar: ProgressBar = %HeroHpBar
@onready var _inv_preview: Label = %LblInventoryPreview
@onready var _inv_panel: PanelContainer = %InventoryPanel
@onready var _inv_list: VBoxContainer = %InvList
@onready var _night_banner: PanelContainer = %NightBanner
@onready var _night_label: Label = %LblNightBanner

var _me: Dictionary = {}
var _entries: Array = []
var _my_turn := false
var _journal_collapsed := false

func _ready() -> void:
	%BtnLeave.pressed.connect(func(): leave_pressed.emit())
	%BtnSend.pressed.connect(func(): _submit(_action.text))
	%BtnD6.pressed.connect(func(): roll_requested.emit("1d6"))
	%BtnD20.pressed.connect(func(): roll_requested.emit("1d20"))
	_action.text_submitted.connect(func(text: String): _submit(text))
	%BtnMySheet.pressed.connect(_on_my_sheet)
	%BtnInventory.pressed.connect(_toggle_inventory)
	%BtnCloseInv.pressed.connect(func(): _inv_panel.visible = false)
	%BtnZoomOut.pressed.connect(func(): zoom_out_requested.emit())
	%BtnZoomIn.pressed.connect(func(): zoom_in_requested.emit())
	%BtnFit.pressed.connect(func(): fit_requested.emit())
	for btn in [%BtnExplore, %BtnTalk, %BtnInspect, %BtnFight]:
		var phrase := str(btn.tooltip_text)
		btn.pressed.connect(func(): _submit(phrase))
	var btn_collapse: Button = %BtnClearFocus
	btn_collapse.visible = true
	btn_collapse.text = "«"
	btn_collapse.tooltip_text = "Replier / déplier l'histoire"
	btn_collapse.pressed.connect(_toggle_journal)
	resized.connect(_on_resized)
	if _night_banner:
		_night_banner.visible = false
	call_deferred("_adapt_chrome")

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
		if _hero_hp_bar:
			_hero_hp_bar.visible = false
		_inv_preview.text = "Aucun personnage"
		_portrait.texture = null
		return
	_hero_name.text = str(_me.get("name", "Aventurier"))
	var race := str(_me.get("race", "")).strip_edges()
	var klass := str(_me.get("class", "")).strip_edges()
	_hero_sub.text = "%s · %s" % [race if not race.is_empty() else "—", klass if not klass.is_empty() else "—"]
	_hero_hp.text = "PV %d   ·   CA %d" % [SessionStyle.member_hp(_me), int(_me.get("ac", 0))]
	if _hero_hp_bar:
		_hero_hp_bar.visible = true
		SessionStyle.style_hp_bar(_hero_hp_bar, _me)
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
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var btn := SessionStyle.button(" %s" % label, "Ouvrir la fiche de %s" % member_name)
		btn.custom_minimum_size = Vector2(0, 32)
		var path := str(member.get("portrait", member.get("image", ""))).strip_edges()
		if not path.is_empty():
			var texture := MapData.load_token_cutout(path, 48)
			if texture != null:
				btn.icon = texture
				btn.expand_icon = true
		var captured: Dictionary = member.duplicate(true)
		btn.pressed.connect(func(): open_character.emit(captured))
		var hp_lbl := Label.new()
		hp_lbl.theme_type_variation = &"CaptionLabel"
		hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_lbl.text = "PV %d" % SessionStyle.member_hp(member)
		var hp_bar := ProgressBar.new()
		SessionStyle.style_hp_bar(hp_bar, member)
		hp_bar.custom_minimum_size = Vector2(64, 6)
		col.add_child(btn)
		col.add_child(hp_lbl)
		col.add_child(hp_bar)
		_party_row.add_child(col)
	_apply_party_compact()

func reset_log(entries: Array) -> void:
	_entries = entries.duplicate()
	_rebuild_log()

func append_log(entry: Dictionary) -> void:
	_entries.append(entry)
	if not is_node_ready():
		await ready
	var before := _log_text.get_parsed_text().length() if _log_text else 0
	_write_log_entry(entry)
	var after := _log_text.get_parsed_text().length() if _log_text else 0
	if after <= before:
		_rebuild_log()
	else:
		_scroll_log_end()

## Bandeau / toast court (nuit, navigation bloquée).
func show_toast(text: String) -> void:
	var body := text.strip_edges()
	if body.is_empty() or _night_label == null:
		return
	_night_label.text = body
	if _night_banner:
		_night_banner.visible = true
	var tw := create_tween()
	tw.tween_interval(4.2)
	tw.tween_callback(func():
		if _night_label != null and _night_label.text == body and not GameData.local_member_is_night_blind():
			if _night_banner:
				_night_banner.visible = false
	)

func set_night_blind(blind: bool) -> void:
	if _night_banner == null:
		return
	if blind:
		_night_label.text = "Sans lanterne, vous êtes aveugle"
		_night_banner.visible = true
	else:
		_night_banner.visible = false

## Insets carte (gauche, haut, droite, bas) mesurés sur le HUD réel.
## La fiche héros est un coin, pas une colonne : elle ne doit pas décaler toute la carte.
func chrome_insets() -> Vector4:
	if not is_node_ready():
		return Vector4(16.0, 52.0, 260.0, 120.0)
	var vp := size
	var top_bar: Control = $TopBar
	var bottom_bar: Control = $BottomBar
	var journal: Control = $JournalDock
	var top := maxf(48.0, top_bar.size.y + 4.0) if top_bar else 52.0
	var bottom := maxf(96.0, bottom_bar.size.y + 8.0) if bottom_bar else 120.0
	var left := 12.0
	var right := 28.0
	if journal and journal.visible and not _journal_collapsed:
		right = maxf(right, journal.size.x + 8.0)
	var max_side := maxf(180.0, vp.x * 0.24)
	left = minf(left, max_side)
	right = minf(right, max_side)
	top = minf(top, maxf(48.0, vp.y * 0.12))
	bottom = minf(bottom, maxf(88.0, vp.y * 0.26))
	if vp.x - left - right < vp.x * 0.42:
		right = maxf(160.0, vp.x - left - vp.x * 0.42)
	if vp.y - top - bottom < vp.y * 0.42:
		bottom = maxf(80.0, vp.y - top - vp.y * 0.42)
	return Vector4(left, top, right, bottom)

func set_enabled(enabled: bool) -> void:
	_action.editable = enabled
	%BtnSend.disabled = not enabled
	# Les dés restent disponibles hors tour (quick win audit UX).
	%BtnD6.disabled = false
	%BtnD20.disabled = false
	for btn in [%BtnExplore, %BtnTalk, %BtnInspect, %BtnFight]:
		btn.disabled = not enabled

func _toggle_journal() -> void:
	_journal_collapsed = not _journal_collapsed
	%BtnClearFocus.text = "»" if _journal_collapsed else "«"
	%LogScroll.visible = not _journal_collapsed
	_adapt_chrome()
	chrome_changed.emit()

func _on_resized() -> void:
	_adapt_chrome()
	chrome_changed.emit()

func _is_compact() -> bool:
	return size.y < 820.0 or size.x < 1480.0

## Demi-écran 2x2 (~1720×696) : journal borné, barre basse et fiche compactes.
func _adapt_chrome() -> void:
	if not is_node_ready():
		return
	var compact := _is_compact()
	var short := size.y < 740.0
	var bottom_h := 96.0 if short else (118.0 if compact else 180.0)
	var top_h := 50.0
	var journal_w := minf(268.0 if compact else 340.0, maxf(size.x * 0.20, 200.0))
	var suggest: Control = get_node_or_null("%SuggestRow")
	if suggest:
		suggest.visible = not short
	var bottom: Control = $BottomBar
	if bottom:
		bottom.offset_top = -bottom_h
	var journal: Control = $JournalDock
	if journal:
		journal.anchor_left = 1.0
		journal.anchor_right = 1.0
		journal.offset_top = top_h + 6.0
		journal.offset_bottom = -bottom_h + 4.0
		if _journal_collapsed:
			journal.offset_left = -44.0
			journal.offset_right = -6.0
		else:
			journal.offset_left = -(journal_w + 8.0)
			journal.offset_right = -8.0
	var hero: Control = $HeroDock
	var hero_w := 216.0 if compact else 300.0
	var hero_h := 108.0 if compact else 160.0
	if hero:
		hero.offset_left = 0.0
		hero.offset_right = hero_w + 10.0
		hero.offset_top = -(bottom_h + hero_h + 8.0)
		hero.offset_bottom = -bottom_h - 4.0
	if _inv_preview:
		_inv_preview.visible = not compact
	if _inv_panel:
		_inv_panel.offset_left = 10.0
		_inv_panel.offset_right = hero_w + 20.0
		_inv_panel.offset_bottom = -(bottom_h + hero_h + 12.0)
		_inv_panel.offset_top = _inv_panel.offset_bottom - (220.0 if compact else 232.0)
	_apply_party_compact()

func _apply_party_compact() -> void:
	if _party_row == null:
		return
	var compact := _is_compact()
	for col in _party_row.get_children():
		if not (col is VBoxContainer):
			continue
		var kids := col.get_children()
		for i in range(1, kids.size()):
			kids[i].visible = not compact

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
