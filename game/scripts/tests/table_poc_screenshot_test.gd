extends SceneTree

## Captures visuelles du POC « table de taverne » (places autour de la table).
## Lancer SANS --headless (le SubViewport 3D doit rendre) :
##   godot --path game --user-data-dir <profil> -s res://scripts/tests/table_poc_screenshot_test.gd
## Chargement à l'exécution : un `preload` compile avant les autoloads en `-s`.

const OUT_DIR := "user://table_poc_screenshots"

var _failed := false

## `docs/screenshots/table_poc` du dépôt — chemin normalisé (pas de « .. »,
## refusé par certains sandboxes de fichiers).
var _copy_dir: String = ""

func _copy_target() -> String:
	if _copy_dir.is_empty():
		var game_root := ProjectSettings.globalize_path("res://").rstrip("/")
		_copy_dir = game_root.get_base_dir().path_join("docs/screenshots/table_poc")
	return _copy_dir

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var BootScript: GDScript = load("res://scripts/debug/table_poc_boot.gd") as GDScript
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript
	var demo: Dictionary = BootScript.build_demo(md)
	if demo.is_empty():
		printerr("table_poc_screenshot_test:FAIL (pas de carte démo)")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_copy_target())

	DisplayServer.window_set_title("POC Table — captures")
	DisplayServer.window_set_size(Vector2i(1440, 810))
	get_root().size = Vector2i(1440, 810)

	var engine: Control = Engine3DScript.new()
	engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine.size = Vector2(1440, 810)
	get_root().add_child(engine)
	await process_frame
	engine.configure(
		demo["map"], demo["tokens"], demo["party"], [], [], [],
		false, true, {"mode": "select"}, {}, ""
	)
	engine.set_table_view(true)
	for _i in range(45):
		await process_frame
	engine.reset_zoom()
	for _i in range(15):
		await process_frame

	_assert("table_env", engine._table_env != null)
	_assert("cam_perspective", engine._camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	if _failed:
		quit(1)
		return

	# Mesures de cadrage avant capture : centre de la table au centre écran,
	# coins visibles. (Diagnostic rendu — pas seulement la logique headless.)
	var md_map: Dictionary = demo["map"]
	var mw := float(md_map.get("width", 22))
	var mh := float(md_map.get("height", 15))
	var mid := engine.size * 0.5
	var cpx: Vector2 = engine.grid_to_screen(mw * 0.5, mh * 0.5)
	print("  [cadrage] size=", engine.size, " center=", cpx, " rot=",
		engine._camera.rotation_degrees, " pos=", engine._camera.position,
		" dist=", engine._camera.position.distance_to(engine._table_target_point()))
	_assert("frame_center", absf(cpx.x - mid.x) < engine.size.x * 0.08 \
		and absf(cpx.y - mid.y) < engine.size.y * 0.08)
	var corners_ok := true
	var exp_min := Vector2(INF, INF)
	var exp_max := Vector2(-INF, -INF)
	for corner: Vector2 in [Vector2(0, 0), Vector2(mw, 0), Vector2(0, mh), Vector2(mw, mh)]:
		var px: Vector2 = engine.grid_to_screen(corner.x, corner.y)
		print("  [cadrage] corner ", corner, " -> ", px)
		exp_min = Vector2(minf(exp_min.x, px.x), minf(exp_min.y, px.y))
		exp_max = Vector2(maxf(exp_max.x, px.x), maxf(exp_max.y, px.y))
		if px.x < -1.0 or px.x > engine.size.x + 1.0 or px.y < -1.0 or px.y > engine.size.y + 1.0:
			corners_ok = false
	_assert("frame_corners", corners_ok)

	# Vérité terrain : boîte des pixels « carte lumineuse » dans le rendu de la
	# caméra (texture SubViewport — insensible au DPI de la fenêtre), comparée
	# à la boîte théorique.
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var img: Image = (engine._viewport.get_texture() as Texture2D).get_image()
	var k := float(img.get_width()) / maxf(engine.size.x, 1.0)
	var obs := _bright_bbox(img)
	var exp := Rect2(exp_min * k, (exp_max - exp_min) * k)
	print("  [pixels] attendu=", exp, " observe=", obs, " (k=", k, ")")
	_assert("bbox_overlap", exp.grow(60.0).encloses(obs) or obs.grow(60.0).encloses(exp) \
		or exp.intersects(obs))

	await _shot("01_place_sud", engine)
	engine.set_table_seat(1)
	await _wait(10)
	await _shot("02_place_est", engine)
	engine.set_table_seat(2)
	await _wait(10)
	await _shot("03_place_nord", engine)

	# Vue plus haute (depuis la place sud).
	engine.set_table_seat(0)
	engine._table_elev = 58.0
	engine._update_ortho_size()
	await _wait(10)
	await _shot("04_vue_haute", engine)

	# Gros plan sur le plateau (zoom = s'approcher).
	engine.reset_zoom()
	await _wait(8)
	engine._apply_zoom(1.9, engine.size * 0.5)
	await _wait(10)
	await _shot("05_zoom_plateau", engine)

	# Lancer de dés 2d6 (clic droit en jeu) — valables seulement s'ils
	# atterrissent sur les creux (rectangles noirs) du plateau.
	engine.reset_zoom()
	engine.set_table_seat(0)
	engine.set_table_dice_color(Color(0.82, 0.24, 0.18))
	var zones: Array = engine._table_env.dice_zones()
	if not zones.is_empty():
		var z: Rect2 = zones[0]
		engine.roll_table_dice_at(Vector3(z.get_center().x, 0.0, z.get_center().y))
		for _i in range(360):
			await process_frame
			if engine._dice != null and engine._dice._pending == 0:
				break
		await _wait(4)
		await _shot("06_lancer_des", engine)
		var res: Dictionary = engine._dice.read_result()
		print("  [des] faces=", res["faces"], " positions=", res["positions"])
		# Gros plan sur les dés pour vérifier les chiffres des faces.
		var dpos: PackedVector3Array = res["positions"]
		if dpos.size() > 0:
			engine._table_target = Vector2(dpos[0].x, dpos[0].z)
			engine._apply_zoom(3.4, engine.size * 0.5)
			await _wait(12)
			await _shot("07_des_zoom", engine)

	print("")
	print("=== TABLE POC SCREENSHOTS ===")
	print("out=", OUT_DIR, " copy=", _copy_target())
	if _failed:
		printerr("table_poc_screenshot_test:FAIL")
		quit(1)
		return
	print("table_poc_screenshot_test:PASS")
	quit(0)

func _wait(n: int) -> void:
	for _i in range(n):
		await process_frame

## Boîte englobante des pixels lumineux (la carte illustrée) dans l'image.
func _bright_bbox(img: Image) -> Rect2:
	var w := img.get_width()
	var h := img.get_height()
	var minp := Vector2(w, h)
	var maxp := Vector2(0, 0)
	for y in range(0, h, 6):
		for x in range(0, w, 6):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 1.5:
				minp = Vector2(minf(minp.x, x), minf(minp.y, y))
				maxp = Vector2(maxf(maxp.x, x), maxf(maxp.y, y))
	if maxp.x <= minp.x:
		return Rect2()
	return Rect2(minp, maxp - minp)

## Capture la sortie exacte de la caméra (texture SubViewport) — la fenêtre
## peut être recadrée par la virtualisation DPI, pas le buffer 3D.
func _shot(name: String, engine: Control) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var tex: Texture2D = engine._viewport.get_texture()
	if tex == null:
		_assert("shot_tex_" + name, false)
		return
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 10:
		_assert("shot_img_" + name, false)
		return
	var user_path := OUT_DIR.path_join(name + ".png")
	var err := img.save_png(user_path)
	_assert("shot_save_" + name, err == OK)
	var abs_user := ProjectSettings.globalize_path(user_path)
	var copy_path := _copy_target().path_join(name + ".png")
	var copied := DirAccess.copy_absolute(abs_user, copy_path)
	_assert("shot_copy_" + name, copied == OK)
	print("  shot ", name, " → ", copy_path, " (", img.get_width(), "x", img.get_height(), ")")

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true
