extends VBoxContainer

## Bibliothèque 2D : tuiles, marqueurs, décors sprite.

signal tile_picked(tile_id: String)
signal marker_picked(marker_id: String)
signal prop_picked(asset_path: String, size: float)
signal refresh_assets_pressed

const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

var _tile_host: HBoxContainer
var _marker_host: HBoxContainer
var _prop_host: GridContainer
var _category_row: HBoxContainer
var _prop_category: String = "buildings"

func _ready() -> void:
	_tile_host = %TileBox
	_marker_host = %MarkerBox
	_prop_host = %PropGrid
	_category_row = %PropCategoryRow
	%BtnRefreshProps.pressed.connect(func():
		refresh_assets_pressed.emit()
		rebuild_props()
	)
	_fill_categories()

func rebuild_tiles(map_data: Dictionary, selected: String) -> void:
	_clear(_tile_host)
	var tiles: Dictionary = MapData.get_tile_palette(map_data)
	for tile_id in tiles.keys():
		var def: Dictionary = tiles[tile_id]
		var btn := Button.new()
		btn.text = str(def.get("label", tile_id))
		btn.toggle_mode = true
		btn.button_pressed = tile_id == selected
		btn.custom_minimum_size = Vector2(0, 32)
		var style := StyleBoxFlat.new()
		style.bg_color = Color.html(str(def.get("color", "#444444")))
		style.set_corner_radius_all(4)
		style.content_margin_left = 8
		style.content_margin_right = 8
		btn.add_theme_stylebox_override("normal", style)
		var tid := str(tile_id)
		btn.pressed.connect(func(): tile_picked.emit(tid))
		_tile_host.add_child(btn)

func rebuild_markers(map_data: Dictionary, selected: String) -> void:
	_clear(_marker_host)
	for marker_id in MapData.get_editor_marker_types(map_data):
		var btn := Button.new()
		btn.text = "%s %s" % [MapData.get_marker_emoji(marker_id), MapData.get_marker_label(marker_id)]
		btn.toggle_mode = true
		btn.button_pressed = marker_id == selected
		btn.custom_minimum_size = Vector2(0, 32)
		var mid := str(marker_id)
		btn.pressed.connect(func(): marker_picked.emit(mid))
		_marker_host.add_child(btn)

func rebuild_props() -> void:
	_clear(_prop_host)
	var assets: Array = AssetLibraryScript.list_assets(_prop_category)
	if assets.is_empty():
		var empty := Label.new()
		empty.text = "Aucun décor dans cette catégorie."
		empty.theme_type_variation = &"CaptionLabel"
		_prop_host.add_child(empty)
		return
	for asset_variant in assets:
		var asset: Dictionary = asset_variant
		var btn := Button.new()
		btn.text = str(asset.get("name", "Décor"))
		btn.tooltip_text = str(asset.get("path", ""))
		btn.custom_minimum_size = Vector2(0, 36)
		var path := str(asset.get("path", ""))
		var size := float(asset.get("size", 2.0))
		btn.pressed.connect(func(): prop_picked.emit(path, size))
		_prop_host.add_child(btn)

func _fill_categories() -> void:
	_clear(_category_row)
	for entry_variant in AssetLibraryScript.CATEGORIES:
		var entry: Dictionary = entry_variant
		var btn := Button.new()
		btn.text = "%s %s" % [entry.get("icon", ""), entry.get("label", "")]
		btn.toggle_mode = true
		btn.button_pressed = str(entry.get("id", "")) == _prop_category
		var cid := str(entry.get("id", ""))
		btn.pressed.connect(func():
			_prop_category = cid
			_fill_categories()
			rebuild_props()
		)
		_category_row.add_child(btn)

func _clear(host: Node) -> void:
	if host == null:
		return
	for child in host.get_children():
		child.queue_free()
