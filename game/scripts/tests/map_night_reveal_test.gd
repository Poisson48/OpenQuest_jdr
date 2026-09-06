extends SceneTree

## Révélation nuit/jour façon brouillard : résolution chemins, procédural, masque, schéma.
## MapData n'est pas un identifiant global au parse des --script : on le lit depuis root.

const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")

var DocScript: GDScript
var _failed: bool = false
var _sources: Array = []
var _md

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_md = get_root().get_node("MapData")
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd") as GDScript
	_test_schema_defaults()
	_test_resolve_night_path()
	_test_procedural_night()
	_test_light_reveal_cells()
	_test_document_light_reveal()
	await _test_ground_night_material()
	_cleanup()
	if _failed:
		quit(1)
		return
	print("map_night_reveal_test:PASS")
	quit(0)

func _cleanup() -> void:
	for path in _sources:
		DirAccess.remove_absolute(path)

func _make_png(name: String, color: Color = Color(0.7, 0.55, 0.35, 1.0)) -> String:
	var path := "user://test-night-%s.png" % name
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	img.fill(color)
	img.save_png(path)
	_sources.append(path)
	return path

func _test_schema_defaults() -> void:
	var m: Dictionary = _md.ensure_map_schema({})
	var light: Dictionary = _md.get_lighting_config(m)
	_assert("nightMode_default", light.get("nightMode", true) == false)
	_assert("nightAmbient_default", float(light.get("nightAmbient", 0.0)) > 0.0)
	_assert("bg_night_key", m.has("backgroundImageNight"))
	var pd: Dictionary = _md.ensure_play_defaults(m)
	_assert("lightRevealed_array", pd.get("lightRevealed") is Array)

func _test_resolve_night_path() -> void:
	var auto := str(_md.resolve_night_image_path({
		"backgroundImage": "res://assets/maps/valbois_village.png",
	}))
	_assert("auto_night_suffix", auto.ends_with("valbois_village_night.png"))
	var explicit := str(_md.resolve_night_image_path({
		"backgroundImage": "res://assets/maps/valbois_village.png",
		"backgroundImageNight": "res://assets/maps/custom_night.png",
	}))
	_assert("explicit_night", explicit == "res://assets/maps/custom_night.png")

func _test_procedural_night() -> void:
	var day_path := _make_png("day", Color(0.9, 0.8, 0.5, 1.0))
	var tex: Texture2D = _md.load_night_texture({"backgroundImage": day_path})
	_assert("procedural_tex", tex != null)
	var img := tex.get_image()
	_assert("procedural_size", img != null and img.get_width() == 64)
	var sample := img.get_pixel(32, 24)
	var lum := sample.r * 0.299 + sample.g * 0.587 + sample.b * 0.114
	_assert("procedural_darker", lum < 0.55)

func _test_light_reveal_cells() -> void:
	var cells: Array = _md.light_reveal_cells({"x": 5.0, "y": 5.0, "radius": 1.5}, 20, 20)
	_assert("cells_center", cells.has("5,5"))
	_assert("cells_count", cells.size() >= 5)
	_assert("cells_bounded", not cells.has("0,0"))

func _test_document_light_reveal() -> void:
	var doc = DocScript.new()
	var blank: Dictionary = _md.ensure_map_schema({
		"id": "test-night-doc",
		"title": "Night Test",
		"renderMode": _md.RENDER_MODE_COMPLEX,
		"width": 16,
		"height": 12,
		"tiles": [],
	})
	var tiles: Array = []
	tiles.resize(16 * 12)
	tiles.fill("floor")
	blank["tiles"] = tiles
	doc.load_map(blank)
	_assert("empty_lit", doc.light_revealed_cells().is_empty())
	var lid: String = doc.add_element({
		"x": 3.0, "y": 4.0, "radius": 2.0, "energy": 1.6, "label": "L",
	}, "light", "Lumière")
	doc.rebuild_light_reveal_from_lights()
	var lit: Array = doc.light_revealed_cells()
	_assert("stamped", lit.has("3,4"))
	# Déplacer la lumière : l'ancien halo disparaît, le nouveau suit.
	doc.set_live_position(lid, 10.0, 8.0)
	doc.commit_live_edit([lid], "Move light")
	doc.rebuild_light_reveal_from_lights()
	var lit2: Array = doc.light_revealed_cells()
	_assert("moved_has_new", lit2.has("10,8"))
	_assert("moved_drops_old", not lit2.has("3,4"))
	doc.remove_element(lid)
	_assert("after_del", doc.light_revealed_cells().is_empty())
	doc.clear_light_reveal()
	_assert("cleared", doc.light_revealed_cells().is_empty())

func _test_ground_night_material() -> void:
	var day_path := _make_png("ground-day", Color(0.85, 0.7, 0.4, 1.0))
	var night_path := _make_png("ground-night", Color(0.1, 0.12, 0.25, 1.0))
	var day_img := Image.new()
	day_img.load(day_path)
	var night_img := Image.new()
	night_img.load(night_path)
	var day_tex := ImageTexture.create_from_image(day_img)
	var night_tex := ImageTexture.create_from_image(night_img)

	var ground = GroundScript.new()
	get_root().add_child(ground)
	await process_frame
	ground.configure(
		day_tex, 8, 6, 1.0, true,
		night_tex, true,
		[{"x": 2.0, "y": 2.0, "radius": 2.5, "energy": 1.6}],
		["1,1", "2,2"],
		0.2
	)
	_assert("night_active", ground.is_night_active())
	var mi: MeshInstance3D = null
	for child in ground.get_children():
		if child is MeshInstance3D:
			mi = child
			break
	_assert("has_mesh", mi != null)
	if mi:
		_assert("shader_mat", mi.material_override is ShaderMaterial)
		if mi.material_override is ShaderMaterial:
			var sm := mi.material_override as ShaderMaterial
			_assert("has_day", sm.get_shader_parameter("day_tex") != null)
			_assert("has_night", sm.get_shader_parameter("night_tex") != null)
			_assert("has_mask", sm.get_shader_parameter("light_mask") != null)
	ground.queue_free()

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK ", name)
	else:
		_failed = true
		print("map_night_reveal_test:FAIL at ", name)
