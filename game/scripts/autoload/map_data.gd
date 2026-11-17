extends Node

signal maps_updated

const MAPS_PATH := "user://maps.json"
const MAP_ASSETS_DIR := "user://map_assets/"
const SCHEMA_VERSION := 5
## Schéma de carte (phase 2.8) : normalisation pure dans `core/maps/map_schema.gd`.
const MapSchema := preload("res://scripts/core/maps/map_schema.gd")
const DemoCatalog := preload("res://scripts/core/maps/demo_catalog.gd")
const RENDER_MODE_SIMPLE = MapSchema.RENDER_MODE_SIMPLE
const RENDER_MODE_COMPLEX := "complex"
## Type de sol d'une carte 2.5D : vrai terrain 3D (heightfield) ou fond illustré plat.
const GROUND_TERRAIN3D = MapSchema.GROUND_TERRAIN3D
const GROUND_ILLUSTRATED = MapSchema.GROUND_ILLUSTRATED
## Matières de sol peintes (`terrainMaterials`, une par case) : herbe, terre,
## pierre, neige, sable. Mêmes valeurs que le document et le calque sol.
const MATERIAL_GRASS := 0
const MATERIAL_DIRT := 1
const MATERIAL_STONE := 2
const MATERIAL_SNOW := 3
const MATERIAL_SAND := 4
const MATERIAL_IDS := [MATERIAL_GRASS, MATERIAL_DIRT, MATERIAL_STONE, MATERIAL_SNOW, MATERIAL_SAND]
const DEMO_MAP_IDS = DemoCatalog.DEMO_MAP_IDS
## Carte démo « Cité des Saules » : mêmes dimensions et graine que la scène de
## debug `cite_boot.gd`, mais matérialisée dans le catalogue du Hub.
const CITE_DEMO_ID = DemoCatalog.CITE_DEMO_ID
const CITE_DEMO_SEED = DemoCatalog.CITE_DEMO_SEED
const CITE_DEMO_WIDTH = DemoCatalog.CITE_DEMO_WIDTH
const CITE_DEMO_HEIGHT = DemoCatalog.CITE_DEMO_HEIGHT
const ProceduralCityScript := preload("res://scripts/maps/construction/procedural_city.gd")
## Traitement d'image (phase 2.8) : cutout alpha, nuit procédurale, vignettes.
const CutoutScript := preload("res://scripts/core/image/cutout.gd")
const NightTextureScript := preload("res://scripts/core/image/night_texture.gd")
const ThumbnailScript := preload("res://scripts/core/image/thumbnail.gd")
const DEFAULT_GRID_CONFIG = MapSchema.DEFAULT_GRID_CONFIG
const LIGHTING_PRESET_ORDER := ["jour", "matin", "coucher", "nuit", "donjon", "tiny_glade", "performance"]
## `atmosFog` : opt-in de la brume atmosphérique (profondeur + hauteur) du
## moteur 3D. DÉFAUT NEUTRE : clé absente = rendu d'origine (brume
## exponentielle du preset uniquement) — tiny_glade garde ainsi sa brume
## légère réglée à la main (exponentielle + volumétrique).
const LIGHTING_PRESETS := {
	"jour": {
		"label": "☀ Jour clair", "sunColor": "#fff1d8", "sunEnergy": 1.25,
		"sunAngle": -58.0, "sunYaw": 38.0, "ambientColor": "#9fb4d4",
		"ambientEnergy": 0.58, "background": "#10151c", "exposure": 1.0,
		"fogDensity": 0.0, "glow": 0.28, "atmosFog": true,
	},
	"matin": {
		"label": "🌅 Matin", "sunColor": "#ffd9a8", "sunEnergy": 1.05,
		"sunAngle": -46.0, "sunYaw": -58.0, "ambientColor": "#aebfd8",
		"ambientEnergy": 0.50, "background": "#151b22", "exposure": 1.02,
		"fogDensity": 0.004, "glow": 0.32, "atmosFog": true,
	},
	"coucher": {
		"label": "🌇 Coucher de soleil", "sunColor": "#ffab5f", "sunEnergy": 1.2,
		"sunAngle": -32.0, "sunYaw": -98.0, "ambientColor": "#7887b0",
		"ambientEnergy": 0.40, "background": "#1b1418", "exposure": 1.04,
		"fogDensity": 0.008, "glow": 0.42, "atmosFog": true,
	},
	"nuit": {
		"label": "🌙 Nuit claire", "sunColor": "#8ba8d8", "sunEnergy": 0.34,
		"sunAngle": -52.0, "sunYaw": -35.0, "ambientColor": "#2d3854",
		"ambientEnergy": 0.26, "background": "#070a12", "exposure": 1.08,
		"fogDensity": 0.012, "glow": 0.55, "atmosFog": true,
	},
	"donjon": {
		"label": "🕯 Donjon", "sunColor": "#aebcff", "sunEnergy": 0.22,
		"sunAngle": -62.0, "sunYaw": 15.0, "ambientColor": "#171b2a",
		"ambientEnergy": 0.20, "background": "#05060a", "exposure": 1.12,
		"fogDensity": 0.02, "glow": 0.65, "atmosFog": true,
	},
	"tiny_glade": {
		# Direction artistique Tiny Glade : ciel pastel, soleil chaud et doux,
		# ambiance lumineuse, horizon crème, brume légère de profondeur.
		"label": "🌤 Tiny Glade", "sunColor": "#ffe3b8", "sunEnergy": 1.75,
		"sunAngle": -42.0, "sunYaw": -52.0, "ambientColor": "#cfe6ff",
		"ambientEnergy": 0.52, "background": "#bfe0ef", "exposure": 0.90,
		"fogDensity": 0.0022, "glow": 0.42,
		"sky": true, "skyTop": "#9ccbe8", "skyHorizon": "#ffe6c2",
		"skyGroundBottom": "#efe6d6", "sunGlow": 1.1, "skyEnergy": 1.0,
		"fogSkyAffect": 0.20, "fogColor": "#f5e8d6", "shadowBlur": 1.7,
		"backdropCenter": "#d6e2ad", "backdropMid": "#b8cfa3",
		"backdropEdge": "#f2ead8",
		"saturation": 1.33, "brightness": 0.98, "contrast": 1.20,
		# Rendu avancé : GI dynamique, réflexions, brume volumétrique, ambiante
		# de ciel, ombres à pénombres douces (palliatif aux assets low-poly).
		"gi": true, "giEnergy": 0.9, "ssil": true, "ssilIntensity": 0.9,
		"ssr": true, "volumetricFog": true, "volumetricDensity": 0.006,
		"volumetricColor": "#fff1de", "ambientFromSky": true,
		"skyContribution": 0.7, "aerial": 0.35, "sunScatter": 0.18,
		"shadowAngular": 1.3, "fogLightEnergy": 1.0,
	},
	"performance": {
		# Léger : désactive GI/SSR/SSIL/brume volumétrique (coûteux sur GPU),
		# conserve une lumière propre et un léger glow. Pour les grosses cartes.
		"label": "⚡ Performance", "sunColor": "#fff1d8", "sunEnergy": 1.12,
		"sunAngle": -58.0, "sunYaw": 38.0, "ambientColor": "#aebed2",
		"ambientEnergy": 0.56, "background": "#10151c", "exposure": 1.0,
		"fogDensity": 0.0, "glow": 0.20, "atmosFog": true,
		"gi": false, "ssil": false, "ssr": false, "volumetricFog": false,
		"saturation": 1.0, "brightness": 1.02, "contrast": 1.02,
	},
}
const DEFAULT_LIGHTING_CONFIG = MapSchema.DEFAULT_LIGHTING_CONFIG
const DEFAULT_PLAY_DEFAULTS = MapSchema.DEFAULT_PLAY_DEFAULTS
## Catégories de lieux, reprises telles quelles dans la légende de la carte.
## Elles correspondent aux pictogrammes des cartes de village illustrées.
const AREA_CATEGORIES := [
	{"id": "building", "label": "Bâtiment", "icon": "🏠"},
	{"id": "shop", "label": "Commerce / Service", "icon": "💰"},
	{"id": "poi", "label": "Lieu d'intérêt", "icon": "⭐"},
	{"id": "exit", "label": "Sortie", "icon": "➡"},
	{"id": "nature", "label": "Nature", "icon": "🌲"},
]

