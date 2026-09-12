extends Control

const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const GraphNodeScene := preload("res://scenes/scenario_editor/panels/graph_node.tscn")
const TransitionRowScene := preload("res://scenes/scenario_editor/panels/transition_row.tscn")
const NpcRowScene := preload("res://scenes/scenario_editor/panels/npc_row.tscn")

@onready var status_lbl: Label = %LblStatus
@onready var graph_edit: GraphEdit = %GraphEdit
@onready var graph_health_lbl: Label = %LblGraphHealth
@onready var meta_title: LineEdit = %MetaTitle
@onready var meta_synopsis: TextEdit = %MetaSynopsis
@onready var meta_setting: TextEdit = %MetaSetting
@onready var meta_format: OptionButton = %MetaFormat
@onready var meta_roster: OptionButton = %MetaRoster
@onready var meta_mystery: TextEdit = %MetaMystery
@onready var lbl_mystery: Label = %LblMystery
@onready var meta_start_scene: OptionButton = %MetaStartScene
@onready var npc_list: VBoxContainer = %NpcList
@onready var lbl_no_selection: Label = %LblNoSelection
@onready var scene_editor: VBoxContainer = %SceneEditor
@onready var lbl_scene_id: Label = %LblSceneId
@onready var scene_title: LineEdit = %SceneTitle
@onready var scene_tags: LineEdit = %SceneTags
@onready var scene_maps: ItemList = %SceneMaps
@onready var scene_content: TextEdit = %SceneContent
@onready var transitions_list: VBoxContainer = %TransitionsList
@onready var scene_badge_lbl: Label = %LblSceneBadge

var _scenario: Dictionary = {}
var _selected_scene_id: String = ""
var _rebuilding_graph: bool = false
var _locked_roster: String = ""
var _locked_format: String = ""
var _dirty: bool = false
var _graph_popup: PopupMenu
var _pending_focus_scene_id: String = ""
var _graph_panning: bool = false
var _graph_pan_last: Vector2 = Vector2.ZERO
var _refreshing_scene_maps: bool = false
var _rebuild_scheduled: bool = false

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnSave.pressed.connect(_on_save_pressed)
	%BtnAddScene.pressed.connect(_on_add_scene_pressed)
	%BtnAddNpc.pressed.connect(_on_add_npc_pressed)
	%BtnSetStart.pressed.connect(_on_set_start_pressed)
	%BtnDeleteScene.pressed.connect(_on_delete_scene_pressed)
	%BtnAddTransition.pressed.connect(_on_add_transition_pressed)
	%BtnAutoLayout.pressed.connect(_on_auto_layout_pressed)
	%BtnFitView.pressed.connect(_on_fit_view_pressed)
	%BtnValidate.pressed.connect(_on_validate_pressed)
	%ConfirmDeleteScene.confirmed.connect(_on_confirm_delete_scene)
	scene_maps.multi_selected.connect(_on_scene_maps_multi_selected)
	scene_maps.item_selected.connect(func(_idx): _on_scene_maps_changed())

	_configure_graph_edit()
	_setup_graph_popup()
	_setup_option_buttons()
	_apply_entry_context()
	_load_scenario()
	_connect_graph_signals()
	_refresh_all()
	call_deferred("_on_fit_view_pressed")

func _configure_graph_edit() -> void:
	graph_edit.show_grid = true
	graph_edit.snapping_enabled = true
	graph_edit.snapping_distance = 16
	graph_edit.right_disconnects = true
	graph_edit.minimap_enabled = true
	graph_edit.minimap_size = Vector2(140, 90)
	if graph_edit.has_method("set_connection_lines_curvature"):
		graph_edit.connection_lines_curvature = 0.35
	if "connection_lines_thickness" in graph_edit:
		graph_edit.connection_lines_thickness = 2.0
	# Clic-glisser sur le fond = déplacer la vue (en plus du clic milieu).
	if not graph_edit.gui_input.is_connected(_on_graph_gui_input):
		graph_edit.gui_input.connect(_on_graph_gui_input)

func _on_graph_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Ne pas démarrer un pan si le pointeur est sur une scène (évite de bloquer le drag).
			if _is_pointer_over_graph_node():
				return
			_graph_panning = true
			_graph_pan_last = event.position
			graph_edit.mouse_default_cursor_shape = Control.CURSOR_MOVE
			graph_edit.accept_event()
		else:
			_stop_graph_panning()
		return
	if event is InputEventMouseMotion and _graph_panning:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_stop_graph_panning()
			return
		var motion := event as InputEventMouseMotion
		graph_edit.scroll_offset -= motion.relative
		_graph_pan_last = motion.position
		graph_edit.accept_event()

func _is_pointer_over_graph_node() -> bool:
	var mouse := graph_edit.get_global_mouse_position()
	for child in graph_edit.get_children():
		if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
			if (child as Control).get_global_rect().has_point(mouse):
				return true
	return false

func _stop_graph_panning() -> void:
	if not _graph_panning:
		return
	_graph_panning = false
	graph_edit.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _setup_option_buttons() -> void:
	meta_format.clear()
	meta_format.add_item("One-shot", 0)
	meta_format.set_item_metadata(0, "oneshot")
	meta_format.add_item("Campagne longue", 1)
	meta_format.set_item_metadata(1, "long")
	meta_format.add_item("Enquête", 2)
	meta_format.set_item_metadata(2, "investigation")

	meta_roster.clear()
	meta_roster.add_item("Aventure", 0)
	meta_roster.set_item_metadata(0, "general")
	meta_roster.add_item("Enquête", 1)
	meta_roster.set_item_metadata(1, "investigation")

	meta_format.item_selected.connect(_on_meta_changed)
	meta_roster.item_selected.connect(_on_meta_changed)
	meta_title.text_changed.connect(func(_t): _on_meta_changed())
	meta_synopsis.text_changed.connect(func(): _on_meta_changed())
	meta_setting.text_changed.connect(func(): _on_meta_changed())
	meta_mystery.text_changed.connect(func(): _on_meta_changed())

