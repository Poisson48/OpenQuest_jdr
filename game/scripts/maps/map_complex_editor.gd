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

const SAVE_MANUAL := "manual"
const SAVE_ON_CHANGE := "on_change"
const SAVE_INTERVAL := "interval"

# --- État --------------------------------------------------------------------
var doc: MapEditDocument = MapEditDocument.new()
var _editable: bool = true
var _tool: String = ToolsScript.SELECT
var _snap_mode: String = "cell"
var _save_policy: String = SAVE_MANUAL
var _save_interval: float = 30.0

var _effect_preset: String = "fire"
var _marker_type: String = "npc"
var _member_index: int = 0
var _token_label: String = ""
var _token_size: float = 1.0
var _zone_radius: float = 1.5
var _zone_label: String = "Zone"
var _effect_radius: float = 1.0
var _brush_size: int = 0
var _fog_brush: int = 1
var _paint_tile: String = ""
var _selected_template: String = ""
var _area_category: String = "building"
var _area_label: String = ""
var _template_rotation: int = 0
var _space_held: bool = false
var _syncing: bool = false

# --- Interaction --------------------------------------------------------------
var _press_mode: String = "none"
var _press_start_grid: Vector2 = Vector2.ZERO
var _press_start_screen: Vector2 = Vector2.ZERO
var _press_moved: bool = false
var _drag_ids: Array = []
var _drag_origins: Dictionary = {}
var _link_source: String = ""
var _painted_cells: Dictionary = {}
var _band_base_selection: Array = []

# --- Nœuds --------------------------------------------------------------------
var _engine: Control
var _overlay: MapEditorOverlay
var _minimap: MapEditorMinimap
var _inspector: MapEditorInspector
var _outliner: MapEditorOutliner
var _left_panel: VBoxContainer
var _left_scroll: ScrollContainer
var _right_tabs: TabContainer
var _right_scroll: ScrollContainer
var _tool_options: VBoxContainer
var _history_list: VBoxContainer
var _template_list: VBoxContainer
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
var _import_dialog: FileDialog
var _esc_menu: PopupPanel
var _template_name_dialog: AcceptDialog
var _template_name_input: LineEdit
var _settings_widgets: Dictionary = {}
var _split_outer: HSplitContainer
var _split_inner: HSplitContainer

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 640)
	focus_mode = Control.FOCUS_ALL
	doc.changed.connect(_on_doc_changed)
	doc.selection_changed.connect(_on_selection_changed)
	doc.history_changed.connect(_on_history_changed)
	doc.dirty_changed.connect(_on_dirty_changed)
	_build_ui()

# ===========================================================================
# API publique (consommée par map_viewer.gd)
# ===========================================================================

func set_editable(on: bool) -> void:
	_editable = on
	if _left_scroll:
		_left_scroll.visible = on
	if _right_scroll:
		_right_scroll.visible = on
	if _split_outer:
		_split_outer.split_offset = 250 if on else 0
	if _split_inner:
		_split_inner.split_offset = 0 if on else 0
	if _engine and _engine.has_method("set_editor_mode"):
		_engine.set_editor_mode(on)
	_sync_engine()
	_update_hint()

func load_map(map_data: Dictionary) -> void:
	doc.load_map(map_data)
	_paint_tile = _default_tile()
	_marker_type = _first_marker_type()
	_sync_settings_ui()
	_rebuild_palettes()
	_refresh_templates()
	_sync_engine(true)
	_refresh_panels()
	_update_hint()

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
	_set_status("Carte enregistrée.")
	layout_changed.emit()

# ===========================================================================
# Construction de l'interface
# ===========================================================================

func _build_ui() -> void:
	_split_outer = HSplitContainer.new()
	_split_outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_split_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split_outer.split_offset = 250
	add_child(_split_outer)

	_build_left_column()

	_split_inner = HSplitContainer.new()
	_split_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split_inner.split_offset = -320
	_split_outer.add_child(_split_inner)

	_build_center_column()
	_build_right_column()
	_build_dialogs()
	_minimap.set_context(_engine, doc)

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = _save_interval
	_autosave_timer.timeout.connect(func():
		if _save_policy == SAVE_INTERVAL and doc.is_dirty():
			save_now()
	)
	add_child(_autosave_timer)

	_set_tool(ToolsScript.SELECT)

# --- Colonne gauche : outils --------------------------------------------------

