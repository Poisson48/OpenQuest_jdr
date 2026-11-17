extends RefCounted

## Cartes de démo (phase 2.8c du refactor) — **données pures**, extraites de
## `game/scripts/autoload/map_data.gd`.
##
## Contenu : catalogue des cartes de démonstration (Valbois village + place,
## cimetière de Brumeval, Cité des Saules) et leurs helpers de données (PNJ,
## lieux, décors, relief). Aucun autoload ni `Node` : les quelques helpers de
## `MapData` sont injectés dans le dictionnaire `deps`, et l'I/O (lecture des
## images, import vers `user://`, affectation de `MapData.maps`, sauvegarde)
## reste dans `MapData`.
##
## Les corps de fonctions sont copiés à l'identique depuis MapData : mêmes ids,
## mêmes clés, même ordre d'insertion, même comportement.
##
## Contrat de `deps` (rempli par `MapData._build_demo_catalog`) :
##   ensure_schema: Callable         -> MapData.ensure_map_schema
##   grid_config: Callable           -> MapData.get_grid_config
##   lighting_config: Callable       -> MapData.get_lighting_config
##   character_sprite_path: Callable -> MapData.get_character_sprite_path(role, label)
##   is_usable_sprite: Callable      -> MapData.is_usable_sprite(path)
##   build_plan: Callable            -> ProceduralCity.generate(w, h, seed, density)
##   build_elements: Callable        -> ProceduralCity.build_city_elements(plan, w, h)
##   schema_version: int             -> MapData.SCHEMA_VERSION
##   render_mode_complex: String     -> MapData.RENDER_MODE_COMPLEX
##   material_grass: int             -> MapData.MATERIAL_GRASS
##   material_sand: int              -> MapData.MATERIAL_SAND
##   material_sand: int              -> MapData.deps["material_sand"]

const MapSchema := preload("res://scripts/core/maps/map_schema.gd")

const DEMO_MAP_IDS := ["demo-valbois-village", "demo-valbois-place", "demo-crypte-brumeval",
	"demo-cite-skyline"]
const VILLAGE_PNG := "res://assets/maps/valbois_village.png"
const PLACE_PNG := "res://assets/maps/place_du_marche.png"
const VILLAGE_NIGHT_PNG := "res://assets/maps/valbois_village_night.png"
const PLACE_NIGHT_PNG := "res://assets/maps/place_du_marche_night.png"

const CITE_DEMO_ID := "demo-cite-skyline"
const CITE_DEMO_SEED := 20261112
const CITE_DEMO_WIDTH := 44
const CITE_DEMO_HEIGHT := 32


# ---------------------------------------------------------------------------
# Cartes principales
# ---------------------------------------------------------------------------

## Cimetière de Brumeval — le schéma est normalisé par l'appelant (`MapData`),
## comme avant l'extraction.
static func brumeval_cemetery_map(deps: Dictionary) -> Dictionary:
	var w := 16
	var h := 12
	var tiles := brumeval_cemetery_tiles(w, h)
	var tokens: Array = []
	for npc in brumeval_on_map_npcs():
		var image: String = deps["character_sprite_path"].call(str(npc.role), str(npc.name))
		var tok := {
			"id": "tok-npc-%s" % str(npc.id),
			"x": float(npc.x),
			"y": float(npc.y),
			"kind": "npc",
			"markerType": "npc",
			"label": str(npc.name),
			"role": str(npc.role),
			"scale": 1.0,
		}
		if not image.is_empty():
			tok["image"] = image
		tokens.append(tok)
	var door := "res://data/props/objects/porte_bois.png"
	var props: Array = brumeval_cemetery_props(deps)
	if deps["is_usable_sprite"].call(door):
		props.append(map_prop("prop-porte", door, 1.0, 5.0, 1.15, 1.35))
	return {
		"id": "demo-crypte-brumeval",
		"title": "Brumeval — Cimetière",
		"description": "Cimetière villageois de la quête « La Crypte Oubliée ».",
		"scenarioId": "demo-crypte",
		"renderMode": MapSchema.RENDER_MODE_SIMPLE,
		"mapKind": "local",
		"roster": "general",
		"parentMapId": "",
		"width": w,
		"height": h,
		"tiles": tiles,
		"markers": [],
		"locationLinks": [],
		"props": props,
		"areas": [
			{
				"id": "area-exit-village",
				"x": 1.0, "y": 5.0, "w": 1.2, "h": 1.2,
				"label": "",
				"category": "exit",
				"icon": "",
				"showCallout": false,
				"targetMapId": "",
			},
			{
				"id": "area-crypte",
				"x": 10.5, "y": 3.0, "w": 2.4, "h": 2.2,
				"label": "",
				"category": "poi",
				"icon": "",
				"showCallout": false,
				"targetMapId": "",
			},
		],
		"fogEnabled": false,
		"playDefaults": {
			"tokens": tokens,
			"effects": [], "zones": [], "fogRevealed": [], "lightRevealed": [], "viewState": {},
		},
	}

