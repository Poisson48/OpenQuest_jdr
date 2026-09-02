extends Node

signal maps_updated

const MAPS_PATH := "user://maps.json"
const MEMBER_COLOR_HEX := [
	"#e8c547", "#47a8e8", "#e86a47",
	"#47e88a", "#b847e8", "#e89247",
]

const MARKERS := {
	"party": "⚔️", "npc": "🎭", "poi": "📍", "danger": "⚠️", "treasure": "💎", "exit": "🚪",
	"capital": "👑", "city": "🏙️", "dungeon": "🏰", "quest": "❗", "camp": "⛺", "ruin": "🏛️",
	"detective": "🔍", "suspect": "🕵️", "evidence": "📎", "witness": "🗣️", "crime": "🩸",
}

var maps: Array = []
var preview_map_id: String = ""
var editor_mode: String = "preview"
var pending_link_target_id: String = ""
var _tile_defs: Dictionary = {}

func _ready() -> void:
	_load_tile_defs()
	load_maps()

func _load_tile_defs() -> void:
	var raw := FileAccess.get_file_as_string("res://data/tiles.json")
	var data = JSON.parse_string(raw)
	if data is Dictionary:
		_tile_defs = data

func load_maps() -> void:
	var data = _load_json(MAPS_PATH)
	if data is Array and not data.is_empty():
		maps = data
	else:
		maps = _load_default_maps()
		save_maps()
	maps_updated.emit()

func save_maps() -> void:
	_save_json(MAPS_PATH, maps)
	maps_updated.emit()

func get_by_id(map_id: String) -> Dictionary:
	for m in maps:
		if m.get("id") == map_id:
			return m
	return {}

func list_for_scenario(scenario_id: String, roster: String = "") -> Array:
	var result: Array = []
	for m in maps:
		if not roster.is_empty() and m.get("roster", "general") != roster:
			continue
		if m.get("scenarioId", "") == scenario_id or scenario_id.is_empty():
			result.append(m)
	return result

func get_map_ids_for_scenario(scenario_id: String, quest_format: String = "") -> Array:
	var ids: Array = []
	for m in maps:
		if m.get("scenarioId") == scenario_id:
			ids.append(m.get("id"))
	if ids.is_empty():
		if quest_format == "investigation" or scenario_id.begins_with("inv-"):
			if get_by_id("demo-quartier-serpent").has("id"):
				ids.append("demo-quartier-serpent")
		elif scenario_id == "demo-couronne-fracturee":
			ids.append("demo-monde-couronne")
			ids.append("demo-taverne")
		else:
			if get_by_id("demo-taverne").has("id"):
				ids.append("demo-taverne")
	return ids

func get_setup_map_pool(scenario_id: String, quest_format: String) -> Array:
	var pool: Array = []
	var is_investigation := quest_format == "investigation" or scenario_id.begins_with("inv-")
	for m in maps:
		if is_investigation:
			if m.get("roster", "general") != "investigation":
				continue
		else:
			if m.get("roster", "") == "investigation":
				continue
		pool.append(m)
	pool.sort_custom(func(a, b):
		var a_linked := 0 if a.get("scenarioId", "") == scenario_id and not scenario_id.is_empty() else 1
		var b_linked := 0 if b.get("scenarioId", "") == scenario_id and not scenario_id.is_empty() else 1
		if a_linked != b_linked:
			return a_linked < b_linked
		var a_world := 0 if is_world_map(a) else 1
		var b_world := 0 if is_world_map(b) else 1
		if a_world != b_world:
			return a_world < b_world
		return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower()
	)
	return pool

func get_default_selected_map_ids(scenario_id: String, quest_format: String) -> Array:
	var ids: Array = []
	for m in get_setup_map_pool(scenario_id, quest_format):
		if m.get("scenarioId", "") == scenario_id:
			ids.append(m.get("id", ""))
	if ids.is_empty():
		ids = get_map_ids_for_scenario(scenario_id, quest_format)
	return ids

func is_world_map(map_data: Dictionary) -> bool:
	return map_data.get("mapKind", "local") == "world"

func get_tile_color(map_data: Dictionary, tile_id: String) -> Color:
	var kind := "local"
	if map_data.get("roster") == "investigation":
		kind = "investigation"
	elif is_world_map(map_data):
		kind = "world"
	if _tile_defs.has(kind) and _tile_defs[kind].has(tile_id):
		return Color.html(_tile_defs[kind][tile_id].get("color", "#444444"))
	return Color.html("#333333")

func get_marker_emoji(marker_type: String) -> String:
	return MARKERS.get(marker_type, "•")

func get_member_color(member_id: String, party: Array) -> Color:
	for i in range(party.size()):
		if party[i].get("id") == member_id:
			return Color.html(MEMBER_COLOR_HEX[i % MEMBER_COLOR_HEX.size()])
	return Color.html(MEMBER_COLOR_HEX[0])

func get_linked_local_map_ids(world_map: Dictionary) -> Array:
	var ids: Array = []
	for link in world_map.get("locationLinks", []):
		var tid: String = link.get("targetMapId", "")
		if not tid.is_empty() and not ids.has(tid):
			ids.append(tid)
	return ids

func get_session_marker_types(quest_format: String, map_data: Dictionary) -> Array:
	if quest_format == "investigation":
		return ["detective", "suspect", "evidence", "witness", "crime", "poi", "danger"]
	if is_world_map(map_data):
		return ["capital", "city", "dungeon", "quest", "camp", "ruin", "danger"]
	return ["npc", "poi", "danger", "treasure"]

