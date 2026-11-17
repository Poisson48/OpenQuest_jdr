extends RefCounted

## Controleur de graphe de l'editeur de scenario — extrait de `scenario_editor.gd`
## (phase 3.3, patron de composition `setup(editor)` deja utilise par les panneaux).
##
## Responsabilites : configuration du `GraphEdit`, construction/reconstruction des
## cartes de scene, liens et activite des cables, zoom/cadrage, glisser-deposer et
## persistance des positions, menu contextuel et navigation de selection. Le
## controleur de scene garde des wrappers d'une ligne (contrat de test fige) et
## reste proprietaire de l'etat (`_ed._scenario`, `_ed.graph_edit`, outils...).
##
## Extraction mecanique : aucun changement de comportement ni de rendu. Les
## constantes de graphe (zoom, insets de cadrage, ids d'outils) vivent ici et sont
## exposees au controleur par alias (`const TOOL_LINK := GraphControllerScript.TOOL_LINK`).

const GraphNodeScene := preload("res://scenes/scenario_editor/panels/graph_node.tscn")
const GraphLinkOverlayScript := preload("res://scripts/scenario_editor/panels/graph_link_overlay.gd")
const QuestNavigation = preload("res://scripts/quest_navigation.gd")

## Bornes du zoom manuel (pilule zoom / rail d'outils).
const GRAPH_ZOOM_MIN := 0.35
const GRAPH_ZOOM_MAX := 1.6
## Cadrage : espace reserve aux panneaux flottants du canevas (rail d'outils a
## gauche, pilules en bas). Le graphe se cale dans l'espace restant pour
## qu'aucune carte ne passe sous un panneau.
const FIT_INSET_LEFT := 54.0
const FIT_INSET_RIGHT := 6.0
const FIT_INSET_TOP := 8.0
const FIT_INSET_BOTTOM := 10.0
## Outils de la sous-barre (source unique ; le controleur les alias).
const TOOL_SELECT := "select"
const TOOL_LINK := "link"
const TOOL_NOTE := "note"
const TOOL_FRAME := "frame"

## Editeur proprietaire (Control) — non type pour eviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor


func _configure_graph_edit() -> void:
	_ed.graph_edit.show_grid = true
	_ed.graph_edit.snapping_enabled = true
	_ed.graph_edit.snapping_distance = 16
	_ed.graph_edit.right_disconnects = true
	# La minimap native ne dessine pas l'overlay des liens (elle resterait vide) :
	# on la désactive, la vue d'ensemble se fait avec « Cadrer » + zoom.
	_ed.graph_edit.minimap_enabled = false
	if _ed.graph_edit.has_method("set_connection_lines_curvature"):
		_ed.graph_edit.connection_lines_curvature = 0.35
	if "connection_lines_thickness" in _ed.graph_edit:
		_ed.graph_edit.connection_lines_thickness = 2.0
	# Clic-glisser sur le fond = déplacer la vue (en plus du clic milieu).
	if not _ed.graph_edit.gui_input.is_connected(_ed._on_graph_gui_input):
		_ed.graph_edit.gui_input.connect(_ed._on_graph_gui_input)
	# Le zoom et les outils sont dans la sous-barre : on masque la barre d'outils
	# native de GraphEdit (boutons de zoom, grille, accroche, menu, minimap).
	for native_toolbar_prop in [
		"show_zoom_buttons", "show_zoom_label", "show_grid_buttons",
		"show_minimap_button", "show_arrange_button", "show_menu",
	]:
		if _ed._property_exists(_ed.graph_edit, str(native_toolbar_prop)):
			_ed.graph_edit.set(str(native_toolbar_prop), false)
	# Bornes de zoom alignées sur les boutons − / + de la sous-barre.
	if _ed._property_exists(_ed.graph_edit, "zoom_min"):
		_ed.graph_edit.set("zoom_min", GRAPH_ZOOM_MIN)
	if _ed._property_exists(_ed.graph_edit, "zoom_max"):
		_ed.graph_edit.set("zoom_max", GRAPH_ZOOM_MAX)
	_ed._setup_link_overlay()

