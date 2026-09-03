extends Node

signal maps_updated

const MAPS_PATH := "user://maps.json"
const MAP_ASSETS_DIR := "user://map_assets/"
const SCHEMA_VERSION := 4
const RENDER_MODE_SIMPLE := "simple"
const RENDER_MODE_COMPLEX := "complex"
const DEFAULT_GRID_CONFIG := {
	"size": 70,
	"opacity": 0.22,
	"color": "#ffffff",
	"enabled": true,
}
const DEFAULT_LIGHTING_CONFIG := {
	"enabled": false,
	"direction": "nw",
	"intensity": 0.35,
	"ambient": "#121018",
	"sources": [],
}
const DEFAULT_PLAY_DEFAULTS := {
	"tokens": [],
	"effects": [],
	"zones": [],
	"fogRevealed": [],
	"viewState": {},
}
## Catégories de lieux, reprises telles quelles dans la légende de la carte.
## Elles correspondent aux pictogrammes des cartes de village illustrées.
const AREA_CATEGORIES := [
	{"id": "building", "label": "Bâtiment", "icon": "🏠"},
	{"id": "shop", "label": "Commerce / Service", "icon": "💰"},
	{"id": "poi", "label": "Lieu d'intérêt", "icon": "⭐"},
	{"id": "exit", "label": "Sortie", "icon": "➡"},
	{"id": "nature", "label": "Nature", "icon": "🌲"},
]

## Échelle par défaut d'une case (1,5 m ≈ 5 pieds, standard des JDR sur grille).
const DEFAULT_MEASURE := {
	"unit": "m",
	"perCell": 1.5,
}
## Calques d'édition par défaut (ordre d'empilement du sol vers les notes MJ).
const DEFAULT_LAYERS := [
	{"id": 0, "name": "Terrain", "visible": true, "locked": false},
	{"id": 1, "name": "Décor", "visible": true, "locked": false},
	{"id": 2, "name": "Structures", "visible": true, "locked": false},
	{"id": 3, "name": "Zones & effets", "visible": true, "locked": false},
	{"id": 4, "name": "Tokens", "visible": true, "locked": false},
	{"id": 5, "name": "Notes MJ", "visible": true, "locked": false},
]
const PERSPECTIVE_TOPDOWN := "topdown"
const PERSPECTIVE_ISOMETRIC := "isometric"
const PERSPECTIVE_TILT := "perspective"
const MEMBER_COLOR_HEX := [
	"#e8c547", "#47a8e8", "#e86a47",
	"#47e88a", "#b847e8", "#e89247",
]
const MEMBER_PLAYER_EMOJIS_GENERAL := ["⚔️", "🛡️", "🏹", "🗡️", "🪄", "🦅"]
const MEMBER_PLAYER_EMOJIS_INVESTIGATION := ["🔍", "🕵️", "📋", "🧢", "👤", "🗝️"]

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
	for i in range(maps.size()):
		maps[i] = ensure_map_schema(maps[i])
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
			if is_world_map(m):
				continue
		else:
			if m.get("roster", "") == "investigation":
				continue
			if quest_format == "oneshot" and is_world_map(m):
				continue
		var linked_id: String = str(m.get("scenarioId", ""))
		if not linked_id.is_empty() and linked_id != scenario_id:
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

func is_playable_member(member: Dictionary) -> bool:
	if member.get("isBot", false):
		return false
	return member.get("isPlayer", false) or member.get("isHuman", false)

func get_player_members(party: Array) -> Array:
	var result: Array = []
	for m in party:
		if is_playable_member(m):
			result.append(m)
	return result

