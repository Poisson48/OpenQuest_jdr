extends Control

const UiShortcuts := preload("res://scripts/shared/ui_shortcuts.gd")

const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const GraphNodeScene := preload("res://scenes/scenario_editor/panels/graph_node.tscn")
const TransitionRowScene := preload("res://scenes/scenario_editor/panels/transition_row.tscn")
const NpcRowScene := preload("res://scenes/scenario_editor/panels/npc_row.tscn")
const GraphLinkOverlayScript := preload("res://scripts/scenario_editor/panels/graph_link_overlay.gd")
const ScenarioEditorStyle := preload("res://scripts/scenario_editor/scenario_editor_style.gd")

## Bornes du zoom manuel (pilule zoom / rail d'outils).
const GRAPH_ZOOM_MIN := 0.35
const GRAPH_ZOOM_MAX := 1.6
## Cadrage : espace réservé aux panneaux flottants du canevas (rail d'outils à
## gauche, pilules en bas). Le graphe se cale dans l'espace restant pour
## qu'aucune carte ne passe sous un panneau.
const FIT_INSET_LEFT := 54.0
const FIT_INSET_RIGHT := 6.0
const FIT_INSET_TOP := 8.0
const FIT_INSET_BOTTOM := 10.0
## Inspecteur de droite (≈ 390 px, style Atelier).
const INSPECTOR_WIDTH := 380.0
## Panneau flottant « Plan d'ensemble » (minimap) en bas-gauche du canevas.
const MINIMAP_CAPTION := "Plan d'ensemble"
const MINIMAP_PANEL_SIZE := Vector2(220.0, 150.0)
const MINIMAP_MARGIN := Vector2(10.0, 62.0)
## Onglets de l'inspecteur de droite (refonte 04).
const DETAILS_TAB_SCENE := "scene"
const DETAILS_TAB_BRANCHES := "branches"
const DETAILS_TAB_META := "meta"
## Modes du centre (refonte 04 « Console de nœuds »).
const MODE_GRAPH := "graph"
const MODE_SCENARIO := "scenario"
const MODE_NPC := "npc"
const MODE_MAPS := "maps"
## Outils de la sous-barre.
const TOOL_SELECT := "select"
const TOOL_LINK := "link"
const TOOL_NOTE := "note"
const TOOL_FRAME := "frame"
## Onglets du dock bas.
const DOCK_TAB_ISSUES := "issues"
const DOCK_TAB_HISTORY := "history"
const DOCK_TAB_JOURNAL := "journal"

@onready var status_lbl: Label = %LblStatus
@onready var graph_edit: GraphEdit = %GraphEdit
@onready var graph_health_lbl: Label = %LblGraphHealth
@onready var meta_title: LineEdit = %MetaTitle
@onready var meta_synopsis: TextEdit = %MetaSynopsis
@onready var meta_setting: TextEdit = %MetaSetting
@onready var meta_format: OptionButton = %MetaFormat
@onready var meta_roster: OptionButton = %MetaRoster
@onready var meta_mystery: TextEdit = %MetaMystery
@onready var lbl_mystery: Label = %LblMystery
@onready var meta_start_scene: OptionButton = %MetaStartScene
@onready var npc_list: VBoxContainer = %NpcList
@onready var lbl_no_selection: Label = %LblNoSelection
@onready var scene_editor: VBoxContainer = %SceneEditor
@onready var lbl_scene_id: Label = %LblSceneId
@onready var scene_title: LineEdit = %SceneTitle
@onready var scene_tags: LineEdit = %SceneTags
@onready var scene_maps: ItemList = %SceneMaps
@onready var scene_content: TextEdit = %SceneContent
@onready var transitions_list: VBoxContainer = %TransitionsList
@onready var scene_badge_lbl: Label = %LblSceneBadge
# --- Console de nœuds (refonte 04) : barre slim, inspecteur, dock ---
@onready var scenario_badge_lbl: Label = %LblScenarioBadge
@onready var scenario_badge_id_lbl: Label = %LblScenarioBadgeId
@onready var graph_count_lbl: Label = %LblGraphCount
@onready var zoom_lbl: Label = %LblZoom
@onready var mode_graph_btn: Button = %BtnModeGraph
@onready var details_btn_scene: Button = %BtnDetailsScene
@onready var details_btn_branches: Button = %BtnDetailsBranches
@onready var details_btn_meta: Button = %BtnDetailsMeta
@onready var details_scene_tab: VBoxContainer = %DetailsSceneTab
@onready var details_branches_tab: VBoxContainer = %DetailsBranchesTab
@onready var details_meta_tab: VBoxContainer = %DetailsMetaTab
@onready var branches_hint_lbl: Label = %LblBranchesHint
@onready var dock_issues_list: VBoxContainer = %DockIssuesList
@onready var dock_issues_btn: Button = %BtnDockIssues
@onready var dock_issue_count_lbl: Label = %LblIssueCount
# --- Mix Atelier : barre slim, canevas ouvert, panneaux flottants ---
@onready var top_bar: HBoxContainer = %TopBar
@onready var search_btn: Button = %BtnTopSearch
@onready var health_summary_btn: Button = %BtnHealthSummary
@onready var validation_btn: Button = %BtnValidation
@onready var test_btn: Button = %BtnTest
@onready var problems_pill: Button = %BtnProblemsPill
@onready var dock_panel: PanelContainer = %DockPanel
@onready var dock_close_btn: Button = %BtnDockClose
@onready var graph_panel_node: PanelContainer = %GraphPanel
@onready var canvas_overlay: Control = %CanvasOverlay
@onready var tool_rail: PanelContainer = %ToolRail
@onready var legend_pill: PanelContainer = %LegendPill
@onready var zoom_pill: PanelContainer = %ZoomPill
@onready var hint_pill: PanelContainer = %HintPill
@onready var legend_health_lbl: Label = %LblLegendHealth
@onready var scene_badge_panel: PanelContainer = %ScenarioBadgePanel
@onready var scene_kicker_lbl: Label = %LblSceneKicker
@onready var scene_title_big: Label = %LblSceneTitleBig
@onready var scene_id_chip: PanelContainer = %SceneIdChip
@onready var scene_tag_chips: HFlowContainer = %SceneTagChips
@onready var scene_map_chips: HFlowContainer = %SceneMapChips
@onready var scene_npc_chips: HFlowContainer = %SceneNpcChips
@onready var scene_npc_col: VBoxContainer = %SceneNpcCol
@onready var duplicate_scene_btn: Button = %BtnDuplicateScene
@onready var scene_action_bar: VBoxContainer = %SceneActionBar
@onready var branches_count_lbl: Label = %LblTransitions
@onready var hints_lbl: Label = %LblHints

var _scenario: Dictionary = {}
var _selected_scene_id: String = ""
var _rebuilding_graph: bool = false
var _locked_roster: String = ""
var _locked_format: String = ""
var _dirty: bool = false
var _pending_action: Callable = Callable()
var _graph_popup: PopupMenu
var _pending_focus_scene_id: String = ""
var _graph_panning: bool = false
var _graph_pan_last: Vector2 = Vector2.ZERO
var _refreshing_scene_maps: bool = false
var _rebuild_scheduled: bool = false
var _link_overlay: Control = null
var _details_tab: String = DETAILS_TAB_SCENE
var _graph_issues: Array = []
var _initial_fit_done: bool = false
# --- Console de nœuds : modes, outils, vues, palette, minimap, dock ---------
var _mode: String = MODE_GRAPH
var _tool: String = TOOL_SELECT
var _dock_tab: String = DOCK_TAB_ISSUES
var _dock_open: bool = false
var _link_source_id: String = ""
var _views: Control = null
var _palette: Control = null
var _minimap: Control = null
var _graph_panel: Control = null
var _views_host: Control = null
var _dock_issues_panel: Control = null
var _dock_history_panel: Control = null
var _dock_journal_panel: Control = null
var _validation_badge: Button = null
var _hints_lbl: Label = null
var _mode_buttons: Dictionary = {}
var _tool_buttons: Dictionary = {}
var _dock_buttons: Dictionary = {}
var _history_entries: Array = []
var _journal_entries: Array = []
var _frame_dragging: bool = false
var _frame_drag_start: Vector2 = Vector2.ZERO
var _note_dialog: ConfirmationDialog = null
var _note_edit: LineEdit = null
var _note_editing_id: String = ""
var _link_last_sid: String = ""
var _link_click_ms: int = 0

func _ready() -> void:
	%TopBar.back_pressed.connect(_on_back_pressed)
	%ConfirmDiscard.confirmed.connect(_on_confirm_discard)
	%BtnSave.pressed.connect(_on_save_pressed)
	%BtnAddScene.pressed.connect(_on_add_scene_pressed)
	%BtnAddNpc.pressed.connect(_on_add_npc_pressed)
	if has_node("%BtnAddNpcPanel"):
		%BtnAddNpcPanel.pressed.connect(_on_add_npc_pressed)
	%BtnSetStart.pressed.connect(_on_set_start_pressed)
	%BtnDeleteScene.pressed.connect(_on_delete_scene_pressed)
	%BtnAddTransition.pressed.connect(_on_add_transition_pressed)
	%BtnAutoLayout.pressed.connect(_on_auto_layout_pressed)
	%BtnFitView.pressed.connect(_on_fit_view_pressed)
	%BtnValidate.pressed.connect(_on_validate_pressed)
	%ConfirmDeleteScene.confirmed.connect(_on_confirm_delete_scene)
	_validation_badge = validation_btn
	_hints_lbl = hints_lbl
	_connect_console_buttons()
	_slim_top_bar()
	_install_backdrop()
	_style_compact_ui()
	_style_floating_panels()
	scene_maps.multi_selected.connect(_on_scene_maps_multi_selected)
	scene_maps.item_selected.connect(func(_idx): _on_scene_maps_changed())

	_configure_graph_edit()
	_setup_graph_popup()
	_setup_option_buttons()
	_apply_entry_context()
	_load_scenario()
	_connect_graph_signals()
	_refresh_all()
	_set_details_tab(DETAILS_TAB_SCENE)
	_style_tab_button(mode_graph_btn, true)
	for disabled_tab in [%BtnModeScenario, %BtnModeNpc, %BtnModeMaps, %BtnDockHistory, %BtnDockJournal]:
		_style_tab_button(disabled_tab, false)
	_style_tab_button(dock_issues_btn, true)
	_build_console_extras()
	_update_zoom_label()
	call_deferred("_run_initial_fit")
	call_deferred("_enforce_compact_buttons")
	call_deferred("_balance_top_bar")
	if not top_bar.resized.is_connected(_balance_top_bar):
		top_bar.resized.connect(_balance_top_bar)

## Cadrage initial : le graphe est reconstruit en différé et les tailles de cartes
## sont appliquées après coup. Cadrer trop tôt donnait un zoom minimal (35 %) et
## des cartes coupées. On attend la fin du rebuild + stabilisation du layout.
func _run_initial_fit() -> void:
	if _initial_fit_done:
		return
	await get_tree().process_frame
	for _i in range(60):
		if not is_inside_tree():
			return
		await get_tree().process_frame
		var nodes := 0
		for child in graph_edit.get_children():
			if child is GraphNode and is_instance_valid(child):
				nodes += 1
		if not _rebuilding_graph and nodes > 0:
			break
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_on_fit_view_pressed()
	_auto_select_start_scene()
	# Les tailles définitives des cartes (contenu, lignes tronquées) arrivent
	# après plusieurs frames : on recadre pendant ~0,7 s pour converger, sinon la
	# vue reste coupée en bas (zoom calculé sur des tailles provisoires).
	for _i in range(42):
		if not is_inside_tree():
			return
		await get_tree().process_frame
		_on_fit_view_pressed()
	_initial_fit_done = true

## Sélectionne la scène de départ à l'ouverture (sinon le panneau détails reste
## vide et le graphe n'a aucun nœud sélectionné).
func _auto_select_start_scene() -> void:
	if not _selected_scene_id.is_empty():
		return
	var start_id := str(_scenario.get("startSceneId", ""))
	if start_id.is_empty() or _scene_index_for_id(start_id) < 0:
		return
	_selected_scene_id = start_id
	_refresh_graph_node_chrome(start_id)
	_refresh_graph_selection_styles()
	_refresh_transitions_ui()
	_refresh_scene_panel()

## Barre haute compacte du mix Atelier : fil d'Ariane et titre resserrés, le
## badge scénario suit directement le titre, le champ de recherche occupe le
## centre et les actions restent à droite.
func _slim_top_bar() -> void:
	ScenarioEditorStyle.slim_top_bar(self)

## Fond de page façon Atelier : aplat très sombre + trame de points sur TOUTE la
## fenêtre, et canevas du graphe transparent (ni panneau opaque, ni grille
## GraphEdit) pour laisser respirer le « côté ouvert ». Aucun dégradé.
func _install_backdrop() -> void:
	ScenarioEditorStyle.install_backdrop(self)


## Branche les contrôles propres à la console (sous-barre, onglets, dock).
func _connect_console_buttons() -> void:
	%BtnZoomOut.pressed.connect(_on_zoom_out_pressed)
	%BtnZoomIn.pressed.connect(_on_zoom_in_pressed)
	# Bouton de mode actif : ne jamais pouvoir le désactiver (aucune autre vue).
	mode_graph_btn.toggled.connect(func(on: bool):
		if not on:
			mode_graph_btn.button_pressed = true
	)
	details_btn_scene.pressed.connect(func(): _set_details_tab(DETAILS_TAB_SCENE))
	details_btn_branches.pressed.connect(func(): _set_details_tab(DETAILS_TAB_BRANCHES))
	details_btn_meta.pressed.connect(func(): _set_details_tab(DETAILS_TAB_META))
	# Onglet « Problèmes » : déjà actif, on rafraîchit par confort (pas de vue morte).
	dock_issues_btn.toggled.connect(func(on: bool):
		if not on:
			dock_issues_btn.button_pressed = true
			return
		_refresh_dock()
	)
	# --- Barre slim : recherche, résumé, validation, test, dock --------------
	search_btn.pressed.connect(_open_palette)
	health_summary_btn.pressed.connect(_open_palette)
	validation_btn.pressed.connect(_on_validation_badge_pressed)
	test_btn.pressed.connect(_on_test_pressed)
	problems_pill.pressed.connect(_toggle_dock)
	dock_close_btn.pressed.connect(func(): _set_dock_open(false))
	duplicate_scene_btn.pressed.connect(_on_duplicate_scene_pressed)
	if graph_edit.has_signal("zoom_changed"):
		graph_edit.zoom_changed.connect(_update_zoom_label)

