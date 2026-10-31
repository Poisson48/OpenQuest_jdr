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
var _resize_dialog: ConfirmationDialog
var _resize_w_spin: SpinBox
var _resize_h_spin: SpinBox
var _link_dialog: ConfirmationDialog
var _link_side_opt: OptionButton
var _link_target_opt: OptionButton
var _link_offset_spin: SpinBox
var hover_zone_id: String = ""
var _unlink_dialog: ConfirmationDialog
var _pending_unlink_zone: String = ""
var _pending_unlink_side: String = ""
var _assign_dialog: ConfirmationDialog
var _assign_opt: OptionButton
var _editor_root: Control
var _fullscreen: bool = false
var _original_parent: Node
var _original_index: int = 0
var _fullscreen_btn: Button

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
	_button(bar, "Lier…", func(): _open_link())
	_button(bar, "Valider", func(): validate_world())
	_button(bar, "Ouvrir", func(): open_selected())
	_button(bar, "▶ Tester", func(): test_world())
	_button(bar, "Renommer", func(): _open_rename())
	_button(bar, "Taille…", func(): _open_resize())
	_button(bar, "Dupliquer", func(): duplicate_selected())
	_button(bar, "Assigner…", func(): _open_assign())
	_button(bar, "Supprimer", func(): _open_delete())
	_button(bar, "Recentrer", func(): fit_view())
	_button(bar, "⟳", func(): refresh())
	_fullscreen_btn = _button(bar, "⤢ Plein écran", func(): toggle_fullscreen())
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
	var hover := _zone_by_id(hover_zone_id)
	if not hover.is_empty():
		extra += " · survol : %s (%d×%d)" % [
			str(hover.get("title", "")), int(hover.get("w", 0)), int(hover.get("h", 0))]
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

## L'éditeur fournit sa racine pour pouvoir passer la vue Monde en plein écran.
func set_editor_root(root: Control) -> void:
	_editor_root = root

func is_fullscreen() -> bool:
	return _fullscreen

func toggle_fullscreen() -> void:
	if _fullscreen:
		_exit_fullscreen()
	else:
		_enter_fullscreen()

func _enter_fullscreen() -> void:
	if _editor_root == null or _fullscreen:
		return
	_original_parent = get_parent()
	_original_index = get_index()
	if _original_parent != null:
		_original_parent.remove_child(self)
	_editor_root.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	_fullscreen = true
	_has_fitted = false
	if _fullscreen_btn != null:
		_fullscreen_btn.text = "⤡ Réduire"
	call_deferred("fit_view")
	queue_redraw()

func _exit_fullscreen() -> void:
	if not _fullscreen or _original_parent == null:
		return
	var current_parent := get_parent()
	if current_parent != null:
		current_parent.remove_child(self)
	_original_parent.add_child(self)
	var count := _original_parent.get_child_count()
	_original_parent.move_child(self, clampi(_original_index, 0, count - 1))
	z_index = 0
	_fullscreen = false
	_has_fitted = false
	if _fullscreen_btn != null:
		_fullscreen_btn.text = "⤢ Plein écran"
	call_deferred("fit_view")
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not _fullscreen:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_exit_fullscreen()
		get_viewport().set_input_as_handled()

func open_selected() -> void:
	if selected_id.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	open_map_requested.emit(selected_id)

