extends VBoxContainer
class_name MapWorkspacePanel

## Assemble la zone carte : navigateur (haut), scène (centre), outils (bas).
## Structure dans `scenes/session/panels/map_workspace.tscn`.
##
## Seul endroit de la session qui parle « carte » à GameData : les trois
## panneaux enfants restent muets sur l'état de jeu.

signal speaker_focus_requested(npc_name: String)
signal notice_requested(text: String)

const WorldNavigationScript := preload("res://scripts/session/world_navigation.gd")
const WorldMapOverlayScript := preload("res://scripts/session/world_map_overlay.gd")

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
var _world_map: Control
var _exits_lbl: Label
var _fade: ColorRect
var _transitioning: bool = false
var _zone_title_lbl: Label
var _zone_new_lbl: Label
var _help_overlay: PanelContainer
var _minimap_panel: PanelContainer
var _minimap: SessionMinimap
var _exits_btn_box: HBoxContainer

func _ready() -> void:
	navigator.map_selected.connect(_on_map_selected)
	navigator.exit_area_requested.connect(func(): GameData.exit_area(); refresh())
	navigator.exit_to_world_requested.connect(func(): GameData.exit_to_world_map(); refresh())
	navigator.zoom_in_requested.connect(func(): stage.zoom_in())
	navigator.zoom_out_requested.connect(func(): stage.zoom_out())
	navigator.fit_requested.connect(func(): stage.fit())
	navigator.focus_party_requested.connect(func(): _focus_party())
	navigator.world_map_requested.connect(func(): _toggle_world_map())

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

	# Boussole de sorties (zones voisines) + rappel carte du monde.
	var exits_panel := PanelContainer.new()
	exits_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var exits_style := StyleBoxFlat.new()
	exits_style.bg_color = Color(0.03, 0.03, 0.035, 0.62)
	exits_style.corner_radius_top_left = 7
	exits_style.corner_radius_top_right = 7
	exits_style.corner_radius_bottom_left = 7
	exits_style.corner_radius_bottom_right = 7
	exits_style.content_margin_left = 9
	exits_style.content_margin_right = 9
	exits_style.content_margin_top = 4
	exits_style.content_margin_bottom = 4
	exits_panel.add_theme_stylebox_override("panel", exits_style)
	exits_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	exits_panel.offset_left = 12
	exits_panel.offset_top = 8
	stage.add_child(exits_panel)
	var exits_box := VBoxContainer.new()
	exits_box.add_theme_constant_override("separation", 2)
	exits_panel.add_child(exits_box)
	_exits_lbl = Label.new()
	_exits_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exits_lbl.add_theme_font_size_override("font_size", 12)
	_exits_lbl.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75, 0.95))
	_exits_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_exits_lbl.add_theme_constant_override("shadow_offset_x", 1)
	_exits_lbl.add_theme_constant_override("shadow_offset_y", 1)
	exits_box.add_child(_exits_lbl)
	_exits_btn_box = HBoxContainer.new()
	_exits_btn_box.add_theme_constant_override("separation", 4)
	exits_box.add_child(_exits_btn_box)

	# Aide des raccourcis de session (touche H), centrée et compacte.
	var help_center := CenterContainer.new()
	help_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(help_center)
	_help_overlay = PanelContainer.new()
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_overlay.custom_minimum_size = Vector2(560, 520)
	var help_style := StyleBoxFlat.new()
	help_style.bg_color = Color(0.04, 0.04, 0.05, 0.94)
	help_style.border_color = Color(0.85, 0.72, 0.42, 0.8)
	help_style.set_border_width_all(1)
	help_style.set_corner_radius_all(10)
	help_style.set_content_margin_all(16)
	_help_overlay.add_theme_stylebox_override("panel", help_style)
	help_center.add_child(_help_overlay)
	var help_text := RichTextLabel.new()
	help_text.bbcode_enabled = true
	help_text.scroll_active = true
	help_text.fit_content = false
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text.custom_minimum_size = Vector2(520, 480)
	help_text.text = """[center][b]Aide de session[/b][/center]

[b]Déplacements[/b]
• Glisser un pion vers un bord de carte change de zone.
• Boutons [b]Groupe[/b] (G) et [b]Monde[/b] (M) dans la barre.

[b]Carte du monde[/b]
• [b]M[/b] ouvre/ferme la carte du monde.
• Clic sur une zone découverte : voyage rapide.
• Survol : nom et taille de la zone.

[b]Caméra[/b]
• Molette ou [b]+ / −[/b] : zoom.
• [b]G[/b] : recentrer sur le groupe · [b]F[/b] : cadrer la carte.
• [b]1-9[/b] : changer de carte/zone.

[b]Divers[/b]
• [b]N[/b] : afficher/masquer les noms des figurines.
• [b]H[/b] ou [b]Échap[/b] : fermer cette aide."""
	_help_overlay.add_child(help_text)
	_help_overlay.visible = false

	# Mini-carte de la zone courante (coin bas-droit, touche C).
	var mini_layer := Control.new()
	mini_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(mini_layer)
	_minimap_panel = PanelContainer.new()
	var mini_style := StyleBoxFlat.new()
	mini_style.bg_color = Color(0.03, 0.03, 0.045, 0.82)
	mini_style.border_color = Color(0.85, 0.72, 0.42, 0.7)
	mini_style.set_border_width_all(1)
	mini_style.set_corner_radius_all(8)
	mini_style.set_content_margin_all(2)
	_minimap_panel.add_theme_stylebox_override("panel", mini_style)
	_minimap_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap_panel.offset_left = -230
	_minimap_panel.offset_top = -196
	_minimap_panel.offset_right = -10
	_minimap_panel.offset_bottom = -10
	mini_layer.add_child(_minimap_panel)
	_minimap = SessionMinimap.new()
	_minimap.custom_minimum_size = Vector2(216, 182)
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap.jump_requested.connect(func(grid: Vector2):
		stage.focus_grid_rect(Rect2(grid - Vector2(4.0, 3.0), Vector2(8.0, 6.0)), 1.5)
	)
	_minimap_panel.add_child(_minimap)

	# Carte du monde de session (touche M) : superposée à toute la fenêtre.
	_world_map = WorldMapOverlayScript.new()
	get_tree().root.add_child(_world_map)
	_world_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_map.visible = false
	_world_map.zone_selected.connect(_on_world_zone_selected)
	# Fondu noir de transition entre zones (façon Dofus).
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	get_tree().root.add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Titre de zone affiché pendant le fondu (façon Dofus).
	_zone_title_lbl = Label.new()
	_zone_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zone_title_lbl.add_theme_font_size_override("font_size", 46)
	_zone_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.65))
	_zone_title_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_zone_title_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_zone_title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_zone_title_lbl.modulate.a = 0.0
	_zone_title_lbl.visible = false
	get_tree().root.add_child(_zone_title_lbl)
	_zone_title_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Sous-titre « nouvelle zone découverte » sous le nom (première visite).
	_zone_new_lbl = Label.new()
	_zone_new_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_new_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_new_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zone_new_lbl.add_theme_font_size_override("font_size", 20)
	_zone_new_lbl.add_theme_color_override("font_color", Color(0.7, 0.88, 1.0))
	_zone_new_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_zone_new_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_zone_new_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_zone_new_lbl.modulate.a = 0.0
	_zone_new_lbl.visible = false
	get_tree().root.add_child(_zone_new_lbl)
	_zone_new_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zone_new_lbl.offset_top = 58
	tree_exiting.connect(func():
		if _world_map != null and is_instance_valid(_world_map):
			_world_map.queue_free()
		if _fade != null and is_instance_valid(_fade):
			_fade.queue_free()
		if _zone_title_lbl != null and is_instance_valid(_zone_title_lbl):
			_zone_title_lbl.queue_free()
		if _zone_new_lbl != null and is_instance_valid(_zone_new_lbl):
			_zone_new_lbl.queue_free()
	)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_M:
		_toggle_world_map()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_G:
		_focus_party()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F:
		stage.fit()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_C:
		if _minimap_panel != null:
			_minimap_panel.visible = not _minimap_panel.visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_H:
		if _help_overlay != null:
			_help_overlay.visible = not _help_overlay.visible
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _help_overlay != null and _help_overlay.visible:
		_help_overlay.visible = false
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_N:
		# Afficher/masquer les noms flottants des figurines.
		MapToken3D.labels_enabled = not MapToken3D.labels_enabled
		notice_requested.emit("Noms des figurines : %s" % ("affichés" if MapToken3D.labels_enabled else "masqués"))
		get_viewport().set_input_as_handled()
	elif key.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
		stage.zoom_in()
		get_viewport().set_input_as_handled()
	elif key.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		stage.zoom_out()
		get_viewport().set_input_as_handled()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
		# 1-9 : bascule rapide entre les cartes/onglets de zone.
		if navigator != null and navigator.select_map_index(int(key.keycode - KEY_1)):
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and _world_map != null and _world_map.visible:
		_world_map.visible = false
		get_viewport().set_input_as_handled()