## Tailles compactes : l'autoload ButtonSizing impose 48 px de haut à tous les
## boutons ; la barre slim et les panneaux flottants ont besoin de contrôles de
## 26 à 34 px. `skip_button_sizing` empêche l'écrasement (posé avant le passage
## différé de l'autoload), `_enforce_compact_buttons` le re-applique ensuite.
func _style_compact_ui() -> void:
	ScenarioEditorStyle.style_compact_ui(self)


## Centre visuellement le champ de recherche dans la barre haute : les deux
## ressorts autour de lui reçoivent la place restante, recalculée à chaque
## redimensionnement (sinon il dérive vers la droite à cause des actions).
func _balance_top_bar() -> void:
	ScenarioEditorStyle.balance_top_bar(self)

## Re-applique les tailles compactes après le passage différé de ButtonSizing.
func _enforce_compact_buttons() -> void:
	ScenarioEditorStyle.enforce_compact_buttons(self)

## Style commun des panneaux flottants du canevas (pilules sombres arrondies).
func _style_floating_panels() -> void:
	ScenarioEditorStyle.style_floating_panels(self)


func _configure_graph_edit() -> void:
	graph_edit.show_grid = true
	graph_edit.snapping_enabled = true
	graph_edit.snapping_distance = 16
	graph_edit.right_disconnects = true
	# La minimap native ne dessine pas l'overlay des liens (elle resterait vide) :
	# on la désactive, la vue d'ensemble se fait avec « Cadrer » + zoom.
	graph_edit.minimap_enabled = false
	if graph_edit.has_method("set_connection_lines_curvature"):
		graph_edit.connection_lines_curvature = 0.35
	if "connection_lines_thickness" in graph_edit:
		graph_edit.connection_lines_thickness = 2.0
	# Clic-glisser sur le fond = déplacer la vue (en plus du clic milieu).
	if not graph_edit.gui_input.is_connected(_on_graph_gui_input):
		graph_edit.gui_input.connect(_on_graph_gui_input)
	# Le zoom et les outils sont dans la sous-barre : on masque la barre d'outils
	# native de GraphEdit (boutons de zoom, grille, accroche, menu, minimap).
	for native_toolbar_prop in [
		"show_zoom_buttons", "show_zoom_label", "show_grid_buttons",
		"show_minimap_button", "show_arrange_button", "show_menu",
	]:
		if _property_exists(graph_edit, str(native_toolbar_prop)):
			graph_edit.set(str(native_toolbar_prop), false)
	# Bornes de zoom alignées sur les boutons − / + de la sous-barre.
	if _property_exists(graph_edit, "zoom_min"):
		graph_edit.set("zoom_min", GRAPH_ZOOM_MIN)
	if _property_exists(graph_edit, "zoom_max"):
		graph_edit.set("zoom_max", GRAPH_ZOOM_MAX)
	_setup_link_overlay()

## Vrai si l'objet expose la propriété donnée (compat. versions de Godot).
func _property_exists(obj: Object, property_name: String) -> bool:
	if obj == null:
		return false
	for entry in obj.get_property_list():
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("name", "")) == property_name:
			return true
	return false

## Overlay des branches, dessiné AU-DESSUS des cartes : GraphEdit trace ses
## liens sous les GraphNode (invisibles dès que deux scènes se chevauchent).
## L'overlay gère les peignes de séparation, les détours et les libellés.
func _setup_link_overlay() -> void:
	if _link_overlay != null and is_instance_valid(_link_overlay):
		return
	_link_overlay = GraphLinkOverlayScript.new()
	_link_overlay.name = "GraphLinkOverlay"
	add_child(_link_overlay)
	_link_overlay.call("setup", graph_edit,
		func() -> Dictionary: return _scenario,
		func() -> String: return _selected_scene_id)

func _notify_links_changed() -> void:
	if _link_overlay != null and is_instance_valid(_link_overlay):
		_link_overlay.call("notify_scenario_changed")

## Suivi du survol (indispensable : l'overlay est traversant, donc sans souris)
## et suppression d'une branche au clic droit sur le lien *visible*.
func _input(event: InputEvent) -> void:
	if _link_overlay == null or not is_instance_valid(_link_overlay):
		return
	if graph_edit == null or not is_instance_valid(graph_edit):
		return
	if event is InputEventMouseMotion:
		var mouse_global := (event as InputEventMouseMotion).global_position
		if graph_edit.is_visible_in_tree() and graph_edit.get_global_rect().has_point(mouse_global):
			_link_overlay.call("set_hover_global", mouse_global)
		else:
			_link_overlay.call("clear_hover")
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed or button.button_index != MOUSE_BUTTON_RIGHT:
			return
		var hovered: Dictionary = _link_overlay.call("get_hovered_edge")
		if hovered.is_empty():
			return
		var from_id := str(hovered.get("from_id", ""))
		var to_id := str(hovered.get("to_id", ""))
		if from_id.is_empty() or to_id.is_empty():
			return
		_on_graph_disconnection_request(_graph_node_name_for_id(from_id), 0, _graph_node_name_for_id(to_id), 0)
		if get_viewport() != null:
			get_viewport().set_input_as_handled()

func _on_graph_gui_input(event: InputEvent) -> void:
	# Outils Note / Cadre : la souris sert à créer des annotations, pas à pan.
	if _tool == TOOL_NOTE or _tool == TOOL_FRAME:
		if _handle_annotation_input(event):
			return
	# Molette = zoom natif de GraphEdit : on resynchronise le libellé après coup.
	if event is InputEventMouseButton and event.pressed:
		var wheel := event as InputEventMouseButton
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			call_deferred("_update_zoom_label")
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Ne pas démarrer un pan si le pointeur est sur une scène (évite de bloquer le drag).
			if _is_pointer_over_graph_node():
				return
			_graph_panning = true
			_graph_pan_last = event.position
			graph_edit.mouse_default_cursor_shape = Control.CURSOR_MOVE
			graph_edit.accept_event()
		else:
			_stop_graph_panning()
		return
	if event is InputEventMouseMotion and _graph_panning:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_stop_graph_panning()
			return
		var motion := event as InputEventMouseMotion
		graph_edit.scroll_offset -= motion.relative
		_graph_pan_last = motion.position
		graph_edit.accept_event()

func _is_pointer_over_graph_node() -> bool:
	var mouse := graph_edit.get_global_mouse_position()
	for child in graph_edit.get_children():
		if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
			if (child as Control).get_global_rect().has_point(mouse):
				return true
	return false

func _stop_graph_panning() -> void:
	if not _graph_panning:
		return
	_graph_panning = false
	graph_edit.mouse_default_cursor_shape = Control.CURSOR_ARROW

func _setup_option_buttons() -> void:
	_rebuild_format_options_for_context()

	meta_roster.clear()
	meta_roster.add_item("Aventure", 0)
	meta_roster.set_item_metadata(0, "general")
	meta_roster.add_item("Enquête", 1)
	meta_roster.set_item_metadata(1, "investigation")

	meta_format.item_selected.connect(_on_meta_changed)
	meta_roster.item_selected.connect(_on_meta_changed)
	meta_title.text_changed.connect(func(_t): _on_meta_changed())
	meta_synopsis.text_changed.connect(func(): _on_meta_changed())
	meta_setting.text_changed.connect(func(): _on_meta_changed())
	meta_mystery.text_changed.connect(func(): _on_meta_changed())

func _rebuild_format_options_for_context() -> void:
	var previous := ""
	if meta_format.item_count > 0 and meta_format.selected >= 0:
		previous = str(meta_format.get_item_metadata(meta_format.selected))
	meta_format.clear()
	meta_format.add_item("One-shot", 0)
	meta_format.set_item_metadata(0, "oneshot")
	meta_format.add_item("Campagne longue", 1)
	meta_format.set_item_metadata(1, "long")
	# Pas d'option « Enquête » si on vient du hub Aventure (évite le mélange).
	var allow_inv := _locked_roster.is_empty() and _locked_format.is_empty()
	if allow_inv:
		meta_format.add_item("Enquête", 2)
		meta_format.set_item_metadata(2, "investigation")
	var select_idx := 0
	for i in range(meta_format.item_count):
		if str(meta_format.get_item_metadata(i)) == previous:
			select_idx = i
			break
	if meta_format.item_count > 0:
		meta_format.select(select_idx)

func _apply_entry_context() -> void:
	if get_tree().has_meta("preselected_scenario_roster"):
		_locked_roster = str(get_tree().get_meta("preselected_scenario_roster"))
		get_tree().remove_meta("preselected_scenario_roster")
	if get_tree().has_meta("preselected_quest_format"):
		_locked_format = str(get_tree().get_meta("preselected_quest_format"))
		get_tree().remove_meta("preselected_quest_format")
	_rebuild_format_options_for_context()

func _load_scenario() -> void:
	var scenario_id := GameData.editor_scenario_id
	GameData.editor_scenario_id = ""
	if scenario_id.is_empty():
		var roster := _locked_roster if not _locked_roster.is_empty() else "general"
		var fmt := _locked_format if not _locked_format.is_empty() else "oneshot"
		if roster == "investigation":
			fmt = "investigation"
		_scenario = GameData.create_blank_scenario(roster, fmt)
	else:
		var existing := GameData.get_scenario_by_id(scenario_id)
		if existing.is_empty():
			_scenario = GameData.create_blank_scenario()
		else:
			_scenario = existing.duplicate(true)
	_scenario = QuestNavigation.ensure_graph_positions(_scenario)
	_dirty = false

func _setup_graph_popup() -> void:
	_graph_popup = PopupMenu.new()
	_graph_popup.name = "GraphScenePopup"
	add_child(_graph_popup)
	_graph_popup.index_pressed.connect(_on_graph_popup_index_pressed)

func _connect_graph_signals() -> void:
	graph_edit.connection_request.connect(_on_graph_connection_request)
	graph_edit.disconnection_request.connect(_on_graph_disconnection_request)
	graph_edit.node_selected.connect(_on_graph_node_selected)
	graph_edit.popup_request.connect(_on_graph_popup_request)
	if graph_edit.has_signal("end_node_move"):
		graph_edit.end_node_move.connect(_on_graph_end_node_move)
	if graph_edit.has_signal("node_dragged"):
		graph_edit.node_dragged.connect(_on_graph_node_dragged)

func _refresh_all() -> void:
	_notify_links_changed()
	_sync_meta_ui()
	_rebuild_graph()
	_refresh_npc_list()
	_refresh_scene_panel()
	_update_mystery_visibility()
	_refresh_graph_health()

func _sync_meta_ui() -> void:
	meta_title.text = str(_scenario.get("title", ""))
	meta_synopsis.text = str(_scenario.get("synopsis", ""))
	meta_setting.text = str(_scenario.get("setting", ""))
	meta_mystery.text = str(_scenario.get("mystery", ""))

	var fmt: String = str(_scenario.get("questFormat", "oneshot"))
	for i in range(meta_format.item_count):
		if str(meta_format.get_item_metadata(i)) == fmt:
			meta_format.select(i)
			break
	if not _locked_format.is_empty():
		meta_format.disabled = true

	var roster: String = str(_scenario.get("roster", "general"))
	for i in range(meta_roster.item_count):
		if str(meta_roster.get_item_metadata(i)) == roster:
			meta_roster.select(i)
			break
	if not _locked_roster.is_empty():
		meta_roster.disabled = true

	_update_mode_dropdowns_visibility()
	_refresh_start_scene_options()

func _is_investigation_mode() -> bool:
	return str(_scenario.get("roster", "")) == "investigation" \
		or str(_scenario.get("questFormat", "")) == "investigation"

func _update_mode_dropdowns_visibility() -> void:
	# Mode verrouillé depuis le hub : un seul univers, pas de bascule Aventure ↔ Enquête.
	if not _locked_roster.is_empty() or not _locked_format.is_empty():
		meta_format.visible = _locked_roster != "investigation" and _locked_format != "investigation" \
			and str(_scenario.get("roster", "")) != "investigation"
		# En aventure verrouillée, le format oneshot/long reste utile ; le roster est fixe.
		meta_roster.visible = false
		return
	# Enquête libre : un seul menu (roster).
	var is_inv := _is_investigation_mode()
	meta_format.visible = not is_inv
	meta_roster.visible = true

func _refresh_start_scene_options() -> void:
	meta_start_scene.clear()
	var start_id := str(_scenario.get("startSceneId", ""))
	var select_idx := 0
	for i in range(_scenario.get("scenes", []).size()):
		var scene: Dictionary = _scenario["scenes"][i]
		var sid := str(scene.get("id", ""))
		var label := "%s (%s)" % [scene.get("title", sid), sid]
		meta_start_scene.add_item(label, i)
		meta_start_scene.set_item_metadata(i, sid)
		if sid == start_id:
			select_idx = i
	if meta_start_scene.item_count > 0:
		meta_start_scene.select(select_idx)
	if not meta_start_scene.item_selected.is_connected(_on_start_scene_selected):
		meta_start_scene.item_selected.connect(_on_start_scene_selected)

func _on_start_scene_selected(_idx: int) -> void:
	if meta_start_scene.selected >= 0:
		_scenario["startSceneId"] = str(meta_start_scene.get_item_metadata(meta_start_scene.selected))
		_mark_dirty("Scène de départ mise à jour")
		_rebuild_graph()

