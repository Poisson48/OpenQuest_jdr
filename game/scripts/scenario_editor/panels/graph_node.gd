extends GraphNode

## Nœud de scène du graphe. Structure dans `graph_node.tscn`.
## Les teintes de bordure restent data-driven (début / fin / sélection).

signal context_requested(scene_id: String, screen_pos: Vector2)
signal scene_activated(scene_id: String)
signal scene_focus_requested(scene_id: String)

const QuestNavigationScript := preload("res://scripts/quest_navigation.gd")
const MIN_SIZE := Vector2(160, 90)
const MAX_SIZE := Vector2(520, 420)
const CLICK_DRAG_THRESHOLD_PX := 6.0

var _left_pressing: bool = false
var _left_press_global: Vector2 = Vector2.ZERO

func _ready() -> void:
	resizable = true
	draggable = true
	selectable = true
	_ignore_mouse_on_content()

func _ignore_mouse_on_content() -> void:
	# Uniquement le contenu métier — ne pas toucher aux enfants internes du GraphNode
	# (poignée de drag / resize), sinon les scènes ne sont plus déplaçables.
	var body := get_node_or_null("Body")
	if body is Control:
		_set_mouse_ignore_recursive(body as Control)

func _set_mouse_ignore_recursive(ctrl: Control) -> void:
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in ctrl.get_children():
		if child is Control:
			_set_mouse_ignore_recursive(child as Control)

func _gui_input(event: InputEvent) -> void:
	var sid := str(get_meta("scene_id", ""))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		context_requested.emit(sid, get_global_mouse_position())
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_pressing = true
			_left_press_global = event.global_position
			# Sélection / panneau sans voler le focus (sinon le drag GraphEdit est annulé).
			scene_activated.emit(sid)
		else:
			if _left_pressing and event.global_position.distance_to(_left_press_global) <= CLICK_DRAG_THRESHOLD_PX:
				scene_focus_requested.emit(sid)
			_left_pressing = false
		# Ne pas accept_event : laisse GraphEdit démarrer le déplacement du nœud.

func setup(scene: Dictionary, sid: String, index: int, is_unreachable: bool, start_id: String, selected_id: String) -> void:
	if not is_node_ready():
		await ready
	# Le nom stable (par id de scène) est posé par l'éditeur ; ne pas l'écraser par l'index.
	set_meta("scene_id", sid)
	set_meta("is_unreachable", is_unreachable)
	set_meta("is_start", sid == start_id)
	draggable = true
	resizable = true
	selectable = true
	_apply_size_from_scene(scene)
	refresh_chrome(scene, sid, is_unreachable, start_id, selected_id)

func refresh_chrome(scene: Dictionary, sid: String, is_unreachable: bool, start_id: String, selected_id: String) -> void:
	var is_start: bool = sid == start_id
	var transitions: Array = scene.get("transitions", [])
	if typeof(transitions) != TYPE_ARRAY:
		transitions = []
	var is_terminal: bool = transitions.is_empty()
	var is_selected: bool = sid == selected_id
	set_meta("is_unreachable", is_unreachable)
	set_meta("is_start", is_start)

	var title := str(scene.get("title", sid))
	if is_start:
		title = "★ " + title
	elif is_terminal:
		title = "⚑ " + title
	self.title = title
	_apply_panel_style(is_selected, is_start, is_unreachable, is_terminal)

	var tags: Array = scene.get("tags", [])
	var tags_lbl: Label = %LblTags
	if tags is Array and not tags.is_empty():
		var tag_parts: PackedStringArray = []
		for tag in tags:
			tag_parts.append("#%s" % str(tag))
		tags_lbl.text = " ".join(tag_parts)
		tags_lbl.visible = true
	else:
		tags_lbl.visible = false

	var content: String = str(scene.get("content", "")).strip_edges()
	var preview: Label = %LblPreview
	if content.is_empty():
		preview.text = "(contenu vide)"
		preview.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	else:
		preview.text = content if content.length() <= 160 else content.substr(0, 157) + "…"
		preview.add_theme_color_override("font_color", ThemeColors.TEXT)

	var branches: Label = %LblBranches
	if is_terminal:
		branches.text = "⚑ Fin de branche"
		branches.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		var lines: PackedStringArray = []
		for transition in transitions:
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var mark := "★" if transition.get("default", false) else ("👁" if transition.get("gmOnly", false) else "→")
			var label := str(transition.get("label", "Branche")).strip_edges()
			if label.is_empty():
				label = str(transition.get("to", "?"))
			if label.length() > 36:
				label = label.substr(0, 33) + "…"
			lines.append("%s %s" % [mark, label])
		branches.text = "\n".join(lines)
		branches.add_theme_color_override("font_color", ThemeColors.GOLD)

	%LblWarn.visible = is_unreachable and not is_start

	var slot_color := ThemeColors.GOLD if is_start else (ThemeColors.SUCCESS if is_terminal else ThemeColors.GOLD_LIGHT)
	set_slot(0, true, 0, slot_color, true, 0, slot_color)

