extends Control

## Vue « Monde » de l'éditeur de cartes : les cartes sont des **zones**
## rectangulaires posées sur un plan (façon Dofus), reliées par leurs bords.
## Les zones peuvent avoir des tailles différentes.
##
## Affiche le plan, permet de créer une zone, de la déplacer, de relier
## automatiquement les bords, de valider le monde et d'ouvrir une zone.

signal open_map_requested(map_id: String)

const WorldZonesScript := preload("res://scripts/maps/world/world_zones.gd")
const BAR_H := 104.0
const BASE_PX_PER_CELL := 99.0  # 1 case = BASE_PX_PER_CELL * zoom pixels
const ZONE_COLORS := [
	Color(0.28, 0.40, 0.24, 0.92),
	Color(0.34, 0.30, 0.42, 0.92),
	Color(0.42, 0.32, 0.24, 0.92),
	Color(0.24, 0.36, 0.40, 0.92),
	Color(0.40, 0.36, 0.22, 0.92),
]

var zones: Array = []
var selected_id: String = ""
var zoom: float = 0.12
var pan: Vector2 = Vector2.ZERO

var _status_lbl: Label
var _error_lbl: Label
var _drag_active := false
var _drag_zone_id := ""
var _drag_start_screen := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _dragged := false
var _has_fitted := false
var current_id: String = ""

var _rename_dialog: AcceptDialog
var _rename_input: LineEdit
var _delete_dialog: ConfirmationDialog
var _zone_dialog: ConfirmationDialog
var _zone_w_spin: SpinBox
var _zone_h_spin: SpinBox

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	resized.connect(_on_resized)
	refresh()
	call_deferred("fit_view")

# ===========================================================================
# UI
# ===========================================================================

func _build_ui() -> void:
	var bar := HFlowContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_top = 6
	bar.offset_bottom = 6 + BAR_H - 12
	bar.add_theme_constant_override("h_separation", 4)
	bar.add_theme_constant_override("v_separation", 4)
	add_child(bar)

	_button(bar, "＋ Zone", func(): _open_create_zone())
	_button(bar, "Relier les bords", func(): auto_link())
	_button(bar, "Valider", func(): validate_world())
	_button(bar, "Ouvrir", func(): open_selected())
	_button(bar, "Renommer", func(): _open_rename())
	_button(bar, "Supprimer", func(): _open_delete())
	_button(bar, "Recentrer", func(): fit_view())
	_button(bar, "⟳", func(): refresh())
	_ensure_dialogs()

	_status_lbl = Label.new()
	_status_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_status_lbl.offset_left = 8
	_status_lbl.offset_right = -8
	_status_lbl.offset_top = BAR_H + 6
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_lbl)

	_error_lbl = Label.new()
	_error_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_error_lbl.offset_left = 8
	_error_lbl.offset_right = -8
	_error_lbl.offset_top = -96
	_error_lbl.offset_bottom = -8
	_error_lbl.add_theme_font_size_override("font_size", 11)
	_error_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55))
	_error_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_error_lbl)

func _button(parent: Control, text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn

# ===========================================================================
# Données
# ===========================================================================

## Recharge la liste des zones du monde courant depuis MapData.
func refresh() -> void:
	zones.clear()
	var md = get_node_or_null("/root/MapData")
	if md == null:
		queue_redraw()
		return
	var world_id := _current_world_id()
	current_id = _current_map_id()
	for map_variant in md.maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("renderMode", "")) != "complex":
			continue
		if str(map.get("worldId", "")) != world_id:
			continue
		var zone: Dictionary = WorldZonesScript.zone_from_map(map)
		if int(zone.get("w", 0)) <= 0 or int(zone.get("h", 0)) <= 0:
			continue
		zones.append(zone)
	zones.sort_custom(func(a, b):
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		return int(a.get("x", 0)) < int(b.get("x", 0))
	)
	if not selected_id.is_empty() and _zone_by_id(selected_id).is_empty():
		selected_id = ""
	_update_status()
	queue_redraw()

