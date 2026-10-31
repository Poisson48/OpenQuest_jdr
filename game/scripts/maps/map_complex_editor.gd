extends Control

## Éditeur de battlemap 3D complet.
##
## Architecture inspirée de l'éditeur Meownopoly (cf. docs/MAP_EDITOR.md) :
##   • un document (`MapEditDocument`) porte le modèle et l'historique par deltas ;
##   • une machine à états d'outils décide de l'interprétation de la souris ;
##   • le moteur 3D ne fait que rendre et projeter, l'overlay 2D dessine la
##     sélection, les liens, les aperçus et la règle ;
##   • les panneaux (inspecteur, arborescence, bibliothèque, historique) lisent
##     et écrivent uniquement à travers le document.

signal layout_changed
signal open_map_requested(map_id: String)

const ComplexMapEngineScript := preload("res://scripts/maps/complex_map_engine_3d.gd")
const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")
const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")
const OverlayScript := preload("res://scripts/maps/editor/map_editor_overlay.gd")
const MinimapScript := preload("res://scripts/maps/editor/map_editor_minimap.gd")
const InspectorScript := preload("res://scripts/maps/editor/map_editor_inspector.gd")
const OutlinerScript := preload("res://scripts/maps/editor/map_editor_outliner.gd")
const TemplatesScript := preload("res://scripts/maps/editor/map_editor_templates.gd")
const HistoryPanelScript := preload("res://scripts/maps/editor/map_editor_history_panel.gd")
const SettingsPanelScript := preload("res://scripts/maps/editor/map_editor_settings_panel.gd")
const LibraryPanelScript := preload("res://scripts/maps/editor/map_editor_library_panel.gd")
const EscMenuScript := preload("res://scripts/maps/editor/map_editor_esc_menu.gd")
const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const MapVisionScript := preload("res://scripts/maps/map_vision.gd")
const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")

const SAVE_MANUAL := "manual"
const SAVE_ON_CHANGE := "on_change"
const SAVE_INTERVAL := "interval"

# --- État --------------------------------------------------------------------
# Types via preload (pas class_name global) : clone sans .godot compile (AUDIT UI P0-1).
var doc = DocumentScript.new()
var _editable: bool = true
var _tool: String = ToolsScript.SELECT
var _snap_mode: String = "cell"
var _save_policy: String = SAVE_MANUAL
var _save_interval: float = 30.0

var _effect_preset: String = "fire"
var _marker_type: String = "npc"
var _member_index: int = 0
var _token_label: String = ""
var _token_kind: String = "member"
var _token_dialogue: String = ""
var _token_size: float = 1.0
var _zone_radius: float = 1.5
var _zone_label: String = "Zone"
var _effect_radius: float = 1.0
var _brush_size: int = 0
## Relief : pinceau de hauteurs (mode raise/lower/flatten/smooth).
var _relief_radius: float = 1.5
var _relief_strength: float = 0.35
var _relief_mode: String = "raise"
## Sol : matière peinte (0 herbe, 1 terre, 2 pierre) + rayon du pinceau.
var _material_id: int = 0
var _material_radius: float = 1.5
var _fog_brush: int = 1
var _paint_tile: String = ""
var _selected_template: String = ""
var _area_category: String = "building"
var _prop_asset: String = ""
var _prop_size: float = 2.0
var _prop_standing: bool = true
var _prop_rotation: float = 0.0
var _prop_category: String = "buildings"
## Objets 3D (carte 2.5D) : mesh GLB sélectionné dans la bibliothèque.
var _mesh_asset: String = ""
var _mesh_scale: float = 1.0
var _mesh_rotation: float = 0.0
var _mesh_snap_modules: bool = true
var _mesh_footprint_cache: Dictionary = {}
## Dialogue d'import de modèles 3D (GLB/glTF) pour la bibliothèque d'objets.
var _mesh_import_dialog: FileDialog
var _help_dialog: AcceptDialog
var _validate_dialog: AcceptDialog
var _validate_text: RichTextLabel
var _last_saved_at: float = 0.0
var _status_badges: HBoxContainer
var _policy_chip: Label
var _saved_ago_lbl: Label
var _autosave_lbl: Label
var _undo_depth_lbl: Label
var _status_tick: Timer
var _effect_list: VBoxContainer
var _area_label: String = ""
var _template_rotation: int = 0
var _space_held: bool = false
var _syncing: bool = false
## Aperçu session : ce que voit le joueur (brouillard + nuit/lumières). Non persisté.
var _player_view: bool = false
var _player_view_btn: Button
var _light_place_radius: float = 3.0

# --- Interaction --------------------------------------------------------------
var _press_mode: String = "none"
var _press_start_grid: Vector2 = Vector2.ZERO
var _press_start_screen: Vector2 = Vector2.ZERO
var _press_moved: bool = false
var _drag_ids: Array = []
var _drag_origins: Dictionary = {}
var _handle_state: Dictionary = {}
var _link_source: String = ""
var _painted_cells: Dictionary = {}
var _band_base_selection: Array = []

# --- Nœuds --------------------------------------------------------------------
var _engine: Control
var _overlay
var _minimap
var _inspector
var _outliner
var _world_panel: Control
var _left_panel: VBoxContainer
var _left_scroll: ScrollContainer
var _right_tabs: TabContainer
var _right_scroll: ScrollContainer = null
var _tool_options: VBoxContainer
var _history_list: VBoxContainer
var _template_list: VBoxContainer
var _asset_grid: GridContainer
var _asset_search: LineEdit
var _asset_filter_row: HFlowContainer
var _object3d_filter: String = "all"
var _object3d_search: String = ""
var _asset_category_row: HBoxContainer
var _asset_dialog: FileDialog
var _asset_hint: Label
var _status_lbl: Label
var _hint_lbl: Label
var _zoom_lbl: Label
var _dirty_lbl: Label
var _breadcrumb: HBoxContainer
var _undo_btn: Button
var _redo_btn: Button
var _tool_buttons: Dictionary = {}
var _autosave_timer: Timer
var _file_dialog: FileDialog
var _overlay_dialog: FileDialog
var _export_dialog: FileDialog
var _export_image_dialog: FileDialog
var _import_dialog: FileDialog
var _esc_menu
var _settings_panel
var _library_panel
var _template_name_dialog: AcceptDialog
var _template_name_input: LineEdit
var _settings_widgets: Dictionary = {}
var _split_outer: HSplitContainer
var _split_inner: HSplitContainer
var _center_column: VBoxContainer
## Largeurs de dock adaptées à la surface client réelle (recalculées au resize).
var _dock_left_w: float = 220.0
var _dock_right_w: float = 300.0
var _layout_applied_size: Vector2 = Vector2(-1, -1)
var _layout_retry: int = 0
var _layout_force: bool = true
var _viewport_frame: PanelContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 0)
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	doc.changed.connect(_on_doc_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.history_changed.connect(_on_history_changed)
	doc.dirty_changed.connect(_on_dirty_changed)
	_bind_ui()
	resized.connect(_on_editor_resized)
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)

# ===========================================================================
# API publique (consommée par map_viewer.gd)
# ===========================================================================

func set_editable(on: bool) -> void:
	_editable = on
	if _left_scroll:
		_left_scroll.visible = on
	if _right_tabs:
		_right_tabs.visible = on
	elif _right_scroll:
		_right_scroll.visible = on
	if _engine and _engine.has_method("set_editor_mode"):
		_engine.set_editor_mode(on)
	_sync_engine()
	_update_hint()
	_layout_force = true
	call_deferred("_apply_responsive_layout")

func load_map(map_data: Dictionary) -> void:
	doc.load_map(map_data)
	_paint_tile = _default_tile()
	_marker_type = _first_marker_type()
	_sync_settings_ui()
	_rebuild_palettes()
	_refresh_asset_library()
	_refresh_templates()
	_sync_engine(true)
	_refresh_panels()
	_update_hint()
	if _world_panel != null:
		_world_panel.refresh()

func apply_to_map_data() -> Dictionary:
	if _engine and _engine.has_method("get_view_state"):
		doc.play_defaults["viewState"] = _engine.get_view_state()
	return doc.to_map_data()

func get_play_defaults() -> Dictionary:
	var snapshot := apply_to_map_data()
	var defaults = snapshot.get("playDefaults", {})
	return (defaults as Dictionary).duplicate(true) if defaults is Dictionary else {}

func save_now() -> void:
	var snapshot := apply_to_map_data()
	MapData.update_map(snapshot)
	doc.mark_saved()
	_last_saved_at = Time.get_unix_time_from_system()
	_set_status("Carte enregistrée.")
	_refresh_status_badges()
	layout_changed.emit()

# ===========================================================================
# Construction de l'interface
# ===========================================================================

func _bind_ui() -> void:
	_split_outer = %SplitOuter
	_split_inner = %SplitInner
	_left_scroll = %LeftScroll
	_left_panel = %LeftPanel
	_tool_options = %ToolOptions
	_center_column = %CenterColumn
	_viewport_frame = %ViewportFrame
	_status_lbl = %LblStatus
	_hint_lbl = %LblHint
	_right_tabs = %RightTabs
	_right_scroll = null

	_populate_tools(%ToolHost)
	_populate_snap(%SnapOption)
	_minimap = MinimapScript.new()
	_minimap.jump_requested.connect(func(grid_pos: Vector2):
		if _engine and _engine.has_method("center_on_grid"):
			_engine.center_on_grid(grid_pos.x - 0.5, grid_pos.y - 0.5)
			_refresh_overlay()
	)
	%MinimapHost.add_child(_minimap)
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_action_bar()
	_create_engine(%ViewportStack)
	_bind_docks()
	_build_dialogs()
	_minimap.set_context(_engine, doc)

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = _save_interval
	_autosave_timer.timeout.connect(func():
		if _save_policy == SAVE_INTERVAL and doc.is_dirty():
			save_now()
	)
	add_child(_autosave_timer)

	_status_tick = Timer.new()
	_status_tick.wait_time = 1.0
	_status_tick.timeout.connect(_refresh_status_badges)
	add_child(_status_tick)
	_status_tick.start()

	_set_tool(ToolsScript.SELECT)
	_layout_force = true
	call_deferred("_apply_responsive_layout")
	call_deferred("_refresh_status_badges")

# --- Colonne gauche : outils --------------------------------------------------

func _populate_tools(host: VBoxContainer) -> void:
	for group in ToolsScript.GROUP_ORDER:
		_section(host, str(ToolsScript.GROUP_LABELS.get(group, group)))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		host.add_child(grid)
		for def in ToolsScript.defs_in_group(group):
			var tool_id := str(def["id"])
			var btn := Button.new()
			btn.text = str(def["icon"])
			btn.toggle_mode = true
			btn.tooltip_text = ToolsScript.tooltip(tool_id)
			btn.custom_minimum_size = Vector2(46, 38)
			btn.pressed.connect(func(): _set_tool(tool_id))
			_tool_buttons[tool_id] = btn
			grid.add_child(btn)

func _populate_snap(snap_option: OptionButton) -> void:
	for i in range(ToolsScript.SNAP_MODES.size()):
		var mode: Dictionary = ToolsScript.SNAP_MODES[i]
		snap_option.add_item(str(mode["label"]), i)
		snap_option.set_item_metadata(i, str(mode["id"]))
		if str(mode["id"]) == _snap_mode:
			snap_option.select(i)
	snap_option.item_selected.connect(func(index):
		_snap_mode = str(snap_option.get_item_metadata(index))
		_set_status("Aimantation : %s" % snap_option.get_item_text(index))
	)

# --- Colonne centrale : vue 3D -------------------------------------------------

func _create_engine(stack: Control) -> void:
	_engine = ComplexMapEngineScript.new()
	_engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_engine.editor_mode = true
	_engine.editor_pointer_pressed.connect(_on_pointer_pressed)
	_engine.editor_pointer_moved.connect(_on_pointer_moved)
	_engine.editor_pointer_released.connect(_on_pointer_released)
	_engine.view_changed.connect(_refresh_overlay)
	_engine.zoom_changed.connect(func(_z): _update_zoom_label())
	_engine.token_moved.connect(_on_engine_token_moved)
	stack.add_child(_engine)

	_overlay = OverlayScript.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.set_context(_engine, doc)
	stack.add_child(_overlay)

