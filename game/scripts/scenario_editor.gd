extends Control

const UiShortcuts := preload("res://scripts/shared/ui_shortcuts.gd")

const QuestNavigation = preload("res://scripts/quest_navigation.gd")
const GraphControllerScript := preload("res://scripts/scenario_editor/graph_controller.gd")
const SceneInspectorScript := preload("res://scripts/scenario_editor/scene_inspector.gd")
const DockHistoryScript := preload("res://scripts/scenario_editor/dock_history.gd")
const TransitionsPanelScript := preload("res://scripts/scenario_editor/transitions_panel.gd")
const ScenarioEditorStyle := preload("res://scripts/scenario_editor/scenario_editor_style.gd")

## Inspecteur de droite (≈ 390 px, style Atelier).
const INSPECTOR_WIDTH := 380.0
## Panneau flottant « Plan d'ensemble » (minimap) en bas-gauche du canevas.
const MINIMAP_CAPTION := "Plan d'ensemble"
const MINIMAP_PANEL_SIZE := Vector2(220.0, 150.0)
const MINIMAP_MARGIN := Vector2(10.0, 62.0)
## Onglets de l'inspecteur de droite (refonte 04).
const DETAILS_TAB_SCENE := SceneInspectorScript.DETAILS_TAB_SCENE
const DETAILS_TAB_BRANCHES := SceneInspectorScript.DETAILS_TAB_BRANCHES
const DETAILS_TAB_META := SceneInspectorScript.DETAILS_TAB_META
## Modes du centre (refonte 04 « Console de nœuds »).
const MODE_GRAPH := "graph"
const MODE_SCENARIO := "scenario"
const MODE_NPC := "npc"
const MODE_MAPS := "maps"
## Outils de la sous-barre.
const TOOL_SELECT := GraphControllerScript.TOOL_SELECT
const TOOL_LINK := GraphControllerScript.TOOL_LINK
const TOOL_NOTE := GraphControllerScript.TOOL_NOTE
const TOOL_FRAME := GraphControllerScript.TOOL_FRAME
## Onglets du dock bas.
const DOCK_TAB_ISSUES := DockHistoryScript.DOCK_TAB_ISSUES
const DOCK_TAB_HISTORY := DockHistoryScript.DOCK_TAB_HISTORY
const DOCK_TAB_JOURNAL := DockHistoryScript.DOCK_TAB_JOURNAL

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
var _graph = GraphControllerScript.new()
var _scene_panel = SceneInspectorScript.new()
var _dock = DockHistoryScript.new()
var _transitions = TransitionsPanelScript.new()

func _ready() -> void:
	_scene_panel.setup(self)
	_dock.setup(self)
	_transitions.setup(self)
	_graph.setup(self)
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
	_graph._configure_graph_edit()

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
	_graph._setup_link_overlay()

func _notify_links_changed() -> void:
	_graph._notify_links_changed()

## Suivi du survol (indispensable : l'overlay est traversant, donc sans souris)
## et suppression d'une branche au clic droit sur le lien *visible*.
func _input(event: InputEvent) -> void:
	_graph._input(event)

func _on_graph_gui_input(event: InputEvent) -> void:
	_graph._on_graph_gui_input(event)

func _is_pointer_over_graph_node() -> bool:
	return _graph._is_pointer_over_graph_node()

func _stop_graph_panning() -> void:
	_graph._stop_graph_panning()

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
	_graph._setup_graph_popup()

func _connect_graph_signals() -> void:
	_graph._connect_graph_signals()

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
	_dock._refresh_dock(analysis)

func _collect_graph_issues(analysis: Dictionary) -> Array:
	return _dock._collect_graph_issues(analysis)

func _create_dock_issue_row(issue: Dictionary) -> HBoxContainer:
	return _dock._create_dock_issue_row(issue)

func _issue_rank(issue: Dictionary) -> int:
	return _dock._issue_rank(issue)

## Numéro d'acte déduit des tags d'une scène (« acte-2 », « act-2 »), 0 sinon.
func _scene_act_number(scene: Dictionary) -> int:
	return _dock._scene_act_number(scene)

func _on_zoom_in_pressed() -> void:
	_graph._on_zoom_in_pressed()

func _on_zoom_out_pressed() -> void:
	_graph._on_zoom_out_pressed()

func _set_graph_zoom(value: float) -> void:
	_graph._set_graph_zoom(value)

func _update_zoom_label() -> void:
	_graph._update_zoom_label()

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
	_graph._rebuild_graph()

func _rebuild_graph_deferred() -> void:
	_graph._rebuild_graph_deferred()

func _sync_graph_layout_from_nodes() -> void:
	_graph._sync_graph_layout_from_nodes()

func _build_scene_graph_node(scene: Dictionary, sid: String, index: int, is_unreachable: bool) -> GraphNode:
	return _graph._build_scene_graph_node(scene, sid, index, is_unreachable)

func _apply_all_graph_connections() -> void:
	_graph._apply_all_graph_connections()