const DEFAULT_MEASURE = MapSchema.DEFAULT_MEASURE
const DEFAULT_LAYERS = MapSchema.DEFAULT_LAYERS
const PERSPECTIVE_TOPDOWN = MapSchema.PERSPECTIVE_TOPDOWN
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
	var demos := _build_demo_catalog()
	var demo_ids: Dictionary = {}
	for m in demos:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var did := str(m.get("id", ""))
		if not did.is_empty():
			demo_ids[did] = true

	var merged: Array = []
	for m in demos:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var demo_map: Dictionary = ensure_map_schema((m as Dictionary).duplicate(true))
		demo_map["status"] = "published"
		merged.append(demo_map)

	var saved = _load_json(MAPS_PATH)
	if saved is Array:
		for entry in saved:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var mid := str(entry.get("id", ""))
			if mid.is_empty() or demo_ids.has(mid):
				continue
			var user_map: Dictionary = ensure_map_schema((entry as Dictionary).duplicate(true))
			if str(user_map.get("status", "")).is_empty():
				user_map["status"] = "draft"
			merged.append(user_map)

	maps = merged
	save_maps()

func save_maps() -> void:
	_save_json(MAPS_PATH, maps)
	maps_updated.emit()

func is_demo_map_id(map_id: String) -> bool:
	return DEMO_MAP_IDS.has(map_id)

func is_catalog_map(map_data: Dictionary) -> bool:
	var mid := str(map_data.get("id", ""))
	if mid.is_empty():
		return false
	if is_demo_map_id(mid):
		return true
	return str(map_data.get("status", "")) == "published"