func _setup_link_overlay() -> void:
	if _ed._link_overlay != null and is_instance_valid(_ed._link_overlay):
		return
	_ed._link_overlay = GraphLinkOverlayScript.new()
	_ed._link_overlay.name = "GraphLinkOverlay"
	_ed.add_child(_ed._link_overlay)
	_ed._link_overlay.call("setup", _ed.graph_edit,
		func() -> Dictionary: return _ed._scenario,
		func() -> String: return _ed._selected_scene_id)

func _notify_links_changed() -> void:
	if _ed._link_overlay != null and is_instance_valid(_ed._link_overlay):
		_ed._link_overlay.call("notify_scenario_changed")

func _input(event: InputEvent) -> void:
	if _ed._link_overlay == null or not is_instance_valid(_ed._link_overlay):
		return
	if _ed.graph_edit == null or not is_instance_valid(_ed.graph_edit):
		return
	if event is InputEventMouseMotion:
		var mouse_global := (event as InputEventMouseMotion).global_position
		if _ed.graph_edit.is_visible_in_tree() and _ed.graph_edit.get_global_rect().has_point(mouse_global):
			_ed._link_overlay.call("set_hover_global", mouse_global)
		else:
			_ed._link_overlay.call("clear_hover")
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed or button.button_index != MOUSE_BUTTON_RIGHT:
			return
		var hovered: Dictionary = _ed._link_overlay.call("get_hovered_edge")
		if hovered.is_empty():
			return
		var from_id := str(hovered.get("from_id", ""))
		var to_id := str(hovered.get("to_id", ""))
		if from_id.is_empty() or to_id.is_empty():
			return
		_ed._on_graph_disconnection_request(_ed._graph_node_name_for_id(from_id), 0, _ed._graph_node_name_for_id(to_id), 0)
		if _ed.get_viewport() != null:
			_ed.get_viewport().set_input_as_handled()

func _on_graph_gui_input(event: InputEvent) -> void:
	# Outils Note / Cadre : la souris sert à créer des annotations, pas à pan.
	if _ed._tool == TOOL_NOTE or _ed._tool == TOOL_FRAME:
		if _ed._handle_annotation_input(event):
			return
	# Molette = zoom natif de GraphEdit : on resynchronise le libellé après coup.
	if event is InputEventMouseButton and event.pressed:
		var wheel := event as InputEventMouseButton
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ed.call_deferred("_update_zoom_label")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Ne pas démarrer un pan si le pointeur est sur une scène (évite de bloquer le drag).
			if _ed._is_pointer_over_graph_node():
				return
			_ed._graph_panning = true
			_ed._graph_pan_last = event.position
			_ed.graph_edit.mouse_default_cursor_shape = Control.CURSOR_MOVE
			_ed.graph_edit.accept_event()
		else:
			_ed._stop_graph_panning()
		return
	if event is InputEventMouseMotion and _ed._graph_panning:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_ed._stop_graph_panning()
			return
		var motion := event as InputEventMouseMotion
		_ed.graph_edit.scroll_offset -= motion.relative
		_ed._graph_pan_last = motion.position
		_ed.graph_edit.accept_event()

func _is_pointer_over_graph_node() -> bool:
	var mouse = _ed.graph_edit.get_global_mouse_position()
	for child in _ed.graph_edit.get_children():
		if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
			if (child as Control).get_global_rect().has_point(mouse):
				return true
	return false

func _stop_graph_panning() -> void:
	if not _ed._graph_panning:
		return
	_ed._graph_panning = false
	_ed.graph_edit.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _setup_graph_popup() -> void:
	_ed._graph_popup = PopupMenu.new()
	_ed._graph_popup.name = "GraphScenePopup"
	_ed.add_child(_ed._graph_popup)
	_ed._graph_popup.index_pressed.connect(_ed._on_graph_popup_index_pressed)

