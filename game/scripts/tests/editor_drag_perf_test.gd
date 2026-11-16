extends SceneTree

## Performance du drag live : déplacer/rotationner/redimensionner un objet ne
## doit PAS reconstruire les couches 3D (freeze ~1-2 s sur une carte HD).
## On mesure le coût par mouvement et on vérifie que le nœud reste le même
## (aucun rebuild) et que la transform est réellement appliquée.

const MAP_BUILDER := preload("res://scripts/debug/cite_eau_boot.gd")
const MAX_STEP_SECONDS := 0.12

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = MAP_BUILDER.build_map(md)
	_assert("city_map_built", not map.is_empty())
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	for _i in range(4):
		await process_frame
	var engine = editor._engine
	var edit_ops = editor._edit_ops
	_assert("engine_ready", engine != null and edit_ops != null)

	# Mesure de référence : coût du rebuild complet (l'ancien freeze).
	var t_sync := Time.get_ticks_usec()
	editor._sync_engine()
	var sync_ms := float(Time.get_ticks_usec() - t_sync) / 1000.0
	print("  [perf] rebuild complet (ancien freeze) : %.0f ms" % sync_ms)

	var mesh_elem: Dictionary = {}
	for elem in editor.doc.elements_sorted():
		if str(elem.get("kind", "")) == "mesh":
			mesh_elem = elem
			break
	_assert("mesh_element_found", not mesh_elem.is_empty())
	if mesh_elem.is_empty():
		_finish()
		return
	var mesh_id := str(mesh_elem.get("id", ""))
	var node := _mesh_node(engine, mesh_id)
	_assert("mesh_node_found", node != null)
	if node == null:
		_finish()
		return
	var instance_id := node.get_instance_id()
	var start_x: float = node.position.x

	# --- DRAG DE DÉPLACEMENT --------------------------------------------------
	editor._press_mode = "move"
	editor._live_incremental = true
	editor._drag_ids = [mesh_id]
	editor._drag_origins = {mesh_id: Vector2(float(mesh_elem.get("x", 0.0)),
		float(mesh_elem.get("y", 0.0)))}
	editor._press_start_grid = Vector2(float(mesh_elem.get("x", 0.0)),
		float(mesh_elem.get("y", 0.0)))
	var t0 := Time.get_ticks_usec()
	for i in range(10):
		var grid := Vector2(float(mesh_elem.get("x", 0.0)) + float(i + 1) * 0.25,
			float(mesh_elem.get("y", 0.0)) + float(i + 1) * 0.1)
		edit_ops._on_pointer_moved(grid, Vector2(640.0, 360.0), {})
	var move_avg := float(Time.get_ticks_usec() - t0) / 10.0 / 1000000.0
	print("  [perf] déplacement : %.1f ms / mouvement" % (move_avg * 1000.0))
	_assert("move_step_fast", move_avg < MAX_STEP_SECONDS,
		"%.1f ms par mouvement" % (move_avg * 1000.0))
	node = _mesh_node(engine, mesh_id)
	_assert("move_no_rebuild", node != null and node.get_instance_id() == instance_id)
	_assert("move_applied", node != null and absf(node.position.x - start_x) > 0.01,
		"x %.3f -> %.3f" % [start_x, node.position.x if node != null else -999.0])

	# --- POIGNÉE DE ROTATION --------------------------------------------------
	editor._press_mode = "rotate"
	editor._live_incremental = false
	editor._handle_state = {
		"id": mesh_id,
		"x": float(mesh_elem.get("x", 0.0)),
		"y": float(mesh_elem.get("y", 0.0)),
		"start_grid": Vector2(float(mesh_elem.get("x", 0.0)) + 1.0,
			float(mesh_elem.get("y", 0.0))),
		"rotation": float((mesh_elem.get("display", {}) as Dictionary).get("rotation", 0.0)),
	}
	var rot_before := node.rotation_degrees.y
	t0 = Time.get_ticks_usec()
	for i in range(10):
		var grid := Vector2(float(mesh_elem.get("x", 0.0)) + cos(float(i + 1) * 0.1) * 1.5,
			float(mesh_elem.get("y", 0.0)) + sin(float(i + 1) * 0.1) * 1.5)
		edit_ops._apply_handle_rotate(grid)
	var rotate_avg := float(Time.get_ticks_usec() - t0) / 10.0 / 1000000.0
	print("  [perf] rotation : %.1f ms / mouvement" % (rotate_avg * 1000.0))
	_assert("rotate_step_fast", rotate_avg < MAX_STEP_SECONDS,
		"%.1f ms par mouvement" % (rotate_avg * 1000.0))
	node = _mesh_node(engine, mesh_id)
	_assert("rotate_no_rebuild", node != null and node.get_instance_id() == instance_id)
	_assert("rotate_applied", node != null and absf(node.rotation_degrees.y - rot_before) > 1.0,
		"yaw %.2f -> %.2f" % [rot_before, node.rotation_degrees.y if node != null else -999.0])

	# --- POIGNÉE DE REDIMENSIONNEMENT ----------------------------------------
	editor._press_mode = "resize"
	editor._live_incremental = false
	editor._handle_state = {
		"id": mesh_id,
		"x": float(mesh_elem.get("x", 0.0)),
		"y": float(mesh_elem.get("y", 0.0)),
		"start_grid": Vector2(float(mesh_elem.get("x", 0.0)) + 1.0,
			float(mesh_elem.get("y", 0.0))),
		"w": float(mesh_elem.get("w", 1.0)),
		"h": float(mesh_elem.get("h", 1.0)),
		"mesh_dims": Vector3.ONE,
	}
	var scale_before: Vector3 = node.scale
	t0 = Time.get_ticks_usec()
	for i in range(10):
		var grid := Vector2(float(mesh_elem.get("x", 0.0)) + 1.0 + float(i + 1) * 0.1,
			float(mesh_elem.get("y", 0.0)))
		edit_ops._apply_handle_resize(grid)
	var resize_avg := float(Time.get_ticks_usec() - t0) / 10.0 / 1000000.0
	print("  [perf] redimensionnement : %.1f ms / mouvement" % (resize_avg * 1000.0))
	_assert("resize_step_fast", resize_avg < MAX_STEP_SECONDS,
		"%.1f ms par mouvement" % (resize_avg * 1000.0))
	node = _mesh_node(engine, mesh_id)
	_assert("resize_no_rebuild", node != null and node.get_instance_id() == instance_id)
	_assert("resize_applied", node != null and node.scale.distance_to(scale_before) > 0.01,
		"scale %s -> %s" % [str(scale_before), str(node.scale if node != null else Vector3.ZERO)])

	for _i in range(2):
		await process_frame
	editor.queue_free()
	await process_frame
	_finish()


func _mesh_node(engine, mesh_id: String) -> Node3D:
	var layer = engine._meshes_layer
	if layer == null:
		return null
	var nodes: Dictionary = layer._nodes
	if not nodes.has(mesh_id):
		return null
	return nodes[mesh_id] as Node3D


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)


func _finish() -> void:
	if _failed:
		print("editor_drag_perf_test:FAIL")
		quit(1)
		return
	print("editor_drag_perf_test:PASS")
	quit(0)