## Village de Valbois (carte illustrée : lieux, tokens Kael + PNJ).
static func valbois_village(cells: Vector2i, deps: Dictionary) -> Dictionary:
	var village: Dictionary = deps["ensure_schema"].call({
		"id": "demo-valbois-village",
		"title": "Valbois — Village de l'Ouest",
		"description": "Carte complexe illustrée — cliquez la Place du Marché pour zoomer.",
		"roster": "general",
		"mapKind": "local",
		"renderMode": deps["render_mode_complex"],
		"renderStyle": "2.5d",
		"scenarioId": "demo-valbois",
		"width": cells.x,
		"height": cells.y,
		"tiles": [],
		"markers": [],
		"locationLinks": [],
		"areas": valbois_village_areas(cells),
		"fogEnabled": false,
		"parentMapId": "",
		"schemaVersion": deps["schema_version"],
	})
	var tiles_v: Array = []
	tiles_v.resize(cells.x * cells.y)
	tiles_v.fill("grass")
	village["tiles"] = tiles_v
	var grid_v: Dictionary = deps["grid_config"].call(village).duplicate(true)
	grid_v["show"] = false
	village["grid"] = grid_v
	village["atmosphere"] = {"enabled": false, "tint": "#1a1410", "opacity": 0.0, "vignette": 0.0}
	village["backgroundImage"] = VILLAGE_PNG
	village["backgroundImageNight"] = VILLAGE_NIGHT_PNG
	var village_light: Dictionary = deps["lighting_config"].call(village).duplicate(true)
	village_light["nightMode"] = false
	village_light["nightAmbient"] = 0.22
	village["lighting"] = village_light
	var village_tokens: Array = [{
		"id": "tok-kael",
		"x": float(cells.x) * 0.28,
		"y": float(cells.y) * 0.38,
		"kind": "member",
		"memberId": "char-kael",
		"label": "Kael",
		"scale": 1.0,
	}]
	for npc in valbois_village_npcs(cells):
		village_tokens.append(valbois_npc_token(deps, npc))
	village["playDefaults"] = {
		"tokens": village_tokens,
		"effects": [], "zones": [], "fogRevealed": [], "lightRevealed": [], "viewState": {},
	}
	return village

## Place du Marché (carte enfant du village de Valbois).
static func valbois_place(cells: Vector2i, deps: Dictionary) -> Dictionary:
	var place: Dictionary = deps["ensure_schema"].call({
		"id": "demo-valbois-place",
		"title": "Place du Marché",
		"description": "Détail de la Place du Marché — tokens, lieux, Kael.",
		"roster": "general",
		"mapKind": "local",
		"renderMode": deps["render_mode_complex"],
		"renderStyle": "2.5d",
		"scenarioId": "demo-valbois",
		"width": cells.x,
		"height": cells.y,
		"tiles": [],
		"markers": [],
		"locationLinks": [],
		"areas": valbois_place_areas(cells),
		"fogEnabled": false,
		"parentMapId": "demo-valbois-village",
		"schemaVersion": deps["schema_version"],
	})
	var tiles_p: Array = []
	tiles_p.resize(cells.x * cells.y)
	tiles_p.fill("floor")
	place["tiles"] = tiles_p
	var grid_p: Dictionary = deps["grid_config"].call(place).duplicate(true)
	grid_p["show"] = false
	place["grid"] = grid_p
	place["atmosphere"] = {"enabled": false, "tint": "#1a1410", "opacity": 0.0, "vignette": 0.0}
	place["backgroundImage"] = PLACE_PNG
	place["backgroundImageNight"] = PLACE_NIGHT_PNG
	var place_light: Dictionary = deps["lighting_config"].call(place).duplicate(true)
	place_light["nightMode"] = false
	place_light["nightAmbient"] = 0.22
	place["lighting"] = place_light
	var place_tokens: Array = [{
		"id": "tok-kael-place",
		"x": float(cells.x) * 0.50,
		"y": float(cells.y) * 0.55,
		"kind": "member",
		"memberId": "char-kael",
		"label": "Kael",
		"scale": 1.0,
	}]
	for npc in valbois_place_npcs(cells):
		place_tokens.append(valbois_npc_token(deps, npc))
	place["playDefaults"] = {
		"tokens": place_tokens,
		"effects": [], "zones": [], "fogRevealed": [], "lightRevealed": [], "viewState": {},
	}
	return place