func _on_meta_changed(_arg = null) -> void:
	_scenario["title"] = meta_title.text.strip_edges()
	_scenario["synopsis"] = meta_synopsis.text.strip_edges()
	_scenario["setting"] = meta_setting.text.strip_edges()
	_scenario["mystery"] = meta_mystery.text.strip_edges()
	if meta_roster.selected >= 0:
		_scenario["roster"] = str(meta_roster.get_item_metadata(meta_roster.selected))
	var roster := str(_scenario.get("roster", "general"))
	if roster == "investigation":
		_scenario["questFormat"] = "investigation"
	elif meta_format.visible and meta_format.selected >= 0:
		var fmt := str(meta_format.get_item_metadata(meta_format.selected))
		# Le format « Enquête » bascule tout le scénario en enquête.
		if fmt == "investigation":
			_scenario["roster"] = "investigation"
			_scenario["questFormat"] = "investigation"
		else:
			_scenario["questFormat"] = fmt
	elif str(_scenario.get("questFormat", "")) == "investigation":
		# On quitte l’enquête via le roster : format aventure par défaut.
		_scenario["questFormat"] = "oneshot"
	_update_mode_dropdowns_visibility()
	if meta_format.visible:
		var shown_fmt := str(_scenario.get("questFormat", "oneshot"))
		for i in range(meta_format.item_count):
			if str(meta_format.get_item_metadata(i)) == shown_fmt:
				meta_format.select(i)
				break
	for i in range(meta_roster.item_count):
		if str(meta_roster.get_item_metadata(i)) == str(_scenario.get("roster", "general")):
			meta_roster.select(i)
			break
	_update_mystery_visibility()
	_dirty = true
	_refresh_graph_health()

func _update_mystery_visibility() -> void:
	var show: bool = _is_investigation_mode()
	lbl_mystery.visible = show
	meta_mystery.visible = show

func _refresh_graph_health() -> void:
	var analysis := QuestNavigation.analyze_graph(_scenario)
	graph_health_lbl.text = QuestNavigation.format_graph_health(analysis)
	if analysis.get("ok", false):
		graph_health_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		graph_health_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	_update_scenario_header()
	_update_graph_counters(analysis)
	_refresh_dock(analysis)
	_update_validation_badge()
	_update_canvas_chrome()

## En-tête : titre du scénario + badge d'identifiant (barre slim du mix Atelier).
func _update_scenario_header() -> void:
	var title := str(_scenario.get("title", "")).strip_edges()
	if title.is_empty():
		title = "Éditeur de scénario"
	if %TopBar.has_method("set_title"):
		%TopBar.set_title(title)
	var scenario_id := str(_scenario.get("id", ""))
	scenario_badge_lbl.text = "Brouillon"
	scenario_badge_id_lbl.text = scenario_id
	scenario_badge_id_lbl.visible = not scenario_id.is_empty()
	scenario_badge_lbl.tooltip_text = "Statut et identifiant du scénario"

## Compteur « N nœuds · M liens » de la sous-barre.
func _update_graph_counters(analysis: Dictionary) -> void:
	if graph_count_lbl == null:
		return
	graph_count_lbl.text = "%d nœuds · %d liens" % [
		int(analysis.get("sceneCount", 0)),
		int(analysis.get("branchCount", 0)),
	]
	if health_summary_btn != null:
		var ok := bool(analysis.get("ok", false))
		var mark := "✓" if ok else "⚠"
		health_summary_btn.text = "%s %d scènes · %d branches" % [
			mark, int(analysis.get("sceneCount", 0)), int(analysis.get("branchCount", 0))]
		health_summary_btn.add_theme_color_override("font_color",
			ThemeColors.SUCCESS if ok else ThemeColors.GOLD_LIGHT)

## Pilule légende (santé du graphe) + pilule « Problèmes » du canevas ouvert.
func _update_canvas_chrome() -> void:
	if legend_health_lbl != null:
		var ok := QuestNavigation.validate_scenario_graph(_scenario).is_empty()
		legend_health_lbl.text = "● graphe valide" if ok else "● graphe à vérifier"
		legend_health_lbl.add_theme_color_override("font_color",
			ThemeColors.SUCCESS if ok else ThemeColors.GOLD_LIGHT)
	if problems_pill != null:
		var problems := 0
		for issue in _graph_issues:
			if str(issue.get("severity", "warn")) != "ok":
				problems += 1
		problems_pill.text = "⚠ Problèmes %d" % problems if problems > 0 else "✓ Problèmes 0"
		problems_pill.add_theme_color_override("font_color",
			ThemeColors.GOLD_LIGHT if problems > 0 else ThemeColors.SUCCESS)
		problems_pill.tooltip_text = "Ouvrir le panneau Problèmes / Historique / Journal" \
			if not _dock_open else "Fermer le panneau"

# ---------------------------------------------------------------------------
# Dock « Problèmes » (refonte 04)
# ---------------------------------------------------------------------------

## Reconstruit la liste des problèmes à partir de l'analyse du graphe.
## Heuristiques volontairement simples : erreurs bloquantes, accessibilité,
## scènes terminales sans carte, carrefours illisibles, branches MJ d'acte.
func _refresh_dock(analysis: Dictionary = {}) -> void:
	if dock_issues_list == null:
		return
	if analysis.is_empty():
		analysis = QuestNavigation.analyze_graph(_scenario)
	for child in dock_issues_list.get_children():
		child.queue_free()
	_graph_issues = _collect_graph_issues(analysis)
	var problems := 0
	for issue in _graph_issues:
		if str(issue.get("severity", "warn")) != "ok":
			problems += 1
	dock_issue_count_lbl.text = str(problems)
	dock_issue_count_lbl.add_theme_color_override("font_color",
		ThemeColors.GOLD_LIGHT if problems > 0 else ThemeColors.TEXT_MUTED)
	if _graph_issues.is_empty():
		var empty := Label.new()
		empty.text = "✓ Aucun problème détecté sur ce graphe."
		empty.add_theme_color_override("font_color", ThemeColors.SUCCESS)
		dock_issues_list.add_child(empty)
		return
	for issue in _graph_issues:
		dock_issues_list.add_child(_create_dock_issue_row(issue))

func _collect_graph_issues(analysis: Dictionary) -> Array:
	var issues: Array = []
	var start_id := str(_scenario.get("startSceneId", ""))
	if start_id.is_empty() or _scene_index_for_id(start_id) < 0:
		issues.append({
			"severity": "error", "scene_id": "",
			"message": "scène de départ manquante ou invalide",
		})
	# Branches cassées (normalement impossibles après normalisation).
	for broken in analysis.get("brokenTransitions", []):
		if typeof(broken) != TYPE_DICTIONARY:
			continue
		issues.append({
			"severity": "error", "scene_id": str(broken.get("from", "")),
			"message": "branche cassée vers « %s »" % str(broken.get("to", "")),
		})
	# Accessibilité depuis la scène de départ.
	var warned: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		var sid := str(uid)
		issues.append({
			"severity": "warn", "scene_id": sid,
			"message": "scène inatteignable depuis le départ — vérifier les branches entrantes",
		})
		warned[sid] = true
	for uid in analysis.get("orphans", []):
		var sid := str(uid)
		if warned.has(sid):
			continue
		issues.append({
			"severity": "warn", "scene_id": sid,
			"message": "scène orpheline (aucune branche entrante)",
		})
		warned[sid] = true
	# Scènes terminales sans carte liée : la session resterait sur la carte précédente.
	for uid in analysis.get("terminals", []):
		var sid := str(uid)
		var scene := _get_scene_dict(sid)
		if scene.is_empty():
			continue
		if QuestNavigation.get_scene_map_ids(scene).is_empty():
			issues.append({
				"severity": "warn", "scene_id": sid,
				"message": "scène terminale sans carte liée — la session restera sur la carte précédente",
			})
	# Carrefours trop chargés en branches entrantes (lisibilité du graphe).
	var incoming: Dictionary = analysis.get("incoming", {})
	for key in incoming.keys():
		var sid := str(key)
		var branch_n := int(incoming[key])
		if branch_n < 5:
			continue
		issues.append({
			"severity": "warn", "scene_id": sid,
			"message": "%d branches entrantes (lisibilité) — envisager un carrefour nommé" % branch_n,
		})
	# Branches MJ franchissant un acte : cohérence narrative à vérifier.
	for scene in _scenario.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_act := _scene_act_number(scene)
		if from_act <= 0:
			continue
		var from_id := str(scene.get("id", ""))
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY or not bool(transition.get("gmOnly", false)):
				continue
			var target := _get_scene_dict(str(transition.get("to", "")))
			if target.is_empty():
				continue
			var to_act := _scene_act_number(target)
			if to_act > from_act:
				issues.append({
					"severity": "warn", "scene_id": from_id,
					"message": "branche MJ vers l'acte %d — vérifier la cohérence avec l'acte suivant" % to_act,
				})
	# Ligne de confirmation quand le point d'entrée est sain.
	if not start_id.is_empty() and _scene_index_for_id(start_id) >= 0 and bool(analysis.get("ok", false)):
		var outgoing := QuestNavigation.get_available_transitions(_scenario, start_id).size()
		issues.append({
			"severity": "ok", "scene_id": start_id,
			"message": "scène de départ atteignable, %d sorties, aucune branche cassée" % outgoing,
		})
	# Déduplication puis tri erreurs → alertes → confirmations.
	var seen: Dictionary = {}
	var result: Array = []
	for issue in issues:
		var key := "%s|%s" % [str(issue.get("scene_id", "")), str(issue.get("message", ""))]
		if seen.has(key):
			continue
		seen[key] = true
		result.append(issue)
	result.sort_custom(func(a, b): return _issue_rank(a) < _issue_rank(b))
	return result

func _create_dock_issue_row(issue: Dictionary) -> HBoxContainer:
	var severity := str(issue.get("severity", "warn"))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var icon := Label.new()
	icon.text = "▲" if severity == "warn" else ("✖" if severity == "error" else "●")
	icon.custom_minimum_size = Vector2(16, 0)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var icon_color := ThemeColors.GOLD_LIGHT
	if severity == "error":
		icon_color = ThemeColors.DANGER
	elif severity == "ok":
		icon_color = ThemeColors.SUCCESS
	icon.add_theme_color_override("font_color", icon_color)
	row.add_child(icon)
	var scene_id := str(issue.get("scene_id", ""))
	if not scene_id.is_empty() and _scene_index_for_id(scene_id) >= 0:
		var where := LinkButton.new()
		where.text = scene_id
		where.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		where.tooltip_text = "Sélectionner la scène « %s »" % scene_id
		where.focus_mode = Control.FOCUS_NONE
		where.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
		where.add_theme_color_override("font_hover_color", ThemeColors.GOLD)
		where.pressed.connect(func(): _select_and_focus_scene(scene_id))
		row.add_child(where)
	else:
		var where := Label.new()
		where.text = "scénario"
		where.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		row.add_child(where)
	var message := Label.new()
	message.text = str(issue.get("message", ""))
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	row.add_child(message)
	return row

func _issue_rank(issue: Dictionary) -> int:
	match str(issue.get("severity", "warn")):
		"error":
			return 0
		"warn":
			return 1
		_:
			return 2

## Numéro d'acte déduit des tags d'une scène (« acte-2 », « act-2 »), 0 sinon.
func _scene_act_number(scene: Dictionary) -> int:
	var tags: Array = scene.get("tags", [])
	if typeof(tags) != TYPE_ARRAY:
		return 0
	for tag in tags:
		var text := str(tag).strip_edges().to_lower()
		for prefix in ["acte-", "act-"]:
			var prefix_text := str(prefix)
			if text.begins_with(prefix_text):
				var suffix := text.trim_prefix(prefix_text)
				if suffix.is_valid_int():
					return int(suffix)
	return 0

# ---------------------------------------------------------------------------
# Zoom (sous-barre) et onglets de détails (refonte 04)
# ---------------------------------------------------------------------------

func _on_zoom_in_pressed() -> void:
	_set_graph_zoom(graph_edit.zoom * 1.1)

func _on_zoom_out_pressed() -> void:
	_set_graph_zoom(graph_edit.zoom * 0.9)

func _set_graph_zoom(value: float) -> void:
	if graph_edit == null:
		return
	graph_edit.zoom = clampf(value, GRAPH_ZOOM_MIN, GRAPH_ZOOM_MAX)
	_update_zoom_label()

func _update_zoom_label() -> void:
	if graph_edit == null or zoom_lbl == null:
		return
	zoom_lbl.text = "%d %%" % int(round(graph_edit.zoom * 100.0))

## Bascule l'inspecteur de droite entre Scène / Branches / Métadonnées.
func _set_details_tab(tab: String) -> void:
	if tab != DETAILS_TAB_SCENE and tab != DETAILS_TAB_BRANCHES and tab != DETAILS_TAB_META:
		tab = DETAILS_TAB_SCENE
	_details_tab = tab
	details_scene_tab.visible = tab == DETAILS_TAB_SCENE
	details_branches_tab.visible = tab == DETAILS_TAB_BRANCHES
	details_meta_tab.visible = tab == DETAILS_TAB_META
	_style_tab_button(details_btn_scene, tab == DETAILS_TAB_SCENE)
	_style_tab_button(details_btn_branches, tab == DETAILS_TAB_BRANCHES)
	_style_tab_button(details_btn_meta, tab == DETAILS_TAB_META)
	# La rangée d'actions reste collée en bas de l'inspecteur (hors scroll).
	if scene_action_bar != null:
		scene_action_bar.visible = tab == DETAILS_TAB_SCENE and not _selected_scene_id.is_empty()
	if tab == DETAILS_TAB_BRANCHES:
		_refresh_transitions_ui()

## Style « toggle » des onglets : filet or + fond accentué sur l'onglet actif.
func _style_tab_button(btn: Button, active: bool) -> void:
	ScenarioEditorStyle.style_tab_button(btn, active)

func _rebuild_graph() -> void:
	if _rebuild_scheduled:
		return
	_rebuild_scheduled = true
	call_deferred("_rebuild_graph_deferred")

