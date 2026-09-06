extends PanelContainer

## Carte scénario du catalogue. Structure dans `scenario_card.tscn`.

signal edit_pressed(scenario_id: String)
signal view_pressed(scenario: Dictionary)
signal play_pressed(scenario_id: String)
signal delete_pressed(scenario_id: String, title: String)

var _scn: Dictionary = {}

func _ready() -> void:
	%BtnEdit.pressed.connect(func(): edit_pressed.emit(str(_scn.get("id", ""))))
	%BtnView.pressed.connect(func(): view_pressed.emit(_scn))
	%BtnPlay.pressed.connect(func(): play_pressed.emit(str(_scn.get("id", ""))))
	%BtnDelete.pressed.connect(func(): delete_pressed.emit(str(_scn.get("id", "")), str(_scn.get("title", "Scénario"))))

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