func is_draft_map(map_data: Dictionary) -> bool:
	var mid := str(map_data.get("id", ""))
	if mid.is_empty() or is_demo_map_id(mid):
		return false
	return str(map_data.get("status", "draft")) != "published"

func get_draft_maps() -> Array:
	var result: Array = []
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if is_draft_map(m):
			result.append(m)
	return result

func publish_map(map_id: String) -> bool:
	if map_id.is_empty() or is_demo_map_id(map_id):
		return false
	for i in range(maps.size()):
		if str(maps[i].get("id", "")) != map_id:
			continue
		maps[i]["status"] = "published"
		save_maps()
		return true
	return false

func unpublish_map(map_id: String) -> bool:
	if map_id.is_empty() or is_demo_map_id(map_id):
		return false
	for i in range(maps.size()):
		if str(maps[i].get("id", "")) != map_id:
			continue
		maps[i]["status"] = "draft"
		save_maps()
		return true
	return false

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

## Cartes pouvant être liées à une scène : d'abord celles du scénario, puis les orphelines du roster.
func list_linkable_maps_for_scenario(scenario_id: String, roster: String = "general") -> Array:
	var linked: Array = []
	var orphans: Array = []
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not str(m.get("parentMapId", "")).is_empty():
			continue
		if not roster.is_empty() and str(m.get("roster", "general")) != roster:
			continue
		var sid := str(m.get("scenarioId", ""))
		if not scenario_id.is_empty() and sid == scenario_id:
			linked.append(m)
		elif sid.is_empty():
			orphans.append(m)
	var sorter := func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("title", "")).to_lower() < str(b.get("title", "")).to_lower()
	linked.sort_custom(sorter)
	orphans.sort_custom(sorter)
	linked.append_array(orphans)
	return linked

func get_map_ids_for_scenario(scenario_id: String, quest_format: String = "") -> Array:
	var ids: Array = []
	for m in maps:
		if m.get("scenarioId") == scenario_id:
			ids.append(m.get("id"))
	if ids.is_empty():
		if scenario_id == "demo-valbois":
			if get_by_id("demo-valbois-village").has("id"):
				ids.append("demo-valbois-village")
		elif scenario_id == "demo-crypte":
			if get_by_id("demo-crypte-brumeval").has("id"):
				ids.append("demo-crypte-brumeval")
		elif quest_format == "investigation" or scenario_id.begins_with("inv-"):
			if get_by_id("demo-quartier-serpent").has("id"):
				ids.append("demo-quartier-serpent")
		else:
			if get_by_id("demo-crypte-brumeval").has("id"):
				ids.append("demo-crypte-brumeval")
	# Les cartes enfants (Place du Marché) se jouent via les lieux, pas la liste.
	var filtered: Array = []
	for mid in ids:
		var m := get_by_id(str(mid))
		if m.is_empty():
			continue
		if not str(m.get("parentMapId", "")).is_empty():
			continue
		filtered.append(mid)
	return filtered

func get_setup_map_pool(scenario_id: String, quest_format: String) -> Array:
	var pool: Array = []
	var is_investigation := quest_format == "investigation" or scenario_id.begins_with("inv-")
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not is_catalog_map(m):
			continue
		if not str(m.get("parentMapId", "")).is_empty():
			continue
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
		if not scenario_id.is_empty() and linked_id != scenario_id:
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

## Texture de sol livrée — vide si le PNG est un placeholder trop léger.
func get_tile_texture_path(tile_id: String) -> String:
	var paths := {
		"grass": "res://data/props/ground/herbe.png",
		"forest": "res://data/props/ground/herbe.png",
		"road": "res://data/props/ground/sentier_boueux.png",
		"floor": "res://data/props/ground/dalles_pierre.png",
		"stone": "res://data/props/ground/dalles_pierre.png",
		"water": "res://data/props/ground/eau_mare.png",
		"sand": "res://data/props/ground/sentier_boueux.png",
		"plains": "res://data/props/ground/herbe.png",
		"hills": "res://data/props/ground/herbe.png",
		"swamp": "res://data/props/ground/eau_mare.png",
		"coast": "res://data/props/ground/sentier_boueux.png",
	}
	var path := str(paths.get(tile_id, ""))
	if path.is_empty():
		return ""
	return path if is_usable_sprite(path) else ""

func get_marker_sprite_path(marker_type: String) -> String:
	var paths := {
		"exit": "res://data/props/objects/porte_bois.png",
		"npc": "res://data/props/characters/paysan_valbois.png",
		"poi": "res://data/props/objects/panneau_bois.png",
		"treasure": "res://data/props/furniture/coffre_fer.png",
		"camp": "res://data/props/nature/tas_foin.png",
		"city": "res://data/props/buildings/maison_maire.png",
		"capital": "res://data/props/buildings/tour.png",
		"dungeon": "res://data/props/buildings/temple_pierre.png",
		"ruin": "res://data/props/buildings/tour.png",
		"quest": "res://data/props/objects/panneau_bois.png",
	}
	var path := str(paths.get(marker_type, ""))
	if path.is_empty():
		return ""
	return path if is_usable_sprite(path) else ""

