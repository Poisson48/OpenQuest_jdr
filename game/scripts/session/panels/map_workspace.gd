extends VBoxContainer
class_name MapWorkspacePanel

## Assemble la zone carte : navigateur (haut), scène (centre), outils (bas).
## Structure dans `scenes/session/panels/map_workspace.tscn`.
##
## Seul endroit de la session qui parle « carte » à GameData : les trois
## panneaux enfants restent muets sur l'état de jeu.

signal speaker_focus_requested(npc_name: String)

@onready var navigator: MapNavigatorPanel = %MapNavigator
@onready var stage: MapStagePanel = %MapStage
@onready var toolbar: MapToolbarPanel = %MapToolbar
@onready var _empty_state: PanelContainer = %EmptyState

var _active_map_id: String = ""
var _tool: Dictionary = {}
var _mode: String = MapMode.SIMPLE
var _explore_mode: bool = false
var _readonly: bool = false
var _player_preview: bool = false
var _snap: bool = true
var _is_gm: bool = false
var _gm_view: bool = true
var _immersive: bool = false
var _pending_nav: Dictionary = {}
var _inspect_hint: String = ""

func _ready() -> void:
	navigator.map_selected.connect(_on_map_selected)
	navigator.exit_area_requested.connect(func(): GameData.exit_area(); refresh())
	navigator.exit_to_world_requested.connect(func(): GameData.exit_to_world_map(); refresh())
	navigator.zoom_in_requested.connect(func(): stage.zoom_in())
	navigator.zoom_out_requested.connect(func(): stage.zoom_out())
	navigator.fit_requested.connect(func(): stage.fit())

	stage.cell_clicked.connect(_on_cell_clicked)
	stage.grid_clicked.connect(_on_grid_clicked)
	stage.token_moved.connect(_on_token_moved)
	if stage.has_signal("prop_moved"):
		stage.prop_moved.connect(_on_prop_moved)
	stage.fog_revealed.connect(_on_fog_revealed)
	stage.fog_hidden.connect(_on_fog_hidden)
	stage.token_selected.connect(_on_token_selected)
	stage.effect_trigger_requested.connect(_on_effect_triggered)
	stage.area_clicked.connect(_on_area_clicked)
	stage.area_hovered.connect(_on_area_hovered)
	stage.inspect_requested.connect(_on_inspect_requested)
	if stage.has_signal("area_activate_requested"):
		stage.area_activate_requested.connect(_on_area_activate_requested)
	stage.navigation_requested.connect(_on_navigation_requested)
	stage.view_changed.connect(_sync_scale)

	toolbar.tool_selected.connect(_on_tool_selected)
	toolbar.mode_selected.connect(_on_mode_selected)
	toolbar.snap_toggled.connect(_on_snap_toggled)
	toolbar.trigger_requested.connect(_on_trigger_effects)
	if toolbar.has_signal("enter_requested"):
		toolbar.enter_requested.connect(_on_enter_requested)

	%BtnEmptyHub.pressed.connect(_on_empty_hub_pressed)
	%BtnEmptyMaps.pressed.connect(_on_empty_maps_pressed)

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func set_immersive(on: bool) -> void:
	if not is_node_ready():
		await ready
	_immersive = on
	_apply_chrome_visibility()
	stage.set_immersive(on)

## Le porteur du rôle décide qui voit le caché : `GameData.is_gm_view_for_map`
## ignore la vue joueur forcée, on ne peut donc pas s'y fier seul.
func set_gm_view(on: bool) -> void:
	if _gm_view == on:
		return
	_gm_view = on
	refresh()

## Aperçu MJ de la vue joueur : la carte est filtrée comme pour un joueur.
func set_player_preview(on: bool) -> void:
	if _player_preview == on:
		return
	_player_preview = on
	refresh()