func _build_left_column() -> void:
	_left_scroll = ScrollContainer.new()
	_left_scroll.custom_minimum_size = Vector2(240, 0)
	_left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_split_outer.add_child(_left_scroll)

	_left_panel = VBoxContainer.new()
	_left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_panel.add_theme_constant_override("separation", 6)
	_left_scroll.add_child(_left_panel)

	for group in ToolsScript.GROUP_ORDER:
		_section(_left_panel, str(ToolsScript.GROUP_LABELS.get(group, group)))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		_left_panel.add_child(grid)
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

	_section(_left_panel, "⚙️ Options de l'outil")
	_tool_options = VBoxContainer.new()
	_tool_options.add_theme_constant_override("separation", 4)
	_left_panel.add_child(_tool_options)

	_section(_left_panel, "🧲 Aimantation")
	var snap_option := OptionButton.new()
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
	_left_panel.add_child(snap_option)

	_section(_left_panel, "🗺 Mini-carte")
	_minimap = MinimapScript.new()
	_minimap.jump_requested.connect(func(grid_pos: Vector2):
		if _engine and _engine.has_method("center_on_grid"):
			_engine.center_on_grid(grid_pos.x - 0.5, grid_pos.y - 0.5)
			_refresh_overlay()
	)
	_left_panel.add_child(_minimap)

# --- Colonne centrale : vue 3D -------------------------------------------------

func _build_center_column() -> void:
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	_split_inner.add_child(center)

	center.add_child(_build_action_bar())

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_INPUT
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(320, 460)
	frame.clip_contents = true
	center.add_child(frame)

	var stack := Control.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(stack)

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

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 10)
	center.add_child(status_row)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.clip_text = true
	status_row.add_child(_status_lbl)

	_hint_lbl = Label.new()
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_font_size_override("font_size", 11)
	_hint_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	center.add_child(_hint_lbl)

