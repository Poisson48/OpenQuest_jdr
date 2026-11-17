extends Control

## Palette de commandes flottante de l'éditeur de scénario (refonte 04).
##
## Composant 100 % autonome : construit son propre arbre de Controls, se
## positionne au-dessus de tout (`top_level`) et ne dépend que de l'autoload
## `ThemeColors`. L'hôte (l'éditeur) fournit la liste des commandes via
## `open(items)` et écoute `action_chosen(id)`.
##
## items = [{ "id": String, "label": String, "hint": String, "category": String }]
##
## Raccourcis : ↑/↓ sélectionnent, Entrée exécute, Échap ferme, Ctrl+K ferme.

signal action_chosen(id: String)

const PANEL_WIDTH := 560.0
const PANEL_HEIGHT := 440.0
const PANEL_MIN_HEIGHT := 220.0
const PANEL_MARGIN := 24.0
const ROW_HEIGHT := 46.0
const PANEL_BG := Color("1a1622")

var _host: Control = null
var _items: Array = []
var _filtered: Array = []
var _selected_index: int = 0
var _is_open: bool = false
var _built: bool = false

var _dim: ColorRect = null
var _panel: PanelContainer = null
var _margin: MarginContainer = null
var _search: LineEdit = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _footer: Label = null
var _rows: Array = []
var _style_row_normal: StyleBoxFlat = null
var _style_row_selected: StyleBoxFlat = null


func _ready() -> void:
	_ensure_ui()


## Hôte utilisé pour centrer le panneau (facultatif : sinon le viewport).
func setup(host: Control) -> void:
	_host = host
	_ensure_ui()


func is_open() -> bool:
	return _is_open


## Ouvre la palette et affiche la liste fournie (filtrée par la recherche).
func open(items: Array) -> void:
	_ensure_ui()
	_items.clear()
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw
		_items.append({
			"id": str(item.get("id", "")),
			"label": str(item.get("label", item.get("id", ""))),
			"hint": str(item.get("hint", "")),
			"category": str(item.get("category", "")),
		})
	_is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_selected_index = 0
	_search.text = ""
	_apply_filter()
	if is_inside_tree():
		_layout()
		_search.grab_focus()
	set_process(true)


func close() -> void:
	_is_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	if _search != null and is_instance_valid(_search) and _search.has_focus():
		_search.release_focus()


# ---------------------------------------------------------------------------
# API de test / intégration
# ---------------------------------------------------------------------------

func set_query(text: String) -> void:
	_ensure_ui()
	_search.text = text
	_selected_index = 0
	_apply_filter()


func get_filtered_items() -> Array:
	return _filtered.duplicate()


func get_visible_count() -> int:
	return _filtered.size()


func get_selected_index() -> int:
	return _selected_index


func get_selected_item() -> Dictionary:
	if _selected_index < 0 or _selected_index >= _filtered.size():
		return {}
	return _filtered[_selected_index]


func move_selection(delta: int) -> void:
	if _filtered.is_empty():
		_selected_index = 0
		return
	_selected_index = clampi(_selected_index + delta, 0, _filtered.size() - 1)
	_update_row_styles()
	_ensure_selected_visible()


func activate_selected() -> void:
	if _selected_index < 0 or _selected_index >= _filtered.size():
		return
	var id := str((_filtered[_selected_index] as Dictionary).get("id", ""))
	close()
	action_chosen.emit(id)


func get_search_edit() -> LineEdit:
	return _search


func get_panel() -> PanelContainer:
	return _panel


func get_panel_size() -> Vector2:
	if _panel == null:
		return Vector2.ZERO
	return _panel.size


# ---------------------------------------------------------------------------
# Construction de l'interface
# ---------------------------------------------------------------------------

func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	top_level = true
	z_as_relative = false
	z_index = 4096
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_style_row_normal = _make_row_style(false)
	_style_row_selected = _make_row_style(true)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.01, 0.03, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_panel)

	_margin = MarginContainer.new()
	_margin.name = "PanelMargin"
	_margin.add_theme_constant_override("margin_left", 14)
	_margin.add_theme_constant_override("margin_right", 14)
	_margin.add_theme_constant_override("margin_top", 14)
	_margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(_margin)

	var box := VBoxContainer.new()
	box.name = "PanelBox"
	box.add_theme_constant_override("separation", 10)
	_margin.add_child(box)

	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Commande ou scène…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 40)
	_search.add_theme_font_size_override("font_size", 18)
	_search.text_changed.connect(_on_search_changed)
	box.add_child(_search)

	_scroll = ScrollContainer.new()
	_scroll.name = "Results"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.name = "ResultList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	_footer = Label.new()
	_footer.name = "Hints"
	_footer.theme_type_variation = &"MicroLabel"
	_footer.text = "↑ ↓ choisir  ·  Entrée exécuter  ·  Échap fermer"
	_footer.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO)
	box.add_child(_footer)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(12)
	style.set_border_width_all(1)
	style.border_color = ThemeColors.GOLD
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 14
	return style


