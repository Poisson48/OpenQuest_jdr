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
const MESH_WALL := "mesh_wall"
const ROOM_3D := "room_3d"
const ROOF_3D := "roof_3d"
const PROC_ROOF := "proc_roof"
const PROC_POLY_ROOF := "proc_poly_roof"
const FLOOR_3D := "floor_3d"
const DOOR_3D := "door_3d"
const HOUSE_3D := "house_3d"
const WINDOW_3D := "window_3d"
const FURNISH_3D := "furnish_3d"
const FENCE_3D := "fence_3d"
const STAIRS_3D := "stairs_3d"
const INTERIOR_3D := "interior_3d"
const PATH_3D := "path_3d"
const ORGANIC := "organic"
const PROC_WALL := "proc_wall"
const PROC_FENCE := "proc_fence"
const PROC_PATH := "proc_path"
const PATH_BRUSH := "path_brush"
const SCATTER := "scatter"
const FLOWER_ZONE := "flower_zone"
const CONTEXT_DECOR := "context_decor"
const SCENE_GEN := "scene_gen"
const SCENE_ZONE := "scene_zone"
const NOTE := "note"
const LIGHT := "light"
const PAINT := "paint"
const BUCKET := "bucket"
const TERRAIN_HEIGHT := "terrain_height"
const TERRAIN_SPLINE := "terrain_spline"
const GROUND_MATERIAL := "ground_material"
const FOG_REVEAL := "fog"
const FOG_HIDE := "fog_hide"
const ERASE := "erase"
const LINK := "link"
const MEASURE := "measure"
const TEMPLATE := "template"
const AREA := "area"
const PROP := "prop"
const MESH := "mesh"

## Outils qui posent un nouvel élément au clic (mode EM_POSE).
const POSE_TOOLS := [TOKEN, MARKER, EFFECT, ZONE, NOTE, LIGHT, PROP, MESH, DOOR_3D, WINDOW_3D, FURNISH_3D, STAIRS_3D, INTERIOR_3D, CONTEXT_DECOR, SCENE_GEN]

## Outils qui se dessinent par glisser (press → drag → release).
const DRAG_TOOLS := [ZONE_RECT, WALL, MESH_WALL, ROOM_3D, ROOF_3D, PROC_ROOF, FLOOR_3D, HOUSE_3D, FENCE_3D, PATH_3D, MEASURE, PLATFORM, AREA, SCENE_ZONE]

## Outils qui peignent la grille de terrain en continu.
const PAINT_TOOLS := [PAINT, FOG_REVEAL, FOG_HIDE]
## Outil de relief : pinceau de hauteurs (traitement distinct de la peinture de tuiles).
const RELIEF_TOOLS := [TERRAIN_HEIGHT]

