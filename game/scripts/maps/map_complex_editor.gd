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
const ConstructionScript := preload("res://scripts/maps/editor/map_editor_construction.gd")
const ProceduralSceneGeneratorScript := preload("res://scripts/maps/construction/procedural_scene_generator.gd")
const EditOpsScript := preload("res://scripts/maps/editor/map_editor_edit_ops.gd")
const ToolOptionsScript := preload("res://scripts/maps/editor/map_editor_tool_options.gd")
const MapEditorPathUIScript := preload("res://scripts/maps/editor/map_editor_path_ui.gd")
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
const OrganicPathScript := preload("res://scripts/maps/construction/organic_path.gd")
const OrganicScatterScript := preload("res://scripts/maps/construction/organic_scatter.gd")
const ProceduralFlowerZoneScript := preload("res://scripts/maps/construction/procedural_flower_zone.gd")

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
## Relief tracé : courbe, largeur, force, lissage, mode.
var _terrain_spline_points: Array = []
var _terrain_spline_width: float = 2.0
var _terrain_spline_strength: float = 0.5
var _terrain_spline_smoothing: int = 4
var _terrain_spline_mode: String = "ridge"
## Sol : matière peinte (0 herbe, 1 terre, 2 pierre) + rayon du pinceau.
var _material_id: int = 0
var _material_radius: float = 1.5
var _fog_brush: int = 1
## Gomme ciblée : -1 = tout effacer, sinon id du calque à effacer.
var _erase_target: int = -1
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
var _mesh_aabb_cache: Dictionary = {}
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
var _wall_height: float = 1.3
var _roof_height: float = 1.1
var _proc_roof_height: float = 1.1
var _proc_roof_overhang: float = 0.35
var _proc_roof_style: String = "gable"
var _proc_roof_tone: String = "tuiles"
var _proc_poly_roof_height: float = 1.2
var _proc_fence_height: float = 0.9
var _proc_fence_spacing: float = 1.1
var _proc_fence_tone: String = "bois"
var _proc_wall_color: String = "#a89d88"
var _proc_path_width: float = 1.2
var _proc_path_depth: float = 0.10
var _proc_path_color: String = "#8a7654"
var _auto_stack: bool = true
var _house_auto_interior: bool = false
var _house_auto_windows: bool = false
var _house_floors: int = 1
var _house_proc_roof: bool = false
var _roof_asset: String = "res://assets/objects3d/buildings/toit_2pentes.glb"
var _floor_material: int = 2
var _floor_flatten: bool = true
var _flatten_build_footprint: bool = false
var _furnish_preset: String = "salle"
var _fence_asset: String = "res://assets/objects3d/props/barriere.glb"
var _path_width: int = 1
var _path_material: int = 1
## Tracé organique (freehand) : style, lissage Catmull-Rom, espacement des modules.
var _organic_asset: String = "res://assets/objects3d/buildings/mur.glb"
var _organic_smoothing: int = 4
var _organic_spacing: float = 0.0
var _organic_points: Array = []
## Décor auto (végétation) au pinceau : mode, densité, taille, rayon, zone.
var _scatter_mode: String = "mix"
var _scatter_density: float = 1.0
var _scatter_size: float = 1.0
var _scatter_radius: float = 1.4
var _scatter_zone_mode: bool = false
var _scatter_seed: int = 0
var _scatter_active: bool = false
var _scatter_occupied: Dictionary = {}
var _scatter_ids: Array = []
var _scatter_last_point: Vector2 = Vector2.ZERO
## Zones fleuries peintes au pinceau : type, densité, taille, graine.
var _flower_zone_points: Array = []
var _flower_zone_type: String = "marguerite"
var _flower_zone_density: float = 3.0
var _flower_zone_size: float = 0.22
var _flower_zone_seed: int = 1
## Décor contextuel : rayon de recherche du mur, densité, graine.
var _context_decor_radius: float = 3.0
var _context_decor_density: float = 0.7
var _context_decor_seed: int = 1
## Générateur de scène : style, graine, densité.
var _scene_style: String = "village"
var _quick_menu: PopupMenu = null
var _lighting_menu: PopupMenu = null
var _gen_panel: PanelContainer = null
var _gen_label: Label = null
var _gen_bar: ProgressBar = null
var _path_focus: bool = false
var _path_focus_btn: Button = null
var _path_panel: VBoxContainer = null
var _last_path_points: Array = []
var _last_path_painted: bool = false
var _scene_seed: int = 1
var _scene_density: float = 1.0
var _scatter_rng := RandomNumberGenerator.new()

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
	_build_generation_overlay()
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
	_path_focus = str(map_data.get("focusMode", "")) == "paths"
	_paint_tile = _default_tile()
	_marker_type = _first_marker_type()
	_sync_settings_ui()
	_rebuild_palettes()
	if _path_focus:
		_set_tool(ToolsScript.PROC_PATH)
	if _path_focus_btn != null:
		_path_focus_btn.set_pressed_no_signal(_path_focus)
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
	_path_panel = MapEditorPathUIScript.new()
	_left_panel.add_child(_path_panel)
	_left_panel.move_child(_path_panel, _tool_options.get_index() + 1)
	_path_panel.setup(self)
	_path_panel.visible = false
	_path_panel.focus_mode_toggled.connect(_set_path_focus)
	_path_panel.blender_patch_requested.connect(_generate_blender_path_patch)
	_path_panel.help_requested.connect(func():
		if _help_dialog != null:
			_help_dialog.popup_centered()
	)
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
	var focus_tools: Array = [ToolsScript.SELECT, ToolsScript.PAN, ToolsScript.PROC_PATH, ToolsScript.PATH_BRUSH]
	if _path_focus:
		var focus_title := Label.new()
		focus_title.text = "MODE CHEMINS"
		focus_title.add_theme_font_size_override("font_size", 11)
		focus_title.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		focus_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		host.add_child(focus_title)
	for group in ToolsScript.GROUP_ORDER:
		var defs: Array = []
		for def in ToolsScript.defs_in_group(group):
			if _path_focus and not focus_tools.has(str(def.get("id", ""))):
				continue
			defs.append(def)
		if defs.is_empty():
			continue
		_section(host, str(ToolsScript.GROUP_LABELS.get(group, group)))
		var grid := GridContainer.new()
		grid.columns = 1 if _path_focus else 4
		grid.add_theme_constant_override("h_separation", 3)
		grid.add_theme_constant_override("v_separation", 3)
		host.add_child(grid)
		for def in defs:
			var tool_id := str(def["id"])
			var btn := Button.new()
			btn.text = ("%s  %s" % [str(def["icon"]), str(def["label"])]) if _path_focus else str(def["icon"])
			btn.toggle_mode = true
			btn.tooltip_text = ToolsScript.tooltip(tool_id)
			btn.custom_minimum_size = Vector2(0, 40) if _path_focus else Vector2(46, 38)
			if _path_focus:
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
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

