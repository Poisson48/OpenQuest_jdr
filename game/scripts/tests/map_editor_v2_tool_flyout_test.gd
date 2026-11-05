extends SceneTree

## Test du volant d'outils v2 (MapEditorToolFlyout).
## Vérifie la structure (filtre, titres de catégorie en MAJUSCULES, grille
## 4 colonnes de tuiles 62x56 avec meta tool_id, pied de texte), le filtrage
## par libellé insensible aux accents, l'émission de tool_chosen au clic simple
## (fermeture), en Maj+clic (popup conservée), l'armement via Entrée et la
## fermeture via Échap.

const FlyoutScript = preload("res://scripts/maps/editor/v2/tool_flyout.gd")

const TILE_SIZE := Vector2(62, 56)
const FOOTER_TEXT := "Entrée : armer · Maj+clic : garder ouvert · Échap : fermer"

const CATEGORIES := {
	"Dessin": [
		{"id": "tool_wall", "icon": "", "label": "Mur"},
		{"id": "tool_door", "icon": "", "label": "Porte"},
		{"id": "tool_window", "icon": "", "label": "Fenêtre"},
		{"id": "tool_stairs", "icon": "", "label": "Escalier"},
		{"id": "tool_rail", "icon": "", "label": "Garde-corps extérieur"},
	],
	"Terrain": [
		{"id": "tool_water", "icon": "", "label": "Eau"},
		{"id": "tool_rock", "icon": "", "label": "Roche"},
	],
}

var _failed := false
var _events: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame

	# --- Construction via l'API publique. ---
	var flyout = FlyoutScript.new()
	get_root().add_child(flyout)
	flyout.setup(CATEGORIES)
	await process_frame
	await process_frame

	# --- Structure : filtre + titres + grilles + pied de texte. ---
	var filter := _find_node(flyout, "FilterEdit") as LineEdit
	_assert("filter_present", filter != null)
	_assert("filter_placeholder", filter != null and filter.placeholder_text == "Filtrer…")

	var titles := _find_all_prefix(flyout, "CategoryTitle")
	_assert("two_category_titles", titles.size() == 2)
	_assert("titles_uppercase", titles.size() == 2
			and (titles[0] as Label).text == "DESSIN"
			and (titles[1] as Label).text == "TERRAIN")

	var grids := _find_all_prefix(flyout, "ToolGrid")
	_assert("two_grids", grids.size() == 2)
	var cols_ok := true
	for grid in grids:
		if (grid as GridContainer).columns != 4:
			cols_ok = false
	_assert("grids_have_4_columns", cols_ok)

	var tiles := _tool_buttons(flyout)
	_assert("tile_count_is_7", tiles.size() == 7)
	var meta_ok := true
	var size_ok := true
	for tile in tiles:
		if not tile.has_meta("tool_id"):
			meta_ok = false
		if tile.custom_minimum_size != TILE_SIZE:
			size_ok = false
	_assert("tiles_have_meta_tool_id", meta_ok)
	_assert("tiles_are_62x56", size_ok)

	var footer := _find_node(flyout, "FooterLabel") as Label
	_assert("footer_present", footer != null)
	_assert("footer_text", footer != null and footer.text == FOOTER_TEXT)

	# --- Ellipsis : le libellé long est coupé dans la tuile. ---
	var long_label := _find_label(flyout, "Garde-corps extérieur")
	_assert("long_label_ellipsized", long_label != null and long_label.text.ends_with("…"))
	var short_label := _find_label(flyout, "Mur")
	_assert("short_label_untouched", short_label != null and short_label.text == "Mur")

	# --- Filtrage par libellé. ---
	_set_filter(filter, "eau")
	_assert("filter_eau_matches_one", _visible_ids(flyout) == ["tool_water"])

	_set_filter(filter, "fenetre")
	_assert("filter_is_accent_insensitive", _visible_ids(flyout) == ["tool_window"])

	_set_filter(filter, "zzz")
	_assert("filter_without_match_hides_all", _visible_ids(flyout).is_empty())

	_set_filter(filter, "")
	_assert("filter_cleared_shows_all", _visible_ids(flyout).size() == 7)

	# --- Clic simple : tool_chosen(id, false) puis fermeture. ---
	flyout.tool_chosen.connect(_on_tool_chosen)
	flyout.open_at(Vector2(40, 40))
	await process_frame
	_assert("visible_after_open", flyout.visible)
	_assert("width_is_276", flyout.size.x == 276)

	var water := _tile_by_id(flyout, "tool_water")
	_assert("water_tile_found", water != null)
	if water != null:
		_click_tile(water, false)
	_assert("tool_chosen_emitted_on_click", _events.size() == 1 and _events[0][0] == "tool_water")
	_assert("keep_open_false_on_click", _events.size() == 1 and _events[0][1] == false)
	_assert("closed_after_click", not flyout.visible)

	# --- Maj+clic : tool_chosen(id, true) sans fermer. ---
	_events.clear()
	flyout.open_at(Vector2(40, 40))
	await process_frame
	var rock := _tile_by_id(flyout, "tool_rock")
	_assert("rock_tile_found", rock != null)
	if rock != null:
		_click_tile(rock, true)
	_assert("tool_chosen_emitted_on_shift_click", _events.size() == 1 and _events[0][0] == "tool_rock")
	_assert("keep_open_true_on_shift_click", _events.size() == 1 and _events[0][1] == true)
	_assert("stays_open_on_shift_click", flyout.visible)

	# --- Entrée dans le filtre : arme le premier outil visible. ---
	_events.clear()
	_set_filter(filter, "roche")
	filter.text_submitted.emit("roche")
	_assert("enter_arms_first_visible", _events.size() == 1
			and _events[0][0] == "tool_rock" and _events[0][1] == false)
	_assert("closed_after_enter_arm", not flyout.visible)

	# --- Échap : fermeture sans choix. ---
	_events.clear()
	flyout.open_at(Vector2(40, 40))
	await process_frame
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	filter.gui_input.emit(esc)
	_assert("closed_after_escape", not flyout.visible)
	_assert("no_tool_chosen_on_escape", _events.is_empty())

	# --- close_now(). ---
	flyout.open_at(Vector2(40, 40))
	await process_frame
	flyout.close_now()
	_assert("closed_by_close_now", not flyout.visible)

	flyout.queue_free()
	await process_frame

	if _failed:
		print("map_editor_v2_tool_flyout_test:FAIL")
		quit(1)
	else:
		print("map_editor_v2_tool_flyout_test:PASS")
		quit(0)