func _connect_graph_signals() -> void:
	_ed.graph_edit.connection_request.connect(_ed._on_graph_connection_request)
	_ed.graph_edit.disconnection_request.connect(_ed._on_graph_disconnection_request)
	_ed.graph_edit.node_selected.connect(_ed._on_graph_node_selected)
	_ed.graph_edit.popup_request.connect(_ed._on_graph_popup_request)
	if _ed.graph_edit.has_signal("end_node_move"):
		_ed.graph_edit.end_node_move.connect(_ed._on_graph_end_node_move)
	if _ed.graph_edit.has_signal("node_dragged"):
		_ed.graph_edit.node_dragged.connect(_ed._on_graph_node_dragged)

func _on_zoom_in_pressed() -> void:
	_ed._set_graph_zoom(_ed.graph_edit.zoom * 1.1)

func _on_zoom_out_pressed() -> void:
	_ed._set_graph_zoom(_ed.graph_edit.zoom * 0.9)

func _set_graph_zoom(value: float) -> void:
	if _ed.graph_edit == null:
		return
	_ed.graph_edit.zoom = clampf(value, GRAPH_ZOOM_MIN, GRAPH_ZOOM_MAX)
	_ed._update_zoom_label()

func _update_zoom_label() -> void:
	if _ed.graph_edit == null or _ed.zoom_lbl == null:
		return
	_ed.zoom_lbl.text = "%d %%" % int(round(_ed.graph_edit.zoom * 100.0))

func _rebuild_graph() -> void:
	if _ed._rebuild_scheduled:
		return
	_ed._rebuild_scheduled = true
	_ed.call_deferred("_rebuild_graph_deferred")

func _rebuild_graph_deferred() -> void:
	_ed._rebuild_scheduled = false
	_ed._rebuilding_graph = true
	_ed._commit_scene_editor()
	_ed._sync_graph_layout_from_nodes()
	if _ed.graph_edit.has_method("clear_connections"):
		_ed.graph_edit.clear_connections()
	var stale: Array = []
	for child in _ed.graph_edit.get_children():
		if child is GraphNode:
			stale.append(child)
	for child in stale:
		_ed.graph_edit.remove_child(child)
		child.free()

	var scenes: Array = _ed._scenario.get("scenes", [])
	var analysis = QuestNavigation.analyze_graph(_ed._scenario)
	var unreachable: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		unreachable[str(uid)] = true

	for i in range(scenes.size()):
		var scene: Dictionary = scenes[i]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid: String = str(scene.get("id", "scene-%d" % i))
		var node = _ed._build_scene_graph_node(scene, sid, i, unreachable.has(sid))
		_ed.graph_edit.add_child(node)

	_ed._apply_all_graph_connections()
	_ed._rebuilding_graph = false
	_ed._refresh_graph_health()
	if not _ed._pending_focus_scene_id.is_empty():
		var focus_id = _ed._pending_focus_scene_id
		_ed._pending_focus_scene_id = ""
		_ed.call_deferred("_focus_graph_on_scene", focus_id)

func _sync_graph_layout_from_nodes() -> void:
	for child in _ed.graph_edit.get_children():
		if not child is GraphNode or not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var sid := str(child.get_meta("scene_id", ""))
		var idx = _ed._scene_index_for_id(sid)
		if idx < 0:
			continue
		var scene: Dictionary = _ed._scenario["scenes"][idx]
		scene["graphPos"] = { "x": child.position_offset.x, "y": child.position_offset.y }
		var sz: Vector2 = child.size
		if child.has_meta("graph_size"):
			sz = child.get_meta("graph_size")
		if sz.x >= 10.0 and sz.y >= 10.0:
			scene["graphSize"] = { "w": sz.x, "h": sz.y }
		_ed._scenario["scenes"][idx] = scene

func _build_scene_graph_node(scene: Dictionary, sid: String, index: int, is_unreachable: bool) -> GraphNode:
	var node := GraphNodeScene.instantiate()
	node.name = _ed._stable_graph_node_name(sid)
	node.position_offset = _ed._scene_graph_pos(scene, index)
	node.setup(scene, sid, index, is_unreachable, str(_ed._scenario.get("startSceneId", "")), _ed._selected_scene_id)
	node.context_requested.connect(_ed._on_graph_node_context_requested)
	node.scene_activated.connect(_ed._on_graph_scene_activated)
	node.scene_focus_requested.connect(_ed._on_graph_scene_focus_requested)
	node.resize_request.connect(func(new_minsize: Vector2): _ed._on_graph_node_resize_request(node, new_minsize))
	node.draggable = true
	node.selectable = true
	return node