const DEFS := [
	{
		"id": SELECT, "icon": "👆", "label": "Sélection", "shortcut": "V", "group": "base",
		"hint": "Clic : sélectionner (dessus) · glisser la sélection : déplacer même sous d'autres éléments · vide : rectangle · Ctrl/Maj : multi-sélection · Alt : dupliquer.",
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
		"id": MESH_WALL, "icon": "🏗", "label": "Mur 3D", "shortcut": "", "group": "place",
		"hint": "Clic-glisser : un seul panneau de mur lissé (pas de micro-segments), aligné au terrain. Les extrémités s'aimantent aux murs existants : prolongement, coin L automatique, jonction T. Hauteur réglable ; étirement connecté aux murs alignés.",
	},
	{
		"id": ROOM_3D, "icon": "🏠", "label": "Pièce 3D", "shortcut": "", "group": "place",
		"hint": "Clic-glisser : pièce fermée (4 murs raccordés + coins L automatiques). Base de maison façon Sims : les murs se collent aux murs voisins.",
	},
	{
		"id": ROOF_3D, "icon": "🛖", "label": "Toit 3D", "shortcut": "", "group": "place",
		"hint": "Clic-glisser un rectangle : couvre une pièce avec des tuiles de toit 2 pans à la hauteur choisie.",
	},
	{
		"id": PROC_ROOF, "icon": "🏠", "label": "Toit procédural", "shortcut": "", "group": "place",
		"hint": "Clic-glisser un rectangle : un seul mesh de toit à deux pans, avec débord et pignons, adapté à l'emprise. Fini les rangées de tuiles à recaler.",
	},
	{
		"id": PROC_POLY_ROOF, "icon": "⛺", "label": "Toit libre", "shortcut": "", "group": "place",
		"hint": "Clic-glisser pour dessiner une emprise libre : toit triangulé sur forme irrégulière (L, U, courbe). Hauteur réglable.",
	},
	{
		"id": FLOOR_3D, "icon": "▦", "label": "Dallage", "shortcut": "", "group": "place",
		"hint": "Clic-glisser un rectangle : pose un dallage de pierre et nivelle le sol intérieur.",
	},
	{
		"id": DOOR_3D, "icon": "🚪", "label": "Porte 3D", "shortcut": "", "group": "place",
		"hint": "Clic sur un mur 3D : ouvre le mur (deux montants) et insère une porte à auvent.",
	},
	{
		"id": HOUSE_3D, "icon": "🏡", "label": "Maison rapide", "shortcut": "", "group": "place",
		"hint": "Clic-glisser un rectangle : construit murs + dallage + toit + porte en une passe.",
	},
	{
		"id": WINDOW_3D, "icon": "🪟", "label": "Fenêtre 3D", "shortcut": "", "group": "place",
		"hint": "Clic sur un mur 3D : pose une fenêtre à volets sur la façade extérieure.",
	},
	{
		"id": FURNISH_3D, "icon": "🪑", "label": "Meubler", "shortcut": "", "group": "place",
		"hint": "Clic dans une pièce : pose un ensemble de mobilier (salle commune, chambre, comptoir, campement).",
	},
	{
		"id": STAIRS_3D, "icon": "🪜", "label": "Escalier 3D", "shortcut": "", "group": "place",
		"hint": "Clic près d'un mur : pose un escalier extérieur adossé à la façade.",
	},
	{
		"id": INTERIOR_3D, "icon": "🚪", "label": "Intérieur", "shortcut": "", "group": "place",
		"hint": "Clic sur une porte 3D : crée son lieu et sa carte intérieure (taille indépendante), puis l'ouvre.",
	},
	{
		"id": FENCE_3D, "icon": "🪵", "label": "Clôture", "shortcut": "", "group": "place",
		"hint": "Clic-glisser : pose une clôture modulaire (barrière, clôture basse ou palissade) le long du tracé.",
	},
	{
		"id": PATH_3D, "icon": "🛤", "label": "Chemin", "shortcut": "", "group": "place",
		"hint": "Clic-glisser : trace un chemin de terre (largeur réglable) sur le terrain.",
	},
	{
		"id": ORGANIC, "icon": "🌀", "label": "Tracé organique", "shortcut": "", "group": "place",
		"hint": "Clic-glisser libre : dessine une courbe lissée (Catmull-Rom) et la construit en modules continus (mur, clôture, palissade) orientés sur la tangente. Relâchez pour construire : courbes, virages doux, diagonales. Options style / hauteur / lissage.",
	},
	{
		"id": PROC_WALL, "icon": "🪄", "label": "Mur procédural", "shortcut": "", "group": "place",
		"hint": "Clic-glisser libre : génère un vrai mesh de mur continu (mitres, sans couture) à partir de la courbe. Hauteur et lissage réglables ; prochaine étape du plan Tiny Glade.",
	},
	{
		"id": PROC_FENCE, "icon": "🪵", "label": "Clôture procédurale", "shortcut": "", "group": "place",
		"hint": "Clic-glisser libre : poteaux et lisses générés en un seul mesh le long de la courbe. Hauteur et espacement réglables.",
	},
	{
		"id": PROC_PATH, "icon": "🛤", "label": "Chemin procédural", "shortcut": "", "group": "place",
		"hint": "Clic-glisser libre : chemin continu qui suit le relief, légèrement enfoncé, bords irréguliers. Largeur et creux réglables.",
	},
	{
		"id": PATH_BRUSH, "icon": "🖌", "label": "Pinceau chemin", "shortcut": "", "group": "place",
		"hint": "Clic-glisser comme un pinceau : peint un chemin avec la largeur choisie. Idéal pour tracer rapidement des sentiers et des places.",
	},
	{
		"id": SCATTER, "icon": "🌿", "label": "Végétation", "shortcut": "", "group": "place",
		"hint": "Clic-glisser : disperse automatiquement buissons, haies, roseaux, arbres, bosquets ou rochers autour du tracé (densité, taille, rayon). Rotations et échelles variées, sans doublon sur une case, eau évitée, un seul undo par trait.",
	},
	{
		"id": FLOWER_ZONE, "icon": "🌸", "label": "Zone fleurie", "shortcut": "", "group": "place",
		"hint": "Clic-glisser pour dessiner une zone fermée : des fleurs procédurales du type choisi (coquelicots, marguerites, lavande, bleues, mélange) apparaissent uniquement dans cette zone.",
	},
	{
		"id": CONTEXT_DECOR, "icon": "🍂", "label": "Décor contextuel", "shortcut": "", "group": "place",
		"hint": "Clic près d'un mur : pose automatiquement buissons, rochers et touffes le long de ses abords, avec variations déterministes. Un seul undo.",
	},
	{
		"id": SCENE_GEN, "icon": "🏘", "label": "Générer scène", "shortcut": "", "group": "place",
		"hint": "Clic : génère un village, une forêt ou un camp sur toute la carte, avec chemins, bâtiments et décor. Style, graine et densité réglables.",
	},
	{
		"id": SCENE_ZONE, "icon": "✏️", "label": "Esquisser une scène", "shortcut": "", "group": "place",
		"hint": "Clic-glisser une zone : l'algorithme complète village/forêt/camp uniquement dans cette zone. Donne les grandes lignes, le procédural fait le détail.",
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
		"id": MESH, "icon": "🧊", "label": "Objet 3D", "shortcut": "O", "group": "place",
		"hint": "Clic : poser l'objet 3D sélectionné (GLB) — bâtiment, tour, pont, rocher. R : pivoter de 90° · Échelle dans les options.",
	},
	{
		"id": AREA, "icon": "🏠", "label": "Lieu", "shortcut": "A", "group": "place",
		"hint": "Clic-glisser : délimiter un lieu nommé (taverne, place, sortie). Un lieu peut ouvrir sa propre carte, où l'on place les personnages.",
	},
	{
		"id": PAINT, "icon": "🖌", "label": "Terrain", "shortcut": "", "group": "terrain",
		"hint": "Clic ou glisser : peindre le terrain avec la tuile sélectionnée. Taille de pinceau réglable.",
	},
	{
		"id": BUCKET, "icon": "🪣", "label": "Remplir", "shortcut": "G", "group": "terrain",
		"hint": "Clic : remplir toute la zone contiguë de même tuile.",
	},
	{
		"id": TERRAIN_HEIGHT, "icon": "⛰", "label": "Relief", "shortcut": "U", "group": "terrain",
		"hint": "Clic ou glisser : monter/baisser le terrain. Les objets 3D posés s'adaptent à la hauteur. Mode, pinceau et force dans les options.",
	},
	{
		"id": TERRAIN_SPLINE, "icon": "🏔", "label": "Relief tracé", "shortcut": "", "group": "terrain",
		"hint": "Clic-glisser libre : déforme le terrain le long d'une courbe (crête, vallée, aplatir, lisser). Largeur et force réglables ; idéal pour collines, berges et chemins creusés.",
	},
	{
		"id": GROUND_MATERIAL, "icon": "🟫", "label": "Sol", "shortcut": "Y", "group": "terrain",
		"hint": "Clic ou glisser : peindre la matière du sol (herbe, terre/chemin, pierre). Choix de matière et taille de pinceau dans les options. Seulement en mode sol 3D.",
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
		"id": LINK, "icon": "🔗", "label": "Lier", "shortcut": "", "group": "tools",
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

## Sous-ensemble 2D : même flux (sélection, palette, inspecteur, undo)
## sans murs / lumières / plateformes / effets 3D.
const SIMPLE_IDS := [
	SELECT, PAN, MARKER, NOTE, AREA, PROP,
	PAINT, BUCKET, FOG_REVEAL, FOG_HIDE, LINK, MEASURE, ERASE,
]

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

static func simple_defs() -> Array:
	var out: Array = []
	for def in DEFS:
		if SIMPLE_IDS.has(str(def["id"])):
			out.append(def)
	return out

static func simple_defs_in_group(group: String) -> Array:
	var out: Array = []
	for def in simple_defs():
		if def["group"] == group:
			out.append(def)
	return out

static func is_simple_tool(tool_id: String) -> bool:
	return SIMPLE_IDS.has(tool_id)

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
	{"keys": "U", "action": "Relief (monter/baisser le terrain)"},
	{"keys": "Y", "action": "Peinture du sol (herbe / terre / pierre)"},
	{"keys": "Échap", "action": "Annuler l'action en cours / menu éditeur"},
	{"keys": "Flèches", "action": "Décaler la sélection (Maj : 1 case)"},
	{"keys": "Molette", "action": "Zoom · clic droit glissé : déplacer · Maj+clic droit : orbite"},
	{"keys": "Espace maintenu", "action": "Navigation temporaire"},
	{"keys": "Ctrl+clic", "action": "Ajouter/retirer de la sélection"},
	{"keys": "Maj+clic", "action": "Ajouter à la sélection"},
	{"keys": "Alt+glisser", "action": "Dupliquer en glissant"},
	{"keys": "Page ↑ / ↓", "action": "Avancer / reculer d'un rang"},
	{"keys": "F", "action": "Recadrer sur la sélection"},
	{"keys": "Poignée de mur 3D", "action": "Étirer une extrémité : l'opposée reste fixe, les murs alignés raccordés suivent, la hauteur est conservée"},
	{"keys": "Tracé organique", "action": "Clic-glisser libre : courbe lissée en modules continus (mur/clôture/palissade), relâchez pour construire"},
	{"keys": "Végétation", "action": "Clic-glisser : dispersion auto de buissons/arbres/rochers (densité, taille, rayon), un seul undo par trait"},
	{"keys": "V H 1..0 B G U R T L M K E O", "action": "Sélection directe d'un outil"},
]

static func shortcuts_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for entry in SHORTCUTS:
		lines.append("%s — %s" % [entry["keys"], entry["action"]])
	return "\n".join(lines)
