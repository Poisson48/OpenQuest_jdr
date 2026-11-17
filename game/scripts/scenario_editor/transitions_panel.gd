extends RefCounted

## Panneau des transitions de la scene selectionnee — extrait de
## `scenario_editor.gd` (phase 3.4, composition `setup(editor)`).
##
## Responsabilites : rendu de la liste des branches, cartes de transition
## (cible, libelle, defaut, MJ), options de cible, ajout/mise a jour/suppression,
## transitions par defaut et rafraichissement des styles de cables sortants.
## Le controleur garde des wrappers d'une ligne (contrat de test fige) et reste
## proprietaire de l'etat (`_ed._scenario`, `_ed._selected_scene_id`, widgets).

const QuestNavigation := preload("res://scripts/quest_navigation.gd")
const TransitionRowScene := preload("res://scenes/scenario_editor/panels/transition_row.tscn")

## Editeur proprietaire (Control) — non type pour eviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor

func _refresh_transitions_ui() -> void:
	for child in _ed.transitions_list.get_children():
		child.queue_free()
	var scene = _ed._get_scene_dict(_ed._selected_scene_id)
	if scene.is_empty():
		_ed.branches_count_lbl.text = "BRANCHES SORTANTES"
		return
	var transitions: Array = scene.get("transitions", [])
	_ed.branches_count_lbl.text = "BRANCHES SORTANTES %d" % (
		transitions.size() if typeof(transitions) == TYPE_ARRAY else 0)
	if transitions.is_empty():
		var empty := Label.new()
		empty.text = "Aucune branche — scène terminale, ou glissez un lien depuis le graphe."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_ed.transitions_list.add_child(empty)
		return
	for t_idx in range(transitions.size()):
		var transition: Dictionary = transitions[t_idx]
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		_ed.transitions_list.add_child(_ed._create_transition_row(_ed._selected_scene_id, t_idx, transition))

func _create_transition_row(from_id: String, index: int, transition: Dictionary) -> PanelContainer:
	var row := TransitionRowScene.instantiate()
	row.setup(transition)
	_ed._populate_target_options(row.get_target_option(), str(transition.get("to", "")), from_id, index)
	_ed._style_transition_row(row, transition)
	var captured_idx := index
	row.target_changed.connect(func(to_id: String):
		_ed._on_transition_target_changed(from_id, captured_idx, to_id)
	)
	row.label_changed.connect(func(text: String):
		_ed._update_transition_field(from_id, captured_idx, "label", text)
		_ed._dirty = true
	)
	row.default_toggled.connect(func(on: bool):
		if on:
			_ed._clear_default_transitions(from_id)
		_ed._update_transition_field(from_id, captured_idx, "default", on)
		_ed._mark_dirty()
		_ed._refresh_outgoing_connection_styles(from_id)
		_ed.call_deferred("_refresh_transitions_ui")
	)
	row.gm_only_toggled.connect(func(on: bool):
		_ed._update_transition_field(from_id, captured_idx, "gmOnly", on)
		_ed._mark_dirty()
		_ed._refresh_outgoing_connection_styles(from_id)
		_ed.call_deferred("_refresh_transitions_ui")
	)
	row.delete_pressed.connect(func():
		var old_to = _ed._transition_to_at(from_id, captured_idx)
		_ed._remove_transition_at(from_id, captured_idx)
		if not old_to.is_empty():
			_ed._disconnect_graph_edge(from_id, old_to)
		_ed._mark_dirty("Branche supprimée")
		_ed._refresh_graph_node_chrome(from_id)
		_ed._refresh_transitions_ui()
		_ed._refresh_scene_panel()
	)
	return row