func set_selected_visual(is_selected: bool) -> void:
	var is_start := bool(get_meta("is_start", false))
	var is_unreachable := bool(get_meta("is_unreachable", false))
	var is_terminal: bool = str(%LblBranches.text).begins_with("⚑")
	_apply_panel_style(is_selected, is_start, is_unreachable, is_terminal)

func apply_size(sz: Vector2) -> Vector2:
	var clamped := _clamp_size(sz)
	custom_minimum_size = clamped
	size = clamped
	set_meta("graph_size", clamped)
	var preview: Label = %LblPreview
	preview.custom_minimum_size = Vector2(maxf(clamped.x - 30.0, 120.0), 0)
	# Re-applique après le layout Godot, qui peut sinon rétablir la taille auto.
	if not is_inside_tree():
		return clamped
	var token := int(get_meta("graph_size_token", 0)) + 1
	set_meta("graph_size_token", token)
	call_deferred("_reapply_size_deferred", clamped, token)
	return clamped

func _reapply_size_deferred(sz: Vector2, token: int) -> void:
	if not is_instance_valid(self) or int(get_meta("graph_size_token", 0)) != token:
		return
	custom_minimum_size = sz
	size = sz

func _apply_size_from_scene(scene: Dictionary) -> void:
	var gs = scene.get("graphSize", {})
	if typeof(gs) == TYPE_DICTIONARY and gs.has("w") and gs.has("h"):
		apply_size(Vector2(float(gs["w"]), float(gs["h"])))
	else:
		custom_minimum_size = Vector2(QuestNavigationScript.NODE_WIDTH, 0)
		if has_meta("graph_size"):
			remove_meta("graph_size")
		var preview: Label = %LblPreview
		preview.custom_minimum_size = Vector2(190, 0)

func _clamp_size(sz: Vector2) -> Vector2:
	return Vector2(
		clampf(sz.x, MIN_SIZE.x, MAX_SIZE.x),
		clampf(sz.y, MIN_SIZE.y, MAX_SIZE.y)
	)

func _apply_panel_style(is_selected: bool, is_start: bool, is_unreachable: bool, is_terminal: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.set_border_width_all(2)
	if is_selected:
		style.border_color = ThemeColors.GOLD_LIGHT
		style.bg_color = Color(ThemeColors.BG_CARD.r, ThemeColors.BG_CARD.g, ThemeColors.BG_CARD.b, 1.0).lightened(0.08)
	elif is_start:
		style.border_color = ThemeColors.GOLD
	elif is_unreachable:
		style.border_color = ThemeColors.DANGER
	elif is_terminal:
		style.border_color = ThemeColors.SUCCESS
	else:
		style.border_color = ThemeColors.BORDER
	add_theme_stylebox_override("panel", style)
	add_theme_stylebox_override("panel_selected", style)
	add_theme_color_override("title_color", ThemeColors.GOLD_LIGHT if is_start else ThemeColors.TEXT)
