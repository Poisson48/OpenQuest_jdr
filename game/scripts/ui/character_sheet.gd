extends Control
class_name CharacterSheet

## Fiche personnage plein écran — pas de scroll.
## Gauche : stats / histoire · Droite : silhouette en pied.
## Répliques façon Darkest Dungeon qui tournent seules.

signal closed

const BARK_INTERVAL := 7.5

var _member: Dictionary = {}
var _showing_story: bool = false
var _bark_idx: int = 0
var _bark_timer: float = 0.0

var _dim: ColorRect
var _root: HBoxContainer
var _left: PanelContainer
var _left_body: VBoxContainer
var _art: TextureRect
var _bark_lbl: Label
var _story_btn: Button
var _close_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	visible = false
	set_process(false)
	_build()

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.04, 0.03, 0.02, 0.82)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dim)

	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 36)
	frame.add_theme_constant_override("margin_right", 36)
	frame.add_theme_constant_override("margin_top", 28)
	frame.add_theme_constant_override("margin_bottom", 28)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_root = HBoxContainer.new()
	_root.add_theme_constant_override("separation", 0)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_root)

	_left = PanelContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 0.92
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = Color(0.12, 0.09, 0.07, 0.97)
	left_style.border_color = ThemeColors.GOLD.darkened(0.25)
	left_style.set_border_width_all(1)
	left_style.content_margin_left = 28
	left_style.content_margin_right = 28
	left_style.content_margin_top = 24
	left_style.content_margin_bottom = 22
	_left.add_theme_stylebox_override("panel", left_style)
	_root.add_child(_left)

	_left_body = VBoxContainer.new()
	_left_body.add_theme_constant_override("separation", 14)
	_left_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left.add_child(_left_body)

	var art_wrap := PanelContainer.new()
	art_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_wrap.size_flags_stretch_ratio = 1.15
	var art_style := StyleBoxFlat.new()
	art_style.bg_color = Color(0.02, 0.015, 0.02, 1.0)
	art_style.border_color = ThemeColors.BORDER
	art_style.set_border_width_all(1)
	art_style.content_margin_left = 8
	art_style.content_margin_right = 8
	art_style.content_margin_top = 8
	art_style.content_margin_bottom = 8
	art_wrap.add_theme_stylebox_override("panel", art_style)
	_root.add_child(art_wrap)

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_wrap.add_child(_art)

func open(member: Dictionary) -> void:
	_member = member.duplicate(true)
	_showing_story = false
	_bark_idx = randi() % maxi(1, _barks().size())
	_bark_timer = 0.0
	_rebuild_left()
	_load_art()
	visible = true
	set_process(true)
	move_to_front()

func close() -> void:
	visible = false
	set_process(false)
	closed.emit()

func _process(delta: float) -> void:
	if not visible or _showing_story:
		return
	_bark_timer += delta
	if _bark_timer < BARK_INTERVAL:
		return
	_bark_timer = 0.0
	var lines := _barks()
	if lines.is_empty() or _bark_lbl == null:
		return
	_bark_idx = (_bark_idx + 1) % lines.size()
	_bark_lbl.text = "« %s »" % lines[_bark_idx]
	# Léger fade via modulate.
	_bark_lbl.modulate.a = 0.35
	var tw := create_tween()
	tw.tween_property(_bark_lbl, "modulate:a", 1.0, 0.45)

func _load_art() -> void:
	var path := str(_member.get("portrait", _member.get("image", ""))).strip_edges()
	_art.texture = null
	if path.is_empty():
		return
	# Préfère la découpe transparente plein corps.
	var cut := MapData.load_token_cutout(path, 720)
	if cut != null:
		_art.texture = cut
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return
	var tex := MapData.load_token_portrait(path, Color(0.1, 0.08, 0.06), 512)
	if tex != null:
		_art.texture = tex

