extends SceneTree

## Captures réelles des **formations rocheuses Tripo3D** sur la carte de démo
## (dossier `docs/screenshots/`) :
##   • `rochers_formation_editor.png`     — l'éditeur complet, bibliothèque sur les rochers ;
##   • `rochers_formation_overview.png`    — vue d'ensemble des 4 formations ;
##   • `rochers_formation_affleurement.png`— crête de `bloc_rocheux_*` (assises + éboulis) ;
##   • `rochers_formation_eboulis.png`     — cône de cailloux `caillou_*` ;
##   • `rochers_formation_carriere.png`    — front de taille (falaise + banquette) ;
##   • `rochers_formation_ombres.png`      — contre-plongée montrant les ombres du
##     preset qualité `cinema`.
##
## Non headless : nécessite un rendu réel (fenêtre cachée via run_tests.ps1
## -IncludeShots). Lancement direct :
##   godot --path game --script res://scripts/tests/rock_formation_shot_test.gd

const Demo := preload("res://scripts/debug/rochers_boot.gd")

const MAP_W := 30
const MAP_H := 20
const SHOT_PREFIX := "rochers_formation"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	get_root().content_scale_factor = 1.0

	var md = get_root().get_node("MapData")
	var map: Dictionary = Demo.build_map(md)
	if map.is_empty():
		printerr("rock_formation_shot_test:FAIL carte vide")
		quit(1)
		return
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = get_root().get_visible_rect().size
	editor.load_map(map)
	await process_frame
	_assert("quality_preset", str(editor.doc.map_data.get("qualityPreset", "")) == "cinema",
		"preset=%s" % str(editor.doc.map_data.get("qualityPreset", "")))

	var plans: Array = Demo.generate_plans(MAP_W, MAP_H)
	var placed: int = Demo.apply_formations(editor.doc, plans)
	await process_frame
	editor.doc.clear_selection()
	editor._sync_engine()
	await process_frame
	_assert("formations_placed", placed > 25, "placed=%d" % placed)
	_assert("meshes_in_doc", editor.doc.elements_of_kind("mesh").size() == placed,
		"meshes=%d" % editor.doc.elements_of_kind("mesh").size())
	_assert("four_formations", plans.size() == 4)

	if editor._engine != null:
		editor._engine.focus_grid_rect(
			Rect2(0.5, 0.5, float(MAP_W) - 1.0, float(MAP_H) - 1.0))
	for _i in range(16):
		await process_frame
	await _shot("editor")

	_hide_chrome(editor)
	for _i in range(8):
		await process_frame
	await _shot("overview")

	var affleurement: Dictionary = plans[0]
	_frame_bounds(editor, affleurement["bounds"], 1.20)
	for _i in range(14):
		await process_frame
	await _shot("affleurement")

	var eboulis: Dictionary = plans[2]
	_frame_bounds(editor, eboulis["bounds"], 1.14)
	for _i in range(14):
		await process_frame
	await _shot("eboulis")

	var carriere: Dictionary = plans[3]
	_frame_bounds(editor, carriere["bounds"], 1.16)
	for _i in range(14):
		await process_frame
	await _shot("carriere")

	# Contre-plongée sur l'affleurement : les ombres du soleil « cinema » sont
	# lisibles sur le sol, la crête et les cailloux.
	_low_angle(editor, affleurement["bounds"], 1.26)
	for _i in range(16):
		await process_frame
	await _shot("ombres")

	if _failed:
		print("rock_formation_shot_test:FAIL")
		quit(1)
		return
	print("rock_formation_shot_test:PASS")
	quit(0)

# ===========================================================================
# Cadrage
# ===========================================================================

## Cadre une formation avec une marge serrée (le paramètre `margin` de
## `focus_grid_rect` : 1.0 = rect collé aux bords de l'écran).
func _frame_bounds(editor: Control, bounds: Rect2, margin: float) -> void:
	if editor._engine == null or not bounds.has_area():
		return
	editor._engine.focus_grid_rect(bounds, margin)

func _low_angle(editor: Control, bounds: Rect2, margin: float) -> void:
	if editor._engine == null or not bounds.has_area():
		return
	var engine = editor._engine
	_frame_bounds(editor, bounds, margin)
	if engine._camera == null:
		return
	# Inclinaison basse (le style 2.5d est à -50°) pour révéler les ombres
	# portées ; on itère le recentrage car le point visé dépend de l'inclinaison.
	engine._camera.rotation_degrees.x = -40.0
	var target: Vector2 = (bounds.get_center() as Vector2) * float(engine._cell_size)
	for _i in range(3):
		engine._center_focus_on(target)

# ===========================================================================
# Chrome et captures
# ===========================================================================

func _hide_chrome(editor: Control) -> void:
	editor.set_editable(false)
	var overlay = editor.get("_overlay")
	if overlay != null and overlay is CanvasItem:
		(overlay as CanvasItem).visible = false
	for child in editor.get_children():
		if child is PanelContainer and child.name != "ViewportFrame":
			(child as CanvasItem).visible = false

func _shot(shot_name: String) -> void:
	for _i in range(4):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		# GPU partagé : deuxième chance après 5 s.
		await create_timer(5.0).timeout
		img = get_root().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % shot_name, false, "texture nulle")
		return
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s_%s.png" % [SHOT_PREFIX, shot_name])
	img.save_png(out)
	_assert("capture_%s" % shot_name, FileAccess.file_exists(out), out)
	print("  capture: %s" % out)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
