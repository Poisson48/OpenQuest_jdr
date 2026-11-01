extends CardBase
class_name MapCard

## Carte du catalogue hub. Enveloppe : `scenes/shared/card_base.tscn`.

signal preview_pressed(map_id: String)
signal edit_pressed(map_id: String)
signal delete_pressed(map_id: String, title: String)
signal publish_pressed(map_id: String, title: String)
signal unpublish_pressed(map_id: String, title: String)
signal demo_pressed

## Menu « ⋯ » : actions secondaires regroupées.
const MENU_DEMO := 0
const MENU_PUBLISH := 1
const MENU_UNPUBLISH := 2
const MENU_DELETE := 3

const MapModeScript := preload("res://scripts/maps/map_mode.gd")

var _map_id: String = ""
var _title_text: String = ""
var _menu: MenuButton

func _ready() -> void:
	overflow_selected.connect(_on_menu_action)

func setup(map_data: Dictionary, category: String) -> void:
	if not is_node_ready():
		await ready
	_map_id = str(map_data.get("id", ""))
	_title_text = str(map_data.get("title", "Sans titre"))
	reset_card()

	set_title(_title_text)
	var w: int = int(map_data.get("width", 0))
	var h: int = int(map_data.get("height", 0))
	var badge_icon := "🌍" if category == "world" else ("🔍" if category == "investigation" else "⚔️")
	set_badge("%s %d×%d · %d carrés" % [badge_icon, w, h, w * h], ThemeColors.GOLD)

	var scenario_id: String = str(map_data.get("scenarioId", ""))
	if not scenario_id.is_empty():
		add_body("Scénario : %s" % scenario_id, "CaptionLabel")

	var desc_text: String = str(map_data.get("description", ""))
	if not desc_text.is_empty():
		add_body(desc_text, "MutedLabel")

	var complex_map := MapData.is_complex_map(map_data)
	var mode_lbl := add_body(MapModeScript.badge(MapData.get_render_mode(map_data)), "CaptionLabel")
	mode_lbl.add_theme_color_override(
		"font_color",
		ThemeColors.GOLD_LIGHT if complex_map else ThemeColors.TEXT_MUTED
	)

	var link_count: int = map_data.get("locationLinks", []).size()
	if category == "world" and link_count > 0:
		add_body("%d marqueur(s) · %d scène(s) liée(s)" % [map_data.get("markers", []).size(), link_count], "CaptionLabel")
	elif category != "world":
		var world_links: Array = MapData.get_world_links_to_map(_map_id)
		if world_links.is_empty():
			add_body("%d marqueur(s) · non liée au monde" % map_data.get("markers", []).size(), "CaptionLabel")
		else:
			add_body("%d marqueur(s) · intégrée dans %d carte(s) monde" % [map_data.get("markers", []).size(), world_links.size()], "CaptionLabel")
	else:
		add_body("%d marqueur(s)" % map_data.get("markers", []).size(), "CaptionLabel")

	var preview := add_action("Aperçu", "", true)
	preview.pressed.connect(func(): preview_pressed.emit(_map_id))
	var edit := add_action("Modifier", "", true)
	edit.pressed.connect(func(): edit_pressed.emit(_map_id))
	_menu = add_overflow([
		"🎲 Jouer avec Kael",
		"📚 Publier",
		"📝 Remettre en brouillon",
		"🗑 Supprimer",
	])

	var is_draft := MapData.is_draft_map(map_data)
	var is_demo := MapData.is_demo_map_id(_map_id)
	var can_unpublish := MapData.is_catalog_map(map_data) and not is_demo
	set_overflow_enabled(_menu, MENU_DEMO, scenario_id == "demo-valbois")
	set_overflow_enabled(_menu, MENU_PUBLISH, is_draft)
	set_overflow_enabled(_menu, MENU_UNPUBLISH, can_unpublish)
	set_overflow_enabled(_menu, MENU_DELETE, not is_demo)

func _on_menu_action(id: int) -> void:
	match id:
		MENU_DEMO:
			demo_pressed.emit()
		MENU_PUBLISH:
			publish_pressed.emit(_map_id, _title_text)
		MENU_UNPUBLISH:
			unpublish_pressed.emit(_map_id, _title_text)
		MENU_DELETE:
			delete_pressed.emit(_map_id, _title_text)
