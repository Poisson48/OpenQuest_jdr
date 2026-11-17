extends Control

## Vues de contenu de l'éditeur de scénario (refonte 04 « Console de nœuds »).
##
## Trois modes partagent le même contrôle :
##  - "scenario" : cartes des scènes (départ / fin / tags / extrait / branches) ;
##  - "npc"      : édition directe des PNJ du scénario ;
##  - "maps"     : cartes disponibles et rattachement à la scène sélectionnée.
##
## Le composant est autonome : il construit ses Controls et travaille
## directement sur le Dictionary `scenario` fourni (mêmes références). L'hôte
## (éditeur) se contente de brancher les signaux et de rappeler `refresh()`.

signal scene_selected(id: String)
signal npc_changed()
signal map_link_changed()
signal request_add_npc()
signal request_add_map_link(map_id: String)

const QuestNavigationScript := preload("res://scripts/quest_navigation.gd")

const MODE_SCENARIO := "scenario"
const MODE_NPC := "npc"
const MODE_MAPS := "maps"
const CARD_BG := Color("1a1622")

var _scenario: Dictionary = {}
var _maps_provider: Callable = Callable()
var _selected_provider: Callable = Callable()
var _mode: String = MODE_SCENARIO
var _built: bool = false
var _root: VBoxContainer = null


func setup(scenario: Dictionary, maps_provider: Callable, selected_provider: Callable) -> void:
	_scenario = scenario
	_maps_provider = maps_provider
	_selected_provider = selected_provider
	_ensure_ui()
	refresh()


func set_mode(mode: String) -> void:
	if mode != MODE_SCENARIO and mode != MODE_NPC and mode != MODE_MAPS:
		return
	_mode = mode
	_ensure_ui()
	refresh()


func refresh() -> void:
	_ensure_ui()
	_clear_root()
	match _mode:
		MODE_NPC:
			_build_npc_mode()
		MODE_MAPS:
			_build_maps_mode()
		_:
			_build_scenario_mode()


func get_mode() -> String:
	return _mode


# ---------------------------------------------------------------------------
# API de test / intégration
# ---------------------------------------------------------------------------

func get_scene_card(scene_id: String) -> Control:
	return find_child("SceneCard_" + _safe_node_name(scene_id), true, false) as Control


func get_npc_card(index: int) -> Control:
	return find_child("NpcCard_%d" % index, true, false) as Control


func get_map_card(map_id: String) -> Control:
	return find_child("MapCard_" + _safe_node_name(map_id), true, false) as Control


func get_rendered_text() -> String:
	var parts: PackedStringArray = []
	_collect_text(self, parts)
	return "\n".join(parts)


# ---------------------------------------------------------------------------
# Construction générale
# ---------------------------------------------------------------------------

func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root = VBoxContainer.new()
	_root.name = "ViewsRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)


func _clear_root() -> void:
	# `free()` immédiat (et non `queue_free`) : les tests et l'hôte peuvent
	# reconstruire plusieurs fois dans la même frame, et les anciens Controls ne
	# doivent ni rester trouvables ni fuiter. Les refresh déclenchés par un
	# signal sont donc différés par `call_deferred`.
	for child in _root.get_children():
		child.free()


func _build_scenario_mode() -> void:
	_root.add_child(_make_section_title("Scènes (%d)" % _scenes().size()))
	var scroll := _make_scroll("ScenarioScroll")
	_root.add_child(scroll)
	var list := _make_list("ScenarioList")
	scroll.add_child(list)

	var start_id := str(_scenario.get("startSceneId", ""))
	for i in range(_scenes().size()):
		var scene = _scenes()[i]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		list.add_child(_make_scene_card(scene, i, start_id))
	if list.get_child_count() == 0:
		list.add_child(_make_empty_state("Aucune scène dans ce scénario."))