func _make_row_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	if selected:
		style.bg_color = Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g, ThemeColors.GOLD.b, 0.16)
		style.border_color = Color(ThemeColors.GOLD_LIGHT.r, ThemeColors.GOLD_LIGHT.g,
			ThemeColors.GOLD_LIGHT.b, 0.6)
	else:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	return style


func _process(_delta: float) -> void:
	if _is_open and is_inside_tree():
		_layout()


func _layout() -> void:
	var viewport_rect := get_viewport_rect()
	global_position = viewport_rect.position
	size = viewport_rect.size
	if _dim != null:
		_dim.position = Vector2.ZERO
		_dim.size = size
	var desired_h := minf(PANEL_HEIGHT, maxf(size.y - 2.0 * PANEL_MARGIN, PANEL_MIN_HEIGHT))
	_panel.size = Vector2(minf(PANEL_WIDTH, maxf(size.x - 2.0 * PANEL_MARGIN, 280.0)), desired_h)
	var center := viewport_rect.size * 0.5
	if _host != null and is_instance_valid(_host) and _host.is_inside_tree():
		center = _host.get_global_rect().get_center() - viewport_rect.position
	_panel.position = (center - _panel.size * 0.5).round()
	_panel.position.x = clampf(_panel.position.x, 12.0,
		maxf(size.x - _panel.size.x - 12.0, 12.0))
	_panel.position.y = clampf(_panel.position.y, 12.0,
		maxf(size.y - _panel.size.y - 12.0, 12.0))


# ---------------------------------------------------------------------------
# Filtre et liste
# ---------------------------------------------------------------------------

func _on_search_changed(_text: String) -> void:
	_selected_index = 0
	_apply_filter()


func _apply_filter() -> void:
	var query := _search.text.strip_edges().to_lower()
	_filtered.clear()
	for item in _items:
		if _matches(item, query):
			_filtered.append(item)
	if _filtered.is_empty():
		_selected_index = 0
	elif _selected_index >= _filtered.size():
		_selected_index = _filtered.size() - 1
	_rebuild_rows()
	call_deferred("_ensure_selected_visible")


func _matches(item: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var haystack := "%s\n%s\n%s" % [
		str(item.get("label", "")).to_lower(),
		str(item.get("hint", "")).to_lower(),
		str(item.get("category", "")).to_lower(),
	]
	return haystack.contains(query)


func _rebuild_rows() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	for i in range(_filtered.size()):
		var row := _create_row(_filtered[i] as Dictionary, i)
		_list.add_child(row)
		_rows.append(row)
	if _filtered.is_empty():
		var empty := Label.new()
		empty.name = "EmptyLabel"
		empty.text = "Aucune commande"
		empty.theme_type_variation = &"MutedLabel"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 48)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)
	_update_row_styles()


func _create_row(item: Dictionary, index: int) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "Row%d" % index
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_stylebox_override("panel", _style_row_normal)
	row.set_meta("item_id", str(item.get("id", "")))
	row.gui_input.connect(_on_row_gui_input.bind(index))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	row.add_child(margin)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	margin.add_child(line)

	var category := Label.new()
	category.theme_type_variation = &"MicroLabel"
	category.custom_minimum_size = Vector2(84, 0)
	category.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	category.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO + 1)
	category.add_theme_color_override("font_color", ThemeColors.GOLD)
	category.text = str(item.get("category", "")).to_upper()
	line.add_child(category)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 1)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(text_box)

	var label := Label.new()
	label.text = str(item.get("label", ""))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_BODY)
	text_box.add_child(label)

	var hint_text := str(item.get("hint", ""))
	if not hint_text.is_empty():
		var hint := Label.new()
		hint.text = hint_text
		hint.theme_type_variation = &"MutedLabel"
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO + 1)
		text_box.add_child(hint)
	return row


func _update_row_styles() -> void:
	for i in range(_rows.size()):
		var row: PanelContainer = _rows[i]
		if not is_instance_valid(row):
			continue
		var is_selected := i == _selected_index
		row.add_theme_stylebox_override("panel",
			_style_row_selected if is_selected else _style_row_normal)
		row.set_meta("selected", is_selected)


func _ensure_selected_visible() -> void:
	if not is_inside_tree() or _scroll == null:
		return
	if _selected_index < 0 or _selected_index >= _rows.size():
		return
	var row: Control = _rows[_selected_index]
	if is_instance_valid(row) and is_instance_valid(_scroll):
		_scroll.ensure_control_visible(row)


# ---------------------------------------------------------------------------
# Entrées
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# Le voile plein écran reçoit déjà le clic hors panneau ; ce garde-fou
		# couvre le cas d'un clic reçu directement par la racine.
		if not _panel.get_global_rect().has_point(event.global_position):
			close()
			_mark_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		close()
		_mark_handled()
	elif key.keycode == KEY_UP:
		move_selection(-1)
		_mark_handled()
	elif key.keycode == KEY_DOWN:
		move_selection(1)
		_mark_handled()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		activate_selected()
		_mark_handled()
	elif key.keycode == KEY_K and key.ctrl_pressed:
		close()
		_mark_handled()


func _on_row_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if index < 0 or index >= _filtered.size():
			return
		_selected_index = index
		_update_row_styles()
		activate_selected()


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		_mark_handled()


func _mark_handled() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