func _zone_by_id(zone_id: String) -> Dictionary:
	for zone_variant in zones:
		if str((zone_variant as Dictionary).get("id", "")) == zone_id:
			return zone_variant
	return {}

## Monde courant : celui de la carte éditée, sinon le premier monde trouvé.
func _current_world_id() -> String:
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return ""
	var preview := str(md.preview_map_id)
	if not preview.is_empty():
		var current: Dictionary = md.get_by_id(preview)
		var current_world := str(current.get("worldId", ""))
		if not current_world.is_empty():
			return current_world
	for map_variant in md.maps:
		if not map_variant is Dictionary:
			continue
		var world := str((map_variant as Dictionary).get("worldId", ""))
		if not world.is_empty():
			return world
	return ""

func _current_map_id() -> String:
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return ""
	return str(md.preview_map_id)

func _update_status() -> void:
	if _status_lbl == null:
		return
	var sel := _zone_by_id(selected_id)
	var extra := ""
	if not sel.is_empty():
		extra = " · sélection : %s (%d×%d en %d,%d)" % [
			str(sel.get("title", "")), int(sel.get("w", 0)), int(sel.get("h", 0)),
			int(sel.get("x", 0)), int(sel.get("y", 0)),
		]
	_status_lbl.text = "%d zone(s) · molette = zoom · glisser = déplacer une zone · double-clic = ouvrir%s" % [zones.size(), extra]

# ===========================================================================
# Actions
# ===========================================================================

## Crée une nouvelle carte 2.5D de taille libre et la pose à droite du monde.
func create_zone(width: int = 12, height: int = 9) -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return
	var bounds: Rect2i = WorldZonesScript.world_bounds(zones)
	var pos := Vector2i(0, 0)
	if bounds.size.x > 0 or bounds.size.y > 0:
		# Sous le monde existant : emplacement garanti libre (pas de chevauchement).
		pos = Vector2i(bounds.position.x, bounds.position.y + bounds.size.y + 1)
	var title := "Zone %d" % (zones.size() + 1)
	var map: Dictionary = md.create_complex_map(title, "general", "local", width, height)
	if map.is_empty():
		return
	var map_id := str(map.get("id", ""))
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["worldId"] = _current_world_id() if not _current_world_id().is_empty() else "monde"
	var zone: Dictionary = WorldZonesScript.map_to_zone_patch({
		"id": map_id, "title": title, "x": pos.x, "y": pos.y,
		"w": width, "h": height, "edges": {},
	})
	map.merge(zone, true)
	md.update_map(map)
	selected_id = map_id
	refresh()
	fit_view()
	show_status("Zone créée : %s (%d×%d)." % [title, width, height])

## Détecte et écrit les liens de bords entre toutes les zones.
func auto_link() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or zones.size() < 2:
		show_status("Il faut au moins deux zones pour les relier.")
		return
	var detected: Dictionary = WorldZonesScript.auto_detect_edges(zones)
	var count := 0
	for zone_id in detected:
		var zone := _zone_by_id(str(zone_id))
		if zone.is_empty():
			continue
		var map: Dictionary = md.get_by_id(str(zone_id))
		if map.is_empty():
			continue
		var edges: Dictionary = zone.get("edges", {}).duplicate(true)
		edges.merge(detected[zone_id], true)
		map["edges"] = edges
		map["zoneX"] = int(zone.get("x", 0))
		map["zoneY"] = int(zone.get("y", 0))
		map["zoneW"] = int(zone.get("w", 0))
		map["zoneH"] = int(zone.get("h", 0))
		md.update_map(map)
		for side in detected[zone_id]:
			if not str((detected[zone_id][side] as Dictionary).get("target", "")).is_empty():
				count += 1
	refresh()
	show_status("%d lien(s) de bord écrit(s)." % count)

