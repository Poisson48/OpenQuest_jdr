extends RefCounted

## Dock bas de l'editeur de scenario — extrait de `scenario_editor.gd`
## (phase 3.4, composition `setup(editor)`).
##
## Responsabilites : onglets du dock (Problemes / Historique / Journal), liste
## des problemes de graphe (collecte + rang + lignes), panneaux historique et
## journal (ajout, rendu) et validation du scenario. Les horodatages viennent de
## `Time.get_time_string_from_system()` : les captures du dock sont donc non
## deterministes par construction (deja constate phase 3.2). Le controleur garde
## des wrappers d'une ligne (contrat de test fige).

const QuestNavigation := preload("res://scripts/quest_navigation.gd")
const DOCK_TAB_ISSUES := "issues"
const DOCK_TAB_HISTORY := "history"
const DOCK_TAB_JOURNAL := "journal"

## Editeur proprietaire (Control) — non type pour eviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor

func _refresh_dock(analysis: Dictionary = {}) -> void:
	if _ed.dock_issues_list == null:
		return
	if analysis.is_empty():
		analysis = QuestNavigation.analyze_graph(_ed._scenario)
	for child in _ed.dock_issues_list.get_children():
		child.queue_free()
	_ed._graph_issues = _ed._collect_graph_issues(analysis)
	var problems := 0
	for issue in _ed._graph_issues:
		if str(issue.get("severity", "warn")) != "ok":
			problems += 1
	_ed.dock_issue_count_lbl.text = str(problems)
	_ed.dock_issue_count_lbl.add_theme_color_override("font_color",
		ThemeColors.GOLD_LIGHT if problems > 0 else ThemeColors.TEXT_MUTED)
	if _ed._graph_issues.is_empty():
		var empty := Label.new()
		empty.text = "✓ Aucun problème détecté sur ce graphe."
		empty.add_theme_color_override("font_color", ThemeColors.SUCCESS)
		_ed.dock_issues_list.add_child(empty)
		return
	for issue in _ed._graph_issues:
		_ed.dock_issues_list.add_child(_ed._create_dock_issue_row(issue))

func _collect_graph_issues(analysis: Dictionary) -> Array:
	var issues: Array = []
	var start_id = str(_ed._scenario.get("startSceneId", ""))
	if start_id.is_empty() or _ed._scene_index_for_id(start_id) < 0:
		issues.append({
			"severity": "error", "scene_id": "",
			"message": "scène de départ manquante ou invalide",
		})
	# Branches cassées (normalement impossibles après normalisation).
	for broken in analysis.get("brokenTransitions", []):
		if typeof(broken) != TYPE_DICTIONARY:
			continue
		issues.append({
			"severity": "error", "scene_id": str(broken.get("from", "")),
			"message": "branche cassée vers « %s »" % str(broken.get("to", "")),
		})
	# Accessibilité depuis la scène de départ.
	var warned: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		var sid := str(uid)
		issues.append({
			"severity": "warn", "scene_id": sid,
			"message": "scène inatteignable depuis le départ — vérifier les branches entrantes",
		})
		warned[sid] = true
	for uid in analysis.get("orphans", []):
		var sid := str(uid)
		if warned.has(sid):
			continue
		issues.append({
			"severity": "warn", "scene_id": sid,
			"message": "scène orpheline (aucune branche entrante)",
		})
		warned[sid] = true
	# Scènes terminales sans carte liée : la session resterait sur la carte précédente.
	for uid in analysis.get("terminals", []):
		var sid := str(uid)
		var scene = _ed._get_scene_dict(sid)
		if scene.is_empty():
			continue
		if QuestNavigation.get_scene_map_ids(scene).is_empty():
			issues.append({
				"severity": "warn", "scene_id": sid,
				"message": "scène terminale sans carte liée — la session restera sur la carte précédente",
			})
	# Carrefours trop chargés en branches entrantes (lisibilité du graphe).
	var incoming: Dictionary = analysis.get("incoming", {})
	for key in incoming.keys():
		var sid := str(key)
		var branch_n := int(incoming[key])
		if branch_n < 5:
			continue
		issues.append({
			"severity": "warn", "scene_id": sid,
			"message": "%d branches entrantes (lisibilité) — envisager un carrefour nommé" % branch_n,
		})
	# Branches MJ franchissant un acte : cohérence narrative à vérifier.
	for scene in _ed._scenario.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_act = _ed._scene_act_number(scene)
		if from_act <= 0:
			continue
		var from_id := str(scene.get("id", ""))
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY or not bool(transition.get("gmOnly", false)):
				continue
			var target = _ed._get_scene_dict(str(transition.get("to", "")))
			if target.is_empty():
				continue
			var to_act = _ed._scene_act_number(target)
			if to_act > from_act:
				issues.append({
					"severity": "warn", "scene_id": from_id,
					"message": "branche MJ vers l'acte %d — vérifier la cohérence avec l'acte suivant" % to_act,
				})
	# Ligne de confirmation quand le point d'entrée est sain.
	if not start_id.is_empty() and _ed._scene_index_for_id(start_id) >= 0 and bool(analysis.get("ok", false)):
		var outgoing = QuestNavigation.get_available_transitions(_ed._scenario, start_id).size()
		issues.append({
			"severity": "ok", "scene_id": start_id,
			"message": "scène de départ atteignable, %d sorties, aucune branche cassée" % outgoing,
		})
	# Déduplication puis tri erreurs → alertes → confirmations.
	var seen: Dictionary = {}
	var result: Array = []
	for issue in issues:
		var key := "%s|%s" % [str(issue.get("scene_id", "")), str(issue.get("message", ""))]
		if seen.has(key):
			continue
		seen[key] = true
		result.append(issue)
	result.sort_custom(func(a, b): return _ed._issue_rank(a) < _ed._issue_rank(b))
	return result