func _apply_all_graph_connections() -> void:
	if _ed.graph_edit.has_method("clear_connections"):
		_ed.graph_edit.clear_connections()
	var scenes: Array = _ed._scenario.get("scenes", [])
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_id := str(scene.get("id", ""))
		var from_name = _ed._graph_node_name_for_id(from_id)
		if from_name.is_empty():
			continue
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", ""))
			if to_id.is_empty() or to_id == from_id:
				continue
			var to_name = _ed._graph_node_name_for_id(to_id)
			if to_name.is_empty():
				continue
			if not _ed.graph_edit.is_node_connected(from_name, 0, to_name, 0):
				_ed.graph_edit.connect_node(from_name, 0, to_name, 0)
			_ed._set_connection_activity_for_transition(from_name, to_name, transition)

func _set_connection_activity_for_transition(from_name: StringName, to_name: StringName, transition: Dictionary) -> void:
	# Les liens natifs de GraphEdit sont masqués : c'est l'overlay qui dessine les
	# branches (couleurs ★/branche/MJ). L'« activité » de GraphEdit mélange la
	# connexion vers une couleur claire et la rendait visible PAR-DESSUS les cartes
	# (couche _connection_layer) : on la force à 0 (couleur du port = transparente).
	_ed.graph_edit.set_connection_activity(from_name, 0, to_name, 0, 0.0)

func _connect_graph_edge(from_id: String, to_id: String, transition: Dictionary = {}) -> void:
	var from_name = _ed._graph_node_name_for_id(from_id)
	var to_name = _ed._graph_node_name_for_id(to_id)
	if from_name.is_empty() or to_name.is_empty():
		return
	if not _ed.graph_edit.is_node_connected(from_name, 0, to_name, 0):
		_ed.graph_edit.connect_node(from_name, 0, to_name, 0)
	if not transition.is_empty():
		_ed._set_connection_activity_for_transition(from_name, to_name, transition)
	else:
		_ed.graph_edit.set_connection_activity(from_name, 0, to_name, 0, 0.0)

func _disconnect_graph_edge(from_id: String, to_id: String) -> void:
	var from_name = _ed._graph_node_name_for_id(from_id)
	var to_name = _ed._graph_node_name_for_id(to_id)
	if from_name.is_empty() or to_name.is_empty():
		return
	if _ed.graph_edit.is_node_connected(from_name, 0, to_name, 0):
		_ed.graph_edit.disconnect_node(from_name, 0, to_name, 0)

func _refresh_graph_node_chrome(scene_id: String = "") -> void:
	_ed._notify_links_changed()
	var analysis = QuestNavigation.analyze_graph(_ed._scenario)
	var unreachable: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		unreachable[str(uid)] = true
	var start_id = str(_ed._scenario.get("startSceneId", ""))
	for child in _ed.graph_edit.get_children():
		if not child is GraphNode or not child.has_method("refresh_chrome"):
			continue
		var sid := str(child.get_meta("scene_id", ""))
		if not scene_id.is_empty() and sid != scene_id:
			continue
		var scene = _ed._get_scene_dict(sid)
		if scene.is_empty():
			continue
		child.refresh_chrome(scene, sid, unreachable.has(sid), start_id, _ed._selected_scene_id)

func _scene_graph_pos(scene: Dictionary, index: int) -> Vector2:
	var gp = scene.get("graphPos", {})
	if gp is Dictionary and gp.has("x") and gp.has("y"):
		return Vector2(float(gp["x"]), float(gp["y"]))
	var col := index % 3
	var row := int(index / 3)
	return Vector2(40.0 + col * 280.0, 40.0 + row * 210.0)