func refresh() -> void:
	if not is_node_ready():
		await ready
	var state: Dictionary = GameData.active_game
	var map_ids: Array = state.get("mapIds", [])
	visible = true
	if map_ids.is_empty():
		_show_empty_state(true)
		return

	_show_empty_state(false)
	_readonly = str(state.get("status", "")) == "completed"
	var active_id := _resolve_active_map_id(map_ids)
	var ctx := GameData.get_session_display_map(active_id)
	var display_map: Dictionary = ctx.get("displayMap", {})
	if display_map.is_empty():
		_show_empty_state(true)
		return
	var map_id := str(display_map.get("id", ""))

	_explore_mode = not str(display_map.get("backgroundImage", "")).strip_edges().is_empty()
	_mode = MapMode.COMPLEX if _explore_mode else GameData.get_effective_render_mode(active_id)
	_is_gm = _gm_view and GameData.is_gm_view_for_map(map_id) and not _player_preview
	if _tool.is_empty() or (not _is_gm and SessionToolRegistry.is_place_tool(_tool)):
		_tool = SessionToolRegistry.default_tool()

	_render_navigator(ctx, map_ids, active_id)
	_render_toolbar(state, display_map)
	_configure_stage(state, ctx, map_id)
	_apply_chrome_visibility()

func _show_empty_state(on: bool) -> void:
	if _empty_state:
		_empty_state.visible = on
	navigator.visible = not on and not _immersive
	stage.visible = not on
	toolbar.visible = not on and not _immersive

func _on_empty_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

func _on_empty_maps_pressed() -> void:
	get_tree().set_meta("hub_tab", "Cartes")
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

## La barre d'outils se rend visible en se reconstruisant : en vue immersive on
## la remasque après coup, sinon la carte perdrait sa pleine page au premier
## rafraîchissement.
func _apply_chrome_visibility() -> void:
	if _empty_state and _empty_state.visible:
		return
	if _immersive:
		navigator.visible = false
		toolbar.visible = false
	else:
		navigator.visible = true
		toolbar.visible = true

## Décrit l'état carte — utilisé par les tests de mise en page.
func describe() -> Dictionary:
	return {
		"map_id": _active_map_id,
		"mode": _mode,
		"is_gm": _is_gm,
		"tool": _tool.get("mode", ""),
		"pending_nav": _pending_nav.duplicate(true),
		"scale": stage.get_effective_scale() if stage else 0.0,
		"stage_size": stage.size if stage else Vector2.ZERO,
		"chrome_visible": navigator.visible if navigator else false,
		"speech_bubbles": stage.speech_bubble_count() if stage else 0,
	}

func show_npc_speech(speaker: String, text: String) -> void:
	if stage == null:
		return
	var grid := GameData.find_speaker_grid(speaker)
	stage.show_speech(speaker, text, grid)

# ---------------------------------------------------------------------------
# Rendu
# ---------------------------------------------------------------------------

func _render_navigator(ctx: Dictionary, map_ids: Array, active_id: String) -> void:
	var tabs: Array = []
	if not _explore_mode:
		for map_id_variant in map_ids:
			var entry := MapData.get_by_id(str(map_id_variant))
			if entry.is_empty() or not str(entry.get("parentMapId", "")).is_empty():
				continue
			tabs.append({ "id": str(entry.get("id", "")), "title": str(entry.get("title", "Carte")) })
	navigator.set_tabs(tabs, active_id)
	var nav_ctx: Dictionary = ctx.get("navContext", {}).duplicate(true)
	nav_ctx["title"] = str(ctx.get("displayMap", {}).get("title", "Carte"))
	navigator.set_breadcrumb(nav_ctx)

func _render_toolbar(state: Dictionary, display_map: Dictionary) -> void:
	toolbar.rebuild({
		"mode": _mode,
		"is_gm": _is_gm,
		"readonly": _readonly,
		"explore_mode": _explore_mode,
		"party": state.get("party", []),
		"quest_format": str(state.get("questFormat", "oneshot")),
		"display_map": display_map,
		"tool": _tool,
		"snap": _snap,
		"show_mode_toggle": _is_gm and not _explore_mode,
		"pending_nav": _pending_nav,
	})

