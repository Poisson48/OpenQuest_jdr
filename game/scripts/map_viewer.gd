extends Control

const MapModeScript := preload("res://scripts/maps/map_mode.gd")

@onready var title_lbl: Label = %MapTitle

var _map_data: Dictionary = {}
var _edit_mode: bool = false
var _title_input: LineEdit
var _hint_lbl: Label
var _btn_mode_simple: Button
var _btn_mode_complex: Button
var _mode_hint_lbl: Label
var _simple_editor: Control
var _complex_editor: Control

func _ready() -> void:
	%BtnBack.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/hub.tscn"))
	_edit_mode = MapData.editor_mode == "edit"
	_bind_ui()
	_sync_chrome()
	_load_map()
	resized.connect(_on_viewer_resized)
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_on_viewer_resized):
		vp.size_changed.connect(_on_viewer_resized)

func _on_viewer_resized() -> void:
	if _complex_editor == null or not _complex_editor.visible:
		return
	if _complex_editor.has_method("_on_viewport_size_changed"):
		_complex_editor.call("_on_viewport_size_changed")

func _bind_ui() -> void:
	_title_input = %TitleInput
	_hint_lbl = %LblHint
	_btn_mode_simple = %ModeRow.get_node("%BtnModeSimple")
	_btn_mode_complex = %ModeRow.get_node("%BtnModeComplex")
	_mode_hint_lbl = %ModeRow.get_node("%LblModeHint")
	_simple_editor = %SimpleEditor
	_complex_editor = %MapEditor

	%BtnSave.pressed.connect(_save_map)
	%BtnEdit.pressed.connect(func():
		_edit_mode = true
		MapData.editor_mode = "edit"
		_rebuild_for_mode()
	)
	%BtnPreview.pressed.connect(func():
		_pull_active_editor()
		_edit_mode = false
		MapData.editor_mode = "preview"
		_rebuild_for_mode()
	)
	_btn_mode_simple.pressed.connect(func(): _set_render_mode(MapModeScript.SIMPLE))
	_btn_mode_complex.pressed.connect(func(): _set_render_mode(MapModeScript.COMPLEX))

	if _simple_editor:
		_simple_editor.open_map_requested.connect(_on_editor_open_map)
		_simple_editor.place_on_world_requested.connect(_on_place_on_world)
		_simple_editor.save_requested.connect(func():
			_map_data = _simple_editor.apply_to_map_data()
			_sync_title_from_map()
		)
	if _complex_editor:
		_complex_editor.open_map_requested.connect(_on_editor_open_map)

func _sync_chrome() -> void:
	_title_input.visible = _edit_mode
	title_lbl.visible = not _edit_mode
	%BtnSave.visible = _edit_mode
	%BtnEdit.visible = not _edit_mode
	%BtnPreview.visible = _edit_mode

func _sync_render_mode_ui() -> void:
	if _btn_mode_simple == null or _map_data.is_empty():
		return
	var mode := MapData.get_render_mode(_map_data)
	_btn_mode_simple.set_pressed_no_signal(mode == MapModeScript.SIMPLE)
	_btn_mode_complex.set_pressed_no_signal(mode == MapModeScript.COMPLEX)
	var editable := _edit_mode
	_btn_mode_simple.disabled = not editable
	_btn_mode_complex.disabled = not editable
	if editable:
		if mode == MapModeScript.COMPLEX:
			var style := str(_map_data.get("renderStyle", "diorama"))
			if style == "vtt":
				_mode_hint_lbl.text = "VTT 3D : grille, murs volumétriques, ombres, fog et tokens."
			elif style == "dd2_hybrid":
				_mode_hint_lbl.text = "Hybride DD2 : fond illustré + caméra inclinée + personnages dressés."
			else:
				_mode_hint_lbl.text = "Diorama 2.5D : fond illustré, lieux cliquables, décors et tokens."
		else:
			_mode_hint_lbl.text = "Éditeur 2D — tuiles, marqueurs, lieux, notes, brouillard et undo."
	else:
		_mode_hint_lbl.text = "Cliquez sur « Modifier » pour changer le mode de cette carte."

func _set_render_mode(mode: String) -> void:
	if _map_data.is_empty() or not _edit_mode:
		return
	var current := MapData.get_render_mode(_map_data)
	if mode == current:
		return
	_pull_active_editor()
	_map_data["renderMode"] = mode
	_map_data = MapData.ensure_map_schema(_map_data)
	MapData.update_map(_map_data)
	_sync_editor_mode()
	_sync_render_mode_ui()
	_update_hint()
	_refresh_map_view(true)

