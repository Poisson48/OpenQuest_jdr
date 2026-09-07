extends RefCounted
class_name SessionToolRegistry

## Catalogue des outils carte disponibles pendant une partie.
##
## Même forme que `MapEditorTools` côté éditeur : des identifiants constants,
## une table `DEFS` descriptive et des accesseurs statiques. La barre d'outils
## se contente de lire ce catalogue ; elle ne décide de rien.

const SELECT := "select"
const MEMBER := "member"
const MARKER := "marker"
const EFFECT := "effect"
const FOG := "fog"
const ZONE := "zone"
const ERASE := "erase"

## Outils dont les boutons sont engendrés depuis les données de la partie
## (un bouton par personnage, un bouton par type de marqueur).
const DATA_DRIVEN := [MEMBER, MARKER]

const DEFS := [
	{
		"id": SELECT, "label": "Sélection", "glyph": "Sél", "group": "base",
		"modes": ["simple", "complex"], "gm_only": false,
		"hint": "Clic : inspecter. Glisser un jeton ou un décor : le déplacer. Double-clic : entrer dans un lieu.",
	},
	{
		"id": MEMBER, "label": "Personnage", "glyph": "PJ", "group": "place",
		"modes": ["simple", "complex"], "gm_only": true,
		"hint": "Clic : poser le personnage choisi s'il n'est pas déjà sur la carte.",
	},
	{
		"id": MARKER, "label": "Marqueur", "glyph": "Mrq", "group": "place",
		"modes": ["simple", "complex"], "gm_only": true,
		"hint": "Clic : poser un repère narratif (PNJ, danger, trésor…).",
	},
	{
		"id": EFFECT, "label": "Effet", "glyph": "Effet", "group": "gm",
		"modes": ["complex"], "gm_only": true,
		"hint": "Clic : poser un effet (feu, fumée, magie). ▶ le déclenche.",
	},
	{
		"id": FOG, "label": "Brouillard", "glyph": "Voile", "group": "gm",
		"modes": ["complex"], "gm_only": true,
		"hint": "Clic ou glisser : révéler le brouillard. Ctrl : le remettre.",
	},
	{
		"id": ZONE, "label": "Zone", "glyph": "Zone", "group": "gm",
		"modes": ["complex"], "gm_only": true,
		"hint": "Clic : marquer une zone d'effet (sort, piège, aura).",
	},
	{
		"id": ERASE, "label": "Gomme", "glyph": "Gomme", "group": "edit",
		"modes": ["simple", "complex"], "gm_only": true,
		"hint": "Clic : retirer le token ou le marqueur sous le curseur.",
	},
]

const GROUP_LABELS := {
	"base": "Vue",
	"place": "Placer",
	"gm": "MJ",
	"edit": "Corriger",
}

const GROUP_ORDER := ["base", "place", "gm", "edit"]

const PLACE_MODES := [MEMBER, MARKER, EFFECT, FOG, ZONE, ERASE]

const EFFECT_PRESETS := ["fire", "smoke", "magic"]

static func get_def(tool_id: String) -> Dictionary:
	for def in DEFS:
		if def["id"] == tool_id:
			return def
	return DEFS[0]

static func label(tool_id: String) -> String:
	return str(get_def(tool_id).get("label", tool_id))

static func glyph(tool_id: String) -> String:
	return str(get_def(tool_id).get("glyph", "?"))

static func hint(tool_id: String) -> String:
	return str(get_def(tool_id).get("hint", ""))

static func tooltip(tool_id: String) -> String:
	var def := get_def(tool_id)
	return "%s\n%s" % [def.get("label", tool_id), def.get("hint", "")]

static func is_available(tool_id: String, render_mode: String, is_gm: bool) -> bool:
	var def := get_def(tool_id)
	if bool(def.get("gm_only", false)) and not is_gm:
		return false
	var modes: Array = def.get("modes", [])
	return modes.has(render_mode)

static func defs_in_group(group: String, render_mode: String, is_gm: bool) -> Array:
	var out: Array = []
	for def in DEFS:
		if def["group"] != group:
			continue
		if not is_available(str(def["id"]), render_mode, is_gm):
			continue
		out.append(def)
	return out

## Outil par défaut : sélection / navigation. Placer un PJ ou un combat
## exige un bouton explicite — un clic nu ne déclenche plus d'action opaque.
static func default_tool(_party: Array = []) -> Dictionary:
	return { "mode": SELECT }

static func is_place_tool(tool: Dictionary) -> bool:
	return PLACE_MODES.has(str(tool.get("mode", SELECT)))

static func make(tool_id: String, extra: Dictionary = {}) -> Dictionary:
	var tool := { "mode": tool_id }
	tool.merge(extra, true)
	match tool_id:
		EFFECT:
			tool["preset"] = tool.get("preset", EFFECT_PRESETS[0])
			tool["radius"] = tool.get("radius", 1.0)
		ZONE:
			tool["radius"] = tool.get("radius", 1.5)
			tool["label"] = tool.get("label", "Zone")
	return tool

static func same_tool(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("mode", "")) != str(b.get("mode", "")):
		return false
	match str(a.get("mode", "")):
		MEMBER:
			return str(a.get("member_id", "")) == str(b.get("member_id", ""))
		MARKER:
			return str(a.get("marker_type", "")) == str(b.get("marker_type", ""))
		EFFECT:
			return str(a.get("preset", "")) == str(b.get("preset", ""))
	return true

# ---------------------------------------------------------------------------
# Traduction vers les moteurs de carte
# ---------------------------------------------------------------------------

## Format attendu par `interactive_map.set_session_tool`.
static func to_simple_tool(tool: Dictionary) -> Dictionary:
	match str(tool.get("mode", SELECT)):
		ERASE:
			return { "mode": ERASE }
		MARKER:
			return { "mode": MARKER, "markerType": str(tool.get("marker_type", "")) }
		MEMBER:
			return { "mode": MEMBER, "memberId": str(tool.get("member_id", "")) }
		_:
			return { "mode": SELECT }

## Format attendu par `complex_map_engine_3d.set_session_tool`.
static func to_complex_tool(tool: Dictionary) -> Dictionary:
	var mode := str(tool.get("mode", SELECT))
	var out := { "mode": mode }
	match mode:
		MEMBER:
			out["memberId"] = str(tool.get("member_id", ""))
		MARKER:
			out["markerType"] = str(tool.get("marker_type", ""))
		EFFECT:
			out["preset"] = str(tool.get("preset", EFFECT_PRESETS[0]))
			out["radius"] = float(tool.get("radius", 1.0))
		ZONE:
			out["radius"] = float(tool.get("radius", 1.5))
			out["label"] = str(tool.get("label", "Zone"))
	return out