func _apply_entry_context() -> void:
	if get_tree().has_meta("preselected_scenario_roster"):
		_locked_roster = str(get_tree().get_meta("preselected_scenario_roster"))
		get_tree().remove_meta("preselected_scenario_roster")
	if get_tree().has_meta("preselected_quest_format"):
		_locked_format = str(get_tree().get_meta("preselected_quest_format"))
		get_tree().remove_meta("preselected_quest_format")

func _load_scenario() -> void:
	var scenario_id := GameData.editor_scenario_id
	GameData.editor_scenario_id = ""
	if scenario_id.is_empty():
		var roster := _locked_roster if not _locked_roster.is_empty() else "general"
		var fmt := _locked_format if not _locked_format.is_empty() else "oneshot"
		if roster == "investigation":
			fmt = "investigation"
		_scenario = GameData.create_blank_scenario(roster, fmt)
	else:
		var existing := GameData.get_scenario_by_id(scenario_id)
		if existing.is_empty():
			_scenario = GameData.create_blank_scenario()
		else:
			_scenario = existing.duplicate(true)
	_scenario = QuestNavigation.ensure_graph_positions(_scenario)
	_dirty = false

func _setup_graph_popup() -> void:
	_graph_popup = PopupMenu.new()
	_graph_popup.name = "GraphScenePopup"
	add_child(_graph_popup)
	_graph_popup.index_pressed.connect(_on_graph_popup_index_pressed)

func _connect_graph_signals() -> void:
	graph_edit.connection_request.connect(_on_graph_connection_request)
	graph_edit.disconnection_request.connect(_on_graph_disconnection_request)
	graph_edit.node_selected.connect(_on_graph_node_selected)
	graph_edit.popup_request.connect(_on_graph_popup_request)
	if graph_edit.has_signal("end_node_move"):
		graph_edit.end_node_move.connect(_on_graph_end_node_move)
	if graph_edit.has_signal("node_dragged"):
		graph_edit.node_dragged.connect(_on_graph_node_dragged)

func _refresh_all() -> void:
	_sync_meta_ui()
	_rebuild_graph()
	_refresh_npc_list()
	_refresh_scene_panel()
	_update_mystery_visibility()
	_refresh_graph_health()

func _sync_meta_ui() -> void:
	meta_title.text = str(_scenario.get("title", ""))
	meta_synopsis.text = str(_scenario.get("synopsis", ""))
	meta_setting.text = str(_scenario.get("setting", ""))
	meta_mystery.text = str(_scenario.get("mystery", ""))

	var fmt: String = str(_scenario.get("questFormat", "oneshot"))
	for i in range(meta_format.item_count):
		if str(meta_format.get_item_metadata(i)) == fmt:
			meta_format.select(i)
			break
	if not _locked_format.is_empty():
		meta_format.disabled = true

	var roster: String = str(_scenario.get("roster", "general"))
	for i in range(meta_roster.item_count):
		if str(meta_roster.get_item_metadata(i)) == roster:
			meta_roster.select(i)
			break
	if not _locked_roster.is_empty():
		meta_roster.disabled = true

	_refresh_start_scene_options()

func _refresh_start_scene_options() -> void:
	meta_start_scene.clear()
	var start_id := str(_scenario.get("startSceneId", ""))
	var select_idx := 0
	for i in range(_scenario.get("scenes", []).size()):
		var scene: Dictionary = _scenario["scenes"][i]
		var sid := str(scene.get("id", ""))
		var label := "%s (%s)" % [scene.get("title", sid), sid]
		meta_start_scene.add_item(label, i)
		meta_start_scene.set_item_metadata(i, sid)
		if sid == start_id:
			select_idx = i
	if meta_start_scene.item_count > 0:
		meta_start_scene.select(select_idx)
	if not meta_start_scene.item_selected.is_connected(_on_start_scene_selected):
		meta_start_scene.item_selected.connect(_on_start_scene_selected)

func _on_start_scene_selected(_idx: int) -> void:
	if meta_start_scene.selected >= 0:
		_scenario["startSceneId"] = str(meta_start_scene.get_item_metadata(meta_start_scene.selected))
		_mark_dirty("Scène de départ mise à jour")
		_rebuild_graph()

func _on_meta_changed(_arg = null) -> void:
	_scenario["title"] = meta_title.text.strip_edges()
	_scenario["synopsis"] = meta_synopsis.text.strip_edges()
	_scenario["setting"] = meta_setting.text.strip_edges()
	_scenario["mystery"] = meta_mystery.text.strip_edges()
	if meta_format.selected >= 0:
		_scenario["questFormat"] = str(meta_format.get_item_metadata(meta_format.selected))
	if meta_roster.selected >= 0:
		_scenario["roster"] = str(meta_roster.get_item_metadata(meta_roster.selected))
	_update_mystery_visibility()
	_dirty = true
	_refresh_graph_health()

func _update_mystery_visibility() -> void:
	var show: bool = str(_scenario.get("roster", "")) == "investigation" or str(_scenario.get("questFormat", "")) == "investigation"
	lbl_mystery.visible = show
	meta_mystery.visible = show

func _refresh_graph_health() -> void:
	var analysis := QuestNavigation.analyze_graph(_scenario)
	graph_health_lbl.text = QuestNavigation.format_graph_health(analysis)
	if analysis.get("ok", false):
		graph_health_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		graph_health_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)

func _rebuild_graph() -> void:
	if _rebuild_scheduled:
		return
	_rebuild_scheduled = true
	call_deferred("_rebuild_graph_deferred")