func get_member_emoji(member_id: String, party: Array, quest_format: String = "oneshot") -> String:
	var member: Dictionary = {}
	for m in party:
		if m.get("id") == member_id:
			member = m
			break
	if member.is_empty():
		return "⚔️"
	if member.get("isBot", false):
		return "🤖"
	if not is_playable_member(member):
		return "🔍" if quest_format == "investigation" else "⚔️"
	var players := get_player_members(party)
	var index := 0
	for i in range(players.size()):
		if players[i].get("id") == member_id:
			index = i
			break
	var pool: Array = MEMBER_PLAYER_EMOJIS_INVESTIGATION if quest_format == "investigation" else MEMBER_PLAYER_EMOJIS_GENERAL
	return pool[index % pool.size()]

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
	return ["npc", "poi", "danger", "treasure", "exit"]

const INVESTIGATION_VISIBLE_MARKERS := ["detective", "party", "camp"]
const INVESTIGATION_HIDDEN_LOCAL := ["evidence", "witness", "suspect", "crime", "poi", "danger"]
const INVESTIGATION_HIDDEN_WORLD := ["city", "capital", "quest", "dungeon", "ruin"]

func is_investigation_map_context(map_data: Dictionary, quest_format: String) -> bool:
	return quest_format == "investigation" or map_data.get("roster", "") == "investigation"

func is_investigation_hidden_marker(marker_type: String, map_data: Dictionary, quest_format: String) -> bool:
	if not is_investigation_map_context(map_data, quest_format):
		return false
	if marker_type in INVESTIGATION_VISIBLE_MARKERS:
		return false
	if is_world_map(map_data):
		return marker_type in INVESTIGATION_HIDDEN_WORLD
	return marker_type in INVESTIGATION_HIDDEN_LOCAL

func is_investigation_hidden_link(map_data: Dictionary, quest_format: String) -> bool:
	return is_investigation_map_context(map_data, quest_format) and is_world_map(map_data)

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

func get_render_mode(map_data: Dictionary) -> String:
	var mode := str(map_data.get("renderMode", RENDER_MODE_SIMPLE))
	return RENDER_MODE_COMPLEX if mode == RENDER_MODE_COMPLEX else RENDER_MODE_SIMPLE

func set_render_mode(map_id: String, mode: String) -> void:
	if map_id.is_empty():
		return
	var normalized := RENDER_MODE_COMPLEX if mode == RENDER_MODE_COMPLEX else RENDER_MODE_SIMPLE
	for i in range(maps.size()):
		if maps[i].get("id") == map_id:
			maps[i] = ensure_map_schema(maps[i])
			maps[i]["renderMode"] = normalized
			save_maps()
			return

func is_complex_map(map_data: Dictionary) -> bool:
	return get_render_mode(map_data) == RENDER_MODE_COMPLEX

func get_grid_config(map_data: Dictionary) -> Dictionary:
	var cfg: Dictionary = DEFAULT_GRID_CONFIG.duplicate(true)
	if map_data.get("grid") is Dictionary:
		cfg.merge(map_data["grid"], true)
	return cfg

func get_lighting_config(map_data: Dictionary) -> Dictionary:
	var cfg: Dictionary = DEFAULT_LIGHTING_CONFIG.duplicate(true)
	if map_data.get("lighting") is Dictionary:
		cfg.merge(map_data["lighting"], true)
	return cfg

func get_perspective(map_data: Dictionary) -> String:
	var p := str(map_data.get("perspective", PERSPECTIVE_TOPDOWN))
	if p in [PERSPECTIVE_ISOMETRIC, PERSPECTIVE_TILT]:
		return p
	return PERSPECTIVE_TOPDOWN

func get_elevation_layers(map_data: Dictionary) -> Array:
	var layers = map_data.get("elevationLayers", [])
	return layers if layers is Array else []

