extends RefCounted

## Inspecteur de scene de l'editeur de scenario — extrait de
## `scenario_editor.gd` (phase 3.5, composition `setup(editor)`).
##
## Responsabilites : panneau de details de la scene selectionnee (titre, tags,
## cartes liees, contenu, PNJ), chips et mode edition, CRUD des scenes (ajout,
## demarrage, suppression, duplication), ouverture/commit de l'editeur de scene
## et brouillon d'inspection. Le controleur garde des wrappers d'une ligne
## (contrat de test fige) et reste proprietaire de l'etat (`_ed._scenario`).

const QuestNavigation := preload("res://scripts/quest_navigation.gd")
const NpcRowScene := preload("res://scenes/scenario_editor/panels/npc_row.tscn")
const DETAILS_TAB_SCENE := "scene"
const DETAILS_TAB_BRANCHES := "branches"
const DETAILS_TAB_META := "meta"

## Editeur proprietaire (Control) — non type pour eviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor

func _open_scene_editor(sid: String, focus_fields: bool = false) -> void:
	if sid.is_empty():
		return
	# Ne pas reconstruire le graphe ici : ça casse le glisser-déposer au clic gauche.
	if sid != _ed._selected_scene_id:
		_ed._commit_scene_editor()
		_ed._selected_scene_id = sid
		_ed._refresh_graph_selection_styles()
	# Console 04 : cliquer un nœud ramène sur la fiche Scène de l'inspecteur.
	_ed._set_details_tab(DETAILS_TAB_SCENE)
	_ed._refresh_scene_panel()
	# Focus uniquement sur un vrai clic (pas pendant un drag), sinon le déplacement est annulé.
	if focus_fields:
		_ed.call_deferred("_focus_scene_editor_fields")

func _focus_scene_editor_fields() -> void:
	if not _ed.scene_editor.visible:
		return
	if _ed.scene_title:
		_ed.scene_title.grab_focus()
		_ed.scene_title.caret_column = _ed.scene_title.text.length()

func _refresh_scene_panel() -> void:
	# L'onglet Branches affiche une invite tant qu'aucune scène n'est sélectionnée.
	_ed.branches_hint_lbl.visible = _ed._selected_scene_id.is_empty()
	if _ed._selected_scene_id.is_empty():
		_ed.lbl_no_selection.visible = true
		_ed.scene_editor.visible = false
		_ed.scene_kicker_lbl.text = "SCÈNE — / —"
		_ed.scene_title_big.text = "Aucune scène sélectionnée"
		_ed.scene_id_chip.visible = false
		_ed._clear_chip_row(_ed.scene_tag_chips)
		_ed._clear_chip_row(_ed.scene_map_chips)
		_ed._clear_chip_row(_ed.scene_npc_chips)
		_ed.scene_npc_col.visible = false
		if _ed.scene_action_bar != null:
			_ed.scene_action_bar.visible = false
		return
	_ed.lbl_no_selection.visible = false
	_ed.scene_editor.visible = true
	if _ed.scene_action_bar != null:
		_ed.scene_action_bar.visible = _ed._details_tab == DETAILS_TAB_SCENE
	var scene = _ed._get_scene_dict(_ed._selected_scene_id)
	if scene.is_empty():
		return
	var scene_index: int = _ed._scene_index_for_id(_ed._selected_scene_id)
	var scene_total: int = _ed._scenario.get("scenes", []).size()
	var act: int = _ed._scene_act_number(scene)
	# En-tête structuré façon Atelier : « SCÈNE n / N · ACTE n » + chip d'id.
	_ed.scene_kicker_lbl.text = "SCÈNE %d / %d" % [scene_index + 1, scene_total]
	if act > 0:
		_ed.scene_kicker_lbl.text += " · ACTE %d" % act
	_ed.scene_title_big.text = str(scene.get("title", _ed._selected_scene_id))
	_ed.scene_id_chip.visible = true
	_ed.lbl_scene_id.text = _ed._selected_scene_id
	var is_start: bool = _ed._selected_scene_id == str(_ed._scenario.get("startSceneId", ""))
	var transitions: Array = scene.get("transitions", [])
	var is_terminal: bool = typeof(transitions) != TYPE_ARRAY or transitions.is_empty()
	if is_start:
		_ed.scene_badge_lbl.text = "★ Scène de départ"
		_ed.scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.GOLD)
	elif is_terminal:
		_ed.scene_badge_lbl.text = "⚑ Scène terminale"
		_ed.scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		var branch_n: int = transitions.size() if typeof(transitions) == TYPE_ARRAY else 0
		_ed.scene_badge_lbl.text = "↔ %d branche(s) sortante(s)" % branch_n
		_ed.scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	var start_btn = _ed.get_node("%BtnSetStart")
	start_btn.disabled = is_start
	start_btn.text = "★ Départ" if not is_start else "★ Scène de départ"
	_ed.scene_title.text = str(scene.get("title", ""))
	var tags: Array = scene.get("tags", [])
	if tags is Array:
		var tag_texts: PackedStringArray = []
		for tag in tags:
			tag_texts.append(str(tag))
		_ed.scene_tags.text = ", ".join(tag_texts)
		_ed._refresh_tag_chips(tags)
	else:
		_ed.scene_tags.text = ""
		_ed._clear_chip_row(_ed.scene_tag_chips)
	_ed.scene_content.text = str(scene.get("content", ""))
	_ed._refresh_scene_maps_ui(scene)
	_ed._refresh_scene_link_chips(scene)
	_ed._refresh_transitions_ui()