func _make_scene_card(scene: Dictionary, index: int, start_id: String) -> PanelContainer:
	var sid := str(scene.get("id", "scene-%d" % index))
	var is_start := sid == start_id
	var transitions: Array = scene.get("transitions", [])
	if typeof(transitions) != TYPE_ARRAY:
		transitions = []
	var is_terminal := transitions.is_empty()
	var is_selected := sid == _selected_scene_id()

	var card := _make_card("SceneCard_" + _safe_node_name(sid),
		_card_style(is_selected))
	card.set_meta("scene_id", sid)
	card.set_meta("selected", is_selected)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_scene_card_gui_input.bind(sid))
	var body := _card_body(card)

	# En-tête : numéro + titre (★ départ / ⚑ fin).
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	var number := Label.new()
	number.name = "SceneNumber"
	number.text = "%02d" % (index + 1)
	number.theme_type_variation = &"MicroLabel"
	number.custom_minimum_size = Vector2(26, 0)
	number.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO + 2)
	number.add_theme_color_override("font_color", ThemeColors.GOLD)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(number)

	var title := Label.new()
	title.name = "SceneTitle"
	title.theme_type_variation = &"HeadingLabel"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_H3 + 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_text := str(scene.get("title", sid)).strip_edges()
	if title_text.is_empty():
		title_text = sid
	if is_start:
		title.text = "★ " + title_text
		title.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	elif is_terminal:
		title.text = "⚑ " + title_text
		title.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		title.text = title_text
	head.add_child(title)

	if is_selected:
		var marker := Label.new()
		marker.name = "SceneSelectedMarker"
		marker.text = "▸"
		marker.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		head.add_child(marker)

	# Tags en chips.
	var tags: Array = scene.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and not tags.is_empty():
		var tags_flow := HFlowContainer.new()
		tags_flow.name = "SceneTags"
		tags_flow.add_theme_constant_override("h_separation", 4)
		tags_flow.add_theme_constant_override("v_separation", 4)
		for tag in tags:
			var tag_text := str(tag).strip_edges()
			if tag_text.is_empty():
				continue
			tags_flow.add_child(_make_tag_chip("#" + tag_text, ThemeColors.GOLD))
		if tags_flow.get_child_count() > 0:
			body.add_child(tags_flow)
		else:
			tags_flow.free()

	# Extrait du contenu (2 lignes max).
	var excerpt := Label.new()
	excerpt.name = "SceneExcerpt"
	excerpt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	excerpt.max_lines_visible = 2
	excerpt.clip_text = true
	excerpt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	excerpt.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION)
	var content := str(scene.get("content", "")).strip_edges()
	if content.is_empty():
		excerpt.text = "(contenu vide)"
		excerpt.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	else:
		excerpt.text = content
		excerpt.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	body.add_child(excerpt)

	# Pied : nombre de branches + marqueurs de sémantique.
	var footer := HBoxContainer.new()
	footer.name = "SceneBranches"
	footer.add_theme_constant_override("separation", 6)
	body.add_child(footer)
	var branches := Label.new()
	branches.text = _branches_text(transitions)
	branches.theme_type_variation = &"MicroLabel"
	branches.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO)
	branches.add_theme_color_override("font_color",
		ThemeColors.SUCCESS if is_terminal else ThemeColors.GOLD)
	footer.add_child(branches)
	return card


# ---------------------------------------------------------------------------
# Mode PNJ
# ---------------------------------------------------------------------------

