extends SceneTree

## Zoom **vers le curseur** : le point du monde sous la souris doit y rester
## après un zoom (pas un zoom centré), y compris sur relief sculpté — l'ancien
## algorithme dérivait quand un rayon rasait une montagne.

var Engine3DScript: GDScript
const FieldScript := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test zoom souris", "general", "local", 20, 14)
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(0.3)
	map["terrainHeights"] = heights
	# Une montagne sculptée en travers de la vue : les rayons qui rasaient son
	# sommet faisaient dériver l'ancienne correction de zoom.
	var sculpt = FieldScript.new(heights, 20, 14, [], {})
	for pos in [Vector2(9.0, 7.0), Vector2(10.5, 7.5), Vector2(9.8, 6.2)]:
		sculpt.sculpt_stamp(Vector3(pos.x, sculpt.top_surface_at(pos.x, pos.y), pos.y), 2.2, 1.2)
	map["terrainSculpt"] = sculpt.get_sculpt()
	var engine: Control = Engine3DScript.new()
	engine.size = Vector2(960, 540)
	get_root().add_child(engine)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(8):
		await process_frame
	engine.request_fit_to_view()
	for _i in range(8):
		await process_frame

	var anchors: Array = [
		Vector2(200.0, 180.0),
		Vector2(760.0, 420.0),
		Vector2(480.0, 140.0),
		Vector2(520.0, 300.0),  # sur la montagne elle-même
	]
	for anchor in anchors:
		var anchor_vp: Vector2 = engine._control_to_viewport(anchor)
		var before: Vector3 = engine._raycast_ground(anchor_vp)
		_assert("zoom_anchor_hits", before != Vector3.INF, "ancre=%s" % str(anchor))
		if before == Vector3.INF:
			continue
		engine._apply_zoom(1.6, anchor)
		await process_frame
		# Invariant direct : le point figé repasse exactement sous la souris.
		var seen: Vector2 = engine._camera.unproject_position(before)
		_assert("zoom_to_cursor_px", absf(seen.x - anchor_vp.x) < 1.0 \
			and absf(seen.y - anchor_vp.y) < 1.0,
			"ancre=%s dérive=(%.1f, %.1f) px" % [str(anchor),
				seen.x - anchor_vp.x, seen.y - anchor_vp.y])
		_assert("zoom_changed", engine.zoom > 1.0, "zoom=%.2f" % engine.zoom)
		engine._apply_zoom(1.0 / 1.6, anchor)
		await process_frame

	if _failed:
		print("zoom_to_cursor_test:FAIL")
		quit(1)
		return
	print("zoom_to_cursor_test:PASS")
	quit(0)

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