func _build_action_bar() -> void:
	var bar: HBoxContainer = %ActionBar

	_undo_btn = _icon_button(bar, "↶", "Annuler (Ctrl+Z)", func(): _do_undo())
	_redo_btn = _icon_button(bar, "↷", "Rétablir (Ctrl+Y)", func(): _do_redo())
	_icon_button(bar, "💾", "Enregistrer (Ctrl+S)", func(): save_now())
	_icon_button(bar, "⧉", "Dupliquer la sélection (Ctrl+D)", func(): doc.duplicate_selection())
	_icon_button(bar, "🗑", "Supprimer la sélection (Suppr)", func(): doc.remove_elements(doc.selection()))

	bar.add_child(VSeparator.new())
	_icon_button(bar, "⬆", "Premier plan", func(): doc.bring_to_front())
	_icon_button(bar, "⬇", "Arrière-plan", func(): doc.send_to_back())
	_icon_button(bar, "⇤", "Aligner à gauche", func(): doc.align_selection("left"))
	_icon_button(bar, "⇥", "Aligner à droite", func(): doc.align_selection("right"))
	_icon_button(bar, "⤒", "Aligner en haut", func(): doc.align_selection("top"))
	_icon_button(bar, "⤓", "Aligner en bas", func(): doc.align_selection("bottom"))
	_icon_button(bar, "⇔", "Centrer horizontalement", func(): doc.align_selection("center_h"))
	_icon_button(bar, "⇕", "Centrer verticalement", func(): doc.align_selection("center_v"))
	_icon_button(bar, "↔", "Distribuer horizontalement", func(): doc.distribute_selection(true))
	_icon_button(bar, "↕", "Distribuer verticalement", func(): doc.distribute_selection(false))

	bar.add_child(VSeparator.new())
	_breadcrumb = HBoxContainer.new()
	_breadcrumb.add_theme_constant_override("separation", 2)
	bar.add_child(_breadcrumb)

	_status_badges = HBoxContainer.new()
	_status_badges.add_theme_constant_override("separation", 6)
	_status_badges.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status_badges)

	_dirty_lbl = Label.new()
	_dirty_lbl.add_theme_font_size_override("font_size", 11)
	_status_badges.add_child(_dirty_lbl)

	_policy_chip = _make_status_chip("Manuelle")
	_status_badges.add_child(_policy_chip)
	_saved_ago_lbl = _make_status_chip("—")
	_status_badges.add_child(_saved_ago_lbl)
	_autosave_lbl = _make_status_chip("")
	_autosave_lbl.visible = false
	_status_badges.add_child(_autosave_lbl)
	_undo_depth_lbl = _make_status_chip("↶ 0")
	_status_badges.add_child(_undo_depth_lbl)

	_icon_button(bar, "−", "Dézoomer", func(): _engine.zoom_out())
	_zoom_lbl = Label.new()
	_zoom_lbl.text = "100%"
	_zoom_lbl.custom_minimum_size = Vector2(46, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	bar.add_child(_zoom_lbl)
	_icon_button(bar, "+", "Zoomer", func(): _engine.zoom_in())
	_icon_button(bar, "⟲", "Recadrer sur la carte", func():
		if _engine.has_method("request_fit_to_view"):
			_engine.request_fit_to_view()
		else:
			_engine.reset_zoom()
	)
	_icon_button(bar, "🎯", "Recadrer sur la sélection (F)", func(): _focus_selection())
	bar.add_child(VSeparator.new())
	_icon_button(bar, "‹", "Zone précédente du monde", func(): _cycle_world_map(-1))
	_icon_button(bar, "›", "Zone suivante du monde", func(): _cycle_world_map(1))
	var test_btn := Button.new()
	test_btn.text = "▶ Tester"
	test_btn.tooltip_text = "Enregistre puis lance une session de jeu sur cette carte (et son monde si elle en a un)."
	test_btn.add_theme_font_size_override("font_size", 11)
	test_btn.pressed.connect(_test_current_map)
	bar.add_child(test_btn)
	_player_view_btn = Button.new()
	_player_view_btn.toggle_mode = true
	_player_view_btn.text = "👁 Vue joueur"
	_player_view_btn.tooltip_text = "Aperçu de ce que voit le groupe (nuit, lumières, brouillard). Non enregistré."
	_player_view_btn.add_theme_font_size_override("font_size", 11)
	_player_view_btn.toggled.connect(_on_player_view_toggled)
	bar.add_child(_player_view_btn)
	_icon_button(bar, "☰", "Menu éditeur (Échap)", func(): _open_esc_menu())
	_icon_button(bar, "?", "Aide rapide : parcours et raccourcis", func(): _open_help())
	_icon_button(bar, "✓", "Vérifier la carte (tailles, objets, eau, liens)", func(): _validate_map())
	_icon_button(bar, "📷", "Exporter une image PNG de la carte", func(): _open_export_image())

# --- Colonne droite : panneaux -------------------------------------------------

func _bind_docks() -> void:
	_inspector = %Inspector
	_inspector.set_document(doc)
	_inspector.focus_requested.connect(_focus_element)
	_inspector.unlink_requested.connect(func(a, b): doc.unlink_elements(a, b))
	_inspector.child_map_requested.connect(_on_child_map_requested)
	_inspector.open_map_requested.connect(_on_open_map_requested)
	_inspector.link_mode_requested.connect(func(id):
		_link_source = id
		_set_tool(ToolsScript.LINK)
		_set_status("Cliquez l'élément cible pour créer le lien.")
	)

	_outliner = %Outliner
	_outliner.set_document(doc)
	_outliner.focus_requested.connect(_focus_element)

	_world_panel = %Monde
	_world_panel.open_map_requested.connect(_on_open_map_requested)
	if _world_panel.has_method("set_editor_root"):
		_world_panel.set_editor_root(self)
	_world_panel.visibility_changed.connect(func():
		if _world_panel.visible:
			_world_panel.refresh()
	)
	if _right_tabs:
		_right_tabs.tab_changed.connect(_on_right_tab_changed)

	_bind_settings_tab()
	_bind_library_tab()
	_bind_history_tab()

func _on_right_tab_changed(index: int) -> void:
	if _world_panel == null or _right_tabs == null:
		return
	if _right_tabs.get_current_tab_control() == _world_panel:
		_world_panel.refresh()
		if not bool(_world_panel.get("_has_fitted")):
			_world_panel.call_deferred("fit_view")

func _on_viewport_size_changed() -> void:
	_layout_force = true
	_on_editor_resized()

func _on_editor_resized() -> void:
	# Debounce : ignorer les micro-variations (focus SubViewport / clic carte).
	var measured := _measure_layout_size()
	if not _layout_force \
			and absf(measured.x - _layout_applied_size.x) < 6.0 \
			and absf(measured.y - _layout_applied_size.y) < 6.0:
		return
	_apply_responsive_layout()

## Surface client réelle de l'éditeur (jamais un ratio 16:9 déduit).
func _measure_layout_size() -> Vector2:
	var s := size
	if s.x >= 80.0 and s.y >= 60.0:
		return s
	var vp := get_viewport()
	if vp:
		var vr := vp.get_visible_rect().size
		if vr.x >= 80.0 and vr.y >= 60.0:
			return vr
	return s

## Calcule docks et chrome d'après la largeur ET la hauteur client actuelles.
func _apply_responsive_layout() -> void:
	if _split_outer == null:
		return
	var measured := _measure_layout_size()
	var total := measured.x
	var total_h := measured.y
	if total < 80.0:
		_layout_retry += 1
		if _layout_retry < 12:
			call_deferred("_apply_responsive_layout")
		return
	_layout_retry = 0

	if not _layout_force \
			and absf(total - _layout_applied_size.x) < 6.0 \
			and absf(total_h - _layout_applied_size.y) < 6.0:
		return

	# Ratios de la largeur COURANTE — bornes qui restent valides en ultrawide
	# (2560×1080) comme en 16:10 / 3:2 / fenêtre étroite.
	var left_w := clampf(total * 0.14, 150.0, 260.0)
	var right_w := clampf(total * 0.20, 200.0, 380.0)
	if total < 1400.0:
		left_w = clampf(total * 0.15, 150.0, 230.0)
		right_w = clampf(total * 0.22, 190.0, 320.0)
	if total < 1100.0:
		left_w = clampf(total * 0.16, 140.0, 200.0)
		right_w = clampf(total * 0.24, 180.0, 280.0)
	if total < 900.0:
		left_w = clampf(total * 0.18, 130.0, 170.0)
		right_w = clampf(total * 0.26, 160.0, 230.0)

	# Écrans courts (ultrawide bas, 16:10 laptop) : docks un peu plus étroits
	# pour laisser de la hauteur utile au viewport central.
	if total_h > 0.0 and total_h < 720.0:
		left_w = minf(left_w, 200.0)
		right_w = minf(right_w, 280.0)
	if total_h > 0.0 and total_h < 600.0:
		left_w = minf(left_w, 170.0)
		right_w = minf(right_w, 220.0)

	# Toujours laisser de la place au centre + aux deux docks.
	var min_center := clampf(total * 0.28, 120.0, 280.0)
	var max_side := maxf(0.0, (total - min_center) * 0.5)
	left_w = minf(left_w, max_side)
	right_w = minf(right_w, max_side)
	if not _editable:
		left_w = 0.0
		right_w = 0.0

	_dock_left_w = left_w
	_dock_right_w = right_w
	_layout_applied_size = measured
	_layout_force = false

	if _left_scroll:
		_left_scroll.custom_minimum_size = Vector2(left_w if left_w > 1.0 else 0.0, 0)
		_left_scroll.visible = _editable
		_left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _right_tabs:
		_right_tabs.custom_minimum_size = Vector2(right_w if right_w > 1.0 else 0.0, 0)
		_right_tabs.visible = _editable
		_right_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# split_offset depuis la largeur ÉDITEUR mesurée (pas size interne stale).
	if _editable:
		_split_outer.split_offset = int(left_w)
		var center_w := maxf(total - left_w - right_w, min_center)
		_split_inner.split_offset = int(center_w)
	else:
		_split_outer.split_offset = 0
		if _split_inner:
			_split_inner.split_offset = int(maxi(80, int(total)))

	_adapt_tool_chrome(total, total_h)

func _adapt_tool_chrome(total_w: float, total_h: float = 800.0) -> void:
	var btn_w := 46.0
	var btn_h := 38.0
	var cols := 4
	if total_w < 1280.0 or total_h < 720.0:
		btn_w = 42.0
		btn_h = 34.0
	if total_w < 980.0 or total_h < 600.0:
		btn_w = 38.0
		btn_h = 32.0
		cols = 3
	if total_w < 820.0:
		btn_w = 34.0
		btn_h = 30.0
		cols = 3
	for btn in _tool_buttons.values():
		if btn is Button:
			(btn as Button).custom_minimum_size = Vector2(btn_w, btn_h)
	var tool_host := get_node_or_null("%ToolHost")
	if tool_host:
		for child in tool_host.get_children():
			if child is GridContainer:
				(child as GridContainer).columns = cols
	elif _left_panel:
		for child in _left_panel.get_children():
			if child is GridContainer:
				(child as GridContainer).columns = cols
	var mini_h := 110.0
	if total_h < 720.0 or total_w < 1280.0:
		mini_h = 90.0
	if total_h < 600.0:
		mini_h = 70.0
	if _minimap and _minimap.has_method("set_preferred_height"):
		_minimap.call("set_preferred_height", mini_h)
	elif _minimap:
		_minimap.custom_minimum_size = Vector2(0, mini_h)
	if _viewport_frame:
		# Hauteur min du viewport central : proportion de la hauteur client,
		# jamais une constante calée sur 16:9.
		var frame_min_h := clampf(total_h * 0.35, 80.0, 160.0) if total_h > 0.0 else 80.0
		_viewport_frame.custom_minimum_size = Vector2(80, frame_min_h)

func _wrap_scroll(content: Control, tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll

# ===========================================================================
# Onglet « Carte »
# ===========================================================================

func _bind_settings_tab() -> void:
	_settings_panel = %Settings
	_settings_widgets = _settings_panel.widgets
	_settings_panel.import_background_pressed.connect(func(): _file_dialog.popup_centered(Vector2i(760, 500)))
	_settings_panel.import_overlay_pressed.connect(func(): _overlay_dialog.popup_centered(Vector2i(760, 500)))
	_settings_panel.remove_background_pressed.connect(_remove_background)
	_settings_panel.size_changed.connect(_on_size_changed)
	_settings_panel.grid_changed.connect(_on_grid_changed)
	_settings_panel.measure_changed.connect(_on_measure_changed)
	_settings_panel.fog_setting_changed.connect(_on_fog_setting_changed)
	_settings_panel.los_changed.connect(_on_los_changed)
	_settings_panel.fog_hide_all_pressed.connect(func(): doc.set_fog_cells([], "Brouillard total"))
	_settings_panel.fog_reveal_all_pressed.connect(func(): doc.reveal_all_fog())
	_settings_panel.render_style_changed.connect(_on_render_style_changed)
	_settings_panel.ground_mode_changed.connect(_on_ground_mode_changed)
	_settings_panel.water_changed.connect(_on_water_changed)
	_settings_panel.ambient_fx_changed.connect(_on_ambient_fx_changed)
	_settings_panel.perspective_changed.connect(_on_perspective_changed)
	_settings_panel.atmosphere_changed.connect(_on_atmosphere_changed)
	_settings_panel.lighting_changed.connect(_on_lighting_changed)
	_settings_panel.night_mode_changed.connect(_on_night_mode_changed)
	_settings_panel.clear_light_reveal_pressed.connect(func():
		doc.clear_light_reveal()
		_sync_engine()
		_set_status("Zones éclairées effacées.")
	)
	_settings_panel.show_links_toggled.connect(func(on):
		_overlay.show_links = on and not _player_view
		_refresh_overlay()
	)
	_settings_panel.show_ids_toggled.connect(func(on):
		_overlay.show_ids = on
		_refresh_overlay()
	)
	_settings_panel.show_vision_toggled.connect(func(on):
		_overlay.show_vision = on
		_refresh_vision_preview()
	)
	_settings_panel.save_policy_changed.connect(func(policy, label):
		_save_policy = policy
		if _save_policy == SAVE_INTERVAL:
			_autosave_timer.start(_save_interval)
		else:
			_autosave_timer.stop()
		_set_status("Politique de sauvegarde : %s" % label)
		_refresh_status_badges()
		if _esc_menu and _esc_menu.has_method("sync_policy"):
			_esc_menu.sync_policy(_save_policy)
	)
	_settings_panel.export_json_pressed.connect(func(): _export_dialog.popup_centered(Vector2i(760, 500)))
	_settings_panel.import_json_pressed.connect(func(): _import_dialog.popup_centered(Vector2i(760, 500)))


# ===========================================================================
# Onglet « Bibliothèque »
# ===========================================================================

func _bind_library_tab() -> void:
	_library_panel = %Library
	_asset_hint = _library_panel.asset_hint
	_asset_category_row = _library_panel.asset_category_row
	_asset_grid = _library_panel.asset_grid
	_asset_search = _library_panel.asset_search
	_asset_filter_row = _library_panel.asset_filter_row
	if _asset_search != null:
		_asset_search.text_changed.connect(func(text):
			_object3d_search = text.strip_edges().to_lower()
			if _prop_category == "objects3d":
				_refresh_asset_library()
		)
	_effect_list = _library_panel.effect_list
	_template_list = _library_panel.template_list
	_settings_widgets["member_grid"] = _library_panel.member_grid
	_settings_widgets["marker_box"] = _library_panel.marker_box
	_settings_widgets["tile_box"] = _library_panel.tile_box
	_library_panel.import_assets_pressed.connect(func(): _asset_dialog.popup_centered(Vector2i(820, 560)))
	_library_panel.refresh_assets_pressed.connect(_refresh_asset_library)
	_library_panel.member_token_pressed.connect(func(index):
		_member_index = index
		_set_tool(ToolsScript.TOKEN)
	)
	_library_panel.effect_preset_pressed.connect(func(preset_id):
		_effect_preset = preset_id
		_set_tool(ToolsScript.EFFECT)
	)
	_library_panel.trigger_all_effects_pressed.connect(_trigger_all_effects)
	_library_panel.save_template_pressed.connect(_prompt_save_template)
	_library_panel.refresh_templates_pressed.connect(_refresh_templates)

func _bind_history_tab() -> void:
	var panel = %History
	panel.undo_pressed.connect(_do_undo)
	panel.redo_pressed.connect(_do_redo)
	_history_list = panel.history_list

# ===========================================================================
# Dialogues
# ===========================================================================

func _build_dialogs() -> void:
	_file_dialog = _make_file_dialog("Importer une battlemap", FileDialog.FILE_MODE_OPEN_FILE,
		["*.png ; Images PNG", "*.jpg, *.jpeg ; Images JPEG", "*.webp ; Images WebP"])
	_file_dialog.file_selected.connect(_on_background_imported)

	_overlay_dialog = _make_file_dialog("Importer un calque d'élévation", FileDialog.FILE_MODE_OPEN_FILE,
		["*.png ; Images PNG", "*.webp ; Images WebP"])
	_overlay_dialog.file_selected.connect(_on_overlay_imported)

	_export_dialog = _make_file_dialog("Exporter la carte", FileDialog.FILE_MODE_SAVE_FILE, ["*.json ; Carte JSON"])
	_export_dialog.file_selected.connect(_on_export_selected)
	_export_image_dialog = _make_file_dialog("Exporter une image de la carte", FileDialog.FILE_MODE_SAVE_FILE, ["*.png ; Image PNG"])
	_export_image_dialog.file_selected.connect(_on_export_image_selected)

	_import_dialog = _make_file_dialog("Importer une carte", FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Carte JSON"])
	_import_dialog.file_selected.connect(_on_import_selected)

	_asset_dialog = _make_file_dialog("Importer des décors", FileDialog.FILE_MODE_OPEN_FILES,
		["*.png ; Images PNG (fond transparent)", "*.webp ; Images WebP", "*.jpg, *.jpeg ; Images JPEG"])
	_asset_dialog.files_selected.connect(_on_assets_imported)

	_help_dialog = AcceptDialog.new()
	_help_dialog.title = "Aide — éditeur de carte 2.5D"
	add_child(_help_dialog)
	var help_box := VBoxContainer.new()
	help_box.custom_minimum_size = Vector2(680, 540)
	_help_dialog.add_child(help_box)
	var help_text := RichTextLabel.new()
	help_text.bbcode_enabled = true
	help_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_text.text = """[b]Parcours rapide[/b]
1. [b]Carte[/b] : choisis le [i]Type de sol[/i] « Terrain 3D ».
2. Peins le relief (⛰ [b]U[/b]) puis les matières (🟫 [b]Y[/b]) ; règle l'eau et l'ambiance (onglet Carte).
3. Onglet [b]Biblio → 🧊 Objets 3D[/b] : pose bâtiments, toits et façades (aimantation automatique).
4. Onglet [b]Monde[/b] : ajoute des zones (＋ Zone), relie leurs bords, puis [b]▶ Tester[/b].

[b]Astuces[/b]
• Les toits/facades se posent sur le bâtiment le plus proche (case « Aimantation » dans les options de l'outil).
• Un module peut être pivoté : sélection → rotation dans l'inspecteur, ou [b]R[/b] avant la pose.
• Sur le plan Monde : clic sur un point d'accroche = éditer le lien, clic droit = le retirer.
• Toits et façades héritent de la rotation du bâtiment.

[b]Raccourcis[/b]
[b]V[/b] sélection · [b]B[/b] brosse · [b]Y[/b] sol · [b]U[/b] relief · [b]P[/b] décor · [b]R[/b] pivoter
[b]Ctrl+S[/b] enregistrer · [b]Ctrl+Z / Ctrl+Y[/b] annuler/rétablir · [b]Suppr[/b] supprimer
[b]Molette[/b] zoom · [b]Espace+glisser[/b] déplacer la vue · [b]Échap[/b] menu / annuler un tracé
[b]F[/b] cadrer la sélection · [b]M[/b] (session) carte du monde

[b]Aide complète[/b] : docs/GUIDE_CARTE_25D.md et docs/MAP_EDITOR.md"""
	help_box.add_child(help_text)
	_help_dialog.confirmed.connect(func(): _help_dialog.hide())

	_validate_dialog = AcceptDialog.new()
	_validate_dialog.title = "Vérification de la carte"
	add_child(_validate_dialog)
	var validate_box := VBoxContainer.new()
	validate_box.custom_minimum_size = Vector2(560, 360)
	_validate_dialog.add_child(validate_box)
	_validate_text = RichTextLabel.new()
	_validate_text.bbcode_enabled = true
	_validate_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	validate_box.add_child(_validate_text)

	_template_name_dialog = %TemplateNameDialog
	_template_name_input = %TemplateNameInput
	_template_name_dialog.confirmed.connect(_on_template_name_confirmed)

	_esc_menu = %EscMenu
	_esc_menu.save_pressed.connect(save_now)
	_esc_menu.undo_pressed.connect(_do_undo)
	_esc_menu.redo_pressed.connect(_do_redo)
	_esc_menu.fit_view_pressed.connect(func():
		if _engine and _engine.has_method("request_fit_to_view"):
			_engine.request_fit_to_view()
		elif _engine:
			_engine.reset_zoom()
	)
	_esc_menu.clear_selection_pressed.connect(func(): doc.clear_selection())
	_esc_menu.import_json_pressed.connect(func(): _import_dialog.popup_centered(Vector2i(760, 500)))
	_esc_menu.export_json_pressed.connect(func(): _export_dialog.popup_centered(Vector2i(760, 500)))
	_esc_menu.save_policy_selected.connect(func(policy, label):
		_save_policy = policy
		if _save_policy == SAVE_INTERVAL:
			_autosave_timer.start(_save_interval)
		else:
			_autosave_timer.stop()
		_set_status("Sauvegarde : %s" % label)
		_refresh_status_badges()
	)
	_esc_menu.sync_policy(_save_policy)

func _make_file_dialog(title: String, mode: int, filters: Array) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(filters)
	dialog.ok_button_text = "Enregistrer" if mode == FileDialog.FILE_MODE_SAVE_FILE else "Ouvrir"
	dialog.cancel_button_text = "Annuler"
	add_child(dialog)
	return dialog

# ===========================================================================
# Machine à états d'outils
# ===========================================================================

func _set_tool(tool_id: String) -> void:
	_tool = tool_id
	for key in _tool_buttons:
		(_tool_buttons[key] as Button).button_pressed = key == tool_id
	if tool_id != ToolsScript.LINK:
		_link_source = ""
	if tool_id != ToolsScript.ZONE_POLY:
		_overlay.polygon_points.clear()
	if tool_id != ToolsScript.MEASURE and _overlay:
		_overlay.measure_active = false
		_overlay.measure_from = Vector2.ZERO
		_overlay.measure_to = Vector2.ZERO
	_rebuild_tool_options()
	_update_hint()
	_refresh_overlay()

func _on_pointer_pressed(grid: Vector2, screen: Vector2, button: int, mods: Dictionary) -> void:
	if not _editable:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_handle_right_click(grid)
		return
	_press_start_grid = grid
	_press_start_screen = screen
	_press_moved = false
	_painted_cells.clear()

	if _space_held or _tool == ToolsScript.PAN:
		_press_mode = "pan"
		_engine.begin_view_pan(screen)
		return

	var wants_select := _tool == ToolsScript.SELECT or bool(mods.get("ctrl", false)) or bool(mods.get("shift", false))
	if wants_select:
		_begin_select_or_move(grid, screen, mods)
		return

	if ToolsScript.is_pose_tool(_tool):
		_place_pose_element(_snap(grid))
		_press_mode = "none"
		return
	if ToolsScript.is_drag_tool(_tool):
		_press_mode = "draw"
		_overlay.drag_preview = {
			"mode": _drag_preview_mode(),
			"from": _snap(grid),
			"to": _snap(grid),
		}
		_refresh_overlay()
		return
	if _tool == ToolsScript.ZONE_POLY:
		_overlay.polygon_points.append(_snap(grid))
		_press_mode = "none"
		_refresh_overlay()
		return
	if _tool == ToolsScript.PAINT:
		_press_mode = "paint"
		_paint_terrain(grid)
		return
	if _tool == ToolsScript.TERRAIN_HEIGHT:
		_press_mode = "relief"
		doc.begin_transaction()
		_paint_relief(grid)
		return
	if _tool == ToolsScript.GROUND_MATERIAL:
		_press_mode = "ground_material"
		doc.begin_transaction()
		_paint_ground_material(grid)
		return
	if _tool == ToolsScript.BUCKET:
		doc.bucket_fill(int(roundf(grid.x)), int(roundf(grid.y)), _paint_tile)
		_press_mode = "none"
		return
	if _tool == ToolsScript.FOG_REVEAL or _tool == ToolsScript.FOG_HIDE:
		_press_mode = "paint"
		_paint_fog(grid)
		return
	if _tool == ToolsScript.ERASE:
		_erase_at(screen)
		_press_mode = "none"
		return
	if _tool == ToolsScript.LINK:
		_handle_link_click(screen)
		_press_mode = "none"
		return
	if _tool == ToolsScript.TEMPLATE:
		_place_template(_snap(grid))
		_press_mode = "none"
		return
	_press_mode = "none"

func _begin_select_or_move(grid: Vector2, screen: Vector2, mods: Dictionary) -> void:
	# Poignées d'un décor déjà sélectionné : resize / rotate avant le hit-test.
	var handle: Dictionary = _overlay.handle_at_screen(screen)
	if not handle.is_empty():
		var hid := str(handle.get("id", ""))
		var handle_elem: Dictionary = doc.get_element(hid)
		if not handle_elem.is_empty():
			doc.select_only(hid)
			_press_mode = str(handle.get("kind", "resize"))
			_drag_ids = [hid]
			var display: Dictionary = handle_elem.get("display", {}) if handle_elem.get("display") is Dictionary else {}
			_handle_state = {
				"id": hid,
				"corner": int(handle.get("corner", 0)),
				"x": float(handle_elem.get("x", 0.0)),
				"y": float(handle_elem.get("y", 0.0)),
				"w": float(handle_elem.get("w", 1.0)),
				"h": float(handle_elem.get("h", 1.0)),
				"rotation": float(display.get("rotation", 0.0)),
				"start_grid": grid,
			}
			_refresh_overlay()
			return

	var additive := bool(mods.get("ctrl", false)) or bool(mods.get("shift", false))
	# GIMP / Meownopoly : si le clic touche la sélection courante, on déplace
	# celle-ci même si un autre élément est empilé par-dessus.
	if not additive and not doc.selection().is_empty():
		var sticky: String = _overlay.selected_element_at_screen(screen)
		if not sticky.is_empty():
			var movable: Array = doc.movable_selection_ids()
			if movable.is_empty():
				_press_mode = "none"
				_set_status("Sélection verrouillée — déverrouillez l'élément ou le calque.")
				_refresh_overlay()
				return
			if bool(mods.get("alt", false)):
				doc.duplicate_selection()
				movable = doc.movable_selection_ids()
			_start_move_drag(movable)
			return

	var hit: String = _overlay.element_at_screen(screen)
	if hit.is_empty():
		var blocked: String = _overlay.blocked_element_at_screen(screen)
		if not blocked.is_empty() and not additive:
			_press_mode = "none"
			_set_status("Élément verrouillé — impossible de le sélectionner.")
			_refresh_overlay()
			return
		_press_mode = "band"
		_overlay.band_active = true
		_overlay.band_start = screen
		_overlay.band_end = screen
		# Ctrl/Maj : le rectangle s'ajoute à la sélection existante.
		_band_base_selection = doc.selection() if additive else []
		if not additive:
			doc.clear_selection()
		_refresh_overlay()
		return
	if bool(mods.get("ctrl", false)):
		doc.toggle_selection(hit)
	elif bool(mods.get("shift", false)):
		doc.add_to_selection([hit])
	elif not doc.is_selected(hit):
		doc.select_only(hit)
	doc.expand_selection_to_groups()
	if bool(mods.get("alt", false)):
		doc.duplicate_selection()
	var movable_hit: Array = doc.movable_selection_ids()
	if movable_hit.is_empty():
		_press_mode = "none"
		_set_status("Sélection verrouillée — déverrouillez l'élément ou le calque.")
		_refresh_overlay()
		return
	_start_move_drag(movable_hit)

func _start_move_drag(ids: Array) -> void:
	_press_mode = "move"
	_drag_ids = ids.duplicate()
	_drag_origins.clear()
	for id_variant in _drag_ids:
		var elem: Dictionary = doc.get_element(str(id_variant))
		_drag_origins[str(id_variant)] = Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	_refresh_overlay()

func _on_pointer_moved(grid: Vector2, screen: Vector2, mods: Dictionary) -> void:
	_overlay.hover_grid = grid
	_overlay.hover_valid = _in_bounds(grid)
	_update_status_position(grid)
	match _press_mode:
		"pan":
			_engine.update_view_pan(screen)
		"band":
			_overlay.band_end = screen
			_press_moved = true
			var ids: Array = _band_base_selection.duplicate()
			for id in _overlay.elements_in_band(Rect2(_overlay.band_start, screen - _overlay.band_start)):
				if not ids.has(id):
					ids.append(id)
			doc.set_selection(ids)
		"move":
			_press_moved = true
			var delta := grid - _press_start_grid
			var moved_light := false
			for id_variant in _drag_ids:
				var id := str(id_variant)
				var origin: Vector2 = _drag_origins.get(id, Vector2.ZERO)
				var target := _snap(origin + delta)
				doc.set_live_position(id, target.x, target.y)
				_engine.set_element_position(id, target.x, target.y)
				if str(doc.get_element(id).get("kind", "")) == DocumentScript.KIND_LIGHT:
					moved_light = true
			if moved_light:
				_refresh_light_mask_live()
		"resize":
			_press_moved = true
			_apply_handle_resize(grid)
		"rotate":
			_press_moved = true
			_apply_handle_rotate(grid)
		"draw":
			_press_moved = true
			var to := _snap(grid)
			if bool(mods.get("shift", false)) and _tool == ToolsScript.WALL:
				to = _constrain_axis(_press_start_grid, to)
			_overlay.drag_preview["to"] = to
		"paint":
			if _tool == ToolsScript.PAINT:
				_paint_terrain(grid)
			else:
				_paint_fog(grid)
		"relief":
			_paint_relief(grid)
		"ground_material":
			_paint_ground_material(grid)
	_refresh_ghost()
	_refresh_overlay()

func _on_pointer_released(grid: Vector2, _screen: Vector2, button: int, _mods: Dictionary) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var was_live := _press_mode in ["move", "resize", "rotate"]
	match _press_mode:
		"pan":
			_engine.end_view_pan()
		"band":
			_overlay.band_active = false
			_band_base_selection.clear()
		"move":
			if _press_moved:
				doc.commit_live_edit(_drag_ids, "Déplacement")
				_rebuild_lights_illumination(_drag_ids)
				_sync_engine()
			_drag_ids.clear()
			_drag_origins.clear()
		"resize":
			if _press_moved:
				doc.commit_live_edit(_drag_ids, "Redimensionnement")
				_rebuild_lights_illumination(_drag_ids)
				_sync_engine()
			_drag_ids.clear()
			_handle_state.clear()
		"rotate":
			if _press_moved:
				doc.commit_live_edit(_drag_ids, "Rotation")
				_sync_engine()
			_drag_ids.clear()
			_handle_state.clear()
		"draw":
			_finish_draw(_snap(grid))
		"paint":
			_painted_cells.clear()
		"relief":
			doc.commit_transaction()
			_sync_engine()
			_set_status("Relief appliqué — les objets 3D s'adaptent à la hauteur.")
		"ground_material":
			doc.commit_transaction()
			_sync_engine()
			_set_status("Sol peint — matière enregistrée avec la carte.")
	_press_mode = "none"
	_overlay.drag_preview.clear()
	if was_live:
		_refresh_panels()
	_refresh_overlay()

func _handle_right_click(grid: Vector2) -> void:
	if not _overlay.polygon_points.is_empty():
		_close_polygon()
		return
	if _press_mode != "none":
		_cancel_action()
		return
	# Clic droit sur le vide : recadrage rapide façon « focus ».
	if _in_bounds(grid):
		_set_status("Position (%.1f, %.1f) — %s" % [grid.x, grid.y, doc.get_tile_at(int(roundf(grid.x)), int(roundf(grid.y)))])

func _cancel_action() -> void:
	if _press_mode in ["move", "resize", "rotate"] and not _drag_ids.is_empty():
		doc.revert_live_edit(_drag_ids)
		_sync_engine()
	_press_mode = "none"
	_drag_ids.clear()
	_drag_origins.clear()
	_handle_state.clear()
	_overlay.clear_transient()
	_link_source = ""
	_refresh_panels()
	_set_status("Action annulée.")

func _apply_handle_resize(grid: Vector2) -> void:
	if _handle_state.is_empty():
		return
	var id := str(_handle_state.get("id", ""))
	var center := Vector2(float(_handle_state.get("x", 0.0)), float(_handle_state.get("y", 0.0)))
	var start: Vector2 = _handle_state.get("start_grid", _press_start_grid)
	var start_dist := maxf(0.15, start.distance_to(center))
	var scale := clampf(grid.distance_to(center) / start_dist, 0.15, 8.0)
	var w := maxf(0.25, float(_handle_state.get("w", 1.0)) * scale)
	var h := maxf(0.25, float(_handle_state.get("h", 1.0)) * scale)
	var fields: Dictionary = {"w": w, "h": h}
	var kind := str(doc.get_element(id).get("kind", ""))
	if kind == DocumentScript.KIND_MESH:
		# Objet 3D : la poignée de coin dimensionne l'objet (X/Z) proportionnellement.
		var elem: Dictionary = doc.get_element(id)
		var base_w := maxf(0.01, float(_handle_state.get("w", 1.0)))
		var ratio := w / base_w
		fields["sizeX"] = w
		fields["sizeZ"] = h
		if float(elem.get("sizeY", 0.0)) > 0.0:
			fields["sizeY"] = maxf(0.1, float(elem.get("sizeY", 1.0)) * ratio)
		doc.set_live_fields(id, fields)
		return
	if str(doc.get_element(id).get("kind", "")) == DocumentScript.KIND_LIGHT:
		var radius := maxf(0.5, maxf(w, h) * 0.5)
		fields["radius"] = radius
		doc.set_live_fields(id, fields)
		if _engine and _engine.has_method("set_element_light_radius"):
			_engine.set_element_light_radius(id, radius)
		_refresh_light_mask_live()
		return
	doc.set_live_fields(id, fields)

func _apply_handle_rotate(grid: Vector2) -> void:
	if _handle_state.is_empty():
		return
	var id := str(_handle_state.get("id", ""))
	var center := Vector2(float(_handle_state.get("x", 0.0)), float(_handle_state.get("y", 0.0)))
	var start: Vector2 = _handle_state.get("start_grid", _press_start_grid)
	var start_angle := (start - center).angle()
	var cur_angle := (grid - center).angle()
	var rot := float(_handle_state.get("rotation", 0.0)) + rad_to_deg(cur_angle - start_angle)
	doc.set_live_fields(id, {"display": {"rotation": rot}})

func _constrain_axis(from: Vector2, to: Vector2) -> Vector2:
	if absf(to.x - from.x) >= absf(to.y - from.y):
		return Vector2(to.x, from.y)
	return Vector2(from.x, to.y)

func _drag_preview_mode() -> String:
	if _tool == ToolsScript.WALL or _tool == ToolsScript.MEASURE:
		return "line"
	return "rect"

func _finish_draw(to: Vector2) -> void:
	var from: Vector2 = _press_start_grid
	if _overlay.drag_preview.has("to"):
		to = _overlay.drag_preview["to"]
	if _tool == ToolsScript.AREA:
		_create_area(from, to)
	elif _tool == ToolsScript.ZONE_RECT:
		_create_rect_zone(from, to)
	elif _tool == ToolsScript.PLATFORM:
		_create_platform(from, to)
	elif _tool == ToolsScript.WALL:
		_create_wall(from, to)
	elif _tool == ToolsScript.MEASURE:
		var cells := from.distance_to(to)
		if cells < 0.15:
			_overlay.measure_active = false
			_set_status("Mesure trop courte.")
			_refresh_overlay()
			return
		_overlay.measure_active = true
		_overlay.measure_from = from
		_overlay.measure_to = to
		var measure: Dictionary = doc.map_data.get("measure", {}) if doc.map_data.get("measure") is Dictionary else {}
		_set_status("Distance : %.2f cases · %.2f %s" % [
			cells, cells * float(measure.get("perCell", 1.5)), measure.get("unit", "m")])
		_refresh_overlay()
		return
	_sync_engine()

# ===========================================================================
# Création d'éléments
# ===========================================================================

func _snap(v: Vector2) -> Vector2:
	return ToolsScript.snap_vector(v, _snap_mode)

func _in_bounds(grid: Vector2) -> bool:
	var w := float(doc.map_data.get("width", 16))
	var h := float(doc.map_data.get("height", 12))
	return grid.x >= -0.5 and grid.y >= -0.5 and grid.x <= w and grid.y <= h

func _place_pose_element(grid: Vector2) -> void:
	if not _in_bounds(grid):
		return
	if _tool == ToolsScript.TOKEN:
		_create_token(grid)
	elif _tool == ToolsScript.MARKER:
		_create_marker(grid)
	elif _tool == ToolsScript.EFFECT:
		_create_effect(grid)
	elif _tool == ToolsScript.ZONE:
		_create_circle_zone(grid)
	elif _tool == ToolsScript.NOTE:
		_create_note(grid)
	elif _tool == ToolsScript.LIGHT:
		_create_light(grid)
	elif _tool == ToolsScript.PROP:
		_create_prop(grid)
	elif _tool == ToolsScript.MESH:
		_create_mesh(grid)
	_sync_engine()

func _create_token(grid: Vector2) -> void:
	var label := _token_label
	if label.is_empty():
		var prefix := "Token"
		if _token_kind == "npc":
			prefix = "PNJ"
		elif _token_kind == "monster":
			prefix = "Monstre"
		label = "%s %d" % [prefix, doc.count_of_kind(DocumentScript.KIND_TOKEN) + 1]
	var color: String = str(MapData.MEMBER_COLOR_HEX[_member_index % MapData.MEMBER_COLOR_HEX.size()]) \
		if _token_kind == "member" else ("#d9b45a" if _token_kind == "npc" else "#b3513f")
	var emoji: String = str(MapData.MEMBER_PLAYER_EMOJIS_GENERAL[_member_index % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()]) \
		if _token_kind == "member" else ("🧑" if _token_kind == "npc" else "👹")
	var portrait := _default_token_portrait() if _token_kind == "member" else ""
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": _token_size, "h": _token_size,
		"tokenKind": _token_kind,
		"label": label,
		"emoji": emoji,
		"color": color,
		"image": portrait,
		"scale": maxf(_token_size, 1.0),
		"layer": 4,
	}, DocumentScript.KIND_TOKEN, "Token")
	var elem: Dictionary = doc.get_element(id)
	if _token_kind == "member":
		elem["memberId"] = "editor-mock-%d" % _member_index
		elem["memberIndex"] = _member_index
	elif _token_kind == "npc" and not _token_dialogue.is_empty():
		elem["dialogue"] = _token_dialogue
	doc.select_only(id)

func _default_token_portrait() -> String:
	var known: Array = MapData.list_token_images()
	if not known.is_empty():
		return str(known[0])
	var shipped := "res://assets/portraits/voleur_kael.png"
	if ResourceLoader.exists(shipped) or FileAccess.file_exists(ProjectSettings.globalize_path(shipped)):
		var imported := MapData.import_token_image(ProjectSettings.globalize_path(shipped))
		return imported if not imported.is_empty() else shipped
	return ""

func _create_marker(grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"markerType": _marker_type,
		"label": MapData.get_marker_label(_marker_type),
		"layer": 3,
	}, DocumentScript.KIND_MARKER, "Marqueur")
	doc.select_only(id)