func _build_npc_mode() -> void:
	var header := HBoxContainer.new()
	header.name = "NpcHeader"
	header.add_theme_constant_override("separation", 8)
	header.add_child(_make_section_title("PNJ (%d)" % _npcs().size()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var add_btn := Button.new()
	add_btn.name = "BtnAddNpc"
	add_btn.text = "+ PNJ"
	add_btn.theme_type_variation = &"GhostButton"
	add_btn.pressed.connect(func(): request_add_npc.emit())
	header.add_child(add_btn)
	_root.add_child(header)

	var scroll := _make_scroll("NpcScroll")
	_root.add_child(scroll)
	var list := _make_list("NpcList")
	scroll.add_child(list)
	for i in range(_npcs().size()):
		var npc = _npcs()[i]
		if typeof(npc) != TYPE_DICTIONARY:
			continue
		list.add_child(_make_npc_card(npc, i))
	if list.get_child_count() == 0:
		list.add_child(_make_empty_state("Aucun PNJ — utilisez « + PNJ »."))


func _make_npc_card(npc: Dictionary, index: int) -> PanelContainer:
	var card := _make_card("NpcCard_%d" % index, _card_style(false))
	card.set_meta("npc_index", index)
	var body := _card_body(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)

	var name_edit := LineEdit.new()
	name_edit.name = "NpcName"
	name_edit.placeholder_text = "Nom du PNJ"
	name_edit.text = str(npc.get("name", ""))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION + 2)
	name_edit.text_changed.connect(func(text: String):
		_write_npc_field(npc, "name", str(text).strip_edges())
	)
	row.add_child(name_edit)

	var role_edit := LineEdit.new()
	role_edit.name = "NpcRole"
	role_edit.placeholder_text = "Rôle"
	role_edit.text = str(npc.get("role", ""))
	role_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_edit.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION + 2)
	role_edit.text_changed.connect(func(text: String):
		_write_npc_field(npc, "role", str(text).strip_edges())
	)
	row.add_child(role_edit)

	var desc := TextEdit.new()
	desc.name = "NpcDescription"
	desc.placeholder_text = "Description"
	desc.text = str(npc.get("description", ""))
	desc.custom_minimum_size = Vector2(0, 54)
	desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION + 1)
	desc.text_changed.connect(func():
		_write_npc_field(npc, "description", str(desc.text))
	)
	body.add_child(desc)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	body.add_child(footer)
	var scenes_lbl := Label.new()
	scenes_lbl.name = "NpcScenes"
	scenes_lbl.theme_type_variation = &"MicroLabel"
	scenes_lbl.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO)
	scenes_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	scenes_lbl.text = _npc_scenes_text(npc)
	scenes_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(scenes_lbl)

	var delete_btn := Button.new()
	delete_btn.name = "BtnDeleteNpc"
	delete_btn.text = "Supprimer"
	delete_btn.theme_type_variation = &"DangerButton"
	delete_btn.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION)
	delete_btn.pressed.connect(func(): _delete_npc_at(index))
	footer.add_child(delete_btn)
	return card


func _write_npc_field(npc: Dictionary, field: String, value: String) -> void:
	if typeof(npc) != TYPE_DICTIONARY:
		return
	npc[field] = value
	npc_changed.emit()


func _delete_npc_at(index: int) -> void:
	var npcs := _npcs()
	if index < 0 or index >= npcs.size():
		return
	npcs.remove_at(index)
	_scenario["npcs"] = npcs
	npc_changed.emit()
	call_deferred("refresh")


func _npc_scenes_text(npc: Dictionary) -> String:
	var raw: Variant = npc.get("scenes", null)
	if raw == null:
		return "Scènes : —"
	var ids: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw:
			var text := str(entry).strip_edges()
			if not text.is_empty():
				ids.append(text)
	elif typeof(raw) == TYPE_STRING:
		var text := str(raw).strip_edges()
		if not text.is_empty():
			ids = [text]
	if ids.is_empty():
		return "Scènes : —"
	return "Scènes : " + " · ".join(ids)


# ---------------------------------------------------------------------------
# Mode Cartes
# ---------------------------------------------------------------------------