func _build_action_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)

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
	_icon_button(bar, "⇕", "Centrer verticalement", func(): doc.align_selection("center_v"))
	_icon_button(bar, "↔", "Distribuer horizontalement", func(): doc.distribute_selection(true))

	bar.add_child(VSeparator.new())
	_breadcrumb = HBoxContainer.new()
	_breadcrumb.add_theme_constant_override("separation", 2)
	bar.add_child(_breadcrumb)

	_dirty_lbl = Label.new()
	_dirty_lbl.add_theme_font_size_override("font_size", 11)
	_dirty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_dirty_lbl)

	_icon_button(bar, "−", "Dézoomer", func(): _engine.zoom_out())
	_zoom_lbl = Label.new()
	_zoom_lbl.text = "100%"
	_zoom_lbl.custom_minimum_size = Vector2(46, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	bar.add_child(_zoom_lbl)
	_icon_button(bar, "+", "Zoomer", func(): _engine.zoom_in())
	_icon_button(bar, "⟲", "Recadrer sur la carte", func(): _engine.reset_zoom())
	_icon_button(bar, "🎯", "Recadrer sur la sélection (F)", func(): _focus_selection())
	_icon_button(bar, "☰", "Menu éditeur (Échap)", func(): _open_esc_menu())
	return bar

# --- Colonne droite : panneaux -------------------------------------------------

func _build_right_column() -> void:
	_right_scroll = ScrollContainer.new()
	_right_scroll.custom_minimum_size = Vector2(310, 0)
	_right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_split_inner.add_child(_right_scroll)

	_right_tabs = TabContainer.new()
	_right_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_tabs.custom_minimum_size = Vector2(300, 520)
	_right_scroll.add_child(_right_tabs)

	_inspector = InspectorScript.new()
	_inspector.name = "Inspecteur"
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
	_right_tabs.add_child(_wrap_scroll(_inspector, "Inspecteur"))

	_outliner = OutlinerScript.new()
	_outliner.name = "Calques"
	_outliner.set_document(doc)
	_outliner.focus_requested.connect(_focus_element)
	_right_tabs.add_child(_wrap_scroll(_outliner, "Calques"))

	_right_tabs.add_child(_build_map_settings_tab())
	_right_tabs.add_child(_build_library_tab())
	_right_tabs.add_child(_build_history_tab())

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

func _build_map_settings_tab() -> ScrollContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)

	_section(box, "🖼 Fond de carte")
	var bg_status := Label.new()
	bg_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg_status.add_theme_font_size_override("font_size", 11)
	bg_status.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	box.add_child(bg_status)
	_settings_widgets["bg_status"] = bg_status

	var bg_row := HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 4)
	box.add_child(bg_row)
	_text_button(bg_row, "Importer PNG…", func(): _file_dialog.popup_centered(Vector2i(760, 500)))
	_text_button(bg_row, "Calque +", func(): _overlay_dialog.popup_centered(Vector2i(760, 500)))
	_text_button(bg_row, "✕", func(): _remove_background())

	_section(box, "📐 Dimensions (cases)")
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	box.add_child(size_row)
	_settings_widgets["width"] = _spin(size_row, "Largeur", 4, 128, 16, 1, func(v): _on_size_changed())
	_settings_widgets["height"] = _spin(size_row, "Hauteur", 4, 128, 12, 1, func(v): _on_size_changed())

	_section(box, "⊞ Grille")
	_settings_widgets["grid_enabled"] = _checkbox(box, "Afficher la grille", true, func(_on): _on_grid_changed())
	var grid_row := HBoxContainer.new()
	grid_row.add_theme_constant_override("separation", 6)
	box.add_child(grid_row)
	_settings_widgets["grid_size"] = _spin(grid_row, "Taille px", 20, 160, 70, 1, func(v): _on_grid_changed())
	_settings_widgets["grid_opacity"] = _spin(grid_row, "Opacité", 0.0, 1.0, 0.22, 0.01, func(v): _on_grid_changed())
	_settings_widgets["grid_color"] = _color_row(box, "Couleur", "#ffffff", func(hex): _on_grid_changed())

	_section(box, "📏 Échelle")
	var measure_row := HBoxContainer.new()
	measure_row.add_theme_constant_override("separation", 6)
	box.add_child(measure_row)
	_settings_widgets["measure_per_cell"] = _spin(measure_row, "Par case", 0.1, 100.0, 1.5, 0.1, func(v): _on_measure_changed())
	_settings_widgets["measure_unit"] = _line_row(measure_row, "Unité", "m", func(text): _on_measure_changed())

	_section(box, "🌫 Brouillard de guerre")
	_settings_widgets["fog_enabled"] = _checkbox(box, "Activer le brouillard", true, func(_on): _on_fog_setting_changed())
	_settings_widgets["los_enabled"] = _checkbox(box, "Ligne de vue (murs bloquants)", false, func(_on): _on_los_changed())
	var los_note := Label.new()
	los_note.text = "En session, le brouillard se révèle automatiquement selon ce que voient les tokens, murs et portes compris."
	los_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	los_note.add_theme_font_size_override("font_size", 10)
	los_note.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	box.add_child(los_note)
	var fog_row := HBoxContainer.new()
	fog_row.add_theme_constant_override("separation", 4)
	box.add_child(fog_row)
	_text_button(fog_row, "Tout masquer", func(): doc.set_fog_cells([], "Brouillard total"))
	_text_button(fog_row, "Tout révéler", func(): doc.reveal_all_fog())

	_section(box, "📷 Perspective")
	var persp := OptionButton.new()
	persp.add_item("Vue de dessus", 0)
	persp.set_item_metadata(0, MapData.PERSPECTIVE_TOPDOWN)
	persp.add_item("Isométrique", 1)
	persp.set_item_metadata(1, MapData.PERSPECTIVE_ISOMETRIC)
	persp.add_item("Perspective inclinée", 2)
	persp.set_item_metadata(2, MapData.PERSPECTIVE_TILT)
	persp.item_selected.connect(func(_i): _on_perspective_changed())
	box.add_child(persp)
	_settings_widgets["perspective"] = persp

	_section(box, "🌘 Atmosphère")
	_settings_widgets["atmo_enabled"] = _checkbox(box, "Teinte d'ambiance", false, func(_on): _on_atmosphere_changed())
	_settings_widgets["atmo_tint"] = _color_row(box, "Teinte", "#141018", func(hex): _on_atmosphere_changed())
	var atmo_row := HBoxContainer.new()
	atmo_row.add_theme_constant_override("separation", 6)
	box.add_child(atmo_row)
	_settings_widgets["atmo_opacity"] = _spin(atmo_row, "Opacité", 0.0, 1.0, 0.12, 0.01, func(v): _on_atmosphere_changed())
	_settings_widgets["atmo_vignette"] = _spin(atmo_row, "Vignettage", 0.0, 1.0, 0.18, 0.01, func(v): _on_atmosphere_changed())

	_section(box, "💡 Éclairage global")
	_settings_widgets["light_enabled"] = _checkbox(box, "Éclairage directionnel", false, func(_on): _on_lighting_changed())
	var light_dir := OptionButton.new()
	var dirs := ["nw", "ne", "sw", "se"]
	var dir_labels := ["Nord-Ouest", "Nord-Est", "Sud-Ouest", "Sud-Est"]
	for i in range(dirs.size()):
		light_dir.add_item(dir_labels[i], i)
		light_dir.set_item_metadata(i, dirs[i])
	light_dir.item_selected.connect(func(_i): _on_lighting_changed())
	box.add_child(light_dir)
	_settings_widgets["light_dir"] = light_dir
	_settings_widgets["light_intensity"] = _spin(_hbox(box), "Intensité", 0.0, 2.0, 0.35, 0.05, func(v): _on_lighting_changed())

	_section(box, "👁 Affichage éditeur")
	_checkbox(box, "Afficher les liens", true, func(on):
		_overlay.show_links = on
		_refresh_overlay()
	)
	_checkbox(box, "Afficher les noms", false, func(on):
		_overlay.show_ids = on
		_refresh_overlay()
	)
	_checkbox(box, "Aperçu ligne de vue", false, func(on):
		_overlay.show_vision = on
		_refresh_vision_preview()
	)

	_section(box, "💾 Sauvegarde")
	var policy := OptionButton.new()
	policy.add_item("Manuelle", 0)
	policy.set_item_metadata(0, SAVE_MANUAL)
	policy.add_item("À chaque modification", 1)
	policy.set_item_metadata(1, SAVE_ON_CHANGE)
	policy.add_item("Périodique (30 s)", 2)
	policy.set_item_metadata(2, SAVE_INTERVAL)
	policy.item_selected.connect(func(index):
		_save_policy = str(policy.get_item_metadata(index))
		if _save_policy == SAVE_INTERVAL:
			_autosave_timer.start(_save_interval)
		else:
			_autosave_timer.stop()
		_set_status("Politique de sauvegarde : %s" % policy.get_item_text(index))
	)
	box.add_child(policy)

	var io_row := HBoxContainer.new()
	io_row.add_theme_constant_override("separation", 4)
	box.add_child(io_row)
	_text_button(io_row, "⬆ Exporter JSON", func(): _export_dialog.popup_centered(Vector2i(760, 500)))
	_text_button(io_row, "⬇ Importer JSON", func(): _import_dialog.popup_centered(Vector2i(760, 500)))

	return _wrap_scroll(box, "Carte")

