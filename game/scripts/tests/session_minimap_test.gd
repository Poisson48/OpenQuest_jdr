extends SceneTree

## Mini-carte de session : rendu des sols/eau/tokens et clic → recentrage.

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var mini = (load("res://scripts/session/panels/session_minimap.gd") as GDScript).new()
	get_root().add_child(mini)
	mini.size = Vector2(220, 180)
	var materials: Array = []
	materials.resize(10 * 8)
	materials.fill(0)
	materials[2 * 10 + 3] = 2
	var heights: Array = []
	heights.resize(10 * 8)
	heights.fill(0.0)
	for i in range(40):
		heights[i] = -0.4
	var map := {
		"id": "map-mini-test", "title": "Mini test", "width": 10, "height": 8,
		"terrainMaterials": materials, "terrainHeights": heights, "waterLevel": -0.2,
		"meshes": [{"x": 4.0, "y": 4.0}],
	}
	mini.configure(map, [
		{"id": "tok-a", "x": 2.0, "y": 2.0, "color": "#e6b04a", "kind": "member"},
		{"id": "tok-b", "x": 7.0, "y": 5.0, "kind": "monster"},
	], "tok-a")
	mini._draw()
	_assert("mini_map_rect", mini._map_rect.size.x > 0.0 and mini._map_rect.size.y > 0.0)
	var jumped: Array = []
	mini.jump_requested.connect(func(pos: Vector2): jumped.append(pos))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = mini._map_rect.get_center()
	mini._gui_input(ev)
	_assert("mini_jump", jumped.size() == 1)
	if jumped.size() == 1:
		_assert("mini_jump_inside", (jumped[0] as Vector2).x >= 0.0 and (jumped[0] as Vector2).x <= 10.0)
	# Clic hors de la carte : ignoré.
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	ev2.position = Vector2(1, 1)
	mini._gui_input(ev2)
	_assert("mini_jump_outside", jumped.size() == 1)
	mini.queue_free()
	await process_frame
	if _failed:
		print("session_minimap_test:FAIL")
		quit(1)
		return
	print("session_minimap_test:PASS")
	quit(0)

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