func _build_maps_mode() -> void:
	var selected_scene := _selected_scene_id()
	var header := HBoxContainer.new()
	header.name = "MapsHeader"
	header.add_theme_constant_override("separation", 8)
	header.add_child(_make_section_title("Cartes"))
	var hint := Label.new()
	hint.theme_type_variation = &"MicroLabel"
	hint.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO)
	hint.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	hint.text = "scène : %s" % (selected_scene if not selected_scene.is_empty() else "aucune")
	header.add_child(hint)
	_root.add_child(header)

	var scroll := _make_scroll("MapsScroll")
	_root.add_child(scroll)
	var list := _make_list("MapsList")
	scroll.add_child(list)

	var maps: Array = []
	if _maps_provider.is_valid():
		var provided: Variant = _maps_provider.call()
		if provided is Array:
			maps = provided
	for map in maps:
		if typeof(map) != TYPE_DICTIONARY:
			continue
		list.add_child(_make_map_card(map, selected_scene))
	if list.get_child_count() == 0:
		list.add_child(_make_empty_state("Aucune carte disponible."))


func _make_map_card(map: Dictionary, selected_scene: String) -> PanelContainer:
	var map_id := str(map.get("id", ""))
	var card := _make_card("MapCard_" + _safe_node_name(map_id), _card_style(false))
	card.set_meta("map_id", map_id)
	var body := _card_body(card)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	var title := Label.new()
	title.name = "MapTitle"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_H3)
	title.text = str(map.get("title", map_id))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	var is_world := str(map.get("mapKind", "local")) == "world"
	head.add_child(_make_tag_chip("MONDE" if is_world else "LOCALE",
		ThemeColors.GOLD if is_world else ThemeColors.INVESTIGATION_ACCENT))

	# Chips des scènes déjà rattachées à cette carte.
	var linked: Array = []
	for scene in _scenes():
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var map_ids: Array = QuestNavigationScript.get_scene_map_ids(scene)
		if map_ids.has(map_id):
			linked.append(scene)
	if not linked.is_empty():
		var chips_flow := HFlowContainer.new()
		chips_flow.name = "MapSceneChips"
		chips_flow.add_theme_constant_override("h_separation", 4)
		chips_flow.add_theme_constant_override("v_separation", 4)
		for scene in linked:
			var scene_id := str(scene.get("id", ""))
			var scene_title := str(scene.get("title", scene_id)).strip_edges()
			if scene_title.is_empty():
				scene_title = scene_id
			var chip := _make_chip_button(scene_title, ThemeColors.GOLD_LIGHT)
			chip.name = "SceneChip_" + _safe_node_name(scene_id)
			chip.tooltip_text = "Voir la scène « %s »" % scene_title
			chip.set_meta("scene_id", scene_id)
			chip.pressed.connect(func(): scene_selected.emit(scene_id))
			chips_flow.add_child(chip)
		body.add_child(chips_flow)
	else:
		var none := Label.new()
		none.name = "MapNoScene"
		none.theme_type_variation = &"MutedLabel"
		none.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO + 2)
		none.text = "Aucune scène rattachée"
		body.add_child(none)

	var link_btn := Button.new()
	link_btn.name = "BtnLinkMap"
	link_btn.text = "Lier la scène sélectionnée"
	link_btn.theme_type_variation = &"GhostButton"
	link_btn.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION)
	link_btn.disabled = selected_scene.is_empty()
	if not selected_scene.is_empty():
		var already_linked := false
		for scene in linked:
			if str(scene.get("id", "")) == selected_scene:
				already_linked = true
				break
		if already_linked:
			link_btn.text = "Déjà liée à la scène"
	link_btn.pressed.connect(func(): _link_map_to_selected(map_id))
	body.add_child(link_btn)
	return card


func _link_map_to_selected(map_id: String) -> void:
	var scene_id := _selected_scene_id()
	if scene_id.is_empty():
		return
	var scene := _find_scene(scene_id)
	if scene.is_empty():
		return
	var map_ids: Array = QuestNavigationScript.get_scene_map_ids(scene)
	if not map_ids.has(map_id):
		map_ids.append(map_id)
	scene["mapIds"] = map_ids
	map_link_changed.emit()
	request_add_map_link.emit(map_id)
	call_deferred("refresh")


# ---------------------------------------------------------------------------
# Aides communes
# ---------------------------------------------------------------------------

func _scenes() -> Array:
	var scenes: Variant = _scenario.get("scenes", [])
	if typeof(scenes) != TYPE_ARRAY:
		return []
	return scenes