## Carte vitrine « Cité des Saules » (matérialisée à la construction du catalogue,
## générée à graine fixe par le convertisseur pur de l'éditeur).
static func cite_skyline_map(deps: Dictionary) -> Dictionary:
	var plan: Dictionary = deps["build_plan"].call(CITE_DEMO_WIDTH,
		CITE_DEMO_HEIGHT, CITE_DEMO_SEED, 1.0)
	var built: Dictionary = deps["build_elements"].call(plan,
		CITE_DEMO_WIDTH, CITE_DEMO_HEIGHT)
	# --- Éléments 3D (mêmes champs qu'un document d'éditeur) ------------------
	# L'éditeur normalise les éléments à son chargement (`_ingest`), la session
	# 3D lit directement x/y/w/h/asset/display/elevation. On ne stocke donc que
	# les champs utiles + un id déterministe (le catalogue est reconstruit à
	# chaque démarrage, les ids doivent être stables).
	var meshes: Array = []
	var index := 0
	for entry_variant in built.get("elements", []):
		var entry: Dictionary = entry_variant
		var raw: Dictionary = (entry.get("elem", {}) as Dictionary).duplicate(true)
		if raw.is_empty():
			continue
		raw["id"] = "cite-%04d" % index
		raw["hidden"] = false
		index += 1
		meshes.append(raw)
	# --- Sols : matières peintes par le plan (rues pavées, place, approches) ---
	var terrain: Dictionary = built.get("terrain", {})
	var materials: Array = []
	materials.resize(CITE_DEMO_WIDTH * CITE_DEMO_HEIGHT)
	materials.fill(deps["material_grass"])
	for cell_variant in terrain.keys():
		var cell: Vector2i = cell_variant
		if cell.x < 0 or cell.y < 0 or cell.x >= CITE_DEMO_WIDTH \
				or cell.y >= CITE_DEMO_HEIGHT:
			continue
		materials[cell.y * CITE_DEMO_WIDTH + cell.x] = clampi(
			int(terrain[cell_variant]), deps["material_grass"], deps["material_sand"])
	var tiles: Array = []
	tiles.resize(CITE_DEMO_WIDTH * CITE_DEMO_HEIGHT)
	tiles.fill("floor")
	var map: Dictionary = deps["ensure_schema"].call({
		"id": CITE_DEMO_ID,
		"title": "Cité des Saules",
		"description": "Vitrine 2.5D « qualité CS2 » : cité composée de vrais assets 3D (bâtiments, toits, façades, marché, tours), générée à graine fixe. Modifiable dans l'éditeur.",
		"roster": "general",
		"mapKind": "local",
		"renderMode": deps["render_mode_complex"],
		"renderStyle": "2.5d",
		"scenarioId": "",
		"parentMapId": "",
		"width": CITE_DEMO_WIDTH,
		"height": CITE_DEMO_HEIGHT,
		"tiles": tiles,
		"markers": [],
		"locationLinks": [],
		"backgroundImage": "",
		"backgroundImageNight": "",
		"groundMode": MapSchema.GROUND_TERRAIN3D,
		"fogEnabled": false,
		"perspective": MapSchema.PERSPECTIVE_TOPDOWN,
		"elevationLayers": [],
		# Même éclairage que `cite_boot.gd` (correctif Lead : soleil jour + ombres
		# franches au lieu du preset pastel tiny_glade qui lavait la cité).
		"lighting": {"enabled": true, "preset": "jour", "direction": "nw",
			"intensity": 0.35, "sources": []},
		"qualityPreset": "cinema",
		# Brume fine de distance, composante hauteur neutralisée.
		"atmosphericFog": {"enabled": true, "density": 0.04, "heightDensity": 0.0},
		"atmosphere": {"enabled": false, "tint": "#1a1410", "opacity": 0.0,
			"vignette": 0.0},
		"terrainHeights": cite_relief_heights(),
		"terrainMaterials": materials,
		"meshes": meshes,
		"zoneX": 0,
		"zoneY": 0,
		"zoneW": CITE_DEMO_WIDTH,
		"zoneH": CITE_DEMO_HEIGHT,
		"schemaVersion": deps["schema_version"],
	})
	var grid: Dictionary = deps["grid_config"].call(map).duplicate(true)
	grid["show"] = false
	map["grid"] = grid
	return map