func _rebuild_graph_deferred() -> void:
	_rebuild_scheduled = false
	_rebuilding_graph = true
	_commit_scene_editor()
	_sync_graph_layout_from_nodes()
	if graph_edit.has_method("clear_connections"):
		graph_edit.clear_connections()
	var stale: Array = []
	for child in graph_edit.get_children():
		if child is GraphNode:
			stale.append(child)
	for child in stale:
		graph_edit.remove_child(child)
		child.free()

	var scenes: Array = _scenario.get("scenes", [])
	var analysis := QuestNavigation.analyze_graph(_scenario)
	var unreachable: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		unreachable[str(uid)] = true

	for i in range(scenes.size()):
		var scene: Dictionary = scenes[i]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid: String = str(scene.get("id", "scene-%d" % i))
		var node := _build_scene_graph_node(scene, sid, i, unreachable.has(sid))
		graph_edit.add_child(node)

	_apply_all_graph_connections()
	_rebuilding_graph = false
	_refresh_graph_health()
	if not _pending_focus_scene_id.is_empty():
		var focus_id := _pending_focus_scene_id
		_pending_focus_scene_id = ""
		call_deferred("_focus_graph_on_scene", focus_id)

func _sync_graph_layout_from_nodes() -> void:
	for child in graph_edit.get_children():
		if not child is GraphNode or not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var sid := str(child.get_meta("scene_id", ""))
		var idx := _scene_index_for_id(sid)
		if idx < 0:
			continue
		var scene: Dictionary = _scenario["scenes"][idx]
		scene["graphPos"] = { "x": child.position_offset.x, "y": child.position_offset.y }
		var sz: Vector2 = child.size
		if child.has_meta("graph_size"):
			sz = child.get_meta("graph_size")
		if sz.x >= 10.0 and sz.y >= 10.0:
			scene["graphSize"] = { "w": sz.x, "h": sz.y }
		_scenario["scenes"][idx] = scene

func _build_scene_graph_node(scene: Dictionary, sid: String, index: int, is_unreachable: bool) -> GraphNode:
	var node := GraphNodeScene.instantiate()
	node.name = _stable_graph_node_name(sid)
	node.position_offset = _scene_graph_pos(scene, index)
	node.setup(scene, sid, index, is_unreachable, str(_scenario.get("startSceneId", "")), _selected_scene_id)
	node.context_requested.connect(_on_graph_node_context_requested)
	node.scene_activated.connect(_on_graph_scene_activated)
	node.scene_focus_requested.connect(_on_graph_scene_focus_requested)
	node.resize_request.connect(func(new_minsize: Vector2): _on_graph_node_resize_request(node, new_minsize))
	node.draggable = true
	node.selectable = true
	return node

func _apply_all_graph_connections() -> void:
	if graph_edit.has_method("clear_connections"):
		graph_edit.clear_connections()
	var scenes: Array = _scenario.get("scenes", [])
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_id := str(scene.get("id", ""))
		var from_name := _graph_node_name_for_id(from_id)
		if from_name.is_empty():
			continue
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", ""))
			if to_id.is_empty() or to_id == from_id:
				continue
			var to_name := _graph_node_name_for_id(to_id)
			if to_name.is_empty():
				continue
			if not graph_edit.is_node_connected(from_name, 0, to_name, 0):
				graph_edit.connect_node(from_name, 0, to_name, 0)
			_set_connection_activity_for_transition(from_name, to_name, transition)

func _set_connection_activity_for_transition(from_name: StringName, to_name: StringName, transition: Dictionary) -> void:
	var activity := 1.0 if transition.get("default", false) else (0.35 if transition.get("gmOnly", false) else 0.7)
	graph_edit.set_connection_activity(from_name, 0, to_name, 0, activity)

func _connect_graph_edge(from_id: String, to_id: String, transition: Dictionary = {}) -> void:
	var from_name := _graph_node_name_for_id(from_id)
	var to_name := _graph_node_name_for_id(to_id)
	if from_name.is_empty() or to_name.is_empty():
		return
	if not graph_edit.is_node_connected(from_name, 0, to_name, 0):
		graph_edit.connect_node(from_name, 0, to_name, 0)
	if not transition.is_empty():
		_set_connection_activity_for_transition(from_name, to_name, transition)
	else:
		graph_edit.set_connection_activity(from_name, 0, to_name, 0, 0.7)

func _disconnect_graph_edge(from_id: String, to_id: String) -> void:
	var from_name := _graph_node_name_for_id(from_id)
	var to_name := _graph_node_name_for_id(to_id)
	if from_name.is_empty() or to_name.is_empty():
		return
	if graph_edit.is_node_connected(from_name, 0, to_name, 0):
		graph_edit.disconnect_node(from_name, 0, to_name, 0)

func _refresh_graph_node_chrome(scene_id: String = "") -> void:
	var analysis := QuestNavigation.analyze_graph(_scenario)
	var unreachable: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		unreachable[str(uid)] = true
	var start_id := str(_scenario.get("startSceneId", ""))
	for child in graph_edit.get_children():
		if not child is GraphNode or not child.has_method("refresh_chrome"):
			continue
		var sid := str(child.get_meta("scene_id", ""))
		if not scene_id.is_empty() and sid != scene_id:
			continue
		var scene := _get_scene_dict(sid)
		if scene.is_empty():
			continue
		child.refresh_chrome(scene, sid, unreachable.has(sid), start_id, _selected_scene_id)

func _scene_graph_pos(scene: Dictionary, index: int) -> Vector2:
	var gp = scene.get("graphPos", {})
	if gp is Dictionary and gp.has("x") and gp.has("y"):
		return Vector2(float(gp["x"]), float(gp["y"]))
	var col := index % 3
	var row := int(index / 3)
	return Vector2(40.0 + col * 260.0, 40.0 + row * 150.0)

