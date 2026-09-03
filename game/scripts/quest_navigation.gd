class_name QuestNavigation
extends RefCounted

## Normalisation et navigation non linéaire des scènes de scénario.
## Rétrocompatible : scénarios sans `id`/`transitions` deviennent linéaires implicites.

const NODE_WIDTH := 220.0
const NODE_HEIGHT := 120.0
const LAYOUT_H_GAP := 280.0
const LAYOUT_V_GAP := 150.0
const LAYOUT_ORIGIN := Vector2(48, 48)

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

	var legacy_linear := true
	for scene in scenes:
		if typeof(scene) == TYPE_DICTIONARY and scene.has("transitions"):
			legacy_linear = false
			break

	for i in range(scenes.size()):
		var scene: Dictionary = scenes[i]
		var has_transition_field: bool = scene.has("transitions")
		var transitions: Array = []
		if has_transition_field and typeof(scene.get("transitions")) == TYPE_ARRAY:
			transitions = scene.get("transitions")
		# Rétrocompat : chaîne linéaire seulement pour les scénarios 100 % legacy
		# (aucune scène n'a le champ `transitions`). Un [] explicite = terminale.
		if legacy_linear and not has_transition_field and i + 1 < scenes.size():
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

## Analyse du graphe pour l'éditeur et les tests.
static func analyze_graph(scenario: Dictionary) -> Dictionary:
	var normalized := normalize_scenario(scenario.duplicate(true))
	var scenes: Array = normalized.get("scenes", [])
	var start_id := str(normalized.get("startSceneId", ""))
	var ids: Array = []
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	var branch_count := 0
	var broken: Array = []
	var terminals: Array = []

	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid := str(scene.get("id", ""))
		ids.append(sid)
		outgoing[sid] = []
		if not incoming.has(sid):
			incoming[sid] = 0

	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid := str(scene.get("id", ""))
		var transitions: Array = scene.get("transitions", [])
		if typeof(transitions) != TYPE_ARRAY:
			transitions = []
		if transitions.is_empty():
			terminals.append(sid)
		for transition in transitions:
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", "")).strip_edges()
			branch_count += 1
			if to_id.is_empty() or not outgoing.has(to_id):
				broken.append({ "from": sid, "to": to_id, "label": str(transition.get("label", "")) })
				continue
			(outgoing[sid] as Array).append(transition.duplicate(true))
			incoming[to_id] = int(incoming.get(to_id, 0)) + 1

	var reachable := get_reachable_ids(normalized, start_id)
	var unreachable: Array = []
	var orphans: Array = []
	for sid in ids:
		if not reachable.has(sid):
			unreachable.append(sid)
		var out_n: int = (outgoing.get(sid, []) as Array).size()
		var in_n: int = int(incoming.get(sid, 0))
		if sid != start_id and in_n == 0 and out_n == 0:
			orphans.append(sid)
		elif sid != start_id and in_n == 0:
			orphans.append(sid)

	var warnings: Array = []
	if scenes.is_empty():
		warnings.append("Aucune scène.")
	if start_id.is_empty():
		warnings.append("Scène de départ manquante.")
	elif get_scene_by_id(normalized, start_id).is_empty():
		warnings.append("Scène de départ invalide.")
	if not broken.is_empty():
		warnings.append("%d branche(s) cassée(s)." % broken.size())
	if not unreachable.is_empty():
		warnings.append("%d scène(s) inatteignable(s) depuis le départ." % unreachable.size())
	if not orphans.is_empty():
		warnings.append("%d scène(s) orpheline(s) (sans entrée)." % orphans.size())

	var multi_branch := 0
	for sid in outgoing.keys():
		if (outgoing[sid] as Array).size() > 1:
			multi_branch += 1

	var hard_ok: bool = broken.is_empty() and not scenes.is_empty() and not start_id.is_empty() \
		and not get_scene_by_id(normalized, start_id).is_empty()

	return {
		"ok": hard_ok,
		"sceneCount": ids.size(),
		"branchCount": branch_count,
		"multiBranchScenes": multi_branch,
		"startSceneId": start_id,
		"terminals": terminals,
		"unreachable": unreachable,
		"orphans": orphans,
		"brokenTransitions": broken,
		"reachableCount": reachable.size(),
		"warnings": warnings,
		"incoming": incoming,
		"outgoing": outgoing,
	}

static func get_reachable_ids(scenario: Dictionary, from_id: String) -> Dictionary:
	var result: Dictionary = {}
	var start := str(from_id).strip_edges()
	if start.is_empty() or get_scene_by_id(scenario, start).is_empty():
		return result
	var queue: Array = [start]
	result[start] = true
	while not queue.is_empty():
		var current: String = str(queue.pop_front())
		for transition in get_available_transitions(scenario, current):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", ""))
			if to_id.is_empty() or result.has(to_id):
				continue
			if get_scene_by_id(scenario, to_id).is_empty():
				continue
			result[to_id] = true
			queue.append(to_id)
	return result