## Recentre la caméra sur le groupe (touche G), ou sur la carte si vide.
func _focus_party() -> void:
	if stage == null:
		return
	var map_id := _current_map_id()
	var party_ids: Array = []
	for member_variant in GameData.active_game.get("party", []):
		if member_variant is Dictionary:
			party_ids.append(str((member_variant as Dictionary).get("id", "")))
	var points: Array = []
	for token_variant in GameData.get_map_play_tokens(map_id):
		if not token_variant is Dictionary:
			continue
		var token: Dictionary = token_variant
		if str(token.get("kind", "")) != "member":
			continue
		if not party_ids.is_empty() and not party_ids.has(str(token.get("memberId", ""))):
			continue
		points.append(Vector2(float(token.get("x", 0.0)), float(token.get("y", 0.0))))
	if points.is_empty():
		stage.fit()
		return
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point_variant in points:
		var point: Vector2 = point_variant
		bounds = bounds.expand(point)
	var center := bounds.get_center()
	var half := maxf(3.0, maxf(bounds.size.x, bounds.size.y) * 0.5 + 3.0)
	var focus := Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)
	if stage.has_method("focus_grid_rect"):
		stage.focus_grid_rect(focus, 1.5)
	else:
		stage.fit()

func _toggle_world_map() -> void:
	if _world_map == null:
		return
	_world_map.visible = not _world_map.visible
	if _world_map.visible:
		_world_map.refresh()
		_world_map.fit_view()

