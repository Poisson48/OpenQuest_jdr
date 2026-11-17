extends SceneTree

## Tests headless de la palette de commandes (refonte 04, composant autonome).
##
## Couvre : ouverture / centrage, filtre insensible à la casse sur
## label+hint+category, navigation ↑/↓, émission `action_chosen`, fermeture par
## Entrée, Échap, Ctrl+K et clic hors panneau.

const REPORT_PATH := "user://command_palette_test_report.json"
const PaletteScript := preload("res://scripts/scenario_editor/panels/command_palette.gd")

var _steps: Array = []
var _failed := false
var _palette = null
var _host: Control = null
var _chosen: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var root := get_root()
	_host = Control.new()
	_host.name = "Host"
	_host.position = Vector2(40, 30)
	_host.size = Vector2(1000, 700)
	root.add_child(_host)

	_palette = PaletteScript.new()
	root.add_child(_palette)
	await process_frame
	_palette.call("setup", _host)
	_palette.action_chosen.connect(func(id: String): _chosen.append(id))
	await process_frame

	await _step("ouverture_centrage", func():
		_palette.call("open", _items())
		await process_frame
		await process_frame
		var panel: Control = _palette.call("get_panel")
		var search: LineEdit = _palette.call("get_search_edit")
		var panel_size: Vector2 = _palette.call("get_panel_size")
		return {
			"open": bool(_palette.call("is_open")),
			"visible": bool(_palette.visible),
			"top_level": bool(_palette.top_level),
			"panel_w": panel_size.x,
			"count": int(_palette.call("get_visible_count")),
			"selected": int(_palette.call("get_selected_index")),
			"search_empty": search.text.is_empty(),
			"centered": absf(panel.get_global_rect().get_center().x - _host.get_global_rect().get_center().x) < 1.0,
			"ok": bool(_palette.call("is_open")) and bool(_palette.visible) and bool(_palette.top_level)
				and absf(panel_size.x - 560.0) < 0.5
				and int(_palette.call("get_visible_count")) == 4
				and int(_palette.call("get_selected_index")) == 0
				and search.text.is_empty(),
		}
	)

	await _step("filtre_insensible_casse", func():
		_palette.call("set_query", "AJOUTER")
		var upper := int(_palette.call("get_visible_count"))
		var upper_ids := _filtered_ids()
		_palette.call("set_query", "village")
		var hint_count := int(_palette.call("get_visible_count"))
		var hint_id := str((_palette.call("get_selected_item") as Dictionary).get("id", ""))
		_palette.call("set_query", "cartes")
		var category_count := int(_palette.call("get_visible_count"))
		var category_id := str((_palette.call("get_selected_item") as Dictionary).get("id", ""))
		_palette.call("set_query", "zzz")
		var empty_count := int(_palette.call("get_visible_count"))
		var empty_lbl := _palette.find_child("EmptyLabel", true, false) as Label
		_palette.call("set_query", "")
		var restored := int(_palette.call("get_visible_count"))
		return {
			"upper": upper, "upper_ids": upper_ids,
			"hint": hint_count, "hint_id": hint_id,
			"category": category_count, "category_id": category_id,
			"empty": empty_count, "empty_label": empty_lbl != null,
			"restored": restored,
			"ok": upper == 2 and upper_ids.has("scene-ajouter") and upper_ids.has("pnj-ajouter")
				and hint_count == 1 and hint_id == "carte-lier"
				and category_count == 1 and category_id == "carte-lier"
				and empty_count == 0 and empty_lbl != null
				and restored == 4,
		}
	)

	await _step("navigation_et_emission", func():
		_chosen.clear()
		_palette.call("set_query", "ajouter")
		_palette.call("move_selection", 1)
		var index := int(_palette.call("get_selected_index"))
		var id := str((_palette.call("get_selected_item") as Dictionary).get("id", ""))
		_palette.call("activate_selected")
		await process_frame
		return {
			"index": index, "id": id, "chosen": _chosen.duplicate(),
			"closed": not bool(_palette.call("is_open")),
			"ok": index == 1 and id == "pnj-ajouter"
				and _chosen.size() == 1 and str(_chosen[0]) == "pnj-ajouter"
				and not bool(_palette.call("is_open")),
		}
	)

	await _step("entree_execute", func():
		_chosen.clear()
		_palette.call("open", _items())
		await process_frame
		_palette.call("set_query", "carte")
		_palette.call("_input", _key_event(KEY_ENTER))
		await process_frame
		return {
			"chosen": _chosen.duplicate(),
			"closed": not bool(_palette.call("is_open")),
			"ok": _chosen.size() == 1 and str(_chosen[0]) == "carte-lier"
				and not bool(_palette.call("is_open")),
		}
	)

	await _step("echap_ferme", func():
		_palette.call("open", _items())
		await process_frame
		_palette.call("_input", _key_event(KEY_ESCAPE))
		await process_frame
		return {
			"closed": not bool(_palette.call("is_open")),
			"ok": not bool(_palette.call("is_open")),
		}
	)

	await _step("ctrl_k_ferme", func():
		_palette.call("open", _items())
		await process_frame
		_palette.call("_input", _key_event(KEY_K, true))
		await process_frame
		return {
			"closed": not bool(_palette.call("is_open")),
			"ok": not bool(_palette.call("is_open")),
		}
	)

	await _step("clic_exterieur_ferme", func():
		_palette.call("open", _items())
		await process_frame
		var dim: ColorRect = _palette.get_node("Dim")
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		event.position = Vector2(8, 8)
		event.global_position = Vector2(8, 8)
		dim.gui_input.emit(event)
		await process_frame
		return {
			"closed": not bool(_palette.call("is_open")),
			"visible": bool(_palette.visible),
			"ok": not bool(_palette.call("is_open")) and not bool(_palette.visible),
		}
	)

	if _palette != null and is_instance_valid(_palette):
		_palette.free()
	if _host != null and is_instance_valid(_host):
		_host.free()
	await process_frame
	_write_report()
	quit(0 if not _failed else 1)


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _items() -> Array:
	return [
		{ "id": "scene-ajouter", "label": "Ajouter une scène", "hint": "Graphe", "category": "Scène" },
		{ "id": "pnj-ajouter", "label": "Ajouter un PNJ", "hint": "Distribution", "category": "PNJ" },
		{ "id": "carte-lier", "label": "Lier une carte", "hint": "Village", "category": "Cartes" },
		{ "id": "note-creer", "label": "Créer une note", "hint": "Graphe", "category": "Scène" },
	]


func _filtered_ids() -> Array:
	var ids: Array = []
	for item in _palette.call("get_filtered_items"):
		ids.append(str((item as Dictionary).get("id", "")))
	return ids


func _key_event(keycode: int, ctrl: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	return event


func _step(step_name: String, action: Callable) -> void:
	print("[COMMAND_PALETTE] ", step_name, "...")
	var result: Variant = await action.call()
	var ok := _result_ok(result)
	_steps.append({ "step": step_name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[COMMAND_PALETTE] FAIL ", step_name, " -> ", result)
	else:
		print("[COMMAND_PALETTE] OK   ", step_name, " -> ", result)


func _result_ok(result: Variant) -> bool:
	if result is Dictionary:
		if result.has("error"):
			return false
		if result.has("ok"):
			return bool(result.get("ok"))
	return true


func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT TEST PALETTE DE COMMANDES ===")
	print(JSON.stringify(report, "\t"))
