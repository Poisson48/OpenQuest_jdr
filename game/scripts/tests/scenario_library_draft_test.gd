extends SceneTree

## Smoke test : catalogue vs brouillons + persistance user://.

const REPORT_PATH := "user://scenario_library_draft_test_report.json"

var _steps: Array = []
var _failed := false
var _gd: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_gd = get_root().get_node("GameData")
	await process_frame

	await _step("draft_helpers_and_persistence", func():
		_gd.load_scenarios()
		var catalog_before: int = _gd.get_scenarios().size()
		var drafts_before: int = _gd.get_draft_scenarios().size()
		var blank_adv: Dictionary = _gd.create_blank_scenario("general", "oneshot")
		blank_adv["title"] = "Brouillon Aventure Test"
		_gd.save_scenario(blank_adv)
		var blank_inv: Dictionary = _gd.create_blank_scenario("investigation", "investigation")
		blank_inv["title"] = "Brouillon Enquête Test"
		_gd.save_scenario(blank_inv)

		var drafts_all: Array = _gd.get_draft_scenarios()
		var drafts_adv: Array = _gd.get_draft_scenarios("adventure")
		var drafts_inv: Array = _gd.get_draft_scenarios("investigation")
		var catalog_after: int = _gd.get_scenarios().size()

		var has_adv := false
		var has_inv := false
		for d in drafts_adv:
			if str(d.get("id")) == str(blank_adv.get("id")):
				has_adv = true
		for d in drafts_inv:
			if str(d.get("id")) == str(blank_inv.get("id")):
				has_inv = true

		# Recharge : les brouillons doivent survivre au merge builtins + user.
		_gd.load_scenarios()
		var drafts_reloaded: Array = _gd.get_draft_scenarios()
		var still_adv := false
		var still_inv := false
		for d in drafts_reloaded:
			var sid := str(d.get("id"))
			if sid == str(blank_adv.get("id")):
				still_adv = true
			if sid == str(blank_inv.get("id")):
				still_inv = true

		_gd.delete_scenario(str(blank_adv.get("id")))
		_gd.delete_scenario(str(blank_inv.get("id")))

		return {
			"catalog_before": catalog_before,
			"catalog_after": catalog_after,
			"drafts_before": drafts_before,
			"drafts_all": drafts_all.size(),
			"has_adv": has_adv,
			"has_inv": has_inv,
			"still_adv": still_adv,
			"still_inv": still_inv,
			"ok": catalog_after == catalog_before
				and has_adv and has_inv
				and still_adv and still_inv
				and drafts_all.size() >= drafts_before + 2,
		}
	)

	await _step("publish_draft_to_catalog", func():
		_gd.load_scenarios()
		var blank: Dictionary = _gd.create_blank_scenario("general", "oneshot")
		blank["title"] = "À publier"
		_gd.save_scenario(blank)
		var sid := str(blank.get("id"))
		var catalog_before: int = _gd.get_scenarios().size()
		var drafts_before: int = _gd.get_draft_scenarios().size()
		var published: bool = bool(_gd.publish_scenario(sid))
		var in_catalog := false
		for s in _gd.get_scenarios():
			if str(s.get("id")) == sid:
				in_catalog = true
		var still_draft := false
		for s in _gd.get_draft_scenarios():
			if str(s.get("id")) == sid:
				still_draft = true
		var unpublished: bool = bool(_gd.unpublish_scenario(sid))
		var back_in_drafts := false
		for s in _gd.get_draft_scenarios():
			if str(s.get("id")) == sid:
				back_in_drafts = true
		_gd.delete_scenario(sid)
		return {
			"published": published,
			"in_catalog": in_catalog,
			"still_draft": still_draft,
			"catalog_delta": _gd.get_scenarios().size() - catalog_before + 1, # deleted after
			"drafts_before": drafts_before,
			"unpublished": unpublished,
			"back_in_drafts": back_in_drafts,
			"ok": published and in_catalog and not still_draft and unpublished and back_in_drafts,
		}
	)

	await _step("library_tabs_exist", func():
		change_scene_to_file("res://scenes/scenario_list.tscn")
		for _i in range(120):
			await process_frame
			if current_scene and current_scene.name == "ScenarioList":
				break
		await process_frame
		var editor := current_scene
		var tabs: HBoxContainer = editor.get_node("%LibraryTabs")
		var tab_ids: Array = []
		for child in tabs.get_children():
			if child is Button:
				tab_ids.append(str(child.get_meta("tab_id", "")))
		editor.set("_library_tab", "draft")
		editor.call("_sync_library_tab_buttons")
		editor.call("refresh_list")
		await process_frame
		return {
			"tab_ids": tab_ids,
			"current": editor.get("_library_tab"),
			"ok": tab_ids.has("catalog") and tab_ids.has("draft")
				and str(editor.get("_library_tab")) == "draft",
		}
	)

	_write_report()
	quit(0 if not _failed else 1)

func _step(name: String, action: Callable) -> void:
	print("[SCENARIO_LIBRARY] ", name, "...")
	var result: Variant = await action.call()
	var ok := true
	if result is Dictionary:
		ok = bool(result.get("ok", true)) and not result.has("error")
	_steps.append({ "step": name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[SCENARIO_LIBRARY] FAIL ", name, " -> ", result)
	else:
		print("[SCENARIO_LIBRARY] OK   ", name, " -> ", result)

func _write_report() -> void:
	var report := { "passed": not _failed, "steps": _steps }
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
	print("\n=== RAPPORT TEST BIBLIOTHÈQUE BROUILLONS ===")
	print(JSON.stringify(report, "\t"))