func _npcs() -> Array:
	var npcs: Variant = _scenario.get("npcs", [])
	if typeof(npcs) != TYPE_ARRAY:
		return []
	return npcs


func _find_scene(scene_id: String) -> Dictionary:
	for scene in _scenes():
		if typeof(scene) == TYPE_DICTIONARY and str(scene.get("id", "")) == scene_id:
			return scene
	return {}


func _selected_scene_id() -> String:
	if not _selected_provider.is_valid():
		return ""
	var value: Variant = _selected_provider.call()
	if value == null:
		return ""
	return str(value).strip_edges()


func _branches_text(transitions: Array) -> String:
	var markers: PackedStringArray = []
	for transition in transitions:
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		if bool((transition as Dictionary).get("default", false)):
			markers.append("★")
		elif bool((transition as Dictionary).get("gmOnly", false)):
			markers.append("👁")
		else:
			markers.append("→")
	var count := markers.size()
	var text := "%d branche%s" % [count, "" if count <= 1 else "s"]
	if count == 0:
		text += " · ⚑ terminal"
	else:
		text += " · " + " ".join(markers)
	return text


func _make_scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _make_list(node_name: String) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.name = node_name
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	return list


func _make_section_title(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"SectionLabel"
	label.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION)
	label.text = text
	return label


func _make_empty_state(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 96)
	label.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_CAPTION)
	label.text = text
	return label


func _make_card(node_name: String, style: StyleBoxFlat) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = node_name
	card.add_theme_stylebox_override("panel", style)
	card.mouse_default_cursor_shape = Control.CURSOR_ARROW

	var margin := MarginContainer.new()
	margin.name = "CardMargin"
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var body := VBoxContainer.new()
	body.name = "CardBody"
	body.add_theme_constant_override("separation", 5)
	margin.add_child(body)
	return card


func _card_body(card: PanelContainer) -> VBoxContainer:
	return card.get_node("CardMargin/CardBody") as VBoxContainer


func _card_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2 if selected else 1)
	style.bg_color = CARD_BG
	if selected:
		style.bg_color = CARD_BG.lightened(0.08)
		style.border_color = ThemeColors.GOLD_LIGHT
	else:
		style.border_color = ThemeColors.BORDER
	return style


func _make_tag_chip(text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.10)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"MicroLabel"
	label.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO)
	label.add_theme_color_override("font_color", accent)
	chip.add_child(label)
	return chip


func _make_chip_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.custom_minimum_size = Vector2(0, 22)
	button.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO)
	button.add_theme_color_override("font_color", accent)
	button.add_theme_color_override("font_hover_color", ThemeColors.GOLD_LIGHT)
	button.add_theme_color_override("font_pressed_color", ThemeColors.GOLD)
	button.add_theme_stylebox_override("normal", _chip_button_style(accent, 0.10, 0.35))
	button.add_theme_stylebox_override("hover", _chip_button_style(accent, 0.20, 0.55))
	button.add_theme_stylebox_override("pressed", _chip_button_style(accent, 0.26, 0.65))
	button.add_theme_stylebox_override("focus", _chip_button_style(accent, 0.16, 0.50))
	return button


func _chip_button_style(accent: Color, bg_alpha: float, border_alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, bg_alpha)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(accent.r, accent.g, accent.b, border_alpha)
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style


func _on_scene_card_gui_input(event: InputEvent, scene_id: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		scene_selected.emit(scene_id)


func _collect_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	elif node is LineEdit:
		parts.append((node as LineEdit).text)
	elif node is TextEdit:
		parts.append((node as TextEdit).text)
	for child in node.get_children():
		_collect_text(child, parts)


func _safe_node_name(text: String) -> String:
	var result := ""
	for i in range(text.length()):
		var ch := text[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \
				or (ch >= "0" and ch <= "9") or ch == "_":
			result += ch
		else:
			result += "_"
	if result.is_empty():
		result = "node"
	return result