func get_character_sprite_path(role: String, label: String = "") -> String:
	var hay := ("%s %s" % [role, label]).to_lower()
	var path := ""
	if hay.contains("garde") or hay.contains("milice") or hay.contains("sentinelle") \
			or hay.contains("capitaine") or hay.contains("veilleur"):
		path = "res://data/props/characters/garde_valbois.png"
	elif hay.contains("hallebarde"):
		path = "res://data/props/characters/garde_hallebarde.png"
	elif hay.contains("marchand") or hay.contains("herboriste"):
		path = "res://data/props/characters/marchande.png"
	elif hay.contains("forge"):
		path = "res://data/props/characters/forgeron.png"
	elif hay.contains("villageois") or hay.contains("paysan"):
		var villager := "res://data/props/characters/villageois.png"
		if is_usable_sprite(villager):
			path = villager
		else:
			path = "res://data/props/characters/paysan_valbois.png"
	# Inconnu : aucun sprite — mieux qu'un paysan générique.
	return path if (not path.is_empty() and is_usable_sprite(path)) else ""

## Ignore les PNG procéduraux minuscules (placeholders) au profit d'une couleur.
func is_usable_sprite(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	var abs_path := path
	if path.begins_with("res://"):
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				var tex := res as Texture2D
				return tex.get_width() >= 48 and tex.get_height() >= 48
		abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return false
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return false
	var n := f.get_length()
	f.close()
	return n >= 2048

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

func get_maps_by_category(category: String, library_tab: String = "catalog") -> Array:
	var result: Array = []
	for m in maps:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not str(m.get("parentMapId", "")).is_empty():
			continue
		if library_tab == "draft" and not is_draft_map(m):
			continue
		elif library_tab == "catalog" and not is_catalog_map(m):
			continue
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

## Type de sol : `terrain3d` (heightfield réel) ou `illustrated` (fond peint plat).
## Sans clé : une carte avec fond illustré reste en `illustrated` (compatibilité),
## sinon on prend le vrai terrain 3D.
func get_ground_mode(map_data: Dictionary) -> String:
	var mode := str(map_data.get("groundMode", ""))
	if mode == GROUND_TERRAIN3D or mode == GROUND_ILLUSTRATED:
		return mode
	if not str(map_data.get("backgroundImage", "")).strip_edges().is_empty():
		return GROUND_ILLUSTRATED
	return GROUND_TERRAIN3D

## Normalise un ID de matière de sol : 0..4 (herbe → sable).
func normalize_terrain_material(value: int) -> int:
	return clampi(value, MATERIAL_GRASS, MATERIAL_SAND)

## Libellé d'une matière de sol (UI / aperçus).
func terrain_material_label(material: int) -> String:
	match normalize_terrain_material(material):
		MATERIAL_DIRT:
			return "Terre / chemin"
		MATERIAL_STONE:
			return "Pierre / pavé"
		MATERIAL_SNOW:
			return "Neige"
		MATERIAL_SAND:
			return "Sable"
		_:
			return "Herbe"

## Couleur d'aperçu d'une matière de sol (mini-carte, plans de zones).
func terrain_material_color(material: int) -> Color:
	match normalize_terrain_material(material):
		MATERIAL_DIRT:
			return Color(0.46, 0.36, 0.25)
		MATERIAL_STONE:
			return Color(0.55, 0.52, 0.46)
		MATERIAL_SNOW:
			return Color(0.88, 0.91, 0.96)
		MATERIAL_SAND:
			return Color(0.86, 0.76, 0.56)
		_:
			return Color(0.33, 0.45, 0.25)

func get_grid_config(map_data: Dictionary) -> Dictionary:
	var cfg: Dictionary = DEFAULT_GRID_CONFIG.duplicate(true)
	if map_data.get("grid") is Dictionary:
		cfg.merge(map_data["grid"], true)
	return cfg

func get_lighting_config(map_data: Dictionary) -> Dictionary:
	var cfg: Dictionary = DEFAULT_LIGHTING_CONFIG.duplicate(true)
	if map_data.get("lighting") is Dictionary:
		cfg.merge(map_data["lighting"], true)
	if not cfg.has("sources") or typeof(cfg["sources"]) != TYPE_ARRAY:
		cfg["sources"] = []
	if not cfg.has("nightMode"):
		cfg["nightMode"] = false
	if not cfg.has("nightAmbient"):
		cfg["nightAmbient"] = 0.22
	return cfg

func is_night_mode(map_data: Dictionary) -> bool:
	return bool(get_lighting_config(map_data).get("nightMode", false))

static func get_lighting_preset(preset_id: String) -> Dictionary:
	if LIGHTING_PRESETS.has(preset_id):
		return LIGHTING_PRESETS[preset_id]
	return LIGHTING_PRESETS["jour"]

## Chemin nuit explicite, sinon `<stem>_night.png` à côté du fond jour.
func resolve_night_image_path(map_data: Dictionary) -> String:
	var explicit := str(map_data.get("backgroundImageNight", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var day := str(map_data.get("backgroundImage", "")).strip_edges()
	if day.is_empty():
		return ""
	var dot := day.rfind(".")
	if dot <= 0:
		return day + "_night.png"
	return day.substr(0, dot) + "_night" + day.substr(dot)

func night_image_exists(map_data: Dictionary) -> bool:
	var path := resolve_night_image_path(map_data)
	if path.is_empty():
		return false
	if path.begins_with("res://") or path.begins_with("user://"):
		return FileAccess.file_exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))
	return FileAccess.file_exists(path)

## Texture nuit : fichier dédié, sinon assombrissement procédural du jour.
## Façade : implémentation dans `core/image/night_texture.gd` (phase 2.8).
func load_night_texture(map_data: Dictionary) -> Texture2D:
	var night_path := resolve_night_image_path(map_data)
	var night_ok := not night_path.is_empty() and night_image_exists(map_data)
	var day_path := str(map_data.get("backgroundImage", "")).strip_edges()
	return NightTextureScript.load_texture(day_path, night_path if night_ok else "")

## Assombrit / désature une image jour (fallback offline sans Gemini).
## Façade : implémentation dans `core/image/night_texture.gd`.
func make_procedural_night_image(day: Image) -> Image:
	return NightTextureScript.make_procedural_night_image(day)

## Cases dans le rayon d'une lumière (disque grille, pour stamp lightRevealed).
func light_reveal_cells(source: Dictionary, map_w: int = 0, map_h: int = 0) -> Array:
	var cx := int(roundf(float(source.get("x", 0.0))))
	var cy := int(roundf(float(source.get("y", 0.0))))
	var radius := maxf(0.5, float(source.get("radius", 3.0)))
	var r_i := int(ceil(radius))
	var cells: Array = []
	for dy in range(-r_i, r_i + 1):
		for dx in range(-r_i, r_i + 1):
			if float(dx * dx + dy * dy) > radius * radius + 0.01:
				continue
			var x := cx + dx
			var y := cy + dy
			if map_w > 0 and (x < 0 or x >= map_w):
				continue
			if map_h > 0 and (y < 0 or y >= map_h):
				continue
			cells.append("%d,%d" % [x, y])
	return cells

func get_perspective(map_data: Dictionary) -> String:
	var p := str(map_data.get("perspective", PERSPECTIVE_TOPDOWN))
	if p in [PERSPECTIVE_ISOMETRIC, PERSPECTIVE_TILT]:
		return p
	return PERSPECTIVE_TOPDOWN

func get_elevation_layers(map_data: Dictionary) -> Array:
	var layers = map_data.get("elevationLayers", [])
	return layers if layers is Array else []

func ensure_map_schema(map_data: Dictionary) -> Dictionary:
	return MapSchema.ensure_map_schema(
		map_data, is_world_map(map_data), is_demo_map_id(str(map_data.get("id", ""))))

func get_play_defaults(map_data: Dictionary) -> Dictionary:
	return MapSchema.get_play_defaults(
		map_data, is_world_map(map_data), is_demo_map_id(str(map_data.get("id", ""))))

func ensure_play_defaults(map_data: Dictionary) -> Dictionary:
	return MapSchema.ensure_play_defaults(
		map_data, is_world_map(map_data), is_demo_map_id(str(map_data.get("id", ""))))

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
		"renderStyle": "2.5d",
		"scenarioId": "",
		"status": "draft",
		"width": grid_cells_w,
		"height": grid_cells_h,
		"tiles": tiles,
		"markers": [],
		"locationLinks": [],
		"backgroundImage": "",
		"backgroundImageNight": "",
		"groundMode": GROUND_TERRAIN3D,
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
		if bool(area.get("hidden", false)):
			continue
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
func create_child_map_for_area(parent_map_id: String, area_id: String, grid_w: int = 24, grid_h: int = 18, render_mode: String = "") -> Dictionary:
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
	if render_mode.is_empty():
		render_mode = get_render_mode(parent)
	var child: Dictionary
	if render_mode == RENDER_MODE_COMPLEX:
		child = create_complex_map(
			title,
			str(parent.get("roster", "general")),
			"local",
			grid_w, grid_h
		)
	else:
		child = create_blank_map(title, str(parent.get("roster", "general")), "local")
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
## Façade : implémentation dans `core/image/thumbnail.gd` (phase 2.8).
func load_token_portrait(path: String, border: Color = Color(0.15, 0.12, 0.1), size: int = 160) -> Texture2D:
	return ThumbnailScript.make_token_portrait(path, border, size)

## Détourages déjà calculés, indexés par « chemin@hauteur ». Le découpage est
## une boucle par pixel : sans ce cache, chaque rendu de liste de groupe ou de
## journal le refaisait pour tous les portraits.
var _token_cutout_cache: Dictionary = {}

## Découpe en pied pour le diorama. Si le PNG a déjà de l'alpha, on le garde
## (évite de percer les habits sombres). Sinon détourage du fond depuis les bords.
func load_token_cutout(path: String, max_height: int = 256) -> Texture2D:
	var cache_key := "%s@%d" % [path, max_height]
	if _token_cutout_cache.has(cache_key):
		return _token_cutout_cache[cache_key]
	var tex := CutoutScript.build_token_cutout(path, max_height)
	_token_cutout_cache[cache_key] = tex
	return tex

func clear_token_cutout_cache() -> void:
	_token_cutout_cache.clear()

## Dimensions en pixels d'une image source (façade `core/image/thumbnail.gd`).
func get_image_pixel_size(source_path: String) -> Vector2i:
	return ThumbnailScript.image_pixel_size(source_path)

## Nombre de cases suggéré pour une grille de `grid_px` pixels (façade).
func suggest_cells_from_image(source_path: String, grid_px: int = 70) -> Vector2i:
	return ThumbnailScript.suggest_cells(source_path, grid_px)

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
	# Toujours le PNG source (user:// ou res://), jamais la CompressedTexture2D
	# importée — sinon detect_3d/compress peut dégrader l'illustration.
	# Façade : implémentation dans `core/image/cutout.gd` (phase 2.8).
	return CutoutScript.load_texture(path)

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
		"status": "draft",
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
	if map_id.is_empty() or is_demo_map_id(map_id):
		return
	maps = maps.filter(func(m): return m.get("id", "") != map_id)
	# Nettoie les références orphelines laissées par la carte supprimée.
	for map_variant in maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		var edges: Dictionary = map.get("edges", {}) if map.get("edges") is Dictionary else {}
		var changed := false
		for side in edges.keys():
			var edge = edges[side]
			if edge is Dictionary and str((edge as Dictionary).get("target", "")) == map_id:
				edges.erase(side)
				changed = true
		if changed:
			map["edges"] = edges
		var location_links = map.get("locationLinks", [])
		if location_links is Array:
			var kept: Array = []
			for link_variant in location_links:
				if link_variant is Dictionary and str((link_variant as Dictionary).get("targetMapId", "")) == map_id:
					continue
				kept.append(link_variant)
			if kept.size() != (location_links as Array).size():
				map["locationLinks"] = kept
		for area_variant in map.get("areas", []):
			if not area_variant is Dictionary:
				continue
			var area: Dictionary = area_variant
			if str(area.get("targetMapId", "")) == map_id:
				area["targetMapId"] = ""
	save_maps()

## Redimensionne une carte complexe (façon Dofus : zones de tailles libres).
## Contenu conservé au coin haut-gauche, objets/éléments clampés dans la carte.
func resize_complex_map(map_id: String, new_w: int, new_h: int) -> bool:
	var map: Dictionary = get_by_id(map_id)
	if map.is_empty():
		return false
	new_w = clampi(new_w, 3, 96)
	new_h = clampi(new_h, 3, 96)
	var old_w := int(map.get("width", 0))
	var old_h := int(map.get("height", 0))
	if old_w <= 0 or old_h <= 0 or (old_w == new_w and old_h == new_h):
		return false
	map["tiles"] = _resize_flat_array(map.get("tiles", []), old_w, old_h, new_w, new_h, "")
	map["terrainHeights"] = _resize_flat_array(map.get("terrainHeights", []), old_w, old_h, new_w, new_h, 0.0)
	map["terrainMaterials"] = _resize_flat_array(map.get("terrainMaterials", []), old_w, old_h, new_w, new_h, 0)
	_clamp_elements_2d(map.get("meshes", []), new_w, new_h)
	_clamp_elements_2d(map.get("props", []), new_w, new_h)
	_clamp_elements_2d(map.get("markers", []), new_w, new_h)
	# Lieux (areas) : clamp position et taille.
	for area_variant in map.get("areas", []):
		if not area_variant is Dictionary:
			continue
		var area: Dictionary = area_variant
		area["x"] = clampf(float(area.get("x", 0.0)), 0.0, float(new_w - 1))
		area["y"] = clampf(float(area.get("y", 0.0)), 0.0, float(new_h - 1))
		area["w"] = minf(float(area.get("w", 1.0)), float(new_w) - float(area["x"]))
		area["h"] = minf(float(area.get("h", 1.0)), float(new_h) - float(area["y"]))
	map["width"] = new_w
	map["height"] = new_h
	map["zoneW"] = new_w
	map["zoneH"] = new_h
	update_map(map)
	return true

func _resize_flat_array(raw, old_w: int, old_h: int, new_w: int, new_h: int, default_value) -> Array:
	var out: Array = []
	out.resize(new_w * new_h)
	out.fill(default_value)
	if not raw is Array:
		return out
	var copy_w := mini(old_w, new_w)
	var copy_h := mini(old_h, new_h)
	for y in range(copy_h):
		for x in range(copy_w):
			var src: int = y * old_w + x
			var dst: int = y * new_w + x
			if src < (raw as Array).size():
				out[dst] = (raw as Array)[src]
	return out

func _clamp_elements_2d(elements, new_w: int, new_h: int) -> void:
	if not elements is Array:
		return
	for elem_variant in elements:
		if not elem_variant is Dictionary:
			continue
		var elem: Dictionary = elem_variant
		var x := clampf(float(elem.get("x", 0.0)), 0.0, float(new_w - 1))
		var y := clampf(float(elem.get("y", 0.0)), 0.0, float(new_h - 1))
		elem["x"] = x
		elem["y"] = y
		if elem.has("w"):
			elem["w"] = minf(float(elem.get("w", 1.0)), float(new_w) - x)
		if elem.has("h"):
			elem["h"] = minf(float(elem.get("h", 1.0)), float(new_h) - y)

## Duplique une carte complexe (zone façon Dofus) : contenu copié, nouvel id,
## position décalée sur le plan monde, liens de bords réinitialisés.
func duplicate_complex_map(map_id: String, new_title: String = "", offset_x: int = 0, offset_y: int = 1) -> Dictionary:
	var src: Dictionary = get_by_id(map_id)
	if src.is_empty():
		return {}
	var copy: Dictionary = src.duplicate(true)
	copy["id"] = generate_id("map")
	copy["title"] = new_title if not new_title.is_empty() else "%s (copie)" % str(src.get("title", "Zone"))
	copy["zoneX"] = int(src.get("zoneX", 0)) + offset_x
	copy["zoneY"] = int(src.get("zoneY", 0)) + offset_y
	copy["edges"] = {}
	maps.append(copy)
	save_maps()
	return copy

## Écrit (ou retire si `target_id` est vide) un lien de bord manuel d'une zone.
func set_zone_edge(map_id: String, side: String, target_id: String, offset: int = 0) -> bool:
	if not side in ["north", "south", "east", "west"]:
		return false
	var map: Dictionary = get_by_id(map_id)
	if map.is_empty():
		return false
	if not target_id.is_empty() and get_by_id(target_id).is_empty():
		return false
	var edges: Dictionary = map.get("edges", {}) if map.get("edges") is Dictionary else {}
	if target_id.is_empty():
		edges.erase(side)
	else:
		edges[side] = {"target": target_id, "offset": int(offset)}
	map["edges"] = edges
	update_map(map)
	return true

## Rattache une carte existante à un monde de zones, à la position donnée.
func assign_map_to_world(map_id: String, world_id: String, zone_x: int, zone_y: int) -> bool:
	var map: Dictionary = get_by_id(map_id)
	if map.is_empty():
		return false
	map["worldId"] = world_id
	map["zoneX"] = int(zone_x)
	map["zoneY"] = int(zone_y)
	map["zoneW"] = int(map.get("width", 12))
	map["zoneH"] = int(map.get("height", 9))
	map["edges"] = {}
	update_map(map)
	return true

## Nom lisible d'un monde (worldTitle porté par ses zones), sinon son id.
func get_world_title(world_id: String) -> String:
	if world_id.is_empty():
		return ""
	for map_variant in maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("worldId", "")) != world_id:
			continue
		var title := str(map.get("worldTitle", "")).strip_edges()
		if not title.is_empty():
			return title
		return world_id
	return world_id