# ===========================================================================
# Onglet « Bibliothèque »
# ===========================================================================

func _build_library_tab() -> ScrollContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)

	_section(box, "🧍 Tokens")
	var member_grid := GridContainer.new()
	member_grid.columns = 6
	member_grid.add_theme_constant_override("h_separation", 3)
	box.add_child(member_grid)
	_settings_widgets["member_grid"] = member_grid
	for i in range(MapData.MEMBER_COLOR_HEX.size()):
		var index := i
		var btn := Button.new()
		btn.text = str(MapData.MEMBER_PLAYER_EMOJIS_GENERAL[i % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()])
		btn.toggle_mode = true
		btn.button_pressed = i == 0
		btn.custom_minimum_size = Vector2(38, 32)
		btn.tooltip_text = "Couleur de token %d" % (i + 1)
		btn.pressed.connect(func():
			_member_index = index
			for child in member_grid.get_children():
				if child is Button:
					(child as Button).button_pressed = false
			btn.button_pressed = true
			_set_tool(ToolsScript.TOKEN)
		)
		member_grid.add_child(btn)

	_section(box, "📍 Marqueurs")
	var marker_box := VBoxContainer.new()
	marker_box.add_theme_constant_override("separation", 2)
	box.add_child(marker_box)
	_settings_widgets["marker_box"] = marker_box

	_section(box, "✨ Effets")
	var fx_grid := GridContainer.new()
	fx_grid.columns = 4
	fx_grid.add_theme_constant_override("h_separation", 3)
	box.add_child(fx_grid)
	for preset_id_variant in MapEffectPresetsScript.PRESET_IDS:
		var preset_id := str(preset_id_variant)
		var preset := MapEffectPresetsScript.get_preset(preset_id)
		var btn := Button.new()
		btn.text = str(preset.get("emoji", "✨"))
		btn.tooltip_text = str(preset.get("label", preset_id))
		btn.custom_minimum_size = Vector2(42, 32)
		btn.pressed.connect(func():
			_effect_preset = preset_id
			_set_tool(ToolsScript.EFFECT)
		)
		fx_grid.add_child(btn)
	_text_button(box, "▶ Déclencher tous les effets", func(): _trigger_all_effects())

	_section(box, "🎨 Terrain")
	var tile_box := VBoxContainer.new()
	tile_box.add_theme_constant_override("separation", 2)
	box.add_child(tile_box)
	_settings_widgets["tile_box"] = tile_box

	_section(box, "🧩 Templates")
	var tpl_actions := HBoxContainer.new()
	tpl_actions.add_theme_constant_override("separation", 4)
	box.add_child(tpl_actions)
	_text_button(tpl_actions, "＋ Depuis la sélection", func(): _prompt_save_template())
	_text_button(tpl_actions, "⟳", func(): _refresh_templates())
	_template_list = VBoxContainer.new()
	_template_list.add_theme_constant_override("separation", 2)
	box.add_child(_template_list)

	return _wrap_scroll(box, "Biblio")

