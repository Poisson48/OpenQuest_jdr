extends SceneTree

## Style de rendu diorama / VTT : résolution, parallaxe, teinte, priorité.

const StyleScript := preload("res://scripts/maps/map_render_style.gd")
const Props3DScript := preload("res://scripts/maps/map_layers/map_props_3d.gd")
const LibraryScript := preload("res://scripts/maps/map_asset_library.gd")

var _failed: bool = false
var _sources: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_test_resolution()
	_test_parallax_and_tint()
	_test_render_priority()
	_test_props_by_style()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("map_render_style_test:PASS")
	quit(0)

func _make_png(name: String, width: int, height: int) -> String:
	var path := "user://test-style-%s.png" % name
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.45, 0.35, 1.0))
	img.save_png(path)
	_sources.append(path)
	return path

func _cleanup() -> void:
	for entry_variant in LibraryScript.list_assets():
		LibraryScript.remove_asset(str((entry_variant as Dictionary).get("path", "")))
	for path in _sources:
		DirAccess.remove_absolute(path)

func _test_resolution() -> void:
	_assert("default_diorama", StyleScript.style_of({}) == StyleScript.DIORAMA)
	_assert("missing_is_diorama", StyleScript.is_diorama({}))
	_assert("explicit_vtt", StyleScript.style_of({"renderStyle": "vtt"}) == StyleScript.VTT)
	_assert("unknown_falls_back", StyleScript.style_of({"renderStyle": "xyz"}) == StyleScript.DIORAMA)
	_assert("label_diorama", not StyleScript.style_label(StyleScript.DIORAMA).is_empty())
	_assert("label_vtt", not StyleScript.style_label(StyleScript.VTT).is_empty())

	var dio: Dictionary = StyleScript.config({})
	_assert("cfg_parallax", float(dio.get("parallax", 0.0)) > 0.0)
	_assert("cfg_no_shadows", not bool(dio.get("shadows", true)))
	_assert("cfg_perspective", bool(dio.get("perspective", false)))
	_assert("cfg_no_walls", not bool(dio.get("volumetricWalls", true)))

	var vtt: Dictionary = StyleScript.config({"renderStyle": "vtt"})
	_assert("vtt_shadows", bool(vtt.get("shadows", false)))
	_assert("vtt_walls", bool(vtt.get("volumetricWalls", false)))
	_assert("vtt_no_parallax", is_equal_approx(float(vtt.get("parallax", 1.0)), 0.0))

	var overridden: Dictionary = StyleScript.config({
		"renderStyle": "diorama",
		"renderStyleOverrides": {"parallax": 0.8},
	})
	_assert("override_parallax", is_equal_approx(float(overridden.get("parallax", 0.0)), 0.8))

	var illustrated: Dictionary = StyleScript.config({
		"renderStyle": "diorama",
		"backgroundImage": "user://map_assets/fake.png",
	})
	_assert("illustrated_no_persp", not bool(illustrated.get("perspective", true)))
	_assert("illustrated_tilt_flat", is_equal_approx(float(illustrated.get("tilt", 0.0)), -90.0))
	_assert("illustrated_no_parallax", is_equal_approx(float(illustrated.get("parallax", 1.0)), 0.0))

func _test_parallax_and_tint() -> void:
	var cfg: Dictionary = StyleScript.CONFIGS[StyleScript.DIORAMA]
	var back := StyleScript.parallax_offset(1, cfg)
	var mid := StyleScript.parallax_offset(3, cfg)
	var front := StyleScript.parallax_offset(5, cfg)
	_assert("parallax_order", back < mid and mid < front)
	_assert("parallax_zero_vtt", is_equal_approx(StyleScript.parallax_offset(2, StyleScript.CONFIGS[StyleScript.VTT]), 0.0))

	_assert("depth_near", is_equal_approx(StyleScript.depth_ratio(12.0, 12.0), 1.0))
	_assert("depth_far", is_equal_approx(StyleScript.depth_ratio(0.0, 12.0), 0.0))

	var base := Color(1, 0.8, 0.5, 0.9)
	var atmo := Color(0.1, 0.1, 0.14)
	var far_tint := StyleScript.depth_tint(base, 0.0, atmo, cfg)
	var near_tint := StyleScript.depth_tint(base, 1.0, atmo, cfg)
	_assert("tint_keeps_alpha", is_equal_approx(far_tint.a, base.a))
	_assert("tint_fades_far", far_tint.r < near_tint.r)
	_assert("tint_near_intact", is_equal_approx(near_tint.r, base.r))
	_assert("tint_off_vtt", StyleScript.depth_tint(base, 0.0, atmo, StyleScript.CONFIGS[StyleScript.VTT]) == base)

func _test_render_priority() -> void:
	var far_back := StyleScript.render_priority(1, 0.0)
	var near_front := StyleScript.render_priority(5, 1.0)
	_assert("priority_near_front_higher", near_front > far_back)
	_assert("priority_bounded", StyleScript.render_priority(99, 2.0) <= 127)
	_assert("priority_bounded_low", StyleScript.render_priority(-3, -1.0) >= -128)

func _test_props_by_style() -> void:
	var source := _make_png("maison", 64, 96)
	var entry: Dictionary = LibraryScript.import_asset(source, "buildings", "Maison")
	var asset := str(entry.get("path", ""))
	var layer: Node3D = Props3DScript.new()
	get_root().add_child(layer)

	var props := [
		{"id": "a", "x": 2.0, "y": 2.0, "w": 2.0, "h": 3.0, "asset": asset, "standing": true, "layer": 1},
		{"id": "b", "x": 2.0, "y": 8.0, "w": 2.0, "h": 3.0, "asset": asset, "standing": true, "layer": 1},
	]
	var map_dio := {"height": 12, "renderStyle": "diorama", "atmosphere": {"tint": "#141018"}}
	layer.configure(props, 1.0, map_dio)
	_assert("dio_props_built", layer.get_child_count() == 2)

	var mats: Array = []
	for child in layer.get_children():
		var mesh := (child as Node3D).get_child(0) as MeshInstance3D
		mats.append(mesh.material_override as StandardMaterial3D)
	_assert("dio_unshaded", (mats[0] as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	_assert("dio_depth_prepass", (mats[0] as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS)
	# Le décor plus « devant » (y plus grand) a une priorité de rendu plus haute.
	_assert("dio_priority_by_depth", (mats[1] as StandardMaterial3D).render_priority > (mats[0] as StandardMaterial3D).render_priority)

	var map_vtt := {"height": 12, "renderStyle": "vtt"}
	layer.configure([
		{"id": "c", "x": 1.0, "y": 1.0, "w": 2.0, "h": 2.0, "asset": asset, "standing": true, "layer": 2},
	], 1.0, map_vtt)
	var vtt_mesh := (layer.get_child(0) as Node3D).get_child(0) as MeshInstance3D
	var vtt_mat := vtt_mesh.material_override as StandardMaterial3D
	_assert("vtt_lit", vtt_mat.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL)

	layer.queue_free()

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true