func _on_world_zone_selected(map_id: String) -> void:
	if map_id.is_empty() or _transitioning:
		return
	if _world_map != null:
		_world_map.visible = false
	_travel_to_zone(map_id)

## Voyage rapide depuis la carte du monde, avec fondu noir.
func _travel_to_zone(map_id: String) -> void:
	_transitioning = true
	await _fade_to(1.0)
	var was_known := GameData.get_discovered_world_zones().has(map_id)
	if GameData.enter_world_zone(map_id):
		_active_map_id = map_id
		refresh()
		var title := str(MapData.get_by_id(map_id).get("title", "Zone"))
		notice_requested.emit("Voyage vers %s" % title)
		await _flash_zone_title(title, not was_known)
	await _fade_to(0.0)
	_transitioning = false

## Affiche le nom de la zone au centre pendant le fondu (écran noir).
func _flash_zone_title(title: String, is_new: bool = false) -> void:
	if _zone_title_lbl == null:
		return
	_zone_title_lbl.text = title
	_zone_title_lbl.visible = true
	_zone_title_lbl.modulate.a = 0.0
	if _zone_new_lbl != null:
		_zone_new_lbl.text = "Nouvelle zone découverte" if is_new else ""
		_zone_new_lbl.visible = is_new
		_zone_new_lbl.modulate.a = 0.0
	var tween_in := create_tween()
	tween_in.tween_property(_zone_title_lbl, "modulate:a", 1.0, 0.18)
	if _zone_new_lbl != null and is_new:
		tween_in.parallel().tween_property(_zone_new_lbl, "modulate:a", 1.0, 0.18)
	await tween_in.finished
	await get_tree().create_timer(0.55).timeout
	var tween_out := create_tween()
	tween_out.tween_property(_zone_title_lbl, "modulate:a", 0.0, 0.25)
	if _zone_new_lbl != null and is_new:
		tween_out.parallel().tween_property(_zone_new_lbl, "modulate:a", 0.0, 0.25)
	await tween_out.finished
	_zone_title_lbl.visible = false
	if _zone_new_lbl != null:
		_zone_new_lbl.visible = false

## Fond noir progressif entre deux zones.
func _fade_to(alpha: float) -> void:
	if _fade == null:
		return
	_fade.visible = true
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, 0.22)
	await tween.finished
	if alpha <= 0.01:
		_fade.visible = false

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

func set_immersive(on: bool) -> void:
	if not is_node_ready():
		await ready
	_immersive = on
	_apply_chrome_visibility()
	stage.set_immersive(on)