## Renomme un monde (écrit worldTitle sur toutes ses zones).
func set_world_title(world_id: String, title: String) -> bool:
	if world_id.is_empty():
		return false
	var clean := title.strip_edges()
	if clean.is_empty():
		return false
	var touched := false
	for map_variant in maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("worldId", "")) != world_id:
			continue
		map["worldTitle"] = clean
		touched = true
	if touched:
		save_maps()
	return touched

## Exporte toutes les zones d'un monde (cartes + liens) dans un bundle JSON-able.
func export_world_bundle(world_id: String) -> Dictionary:
	var zone_maps: Array = []
	for map_variant in maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("worldId", "")) != world_id:
			continue
		if str(map.get("renderMode", "")) != "complex":
			continue
		zone_maps.append(map.duplicate(true))
	return {
		"version": 1,
		"worldId": world_id,
		"worldTitle": get_world_title(world_id),
		"exportsAt": Time.get_unix_time_from_system(),
		"zones": zone_maps,
	}

## Importe un bundle de monde : recrée les zones avec de nouveaux ids et
## re-cible les liens internes. `target_world_id` vide → nouveau monde.
func import_world_bundle(bundle: Dictionary, target_world_id: String = "") -> Dictionary:
	var source_zones = bundle.get("zones", [])
	if typeof(source_zones) != TYPE_ARRAY or (source_zones as Array).is_empty():
		return {}
	var world_id := target_world_id.strip_edges()
	if world_id.is_empty():
		# Cible omise : nouveau monde indépendant (ne pas réutiliser l'id source).
		world_id = generate_id("world")
	# Conserve le nom du monde cible s'il existe, sinon celui du bundle importé.
	var target_exists := false
	for map_variant in maps:
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == world_id:
			target_exists = true
			break
	var world_title := get_world_title(world_id) if target_exists else str(bundle.get("worldTitle", "")).strip_edges()
	var id_map: Dictionary = {}
	var pending: Array = []
	for zone_variant in source_zones:
		if not zone_variant is Dictionary:
			continue
		var source: Dictionary = zone_variant
		var old_id := str(source.get("id", ""))
		var copy: Dictionary = source.duplicate(true)
		var new_id: String = generate_id("map")
		copy["id"] = new_id
		copy["worldId"] = world_id
		if not world_title.is_empty():
			copy["worldTitle"] = world_title
		copy["edges"] = {}
		if old_id.is_empty():
			old_id = new_id
		id_map[old_id] = new_id
		pending.append({"copy": copy, "source": source})
	# Second passage : liens remappés vers les nouvelles cartes.
	var imported_ids: Array = []
	for item_variant in pending:
		var item: Dictionary = item_variant
		var copy: Dictionary = item["copy"]
		var source: Dictionary = item["source"]
		var edges: Dictionary = {}
		var source_edges = source.get("edges", {})
		if source_edges is Dictionary:
			for side in source_edges:
				var edge_variant = (source_edges as Dictionary).get(side, {})
				if not edge_variant is Dictionary:
					continue
				var edge: Dictionary = edge_variant
				var target_old := str(edge.get("target", ""))
				if target_old.is_empty() or not id_map.has(target_old):
					continue
				edges[str(side)] = {"target": str(id_map[target_old]), "offset": int(edge.get("offset", 0))}
		copy["edges"] = edges
		maps.append(ensure_map_schema(copy))
		imported_ids.append(str(copy.get("id", "")))
	save_maps()
	return {"worldId": world_id, "mapIds": imported_ids}

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
	return _build_demo_catalog()

