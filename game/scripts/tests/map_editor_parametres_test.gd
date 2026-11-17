extends SceneTree

## Test du menu « Paramètres » de l'éditeur de cartes 3D (atelier plein écran) :
## persistance, surcharges de rendu appliquées au moteur, remap des raccourcis,
## neutralité par défaut (rendu de la carte intact) et structure de l'UI.
##
## Les autoloads sont récupérés via `get_root().get_node()` (comme les autres
## tests `--script` : les identifiants d'autoload ne sont pas compilés ici).

var _failed := false
var _as: Node = null   # AppSettings
var _md: Node = null   # MapData

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_as = get_root().get_node("AppSettings")
	_md = get_root().get_node("MapData")
	if _as == null or _md == null:
		printerr("autoloads manquants : AppSettings / MapData")
		quit(1)
		return

	# Le test écrit de vraies préférences : on note l'état pour le restaurer.
	var backup := _snapshot_settings()

	# --- 1) Valeurs par défaut : aucune surcharge du rendu de la carte -------
	_as.reset_all()
	var neutral: Dictionary = _as.overrides_config()
	_assert("default_preset_is_carte", str(_as.get_rendering("preset")) == "carte")
	_assert("neutral_msaa_auto", int(neutral["msaa"]) == -1 and int(neutral["screen_space_aa"]) == -1)
	_assert("neutral_shadow_map", str(neutral["shadow_quality"]) == "map")
	_assert("neutral_render_scale", is_equal_approx(float(neutral["render_scale"]), 1.0))
	var untouched = _as.translate_key_event(_key(KEY_Z, true))
	_assert("default_translation_passthrough", untouched != null and untouched.keycode == KEY_Z)

	# --- 2) Persistance : écriture / relecture du .cfg -----------------------
	_as.set_value("display", "max_fps", 60)
	_as.set_value("rendering", "render_scale", 0.75)
	_as.set_value("interface", "confirm_delete", true)
	_as.save_settings()
	var cfg := ConfigFile.new()
	_assert("cfg_saved", cfg.load("user://app_settings.cfg") == OK)
	_assert("cfg_max_fps", int(cfg.get_value("display", "max_fps", -1)) == 60)
	_assert("cfg_render_scale", is_equal_approx(float(cfg.get_value("rendering", "render_scale", 0.0)), 0.75))
	_assert("cfg_confirm_delete", bool(cfg.get_value("interface", "confirm_delete", false)) == true)
	_as.load_settings()
	_assert("reload_max_fps", int(_as.get_display("max_fps")) == 60)
	_assert("reload_render_scale", is_equal_approx(float(_as.get_rendering("render_scale")), 0.75))
	_assert("engine_max_fps", Engine.max_fps == 60)
	_as.reset_all()
	_assert("reset_max_fps", int(_as.get_display("max_fps")) == 0 and Engine.max_fps == 0)

	# --- 3) Éditeur : chargement d'une carte et application des surcharges ---
	var editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	get_root().add_child(editor)
	await process_frame
	await process_frame
	var map: Dictionary = _md.create_complex_map("Test paramètres", "general", "local", 16, 12)
	editor.load_map(map)
	await process_frame
	await process_frame
	var engine = editor._engine
	_assert("editor_engine", engine != null)
	var viewport = engine.call("get_3d_viewport")
	_assert("engine_viewport", viewport is SubViewport)
	if viewport is SubViewport:
		_assert("default_msaa_unchanged",
			(viewport as SubViewport).msaa_3d == Viewport.MSAA_2X)
		_assert("default_render_scale",
			is_equal_approx((viewport as SubViewport).scaling_3d_scale, 1.0))

	# Preset Performance : MSAA off, échelle 85 %, ombres coupées.
	_as.set_preset("performance")
	await process_frame
	if viewport is SubViewport:
		_assert("perf_msaa_off", (viewport as SubViewport).msaa_3d == Viewport.MSAA_DISABLED)
		_assert("perf_render_scale",
			is_equal_approx((viewport as SubViewport).scaling_3d_scale, 0.85))
	_assert("perf_shadows_off", engine._sun != null and not engine._sun.shadow_enabled)

	# La carte reste la propriétaire : un `configure()` ne doit PAS écraser la
	# préférence globale (c'est tout l'intérêt du hook post-configure).
	editor._sync_engine()
	await process_frame
	if viewport is SubViewport:
		_assert("overrides_survive_configure",
			(viewport as SubViewport).msaa_3d == Viewport.MSAA_DISABLED)
	_assert("overrides_survive_configure_shadows",
		engine._sun != null and not engine._sun.shadow_enabled)

	# Preset Cinéma : MSAA 4×, puis retour au rendu de la carte.
	_as.set_preset("cinema")
	await process_frame
	if viewport is SubViewport:
		_assert("cinema_msaa_4x", (viewport as SubViewport).msaa_3d == Viewport.MSAA_4X)
	_as.set_preset("carte")
	await process_frame
	if viewport is SubViewport:
		_assert("back_to_card_msaa", (viewport as SubViewport).msaa_3d == Viewport.MSAA_2X)

	# --- 4) Remap des raccourcis -------------------------------------------
	var remap := {"keycode": KEY_U, "ctrl": true, "alt": false, "shift": false}
	_assert("remap_accepted", _as.set_action_binding("undo", remap) == "")
	var translated = _as.translate_key_event(_key(KEY_U, true))
	_assert("remap_translates",
		translated != null and translated.keycode == KEY_Z and translated.ctrl_pressed)
	_assert("remap_blocks_old_key", _as.translate_key_event(_key(KEY_Z, true)) == null)
	# Conflit : Ctrl+U est déjà pris par « Annuler ».
	var conflict: String = _as.set_action_binding("save", remap)
	_assert("remap_conflict_detected", not conflict.is_empty())
	# Touche réservée (Espace) refusée.
	_assert("remap_reserved_refused", not _as.set_action_binding(
		"save", {"keycode": KEY_SPACE, "ctrl": false, "alt": false, "shift": false}).is_empty())
	# Réinitialisation : Ctrl+Z redevient actif.
	_as.reset_keys()
	_assert("remap_reset", _as.translate_key_event(_key(KEY_Z, true)) != null)
	# Le remap persiste dans le fichier.
	_as.set_action_binding("delete", {"keycode": KEY_X, "ctrl": false, "alt": false, "shift": true})
	_as.save_settings()
	var cfg2 := ConfigFile.new()
	cfg2.load("user://app_settings.cfg")
	_assert("cfg_has_key_remap", cfg2.has_section("keys") and cfg2.has_section_key("keys", "delete"))
	_as.reset_keys()

	# --- 5) Menu : structure, navigation, préférences d'affichage -----------
	var menu = editor._parametres
	_assert("menu_created", menu != null)
	_assert("menu_hidden_at_start", menu != null and not menu.visible)
	editor._open_parametres()
	await process_frame
	_assert("menu_opens", menu.visible)
	_assert("menu_pages", menu._pages.size() == 5 and menu._nav_buttons.size() == 5)
	_assert("menu_preview_fps",
		menu._fps_value != null and menu._fps_ms != null and menu._fps_dc != null)
	_assert("menu_default_page", menu.current_page() == "graphics")
	menu._show_page("keys")
	_assert("menu_switch_page", menu.current_page() == "keys" and menu._pages["keys"].visible)
	_assert("menu_keys_rows", menu._keys_list.get_child_count() > 0)
	menu._show_page("display")
	_assert("menu_back_display",
		menu._pages["display"].visible and not menu._pages["keys"].visible)
	menu.close()
	await process_frame
	_assert("menu_closes", not menu.visible)

	# Entrées du menu : F10, bouton d'en-tête et menu Échap.
	editor._unhandled_key_input(_key(KEY_F10))
	await process_frame
	_assert("f10_opens_menu", menu.visible)
	menu._unhandled_key_input(_key(KEY_ESCAPE))
	await process_frame
	_assert("escape_closes_menu", not menu.visible)
	_assert("esc_menu_entry",
		editor._esc_menu != null and editor._esc_menu.get_node_or_null("%BtnParametres") != null)
	var header_buttons: Array = []
	for node in editor.find_children("*", "Button", true, false):
		if (node as Button).text.contains("Paramètres"):
			header_buttons.append(node)
	_assert("header_settings_button", not header_buttons.is_empty())

	# Compteur FPS : position et visibilité sont des préférences.
	_as.set_value("display", "fps_position", "top_right")
	await process_frame
	_assert("fps_overlay_created", editor._fps_overlay != null)
	_assert("fps_overlay_visible", editor._fps_overlay.visible)
	_as.set_value("display", "fps_visible", false)
	await process_frame
	_assert("fps_hidden", not editor._fps_overlay.visible and not editor._fps_lbl.visible)
	_as.set_value("display", "fps_position", "status")
	_as.set_value("display", "fps_visible", true)
	await process_frame
	_assert("fps_status_visible", editor._fps_lbl.visible and not editor._fps_overlay.visible)

	# Mini-carte masquée par préférence.
	_as.set_value("interface", "show_minimap", false)
	await process_frame
	_assert("minimap_hidden", not editor.get_node("%MinimapHost").visible)
	_as.set_value("interface", "show_minimap", true)
	await process_frame
	_assert("minimap_restored", editor.get_node("%MinimapHost").visible)

	# Résolution : sélecteur, essai non persistant, confirmation, annulation.
	_as.set_value("display", "window_width", 0, false)
	_as.set_value("display", "window_height", 0, true)
	editor._open_parametres()
	await process_frame
	menu._show_page("graphics")
	await process_frame
	var resolutions: Array = menu._available_resolutions()
	_assert("resolution_options", resolutions.size() >= 3)
	_assert("resolution_auto_first", resolutions[0][0] == Vector2i.ZERO)
	menu._request_resolution(Vector2i(1280, 720))
	await process_frame
	_assert("resolution_dialog", menu._resolution_dialog != null
		and menu._resolution_dialog.visible and menu._resolution_pending == Vector2i(1280, 720))
	_assert("resolution_not_saved_before_confirm", _as.window_resolution() == Vector2i.ZERO)
	menu._confirm_resolution()
	await process_frame
	_assert("resolution_confirmed_saved", _as.window_resolution() == Vector2i(1280, 720))
	menu._request_resolution(Vector2i(1024, 768))
	await process_frame
	menu._cancel_resolution()
	await process_frame
	_assert("resolution_cancel_keeps_previous", _as.window_resolution() == Vector2i(1280, 720))
	_assert("resolution_cancel_hides_dialog", not menu._resolution_dialog.visible)
	menu.close()
	await process_frame

	# Confirmation de suppression : la boîte apparaît, la sélection survit.
	var element_id: String = editor.doc.add_element({
		"x": 3.0, "y": 3.0, "label": "Note test",
	}, "note", "Note")
	editor.doc.set_selection([element_id])
	_as.set_value("interface", "confirm_delete", true)
	editor._delete_selection()
	await process_frame
	_assert("confirm_dialog_created", editor._delete_confirm_dialog != null
		and editor._delete_confirm_dialog.visible)
	_assert("selection_kept_until_confirm", not editor.doc.selection().is_empty())
	editor._delete_confirm_dialog.hide()
	_as.set_value("interface", "confirm_delete", false)
	editor._delete_selection()
	await process_frame
	_assert("delete_without_confirm", editor.doc.selection().is_empty())

	# --- 6) Recherche dans la page et mesure FPS ---------------------------
	editor._open_parametres()
	await process_frame
	menu._show_page("graphics")
	menu._on_search_changed("ombres")
	await process_frame
	var visible_rows := 0
	var hidden_rows := 0
	for entry in menu._search_entries:
		if str(entry["page"]) != "graphics":
			continue
		if (entry["row"] as Control).visible:
			visible_rows += 1
		else:
			hidden_rows += 1
	_assert("search_hides_rows", hidden_rows > 0 and visible_rows > 0)
	menu._on_search_changed("")
	await process_frame
	_assert("search_restores_rows", hidden_rows > 0)
	# Mesure 10 s : alimentée par des échantillons puis clôturée par `_process`.
	menu._start_measure()
	menu._measure_samples = [60.0, 62.0, 58.0]
	menu._process(10.5)
	await process_frame
	_assert("measure_done", menu._measure_label.text.contains("Moyenne"))
	menu.close()
	await process_frame

	# --- 7) Thème (or / jade) et taille de l'interface ---------------------
	var theme_script = load("res://scripts/theme/cartographer_theme.gd")
	_assert("theme_default_or", str(_as.get_interface("theme")) == "or")
	_assert("theme_active_or", theme_script.active_variant() == "or")
	_assert("theme_gold_button",
		editor.theme.get_color("font_pressed_color", "Button") == Color("#f2c46c"))
	_as.set_value("interface", "theme", "jade")
	await process_frame
	await process_frame
	_assert("theme_jade_active", theme_script.active_variant() == "jade")
	_assert("theme_jade_button",
		editor.theme.get_color("font_pressed_color", "Button") == Color("#55d6be"))
	_assert("theme_jade_label_recolored",
		editor._fps_lbl.get_theme_color("font_color") != Color("#a59173"))
	_as.set_value("interface", "theme", "or")
	await process_frame
	await process_frame
	_assert("theme_back_or",
		editor.theme.get_color("font_pressed_color", "Button") == Color("#f2c46c"))
	_assert("theme_back_label",
		editor._fps_lbl.get_theme_color("font_color") == Color("#a59173"))
	# Taille de l'interface : facteur d'échelle du canvas racine.
	_as.set_value("interface", "ui_scale", 110)
	await process_frame
	_assert("ui_scale_110", is_equal_approx(get_root().content_scale_factor, 1.1))
	_as.set_value("interface", "ui_scale", 100)
	await process_frame
	_assert("ui_scale_100", is_equal_approx(get_root().content_scale_factor, 1.0))

	# --- 8) Cohérence documentaire : le preset de qualité suit la carte ------
	editor.doc.set_meta_values({"qualityPreset": "cinema"}, "Test")
	await process_frame
	_assert("map_quality_read", menu._map_quality_preset() == "cinema")
	editor.doc.set_meta_values({}, "Test")

	# --- Nettoyage / restauration ------------------------------------------
	editor.queue_free()
	await process_frame
	_restore_settings(backup)
	_as.save_settings()
	await process_frame

	if _failed:
		print("map_editor_parametres_test:FAIL")
		quit(1)
		return
	print("map_editor_parametres_test:PASS")
	quit(0)

func _key(keycode: int, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.pressed = true
	return event

func _snapshot_settings() -> Dictionary:
	var out := {}
	for section in ["display", "rendering", "interface"]:
		var values: Array = []
		for key in (_as.DEFAULTS[section] as Dictionary).keys():
			values.append(_as.get_value(section, str(key)))
		out[section] = values
	return out

func _restore_settings(backup: Dictionary) -> void:
	# On repart des défauts puis on réapplique les valeurs notées (les types
	# peuvent avoir changé pendant le test).
	_as.reset_all()
	for section in ["display", "rendering", "interface"]:
		var keys: Array = (_as.DEFAULTS[section] as Dictionary).keys()
		var values: Array = backup.get(section, [])
		for i in range(mini(keys.size(), values.size())):
			_as.set_value(section, str(keys[i]), values[i], false)
	_as.apply_section("display")
	_as.apply_section("rendering")
	_as.apply_section("interface")

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