func _create_effect(grid: Vector2) -> void:
	var preset := MapEffectPresetsScript.get_preset(_effect_preset)
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": _effect_radius * 2.0, "h": _effect_radius * 2.0,
		"type": "particles",
		"preset": _effect_preset,
		"radius": _effect_radius,
		"triggered": true,
		"label": str(preset.get("label", _effect_preset)),
		"layer": 3,
	}, DocumentScript.KIND_EFFECT, "Effet")
	doc.select_only(id)

func _create_circle_zone(grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"shape": "circle",
		"radius": _zone_radius,
		"w": _zone_radius * 2.0, "h": _zone_radius * 2.0,
		"label": _zone_label,
		"color": "#c9a227",
		"layer": 3,
	}, DocumentScript.KIND_ZONE, "Zone")
	doc.select_only(id)

func _create_rect_zone(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	if rect.size.x < 0.25 or rect.size.y < 0.25:
		return
	var id: String = doc.add_element({
		"x": rect.get_center().x, "y": rect.get_center().y,
		"shape": "rect",
		"w": rect.size.x, "h": rect.size.y,
		"radius": maxf(rect.size.x, rect.size.y) * 0.5,
		"label": _zone_label,
		"color": "#c9a227",
		"layer": 3,
	}, DocumentScript.KIND_ZONE, "Zone rectangulaire")
	doc.select_only(id)

## Un lieu délimite une portion de la carte illustrée : une taverne, une place,
## une sortie de village. Il porte un nom affiché en cartouche et peut ouvrir
## sa propre carte, où l'on place réellement les personnages.
func _create_area(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	if rect.size.x < 0.5 or rect.size.y < 0.5:
		rect = Rect2(from - Vector2(1.5, 1.5), Vector2(3.0, 3.0))
	var id: String = doc.add_element({
		"x": rect.get_center().x, "y": rect.get_center().y,
		"w": rect.size.x, "h": rect.size.y,
		"shape": "rect",
		"category": _area_category,
		"label": _area_label if not _area_label.is_empty() else "Nouveau lieu",
		"targetMapId": "",
		"showCallout": true,
		"labelOffset": {"x": 0.0, "y": -(rect.size.y * 0.5 + 0.8)},
		"layer": 5,
	}, DocumentScript.KIND_AREA, "Lieu")
	doc.select_only(id)
	if _right_tabs:
		_right_tabs.current_tab = 0

func _create_platform(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	if rect.size.x < 0.5 or rect.size.y < 0.5:
		rect.size = Vector2(3, 3)
	var id: String = doc.add_element({
		"x": rect.position.x, "y": rect.position.y,
		"w": maxf(1.0, roundf(rect.size.x)), "h": maxf(1.0, roundf(rect.size.y)),
		"elevation": 1.0,
		"opacity": 0.38,
		"tint": "#8a7a60",
		"label": "Plateforme",
		"layer": 2,
	}, DocumentScript.KIND_PLATFORM, "Plateforme")
	doc.select_only(id)

func _create_wall(from: Vector2, to: Vector2) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.4:
		return
	var id: String = doc.add_element({
		"x": (from.x + to.x) * 0.5, "y": (from.y + to.y) * 0.5,
		"w": length, "h": 0.25,
		"height": 1.4,
		"color": "#4a423a",
		"blocksSight": true,
		"label": "Mur",
		"layer": 2,
		"display": {"rotation": rad_to_deg(delta.angle())},
	}, DocumentScript.KIND_WALL, "Mur")
	doc.select_only(id)

## Pose un décor à l'échelle de son asset : une maison garde ses proportions,
## on ne se retrouve pas avec une charrette carrée.
func _create_prop(grid: Vector2) -> void:
	if _prop_asset.is_empty():
		_set_status("Choisissez d'abord un décor dans la bibliothèque (onglet Biblio).")
		return
	var ratio := AssetLibraryScript.aspect_ratio(_prop_asset)
	var height := maxf(0.25, _prop_size)
	var width := maxf(0.25, height * ratio)
	var asset := AssetLibraryScript.get_asset(_prop_asset)
	# Carte illustrée top-down : forcer à plat pour rester visible (sinon tranche).
	var standing := _prop_standing and not MapRenderStyleScript.prefer_flat_props(doc.map_data)
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": width, "h": height,
		"asset": _prop_asset,
		"standing": standing,
		"billboard": standing,
		"lit": false,
		"elevation": 0.0,
		"label": str(asset.get("name", _prop_asset.get_file().get_basename())),
		"layer": 1,
		"display": {"rotation": _prop_rotation},
	}, DocumentScript.KIND_PROP, "Décor")
	doc.select_only(id)

## Pose un objet 3D générique (mesh GLB) sur la carte 2.5D.
func _create_mesh(grid: Vector2) -> void:
	if _mesh_asset.is_empty():
		_set_status("Choisissez d'abord un objet 3D dans la bibliothèque (onglet Biblio → Objets 3D).")
		return
	var asset := AssetLibraryScript.get_object3d_asset(_mesh_asset)
	var bounds := _mesh_bounds_cells(_mesh_asset)
	var footprint := Vector2(maxf(0.5, bounds.x), maxf(0.5, bounds.z))
	var placement := {"x": grid.x, "y": grid.y, "elevation": 0.0, "rotation": _mesh_rotation}
	if _mesh_snap_modules:
		var snapped := _snap_module_placement(_mesh_asset, grid)
		if not snapped.is_empty():
			placement = snapped
	var id: String = doc.add_element({
		"x": placement["x"], "y": placement["y"],
		"w": footprint.x, "h": footprint.y,
		"sizeX": footprint.x, "sizeY": maxf(0.2, bounds.y), "sizeZ": footprint.y,
		"asset": _mesh_asset,
		"elevation": float(placement.get("elevation", 0.0)),
		"followTerrain": true,
		"tiltToTerrain": _mesh_tilt_default(asset),
		"label": str(asset.get("name", _mesh_asset.get_file().get_basename())),
		"layer": 1,
		"display": {"rotation": float(placement.get("rotation", _mesh_rotation)), "scale": _mesh_scale},
	}, DocumentScript.KIND_MESH, "Objet 3D")
	doc.select_only(id)
	if placement.has("snapped_to"):
		_set_status("Module aimanté sur « %s »." % str(placement.get("snapped_to", "bâtiment")))

## Positionne automatiquement un module de toit/façade sur le bâtiment le plus
## proche (manifeste Blender : anchor `roof` / `wall`, dimensions, hauteur).
func _snap_module_placement(asset_path: String, grid: Vector2) -> Dictionary:
	var meta: Dictionary = AssetLibraryScript.get_object3d_meta(asset_path)
	if meta.is_empty():
		return {}
	var anchor := str(meta.get("anchor", "base"))
	if anchor != "roof" and anchor != "wall":
		return {}
	var best: Dictionary = {}
	var best_distance := 999.0
	for elem_variant in doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		var other_path := str(elem.get("asset", ""))
		var other_meta: Dictionary = AssetLibraryScript.get_object3d_meta(other_path)
		if other_meta.is_empty():
			continue
		if str(other_meta.get("anchor", "base")) != "base":
			continue
		if str(other_meta.get("category", "")) != "buildings":
			continue
		var other_name := str(other_meta.get("name", "")).to_lower()
		if other_name.begins_with("toit") or other_name.begins_with("cheminee") \
				or other_name.begins_with("clocheton") or other_name.begins_with("pnj_"):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var distance := center.distance_to(grid)
		if distance < best_distance:
			best_distance = distance
			best = elem
	if best.is_empty() or best_distance > 9.0:
		return {}
	var dims: Array = meta.get("dimensions_cells", [1.0, 1.0, 0.8])
	var mod_depth := float(dims[1]) if dims.size() > 1 else 1.0
	var mod_height := float(dims[2]) if dims.size() > 2 else 0.8
	var building_h := float(best.get("sizeY", 1.5))
	var building_h_foot := float(best.get("h", 1.0))
	var label := str(best.get("label", best.get("asset", "")))
	var building_display: Dictionary = best.get("display", {}) if best.get("display") is Dictionary else {}
	var building_rotation := float(building_display.get("rotation", 0.0))
	if anchor == "roof":
		return {
			"x": float(best.get("x", grid.x)),
			"y": float(best.get("y", grid.y)),
			"elevation": maxf(0.2, building_h - mod_height * 0.2),
			"rotation": building_rotation,
			"snapped_to": label,
		}
	# Façade : sur l'avant du bâtiment (côté +Z local, donc suit sa rotation).
	var front_rad := deg_to_rad(building_rotation)
	var front_dir := Vector2(-sin(front_rad), cos(front_rad))
	var facade_offset := building_h_foot * 0.5 + mod_depth * 0.5
	return {
		"x": float(best.get("x", grid.x)) + front_dir.x * facade_offset,
		"y": float(best.get("y", grid.y)) + front_dir.y * facade_offset,
		"elevation": 0.0,
		"rotation": building_rotation,
		"snapped_to": label,
	}

## Dimensions (en cases) de la boîte englobante du GLB, échelle de pose incluse.
func _mesh_bounds_cells(asset_path: String, scale_factor: float = -1.0) -> Vector3:
	if asset_path.is_empty():
		return Vector3.ZERO
	var factor := _mesh_scale if scale_factor < 0.0 else scale_factor
	var cache_key := "b:%s|%.3f" % [asset_path, factor]
	if _mesh_footprint_cache.has(cache_key):
		return _mesh_footprint_cache[cache_key]
	var out := Vector3.ZERO
	var inst: Node3D = AssetLibraryScript.instantiate_object3d_scene(asset_path)
	if inst != null:
		var bounds: Array = []
		_collect_mesh_aabbs(inst, Transform3D.IDENTITY, bounds)
		var first := true
		var merged := AABB()
		for aabb_variant in bounds:
			var aabb: AABB = aabb_variant
			merged = aabb if first else merged.merge(aabb)
			first = false
		if not first and merged.size.length() > 0.0:
			out = merged.size * factor
		inst.free()
	_mesh_footprint_cache[cache_key] = out
	return out

## Empreinte au sol (en cases) déduite de la boîte englobante du GLB : le MJ
## n'a aucune dimension à saisir et la sélection colle au modèle.
func _mesh_footprint_cells(asset_path: String, scale_factor: float = -1.0) -> Vector2:
	var bounds := _mesh_bounds_cells(asset_path, scale_factor)
	if bounds == Vector3.ZERO:
		return Vector2.ONE
	return Vector2(maxf(0.5, bounds.x), maxf(0.5, bounds.z))

func _collect_mesh_aabbs(node: Node, xform: Transform3D, out: Array) -> void:
	var next_xform := xform
	if node is Node3D:
		next_xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		out.append(next_xform * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, next_xform, out)

func _create_note(grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"label": "Note",
		"text": "",
		"layer": 5,
	}, DocumentScript.KIND_NOTE, "Note")
	doc.select_only(id)
	if _right_tabs:
		_right_tabs.current_tab = 0

