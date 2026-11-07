extends SceneTree

## Capture de l'interface « palettes » : carte plein écran, colonne d'icônes
## fine à gauche, palettes flottantes (options en haut, inspecteur à droite).

const OUT_DIR := "user://ui_shots"
const COPY_DIR := "docs/screenshots"

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Interface palettes", "general", "local", 24, 16)
	var heights: Array = []
	heights.resize(24 * 16)
	for y in range(16):
		for x in range(24):
			heights[y * 24 + x] = 0.4 * sin(x * 0.4) + 0.3 * cos(y * 0.5)
	map["terrainHeights"] = heights
	var scene: PackedScene = load("res://scenes/map_editor/map_editor.tscn")
	var editor: Control = scene.instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	editor.load_map(map)
	editor.set_editable(true)
	for _i in range(10):
		await process_frame
	# Palettes ouvertes pour la capture (comme l'utilisateur peut les déplier).
	editor._toggle_palette("right")
	await process_frame
	var img: Image = await _shot(editor, "ui_palettes")
	_assert("shot_not_blank", img != null and not _is_blank(img))
	if _failed:
		print("ui_palette_shot_test:FAIL")
		quit(1)
		return
	print("ui_palette_shot_test:PASS")
	quit(0)

func _shot(editor: Control, name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = editor.get_viewport().get_texture().get_image()
	if img == null:
		return null
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	DirAccess.make_dir_recursive_absolute(COPY_DIR)
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name]),
		ProjectSettings.globalize_path(COPY_DIR) + "/" + name + ".png")
	print("  capture: %s/%s.png" % [COPY_DIR, name])
	return img

func _is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(w / 2, h / 2)
	for pt in [Vector2i(w / 4, h / 4), Vector2i(3 * w / 4, h / 2), Vector2i(w / 2, 3 * h / 4)]:
		if img.get_pixelv(pt) != first:
			return false
	return true

func _assert(name: String, cond: bool) -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s" % name)