const VILLAGE_PNG = DemoCatalog.VILLAGE_PNG
const PLACE_PNG = DemoCatalog.PLACE_PNG
const VILLAGE_NIGHT_PNG = DemoCatalog.VILLAGE_NIGHT_PNG
const PLACE_NIGHT_PNG = DemoCatalog.PLACE_NIGHT_PNG

## Construit le catalogue de cartes de démo : les DONNÉES pures vivent dans
## `core/maps/demo_catalog.gd` ; ici on garde l'orchestration et l'I/O
## (dimensions depuis les PNG, import des images, affects `maps`, sauvegarde).
func _build_demo_catalog() -> Array:
	var build_plan := func(w: int, h: int, seed_value: int, density: float) -> Dictionary:
		return ProceduralCityScript.generate(w, h, seed_value, density)
	var build_elements := func(plan: Dictionary, w: int, h: int) -> Dictionary:
		return ProceduralCityScript.build_city_elements(plan, w, h)
	var deps := {
		"ensure_schema": ensure_map_schema,
		"grid_config": get_grid_config,
		"lighting_config": get_lighting_config,
		"character_sprite_path": get_character_sprite_path,
		"is_usable_sprite": is_usable_sprite,
		"build_plan": build_plan,
		"build_elements": build_elements,
		"schema_version": SCHEMA_VERSION,
		"render_mode_complex": RENDER_MODE_COMPLEX,
		"material_grass": MATERIAL_GRASS,
		"material_sand": MATERIAL_SAND,
	}
	var list: Array = []
	list.append(ensure_map_schema(DemoCatalog.brumeval_cemetery_map(deps)))

	var village_src := ProjectSettings.globalize_path(VILLAGE_PNG)
	var place_src := ProjectSettings.globalize_path(PLACE_PNG)
	var cells_v := suggest_cells_from_image(village_src, 70) if FileAccess.file_exists(village_src) else Vector2i(24, 16)
	var cells_p := suggest_cells_from_image(place_src, 70) if FileAccess.file_exists(place_src) else Vector2i(20, 14)

	list.append(DemoCatalog.valbois_village(cells_v, deps))
	list.append(DemoCatalog.valbois_place(cells_p, deps))
	# Vitrine 2.5D « qualité CS2 » : la cité composée de vrais assets 3D, générée
	# à graine fixe par le MÊME convertisseur pur que l'éditeur.
	list.append(DemoCatalog.cite_skyline_map(deps))

	maps = list
	var portrait_src := ProjectSettings.globalize_path("res://assets/portraits/voleur_kael.png")
	var portrait_dest := import_token_image(portrait_src) if FileAccess.file_exists(portrait_src) else ""
	if portrait_dest.is_empty():
		portrait_dest = "res://assets/portraits/voleur_kael.png"
	for m in maps:
		var pd: Dictionary = m.get("playDefaults", {})
		for tok_variant in pd.get("tokens", []):
			if tok_variant is Dictionary and str(tok_variant.get("memberId", "")) == "char-kael":
				tok_variant["image"] = portrait_dest
				tok_variant["label"] = "Kael"
	# Ré-importe systématiquement les PNG HD du projet → user:// (écrase un
	# vieux cache JPEG/basse résidu).
	if FileAccess.file_exists(village_src):
		import_background_image("demo-valbois-village", village_src)
	if FileAccess.file_exists(place_src):
		import_background_image("demo-valbois-place", place_src)
	return maps


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		# Fichier vide (ex. 1er boot, écriture interrompue) — pas une erreur.
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Erreur lecture JSON (%s) : %s" % [path, json.get_error_message()])
		return null
	return json.data

func _save_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