# ===========================================================================
# Onglet « Historique »
# ===========================================================================

func _build_history_tab() -> ScrollContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_section(box, "🕘 Historique")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	_text_button(row, "↶ Annuler", func(): _do_undo())
	_text_button(row, "↷ Rétablir", func(): _do_redo())
	_history_list = VBoxContainer.new()
	_history_list.add_theme_constant_override("separation", 1)
	box.add_child(_history_list)

	_section(box, "⌨ Raccourcis")
	for entry_variant in ToolsScript.SHORTCUTS:
		var entry: Dictionary = entry_variant
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		box.add_child(line)
		var keys := Label.new()
		keys.text = str(entry["keys"])
		keys.custom_minimum_size = Vector2(120, 0)
		keys.add_theme_font_size_override("font_size", 11)
		keys.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		line.add_child(keys)
		var action := Label.new()
		action.text = str(entry["action"])
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.add_theme_font_size_override("font_size", 11)
		action.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		line.add_child(action)

	return _wrap_scroll(box, "Historique")

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

	_import_dialog = _make_file_dialog("Importer une carte", FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Carte JSON"])
	_import_dialog.file_selected.connect(_on_import_selected)

	_template_name_dialog = AcceptDialog.new()
	_template_name_dialog.title = "Nom du template"
	_template_name_dialog.dialog_hide_on_ok = true
	var name_box := VBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "Nom du template à créer depuis la sélection :"
	name_box.add_child(name_lbl)
	_template_name_input = LineEdit.new()
	_template_name_input.custom_minimum_size = Vector2(320, 0)
	name_box.add_child(_template_name_input)
	_template_name_dialog.add_child(name_box)
	_template_name_dialog.confirmed.connect(_on_template_name_confirmed)
	add_child(_template_name_dialog)

	_esc_menu = PopupPanel.new()
	var menu_box := VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 4)
	menu_box.custom_minimum_size = Vector2(280, 0)
	_esc_menu.add_child(menu_box)
	_section(menu_box, "☰ Menu éditeur")
	_text_button(menu_box, "💾 Enregistrer", func():
		save_now()
		_esc_menu.hide()
	)
	_text_button(menu_box, "↶ Annuler", func(): _do_undo())
	_text_button(menu_box, "↷ Rétablir", func(): _do_redo())
	_text_button(menu_box, "🎯 Recadrer sur la carte", func():
		_engine.reset_zoom()
		_esc_menu.hide()
	)
	_text_button(menu_box, "🧹 Vider la sélection", func():
		doc.clear_selection()
		_esc_menu.hide()
	)
	_text_button(menu_box, "⬆ Exporter JSON", func():
		_esc_menu.hide()
		_export_dialog.popup_centered(Vector2i(760, 500))
	)
	var help := Label.new()
	help.text = ToolsScript.shortcuts_text()
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	menu_box.add_child(help)
	add_child(_esc_menu)

func _make_file_dialog(title: String, mode: int, filters: Array) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(filters)
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
	var hit := _overlay.element_at_screen(screen)
	if hit.is_empty():
		_press_mode = "band"
		_overlay.band_active = true
		_overlay.band_start = screen
		_overlay.band_end = screen
		# Ctrl/Maj : le rectangle s'ajoute à la sélection existante.
		var additive := bool(mods.get("ctrl", false)) or bool(mods.get("shift", false))
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
	_press_mode = "move"
	_drag_ids = doc.selection()
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
			for id_variant in _drag_ids:
				var id := str(id_variant)
				var origin: Vector2 = _drag_origins.get(id, Vector2.ZERO)
				var target := _snap(origin + delta)
				doc.set_live_position(id, target.x, target.y)
				_engine.set_element_position(id, target.x, target.y)
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
	_refresh_ghost()
	_refresh_overlay()