func _create_dock_issue_row(issue: Dictionary) -> HBoxContainer:
	var severity := str(issue.get("severity", "warn"))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var icon := Label.new()
	icon.text = "▲" if severity == "warn" else ("✖" if severity == "error" else "●")
	icon.custom_minimum_size = Vector2(16, 0)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var icon_color := ThemeColors.GOLD_LIGHT
	if severity == "error":
		icon_color = ThemeColors.DANGER
	elif severity == "ok":
		icon_color = ThemeColors.SUCCESS
	icon.add_theme_color_override("font_color", icon_color)
	row.add_child(icon)
	var scene_id := str(issue.get("scene_id", ""))
	if not scene_id.is_empty() and _ed._scene_index_for_id(scene_id) >= 0:
		var where := LinkButton.new()
		where.text = scene_id
		where.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		where.tooltip_text = "Sélectionner la scène « %s »" % scene_id
		where.focus_mode = Control.FOCUS_NONE
		where.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		where.add_theme_color_override("font_hover_color", ThemeColors.GOLD)
		where.pressed.connect(func(): _ed._select_and_focus_scene(scene_id))
		row.add_child(where)
	else:
		var where := Label.new()
		where.text = "scénario"
		where.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		row.add_child(where)
	var message := Label.new()
	message.text = str(issue.get("message", ""))
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(message)
	return row

func _issue_rank(issue: Dictionary) -> int:
	match str(issue.get("severity", "warn")):
		"error":
			return 0
		"warn":
			return 1
		_:
			return 2

func _scene_act_number(scene: Dictionary) -> int:
	var tags: Array = scene.get("tags", [])
	if typeof(tags) != TYPE_ARRAY:
		return 0
	for tag in tags:
		var text := str(tag).strip_edges().to_lower()
		for prefix in ["acte-", "act-"]:
			var prefix_text := str(prefix)
			if text.begins_with(prefix_text):
				var suffix := text.trim_prefix(prefix_text)
				if suffix.is_valid_int():
					return int(suffix)
	return 0

# ---------------------------------------------------------------------------
# Zoom (sous-barre) et onglets de détails (refonte 04)
# ---------------------------------------------------------------------------

func _on_validate_pressed() -> void:
	_ed._commit_scene_editor()
	_ed._on_meta_changed()
	var errors = QuestNavigation.validate_scenario_graph(_ed._scenario)
	var analysis = QuestNavigation.analyze_graph(_ed._scenario)
	_ed._refresh_graph_health()
	if not errors.is_empty():
		_ed._set_status("Erreur : %s" % str(errors[0]))
		return
	var warnings: Array = analysis.get("warnings", [])
	_ed._journal_add("Validation — %d erreur(s), %d avertissement(s)" % [errors.size(), warnings.size()])
	if not warnings.is_empty():
		_ed._set_status("Attention : %s" % str(warnings[0]))
	else:
		_ed._set_status("Graphe valide — %d scènes, %d branches" % [
			int(analysis.get("sceneCount", 0)),
			int(analysis.get("branchCount", 0)),
		])

func _validate_scenario(scenario: Dictionary) -> String:
	var errors := QuestNavigation.validate_scenario_graph(scenario)
	if not errors.is_empty():
		return str(errors[0])
	return ""

func _set_dock_open(open: bool) -> void:
	_ed._dock_open = open
	if _ed.dock_panel != null:
		_ed.dock_panel.visible = open
	if open:
		_ed._set_dock_tab(_ed._dock_tab)
	_ed._update_canvas_chrome()

func _toggle_dock() -> void:
	_ed._set_dock_open(not _ed._dock_open)