## Lance une session de test sur le monde courant (depuis l'éditeur).
func test_world() -> void:
	if zones.is_empty():
		show_status("Aucune zone à tester.")
		return
	var gd = get_node_or_null("/root/GameData")
	if gd == null or not gd.has_method("start_world_playtest"):
		show_status("Session indisponible.")
		return
	var ids: Array = []
	for zone_variant in zones:
		ids.append(str((zone_variant as Dictionary).get("id", "")))
	var current := current_id if zones.any(func(z): return str((z as Dictionary).get("id", "")) == current_id) else str((zones[0] as Dictionary).get("id", ""))
	if gd.start_world_playtest(ids, current):
		show_status("Session de test lancée sur le monde.")
	else:
		show_status("Impossible de lancer la session de test.")

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

	_resize_dialog = ConfirmationDialog.new()
	_resize_dialog.title = "Taille de la zone"
	add_child(_resize_dialog)
	var resize_box := VBoxContainer.new()
	resize_box.custom_minimum_size = Vector2(320, 130)
	_resize_dialog.add_child(resize_box)
	var note := Label.new()
	note.text = "Redimensionne la carte de cette zone (contenu conservé en haut à gauche)."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	resize_box.add_child(note)
	var row_w := HBoxContainer.new()
	resize_box.add_child(row_w)
	var lbl_w := Label.new()
	lbl_w.text = "Largeur"
	row_w.add_child(lbl_w)
	_resize_w_spin = SpinBox.new()
	_resize_w_spin.min_value = 3
	_resize_w_spin.max_value = 96
	row_w.add_child(_resize_w_spin)
	var row_h := HBoxContainer.new()
	resize_box.add_child(row_h)
	var lbl_h := Label.new()
	lbl_h.text = "Hauteur"
	row_h.add_child(lbl_h)
	_resize_h_spin = SpinBox.new()
	_resize_h_spin.min_value = 3
	_resize_h_spin.max_value = 96
	row_h.add_child(_resize_h_spin)
	_resize_dialog.confirmed.connect(_apply_resize)

	_link_dialog = ConfirmationDialog.new()
	_link_dialog.title = "Lier une zone"
	add_child(_link_dialog)
	var link_box := VBoxContainer.new()
	link_box.custom_minimum_size = Vector2(340, 150)
	_link_dialog.add_child(link_box)
	var side_row := HBoxContainer.new()
	link_box.add_child(side_row)
	var side_lbl := Label.new()
	side_lbl.text = "Bord"
	side_row.add_child(side_lbl)
	_link_side_opt = OptionButton.new()
	side_row.add_child(_link_side_opt)
	for side_entry in [["north", "Nord"], ["south", "Sud"], ["east", "Est"], ["west", "Ouest"]]:
		var idx := _link_side_opt.item_count
		_link_side_opt.add_item(str(side_entry[1]), idx)
		_link_side_opt.set_item_metadata(idx, str(side_entry[0]))
	var target_row := HBoxContainer.new()
	link_box.add_child(target_row)
	var target_lbl := Label.new()
	target_lbl.text = "Vers"
	target_row.add_child(target_lbl)
	_link_target_opt = OptionButton.new()
	target_row.add_child(_link_target_opt)
	var offset_row := HBoxContainer.new()
	link_box.add_child(offset_row)
	var offset_lbl := Label.new()
	offset_lbl.text = "Décalage"
	offset_row.add_child(offset_lbl)
	_link_offset_spin = SpinBox.new()
	_link_offset_spin.min_value = -32
	_link_offset_spin.max_value = 32
	offset_row.add_child(_link_offset_spin)
	_link_dialog.confirmed.connect(_apply_link)

	_assign_dialog = ConfirmationDialog.new()
	_assign_dialog.title = "Assigner une carte existante au monde"
	add_child(_assign_dialog)
	var assign_box := VBoxContainer.new()
	assign_box.custom_minimum_size = Vector2(380, 110)
	_assign_dialog.add_child(assign_box)
	var assign_note := Label.new()
	assign_note.text = "La carte choisie devient une zone du monde courant, placée sous les zones existantes."
	assign_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assign_note.custom_minimum_size = Vector2(380, 0)
	assign_box.add_child(assign_note)
	_assign_opt = OptionButton.new()
	assign_box.add_child(_assign_opt)
	_assign_dialog.confirmed.connect(_apply_assign)

	_unlink_dialog = ConfirmationDialog.new()
	_unlink_dialog.title = "Retirer le lien"
	add_child(_unlink_dialog)
	_unlink_dialog.confirmed.connect(_apply_unlink)

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

func _open_assign() -> void:
	_ensure_dialogs()
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return
	var world_id := _current_world_id()
	_assign_opt.clear()
	for map_variant in md.maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("renderMode", "")) != "complex":
			continue
		if str(map.get("worldId", "")) == world_id and not world_id.is_empty():
			continue
		var index := _assign_opt.item_count
		_assign_opt.add_item(str(map.get("title", map.get("id", "Carte"))), index)
		_assign_opt.set_item_metadata(index, str(map.get("id", "")))
	if _assign_opt.item_count == 0:
		show_status("Aucune carte libre à assigner (toutes sont déjà dans ce monde).")
		return
	_assign_dialog.popup_centered(Vector2i(520, 220))