func _on_pointer_released(grid: Vector2, _screen: Vector2, button: int, _mods: Dictionary) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	match _press_mode:
		"pan":
			_engine.end_view_pan()
		"band":
			_overlay.band_active = false
			_band_base_selection.clear()
		"move":
			if _press_moved:
				doc.commit_live_edit(_drag_ids, "Déplacement")
				_sync_engine()
			_drag_ids.clear()
			_drag_origins.clear()
		"draw":
			_finish_draw(_snap(grid))
		"paint":
			_painted_cells.clear()
	_press_mode = "none"
	_overlay.drag_preview.clear()
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
	if _press_mode == "move" and not _drag_ids.is_empty():
		doc.revert_live_edit(_drag_ids)
		_sync_engine()
	_press_mode = "none"
	_drag_ids.clear()
	_drag_origins.clear()
	_overlay.clear_transient()
	_link_source = ""
	_set_status("Action annulée.")

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
		_overlay.measure_active = true
		_overlay.measure_from = from
		_overlay.measure_to = to
		var cells := from.distance_to(to)
		var measure: Dictionary = doc.map_data.get("measure", {}) if doc.map_data.get("measure") is Dictionary else {}
		_set_status("Distance : %.2f cases · %.2f %s" % [
			cells, cells * float(measure.get("perCell", 1.5)), measure.get("unit", "m")])
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
	_sync_engine()

func _create_token(grid: Vector2) -> void:
	var label := _token_label
	if label.is_empty():
		label = "Token %d" % (doc.count_of_kind(MapEditDocument.KIND_TOKEN) + 1)
	var color: String = str(MapData.MEMBER_COLOR_HEX[_member_index % MapData.MEMBER_COLOR_HEX.size()])
	var emoji: String = str(MapData.MEMBER_PLAYER_EMOJIS_GENERAL[_member_index % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()])
	var id := doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": _token_size, "h": _token_size,
		"tokenKind": "member",
		"memberId": "editor-mock-%d" % _member_index,
		"memberIndex": _member_index,
		"label": label,
		"emoji": emoji,
		"color": color,
		"layer": 4,
	}, MapEditDocument.KIND_TOKEN, "Token")
	doc.select_only(id)

func _create_marker(grid: Vector2) -> void:
	var id := doc.add_element({
		"x": grid.x, "y": grid.y,
		"markerType": _marker_type,
		"label": MapData.get_marker_label(_marker_type),
		"layer": 3,
	}, MapEditDocument.KIND_MARKER, "Marqueur")
	doc.select_only(id)

func _create_effect(grid: Vector2) -> void:
	var preset := MapEffectPresetsScript.get_preset(_effect_preset)
	var id := doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": _effect_radius * 2.0, "h": _effect_radius * 2.0,
		"type": "particles",
		"preset": _effect_preset,
		"radius": _effect_radius,
		"triggered": true,
		"label": str(preset.get("label", _effect_preset)),
		"layer": 3,
	}, MapEditDocument.KIND_EFFECT, "Effet")
	doc.select_only(id)

func _create_circle_zone(grid: Vector2) -> void:
	var id := doc.add_element({
		"x": grid.x, "y": grid.y,
		"shape": "circle",
		"radius": _zone_radius,
		"w": _zone_radius * 2.0, "h": _zone_radius * 2.0,
		"label": _zone_label,
		"color": "#c9a227",
		"layer": 3,
	}, MapEditDocument.KIND_ZONE, "Zone")
	doc.select_only(id)