## Relief doux des marges (identique à `cite_boot`) : le cœur de la cité reste
## plat pour que les bâtiments soient droits, les ceintures ondulent doucement.

# ---------------------------------------------------------------------------
# Helpers de données
# ---------------------------------------------------------------------------


static func brumeval_cemetery_tiles(w: int, h: int) -> Array:
	var tiles: Array = []
	tiles.resize(w * h)
	for y in range(h):
		for x in range(w):
			var id := "grass"
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				id = "forest"
			elif y == 5 and x >= 1 and x <= 12:
				id = "road"
			elif x >= 3 and x <= 5 and y >= 2 and y <= 3:
				id = "water"
			elif x >= 9 and x <= 12 and y >= 2 and y <= 4:
				id = "stone"
			elif x >= 10 and x <= 12 and y >= 8 and y <= 9:
				id = "stone"
			tiles[y * w + x] = id
	return tiles

static func brumeval_cemetery_props(deps: Dictionary) -> Array:
	var chapel := "res://data/props/buildings/temple_eliandre.png"
	if not deps["is_usable_sprite"].call(chapel):
		chapel = "res://data/props/buildings/temple_pierre.png"
	return [
		map_prop("prop-chapelle", chapel, 10.6, 2.7, 3.0, 3.0),
		map_prop("prop-arbre-n", "res://data/props/nature/arbre_valbois.png", 4.2, 1.6, 2.2, 2.2),
		map_prop("prop-chene", "res://data/props/nature/chene_isole.png", 7.2, 8.6, 2.0, 2.2),
		map_prop("prop-sapin", "res://data/props/nature/sapin.png", 13.2, 6.4, 1.8, 2.4),
		map_prop("prop-arbre-s", "res://data/props/nature/arbre_valbois.png", 2.4, 9.2, 2.0, 2.0),
		map_prop("prop-fleurs", "res://data/props/nature/fleurs_sauvages.png", 6.4, 3.6, 1.4, 1.2),
		map_prop("prop-foin", "res://data/props/nature/tas_foin.png", 12.4, 8.6, 1.5, 1.3),
		map_prop("prop-panneau", "res://data/props/objects/panneau_bois.png", 2.3, 4.2, 1.0, 1.2),
		map_prop("prop-fontaine", "res://data/props/objects/fontaine.png", 7.6, 6.6, 1.4, 1.4),
		map_prop("prop-puits", "res://data/props/objects/puits.png", 5.4, 8.2, 1.3, 1.5),
		map_prop("prop-buisson", "res://data/props/nature/buisson.png", 8.6, 4.6, 1.2, 1.1),
		map_prop("prop-rocher", "res://data/props/nature/rocher.png", 4.8, 7.0, 1.1, 1.0),
		map_prop("prop-torche", "res://data/props/objects/torche.png", 9.2, 4.2, 0.7, 1.0),
	]

static func map_prop(id: String, asset: String, x: float, y: float, pw: float, ph: float) -> Dictionary:
	return {
		"id": id,
		"asset": asset,
		"x": x, "y": y, "w": pw, "h": ph,
		"hidden": false,
		"display": {"opacity": 1.0},
	}

## Personnages visibles sur la carte (le reste du casting reste dans le scénario).

