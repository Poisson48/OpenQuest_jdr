extends PanelContainer
class_name MapCard

## Carte du catalogue hub. Structure dans `scenes/hub/panels/map_card.tscn`.

signal preview_pressed(map_id: String)
signal edit_pressed(map_id: String)
signal delete_pressed(map_id: String, title: String)
signal demo_pressed

const MapModeScript := preload("res://scripts/maps/map_mode.gd")

@onready var _badge: Label = %LblBadge
@onready var _title: Label = %LblTitle
@onready var _scenario: Label = %LblScenario
@onready var _desc: Label = %LblDesc
@onready var _mode: Label = %LblMode
@onready var _meta: Label = %LblMeta
@onready var _btn_demo: Button = %BtnDemo

var _map_id: String = ""
var _title_text: String = ""

func _ready() -> void:
	%BtnPreview.pressed.connect(func(): preview_pressed.emit(_map_id))
	%BtnEdit.pressed.connect(func(): edit_pressed.emit(_map_id))
	%BtnDelete.pressed.connect(func(): delete_pressed.emit(_map_id, _title_text))
	_btn_demo.pressed.connect(func(): demo_pressed.emit())

func setup(map_data: Dictionary, category: String) -> void:
	if not is_node_ready():
		await ready
	_map_id = str(map_data.get("id", ""))
	_title_text = str(map_data.get("title", "Sans titre"))
	var w: int = int(map_data.get("width", 0))
	var h: int = int(map_data.get("height", 0))
	var badge_icon := "🌍" if category == "world" else ("🔍" if category == "investigation" else "⚔️")
	_badge.text = "%s %d×%d · %d carrés" % [badge_icon, w, h, w * h]
	_title.text = _title_text

	var scenario_id: String = str(map_data.get("scenarioId", ""))
	_scenario.visible = not scenario_id.is_empty()
	_scenario.text = "Scénario : %s" % scenario_id

	var desc_text: String = str(map_data.get("description", ""))
	_desc.visible = not desc_text.is_empty()
	_desc.text = desc_text

	var complex_map := MapData.is_complex_map(map_data)
	_mode.text = MapModeScript.badge(MapData.get_render_mode(map_data))
	_mode.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT if complex_map else ThemeColors.TEXT_MUTED)

	var link_count: int = map_data.get("locationLinks", []).size()
	if category == "world" and link_count > 0:
		_meta.text = "%d marqueur(s) · %d scène(s) liée(s)" % [map_data.get("markers", []).size(), link_count]
	elif category != "world":
		var world_links: Array = MapData.get_world_links_to_map(_map_id)
		if world_links.is_empty():
			_meta.text = "%d marqueur(s) · non liée au monde" % map_data.get("markers", []).size()
		else:
			_meta.text = "%d marqueur(s) · intégrée dans %d carte(s) monde" % [map_data.get("markers", []).size(), world_links.size()]
	else:
		_meta.text = "%d marqueur(s)" % map_data.get("markers", []).size()

	_btn_demo.visible = scenario_id == "demo-valbois"
