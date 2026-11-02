extends SceneTree

## Test : un mur procédural bloque le déplacement en session.

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test blocage mur proc", "general", "local", 16, 12)
	var map_id := str(map.get("id", ""))
	map["meshes"] = [{
		"id": "proc_wall_1", "kind": "mesh",
		"x": 6.0, "y": 6.0, "w": 6.0, "h": 0.7,
		"asset": "procedural://wall",
		"points": [[-3.0, 0.0], [0.0, 0.0], [3.0, 0.0]],
		"height": 2.2, "thickness": 0.7, "bevel": 0.12,
		"elevation": 0.0, "label": "Mur procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}]
	md.update_map(map)
	var workspace: Control = (load("res://scripts/session/panels/map_workspace.gd") as GDScript).new()
	get_root().add_child(workspace)
	await process_frame
	_assert("proc_wall_blocks", workspace._cell_blocked_by_building(map_id, 6.0, 6.0))
	_assert("proc_wall_blocks_side", workspace._cell_blocked_by_building(map_id, 5.0, 6.1))
	_assert("proc_wall_free", not workspace._cell_blocked_by_building(map_id, 6.0, 9.0))
	if _failed:
		print("session_procedural_wall_block_test:FAIL")
		quit(1)
		return
	print("session_procedural_wall_block_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
