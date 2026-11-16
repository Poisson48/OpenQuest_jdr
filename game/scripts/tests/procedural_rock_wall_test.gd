extends SceneTree

## Contrat du planificateur de rochers empilables (API 2D en cases) :
## déterminisme, rôles par assise, élévations croissantes, assets livrés réels.

const RockWall := preload("res://scripts/maps/construction/procedural_rock_wall.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var first: Array = RockWall.build_run_cells(Vector2(3.0, 4.0), Vector2(1.0, 0.0), 5.0, 3, 42)
	var second: Array = RockWall.build_run_cells(Vector2(3.0, 4.0), Vector2(1.0, 0.0), 5.0, 3, 42)
	_assert("placements_created", first.size() >= 12, "count=%d" % first.size())
	_assert("deterministic_count", first.size() == second.size())

	var rows_seen: Dictionary = {}
	var assets: Dictionary = {}
	for i in range(first.size()):
		var a: Dictionary = first[i]
		var b: Dictionary = second[i]
		_assert("deterministic_%d" % i, str(a["asset"]) == str(b["asset"])
			and is_equal_approx(float(a["x"]), float(b["x"]))
			and is_equal_approx(float(a["y"]), float(b["y"]))
			and is_equal_approx(float(a["elevation"]), float(b["elevation"]))
			and is_equal_approx(float(a["scale"]), float(b["scale"])))
		var row := int(a["row"])
		rows_seen[row] = true
		var asset := str(a["asset"])
		assets[asset] = true
		_assert("asset_exists_%d" % i, ResourceLoader.exists(asset), asset)
		_assert("elevation_matches_row_%d" % i,
			is_equal_approx(float(a["elevation"]), float(row) * RockWall.ROW_STEP),
			"row=%d elev=%.3f" % [row, float(a["elevation"])])
		_assert("scale_bounded_%d" % i, float(a["scale"]) >= 0.88 and float(a["scale"]) <= 1.08)
		_assert("rotation_bounded_%d" % i, absf(float(a["rotation"])) <= 190.0)
	_assert("three_rows", rows_seen.size() == 3, "rows=%s" % str(rows_seen.keys()))
	_assert("kit_roles_used", assets.size() >= 3, "assets=%d" % assets.size())

	# Le socle n'apparaît que sur la première assise, la couronne sur la dernière.
	for item_variant in first:
		var item: Dictionary = item_variant
		var role := str(item["role"])
		var row := int(item["row"])
		if role == RockWall.ROLE_FOUNDATION:
			_assert("foundation_bottom", row == 0, "row=%d" % row)
		if role == RockWall.ROLE_CAP:
			_assert("cap_top", row == 2, "row=%d" % row)
		if row == 0:
			_assert("bottom_is_foundation", role == RockWall.ROLE_FOUNDATION, role)

	_assert("empty_for_short_run",
		RockWall.build_run_cells(Vector2.ZERO, Vector2.RIGHT, 0.1, 3, 1).is_empty())
	_assert("empty_for_zero_rows",
		RockWall.build_run_cells(Vector2.ZERO, Vector2.RIGHT, 4.0, 0, 1).is_empty())
	# Direction dégénérée : le mur reste horizontal plutôt que de planter.
	var degenerate := RockWall.build_run_cells(Vector2.ZERO, Vector2.ZERO, 3.0, 2, 7)
	_assert("degenerate_direction_ok", not degenerate.is_empty())

	if _failed:
		print("procedural_rock_wall_test:FAIL")
		quit(1)
		return
	print("procedural_rock_wall_test:PASS")
	quit(0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
