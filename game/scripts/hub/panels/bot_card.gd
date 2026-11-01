extends CardBase
class_name BotCard

## Carte compagnon du hub. Enveloppe : `scenes/shared/card_base.tscn`.

signal delete_pressed(bot_id: String, bot_name: String)

var _bot_id: String = ""
var _bot_name: String = ""
var _bot: Dictionary = {}

func _ready() -> void:
	if not LocaleSettings.locale_changed.is_connected(_on_locale_changed):
		LocaleSettings.locale_changed.connect(_on_locale_changed)

func _on_locale_changed(_locale: String) -> void:
	if not _bot.is_empty():
		setup(_bot)

func setup(bot: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_bot = bot.duplicate(true)
	reset_card()
	_bot_id = str(bot.get("id", ""))
	_bot_name = str(bot.get("name", "Bot"))
	set_title("🤖 " + _bot_name)
	var investigation := GameData.is_investigation_bot(bot)
	set_badge(
		tr("🔍 Enquête") if investigation else tr("⚔️ Aventure"),
		ThemeColors.INVESTIGATION_ACCENT if investigation else ThemeColors.ONESHOT_ACCENT
	)
	set_meta_line("%s · %s" % [bot.get("race", ""), bot.get("class", "")])
	var personality := _personality_label(str(bot.get("personality", "")))
	if not personality.is_empty():
		add_body(personality.to_upper(), "BadgeLabel")
	var traits: Array = bot.get("traits", [])
	if not traits.is_empty():
		var localized := PackedStringArray()
		for trait_value in traits:
			localized.append(tr(str(trait_value)))
		add_body(", ".join(localized))
	var stats: Dictionary = bot.get("stats", {})
	add_body(tr("PV %d · CA %d · FOR %d") % [bot.get("hp", 10), bot.get("ac", 10), stats.get("str", 10)], "MutedLabel")

	var del := add_action(tr("Supprimer"), "DangerButton")
	del.pressed.connect(func(): delete_pressed.emit(_bot_id, _bot_name))

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