func ensure_map_schema(map_data: Dictionary) -> Dictionary:
	if not map_data.has("schemaVersion"):
		map_data["schemaVersion"] = 1
	if not map_data.has("renderMode"):
		map_data["renderMode"] = RENDER_MODE_SIMPLE
	if not map_data.has("grid"):
		map_data["grid"] = DEFAULT_GRID_CONFIG.duplicate(true)
	if not map_data.has("fogEnabled"):
		map_data["fogEnabled"] = not is_world_map(map_data)
	if not map_data.has("perspective"):
		map_data["perspective"] = PERSPECTIVE_TOPDOWN
	if not map_data.has("elevationLayers"):
		map_data["elevationLayers"] = []
	if not map_data.has("lighting"):
		map_data["lighting"] = DEFAULT_LIGHTING_CONFIG.duplicate(true)
	if not map_data.has("atmosphere"):
		map_data["atmosphere"] = {"enabled": false, "tint": "#1a1410", "opacity": 0.25, "vignette": 0.15}
	if not map_data.has("playDefaults"):
		map_data["playDefaults"] = DEFAULT_PLAY_DEFAULTS.duplicate(true)
	# Schéma 3 — éléments d'éditeur : murs, notes MJ, calques, échelle.
	if not map_data.has("walls") or typeof(map_data["walls"]) != TYPE_ARRAY:
		map_data["walls"] = []
	if not map_data.has("notes") or typeof(map_data["notes"]) != TYPE_ARRAY:
		map_data["notes"] = []
	if not map_data.has("measure") or typeof(map_data["measure"]) != TYPE_DICTIONARY:
		map_data["measure"] = DEFAULT_MEASURE.duplicate(true)
	if not map_data.has("losEnabled"):
		map_data["losEnabled"] = false
	# Schéma 4 — cartes illustrées à plusieurs échelles.
	if not map_data.has("areas") or typeof(map_data["areas"]) != TYPE_ARRAY:
		map_data["areas"] = []
	if not map_data.has("props") or typeof(map_data["props"]) != TYPE_ARRAY:
		map_data["props"] = []
	if not map_data.has("parentMapId"):
		map_data["parentMapId"] = ""
	if not map_data.has("layers") or typeof(map_data["layers"]) != TYPE_ARRAY:
		map_data["layers"] = DEFAULT_LAYERS.duplicate(true)
	# Schéma 5 — style diorama 2.5D (défaut) ou VTT tactique.
	if not map_data.has("renderStyle"):
		map_data["renderStyle"] = "diorama"
	if str(map_data.get("renderStyle", "diorama")) == "diorama":
		# Grille masquée par défaut sur un village illustré.
		var grid: Dictionary = map_data.get("grid", {})
		if grid is Dictionary and not grid.has("show"):
			grid = grid.duplicate(true)
			grid["show"] = false
			map_data["grid"] = grid
	return map_data

func get_play_defaults(map_data: Dictionary) -> Dictionary:
	var m := ensure_map_schema(map_data)
	return m.get("playDefaults", DEFAULT_PLAY_DEFAULTS.duplicate(true)).duplicate(true)

func ensure_play_defaults(map_data: Dictionary) -> Dictionary:
	var m := ensure_map_schema(map_data)
	var pd: Dictionary = m.get("playDefaults", {})
	if typeof(pd) != TYPE_DICTIONARY:
		pd = DEFAULT_PLAY_DEFAULTS.duplicate(true)
		m["playDefaults"] = pd
	for key in ["tokens", "effects", "zones", "fogRevealed"]:
		if not pd.has(key) or typeof(pd[key]) != TYPE_ARRAY:
			pd[key] = []
	if not pd.has("viewState") or typeof(pd["viewState"]) != TYPE_DICTIONARY:
		pd["viewState"] = {}
	m["playDefaults"] = pd
	return pd

func generate_id(prefix: String) -> String:
	return "%s-%d-%s" % [prefix, Time.get_unix_time_from_system(), str(randi() % 90000 + 10000)]

