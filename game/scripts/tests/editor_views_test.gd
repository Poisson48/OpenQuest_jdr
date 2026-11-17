extends SceneTree

## Tests headless des vues de contenu de l'éditeur (refonte 04).
##
## Couvre les trois modes : cartes de scènes (titres, tags, extrait, branches,
## surbrillance), édition directe des PNJ (mutations dans le Dictionary
## scénario) et rattachement des cartes à la scène sélectionnée.

const REPORT_PATH := "user://editor_views_test_report.json"
const ViewsScript := preload("res://scripts/scenario_editor/panels/editor_views.gd")

var _steps: Array = []
var _failed := false
var _views = null
var _scenario: Dictionary = {}
var _selected_id: String = "s1"
var _scene_events: Array = []
var _npc_events: int = 0
var _map_link_events: int = 0
var _add_npc_requests: int = 0
var _add_map_link_requests: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_scenario = _fixture()
	var root := get_root()
	_views = ViewsScript.new()
	root.add_child(_views)
	await process_frame
	_views.setup(_scenario, Callable(self, "_maps_provider"), Callable(self, "_selected_provider"))
	_views.scene_selected.connect(func(id: String): _scene_events.append(id))
	_views.npc_changed.connect(func(): _npc_events += 1)
	_views.map_link_changed.connect(func(): _map_link_events += 1)
	_views.request_add_npc.connect(func(): _add_npc_requests += 1)
	_views.request_add_map_link.connect(func(map_id: String): _add_map_link_requests.append(map_id))
	await process_frame

	await _step("mode_scenario_cartes", func():
		_views.call("set_mode", "scenario")
		await process_frame
		var text := str(_views.call("get_rendered_text"))
		var card_s1 = _views.call("get_scene_card", "s1")
		var card_s2 = _views.call("get_scene_card", "s2")
		var card_s3 = _views.call("get_scene_card", "s3")
		return {
			"text_sample": text.substr(0, 260),
			"has_start": text.contains("★ Entrée"),
			"has_terminal": text.contains("⚑ Finale"),
			"has_tag": text.contains("#debut"),
			"has_excerpt": text.contains("Le vent hurle sur les remparts."),
			"has_branches": text.contains("3 branches") and text.contains("★ → 👁"),
			"has_npc_not_listed": not text.contains("Gardien"),
			"cards": card_s1 != null and card_s2 != null and card_s3 != null,
			"highlight": card_s1 != null and bool(card_s1.get_meta("selected", false))
				and card_s2 != null and not bool(card_s2.get_meta("selected", true)),
			"ok": text.contains("★ Entrée") and text.contains("⚑ Finale")
				and text.contains("#debut")
				and text.contains("Le vent hurle sur les remparts.")
				and text.contains("3 branches") and text.contains("★ → 👁")
				and not text.contains("Gardien")
				and card_s1 != null and card_s2 != null and card_s3 != null
				and bool(card_s1.get_meta("selected", false))
				and not bool(card_s2.get_meta("selected", true)),
		}
	)

	await _step("clic_scene_emet", func():
		_scene_events.clear()
		var card: Control = _views.call("get_scene_card", "s2")
		if card == null:
			return { "error": "carte s2 absente" }
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		card.gui_input.emit(event)
		await process_frame
		return {
			"events": _scene_events.duplicate(),
			"ok": _scene_events.size() == 1 and str(_scene_events[0]) == "s2",
		}
	)

	await _step("mode_npc_edition", func():
		_views.call("set_mode", "npc")
		await process_frame
		var text := str(_views.call("get_rendered_text"))
		var card: Control = _views.call("get_npc_card", 0)
		if card == null:
			return { "error": "carte PNJ 0 absente" }
		var name_edit := card.find_child("NpcName", true, false) as LineEdit
		var role_edit := card.find_child("NpcRole", true, false) as LineEdit
		var desc := card.find_child("NpcDescription", true, false) as TextEdit
		if name_edit == null or role_edit == null or desc == null:
			return { "error": "champs PNJ absents" }
		var before := _npc_events
		name_edit.text = "Veilleur"
		name_edit.text_changed.emit("Veilleur")
		role_edit.text = "Éclaireur"
		role_edit.text_changed.emit("Éclaireur")
		desc.text = "Il connaît les ruelles."
		desc.text_changed.emit()
		await process_frame
		var npc: Dictionary = _scenario["npcs"][0]
		var add_btn := _views.find_child("BtnAddNpc", true, false) as Button
		if add_btn != null:
			add_btn.pressed.emit()
		await process_frame
		return {
			"before_text": text.contains("Gardien") and text.contains("Sentinelle")
				and text.contains("Scènes : s1"),
			"name": npc.get("name"),
			"role": npc.get("role"),
			"description": npc.get("description"),
			"npc_events": _npc_events - before,
			"add_requests": _add_npc_requests,
			"ok": text.contains("Gardien") and text.contains("Sentinelle")
				and text.contains("Scènes : s1")
				and npc.get("name") == "Veilleur"
				and npc.get("role") == "Éclaireur"
				and str(npc.get("description", "")).contains("ruelles")
				and _npc_events - before == 3
				and _add_npc_requests == 1,
		}
	)

	await _step("mode_npc_supprimer", func():
		var before := _npc_events
		_views.call("set_mode", "npc")
		await process_frame
		var card: Control = _views.call("get_npc_card", 0)
		if card == null:
			return { "error": "carte PNJ absente avant suppression" }
		var delete_btn := card.find_child("BtnDeleteNpc", true, false) as Button
		if delete_btn == null:
			return { "error": "bouton supprimer absent" }
		delete_btn.pressed.emit()
		await process_frame
		await process_frame
		var npcs: Array = _scenario.get("npcs", [])
		return {
			"npcs": npcs.size(),
			"npc_events": _npc_events - before,
			"empty_state": str(_views.call("get_rendered_text")).contains("Aucun PNJ"),
			"ok": npcs.is_empty() and _npc_events - before == 1
				and str(_views.call("get_rendered_text")).contains("Aucun PNJ"),
		}
	)

	await _step("mode_maps_et_rattachement", func():
		_selected_id = "s2"
		_scene_events.clear()
		_map_link_events = 0
		_add_map_link_requests.clear()
		_views.call("set_mode", "maps")
		await process_frame
		var text := str(_views.call("get_rendered_text"))
		var card_a: Control = _views.call("get_map_card", "map-a")
		var card_b: Control = _views.call("get_map_card", "map-b")
		if card_a == null or card_b == null:
			return { "error": "cartes de map absentes", "text": text.substr(0, 220) }
		var chip: Button = card_a.find_child("SceneChip_s1", true, false) as Button
		var chip_ok := chip != null
		if chip != null:
			chip.pressed.emit()
			await process_frame
		var link_btn := card_b.find_child("BtnLinkMap", true, false) as Button
		var link_ok := link_btn != null
		if link_btn != null:
			link_btn.pressed.emit()
			await process_frame
			await process_frame
		var scene_b: Dictionary = _scenario["scenes"][1]
		var map_ids: Array = scene_b.get("mapIds", [])
		var card_b_after: Control = _views.call("get_map_card", "map-b")
		var chip_after: Button = null
		if card_b_after != null:
			chip_after = card_b_after.find_child("SceneChip_s2", true, false) as Button
		return {
			"has_local_badge": text.contains("LOCALE"),
			"has_world_badge": text.contains("MONDE"),
			"has_titles": text.contains("Village") and text.contains("Royaume"),
			"chip_scene_event": _scene_events.duplicate(),
			"map_ids": map_ids,
			"map_link_events": _map_link_events,
			"add_requests": _add_map_link_requests.duplicate(),
			"chip_after": chip_after != null,
			"ok": text.contains("LOCALE") and text.contains("MONDE")
				and text.contains("Village") and text.contains("Royaume")
				and chip_ok and _scene_events.size() == 1 and str(_scene_events[0]) == "s1"
				and link_ok and map_ids.has("map-b")
				and _map_link_events == 1
				and _add_map_link_requests == ["map-b"]
				and chip_after != null,
		}
	)

	if _views != null and is_instance_valid(_views):
		_views.free()
	await process_frame
	_write_report()
	quit(0 if not _failed else 1)


