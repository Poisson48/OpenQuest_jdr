extends CardBase

## Carte scénario du catalogue. Enveloppe : `scenes/shared/card_base.tscn`.

signal edit_pressed(scenario_id: String)
signal view_pressed(scenario: Dictionary)
signal play_pressed(scenario_id: String)
signal delete_pressed(scenario_id: String, title: String)
signal publish_pressed(scenario_id: String, title: String)
signal unpublish_pressed(scenario_id: String, title: String)

## Menu « ⋯ » : actions secondaires pour ne pas surcharger la carte.
const MENU_VIEW := 0
const MENU_PUBLISH := 1
const MENU_UNPUBLISH := 2
const MENU_DELETE := 3

var _scn: Dictionary = {}
var _btn_play: Button
var _menu: MenuButton

func _ready() -> void:
	if not LocaleSettings.locale_changed.is_connected(_on_locale_changed):
		LocaleSettings.locale_changed.connect(_on_locale_changed)
	overflow_selected.connect(_on_menu_action)

func _on_locale_changed(_locale: String) -> void:
	if not _scn.is_empty():
		setup(_scn)

func setup(scn: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_scn = scn.duplicate(true)
	reset_card()

	set_title(str(scn.get("title", "Sans titre")))
	var mode := GameData.get_scenario_mode_label(scn)
	match mode:
		"investigation":
			set_badge(
				"🔍 Enquête longue" if scn.get("questFormat", "oneshot") == "long" else "🔍 Enquête courte",
				ThemeColors.INVESTIGATION_ACCENT
			)
		"long":
			set_badge("🏰 Campagne", ThemeColors.GOLD)
		_:
			set_badge("⚔️ One-shot", ThemeColors.ONESHOT_ACCENT)

	var synopsis := str(scn.get("synopsis", "Pas de synopsis."))
	if synopsis.length() > 120:
		synopsis = synopsis.substr(0, 117) + "..."
	add_body(synopsis, "MutedLabel")

	var scenes: Array = scn.get("scenes", [])
	var npcs: Array = scn.get("npcs", [])
	add_body("📜 %d scènes · 👤 %d PNJ" % [scenes.size(), npcs.size()], "CaptionLabel")

	var scn_id := str(scn.get("id", ""))
	var title := str(scn.get("title", "Scénario"))
	_btn_play = add_action("🎮 Lancer", "AccentButton", true)
	_btn_play.pressed.connect(func(): play_pressed.emit(scn_id))
	var edit := add_action("✏️ Modifier", "", true)
	edit.pressed.connect(func(): edit_pressed.emit(scn_id))
	_menu = add_overflow([
		"👁 Voir détails",
		"📚 Publier dans le catalogue",
		"📝 Remettre en brouillon",
		"🗑 Supprimer",
	])

	var is_draft := GameData.is_draft_scenario(scn)
	var can_unpublish := GameData.is_catalog_scenario(scn) and not GameData.DEMO_SCENARIO_IDS.has(scn_id)
	_btn_play.visible = not is_draft
	set_overflow_enabled(_menu, MENU_PUBLISH, is_draft)
	set_overflow_enabled(_menu, MENU_UNPUBLISH, can_unpublish)

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