func _rebuild_graph_deferred() -> void:
	_rebuild_scheduled = false
	_rebuilding_graph = true
	_commit_scene_editor()
	_sync_graph_layout_from_nodes()
	if graph_edit.has_method("clear_connections"):
		graph_edit.clear_connections()
	var stale: Array = []
	for child in graph_edit.get_children():
		if child is GraphNode:
			stale.append(child)
	for child in stale:
		graph_edit.remove_child(child)
		child.free()

	var scenes: Array = _scenario.get("scenes", [])
	var analysis := QuestNavigation.analyze_graph(_scenario)
	var unreachable: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		unreachable[str(uid)] = true

	for i in range(scenes.size()):
		var scene: Dictionary = scenes[i]
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid: String = str(scene.get("id", "scene-%d" % i))
		var node := _build_scene_graph_node(scene, sid, i, unreachable.has(sid))
		graph_edit.add_child(node)

	_apply_all_graph_connections()
	_rebuilding_graph = false
	_refresh_graph_health()
	if not _pending_focus_scene_id.is_empty():
		var focus_id := _pending_focus_scene_id
		_pending_focus_scene_id = ""
		call_deferred("_focus_graph_on_scene", focus_id)

func _sync_graph_layout_from_nodes() -> void:
	for child in graph_edit.get_children():
		if not child is GraphNode or not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		var sid := str(child.get_meta("scene_id", ""))
		var idx := _scene_index_for_id(sid)
		if idx < 0:
			continue
		var scene: Dictionary = _scenario["scenes"][idx]
		scene["graphPos"] = { "x": child.position_offset.x, "y": child.position_offset.y }
		var sz: Vector2 = child.size
		if child.has_meta("graph_size"):
			sz = child.get_meta("graph_size")
		if sz.x >= 10.0 and sz.y >= 10.0:
			scene["graphSize"] = { "w": sz.x, "h": sz.y }
		_scenario["scenes"][idx] = scene

func _build_scene_graph_node(scene: Dictionary, sid: String, index: int, is_unreachable: bool) -> GraphNode:
	var node := GraphNodeScene.instantiate()
	node.name = _stable_graph_node_name(sid)
	node.position_offset = _scene_graph_pos(scene, index)
	node.setup(scene, sid, index, is_unreachable, str(_scenario.get("startSceneId", "")), _selected_scene_id)
	node.context_requested.connect(_on_graph_node_context_requested)
	node.scene_activated.connect(_on_graph_scene_activated)
	node.scene_focus_requested.connect(_on_graph_scene_focus_requested)
	node.resize_request.connect(func(new_minsize: Vector2): _on_graph_node_resize_request(node, new_minsize))
	node.draggable = true
	node.selectable = true
	return node

func _apply_all_graph_connections() -> void:
	if graph_edit.has_method("clear_connections"):
		graph_edit.clear_connections()
	var scenes: Array = _scenario.get("scenes", [])
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var from_id := str(scene.get("id", ""))
		var from_name := _graph_node_name_for_id(from_id)
		if from_name.is_empty():
			continue
		for transition in scene.get("transitions", []):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", ""))
			if to_id.is_empty() or to_id == from_id:
				continue
			var to_name := _graph_node_name_for_id(to_id)
			if to_name.is_empty():
				continue
			if not graph_edit.is_node_connected(from_name, 0, to_name, 0):
				graph_edit.connect_node(from_name, 0, to_name, 0)
			_set_connection_activity_for_transition(from_name, to_name, transition)

func _set_connection_activity_for_transition(from_name: StringName, to_name: StringName, transition: Dictionary) -> void:
	# Les liens natifs de GraphEdit sont masqués : c'est l'overlay qui dessine les
	# branches (couleurs ★/branche/MJ). L'« activité » de GraphEdit mélange la
	# connexion vers une couleur claire et la rendait visible PAR-DESSUS les cartes
	# (couche _connection_layer) : on la force à 0 (couleur du port = transparente).
	graph_edit.set_connection_activity(from_name, 0, to_name, 0, 0.0)

func _connect_graph_edge(from_id: String, to_id: String, transition: Dictionary = {}) -> void:
	var from_name := _graph_node_name_for_id(from_id)
	var to_name := _graph_node_name_for_id(to_id)
	if from_name.is_empty() or to_name.is_empty():
		return
	if not graph_edit.is_node_connected(from_name, 0, to_name, 0):
		graph_edit.connect_node(from_name, 0, to_name, 0)
	if not transition.is_empty():
		_set_connection_activity_for_transition(from_name, to_name, transition)
	else:
		graph_edit.set_connection_activity(from_name, 0, to_name, 0, 0.0)

func _disconnect_graph_edge(from_id: String, to_id: String) -> void:
	var from_name := _graph_node_name_for_id(from_id)
	var to_name := _graph_node_name_for_id(to_id)
	if from_name.is_empty() or to_name.is_empty():
		return
	if graph_edit.is_node_connected(from_name, 0, to_name, 0):
		graph_edit.disconnect_node(from_name, 0, to_name, 0)

func _refresh_graph_node_chrome(scene_id: String = "") -> void:
	_notify_links_changed()
	var analysis := QuestNavigation.analyze_graph(_scenario)
	var unreachable: Dictionary = {}
	for uid in analysis.get("unreachable", []):
		unreachable[str(uid)] = true
	var start_id := str(_scenario.get("startSceneId", ""))
	for child in graph_edit.get_children():
		if not child is GraphNode or not child.has_method("refresh_chrome"):
			continue
		var sid := str(child.get_meta("scene_id", ""))
		if not scene_id.is_empty() and sid != scene_id:
			continue
		var scene := _get_scene_dict(sid)
		if scene.is_empty():
			continue
		child.refresh_chrome(scene, sid, unreachable.has(sid), start_id, _selected_scene_id)

func _scene_graph_pos(scene: Dictionary, index: int) -> Vector2:
	var gp = scene.get("graphPos", {})
	if gp is Dictionary and gp.has("x") and gp.has("y"):
		return Vector2(float(gp["x"]), float(gp["y"]))
	var col := index % 3
	var row := int(index / 3)
	return Vector2(40.0 + col * 280.0, 40.0 + row * 210.0)

func _stable_graph_node_name(scene_id: String) -> String:
	var safe := scene_id.validate_node_name()
	if safe.is_empty():
		safe = "unknown"
	return "SN_%s" % safe

func _graph_node_name_for_id(scene_id: String) -> StringName:
	if scene_id.is_empty() or _scene_index_for_id(scene_id) < 0:
		return StringName("")
	return StringName(_stable_graph_node_name(scene_id))

func _scene_index_for_id(scene_id: String) -> int:
	var scenes: Array = _scenario.get("scenes", [])
	for i in range(scenes.size()):
		if str(scenes[i].get("id", "")) == scene_id:
			return i
	return -1

func _get_scene_dict(scene_id: String) -> Dictionary:
	var idx := _scene_index_for_id(scene_id)
	if idx < 0:
		return {}
	return _scenario["scenes"][idx]

func _on_graph_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding_graph:
		return
	var from_id := _scene_id_from_graph_node(from_node)
	var to_id := _scene_id_from_graph_node(to_node)
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		_set_status("Lien impossible (même scène).")
		return
	if _has_transition(from_id, to_id):
		_set_status("Cette branche existe déjà.")
		return
	_add_or_update_transition(from_id, to_id, "Nouvelle branche", false, false)
	if not graph_edit.is_node_connected(from_node, from_port, to_node, to_port):
		graph_edit.connect_node(from_node, from_port, to_node, to_port)
	graph_edit.set_connection_activity(from_node, from_port, to_node, to_port, 0.0)
	_mark_dirty("Branche créée")
	_refresh_graph_node_chrome(from_id)
	if _selected_scene_id == from_id:
		_refresh_transitions_ui()
		_refresh_scene_panel()

func _on_graph_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if _rebuilding_graph:
		return
	var from_id := _scene_id_from_graph_node(from_node)
	var to_id := _scene_id_from_graph_node(to_node)
	if graph_edit.is_node_connected(from_node, from_port, to_node, to_port):
		graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	_remove_transition(from_id, to_id)
	_mark_dirty("Branche retirée")
	_refresh_graph_node_chrome(from_id)
	if _selected_scene_id == from_id:
		_refresh_transitions_ui()
		_refresh_scene_panel()

func _scene_id_from_graph_node(node_name: StringName) -> String:
	for child in graph_edit.get_children():
		if child is GraphNode and child.name == node_name:
			return str(child.get_meta("scene_id", ""))
	return ""

func _on_graph_node_selected(node: Node) -> void:
	if not node is GraphNode:
		return
	var sid := str(node.get_meta("scene_id", ""))
	if _tool == TOOL_LINK:
		_handle_link_click(sid)
		return
	_open_scene_editor(sid, false)

func _on_graph_scene_activated(scene_id: String) -> void:
	if _tool == TOOL_LINK:
		return
	_open_scene_editor(scene_id, false)

func _on_graph_scene_focus_requested(scene_id: String) -> void:
	if _tool == TOOL_LINK:
		return
	_open_scene_editor(scene_id, true)

func _open_scene_editor(sid: String, focus_fields: bool = false) -> void:
	if sid.is_empty():
		return
	# Ne pas reconstruire le graphe ici : ça casse le glisser-déposer au clic gauche.
	if sid != _selected_scene_id:
		_commit_scene_editor()
		_selected_scene_id = sid
		_refresh_graph_selection_styles()
	# Console 04 : cliquer un nœud ramène sur la fiche Scène de l'inspecteur.
	_set_details_tab(DETAILS_TAB_SCENE)
	_refresh_scene_panel()
	# Focus uniquement sur un vrai clic (pas pendant un drag), sinon le déplacement est annulé.
	if focus_fields:
		call_deferred("_focus_scene_editor_fields")

func _focus_scene_editor_fields() -> void:
	if not scene_editor.visible:
		return
	if scene_title:
		scene_title.grab_focus()
		scene_title.caret_column = scene_title.text.length()

func _refresh_graph_selection_styles() -> void:
	for child in graph_edit.get_children():
		if child is GraphNode and child.has_method("set_selected_visual"):
			var sid := str(child.get_meta("scene_id", ""))
			child.set_selected_visual(sid == _selected_scene_id)

func _on_graph_node_resize_request(node: GraphNode, new_minsize: Vector2) -> void:
	var clamped := new_minsize
	if node.has_method("apply_size"):
		clamped = node.apply_size(new_minsize)
	else:
		clamped = Vector2(
			clampf(new_minsize.x, 160.0, 520.0),
			clampf(new_minsize.y, 90.0, 420.0)
		)
		node.custom_minimum_size = clamped
		node.size = clamped
	var sid := str(node.get_meta("scene_id", ""))
	_store_scene_graph_size(sid, clamped)

func _store_scene_graph_size(sid: String, sz: Vector2) -> void:
	var idx := _scene_index_for_id(sid)
	if idx < 0 or sz.x < 10.0 or sz.y < 10.0:
		return
	var scene: Dictionary = _scenario["scenes"][idx]
	scene["graphSize"] = { "w": sz.x, "h": sz.y }
	_scenario["scenes"][idx] = scene
	_dirty = true

func _on_graph_popup_request(at_position: Vector2) -> void:
	_show_graph_scene_popup("", graph_edit.get_screen_position() + at_position)

func _on_graph_node_context_requested(scene_id: String, screen_pos: Vector2) -> void:
	_show_graph_scene_popup(scene_id, screen_pos)

func _show_graph_scene_popup(context_scene_id: String, screen_pos: Vector2) -> void:
	_graph_popup.clear()
	var has_branches := false
	if not context_scene_id.is_empty():
		var context_scene := _get_scene_dict(context_scene_id)
		var transitions: Array = context_scene.get("transitions", [])
		if typeof(transitions) == TYPE_ARRAY:
			for transition in transitions:
				if typeof(transition) != TYPE_DICTIONARY:
					continue
				var to_id := str(transition.get("to", ""))
				if to_id.is_empty() or _scene_index_for_id(to_id) < 0:
					continue
				var label := str(transition.get("label", "")).strip_edges()
				if label.is_empty():
					var target := _get_scene_dict(to_id)
					label = str(target.get("title", to_id))
				var mark := "★" if transition.get("default", false) else ("👁" if transition.get("gmOnly", false) else "→")
				var idx := _graph_popup.item_count
				_graph_popup.add_item("%s %s" % [mark, label])
				_graph_popup.set_item_metadata(idx, to_id)
				has_branches = true
	if has_branches:
		_graph_popup.add_separator("Toutes les scènes")
	else:
		_graph_popup.add_separator("Aller à une scène")

	for scene in _scenario.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid := str(scene.get("id", ""))
		if sid.is_empty():
			continue
		var idx := _graph_popup.item_count
		_graph_popup.add_item(QuestNavigation.format_picker_label(scene, sid == _selected_scene_id, false))
		_graph_popup.set_item_metadata(idx, sid)

	if _graph_popup.item_count == 0:
		return
	_graph_popup.position = Vector2i(screen_pos)
	_graph_popup.popup()

func _on_graph_popup_index_pressed(index: int) -> void:
	var sid := str(_graph_popup.get_item_metadata(index))
	if sid.is_empty():
		return
	_select_and_focus_scene(sid)

func _select_and_focus_scene(sid: String) -> void:
	if sid.is_empty():
		return
	_open_scene_editor(sid, true)
	call_deferred("_focus_graph_on_scene", sid)

func _focus_graph_on_scene(sid: String) -> void:
	var node_name := _graph_node_name_for_id(sid)
	if node_name.is_empty():
		return
	var gn := graph_edit.get_node_or_null(NodePath(str(node_name)))
	if not gn is GraphNode:
		return
	var z := graph_edit.zoom
	var view := graph_edit.size
	if view.x < 10 or view.y < 10:
		return
	var node_size: Vector2 = gn.size
	if node_size.x < 10:
		node_size = Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)
	graph_edit.scroll_offset = gn.position_offset * z - (view - node_size * z) * 0.5

func _on_graph_node_dragged(node: Node) -> void:
	if not node is GraphNode:
		return
	_persist_graph_node_layout(node)

func _on_graph_end_node_move() -> void:
	_sync_graph_layout_from_nodes()
	if not _dirty:
		_dirty = true

func _persist_graph_node_layout(node: GraphNode) -> void:
	var sid := str(node.get_meta("scene_id", ""))
	var idx := _scene_index_for_id(sid)
	if idx < 0:
		return
	var scene: Dictionary = _scenario["scenes"][idx]
	scene["graphPos"] = { "x": node.position_offset.x, "y": node.position_offset.y }
	_scenario["scenes"][idx] = scene
	_dirty = true