func _stable_graph_node_name(scene_id: String) -> String:
	var safe := scene_id.validate_node_name()
	if safe.is_empty():
		safe = "unknown"
	return "SN_%s" % safe

func _graph_node_name_for_id(scene_id: String) -> StringName:
	if scene_id.is_empty() or _scene_index_for_id(scene_id) < 0:
		return StringName("")
	return StringName(_stable_graph_node_name(scene_id))

func _scene_index_for_id(scene_id: String) -> int:
	var scenes: Array = _scenario.get("scenes", [])
	for i in range(scenes.size()):
		if str(scenes[i].get("id", "")) == scene_id:
			return i
	return -1

func _get_scene_dict(scene_id: String) -> Dictionary:
	var idx := _scene_index_for_id(scene_id)
	if idx < 0:
		return {}
	return _scenario["scenes"][idx]

func _on_graph_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding_graph:
		return
	var from_id := _scene_id_from_graph_node(from_node)
	var to_id := _scene_id_from_graph_node(to_node)
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		_set_status("Lien impossible (même scène).")
		return
	if _has_transition(from_id, to_id):
		_set_status("Cette branche existe déjà.")
		return
	_add_or_update_transition(from_id, to_id, "Nouvelle branche", false, false)
	if not graph_edit.is_node_connected(from_node, from_port, to_node, to_port):
		graph_edit.connect_node(from_node, from_port, to_node, to_port)
	graph_edit.set_connection_activity(from_node, from_port, to_node, to_port, 0.7)
	_mark_dirty("Branche créée")
	_refresh_graph_node_chrome(from_id)
	if _selected_scene_id == from_id:
		_refresh_transitions_ui()
		_refresh_scene_panel()

func _on_graph_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding_graph:
		return
	var from_id := _scene_id_from_graph_node(from_node)
	var to_id := _scene_id_from_graph_node(to_node)
	if graph_edit.is_node_connected(from_node, from_port, to_node, to_port):
		graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	_remove_transition(from_id, to_id)
	_mark_dirty("Branche retirée")
	_refresh_graph_node_chrome(from_id)
	if _selected_scene_id == from_id:
		_refresh_transitions_ui()
		_refresh_scene_panel()

func _scene_id_from_graph_node(node_name: StringName) -> String:
	for child in graph_edit.get_children():
		if child is GraphNode and child.name == node_name:
			return str(child.get_meta("scene_id", ""))
	return ""

func _on_graph_node_selected(node: Node) -> void:
	if not node is GraphNode:
		return
	var sid := str(node.get_meta("scene_id", ""))
	_open_scene_editor(sid, false)

func _on_graph_scene_activated(scene_id: String) -> void:
	_open_scene_editor(scene_id, false)

func _on_graph_scene_focus_requested(scene_id: String) -> void:
	_open_scene_editor(scene_id, true)

func _open_scene_editor(sid: String, focus_fields: bool = false) -> void:
	if sid.is_empty():
		return
	# Ne pas reconstruire le graphe ici : ça casse le glisser-déposer au clic gauche.
	if sid != _selected_scene_id:
		_commit_scene_editor()
		_selected_scene_id = sid
		_refresh_graph_selection_styles()
	_refresh_scene_panel()
	# Focus uniquement sur un vrai clic (pas pendant un drag), sinon le déplacement est annulé.
	if focus_fields:
		call_deferred("_focus_scene_editor_fields")

func _focus_scene_editor_fields() -> void:
	if not scene_editor.visible:
		return
	if scene_title:
		scene_title.grab_focus()
		scene_title.caret_column = scene_title.text.length()

func _refresh_graph_selection_styles() -> void:
	for child in graph_edit.get_children():
		if child is GraphNode and child.has_method("set_selected_visual"):
			var sid := str(child.get_meta("scene_id", ""))
			child.set_selected_visual(sid == _selected_scene_id)

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
	_store_scene_graph_size(sid, clamped)

func _store_scene_graph_size(sid: String, sz: Vector2) -> void:
	var idx := _scene_index_for_id(sid)
	if idx < 0 or sz.x < 10.0 or sz.y < 10.0:
		return
	var scene: Dictionary = _scenario["scenes"][idx]
	scene["graphSize"] = { "w": sz.x, "h": sz.y }
	_scenario["scenes"][idx] = scene
	_dirty = true

func _on_graph_popup_request(at_position: Vector2) -> void:
	_show_graph_scene_popup("", graph_edit.get_screen_position() + at_position)

func _on_graph_node_context_requested(scene_id: String, screen_pos: Vector2) -> void:
	_show_graph_scene_popup(scene_id, screen_pos)

func _show_graph_scene_popup(context_scene_id: String, screen_pos: Vector2) -> void:
	_graph_popup.clear()
	var has_branches := false
	if not context_scene_id.is_empty():
		var context_scene := _get_scene_dict(context_scene_id)
		var transitions: Array = context_scene.get("transitions", [])
		if typeof(transitions) == TYPE_ARRAY:
			for transition in transitions:
				if typeof(transition) != TYPE_DICTIONARY:
					continue
				var to_id := str(transition.get("to", ""))
				if to_id.is_empty() or _scene_index_for_id(to_id) < 0:
					continue
				var label := str(transition.get("label", "")).strip_edges()
				if label.is_empty():
					var target := _get_scene_dict(to_id)
					label = str(target.get("title", to_id))
				var mark := "★" if transition.get("default", false) else ("👁" if transition.get("gmOnly", false) else "→")
				var idx := _graph_popup.item_count
				_graph_popup.add_item("%s %s" % [mark, label])
				_graph_popup.set_item_metadata(idx, to_id)
				has_branches = true
	if has_branches:
		_graph_popup.add_separator("Toutes les scènes")
	else:
		_graph_popup.add_separator("Aller à une scène")

	for scene in _scenario.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid := str(scene.get("id", ""))
		if sid.is_empty():
			continue
		var idx := _graph_popup.item_count
		_graph_popup.add_item(QuestNavigation.format_picker_label(scene, sid == _selected_scene_id, false))
		_graph_popup.set_item_metadata(idx, sid)

	if _graph_popup.item_count == 0:
		return
	_graph_popup.position = Vector2i(screen_pos)
	_graph_popup.popup()

