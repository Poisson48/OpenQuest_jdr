extends PanelContainer
class_name GmNotesPanel

## Bloc-notes du MJ, attaché à la scène en cours.
## Structure dans `scenes/session/panels/gm_notes.tscn`.
##
## Sauvegarde différée : on n'écrit qu'après une pause de frappe, pour que
## chaque touche ne déclenche pas une écriture disque.

signal notes_changed(text: String)

@onready var _status: Label = %LblStatus
@onready var _editor: TextEdit = %NotesInput
@onready var _timer: Timer = %SaveTimer

var _suppress: bool = false

func _ready() -> void:
	_editor.text_changed.connect(_on_text_changed)
	_timer.timeout.connect(_flush)

func set_text(text: String) -> void:
	if not is_node_ready():
		await ready
	if _editor.text == text:
		return
	_suppress = true
	var caret := _editor.get_caret_line()
	_editor.text = text
	_editor.set_caret_line(mini(caret, maxi(0, _editor.get_line_count() - 1)))
	_suppress = false
	_status.text = ""

func set_scene_label(label: String) -> void:
	_status.tooltip_text = label

func flush_now() -> void:
	if _timer.is_stopped():
		return
	_timer.stop()
	_flush()

func _on_text_changed() -> void:
	if _suppress:
		return
	_status.text = "…"
	_timer.start()

func _flush() -> void:
	_status.text = "enregistré"
	notes_changed.emit(_editor.text)