func _create_rect_zone(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	if rect.size.x < 0.25 or rect.size.y < 0.25:
		return
	var id := doc.add_element({
		"x": rect.get_center().x, "y": rect.get_center().y,
		"shape": "rect",
		"w": rect.size.x, "h": rect.size.y,
		"radius": maxf(rect.size.x, rect.size.y) * 0.5,
		"label": _zone_label,
		"color": "#c9a227",
		"layer": 3,
	}, MapEditDocument.KIND_ZONE, "Zone rectangulaire")
	doc.select_only(id)

## Un lieu délimite une portion de la carte illustrée : une taverne, une place,
## une sortie de village. Il porte un nom affiché en cartouche et peut ouvrir
## sa propre carte, où l'on place réellement les personnages.
func _create_area(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	if rect.size.x < 0.5 or rect.size.y < 0.5:
		rect = Rect2(from - Vector2(1.5, 1.5), Vector2(3.0, 3.0))
	var id := doc.add_element({
		"x": rect.get_center().x, "y": rect.get_center().y,
		"w": rect.size.x, "h": rect.size.y,
		"shape": "rect",
		"category": _area_category,
		"label": _area_label if not _area_label.is_empty() else "Nouveau lieu",
		"targetMapId": "",
		"showCallout": true,
		"labelOffset": {"x": 0.0, "y": -(rect.size.y * 0.5 + 0.8)},
		"layer": 5,
	}, MapEditDocument.KIND_AREA, "Lieu")
	doc.select_only(id)
	if _right_tabs:
		_right_tabs.current_tab = 0

func _create_platform(from: Vector2, to: Vector2) -> void:
	var rect := Rect2(from, to - from).abs()
	if rect.size.x < 0.5 or rect.size.y < 0.5:
		rect.size = Vector2(3, 3)
	var id := doc.add_element({
		"x": rect.position.x, "y": rect.position.y,
		"w": maxf(1.0, roundf(rect.size.x)), "h": maxf(1.0, roundf(rect.size.y)),
		"elevation": 1.0,
		"opacity": 0.38,
		"tint": "#8a7a60",
		"label": "Plateforme",
		"layer": 2,
	}, MapEditDocument.KIND_PLATFORM, "Plateforme")
	doc.select_only(id)

func _create_wall(from: Vector2, to: Vector2) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.4:
		return
	var id := doc.add_element({
		"x": (from.x + to.x) * 0.5, "y": (from.y + to.y) * 0.5,
		"w": length, "h": 0.25,
		"height": 1.4,
		"color": "#4a423a",
		"blocksSight": true,
		"label": "Mur",
		"layer": 2,
		"display": {"rotation": rad_to_deg(delta.angle())},
	}, MapEditDocument.KIND_WALL, "Mur")
	doc.select_only(id)

func _create_note(grid: Vector2) -> void:
	var id := doc.add_element({
		"x": grid.x, "y": grid.y,
		"label": "Note",
		"text": "",
		"layer": 5,
	}, MapEditDocument.KIND_NOTE, "Note")
	doc.select_only(id)
	if _right_tabs:
		_right_tabs.current_tab = 0

func _create_light(grid: Vector2) -> void:
	var id := doc.add_element({
		"x": grid.x, "y": grid.y,
		"radius": 3.0,
		"energy": 1.6,
		"color": "#ffb35c",
		"elevation": 0.6,
		"flicker": true,
		"label": "Lumière",
		"layer": 2,
	}, MapEditDocument.KIND_LIGHT, "Lumière")
	doc.select_only(id)

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
	var id := doc.add_element({
		"x": center.x, "y": center.y,
		"shape": "polygon",
		"points": serialized,
		"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
		"radius": maxf(max_p.x - min_p.x, max_p.y - min_p.y) * 0.5,
		"label": _zone_label,
		"color": "#7ad9a0",
		"layer": 3,
	}, MapEditDocument.KIND_ZONE, "Zone libre")
	doc.select_only(id)
	_sync_engine()

func _erase_at(screen: Vector2) -> void:
	var hit := _overlay.element_at_screen(screen)
	if hit.is_empty():
		return
	doc.remove_element(hit)
	_sync_engine()

func _handle_link_click(screen: Vector2) -> void:
	var hit := _overlay.element_at_screen(screen)
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
		new_ids.append(doc.add_element(elem, str(elem.get("kind", MapEditDocument.KIND_TOKEN)), "Template"))
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
			if _press_mode != "none" or not _overlay.polygon_points.is_empty() or not _link_source.is_empty():
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
			else:
				_apply_shortcut_tool(key)
				return
		_:
			_apply_shortcut_tool(key)
			return
	get_viewport().set_input_as_handled()

func _apply_shortcut_tool(key: InputEventKey) -> void:
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

func _open_esc_menu() -> void:
	if _esc_menu == null:
		return
	_esc_menu.popup_centered(Vector2i(320, 380))

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

func _focus_selection() -> void:
	var bounds := doc.selection_bounds()
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
	var snapshot := doc.to_map_data()
	var defaults: Dictionary = snapshot.get("playDefaults", {})
	var view_state: Dictionary = defaults.get("viewState", {}) if defaults.get("viewState") is Dictionary else {}
	_engine.set_snap_to_grid(_snap_mode == "cell")
	_engine.configure(
		snapshot,
		defaults.get("tokens", []),
		_mock_party(),
		defaults.get("effects", []),
		defaults.get("zones", []),
		defaults.get("fogRevealed", []),
		not _editable,
		true,
		{"mode": "select"},
		view_state,
	)
	if reset_view and view_state.is_empty():
		_engine.call_deferred("reset_zoom")
	call_deferred("_update_zoom_label")
	_refresh_overlay()

func _mock_party() -> Array:
	var party: Array = []
	for i in range(MapData.MEMBER_COLOR_HEX.size()):
		party.append({
			"id": "editor-mock-%d" % i,
			"name": "Token %d" % (i + 1),
			"isPlayer": true,
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
	var selected := doc.selection()
	if not selected.is_empty():
		var elem: Dictionary = doc.get_element(str(selected[0]))
		origin = Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	elif _overlay.hover_valid:
		origin = _snap(_overlay.hover_grid)
	else:
		_refresh_overlay()
		return
	for key in MapVision.visible_cells(doc.to_map_data(), origin, MapVision.DEFAULT_VISION_RADIUS):
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
	if ToolsScript.is_pose_tool(_tool):
		var size := _ghost_size()
		_overlay.ghost = {
			"x": _snap(_overlay.hover_grid).x,
			"y": _snap(_overlay.hover_grid).y,
			"w": size.x, "h": size.y,
			"icon": ToolsScript.icon(_tool),
		}
	elif _tool == ToolsScript.TEMPLATE and not _selected_template.is_empty():
		var footprint: Vector2 = TemplatesScript.footprint(_selected_template, _template_rotation)
		_overlay.ghost = {
			"x": _snap(_overlay.hover_grid).x,
			"y": _snap(_overlay.hover_grid).y,
			"w": footprint.x, "h": footprint.y,
			"icon": "🧩",
		}
	elif ToolsScript.is_paint_tool(_tool):
		var brush := float(_brush_size if _tool == ToolsScript.PAINT else _fog_brush) * 2.0 + 1.0
		_overlay.ghost = {
			"x": roundf(_overlay.hover_grid.x),
			"y": roundf(_overlay.hover_grid.y),
			"w": brush, "h": brush,
			"icon": ToolsScript.icon(_tool),
		}
	else:
		_overlay.ghost.clear()

func _ghost_size() -> Vector2:
	if _tool == ToolsScript.TOKEN:
		return Vector2(_token_size, _token_size)
	if _tool == ToolsScript.EFFECT:
		return Vector2(_effect_radius * 2.0, _effect_radius * 2.0)
	if _tool == ToolsScript.ZONE:
		return Vector2(_zone_radius * 2.0, _zone_radius * 2.0)
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
		_refresh_panels()
	if reason in ["undo", "redo", "meta", "fog", "tiles", "order"]:
		_sync_engine()
	_refresh_overlay()
	if _save_policy == SAVE_ON_CHANGE and doc.is_dirty() and reason != "load":
		save_now()
	layout_changed.emit()

func _on_selection_changed(_ids: Array) -> void:
	if _overlay and _overlay.show_vision:
		call_deferred("_refresh_vision_preview")
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

func _on_dirty_changed(is_dirty: bool) -> void:
	if _dirty_lbl:
		_dirty_lbl.text = "● modifications non enregistrées" if is_dirty else "✓ enregistré"
		_dirty_lbl.add_theme_color_override("font_color",
			ThemeColors.GOLD_LIGHT if is_dirty else ThemeColors.TEXT_MUTED)

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
	_select_metadata("light_dir", str(light.get("direction", "nw")))
	_select_metadata("perspective", MapData.get_perspective(doc.map_data))
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
	_sync_engine()

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
	doc.set_meta_values({"lighting": light}, "Éclairage")
	_sync_engine()

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
	if px != Vector2i.ZERO:
		lbl.text = "Fond : %s (%d×%d px)" % [path.get_file(), px.x, px.y]
	else:
		lbl.text = "Fond : %s" % path.get_file()

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
	doc.set_meta_values({"backgroundImage": dest}, "Fond de carte")
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
	}, MapEditDocument.KIND_OVERLAY, "Calque")
	_sync_engine()
	_set_status("Calque ajouté : %s" % dest.get_file())

func _remove_background() -> void:
	var map_id := str(doc.map_data.get("id", ""))
	if not map_id.is_empty():
		MapData.clear_background_image(map_id)
	doc.set_meta_values({"backgroundImage": ""}, "Fond de carte")
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
	for elem_variant in doc.elements_of_kind(MapEditDocument.KIND_EFFECT):
		var elem: Dictionary = elem_variant
		doc.modify_element(str(elem.get("id", "")), {"triggered": true}, "Déclenchement")
	doc.commit_transaction()
	_sync_engine()

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
	elif _tool == ToolsScript.MARKER:
		_option_note("Type : %s %s" % [MapData.get_marker_emoji(_marker_type), MapData.get_marker_label(_marker_type)])
	elif _tool == ToolsScript.EFFECT:
		_spin(_hbox(_tool_options), "Rayon", 0.25, 8.0, _effect_radius, 0.25, func(v): _effect_radius = v)
		_option_note("Preset : %s" % _effect_preset)
	elif _tool in [ToolsScript.ZONE, ToolsScript.ZONE_RECT, ToolsScript.ZONE_POLY]:
		_spin(_hbox(_tool_options), "Rayon", 0.25, 12.0, _zone_radius, 0.25, func(v): _zone_radius = v)
		_line_row(_hbox(_tool_options), "Nom", _zone_label, func(text): _zone_label = text)
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