func create_complex_map(title: String, roster: String, map_kind: String = "local", grid_cells_w: int = 20, grid_cells_h: int = 14) -> Dictionary:
	var tiles: Array = []
	tiles.resize(grid_cells_w * grid_cells_h)
	tiles.fill("floor")
	var map := ensure_map_schema({
		"id": generate_id("map"),
		"title": title,
		"description": "",
		"roster": roster,
		"mapKind": map_kind,
		"renderMode": RENDER_MODE_COMPLEX,
		"renderStyle": "diorama",
		"scenarioId": "",
		"width": grid_cells_w,
		"height": grid_cells_h,
		"tiles": tiles,
		"markers": [],
		"locationLinks": [],
		"backgroundImage": "",
		"fogEnabled": true,
		"perspective": PERSPECTIVE_TOPDOWN,
		"elevationLayers": [],
		"lighting": DEFAULT_LIGHTING_CONFIG.duplicate(true),
		"atmosphere": {"enabled": true, "tint": "#141018", "opacity": 0.12, "vignette": 0.18},
		"schemaVersion": SCHEMA_VERSION,
	})
	maps.append(map)
	save_maps()
	return map

# ===========================================================================
# Cartes à plusieurs échelles
# ===========================================================================
#
# Une carte de village illustrée porte des « lieux » (areas). Chaque lieu peut
# ouvrir une carte enfant — la place du marché, l'intérieur d'une taverne — où
# l'on place réellement les personnages. La profondeur n'est pas limitée.

static func area_category(category_id: String) -> Dictionary:
	for category in AREA_CATEGORIES:
		if category["id"] == category_id:
			return category
	return AREA_CATEGORIES[0]

static func area_icon(area: Dictionary) -> String:
	var icon := str(area.get("icon", "")).strip_edges()
	if not icon.is_empty():
		return icon
	return str(area_category(str(area.get("category", "building"))).get("icon", "🏠"))

func get_areas(map_data: Dictionary) -> Array:
	var areas = map_data.get("areas", [])
	return areas if areas is Array else []

func get_area(map_data: Dictionary, area_id: String) -> Dictionary:
	for area_variant in get_areas(map_data):
		if str((area_variant as Dictionary).get("id", "")) == area_id:
			return area_variant
	return {}

## Lieu dont l'emprise contient la position grille donnée (le plus petit gagne,
## pour qu'un lieu imbriqué l'emporte sur celui qui le contient).
func get_area_at(map_data: Dictionary, gx: float, gy: float) -> Dictionary:
	var best: Dictionary = {}
	var best_size := INF
	for area_variant in get_areas(map_data):
		var area: Dictionary = area_variant
		var half_w := float(area.get("w", 2.0)) * 0.5
		var half_h := float(area.get("h", 2.0)) * 0.5
		var cx := float(area.get("x", 0.0))
		var cy := float(area.get("y", 0.0))
		var inside := false
		if str(area.get("shape", "rect")) == "circle":
			inside = Vector2(gx - cx, gy - cy).length() <= maxf(half_w, half_h)
		else:
			inside = absf(gx - cx) <= half_w and absf(gy - cy) <= half_h
		if not inside:
			continue
		var size := half_w * half_h
		if size < best_size:
			best_size = size
			best = area
	return best

## Crée la carte enfant d'un lieu et la relie dans les deux sens.
## Renvoie la carte créée (ou l'existante si le lieu en avait déjà une).
func create_child_map_for_area(parent_map_id: String, area_id: String, grid_w: int = 24, grid_h: int = 18) -> Dictionary:
	var parent := get_by_id(parent_map_id)
	if parent.is_empty():
		return {}
	var area := get_area(parent, area_id)
	if area.is_empty():
		return {}
	var existing := str(area.get("targetMapId", ""))
	if not existing.is_empty():
		var already := get_by_id(existing)
		if not already.is_empty():
			return already
	var title := str(area.get("label", "Lieu")).strip_edges()
	if title.is_empty():
		title = "Lieu"
	var child := create_complex_map(
		title,
		str(parent.get("roster", "general")),
		"local",
		grid_w, grid_h
	)
	child["parentMapId"] = parent_map_id
	child["scenarioId"] = str(parent.get("scenarioId", ""))
	update_map(child)
	# Le lieu pointe désormais vers sa carte.
	for i in range(maps.size()):
		if maps[i].get("id") != parent_map_id:
			continue
		var parent_map: Dictionary = ensure_map_schema(maps[i])
		var areas: Array = parent_map.get("areas", [])
		for area_entry_variant in areas:
			var area_entry: Dictionary = area_entry_variant
			if str(area_entry.get("id", "")) == area_id:
				area_entry["targetMapId"] = str(child.get("id", ""))
		parent_map["areas"] = areas
		maps[i] = parent_map
		save_maps()
		break
	return child

