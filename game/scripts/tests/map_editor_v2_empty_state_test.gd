extends SceneTree

## Tests du composant d'état vide de l'éditeur v2 (MapEditorEmptyState).

const EmptyStateScript := preload("res://scripts/maps/editor/v2/empty_state.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame

	# --- 1) Setup avec action ---------------------------------------------
	var state: VBoxContainer = EmptyStateScript.new()
	get_root().add_child(state)
	state.setup("🗀", "Aucun objet", "Ajoutez un objet pour commencer.", "Ajouter", _on_action)
	await process_frame

	var icon := _label_at(state, 0)
	var title := _label_at(state, 1)
	var text := _label_at(state, 2)
	var button := _button_of(state)

	_assert("icon_present", icon != null and icon.text == "🗀")
	_assert("title_present", title != null and title.text == "Aucun objet")
	_assert("text_present", text != null and text.text == "Ajoutez un objet pour commencer.")
	_assert("button_present", button != null and button.text == "Ajouter")

	_action_fired = false
	if button != null:
		button.pressed.emit()
	_assert("action_emitted_on_click", _action_fired)

	# --- 2) Setup sans action ---------------------------------------------
	state.setup("🗀", "Aucun objet", "Ajoutez un objet pour commencer.")
	await process_frame
	_assert("no_button_without_action", _button_of(state) == null)

	state.queue_free()
	await process_frame

	if _failed:
		print("map_editor_v2_empty_state_test:FAIL")
		quit(1)
		return
	print("map_editor_v2_empty_state_test:PASS")
	quit(0)


var _action_fired := false


func _on_action() -> void:
	_action_fired = true


func _label_at(state: VBoxContainer, index: int) -> Label:
	if index >= state.get_child_count():
		return null
	return state.get_child(index) as Label


func _button_of(state: VBoxContainer) -> Button:
	for child in state.get_children():
		if child is Button:
			return child as Button
	return null


func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
