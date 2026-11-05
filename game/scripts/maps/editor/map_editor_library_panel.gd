extends VBoxContainer
class_name MapEditorLibraryPanel

## Onglet « Biblio ». Structure dans `scenes/map_editor/panels/library.tscn`.

const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")
const EmptyStateScript := preload("res://scripts/maps/editor/v2/empty_state.gd")

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
var asset_search: LineEdit
var asset_filter_row: HFlowContainer
var widgets: Dictionary = {}
var _asset_empty_state = null  # MapEditorEmptyState, construit à l'exécution.
var _asset_empty_update_queued := false

func _ready() -> void:
	asset_hint = %LblAssetHint
	asset_category_row = %AssetCategoryRow
	asset_grid = %AssetGrid
	asset_search = %AssetSearch
	asset_filter_row = %AssetFilterRow
	member_grid = %MemberGrid
	marker_box = %MarkerBox
	effect_list = %EffectList
	tile_box = %TileBox
	template_list = %TemplateList
	widgets["member_grid"] = member_grid
	widgets["marker_box"] = marker_box
	widgets["tile_box"] = tile_box

	_setup_asset_empty_state()

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

# ===========================================================================
# État vide « aucun résultat » de la bibliothèque
# ===========================================================================

## Construit l'état vide (juste après AssetGrid) et observe la grille, la
## recherche et les filtres pour l'afficher/masquer automatiquement.
func _setup_asset_empty_state() -> void:
	_asset_empty_state = EmptyStateScript.new()
	_asset_empty_state.setup("⌕", "Aucun objet", "Essayez un autre mot ou retirez les filtres.",
		"Effacer les filtres", clear_asset_filters)
	_asset_empty_state.visible = false
	add_child(_asset_empty_state)
	move_child(_asset_empty_state, asset_grid.get_index() + 1)
	asset_grid.child_entered_tree.connect(func(_n): _queue_asset_empty_update())
	asset_grid.child_exiting_tree.connect(func(_n): _queue_asset_empty_update())
	asset_filter_row.child_entered_tree.connect(func(_n): _queue_asset_empty_update())
	asset_filter_row.child_exiting_tree.connect(func(_n): _queue_asset_empty_update())
	asset_search.text_changed.connect(func(_t): _queue_asset_empty_update())

## Action « Effacer les filtres » : vide la recherche et réactive le filtre
## par défaut (« Tous ») via le callback existant de l'éditeur.
func clear_asset_filters() -> void:
	if asset_search != null:
		# Le setter text n'émet pas text_changed : émission manuelle pour que
		# l'éditeur réinitialise sa recherche et rafraîchisse la grille.
		asset_search.text = ""
		asset_search.text_changed.emit("")
	if asset_filter_row != null:
		for child in asset_filter_row.get_children():
			if child.is_queued_for_deletion() or not (child is BaseButton):
				continue
			var filter_btn := child as BaseButton
			# Premier bouton = « Tous » : s'il n'est pas actif, le réactiver
			# (l'émission de `pressed` déclenche le rafraîchissement de l'éditeur).
			if not filter_btn.button_pressed:
				filter_btn.pressed.emit()
			break
	_queue_asset_empty_update()

## Affiche l'état vide quand une recherche ou un filtre actif ne laisse
## aucune vignette dans la grille (fin de frame : les vignettes remplacées
## via queue_free ne sont plus comptées).
func _update_asset_empty_state() -> void:
	_asset_empty_update_queued = false
	if _asset_empty_state == null:
		return
	_asset_empty_state.visible = _asset_query_active() and _asset_result_count() == 0

func _queue_asset_empty_update() -> void:
	if _asset_empty_update_queued:
		return
	_asset_empty_update_queued = true
	_update_asset_empty_state.call_deferred()

## Vrai si la recherche contient du texte ou si un filtre autre que
## « Tous » (premier bouton) est actif.
func _asset_query_active() -> bool:
	if asset_search != null and asset_search.visible \
			and not asset_search.text.strip_edges().is_empty():
		return true
	if asset_filter_row != null and asset_filter_row.visible:
		for child in asset_filter_row.get_children():
			if child.is_queued_for_deletion() or not (child is BaseButton):
				continue
			return not (child as BaseButton).button_pressed
	return false

## Nombre de vignettes résultats vivantes. Le bouton « Importer un GLB… »
## n'est pas un bouton à bascule : il n'est jamais compté comme résultat.
func _asset_result_count() -> int:
	var count := 0
	for child in asset_grid.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is BaseButton and (child as BaseButton).toggle_mode:
			count += 1
	return count