## Chaîne des cartes parentes, de la racine jusqu'à celle-ci (fil d'Ariane).
func get_map_breadcrumb(map_id: String) -> Array:
	var chain: Array = []
	var current := map_id
	var guard := 0
	while not current.is_empty() and guard < 16:
		var map_def := get_by_id(current)
		if map_def.is_empty():
			break
		chain.push_front({"id": current, "title": str(map_def.get("title", "Carte"))})
		current = str(map_def.get("parentMapId", ""))
		guard += 1
	return chain

func get_child_maps(map_id: String) -> Array:
	var out: Array = []
	for m in maps:
		if str(m.get("parentMapId", "")) == map_id:
			out.append(m)
	return out

func import_background_image(map_id: String, source_path: String) -> String:
	if map_id.is_empty() or source_path.is_empty():
		return ""
	if not FileAccess.file_exists(source_path):
		push_warning("Image introuvable : %s" % source_path)
		return ""
	DirAccess.make_dir_recursive_absolute(MAP_ASSETS_DIR)
	var ext := source_path.get_extension().to_lower()
	if ext.is_empty():
		ext = "png"
	var dest := "%s%s.%s" % [MAP_ASSETS_DIR, map_id, ext]
	var src := FileAccess.open(source_path, FileAccess.READ)
	if not src:
		return ""
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if not dst:
		return ""
	dst.store_buffer(src.get_buffer(src.get_length()))
	for i in range(maps.size()):
		if maps[i].get("id") == map_id:
			maps[i]["backgroundImage"] = dest
			maps[i]["renderMode"] = RENDER_MODE_COMPLEX
			maps[i]["schemaVersion"] = SCHEMA_VERSION
			save_maps()
			return dest
	return dest

const TOKEN_ASSETS_DIR := "user://map_assets/tokens/"

## Importe un portrait de token et renvoie son chemin dans `user://`.
## Les avatars sont partagés entre cartes : ils sont nommés d'après leur source.
func import_token_image(source_path: String) -> String:
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return ""
	DirAccess.make_dir_recursive_absolute(TOKEN_ASSETS_DIR)
	var ext := source_path.get_extension().to_lower()
	if ext.is_empty():
		ext = "png"
	var base := source_path.get_file().get_basename().to_lower()
	var safe := ""
	for i in range(base.length()):
		var c := base[i]
		safe += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" else "_"
	if safe.is_empty():
		safe = "token"
	var dest := "%s%s-%d.%s" % [TOKEN_ASSETS_DIR, safe, Time.get_unix_time_from_system(), ext]
	var src := FileAccess.open(source_path, FileAccess.READ)
	if src == null:
		return ""
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		return ""
	dst.store_buffer(src.get_buffer(src.get_length()))
	return dest