func _scene_graph_size(scene: Dictionary) -> Vector2:
	var gs = scene.get("graphSize", {})
	if typeof(gs) == TYPE_DICTIONARY and gs.has("w") and gs.has("h"):
		return Vector2(float(gs["w"]), float(gs["h"]))
	return Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)

func _refresh_scene_panel() -> void:
	# L'onglet Branches affiche une invite tant qu'aucune scène n'est sélectionnée.
	branches_hint_lbl.visible = _selected_scene_id.is_empty()
	if _selected_scene_id.is_empty():
		lbl_no_selection.visible = true
		scene_editor.visible = false
		scene_kicker_lbl.text = "SCÈNE — / —"
		scene_title_big.text = "Aucune scène sélectionnée"
		scene_id_chip.visible = false
		_clear_chip_row(scene_tag_chips)
		_clear_chip_row(scene_map_chips)
		_clear_chip_row(scene_npc_chips)
		scene_npc_col.visible = false
		if scene_action_bar != null:
			scene_action_bar.visible = false
		return
	lbl_no_selection.visible = false
	scene_editor.visible = true
	if scene_action_bar != null:
		scene_action_bar.visible = _details_tab == DETAILS_TAB_SCENE
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	var scene_index: int = _scene_index_for_id(_selected_scene_id)
	var scene_total: int = _scenario.get("scenes", []).size()
	var act: int = _scene_act_number(scene)
	# En-tête structuré façon Atelier : « SCÈNE n / N · ACTE n » + chip d'id.
	scene_kicker_lbl.text = "SCÈNE %d / %d" % [scene_index + 1, scene_total]
	if act > 0:
		scene_kicker_lbl.text += " · ACTE %d" % act
	scene_title_big.text = str(scene.get("title", _selected_scene_id))
	scene_id_chip.visible = true
	lbl_scene_id.text = _selected_scene_id
	var is_start: bool = _selected_scene_id == str(_scenario.get("startSceneId", ""))
	var transitions: Array = scene.get("transitions", [])
	var is_terminal: bool = typeof(transitions) != TYPE_ARRAY or transitions.is_empty()
	if is_start:
		scene_badge_lbl.text = "★ Scène de départ"
		scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.GOLD)
	elif is_terminal:
		scene_badge_lbl.text = "⚑ Scène terminale"
		scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.SUCCESS)
	else:
		var branch_n: int = transitions.size() if typeof(transitions) == TYPE_ARRAY else 0
		scene_badge_lbl.text = "↔ %d branche(s) sortante(s)" % branch_n
		scene_badge_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	var start_btn := %BtnSetStart
	start_btn.disabled = is_start
	start_btn.text = "★ Départ" if not is_start else "★ Scène de départ"
	scene_title.text = str(scene.get("title", ""))
	var tags: Array = scene.get("tags", [])
	if tags is Array:
		var tag_texts: PackedStringArray = []
		for tag in tags:
			tag_texts.append(str(tag))
		scene_tags.text = ", ".join(tag_texts)
		_refresh_tag_chips(tags)
	else:
		scene_tags.text = ""
		_clear_chip_row(scene_tag_chips)
	scene_content.text = str(scene.get("content", ""))
	_refresh_scene_maps_ui(scene)
	_refresh_scene_link_chips(scene)
	_refresh_transitions_ui()

## Chips de tags de la scène (sous le grand titre, façon Atelier).
func _refresh_tag_chips(tags: Array) -> void:
	_clear_chip_row(scene_tag_chips)
	for tag in tags:
		var text := str(tag).strip_edges()
		if text.is_empty():
			continue
		scene_tag_chips.add_child(_make_chip("#%s" % text, ThemeColors.LOG_NPC))

## Colonnes « Cartes liées » / « PNJ présents » : chips (masquées si vide).
func _refresh_scene_link_chips(scene: Dictionary) -> void:
	_clear_chip_row(scene_map_chips)
	for map_id in QuestNavigation.get_scene_map_ids(scene):
		var map_data := MapData.get_by_id(str(map_id))
		var title := str(map_data.get("title", map_id)) if not map_data.is_empty() else str(map_id)
		scene_map_chips.add_child(_make_chip(title, ThemeColors.INVESTIGATION_ACCENT))
	_clear_chip_row(scene_npc_chips)
	var present: Array = []
	for npc_variant in _scenario.get("npcs", []):
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		var scenes: Variant = npc.get("scenes", [])
		if typeof(scenes) != TYPE_ARRAY:
			continue
		for sid in scenes:
			if str(sid) == _selected_scene_id:
				present.append(str(npc.get("name", npc.get("id", "PNJ"))))
				break
	for npc_name in present:
		scene_npc_chips.add_child(_make_chip(npc_name, ThemeColors.LOG_NPC))
	scene_npc_col.visible = not present.is_empty()

## Chip compact (pilule teintée) pour l'inspecteur.
func _make_chip(text: String, color: Color) -> Control:
	return ScenarioEditorStyle.make_chip(text, color)

func _clear_chip_row(row: HFlowContainer) -> void:
	if row == null:
		return
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()

func _refresh_scene_maps_ui(scene: Dictionary) -> void:
	_refreshing_scene_maps = true
	scene_maps.clear()
	var roster := str(_scenario.get("roster", "general"))
	var scenario_id := str(_scenario.get("id", ""))
	var selected_ids := QuestNavigation.get_scene_map_ids(scene)
	var maps: Array = MapData.list_linkable_maps_for_scenario(scenario_id, roster)
	if maps.is_empty():
		scene_maps.add_item("Aucune carte disponible pour ce roster")
		scene_maps.set_item_disabled(0, true)
		_refreshing_scene_maps = false
		return
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid := str(m.get("id", ""))
		if mid.is_empty():
			continue
		var title := str(m.get("title", mid))
		var kind := "🌍" if MapData.is_world_map(m) else "🗺️"
		var linked := str(m.get("scenarioId", ""))
		var suffix := ""
		if not linked.is_empty() and linked == scenario_id:
			suffix = " · liée au scénario"
		elif linked.is_empty():
			suffix = " · libre"
		var idx := scene_maps.item_count
		scene_maps.add_item("%s %s%s" % [kind, title, suffix])
		scene_maps.set_item_metadata(idx, mid)
		if selected_ids.has(mid):
			scene_maps.select(idx, false)
	_refreshing_scene_maps = false

func _on_scene_maps_multi_selected(_index: int, _selected: bool) -> void:
	_on_scene_maps_changed()

func _on_scene_maps_changed() -> void:
	if _refreshing_scene_maps or _selected_scene_id.is_empty():
		return
	_commit_scene_maps_from_ui()
	_mark_dirty("Cartes de scène mises à jour")

func _commit_scene_maps_from_ui() -> void:
	if _selected_scene_id.is_empty() or _refreshing_scene_maps:
		return
	var idx := _scene_index_for_id(_selected_scene_id)
	if idx < 0:
		return
	# Ne pas écraser mapIds quand la liste affiche seulement le placeholder désactivé.
	if scene_maps.item_count == 0:
		return
	if scene_maps.item_count == 1 and scene_maps.is_item_disabled(0):
		return
	var selected: Array = []
	for i in scene_maps.get_selected_items():
		var mid := str(scene_maps.get_item_metadata(i))
		if mid.is_empty():
			continue
		selected.append(mid)
		_ensure_map_linked_to_scenario(mid)
	var scene: Dictionary = _scenario["scenes"][idx]
	scene["mapIds"] = selected
	_scenario["scenes"][idx] = scene

func _ensure_map_linked_to_scenario(map_id: String) -> void:
	var scenario_id := str(_scenario.get("id", ""))
	if scenario_id.is_empty() or map_id.is_empty():
		return
	var map_data := MapData.get_by_id(map_id)
	if map_data.is_empty():
		return
	if str(map_data.get("scenarioId", "")).is_empty():
		map_data["scenarioId"] = scenario_id
		MapData.update_map(map_data)

func _commit_scene_editor() -> void:
	if _selected_scene_id.is_empty():
		return
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		return
	var prev_title := str(scene.get("title", ""))
	scene["title"] = scene_title.text.strip_edges()
	scene["content"] = scene_content.text.strip_edges()
	var tag_parts := scene_tags.text.split(",", false)
	var tags: Array = []
	for part in tag_parts:
		var tag := str(part).strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	scene["tags"] = tags
	_commit_scene_maps_from_ui()
	if scene["title"] != prev_title:
		_dirty = true

func _refresh_transitions_ui() -> void:
	for child in transitions_list.get_children():
		child.queue_free()
	var scene := _get_scene_dict(_selected_scene_id)
	if scene.is_empty():
		branches_count_lbl.text = "BRANCHES SORTANTES"
		return
	var transitions: Array = scene.get("transitions", [])
	branches_count_lbl.text = "BRANCHES SORTANTES %d" % (
		transitions.size() if typeof(transitions) == TYPE_ARRAY else 0)
	if transitions.is_empty():
		var empty := Label.new()
		empty.text = "Aucune branche — scène terminale, ou glissez un lien depuis le graphe."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		transitions_list.add_child(empty)
		return
	for t_idx in range(transitions.size()):
		var transition: Dictionary = transitions[t_idx]
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		transitions_list.add_child(_create_transition_row(_selected_scene_id, t_idx, transition))

## Carte de branche (style Atelier) : barre de couleur à gauche (or = défaut,
## bleu = branche, violet = MJ), nom sur la première ligne, cible en dessous,
## badge DÉFAUT / BRANCHE / MJ à droite.
func _create_transition_row(from_id: String, index: int, transition: Dictionary) -> PanelContainer:
	var row := TransitionRowScene.instantiate()
	row.setup(transition)
	_populate_target_options(row.get_target_option(), str(transition.get("to", "")), from_id, index)
	_style_transition_row(row, transition)
	var captured_idx := index
	row.target_changed.connect(func(to_id: String):
		_on_transition_target_changed(from_id, captured_idx, to_id)
	)
	row.label_changed.connect(func(text: String):
		_update_transition_field(from_id, captured_idx, "label", text)
		_dirty = true
	)
	row.default_toggled.connect(func(on: bool):
		if on:
			_clear_default_transitions(from_id)
		_update_transition_field(from_id, captured_idx, "default", on)
		_mark_dirty()
		_refresh_outgoing_connection_styles(from_id)
		call_deferred("_refresh_transitions_ui")
	)
	row.gm_only_toggled.connect(func(on: bool):
		_update_transition_field(from_id, captured_idx, "gmOnly", on)
		_mark_dirty()
		_refresh_outgoing_connection_styles(from_id)
		call_deferred("_refresh_transitions_ui")
	)
	row.delete_pressed.connect(func():
		var old_to := _transition_to_at(from_id, captured_idx)
		_remove_transition_at(from_id, captured_idx)
		if not old_to.is_empty():
			_disconnect_graph_edge(from_id, old_to)
		_mark_dirty("Branche supprimée")
		_refresh_graph_node_chrome(from_id)
		_refresh_transitions_ui()
		_refresh_scene_panel()
	)
	return row

## Met la carte de branche au format compact de l'inspecteur Atelier.
func _style_transition_row(row: PanelContainer, transition: Dictionary) -> void:
	ScenarioEditorStyle.style_transition_row(row, transition)

func _populate_target_options(opt: OptionButton, selected_id: String, exclude_id: String = "", transition_index: int = -1) -> void:
	opt.clear()
	var select_idx := -1
	var added := 0
	var taken: Dictionary = {}
	if not exclude_id.is_empty():
		var scene := _get_scene_dict(exclude_id)
		var transitions: Array = scene.get("transitions", [])
		for i in range(transitions.size()):
			if i == transition_index:
				continue
			if typeof(transitions[i]) == TYPE_DICTIONARY:
				var other_to := str(transitions[i].get("to", ""))
				if not other_to.is_empty():
					taken[other_to] = true
	for i in range(_scenario.get("scenes", []).size()):
		var scene: Dictionary = _scenario["scenes"][i]
		var sid := str(scene.get("id", ""))
		if sid.is_empty() or sid == exclude_id:
			continue
		if taken.has(sid) and sid != selected_id:
			continue
		opt.add_item("%s" % scene.get("title", sid), added)
		opt.set_item_metadata(added, sid)
		if sid == selected_id:
			select_idx = added
		added += 1
	if opt.item_count <= 0:
		opt.add_item("(aucune cible)", 0)
		opt.set_item_metadata(0, "")
		opt.set_item_disabled(0, true)
		opt.select(0)
		return
	if select_idx < 0:
		# Cible invalide / orpheline : on l'ajoute pour ne pas basculer silencieusement.
		if not selected_id.is_empty():
			opt.add_item("⚠ %s (manquante)" % selected_id, added)
			opt.set_item_metadata(added, selected_id)
			select_idx = added
		else:
			select_idx = 0
	opt.select(select_idx)

func _on_transition_target_changed(from_id: String, index: int, to_id: String) -> void:
	to_id = to_id.strip_edges()
	if to_id.is_empty() or to_id == from_id:
		_set_status("Cible de branche invalide.")
		call_deferred("_refresh_transitions_ui")
		return
	var old_to := _transition_to_at(from_id, index)
	if old_to == to_id:
		return
	if _has_transition(from_id, to_id):
		_set_status("Cette branche existe déjà.")
		call_deferred("_refresh_transitions_ui")
		return
	_update_transition_field(from_id, index, "to", to_id)
	if not old_to.is_empty():
		_disconnect_graph_edge(from_id, old_to)
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	var tr: Dictionary = {}
	if index >= 0 and index < transitions.size() and typeof(transitions[index]) == TYPE_DICTIONARY:
		tr = transitions[index]
	_connect_graph_edge(from_id, to_id, tr)
	_mark_dirty("Cible de branche mise à jour")
	_refresh_graph_node_chrome(from_id)

func _transition_to_at(from_id: String, index: int) -> String:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index < 0 or index >= transitions.size():
		return ""
	if typeof(transitions[index]) != TYPE_DICTIONARY:
		return ""
	return str(transitions[index].get("to", ""))