static func validate_scenario_graph(scenario: Dictionary) -> Array:
	var analysis := analyze_graph(scenario)
	var errors: Array = []
	if str(scenario.get("title", "")).strip_edges().is_empty():
		errors.append("Le titre est obligatoire.")
	if int(analysis.get("sceneCount", 0)) <= 0:
		errors.append("Ajoutez au moins une scène.")
	var start_id := str(analysis.get("startSceneId", ""))
	if start_id.is_empty() or get_scene_by_id(scenario, start_id).is_empty():
		errors.append("Définissez une scène de départ valide.")
	for broken in analysis.get("brokenTransitions", []):
		if typeof(broken) == TYPE_DICTIONARY:
			errors.append("Branche invalide « %s » → « %s »." % [broken.get("from", "?"), broken.get("to", "?")])
	return errors

static func format_graph_health(analysis: Dictionary) -> String:
	var parts: PackedStringArray = []
	parts.append("%d scènes" % int(analysis.get("sceneCount", 0)))
	parts.append("%d branches" % int(analysis.get("branchCount", 0)))
	if int(analysis.get("multiBranchScenes", 0)) > 0:
		parts.append("%d carrefours" % int(analysis.get("multiBranchScenes", 0)))
	var warnings: Array = analysis.get("warnings", [])
	# Les orphelines / inatteignables sont des alertes UX, pas des erreurs bloquantes.
	var soft: Array = []
	for w in warnings:
		var text := str(w)
		if text.contains("orpheline") or text.contains("inatteignable"):
			soft.append(text)
	if analysis.get("ok", false) and soft.is_empty():
		return "✓ " + " · ".join(parts)
	if not soft.is_empty():
		return "⚠ " + " · ".join(parts) + " — " + str(soft[0])
	if not analysis.get("ok", false) and not warnings.is_empty():
		return "⚠ " + " · ".join(parts) + " — " + str(warnings[0])
	return "✓ " + " · ".join(parts)
## Disposition automatique en couches (BFS depuis la scène de départ).
static func auto_layout_positions(scenario: Dictionary) -> Dictionary:
	var normalized := normalize_scenario(scenario.duplicate(true))
	var start_id := str(normalized.get("startSceneId", ""))
	var layers: Dictionary = {}
	var order: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array = []

	if not start_id.is_empty() and not get_scene_by_id(normalized, start_id).is_empty():
		queue.append(start_id)
		visited[start_id] = true
		layers[start_id] = 0
		order[start_id] = 0

	while not queue.is_empty():
		var current: String = str(queue.pop_front())
		var layer: int = int(layers.get(current, 0))
		var child_index := 0
		for transition in get_available_transitions(normalized, current):
			if typeof(transition) != TYPE_DICTIONARY:
				continue
			var to_id := str(transition.get("to", ""))
			if to_id.is_empty() or visited.has(to_id):
				continue
			if get_scene_by_id(normalized, to_id).is_empty():
				continue
			visited[to_id] = true
			layers[to_id] = layer + 1
			order[to_id] = child_index
			child_index += 1
			queue.append(to_id)

	# Scènes hors graphe (inatteignables) : colonnes à part
	var orphan_col := 0
	for scene in normalized.get("scenes", []):
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var sid := str(scene.get("id", ""))
		if visited.has(sid):
			continue
		layers[sid] = -1
		order[sid] = orphan_col
		orphan_col += 1

	var layer_buckets: Dictionary = {}
	for sid in layers.keys():
		var layer: int = int(layers[sid])
		if not layer_buckets.has(layer):
			layer_buckets[layer] = []
		(layer_buckets[layer] as Array).append(sid)

	var max_layer := 0
	for layer in layer_buckets.keys():
		max_layer = maxi(max_layer, int(layer))

	var positions: Dictionary = {}
	for layer in layer_buckets.keys():
		var bucket: Array = layer_buckets[layer]
		bucket.sort_custom(func(a, b): return int(order.get(a, 0)) < int(order.get(b, 0)))
		var col: int = int(layer) if int(layer) >= 0 else (max_layer + 1)
		for i in range(bucket.size()):
			var sid: String = str(bucket[i])
			positions[sid] = LAYOUT_ORIGIN + Vector2(float(col) * LAYOUT_H_GAP, float(i) * LAYOUT_V_GAP)

	return positions

static func apply_auto_layout(scenario: Dictionary) -> Dictionary:
	var result: Dictionary = scenario.duplicate(true)
	var positions := auto_layout_positions(result)
	var scenes: Array = result.get("scenes", [])
	for i in range(scenes.size()):
		if typeof(scenes[i]) != TYPE_DICTIONARY:
			continue
		var scene: Dictionary = scenes[i]
		var sid := str(scene.get("id", ""))
		if positions.has(sid):
			var pos: Vector2 = positions[sid]
			scene["graphPos"] = { "x": pos.x, "y": pos.y }
			scenes[i] = scene
	result["scenes"] = scenes
	return result

static func ensure_graph_positions(scenario: Dictionary) -> Dictionary:
	var result: Dictionary = scenario.duplicate(true)
	var scenes: Array = result.get("scenes", [])
	var missing := false
	for scene in scenes:
		if typeof(scene) != TYPE_DICTIONARY:
			continue
		var gp = scene.get("graphPos", {})
		if typeof(gp) != TYPE_DICTIONARY or not gp.has("x") or not gp.has("y"):
			missing = true
			break
	if missing:
		return apply_auto_layout(result)
	return result

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
