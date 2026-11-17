extends RefCounted

## Schéma de carte (phase 2.8 du refactor) — normalisation **pure**.
##
## Extrait de `game/scripts/autoload/map_data.gd` : `ensure_map_schema`
## (complète une carte avec toutes les clés/valeurs par défaut du schéma courant)
## et les valeurs de jeu par défaut (`playDefaults`). Aucune dépendance `Node`
## ni autoload : les prédicats qui dépendent du catalogue (`is_world_map`,
## `is_demo_map_id`) sont reçus en paramètres, et le dictionnaire de carte est
## muté en place comme avant.
##
## Les constantes de schéma vivent ici (source unique) ; `MapData` les réexpose
## en alias pour son API publique et pour les autres modules.
##
## Ordre d'insertion des clés : il est significatif (sérialisation JSON des
## cartes) — ne pas réordonner `ensure_map_schema` sans migration.

const RENDER_MODE_SIMPLE := "simple"
const GROUND_TERRAIN3D := "terrain3d"
const GROUND_ILLUSTRATED := "illustrated"
const PERSPECTIVE_TOPDOWN := "topdown"

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
	"preset": "jour",
	"sources": [],
	## Mode nuit façon brouillard : base = image nuit, lumières révèlent le jour.
	"nightMode": false,
	"nightAmbient": 0.22,
}
const DEFAULT_PLAY_DEFAULTS := {
	"tokens": [],
	"effects": [],
	"zones": [],
	"fogRevealed": [],
	## Cases illuminées persistantes (comme fogRevealed, mais pour le jour sous la nuit).
	"lightRevealed": [],
	"viewState": {},
}
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