func _rebuild_left() -> void:
	for child in _left_body.get_children():
		child.queue_free()
	_bark_lbl = null
	_story_btn = null

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_left_body.add_child(top)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	top.add_child(titles)

	var name_lbl := Label.new()
	name_lbl.text = str(_member.get("name", "Aventurier")).to_upper()
	name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	name_lbl.add_theme_font_size_override("font_size", 28)
	titles.add_child(name_lbl)

	var subtitle := Label.new()
	subtitle.text = "%s  ·  %s" % [_member.get("race", "?"), _member.get("class", "?")]
	subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	subtitle.add_theme_font_size_override("font_size", 14)
	titles.add_child(subtitle)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.custom_minimum_size = Vector2(36, 36)
	_close_btn.tooltip_text = "Fermer"
	_close_btn.pressed.connect(close)
	top.add_child(_close_btn)

	var rule := ColorRect.new()
	rule.color = ThemeColors.GOLD.darkened(0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_body.add_child(rule)

	if _showing_story:
		_build_story_page()
	else:
		_build_stats_page()

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	_left_body.add_child(footer)

	_story_btn = Button.new()
	_story_btn.text = "← Fiche" if _showing_story else "Histoire ▸"
	_story_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_btn.custom_minimum_size = Vector2(0, 40)
	_story_btn.pressed.connect(func():
		_showing_story = not _showing_story
		_rebuild_left()
	)
	footer.add_child(_story_btn)

func _build_stats_page() -> void:
	var vitals := HBoxContainer.new()
	vitals.add_theme_constant_override("separation", 16)
	_left_body.add_child(vitals)
	vitals.add_child(_stat_chip("PV", str(_member.get("hp", 10)), ThemeColors.DANGER.lightened(0.25)))
	vitals.add_child(_stat_chip("CA", str(_member.get("ac", 10)), ThemeColors.INVESTIGATION_ACCENT))
	var stress := str(_member.get("stress", "Calme"))
	vitals.add_child(_stat_chip("Humeur", stress, ThemeColors.GOLD))

	var stats: Dictionary = _member.get("stats", {}) if _member.get("stats") is Dictionary else {}
	if stats.is_empty():
		stats = {"str": 10, "dex": 16, "con": 12, "int": 11, "wis": 13, "cha": 9}
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_body.add_child(grid)
	for key in ["str", "dex", "con", "int", "wis", "cha"]:
		grid.add_child(_ability_block(key, int(stats.get(key, 10))))

	var traits_title := Label.new()
	traits_title.text = "TEMPÉRAMENT"
	traits_title.add_theme_color_override("font_color", ThemeColors.GOLD)
	traits_title.add_theme_font_size_override("font_size", 12)
	_left_body.add_child(traits_title)

	var traits := Label.new()
	traits.text = str(_member.get("temperament", "Méfiant · Silencieux · Opportuniste"))
	traits.add_theme_color_override("font_color", ThemeColors.TEXT)
	traits.add_theme_font_size_override("font_size", 14)
	traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_body.add_child(traits)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_body.add_child(spacer)

	var bark_box := PanelContainer.new()
	var bark_style := StyleBoxFlat.new()
	bark_style.bg_color = Color(0.08, 0.06, 0.05, 1.0)
	bark_style.border_color = ThemeColors.BORDER
	bark_style.set_border_width_all(1)
	bark_style.content_margin_left = 14
	bark_style.content_margin_right = 14
	bark_style.content_margin_top = 12
	bark_style.content_margin_bottom = 12
	bark_box.add_theme_stylebox_override("panel", bark_style)
	_left_body.add_child(bark_box)

	_bark_lbl = Label.new()
	var lines: Array = _barks()
	var line: String = str(lines[_bark_idx % lines.size()]) if not lines.is_empty() else "…"
	_bark_lbl.text = "« %s »" % line
	_bark_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_bark_lbl.add_theme_font_size_override("font_size", 15)
	_bark_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bark_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bark_box.add_child(_bark_lbl)

func _build_story_page() -> void:
	var title := Label.new()
	title.text = "HISTOIRE"
	title.add_theme_color_override("font_color", ThemeColors.GOLD)
	title.add_theme_font_size_override("font_size", 12)
	_left_body.add_child(title)

	# Pas de ScrollContainer : texte calé pour tenir dans le panneau.
	var story := Label.new()
	story.text = str(_member.get("backstory", "Aucune histoire écrite.")).strip_edges()
	story.add_theme_color_override("font_color", ThemeColors.TEXT)
	story.add_theme_font_size_override("font_size", 15)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_left_body.add_child(story)

	var quirk_title := Label.new()
	quirk_title.text = "PARTICULARITÉ"
	quirk_title.add_theme_color_override("font_color", ThemeColors.GOLD)
	quirk_title.add_theme_font_size_override("font_size", 12)
	_left_body.add_child(quirk_title)

	var quirk := Label.new()
	quirk.text = str(_member.get("quirk", "Surveille toujours les sorties."))
	quirk.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	quirk.add_theme_font_size_override("font_size", 14)
	quirk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_body.add_child(quirk)

func _stat_chip(label: String, value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
	st.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	st.set_border_width_all(1)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	l.add_theme_font_size_override("font_size", 11)
	v.add_child(l)
	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", ThemeColors.TEXT)
	val.add_theme_font_size_override("font_size", 20)
	v.add_child(val)
	panel.add_child(v)
	return panel

func _ability_block(key: String, value: int) -> PanelContainer:
	var labels := {
		"str": "FOR", "dex": "DEX", "con": "CON",
		"int": "INT", "wis": "SAG", "cha": "CHA",
	}
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.12, 0.09, 1.0)
	st.border_color = ThemeColors.BORDER
	st.set_border_width_all(1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var name_lbl := Label.new()
	name_lbl.text = str(labels.get(key, key.to_upper()))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	name_lbl.add_theme_font_size_override("font_size", 11)
	v.add_child(name_lbl)
	var val := Label.new()
	val.text = str(value)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	val.add_theme_font_size_override("font_size", 22)
	v.add_child(val)
	var mod := Label.new()
	var m := int(floor((value - 10) / 2.0))
	mod.text = ("%+d" % m) if m != 0 else "±0"
	mod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mod.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	mod.add_theme_font_size_override("font_size", 12)
	v.add_child(mod)
	panel.add_child(v)
	return panel

func _barks() -> Array:
	var custom = _member.get("barks", [])
	if custom is Array and not custom.is_empty():
		return custom
	return [
		"Les ombres mentent rarement. Les hommes, toujours.",
		"Un regard de trop… je disparais.",
		"La fortune favorise les doigts agiles.",
	]

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
