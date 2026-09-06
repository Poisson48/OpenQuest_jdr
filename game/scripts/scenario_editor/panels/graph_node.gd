extends GraphNode

## Nœud de scène du graphe. Structure dans `graph_node.tscn`.
## Les teintes de bordure restent data-driven (début / fin / sélection).

const QuestNavigationScript := preload("res://scripts/quest_navigation.gd")

func setup(scene: Dictionary, sid: String, index: int, is_unreachable: bool, start_id: String, selected_id: String) -> void:
	if not is_node_ready():
		await ready
	name = "SceneNode_%d" % index
	set_meta("scene_id", sid)
	var is_start: bool = sid == start_id
	var transitions: Array = scene.get("transitions", [])
	if typeof(transitions) != TYPE_ARRAY:
		transitions = []
	var is_terminal: bool = transitions.is_empty()
	var is_selected: bool = sid == selected_id

	var title := str(scene.get("title", sid))
	if is_start:
		title = "★ " + title
	elif is_terminal:
		title = "⚑ " + title
	self.title = title
	custom_minimum_size = Vector2(QuestNavigationScript.NODE_WIDTH, 0)

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
		preview.text = content if content.length() <= 100 else content.substr(0, 97) + "…"
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
			if label.length() > 28:
				label = label.substr(0, 25) + "…"
			lines.append("%s %s" % [mark, label])
		branches.text = "\n".join(lines)
		branches.add_theme_color_override("font_color", ThemeColors.GOLD)

	%LblWarn.visible = is_unreachable and not is_start

	var slot_color := ThemeColors.GOLD if is_start else (ThemeColors.SUCCESS if is_terminal else ThemeColors.GOLD_LIGHT)
	set_slot(0, true, 0, slot_color, true, 0, slot_color)
