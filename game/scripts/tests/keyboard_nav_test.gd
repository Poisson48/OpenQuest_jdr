extends SceneTree

## Accessibilité clavier — vérifie les raccourcis Échap / Ctrl+Entrée.
##
## Lancement :
##   godot --headless --path game -s res://scripts/tests/keyboard_nav_test.gd

const REPORT_PATH := "user://keyboard_nav_test_report.json"

var _steps: Array = []
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	await _step("editor_escape_closes_form", func():
		change_scene_to_file("res://scenes/character_editor.tscn")
		await _wait_scene("CharacterEditor")
		var editor := current_scene
		editor._begin_new_with_tier("medium")
		await process_frame
		await process_frame
		var opened: bool = editor.get_node("%FormPanel").visible
		await _press_escape()
		await process_frame
		var closed: bool = not editor.get_node("%FormPanel").visible
		return { "opened": opened, "closed": closed }
	)

	await _step("editor_escape_then_back", func():
		change_scene_to_file("res://scenes/character_editor.tscn")
		await _wait_scene("CharacterEditor")
		# Formulaire fermé : Échap doit revenir au hub.
		await _press_escape()
		await process_frame
		await process_frame
		var scene := current_scene
		return { "scene": scene.name if scene else "" }
	)

	await _step("scenario_list_escape_closes_detail", func():
		change_scene_to_file("res://scenes/scenario_list.tscn")
		await _wait_scene("ScenarioList")
		var list := current_scene
		var gd := root.get_node("GameData")
		var scenarios: Array = gd.get_scenarios()
		var ok_open := false
		if not scenarios.is_empty():
			list._show_scenario_details(scenarios[0])
			await process_frame
			ok_open = list.get_node("%DetailPanel").visible
		await _press_escape()
		await process_frame
		var ok_closed: bool = not list.get_node("%DetailPanel").visible
		return { "opened": ok_open, "closed": ok_closed }
	)

	await _step("action_bar_ctrl_enter_submits", func():
		var packed: PackedScene = load("res://scenes/session/panels/action_bar.tscn")
		var bar := packed.instantiate()
		root.add_child(bar)
		await process_frame
		bar.set_turn({ "headline": "Test", "hint": "", "tone": "active" })
		bar.set_player_controls_visible(true)
		var got := {"text": ""}
		bar.action_submitted.connect(func(t: String): got["text"] = t)
		bar.get_node("%ActionInput").text = "Je fouille la remorque."
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.ctrl_pressed = true
		ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		await process_frame
		bar.queue_free()
		return { "submitted": got["text"] }
	)

	var report := { "ok": not _failed, "steps": _steps }
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	var verdict := "PASS" if not _failed else "FAIL"
	print("[KEYBOARD NAV] %s" % verdict)
	for s in _steps:
		var ok: bool = s["ok"]
		print("  %s   %s  %s" % ["OK  " if ok else "FAIL", s["step"], s["result"]])
	quit(0 if not _failed else 1)

func _step(step_name: String, fn: Callable) -> void:
	var result: Dictionary = await fn.call()
	var ok := _check(step_name, result)
	_steps.append({ "step": step_name, "ok": ok, "result": result })
	if not ok:
		_failed = true

func _check(step_name: String, result: Dictionary) -> bool:
	match step_name:
		"editor_escape_closes_form":
			return bool(result.get("opened", false)) and bool(result.get("closed", false))
		"editor_escape_then_back":
			return str(result.get("scene", "")) == "Hub"
		"scenario_list_escape_closes_detail":
			return bool(result.get("opened", false)) and bool(result.get("closed", false))
		"action_bar_ctrl_enter_submits":
			return str(result.get("submitted", "")).begins_with("Je fouille")
	return false

func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame

func _wait_scene(expected_name: String, max_frames: int = 120) -> void:
	for i in max_frames:
		await process_frame
		var scene := current_scene
		if scene != null and scene.name == expected_name:
			return
