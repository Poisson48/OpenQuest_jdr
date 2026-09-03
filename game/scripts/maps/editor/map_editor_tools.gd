extends RefCounted
class_name MapEditorTools

## Catalogue des outils de l'éditeur de cartes + table des raccourcis.
##
## Chaque outil correspond à un « MouseLogic » de l'éditeur Meownopoly :
## le mode courant décide de l'interprétation du clic, du glisser et du relâchement.

const SELECT := "select"
const PAN := "pan"
const TOKEN := "token"
const MARKER := "marker"
const EFFECT := "effect"
const ZONE := "zone"
const ZONE_RECT := "zone_rect"
const ZONE_POLY := "zone_poly"
const PLATFORM := "platform"
const WALL := "wall"
const NOTE := "note"
const LIGHT := "light"
const PAINT := "paint"
const BUCKET := "bucket"
const FOG_REVEAL := "fog"
const FOG_HIDE := "fog_hide"
const ERASE := "erase"
const LINK := "link"
const MEASURE := "measure"
const TEMPLATE := "template"
const AREA := "area"
const PROP := "prop"

## Outils qui posent un nouvel élément au clic (mode EM_POSE).
const POSE_TOOLS := [TOKEN, MARKER, EFFECT, ZONE, NOTE, LIGHT, PROP]

## Outils qui se dessinent par glisser (press → drag → release).
const DRAG_TOOLS := [ZONE_RECT, WALL, MEASURE, PLATFORM, AREA]

## Outils qui peignent la grille de terrain en continu.
const PAINT_TOOLS := [PAINT, FOG_REVEAL, FOG_HIDE]

const DEFS := [
	{
		"id": SELECT, "icon": "👆", "label": "Sélection", "shortcut": "V", "group": "base",
		"hint": "Clic : sélectionner · glisser dans le vide : rectangle de sélection · glisser un élément : déplacer · Ctrl+clic : ajouter/retirer.",
	},
	{
		"id": PAN, "icon": "✋", "label": "Navigation", "shortcut": "H", "group": "base",
		"hint": "Clic-glisser : déplacer la vue. La molette zoome dans tous les modes.",
	},
	{
		"id": TOKEN, "icon": "🧍", "label": "Token", "shortcut": "1", "group": "place",
		"hint": "Clic : poser un token joueur/PNJ. Choisissez la couleur et la taille dans les options.",
	},
	{
		"id": MARKER, "icon": "📍", "label": "Marqueur", "shortcut": "2", "group": "place",
		"hint": "Clic : poser un marqueur narratif (PNJ, indice, danger…).",
	},
	{
		"id": EFFECT, "icon": "🔥", "label": "Effet", "shortcut": "3", "group": "place",
		"hint": "Clic : poser un effet de particules (feu, fumée, magie, pluie).",
	},
	{
		"id": ZONE, "icon": "⭕", "label": "Zone ronde", "shortcut": "4", "group": "place",
		"hint": "Clic : poser une zone circulaire (sort, piège, aura).",
	},
	{
		"id": ZONE_RECT, "icon": "▭", "label": "Zone rect.", "shortcut": "5", "group": "place",
		"hint": "Clic-glisser : tracer une zone rectangulaire.",
	},
	{
		"id": ZONE_POLY, "icon": "⬡", "label": "Zone libre", "shortcut": "6", "group": "place",
		"hint": "Clics successifs : sommets du polygone · Entrée ou clic droit : fermer · Échap : annuler.",
	},
	{
		"id": PLATFORM, "icon": "🟫", "label": "Plateforme", "shortcut": "7", "group": "place",
		"hint": "Clic-glisser : tracer une plateforme surélevée (étage, pont, estrade).",
	},
	{
		"id": WALL, "icon": "🧱", "label": "Mur", "shortcut": "8", "group": "place",
		"hint": "Clic-glisser : tracer un mur. Maj : contraindre à l'horizontale/verticale.",
	},
	{
		"id": NOTE, "icon": "📝", "label": "Note MJ", "shortcut": "9", "group": "place",
		"hint": "Clic : épingler une note visible du MJ uniquement.",
	},
	{
		"id": LIGHT, "icon": "💡", "label": "Lumière", "shortcut": "0", "group": "place",
		"hint": "Clic : poser une source lumineuse (torche, brasier, lanterne).",
	},
	{
		"id": PROP, "icon": "🏚", "label": "Décor", "shortcut": "P", "group": "place",
		"hint": "Clic : poser le décor sélectionné dans la bibliothèque (bâtiment, charrette, mobilier…). Molette + Maj : agrandir · R : pivoter.",
	},
	{
		"id": AREA, "icon": "🏠", "label": "Lieu", "shortcut": "A", "group": "place",
		"hint": "Clic-glisser : délimiter un lieu nommé (taverne, place, sortie). Un lieu peut ouvrir sa propre carte, où l'on place les personnages.",
	},
	{
		"id": PAINT, "icon": "🖌", "label": "Terrain", "shortcut": "B", "group": "terrain",
		"hint": "Clic ou glisser : peindre le terrain avec la tuile sélectionnée. Taille de pinceau réglable.",
	},
	{
		"id": BUCKET, "icon": "🪣", "label": "Remplir", "shortcut": "G", "group": "terrain",
		"hint": "Clic : remplir toute la zone contiguë de même tuile.",
	},
	{
		"id": FOG_REVEAL, "icon": "🌫", "label": "Révéler", "shortcut": "R", "group": "fog",
		"hint": "Clic ou glisser : révéler le brouillard de guerre autour du curseur.",
	},
	{
		"id": FOG_HIDE, "icon": "🚫", "label": "Masquer", "shortcut": "T", "group": "fog",
		"hint": "Clic ou glisser : remasquer les cases déjà révélées.",
	},
	{
		"id": LINK, "icon": "🔗", "label": "Lier", "shortcut": "L", "group": "tools",
		"hint": "Clic sur la source puis sur la cible : crée un lien orienté (patrouille, passage, chaîne d'indices).",
	},
	{
		"id": MEASURE, "icon": "📏", "label": "Mesurer", "shortcut": "M", "group": "tools",
		"hint": "Clic-glisser : mesurer une distance en cases et en mètres.",
	},
	{
		"id": TEMPLATE, "icon": "🧩", "label": "Template", "shortcut": "K", "group": "tools",
		"hint": "Clic : poser le template sélectionné. R : le faire pivoter avant de poser.",
	},
	{
		"id": ERASE, "icon": "🧹", "label": "Gomme", "shortcut": "E", "group": "tools",
		"hint": "Clic : supprimer l'élément sous le curseur (les éléments verrouillés sont ignorés).",
	},
]