func _refresh_tag_chips(tags: Array) -> void:
	_ed._clear_chip_row(_ed.scene_tag_chips)
	for tag in tags:
		var text := str(tag).strip_edges()
		if text.is_empty():
			continue
		_ed.scene_tag_chips.add_child(_ed._make_chip("#%s" % text, ThemeColors.LOG_NPC))

func _refresh_scene_link_chips(scene: Dictionary) -> void:
	_ed._clear_chip_row(_ed.scene_map_chips)
	for map_id in QuestNavigation.get_scene_map_ids(scene):
		var map_data := MapData.get_by_id(str(map_id))
		var title := str(map_data.get("title", map_id)) if not map_data.is_empty() else str(map_id)
		_ed.scene_map_chips.add_child(_ed._make_chip(title, ThemeColors.INVESTIGATION_ACCENT))
	_ed._clear_chip_row(_ed.scene_npc_chips)
	var present: Array = []
	for npc_variant in _ed._scenario.get("npcs", []):
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		var scenes: Variant = npc.get("scenes", [])
		if typeof(scenes) != TYPE_ARRAY:
			continue
		for sid in scenes:
			if str(sid) == _ed._selected_scene_id:
				present.append(str(npc.get("name", npc.get("id", "PNJ"))))
				break
	for npc_name in present:
		_ed.scene_npc_chips.add_child(_ed._make_chip(npc_name, ThemeColors.LOG_NPC))
	_ed.scene_npc_col.visible = not present.is_empty()

func _clear_chip_row(row: HFlowContainer) -> void:
	if row == null:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()

func _refresh_scene_maps_ui(scene: Dictionary) -> void:
	_ed._refreshing_scene_maps = true
	_ed.scene_maps.clear()
	var roster = str(_ed._scenario.get("roster", "general"))
	var scenario_id = str(_ed._scenario.get("id", ""))
	var selected_ids := QuestNavigation.get_scene_map_ids(scene)
	var maps: Array = MapData.list_linkable_maps_for_scenario(scenario_id, roster)
	if maps.is_empty():
		_ed.scene_maps.add_item("Aucune carte disponible pour ce roster")
		_ed.scene_maps.set_item_disabled(0, true)
		_ed._refreshing_scene_maps = false
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
		var idx = _ed.scene_maps.item_count
		_ed.scene_maps.add_item("%s %s%s" % [kind, title, suffix])
		_ed.scene_maps.set_item_metadata(idx, mid)
		if selected_ids.has(mid):
			_ed.scene_maps.select(idx, false)
	_ed._refreshing_scene_maps = false

func _on_scene_maps_multi_selected(_index: int, _selected: bool) -> void:
	_ed._on_scene_maps_changed()

func _on_scene_maps_changed() -> void:
	if _ed._refreshing_scene_maps or _ed._selected_scene_id.is_empty():
		return
	_ed._commit_scene_maps_from_ui()
	_ed._mark_dirty("Cartes de scène mises à jour")

