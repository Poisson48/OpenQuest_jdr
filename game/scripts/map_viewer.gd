extends Control

@onready var grid: GridContainer = %TileGrid
@onready var title_lbl: Label = %MapTitle

var _tile_defs: Dictionary = {}
var _cell_size := 32

func _ready() -> void:
	%BtnBack.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	_load_tile_defs()
	_render_demo_map()

func _load_tile_defs() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/tiles.json"))
	if data is Dictionary and data.has("local"):
		_tile_defs = data["local"]

func _render_demo_map() -> void:
	title_lbl.text = "🗺️ Carte démo — Crypte (aperçu Godot)"
	for child in grid.get_children():
		child.queue_free()

	# Petite carte 16x10 inspirée d'un donjon
	var layout := [
		"wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall", "wall",
		"wall", "floor", "floor", "floor", "floor", "stone", "stone", "floor", "floor", "floor", "water", "water", "floor", "floor", "floor", "wall",
		"wall", "floor", "grass", "grass", "floor", "stone", "stone", "floor", "forest", "forest", "water", "water", "floor", "road", "road", "wall",
		"wall", "floor", "grass", "floor", "floor", "floor", "floor", "floor", "floor", "floor", "floor", "floor", "floor", "road", "floor", "wall",
		"wall", "floor", "floor", "floor", "sand", "sand", "floor", "floor", "floor", "floor", "stone", "stone", "floor", "floor", "floor", "wall",
		"wall", "floor", "floor", "sand", "sand", "sand", "floor", "floor", "floor", "stone", "stone", "floor", "floor", "floor", "floor", "wall",
		"wall", "floor", "floor", "floor", "floor", "floor", "floor", "road", "road", "floor", "floor", "floor", "floor", "floor", "floor", "wall",
		"wall", "floor", "floor", "floor", "floor", "floor", "floor", "road", "road", "floor", "floor", "floor", "floor", "floor", "floor", "wall",
		"wall", "wall", "wall", "wall", "wall", "floor", "floor", "floor", "floor", "floor", "wall", "wall", "wall", "wall", "wall", "wall",
	]

	grid.columns = 16
	for tile_id in layout:
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(_cell_size, _cell_size)
		rect.color = _color_for_tile(tile_id)
		grid.add_child(rect)

	# Token joueur
	var token := PanelContainer.new()
	token.custom_minimum_size = Vector2(_cell_size - 4, _cell_size - 4)
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.GOLD
	style.set_corner_radius_all(4)
	token.add_theme_stylebox_override("panel", style)
	token.position = Vector2(5 * _cell_size + 2, 3 * _cell_size + 2)
	add_child(token)

	var token_lbl := Label.new()
	token_lbl.text = "⚔️"
	token_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	token.add_child(token_lbl)

func _color_for_tile(tile_id: String) -> Color:
	if _tile_defs.has(tile_id):
		return Color.html(_tile_defs[tile_id].get("color", "#444444"))
	match tile_id:
		"grass": return Color.html("#3a6b45")
		"wall": return Color.html("#2a2520")
		"floor": return Color.html("#4a4035")
		_: return Color.html("#333333")