func _build_generation_overlay() -> void:
	_gen_panel = PanelContainer.new()
	_gen_panel.set_anchors_preset(Control.PRESET_CENTER)
	_gen_panel.custom_minimum_size = Vector2(480, 104)
	_gen_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gen_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_gen_panel.z_index = 300
	_gen_panel.visible = false
	_gen_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_gen_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_gen_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_gen_label = Label.new()
	_gen_label.text = "Génération…"
	_gen_label.add_theme_font_size_override("font_size", 13)
	_gen_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	box.add_child(_gen_label)
	_gen_bar = ProgressBar.new()
	_gen_bar.min_value = 0
	_gen_bar.max_value = 100
	_gen_bar.value = 0
	_gen_bar.show_percentage = true
	box.add_child(_gen_bar)

func _show_generation(title: String) -> void:
	if _gen_panel == null:
		return
	_gen_label.text = title
	_gen_bar.value = 0
	_gen_panel.visible = true

func _update_generation(value: float, label: String) -> void:
	if _gen_panel == null or not _gen_panel.visible:
		return
	_gen_bar.value = clampf(value, 0.0, 100.0)
	_gen_label.text = label

func _hide_generation() -> void:
	if _gen_panel != null:
		_gen_panel.visible = false

func _build_action_bar() -> void:
	var bar: HBoxContainer = %ActionBar

	_undo_btn = _icon_button(bar, "↶", "Annuler (Ctrl+Z)", func(): _do_undo())
	_redo_btn = _icon_button(bar, "↷", "Rétablir (Ctrl+Y)", func(): _do_redo())
	_icon_button(bar, "💾", "Enregistrer (Ctrl+S)", func(): save_now())
	_icon_button(bar, "⧉", "Dupliquer la sélection (Ctrl+D)", func(): doc.duplicate_selection())
	_icon_button(bar, "🗑", "Supprimer la sélection (Suppr)", func(): doc.remove_elements(doc.selection()))

	bar.add_child(VSeparator.new())
	var quick_btn := Button.new()
	quick_btn.text = "✨ Démarrage"
	quick_btn.tooltip_text = "Créer une carte agréable en un clic : village, forêt, camp ou maison, avec lumière et décor prêts."
	quick_btn.add_theme_font_size_override("font_size", 11)
	quick_btn.pressed.connect(func():
		_quick_menu.position = Vector2i(quick_btn.global_position + Vector2(0, quick_btn.size.y))
		_quick_menu.popup()
	)
	bar.add_child(quick_btn)
	_quick_menu = PopupMenu.new()
	_quick_menu.add_item("🏘  Village", 0)
	_quick_menu.add_item("🌲  Forêt", 1)
	_quick_menu.add_item("⛺  Camp", 2)
	_quick_menu.add_item("🏡  Une maison", 3)
	_quick_menu.id_pressed.connect(_on_quick_start)
	add_child(_quick_menu)

	var light_btn := Button.new()
	light_btn.text = "☀"
	light_btn.tooltip_text = "Ambiance rapide : applique un preset de lumière."
	light_btn.add_theme_font_size_override("font_size", 13)
	light_btn.pressed.connect(func():
		_lighting_menu.position = Vector2i(light_btn.global_position + Vector2(0, light_btn.size.y))
		_lighting_menu.popup()
	)
	bar.add_child(light_btn)
	_lighting_menu = PopupMenu.new()
	for preset_id in MapData.LIGHTING_PRESET_ORDER:
		var preset: Dictionary = MapData.get_lighting_preset(str(preset_id))
		var idx := _lighting_menu.item_count
		_lighting_menu.add_item(str(preset.get("label", preset_id)), idx)
		_lighting_menu.set_item_metadata(idx, str(preset_id))
	_lighting_menu.id_pressed.connect(_on_quick_lighting)
	add_child(_lighting_menu)

	_path_focus_btn = Button.new()
	_path_focus_btn.text = "🛤 Chemins"
	_path_focus_btn.toggle_mode = true
	_path_focus_btn.tooltip_text = "Mode focalisé chemins : masque tous les autres outils. Cliquez à nouveau pour tout réafficher."
	_path_focus_btn.add_theme_font_size_override("font_size", 11)
	_path_focus_btn.toggled.connect(_set_path_focus)
	bar.add_child(_path_focus_btn)
	_path_focus_btn.set_pressed_no_signal(_path_focus)

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
	_icon_button(bar, "🧭", "Vue 3D : réinitialiser l'orbite (clic droit glissé = déplacer, Maj+clic droit = orbite, molette = zoom)", func():
		if _engine.has_method("reset_editor_camera"):
			_engine.reset_editor_camera()
		else:
			_engine.request_fit_to_view()
	)
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
	_inspector.create_interior_requested.connect(_on_create_interior_requested)
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
		_right_tabs.visible = _editable and not _path_focus
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
	_settings_panel.vegetation_changed.connect(_on_vegetation_changed)
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