## Complète `map_data` avec toutes les clés du schéma courant (mutée en place).
## `is_world` = résultat de `MapData.is_world_map(map_data)` (fog coupé sur une
## carte monde), `is_demo` = résultat de `MapData.is_demo_map_id(map_data["id"])`
## (statut publié) — les calculer avant l'appel ne change rien : ces clés
## (`mapKind`, `id`) ne sont pas modifiées ici.
static func ensure_map_schema(map_data: Dictionary, is_world: bool, is_demo: bool) -> Dictionary:
	if not map_data.has("schemaVersion"):
		map_data["schemaVersion"] = 1
	if not map_data.has("renderMode"):
		map_data["renderMode"] = RENDER_MODE_SIMPLE
	if not map_data.has("grid"):
		map_data["grid"] = DEFAULT_GRID_CONFIG.duplicate(true)
	if not map_data.has("fogEnabled"):
		map_data["fogEnabled"] = not is_world
	if not map_data.has("perspective"):
		map_data["perspective"] = PERSPECTIVE_TOPDOWN
	if not map_data.has("elevationLayers"):
		map_data["elevationLayers"] = []
	if not map_data.has("lighting"):
		map_data["lighting"] = DEFAULT_LIGHTING_CONFIG.duplicate(true)
	else:
		var light: Dictionary = map_data["lighting"]
		if light is Dictionary:
			if not light.has("nightMode"):
				light["nightMode"] = false
			if not light.has("nightAmbient"):
				light["nightAmbient"] = 0.22
			if not light.has("sources") or typeof(light["sources"]) != TYPE_ARRAY:
				light["sources"] = []
			map_data["lighting"] = light
	if not map_data.has("backgroundImageNight"):
		map_data["backgroundImageNight"] = ""
	# Sol : vrai terrain 3D par défaut, ou fond illustré si une image est fournie.
	if not map_data.has("groundMode"):
		map_data["groundMode"] = GROUND_ILLUSTRATED \
			if not str(map_data.get("backgroundImage", "")).strip_edges().is_empty() \
			else GROUND_TERRAIN3D
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
	# Schéma 5 — objets 3D génériques (mix 2D/3D de la carte 2.5D).
	if not map_data.has("meshes") or typeof(map_data["meshes"]) != TYPE_ARRAY:
		map_data["meshes"] = []
	# Relief : une hauteur de terrain par case (0 = plat).
	if not map_data.has("terrainHeights") or typeof(map_data["terrainHeights"]) != TYPE_ARRAY:
		map_data["terrainHeights"] = []
	# Matières du sol : une par case (0 = herbe, 1 = terre, 2 = pierre).
	if not map_data.has("terrainMaterials") or typeof(map_data["terrainMaterials"]) != TYPE_ARRAY:
		map_data["terrainMaterials"] = []
	# Creusements volumétriques (Voie B) : primitives SDF (trous, grottes,
	# tunnels, remblais) combinées au heightfield de relief.
	if not map_data.has("terrainCarves") or typeof(map_data["terrainCarves"]) != TYPE_ARRAY:
		map_data["terrainCarves"] = []
	# Eau : niveau du plan d'eau en cases (-1 = aucune eau).
	if not map_data.has("waterLevel"):
		map_data["waterLevel"] = -1.0
	# Bassins d'eau (lacs, mares, rivières, cascades) : chacun a son niveau,
	# son aire (polygone) ou son tracé (rivière avec sens d'écoulement).
	if not map_data.has("waterBodies") or typeof(map_data["waterBodies"]) != TYPE_ARRAY:
		map_data["waterBodies"] = []
	# Ambiance animée : "" (aucune), fireflies, dust, leaves.
	if not map_data.has("ambientFx"):
		map_data["ambientFx"] = ""
	# Monde (gestion de cartes façon Dofus) : identifiant du monde de zones.
	if not map_data.has("worldId"):
		map_data["worldId"] = ""
	if not map_data.has("parentMapId"):
		map_data["parentMapId"] = ""
	if not map_data.has("status") or str(map_data.get("status", "")).is_empty():
		map_data["status"] = "published" if is_demo else "draft"
	if not map_data.has("layers") or typeof(map_data["layers"]) != TYPE_ARRAY:
		map_data["layers"] = DEFAULT_LAYERS.duplicate(true)
	# Schéma 5 — style de rendu : carte 2.5D (défaut), VTT tactique ou diorama.
	if not map_data.has("renderStyle"):
		map_data["renderStyle"] = "2.5d"
	if str(map_data.get("renderStyle", "2.5d")) in ["2.5d", "diorama", "dd2_hybrid"]:
		# Grille masquée par défaut sur un décor peint.
		var grid: Dictionary = map_data.get("grid", {})
		if grid is Dictionary and not grid.has("show"):
			grid = grid.duplicate(true)
			grid["show"] = false
			map_data["grid"] = grid
	return map_data


## Valeurs de jeu par défaut (copie profonde) ; complète d'abord le schéma.
static func get_play_defaults(map_data: Dictionary, is_world: bool, is_demo: bool) -> Dictionary:
	var m := ensure_map_schema(map_data, is_world, is_demo)
	return m.get("playDefaults", DEFAULT_PLAY_DEFAULTS.duplicate(true)).duplicate(true)


## Garantit `playDefaults` complet sur la carte (tableaux + `viewState`) et le
## retourne (référence vers la valeur stockée dans la carte).
static func ensure_play_defaults(map_data: Dictionary, is_world: bool, is_demo: bool) -> Dictionary:
	var m := ensure_map_schema(map_data, is_world, is_demo)
	var pd: Dictionary = m.get("playDefaults", {})
	if typeof(pd) != TYPE_DICTIONARY:
		pd = DEFAULT_PLAY_DEFAULTS.duplicate(true)
		m["playDefaults"] = pd
	for key in ["tokens", "effects", "zones", "fogRevealed", "lightRevealed"]:
		if not pd.has(key) or typeof(pd[key]) != TYPE_ARRAY:
			pd[key] = []
	if not pd.has("viewState") or typeof(pd["viewState"]) != TYPE_DICTIONARY:
		pd["viewState"] = {}
	m["playDefaults"] = pd
	return pd
