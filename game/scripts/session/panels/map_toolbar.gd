extends PanelContainer
class_name MapToolbarPanel

## Barre d'outils carte. Se reconstruit à partir d'un contexte fourni ; elle
## n'interroge ni la partie ni la carte.
## Structure dans `scenes/session/panels/map_toolbar.tscn` — les boutons sont
## engendrés depuis les données (un par personnage, un par type de repère),
## donc seule la rangée existe dans la scène.

signal tool_selected(tool: Dictionary)
signal mode_selected(mode: String)
signal snap_toggled(enabled: bool)
signal trigger_requested
signal enter_requested

const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

@onready var _row: HBoxContainer = %ToolRow
@onready var _hint: Label = %LblHint

func rebuild(context: Dictionary) -> void:
	if not is_node_ready():
		await ready
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()

	if bool(context.get("readonly", false)):
		visible = false
		return
	visible = true

	var mode := str(context.get("mode", MapMode.SIMPLE))
	var is_gm := bool(context.get("is_gm", false))
	var tool: Dictionary = context.get("tool", {})

	if bool(context.get("show_mode_toggle", false)):
		_add_mode_toggle(mode)
		_add_separator()

	_add_tool(SessionToolRegistry.SELECT, SessionToolRegistry.make(SessionToolRegistry.SELECT), tool)
	if is_gm:
		_add_separator()
		_add_member_tools(context, tool)
		_add_marker_tools(context, tool)
		if MapMode.is_complex(mode) and not bool(context.get("explore_mode", false)):
			_add_separator()
			_add_gm_tools(context, tool)
		_add_separator()
		_add_tool(SessionToolRegistry.ERASE, SessionToolRegistry.make(SessionToolRegistry.ERASE), tool)
		_add_pending_enter(context)

	var pending: Dictionary = context.get("pending_nav", {})
	if not pending.is_empty():
		set_hint(str(pending.get("hint", SessionToolRegistry.hint(SessionToolRegistry.SELECT))))
	else:
		set_hint(SessionToolRegistry.hint(str(tool.get("mode", SessionToolRegistry.SELECT))))

func set_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text

# ---------------------------------------------------------------------------
# Groupes de boutons
# ---------------------------------------------------------------------------

func _add_mode_toggle(mode: String) -> void:
	for entry in [
		{ "id": MapMode.SIMPLE, "label": "Plan", "tip": "Carte tuilée d'exploration" },
		{ "id": MapMode.COMPLEX, "label": "Table", "tip": "Battlemap : tokens, brouillard, effets" },
	]:
		var btn := SessionStyle.tool_button(str(entry["label"]), str(entry["tip"]))
		btn.set_pressed_no_signal(mode == entry["id"])
		var target := str(entry["id"])
		btn.pressed.connect(func(): mode_selected.emit(target))
		_row.add_child(btn)

func _add_member_tools(context: Dictionary, current: Dictionary) -> void:
	for member_variant in context.get("party", []):
		var member: Dictionary = member_variant
		var member_id := str(member.get("id", ""))
		var member_name := str(member.get("name", "?"))
		var btn := SessionStyle.tool_button(member_name, "Placer %s sur la carte" % member_name)
		var portrait := str(member.get("portrait", member.get("image", ""))).strip_edges()
		if not portrait.is_empty():
			var cutout := MapData.load_token_cutout(portrait, 64)
			if cutout != null:
				btn.icon = cutout
				btn.expand_icon = true
		var tool := SessionToolRegistry.make(SessionToolRegistry.MEMBER, { "member_id": member_id })
		btn.set_pressed_no_signal(SessionToolRegistry.same_tool(current, tool))
		btn.pressed.connect(func(): tool_selected.emit(tool))
		_row.add_child(btn)

func _add_marker_tools(context: Dictionary, current: Dictionary) -> void:
	var types: Array = MapData.get_session_marker_types(
		str(context.get("quest_format", "oneshot")), context.get("display_map", {})
	)
	if types.is_empty():
		return
	_add_separator()
	for marker_type_variant in types:
		var marker_type := str(marker_type_variant)
		var label := MapData.get_marker_label(marker_type)
		var btn := SessionStyle.tool_button(
			"%s %s" % [MapData.get_marker_emoji(marker_type), label],
			"Poser un repère « %s »" % label
		)
		var tool := SessionToolRegistry.make(SessionToolRegistry.MARKER, { "marker_type": marker_type })
		btn.set_pressed_no_signal(SessionToolRegistry.same_tool(current, tool))
		btn.pressed.connect(func(): tool_selected.emit(tool))
		_row.add_child(btn)

func _add_gm_tools(context: Dictionary, current: Dictionary) -> void:
	for preset_id in SessionToolRegistry.EFFECT_PRESETS:
		var preset := MapEffectPresetsScript.get_preset(preset_id)
		var label := str(preset.get("label", preset_id))
		var btn := SessionStyle.tool_button(label, "Poser un effet : %s" % label)
		var tool := SessionToolRegistry.make(SessionToolRegistry.EFFECT, { "preset": preset_id })
		btn.set_pressed_no_signal(SessionToolRegistry.same_tool(current, tool))
		btn.pressed.connect(func(): tool_selected.emit(tool))
		_row.add_child(btn)

	var trigger := SessionStyle.tool_button("▶", "Déclencher les effets posés", false)
	trigger.pressed.connect(func(): trigger_requested.emit())
	_row.add_child(trigger)

	_add_tool(SessionToolRegistry.FOG, SessionToolRegistry.make(SessionToolRegistry.FOG), current)
	_add_tool(SessionToolRegistry.ZONE, SessionToolRegistry.make(SessionToolRegistry.ZONE), current)

	var snap := SessionStyle.tool_button("Grille", "Aimanter les tokens à la grille")
	snap.set_pressed_no_signal(bool(context.get("snap", true)))
	snap.toggled.connect(func(on: bool): snap_toggled.emit(on))
	_row.add_child(snap)

func _add_tool(tool_id: String, tool: Dictionary, current: Dictionary) -> void:
	var btn := SessionStyle.tool_button(
		SessionToolRegistry.glyph(tool_id), SessionToolRegistry.tooltip(tool_id)
	)
	btn.set_pressed_no_signal(SessionToolRegistry.same_tool(current, tool))
	btn.pressed.connect(func(): tool_selected.emit(tool))
	_row.add_child(btn)

func _add_pending_enter(context: Dictionary) -> void:
	var pending: Dictionary = context.get("pending_nav", {})
	var label := str(pending.get("label", "")).strip_edges()
	if label.is_empty() or not bool(pending.get("can_enter", false)):
		return
	_add_separator()
	var btn := SessionStyle.tool_button("Entrer", "Entrer dans « %s »" % label, false)
	btn.pressed.connect(func(): enter_requested.emit())
	_row.add_child(btn)

func _add_separator() -> void:
	if _row.get_child_count() == 0:
		return
	_row.add_child(VSeparator.new())
