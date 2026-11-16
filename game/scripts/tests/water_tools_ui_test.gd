extends SceneTree

## Outils Eau : Rivière et Lac doivent être des outils VISIBLES de la palette
## (et pas seulement des entrées du menu « Mode » de « Peindre l'eau »).
## Vérifie aussi que le bouton actif suit le mode et que les options restent
## cohérentes.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Test outils eau", "general", "local", 24, 16)
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1400, 800)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	for _i in range(3):
		await process_frame

	var palette = editor._palette_v2
	_assert("palette_ready", palette != null)
	var buttons: Dictionary = palette._buttons if palette != null else {}
	for tool_id in ["water_paint", "water_river", "water_lake"]:
		_assert("palette_has_%s" % tool_id, buttons.has(tool_id))

	# --- Rivière : outil moteur Eau + mode river ------------------------------
	editor._set_tool("water_river")
	for _i in range(2):
		await process_frame
	_assert("river_maps_to_water_tool", editor._tool == "water_paint", str(editor._tool))
	_assert("river_mode", editor._water_mode == "river", editor._water_mode)
	_assert("river_active_id", editor._active_water_tool_id() == "water_river")
	if buttons.has("water_river"):
		_assert("river_button_pressed", (buttons["water_river"] as Button).button_pressed)

	# Options : sélecteur de mode avec Rivière et Lac.
	var mode_option := _find_mode_option(editor._tool_options)
	_assert("mode_option_present", mode_option != null)
	if mode_option != null:
		var texts := ""
		for i in range(mode_option.item_count):
			texts += str(mode_option.get_item_text(i)) + "|"
		_assert("mode_option_has_river", texts.to_lower().contains("rivi"))
		_assert("mode_option_has_lake", texts.to_lower().contains("lac"))

	# --- Lac : bouton dédié ---------------------------------------------------
	editor._set_tool("water_lake")
	for _i in range(2):
		await process_frame
	_assert("lake_maps_to_water_tool", editor._tool == "water_paint", str(editor._tool))
	_assert("lake_mode", editor._water_mode == "lake", editor._water_mode)
	_assert("lake_active_id", editor._active_water_tool_id() == "water_lake")
	if buttons.has("water_lake"):
		_assert("lake_button_pressed", (buttons["water_lake"] as Button).button_pressed)

	# --- Menu Mode : sélectionner « Rivière » resynchronise la palette ---------
	mode_option = _find_mode_option(editor._tool_options)
	_assert("mode_option_present_after_lake", mode_option != null)
	if mode_option != null:
		var river_index := -1
		for i in range(mode_option.item_count):
			if str(mode_option.get_item_text(i)).to_lower().contains("rivi"):
				river_index = i
		if river_index >= 0:
			mode_option.select(river_index)
			mode_option.item_selected.emit(river_index)
			await process_frame
			_assert("mode_select_sets_river_mode", editor._water_mode == "river", editor._water_mode)
			_assert("mode_select_updates_active",
				editor._active_water_tool_id() == "water_river")
			if buttons.has("water_river"):
				_assert("mode_select_presses_river_button",
					(buttons["water_river"] as Button).button_pressed)

	# --- Peindre (niveau) reste disponible ------------------------------------
	editor._set_tool("water_paint")
	await process_frame
	_assert("paint_mode", editor._water_mode == "paint", editor._water_mode)
	_assert("paint_active_id", editor._active_water_tool_id() == "water_paint")

	editor.queue_free()
	await process_frame
	_finish()


func _find_mode_option(options: Node) -> OptionButton:
	if options == null:
		return null
	for child in options.get_children():
		if child is OptionButton:
			return child as OptionButton
		var nested := _find_mode_option(child)
		if nested != null:
			return nested
	return null


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)


func _finish() -> void:
	if _failed:
		print("water_tools_ui_test:FAIL")
		quit(1)
		return
	print("water_tools_ui_test:PASS")
	quit(0)