## Valide le monde (chevauchements, liens cassés, tailles…).
func validate_world() -> void:
	var errors: Array = WorldZonesScript.validate(zones)
	if errors.is_empty():
		if _error_lbl:
			_error_lbl.text = ""
		show_status("Monde valide : pas d'erreur détectée.")
		return
	if _error_lbl:
		_error_lbl.text = "\n".join(errors.slice(0, 6))
	show_status("%d erreur(s) — voir le détail en bas." % errors.size())

func open_selected() -> void:
	if selected_id.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	open_map_requested.emit(selected_id)

func show_status(text: String) -> void:
	if _status_lbl:
		_status_lbl.text = text

# ===========================================================================
# Dialogues (création / renommage / suppression)
# ===========================================================================

func _ensure_dialogs() -> void:
	if _rename_dialog != null:
		return
	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Renommer la zone"
	add_child(_rename_dialog)
	var rename_box := VBoxContainer.new()
	rename_box.custom_minimum_size = Vector2(340, 56)
	_rename_dialog.add_child(rename_box)
	_rename_input = LineEdit.new()
	rename_box.add_child(_rename_input)
	_rename_dialog.confirmed.connect(_apply_rename)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Supprimer la zone"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_apply_delete)

	_zone_dialog = ConfirmationDialog.new()
	_zone_dialog.title = "Nouvelle zone"
	add_child(_zone_dialog)
	var zone_box := VBoxContainer.new()
	zone_box.custom_minimum_size = Vector2(300, 90)
	_zone_dialog.add_child(zone_box)
	var size_row := HBoxContainer.new()
	zone_box.add_child(size_row)
	var w_label := Label.new()
	w_label.text = "Largeur"
	size_row.add_child(w_label)
	_zone_w_spin = SpinBox.new()
	_zone_w_spin.min_value = 3
	_zone_w_spin.max_value = 96
	_zone_w_spin.value = 12
	size_row.add_child(_zone_w_spin)
	var size_row2 := HBoxContainer.new()
	zone_box.add_child(size_row2)
	var h_label := Label.new()
	h_label.text = "Hauteur"
	size_row2.add_child(h_label)
	_zone_h_spin = SpinBox.new()
	_zone_h_spin.min_value = 3
	_zone_h_spin.max_value = 96
	_zone_h_spin.value = 9
	size_row2.add_child(_zone_h_spin)
	_zone_dialog.confirmed.connect(_apply_create_zone)

func _open_create_zone() -> void:
	_ensure_dialogs()
	_zone_dialog.popup_centered(Vector2i(360, 180))

func _apply_create_zone() -> void:
	create_zone(int(_zone_w_spin.value), int(_zone_h_spin.value))

func _open_rename() -> void:
	_ensure_dialogs()
	var zone := _zone_by_id(selected_id)
	if zone.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	_rename_input.text = str(zone.get("title", ""))
	_rename_dialog.popup_centered(Vector2i(420, 140))
	_rename_input.grab_focus()

func _apply_rename() -> void:
	var zone := _zone_by_id(selected_id)
	var md = get_node_or_null("/root/MapData")
	if zone.is_empty() or md == null:
		return
	var new_title := _rename_input.text.strip_edges()
	if new_title.is_empty():
		return
	var map: Dictionary = md.get_by_id(selected_id)
	if map.is_empty():
		return
	map["title"] = new_title
	md.update_map(map)
	refresh()
	show_status("Zone renommée : %s" % new_title)

func _open_delete() -> void:
	_ensure_dialogs()
	var zone := _zone_by_id(selected_id)
	if zone.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	_delete_dialog.dialog_text = "Supprimer la zone « %s » ?" % str(zone.get("title", ""))
	_delete_dialog.popup_centered(Vector2i(420, 140))