func _apply_assign() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or _assign_opt.selected < 0:
		return
	var map_id := str(_assign_opt.get_item_metadata(_assign_opt.selected))
	var world_id := _current_world_id()
	if world_id.is_empty():
		world_id = "monde"
	var bounds: Rect2i = WorldZonesScript.world_bounds(zones)
	var pos := Vector2i(bounds.position.x, bounds.position.y + bounds.size.y + 1) if bounds.size.x > 0 \
		else Vector2i.ZERO
	if md.assign_map_to_world(map_id, world_id, pos.x, pos.y):
		selected_id = map_id
		refresh()
		fit_view()
		show_status("Carte assignée au monde.")
	else:
		show_status("Assignation impossible.")

func _open_link(prefill_zone_id: String = "", prefill_side: String = "") -> void:
	_ensure_dialogs()
	var zone_id := prefill_zone_id if not prefill_zone_id.is_empty() else selected_id
	var zone := _zone_by_id(zone_id)
	if zone.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	selected_id = zone_id
	_link_target_opt.clear()
	for other_variant in zones:
		var other: Dictionary = other_variant
		var other_id := str(other.get("id", ""))
		if other_id == zone_id:
			continue
		var index := _link_target_opt.item_count
		_link_target_opt.add_item(str(other.get("title", other_id)), index)
		_link_target_opt.set_item_metadata(index, other_id)
	if _link_target_opt.item_count == 0:
		show_status("Aucune autre zone à relier.")
		return
	var side_order := ["north", "south", "east", "west"]
	var side_index := 2  # Est par défaut.
	if not prefill_side.is_empty():
		var found := side_order.find(prefill_side)
		if found >= 0:
			side_index = found
	var edges: Dictionary = zone.get("edges", {}) if zone.get("edges") is Dictionary else {}
	var existing: Dictionary = edges.get(prefill_side, {}) if edges.get(prefill_side) is Dictionary else {}
	var existing_target := str(existing.get("target", ""))
	if not existing_target.is_empty():
		for i in range(_link_target_opt.item_count):
			if str(_link_target_opt.get_item_metadata(i)) == existing_target:
				_link_target_opt.select(i)
				break
	_link_side_opt.select(side_index)
	_link_offset_spin.value = int(existing.get("offset", 0))
	_link_dialog.popup_centered(Vector2i(460, 240))

## Clic droit sur un point d'accroche lié : propose de retirer le lien.
func _open_unlink(zone_id: String, side: String) -> void:
	_ensure_dialogs()
	var zone := _zone_by_id(zone_id)
	if zone.is_empty():
		return
	var edges: Dictionary = zone.get("edges", {}) if zone.get("edges") is Dictionary else {}
	var edge: Dictionary = edges.get(side, {}) if edges.get(side) is Dictionary else {}
	if str(edge.get("target", "")).is_empty():
		return
	_pending_unlink_zone = zone_id
	_pending_unlink_side = side
	var target := _zone_by_id(str(edge.get("target", "")))
	_unlink_dialog.dialog_text = "Retirer le lien %s de « %s » vers « %s » ?" % [
		side, str(zone.get("title", "")), str(target.get("title", edge.get("target", "")))]
	_unlink_dialog.popup_centered(Vector2i(480, 150))

func _apply_unlink() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or _pending_unlink_zone.is_empty():
		return
	md.set_zone_edge(_pending_unlink_zone, _pending_unlink_side, "")
	refresh()
	show_status("Lien %s retiré." % _pending_unlink_side)
	_pending_unlink_zone = ""
	_pending_unlink_side = ""

func _apply_link() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or selected_id.is_empty():
		return
	if _link_side_opt.selected < 0 or _link_target_opt.selected < 0:
		return
	var side := str(_link_side_opt.get_item_metadata(_link_side_opt.selected))
	var target_id := str(_link_target_opt.get_item_metadata(_link_target_opt.selected))
	if md.set_zone_edge(selected_id, side, target_id, int(_link_offset_spin.value)):
		refresh()
		show_status("Lien %s → %s posé." % [side, target_id])
	else:
		show_status("Lien impossible.")

func _open_resize() -> void:
	_ensure_dialogs()
	var zone := _zone_by_id(selected_id)
	if zone.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return
	var map: Dictionary = md.get_by_id(selected_id)
	if map.is_empty():
		return
	_resize_w_spin.value = int(map.get("width", zone.get("w", 12)))
	_resize_h_spin.value = int(map.get("height", zone.get("h", 9)))
	_resize_dialog.popup_centered(Vector2i(480, 240))

