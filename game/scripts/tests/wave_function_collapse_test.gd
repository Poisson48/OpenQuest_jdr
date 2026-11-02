extends SceneTree

## Test WFC — modèle de tuiles simple avec contraintes symétriques.

var WFC: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	WFC = load("res://scripts/maps/construction/wave_function_collapse.gd")
	# 0 herbe, 1 terre, 2 pierre.
	var names := ["herbe", "terre", "pierre"]
	var weights := [4.0, 2.0, 1.0]
	var adjacency := [
		[[0, 1], [0, 1, 2], [1]],        # est
		[[0, 1], [0, 1, 2], [1]],        # ouest
		[[0, 1], [0, 1, 2], [1, 2]],     # sud
		[[0, 1], [0, 1, 2], [1, 2]],     # nord
	]
	var wfc = WFC.new()
	wfc.configure(weights, adjacency, 12345)
	var grid: Array = wfc.generate(16, 12, {0: 0, 191: 2})
	_assert("wfc_size", grid.size() == 16 * 12, "size=%d" % grid.size())
	_assert("wfc_fixed_corner", int(grid[0]) == 0)
	_assert("wfc_fixed_far", int(grid[191]) == 2)
	var invalid := 0
	for y in range(12):
		for x in range(16):
			var t := int(grid[y * 16 + x])
			for d in range(4):
				var dir: Vector2i = WFC.DIRECTIONS[d]
				var nx: int = x + dir.x
				var ny: int = y + dir.y
				if nx < 0 or ny < 0 or nx >= 16 or ny >= 12:
					continue
				var nt := int(grid[ny * 16 + nx])
				if not (nt in adjacency[d][t]):
					invalid += 1
	_assert("wfc_constraints", invalid == 0, "invalid=%d" % invalid)
	_assert("wfc_tiles_used", grid.size() > 0 and not (grid as Array).has(-1))
	for t in grid:
		_assert("wfc_tile_range", int(t) >= 0 and int(t) < names.size(), "tile=%s" % t)
		break
	if _failed:
		print("wave_function_collapse_test:FAIL")
		quit(1)
		return
	print("wave_function_collapse_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