func _create_light(grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"radius": _light_place_radius,
		"energy": 1.6,
		"color": "#ffb35c",
		"elevation": 0.6,
		"flicker": true,
		"label": "Lumière",
		"layer": 2,
	}, DocumentScript.KIND_LIGHT, "Lumière")
	doc.select_only(id)
	# Halo = position courante des lumières (rebuild, pas d'accumulation).
	doc.rebuild_light_reveal_from_lights("Pose lumière")
	if MapData.is_night_mode(doc.map_data):
		_set_status("Mode nuit — les lumières révèlent le jour")
	_sync_engine()

func _close_polygon() -> void:
	var points: Array = _overlay.polygon_points.duplicate()
	_overlay.polygon_points.clear()
	if points.size() < 3:
		_refresh_overlay()
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var serialized: Array = []
	for point_variant in points:
		var point: Vector2 = point_variant
		min_p.x = minf(min_p.x, point.x)
		min_p.y = minf(min_p.y, point.y)
		max_p.x = maxf(max_p.x, point.x)
		max_p.y = maxf(max_p.y, point.y)
		serialized.append({"x": point.x, "y": point.y})
	var center := (min_p + max_p) * 0.5
	var id: String = doc.add_element({
		"x": center.x, "y": center.y,
		"shape": "polygon",
		"points": serialized,
		"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
		"radius": maxf(max_p.x - min_p.x, max_p.y - min_p.y) * 0.5,
		"label": _zone_label,
		"color": "#7ad9a0",
		"layer": 3,
	}, DocumentScript.KIND_ZONE, "Zone libre")
	doc.select_only(id)
	_sync_engine()

func _erase_at(screen: Vector2) -> void:
	var hit: String = _overlay.element_at_screen(screen)
	if hit.is_empty():
		return
	doc.remove_element(hit)
	_sync_engine()

func _handle_link_click(screen: Vector2) -> void:
	var hit: String = _overlay.element_at_screen(screen)
	if hit.is_empty():
		_link_source = ""
		_set_status("Lien annulé : aucun élément sous le curseur.")
		return
	if _link_source.is_empty():
		_link_source = hit
		doc.select_only(hit)
		_set_status("Source sélectionnée. Cliquez la cible.")
		return
	if doc.link_elements(_link_source, hit):
		_set_status("Lien créé.")
	else:
		_set_status("Lien impossible (déjà existant ou identique).")
	_link_source = ""
	_refresh_overlay()

func _paint_terrain(grid: Vector2) -> void:
	var w: int = int(doc.map_data.get("width", 16))
	var cells: Dictionary = {}
	var cx := int(roundf(grid.x))
	var cy := int(roundf(grid.y))
	for dy in range(-_brush_size, _brush_size + 1):
		for dx in range(-_brush_size, _brush_size + 1):
			var x := cx + dx
			var y := cy + dy
			if doc.get_tile_at(x, y).is_empty():
				continue
			var key := str(y * w + x)
			if _painted_cells.has(key):
				continue
			_painted_cells[key] = true
			cells[key] = _paint_tile
	if not cells.is_empty():
		doc.paint_tiles(cells)
		_sync_engine()

func _paint_relief(grid: Vector2) -> void:
	doc.paint_terrain_brush(grid, _relief_radius, _relief_strength, _relief_mode, "Relief")
	# Aperçu fluide : le moteur reconfigure seulement le sol + les objets posés.
	if _engine != null and _engine.has_method("refresh_terrain"):
		_engine.call("refresh_terrain", doc.map_data)
	_refresh_overlay()

## Peint la matière du sol (herbe / terre / pierre) sous le curseur.
func _paint_ground_material(grid: Vector2) -> void:
	doc.paint_terrain_material_brush(grid, _material_radius, _material_id, "Sol")
	if _engine != null and _engine.has_method("refresh_terrain"):
		_engine.call("refresh_terrain", doc.map_data)
	_refresh_overlay()

func _paint_fog(grid: Vector2) -> void:
	var cx := int(roundf(grid.x))
	var cy := int(roundf(grid.y))
	var cells: Array = []
	for dy in range(-_fog_brush, _fog_brush + 1):
		for dx in range(-_fog_brush, _fog_brush + 1):
			if absi(dx) + absi(dy) > _fog_brush:
				continue
			cells.append("%d,%d" % [cx + dx, cy + dy])
	if _tool == ToolsScript.FOG_REVEAL:
		doc.reveal_fog(cells)
	else:
		doc.hide_fog(cells)
	_sync_engine()

# ===========================================================================
# Templates
# ===========================================================================

func _prompt_save_template() -> void:
	if doc.selection().is_empty():
		_set_status("Sélectionnez d'abord des éléments à enregistrer.")
		return
	_template_name_input.text = ""
	_template_name_dialog.popup_centered(Vector2i(420, 160))

func _on_template_name_confirmed() -> void:
	var name := _template_name_input.text.strip_edges()
	if name.is_empty():
		return
	var elements: Array = []
	for id in doc.selection():
		elements.append(doc.get_element(str(id)))
	if TemplatesScript.save_template(name, elements):
		_set_status("Template « %s » enregistré (%d éléments)." % [name, elements.size()])
		_refresh_templates()
	else:
		_set_status("Échec de l'enregistrement du template.")

## Bibliothèque de décors : une rangée de catégories, puis les vignettes.
## Cliquer une vignette arme l'outil Décor avec cet asset.
func _refresh_asset_library() -> void:
	if _asset_category_row == null or _asset_grid == null:
		return
	for child in _asset_category_row.get_children():
		child.queue_free()
	for child in _asset_grid.get_children():
		child.queue_free()
	var objects_mode := _prop_category == "objects3d"
	if _asset_search != null:
		_asset_search.visible = objects_mode
	if _asset_filter_row != null:
		_asset_filter_row.visible = objects_mode
		for child in _asset_filter_row.get_children():
			child.queue_free()

	# Catégorie spéciale en tête : objets 3D livrés (GLB exportés de Blender).
	var mesh_btn := Button.new()
	mesh_btn.text = "🧊 Objets 3D"
	mesh_btn.toggle_mode = true
	mesh_btn.button_pressed = _prop_category == "objects3d"
	mesh_btn.add_theme_font_size_override("font_size", 11)
	mesh_btn.tooltip_text = "Meshes 3D posables (bâtiments, tours, ponts, rochers…)\nExport Blender : voir docs/BLENDER_PIPELINE.md"
	mesh_btn.pressed.connect(func():
		_prop_category = "objects3d"
		_refresh_asset_library()
	)
	_asset_category_row.add_child(mesh_btn)

	for category_variant in AssetLibraryScript.CATEGORIES:
		var category: Dictionary = category_variant
		var category_id := str(category["id"])
		var btn := Button.new()
		btn.text = "%s %s" % [category["icon"], category["label"]]
		btn.toggle_mode = true
		btn.button_pressed = category_id == _prop_category
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func():
			_prop_category = category_id
			_refresh_asset_library()
		)
		_asset_category_row.add_child(btn)

	if _prop_category == "objects3d":
		_build_object3d_filters()
		_refresh_object3d_library()
		return

	var assets: Array = AssetLibraryScript.list_assets(_prop_category)
	if assets.is_empty():
		_asset_hint.text = "Aucun décor dans « %s ». Importez des PNG détourés (fond transparent) : maisons, charrettes, tonneaux, arbres…" % \
			AssetLibraryScript.category(_prop_category).get("label", _prop_category)
		return
	_asset_hint.text = "%d décor(s) — cliquez pour armer l'outil, puis cliquez la carte." % assets.size()

	for asset_variant in assets:
		var asset: Dictionary = asset_variant
		var path := str(asset.get("path", ""))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(84, 92)
		btn.tooltip_text = "%s\n%s" % [asset.get("name", ""), path.get_file()]
		btn.toggle_mode = true
		btn.button_pressed = path == _prop_asset
		btn.icon = AssetLibraryScript.load_thumbnail(path)
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.text = str(asset.get("name", "")).substr(0, 12)
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func(): _select_prop_asset(asset))
		_asset_grid.add_child(btn)

		var remove := Button.new()
		remove.text = "✕"
		remove.flat = true
		remove.custom_minimum_size = Vector2(18, 18)
		remove.tooltip_text = "Retirer de la bibliothèque"
		remove.pressed.connect(func():
			AssetLibraryScript.remove_asset(path)
			if _prop_asset == path:
				_prop_asset = ""
			_refresh_asset_library()
		)
		btn.add_child(remove)