func _commit_scene_maps_from_ui() -> void:
	if _ed._selected_scene_id.is_empty() or _ed._refreshing_scene_maps:
		return
	var idx = _ed._scene_index_for_id(_ed._selected_scene_id)
	if idx < 0:
		return
	# Ne pas écraser mapIds quand la liste affiche seulement le placeholder désactivé.
	if _ed.scene_maps.item_count == 0:
		return
	if _ed.scene_maps.item_count == 1 and _ed.scene_maps.is_item_disabled(0):
		return
	var selected: Array = []
	for i in _ed.scene_maps.get_selected_items():
		var mid = str(_ed.scene_maps.get_item_metadata(i))
		if mid.is_empty():
			continue
		selected.append(mid)
		_ed._ensure_map_linked_to_scenario(mid)
	var scene: Dictionary = _ed._scenario["scenes"][idx]
	scene["mapIds"] = selected
	_ed._scenario["scenes"][idx] = scene

func _ensure_map_linked_to_scenario(map_id: String) -> void:
	var scenario_id = str(_ed._scenario.get("id", ""))
	if scenario_id.is_empty() or map_id.is_empty():
		return
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return
	if str(map_data.get("scenarioId", "")).is_empty():
		map_data["scenarioId"] = scenario_id
		MapData.update_map(map_data)

func _commit_scene_editor() -> void:
	if _ed._selected_scene_id.is_empty():
		return
	var scene = _ed._get_scene_dict(_ed._selected_scene_id)
	if scene.is_empty():
		return
	var prev_title := str(scene.get("title", ""))
	scene["title"] = _ed.scene_title.text.strip_edges()
	scene["content"] = _ed.scene_content.text.strip_edges()
	var tag_parts = _ed.scene_tags.text.split(",", false)
	var tags: Array = []
	for part in tag_parts:
		var tag := str(part).strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	scene["tags"] = tags
	_ed._commit_scene_maps_from_ui()
	if scene["title"] != prev_title:
		_ed._dirty = true

func _on_add_scene_pressed() -> void:
	_ed._commit_scene_editor()
	var scenes: Array = _ed._scenario.get("scenes", [])
	var new_id := "scene-%d" % (scenes.size() + 1)
	while _ed._scene_index_for_id(new_id) >= 0:
		new_id += "-x"
	var offset := Vector2(40 + (scenes.size() % 3) * 260, 40 + int(scenes.size() / 3) * 150)
	# Place near selected node if any
	if not _ed._selected_scene_id.is_empty():
		var selected = _ed._get_scene_dict(_ed._selected_scene_id)
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
	_ed._scenario["scenes"] = scenes
	if scenes.size() == 1:
		_ed._scenario["startSceneId"] = new_id
	# Auto-link from selected scene if it had no path to the new one
	if not _ed._selected_scene_id.is_empty() and _ed._selected_scene_id != new_id:
		var from_scene = _ed._get_scene_dict(_ed._selected_scene_id)
		var existing: Array = from_scene.get("transitions", [])
		if typeof(existing) != TYPE_ARRAY or existing.is_empty():
			_ed._add_or_update_transition(_ed._selected_scene_id, new_id, "Continuer", true, false)
	_ed._selected_scene_id = new_id
	_ed._refresh_start_scene_options()
	_ed._mark_dirty("Scène ajoutée")
	_ed._rebuild_graph()
	_ed._refresh_scene_panel()

func _on_set_start_pressed() -> void:
	if _ed._selected_scene_id.is_empty():
		return
	_ed._scenario["startSceneId"] = _ed._selected_scene_id
	_ed._refresh_start_scene_options()
	_ed._mark_dirty("Scène de départ définie")
	_ed._rebuild_graph()
	_ed._refresh_scene_panel()

func _on_delete_scene_pressed() -> void:
	if _ed._selected_scene_id.is_empty():
		return
	_ed.get_node("%ConfirmDeleteScene").dialog_text = "Supprimer la scène « %s » et ses liens ?" % _ed._selected_scene_id
	_ed.get_node("%ConfirmDeleteScene").popup_centered()