func _refresh_outgoing_connection_styles(from_id: String) -> void:
	var scene := _get_scene_dict(from_id)
	var from_name := _graph_node_name_for_id(from_id)
	if from_name.is_empty() or scene.is_empty():
		return
	for transition in scene.get("transitions", []):
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		var to_name := _graph_node_name_for_id(str(transition.get("to", "")))
		if to_name.is_empty():
			continue
		if graph_edit.is_node_connected(from_name, 0, to_name, 0):
			_set_connection_activity_for_transition(from_name, to_name, transition)
	_refresh_graph_node_chrome(from_id)

func _update_transition_field(from_id: String, index: int, field: String, value: Variant) -> void:
	_notify_links_changed()
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index < 0 or index >= transitions.size():
		return
	var copy: Dictionary = transitions[index]
	copy[field] = value
	transitions[index] = copy
	scene["transitions"] = transitions

func _clear_default_transitions(from_id: String) -> void:
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	for i in range(transitions.size()):
		if typeof(transitions[i]) == TYPE_DICTIONARY:
			transitions[i]["default"] = false
	scene["transitions"] = transitions

func _has_transition(from_id: String, to_id: String) -> bool:
	var scene := _get_scene_dict(from_id)
	for transition in scene.get("transitions", []):
		if typeof(transition) == TYPE_DICTIONARY and str(transition.get("to", "")) == to_id:
			return true
	return false

func _add_or_update_transition(from_id: String, to_id: String, label: String, default: bool, gm_only: bool) -> void:
	_notify_links_changed()
	var scene := _get_scene_dict(from_id)
	if scene.is_empty() or from_id == to_id:
		return
	var transitions: Array = scene.get("transitions", [])
	for transition in transitions:
		if typeof(transition) == TYPE_DICTIONARY and str(transition.get("to", "")) == to_id:
			return
	if default:
		_clear_default_transitions(from_id)
	transitions.append({ "to": to_id, "label": label, "default": default, "gmOnly": gm_only })
	scene["transitions"] = transitions

func _remove_transition(from_id: String, to_id: String) -> void:
	_notify_links_changed()
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	for i in range(transitions.size() - 1, -1, -1):
		if typeof(transitions[i]) == TYPE_DICTIONARY and str(transitions[i].get("to", "")) == to_id:
			transitions.remove_at(i)
	scene["transitions"] = transitions

func _remove_transition_at(from_id: String, index: int) -> void:
	_notify_links_changed()
	var scene := _get_scene_dict(from_id)
	var transitions: Array = scene.get("transitions", [])
	if index >= 0 and index < transitions.size():
		transitions.remove_at(index)
	scene["transitions"] = transitions

func _on_add_transition_pressed() -> void:
	if _selected_scene_id.is_empty():
		_set_status("Sélectionnez une scène d'abord.")
		return
	_commit_scene_editor()
	var scenes: Array = _scenario.get("scenes", [])
	var target_id := ""
	for scene in scenes:
		var sid := str(scene.get("id", ""))
		if sid != _selected_scene_id and not _has_transition(_selected_scene_id, sid):
			target_id = sid
			break
	if target_id.is_empty():
		_set_status("Ajoutez une autre scène (non déjà liée) pour créer une branche.")
		return
	_add_or_update_transition(_selected_scene_id, target_id, "Nouvelle branche", false, false)
	_connect_graph_edge(_selected_scene_id, target_id, { "to": target_id, "label": "Nouvelle branche", "default": false, "gmOnly": false })
	_mark_dirty("Branche ajoutée")
	_refresh_graph_node_chrome(_selected_scene_id)
	_refresh_transitions_ui()
	_refresh_scene_panel()

func _on_add_scene_pressed() -> void:
	_commit_scene_editor()
	var scenes: Array = _scenario.get("scenes", [])
	var new_id := "scene-%d" % (scenes.size() + 1)
	while _scene_index_for_id(new_id) >= 0:
		new_id += "-x"
	var offset := Vector2(40 + (scenes.size() % 3) * 260, 40 + int(scenes.size() / 3) * 150)
	# Place near selected node if any
	if not _selected_scene_id.is_empty():
		var selected := _get_scene_dict(_selected_scene_id)
		var gp = selected.get("graphPos", {})
		if gp is Dictionary and gp.has("x"):
			offset = Vector2(float(gp["x"]) + QuestNavigation.LAYOUT_H_GAP, float(gp["y"]))
	var new_scene := {
		"id": new_id,
		"title": "Nouvelle scène %d" % (scenes.size() + 1),
		"content": "",
		"tags": [],
		"transitions": [],
		"mapIds": [],
		"graphPos": { "x": offset.x, "y": offset.y },
	}
	scenes.append(new_scene)
	_scenario["scenes"] = scenes
	if scenes.size() == 1:
		_scenario["startSceneId"] = new_id
	# Auto-link from selected scene if it had no path to the new one
	if not _selected_scene_id.is_empty() and _selected_scene_id != new_id:
		var from_scene := _get_scene_dict(_selected_scene_id)
		var existing: Array = from_scene.get("transitions", [])
		if typeof(existing) != TYPE_ARRAY or existing.is_empty():
			_add_or_update_transition(_selected_scene_id, new_id, "Continuer", true, false)
	_selected_scene_id = new_id
	_refresh_start_scene_options()
	_mark_dirty("Scène ajoutée")
	_rebuild_graph()
	_refresh_scene_panel()

func _on_set_start_pressed() -> void:
	if _selected_scene_id.is_empty():
		return
	_scenario["startSceneId"] = _selected_scene_id
	_refresh_start_scene_options()
	_mark_dirty("Scène de départ définie")
	_rebuild_graph()
	_refresh_scene_panel()

func _on_delete_scene_pressed() -> void:
	if _selected_scene_id.is_empty():
		return
	%ConfirmDeleteScene.dialog_text = "Supprimer la scène « %s » et ses liens ?" % _selected_scene_id
	%ConfirmDeleteScene.popup_centered()

func _on_confirm_delete_scene() -> void:
	if _selected_scene_id.is_empty():
		return
	var removing_id := _selected_scene_id
	var scenes: Array = _scenario.get("scenes", [])
	for i in range(scenes.size() - 1, -1, -1):
		if str(scenes[i].get("id", "")) == removing_id:
			scenes.remove_at(i)
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var transitions: Array = scene.get("transitions", [])
		for j in range(transitions.size() - 1, -1, -1):
			if typeof(transitions[j]) == TYPE_DICTIONARY and str(transitions[j].get("to", "")) == removing_id:
				transitions.remove_at(j)
		scene["transitions"] = transitions
	_scenario["scenes"] = scenes
	if str(_scenario.get("startSceneId", "")) == removing_id:
		if not scenes.is_empty():
			_scenario["startSceneId"] = str(scenes[0].get("id", ""))
		else:
			_scenario["startSceneId"] = ""
	_selected_scene_id = ""
	_refresh_start_scene_options()
	_mark_dirty("Scène supprimée")
	_rebuild_graph()
	_refresh_scene_panel()

func _on_auto_layout_pressed() -> void:
	_commit_scene_editor()
	_scenario = QuestNavigation.apply_auto_layout(_scenario)
	_mark_dirty("Disposition automatique")
	_journal_add("Disposition automatique appliquée (auto-layout)")
	_rebuild_graph()
	call_deferred("_on_fit_view_pressed")

## Cadre tout le graphe DANS L'ESPACE LIBRE du canevas : les marges réservées
## aux panneaux flottants (rail à gauche, pilules/minimap en bas) ne sont pas
## recouvertes par des cartes — c'est ce qui permet un canevas plein écran sans
## dock fixe tout en gardant les cartes lisibles.
func _on_fit_view_pressed() -> void:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	var found := false
	for child in graph_edit.get_children():
		if child is GraphNode:
			found = true
			var pos: Vector2 = child.position_offset
			var size: Vector2 = child.size
			if size.x < 10:
				size = Vector2(QuestNavigation.NODE_WIDTH, QuestNavigation.NODE_HEIGHT)
			min_pos = Vector2(minf(min_pos.x, pos.x), minf(min_pos.y, pos.y))
			max_pos = Vector2(maxf(max_pos.x, pos.x + size.x), maxf(max_pos.y, pos.y + size.y))
	if not found:
		return
	var content := Rect2(min_pos, max_pos - min_pos)
	var view := graph_edit.size
	if view.x < 10 or view.y < 10:
		return
	var insets := Rect2(FIT_INSET_LEFT, FIT_INSET_TOP,
		FIT_INSET_LEFT + FIT_INSET_RIGHT, FIT_INSET_TOP + FIT_INSET_BOTTOM)
	var available := Vector2(
		maxf(view.x - insets.size.x, 40.0),
		maxf(view.y - insets.size.y, 40.0))
	var zoom := clampf(minf(
		available.x / maxf(content.size.x, 1.0),
		available.y / maxf(content.size.y, 1.0)), GRAPH_ZOOM_MIN, GRAPH_ZOOM_MAX)
	graph_edit.zoom = zoom
	var drawn := content.size * zoom
	var offset := Vector2(
		FIT_INSET_LEFT + (available.x - drawn.x) * 0.5,
		FIT_INSET_TOP + (available.y - drawn.y) * 0.5)
	graph_edit.scroll_offset = content.position * zoom - offset
	_update_zoom_label()

func _on_validate_pressed() -> void:
	_commit_scene_editor()
	_on_meta_changed()
	var errors := QuestNavigation.validate_scenario_graph(_scenario)
	var analysis := QuestNavigation.analyze_graph(_scenario)
	_refresh_graph_health()
	if not errors.is_empty():
		_set_status("Erreur : %s" % str(errors[0]))
		return
	var warnings: Array = analysis.get("warnings", [])
	_journal_add("Validation — %d erreur(s), %d avertissement(s)" % [errors.size(), warnings.size()])
	if not warnings.is_empty():
		_set_status("Attention : %s" % str(warnings[0]))
	else:
		_set_status("Graphe valide — %d scènes, %d branches" % [
			int(analysis.get("sceneCount", 0)),
			int(analysis.get("branchCount", 0)),
		])

func _refresh_npc_list() -> void:
	for child in npc_list.get_children():
		child.queue_free()
	for i in range(_scenario.get("npcs", []).size()):
		var npc: Dictionary = _scenario["npcs"][i]
		if typeof(npc) != TYPE_DICTIONARY:
			continue
		npc_list.add_child(_create_npc_row(i, npc))

func _create_npc_row(index: int, npc: Dictionary) -> PanelContainer:
	var row := NpcRowScene.instantiate()
	row.setup(npc)
	row.name_changed.connect(func(text: String):
		_scenario["npcs"][index]["name"] = text
		_dirty = true
	)
	row.role_changed.connect(func(text: String):
		_scenario["npcs"][index]["role"] = text
		_dirty = true
	)
	row.description_changed.connect(func(text: String):
		_scenario["npcs"][index]["description"] = text
		_dirty = true
	)
	row.delete_pressed.connect(func():
		_scenario["npcs"].remove_at(index)
		_dirty = true
		_refresh_npc_list()
	)
	return row

func _on_add_npc_pressed() -> void:
	var npcs: Array = _scenario.get("npcs", [])
	if typeof(npcs) != TYPE_ARRAY:
		npcs = []
	npcs.append({ "id": "npc-%d" % (npcs.size() + 1), "name": "Nouveau PNJ", "role": "", "description": "" })
	_scenario["npcs"] = npcs
	_dirty = true
	_refresh_npc_list()

func _on_save_pressed() -> void:
	_commit_scene_editor()
	_sync_graph_layout_from_nodes()
	_on_meta_changed()
	var normalized := QuestNavigation.normalize_scenario(_scenario.duplicate(true))
	var error := _validate_scenario(normalized)
	if not error.is_empty():
		_set_status("Erreur : %s" % error)
		return
	GameData.save_scenario(normalized)
	_scenario = normalized.duplicate(true)
	_dirty = false
	_refresh_all()
	_journal_add("Scénario enregistré — %d scènes, %d branches" % [
		_scenario.get("scenes", []).size(),
		QuestNavigation.analyze_graph(_scenario).get("branchCount", 0),
	])
	_set_status("Scénario enregistré ✓")

func _validate_scenario(scenario: Dictionary) -> String:
	var errors := QuestNavigation.validate_scenario_graph(scenario)
	if not errors.is_empty():
		return str(errors[0])
	return ""

func _unhandled_input(event: InputEvent) -> void:
	var vp := get_viewport()
	# Palette de commandes ouverte : Échap la ferme avant tout le reste.
	if _palette != null and is_instance_valid(_palette) and bool(_palette.call("is_open")):
		if UiShortcuts.is_cancel(event):
			_palette.call("close")
			if vp != null:
				vp.set_input_as_handled()
			return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and not _is_text_input_focused():
			if key.ctrl_pressed and key.keycode == KEY_K:
				_open_palette()
				if vp != null:
					vp.set_input_as_handled()
				return
			match key.keycode:
				KEY_F:
					_on_fit_view_pressed()
					if vp != null:
						vp.set_input_as_handled()
					return
				KEY_L:
					_set_tool(TOOL_LINK)
					return
				KEY_N:
					_set_tool(TOOL_NOTE)
					return
				KEY_C:
					_set_tool(TOOL_FRAME)
					return
				KEY_V:
					_set_tool(TOOL_SELECT)
					return
	if UiShortcuts.is_cancel(event):
		if vp != null:
			vp.set_input_as_handled()
		_on_back_pressed()
	elif UiShortcuts.is_submit(event) or UiShortcuts.is_save(event):
		if vp != null:
			vp.set_input_as_handled()
		_on_save_pressed()

func _on_back_pressed() -> void:
	if _dirty:
		_pending_action = func(): _go_back()
		%ConfirmDiscard.popup_centered()
		return
	_go_back()

func _on_confirm_discard() -> void:
	if _pending_action.is_valid():
		_pending_action.call()
		_pending_action = Callable()

func _go_back() -> void:
	var mode := "investigation" if str(_scenario.get("roster", "")) == "investigation" \
		or str(_scenario.get("questFormat", "")) == "investigation" \
		or _locked_roster == "investigation" else "adventure"
	GameData.go_to_scenario_list(mode)