func _apply_resize() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or selected_id.is_empty():
		return
	var new_w := int(_resize_w_spin.value)
	var new_h := int(_resize_h_spin.value)
	if md.resize_complex_map(selected_id, new_w, new_h):
		refresh()
		fit_view()
		show_status("Zone redimensionnée : %d×%d." % [new_w, new_h])
	else:
		show_status("Taille inchangée ou redimensionnement impossible.")

func _open_delete() -> void:
	_ensure_dialogs()
	var zone := _zone_by_id(selected_id)
	if zone.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	_delete_dialog.dialog_text = "Supprimer la zone « %s » ?" % str(zone.get("title", ""))
	_delete_dialog.popup_centered(Vector2i(420, 140))

## Duplique la zone sélectionnée sous elle-même (contenu conservé).
func duplicate_selected() -> void:
	var md = get_node_or_null("/root/MapData")
	if md == null or selected_id.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	var zone := _zone_by_id(selected_id)
	if zone.is_empty():
		show_status("Sélectionnez d'abord une zone.")
		return
	var copy: Dictionary = md.duplicate_complex_map(selected_id, "",
		0, int(zone.get("h", 9)) + 1)
	if copy.is_empty():
		show_status("Duplication impossible.")
		return
	selected_id = str(copy.get("id", ""))
	refresh()
	fit_view()
	show_status("Zone dupliquée : %s" % str(copy.get("title", "")))

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
	# 1) Fonds + contenus des zones.
	for i in range(zones.size()):
		var zone: Dictionary = zones[i]
		var rect := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
			Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
		var selected := str(zone.get("id", "")) == selected_id
		var color: Color = ZONE_COLORS[i % ZONE_COLORS.size()]
		if selected:
			color = color.lightened(0.18)
		draw_rect(rect, color, true)
		_draw_zone_content(zone, rect)
		draw_rect(rect, Color(0.95, 0.86, 0.55, 1.0) if selected else Color(0.10, 0.09, 0.07, 0.9),
			false, 2.0 if selected else 1.0)
		if str(zone.get("id", "")) == current_id:
			draw_rect(rect, Color(0.55, 0.85, 1.0, 0.9), false, 2.0)
			draw_circle(rect.get_center(), 4.5, Color(0.55, 0.85, 1.0))
		if str(zone.get("id", "")) == hover_zone_id and not selected:
			draw_rect(rect, Color(0.85, 0.93, 1.0, 0.9), false, 1.5)
	# 2) Liens entre zones (au-dessus des fonds, sous les libellés).
	_draw_connections()
	# 3) Libellés + points d'accroche.
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var rect := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
			Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
		if rect.size.x > 70.0 and rect.size.y > 32.0:
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 32.0)), Color(0.02, 0.02, 0.02, 0.5), true)
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