func get_marker_label(marker_type: String) -> String:
	var labels := {
		"party": "Groupe", "npc": "PNJ", "poi": "Point d'intérêt", "danger": "Danger",
		"treasure": "Trésor", "exit": "Sortie", "capital": "Capitale", "city": "Ville",
		"dungeon": "Donjon", "quest": "Quête", "camp": "Campement", "ruin": "Ruine",
		"detective": "Détective", "suspect": "Suspect", "evidence": "Indice",
		"witness": "Témoin", "crime": "Scène de crime",
	}
	return labels.get(marker_type, marker_type.capitalize())

func get_maps_by_category(category: String) -> Array:
	var result: Array = []
	for m in maps:
		match category:
			"world":
				if is_world_map(m):
					result.append(m)
			"investigation":
				if not is_world_map(m) and m.get("roster", "") == "investigation":
					result.append(m)
			"adventure":
				if not is_world_map(m) and m.get("roster", "general") != "investigation":
					result.append(m)
	return result

func sort_maps(list: Array, sort_mode: String) -> Array:
	var copy: Array = list.duplicate()
	copy.sort_custom(func(a, b):
		match sort_mode:
			"title_desc":
				return str(a.get("title", "")).to_lower() > str(b.get("title", "")).to_lower()
			"size_desc":
				var area_a: int = int(a.get("width", 0)) * int(a.get("height", 0))
				var area_b: int = int(b.get("width", 0)) * int(b.get("height", 0))
				return area_a > area_b
			"scenario":
				var sa: String = str(a.get("scenarioId", ""))
				var sb: String = str(b.get("scenarioId", ""))
				if sa == sb:
					return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower()
				return sa < sb
			_:
				return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower()
	)
	return copy

func create_blank_map(title: String, roster: String, map_kind: String) -> Dictionary:
	var is_world := map_kind == "world"
	var w: int = 48 if is_world else 16
	var h: int = 32 if is_world else 12
	var fill_tile := "grass" if is_world else "floor"
	if roster == "investigation" and not is_world:
		fill_tile = "floor"
	var tiles: Array = []
	tiles.resize(w * h)
	tiles.fill(fill_tile)
	var map := {
		"id": "map-%d" % Time.get_unix_time_from_system(),
		"title": title,
		"description": "",
		"roster": roster,
		"mapKind": map_kind,
		"scenarioId": "",
		"width": w,
		"height": h,
		"tiles": tiles,
		"markers": [],
		"locationLinks": [],
	}
	maps.append(map)
	save_maps()
	return map

func delete_map(map_id: String) -> void:
	maps = maps.filter(func(m): return m.get("id", "") != map_id)
	save_maps()

func update_map(map_data: Dictionary) -> void:
	var map_id: String = map_data.get("id", "")
	if map_id.is_empty():
		return
	for i in range(maps.size()):
		if maps[i].get("id") == map_id:
			maps[i] = map_data
			save_maps()
			return

func get_tile_palette(map_data: Dictionary) -> Dictionary:
	var kind := "local"
	if map_data.get("roster") == "investigation":
		kind = "investigation"
	elif is_world_map(map_data):
		kind = "world"
	if _tile_defs.has(kind):
		return _tile_defs[kind]
	return {}

func get_editor_marker_types(map_data: Dictionary) -> Array:
	if is_world_map(map_data):
		return ["capital", "city", "dungeon", "quest", "camp", "ruin", "danger"]
	if map_data.get("roster") == "investigation":
		return ["detective", "suspect", "evidence", "witness", "crime", "poi", "danger"]
	return ["npc", "poi", "danger", "treasure", "exit"]

const MERGEABLE_MARKER_TYPES := ["city", "capital", "camp", "ruin", "dungeon"]

func is_mergeable_marker(marker_type: String) -> bool:
	return marker_type in MERGEABLE_MARKER_TYPES

func get_local_maps_for_linking(roster: String) -> Array:
	var result: Array = []
	for m in maps:
		if is_world_map(m):
			continue
		if roster == "investigation":
			if m.get("roster", "") != "investigation":
				continue
		elif m.get("roster", "") == "investigation":
			continue
		result.append(m)
	result.sort_custom(func(a, b): return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower())
	return result

func get_world_maps_for_roster(roster: String) -> Array:
	var result: Array = []
	for m in maps:
		if not is_world_map(m):
			continue
		if roster == "investigation":
			if m.get("roster", "") != "investigation":
				continue
		elif m.get("roster", "") == "investigation":
			continue
		result.append(m)
	result.sort_custom(func(a, b): return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower())
	return result

func get_world_links_to_map(local_map_id: String) -> Array:
	var result: Array = []
	if local_map_id.is_empty():
		return result
	for m in maps:
		if not is_world_map(m):
			continue
		for link in m.get("locationLinks", []):
			if link.get("targetMapId", "") == local_map_id:
				result.append({
					"worldMapId": m.get("id", ""),
					"worldTitle": m.get("title", "Carte monde"),
					"x": link.get("x", 0),
					"y": link.get("y", 0),
					"label": link.get("label", ""),
				})
	return result

func get_location_link_at(map_data: Dictionary, x: int, y: int) -> Dictionary:
	for link in map_data.get("locationLinks", []):
		if link.get("x") == x and link.get("y") == y:
			return link
	return {}

func _load_default_maps() -> Array:
	var list: Array = []
	for path in ["res://data/maps/demo-taverne.json", "res://data/maps/demo-monde-couronne.json", "res://data/maps/demo-quartier-serpent.json"]:
		var m = _load_json(path)
		if m is Dictionary and m.has("id"):
			list.append(m)
	return list

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	return JSON.parse_string(text)

func _save_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
