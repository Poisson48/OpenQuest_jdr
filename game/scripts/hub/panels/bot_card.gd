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

func _ready() -> void:
	%BtnDelete.pressed.connect(func(): delete_pressed.emit(_bot_id, _bot_name))

func setup(bot: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_bot_id = str(bot.get("id", ""))
	_bot_name = str(bot.get("name", "Bot"))
	_name.text = "🤖 " + _bot_name
	if GameData.is_investigation_bot(bot):
		_mode.text = "🔍 Enquête"
		_mode.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT)
	else:
		_mode.text = "⚔️ Aventure"
		_mode.add_theme_color_override("font_color", ThemeColors.ONESHOT_ACCENT)
	_meta.text = "%s · %s" % [bot.get("race", ""), bot.get("class", "")]
	_tag.text = str(bot.get("personality", "")).to_upper()
	var traits: Array = bot.get("traits", [])
	_traits.visible = not traits.is_empty()
	_traits.text = ", ".join(traits)
	var stats: Dictionary = bot.get("stats", {})
	_stats.text = "PV %d · CA %d · FOR %d" % [bot.get("hp", 10), bot.get("ac", 10), stats.get("str", 10)]