func _configure_stage(state: Dictionary, ctx: Dictionary, map_id: String) -> void:
	var payload := {
		"map": ctx.get("displayMap", {}),
		"mode": _mode,
		"party": state.get("party", []),
		"readonly": _readonly,
		"is_gm": _is_gm,
		"quest_format": str(state.get("questFormat", "oneshot")),
		"nav_context": ctx.get("navContext", {}),
		"owned_member_id": _owned_member_id(),
	}
	if MapMode.is_complex(_mode):
		var view: Dictionary = GameData.filter_map_entry_for_player(map_id, _is_gm)
		payload["tokens"] = view.get("tokens", [])
		payload["effects"] = view.get("effects", [])
		payload["zones"] = view.get("zones", [])
		payload["fog_revealed"] = view.get("fogRevealed", [])
		payload["view_state"] = GameData.get_map_view_state(map_id)
		payload["selected_token"] = GameData.get_selected_token_id(map_id)
		payload["tool"] = SessionToolRegistry.to_complex_tool(_tool)
	else:
		payload["tokens"] = GameData.get_map_play_tokens(map_id)
		payload["explored"] = GameData.get_explored_cells(map_id)
		payload["revealed_markers"] = GameData.get_revealed_markers(map_id)
		payload["revealed_links"] = GameData.get_revealed_links(map_id)
		payload["suppressed_markers"] = GameData.get_suppressed_marker_keys(map_id)
		payload["suppressed_areas"] = GameData.get_suppressed_area_ids(map_id)
		payload["suppressed_links"] = GameData.get_suppressed_link_keys(map_id)
		payload["suppressed_props"] = GameData.get_suppressed_prop_ids(map_id)
		payload["selected_token"] = GameData.get_selected_token_id(map_id)
		payload["tool"] = SessionToolRegistry.to_simple_tool(_tool)
	stage.configure(payload)
	_sync_scale()

func _sync_scale() -> void:
	navigator.set_effective_scale(stage.get_effective_scale())

func _resolve_active_map_id(map_ids: Array) -> String:
	var play_id := GameData.get_active_play_map_id()
	if not play_id.is_empty() and map_ids.has(play_id):
		_active_map_id = play_id
		return play_id
	if not _active_map_id.is_empty() and map_ids.has(_active_map_id):
		if str(MapData.get_by_id(_active_map_id).get("parentMapId", "")).is_empty():
			return _active_map_id
	for map_id_variant in map_ids:
		var entry := MapData.get_by_id(str(map_id_variant))
		if not entry.is_empty() and str(entry.get("parentMapId", "")).is_empty():
			_active_map_id = str(map_id_variant)
			return _active_map_id
	_active_map_id = str(map_ids[0])
	return _active_map_id

func _current_map_id() -> String:
	return str(GameData.get_session_display_map(_active_map_id).get("displayMap", {}).get("id", ""))

# ---------------------------------------------------------------------------
# Interactions
# ---------------------------------------------------------------------------

func _on_map_selected(map_id: String) -> void:
	_active_map_id = map_id
	refresh()

func _on_tool_selected(tool: Dictionary) -> void:
	_tool = tool
	refresh()

func _on_mode_selected(mode: String) -> void:
	if mode == _mode or _active_map_id.is_empty():
		return
	GameData.set_map_render_mode_override(_active_map_id, mode)
	refresh()

func _on_snap_toggled(enabled: bool) -> void:
	_snap = enabled
	stage.set_snap_to_grid(enabled)

func _owned_member_id() -> String:
	if _is_gm:
		return ""
	if MultiplayerManager.is_p2p_active():
		return str(MultiplayerManager.get_my_party_member(GameData.active_game).get("id", ""))
	for member_variant in GameData.active_game.get("party", []):
		if typeof(member_variant) != TYPE_DICTIONARY:
			continue
		var member: Dictionary = member_variant
		if bool(member.get("isPlayer", false)) or bool(member.get("isHuman", false)):
			return str(member.get("id", ""))
	return ""

func _on_cell_clicked(x: int, y: int) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty() or not SessionToolRegistry.is_place_tool(_tool):
		return
	GameData.apply_map_play_action(map_id, x, y, SessionToolRegistry.to_simple_tool(_tool))
	refresh()

func _on_grid_clicked(gx: float, gy: float, tool: Dictionary) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty() or not SessionToolRegistry.is_place_tool(tool if not tool.is_empty() else _tool):
		return
	GameData.apply_complex_map_click(map_id, gx, gy, tool)
	refresh()

func _on_inspect_requested(info: Dictionary) -> void:
	var map_id := _current_map_id()
	var token_id := str(info.get("token_id", ""))
	if not map_id.is_empty() and not token_id.is_empty():
		GameData.set_selected_token_id(map_id, token_id)
	elif not map_id.is_empty() and str(info.get("kind", "")) == "":
		GameData.set_selected_token_id(map_id, "")
	_pending_nav = _pending_nav_from_inspect(info)
	_inspect_hint = _hint_for_inspect(info)
	_focus_speaker_from_inspect(info)
	if toolbar:
		toolbar.set_hint(_inspect_hint if not _inspect_hint.is_empty() else SessionToolRegistry.hint(str(_tool.get("mode", SessionToolRegistry.SELECT))))
	if _is_gm:
		_render_toolbar(GameData.active_game, GameData.get_session_display_map(_active_map_id).get("displayMap", {}))