func _on_graph_popup_index_pressed(index: int) -> void:
	var sid := str(_graph_popup.get_item_metadata(index))
	if sid.is_empty():
		return
	_select_and_focus_scene(sid)

func _select_and_focus_scene(sid: String) -> void:
	if sid.is_empty():
		return
	_open_scene_editor(sid, true)
	call_deferred("_focus_graph_on_scene", sid)

func _focus_graph_on_scene(sid: String) -> void:
	var node_name := _graph_node_name_for_id(sid)
	if node_name.is_empty():
		return
	var gn := graph_edit.get_node_or_null(NodePath(str(node_name)))
	if not gn is GraphNode:
		return
	var z := graph_edit.zoom
	var view := graph_edit.size
	if view.x < 10 or view.y < 10:
		return
	var node_size: Vector2 = gn.size
	if node_size.x < 10:
		node_size = Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)
	graph_edit.scroll_offset = gn.position_offset * z - (view - node_size * z) * 0.5

func _on_graph_node_dragged(node: Node) -> void:
	if not node is GraphNode:
		return
	_persist_graph_node_layout(node)

func _on_graph_end_node_move() -> void:
	_sync_graph_layout_from_nodes()
	if not _dirty:
		_dirty = true

func _persist_graph_node_layout(node: GraphNode) -> void:
	var sid := str(node.get_meta("scene_id", ""))
	var idx := _scene_index_for_id(sid)
	if idx < 0:
		return
	var scene: Dictionary = _scenario["scenes"][idx]
	scene["graphPos"] = { "x": node.position_offset.x, "y": node.position_offset.y }
	_scenario["scenes"][idx] = scene
	_dirty = true

func _scene_graph_size(scene: Dictionary) -> Vector2:
	var gs = scene.get("graphSize", {})
	if typeof(gs) == TYPE_DICTIONARY and gs.has("w") and gs.has("h"):
		return Vector2(float(gs["w"]), float(gs["h"]))
	return Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)

func _refresh_scene_panel() -> void:
	if _selected_scene_id.is_empty():
		lbl_no_selection.visible = true
		scene_editor.visible = false
		return
	lbl_no_selection.visible = false
	scene_editor.visible = true
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	lbl_scene_id.text = "id: %s" % _selected_scene_id
	var is_start: bool = _selected_scene_id == str(_scenario.get("startSceneId", ""))
	var transitions: Array = scene.get("transitions", [])
	var is_terminal: bool = typeof(transitions) != TYPE_ARRAY or transitions.is_empty()
	if is_start:
		scene_badge_lbl.text = "★ Scène de départ"
		scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.GOLD)
	elif is_terminal:
		scene_badge_lbl.text = "⚑ Scène terminale"
		scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		var branch_n: int = transitions.size() if typeof(transitions) == TYPE_ARRAY else 0
		scene_badge_lbl.text = "↔ %d branche(s) sortante(s)" % branch_n
		scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	scene_title.text = str(scene.get("title", ""))
	var tags: Array = scene.get("tags", [])
	if tags is Array:
		var tag_texts: PackedStringArray = []
		for tag in tags:
			tag_texts.append(str(tag))
		scene_tags.text = ", ".join(tag_texts)
	else:
		scene_tags.text = ""
	scene_content.text = str(scene.get("content", ""))
	_refresh_scene_maps_ui(scene)
	_refresh_transitions_ui()

func _refresh_scene_maps_ui(scene: Dictionary) -> void:
	_refreshing_scene_maps = true
	scene_maps.clear()
	var roster := str(_scenario.get("roster", "general"))
	var scenario_id := str(_scenario.get("id", ""))
	var selected_ids := QuestNavigation.get_scene_map_ids(scene)
	var maps: Array = MapData.list_linkable_maps_for_scenario(scenario_id, roster)
	if maps.is_empty():
		scene_maps.add_item("Aucune carte disponible pour ce roster")
		scene_maps.set_item_disabled(0, true)
		_refreshing_scene_maps = false
		return
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid := str(m.get("id", ""))
		if mid.is_empty():
			continue
		var title := str(m.get("title", mid))
		var kind := "🌍" if MapData.is_world_map(m) else "🗺️"
		var linked := str(m.get("scenarioId", ""))
		var suffix := ""
		if not linked.is_empty() and linked == scenario_id:
			suffix = " · liée au scénario"
		elif linked.is_empty():
			suffix = " · libre"
		var idx := scene_maps.item_count
		scene_maps.add_item("%s %s%s" % [kind, title, suffix])
		scene_maps.set_item_metadata(idx, mid)
		if selected_ids.has(mid):
			scene_maps.select(idx, false)
	_refreshing_scene_maps = false

func _on_scene_maps_multi_selected(_index: int, _selected: bool) -> void:
	_on_scene_maps_changed()

func _on_scene_maps_changed() -> void:
	if _refreshing_scene_maps or _selected_scene_id.is_empty():
		return
	_commit_scene_maps_from_ui()
	_mark_dirty("Cartes de scène mises à jour")