func _set_connection_activity_for_transition(from_name: StringName, to_name: StringName, transition: Dictionary) -> void:
	_graph._set_connection_activity_for_transition(from_name, to_name, transition)

func _connect_graph_edge(from_id: String, to_id: String, transition: Dictionary = {}) -> void:
	_graph._connect_graph_edge(from_id, to_id, transition)

func _disconnect_graph_edge(from_id: String, to_id: String) -> void:
	_graph._disconnect_graph_edge(from_id, to_id)

func _refresh_graph_node_chrome(scene_id: String = "") -> void:
	_graph._refresh_graph_node_chrome(scene_id)

func _scene_graph_pos(scene: Dictionary, index: int) -> Vector2:
	return _graph._scene_graph_pos(scene, index)

func _stable_graph_node_name(scene_id: String) -> String:
	return _graph._stable_graph_node_name(scene_id)

func _graph_node_name_for_id(scene_id: String) -> StringName:
	return _graph._graph_node_name_for_id(scene_id)

func _scene_index_for_id(scene_id: String) -> int:
	return _graph._scene_index_for_id(scene_id)

func _get_scene_dict(scene_id: String) -> Dictionary:
	return _graph._get_scene_dict(scene_id)

func _on_graph_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph._on_graph_connection_request(from_node, from_port, to_node, to_port)

func _on_graph_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	_graph._on_graph_disconnection_request(from_node, from_port, to_node, to_port)

func _scene_id_from_graph_node(node_name: StringName) -> String:
	return _graph._scene_id_from_graph_node(node_name)

func _on_graph_node_selected(node: Node) -> void:
	_graph._on_graph_node_selected(node)

func _on_graph_scene_activated(scene_id: String) -> void:
	_graph._on_graph_scene_activated(scene_id)

func _on_graph_scene_focus_requested(scene_id: String) -> void:
	_graph._on_graph_scene_focus_requested(scene_id)

func _open_scene_editor(sid: String, focus_fields: bool = false) -> void:
	_scene_panel._open_scene_editor(sid, focus_fields)

func _focus_scene_editor_fields() -> void:
	_scene_panel._focus_scene_editor_fields()

func _refresh_graph_selection_styles() -> void:
	_graph._refresh_graph_selection_styles()

func _on_graph_node_resize_request(node: GraphNode, new_minsize: Vector2) -> void:
	_graph._on_graph_node_resize_request(node, new_minsize)

func _store_scene_graph_size(sid: String, sz: Vector2) -> void:
	_graph._store_scene_graph_size(sid, sz)

func _on_graph_popup_request(at_position: Vector2) -> void:
	_graph._on_graph_popup_request(at_position)

func _on_graph_node_context_requested(scene_id: String, screen_pos: Vector2) -> void:
	_graph._on_graph_node_context_requested(scene_id, screen_pos)

func _show_graph_scene_popup(context_scene_id: String, screen_pos: Vector2) -> void:
	_graph._show_graph_scene_popup(context_scene_id, screen_pos)

func _on_graph_popup_index_pressed(index: int) -> void:
	_graph._on_graph_popup_index_pressed(index)

func _select_and_focus_scene(sid: String) -> void:
	_graph._select_and_focus_scene(sid)

func _focus_graph_on_scene(sid: String) -> void:
	_graph._focus_graph_on_scene(sid)

func _on_graph_node_dragged(node: Node) -> void:
	_graph._on_graph_node_dragged(node)

func _on_graph_end_node_move() -> void:
	_graph._on_graph_end_node_move()

func _persist_graph_node_layout(node: GraphNode) -> void:
	_graph._persist_graph_node_layout(node)

func _scene_graph_size(scene: Dictionary) -> Vector2:
	return _graph._scene_graph_size(scene)

func _refresh_scene_panel() -> void:
	_scene_panel._refresh_scene_panel()

## Chips de tags de la scène (sous le grand titre, façon Atelier).
func _refresh_tag_chips(tags: Array) -> void:
	_scene_panel._refresh_tag_chips(tags)

## Colonnes « Cartes liées » / « PNJ présents » : chips (masquées si vide).
func _refresh_scene_link_chips(scene: Dictionary) -> void:
	_scene_panel._refresh_scene_link_chips(scene)

## Chip compact (pilule teintée) pour l'inspecteur.
func _make_chip(text: String, color: Color) -> Control:
	return ScenarioEditorStyle.make_chip(text, color)

func _clear_chip_row(row: HFlowContainer) -> void:
	_scene_panel._clear_chip_row(row)

func _refresh_scene_maps_ui(scene: Dictionary) -> void:
	_scene_panel._refresh_scene_maps_ui(scene)

func _on_scene_maps_multi_selected(_index: int, _selected: bool) -> void:
	_scene_panel._on_scene_maps_multi_selected(_index, _selected)

func _on_scene_maps_changed() -> void:
	_scene_panel._on_scene_maps_changed()