func _mark_dirty(status: String = "") -> void:
	_dirty = true
	_history_add("Modification" if status.is_empty() else status)
	_refresh_graph_health()
	if not status.is_empty():
		_set_status(status)

func _set_status(text: String) -> void:
	if _dirty and not text.begins_with("Scénario enregistré") and not text.begins_with("Erreur"):
		status_lbl.text = text + " · non sauvé"
	else:
		status_lbl.text = text


# ============================================================================
# Console de nœuds — shell complet (modes, outils, palette, minimap, dock)
# ============================================================================

## Construit les éléments de la refonte qui ne sont pas dans la scène : vues
## Scénario / PNJ / Cartes, rail d'outils vertical, palette Ctrl+K, minimap
## flottante, onglets du dock et activation des modes.
func _build_console_extras() -> void:
	_graph_panel = graph_panel_node
	# --- Vues Scénario / PNJ / Cartes, sous les panneaux flottants -----------
	var canvas_host := _graph_panel.get_parent() as Control
	if canvas_host != null:
		_views_host = Control.new()
		_views_host.name = "ViewsHost"
		_views_host.mouse_filter = Control.MOUSE_FILTER_STOP
		_views_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_views_host.visible = false
		canvas_host.add_child(_views_host)
		canvas_host.move_child(_views_host, _graph_panel.get_index() + 1)
		_instantiate_views()
	# --- Minimap : panneau flottant « Plan d'ensemble » (bas-gauche) ---------
	var mini_script: Resource = null
	if ResourceLoader.exists("res://scripts/scenario_editor/panels/editor_minimap.gd"):
		mini_script = load("res://scripts/scenario_editor/panels/editor_minimap.gd")
	if mini_script is Script:
		_minimap = (mini_script as Script).new() as Control
		if _minimap != null:
			add_child(_minimap)
			_minimap.call("setup", graph_edit, func() -> Dictionary: return _scenario)
			_minimap.call("set_caption", MINIMAP_CAPTION)
			_minimap.call("set_panel_size", MINIMAP_PANEL_SIZE)
			_minimap.call("set_placement", "bottom_left", MINIMAP_MARGIN)
			_minimap.call("set_enabled", true)
	# --- Palette de commandes (Ctrl+K) --------------------------------------
	var palette_script: Resource = null
	if ResourceLoader.exists("res://scripts/scenario_editor/panels/command_palette.gd"):
		palette_script = load("res://scripts/scenario_editor/panels/command_palette.gd")
	if palette_script is Script:
		_palette = (palette_script as Script).new() as Control
		if _palette != null:
			add_child(_palette)
			_palette.call("setup", self)
			_palette.connect("action_chosen", _on_palette_action)
	# --- Rail d'outils vertical flottant (canevas ouvert) --------------------
	_build_tool_rail()
	# --- Dock : onglets Problèmes / Historique / Journal --------------------
	_build_dock_tabs()
	_set_dock_open(false)
	# --- Modes : activer les boutons Scénario / PNJ / Cartes ----------------
	var mode_defs: Array = [
		[MODE_GRAPH, %BtnModeGraph],
		[MODE_SCENARIO, %BtnModeScenario],
		[MODE_NPC, %BtnModeNpc],
		[MODE_MAPS, %BtnModeMaps],
	]
	for mode_variant in mode_defs:
		var mode_def: Array = mode_variant
		var mode_btn: Button = mode_def[1] as Button
		if mode_btn == null:
			continue
		var captured_mode := str(mode_def[0])
		_mode_buttons[captured_mode] = mode_btn
		mode_btn.disabled = false
		mode_btn.tooltip_text = ""
		mode_btn.toggle_mode = true
		mode_btn.pressed.connect(func() -> void: _set_mode(captured_mode))
	_set_mode(MODE_GRAPH)
	_journal_add("Console prête — scénario « %s »" % str(_scenario.get("title", "")))
	_history_add("Ouverture de l'éditeur")

## Rail vertical flottant : 4 outils + séparateur + zoom − / + / cadrer.
func _build_tool_rail() -> void:
	var box := %RailBox as VBoxContainer
	if box == null:
		return
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	_tool_buttons.clear()
	var tool_defs: Array = [
		[TOOL_SELECT, "◉", "Sélection (V)"],
		[TOOL_LINK, "⟜", "Créer un lien (L) : cliquez la source puis la cible"],
		[TOOL_NOTE, "✎", "Note (N) : cliquez le plan pour poser une note"],
		[TOOL_FRAME, "▭", "Cadre (C) : glissez pour encadrer un acte"],
	]
	for tool_variant in tool_defs:
		var tool_def: Array = tool_variant
		var tool_btn := _make_console_button(str(tool_def[1]), str(tool_def[2]))
		tool_btn.toggle_mode = true
		tool_btn.name = "BtnTool%s" % str(tool_def[0]).capitalize()
		tool_btn.custom_minimum_size = Vector2(30, 28)
		tool_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tool_btn.add_theme_font_size_override("font_size", 16)
		box.add_child(tool_btn)
		_tool_buttons[str(tool_def[0])] = tool_btn
		var captured_tool := str(tool_def[0])
		tool_btn.pressed.connect(func() -> void: _set_tool(captured_tool))
	var sep := HSeparator.new()
	sep.name = "RailSep"
	sep.custom_minimum_size = Vector2(22, 1)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(sep)
	var rail_actions: Array = [
		["−", "Dézoomer le graphe", _on_zoom_out_pressed],
		["+", "Zoomer le graphe", _on_zoom_in_pressed],
		["⛶", "Cadrer tout le graphe (F)", _on_fit_view_pressed],
	]
	for action_variant in rail_actions:
		var action: Array = action_variant
		var action_btn := _make_console_button(str(action[0]), str(action[1]))
		action_btn.custom_minimum_size = Vector2(30, 28)
		action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		action_btn.add_theme_font_size_override("font_size", 16)
		box.add_child(action_btn)
		action_btn.pressed.connect(action[2] as Callable)
	_style_tool_buttons()

## Ouvre / ferme le dock flottant (masqué par défaut : côté ouvert d'Atelier).
func _set_dock_open(open: bool) -> void:
	_dock_open = open
	if dock_panel != null:
		dock_panel.visible = open
	if open:
		_set_dock_tab(_dock_tab)
	_update_canvas_chrome()

func _toggle_dock() -> void:
	_set_dock_open(not _dock_open)

## Enregistre le scénario puis lance une partie de test (même logique que la
## liste de scénarios : GameData.go_to_game_setup avec le format courant).
func _on_test_pressed() -> void:
	_on_save_pressed()
	if _dirty:
		return
	var scenario_id := str(_scenario.get("id", ""))
	if scenario_id.is_empty():
		_set_status("Erreur : scénario sans identifiant")
		return
	var setup_mode := "investigation" if _is_investigation_mode() else "adventure"
	_journal_add("Partie de test lancée sur « %s »" % scenario_id)
	GameData.go_to_game_setup(setup_mode, scenario_id)

## Duplique la scène sélectionnée (titre, contenu, tags, cartes, branches).
func _on_duplicate_scene_pressed() -> void:
	if _selected_scene_id.is_empty():
		_set_status("Sélectionnez une scène d'abord.")
		return
	_commit_scene_editor()
	var idx := _scene_index_for_id(_selected_scene_id)
	if idx < 0:
		return
	var source: Dictionary = _scenario["scenes"][idx]
	var copy: Dictionary = source.duplicate(true)
	var base_id := str(source.get("id", "scene"))
	var new_id := "%s-copie" % base_id
	var suffix := 2
	while _scene_index_for_id(new_id) >= 0:
		new_id = "%s-copie-%d" % [base_id, suffix]
		suffix += 1
	copy["id"] = new_id
	var source_title := str(source.get("title", new_id)).strip_edges()
	if source_title.is_empty():
		source_title = base_id
	copy["title"] = "%s (copie)" % source_title
	var gp: Variant = copy.get("graphPos", {})
	var pos := _scene_graph_pos(source, idx)
	if typeof(gp) == TYPE_DICTIONARY and gp.has("x") and gp.has("y"):
		pos = Vector2(float(gp["x"]), float(gp["y"]))
	copy["graphPos"] = { "x": pos.x, "y": pos.y + QuestNavigation.LAYOUT_V_GAP }
	var scenes: Array = _scenario.get("scenes", [])
	scenes.append(copy)
	_scenario["scenes"] = scenes
	_selected_scene_id = new_id
	_refresh_start_scene_options()
	_mark_dirty("Scène dupliquée")
	_rebuild_graph()
	_refresh_scene_panel()


## Instancie les vues Scénario / PNJ / Cartes (script séparé).
func _instantiate_views() -> void:
	if _views_host == null:
		return
	var script: Resource = null
	var views_path := "res://scripts/scenario_editor/panels/editor_views.gd"
	if ResourceLoader.exists(views_path):
		script = load(views_path)
	if not (script is Script):
		return
	_views = (script as Script).new() as Control
	if _views == null:
		return
	_views.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_views_host.add_child(_views)
	_views.call("setup", _scenario,
		func() -> Array: return MapData.maps,
		func() -> String: return _selected_scene_id)
	if _views.has_signal("scene_selected"):
		_views.connect("scene_selected", _on_view_scene_selected)
	if _views.has_signal("request_add_npc"):
		_views.connect("request_add_npc", _on_add_npc_pressed)
	if _views.has_signal("npc_changed"):
		_views.connect("npc_changed", func() -> void:
			_refresh_npc_list()
			_mark_dirty("PNJ modifié"))
	if _views.has_signal("map_link_changed"):
		_views.connect("map_link_changed", func() -> void:
			_refresh_scene_panel()
			_mark_dirty("Carte liée à une scène"))


## Crée un bouton compact style console.
func _make_console_button(text: String, tooltip: String) -> Button:
	return ScenarioEditorStyle.make_console_button(text, tooltip)


## Change le mode central : Graphe ou vue Scénario / PNJ / Cartes.
func _set_mode(mode: String) -> void:
	if mode != MODE_GRAPH and mode != MODE_SCENARIO and mode != MODE_NPC and mode != MODE_MAPS:
		mode = MODE_GRAPH
	_mode = mode
	_commit_scene_editor()
	if _graph_panel != null:
		_graph_panel.visible = mode == MODE_GRAPH
	if _views_host != null:
		_views_host.visible = mode != MODE_GRAPH
	# Panneaux flottants du canevas : seulement en vue Graphe.
	if canvas_overlay != null:
		canvas_overlay.visible = mode == MODE_GRAPH
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.call("set_enabled", mode == MODE_GRAPH)
	if _views != null and is_instance_valid(_views) and mode != MODE_GRAPH:
		_views.call("set_mode", mode)
		_views.call("refresh")
	for mode_key in _mode_buttons.keys():
		_style_tab_button(_mode_buttons[mode_key] as Button, str(mode_key) == mode)
	match mode:
		MODE_SCENARIO:
			_set_status("Vue Scénario")
		MODE_NPC:
			_set_status("Vue PNJ")
		MODE_MAPS:
			_set_status("Vue Cartes")
		_:
			_set_status("Prêt")


func _on_view_scene_selected(scene_id: String) -> void:
	_open_scene_editor(scene_id, false)
	if _views != null and is_instance_valid(_views):
		_views.call("refresh")


## Construit les panneaux Historique / Journal du dock (en plus des Problèmes).
func _build_dock_tabs() -> void:
	_dock_issues_panel = dock_issues_list
	var scroll := dock_issues_list.get_parent() as ScrollContainer
	if scroll == null:
		return
	_dock_history_panel = VBoxContainer.new()
	_dock_history_panel.name = "DockHistoryList"
	_dock_history_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_history_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_dock_history_panel)
	_dock_journal_panel = VBoxContainer.new()
	_dock_journal_panel.name = "DockJournalList"
	_dock_journal_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_journal_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_dock_journal_panel)
	var dock_btn_defs: Array = [
		[DOCK_TAB_ISSUES, dock_issues_btn],
		[DOCK_TAB_HISTORY, %BtnDockHistory],
		[DOCK_TAB_JOURNAL, %BtnDockJournal],
	]
	for entry_variant in dock_btn_defs:
		var entry: Array = entry_variant
		var btn: Button = entry[1] as Button
		if btn == null:
			continue
		var captured_tab := str(entry[0])
		_dock_buttons[captured_tab] = btn
		btn.disabled = false
		btn.tooltip_text = ""
		btn.pressed.connect(func() -> void: _set_dock_tab(captured_tab))
	_dock_history_panel.visible = false
	_dock_journal_panel.visible = false
	_set_dock_tab(DOCK_TAB_ISSUES)


func _set_dock_tab(tab: String) -> void:
	if tab != DOCK_TAB_ISSUES and tab != DOCK_TAB_HISTORY and tab != DOCK_TAB_JOURNAL:
		tab = DOCK_TAB_ISSUES
	_dock_tab = tab
	if _dock_issues_panel != null:
		_dock_issues_panel.visible = tab == DOCK_TAB_ISSUES
	if _dock_history_panel != null:
		_dock_history_panel.visible = tab == DOCK_TAB_HISTORY
	if _dock_journal_panel != null:
		_dock_journal_panel.visible = tab == DOCK_TAB_JOURNAL
	for tab_key in _dock_buttons.keys():
		_style_tab_button(_dock_buttons[tab_key] as Button, str(tab_key) == tab)
	if tab == DOCK_TAB_HISTORY:
		_render_history()
	elif tab == DOCK_TAB_JOURNAL:
		_render_journal()


func _on_validation_badge_pressed() -> void:
	_set_mode(MODE_GRAPH)
	_set_dock_tab(DOCK_TAB_ISSUES)
	_set_dock_open(true)


func _update_validation_badge() -> void:
	if _validation_badge == null:
		return
	var errors := QuestNavigation.validate_scenario_graph(_scenario).size()
	var suggestions := _graph_issues.size()
	var text := "%d erreur%s" % [errors, "s" if errors > 1 else ""]
	if errors == 0:
		text = "✓ 0 erreur"
	if suggestions > 0:
		text += " · %d suggestion%s" % [suggestions, "s" if suggestions > 1 else ""]
	_validation_badge.text = text
	var color: Color = ThemeColors.SUCCESS if errors == 0 else ThemeColors.DANGER
	_validation_badge.add_theme_color_override("font_color", color)
	_validation_badge.tooltip_text = "Voir les problèmes du graphe (%d)" % suggestions