func apply_immersive_inset(inset: Vector4) -> void:
	if stage != null and stage.has_method("apply_immersive_inset"):
		stage.apply_immersive_inset(inset)

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
	if not str(display_map.get("worldId", "")).is_empty():
		GameData.mark_world_zone_discovered(map_id)
	_update_exits_hint(display_map, map_id)

	_explore_mode = not str(display_map.get("backgroundImage", "")).strip_edges().is_empty()
	_mode = MapMode.COMPLEX if _explore_mode else GameData.get_effective_render_mode(active_id)
	_is_gm = _gm_view and GameData.is_gm_view_for_map(map_id) and not _player_preview
	if _tool.is_empty() or (not _is_gm and SessionToolRegistry.is_place_tool(_tool)):
		_tool = SessionToolRegistry.default_tool()

	_render_navigator(ctx, map_ids, active_id)
	_render_toolbar(state, display_map)
	_configure_stage(state, ctx, map_id)
	_update_minimap(map_id)
	_apply_chrome_visibility()

## Met à jour la mini-carte avec la zone et les pions courants.
func _update_minimap(map_id: String) -> void:
	if _minimap == null:
		return
	var map := MapData.get_by_id(map_id)
	var tokens: Array = GameData.get_map_play_tokens(map_id)
	var selected := GameData.get_selected_token_id(map_id)
	_minimap.configure(map, tokens, selected)

## Boussole de sorties : zones voisines accessibles depuis la zone courante.
func _update_exits_hint(display_map: Dictionary, map_id: String) -> void:
	if _exits_lbl == null:
		return
	_exits_lbl.text = ""
	if _exits_btn_box != null:
		for child in _exits_btn_box.get_children():
			_exits_btn_box.remove_child(child)
			child.queue_free()
	var world_id := str(display_map.get("worldId", ""))
	if world_id.is_empty():
		return
	var zones: Array = WorldNavigationScript.zones_for_world(_maps_for_world(map_id), world_id)
	var zone: Dictionary = {}
	for zone_variant in zones:
		if str((zone_variant as Dictionary).get("id", "")) == map_id:
			zone = zone_variant
			break
	if zone.is_empty():
		return
	var arrows := {"north": "↑ N", "east": "→ E", "south": "↓ S", "west": "← O"}
	var parts: PackedStringArray = PackedStringArray()
	for side in ["north", "east", "south", "west"]:
		var info: Dictionary = WorldNavigationScript.neighbor_on_side(zones, zone, side)
		var target := str(info.get("target", ""))
		if target.is_empty():
			continue
		var target_map: Dictionary = MapData.get_by_id(target)
		var title := str(target_map.get("title", target))
		parts.append("%s %s" % [arrows[side], title])
		if _exits_btn_box != null:
			var target_id := target
			var btn := Button.new()
			btn.text = "%s %s" % [arrows[side], title]
			btn.tooltip_text = "Aller à %s" % title
			btn.add_theme_font_size_override("font_size", 10)
			btn.pressed.connect(func(): _travel_to_zone(target_id))
			_exits_btn_box.add_child(btn)
	if parts.is_empty():
		return
	_exits_lbl.text = "🧭 Sorties · (M : carte du monde)"

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

func focus_speaker(speaker: String) -> void:
	if stage == null:
		return
	var grid := GameData.find_speaker_grid(speaker)
	if grid.x < 0.0:
		return
	if stage.has_method("center_on_grid"):
		stage.center_on_grid(grid.x, grid.y)

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
	# Franchissement d'un bord de zone : on bascule sur la carte voisine.
	if _try_edge_transition(token_id, gx, gy):
		return
	GameData.submit_map_op(map_id, {
		"type": GameData.MAP_OP_MOVE_TOKEN, "tokenId": token_id, "x": gx, "y": gy,
	})
	GameData.save_map_view_state(map_id, stage.get_view_state())
	refresh()

## Tente une transition par le bord du monde (zones façon Dofus). Renvoie vrai
## si la carte active a changé (le token est déjà replacé par GameData).
func _try_edge_transition(token_id: String, gx: float, gy: float) -> bool:
	if _transitioning:
		return false
	var map_id := _current_map_id()
	var current_map: Dictionary = MapData.get_by_id(map_id)
	if current_map.is_empty():
		return false
	var side: String = WorldNavigationScript.edge_side_near_border(current_map, Vector2(gx, gy))
	if side.is_empty():
		return false
	var maps := _maps_for_world(map_id)
	if maps.size() < 2:
		return false
	var result: Dictionary = WorldNavigationScript.resolve_edge_transition(
		maps, map_id, side, Vector2(gx, gy))
	if not bool(result.get("ok", false)):
		return false
	var target_id := str(result.get("target_map_id", ""))
	_start_zone_transition(target_id, token_id, result.get("position", Vector2.ZERO))
	return true