func _stable_graph_node_name(scene_id: String) -> String:
	var safe := scene_id.validate_node_name()
	if safe.is_empty():
		safe = "unknown"
	return "SN_%s" % safe

func _graph_node_name_for_id(scene_id: String) -> StringName:
	if scene_id.is_empty() or _ed._scene_index_for_id(scene_id) < 0:
		return StringName("")
	return StringName(_ed._stable_graph_node_name(scene_id))

func _scene_index_for_id(scene_id: String) -> int:
	var scenes: Array = _ed._scenario.get("scenes", [])
	for i in range(scenes.size()):
		if str(scenes[i].get("id", "")) == scene_id:
			return i
	return -1

func _get_scene_dict(scene_id: String) -> Dictionary:
	var idx = _ed._scene_index_for_id(scene_id)
	if idx < 0:
		return {}
	return _ed._scenario["scenes"][idx]

func _on_graph_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _ed._rebuilding_graph:
		return
	var from_id = _ed._scene_id_from_graph_node(from_node)
	var to_id = _ed._scene_id_from_graph_node(to_node)
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		_ed._set_status("Lien impossible (même scène).")
		return
	if _ed._has_transition(from_id, to_id):
		_ed._set_status("Cette branche existe déjà.")
		return
	_ed._add_or_update_transition(from_id, to_id, "Nouvelle branche", false, false)
	if not _ed.graph_edit.is_node_connected(from_node, from_port, to_node, to_port):
		_ed.graph_edit.connect_node(from_node, from_port, to_node, to_port)
	_ed.graph_edit.set_connection_activity(from_node, from_port, to_node, to_port, 0.0)
	_ed._mark_dirty("Branche créée")
	_ed._refresh_graph_node_chrome(from_id)
	if _ed._selected_scene_id == from_id:
		_ed._refresh_transitions_ui()
		_ed._refresh_scene_panel()

func _on_graph_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _ed._rebuilding_graph:
		return
	var from_id = _ed._scene_id_from_graph_node(from_node)
	var to_id = _ed._scene_id_from_graph_node(to_node)
	if _ed.graph_edit.is_node_connected(from_node, from_port, to_node, to_port):
		_ed.graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	_ed._remove_transition(from_id, to_id)
	_ed._mark_dirty("Branche retirée")
	_ed._refresh_graph_node_chrome(from_id)
	if _ed._selected_scene_id == from_id:
		_ed._refresh_transitions_ui()
		_ed._refresh_scene_panel()

func _scene_id_from_graph_node(node_name: StringName) -> String:
	for child in _ed.graph_edit.get_children():
		if child is GraphNode and child.name == node_name:
			return str(child.get_meta("scene_id", ""))
	return ""

func _on_graph_node_selected(node: Node) -> void:
	if not node is GraphNode:
		return
	var sid := str(node.get_meta("scene_id", ""))
	if _ed._tool == TOOL_LINK:
		_ed._handle_link_click(sid)
		return
	_ed._open_scene_editor(sid, false)

func _on_graph_scene_activated(scene_id: String) -> void:
	if _ed._tool == TOOL_LINK:
		return
	_ed._open_scene_editor(scene_id, false)

func _on_graph_scene_focus_requested(scene_id: String) -> void:
	if _ed._tool == TOOL_LINK:
		return
	_ed._open_scene_editor(scene_id, true)

func _refresh_graph_selection_styles() -> void:
	for child in _ed.graph_edit.get_children():
		if child is GraphNode and child.has_method("set_selected_visual"):
			var sid := str(child.get_meta("scene_id", ""))
			child.set_selected_visual(sid == _ed._selected_scene_id)

func _on_graph_node_resize_request(node: GraphNode, new_minsize: Vector2) -> void:
	var clamped := new_minsize
	if node.has_method("apply_size"):
		clamped = node.apply_size(new_minsize)
	else:
		clamped = Vector2(
			clampf(new_minsize.x, 160.0, 520.0),
			clampf(new_minsize.y, 90.0, 420.0)
		)
		node.custom_minimum_size = clamped
		node.size = clamped
	var sid := str(node.get_meta("scene_id", ""))
	_ed._store_scene_graph_size(sid, clamped)

