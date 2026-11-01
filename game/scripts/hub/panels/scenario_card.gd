extends PanelContainer

## Carte scénario du catalogue. Structure dans `scenario_card.tscn`.

signal edit_pressed(scenario_id: String)
signal view_pressed(scenario: Dictionary)
signal play_pressed(scenario_id: String)
signal delete_pressed(scenario_id: String, title: String)
signal publish_pressed(scenario_id: String, title: String)
signal unpublish_pressed(scenario_id: String, title: String)

var _scn: Dictionary = {}

## Menu « ⋯ » : actions secondaires pour ne pas surcharger la carte.
const MENU_VIEW := 0
const MENU_PUBLISH := 1
const MENU_UNPUBLISH := 2
const MENU_DELETE := 3

func _ready() -> void:
	%BtnEdit.pressed.connect(func(): edit_pressed.emit(str(_scn.get("id", ""))))
	%BtnPlay.pressed.connect(func(): play_pressed.emit(str(_scn.get("id", ""))))
	var popup: PopupMenu = %MenuMore.get_popup()
	popup.add_item("👁 Voir détails", MENU_VIEW)
	popup.add_item("📚 Publier dans le catalogue", MENU_PUBLISH)
	popup.add_item("📝 Remettre en brouillon", MENU_UNPUBLISH)
	popup.add_item("🗑 Supprimer", MENU_DELETE)
	popup.id_pressed.connect(_on_menu_action)

func _on_menu_action(id: int) -> void:
	var scn_id := str(_scn.get("id", ""))
	var title := str(_scn.get("title", "Scénario"))
	match id:
		MENU_VIEW:
			view_pressed.emit(_scn)
		MENU_PUBLISH:
			publish_pressed.emit(scn_id, title)
		MENU_UNPUBLISH:
			unpublish_pressed.emit(scn_id, title)
		MENU_DELETE:
			delete_pressed.emit(scn_id, title)

func setup(scn: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_scn = scn.duplicate(true)
	%LblTitle.text = str(scn.get("title", "Sans titre"))
	var mode := GameData.get_scenario_mode_label(scn)
	var badge: Label = %LblBadge
	match mode:
		"investigation":
			badge.text = "🔍 Enquête longue" if scn.get("questFormat", "oneshot") == "long" else "🔍 Enquête courte"
			badge.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT)
		"long":
			badge.text = "🏰 Campagne"
			badge.add_theme_color_override("font_color", ThemeColors.GOLD)
		_:
			badge.text = "⚔️ One-shot"
			badge.add_theme_color_override("font_color", ThemeColors.ONESHOT_ACCENT)
	var synopsis := str(scn.get("synopsis", "Pas de synopsis."))
	if synopsis.length() > 120:
		synopsis = synopsis.substr(0, 117) + "..."
	%LblSynopsis.text = synopsis
	var scenes: Array = scn.get("scenes", [])
	var npcs: Array = scn.get("npcs", [])
	%LblMeta.text = "📜 %d scènes · 👤 %d PNJ" % [scenes.size(), npcs.size()]

	var is_draft := GameData.is_draft_scenario(scn)
	var can_unpublish := GameData.is_catalog_scenario(scn) and not GameData.DEMO_SCENARIO_IDS.has(str(scn.get("id", "")))
	%BtnPlay.visible = not is_draft
	var popup: PopupMenu = %MenuMore.get_popup()
	popup.set_item_disabled(popup.get_item_index(MENU_PUBLISH), not is_draft)
	popup.set_item_disabled(popup.get_item_index(MENU_UNPUBLISH), not can_unpublish)
