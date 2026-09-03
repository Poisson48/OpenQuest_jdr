extends Control
class_name PlayerSessionHud

## HUD joueur par-dessus la carte plein écran.
## Uniquement l'essentiel : quitter, perso, action, dés, dernier message.

signal leave_pressed
signal open_character(member: Dictionary)
signal action_submitted(text: String)
signal roll_requested(formula: String)

var _toast: Label
var _action: LineEdit
var _party_row: HBoxContainer
var _title: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	_build()

func _build() -> void:
	# Haut
	var top := MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 56
	top.add_theme_constant_override("margin_left", 16)
	top.add_theme_constant_override("margin_right", 16)
	top.add_theme_constant_override("margin_top", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_row)

	var leave := _pill_button("← Quitter")
	leave.pressed.connect(func(): leave_pressed.emit())
	top_row.add_child(leave)

	_title = Label.new()
	_title.text = ""
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	_title.add_theme_font_size_override("font_size", 14)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(_title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(88, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)

	# Toast narratif (haut-centre sous le bandeau)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.anchor_left = 0.15
	_toast.anchor_right = 0.85
	_toast.offset_top = 58
	_toast.offset_bottom = 110
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78, 0.95))
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	add_child(_toast)

	# Bas : perso + action + dés
	var bottom := MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -118
	bottom.add_theme_constant_override("margin_left", 18)
	bottom.add_theme_constant_override("margin_right", 18)
	bottom.add_theme_constant_override("margin_bottom", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	var bar := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.045, 0.035, 0.78)
	st.border_color = Color(0.55, 0.42, 0.22, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	bar.add_theme_stylebox_override("panel", st)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bottom.add_child(bar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	bar.add_child(col)

	_party_row = HBoxContainer.new()
	_party_row.add_theme_constant_override("separation", 8)
	col.add_child(_party_row)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	col.add_child(action_row)

	_action = LineEdit.new()
	_action.placeholder_text = "Que faites-vous ?"
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.custom_minimum_size = Vector2(0, 36)
	_action.text_submitted.connect(func(t): _submit(t))
	action_row.add_child(_action)

	var send := _pill_button("Envoyer")
	send.pressed.connect(func(): _submit(_action.text))
	action_row.add_child(send)

	var d6 := _pill_button("d6")
	d6.pressed.connect(func(): roll_requested.emit("1d6"))
	action_row.add_child(d6)

	var d20 := _pill_button("d20")
	d20.pressed.connect(func(): roll_requested.emit("1d20"))
	action_row.add_child(d20)

func set_title(text: String) -> void:
	_title.text = text

func set_party(party: Array) -> void:
	for c in _party_row.get_children():
		c.queue_free()
	for m_variant in party:
		var m: Dictionary = m_variant
		if not (m.get("isPlayer", false) or m.get("isHuman", false)):
			continue
		var btn := Button.new()
		btn.text = "  %s" % str(m.get("name", "?"))
		btn.custom_minimum_size = Vector2(0, 40)
		btn.tooltip_text = "Fiche de %s" % m.get("name", "")
		var path := str(m.get("portrait", m.get("image", ""))).strip_edges()
		if not path.is_empty():
			var tex := MapData.load_token_cutout(path, 64)
			if tex != null:
				btn.icon = tex
				btn.expand_icon = true
		var captured: Dictionary = m.duplicate(true)
		btn.pressed.connect(func(): open_character.emit(captured))
		_party_row.add_child(btn)

func show_toast(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		_toast.visible = false
		return
	_toast.text = t
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): _toast.visible = false)

func _submit(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		return
	_action.text = ""
	action_submitted.emit(t)

func _pill_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 36)
	return btn