## Filtres rapides de la bibliothèque 3D (bâtiments, toits, personnages…).
const OBJECT3D_FILTERS := [
	["all", "Tous"],
	["buildings", "Bâtiments"],
	["roofs", "Toits & façades"],
	["characters", "Personnages"],
	["nature", "Nature"],
	["interiors", "Intérieurs"],
	["furniture", "Mobilier"],
]

func _build_object3d_filters() -> void:
	if _asset_filter_row == null:
		return
	for entry in OBJECT3D_FILTERS:
		var filter_id := str(entry[0])
		var btn := Button.new()
		btn.text = str(entry[1])
		btn.toggle_mode = true
		btn.button_pressed = _object3d_filter == filter_id
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func():
			_object3d_filter = filter_id
			_refresh_asset_library()
		)
		_asset_filter_row.add_child(btn)

func _object3d_filter_matches(asset: Dictionary) -> bool:
	var path := str(asset.get("path", ""))
	var name := str(asset.get("name", "")).to_lower()
	var file := path.get_file().get_basename().to_lower()
	if not _object3d_search.is_empty():
		var haystack := "%s %s" % [name, file]
		if not haystack.contains(_object3d_search):
			return false
	if _object3d_filter == "all":
		return true
	var is_character := file.begins_with("pnj_")
	var roof_prefixes := ["toit_", "cheminee", "clocheton", "colombage", "porte_", "fenetre_", "balcon", "auvent", "escalier_"]
	var is_roof := false
	for prefix in roof_prefixes:
		if file.begins_with(str(prefix)):
			is_roof = true
			break
	var interior_names := [
		"table_tabourets", "comptoir", "tapis", "lit", "tonneau_couche",
		"sarcophage", "pile_os", "herse", "chaine_murale", "torche_murale",
	]
	var is_interior := file in interior_names
	var is_nature := path.contains("/vegetation/") or path.contains("/terrain/")
	var is_building := path.contains("/buildings/") and not is_roof and not is_character
	match _object3d_filter:
		"characters":
			return is_character
		"roofs":
			return is_roof
		"interiors":
			return is_interior
		"nature":
			return is_nature
		"buildings":
			return is_building
		"furniture":
			return not is_character and not is_roof and not is_interior and not is_nature and not is_building
	return true

## Liste les meshes 3D livrés et importés par l'utilisateur
## (res://assets/objects3d/<catégorie>/*.glb + user://map_assets/objects3d/...).
func _refresh_object3d_library() -> void:
	if _mesh_import_dialog == null:
		_mesh_import_dialog = FileDialog.new()
		_mesh_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_mesh_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_mesh_import_dialog.filters = PackedStringArray(["*.glb, *.gltf ; Modèles 3D"])
		_mesh_import_dialog.title = "Importer un modèle 3D (GLB / glTF)"
		_mesh_import_dialog.ok_button_text = "Importer"
		_mesh_import_dialog.cancel_button_text = "Annuler"
		_mesh_import_dialog.file_selected.connect(_on_object3d_import_selected)
		add_child(_mesh_import_dialog)

	var assets: Array = AssetLibraryScript.list_object3d_assets()
	var filtered: Array = []
	for asset_variant in assets:
		if _object3d_filter_matches(asset_variant as Dictionary):
			filtered.append(asset_variant)
	_asset_hint.text = "%d / %d objet(s) 3D — cliquez pour armer l'outil, puis cliquez la carte." % [filtered.size(), assets.size()] if not assets.is_empty() \
		else "Aucun objet 3D. Cliquez « Importer un GLB… » ou déposez des .glb dans game/assets/objects3d/."

	var import_btn := Button.new()
	import_btn.text = "＋ Importer un GLB…"
	import_btn.custom_minimum_size = Vector2(84, 40)
	import_btn.tooltip_text = "Ajoute un modèle .glb/.gltf à VOTRE bibliothèque (user://map_assets/objects3d/). Une vignette est générée automatiquement."
	import_btn.add_theme_font_size_override("font_size", 10)
	import_btn.pressed.connect(func(): _mesh_import_dialog.popup_centered(Vector2i(900, 620)))
	_asset_grid.add_child(import_btn)

	for asset_variant in filtered:
		var asset: Dictionary = asset_variant
		var path := str(asset.get("path", ""))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(84, 92)
		btn.tooltip_text = "%s\n%s\n%s" % [asset.get("name", ""), path.get_file(), path]
		btn.toggle_mode = true
		btn.button_pressed = path == _mesh_asset
		var thumb: Texture2D = AssetLibraryScript.load_object3d_thumbnail(path)
		if thumb != null:
			btn.icon = thumb
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		else:
			btn.text = "🧊"
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func(): _select_mesh_asset(asset))
		_asset_grid.add_child(btn)

		# Les assets importés par l'utilisateur peuvent être retirés.
		if bool(asset.get("user", false)):
			var remove := Button.new()
			remove.text = "✕"
			remove.flat = true
			remove.custom_minimum_size = Vector2(18, 18)
			remove.tooltip_text = "Retirer cet objet 3D importé"
			remove.pressed.connect(func():
				AssetLibraryScript.remove_object3d(path)
				if _mesh_asset == path:
					_mesh_asset = ""
				_refresh_asset_library()
			)
			btn.add_child(remove)

## Import d'un GLB choisi par le MJ : copie dans user://, vignette auto, outil armé.
func _on_object3d_import_selected(source_path: String) -> void:
	var entry: Dictionary = AssetLibraryScript.import_object3d(source_path, "imports")
	if entry.is_empty():
		_set_status("Import 3D impossible : fichier .glb/.gltf invalide ou illisible.")
		return
	var asset_path := str(entry.get("path", ""))
	await _generate_object3d_thumbnail(asset_path)
	_prop_category = "objects3d"
	_mesh_asset = asset_path
	_mesh_scale = 1.0
	_mesh_rotation = 0.0
	_set_tool(ToolsScript.MESH)
	_refresh_asset_library()
	_set_status("Objet 3D « %s » importé — cliquez la carte." % entry.get("name", ""))