static func brumeval_on_map_npcs() -> Array:
	return [
		{"id": "eldric", "name": "Eldric le fossoyeur", "role": "Informateur", "x": 3, "y": 5},
		{"id": "rhen", "name": "Capitaine Rhen", "role": "Garde", "x": 2, "y": 2},
		{"id": "myrrha", "name": "Sœur Myrrha", "role": "Prêtresse", "x": 10, "y": 2},
		{"id": "tomas", "name": "Tomas", "role": "Adjoint", "x": 6, "y": 5},
		{"id": "lila", "name": "Lila la veuve", "role": "Témoin", "x": 12, "y": 7},
	]

## Roster complet (console / dialogues) — plus posé sur la carte.

static func brumeval_crowd_npcs() -> Array:
	return [
		{"id": "eldric", "name": "Eldric le fossoyeur", "role": "Informateur", "emoji": "🪦", "x": 3, "y": 5},
		{"id": "myrrha", "name": "Sœur Myrrha", "role": "Prêtresse", "emoji": "⛪", "x": 10, "y": 2},
		{"id": "rhen", "name": "Capitaine Rhen", "role": "Garde", "emoji": "🛡️", "x": 2, "y": 2},
		{"id": "tomas", "name": "Tomas", "role": "Adjoint", "emoji": "🕯️", "x": 6, "y": 5},
		{"id": "lila", "name": "Lila la veuve", "role": "Témoin", "emoji": "🖤", "x": 12, "y": 7},
	]

static func valbois_npc_token(deps: Dictionary, npc: Dictionary) -> Dictionary:
	var image: String = deps["character_sprite_path"].call(str(npc.get("role", "")), str(npc.get("name", "")))
	var tok := {
		"id": "tok-npc-%s" % str(npc.get("id", "x")),
		"x": float(npc.get("x", 0)),
		"y": float(npc.get("y", 0)),
		"kind": "npc",
		"markerType": "npc",
		"label": str(npc.get("name", "PNJ")),
		"role": str(npc.get("role", "PNJ")),
		"scale": 1.0,
	}
	if not image.is_empty():
		tok["image"] = image
	return tok

static func valbois_village_npcs(cells: Vector2i) -> Array:
	var w := float(cells.x)
	var h := float(cells.y)
	return [
		{"id": "lyse", "name": "Lyse", "role": "Garde", "x": w * 0.22, "y": h * 0.40},
		{"id": "pere-alain", "name": "Père Alain", "role": "Prêtre", "x": w * 0.34, "y": h * 0.18},
		{"id": "gareth", "name": "Gareth", "role": "Forgeron", "x": w * 0.20, "y": h * 0.50},
		{"id": "renard", "name": "Renard", "role": "Tavernier", "x": w * 0.38, "y": h * 0.54},
		{"id": "hugo", "name": "Hugo", "role": "Palefrenier", "x": w * 0.74, "y": h * 0.66},
		{"id": "odo", "name": "Odo", "role": "Meunier", "x": w * 0.16, "y": h * 0.24},
		{"id": "elise", "name": "Dame Élise", "role": "Épouse du maire", "x": w * 0.68, "y": h * 0.46},
		{"id": "tom", "name": "Tom le gamin", "role": "Villageois", "x": w * 0.48, "y": h * 0.36},
	]

static func valbois_place_npcs(cells: Vector2i) -> Array:
	var w := float(cells.x)
	var h := float(cells.y)
	return [
		{"id": "marta", "name": "Marta l'étalière", "role": "Marchande", "x": w * 0.36, "y": h * 0.40},
		{"id": "clara", "name": "Clara", "role": "Marchande", "x": w * 0.42, "y": h * 0.52},
		{"id": "nina", "name": "Nina", "role": "Boulangère", "x": w * 0.30, "y": h * 0.58},
		{"id": "sura", "name": "Sura", "role": "Herboriste", "x": w * 0.58, "y": h * 0.60},
		{"id": "capitaine", "name": "Capitaine Ord", "role": "Garde", "x": w * 0.62, "y": h * 0.36},
		{"id": "ombre", "name": "L'Homme hoodé", "role": "Informateur", "x": w * 0.70, "y": h * 0.48},
		{"id": "maire", "name": "Maire Corbin", "role": "Maire", "x": w * 0.78, "y": h * 0.42},
	]

