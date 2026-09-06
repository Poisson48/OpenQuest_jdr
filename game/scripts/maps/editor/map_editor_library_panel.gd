extends VBoxContainer
class_name MapEditorLibraryPanel

## Onglet « Biblio ». Structure dans `scenes/map_editor/panels/library.tscn`.

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

func _ready() -> void:
	asset_hint = %LblAssetHint
	asset_category_row = %AssetCategoryRow
	asset_grid = %AssetGrid
	member_grid = %MemberGrid
	marker_box = %MarkerBox
	effect_list = %EffectList
	tile_box = %TileBox
	template_list = %TemplateList
	widgets["member_grid"] = member_grid
	widgets["marker_box"] = marker_box
	widgets["tile_box"] = tile_box

	%BtnImportAssets.pressed.connect(func(): import_assets_pressed.emit())
	%BtnRefreshAssets.pressed.connect(func(): refresh_assets_pressed.emit())
	%BtnTriggerEffects.pressed.connect(func(): trigger_all_effects_pressed.emit())
	%BtnSaveTemplate.pressed.connect(func(): save_template_pressed.emit())
	%BtnRefreshTemplates.pressed.connect(func(): refresh_templates_pressed.emit())

	_fill_member_tokens()
	_fill_effect_presets()

func _fill_member_tokens() -> void:
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

func _fill_effect_presets() -> void:
	var fx_grid: GridContainer = %EffectGrid
	for preset_id_variant in MapEffectPresetsScript.PRESET_IDS:
		var preset_id := str(preset_id_variant)
		var preset := MapEffectPresetsScript.get_preset(preset_id)
		var btn := Button.new()
		btn.text = str(preset.get("emoji", "✨"))
		btn.tooltip_text = str(preset.get("label", preset_id))
		btn.custom_minimum_size = Vector2(42, 32)
		btn.pressed.connect(func(): effect_preset_pressed.emit(preset_id))
		fx_grid.add_child(btn)