func _commit_scene_maps_from_ui() -> void:
	_scene_panel._commit_scene_maps_from_ui()

func _ensure_map_linked_to_scenario(map_id: String) -> void:
	_scene_panel._ensure_map_linked_to_scenario(map_id)

func _commit_scene_editor() -> void:
	_scene_panel._commit_scene_editor()

func _refresh_transitions_ui() -> void:
	_transitions._refresh_transitions_ui()

## Carte de branche (style Atelier) : barre de couleur à gauche (or = défaut,
## bleu = branche, violet = MJ), nom sur la première ligne, cible en dessous,
## badge DÉFAUT / BRANCHE / MJ à droite.
func _create_transition_row(from_id: String, index: int, transition: Dictionary) -> PanelContainer:
	return _transitions._create_transition_row(from_id, index, transition)

## Met la carte de branche au format compact de l'inspecteur Atelier.
func _style_transition_row(row: PanelContainer, transition: Dictionary) -> void:
	ScenarioEditorStyle.style_transition_row(row, transition)

func _populate_target_options(opt: OptionButton, selected_id: String, exclude_id: String = "", transition_index: int = -1) -> void:
	_transitions._populate_target_options(opt, selected_id, exclude_id, transition_index)

func _on_transition_target_changed(from_id: String, index: int, to_id: String) -> void:
	_transitions._on_transition_target_changed(from_id, index, to_id)

func _transition_to_at(from_id: String, index: int) -> String:
	return _transitions._transition_to_at(from_id, index)

func _refresh_outgoing_connection_styles(from_id: String) -> void:
	_graph._refresh_outgoing_connection_styles(from_id)

func _update_transition_field(from_id: String, index: int, field: String, value: Variant) -> void:
	_transitions._update_transition_field(from_id, index, field, value)

func _clear_default_transitions(from_id: String) -> void:
	_transitions._clear_default_transitions(from_id)

func _has_transition(from_id: String, to_id: String) -> bool:
	return _transitions._has_transition(from_id, to_id)

func _add_or_update_transition(from_id: String, to_id: String, label: String, default: bool, gm_only: bool) -> void:
	_transitions._add_or_update_transition(from_id, to_id, label, default, gm_only)

func _remove_transition(from_id: String, to_id: String) -> void:
	_transitions._remove_transition(from_id, to_id)

func _remove_transition_at(from_id: String, index: int) -> void:
	_transitions._remove_transition_at(from_id, index)

func _on_add_transition_pressed() -> void:
	_transitions._on_add_transition_pressed()

func _on_add_scene_pressed() -> void:
	_scene_panel._on_add_scene_pressed()

func _on_set_start_pressed() -> void:
	_scene_panel._on_set_start_pressed()

func _on_delete_scene_pressed() -> void:
	_scene_panel._on_delete_scene_pressed()

func _on_confirm_delete_scene() -> void:
	_scene_panel._on_confirm_delete_scene()

func _on_auto_layout_pressed() -> void:
	_graph._on_auto_layout_pressed()

## Cadre tout le graphe DANS L'ESPACE LIBRE du canevas : les marges réservées
## aux panneaux flottants (rail à gauche, pilules/minimap en bas) ne sont pas
## recouvertes par des cartes — c'est ce qui permet un canevas plein écran sans
## dock fixe tout en gardant les cartes lisibles.
func _on_fit_view_pressed() -> void:
	_graph._on_fit_view_pressed()

func _on_validate_pressed() -> void:
	_dock._on_validate_pressed()

func _refresh_npc_list() -> void:
	_scene_panel._refresh_npc_list()

func _create_npc_row(index: int, npc: Dictionary) -> PanelContainer:
	return _scene_panel._create_npc_row(index, npc)

func _on_add_npc_pressed() -> void:
	_scene_panel._on_add_npc_pressed()

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
	return _dock._validate_scenario(scenario)

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
	_dock._set_dock_open(open)

func _toggle_dock() -> void:
	_dock._toggle_dock()

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
	_scene_panel._on_duplicate_scene_pressed()


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
	_dock._build_dock_tabs()


func _set_dock_tab(tab: String) -> void:
	_dock._set_dock_tab(tab)


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
	_dock._history_add(text)


func _journal_add(text: String) -> void:
	_dock._journal_add(text)


func _render_history() -> void:
	_dock._render_history()


func _render_journal() -> void:
	_dock._render_journal()


func _make_dock_row(time_text: String, text: String) -> Control:
	return _dock._make_dock_row(time_text, text)


func _make_dock_label(text: String, muted: bool) -> Label:
	return _dock._make_dock_label(text, muted)

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
	return _scene_panel._scene_title(scene_id)

## Convertit une position écran en coordonnées graphe (position_offset).
func _graph_point_from_global(global_pos: Vector2) -> Vector2:
	return _graph._graph_point_from_global(global_pos)


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
	_graph._set_tool_preview_graph(rect)


func _clear_tool_preview() -> void:
	_graph._clear_tool_preview()


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