## Lieux légendés Valbois (callouts) + Place liée + sorties village (P3-B).

static func valbois_village_areas(cells: Vector2i) -> Array:
	var w := float(cells.x)
	var h := float(cells.y)
	return [
		valbois_area("area-place-marche", w * 0.50, h * 0.42, 4.2, 3.2,
			"Place du Marché", "poi", "⭐", true, "demo-valbois-place"),
		valbois_area("area-moulin", w * 0.16, h * 0.22, 3.2, 2.8,
			"Moulin", "poi", "🌬️", true, ""),
		valbois_area("area-temple", w * 0.34, h * 0.16, 3.4, 2.8,
			"Temple d'Éliandre", "poi", "⛪", true, ""),
		valbois_area("area-forge", w * 0.20, h * 0.48, 3.0, 2.6,
			"Forge", "poi", "🔨", true, ""),
		valbois_area("area-taverne", w * 0.38, h * 0.52, 3.2, 2.6,
			"Taverne du Cerf", "poi", "🍺", true, ""),
		valbois_area("area-boulangerie", w * 0.44, h * 0.32, 2.8, 2.4,
			"Boulangerie", "poi", "🥖", true, ""),
		valbois_area("area-librairie", w * 0.58, h * 0.26, 2.8, 2.4,
			"Librairie", "poi", "📚", true, ""),
		valbois_area("area-maire", w * 0.68, h * 0.44, 3.4, 2.8,
			"Maison du Maire", "poi", "🏛️", true, ""),
		valbois_area("area-ecuries", w * 0.74, h * 0.64, 3.2, 2.6,
			"Écuries", "poi", "🐴", true, ""),
		valbois_area("area-epicerie", w * 0.56, h * 0.54, 2.6, 2.2,
			"Épicerie", "poi", "🧺", true, ""),
		valbois_area("area-pharmacie", w * 0.48, h * 0.62, 2.6, 2.2,
			"Pharmacie", "poi", "🌿", true, ""),
		valbois_area("area-exit-foret", w * 0.08, h * 0.72, 3.0, 2.2,
			"Chemin de la Forêt", "exit", "🚪", true, ""),
		valbois_area("area-exit-capitale", w * 0.92, h * 0.52, 3.0, 2.2,
			"Chemin de la Capitale", "exit", "🚪", true, ""),
	]

static func valbois_place_areas(cells: Vector2i) -> Array:
	var w := float(cells.x)
	var h := float(cells.y)
	return [
		valbois_area("area-fontaine", w * 0.50, h * 0.48, 2.4, 2.4,
			"Fontaine", "poi", "⛲", true, ""),
		valbois_area("area-etals", w * 0.38, h * 0.40, 3.0, 2.2,
			"Étals", "poi", "🛒", true, ""),
		valbois_area("area-halle", w * 0.62, h * 0.42, 2.8, 2.2,
			"Halle", "poi", "🏪", true, ""),
	]

static func valbois_area(id: String, x: float, y: float, aw: float, ah: float,
	label: String, category: String, icon: String,
	show_callout: bool, target_map_id: String) -> Dictionary:
	return {
		"id": id,
		"x": x, "y": y,
		"w": aw, "h": ah,
		"label": label,
		"category": category,
		"icon": icon,
		"showCallout": show_callout,
		"targetMapId": target_map_id,
		"labelOffset": {"x": 0.0, "y": -(ah * 0.5 + 0.7)},
	}

static func cite_relief_heights() -> Array:
	var heights: Array = []
	heights.resize(CITE_DEMO_WIDTH * CITE_DEMO_HEIGHT)
	for y in range(CITE_DEMO_HEIGHT):
		for x in range(CITE_DEMO_WIDTH):
			var in_city := x >= 2 and x <= CITE_DEMO_WIDTH - 3 \
				and y >= 2 and y <= CITE_DEMO_HEIGHT - 3
			var value := 0.0
			if not in_city:
				value = 0.16 * sin(float(x) * 0.52) * cos(float(y) * 0.44) \
					+ 0.06 * sin(float(x + y) * 0.85) + 0.04
			heights[y * CITE_DEMO_WIDTH + x] = value
	return heights

## Cimetière de Brumeval : sol texturé, décors PNG, quelques jetons — pas d'emojis.