func _apply_delete() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or selected_id.is_empty():
		return
	md.delete_map(selected_id)
	selected_id = ""
	refresh()
	show_status("Zone supprimée.")

# ===========================================================================
# Géométrie écran
# ===========================================================================

func _px_per_cell() -> float:
	return BASE_PX_PER_CELL * zoom

func _world_to_screen(cell: Vector2) -> Vector2:
	return Vector2(0, BAR_H + 20) + pan + cell * _px_per_cell()

func _screen_to_world(pos: Vector2) -> Vector2:
	return (pos - Vector2(0, BAR_H + 20) - pan) / maxf(0.001, _px_per_cell())

func _zone_rect(zone: Dictionary) -> Rect2:
	return Rect2(Vector2(float(zone.get("x", 0.0)), float(zone.get("y", 0.0))),
		Vector2(float(zone.get("w", 1.0)), float(zone.get("h", 1.0))))

func fit_view() -> void:
	var bounds: Rect2i = WorldZonesScript.world_bounds(zones)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		zoom = 0.12
		pan = Vector2.ZERO
		queue_redraw()
		return
	if size.x < 50.0 or size.y < 50.0:
		# Le panneau n'est pas encore layouté : on recadrera au prochain resize.
		return
	var area := size - Vector2(20, BAR_H + 40)
	zoom = clampf(minf(area.x / (float(bounds.size.x) * BASE_PX_PER_CELL),
		area.y / (float(bounds.size.y) * BASE_PX_PER_CELL)), 0.02, 1.5)
	var center := (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * _px_per_cell()
	pan = (size * 0.5) - center - Vector2(0, (BAR_H + 20) * 0.5)
	_has_fitted = true
	queue_redraw()

func _on_resized() -> void:
	if not _has_fitted:
		fit_view()
	queue_redraw()

# ===========================================================================
# Dessin
# ===========================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.06, 1.0), true)
	# Repères de cases (léger) sur la zone du monde.
	var bounds: Rect2i = WorldZonesScript.world_bounds(zones)
	if bounds.size.x > 0 and _px_per_cell() >= 6.0:
		_draw_grid(bounds)
	for i in range(zones.size()):
		var zone: Dictionary = zones[i]
		var rect := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
			Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
		var selected := str(zone.get("id", "")) == selected_id
		var color: Color = ZONE_COLORS[i % ZONE_COLORS.size()]
		if selected:
			color = color.lightened(0.18)
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0.95, 0.86, 0.55, 1.0) if selected else Color(0.10, 0.09, 0.07, 0.9),
			false, 2.0 if selected else 1.0)
		# Zone actuellement ouverte dans l'éditeur : liseré cyan + point.
		if str(zone.get("id", "")) == current_id:
			draw_rect(rect, Color(0.55, 0.85, 1.0, 0.9), false, 2.0)
			draw_circle(rect.get_center(), 4.5, Color(0.55, 0.85, 1.0))
		# Nom + taille (si assez de place).
		if rect.size.x > 70.0 and rect.size.y > 32.0:
			var font := get_theme_default_font()
			var title := str(zone.get("title", "Carte"))
			var dims := "%d×%d" % [int(zone.get("w", 0)), int(zone.get("h", 0))]
			draw_string(font, rect.position + Vector2(6, 16), title,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 12, Color(1.0, 0.95, 0.82))
			draw_string(font, rect.position + Vector2(6, 30), dims,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 10, Color(0.92, 0.88, 0.75, 0.85))
		_draw_edges(zone, rect)
	# Infobulle de déplacement.
	if _drag_active and not _drag_zone_id.is_empty():
		var zone := _zone_by_id(_drag_zone_id)
		if not zone.is_empty():
			var preview := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))) + _drag_offset,
				Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
			draw_rect(preview, Color(1.0, 0.9, 0.4, 0.18), true)
			draw_rect(preview, Color(1.0, 0.9, 0.4, 0.9), false, 2.0)