func _pull_active_editor() -> void:
	if _map_data.is_empty():
		return
	if MapData.is_complex_map(_map_data) and _complex_editor:
		_map_data = _complex_editor.apply_to_map_data()
	elif _simple_editor:
		_map_data = _simple_editor.apply_to_map_data()

func _sync_editor_mode() -> void:
	if _map_data.is_empty():
		return
	var is_complex := MapData.is_complex_map(_map_data)
	if _simple_editor:
		_simple_editor.visible = not is_complex
		if not is_complex:
			_simple_editor.set_editable(_edit_mode)
			_simple_editor.load_map(_map_data)
	if _complex_editor:
		_complex_editor.visible = is_complex
		if is_complex:
			_complex_editor.set_editable(_edit_mode)
			_complex_editor.load_map(_map_data)
	if _hint_lbl:
		_hint_lbl.visible = is_complex and not _edit_mode

func _load_map() -> void:
	_map_data = {}
	if not MapData.preview_map_id.is_empty():
		_map_data = MapData.get_by_id(MapData.preview_map_id).duplicate(true)
	if _map_data.is_empty() and not MapData.maps.is_empty():
		_map_data = MapData.maps[0].duplicate(true)
	if _map_data.is_empty():
		title_lbl.text = "🗺️ Aucune carte"
		return

	_sync_title_from_map()
	_apply_pending_link_target()
	_sync_render_mode_ui()
	_update_hint()
	_sync_editor_mode()
	_refresh_map_view(true)

func _sync_title_from_map() -> void:
	var title: String = _map_data.get("title", "Carte")
	if _title_input:
		_title_input.text = title
	title_lbl.text = "🗺️ %s" % title

func _apply_pending_link_target() -> void:
	if MapData.pending_link_target_id.is_empty():
		return
	if not MapData.is_world_map(_map_data):
		return
	var target_id := MapData.pending_link_target_id
	MapData.pending_link_target_id = ""
	if _simple_editor and _simple_editor.has_method("_set_tool"):
		_simple_editor._link_target = target_id
		var target_map := MapData.get_by_id(target_id)
		if not target_map.is_empty():
			_simple_editor._link_label = str(target_map.get("title", ""))
		_simple_editor.call("_set_tool", "link")

func _on_place_on_world(world_id: String, local_id: String) -> void:
	if world_id.is_empty():
		return
	_save_map()
	MapData.preview_map_id = world_id
	MapData.editor_mode = "edit"
	MapData.pending_link_target_id = local_id
	get_tree().change_scene_to_file("res://scenes/map_viewer.tscn")

func _refresh_map_view(_reset_view: bool = false) -> void:
	if MapData.is_complex_map(_map_data):
		if _complex_editor:
			_complex_editor.set_editable(_edit_mode)
			_complex_editor.load_map(_map_data)
		return
	if _simple_editor:
		_simple_editor.set_editable(_edit_mode)
		_simple_editor.load_map(_map_data)

func _update_hint() -> void:
	if not _hint_lbl:
		return
	if not _edit_mode:
		var mode := MapData.get_render_mode(_map_data) if not _map_data.is_empty() else MapModeScript.SIMPLE
		if mode == MapModeScript.COMPLEX:
			_hint_lbl.text = "Aperçu battlemap 3D — tokens, effets et brouillard configurés dans l'éditeur."
		else:
			_hint_lbl.text = "Aperçu 2D — molette pour zoomer · glisser pour déplacer."
		return
	_hint_lbl.text = ""

func _save_map() -> void:
	var title := _title_input.text.strip_edges() if _title_input else str(_map_data.get("title", ""))
	if title.is_empty():
		title = "Carte sans titre"
	_pull_active_editor()
	_map_data["title"] = title
	if MapData.is_complex_map(_map_data) and _complex_editor:
		_map_data = _complex_editor.apply_to_map_data()
		_map_data["title"] = title
		MapData.update_map(_map_data)
		if _complex_editor.has_method("save_now"):
			_complex_editor.save_now()
	elif _simple_editor:
		_simple_editor.apply_title(title)
		_map_data = _simple_editor.apply_to_map_data()
		MapData.update_map(_map_data)
		_simple_editor.mark_saved()
	else:
		MapData.update_map(_map_data)
	title_lbl.text = "🗺️ %s" % _map_data.get("title", "Carte")

func _rebuild_for_mode() -> void:
	_sync_chrome()
	_load_map()

func _on_editor_open_map(map_id: String) -> void:
	if map_id.is_empty() or map_id == _map_data.get("id", ""):
		return
	var target := MapData.get_by_id(map_id)
	if target.is_empty():
		return
	MapData.preview_map_id = map_id
	_map_data = target.duplicate(true)
	_sync_title_from_map()
	_sync_render_mode_ui()
	_sync_editor_mode()
	_update_hint()
	_refresh_map_view(true)