## Génère une vignette 256×256 du GLB (rendu hors écran) pour la bibliothèque.
## Silencieux en cas d'échec : la bibliothèque affiche alors l'icône 🧊.
func _generate_object3d_thumbnail(asset_path: String) -> void:
	var thumb_path := AssetLibraryScript.object3d_thumb_path(asset_path)
	if thumb_path.is_empty():
		return
	if FileAccess.file_exists(ProjectSettings.globalize_path(thumb_path)):
		return
	var scene: Node3D = AssetLibraryScript.instantiate_object3d_scene(asset_path)
	if scene == null:
		return
	var boxes: Array = []
	_collect_mesh_aabbs(scene, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		scene.free()
		return
	var merged: AABB = boxes[0]
	for i in range(1, boxes.size()):
		merged = merged.merge(boxes[i])
	var max_dim := maxf(merged.size.x, maxf(merged.size.y, merged.size.z))
	if max_dim <= 0.0001:
		scene.free()
		return
	var fit := 1.8 / max_dim
	scene.scale = Vector3.ONE * fit
	scene.position = Vector3(
		-(merged.position.x + merged.size.x * 0.5) * fit,
		-merged.position.y * fit,
		-(merged.position.z + merged.size.z * 0.5) * fit
	)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(scene)
	var camera := Camera3D.new()
	camera.fov = 35.0
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(1.55, 1.25, 2.1), Vector3(0.0, 0.55, 0.0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
	fill.light_energy = 0.35
	viewport.add_child(fill)
	add_child(viewport)
	for _i in range(5):
		await get_tree().process_frame
	var image: Image = viewport.get_texture().get_image()
	if image != null:
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(ProjectSettings.globalize_path(thumb_path))
		AssetLibraryScript.clear_caches()
	viewport.queue_free()

## Les bâtiments restent droits sur une pente ; la végétation et les rochers
## peuvent s'incliner pour épouser le terrain.
func _mesh_tilt_default(asset: Dictionary) -> bool:
	var category := str(asset.get("category", ""))
	return category == "vegetation" or category == "terrain"

func _select_mesh_asset(asset: Dictionary) -> void:
	_mesh_asset = str(asset.get("path", ""))
	_mesh_scale = 1.0
	_mesh_rotation = 0.0
	_set_tool(ToolsScript.MESH)
	_refresh_asset_library()
	_set_status("Objet 3D « %s » prêt — cliquez la carte." % asset.get("name", ""))

func _select_prop_asset(asset: Dictionary) -> void:
	_prop_asset = str(asset.get("path", ""))
	_prop_size = float(asset.get("size", 2.0))
	_prop_standing = bool(asset.get("standing", true))
	if MapRenderStyleScript.prefer_flat_props(doc.map_data):
		_prop_standing = false
	_prop_rotation = 0.0
	_set_tool(ToolsScript.PROP)
	_refresh_asset_library()
	_set_status("Décor « %s » prêt — cliquez la carte." % asset.get("name", ""))

func _on_assets_imported(paths: PackedStringArray) -> void:
	var count := 0
	for path in paths:
		if not (AssetLibraryScript.import_asset(path, _prop_category) as Dictionary).is_empty():
			count += 1
	_refresh_asset_library()
	_set_status("%d décor(s) importé(s) dans « %s »." % [
		count, AssetLibraryScript.category(_prop_category).get("label", _prop_category)])

func _refresh_templates() -> void:
	if _template_list == null:
		return
	for child in _template_list.get_children():
		child.queue_free()
	var templates: Array = TemplatesScript.list_templates()
	if templates.is_empty():
		var empty := Label.new()
		empty.text = "Aucun template. Sélectionnez des éléments puis « ＋ Depuis la sélection »."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_template_list.add_child(empty)
		return
	for entry_variant in templates:
		var entry: Dictionary = entry_variant
		var template_name := str(entry["name"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		_template_list.add_child(row)
		var btn := Button.new()
		btn.text = "🧩 %s (%d)" % [template_name, int(entry.get("elementCount", 0))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func():
			_selected_template = template_name
			_template_rotation = 0
			_set_tool(ToolsScript.TEMPLATE)
			_set_status("Template « %s » prêt — cliquez la carte (R pour pivoter)." % template_name)
		)
		row.add_child(btn)
		var rot := Button.new()
		rot.text = "⟳"
		rot.custom_minimum_size = Vector2(28, 24)
		rot.tooltip_text = "Pivoter de 90°"
		rot.pressed.connect(func():
			_selected_template = template_name
			_template_rotation = (_template_rotation + 1) % 4
			_set_status("Rotation du template : %d°" % (_template_rotation * 90))
			_refresh_ghost()
		)
		row.add_child(rot)
		var del := Button.new()
		del.text = "✕"
		del.custom_minimum_size = Vector2(26, 24)
		del.pressed.connect(func():
			TemplatesScript.delete_template(template_name)
			_refresh_templates()
		)
		row.add_child(del)

func _place_template(grid: Vector2) -> void:
	if _selected_template.is_empty():
		_set_status("Choisissez un template dans la bibliothèque.")
		return
	var footprint: Vector2 = TemplatesScript.footprint(_selected_template, _template_rotation)
	var origin := grid - footprint * 0.5
	var elements: Array = TemplatesScript.elements_for_placement(_selected_template, origin.x, origin.y, _template_rotation)
	if elements.is_empty():
		_set_status("Template vide.")
		return
	doc.begin_transaction()
	var new_ids: Array = []
	for elem_variant in elements:
		var elem: Dictionary = elem_variant
		new_ids.append(doc.add_element(elem, str(elem.get("kind", DocumentScript.KIND_TOKEN)), "Template"))
	doc.commit_transaction()
	doc.set_selection(new_ids)
	_sync_engine()
	_set_status("Template posé (%d éléments)." % new_ids.size())

# ===========================================================================
# Clavier
# ===========================================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if not _editable or not is_visible_in_tree():
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_SPACE:
		_space_held = key.pressed
		return
	if not key.pressed or key.echo:
		return

	# Pendant un drag / tracé : Échap annule, le reste des raccourcis outils est ignoré.
	var gesturing := _press_mode != "none"
	if gesturing and key.keycode != KEY_ESCAPE:
		if key.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_DELETE, KEY_BACKSPACE]:
			get_viewport().set_input_as_handled()
			return
		# Les lettres d'outils ne doivent pas changer d'outil en plein geste.
		var tool_probe := ToolsScript.tool_for_shortcut(OS.get_keycode_string(key.keycode))
		if not tool_probe.is_empty() and not key.ctrl_pressed:
			get_viewport().set_input_as_handled()
			return

	if key.ctrl_pressed:
		match key.keycode:
			KEY_Z:
				if key.shift_pressed:
					_do_redo()
				else:
					_do_undo()
			KEY_Y:
				_do_redo()
			KEY_C:
				_set_status("%d élément(s) copié(s)." % doc.copy_selection())
			KEY_X:
				_set_status("%d élément(s) coupé(s)." % doc.cut_selection())
				_sync_engine()
			KEY_V:
				if _overlay.hover_valid:
					doc.paste(_snap(_overlay.hover_grid).x, _snap(_overlay.hover_grid).y)
				else:
					doc.paste()
				_sync_engine()
			KEY_D:
				doc.duplicate_selection()
				_sync_engine()
			KEY_A:
				doc.select_all()
			KEY_I:
				doc.invert_selection()
			KEY_G:
				if key.shift_pressed:
					doc.ungroup_selection()
				else:
					doc.group_selection()
			KEY_S:
				save_now()
			_:
				return
		get_viewport().set_input_as_handled()
		return

	match key.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			doc.remove_elements(doc.selection())
			_sync_engine()
		KEY_ESCAPE:
			if _overlay and _overlay.measure_active:
				_overlay.measure_active = false
				_refresh_overlay()
				_set_status("Mesure effacée.")
			elif _press_mode != "none" or not _overlay.polygon_points.is_empty() or not _link_source.is_empty():
				_cancel_action()
			else:
				_open_esc_menu()
		KEY_ENTER, KEY_KP_ENTER:
			if not _overlay.polygon_points.is_empty():
				_close_polygon()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var step := 1.0 if key.shift_pressed else maxf(ToolsScript.snap_step(_snap_mode), 0.25)
			var delta := Vector2.ZERO
			if key.keycode == KEY_LEFT:
				delta.x = -step
			elif key.keycode == KEY_RIGHT:
				delta.x = step
			elif key.keycode == KEY_UP:
				delta.y = -step
			else:
				delta.y = step
			doc.move_elements_by(doc.selection(), delta.x, delta.y)
			_sync_engine()
		KEY_PAGEUP:
			doc.bring_forward()
			_sync_engine()
		KEY_PAGEDOWN:
			doc.send_backward()
			_sync_engine()
		KEY_F:
			_focus_selection()
		KEY_R:
			if _tool == ToolsScript.TEMPLATE:
				_template_rotation = (_template_rotation + 1) % 4
				_refresh_ghost()
			elif _tool == ToolsScript.PROP:
				_prop_rotation = fmod(_prop_rotation + 90.0, 360.0)
				_set_status("Rotation du décor : %d°" % int(_prop_rotation))
				_refresh_ghost()
			elif _tool == ToolsScript.MESH:
				_mesh_rotation = fmod(_mesh_rotation + 90.0, 360.0)
				_set_status("Rotation de l'objet 3D : %d°" % int(_mesh_rotation))
				_refresh_ghost()
			else:
				_apply_shortcut_tool(key)
				return
		_:
			_apply_shortcut_tool(key)
			return
	get_viewport().set_input_as_handled()

func _apply_shortcut_tool(key: InputEventKey) -> void:
	if _press_mode != "none":
		return
	var text := OS.get_keycode_string(key.keycode)
	var tool_id := ToolsScript.tool_for_shortcut(text)
	if tool_id.is_empty():
		return
	_set_tool(tool_id)
	get_viewport().set_input_as_handled()

func _do_undo() -> void:
	if doc.undo():
		_sync_engine()
		_set_status("Annulé.")
	else:
		_set_status("Rien à annuler.")

func _do_redo() -> void:
	if doc.redo():
		_sync_engine()
		_set_status("Rétabli.")
	else:
		_set_status("Rien à rétablir.")

## Enregistre la carte puis lance une session de test (monde entier si la carte
## appartient à un monde de zones).
func _test_current_map() -> void:
	var map_id := str(doc.map_data.get("id", ""))
	if map_id.is_empty():
		_set_status("Impossible de tester : carte non enregistrée.")
		return
	save_now()
	var gd = get_node_or_null("/root/GameData")
	if gd == null or not gd.has_method("start_world_playtest"):
		_set_status("Session de test indisponible.")
		return
	var ids: Array = [map_id]
	var world_id := str(doc.map_data.get("worldId", ""))
	if not world_id.is_empty():
		var world_ids: Array = []
		for map_variant in MapData.maps:
			if not map_variant is Dictionary:
				continue
			var map: Dictionary = map_variant
			if str(map.get("worldId", "")) == world_id and str(map.get("renderMode", "")) == "complex":
				world_ids.append(str(map.get("id", "")))
		if not world_ids.is_empty():
			ids = world_ids
	if gd.start_world_playtest(ids, map_id):
		_set_status("Session de test lancée (%d zone(s))." % ids.size())
	else:
		_set_status("Impossible de lancer la session de test.")

## Vérifie la carte et affiche un rapport (tailles de tampons, objets hors
## limites, assets manquants, eau sans dépression, liens de zone cassés).
func _validate_map() -> void:
	if _validate_dialog == null:
		_build_dialogs()
	var issues := _collect_map_issues()
	var header := _map_report_header()
	if issues.is_empty():
		_validate_text.text = "%s\n[color=#9fe08a]✓ Aucun problème détecté.[/color]" % header
	else:
		var lines: Array = ["%s" % header, "[b]%d problème(s) détecté(s)[/b]" % issues.size(), ""]
		for issue in issues:
			lines.append("• %s" % str(issue))
		_validate_text.text = "\n".join(lines)
	_validate_dialog.popup_centered(Vector2i(620, 420))
	_set_status("Vérification : %d problème(s)." % issues.size())

## Résumé chiffré de la carte affiché en tête du rapport de vérification.
func _map_report_header() -> String:
	var map: Dictionary = doc.map_data
	var w := int(map.get("width", 0))
	var h := int(map.get("height", 0))
	var counts := {"mesh": 0, "prop": 0, "marker": 0}
	for key in [["meshes", "mesh"], ["props", "prop"], ["markers", "marker"]]:
		var elements = map.get(key[0], [])
		if elements is Array:
			counts[key[1]] = (elements as Array).size()
	var heights = map.get("terrainHeights", [])
	var min_h := 0.0
	var max_h := 0.0
	if heights is Array and not (heights as Array).is_empty():
		min_h = float((heights as Array)[0])
		max_h = min_h
		for value in heights:
			min_h = minf(min_h, float(value))
			max_h = maxf(max_h, float(value))
	var mat_counts := [0, 0, 0, 0, 0]
	var materials = map.get("terrainMaterials", [])
	if materials is Array:
		for value in materials:
			var m := clampi(int(value), 0, 4)
			mat_counts[m] += 1
	var water := float(map.get("waterLevel", -1.0))
	var world_id := str(map.get("worldId", ""))
	return ("[b]Carte[/b] : %s — %d×%d cases · objets %d, décors %d, marqueurs %d\n" \
		+ "Relief : %.2f à %.2f · eau : %s · monde : %s\n"
		+ "Sols : herbe %d, terre %d, pierre %d, neige %d, sable %d") % [
		str(map.get("title", "Carte")), w, h,
		int(counts["mesh"]), int(counts["prop"]), int(counts["marker"]),
		min_h, max_h,
		("niveau %.2f" % water) if water > -1.0 else "aucune",
		world_id if not world_id.is_empty() else "—",
		int(mat_counts[0]), int(mat_counts[1]), int(mat_counts[2]),
		int(mat_counts[3]), int(mat_counts[4]),
	]

## Liste des problèmes détectés sur la carte courante (vide si tout est bon).
func _collect_map_issues() -> Array:
	var issues: Array = []
	var map: Dictionary = doc.map_data
	var w := int(map.get("width", 0))
	var h := int(map.get("height", 0))
	if w <= 0 or h <= 0:
		issues.append("Dimensions invalides (%d×%d)." % [w, h])
		return issues
	var expected := w * h
	for key in ["terrainHeights", "terrainMaterials"]:
		var buffer = map.get(key, [])
		if not buffer is Array or (buffer as Array).size() != expected:
			issues.append("%s : %d valeurs pour %d cases." % [key, (buffer as Array).size() if buffer is Array else 0, expected])
	for key in ["meshes", "props", "markers"]:
		var elements = map.get(key, [])
		if not elements is Array:
			continue
		for element_variant in elements:
			if not element_variant is Dictionary:
				continue
			var element: Dictionary = element_variant
			var ex := float(element.get("x", 0.0))
			var ey := float(element.get("y", 0.0))
			if ex < -0.5 or ey < -0.5 or ex > float(w) - 0.5 or ey > float(h) - 0.5:
				issues.append("%s hors carte en %.1f,%.1f." % [str(element.get("label", element.get("id", key))), ex, ey])
			var asset := str(element.get("asset", ""))
			if not asset.is_empty() and not FileAccess.file_exists(asset):
				issues.append("Asset introuvable : %s." % asset)
	var water := float(map.get("waterLevel", -1.0))
	if water > -1.0:
		var heights = map.get("terrainHeights", [])
		var has_hollow := false
		if heights is Array:
			for value in heights:
				if float(value) < water - 0.01:
					has_hollow = true
					break
		if not has_hollow:
			issues.append("Eau au niveau %.2f sans dépression : la carte serait inondée." % water)
	var world_id := str(map.get("worldId", ""))
	if not world_id.is_empty():
		var edges: Dictionary = map.get("edges", {}) if map.get("edges") is Dictionary else {}
		for side in edges:
			var edge = edges[side]
			if not edge is Dictionary:
				continue
			var target := str((edge as Dictionary).get("target", ""))
			if target.is_empty():
				continue
			if MapData.get_by_id(target).is_empty():
				issues.append("Lien %s vers une zone inexistante (%s)." % [side, target])
	return issues

func _open_export_image() -> void:
	_export_image_dialog.current_file = "%s.png" % str(doc.map_data.get("title", "carte")).validate_filename()
	_export_image_dialog.popup_centered_ratio(0.6)

func _on_export_image_selected(path: String) -> void:
	var save_path := path if path.to_lower().ends_with(".png") else path + ".png"
	_export_map_image(save_path)

## Capture le viewport 3D de la carte (sans l'UI) et l'écrit en PNG.
func _export_map_image(path: String) -> void:
	_do_export_map_image(path)

func _do_export_map_image(path: String) -> void:
	await get_tree().process_frame
	if _engine == null or _engine._viewport == null:
		_set_status("Capture impossible.")
		return
	var texture: Texture2D = _engine._viewport.get_texture()
	if texture == null:
		_set_status("Capture impossible (viewport vide).")
		return
	var image: Image = texture.get_image()
	if image == null:
		_set_status("Capture impossible (mode headless).")
		return
	image.convert(Image.FORMAT_RGBA8)
	var err := image.save_png(path)
	if err == OK:
		_set_status("Image exportée : %s" % path)
	else:
		_set_status("Échec de l'écriture de l'image.")

func _open_help() -> void:
	if _help_dialog == null:
		_build_dialogs()
	_help_dialog.popup_centered(Vector2i(720, 600))

func _open_esc_menu() -> void:
	if _esc_menu == null:
		return
	if _esc_menu.has_method("sync_policy"):
		_esc_menu.sync_policy(_save_policy)
	if _esc_menu.has_method("open_centered"):
		_esc_menu.open_centered()
	else:
		_esc_menu.popup_centered(Vector2i(340, 520))

## Crée la carte d'un lieu. La carte courante est enregistrée d'abord : elle
## doit contenir le lieu pour que MapData puisse y écrire le lien retour.
func _on_child_map_requested(area_id: String) -> void:
	var map_id := str(doc.map_data.get("id", ""))
	if map_id.is_empty() or area_id.is_empty():
		return
	save_now()
	var child := MapData.create_child_map_for_area(map_id, area_id)
	if child.is_empty():
		_set_status("Impossible de créer la carte de ce lieu.")
		return
	# On recharge pour récupérer le lien écrit côté MapData.
	doc.load_map(MapData.get_by_id(map_id))
	_sync_settings_ui()
	_refresh_panels()
	_refresh_breadcrumb()
	_set_status("Carte « %s » créée. Ouvrez-la pour la composer." % child.get("title", ""))

func _on_open_map_requested(map_id: String) -> void:
	if map_id.is_empty():
		return
	if doc.is_dirty():
		save_now()
	open_map_requested.emit(map_id)

## Ouvre la zone précédente/suivante du monde courant (navigation rapide).
func _cycle_world_map(direction: int) -> void:
	var map_id := str(doc.map_data.get("id", ""))
	var world_id := str(doc.map_data.get("worldId", ""))
	if map_id.is_empty() or world_id.is_empty():
		_set_status("Cette carte n'appartient pas à un monde.")
		return
	var zones: Array = []
	for map_variant in MapData.maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("worldId", "")) != world_id or str(map.get("renderMode", "")) != "complex":
			continue
		zones.append(map)
	if zones.size() <= 1:
		return
	zones.sort_custom(func(a, b):
		var ay := int((a as Dictionary).get("zoneY", 0))
		var by := int((b as Dictionary).get("zoneY", 0))
		if ay == by:
			return int((a as Dictionary).get("zoneX", 0)) < int((b as Dictionary).get("zoneX", 0))
		return ay < by
	)
	var current := -1
	for i in range(zones.size()):
		if str((zones[i] as Dictionary).get("id", "")) == map_id:
			current = i
			break
	if current < 0:
		return
	var next := (current + direction + zones.size()) % zones.size()
	if next == current:
		return
	_on_open_map_requested(str((zones[next] as Dictionary).get("id", "")))

func _focus_selection() -> void:
	var bounds: Rect2 = doc.selection_bounds()
	if bounds.size == Vector2.ZERO:
		_engine.reset_zoom()
		return
	_engine.focus_grid_rect(bounds)
	_refresh_overlay()

func _focus_element(element_id: String) -> void:
	doc.select_only(element_id)
	_focus_selection()

# ===========================================================================
# Synchronisation moteur / panneaux
# ===========================================================================

func _sync_engine(reset_view: bool = false) -> void:
	if _engine == null or doc.map_data.is_empty():
		return
	var snapshot: Dictionary = doc.to_map_data()
	var defaults: Dictionary = snapshot.get("playDefaults", {})
	var view_state: Dictionary = defaults.get("viewState", {}) if defaults.get("viewState") is Dictionary else {}
	var tokens: Array = defaults.get("tokens", [])
	_ensure_token_portraits(tokens)
	_engine.set_snap_to_grid(_snap_mode == "cell")
	# Vue joueur : is_gm=false → brouillard joueur + présentation contrainte.
	var as_gm := not _player_view
	_engine.configure(
		snapshot,
		tokens,
		_mock_party(),
		defaults.get("effects", []),
		defaults.get("zones", []),
		defaults.get("fogRevealed", []),
		not _editable,
		as_gm,
		{"mode": "select"},
		view_state,
	)
	if reset_view and view_state.is_empty():
		if _engine.has_method("request_fit_to_view"):
			_engine.call_deferred("request_fit_to_view")
		else:
			_engine.call_deferred("reset_zoom")
	call_deferred("_update_zoom_label")
	_apply_player_view_overlay()
	_refresh_overlay()

func _ensure_token_portraits(tokens: Array) -> void:
	var portrait := _default_token_portrait()
	if portrait.is_empty():
		return
	for tok_variant in tokens:
		if not (tok_variant is Dictionary):
			continue
		var tok: Dictionary = tok_variant
		if str(tok.get("image", "")).strip_edges().is_empty():
			tok["image"] = portrait

func _mock_party() -> Array:
	var portrait := _default_token_portrait()
	var party: Array = []
	for i in range(MapData.MEMBER_COLOR_HEX.size()):
		party.append({
			"id": "editor-mock-%d" % i,
			"name": "Token %d" % (i + 1),
			"isPlayer": true,
			"portrait": portrait,
			"image": portrait,
		})
	# Alias Kael démo → même portrait (tokens playDefaults memberId=char-kael).
	if not portrait.is_empty():
		party.append({
			"id": "char-kael",
			"name": "Kael",
			"isPlayer": true,
			"portrait": portrait,
			"image": portrait,
		})
	return party

func _refresh_overlay() -> void:
	if _overlay:
		_overlay.queue_redraw()
	if _minimap:
		_minimap.queue_redraw()

## Recalcule l'aperçu de ligne de vue depuis l'élément sélectionné (ou le
## curseur si rien n'est sélectionné).
func _refresh_vision_preview() -> void:
	if _overlay == null:
		return
	_overlay.vision_cells.clear()
	_overlay.has_vision_origin = false
	if not _overlay.show_vision or doc.map_data.is_empty():
		_refresh_overlay()
		return
	var origin := Vector2.ZERO
	var selected: Array = doc.selection()
	if not selected.is_empty():
		var elem: Dictionary = doc.get_element(str(selected[0]))
		origin = Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	elif _overlay.hover_valid:
		origin = _snap(_overlay.hover_grid)
	else:
		_refresh_overlay()
		return
	for key in MapVisionScript.visible_cells(doc.to_map_data(), origin, MapVisionScript.DEFAULT_VISION_RADIUS):
		_overlay.vision_cells[str(key)] = true
	_overlay.vision_origin = origin
	_overlay.has_vision_origin = true
	_refresh_overlay()

func _refresh_ghost() -> void:
	if _overlay == null:
		return
	if not _editable:
		_overlay.ghost.clear()
		return
	if _tool == ToolsScript.PROP and not _prop_asset.is_empty():
		var ratio := AssetLibraryScript.aspect_ratio(_prop_asset)
		var snapped := _snap(_overlay.hover_grid)
		_overlay.ghost = {
			"x": snapped.x, "y": snapped.y,
			"w": maxf(0.25, _prop_size * ratio), "h": maxf(0.25, _prop_size),
			"icon": "",
			"texture": AssetLibraryScript.load_texture(_prop_asset),
			"rotation": _prop_rotation,
			"standing": _prop_standing and not MapRenderStyleScript.prefer_flat_props(doc.map_data),
			"kind": "prop",
		}
	elif ToolsScript.is_pose_tool(_tool):
		var size := _ghost_size()
		var snapped := _snap(_overlay.hover_grid)
		var ghost := {
			"x": snapped.x,
			"y": snapped.y,
			"w": size.x, "h": size.y,
			"icon": _ghost_icon_for_tool(),
			"kind": _tool,
		}
		if _tool == ToolsScript.MESH:
			var mesh_footprint := _mesh_footprint_cells(_mesh_asset)
			ghost["w"] = mesh_footprint.x
			ghost["h"] = mesh_footprint.y
			ghost["icon"] = "🧊"
			ghost["rotation"] = _mesh_rotation
			ghost["texture"] = AssetLibraryScript.load_object3d_thumbnail(_mesh_asset)
			ghost["standing"] = true
			# Aperçu de l'aimantation : montre où le module sera réellement posé.
			if _mesh_snap_modules and not _mesh_asset.is_empty():
				var snap_preview := _snap_module_placement(_mesh_asset, _overlay.hover_grid)
				if not snap_preview.is_empty():
					ghost["x"] = float(snap_preview.get("x", ghost["x"]))
					ghost["y"] = float(snap_preview.get("y", ghost["y"]))
					ghost["rotation"] = float(snap_preview.get("rotation", 0.0))
					ghost["snapped"] = true
		if _tool == ToolsScript.TOKEN:
			ghost["color"] = MapData.MEMBER_COLOR_HEX[_member_index % MapData.MEMBER_COLOR_HEX.size()]
		elif _tool == ToolsScript.EFFECT:
			var preset := MapEffectPresetsScript.get_preset(_effect_preset)
			ghost["color"] = preset.get("color", Color(1, 0.6, 0.2, 0.8))
		elif _tool == ToolsScript.MARKER:
			ghost["color"] = Color(0.95, 0.75, 0.35, 0.9)
		elif _tool == ToolsScript.LIGHT:
			ghost["color"] = Color(1.0, 0.72, 0.35, 0.9)
			ghost["radius"] = _light_place_radius
		_overlay.ghost = ghost
	elif _tool == ToolsScript.TEMPLATE and not _selected_template.is_empty():
		var footprint: Vector2 = TemplatesScript.footprint(_selected_template, _template_rotation)
		_overlay.ghost = {
			"x": _snap(_overlay.hover_grid).x,
			"y": _snap(_overlay.hover_grid).y,
			"w": footprint.x, "h": footprint.y,
			"icon": "🧩",
			"kind": "template",
			"rotation": float(_template_rotation * 90),
		}
	elif _tool == ToolsScript.TERRAIN_HEIGHT:
		var relief_brush := _relief_radius * 2.0
		_overlay.ghost = {
			"x": _overlay.hover_grid.x,
			"y": _overlay.hover_grid.y,
			"w": relief_brush, "h": relief_brush,
			"icon": "⛰",
			"kind": "terrain_height",
		}
	elif _tool == ToolsScript.GROUND_MATERIAL:
		var material_brush := _material_radius * 2.0
		var mat_colors := {
			MapData.MATERIAL_GRASS: Color(0.42, 0.66, 0.34),
			MapData.MATERIAL_DIRT: Color(0.62, 0.48, 0.32),
			MapData.MATERIAL_STONE: Color(0.66, 0.64, 0.60),
			MapData.MATERIAL_SNOW: Color(0.88, 0.91, 0.96),
			MapData.MATERIAL_SAND: Color(0.86, 0.76, 0.56),
		}
		_overlay.ghost = {
			"x": _overlay.hover_grid.x,
			"y": _overlay.hover_grid.y,
			"w": material_brush, "h": material_brush,
			"icon": "🟫",
			"kind": "ground_material",
			"color": mat_colors.get(_material_id, Color(0.7, 0.7, 0.7)),
		}
	elif ToolsScript.is_paint_tool(_tool):
		var brush := float(_brush_size if _tool == ToolsScript.PAINT else _fog_brush) * 2.0 + 1.0
		_overlay.ghost = {
			"x": roundf(_overlay.hover_grid.x),
			"y": roundf(_overlay.hover_grid.y),
			"w": brush, "h": brush,
			"icon": ToolsScript.icon(_tool),
			"kind": _tool,
		}
	else:
		_overlay.ghost.clear()

func _ghost_icon_for_tool() -> String:
	if _tool == ToolsScript.TOKEN:
		return str(MapData.MEMBER_PLAYER_EMOJIS_GENERAL[_member_index % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()])
	if _tool == ToolsScript.MARKER:
		return MapData.get_marker_emoji(_marker_type)
	if _tool == ToolsScript.EFFECT:
		return str(MapEffectPresetsScript.get_preset(_effect_preset).get("emoji", "✨"))
	return ToolsScript.icon(_tool)
func _ghost_size() -> Vector2:
	if _tool == ToolsScript.TERRAIN_HEIGHT:
		return Vector2(_relief_radius * 2.0, _relief_radius * 2.0)
	if _tool == ToolsScript.GROUND_MATERIAL:
		return Vector2(_material_radius * 2.0, _material_radius * 2.0)
	if _tool == ToolsScript.TOKEN:
		return Vector2(_token_size, _token_size)
	if _tool == ToolsScript.EFFECT:
		return Vector2(_effect_radius * 2.0, _effect_radius * 2.0)
	if _tool == ToolsScript.ZONE:
		return Vector2(_zone_radius * 2.0, _zone_radius * 2.0)
	if _tool == ToolsScript.LIGHT:
		return Vector2(_light_place_radius * 2.0, _light_place_radius * 2.0)
	return Vector2.ONE

## Fil d'Ariane : village → place du marché → taverne. Chaque échelon ramène
## à la carte correspondante.
func _refresh_breadcrumb() -> void:
	if _breadcrumb == null:
		return
	for child in _breadcrumb.get_children():
		child.queue_free()
	var map_id := str(doc.map_data.get("id", ""))
	if map_id.is_empty():
		return
	var chain: Array = MapData.get_map_breadcrumb(map_id)
	if chain.size() <= 1:
		return
	for i in range(chain.size()):
		var step: Dictionary = chain[i]
		if i > 0:
			var sep := Label.new()
			sep.text = "›"
			sep.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
			_breadcrumb.add_child(sep)
		var is_current := i == chain.size() - 1
		var btn := Button.new()
		btn.text = str(step.get("title", "Carte"))
		btn.flat = true
		btn.disabled = is_current
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 11)
		if is_current:
			btn.add_theme_color_override("font_color_disabled", ThemeColors.GOLD_LIGHT)
		var target := str(step.get("id", ""))
		btn.pressed.connect(func(): _on_open_map_requested(target))
		_breadcrumb.add_child(btn)

func _refresh_panels() -> void:
	if _inspector:
		_inspector.call_deferred("rebuild")
	if _outliner:
		_outliner.call_deferred("rebuild")
	if _minimap:
		_minimap.set_context(_engine, doc)
	_refresh_breadcrumb()
	_refresh_history()
	_refresh_effect_list()
	_refresh_status_badges()

func _refresh_history() -> void:
	if _history_list == null:
		return
	for child in _history_list.get_children():
		child.queue_free()
	var labels: Array = doc.history_labels()
	if labels.is_empty():
		var empty := Label.new()
		empty.text = "Aucune action enregistrée."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_history_list.add_child(empty)
		return
	for i in range(labels.size() - 1, -1, -1):
		var lbl := Label.new()
		lbl.text = "%d. %s" % [i + 1, labels[i]]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", ThemeColors.TEXT if i == labels.size() - 1 else ThemeColors.TEXT_MUTED)
		_history_list.add_child(lbl)

func _on_doc_changed(reason: String) -> void:
	if reason in ["undo", "redo", "meta", "load"]:
		_sync_settings_ui()
	if reason in ["add", "remove", "undo", "redo", "order", "modify", "commit"]:
		# Pas de rebuild panneaux pendant un drag live (positions changeantes).
		if _press_mode not in ["move", "resize", "rotate"]:
			_refresh_panels()
	if reason in ["undo", "redo", "meta", "fog", "tiles", "order", "light_reveal", "modify", "commit", "add", "remove"]:
		_sync_engine()
	_refresh_overlay()
	if _save_policy == SAVE_ON_CHANGE and doc.is_dirty() and reason != "load":
		save_now()
	layout_changed.emit()

func _on_selection_changed(_ids: Array) -> void:
	if _overlay and _overlay.show_vision:
		call_deferred("_refresh_vision_preview")
	# Pendant un drag live, ne pas reconstruire l'inspecteur (SpinBox qui se battent).
	if _press_mode not in ["move", "resize", "rotate"]:
		if _inspector:
			_inspector.call_deferred("rebuild")
		if _outliner:
			_outliner.call_deferred("rebuild")
	_update_status_selection()
	_refresh_overlay()

func _on_history_changed() -> void:
	if _undo_btn:
		_undo_btn.disabled = not doc.can_undo()
		_undo_btn.tooltip_text = "Annuler : %s" % doc.undo_label() if doc.can_undo() else "Annuler (Ctrl+Z)"
	if _redo_btn:
		_redo_btn.disabled = not doc.can_redo()
	_refresh_history()
	_refresh_status_badges()

func _on_dirty_changed(is_dirty: bool) -> void:
	if _dirty_lbl:
		_dirty_lbl.text = "● non enregistré" if is_dirty else "✓ enregistré"
		_dirty_lbl.add_theme_color_override("font_color",
			ThemeColors.GOLD_LIGHT if is_dirty else ThemeColors.TEXT_MUTED)
	_refresh_status_badges()

func _on_engine_token_moved(token_id: String, gx: float, gy: float) -> void:
	if not doc.has_element(token_id):
		return
	doc.modify_element(token_id, {"x": gx, "y": gy}, "Déplacement")

# ===========================================================================
# Réglages carte
# ===========================================================================

func _sync_settings_ui() -> void:
	if _settings_widgets.is_empty() or doc.map_data.is_empty():
		return
	_syncing = true
	_set_spin("width", float(doc.map_data.get("width", 16)))
	_set_spin("height", float(doc.map_data.get("height", 12)))
	var grid: Dictionary = MapData.get_grid_config(doc.map_data)
	_set_spin("grid_size", float(grid.get("size", 70)))
	_set_spin("grid_opacity", float(grid.get("opacity", 0.22)))
	_set_check("grid_enabled", bool(grid.get("enabled", true)))
	_set_color("grid_color", str(grid.get("color", "#ffffff")))
	_set_check("fog_enabled", bool(doc.map_data.get("fogEnabled", true)))
	_set_check("los_enabled", bool(doc.map_data.get("losEnabled", false)))
	var measure: Dictionary = doc.map_data.get("measure", {}) if doc.map_data.get("measure") is Dictionary else {}
	_set_spin("measure_per_cell", float(measure.get("perCell", 1.5)))
	_set_line("measure_unit", str(measure.get("unit", "m")))
	var atmo: Dictionary = doc.map_data.get("atmosphere", {}) if doc.map_data.get("atmosphere") is Dictionary else {}
	_set_check("atmo_enabled", bool(atmo.get("enabled", false)))
	_set_color("atmo_tint", str(atmo.get("tint", "#141018")))
	_set_spin("atmo_opacity", float(atmo.get("opacity", 0.12)))
	_set_spin("atmo_vignette", float(atmo.get("vignette", 0.18)))
	var light: Dictionary = MapData.get_lighting_config(doc.map_data)
	_set_check("light_enabled", bool(light.get("enabled", false)))
	_set_spin("light_intensity", float(light.get("intensity", 0.35)))
	_set_check("night_mode", bool(light.get("nightMode", false)))
	_set_spin("night_ambient", float(light.get("nightAmbient", 0.22)))
	_select_metadata("light_dir", str(light.get("direction", "nw")))
	_select_metadata("perspective", MapData.get_perspective(doc.map_data))
	_select_metadata("render_style", str(doc.map_data.get("renderStyle", "2.5d")))
	_select_metadata("ground_mode", MapData.get_ground_mode(doc.map_data))
	_set_spin("water_level", float(doc.map_data.get("waterLevel", -1.0)))
	_select_metadata("ambient_fx", str(doc.map_data.get("ambientFx", "")))
	_refresh_bg_status()
	_syncing = false

func _on_size_changed() -> void:
	if _syncing:
		return
	doc.resize_grid(int(_get_spin("width")), int(_get_spin("height")))
	_sync_engine(true)

func _on_grid_changed() -> void:
	if _syncing:
		return
	doc.set_meta_values({"grid": {
		"size": int(_get_spin("grid_size")),
		"opacity": _get_spin("grid_opacity"),
		"color": _get_color("grid_color"),
		"enabled": _get_check("grid_enabled"),
	}}, "Grille")
	_sync_engine()

func _on_measure_changed() -> void:
	if _syncing:
		return
	doc.set_meta_values({"measure": {
		"perCell": _get_spin("measure_per_cell"),
		"unit": _get_line("measure_unit"),
	}}, "Échelle")

func _on_perspective_changed() -> void:
	if _syncing:
		return
	var option: OptionButton = _settings_widgets.get("perspective")
	if option == null or option.selected < 0:
		return
	doc.set_meta_values({"perspective": str(option.get_item_metadata(option.selected))}, "Perspective")

func _on_render_style_changed() -> void:
	if _syncing:
		return
	var option: OptionButton = _settings_widgets.get("render_style")
	if option == null or option.selected < 0:
		return
	var style := str(option.get_item_metadata(option.selected))
	var patch := {"renderStyle": style}
	# VTT : grille visible ; diorama / DD2 : grille masquée par défaut.
	var grid: Dictionary = MapData.get_grid_config(doc.map_data).duplicate(true)
	grid["show"] = style == "vtt"
	patch["grid"] = grid
	if style == "diorama" or style == "dd2_hybrid" or style == "2.5d":
		patch["perspective"] = MapData.PERSPECTIVE_TILT
	doc.set_meta_values(patch, "Style de rendu")
	_sync_settings_ui()
	_sync_engine(true)
	_sync_engine()

func _on_ground_mode_changed() -> void:
	if _syncing:
		return
	var option: OptionButton = _settings_widgets.get("ground_mode")
	if option == null or option.selected < 0:
		return
	var mode := str(option.get_item_metadata(option.selected))
	doc.set_meta_values({"groundMode": mode}, "Type de sol")
	_sync_engine(true)
	_set_status("Sol : %s" % ("terrain 3D" if mode == "terrain3d" else "fond illustré plat"))

func _on_water_changed() -> void:
	if _syncing:
		return
	var level := _get_spin("water_level")
	doc.set_meta_values({"waterLevel": level}, "Niveau d'eau")
	_sync_engine()
	if level >= 0.0:
		_set_status("Eau : niveau %.1f case(s) — les creux du relief sont immergés." % level)
	else:
		_set_status("Eau désactivée.")

func _on_ambient_fx_changed() -> void:
	if _syncing:
		return
	var option: OptionButton = _settings_widgets.get("ambient_fx")
	if option == null or option.selected < 0:
		return
	var fx := str(option.get_item_metadata(option.selected))
	doc.set_meta_values({"ambientFx": fx}, "Ambiance")
	_sync_engine()
	if fx.is_empty():
		_set_status("Ambiance animée désactivée.")
	else:
		_set_status("Ambiance animée : %s." % option.get_item_text(option.selected))

func _on_atmosphere_changed() -> void:
	if _syncing:
		return
	doc.set_meta_values({"atmosphere": {
		"enabled": _get_check("atmo_enabled"),
		"tint": _get_color("atmo_tint"),
		"opacity": _get_spin("atmo_opacity"),
		"vignette": _get_spin("atmo_vignette"),
	}}, "Atmosphère")
	_sync_engine()

func _on_lighting_changed() -> void:
	if _syncing:
		return
	var light: Dictionary = MapData.get_lighting_config(doc.map_data)
	light["enabled"] = _get_check("light_enabled")
	light["intensity"] = _get_spin("light_intensity")
	var option: OptionButton = _settings_widgets.get("light_dir")
	if option and option.selected >= 0:
		light["direction"] = str(option.get_item_metadata(option.selected))
	# Preserve night fields when editing directional lighting.
	light["nightMode"] = _get_check("night_mode") if _settings_widgets.has("night_mode") else bool(light.get("nightMode", false))
	light["nightAmbient"] = _get_spin("night_ambient") if _settings_widgets.has("night_ambient") else float(light.get("nightAmbient", 0.22))
	doc.set_meta_values({"lighting": light}, "Éclairage")
	_sync_engine()

func _on_night_mode_changed() -> void:
	if _syncing:
		return
	var light: Dictionary = MapData.get_lighting_config(doc.map_data)
	light["nightMode"] = _get_check("night_mode")
	light["nightAmbient"] = _get_spin("night_ambient")
	doc.set_meta_values({"lighting": light}, "Mode nuit")
	_sync_engine()
	if bool(light.get("nightMode", false)):
		_set_status("Mode nuit — les lumières révèlent le jour")
	else:
		_set_status("Mode jour")

func _on_player_view_toggled(on: bool) -> void:
	_player_view = on
	if _player_view_btn:
		_player_view_btn.text = "👁 Vue joueur ●" if on else "👁 Vue joueur"
	_apply_player_view_overlay()
	_sync_engine()
	if on:
		_set_status("Vue joueur — ce que voit le groupe")
	else:
		_set_status("Vue MJ — édition complète")

func _apply_player_view_overlay() -> void:
	if _overlay == null:
		return
	_overlay.player_preview = _player_view
	# Chrome éditeur masqué / atténué en aperçu joueur ; lumières restent visibles.
	if _player_view:
		_overlay.show_links = false
		_overlay.show_ids = false
		_overlay.show_vision = false
	_refresh_overlay()

func _stamp_moved_lights(ids: Array) -> void:
	_rebuild_lights_illumination(ids)

func _rebuild_lights_illumination(ids: Array = []) -> void:
	var touch := ids.is_empty()
	for id_variant in ids:
		if str(doc.get_element(str(id_variant)).get("kind", "")) == DocumentScript.KIND_LIGHT:
			touch = true
			break
	if not touch and not ids.is_empty():
		return
	doc.rebuild_light_reveal_from_lights("Déplacement lumière")
	_refresh_light_mask_live()

func _refresh_light_mask_live() -> void:
	if _engine == null or not MapData.is_night_mode(doc.map_data):
		return
	# Masque = lumières live (positions actuelles). Pas d'ancien stamp résiduel.
	_engine.refresh_night_light_mask(doc.collect_light_sources(), [])

func _on_los_changed() -> void:
	if _syncing:
		return
	doc.set_meta_values({"losEnabled": _get_check("los_enabled")}, "Ligne de vue")
	_refresh_overlay()

func _on_fog_setting_changed() -> void:
	if _syncing:
		return
	doc.set_meta_values({"fogEnabled": _get_check("fog_enabled")}, "Brouillard")
	_sync_engine()

func _refresh_bg_status() -> void:
	var lbl: Label = _settings_widgets.get("bg_status")
	if lbl == null:
		return
	var path := str(doc.map_data.get("backgroundImage", "")).strip_edges()
	if path.is_empty():
		lbl.text = "Aucune image — le sol est généré depuis les tuiles de terrain."
		return
	var px := MapData.get_image_pixel_size(path)
	var night_path := MapData.resolve_night_image_path(doc.map_data)
	var night_note := ""
	if MapData.night_image_exists(doc.map_data):
		night_note = " · nuit : %s" % night_path.get_file()
	elif not path.is_empty():
		night_note = " · nuit procédurale (pas de *_night.png)"
	if px != Vector2i.ZERO:
		lbl.text = "Fond : %s (%d×%d px)%s" % [path.get_file(), px.x, px.y, night_note]
	else:
		lbl.text = "Fond : %s%s" % [path.get_file(), night_note]

func _on_background_imported(path: String) -> void:
	var map_id := str(doc.map_data.get("id", ""))
	if map_id.is_empty():
		return
	var grid_px := int(_get_spin("grid_size"))
	var cells := MapData.suggest_cells_from_image(path, grid_px)
	var dest := MapData.import_background_image(map_id, path)
	if dest.is_empty():
		_set_status("Import impossible.")
		return
	doc.begin_transaction()
	doc.set_meta_values({"backgroundImage": dest, "groundMode": MapData.GROUND_ILLUSTRATED}, "Fond de carte")
	doc.commit_transaction()
	if cells != Vector2i.ZERO:
		doc.resize_grid(cells.x, cells.y)
	_sync_settings_ui()
	_sync_engine(true)
	_set_status("Battlemap importée : %s" % dest.get_file())

func _on_overlay_imported(path: String) -> void:
	var map_id := str(doc.map_data.get("id", ""))
	if map_id.is_empty():
		return
	var dest := MapData.import_elevation_overlay(map_id, path)
	if dest.is_empty():
		return
	# L'import a écrit dans MapData : on récupère le calque et on le rejoue
	# à travers le document pour qu'il entre dans l'historique.
	var stored := MapData.get_by_id(map_id)
	var layers: Array = stored.get("elevationLayers", [])
	if layers.is_empty():
		return
	var last: Dictionary = layers[layers.size() - 1]
	doc.add_element({
		"image": str(last.get("image", dest)),
		"opacity": float(last.get("opacity", 0.92)),
		"elevation": float(last.get("elevation", 0.18)),
		"mapWidth": int(last.get("mapWidth", doc.map_data.get("width", 16))),
		"mapHeight": int(last.get("mapHeight", doc.map_data.get("height", 12))),
		"x": 0.0, "y": 0.0,
		"w": float(last.get("mapWidth", doc.map_data.get("width", 16))),
		"h": float(last.get("mapHeight", doc.map_data.get("height", 12))),
		"label": dest.get_file(),
		"layer": 1,
	}, DocumentScript.KIND_OVERLAY, "Calque")
	_sync_engine()
	_set_status("Calque ajouté : %s" % dest.get_file())

func _remove_background() -> void:
	var map_id := str(doc.map_data.get("id", ""))
	if not map_id.is_empty():
		MapData.clear_background_image(map_id)
	doc.set_meta_values({"backgroundImage": "", "groundMode": MapData.GROUND_TERRAIN3D}, "Fond de carte")
	_sync_settings_ui()
	_sync_engine()

func _on_export_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Export impossible : %s" % path)
		return
	file.store_string(JSON.stringify(apply_to_map_data(), "\t"))
	_set_status("Carte exportée : %s" % path.get_file())

func _on_import_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_set_status("Fichier JSON invalide.")
		return
	var imported: Dictionary = parsed
	# On conserve l'identité de la carte courante pour ne pas casser les liens.
	imported["id"] = doc.map_data.get("id", imported.get("id", ""))
	doc.load_map(imported)
	_sync_settings_ui()
	_rebuild_palettes()
	_sync_engine(true)
	_refresh_panels()
	_set_status("Carte importée depuis %s" % path.get_file())

func _trigger_all_effects() -> void:
	doc.begin_transaction()
	for elem_variant in doc.elements_of_kind(DocumentScript.KIND_EFFECT):
		var elem: Dictionary = elem_variant
		doc.modify_element(str(elem.get("id", "")), {"triggered": true}, "Déclenchement")
	doc.commit_transaction()
	_sync_engine()
	_refresh_effect_list()

func _trigger_effect(effect_id: String) -> void:
	if effect_id.is_empty() or not doc.has_element(effect_id):
		return
	doc.modify_element(effect_id, {"triggered": true}, "Déclenchement")
	_sync_engine()
	_refresh_effect_list()

func _refresh_effect_list() -> void:
	if _effect_list == null:
		return
	for child in _effect_list.get_children():
		child.queue_free()
	var effects: Array = doc.elements_of_kind(DocumentScript.KIND_EFFECT)
	if effects.is_empty():
		var empty := Label.new()
		empty.text = "Aucun effet sur la carte."
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		_effect_list.add_child(empty)
		return
	for elem_variant in effects:
		var elem: Dictionary = elem_variant
		var eid := str(elem.get("id", ""))
		var preset := MapEffectPresetsScript.get_preset(str(elem.get("preset", "fire")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_effect_list.add_child(row)
		var lbl := Label.new()
		var active := "●" if bool(elem.get("triggered", false)) else "○"
		lbl.text = "%s %s %s" % [active, preset.get("emoji", "✨"), elem.get("label", preset.get("label", "Effet"))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.clip_text = true
		row.add_child(lbl)
		var trig := Button.new()
		trig.text = "▶"
		trig.tooltip_text = "Déclencher cet effet"
		trig.custom_minimum_size = Vector2(28, 24)
		trig.pressed.connect(func(): _trigger_effect(eid))
		row.add_child(trig)
		var sel := Button.new()
		sel.text = "◎"
		sel.tooltip_text = "Sélectionner"
		sel.custom_minimum_size = Vector2(28, 24)
		sel.pressed.connect(func():
			doc.select_only(eid)
			_set_tool(ToolsScript.SELECT)
		)
		row.add_child(sel)

func _make_status_chip(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	return lbl

func _save_policy_label() -> String:
	match _save_policy:
		SAVE_ON_CHANGE:
			return "À chaque modif"
		SAVE_INTERVAL:
			return "Toutes les 30 s"
		_:
			return "Manuelle"

func _refresh_status_badges() -> void:
	if _policy_chip:
		_policy_chip.text = "💾 %s" % _save_policy_label()
	if _saved_ago_lbl:
		if _last_saved_at <= 0.0:
			_saved_ago_lbl.text = "jamais sauvé"
		else:
			var ago := int(Time.get_unix_time_from_system() - _last_saved_at)
			if ago < 5:
				_saved_ago_lbl.text = "sauvé à l'instant"
			elif ago < 60:
				_saved_ago_lbl.text = "sauvé il y a %ds" % ago
			elif ago < 3600:
				_saved_ago_lbl.text = "sauvé il y a %d min" % int(ago / 60.0)
			else:
				_saved_ago_lbl.text = "sauvé il y a %d h" % int(ago / 3600.0)
	if _autosave_lbl:
		if _save_policy == SAVE_INTERVAL and _autosave_timer and not _autosave_timer.is_stopped():
			_autosave_lbl.visible = true
			_autosave_lbl.text = "⏱ %ds" % maxi(0, int(ceil(_autosave_timer.time_left)))
		else:
			_autosave_lbl.visible = false
	if _undo_depth_lbl:
		var depth := doc.undo_depth() if doc.has_method("undo_depth") else 0
		_undo_depth_lbl.text = "↶ %d" % depth
		_undo_depth_lbl.tooltip_text = "%d action(s) annulable(s)" % depth

# ===========================================================================
# Palettes contextuelles
# ===========================================================================

func _rebuild_palettes() -> void:
	var marker_box: VBoxContainer = _settings_widgets.get("marker_box")
	if marker_box:
		for child in marker_box.get_children():
			child.queue_free()
		for marker_id_variant in MapData.get_editor_marker_types(doc.map_data):
			var marker_id := str(marker_id_variant)
			var btn := Button.new()
			btn.text = "%s %s" % [MapData.get_marker_emoji(marker_id), MapData.get_marker_label(marker_id)]
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 28)
			btn.pressed.connect(func():
				_marker_type = marker_id
				_set_tool(ToolsScript.MARKER)
			)
			marker_box.add_child(btn)

	var tile_box: VBoxContainer = _settings_widgets.get("tile_box")
	if tile_box:
		for child in tile_box.get_children():
			child.queue_free()
		var palette: Dictionary = MapData.get_tile_palette(doc.map_data)
		for tile_id_variant in palette.keys():
			var tile_id := str(tile_id_variant)
			var def: Dictionary = palette[tile_id]
			var btn := Button.new()
			btn.text = str(def.get("label", tile_id))
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(0, 28)
			var style := StyleBoxFlat.new()
			style.bg_color = Color.html(str(def.get("color", "#444444")))
			style.set_corner_radius_all(3)
			style.content_margin_left = 8
			btn.add_theme_stylebox_override("normal", style)
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.pressed.connect(func():
				_paint_tile = tile_id
				_set_tool(ToolsScript.PAINT)
			)
			tile_box.add_child(btn)

func _rebuild_tool_options() -> void:
	if _tool_options == null:
		return
	for child in _tool_options.get_children():
		child.queue_free()
	if _tool == ToolsScript.TOKEN:
		_spin(_hbox(_tool_options), "Taille", 0.5, 6.0, _token_size, 0.5, func(v): _token_size = v)
		_line_row(_hbox(_tool_options), "Nom", _token_label, func(text): _token_label = text)
		var kind_col := VBoxContainer.new()
		kind_col.add_theme_constant_override("separation", 1)
		kind_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hbox(_tool_options).add_child(kind_col)
		var kind_lbl := Label.new()
		kind_lbl.text = "Type"
		kind_lbl.add_theme_font_size_override("font_size", 10)
		kind_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		kind_col.add_child(kind_lbl)
		var kind_opt := OptionButton.new()
		for kind_entry in [["member", "Joueur"], ["npc", "PNJ"], ["monster", "Monstre"]]:
			var idx := kind_opt.item_count
			kind_opt.add_item(str(kind_entry[1]), idx)
			kind_opt.set_item_metadata(idx, str(kind_entry[0]))
			if str(kind_entry[0]) == _token_kind:
				kind_opt.select(idx)
		kind_opt.item_selected.connect(func(index: int):
			_token_kind = str(kind_opt.get_item_metadata(index))
			_rebuild_tool_options()
		)
		kind_col.add_child(kind_opt)
		if _token_kind == "npc":
			_line_row(_hbox(_tool_options), "Dialogue", _token_dialogue, func(text): _token_dialogue = text)
	elif _tool == ToolsScript.MARKER:
		_option_note("Type : %s %s" % [MapData.get_marker_emoji(_marker_type), MapData.get_marker_label(_marker_type)])
	elif _tool == ToolsScript.EFFECT:
		_spin(_hbox(_tool_options), "Rayon", 0.25, 8.0, _effect_radius, 0.25, func(v): _effect_radius = v)
		_option_note("Preset : %s" % _effect_preset)
	elif _tool in [ToolsScript.ZONE, ToolsScript.ZONE_RECT, ToolsScript.ZONE_POLY]:
		_spin(_hbox(_tool_options), "Rayon", 0.25, 12.0, _zone_radius, 0.25, func(v): _zone_radius = v)
		_line_row(_hbox(_tool_options), "Nom", _zone_label, func(text): _zone_label = text)
	elif _tool == ToolsScript.PROP:
		if _prop_asset.is_empty():
			_option_note("Aucun décor sélectionné. Ouvrez l'onglet Biblio pour en choisir un.")
		else:
			_option_note("Décor : %s" % _prop_asset.get_file())
		_spin(_hbox(_tool_options), "Taille (cases)", 0.25, 40.0, _prop_size, 0.25, func(v):
			_prop_size = v
			_refresh_ghost()
		)
		_checkbox(_tool_options, "Dressé face caméra", _prop_standing, func(on):
			_prop_standing = on
			_refresh_ghost()
		)
		_option_note("Rotation : %d° (R pour pivoter)" % int(_prop_rotation))
	elif _tool == ToolsScript.MESH:
		if _mesh_asset.is_empty():
			_option_note("Aucun objet 3D sélectionné. Ouvrez l'onglet Biblio → Objets 3D.")
		else:
			_option_note("Objet 3D : %s" % _mesh_asset.get_file())
		_spin(_hbox(_tool_options), "Échelle", 0.1, 10.0, _mesh_scale, 0.1, func(v):
			_mesh_scale = v
			_refresh_ghost()
		)
		var snap_chk := CheckBox.new()
		snap_chk.text = "Aimantation aux bâtiments"
		snap_chk.button_pressed = _mesh_snap_modules
		snap_chk.tooltip_text = "Toits et façades se posent automatiquement sur le bâtiment le plus proche."
		snap_chk.toggled.connect(func(on): _mesh_snap_modules = on)
		_tool_options.add_child(snap_chk)
		_option_note("Rotation : %d° (R pour pivoter)" % int(_mesh_rotation))
	elif _tool == ToolsScript.AREA:
		_line_row(_hbox(_tool_options), "Nom du lieu", _area_label, func(text): _area_label = text)
		var cat := OptionButton.new()
		for i in range(MapData.AREA_CATEGORIES.size()):
			var category: Dictionary = MapData.AREA_CATEGORIES[i]
			cat.add_item("%s %s" % [category["icon"], category["label"]], i)
			cat.set_item_metadata(i, str(category["id"]))
			if str(category["id"]) == _area_category:
				cat.select(i)
		cat.item_selected.connect(func(index): _area_category = str(cat.get_item_metadata(index)))
		_tool_options.add_child(cat)
		_option_note("Glissez pour délimiter le lieu, puis reliez-lui une carte depuis l'inspecteur.")
	elif _tool == ToolsScript.PAINT:
		_spin(_hbox(_tool_options), "Pinceau", 0, 6, float(_brush_size), 1, func(v): _brush_size = int(v))
		_option_note("Tuile : %s" % _paint_tile)
	elif _tool == ToolsScript.TERRAIN_HEIGHT:
		var mode_opt := OptionButton.new()
		var relief_modes := [
			["raise", "Monter"], ["lower", "Baisser"],
			["flatten", "Aplatir"], ["smooth", "Lisser"],
		]
		for i in range(relief_modes.size()):
			mode_opt.add_item(str(relief_modes[i][1]), i)
			mode_opt.set_item_metadata(i, str(relief_modes[i][0]))
			if str(relief_modes[i][0]) == _relief_mode:
				mode_opt.select(i)
		mode_opt.item_selected.connect(func(index):
			_relief_mode = str(mode_opt.get_item_metadata(index))
		)
		_tool_options.add_child(mode_opt)
		_spin(_hbox(_tool_options), "Pinceau (cases)", 0.5, 8.0, _relief_radius, 0.5, func(v):
			_relief_radius = v
			_refresh_ghost()
		)
		_spin(_hbox(_tool_options), "Force (cases)", 0.05, 2.0, _relief_strength, 0.05, func(v):
			_relief_strength = v
		)
		var flatten_btn := Button.new()
		flatten_btn.text = "Niveler tout"
		flatten_btn.tooltip_text = "Remet toutes les hauteurs à zéro (annulable)."
		flatten_btn.add_theme_font_size_override("font_size", 10)
		flatten_btn.pressed.connect(func():
			doc.clear_all_terrain()
			_sync_engine()
			_set_status("Relief nivelé à zéro.")
		)
		_tool_options.add_child(flatten_btn)
		_option_note("Les objets 3D posés s'adaptent à la hauteur du terrain. Le relief est enregistré avec la carte.")
	elif _tool == ToolsScript.GROUND_MATERIAL:
		var mat_opt := OptionButton.new()
		var materials := [
			[DocumentScript.MATERIAL_GRASS, "Herbe", "🌿"],
			[DocumentScript.MATERIAL_DIRT, "Terre / chemin", "🟫"],
			[DocumentScript.MATERIAL_STONE, "Pierre / pavé", "🪨"],
			[DocumentScript.MATERIAL_SNOW, "Neige", "❄️"],
			[DocumentScript.MATERIAL_SAND, "Sable", "🏖️"],
		]
		for i in range(materials.size()):
			mat_opt.add_item("%s %s" % [materials[i][2], materials[i][1]], int(materials[i][0]))
			mat_opt.set_item_metadata(i, int(materials[i][0]))
			if int(materials[i][0]) == _material_id:
				mat_opt.select(i)
		mat_opt.item_selected.connect(func(index):
			_material_id = int(mat_opt.get_item_metadata(index))
		)
		_tool_options.add_child(mat_opt)
		_spin(_hbox(_tool_options), "Pinceau (cases)", 0.5, 8.0, _material_radius, 0.5, func(v):
			_material_radius = v
			_refresh_ghost()
		)
		var fill_mat_btn := Button.new()
		fill_mat_btn.text = "Remplir tout"
		fill_mat_btn.tooltip_text = "Applique la matière choisie à toute la carte (annulable)."
		fill_mat_btn.add_theme_font_size_override("font_size", 10)
		fill_mat_btn.pressed.connect(func():
			doc.fill_all_material(_material_id)
			_sync_engine()
			_set_status("Sol entièrement repeint.")
		)
		_tool_options.add_child(fill_mat_btn)
		_option_note("Peint la matière du sol. La carte doit être en mode sol 3D (terrain3d). Matière enregistrée avec la carte.")
	elif _tool == ToolsScript.FOG_REVEAL or _tool == ToolsScript.FOG_HIDE:
		_spin(_hbox(_tool_options), "Pinceau", 0, 6, float(_fog_brush), 1, func(v): _fog_brush = int(v))
	elif _tool == ToolsScript.TEMPLATE:
		_option_note("Template : %s (rotation %d°)" % [
			_selected_template if not _selected_template.is_empty() else "aucun",
			_template_rotation * 90,
		])
	else:
		_option_note(ToolsScript.hint(_tool))

func _option_note(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_tool_options.add_child(lbl)

# ===========================================================================
# Statut & aide
# ===========================================================================

func _set_status(text: String) -> void:
	if _status_lbl:
		_status_lbl.text = text

func _update_status_position(grid: Vector2) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = "Case (%.1f, %.1f) · %d sélectionné(s) · %s" % [
		grid.x, grid.y, doc.selection_size(), ToolsScript.label(_tool)
	]

func _update_status_selection() -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = "%d élément(s) sélectionné(s)" % doc.selection_size()

func _update_hint() -> void:
	if _hint_lbl == null:
		return
	if not _editable:
		_hint_lbl.text = "Aperçu 3D — molette pour zoomer, clic milieu pour déplacer la vue."
		return
	_hint_lbl.text = "%s %s — %s" % [ToolsScript.icon(_tool), ToolsScript.label(_tool), ToolsScript.hint(_tool)]

func _update_zoom_label() -> void:
	if _zoom_lbl and _engine:
		_zoom_lbl.text = "%d%%" % int(round(_engine.zoom * 100.0))

func _default_tile() -> String:
	if MapData.is_world_map(doc.map_data):
		return "plains"
	if str(doc.map_data.get("roster", "")) == "investigation":
		return "street"
	return "floor"

func _first_marker_type() -> String:
	var types: Array = MapData.get_editor_marker_types(doc.map_data)
	return str(types[0]) if not types.is_empty() else "npc"

# ===========================================================================
# Fabrique de widgets
# ===========================================================================

func _section(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)

func _hbox(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row

func _icon_button(parent: Control, text: String, tooltip: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(32, 28)
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn

func _text_button(parent: Control, text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn

func _spin(parent: Control, label_text: String, min_v: float, max_v: float, value: float, step: float, on_change: Callable) -> SpinBox:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	col.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.set_value_no_signal(clampf(value, min_v, max_v))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(v): on_change.call(v))
	col.add_child(spin)
	return spin

func _checkbox(parent: Control, text: String, value: bool, on_change: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.set_pressed_no_signal(value)
	check.add_theme_font_size_override("font_size", 11)
	check.toggled.connect(func(on): on_change.call(on))
	parent.add_child(check)
	return check

func _line_row(parent: Control, label_text: String, value: String, on_change: Callable) -> LineEdit:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	col.add_child(lbl)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text): on_change.call(text))
	edit.focus_exited.connect(func(): on_change.call(edit.text))
	col.add_child(edit)
	return edit

func _color_row(parent: Control, label_text: String, value: String, on_change: Callable) -> ColorPickerButton:
	var row := _hbox(parent)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(64, 26)
	picker.edit_alpha = false
	picker.color = Color.html(value) if not value.is_empty() else Color.WHITE
	picker.color_changed.connect(func(color): on_change.call("#" + color.to_html(false)))
	row.add_child(picker)
	return picker

# --- Accès typés aux widgets de réglage ---------------------------------------

func _set_spin(key: String, value: float) -> void:
	var spin: SpinBox = _settings_widgets.get(key)
	if spin:
		spin.set_value_no_signal(clampf(value, spin.min_value, spin.max_value))

func _get_spin(key: String) -> float:
	var spin: SpinBox = _settings_widgets.get(key)
	return spin.value if spin else 0.0

func _set_check(key: String, value: bool) -> void:
	var check: CheckBox = _settings_widgets.get(key)
	if check:
		check.set_pressed_no_signal(value)

func _get_check(key: String) -> bool:
	var check: CheckBox = _settings_widgets.get(key)
	return check.button_pressed if check else false

func _set_line(key: String, value: String) -> void:
	var edit: LineEdit = _settings_widgets.get(key)
	if edit:
		edit.text = value

func _get_line(key: String) -> String:
	var edit: LineEdit = _settings_widgets.get(key)
	return edit.text.strip_edges() if edit else ""

func _set_color(key: String, value: String) -> void:
	var picker: ColorPickerButton = _settings_widgets.get(key)
	if picker and not value.is_empty():
		picker.color = Color.html(value)

func _get_color(key: String) -> String:
	var picker: ColorPickerButton = _settings_widgets.get(key)
	return "#" + picker.color.to_html(false) if picker else "#ffffff"

func _select_metadata(key: String, value: String) -> void:
	var option: OptionButton = _settings_widgets.get(key)
	if option == null:
		return
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == value:
			option.select(i)
			return