func _store_scene_graph_size(sid: String, sz: Vector2) -> void:
	var idx = _ed._scene_index_for_id(sid)
	if idx < 0 or sz.x < 10.0 or sz.y < 10.0:
		return
	var scene: Dictionary = _ed._scenario["scenes"][idx]
	scene["graphSize"] = { "w": sz.x, "h": sz.y }
	_ed._scenario["scenes"][idx] = scene
	_ed._dirty = true

func _on_graph_popup_request(at_position: Vector2) -> void:
	_ed._show_graph_scene_popup("", _ed.graph_edit.get_screen_position() + at_position)

func _on_graph_node_context_requested(scene_id: String, screen_pos: Vector2) -> void:
	_ed._show_graph_scene_popup(scene_id, screen_pos)

func _show_graph_scene_popup(context_scene_id: String, screen_pos: Vector2) -> void:
	_ed._graph_popup.clear()
	var has_branches := false
	if not context_scene_id.is_empty():
		var context_scene = _ed._get_scene_dict(context_scene_id)
		var transitions: Array = context_scene.get("transitions", [])
		if typeof(transitions) == TYPE_ARRAY:
			for transition in transitions:
				if typeof(transition) != TYPE_DICTIONARY:
					continue
				var to_id := str(transition.get("to", ""))
				if to_id.is_empty() or _ed._scene_index_for_id(to_id) < 0:
					continue
				var label := str(transition.get("label", "")).strip_edges()
				if label.is_empty():
					var target = _ed._get_scene_dict(to_id)
					label = str(target.get("title", to_id))
				var mark := "★" if transition.get("default", false) else ("👁" if transition.get("gmOnly", false) else "→")
				var idx = _ed._graph_popup.item_count
				_ed._graph_popup.add_item("%s %s" % [mark, label])
				_ed._graph_popup.set_item_metadata(idx, to_id)
				has_branches = true
	if has_branches:
		_ed._graph_popup.add_separator("Toutes les scènes")
	else:
		_ed._graph_popup.add_separator("Aller à une scène")

	for scene in _ed._scenario.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid := str(scene.get("id", ""))
		if sid.is_empty():
			continue
		var idx = _ed._graph_popup.item_count
		_ed._graph_popup.add_item(QuestNavigation.format_picker_label(scene, sid == _ed._selected_scene_id, false))
		_ed._graph_popup.set_item_metadata(idx, sid)

	if _ed._graph_popup.item_count == 0:
		return
	_ed._graph_popup.position = Vector2i(screen_pos)
	_ed._graph_popup.popup()

func _on_graph_popup_index_pressed(index: int) -> void:
	var sid = str(_ed._graph_popup.get_item_metadata(index))
	if sid.is_empty():
		return
	_ed._select_and_focus_scene(sid)

func _select_and_focus_scene(sid: String) -> void:
	if sid.is_empty():
		return
	_ed._open_scene_editor(sid, true)
	_ed.call_deferred("_focus_graph_on_scene", sid)

func _focus_graph_on_scene(sid: String) -> void:
	var node_name = _ed._graph_node_name_for_id(sid)
	if node_name.is_empty():
		return
	var gn = _ed.graph_edit.get_node_or_null(NodePath(str(node_name)))
	if not gn is GraphNode:
		return
	var z = _ed.graph_edit.zoom
	var view = _ed.graph_edit.size
	if view.x < 10 or view.y < 10:
		return
	var node_size: Vector2 = gn.size
	if node_size.x < 10:
		node_size = Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)
	_ed.graph_edit.scroll_offset = gn.position_offset * z - (view - node_size * z) * 0.5

func _on_graph_node_dragged(node: Node) -> void:
	if not node is GraphNode:
		return
	_ed._persist_graph_node_layout(node)

func _on_graph_end_node_move() -> void:
	_ed._sync_graph_layout_from_nodes()
	if not _ed._dirty:
		_ed._dirty = true

