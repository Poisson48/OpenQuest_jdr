extends PanelContainer

## Fiche perso / bot dans l'éditeur. Structure dans `character_card.tscn`.

signal edit_pressed(entry: Dictionary, is_bot: bool)
signal delete_pressed(entry_id: String, is_bot: bool)

var _entry: Dictionary = {}
var _is_bot: bool = false

func _ready() -> void:
	%BtnEdit.pressed.connect(func(): edit_pressed.emit(_entry, _is_bot))
	%BtnDelete.pressed.connect(func(): delete_pressed.emit(str(_entry.get("id", "")), _is_bot))

func setup(c: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_entry = c.duplicate(true)
	_is_bot = str(c.get("_entityKind", "")) == "bot"
	%LblName.text = ("🤖 " if _is_bot else "🧙 ") + str(c.get("name", "Sans nom"))
	var tier: String = GameData.get_ruleset_tier(c)
	%LblTier.text = {"simple": "Simple", "medium": "Classique", "complete": "Complet"}.get(tier, "Classique")
	var r: String = str(c.get("roster", "general"))
	%LblRoster.text = "Enquête" if r == "investigation" else "Aventure"
	%LblRoster.add_theme_color_override(
		"font_color",
		ThemeColors.INVESTIGATION_ACCENT if r == "investigation" else ThemeColors.GOLD
	)
	%LblMeta.text = "%s · %s" % [c.get("race", "?"), c.get("class", "?")]
	%LblStats.text = GameData.format_character_summary(c)