func _populate_target_options(opt: OptionButton, selected_id: String, exclude_id: String = "", transition_index: int = -1) -> void:
	opt.clear()
	var select_idx := -1
	var added := 0
	var taken: Dictionary = {}
	if not exclude_id.is_empty():
		var scene = _ed._get_scene_dict(exclude_id)
		var transitions: Array = scene.get("transitions", [])
		for i in range(transitions.size()):
			if i == transition_index:
				continue
			if typeof(transitions[i]) == TYPE_DICTIONARY:
				var other_to := str(transitions[i].get("to", ""))
				if not other_to.is_empty():
					taken[other_to] = true
	for i in range(_ed._scenario.get("scenes", []).size()):
		var scene: Dictionary = _ed._scenario["scenes"][i]
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
		_ed._set_status("Cible de branche invalide.")
		_ed.call_deferred("_refresh_transitions_ui")
		return
	var old_to = _ed._transition_to_at(from_id, index)
	if old_to == to_id:
		return
	if _ed._has_transition(from_id, to_id):
		_ed._set_status("Cette branche existe déjà.")
		_ed.call_deferred("_refresh_transitions_ui")
		return
	_ed._update_transition_field(from_id, index, "to", to_id)
	if not old_to.is_empty():
		_ed._disconnect_graph_edge(from_id, old_to)
	var scene = _ed._get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	var tr: Dictionary = {}
	if index >= 0 and index < transitions.size() and typeof(transitions[index]) == TYPE_DICTIONARY:
		tr = transitions[index]
	_ed._connect_graph_edge(from_id, to_id, tr)
	_ed._mark_dirty("Cible de branche mise à jour")
	_ed._refresh_graph_node_chrome(from_id)

func _transition_to_at(from_id: String, index: int) -> String:
	var scene = _ed._get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index < 0 or index >= transitions.size():
		return ""
	if typeof(transitions[index]) != TYPE_DICTIONARY:
		return ""
	return str(transitions[index].get("to", ""))

func _update_transition_field(from_id: String, index: int, field: String, value: Variant) -> void:
	_ed._notify_links_changed()
	var scene = _ed._get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index < 0 or index >= transitions.size():
		return
	var copy: Dictionary = transitions[index]
	copy[field] = value
	transitions[index] = copy
	scene["transitions"] = transitions

func _clear_default_transitions(from_id: String) -> void:
	var scene = _ed._get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	for i in range(transitions.size()):
		if typeof(transitions[i]) == TYPE_DICTIONARY:
			transitions[i]["default"] = false
	scene["transitions"] = transitions

func _has_transition(from_id: String, to_id: String) -> bool:
	var scene = _ed._get_scene_dict(from_id)
	for transition in scene.get("transitions", []):
		if typeof(transition) == TYPE_DICTIONARY and str(transition.get("to", "")) == to_id:
			return true
	return false

func _add_or_update_transition(from_id: String, to_id: String, label: String, default: bool, gm_only: bool) -> void:
	_ed._notify_links_changed()
	var scene = _ed._get_scene_dict(from_id)
	if scene.is_empty() or from_id == to_id:
		return
	var transitions: Array = scene.get("transitions", [])
	for transition in transitions:
		if typeof(transition) == TYPE_DICTIONARY and str(transition.get("to", "")) == to_id:
			return
	if default:
		_ed._clear_default_transitions(from_id)
	transitions.append({ "to": to_id, "label": label, "default": default, "gmOnly": gm_only })
	scene["transitions"] = transitions

func _remove_transition(from_id: String, to_id: String) -> void:
	_ed._notify_links_changed()
	var scene = _ed._get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	for i in range(transitions.size() - 1, -1, -1):
		if typeof(transitions[i]) == TYPE_DICTIONARY and str(transitions[i].get("to", "")) == to_id:
			transitions.remove_at(i)
	scene["transitions"] = transitions

func _remove_transition_at(from_id: String, index: int) -> void:
	_ed._notify_links_changed()
	var scene = _ed._get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index >= 0 and index < transitions.size():
		transitions.remove_at(index)
	scene["transitions"] = transitions

func _on_add_transition_pressed() -> void:
	if _ed._selected_scene_id.is_empty():
		_ed._set_status("Sélectionnez une scène d'abord.")
		return
	_ed._commit_scene_editor()
	var scenes: Array = _ed._scenario.get("scenes", [])
	var target_id := ""
	for scene in scenes:
		var sid := str(scene.get("id", ""))
		if sid != _ed._selected_scene_id and not _ed._has_transition(_ed._selected_scene_id, sid):
			target_id = sid
			break
	if target_id.is_empty():
		_ed._set_status("Ajoutez une autre scène (non déjà liée) pour créer une branche.")
		return
	_ed._add_or_update_transition(_ed._selected_scene_id, target_id, "Nouvelle branche", false, false)
	_ed._connect_graph_edge(_ed._selected_scene_id, target_id, { "to": target_id, "label": "Nouvelle branche", "default": false, "gmOnly": false })
	_ed._mark_dirty("Branche ajoutée")
	_ed._refresh_graph_node_chrome(_ed._selected_scene_id)
	_ed._refresh_transitions_ui()
	_ed._refresh_scene_panel()