func _draw_grid(bounds: Rect2i) -> void:
	var top_left := _world_to_screen(Vector2(bounds.position))
	var bottom_right := _world_to_screen(Vector2(bounds.position) + Vector2(bounds.size))
	var color := Color(1, 1, 1, 0.045)
	var step := _px_per_cell() * 5.0
	var x := top_left.x
	while x <= bottom_right.x:
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), color, 1.0)
		x += step
	var y := top_left.y
	while y <= bottom_right.y:
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), color, 1.0)
		y += step

func _draw_edges(zone: Dictionary, rect: Rect2) -> void:
	var edges: Dictionary = zone.get("edges", {}) if zone.get("edges") is Dictionary else {}
	var color := Color(0.98, 0.82, 0.35, 0.9)
	var center := rect.get_center()
	for side in ["north", "south", "east", "west"]:
		var edge: Dictionary = edges.get(side, {}) if edges.get(side) is Dictionary else {}
		if str(edge.get("target", "")).is_empty():
			continue
		var p1 := center
		var p2 := center
		match str(side):
			"north":
				p1 = rect.position + Vector2(rect.size.x * 0.5, 0)
				p2 = p1 + Vector2(0, -6)
			"south":
				p1 = rect.position + Vector2(rect.size.x * 0.5, rect.size.y)
				p2 = p1 + Vector2(0, 6)
			"east":
				p1 = rect.position + Vector2(rect.size.x, rect.size.y * 0.5)
				p2 = p1 + Vector2(6, 0)
			"west":
				p1 = rect.position + Vector2(0, rect.size.y * 0.5)
				p2 = p1 + Vector2(-6, 0)
		draw_line(p1, p2, color, 2.0)
		draw_circle(p2, 2.5, color)

# ===========================================================================
# Entrée souris
# ===========================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.15, 0.02, 2.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.15, 0.02, 2.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_drag_start_screen = mb.position
			else:
				_drag_start_screen = Vector2.INF
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click:
					var dbl := _zone_at_screen(mb.position)
					if not dbl.is_empty():
						selected_id = str(dbl.get("id", ""))
						open_selected()
					accept_event()
					return
				var hit := _zone_at_screen(mb.position)
				if not hit.is_empty():
					selected_id = str(hit.get("id", ""))
					_drag_active = true
					_drag_zone_id = selected_id
					_drag_start_screen = mb.position
					_drag_offset = Vector2.ZERO
					_dragged = false
					_update_status()
				else:
					selected_id = ""
					_update_status()
				queue_redraw()
			else:
				if _drag_active and _dragged:
					_commit_drag()
				_drag_active = false
				_drag_zone_id = ""
				queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _drag_active and not _drag_zone_id.is_empty():
			var delta := motion.position - _drag_start_screen
			if delta.length() > 4.0:
				_dragged = true
			_drag_offset = delta
			queue_redraw()
		elif _drag_start_screen != Vector2.INF and (motion.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
			pan += motion.relative
			_drag_start_screen = motion.position
			queue_redraw()

func _zone_at_screen(pos: Vector2) -> Dictionary:
	for i in range(zones.size() - 1, -1, -1):
		var zone: Dictionary = zones[i]
		var rect := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
			Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
		if rect.has_point(pos):
			return zone
	return {}

func _commit_drag() -> void:
	var zone := _zone_by_id(_drag_zone_id)
	if zone.is_empty():
		return
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return
	var delta_cells := _drag_offset / maxf(0.001, _px_per_cell())
	var new_x := int(round(float(zone.get("x", 0)) + delta_cells.x))
	var new_y := int(round(float(zone.get("y", 0)) + delta_cells.y))
	var map: Dictionary = md.get_by_id(_drag_zone_id)
	if map.is_empty():
		return
	map["zoneX"] = new_x
	map["zoneY"] = new_y
	md.update_map(map)
	refresh()