func _on_token_moved(token_id: String, gx: float, gy: float) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	if not GameData.can_session_move_token(map_id, token_id, _is_gm, _owned_member_id()):
		return
	GameData.submit_map_op(map_id, {
		"type": GameData.MAP_OP_MOVE_TOKEN, "tokenId": token_id, "x": gx, "y": gy,
	})
	GameData.save_map_view_state(map_id, stage.get_view_state())
	refresh()

func _on_prop_moved(prop_id: String, gx: float, gy: float) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty() or not _is_gm:
		return
	if GameData.move_map_prop(map_id, prop_id, gx, gy):
		refresh()

func _on_fog_revealed(cells: Array) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	GameData.reveal_fog_cells(map_id, cells)
	refresh()

func _on_fog_hidden(cells: Array) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	GameData.submit_map_op(map_id, { "type": GameData.MAP_OP_FOG_HIDE, "cells": cells })
	refresh()

func _on_token_selected(token_id: String) -> void:
	var map_id := _current_map_id()
	GameData.set_selected_token_id(map_id, token_id)
	if token_id.is_empty():
		return
	var tok := GameData.find_map_token(map_id, token_id)
	if tok.is_empty():
		return
	_on_inspect_requested({
		"kind": str(tok.get("kind", "token")),
		"token_id": token_id,
		"label": str(tok.get("label", tok.get("name", ""))),
		"member_id": str(tok.get("memberId", "")),
		"marker_type": str(tok.get("markerType", "")),
		"role": str(tok.get("role", "")),
	})

func _on_effect_triggered(effect_id: String) -> void:
	GameData.trigger_map_effect(_current_map_id(), effect_id)
	stage.play_effect(effect_id)

func _on_trigger_effects() -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	var selected := GameData.get_selected_token_id(map_id)
	if selected.is_empty():
		for effect_variant in GameData.get_map_effects(map_id):
			GameData.trigger_map_effect(map_id, str((effect_variant as Dictionary).get("id", "")))
	else:
		GameData.trigger_map_effect(map_id, selected)
	for effect_variant in GameData.get_map_effects(map_id):
		var effect: Dictionary = effect_variant
		if bool(effect.get("triggered", false)):
			stage.play_effect(str(effect.get("id", "")))
	refresh()

func _on_area_clicked(area: Dictionary) -> void:
	if area.is_empty():
		return
	_pending_nav = _pending_nav_from_area(area)
	_inspect_hint = _hint_for_inspect({
		"kind": "area",
		"label": str(area.get("label", "")),
		"target_map_id": str(area.get("targetMapId", "")),
	})
	if toolbar:
		toolbar.set_hint(_inspect_hint)
	if _is_gm:
		_render_toolbar(GameData.active_game, GameData.get_session_display_map(_active_map_id).get("displayMap", {}))

func _on_area_activate_requested(area: Dictionary) -> void:
	_enter_area(area)

func _on_enter_requested() -> void:
	if _pending_nav.is_empty():
		return
	if str(_pending_nav.get("action", "")) == "enter_area":
		_enter_area(_pending_nav.get("area", {}))
	elif str(_pending_nav.get("action", "")) == "enter_local":
		_on_navigation_requested("enter_local", _pending_nav.get("data", {}))
	elif str(_pending_nav.get("action", "")) == "exit_world":
		_on_navigation_requested("exit_world", {})

func _enter_area(area: Dictionary) -> void:
	var map_id := _current_map_id()
	var area_id := str(area.get("id", _pending_nav.get("area_id", "")))
	if map_id.is_empty() or area_id.is_empty():
		return
	if GameData.enter_area(map_id, area_id):
		_pending_nav = {}
		refresh()

func _on_area_hovered(area: Dictionary) -> void:
	if area.is_empty():
		if not _inspect_hint.is_empty():
			toolbar.set_hint(_inspect_hint)
		else:
			toolbar.set_hint(SessionToolRegistry.hint(str(_tool.get("mode", SessionToolRegistry.SELECT))))
		return
	var label := str(area.get("label", "")).strip_edges()
	if label.is_empty():
		return
	var linked := not str(area.get("targetMapId", "")).is_empty()
	toolbar.set_hint(("Lieu « %s » — double-clic ou Entrer pour y aller." % label) if linked else label)