func _on_confirm_delete_scene() -> void:
	if _ed._selected_scene_id.is_empty():
		return
	var removing_id = _ed._selected_scene_id
	var scenes: Array = _ed._scenario.get("scenes", [])
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
	_ed._scenario["scenes"] = scenes
	if str(_ed._scenario.get("startSceneId", "")) == removing_id:
		if not scenes.is_empty():
			_ed._scenario["startSceneId"] = str(scenes[0].get("id", ""))
		else:
			_ed._scenario["startSceneId"] = ""
	_ed._selected_scene_id = ""
	_ed._refresh_start_scene_options()
	_ed._mark_dirty("Scène supprimée")
	_ed._rebuild_graph()
	_ed._refresh_scene_panel()

func _refresh_npc_list() -> void:
	for child in _ed.npc_list.get_children():
		child.queue_free()
	for i in range(_ed._scenario.get("npcs", []).size()):
		var npc: Dictionary = _ed._scenario["npcs"][i]
		if typeof(npc) != TYPE_DICTIONARY:
			continue
		_ed.npc_list.add_child(_ed._create_npc_row(i, npc))

func _create_npc_row(index: int, npc: Dictionary) -> PanelContainer:
	var row := NpcRowScene.instantiate()
	row.setup(npc)
	row.name_changed.connect(func(text: String):
		_ed._scenario["npcs"][index]["name"] = text
		_ed._dirty = true
	)
	row.role_changed.connect(func(text: String):
		_ed._scenario["npcs"][index]["role"] = text
		_ed._dirty = true
	)
	row.description_changed.connect(func(text: String):
		_ed._scenario["npcs"][index]["description"] = text
		_ed._dirty = true
	)
	row.delete_pressed.connect(func():
		_ed._scenario["npcs"].remove_at(index)
		_ed._dirty = true
		_ed._refresh_npc_list()
	)
	return row

func _on_add_npc_pressed() -> void:
	var npcs: Array = _ed._scenario.get("npcs", [])
	if typeof(npcs) != TYPE_ARRAY:
		npcs = []
	npcs.append({ "id": "npc-%d" % (npcs.size() + 1), "name": "Nouveau PNJ", "role": "", "description": "" })
	_ed._scenario["npcs"] = npcs
	_ed._dirty = true
	_ed._refresh_npc_list()

func _on_duplicate_scene_pressed() -> void:
	if _ed._selected_scene_id.is_empty():
		_ed._set_status("Sélectionnez une scène d'abord.")
		return
	_ed._commit_scene_editor()
	var idx = _ed._scene_index_for_id(_ed._selected_scene_id)
	if idx < 0:
		return
	var source: Dictionary = _ed._scenario["scenes"][idx]
	var copy: Dictionary = source.duplicate(true)
	var base_id := str(source.get("id", "scene"))
	var new_id := "%s-copie" % base_id
	var suffix := 2
	while _ed._scene_index_for_id(new_id) >= 0:
		new_id = "%s-copie-%d" % [base_id, suffix]
		suffix += 1
	copy["id"] = new_id
	var source_title := str(source.get("title", new_id)).strip_edges()
	if source_title.is_empty():
		source_title = base_id
	copy["title"] = "%s (copie)" % source_title
	var gp: Variant = copy.get("graphPos", {})
	var pos = _ed._scene_graph_pos(source, idx)
	if typeof(gp) == TYPE_DICTIONARY and gp.has("x") and gp.has("y"):
		pos = Vector2(float(gp["x"]), float(gp["y"]))
	copy["graphPos"] = { "x": pos.x, "y": pos.y + QuestNavigation.LAYOUT_V_GAP }
	var scenes: Array = _ed._scenario.get("scenes", [])
	scenes.append(copy)
	_ed._scenario["scenes"] = scenes
	_ed._selected_scene_id = new_id
	_ed._refresh_start_scene_options()
	_ed._mark_dirty("Scène dupliquée")
	_ed._rebuild_graph()
	_ed._refresh_scene_panel()

func _scene_title(scene_id: String) -> String:
	var scene = _ed._get_scene_dict(scene_id)
	return str(scene.get("title", scene_id))


# ---------------------------------------------------------------------------
# Notes et cadres (annotations du plan)
# ---------------------------------------------------------------------------