func _commit_scene_maps_from_ui() -> void:
	if _selected_scene_id.is_empty() or _refreshing_scene_maps:
		return
	var idx := _scene_index_for_id(_selected_scene_id)
	if idx < 0:
		return
	# Ne pas écraser mapIds quand la liste affiche seulement le placeholder désactivé.
	if scene_maps.item_count == 0:
		return
	if scene_maps.item_count == 1 and scene_maps.is_item_disabled(0):
		return
	var selected: Array = []
	for i in scene_maps.get_selected_items():
		var mid := str(scene_maps.get_item_metadata(i))
		if mid.is_empty():
			continue
		selected.append(mid)
		_ensure_map_linked_to_scenario(mid)
	var scene: Dictionary = _scenario["scenes"][idx]
	scene["mapIds"] = selected
	_scenario["scenes"][idx] = scene

func _ensure_map_linked_to_scenario(map_id: String) -> void:
	var scenario_id := str(_scenario.get("id", ""))
	if scenario_id.is_empty() or map_id.is_empty():
		return
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return
	if str(map_data.get("scenarioId", "")).is_empty():
		map_data["scenarioId"] = scenario_id
		MapData.update_map(map_data)

func _commit_scene_editor() -> void:
	if _selected_scene_id.is_empty():
		return
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	var prev_title := str(scene.get("title", ""))
	scene["title"] = scene_title.text.strip_edges()
	scene["content"] = scene_content.text.strip_edges()
	var tag_parts := scene_tags.text.split(",", false)
	var tags: Array = []
	for part in tag_parts:
		var tag := str(part).strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	scene["tags"] = tags
	_commit_scene_maps_from_ui()
	if scene["title"] != prev_title:
		_dirty = true

func _refresh_transitions_ui() -> void:
	for child in transitions_list.get_children():
		child.queue_free()
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	var transitions: Array = scene.get("transitions", [])
	if transitions.is_empty():
		var empty := Label.new()
		empty.text = "Aucune branche — scène terminale, ou glissez un lien depuis le graphe."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		transitions_list.add_child(empty)
		return
	for t_idx in range(transitions.size()):
		var transition: Dictionary = transitions[t_idx]
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		transitions_list.add_child(_create_transition_row(_selected_scene_id, t_idx, transition))

func _create_transition_row(from_id: String, index: int, transition: Dictionary) -> PanelContainer:
	var row := TransitionRowScene.instantiate()
	row.setup(transition)
	_populate_target_options(row.get_target_option(), str(transition.get("to", "")), from_id, index)
	var captured_idx := index
	row.target_changed.connect(func(to_id: String):
		_on_transition_target_changed(from_id, captured_idx, to_id)
	)
	row.label_changed.connect(func(text: String):
		_update_transition_field(from_id, captured_idx, "label", text)
		_dirty = true
	)
	row.default_toggled.connect(func(on: bool):
		if on:
			_clear_default_transitions(from_id)
		_update_transition_field(from_id, captured_idx, "default", on)
		_mark_dirty()
		_refresh_outgoing_connection_styles(from_id)
		call_deferred("_refresh_transitions_ui")
	)
	row.gm_only_toggled.connect(func(on: bool):
		_update_transition_field(from_id, captured_idx, "gmOnly", on)
		_mark_dirty()
		_refresh_outgoing_connection_styles(from_id)
		call_deferred("_refresh_transitions_ui")
	)
	row.delete_pressed.connect(func():
		var old_to := _transition_to_at(from_id, captured_idx)
		_remove_transition_at(from_id, captured_idx)
		if not old_to.is_empty():
			_disconnect_graph_edge(from_id, old_to)
		_mark_dirty("Branche supprimée")
		_refresh_graph_node_chrome(from_id)
		_refresh_transitions_ui()
		_refresh_scene_panel()
	)
	return row

func _populate_target_options(opt: OptionButton, selected_id: String, exclude_id: String = "", transition_index: int = -1) -> void:
	opt.clear()
	var select_idx := -1
	var added := 0
	var taken: Dictionary = {}
	if not exclude_id.is_empty():
		var scene := _get_scene_dict(exclude_id)
		var transitions: Array = scene.get("transitions", [])
		for i in range(transitions.size()):
			if i == transition_index:
				continue
			if typeof(transitions[i]) == TYPE_DICTIONARY:
				var other_to := str(transitions[i].get("to", ""))
				if not other_to.is_empty():
					taken[other_to] = true
	for i in range(_scenario.get("scenes", []).size()):
		var scene: Dictionary = _scenario["scenes"][i]
		var sid := str(scene.get("id", ""))
		if sid.is_empty() or sid == exclude_id:
			continue
		if taken.has(sid) and sid != selected_id:
			continue
		opt.add_item("%s" % scene.get("title", sid), added)
		opt.set_item_metadata(added, sid)
		if sid == selected_id:
			select_idx = added
		added += 1
	if opt.item_count <= 0:
		opt.add_item("(aucune cible)", 0)
		opt.set_item_metadata(0, "")
		opt.set_item_disabled(0, true)
		opt.select(0)
		return
	if select_idx < 0:
		# Cible invalide / orpheline : on l'ajoute pour ne pas basculer silencieusement.
		if not selected_id.is_empty():
			opt.add_item("⚠ %s (manquante)" % selected_id, added)
			opt.set_item_metadata(added, selected_id)
			select_idx = added
		else:
			select_idx = 0
	opt.select(select_idx)

func _on_transition_target_changed(from_id: String, index: int, to_id: String) -> void:
	to_id = to_id.strip_edges()
	if to_id.is_empty() or to_id == from_id:
		_set_status("Cible de branche invalide.")
		call_deferred("_refresh_transitions_ui")
		return
	var old_to := _transition_to_at(from_id, index)
	if old_to == to_id:
		return
	if _has_transition(from_id, to_id):
		_set_status("Cette branche existe déjà.")
		call_deferred("_refresh_transitions_ui")
		return
	_update_transition_field(from_id, index, "to", to_id)
	if not old_to.is_empty():
		_disconnect_graph_edge(from_id, old_to)
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	var tr: Dictionary = {}
	if index >= 0 and index < transitions.size() and typeof(transitions[index]) == TYPE_DICTIONARY:
		tr = transitions[index]
	_connect_graph_edge(from_id, to_id, tr)
	_mark_dirty("Cible de branche mise à jour")
	_refresh_graph_node_chrome(from_id)

func _transition_to_at(from_id: String, index: int) -> String:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index < 0 or index >= transitions.size():
		return ""
	if typeof(transitions[index]) != TYPE_DICTIONARY:
		return ""
	return str(transitions[index].get("to", ""))

func _refresh_outgoing_connection_styles(from_id: String) -> void:
	var scene := _get_scene_dict(from_id)
	var from_name := _graph_node_name_for_id(from_id)
	if from_name.is_empty() or scene.is_empty():
		return
	for transition in scene.get("transitions", []):
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		var to_name := _graph_node_name_for_id(str(transition.get("to", "")))
		if to_name.is_empty():
			continue
		if graph_edit.is_node_connected(from_name, 0, to_name, 0):
			_set_connection_activity_for_transition(from_name, to_name, transition)
	_refresh_graph_node_chrome(from_id)

func _update_transition_field(from_id: String, index: int, field: String, value: Variant) -> void:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index < 0 or index >= transitions.size():
		return
	var copy: Dictionary = transitions[index]
	copy[field] = value
	transitions[index] = copy
	scene["transitions"] = transitions

func _clear_default_transitions(from_id: String) -> void:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	for i in range(transitions.size()):
		if typeof(transitions[i]) == TYPE_DICTIONARY:
			transitions[i]["default"] = false
	scene["transitions"] = transitions

func _has_transition(from_id: String, to_id: String) -> bool:
	var scene := _get_scene_dict(from_id)
	for transition in scene.get("transitions", []):
		if typeof(transition) == TYPE_DICTIONARY and str(transition.get("to", "")) == to_id:
			return true
	return false

func _add_or_update_transition(from_id: String, to_id: String, label: String, default: bool, gm_only: bool) -> void:
	var scene := _get_scene_dict(from_id)
	if scene.is_empty() or from_id == to_id:
		return
	var transitions: Array = scene.get("transitions", [])
	for transition in transitions:
		if typeof(transition) == TYPE_DICTIONARY and str(transition.get("to", "")) == to_id:
			return
	if default:
		_clear_default_transitions(from_id)
	transitions.append({ "to": to_id, "label": label, "default": default, "gmOnly": gm_only })
	scene["transitions"] = transitions

func _remove_transition(from_id: String, to_id: String) -> void:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	for i in range(transitions.size() - 1, -1, -1):
		if typeof(transitions[i]) == TYPE_DICTIONARY and str(transitions[i].get("to", "")) == to_id:
			transitions.remove_at(i)
	scene["transitions"] = transitions

func _remove_transition_at(from_id: String, index: int) -> void:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index >= 0 and index < transitions.size():
		transitions.remove_at(index)
	scene["transitions"] = transitions

func _on_add_transition_pressed() -> void:
	if _selected_scene_id.is_empty():
		_set_status("Sélectionnez une scène d'abord.")
		return
	_commit_scene_editor()
	var scenes: Array = _scenario.get("scenes", [])
	var target_id := ""
	for scene in scenes:
		var sid := str(scene.get("id", ""))
		if sid != _selected_scene_id and not _has_transition(_selected_scene_id, sid):
			target_id = sid
			break
	if target_id.is_empty():
		_set_status("Ajoutez une autre scène (non déjà liée) pour créer une branche.")
		return
	_add_or_update_transition(_selected_scene_id, target_id, "Nouvelle branche", false, false)
	_connect_graph_edge(_selected_scene_id, target_id, { "to": target_id, "label": "Nouvelle branche", "default": false, "gmOnly": false })
	_mark_dirty("Branche ajoutée")
	_refresh_graph_node_chrome(_selected_scene_id)
	_refresh_transitions_ui()
	_refresh_scene_panel()

func _on_add_scene_pressed() -> void:
	_commit_scene_editor()
	var scenes: Array = _scenario.get("scenes", [])
	var new_id := "scene-%d" % (scenes.size() + 1)
	while _scene_index_for_id(new_id) >= 0:
		new_id += "-x"
	var offset := Vector2(40 + (scenes.size() % 3) * 260, 40 + int(scenes.size() / 3) * 150)
	# Place near selected node if any
	if not _selected_scene_id.is_empty():
		var selected := _get_scene_dict(_selected_scene_id)
		var gp = selected.get("graphPos", {})
		if gp is Dictionary and gp.has("x"):
			offset = Vector2(float(gp["x"]) + QuestNavigation.LAYOUT_H_GAP, float(gp["y"]))
	var new_scene := {
		"id": new_id,
		"title": "Nouvelle scène %d" % (scenes.size() + 1),
		"content": "",
		"tags": [],
		"transitions": [],
		"mapIds": [],
		"graphPos": { "x": offset.x, "y": offset.y },
	}
	scenes.append(new_scene)
	_scenario["scenes"] = scenes
	if scenes.size() == 1:
		_scenario["startSceneId"] = new_id
	# Auto-link from selected scene if it had no path to the new one
	if not _selected_scene_id.is_empty() and _selected_scene_id != new_id:
		var from_scene := _get_scene_dict(_selected_scene_id)
		var existing: Array = from_scene.get("transitions", [])
		if typeof(existing) != TYPE_ARRAY or existing.is_empty():
			_add_or_update_transition(_selected_scene_id, new_id, "Continuer", true, false)
	_selected_scene_id = new_id
	_refresh_start_scene_options()
	_mark_dirty("Scène ajoutée")
	_rebuild_graph()
	_refresh_scene_panel()

func _on_set_start_pressed() -> void:
	if _selected_scene_id.is_empty():
		return
	_scenario["startSceneId"] = _selected_scene_id
	_refresh_start_scene_options()
	_mark_dirty("Scène de départ définie")
	_rebuild_graph()
	_refresh_scene_panel()

func _on_delete_scene_pressed() -> void:
	if _selected_scene_id.is_empty():
		return
	%ConfirmDeleteScene.dialog_text = "Supprimer la scène « %s » et ses liens ?" % _selected_scene_id
	%ConfirmDeleteScene.popup_centered()

func _on_confirm_delete_scene() -> void:
	if _selected_scene_id.is_empty():
		return
	var removing_id := _selected_scene_id
	var scenes: Array = _scenario.get("scenes", [])
	for i in range(scenes.size() - 1, -1, -1):
		if str(scenes[i].get("id", "")) == removing_id:
			scenes.remove_at(i)
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var transitions: Array = scene.get("transitions", [])
		for j in range(transitions.size() - 1, -1, -1):
			if typeof(transitions[j]) == TYPE_DICTIONARY and str(transitions[j].get("to", "")) == removing_id:
				transitions.remove_at(j)
		scene["transitions"] = transitions
	_scenario["scenes"] = scenes
	if str(_scenario.get("startSceneId", "")) == removing_id:
		if not scenes.is_empty():
			_scenario["startSceneId"] = str(scenes[0].get("id", ""))
		else:
			_scenario["startSceneId"] = ""
	_selected_scene_id = ""
	_refresh_start_scene_options()
	_mark_dirty("Scène supprimée")
	_rebuild_graph()
	_refresh_scene_panel()

func _on_auto_layout_pressed() -> void:
	_commit_scene_editor()
	_scenario = QuestNavigation.apply_auto_layout(_scenario)
	_mark_dirty("Disposition automatique")
	_rebuild_graph()
	call_deferred("_on_fit_view_pressed")

func _on_fit_view_pressed() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var found := false
	for child in graph_edit.get_children():
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
	var margin := Vector2(40, 40)
	var bounds := Rect2(min_pos - margin, (max_pos - min_pos) + margin * 2.0)
	var view := graph_edit.size
	if view.x < 10 or view.y < 10:
		return
	var zoom_x := view.x / maxf(bounds.size.x, 1.0)
	var zoom_y := view.y / maxf(bounds.size.y, 1.0)
	var zoom := clampf(minf(zoom_x, zoom_y), 0.35, 1.25)
	graph_edit.zoom = zoom
	graph_edit.scroll_offset = bounds.position * zoom - (view - bounds.size * zoom) * 0.5

func _on_validate_pressed() -> void:
	_commit_scene_editor()
	_on_meta_changed()
	var errors := QuestNavigation.validate_scenario_graph(_scenario)
	var analysis := QuestNavigation.analyze_graph(_scenario)
	_refresh_graph_health()
	if not errors.is_empty():
		_set_status("Erreur : %s" % str(errors[0]))
		return
	var warnings: Array = analysis.get("warnings", [])
	if not warnings.is_empty():
		_set_status("Attention : %s" % str(warnings[0]))
	else:
		_set_status("Graphe valide — %d scènes, %d branches" % [
			int(analysis.get("sceneCount", 0)),
			int(analysis.get("branchCount", 0)),
		])

func _refresh_npc_list() -> void:
	for child in npc_list.get_children():
		child.queue_free()
	for i in range(_scenario.get("npcs", []).size()):
		var npc: Dictionary = _scenario["npcs"][i]
		if typeof(npc) != TYPE_DICTIONARY:
			continue
		npc_list.add_child(_create_npc_row(i, npc))

func _create_npc_row(index: int, npc: Dictionary) -> PanelContainer:
	var row := NpcRowScene.instantiate()
	row.setup(npc)
	row.name_changed.connect(func(text: String):
		_scenario["npcs"][index]["name"] = text
		_dirty = true
	)
	row.role_changed.connect(func(text: String):
		_scenario["npcs"][index]["role"] = text
		_dirty = true
	)
	row.description_changed.connect(func(text: String):
		_scenario["npcs"][index]["description"] = text
		_dirty = true
	)
	row.delete_pressed.connect(func():
		_scenario["npcs"].remove_at(index)
		_dirty = true
		_refresh_npc_list()
	)
	return row

func _on_add_npc_pressed() -> void:
	var npcs: Array = _scenario.get("npcs", [])
	if typeof(npcs) != TYPE_ARRAY:
		npcs = []
	npcs.append({ "id": "npc-%d" % (npcs.size() + 1), "name": "Nouveau PNJ", "role": "", "description": "" })
	_scenario["npcs"] = npcs
	_dirty = true
	_refresh_npc_list()

func _on_save_pressed() -> void:
	_commit_scene_editor()
	_sync_graph_layout_from_nodes()
	_on_meta_changed()
	var normalized := QuestNavigation.normalize_scenario(_scenario.duplicate(true))
	var error := _validate_scenario(normalized)
	if not error.is_empty():
		_set_status("Erreur : %s" % error)
		return
	GameData.save_scenario(normalized)
	_scenario = normalized.duplicate(true)
	_dirty = false
	_refresh_all()
	_set_status("Scénario enregistré ✓")

func _validate_scenario(scenario: Dictionary) -> String:
	var errors := QuestNavigation.validate_scenario_graph(scenario)
	if not errors.is_empty():
		return str(errors[0])
	return ""

func _on_back_pressed() -> void:
	GameData.go_to_scenario_list()

func _mark_dirty(status: String = "") -> void:
	_dirty = true
	_refresh_graph_health()
	if not status.is_empty():
		_set_status(status)

func _set_status(text: String) -> void:
	if _dirty and not text.begins_with("Scénario enregistré") and not text.begins_with("Erreur"):
		status_lbl.text = text + " · non sauvé"
	else:
		status_lbl.text = text
