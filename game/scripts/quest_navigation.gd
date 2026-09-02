class_name QuestNavigation
extends RefCounted

## Normalisation et navigation non linéaire des scènes de scénario.
## Rétrocompatible : scénarios sans `id`/`transitions` deviennent linéaires implicites.

static func normalize_scenario(scenario: Dictionary) -> Dictionary:
	if scenario.is_empty():
		return {}
	var normalized: Dictionary = scenario.duplicate(true)
	var scenes: Array = normalized.get("scenes", [])
	if scenes.is_empty():
		return normalized

	var used_ids: Dictionary = {}
	for i in range(scenes.size()):
		if typeof(scenes[i]) != TYPE_DICTIONARY:
			continue
		var scene: Dictionary = (scenes[i] as Dictionary).duplicate(true)
		var scene_id := str(scene.get("id", "")).strip_edges()
		if scene_id.is_empty():
			scene_id = _default_scene_id(scene, i)
		scene_id = _ensure_unique_scene_id(scene_id, used_ids, i)
		scene["id"] = scene_id
		used_ids[scene_id] = true
		scenes[i] = scene

	for i in range(scenes.size()):
		var scene: Dictionary = scenes[i]
		var transitions: Array = scene.get("transitions", [])
		if typeof(transitions) != TYPE_ARRAY:
			transitions = []
		if transitions.is_empty() and i + 1 < scenes.size():
			transitions = [{
				"to": str(scenes[i + 1].get("id", "")),
				"label": "Continuer",
				"default": true,
			}]
		scene["transitions"] = _sanitize_transitions(transitions, used_ids)
		scenes[i] = scene

	normalized["scenes"] = scenes
	var start_id := str(normalized.get("startSceneId", "")).strip_edges()
	if start_id.is_empty() or not used_ids.has(start_id):
		normalized["startSceneId"] = str(scenes[0].get("id", "scene-0"))
	return normalized

static func get_scene_by_id(scenario: Dictionary, scene_id: String) -> Dictionary:
	var target := str(scene_id).strip_edges()
	if target.is_empty():
		return {}
	for scene in scenario.get("scenes", []):
		if typeof(scene) == TYPE_DICTIONARY and str(scene.get("id", "")) == target:
			return scene
	return {}

static func get_scene_index(scenario: Dictionary, scene_id: String) -> int:
	var target := str(scene_id).strip_edges()
	for i in range(scenario.get("scenes", []).size()):
		var scene = scenario["scenes"][i]
		if typeof(scene) == TYPE_DICTIONARY and str(scene.get("id", "")) == target:
			return i
	return -1

static func get_scene_id_at_index(scenario: Dictionary, index: int) -> String:
	var scenes: Array = scenario.get("scenes", [])
	if index < 0 or index >= scenes.size():
		return ""
	var scene = scenes[index]
	if typeof(scene) != TYPE_DICTIONARY:
		return "scene-%d" % index
	return str(scene.get("id", "scene-%d" % index))

static func resolve_current_scene_id(game: Dictionary, scenario: Dictionary) -> String:
	var explicit := str(game.get("currentSceneId", "")).strip_edges()
	if not explicit.is_empty() and not get_scene_by_id(scenario, explicit).is_empty():
		return explicit
	var idx: int = int(game.get("currentSceneIndex", 0))
	return get_scene_id_at_index(scenario, idx)

static func get_available_transitions(scenario: Dictionary, current_scene_id: String) -> Array:
	var scene := get_scene_by_id(scenario, current_scene_id)
	if scene.is_empty():
		return []
	var transitions: Array = scene.get("transitions", [])
	if typeof(transitions) != TYPE_ARRAY:
		return []
	return transitions.duplicate(true)

static func get_default_transition(transitions: Array) -> Dictionary:
	for transition in transitions:
		if typeof(transition) == TYPE_DICTIONARY and transition.get("default", false):
			return transition
	if not transitions.is_empty() and typeof(transitions[0]) == TYPE_DICTIONARY:
		return transitions[0]
	return {}

static func is_terminal_scene(scenario: Dictionary, scene_id: String) -> bool:
	var transitions := get_available_transitions(scenario, scene_id)
	return transitions.is_empty()

static func format_picker_label(scene: Dictionary, is_current: bool, is_visited: bool) -> String:
	var title := str(scene.get("title", scene.get("id", "Scène")))
	var prefix := "▶ " if is_current else ("✓ " if is_visited else "○ ")
	var tags: Array = scene.get("tags", [])
	var tag_suffix := ""
	if tags is Array and not tags.is_empty():
		var tag_parts: PackedStringArray = []
		for tag in tags:
			tag_parts.append(str(tag))
		tag_suffix = " [%s]" % ", ".join(tag_parts)
	return "%s%s%s" % [prefix, title, tag_suffix]

static func format_progress_label(scenario: Dictionary, game: Dictionary) -> String:
	var current_id := resolve_current_scene_id(game, scenario)
	var scene := get_scene_by_id(scenario, current_id)
	if scene.is_empty():
		return "Épilogue"
	var visited: Array = game.get("visitedSceneIds", [])
	var total: int = scenario.get("scenes", []).size()
	var visited_count: int = visited.size() if visited is Array else 0
	var branch_count: int = get_available_transitions(scenario, current_id).size()
	var branch_hint := ""
	if branch_count > 1:
		branch_hint = " · %d branches" % branch_count
	return "%s · %d/%d visitées%s" % [scene.get("title", ""), visited_count, total, branch_hint]

static func _default_scene_id(scene: Dictionary, index: int) -> String:
	var title := str(scene.get("title", "")).strip_edges().to_lower()
	if title.is_empty():
		return "scene-%d" % index
	var slug := ""
	for ch in title:
		if ch.is_valid_identifier() or ch == "-":
			slug += ch
		elif ch == " " or ch == "'":
			slug += "-"
	if slug.is_empty():
		return "scene-%d" % index
	while slug.contains("--"):
		slug = slug.replace("--", "-")
	return slug.strip_edges()

static func _ensure_unique_scene_id(base_id: String, used_ids: Dictionary, index: int) -> String:
	var candidate := base_id if not base_id.is_empty() else "scene-%d" % index
	if not used_ids.has(candidate):
		return candidate
	var suffix := 2
	while used_ids.has("%s-%d" % [candidate, suffix]):
		suffix += 1
	return "%s-%d" % [candidate, suffix]

static func _sanitize_transitions(transitions: Array, used_ids: Dictionary) -> Array:
	var result: Array = []
	var has_default := false
	for transition in transitions:
		if typeof(transition) != TYPE_DICTIONARY:
			continue
		var to_id := str(transition.get("to", "")).strip_edges()
		if to_id.is_empty() or not used_ids.has(to_id):
			continue
		var copy: Dictionary = transition.duplicate(true)
		copy["to"] = to_id
		if copy.get("default", false):
			has_default = true
		result.append(copy)
	if not result.is_empty() and not has_default:
		result[0]["default"] = true
	return result