func _on_navigation_requested(action: String, data: Dictionary) -> void:
	if action == "enter_local":
		GameData.enter_local_map(
			_active_map_id, int(data.get("x", 0)), int(data.get("y", 0)), str(data.get("targetMapId", ""))
		)
	elif action == "enter_area":
		GameData.enter_area(_current_map_id(), str(data.get("areaId", "")))
	elif action == "exit_world":
		GameData.exit_to_world_map()
	_pending_nav = {}
	refresh()

func _pending_nav_from_inspect(info: Dictionary) -> Dictionary:
	var marker_type := str(info.get("marker_type", ""))
	if marker_type == "exit":
		return {
			"action": "exit_world",
			"label": str(info.get("label", "Sortie")),
			"can_enter": true,
			"hint": "Sortie « %s » — double-clic ou Entrer pour quitter." % str(info.get("label", "Sortie")),
		}
	if str(info.get("kind", "")) == "area" and not str(info.get("target_map_id", "")).is_empty():
		return {
			"action": "enter_area",
			"area": { "id": str(info.get("area_id", "")), "label": str(info.get("label", "")), "targetMapId": str(info.get("target_map_id", "")) },
			"area_id": str(info.get("area_id", "")),
			"label": str(info.get("label", "Lieu")),
			"can_enter": true,
			"hint": "Lieu « %s » — double-clic ou Entrer pour y aller." % str(info.get("label", "Lieu")),
		}
	return {}

func _pending_nav_from_area(area: Dictionary) -> Dictionary:
	var label := str(area.get("label", "Lieu")).strip_edges()
	var target := str(area.get("targetMapId", ""))
	if target.is_empty():
		return {}
	return {
		"action": "enter_area",
		"area": area,
		"area_id": str(area.get("id", "")),
		"label": label,
		"can_enter": true,
		"hint": "Lieu « %s » — double-clic ou Entrer pour y aller." % label,
	}

func _hint_for_inspect(info: Dictionary) -> String:
	var label := str(info.get("label", "")).strip_edges()
	var kind := str(info.get("kind", ""))
	var marker_type := str(info.get("marker_type", ""))
	if kind == "member" or not str(info.get("member_id", "")).is_empty():
		return ("%s — sélectionné. Glisser pour déplacer." % label) if not label.is_empty() else "Personnage sélectionné."
	if kind == "npc" or marker_type == "npc":
		return ("%s — glisser pour déplacer, ou Faire parler dans la console." % label) if not label.is_empty() else "PNJ — glisser pour déplacer."
	if kind == "prop":
		return ("%s — glisser pour déplacer." % label) if not label.is_empty() else "Décor — glisser pour déplacer."
	if kind == "area":
		if str(info.get("target_map_id", "")).is_empty():
			return ("Lieu « %s »." % label) if not label.is_empty() else "Lieu."
		return "Lieu « %s » — double-clic ou Entrer pour y aller." % label
	if kind == "marker":
		if marker_type == "danger":
			return ("Repère Danger « %s » — sélectionné (ce n'est pas un combat)." % label) if not label.is_empty() else "Repère Danger — sélectionné (ce n'est pas un combat)."
		if marker_type == "exit":
			return "Sortie « %s » — double-clic ou Entrer pour quitter." % (label if not label.is_empty() else "Sortie")
		if marker_type == "party":
			return ("Repère de groupe « %s » — sélectionné." % label) if not label.is_empty() else "Repère de groupe — sélectionné."
		return ("Repère « %s » — sélectionné." % label) if not label.is_empty() else "Repère sélectionné."
	if kind.is_empty():
		return SessionToolRegistry.hint(str(_tool.get("mode", SessionToolRegistry.SELECT)))
	return ("%s — sélectionné." % label) if not label.is_empty() else ""

func _focus_speaker_from_inspect(info: Dictionary) -> void:
	if not _is_gm:
		return
	var kind := str(info.get("kind", ""))
	var marker_type := str(info.get("marker_type", ""))
	if kind != "npc" and marker_type != "npc":
		return
	var label := str(info.get("label", "")).strip_edges()
	if label.is_empty():
		return
	speaker_focus_requested.emit(label)
