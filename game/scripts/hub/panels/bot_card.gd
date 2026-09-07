extends PanelContainer
class_name BotCard

## Carte compagnon du hub. Structure dans `scenes/hub/panels/bot_card.tscn`.

signal delete_pressed(bot_id: String, bot_name: String)

@onready var _name: Label = %LblName
@onready var _mode: Label = %LblMode
@onready var _meta: Label = %LblMeta
@onready var _tag: Label = %LblTag
@onready var _traits: Label = %LblTraits
@onready var _stats: Label = %LblStats

var _bot_id: String = ""
var _bot_name: String = ""
var _bot: Dictionary = {}

func _ready() -> void:
	%BtnDelete.pressed.connect(func(): delete_pressed.emit(_bot_id, _bot_name))
	if not LocaleSettings.locale_changed.is_connected(_on_locale_changed):
		LocaleSettings.locale_changed.connect(_on_locale_changed)

func _on_locale_changed(_locale: String) -> void:
	if not _bot.is_empty():
		setup(_bot)

func setup(bot: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_bot = bot.duplicate(true)
	_bot_id = str(bot.get("id", ""))
	_bot_name = str(bot.get("name", "Bot"))
	_name.text = "🤖 " + _bot_name
	if GameData.is_investigation_bot(bot):
		_mode.text = tr("🔍 Enquête")
		_mode.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT)
	else:
		_mode.text = tr("⚔️ Aventure")
		_mode.add_theme_color_override("font_color", ThemeColors.ONESHOT_ACCENT)
	_meta.text = "%s · %s" % [bot.get("race", ""), bot.get("class", "")]
	_tag.text = _personality_label(str(bot.get("personality", ""))).to_upper()
	var traits: Array = bot.get("traits", [])
	_traits.visible = not traits.is_empty()
	var localized_traits: PackedStringArray = []
	for trait_value in traits:
		localized_traits.append(tr(str(trait_value)))
	_traits.text = ", ".join(localized_traits)
	var stats: Dictionary = bot.get("stats", {})
	_stats.text = tr("PV %d · CA %d · FOR %d") % [bot.get("hp", 10), bot.get("ac", 10), stats.get("str", 10)]
	%BtnDelete.text = tr("Supprimer")

func _personality_label(code: String) -> String:
	match code.strip_edges().to_lower():
		"cautious":
			return tr("Prudent")
		"curious":
			return tr("Curieux")
		"bold":
			return tr("Audacieux")
		"diplomatic":
			return tr("Diplomatique")
		"fierce":
			return tr("Féroce")
		"cheerful":
			return tr("Enjoué")
		"mystic":
			return tr("Mystique")
		"":
			return ""
		_:
			# Texte libre saisi dans l'éditeur : tente tr(), sinon affiche tel quel.
			return tr(code)
