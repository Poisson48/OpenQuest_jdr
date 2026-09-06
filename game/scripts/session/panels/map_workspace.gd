extends VBoxContainer
class_name MapWorkspacePanel

## Assemble la zone carte : navigateur (haut), scène (centre), outils (bas).
## Structure dans `scenes/session/panels/map_workspace.tscn`.
##
## Seul endroit de la session qui parle « carte » à GameData : les trois
## panneaux enfants restent muets sur l'état de jeu.

@onready var navigator: MapNavigatorPanel = %MapNavigator
@onready var stage: MapStagePanel = %MapStage
@onready var toolbar: MapToolbarPanel = %MapToolbar

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
	stage.fog_revealed.connect(_on_fog_revealed)
	stage.fog_hidden.connect(_on_fog_hidden)
	stage.token_selected.connect(_on_token_selected)
	stage.effect_trigger_requested.connect(_on_effect_triggered)
	stage.area_clicked.connect(_on_area_clicked)
	stage.area_hovered.connect(_on_area_hovered)
	stage.navigation_requested.connect(_on_navigation_requested)
	stage.view_changed.connect(_sync_scale)

	toolbar.tool_selected.connect(_on_tool_selected)
	toolbar.mode_selected.connect(_on_mode_selected)
	toolbar.snap_toggled.connect(_on_snap_toggled)
	toolbar.trigger_requested.connect(_on_trigger_effects)

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
	visible = not map_ids.is_empty()
	if map_ids.is_empty():
		return

	_readonly = str(state.get("status", "")) == "completed"
	var active_id := _resolve_active_map_id(map_ids)
	var ctx := GameData.get_session_display_map(active_id)
	var display_map: Dictionary = ctx.get("displayMap", {})
	if display_map.is_empty():
		return
	var map_id := str(display_map.get("id", ""))

	_explore_mode = not str(display_map.get("backgroundImage", "")).strip_edges().is_empty()
	_mode = MapMode.COMPLEX if _explore_mode else GameData.get_effective_render_mode(active_id)
	_is_gm = _gm_view and GameData.is_gm_view_for_map(map_id) and not _player_preview
	if _tool.is_empty():
		_tool = SessionToolRegistry.default_tool(state.get("party", []))

	_render_navigator(ctx, map_ids, active_id)
	_render_toolbar(state, display_map)
	_configure_stage(state, ctx, map_id)
	_apply_chrome_visibility()

## La barre d'outils se rend visible en se reconstruisant : en vue immersive on
## la remasque après coup, sinon la carte perdrait sa pleine page au premier
## rafraîchissement.
func _apply_chrome_visibility() -> void:
	if _immersive:
		navigator.visible = false
		toolbar.visible = false
	else:
		navigator.visible = true

## Décrit l'état carte — utilisé par les tests de mise en page.
func describe() -> Dictionary:
	return {
		"map_id": _active_map_id,
		"mode": _mode,
		"is_gm": _is_gm,
		"tool": _tool.get("mode", ""),
		"scale": stage.get_effective_scale() if stage else 0.0,
		"stage_size": stage.size if stage else Vector2.ZERO,
		"chrome_visible": navigator.visible if navigator else false,
	}

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

func _on_cell_clicked(x: int, y: int) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	GameData.apply_map_play_action(map_id, x, y, SessionToolRegistry.to_simple_tool(_tool))
	refresh()

func _on_grid_clicked(gx: float, gy: float, tool: Dictionary) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	GameData.apply_complex_map_click(map_id, gx, gy, tool)
	refresh()

func _on_token_moved(token_id: String, gx: float, gy: float) -> void:
	var map_id := _current_map_id()
	if map_id.is_empty():
		return
	GameData.submit_map_op(map_id, {
		"type": GameData.MAP_OP_MOVE_TOKEN, "tokenId": token_id, "x": gx, "y": gy,
	})
	GameData.save_map_view_state(map_id, stage.get_view_state())

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
	GameData.set_selected_token_id(_current_map_id(), token_id)

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
	var map_id := _current_map_id()
	var area_id := str(area.get("id", ""))
	if map_id.is_empty() or area_id.is_empty():
		return
	if GameData.enter_area(map_id, area_id):
		refresh()

func _on_area_hovered(area: Dictionary) -> void:
	if area.is_empty():
		toolbar.set_hint(SessionToolRegistry.hint(str(_tool.get("mode", SessionToolRegistry.MEMBER))))
		return
	var label := str(area.get("label", "")).strip_edges()
	if label.is_empty():
		return
	var linked := not str(area.get("targetMapId", "")).is_empty()
	toolbar.set_hint(("Entrer dans « %s »" % label) if linked else label)

func _on_navigation_requested(action: String, data: Dictionary) -> void:
	if action == "enter_local":
		GameData.enter_local_map(
			_active_map_id, int(data.get("x", 0)), int(data.get("y", 0)), str(data.get("targetMapId", ""))
		)
	elif action == "exit_world":
		GameData.exit_to_world_map()
	refresh()
