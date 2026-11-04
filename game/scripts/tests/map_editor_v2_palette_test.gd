extends SceneTree

## Test de la palette d'outils v2 (MapEditorPaletteV2).
## Vérifie le rendu (groupes, boutons), la sélection silencieuse,
## l'émission de tool_selected au clic et le conteneur d'options.

const PaletteScript = preload("res://scripts/maps/editor/v2/palette.gd")

var _failed := false
# Reçus de tool_selected pendant le test (pour vérifier l'absence de signal).
var _received: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame

	# --- Construction de la palette et remplissage via l'API publique. ---
	var palette = PaletteScript.new()
	get_root().add_child(palette)
	palette.tool_selected.connect(_on_tool_selected)
	palette.setup([
		{
			"title": "Naviguer",
			"tools": [
				{ "id": "select", "icon": "🔍", "label": "Sélection", "shortcut": "S" },
				{ "id": "pan", "icon": "✋", "label": "Déplacer", "shortcut": "P" },
				{ "id": "erase", "icon": "🧽", "label": "Effacer", "shortcut": "E" },
			],
		},
		{
			"title": "Dessiner",
			"tools": [
				{ "id": "path", "icon": "🧭", "label": "Chemin", "shortcut": "C" },
				{ "id": "wall", "icon": "🧱", "label": "Mur", "shortcut": "M" },
			],
		},
	])
	await process_frame

	# --- Rendu : 5 boutons au total (3 + 2) et les 2 titres de groupe. ---
	var buttons := _collect_buttons(palette)
	_assert("buttons_total_5", buttons.size() == 5)
	_assert("title_naviguer", _has_title(palette, "Naviguer"))
	_assert("title_dessiner", _has_title(palette, "Dessiner"))

	# --- Sélection programmatique : coche sans émettre tool_selected. ---
	palette.set_active("path")
	_assert("set_active_no_signal", _received.is_empty())
	_assert("set_active_path", palette.get_active() == "path")

	# --- Clic sur 'wall' : tool_selected('wall') émis et outil actif. ---
	# BaseButton.press() reproduit fidèlement un clic utilisateur :
	# bascule d'état, décochage des autres boutons du groupe, signal 'pressed'.
	var wall_btn := _find_button(palette, "wall")
	_assert("wall_button_found", wall_btn != null)
	if wall_btn != null:
		# Clic utilisateur simulé : bascule d'état + émission du signal pressed.
		wall_btn.set_pressed(true)
		wall_btn.pressed.emit()
	_assert("click_emits_wall", _received.size() == 1 and _received[0] == "wall")
	_assert("click_activates_wall", palette.get_active() == "wall")

	# --- Conteneur d'options contextuelles : présent et vide. ---
	var options_host: VBoxContainer = palette.get_options_host()
	_assert("options_host_not_null", options_host != null)
	_assert("options_host_is_vbox", options_host is VBoxContainer)
	_assert("options_host_empty", options_host.get_child_count() == 0)

	# --- Bilan. ---
	if _failed:
		print("map_editor_v2_palette_test:FAIL")
		quit(1)
	else:
		print("map_editor_v2_palette_test:PASS")
		quit(0)


# ---------------------------------------------------------------------------
# Helpers de test
# ---------------------------------------------------------------------------

## Enregistre les émissions de tool_selected.
func _on_tool_selected(tool_id: String) -> void:
	_received.append(tool_id)


## Vérifie une condition et trace le résultat.
func _assert(assert_name: String, cond: bool) -> void:
	if cond:
		print("  OK   ", assert_name)
	else:
		_failed = true
		print("  FAIL ", assert_name)


## Compte récursivement tous les boutons sous un nœud.
func _collect_buttons(node: Node) -> Array:
	var out: Array = []
	_collect_buttons_in(node, out)
	return out


func _collect_buttons_in(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_collect_buttons_in(child, out)


## Retrouve le bouton d'un outil via son meta "tool_id".
func _find_button(node: Node, tool_id: String) -> Button:
	for child in node.get_children():
		if child is Button and str(child.get_meta("tool_id", "")) == tool_id:
			return child
		var found: Button = _find_button(child, tool_id)
		if found != null:
			return found
	return null


## Vrai si un titre de groupe (Label) porte exactement ce texte.
func _has_title(node: Node, title: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text == title:
			return true
		if _has_title(child, title):
			return true
	return false
