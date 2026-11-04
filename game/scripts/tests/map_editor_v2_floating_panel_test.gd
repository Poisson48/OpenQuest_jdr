extends SceneTree

## Test du panneau flottant v2 (MapEditorFloatingPanel).
## Vérifie la barre de titre (libellé + bouton fermer), la présence du contenu,
## l'ouverture à une position donnée et l'émission de dismissed au clic sur le
## bouton fermer.

const FloatingPanelScript = preload("res://scripts/maps/editor/v2/floating_panel.gd")

var _failed := false
var _dismissed_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame

	# --- Construction du panneau + contenu via l'API publique. ---
	var panel = FloatingPanelScript.new()
	get_root().add_child(panel)

	var content := Label.new()
	content.name = "ContentLabel"
	content.text = "Hello"

	panel.setup("Test", content)
	await process_frame

	# --- Barre de titre : libellé 'Test' + bouton fermer présents. ---
	var title_label := _find_node(panel, "TitleLabel") as Label
	_assert("title_label_present", title_label != null)
	_assert("title_text_is_test", title_label != null and title_label.text == "Test")

	var close_button := _find_node(panel, "CloseButton") as Button
	_assert("close_button_present", close_button != null)

	# --- Contenu : le Label passé à setup est présent dans le panneau. ---
	var content_host := _find_node(panel, "ContentHost")
	_assert("content_host_present", content_host != null)
	_assert("content_present", content.get_parent() == content_host and content.text == "Hello")
	_assert("content_host_is_vbox", content_host is VBoxContainer)

	# --- Ouverture à une position donnée. ---
	panel.dismissed.connect(_on_dismissed)
	panel.open_at(Vector2(120, 80))
	await process_frame
	_assert("panel_visible_after_open", panel.visible)
	_assert("panel_position_set", panel.position == Vector2i(120, 80))

	# --- Clic sur le bouton fermer : dismissed émis + panneau caché. ---
	close_button.pressed.emit()
	_assert("dismissed_emitted_on_close", _dismissed_count == 1)
	_assert("panel_hidden_after_close", not panel.visible)

	# --- Bilan. ---
	if _failed:
		print("map_editor_v2_floating_panel_test:FAIL")
		quit(1)
	else:
		print("map_editor_v2_floating_panel_test:PASS")
		quit(0)


# ---------------------------------------------------------------------------
# Helpers de test
# ---------------------------------------------------------------------------

## Compte les émissions de dismissed.
func _on_dismissed() -> void:
	_dismissed_count += 1


## Vérifie une condition et trace le résultat.
func _assert(assert_name: String, cond: bool) -> void:
	if cond:
		print("  OK   ", assert_name)
	else:
		_failed = true
		print("  FAIL ", assert_name)


## Recherche récursive d'un nœud par nom.
func _find_node(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found := _find_node(child, target_name)
		if found != null:
			return found
	return null