func _build_dock_tabs() -> void:
	_ed._dock_issues_panel = _ed.dock_issues_list
	var scroll = _ed.dock_issues_list.get_parent() as ScrollContainer
	if scroll == null:
		return
	_ed._dock_history_panel = VBoxContainer.new()
	_ed._dock_history_panel.name = "DockHistoryList"
	_ed._dock_history_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ed._dock_history_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_ed._dock_history_panel)
	_ed._dock_journal_panel = VBoxContainer.new()
	_ed._dock_journal_panel.name = "DockJournalList"
	_ed._dock_journal_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ed._dock_journal_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_ed._dock_journal_panel)
	var dock_btn_defs: Array = [
		[DOCK_TAB_ISSUES, _ed.dock_issues_btn],
		[DOCK_TAB_HISTORY, _ed.get_node("%BtnDockHistory")],
		[DOCK_TAB_JOURNAL, _ed.get_node("%BtnDockJournal")],
	]
	for entry_variant in dock_btn_defs:
		var entry: Array = entry_variant
		var btn: Button = entry[1] as Button
		if btn == null:
			continue
		var captured_tab := str(entry[0])
		_ed._dock_buttons[captured_tab] = btn
		btn.disabled = false
		btn.tooltip_text = ""
		btn.pressed.connect(func() -> void: _ed._set_dock_tab(captured_tab))
	_ed._dock_history_panel.visible = false
	_ed._dock_journal_panel.visible = false
	_ed._set_dock_tab(DOCK_TAB_ISSUES)

func _set_dock_tab(tab: String) -> void:
	if tab != DOCK_TAB_ISSUES and tab != DOCK_TAB_HISTORY and tab != DOCK_TAB_JOURNAL:
		tab = DOCK_TAB_ISSUES
	_ed._dock_tab = tab
	if _ed._dock_issues_panel != null:
		_ed._dock_issues_panel.visible = tab == DOCK_TAB_ISSUES
	if _ed._dock_history_panel != null:
		_ed._dock_history_panel.visible = tab == DOCK_TAB_HISTORY
	if _ed._dock_journal_panel != null:
		_ed._dock_journal_panel.visible = tab == DOCK_TAB_JOURNAL
	for tab_key in _ed._dock_buttons.keys():
		_ed._style_tab_button(_ed._dock_buttons[tab_key] as Button, str(tab_key) == tab)
	if tab == DOCK_TAB_HISTORY:
		_ed._render_history()
	elif tab == DOCK_TAB_JOURNAL:
		_ed._render_journal()

func _history_add(text: String) -> void:
	_ed._history_entries.append({
		"time": Time.get_time_string_from_system(),
		"text": text,
	})
	while _ed._history_entries.size() > 120:
		_ed._history_entries.pop_front()
	if _ed._dock_tab == DOCK_TAB_HISTORY and _ed._dock_history_panel != null:
		_ed._render_history()

func _journal_add(text: String) -> void:
	_ed._journal_entries.append({
		"time": Time.get_time_string_from_system(),
		"text": text,
	})
	while _ed._journal_entries.size() > 120:
		_ed._journal_entries.pop_front()
	if _ed._dock_tab == DOCK_TAB_JOURNAL and _ed._dock_journal_panel != null:
		_ed._render_journal()

func _render_history() -> void:
	if _ed._dock_history_panel == null:
		return
	for child in _ed._dock_history_panel.get_children():
		child.queue_free()
	if _ed._history_entries.is_empty():
		_ed._dock_history_panel.add_child(_ed._make_dock_label("Aucune action pour l'instant.", true))
		return
	for i in range(_ed._history_entries.size() - 1, -1, -1):
		var entry: Dictionary = _ed._history_entries[i]
		_ed._dock_history_panel.add_child(_ed._make_dock_row(str(entry.get("time", "")), str(entry.get("text", ""))))

func _render_journal() -> void:
	if _ed._dock_journal_panel == null:
		return
	for child in _ed._dock_journal_panel.get_children():
		child.queue_free()
	if _ed._journal_entries.is_empty():
		_ed._dock_journal_panel.add_child(_ed._make_dock_label("Journal vide.", true))
		return
	for i in range(_ed._journal_entries.size() - 1, -1, -1):
		var entry: Dictionary = _ed._journal_entries[i]
		_ed._dock_journal_panel.add_child(_ed._make_dock_row(str(entry.get("time", "")), str(entry.get("text", ""))))

func _make_dock_row(time_text: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var time_lbl := Label.new()
	time_lbl.text = time_text
	time_lbl.theme_type_variation = &"MicroLabel"
	time_lbl.custom_minimum_size = Vector2(72, 0)
	var msg := Label.new()
	msg.text = text
	msg.theme_type_variation = &"MutedLabel"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(time_lbl)
	row.add_child(msg)
	return row

func _make_dock_label(text: String, muted: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"MutedLabel" if muted else &"CaptionLabel"
	return lbl


# ---------------------------------------------------------------------------
# Outils (rail de la sous-barre)
# ---------------------------------------------------------------------------
