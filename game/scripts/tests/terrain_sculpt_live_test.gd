extends SceneTree

## Sculpture et relief **en direct** : les modifications doivent apparaître
## PENDANT le glisser de souris, pas seulement à la relâche. Le test pilote un
## vrai trait de l'outil Relief (press → moved… → released) et vérifie l'état
## du document ET du rendu AVANT la relâche.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test live", "general", "local", 12, 10)
	var editor: Control = load("res://scenes/map_editor/map_editor.tscn").instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(base)
	await process_frame
	var mods := {"shift": false, "ctrl": false, "alt": false}

	# --- 1) Sculpture 3D (mode Creuser) : tampons + rendu avant la relâche.
	# Les gestes passent par la VRAIE chaîne d'input du moteur
	# (`_editor_gui_input` → signaux → FSM), comme la souris dans l'éditeur.
	editor._set_tool(ToolsScript.TERRAIN_HEIGHT)
	editor._relief_mode = "carve"
	editor._carve_radius = 1.2
	editor._carve_offset = 0.4
	var plain_indices := _ground_indices(editor)
	var s0: Vector2 = editor._engine.grid_to_screen(3.0, 5.0)
	_feed_press(editor, s0)
	await process_frame
	var after_press: int = _sculpt_size(editor)
	_assert("carve_stamp_on_press", after_press > 0, "n=%d" % after_press)
	for i in range(1, 6):
		var g := Vector2(3.0 + float(i) * 1.2, 5.0)
		_feed_move(editor, editor._engine.grid_to_screen(g.x, g.y))
		await process_frame
	var after_move: int = _sculpt_size(editor)
	_assert("carve_stamps_on_move", after_move > after_press + 2,
		"press=%d move=%d" % [after_press, after_move])
	_assert("carve_engine_synced",
		str(editor._engine._terrain_sculpt) == str(editor.doc.map_data.get("terrainSculpt", {})),
		"engine=%d doc=%d" % [str(editor._engine._terrain_sculpt).length(), after_move])
	_assert("carve_cluster_live", editor._engine._ground.get_carve_cluster_count() >= 1)
	_assert("carve_cut_live", _ground_indices(editor) < plain_indices,
		"indices=%d plain=%d" % [_ground_indices(editor), plain_indices])
	_feed_release(editor, editor._engine.grid_to_screen(8.4, 5.0))
	await process_frame
	_assert("carve_release_no_extra", _sculpt_size(editor) == after_move)
	_assert("carve_release_polished", editor._engine._ground.get_carve_cluster_count() >= 1)

	# --- 2) Relief classique (Monter) : le terrain bouge avant la relâche.
	editor._relief_mode = "raise"
	var h_before: float = editor.doc.terrain_height(3, 2)
	_feed_press(editor, editor._engine.grid_to_screen(3.0, 2.0))
	_feed_move(editor, editor._engine.grid_to_screen(3.4, 2.2))
	await process_frame
	var h_mid: float = editor.doc.terrain_height(3, 2)
	_assert("relief_live_on_move", h_mid > h_before + 0.01,
		"avant=%.3f pendant=%.3f" % [h_before, h_mid])
	_assert("relief_engine_live",
		editor._engine.terrain_height_at(3.0, 2.0) > h_before + 0.01)
	_feed_release(editor, editor._engine.grid_to_screen(3.4, 2.2))
	await process_frame

	# --- 3) Symétrie X (façon Blender) : un trait crée deux bosses miroirs
	#     et un SEUL undo les efface toutes les deux.
	editor._relief_mode = "fill"
	editor._sym_x = true
	editor._sculpt_probe = true
	var w: float = float(editor.doc.terrain_size().x)
	var field = editor._engine._ground.get_carve_field()
	var h0: float = field.top_surface_at(5.0, 5.0)
	var h0m: float = field.top_surface_at(w - 5.0, 5.0)
	_feed_press(editor, editor._engine.grid_to_screen(5.0, 5.0))
	_feed_move(editor, editor._engine.grid_to_screen(5.5, 5.0))
	await process_frame
	_feed_release(editor, editor._engine.grid_to_screen(5.5, 5.0))
	await process_frame
	field = editor._engine._ground.get_carve_field()
	_assert("sym_primary_raised", field.top_surface_at(5.0, 5.0) > h0 + 0.1,
		"avant=%.3f apres=%.3f" % [h0, field.top_surface_at(5.0, 5.0)])
	_assert("sym_mirror_raised", field.top_surface_at(w - 5.0, 5.0) > h0m + 0.1,
		"avant=%.3f apres=%.3f" % [h0m, field.top_surface_at(w - 5.0, 5.0)])
	editor.doc.undo()
	await process_frame
	field = editor._engine._ground.get_carve_field()
	_assert("sym_one_undo", absf(field.top_surface_at(5.0, 5.0) - h0) < 0.02,
		"avant=%.3f apres undo=%.3f" % [h0, field.top_surface_at(5.0, 5.0)])
	editor._sym_x = false

	editor.queue_free()
	await _wait_frames(3)
	if _failed:
		print("terrain_sculpt_live_test:FAIL")
		quit(1)
		return
	print("terrain_sculpt_live_test:PASS")
	quit(0)

func _wait_frames(n: int) -> void:
	for _i in range(n):
		await process_frame

## Gestes souris via la chaîne d'input réelle du moteur (comme dans l'éditeur).
func _feed_press(editor: Control, screen: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen
	editor._engine._editor_gui_input(ev)

func _feed_move(editor: Control, screen: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = screen
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	editor._engine._editor_gui_input(ev)

func _feed_release(editor: Control, screen: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = screen
	editor._engine._editor_gui_input(ev)

## Nombre d'indices du maillage heightfield (découpe des quads creusés).
func _ground_indices(editor: Control) -> int:
	var mesh = editor._engine._ground._mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var idx = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	return idx.size() if idx != null else -1

## « Volume » sculpté : longueur de la sérialisation (croît à chaque tampon).
func _sculpt_size(editor: Control) -> int:
	return str(editor.doc.map_data.get("terrainSculpt", {})).length()

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