func _persist_graph_node_layout(node: GraphNode) -> void:
	var sid := str(node.get_meta("scene_id", ""))
	var idx = _ed._scene_index_for_id(sid)
	if idx < 0:
		return
	var scene: Dictionary = _ed._scenario["scenes"][idx]
	scene["graphPos"] = { "x": node.position_offset.x, "y": node.position_offset.y }
	_ed._scenario["scenes"][idx] = scene
	_ed._dirty = true

func _scene_graph_size(scene: Dictionary) -> Vector2:
	var gs = scene.get("graphSize", {})
	if typeof(gs) == TYPE_DICTIONARY and gs.has("w") and gs.has("h"):
		return Vector2(float(gs["w"]), float(gs["h"]))
	return Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)

func _refresh_outgoing_connection_styles(from_id: String) -> void:
	var scene = _ed._get_scene_dict(from_id)
	var from_name = _ed._graph_node_name_for_id(from_id)
	if from_name.is_empty() or scene.is_empty():
		return
	for transition in scene.get("transitions", []):
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		var to_name = _ed._graph_node_name_for_id(str(transition.get("to", "")))
		if to_name.is_empty():
			continue
		if _ed.graph_edit.is_node_connected(from_name, 0, to_name, 0):
			_ed._set_connection_activity_for_transition(from_name, to_name, transition)
	_ed._refresh_graph_node_chrome(from_id)

func _on_auto_layout_pressed() -> void:
	_ed._commit_scene_editor()
	_ed._scenario = QuestNavigation.apply_auto_layout(_ed._scenario)
	_ed._mark_dirty("Disposition automatique")
	_ed._journal_add("Disposition automatique appliquée (auto-layout)")
	_ed._rebuild_graph()
	_ed.call_deferred("_on_fit_view_pressed")

func _on_fit_view_pressed() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var found := false
	for child in _ed.graph_edit.get_children():
		if child is GraphNode:
			found = true
			var pos: Vector2 = child.position_offset
			var size: Vector2 = child.size
			if size.x < 10:
				size = Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)
			min_pos = Vector2(minf(min_pos.x, pos.x), minf(min_pos.y, pos.y))
			max_pos = Vector2(maxf(max_pos.x, pos.x + size.x), maxf(max_pos.y, pos.y + size.y))
	if not found:
		return
	var content := Rect2(min_pos, max_pos - min_pos)
	var view = _ed.graph_edit.size
	if view.x < 10 or view.y < 10:
		return
	var insets := Rect2(FIT_INSET_LEFT, FIT_INSET_TOP,
		FIT_INSET_LEFT + FIT_INSET_RIGHT, FIT_INSET_TOP + FIT_INSET_BOTTOM)
	var available := Vector2(
		maxf(view.x - insets.size.x, 40.0),
		maxf(view.y - insets.size.y, 40.0))
	var zoom := clampf(minf(
		available.x / maxf(content.size.x, 1.0),
		available.y / maxf(content.size.y, 1.0)), GRAPH_ZOOM_MIN, GRAPH_ZOOM_MAX)
	_ed.graph_edit.zoom = zoom
	var drawn := content.size * zoom
	var offset := Vector2(
		FIT_INSET_LEFT + (available.x - drawn.x) * 0.5,
		FIT_INSET_TOP + (available.y - drawn.y) * 0.5)
	_ed.graph_edit.scroll_offset = content.position * zoom - offset
	_ed._update_zoom_label()

func _graph_point_from_global(global_pos: Vector2) -> Vector2:
	var zoom = maxf(_ed.graph_edit.zoom, 0.0001)
	return (global_pos - _ed.graph_edit.global_position + _ed.graph_edit.scroll_offset) / zoom

func _set_tool_preview_graph(rect: Rect2) -> void:
	if _ed._link_overlay != null and is_instance_valid(_ed._link_overlay):
		_ed._link_overlay.call("set_tool_preview_graph", rect)

func _clear_tool_preview() -> void:
	if _ed._link_overlay != null and is_instance_valid(_ed._link_overlay):
		_ed._link_overlay.call("clear_tool_preview")