## Liste les portraits déjà importés, pour la bibliothèque de l'éditeur.
func list_token_images() -> Array:
	var out: Array = []
	var dir := DirAccess.open(TOKEN_ASSETS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			out.append(TOKEN_ASSETS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out

## Charge un portrait et le découpe en disque, prêt à coiffer un token.
## `border` teinte l'anneau extérieur (couleur du personnage).
func load_token_portrait(path: String, border: Color = Color(0.15, 0.12, 0.1), size: int = 160) -> Texture2D:
	var img := _load_rgba_image(path)
	if img == null:
		return null
	# Cadre carré centré (meilleur pour les portraits en pied).
	var side := mini(img.get_width(), img.get_height())
	var ox := (img.get_width() - side) / 2
	var oy := maxi(0, (img.get_height() - side) / 5)  # un peu vers le haut (visage)
	img = img.get_region(Rect2i(ox, oy, side, side))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > 0.86:
				img.set_pixel(x, y, border)
	return ImageTexture.create_from_image(img)

## Découpe en pied pour le diorama. Si le PNG a déjà de l'alpha, on le garde
## (évite de percer les habits sombres). Sinon détourage du fond depuis les bords.
func load_token_cutout(path: String, max_height: int = 256) -> Texture2D:
	var img := _load_rgba_image(path)
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var clear_n := 0
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a < 0.05:
				clear_n += 1
	# Déjà détouré (fond transparent) → ne pas flood-fill les pixels sombres du perso.
	if clear_n < int(w * h * 0.05):
		_knockout_edge_background(img, 0.045)
	var scale := float(max_height) / float(maxi(1, h))
	var new_w := maxi(1, int(round(float(w) * scale)))
	var new_h := max_height
	img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)
	_harden_cutout_alpha(img, 0.40)
	return ImageTexture.create_from_image(img)

## Opaque ou transparent — jamais semi-transparent (évite le fantôme sur la carte).
func _harden_cutout_alpha(img: Image, keep_threshold: float = 0.4) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a >= keep_threshold:
				c.a = 1.0
				img.set_pixel(x, y, c)
			elif c.a > 0.02 and (c.r + c.g + c.b) > 0.08:
				# Anti-alias / trou sombre du perso → opaque, pas transparent.
				c.a = 1.0
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	_fill_cutout_interior_holes(img)

## Bouche les trous intérieurs : tout transparent non relié aux bords = trou dans le perso.
func _fill_cutout_interior_holes(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 3 or h < 3:
		return
	var outside := PackedByteArray()
	outside.resize(w * h)
	outside.fill(0)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if outside[idx] != 0:
			continue
		if img.get_pixel(p.x, p.y).a >= 0.5:
			continue
		outside[idx] = 1
		queue.append(Vector2i(p.x + 1, p.y))
		queue.append(Vector2i(p.x - 1, p.y))
		queue.append(Vector2i(p.x, p.y + 1))
		queue.append(Vector2i(p.x, p.y - 1))
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if outside[idx] != 0:
				continue
			if img.get_pixel(x, y).a >= 0.5:
				continue
			# Trou intérieur : moyenne des voisins opaques.
			var op := 0
			var ar := 0.0
			var ag := 0.0
			var ab := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var n := img.get_pixel(nx, ny)
					if n.a < 0.5:
						continue
					op += 1
					ar += n.r
					ag += n.g
					ab += n.b
			if op > 0:
				img.set_pixel(x, y, Color(ar / float(op), ag / float(op), ab / float(op), 1.0))
			else:
				img.set_pixel(x, y, Color(0.15, 0.12, 0.1, 1.0))

## Remplit en transparent uniquement le fond sombre relié aux bords de l'image.
func _knockout_edge_background(img: Image, threshold: float = 0.12) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		if c.a < 0.05:
			continue
		if c.r > threshold or c.g > threshold or c.b > threshold:
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		queue.append(Vector2i(p.x + 1, p.y))
		queue.append(Vector2i(p.x - 1, p.y))
		queue.append(Vector2i(p.x, p.y + 1))
		queue.append(Vector2i(p.x, p.y - 1))

func _load_rgba_image(path: String) -> Image:
	var raw := path.strip_edges()
	if raw.is_empty():
		return null
	var resolved := raw
	if raw.begins_with("res://") or raw.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(raw)
	var img := Image.new()
	if img.load(resolved) != OK:
		# Fallback : texture importée Godot.
		if raw.begins_with("res://") and ResourceLoader.exists(raw):
			var tex = load(raw)
			if tex is Texture2D:
				img = (tex as Texture2D).get_image()
				if img == null:
					return null
			else:
				return null
		else:
			return null
	img.convert(Image.FORMAT_RGBA8)
	return img

func get_image_pixel_size(source_path: String) -> Vector2i:
	var img := _load_rgba_image(source_path)
	if img == null:
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())

func suggest_cells_from_image(source_path: String, grid_px: int = 70) -> Vector2i:
	var px := get_image_pixel_size(source_path)
	if px == Vector2i.ZERO:
		return Vector2i(20, 14)
	var gs := maxi(20, grid_px)
	return Vector2i(clampi(int(roundf(float(px.x) / float(gs))), 4, 96), clampi(int(roundf(float(px.y) / float(gs))), 4, 96))

func clear_background_image(map_id: String) -> void:
	for i in range(maps.size()):
		if maps[i].get("id") == map_id:
			maps[i]["backgroundImage"] = ""
			save_maps()
			return

func import_elevation_overlay(map_id: String, source_path: String) -> String:
	if map_id.is_empty() or source_path.is_empty():
		return ""
	if not FileAccess.file_exists(source_path):
		return ""
	DirAccess.make_dir_recursive_absolute(MAP_ASSETS_DIR)
	var ext := source_path.get_extension().to_lower()
	if ext.is_empty():
		ext = "png"
	var dest := "%s%s-elev-%d.%s" % [MAP_ASSETS_DIR, map_id, Time.get_unix_time_from_system(), ext]
	var src := FileAccess.open(source_path, FileAccess.READ)
	if not src:
		return ""
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if not dst:
		return ""
	dst.store_buffer(src.get_buffer(src.get_length()))
	for i in range(maps.size()):
		if maps[i].get("id") == map_id:
			var map: Dictionary = ensure_map_schema(maps[i])
			if not map.has("elevationLayers"):
				map["elevationLayers"] = []
			var layers: Array = map.get("elevationLayers", [])
			layers.append({
				"image": dest,
				"opacity": 0.92,
				"elevation": 0.18,
				"offset": {"x": 0, "y": 0},
				"mapWidth": int(map.get("width", 16)),
				"mapHeight": int(map.get("height", 12)),
			})
			map["elevationLayers"] = layers
			map["renderMode"] = RENDER_MODE_COMPLEX
			maps[i] = map
			save_maps()
			return dest
	return dest

func load_background_texture(map_data: Dictionary) -> Texture2D:
	var path: String = str(map_data.get("backgroundImage", "")).strip_edges()
	if path.is_empty():
		return null
	if not FileAccess.file_exists(path) and path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

func generate_tile_texture(map_data: Dictionary, grid_cfg: Dictionary = {}) -> Texture2D:
	var cfg := grid_cfg if not grid_cfg.is_empty() else get_grid_config(map_data)
	var gs := int(cfg.get("size", 70))
	var w: int = maxi(1, int(map_data.get("width", 16)))
	var h: int = maxi(1, int(map_data.get("height", 12)))
	var img := Image.create(w * gs, h * gs, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			var tile_id: String = "floor"
			var tiles: Array = map_data.get("tiles", [])
			if idx < tiles.size():
				tile_id = str(tiles[idx])
			var col := get_tile_color(map_data, tile_id)
			for py in range(gs):
				for px in range(gs):
					img.set_pixel(x * gs + px, y * gs + py, col)
	return ImageTexture.create_from_image(img)

func get_effect_preset_list() -> Array:
	return ["fire", "smoke", "magic", "rain"]

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
	var map := ensure_map_schema({
		"id": generate_id("map"),
		"title": title,
		"description": "",
		"roster": roster,
		"mapKind": map_kind,
		"renderMode": RENDER_MODE_SIMPLE,
		"scenarioId": "",
		"width": w,
		"height": h,
		"tiles": tiles,
		"markers": [],
		"locationLinks": [],
	})
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
	map_data = ensure_map_schema(map_data)
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