const GROUP_LABELS := {
	"base": "Navigation",
	"place": "Placer",
	"terrain": "Terrain",
	"fog": "Brouillard",
	"tools": "Outils",
}

const GROUP_ORDER := ["base", "place", "terrain", "fog", "tools"]

static func get_def(tool_id: String) -> Dictionary:
	for def in DEFS:
		if def["id"] == tool_id:
			return def
	return DEFS[0]

static func label(tool_id: String) -> String:
	return str(get_def(tool_id).get("label", tool_id))

static func icon(tool_id: String) -> String:
	return str(get_def(tool_id).get("icon", "•"))

static func hint(tool_id: String) -> String:
	return str(get_def(tool_id).get("hint", ""))

static func tooltip(tool_id: String) -> String:
	var def := get_def(tool_id)
	return "%s (%s)\n%s" % [def.get("label", tool_id), def.get("shortcut", "—"), def.get("hint", "")]

static func defs_in_group(group: String) -> Array:
	var out: Array = []
	for def in DEFS:
		if def["group"] == group:
			out.append(def)
	return out

static func tool_for_shortcut(key: String) -> String:
	for def in DEFS:
		if str(def.get("shortcut", "")).to_upper() == key.to_upper():
			return str(def["id"])
	return ""

static func is_pose_tool(tool_id: String) -> bool:
	return POSE_TOOLS.has(tool_id)

static func is_drag_tool(tool_id: String) -> bool:
	return DRAG_TOOLS.has(tool_id)

static func is_paint_tool(tool_id: String) -> bool:
	return PAINT_TOOLS.has(tool_id)

# ===========================================================================
# Aimantation
# ===========================================================================

const SNAP_MODES := [
	{"id": "off", "label": "Libre", "step": 0.0},
	{"id": "quarter", "label": "¼ case", "step": 0.25},
	{"id": "half", "label": "½ case", "step": 0.5},
	{"id": "cell", "label": "1 case", "step": 1.0},
]

static func snap_step(mode_id: String) -> float:
	for mode in SNAP_MODES:
		if mode["id"] == mode_id:
			return float(mode["step"])
	return 1.0

static func apply_snap(value: float, mode_id: String) -> float:
	var step := snap_step(mode_id)
	if step <= 0.0:
		return value
	return roundf(value / step) * step

static func snap_vector(v: Vector2, mode_id: String) -> Vector2:
	return Vector2(apply_snap(v.x, mode_id), apply_snap(v.y, mode_id))

# ===========================================================================
# Raccourcis clavier
# ===========================================================================

const SHORTCUTS := [
	{"keys": "Ctrl+Z", "action": "Annuler"},
	{"keys": "Ctrl+Y / Ctrl+Maj+Z", "action": "Rétablir"},
	{"keys": "Ctrl+C / Ctrl+X / Ctrl+V", "action": "Copier / Couper / Coller"},
	{"keys": "Ctrl+D", "action": "Dupliquer la sélection"},
	{"keys": "Ctrl+A", "action": "Tout sélectionner"},
	{"keys": "Ctrl+I", "action": "Inverser la sélection"},
	{"keys": "Ctrl+G / Ctrl+Maj+G", "action": "Grouper / Dégrouper"},
	{"keys": "Ctrl+S", "action": "Enregistrer la carte"},
	{"keys": "Suppr / Retour arrière", "action": "Supprimer la sélection"},
	{"keys": "Échap", "action": "Annuler l'action en cours / menu éditeur"},
	{"keys": "Flèches", "action": "Décaler la sélection (Maj : 1 case)"},
	{"keys": "Molette", "action": "Zoom · Clic milieu : déplacer la vue"},
	{"keys": "Espace maintenu", "action": "Navigation temporaire"},
	{"keys": "Ctrl+clic", "action": "Ajouter/retirer de la sélection"},
	{"keys": "Maj+clic", "action": "Ajouter à la sélection"},
	{"keys": "Alt+glisser", "action": "Dupliquer en glissant"},
	{"keys": "Page ↑ / ↓", "action": "Avancer / reculer d'un rang"},
	{"keys": "F", "action": "Recadrer sur la sélection"},
	{"keys": "V H 1..0 B G R T L M K E", "action": "Sélection directe d'un outil"},
]

static func shortcuts_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for entry in SHORTCUTS:
		lines.append("%s — %s" % [entry["keys"], entry["action"]])
	return "\n".join(lines)