## Change de zone avec fondu : le token est transféré pendant l'écran noir.
func _start_zone_transition(target_id: String, token_id: String, position: Vector2) -> void:
	if _transitioning:
		return
	_transitioning = true
	await _fade_to(1.0)
	var was_known := GameData.get_discovered_world_zones().has(target_id)
	if GameData.transition_map_edge(target_id, token_id, position):
		_active_map_id = target_id
		var target_map: Dictionary = MapData.get_by_id(target_id)
		var title := str(target_map.get("title", "carte"))
		notice_requested.emit("Changement de zone : %s" % title)
		refresh()
		await _flash_zone_title(title, not was_known)
	await _fade_to(0.0)
	_transitioning = false

## Cartes du monde courant (celles de la session + toutes les zones du même monde).
func _maps_for_world(current_map_id: String) -> Array:
	var current: Dictionary = MapData.get_by_id(current_map_id)
	var world_id := str(current.get("worldId", ""))
	var out: Array = []
	var seen: Dictionary = {}
	for map_id_variant in GameData.active_game.get("mapIds", []):
		var map: Dictionary = MapData.get_by_id(str(map_id_variant))
		if map.is_empty() or seen.has(str(map.get("id", ""))):
			continue
		out.append(map)
		seen[str(map.get("id", ""))] = true
	if not world_id.is_empty():
		for map_variant in MapData.maps:
			if not map_variant is Dictionary:
				continue
			var map: Dictionary = map_variant
			if str(map.get("worldId", "")) != world_id:
				continue
			var map_id := str(map.get("id", ""))
			if map_id.is_empty() or seen.has(map_id):
				continue
			out.append(map)
			seen[map_id] = true
	return out

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
	# En P2P, seul le MJ change de lieu (sinon chaque client diverge).
	if MultiplayerManager.is_p2p_active() and not MultiplayerManager.is_p2p_host():
		notice_requested.emit("Seul le maître de jeu peut changer de lieu.")
		if toolbar:
			toolbar.set_hint("Seul le MJ peut entrer dans un lieu en réseau.")
		return
	var map_id := _current_map_id()
	var area_id := str(area.get("id", _pending_nav.get("area_id", "")))
	if map_id.is_empty() or area_id.is_empty():
		return
	if GameData.enter_area(map_id, area_id):
		_pending_nav = {}
		refresh()
	else:
		notice_requested.emit("Impossible d'entrer dans ce lieu.")

func _on_area_hovered(area: Dictionary) -> void:
	if area.is_empty():
		if not _inspect_hint.is_empty():
			toolbar.set_hint(_inspect_hint)
		else:
			toolbar.set_hint(SessionToolRegistry.hint(str(_tool.get("mode", SessionToolRegistry.SELECT))))
		return
	var label := str(area.get("label", "")).strip_edges()
	if label.is_empty() and (area.has("radius") or str(area.get("shape", "")) != ""):
		label = "Zone"
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

# ---------------------------------------------------------------------------
# Pilotage UI (simulateur / tests) — mêmes chemins que la souris
# ---------------------------------------------------------------------------

func ui_select_tool(tool: Dictionary) -> void:
	_on_tool_selected(tool)

func ui_select_select_tool() -> void:
	ui_select_tool(SessionToolRegistry.make(SessionToolRegistry.SELECT))

func ui_move_token(token_id: String, gx: float, gy: float) -> void:
	_on_token_moved(token_id, gx, gy)

func ui_click_grid(gx: float, gy: float) -> void:
	_on_grid_clicked(gx, gy, _tool)

func ui_prepare_enter_area(area_id: String) -> bool:
	var map_id := _current_map_id()
	if map_id.is_empty() or area_id.is_empty():
		return false
	var area := MapData.get_area(MapData.get_by_id(map_id), area_id)
	if area.is_empty():
		return false
	_on_area_clicked(area)
	_render_toolbar(GameData.active_game, GameData.get_session_display_map(_active_map_id).get("displayMap", {}))
	return not _pending_nav.is_empty()

func ui_press_enter() -> void:
	_on_enter_requested()

func ui_press_back() -> void:
	if navigator != null:
		navigator.get_node("%BtnBack").pressed.emit()

func ui_press_toolbar_enter_button() -> bool:
	if toolbar == null:
		return false
	var row: HBoxContainer = toolbar.get_node("%ToolRow")
	for child in row.get_children():
		if child is Button and str(child.text) == "Entrer":
			(child as Button).pressed.emit()
			return true
	ui_press_enter()
	return true

func current_display_map_id() -> String:
	return _current_map_id()
