extends SceneTree

## Captures de la vitrine « Cité au fil de l'eau » (task-11).
##
## Quatre vues de la carte de démonstration (cité générée en assets 3D + canal
## de ville + lac + ponts, preset qualité cinéma, socle de diorama) :
##   • `cite_eau_overview.png`  — vue d'ensemble de l'îlot, canal traversant,
##                                lac en bordure, socle ;
##   • `cite_eau_canal.png`     — caméra BASSE le long du canal : pont, quais,
##                                eau lisible, façades ;
##   • `cite_eau_place.png`     — la place au bord de l'eau, reflets ;
##   • `cite_eau_editor.png`    — l'éditeur ouvert sur la carte (mode édition).
##
## Fenêtre cachée, GPU réel. PASS = `cite_eau_shot_test:PASS`.

const BootScript := preload("res://scripts/debug/cite_eau_boot.gd")
const OUT_DIR := "user://cite_eau_shots"
const COPY_DIR := "docs/screenshots"

var Engine3DScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")
	var map: Dictionary = BootScript.build_map(md, BootScript.DEFAULT_SEED)
	_assert("map_built", not map.is_empty())
	if map.is_empty():
		print("cite_eau_shot_test:FAIL")
		quit(1)
		return

	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true,
		{"mode": "select"}, {}, "")
	for _i in range(18):
		await process_frame

	# --- Vérifications de scène avant capture ------------------------------
	var water = engine._water_layer
	var ground = engine._ground
	_assert("water_layer", water != null and water.is_active())
	_assert("water_two_bodies", water != null and water.get_body_count() >= 2,
		"n=%d" % (water.get_body_count() if water != null else -1))
	_assert("water_no_falls", water != null and water.get_fall_count() == 0,
		"chutes=%d" % (water.get_fall_count() if water != null else -1))
	_assert("water_shore_texture", water != null
		and water.get_shore_texture() != null)
	_assert("city_meshes_rendered", engine._meshes_layer != null
		and engine._meshes_layer.get_child_count() >= 20,
		"n=%d" % (engine._meshes_layer.get_child_count()
			if engine._meshes_layer != null else -1))
	_assert("slab_active", ground != null and ground.is_slab_active())
	_assert("cinema_preset", str(map.get("qualityPreset", "")) == "cinema")

	# --- 1) Vue d'ensemble : l'îlot, le canal, le lac, le socle ------------
	engine._fit_to_view()
	for _i in range(12):
		await process_frame
	var overview: Image = await _shot(engine, "cite_eau_overview")
	if overview != null:
		_assert("overview_not_blank", not _is_blank(overview))

	# --- 2) Caméra BASSE le long du canal : pont, quais, façades -----------
	# Vue 3/4 depuis le quai ouest, un peu au-dessus des toits : le canal file
	# vers le nord avec ses deux ponts, les façades l'encadrent, l'eau reste
	# lisible (profondeur, mousse de rive) et les ombres du preset cinéma
	# asseyent les bâtiments.
	_look(engine, Vector3(8.6, 5.2, 21.5), Vector3(15.2, -0.3, 14.0))
	var canal: Image = await _shot(engine, "cite_eau_canal")
	if canal != null:
		_assert("canal_not_blank", not _is_blank(canal))

	# --- 3) La place au bord de l'eau : reflets ---------------------------
	# Vue depuis la place vers le canal : premier plan pavé, eau au milieu du
	# cadre, façades qui s'y reflètent (réflexions écran + Fresnel).
	_look(engine, Vector3(23.5, 3.4, 21.5), Vector3(14.0, -0.2, 15.0))
	var place: Image = await _shot(engine, "cite_eau_place")
	if place != null:
		_assert("place_not_blank", not _is_blank(place))

	# --- 4) Éditeur ouvert sur la carte -----------------------------------
	engine.queue_free()
	await process_frame
	await process_frame
	var scene: PackedScene = load("res://scenes/map_editor/map_editor.tscn")
	var editor: Control = scene.instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(map)
	editor.set_editable(true)
	for _i in range(12):
		await process_frame
	if editor._engine != null:
		editor._engine._fit_to_view()
		for _i in range(12):
			await process_frame
	var edit_img: Image = await _shot_root("cite_eau_editor")
	if edit_img != null:
		_assert("editor_not_blank", not _is_blank(edit_img))
	editor.queue_free()
	await process_frame

	if _failed:
		print("cite_eau_shot_test:FAIL")
		quit(1)
		return
	print("cite_eau_shot_test:PASS")
	quit(0)

# ===========================================================================
# Caméra & captures
# ===========================================================================

## Pose la caméra et la braque sur `target` (vue basse / rapprochée).
func _look(engine: Control, pos: Vector3, target: Vector3) -> void:
	engine._camera.position = pos
	engine._camera.look_at(target, Vector3.UP)
	for _i in range(6):
		await process_frame

func _shot(engine: Control, name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = engine.get_viewport().get_texture().get_image()
	return _save(img, name)

func _shot_root(name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	return _save(img, name)

func _save(img: Image, name: String) -> Image:
	if img == null:
		_assert("capture_%s" % name, false)
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var abs_from := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	img.save_png(abs_from)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var to := copy_dir.path_join("%s.png" % name)
	DirAccess.copy_absolute(abs_from, to)
	print("  capture: %s" % to)
	return img

func _is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 2 or h <= 2:
		return true
	var first := img.get_pixel(w / 2, h / 2)
	for pt in [Vector2i(w / 4, h / 4), Vector2i(3 * w / 4, h / 2),
			Vector2i(w / 2, 3 * h / 4)]:
		if img.get_pixelv(pt) != first:
			return false
	return true

func _assert(assert_name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [assert_name, detail])
