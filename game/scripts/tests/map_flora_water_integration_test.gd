extends SceneTree

## Test d'intégration : végétation + eau + décor d'eau + ambiance, ensemble,
## pour prouver que le système complet fonctionne sur une seule carte.

const W := 12
const H := 12

var _failed := false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	if EngineScript == null:
		print("map_flora_water_integration_test:FAIL at engine_load")
		quit(1)
		return
	var engine: Control = EngineScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(_make_map(), [], [], [], [], [], false, true)
	await _wait_frames(8)

	_assert("water_active", engine.is_water_active())
	_assert("vegetation_active", engine.is_vegetation_active())
	_assert("ambient_active", engine.is_ambient_fx_active())
	var veg: Dictionary = engine.get_vegetation_counts()
	_assert("veg_tufts", int(veg.get("tufts", 0)) > 0)
	_assert("veg_leaves", int(veg.get("leaves", 0)) > 0)
	var water_layer = engine._water_layer
	_assert("water_duckweed", water_layer.get_duckweed_count() > 0,
		"duckweed=%d" % water_layer.get_duckweed_count())
	_assert("water_lily", water_layer.get_lily_count() > 0,
		"lily=%d" % water_layer.get_lily_count())

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(2)
	if _failed:
		print("map_flora_water_integration_test:FAIL")
		quit(1)
		return
	print("map_flora_water_integration_test:PASS")
	quit(0)

## Carte 12×12 : herbe partout, étang peu profond au centre (hauts-fonds pour
## les nénuphars), eau, décor d'eau, végétation et feuilles qui tombent.
func _make_map() -> Dictionary:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(0.0)
	var center := Vector2(6.0, 6.0)
	for cy in range(H):
		for cx in range(W):
			var d := Vector2(cx, cy).distance_to(center)
			if d < 3.0:
				heights[cy * W + cx] = -0.3 * (1.0 - d / 3.0)
	var mats: Array = []
	mats.resize(W * H)
	mats.fill(0)
	return {
		"id": "flora-water-integration",
		"name": "Flora + eau",
		"width": W, "height": H,
		"grid": {"size": 70},
		"renderStyle": "2.5d",
		"groundMode": "terrain3d",
		"fogEnabled": false,
		"layers": [],
		"terrainHeights": heights,
		"terrainMaterials": mats,
		"waterLevel": -0.1,
		"waterDecorSeed": 7,
		"waterDecorDensity": 1.0,
		"vegetationEnabled": true,
		"vegetationDensity": 1.0,
		"ambientFx": "leaves",
	}

func _wait_frames(n: int = 2) -> void:
	for _i in range(n):
		await process_frame

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		return
	var suffix := "" if detail.is_empty() else " (%s)" % detail
	print("map_flora_water_integration_test:FAIL at ", name, suffix)
	_failed = true