# ---------------------------------------------------------------------------
# Historique et journal (dock)
# ---------------------------------------------------------------------------

func _history_add(text: String) -> void:
	_history_entries.append({
		"time": Time.get_time_string_from_system(),
		"text": text,
	})
	while _history_entries.size() > 120:
		_history_entries.pop_front()
	if _dock_tab == DOCK_TAB_HISTORY and _dock_history_panel != null:
		_render_history()


func _journal_add(text: String) -> void:
	_journal_entries.append({
		"time": Time.get_time_string_from_system(),
		"text": text,
	})
	while _journal_entries.size() > 120:
		_journal_entries.pop_front()
	if _dock_tab == DOCK_TAB_JOURNAL and _dock_journal_panel != null:
		_render_journal()


func _render_history() -> void:
	if _dock_history_panel == null:
		return
	for child in _dock_history_panel.get_children():
		child.queue_free()
	if _history_entries.is_empty():
		_dock_history_panel.add_child(_make_dock_label("Aucune action pour l'instant.", true))
		return
	for i in range(_history_entries.size() - 1, -1, -1):
		var entry: Dictionary = _history_entries[i]
		_dock_history_panel.add_child(_make_dock_row(str(entry.get("time", "")), str(entry.get("text", ""))))


func _render_journal() -> void:
	if _dock_journal_panel == null:
		return
	for child in _dock_journal_panel.get_children():
		child.queue_free()
	if _journal_entries.is_empty():
		_dock_journal_panel.add_child(_make_dock_label("Journal vide.", true))
		return
	for i in range(_journal_entries.size() - 1, -1, -1):
		var entry: Dictionary = _journal_entries[i]
		_dock_journal_panel.add_child(_make_dock_row(str(entry.get("time", "")), str(entry.get("text", ""))))


func _make_dock_row(time_text: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var time_lbl := Label.new()
	time_lbl.text = time_text
	time_lbl.theme_type_variation = &"MicroLabel"
	time_lbl.custom_minimum_size = Vector2(72, 0)
	var msg := Label.new()
	msg.text = text
	msg.theme_type_variation = &"MutedLabel"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(time_lbl)
	row.add_child(msg)
	return row


func _make_dock_label(text: String, muted: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"MutedLabel" if muted else &"CaptionLabel"
	return lbl


# ---------------------------------------------------------------------------
# Outils (rail de la sous-barre)
# ---------------------------------------------------------------------------

func _set_tool(tool: String) -> void:
	if tool != TOOL_SELECT and tool != TOOL_LINK and tool != TOOL_NOTE and tool != TOOL_FRAME:
		tool = TOOL_SELECT
	_tool = tool
	_link_source_id = ""
	if tool == TOOL_NOTE or tool == TOOL_FRAME:
		graph_edit.mouse_default_cursor_shape = Control.CURSOR_CROSS
	else:
		graph_edit.mouse_default_cursor_shape = Control.CURSOR_ARROW
	if _link_overlay != null and is_instance_valid(_link_overlay):
		_link_overlay.call("clear_tool_preview")
	_style_tool_buttons()
	match tool:
		TOOL_LINK:
			_set_status("Outil Lien")
		TOOL_NOTE:
			_set_status("Outil Note")
		TOOL_FRAME:
			_set_status("Outil Cadre")
		_:
			_set_status("Sélection")


func _style_tool_buttons() -> void:
	for tool_key in _tool_buttons.keys():
		_style_tab_button(_tool_buttons[tool_key] as Button, str(tool_key) == _tool)


## En mode Lien : premier clic = source, second = cible → crée la branche.
func _handle_link_click(scene_id: String) -> void:
	if scene_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if scene_id == _link_last_sid and now - _link_click_ms < 350:
		return
	_link_last_sid = scene_id
	_link_click_ms = now
	if _link_source_id.is_empty():
		_link_source_id = scene_id
		_open_scene_editor(scene_id, false)
		_set_status("Lien : départ « %s » — cliquez la scène cible" % _scene_title(scene_id))
		return
	if scene_id == _link_source_id:
		_link_source_id = ""
		_set_status("Lien annulé (même scène)")
		return
	if _has_transition(_link_source_id, scene_id):
		_set_status("Cette branche existe déjà")
		return
	var from_id := _link_source_id
	_add_or_update_transition(from_id, scene_id, "Nouvelle branche", false, false)
	_connect_graph_edge(from_id, scene_id, {
		"to": scene_id,
		"label": "Nouvelle branche",
		"default": false,
		"gmOnly": false,
	})
	_link_source_id = ""
	_mark_dirty("Branche créée (mode Lien)")
	_refresh_graph_node_chrome(from_id)
	_refresh_transitions_ui()
	_refresh_scene_panel()
	_set_status("Branche « %s » → « %s » créée" % [_scene_title(from_id), _scene_title(scene_id)])


func _scene_title(scene_id: String) -> String:
	var scene := _get_scene_dict(scene_id)
	return str(scene.get("title", scene_id))


# ---------------------------------------------------------------------------
# Notes et cadres (annotations du plan)
# ---------------------------------------------------------------------------

## Convertit une position écran en coordonnées graphe (position_offset).
func _graph_point_from_global(global_pos: Vector2) -> Vector2:
	var zoom := maxf(graph_edit.zoom, 0.0001)
	return (global_pos - graph_edit.global_position + graph_edit.scroll_offset) / zoom


## Gère les clics de souris quand un outil d'annotation est actif.
func _handle_annotation_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _tool == TOOL_NOTE:
			if _delete_note_at(_graph_point_from_global(mb.global_position)):
				graph_edit.accept_event()
				return true
			return false
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		var point := _graph_point_from_global(mb.global_position)
		if mb.pressed:
			if _tool == TOOL_NOTE:
				var note := _find_note_at(point)
				if not note.is_empty():
					_open_note_dialog(str(note.get("id", "")))
				else:
					_create_note_at(point)
				graph_edit.accept_event()
				return true
			if _tool == TOOL_FRAME:
				_frame_dragging = true
				_frame_drag_start = point
				_set_tool_preview_graph(Rect2(point, Vector2.ZERO))
				graph_edit.accept_event()
				return true
			return false
		if _tool == TOOL_FRAME and _frame_dragging:
			_frame_dragging = false
			var start := _frame_drag_start
			var rect := Rect2(start, point - start).abs()
			_clear_tool_preview()
			if rect.size.x > 60.0 and rect.size.y > 40.0:
				_create_frame(rect)
			graph_edit.accept_event()
			return true
		return false
	if event is InputEventMouseMotion and _frame_dragging:
		var point := _graph_point_from_global((event as InputEventMouseMotion).global_position)
		_set_tool_preview_graph(Rect2(_frame_drag_start, point - _frame_drag_start).abs())
		return true
	return false


func _set_tool_preview_graph(rect: Rect2) -> void:
	if _link_overlay != null and is_instance_valid(_link_overlay):
		_link_overlay.call("set_tool_preview_graph", rect)


func _clear_tool_preview() -> void:
	if _link_overlay != null and is_instance_valid(_link_overlay):
		_link_overlay.call("clear_tool_preview")


## Notes du plan : stockées dans le scénario (`editorNotes`), dessinées par
## l'overlay ; clic = éditer, clic droit = supprimer.
func _notes() -> Array:
	var raw: Variant = _scenario.get("editorNotes", [])
	return raw if raw is Array else []


func _create_note_at(point: Vector2) -> void:
	var notes: Array = _notes()
	notes.append({
		"id": "note-%d" % (notes.size() + 1),
		"text": "Note",
		"x": point.x,
		"y": point.y,
	})
	_scenario["editorNotes"] = notes
	_mark_dirty("Note ajoutée")
	_notify_links_changed()
	_open_note_dialog("note-%d" % notes.size())


func _find_note_at(point: Vector2) -> Dictionary:
	var notes: Array = _notes()
	for i in range(notes.size() - 1, -1, -1):
		var note: Dictionary = notes[i]
		var rect := Rect2(Vector2(float(note.get("x", 0.0)), float(note.get("y", 0.0))), Vector2(190, 64))
		if rect.has_point(point):
			return note
	return {}


func _delete_note_at(point: Vector2) -> bool:
	var note := _find_note_at(point)
	if note.is_empty():
		return false
	var notes: Array = _notes()
	var remaining: Array = []
	for entry in notes:
		if str((entry as Dictionary).get("id", "")) != str(note.get("id", "")):
			remaining.append(entry)
	_scenario["editorNotes"] = remaining
	_mark_dirty("Note supprimée")
	_notify_links_changed()
	return true


func _ensure_note_dialog() -> void:
	if _note_dialog != null and is_instance_valid(_note_dialog):
		return
	_note_dialog = ConfirmationDialog.new()
	_note_dialog.title = "Note du plan"
	_note_dialog.ok_button_text = "Valider"
	_note_dialog.cancel_button_text = "Annuler"
	_note_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	add_child(_note_dialog)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_note_edit = LineEdit.new()
	_note_edit.custom_minimum_size = Vector2(360, 0)
	_note_edit.placeholder_text = "Texte de la note…"
	margin.add_child(_note_edit)
	_note_dialog.add_child(margin)
	_note_dialog.confirmed.connect(_on_note_dialog_confirmed)


func _open_note_dialog(note_id: String) -> void:
	_ensure_note_dialog()
	_note_editing_id = note_id
	var text := ""
	for entry in _notes():
		if str((entry as Dictionary).get("id", "")) == note_id:
			text = str((entry as Dictionary).get("text", ""))
			break
	_note_edit.text = text
	_note_dialog.popup_centered(Vector2i(420, 120))
	_note_edit.grab_focus()


func _on_note_dialog_confirmed() -> void:
	if _note_editing_id.is_empty():
		return
	var notes: Array = _notes()
	for i in range(notes.size()):
		var note: Dictionary = notes[i]
		if str(note.get("id", "")) == _note_editing_id:
			note["text"] = _note_edit.text.strip_edges()
			notes[i] = note
			break
	_scenario["editorNotes"] = notes
	_note_editing_id = ""
	_mark_dirty("Note modifiée")
	_notify_links_changed()


## Cadres libres : stockés dans le scénario (`editorFrames`), dessinés SOUS les
## cartes avec les cadres d'actes.
func _create_frame(rect: Rect2) -> void:
	var frames: Array = _scenario.get("editorFrames", [])
	if not (frames is Array):
		frames = []
	frames.append({
		"id": "cadre-%d" % (frames.size() + 1),
		"label": "CADRE %d" % (frames.size() + 1),
		"x": rect.position.x,
		"y": rect.position.y,
		"w": rect.size.x,
		"h": rect.size.y,
	})
	_scenario["editorFrames"] = frames
	_mark_dirty("Cadre créé")
	_notify_links_changed()


# ---------------------------------------------------------------------------
# Palette de commandes (Ctrl+K)
# ---------------------------------------------------------------------------

func _open_palette() -> void:
	if _palette == null or not is_instance_valid(_palette):
		return
	_palette.call("open", _palette_items())


func _palette_items() -> Array:
	var items: Array = []
	for scene_variant in _scenario.get("scenes", []):
		if typeof(scene_variant) != TYPE_DICTIONARY:
			continue
		var scene: Dictionary = scene_variant
		var scene_id := str(scene.get("id", ""))
		items.append({
			"id": "scene:" + scene_id,
			"label": str(scene.get("title", scene_id)),
			"hint": scene_id,
			"category": "Scènes",
		})
	var tool_defs: Array = [
		[TOOL_SELECT, "Sélection"],
		[TOOL_LINK, "Créer un lien"],
		[TOOL_NOTE, "Poser une note"],
		[TOOL_FRAME, "Créer un cadre"],
	]
	for tool_variant in tool_defs:
		var tool_def: Array = tool_variant
		items.append({
			"id": "tool:" + str(tool_def[0]),
			"label": str(tool_def[1]),
			"hint": "Outil",
			"category": "Outils",
		})
	var mode_defs: Array = [
		[MODE_GRAPH, "Vue Graphe"],
		[MODE_SCENARIO, "Vue Scénario"],
		[MODE_NPC, "Vue PNJ"],
		[MODE_MAPS, "Vue Cartes"],
	]
	for mode_variant in mode_defs:
		var mode_def: Array = mode_variant
		items.append({
			"id": "mode:" + str(mode_def[0]),
			"label": str(mode_def[1]),
			"hint": "Mode",
			"category": "Navigation",
		})
	var actions: Array = [
		["autolayout", "Auto-layout du graphe"],
		["fit", "Cadrer le graphe"],
		["validate", "Valider le scénario"],
		["save", "Enregistrer"],
		["addscene", "Ajouter une scène"],
		["addnpc", "Ajouter un PNJ"],
		["addtransition", "Ajouter une branche à la scène"],
		["focus", "Cadrer la scène sélectionnée"],
	]
	for action_variant in actions:
		var action_def: Array = action_variant
		items.append({
			"id": "act:" + str(action_def[0]),
			"label": str(action_def[1]),
			"hint": "Commande",
			"category": "Actions",
		})
	return items


func _on_palette_action(id: String) -> void:
	if id.begins_with("scene:"):
		_set_mode(MODE_GRAPH)
		_select_and_focus_scene(id.substr(6))
		return
	if id.begins_with("tool:"):
		_set_tool(id.substr(5))
		return
	if id.begins_with("mode:"):
		_set_mode(id.substr(5))
		return
	if id.begins_with("act:"):
		match id.substr(4):
			"autolayout":
				_on_auto_layout_pressed()
			"fit":
				_on_fit_view_pressed()
			"validate":
				_on_validate_pressed()
			"save":
				_on_save_pressed()
			"addscene":
				_on_add_scene_pressed()
			"addnpc":
				_on_add_npc_pressed()
			"addtransition":
				_on_add_transition_pressed()
			"focus":
				if not _selected_scene_id.is_empty():
					_select_and_focus_scene(_selected_scene_id)


func _is_text_input_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null:
		return false
	return focus is LineEdit or focus is TextEdit