func _generate_blender_path_patch() -> void:
	if _last_path_points.size() < 2:
		_set_status("Patch Blender : dessinez d'abord un chemin.")
		return
	var blender := OS.get_environment("BLENDER_BIN")
	if blender.is_empty():
		blender = "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe"
	if not FileAccess.file_exists(blender):
		_set_status("Patch Blender : Blender introuvable. Définissez BLENDER_BIN.")
		return
	var script_path := ProjectSettings.globalize_path("res://../tools/blender/generate_path_patch.py")
	if not FileAccess.file_exists(script_path):
		_set_status("Patch Blender : générateur introuvable.")
		return
	var blend := OS.get_environment("BLENDER_PATH_BLEND")
	if blend.is_empty():
		blend = ProjectSettings.globalize_path(
			"res://../_tmp_path_asset/Geometry nodes- Path through grass/GeoNodesStonePath_End.blend")
	if not FileAccess.file_exists(blend):
		_set_status("Patch Blender : source .blend introuvable (BLENDER_PATH_BLEND).")
		return
	var json_path := ProjectSettings.globalize_path("user://blender_path_points.json")
	var json_points: Array = []
	for p in _last_path_points:
		json_points.append([float(p.x), float(p.y)])
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		_set_status("Patch Blender : écriture du tracé impossible.")
		return
	f.store_string(JSON.stringify(json_points))
	f.close()
	var out_path := ProjectSettings.globalize_path("user://generated_path.glb")
	_set_status("Patch Blender : génération Geometry Nodes…")
	var args := PackedStringArray([
		"-b", "--python", script_path, "--",
		"--blend", blend,
		"--points-file", json_path,
		"--out", out_path,
	])
	var output: Array = []
	var code := OS.execute(blender, args, output, true)
	if code != 0 or not FileAccess.file_exists(out_path):
		var detail := "\n".join(output.slice(maxi(0, output.size() - 3)))
		_set_status("Patch Blender : échec (code %d). %s" % [code, detail])
		return
	# Le patch Blender remplace le chemin peint : on retire la dernière
	# transaction de peinture pour éviter un chemin 3D qui traverse la terre.
	if _last_path_painted and doc.undo_depth() > 0:
		doc.undo()
		_last_path_painted = false
	var cx := 0.0
	var cy := 0.0
	for p in _last_path_points:
		cx += float(p.x)
		cy += float(p.y)
	cx /= float(_last_path_points.size())
	cy /= float(_last_path_points.size())
	doc.add_element({
		"x": cx, "y": cy, "w": 12.0, "h": 7.0,
		"asset": "user://generated_path.glb",
		"elevation": 0.02,
		"followTerrain": true, "tiltToTerrain": false,
		"label": "Patch Blender généré", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, "mesh", "Patch Blender généré")
	_sync_engine()
	_set_status("Patch Blender généré et posé.")

func _set_path_focus(on: bool) -> void:
	_path_focus = on
	if _path_focus_btn != null:
		_path_focus_btn.set_pressed_no_signal(on)
	var host := get_node_or_null("%ToolHost")
	if host != null:
		for child in host.get_children():
			child.queue_free()
		_tool_buttons.clear()
		_populate_tools(host as VBoxContainer)
	if _right_tabs != null:
		_right_tabs.visible = not on
	if _path_panel != null:
		_path_panel.visible = on
		_path_panel.set_path_focus_enabled(on)
		if on:
			_path_panel.sync_from_host()
	if _tool_options != null:
		_tool_options.visible = not on
	for path in ["%LblToolOptions", "%LblSnap", "%SnapOption", "%LblMinimap", "%MinimapHost"]:
		var node := get_node_or_null(path)
		if node is CanvasItem:
			(node as CanvasItem).visible = not on
	if on and _tool != ToolsScript.PROC_PATH and _tool != ToolsScript.PATH_BRUSH \
			and _tool != ToolsScript.SELECT and _tool != ToolsScript.PAN:
		_set_tool(ToolsScript.PROC_PATH)
	_set_status("Mode chemins : trace libre, pinceau, largeur, creux et matière. Cliquez sur « Chemins » pour tout réafficher." if on else "Tous les outils réaffichés.")
	_layout_force = true
	call_deferred("_apply_responsive_layout")
	_refresh_overlay()

func _set_tool(tool_id: String) -> void:
	_tool = tool_id
	if _path_panel != null:
		_path_panel.set_active_tool(tool_id)
		if _path_focus:
			_path_panel.sync_from_host()
	if _engine != null and _engine.has_method("cancel_navigation_drag"):
		_engine.call("cancel_navigation_drag")
	if _engine != null and _engine.has_method("trace_event"):
		_engine.set("_trace_tool", tool_id)
		_engine.call("trace_event", "TOOL_CHANGE", tool_id)
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


# --- Édition (pointeurs / sélection / poignées) : module extrait ---------------
var _edit_ops = EditOpsScript.new()

## Wrapper de compatibilité → MapEditorEditOps.
func _on_pointer_pressed(grid: Vector2, screen: Vector2, button: int, mods: Dictionary) -> void:
	_edit_ops._on_pointer_pressed(grid, screen, button, mods)

## Wrapper de compatibilité → MapEditorEditOps.
func _begin_select_or_move(grid: Vector2, screen: Vector2, mods: Dictionary) -> void:
	_edit_ops._begin_select_or_move(grid, screen, mods)

## Wrapper de compatibilité → MapEditorEditOps.
func _start_move_drag(ids: Array) -> void:
	_edit_ops._start_move_drag(ids)

## Wrapper de compatibilité → MapEditorEditOps.
func _on_pointer_moved(grid: Vector2, screen: Vector2, mods: Dictionary) -> void:
	_edit_ops._on_pointer_moved(grid, screen, mods)

## Wrapper de compatibilité → MapEditorEditOps.
func _on_pointer_released(grid: Vector2, _screen: Vector2, button: int, _mods: Dictionary) -> void:
	_edit_ops._on_pointer_released(grid, _screen, button, _mods)

## Wrapper de compatibilité → MapEditorEditOps.
func _handle_right_click(grid: Vector2) -> void:
	_edit_ops._handle_right_click(grid)

## Wrapper de compatibilité → MapEditorEditOps.
func _cancel_action() -> void:
	_edit_ops._cancel_action()

## Wrapper de compatibilité → MapEditorEditOps.
func _apply_handle_resize(grid: Vector2) -> void:
	_edit_ops._apply_handle_resize(grid)

## Wrapper de compatibilité → MapEditorEditOps.
func _apply_handle_rotate(grid: Vector2) -> void:
	_edit_ops._apply_handle_rotate(grid)

## Wrapper de compatibilité → MapEditorEditOps.
func _constrain_axis(from: Vector2, to: Vector2) -> Vector2:
	return _edit_ops._constrain_axis(from, to)

## Wrapper de compatibilité → MapEditorEditOps.
func _drag_preview_mode() -> String:
	return _edit_ops._drag_preview_mode()

func _finish_draw(to: Vector2) -> void:
	var from: Vector2 = _press_start_grid
	# Mur 3D : le tracé part de l'extrémité déjà accrochée montrée par l'aperçu.
	if _tool == ToolsScript.MESH_WALL and _overlay.drag_preview.has("from"):
		from = _overlay.drag_preview["from"]
	if _overlay.drag_preview.has("to"):
		to = _overlay.drag_preview["to"]
	if _tool == ToolsScript.AREA:
		_create_area(from, to)
	elif _tool == ToolsScript.ZONE_RECT:
		_create_rect_zone(from, to)
	elif _tool == ToolsScript.PLATFORM:
		_create_platform(from, to)
	elif _tool == ToolsScript.WALL:
		_construction._create_wall(from, to)
	elif _tool == ToolsScript.MESH_WALL:
		_construction._create_mesh_wall_smooth(from, to)
	elif _tool == ToolsScript.ROOM_3D:
		_create_mesh_room(from, to)
	elif _tool == ToolsScript.ROOF_3D:
		_create_mesh_roof(from, to)
	elif _tool == ToolsScript.PROC_ROOF:
		_construction._create_procedural_roof(from, to)
	elif _tool == ToolsScript.FLOOR_3D:
		_create_floor(from, to)
	elif _tool == ToolsScript.HOUSE_3D:
		_create_mesh_house(from, to)
	elif _tool == ToolsScript.FENCE_3D:
		_create_mesh_fence(from, to)
	elif _tool == ToolsScript.PATH_3D:
		_create_path(from, to)
	elif _tool == ToolsScript.SCENE_ZONE:
		_generate_scene_area_live(from, to)
		return
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
	elif _tool == ToolsScript.DOOR_3D:
		_insert_door(grid)
	elif _tool == ToolsScript.WINDOW_3D:
		_insert_window(grid)
	elif _tool == ToolsScript.FURNISH_3D:
		_insert_furniture(grid)
	elif _tool == ToolsScript.STAIRS_3D:
		_insert_stairs(grid)
	elif _tool == ToolsScript.INTERIOR_3D:
		_create_interior_at(grid)
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
		_construction._create_prop(grid)
	elif _tool == ToolsScript.MESH:
		_create_mesh(grid)
	elif _tool == ToolsScript.CONTEXT_DECOR:
		_construction._decorate_context(grid)
	elif _tool == ToolsScript.SCENE_GEN:
		_construction._generate_scene(grid)
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


# --- Construction de carte : module extrait ----------------------------------
# Wrappers fins conservés pour les tests et l'API existante.
var _construction = ConstructionScript.new()

func _init() -> void:
	_construction.setup(self)
	_edit_ops.setup(self)
	_tool_opts.setup(self)

## Wrapper de compatibilité → MapEditorConstruction.
func _wall_endpoints(elem: Dictionary) -> Array:
	return _construction._wall_endpoints(elem)

## Wrapper de compatibilité → MapEditorConstruction.
func _snap_wall_endpoint(point: Vector2) -> Vector2:
	return _construction._snap_wall_endpoint(point)

## Wrapper de compatibilité → MapEditorConstruction.
func _wall_chain_plan(from: Vector2, to: Vector2) -> Dictionary:
	return _construction._wall_chain_plan(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _wall_chain_corner_specs(plan: Dictionary) -> Array:
	return _construction._wall_chain_corner_specs(plan)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_mesh_wall_chain(from: Vector2, to: Vector2) -> void:
	_construction._create_mesh_wall_chain(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_mesh_room(from: Vector2, to: Vector2) -> void:
	_construction._create_mesh_room(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_mesh_house(from: Vector2, to: Vector2) -> void:
	_construction._create_mesh_house(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_path(from: Vector2, to: Vector2) -> void:
	_construction._create_path(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_mesh_fence(from: Vector2, to: Vector2) -> void:
	_construction._create_mesh_fence(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _build_organic_chain(points: Array) -> Array:
	return _construction._build_organic_chain(points)

## Wrapper de compatibilité → MapEditorConstruction.
func _scatter_stroke_points(points: Array) -> Array:
	return _construction._scatter_stroke_points(points)

## Wrapper de compatibilité → MapEditorConstruction.
func _insert_stairs(grid: Vector2) -> void:
	_construction._insert_stairs(grid)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_interior_at(grid: Vector2) -> void:
	_construction._create_interior_at(grid)

## Wrapper de compatibilité → MapEditorConstruction.
func _insert_furniture(grid: Vector2) -> void:
	_construction._insert_furniture(grid)

## Wrapper de compatibilité → MapEditorConstruction.
func _insert_window(grid: Vector2) -> void:
	_construction._insert_window(grid)

## Wrapper de compatibilité → MapEditorConstruction.
func _insert_door(grid: Vector2) -> void:
	_construction._insert_door(grid)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_mesh_roof(from: Vector2, to: Vector2) -> void:
	_construction._create_mesh_roof(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_floor(from: Vector2, to: Vector2) -> void:
	_construction._create_floor(from, to)

## Wrapper de compatibilité → MapEditorConstruction.
func _create_mesh(grid: Vector2) -> void:
	_construction._create_mesh(grid)

## Wrapper de compatibilité → MapEditorConstruction.
func _mesh_actual_dimensions(elem: Dictionary) -> Vector3:
	return _construction._mesh_actual_dimensions(elem)


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
	var hit: String = _overlay.element_at_screen_on_layer(screen, _erase_target)
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
	var h := doc.terrain_height(int(round(grid.x)), int(round(grid.y)))
	_set_status("Relief %s : hauteur %.2f case(s)." % [_relief_mode_label(), h])
	_refresh_overlay()

func _relief_mode_label() -> String:
	match _relief_mode:
		"lower":
			return "baissé"
		"flatten":
			return "aplati"
		"smooth":
			return "lissé"
		_:
			return "monté"

func _finish_terrain_spline() -> void:
	var raw_points: Array = _terrain_spline_points.duplicate()
	_terrain_spline_points.clear()
	_overlay.polygon_points.clear()
	_press_mode = "none"
	if raw_points.size() < 2:
		_set_status("Relief tracé : geste trop court (clic-glissez).")
		_refresh_overlay()
		return
	var curve := OrganicPathScript.path_points(raw_points, {
		"smoothing": _terrain_spline_smoothing,
		"spacing": 0.4,
		"nominal_length": 0.5,
	})
	if curve.size() < 2:
		_refresh_overlay()
		return
	doc.begin_transaction()
	doc.paint_terrain_spline(
		curve, _terrain_spline_width, _terrain_spline_strength,
		_terrain_spline_mode, "Relief tracé"
	)
	doc.commit_transaction()
	if _engine != null and _engine.has_method("refresh_terrain"):
		_engine.call("refresh_terrain", doc.map_data)
	_sync_engine()
	_set_status("Relief tracé : %s · largeur %.1f · force %.2f." % [
		_terrain_spline_mode_label(), _terrain_spline_width, _terrain_spline_strength])
	_refresh_panels()
	_refresh_overlay()

func _preview_terrain_spline() -> void:
	var length := OrganicPathScript.total_length(_terrain_spline_points)
	_set_status("Relief tracé : %d point(s) · %.2f case(s) · %s · relâchez pour appliquer." % [
		_terrain_spline_points.size(), length, _terrain_spline_mode_label()])

func _finish_flower_zone() -> void:
	var points: Array = _flower_zone_points.duplicate()
	_flower_zone_points.clear()
	_overlay.polygon_points.clear()
	_press_mode = "none"
	if points.size() < 3:
		_set_status("Zone fleurie : dessinez une zone fermée (au moins 3 points).")
		_refresh_overlay()
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p_variant in points:
		var p: Vector2 = p_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for p_variant in points:
		var p: Vector2 = (p_variant as Vector2) - center
		local.append([p.x, p.y])
	_flower_zone_seed = (_flower_zone_seed * 1664525 + 1013904223) % 2147483647
	var id: String = doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x),
		"h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://flower_zone",
		"points": local,
		"flowerType": _flower_zone_type,
		"density": _flower_zone_density,
		"size": _flower_zone_size,
		"seed": _flower_zone_seed,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": "Zone fleurie — %s" % _flower_zone_label(),
		"layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Zone fleurie")
	doc.select_only(id)
	_set_status("Zone fleurie : %s · densité %.1f · %d point(s)." % [
		_flower_zone_label(), _flower_zone_density, points.size()])
	_sync_engine()
	_refresh_panels()
	_refresh_overlay()

func _preview_flower_zone() -> void:
	_set_status("Zone fleurie : %d point(s) · %s · relâchez pour semer." % [
		_flower_zone_points.size(), _flower_zone_label()])

func _flower_zone_label() -> String:
	return ProceduralFlowerZoneScript.type_label(_flower_zone_type)

func _terrain_spline_mode_label() -> String:
	match _terrain_spline_mode:
		"valley":
			return "Vallée"
		"flatten":
			return "Aplatir"
		"smooth":
			return "Lisser"
		_:
			return "Crête"

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
	_construction._collect_mesh_aabbs(scene, Transform3D.IDENTITY, boxes)
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
func _on_create_interior_requested(element_id: String) -> void:
	var elem: Dictionary = doc.get_element(element_id)
	if elem.is_empty():
		return
	_create_interior_at(Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0))))

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
	if _engine.has_method("start_camera_trace") and str(_engine.get("_trace_path")).is_empty():
		_engine.call("start_camera_trace")
	var snapshot: Dictionary = doc.to_map_data()
	var defaults: Dictionary = snapshot.get("playDefaults", {})
	var view_state: Dictionary = defaults.get("viewState", {}) if defaults.get("viewState") is Dictionary else {}
	var tokens: Array = defaults.get("tokens", [])
	_ensure_token_portraits(tokens)
	_engine.set_snap_to_grid(_snap_mode == "cell")
	if _engine.has_method("trace_event"):
		_engine.call("trace_event", "SYNC_BEFORE", "tokens=%d view=%s" % [tokens.size(), not view_state.is_empty()])
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
	if _engine.has_method("trace_event"):
		_engine.call("trace_event", "SYNC_AFTER", "tokens=%d view=%s" % [tokens.size(), not view_state.is_empty()])
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
	if _tool == ToolsScript.SCATTER:
		# Pinceau de dispersion : cercle de rayon réglable autour du curseur.
		var brush_radius := maxf(0.3, _scatter_radius) * 2.0
		_overlay.ghost = {
			"x": _overlay.hover_grid.x,
			"y": _overlay.hover_grid.y,
			"w": brush_radius, "h": brush_radius,
			"icon": "🌿", "kind": "ground_material",
			"color": Color(0.55, 0.85, 0.45, 0.9),
		}
	elif _tool == ToolsScript.PROP and not _prop_asset.is_empty():
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
			var mesh_footprint := _construction._mesh_footprint_cells(_mesh_asset)
			ghost["w"] = mesh_footprint.x
			ghost["h"] = mesh_footprint.y
			ghost["icon"] = "🧊"
			ghost["rotation"] = _mesh_rotation
			ghost["texture"] = AssetLibraryScript.load_object3d_thumbnail(_mesh_asset)
			ghost["standing"] = true
			# Aperçu de l'aimantation : montre où le module sera réellement posé.
			if _mesh_snap_modules and not _mesh_asset.is_empty():
				var snap_preview := _construction._snap_module_placement(_mesh_asset, _overlay.hover_grid)
				if not snap_preview.is_empty():
					ghost["x"] = float(snap_preview.get("x", ghost["x"]))
					ghost["y"] = float(snap_preview.get("y", ghost["y"]))
					ghost["rotation"] = float(snap_preview.get("rotation", 0.0))
					ghost["snapped"] = true
			# Aperçu de l'empilement : hauteur du dessus de l'objet survolé.
			if _auto_stack and not _mesh_asset.is_empty():
				var stack_top := _construction._stack_top_at(
					Vector2(float(ghost["x"]), float(ghost["y"])),
					mesh_footprint
				)
				if stack_top > 0.02:
					ghost["elevation"] = stack_top
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
	elif _tool == ToolsScript.MESH_WALL or _tool == ToolsScript.ROOM_3D \
			or _tool == ToolsScript.HOUSE_3D:
		# Feedback de construction : matérialise le point d'accroche au réseau
		# (extrémité ou flanc) quand le curseur en approche un.
		var wall_snap := _construction._snap_wall_point(_snap(_overlay.hover_grid))
		var snap_kind := str(wall_snap.get("kind", "free"))
		if snap_kind != "free":
			var snap_point: Vector2 = wall_snap.get("point", _overlay.hover_grid)
			_overlay.ghost = {
				"x": snap_point.x, "y": snap_point.y,
				"w": 0.8, "h": 0.8,
				"icon": "🧱", "kind": "wall_snap",
				"color": Color(0.95, 0.8, 0.4, 0.95),
				"snapped": true,
			}
		else:
			_overlay.ghost.clear()
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
	_select_metadata("light_preset", str(light.get("preset", "jour")))
	_select_metadata("perspective", MapData.get_perspective(doc.map_data))
	_select_metadata("render_style", str(doc.map_data.get("renderStyle", "2.5d")))
	_select_metadata("ground_mode", MapData.get_ground_mode(doc.map_data))
	_set_spin("water_level", float(doc.map_data.get("waterLevel", -1.0)))
	_select_metadata("ambient_fx", str(doc.map_data.get("ambientFx", "")))
	_set_check("vegetation_enabled", bool(doc.map_data.get("vegetationEnabled", false)))
	_set_spin("vegetation_density", float(doc.map_data.get("vegetationDensity", 1.0)))
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

func _on_vegetation_changed() -> void:
	if _syncing:
		return
	doc.set_meta_values({
		"vegetationEnabled": _get_check("vegetation_enabled"),
		"vegetationDensity": _get_spin("vegetation_density"),
	}, "Végétation")
	_sync_engine()
	_set_status("Végétation procédurale %s (densité %.1f)." % [
		"activée" if _get_check("vegetation_enabled") else "désactivée",
		_get_spin("vegetation_density"),
	])

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

## Démarrage rapide : une carte agréable sans passer par dix outils.
func _on_quick_start(index: int) -> void:
	_run_quick_start(index)

func _run_quick_start(index: int) -> void:
	var width := int(doc.map_data.get("width", 0))
	var height := int(doc.map_data.get("height", 0))
	if width < 8 or height < 8:
		_set_status("Démarrage rapide : carte trop petite (8 × 8 minimum).")
		return
	var styles := ["village", "forest", "camp"]
	_show_generation("Préparation de la carte…")
	await get_tree().process_frame
	if index >= 0 and index < styles.size():
		_scene_style = styles[index]
		_apply_quick_visuals(_scene_style)
		_scene_seed = (int(Time.get_unix_time_from_system()) + randi()) % 1000000
		_update_generation(8, "WFC : plaques de sol…")
		await get_tree().process_frame
		var wfc_patches: int = _construction.apply_wfc_ground(_scene_style)
		_update_generation(18, "Plan de scène…")
		await get_tree().process_frame
		var plan: Dictionary = ProceduralSceneGeneratorScript.generate(
			_scene_style, width, height, _scene_seed, _scene_density
		)
		var counts: Dictionary = await _apply_plan_progressive(plan)
		_update_generation(94, "Rochers Marching Cubes…")
		await get_tree().process_frame
		var rocks: int = _construction.add_procedural_rocks(4)
		_set_status("Démarrage rapide : %s généré avec %d plaque(s) WFC, %d rocher(s) MC." % [
			ProceduralSceneGeneratorScript.style_label(_scene_style), wfc_patches, rocks])
	else:
		_apply_quick_visuals("house")
		_update_generation(30, "Maison rapide…")
		await get_tree().process_frame
		var center := Vector2(float(width) * 0.5, float(height) * 0.5)
		_house_floors = 1
		_house_auto_windows = true
		_house_proc_roof = false
		_construction._create_mesh_house(center - Vector2(2.2, 1.8), center + Vector2(2.2, 1.8))
		_update_generation(85, "Lumière et finitions…")
		await get_tree().process_frame
		_set_status("Démarrage rapide : maison prête, à toi de l'habiller.")
	_update_generation(100, "Prêt.")
	await get_tree().process_frame
	_hide_generation()
	if _engine != null and _engine.has_method("request_fit_to_view"):
		_engine.request_fit_to_view()
	_sync_engine()
	_refresh_panels()

## Applique un plan étape par étape avec une vraie barre de progression.
func _apply_plan_progressive(plan: Dictionary) -> Dictionary:
	var counts := {"paths": 0, "houses": 0, "fences": 0, "flowers": 0, "props": 0}
	_update_generation(24, "Chemins…")
	await get_tree().process_frame
	counts["paths"] = _construction._apply_scene_paths(plan)

	var houses: Array = plan.get("houses", [])
	_update_generation(32, "Maisons…")
	for i in range(houses.size()):
		var rect: Rect2 = houses[i]
		_construction._create_mesh_house(rect.position, rect.end)
		counts["houses"] = int(counts["houses"]) + 1
		_update_generation(32.0 + 36.0 * float(i + 1) / float(maxi(1, houses.size())),
			"Maison %d / %d…" % [i + 1, houses.size()])
		await get_tree().process_frame

	_update_generation(70, "Clôtures…")
	await get_tree().process_frame
	counts["fences"] = _construction._apply_scene_fences(plan)

	_update_generation(78, "Zones fleuries…")
	await get_tree().process_frame
	counts["flowers"] = _construction._apply_scene_flower_zones(plan)

	_update_generation(86, "Décor…")
	await get_tree().process_frame
	counts["props"] = _construction._apply_scene_props(plan)

	_update_generation(92, "Finalisation…")
	await get_tree().process_frame
	_construction._finalize_scene_status(counts)
	return counts

## Génération à l'intérieur d'une zone dessinée (grandes lignes du MJ).
func _generate_scene_area_live(from: Vector2, to: Vector2) -> void:
	var width := int(doc.map_data.get("width", 0))
	var height := int(doc.map_data.get("height", 0))
	var area := Rect2(Vector2(minf(from.x, to.x), minf(from.y, to.y)),
		Vector2(absf(to.x - from.x), absf(to.y - from.y)))
	if area.size.x < 8.0 or area.size.y < 8.0:
		_set_status("Esquisse : dessinez une zone d'au moins 8 × 8 cases.")
		return
	_show_generation("Esquisse de scène…")
	await get_tree().process_frame
	var plan: Dictionary = ProceduralSceneGeneratorScript.generate_in_area(
		_scene_style, width, height, area, _scene_seed, _scene_density
	)
	await _apply_plan_progressive(plan)
	_update_generation(100, "Zone complétée.")
	await get_tree().process_frame
	_hide_generation()
	if _engine != null and _engine.has_method("request_fit_to_view"):
		_engine.request_fit_to_view()
	_refresh_panels()

func _on_quick_lighting(index: int) -> void:
	if _lighting_menu == null:
		return
	var preset_id := str(_lighting_menu.get_item_metadata(index))
	var preset: Dictionary = MapData.get_lighting_preset(preset_id)
	var light: Dictionary = MapData.get_lighting_config(doc.map_data)
	light["enabled"] = true
	light["preset"] = preset_id
	for key in preset.keys():
		if key != "sources" and key != "id":
			light[key] = preset[key]
	doc.set_meta_values({"lighting": light}, "Ambiance rapide")
	_sync_engine()
	_set_status("Ambiance : %s." % str(preset.get("label", preset_id)))

## Applique les défauts visuels qui rendent une carte immédiatement agréable.
func _apply_quick_visuals(style_id: String) -> void:
	var light: Dictionary = MapData.get_lighting_config(doc.map_data)
	var preset: Dictionary = MapData.get_lighting_preset("tiny_glade")
	light["enabled"] = true
	light["preset"] = "tiny_glade"
	for key in preset.keys():
		if key != "sources" and key != "id":
			light[key] = preset[key]
	var fx := "leaves" if style_id == "forest" else ("fireflies" if style_id == "camp" else "leaves")
	doc.set_meta_values({
		"renderStyle": "2.5d",
		"groundMode": "terrain3d",
		"lighting": light,
		"ambientFx": fx,
	}, "Démarrage rapide")

func _on_lighting_changed() -> void:
	if _syncing:
		return
	var light: Dictionary = MapData.get_lighting_config(doc.map_data)
	light["enabled"] = _get_check("light_enabled")
	light["intensity"] = _get_spin("light_intensity")
	var option: OptionButton = _settings_widgets.get("light_dir")
	if option and option.selected >= 0:
		light["direction"] = str(option.get_item_metadata(option.selected))
	var preset_option: OptionButton = _settings_widgets.get("light_preset")
	if preset_option and preset_option.selected >= 0:
		var preset_id := str(preset_option.get_item_metadata(preset_option.selected))
		var preset: Dictionary = MapData.get_lighting_preset(preset_id)
		light["preset"] = preset_id
		for key in ["sunColor", "sunEnergy", "sunAngle", "sunYaw",
				"ambientColor", "ambientEnergy", "exposure", "fogDensity"]:
			if preset.has(key):
				light[key] = preset[key]
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

# --- Options d'outils : module extrait ---------------------------------------
var _tool_opts = ToolOptionsScript.new()

## Wrapper de compatibilité → MapEditorToolOptions.
func _rebuild_tool_options() -> void:
	_tool_opts._rebuild_tool_options()

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
	var selected: Array = doc.selection()
	if selected.size() == 1:
		var elem: Dictionary = doc.get_element(str(selected[0]))
		# Feedback d'édition directe : dimensions du mur et geste attendu.
		if _construction._is_wall_mesh(elem):
			_status_lbl.text = "Mur 3D : %.2f case(s) de long · hauteur %.2f · poignées : étirer une extrémité" % [
				_construction._wall_length(elem), float(elem.get("sizeY", 0.0))]
			return
		if str(elem.get("kind", "")) == DocumentScript.KIND_MESH:
			var dims: Vector3 = _mesh_actual_dimensions(elem)
			_status_lbl.text = "Objet 3D : %.2f × %.2f × %.2f · poignées : redimensionner / pivoter" % [
				dims.x, dims.z, dims.y]
			return
	_status_lbl.text = "%d élément(s) sélectionné(s)" % doc.selection_size()

func _update_hint() -> void:
	if _hint_lbl == null:
		return
	if not _editable:
		_hint_lbl.text = "Aperçu 3D — molette pour zoomer, clic droit glissé pour déplacer la vue."
		return
	_hint_lbl.text = "%s %s — %s · Molette : zoom · clic droit glissé : déplacer · Maj+clic droit : orbite" % [
		ToolsScript.icon(_tool), ToolsScript.label(_tool), ToolsScript.hint(_tool)]

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
