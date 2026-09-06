extends PanelContainer
class_name StoryLogPanel

## Journal de la partie. Structure dans `scenes/session/panels/story_log.tscn`.
##
## Chaque mise à jour réécrit le BBCode d'un bloc (comme l'ancien `_render_log`) :
## `append_text` après un premier `text = ""` n'affiche pas toujours la suite
## dans Godot 4.7, ce qui faisait disparaître Diffuser / Faire parler.

const META_FONT_SIZE := 11

@onready var _text: RichTextLabel = %LogText

var _entries: Array = []
var _last_line: String = ""

func reset(entries: Array) -> void:
	_entries = entries.duplicate()
	_rebuild()

func append(entry: Dictionary) -> void:
	_entries.append(entry)
	_rebuild()

## Dernière réplique lisible, pour le bandeau du HUD joueur.
func latest_line() -> String:
	return _last_line

func visible_text() -> String:
	if _text == null:
		return ""
	return _text.get_parsed_text()

func _rebuild() -> void:
	if not is_node_ready():
		await ready
	_text.clear()
	for entry_variant in _entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		_write(entry_variant)
	_scroll_to_end()

func _write(entry: Dictionary) -> void:
	var author := str(entry.get("author", entry.get("speaker", "Inconnu")))
	var entry_type := str(entry.get("type", "player"))
	var body := str(entry.get("text", ""))
	var time := str(entry.get("time", ""))
	_last_line = "%s — %s" % [author, body]

	var author_hex := ThemeColors.get_bbcode_color(ThemeColors.log_color(entry_type))
	var meta_hex := ThemeColors.get_bbcode_color(ThemeColors.TEXT_MUTED)
	_text.append_text("[color=#%s][b]%s[/b][/color]  [color=#%s][font_size=%d]%s[/font_size][/color]\n%s\n\n" % [
		author_hex, author, meta_hex, META_FONT_SIZE, time, body
	])

func _scroll_to_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(_text):
		return
	var lines := _text.get_line_count()
	if lines > 0:
		_text.scroll_to_line(maxi(0, lines - 1))
