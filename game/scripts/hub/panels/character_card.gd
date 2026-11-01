extends CardBase

## Fiche perso / bot dans l'éditeur. Enveloppe : `scenes/shared/card_base.tscn`.

signal edit_pressed(entry: Dictionary, is_bot: bool)
signal delete_pressed(entry_id: String, is_bot: bool)

var _entry: Dictionary = {}
var _is_bot: bool = false

func _ready() -> void:
	if not LocaleSettings.locale_changed.is_connected(_on_locale_changed):
		LocaleSettings.locale_changed.connect(_on_locale_changed)

func _on_locale_changed(_locale: String) -> void:
	if not _entry.is_empty():
		setup(_entry)

func setup(c: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_entry = c.duplicate(true)
	reset_card()
	_is_bot = str(c.get("_entityKind", "")) == "bot"
	var r: String = str(c.get("roster", "general"))
	var investigation := r == "investigation"
	set_title(("🤖 " if _is_bot else "🧙 ") + str(c.get("name", "Sans nom")))
	set_badge(
		"Enquête" if investigation else "Aventure",
		ThemeColors.INVESTIGATION_ACCENT if investigation else ThemeColors.GOLD
	)
	var tier: String = GameData.get_ruleset_tier(c)
	var tier_label: String = {"simple": "Simple", "medium": "Classique", "complete": "Complet"}.get(tier, "Classique")
	set_meta_line("%s · %s · %s" % [tier_label, c.get("race", "?"), c.get("class", "?")])
	add_body(GameData.format_character_summary(c), "MutedLabel")

	var edit := add_action("Modifier")
	edit.pressed.connect(func(): edit_pressed.emit(_entry, _is_bot))
	var del := add_action("Supprimer", "DangerButton")
	del.pressed.connect(func(): delete_pressed.emit(str(_entry.get("id", "")), _is_bot))
