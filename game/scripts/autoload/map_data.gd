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