# ---------------------------------------------------------------------------
# Fixtures / fournisseurs
# ---------------------------------------------------------------------------

func _fixture() -> Dictionary:
	return {
		"id": "test-views",
		"title": "Vues test",
		"startSceneId": "s1",
		"scenes": [
			{
				"id": "s1", "title": "Entrée",
				"content": "Le vent hurle sur les remparts.",
				"tags": ["debut", "nuit"],
				"transitions": [
					{ "to": "s2", "label": "Porte", "default": true },
					{ "to": "s2", "label": "Passage secret" },
					{ "to": "s3", "label": "Fenêtre", "gmOnly": true },
				],
				"mapIds": ["map-a"],
				"graphPos": { "x": 0, "y": 0 },
			},
			{
				"id": "s2", "title": "Couloir",
				"content": "Un couloir sombre.",
				"tags": [],
				"transitions": [{ "to": "s3", "label": "Suite" }],
				"mapIds": [],
				"graphPos": { "x": 300, "y": 0 },
			},
			{
				"id": "s3", "title": "Finale",
				"content": "",
				"tags": ["fin"],
				"transitions": [],
				"mapIds": [],
				"graphPos": { "x": 600, "y": 0 },
			},
		],
		"npcs": [
			{
				"id": "npc-1",
				"name": "Gardien",
				"role": "Sentinelle",
				"description": "Muet",
				"scenes": ["s1"],
			},
		],
	}


func _maps_provider() -> Array:
	return [
		{ "id": "map-a", "title": "Village", "roster": "general", "mapKind": "local" },
		{ "id": "map-b", "title": "Royaume", "roster": "general", "mapKind": "world" },
	]


func _selected_provider() -> String:
	return _selected_id


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _step(step_name: String, action: Callable) -> void:
	print("[EDITOR_VIEWS] ", step_name, "...")
	var result: Variant = await action.call()
	var ok := _result_ok(result)
	_steps.append({ "step": step_name, "ok": ok, "result": result })
	if not ok:
		_failed = true
		print("[EDITOR_VIEWS] FAIL ", step_name, " -> ", result)
	else:
		print("[EDITOR_VIEWS] OK   ", step_name, " -> ", result)


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
	print("\n=== RAPPORT TEST VUES ÉDITEUR ===")
	print(JSON.stringify(report, "\t"))