## Aperçu du contenu d'une zone : sols peints (matières) + points des objets 3D.
func _draw_zone_content(zone: Dictionary, rect: Rect2) -> void:
	var px := _px_per_cell()
	if px < 1.5:
		return
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return
	var map: Dictionary = md.get_by_id(str(zone.get("id", "")))
	if map.is_empty():
		return
	var w := int(map.get("width", 0))
	var h := int(map.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var mats = map.get("terrainMaterials", [])
	var heights = map.get("terrainHeights", [])
	var step := maxi(1, int(ceil(2.0 / px)))
	var cy := 0
	while cy < h:
		var cx := 0
		while cx < w:
			var idx: int = cy * w + cx
			var material := 0
			if mats is Array and idx < (mats as Array).size():
				material = int((mats as Array)[idx])
			var cell_color := _material_color(material)
			if heights is Array and idx < (heights as Array).size():
				var hgt := float((heights as Array)[idx])
				if hgt > 0.0:
					cell_color = cell_color.lightened(clampf(hgt * 0.09, 0.0, 0.35))
			var block := Vector2(mini(step, w - cx), mini(step, h - cy))
			draw_rect(Rect2(rect.position + Vector2(cx, cy) * px, block * px), cell_color, true)
			cx += step
		cy += step
	var meshes = map.get("meshes", [])
	if meshes is Array:
		for mesh_variant in meshes:
			if not mesh_variant is Dictionary:
				continue
			var mesh: Dictionary = mesh_variant
			var mpos := rect.position + Vector2(float(mesh.get("x", 0.0)) + 0.5, float(mesh.get("y", 0.0)) + 0.5) * px
			draw_circle(mpos, clampf(px * 0.55, 1.0, 3.5), Color(0.16, 0.12, 0.08, 0.95))

func _material_color(material: int) -> Color:
	match material:
		1:
			return Color(0.46, 0.36, 0.25)
		2:
			return Color(0.55, 0.52, 0.46)
		_:
			return Color(0.33, 0.45, 0.25)

## Point d'accroche d'un bord de zone (décalé de 6 px vers l'extérieur).
func _edge_marker_point(zone: Dictionary, side: String) -> Vector2:
	var rect := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
		Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
	match side:
		"north":
			return rect.position + Vector2(rect.size.x * 0.5, -6)
		"south":
			return rect.position + Vector2(rect.size.x * 0.5, rect.size.y + 6)
		"east":
			return rect.position + Vector2(rect.size.x + 6, rect.size.y * 0.5)
		"west":
			return rect.position + Vector2(-6, rect.size.y * 0.5)
	return rect.get_center()

func _opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"south": return "north"
		"east": return "west"
		"west": return "east"
	return ""

## Trace les liens entre zones sur le plan (ligne + flèche vers la zone voisine).
func _draw_connections() -> void:
	var seen: Dictionary = {}
	var color := Color(0.98, 0.82, 0.35, 0.42)
	var arrow_color := Color(0.98, 0.82, 0.35, 0.8)
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var zone_id := str(zone.get("id", ""))
		var edges: Dictionary = zone.get("edges", {}) if zone.get("edges") is Dictionary else {}
		for side in ["north", "south", "east", "west"]:
			var edge: Dictionary = edges.get(side, {}) if edges.get(side) is Dictionary else {}
			var target_id := str(edge.get("target", ""))
			if target_id.is_empty():
				continue
			var reverse_key := "%s|%s" % [target_id, _opposite_side(side)]
			if seen.has(reverse_key):
				continue
			seen["%s|%s" % [zone_id, side]] = true
			var target_zone := _zone_by_id(target_id)
			if target_zone.is_empty():
				continue
			var from := _edge_marker_point(zone, side)
			var to := _edge_marker_point(target_zone, _opposite_side(side))
			if from.distance_to(to) < 2.0:
				continue
			draw_line(from, to, color, 1.5)
			var dir := (to - from).normalized()
			var normal := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([
				to, to - dir * 7.0 + normal * 4.0, to - dir * 7.0 - normal * 4.0,
			]), arrow_color)

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
	var idle_color := Color(0.9, 0.82, 0.6, 0.28)
	var center := rect.get_center()
	for side in ["north", "south", "east", "west"]:
		var edge: Dictionary = edges.get(side, {}) if edges.get(side) is Dictionary else {}
		var linked := not str(edge.get("target", "")).is_empty()
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
		if linked:
			draw_line(p1, p2, color, 2.0)
			draw_circle(p2, 3.0, color)
		else:
			# Point d'accroche discret : cliquez-le pour créer un lien sur ce bord.
			draw_circle(p2, 2.0, idle_color)

## Détecte le point d'accroche de bord sous le curseur (clic création/édition de lien).
func _edge_marker_hit(pos: Vector2) -> Dictionary:
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var rect := Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
			Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())
		var markers := {
			"north": rect.position + Vector2(rect.size.x * 0.5, -6),
			"south": rect.position + Vector2(rect.size.x * 0.5, rect.size.y + 6),
			"east": rect.position + Vector2(rect.size.x + 6, rect.size.y * 0.5),
			"west": rect.position + Vector2(-6, rect.size.y * 0.5),
		}
		for side in markers:
			if pos.distance_to(markers[side]) <= 10.0:
				return {"zone_id": str(zone.get("id", "")), "side": str(side)}
	return {}

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
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				var edge_hit := _edge_marker_hit(mb.position)
				if not edge_hit.is_empty():
					selected_id = str(edge_hit.get("zone_id", ""))
					_open_unlink(selected_id, str(edge_hit.get("side", "")))
					accept_event()
					return
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
				# Point d'accroche de bord : ouvre directement l'édition du lien.
				var edge_hit := _edge_marker_hit(mb.position)
				if not edge_hit.is_empty():
					selected_id = str(edge_hit.get("zone_id", ""))
					_open_link(selected_id, str(edge_hit.get("side", "")))
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
		else:
			var hovered := _zone_at_screen(motion.position)
			var new_hover := "" if hovered.is_empty() else str(hovered.get("id", ""))
			if new_hover != hover_zone_id:
				hover_zone_id = new_hover
				_update_status()
				queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not hover_zone_id.is_empty():
		hover_zone_id = ""
		_update_status()
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
