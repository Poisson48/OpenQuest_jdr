extends SceneTree

## Capture du menu « Paramètres » de l'éditeur (atelier plein écran) sur une
## carte 2.5D réelle. Lancer SANS --headless :
##   godot --path game --script res://scripts/tests/map_editor_parametres_shot_test.gd
##
## Sorties (user://) : graphismes.png, touches.png, systeme.png, apercu_cinema.png

const OUT_DIR := "user://parametres_shots"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture impossible en headless.")
		quit(0)
		return
	await process_frame
	var md = get_root().get_node("MapData")
	var BootScript: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = BootScript.build_demo(md)
	if demo.is_empty():
		printerr("map_editor_parametres_shot_test:FAIL (démo vide)")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_title("Paramètres — éditeur")
	get_root().content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1920, 1200))
	get_root().size = Vector2i(1920, 1200)

	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = editor.get_viewport_rect().size
	editor.load_map(demo["map"])
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	await process_frame

	var menu = editor._parametres
	_assert("menu_created", menu != null)
	if menu == null:
		_finish()
		return
	editor._open_parametres()
	await _wait(30)
	_assert("menu_open", menu.visible)
	_assert("preview_texture", menu._preview_rect != null and menu._preview_rect.texture != null)
	_assert("metrics_live", menu._fps_value != null and menu._fps_value.text != "—")
	_capture("graphismes")

	menu._show_page("keys")
	await _wait(8)
	_capture("raccourcis")
	menu._show_page("display")
	await _wait(8)
	_capture("affichage")
	menu._show_page("interface")
	await _wait(8)
	_capture("interface")
	menu._show_page("system")
	await _wait(8)
	_capture("systeme")

	# Aperçu A/B : le preset de qualité de l'aperçu ne touche pas la carte.
	menu._show_page("graphics")
	menu._set_preview_quality("cinema")
	await _wait(12)
	_assert("ab_preview_cinema", menu._preview_tag.text.contains("CINÉMA"))
	_capture("apercu_cinema")
	menu._set_preview_quality("map")
	await _wait(6)

	# Résolution : essai + boîte de confirmation (retour automatique).
	menu._request_resolution(Vector2i(1280, 720))
	await _wait(10)
	_assert("resolution_dialog_open", menu._resolution_dialog != null
		and menu._resolution_dialog.visible)
	_capture("resolution")
	menu._cancel_resolution()
	await _wait(8)
	_assert("resolution_restored", not menu._resolution_dialog.visible)

	# Variante Jade + taille d'interface (le thème doit être complet).
	var settings = get_root().get_node("AppSettings")
	settings.set_value("interface", "theme", "jade")
	await _wait(14)
	menu._show_page("graphics")
	await _wait(8)
	_capture("jade_graphismes")
	menu._show_page("interface")
	await _wait(8)
	_capture("jade_interface")
	settings.set_value("interface", "ui_scale", 110)
	await _wait(14)
	menu._show_page("interface")
	await _wait(8)
	_capture("jade_interface_110")
	settings.set_value("interface", "ui_scale", 100)
	await _wait(10)
	menu._show_page("graphics")
	await _wait(6)
	# Chrome de l'éditeur en jade : l'en-tête, le dock et les palettes suivent.
	menu.close()
	await _wait(12)
	_capture("jade_editeur_entete")
	settings.set_value("interface", "theme", "or")
	await _wait(14)
	_assert("theme_restored_or",
		editor.theme.get_color("font_pressed_color", "Button") == Color("#f2c46c"))
	await _wait(6)
	_capture("editeur_entete")

	await _wait(2)
	_assert("menu_closed", not menu.visible)
	_assert("captures_written", FileAccess.file_exists(OUT_DIR.path_join("graphismes.png")))
	# Éditeur avec le menu fermé : vérifie l'entrée « ⚙ Paramètres » de l'en-tête.
	await _wait(6)
	_capture("editeur_entete")

	editor.queue_free()
	await _wait(3)
	_finish()

func _finish() -> void:
	if _failed:
		print("map_editor_parametres_shot_test:FAIL")
		quit(1)
		return
	print("map_editor_parametres_shot_test:PASS")
	print("  captures: ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

func _capture(name: String) -> void:
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		_failed = true
		printerr("  FAIL capture nulle (", name, ")")
		return
	img.convert(Image.FORMAT_RGBA8)
	var path := OUT_DIR.path_join(name + ".png")
	img.save_png(path)
	print("  capture: ", path, " (", img.get_width(), "x", img.get_height(), ")")

func _wait(frames: int) -> void:
	for i in range(frames):
		await process_frame

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
