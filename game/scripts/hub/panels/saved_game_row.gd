extends PanelContainer
class_name SavedGameRow

## Une partie en cours, réutilisée par le hub et le menu. Structure dans
## `scenes/hub/panels/saved_game_row.tscn`.

signal resume_pressed(game_id: String)
signal delete_pressed(game_id: String, title: String)

@onready var _title: Label = %LblTitle
@onready var _meta: Label = %LblMeta

var _game_id: String = ""
var _title_text: String = ""

func _ready() -> void:
	%BtnResume.pressed.connect(func(): resume_pressed.emit(_game_id))
	%BtnDelete.pressed.connect(func(): delete_pressed.emit(_game_id, _title_text))

func setup(game: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_game_id = str(game.get("id", ""))
	var display := GameData.get_scenario_display_title(game.get("scenarioId", ""))
	_title_text = str(game.get("scenarioTitle", display))
	_title.text = "« %s »" % display
	_meta.text = GameData.get_game_party_summary(game)
