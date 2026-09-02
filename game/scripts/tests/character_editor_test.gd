extends SceneTree

const REPORT_PATH := "user://character_editor_test_report.json"

var _steps: Array = []
var _failed := false
var _gd: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_gd = get_root().get_node("GameData")
	_gd.characters.clear()
	_gd.bots.clear()
	_gd.save_characters()
	_gd.save_bots()
	await process_frame

	await _step("load_scene", func():
		change_scene_to_file("res://scenes/character_editor.tscn")
		await _wait_scene("CharacterEditor")
		var editor := current_scene
		var script_ok := editor.get_script() != null
		await process_frame
		return {
			"has_form": editor.has_node("%FormPanel"),
			"has_tier_picker": editor.has_node("%TierPickerPanel"),
			"script_ok": script_ok,
			"form_hidden": not editor.get_node("%FormPanel").visible,
		}
	)

	await _step("create_simple_pc", func():
		return await _create_and_verify("simple", false, "Test Simple PC")
	)

	await _step("create_medium_pc", func():
		return await _create_and_verify("medium", false, "Test Medium PC")
	)

	await _step("create_complete_pc", func():
		return await _create_and_verify("complete", false, "Test Complete PC")
	)

	await _step("create_medium_bot", func():
		return await _create_and_verify("medium", true, "Test Medium Bot")
	)

	_write_report()
	quit(0 if not _failed else 1)

func _create_and_verify(tier: String, as_bot: bool, name_val: String) -> Dictionary:
	var editor := current_scene
	var blank: Dictionary = _gd.create_blank_character("general", tier, as_bot)
	blank["name"] = name_val
	if tier == "simple":
		blank["trait"] = "Testeur acharné"
	elif tier == "complete":
		blank["alignment"] = "Neutre Bon"
		blank["spellcasting"] = true
		blank["level"] = 3
	if as_bot:
		blank["traits"] = ["test", "fiable"]
		blank["personality"] = "curious"
		_gd.save_bot(blank)
	else:
		_gd.save_character(blank)

	await process_frame

	var stored: Dictionary = {}
	if as_bot:
		stored = _gd.get_bot_from_storage(blank["id"])
	else:
		stored = _gd.get_character_by_id(blank["id"])

	if stored.is_empty():
		return { "error": "Entité non retrouvée après sauvegarde", "tier": tier, "bot": as_bot }

	var summary: String = _gd.format_character_summary(stored)
	return {
		"id": stored.get("id"),
		"tier": _gd.get_ruleset_tier(stored),
		"bot": as_bot,
		"summary": summary,
		"name_ok": stored.get("name") == name_val,
	}

func _step(name: String, action: Callable) -> void:
	print("[CHAR_EDITOR] ", name, "...")
	var result: Variant = await action.call()
	var ok := not _has_error(result)
	_steps.append({ "step": name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[CHAR_EDITOR] FAIL ", name, " -> ", result)
	else:
		print("[CHAR_EDITOR] OK   ", name, " -> ", result)

func _has_error(result: Variant) -> bool:
	if result is Dictionary:
		if result.has("error"):
			return true
		if result.get("has_form", true) == false:
			return true
		if result.get("has_tier_picker", true) == false:
			return true
		if result.get("script_ok", true) == false:
			return true
		if result.has("name_ok") and result.get("name_ok", true) == false:
			return true
		if result.has("tier") and str(result.get("tier", "")) not in ["simple", "medium", "complete"]:
			return true
	return false

func _wait_scene(root_name: String, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			await process_frame
			return
	push_warning("Timeout scène: " + root_name)

func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT TEST ÉDITEUR PERSONNAGES ===")
	print(JSON.stringify(report, "\t"))