# ---------------------------------------------------------------------------
# Helpers de test
# ---------------------------------------------------------------------------

## Enregistre les émissions de tool_chosen sous forme [tool_id, keep_open].
func _on_tool_chosen(tool_id: String, keep_open: bool) -> void:
	_events.append([tool_id, keep_open])


## Applique un filtre comme si l'utilisateur l'avait saisi.
func _set_filter(filter: LineEdit, text: String) -> void:
	filter.text = text
	filter.text_changed.emit(text)


## Simule un clic (souris) sur une tuile, Maj enfoncée ou non.
func _click_tile(button: Button, shift: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.shift_pressed = shift
	button.gui_input.emit(ev)


## Toutes les tuiles (Buttons avec meta tool_id), dans l'ordre d'affichage.
func _tool_buttons(node: Node) -> Array:
	var out: Array = []
	_collect_buttons(node, out)
	return out


func _collect_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Button and child.has_meta("tool_id"):
			out.append(child)
		_collect_buttons(child, out)


## Ids des tuiles actuellement visibles (état local, hors ouverture popup).
func _visible_ids(node: Node) -> Array:
	var out: Array = []
	for tile in _tool_buttons(node):
		if tile.visible:
			out.append(str(tile.get_meta("tool_id")))
	return out


## Première tuile portant l'id demandé.
func _tile_by_id(node: Node, tool_id: String) -> Button:
	for tile in _tool_buttons(node):
		if str(tile.get_meta("tool_id")) == tool_id:
			return tile
	return null


## Label de tuile dont le texte d'origine (avant ellipsis) vaut full_label.
func _find_label(node: Node, full_label: String) -> Label:
	for label in _find_all(node, "ToolLabel"):
		if (label as Label).has_meta("full_label") and str(label.get_meta("full_label")) == full_label:
			return label
	return null


## Tous les nœuds dont le nom commence par ce préfixe (Godot suffixe les noms
## en double entre frères : « CategoryTitle », « CategoryTitle2 », …).
func _find_all_prefix(node: Node, prefix: String) -> Array:
	var out: Array = []
	_collect_named_prefix(node, prefix, out)
	return out


func _collect_named_prefix(node: Node, prefix: String, out: Array) -> void:
	for child in node.get_children():
		if str(child.name).begins_with(prefix):
			out.append(child)
		_collect_named_prefix(child, prefix, out)


# ---------------------------------------------------------------------------
# Helpers génériques
# ---------------------------------------------------------------------------

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


## Tous les nœuds portant ce nom.
func _find_all(node: Node, target_name: String) -> Array:
	var out: Array = []
	_collect_named(node, target_name, out)
	return out


func _collect_named(node: Node, target_name: String, out: Array) -> void:
	for child in node.get_children():
		if child.name == target_name:
			out.append(child)
		_collect_named(child, target_name, out)
