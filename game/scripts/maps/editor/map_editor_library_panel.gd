extends VBoxContainer
class_name MapEditorLibraryPanel

## Onglet « Biblio » — extrait du monolithe map_complex_editor (P1-C).

const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

signal import_assets_pressed
signal refresh_assets_pressed
signal member_token_pressed(index: int)
signal effect_preset_pressed(preset_id: String)
signal trigger_all_effects_pressed
signal save_template_pressed
signal refresh_templates_pressed

var asset_hint: Label
var asset_category_row: HBoxContainer
var asset_grid: GridContainer
var member_grid: GridContainer
var marker_box: VBoxContainer
var effect_list: VBoxContainer
var tile_box: VBoxContainer
var template_list: VBoxContainer
var widgets: Dictionary = {}

func _init() -> void:
	add_theme_constant_override("separation", 5)

	_section("🏚 Décors à poser")
	asset_hint = Label.new()
	asset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	asset_hint.add_theme_font_size_override("font_size", 11)
	asset_hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	add_child(asset_hint)

	var asset_cat_scroll := ScrollContainer.new()
	asset_cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	asset_cat_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	asset_cat_scroll.custom_minimum_size = Vector2(0, 36)
	add_child(asset_cat_scroll)
	asset_category_row = HBoxContainer.new()
	asset_category_row.add_theme_constant_override("separation", 3)
	asset_cat_scroll.add_child(asset_category_row)

	asset_grid = GridContainer.new()
	asset_grid.columns = 3
	asset_grid.add_theme_constant_override("h_separation", 4)
	asset_grid.add_theme_constant_override("v_separation", 4)
	add_child(asset_grid)

	var asset_actions := HBoxContainer.new()
	asset_actions.add_theme_constant_override("separation", 4)
	add_child(asset_actions)
	_text_button(asset_actions, "＋ Importer des images…", func(): import_assets_pressed.emit())
	_text_button(asset_actions, "⟳", func(): refresh_assets_pressed.emit())

	_section("🧍 Tokens")
	member_grid = GridContainer.new()
	member_grid.columns = 6
	member_grid.add_theme_constant_override("h_separation", 3)
	add_child(member_grid)
	widgets["member_grid"] = member_grid
	for i in range(MapData.MEMBER_COLOR_HEX.size()):
		var index := i
		var btn := Button.new()
		btn.text = str(MapData.MEMBER_PLAYER_EMOJIS_GENERAL[i % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()])
		btn.toggle_mode = true
		btn.button_pressed = i == 0
		btn.custom_minimum_size = Vector2(38, 32)
		btn.tooltip_text = "Couleur de token %d" % (i + 1)
		btn.pressed.connect(func():
			for child in member_grid.get_children():
				if child is Button:
					(child as Button).button_pressed = false
			btn.button_pressed = true
			member_token_pressed.emit(index)
		)
		member_grid.add_child(btn)

	_section("📍 Marqueurs")
	marker_box = VBoxContainer.new()
	marker_box.add_theme_constant_override("separation", 2)
	add_child(marker_box)
	widgets["marker_box"] = marker_box

	_section("✨ Effets")
	var fx_grid := GridContainer.new()
	fx_grid.columns = 4
	fx_grid.add_theme_constant_override("h_separation", 3)
	add_child(fx_grid)
	for preset_id_variant in MapEffectPresetsScript.PRESET_IDS:
		var preset_id := str(preset_id_variant)
		var preset := MapEffectPresetsScript.get_preset(preset_id)
		var btn := Button.new()
		btn.text = str(preset.get("emoji", "✨"))
		btn.tooltip_text = str(preset.get("label", preset_id))
		btn.custom_minimum_size = Vector2(42, 32)
		btn.pressed.connect(func(): effect_preset_pressed.emit(preset_id))
		fx_grid.add_child(btn)
	_text_button(self, "▶ Déclencher tous les effets", func(): trigger_all_effects_pressed.emit())
	effect_list = VBoxContainer.new()
	effect_list.add_theme_constant_override("separation", 2)
	add_child(effect_list)

	_section("🎨 Terrain")
	tile_box = VBoxContainer.new()
	tile_box.add_theme_constant_override("separation", 2)
	add_child(tile_box)
	widgets["tile_box"] = tile_box

	_section("🧩 Templates")
	var tpl_actions := HBoxContainer.new()
	tpl_actions.add_theme_constant_override("separation", 4)
	add_child(tpl_actions)
	_text_button(tpl_actions, "＋ Depuis la sélection", func(): save_template_pressed.emit())
	_text_button(tpl_actions, "⟳", func(): refresh_templates_pressed.emit())
	template_list = VBoxContainer.new()
	template_list.add_theme_constant_override("separation", 2)
	add_child(template_list)

func _section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 12)
	add_child(lbl)

func _text_button(parent: Node, text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn
