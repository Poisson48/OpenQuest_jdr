extends Control

const QuestNavigation = preload("res://scripts/quest_navigation.gd")

@onready var status_lbl: Label = %LblStatus
@onready var graph_edit: GraphEdit = %GraphEdit
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
@onready var scene_content: TextEdit = %SceneContent
@onready var transitions_list: VBoxContainer = %TransitionsList

var _scenario: Dictionary = {}
var _selected_scene_id: String = ""
var _rebuilding_graph: bool = false
var _locked_roster: String = ""
var _locked_format: String = ""

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnSave.pressed.connect(_on_save_pressed)
	%BtnAddScene.pressed.connect(_on_add_scene_pressed)
	%BtnAddNpc.pressed.connect(_on_add_npc_pressed)
	%BtnSetStart.pressed.connect(_on_set_start_pressed)
	%BtnDeleteScene.pressed.connect(_on_delete_scene_pressed)
	%BtnAddTransition.pressed.connect(_on_add_transition_pressed)
	%ConfirmDeleteScene.confirmed.connect(_on_confirm_delete_scene)

	_setup_option_buttons()
	_apply_entry_context()
	_load_scenario()
	_connect_graph_signals()
	_refresh_all()

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

func _connect_graph_signals() -> void:
	graph_edit.connection_request.connect(_on_graph_connection_request)
	graph_edit.disconnection_request.connect(_on_graph_disconnection_request)
	graph_edit.node_selected.connect(_on_graph_node_selected)
	if graph_edit.has_signal("node_dragged"):
		graph_edit.node_dragged.connect(_on_graph_node_dragged)

func _refresh_all() -> void:
	_sync_meta_ui()
	_rebuild_graph()
	_refresh_npc_list()
	_refresh_scene_panel()
	_update_mystery_visibility()

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
		_set_status("Scène de départ mise à jour")

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

func _update_mystery_visibility() -> void:
	var show: bool = str(_scenario.get("roster", "")) == "investigation" or str(_scenario.get("questFormat", "")) == "investigation"
	lbl_mystery.visible = show
	meta_mystery.visible = show

func _rebuild_graph() -> void:
	call_deferred("_rebuild_graph_deferred")

func _rebuild_graph_deferred() -> void:
	_rebuilding_graph = true
	_commit_scene_editor()
	for child in graph_edit.get_children():
		if child is GraphNode:
			child.queue_free()

	var scenes: Array = _scenario.get("scenes", [])
	for i in range(scenes.size()):
		var scene: Dictionary = scenes[i]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid: String = str(scene.get("id", "scene-%d" % i))
		var node := GraphNode.new()
		node.name = _graph_node_name(i)
		node.set_meta("scene_id", sid)
		var is_start: bool = sid == str(_scenario.get("startSceneId", ""))
		node.title = ("★ " if is_start else "") + str(scene.get("title", sid))
		node.position_offset = _scene_graph_pos(scene, i)

		var body := Label.new()
		var content: String = str(scene.get("content", ""))
		if content.length() > 90:
			content = content.substr(0, 87) + "..."
		body.text = content if not content.is_empty() else "(vide)"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(180, 0)
		node.add_child(body)
		node.set_slot(0, true, 0, ThemeColors.GOLD, true, 0, ThemeColors.GOLD_LIGHT)
		graph_edit.add_child(node)

	call_deferred("_finish_graph_connections")

func _finish_graph_connections() -> void:
	var scenes: Array = _scenario.get("scenes", [])
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_name := _graph_node_name_for_id(str(scene.get("id", "")))
		if from_name.is_empty():
			continue
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_name := _graph_node_name_for_id(str(transition.get("to", "")))
			if to_name.is_empty():
				continue
			if not graph_edit.is_node_connected(from_name, 0, to_name, 0):
				graph_edit.connect_node(from_name, 0, to_name, 0)
	_rebuilding_graph = false

func _scene_graph_pos(scene: Dictionary, index: int) -> Vector2:
	var gp = scene.get("graphPos", {})
	if gp is Dictionary and gp.has("x") and gp.has("y"):
		return Vector2(float(gp["x"]), float(gp["y"]))
	var col := index % 3
	var row := int(index / 3)
	return Vector2(40.0 + col * 260.0, 40.0 + row * 150.0)

func _graph_node_name(index: int) -> String:
	return "SceneNode_%d" % index

func _graph_node_name_for_id(scene_id: String) -> StringName:
	var scenes: Array = _scenario.get("scenes", [])
	for i in range(scenes.size()):
		if str(scenes[i].get("id", "")) == scene_id:
			return StringName(_graph_node_name(i))
	return StringName("")

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
	graph_edit.connect_node(from_node, from_port, to_node, to_port)
	var from_id := _scene_id_from_graph_node(from_node)
	var to_id := _scene_id_from_graph_node(to_node)
	if from_id.is_empty() or to_id.is_empty():
		return
	_add_or_update_transition(from_id, to_id, "Nouvelle branche", false, false)
	if _selected_scene_id == from_id:
		_refresh_transitions_ui()

func _on_graph_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding_graph:
		return
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	var from_id := _scene_id_from_graph_node(from_node)
	var to_id := _scene_id_from_graph_node(to_node)
	_remove_transition(from_id, to_id)
	if _selected_scene_id == from_id:
		_refresh_transitions_ui()

func _scene_id_from_graph_node(node_name: StringName) -> String:
	for child in graph_edit.get_children():
		if child is GraphNode and child.name == node_name:
			return str(child.get_meta("scene_id", ""))
	return ""

func _on_graph_node_selected(node: Node) -> void:
	if node is GraphNode:
		_commit_scene_editor()
		_selected_scene_id = str(node.get_meta("scene_id", ""))
		_refresh_scene_panel()

func _on_graph_node_dragged(node: Node) -> void:
	if not node is GraphNode:
		return
	var sid := str(node.get_meta("scene_id", ""))
	var scene := _get_scene_dict(sid)
	if scene.is_empty():
		return
	scene["graphPos"] = { "x": node.position_offset.x, "y": node.position_offset.y }

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
	_refresh_transitions_ui()

func _commit_scene_editor() -> void:
	if _selected_scene_id.is_empty():
		return
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	scene["title"] = scene_title.text.strip_edges()
	scene["content"] = scene_content.text.strip_edges()
	var tag_parts := scene_tags.text.split(",", false)
	var tags: Array = []
	for part in tag_parts:
		var tag := str(part).strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	scene["tags"] = tags

func _refresh_transitions_ui() -> void:
	for child in transitions_list.get_children():
		child.queue_free()
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	var transitions: Array = scene.get("transitions", [])
	for t_idx in range(transitions.size()):
		var transition: Dictionary = transitions[t_idx]
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		transitions_list.add_child(_create_transition_row(_selected_scene_id, t_idx, transition))

func _create_transition_row(from_id: String, index: int, transition: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var top := HBoxContainer.new()
	var target_opt := OptionButton.new()
	target_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_target_options(target_opt, str(transition.get("to", "")))
	var captured_idx := index
	target_opt.item_selected.connect(func(_i):
		_update_transition_field(from_id, captured_idx, "to", str(target_opt.get_item_metadata(target_opt.selected)))
		call_deferred("_rebuild_graph")
	)
	top.add_child(target_opt)
	row.add_child(top)

	var label_edit := LineEdit.new()
	label_edit.placeholder_text = "Libellé de la branche"
	label_edit.text = str(transition.get("label", ""))
	label_edit.text_changed.connect(func(t):
		_update_transition_field(from_id, captured_idx, "label", t.strip_edges())
	)
	row.add_child(label_edit)

	var flags := HBoxContainer.new()
	var chk_default := CheckBox.new()
	chk_default.text = "Défaut ★"
	chk_default.button_pressed = transition.get("default", false)
	chk_default.toggled.connect(func(v):
		if v:
			_clear_default_transitions(from_id)
		_update_transition_field(from_id, captured_idx, "default", v)
		call_deferred("_rebuild_graph")
	)
	var chk_gm := CheckBox.new()
	chk_gm.text = "MJ seul"
	chk_gm.button_pressed = transition.get("gmOnly", false)
	chk_gm.toggled.connect(func(v): _update_transition_field(from_id, captured_idx, "gmOnly", v))
	var btn_del := Button.new()
	btn_del.text = "✕"
	btn_del.pressed.connect(func():
		_remove_transition_at(from_id, captured_idx)
		_refresh_transitions_ui()
		call_deferred("_rebuild_graph")
	)
	flags.add_child(chk_default)
	flags.add_child(chk_gm)
	flags.add_child(btn_del)
	row.add_child(flags)

	panel.add_child(row)
	return panel

func _populate_target_options(opt: OptionButton, selected_id: String) -> void:
	opt.clear()
	var select_idx := 0
	for i in range(_scenario.get("scenes", []).size()):
		var scene: Dictionary = _scenario["scenes"][i]
		var sid := str(scene.get("id", ""))
		opt.add_item("%s" % scene.get("title", sid), i)
		opt.set_item_metadata(i, sid)
		if sid == selected_id:
			select_idx = i
	if opt.item_count > 0:
		opt.select(select_idx)

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
		if sid != _selected_scene_id:
			target_id = sid
			break
	if target_id.is_empty():
		_set_status("Ajoutez une autre scène pour créer une branche.")
		return
	_add_or_update_transition(_selected_scene_id, target_id, "Nouvelle branche", false, false)
	_refresh_transitions_ui()
	_rebuild_graph()

func _on_add_scene_pressed() -> void:
	_commit_scene_editor()
	var scenes: Array = _scenario.get("scenes", [])
	var new_id := "scene-%d" % (scenes.size() + 1)
	while _scene_index_for_id(new_id) >= 0:
		new_id += "-x"
	var new_scene := {
		"id": new_id,
		"title": "Nouvelle scène %d" % (scenes.size() + 1),
		"content": "",
		"tags": [],
		"transitions": [],
		"graphPos": { "x": 40 + (scenes.size() % 3) * 260, "y": 40 + int(scenes.size() / 3) * 150 },
	}
	scenes.append(new_scene)
	_scenario["scenes"] = scenes
	if scenes.size() == 1:
		_scenario["startSceneId"] = new_id
	_selected_scene_id = new_id
	_refresh_start_scene_options()
	_rebuild_graph()
	_refresh_scene_panel()
	_set_status("Scène ajoutée")

func _on_set_start_pressed() -> void:
	if _selected_scene_id.is_empty():
		return
	_scenario["startSceneId"] = _selected_scene_id
	_refresh_start_scene_options()
	_rebuild_graph()
	_set_status("Scène de départ définie")

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
	_rebuild_graph()
	_refresh_scene_panel()
	_set_status("Scène supprimée")

func _refresh_npc_list() -> void:
	for child in npc_list.get_children():
		child.queue_free()
	for i in range(_scenario.get("npcs", []).size()):
		var npc: Dictionary = _scenario["npcs"][i]
		if typeof(npc) != TYPE_DICTIONARY:
			continue
		npc_list.add_child(_create_npc_row(i, npc))

func _create_npc_row(index: int, npc: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Nom du PNJ"
	name_edit.text = str(npc.get("name", ""))
	name_edit.text_changed.connect(func(t): _scenario["npcs"][index]["name"] = t.strip_edges())
	var role_edit := LineEdit.new()
	role_edit.placeholder_text = "Rôle"
	role_edit.text = str(npc.get("role", ""))
	role_edit.text_changed.connect(func(t): _scenario["npcs"][index]["role"] = t.strip_edges())
	var desc_edit := TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 48)
	desc_edit.placeholder_text = "Description"
	desc_edit.text = str(npc.get("description", ""))
	desc_edit.text_changed.connect(func(): _scenario["npcs"][index]["description"] = desc_edit.text.strip_edges())
	var btn_del := Button.new()
	btn_del.text = "Supprimer PNJ"
	btn_del.pressed.connect(func():
		_scenario["npcs"].remove_at(index)
		_refresh_npc_list()
	)
	vbox.add_child(name_edit)
	vbox.add_child(role_edit)
	vbox.add_child(desc_edit)
	vbox.add_child(btn_del)
	panel.add_child(vbox)
	return panel

func _on_add_npc_pressed() -> void:
	var npcs: Array = _scenario.get("npcs", [])
	if typeof(npcs) != TYPE_ARRAY:
		npcs = []
	npcs.append({ "id": "npc-%d" % (npcs.size() + 1), "name": "Nouveau PNJ", "role": "", "description": "" })
	_scenario["npcs"] = npcs
	_refresh_npc_list()

func _on_save_pressed() -> void:
	_commit_scene_editor()
	_on_meta_changed()
	var normalized := QuestNavigation.normalize_scenario(_scenario.duplicate(true))
	var error := _validate_scenario(normalized)
	if not error.is_empty():
		_set_status("Erreur : %s" % error)
		return
	GameData.save_scenario(normalized)
	_scenario = normalized.duplicate(true)
	_refresh_all()
	_set_status("Scénario enregistré ✓")

func _validate_scenario(scenario: Dictionary) -> String:
	if str(scenario.get("title", "")).strip_edges().is_empty():
		return "Le titre est obligatoire."
	var scenes: Array = scenario.get("scenes", [])
	if scenes.is_empty():
		return "Ajoutez au moins une scène."
	var start_id := str(scenario.get("startSceneId", ""))
	if start_id.is_empty():
		return "Définissez une scène de départ."
	if QuestNavigation.get_scene_by_id(scenario, start_id).is_empty():
		return "La scène de départ est invalide."
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", ""))
			if QuestNavigation.get_scene_by_id(scenario, to_id).is_empty():
				return "Branche invalide vers « %s »." % to_id
	return ""

func _on_back_pressed() -> void:
	GameData.go_to_scenario_list()

func _set_status(text: String) -> void:
	status_lbl.text = text
