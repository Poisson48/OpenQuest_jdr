extends RefCounted
class_name ProceduralCity

## Planificateur déterministe de **cité** (style de scène « cite »).
##
## Il ne pose rien dans la carte : il compose un plan de placements que
## l'éditeur applique ensuite comme de vrais éléments du document
## (`doc.add_element`), donc éditables et annulables. Même graine ⇒ même plan.
##
## Différence avec `ProceduralSceneGenerator` village/forêt/camp : au lieu de
## maisons procédurales, la cité **compose les GLB du catalogue**
## (`game/assets/objects3d/`) :
##   • damier de rues larges pavées + place centrale encadrée d'îlots ;
##   • bâtiments GLB **alignés sur la trame**, façade parallèle à la rue, avec
##     une marge d'allée entre bâtiments (aucun chevauchement) ;
##   • accents de toiture discrets seulement (`cheminee_fumante`,
##     `toit_clocheton`) : les bâtiments GLB ont déjà leur toit cuit, empiler un
##     module complet produirait un double toit flottant ;
##   • modules de façade `anchor="wall"` uniquement sur les bâtiments assez
##     hauts pour les recevoir (porte, fenêtre, balcon, colombage) ;
##   • props de place et de rue, végétation, rochers, clôtures GLB ;
##   • tours aux quatre angles de la cité.
##
## Toutes les dimensions viennent du manifeste Blender (`dimensions_cells`,
## ordre [X, Z, Y]) : les empreintes de placement sont donc les vraies, et
## l'allocateur garantit **aucun chevauchement** au sol.
##
## Repères :
##   • les rectangles d'allocation sont en coordonnées de **bord de case** :
##     une case `i` couvre `[i, i+1)` ;
##   • un élément dont le pivot est `x` couvre `[x + 0.5 - w/2, x + 0.5 + w/2]`,
##     d'où l'utilisation systématique de `_elem_rect()`.

const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

const ASSET_ROOT := "res://assets/objects3d/"

## Libellés stables des éléments produits (filtres des tests et de l'inspecteur).
const LABEL_BUILDING := "Bâtiment de cité"
const LABEL_ROOF := "Toiture de cité"
const LABEL_WALL := "Façade de cité"
const LABEL_PROP := "Décor de cité"

## Budget global (éléments de document) : borne la charge de l'éditeur et du rendu.
const MAX_ELEMENTS_HARD := 260

# --- Pools d'assets (chemins relatifs à `res://assets/objects3d/`) ------------

const BUILDINGS := {
	"maison": "buildings/maison.glb",
	"maison_petite": "buildings/maison_petite.glb",
	"maison_grande": "buildings/maison_grande.glb",
	"maison_etage": "buildings/maison_etage.glb",
	"manoir": "buildings/manoir.glb",
	"forge": "buildings/forge.glb",
	"chapelle": "buildings/chapelle.glb",
	"grange": "buildings/grange.glb",
	"ecurie": "buildings/ecurie.glb",
	"tour": "buildings/tour.glb",
	"tour_grande": "buildings/tour_grande.glb",
	"marche_couvert": "buildings/marche_couvert.glb",
}

const ROOF_ACCENTS := {
	"cheminee": "buildings/cheminee_fumante.glb",
	"clocheton": "buildings/toit_clocheton.glb",
	"lucarne": "buildings/toit_lucarne.glb",
}

const WALL_MODULES := {
	"porte": "buildings/porte_auvent.glb",
	"fenetre": "buildings/fenetre_volets.glb",
	"balcon": "buildings/balcon_bois.glb",
	"colombage": "buildings/colombage_panneau.glb",
}

const PROPS := {
	"puits": "props/puits_couvert.glb",
	"fontaine": "props/fontaine.glb",
	"lanterne": "props/lanterne.glb",
	"banc": "props/banc.glb",
	"charrette": "props/charrette.glb",
	"tonneau": "props/tonneau.glb",
	"caisse": "props/caisse.glb",
	"caisse_grande": "props/caisse_grande.glb",
	"etal": "props/etal_marche.glb",
	"banniere": "props/banniere.glb",
	"panneau": "props/panneau.glb",
	"tas_de_bois": "props/tas_de_bois.glb",
}

const VEGETATION := {
	"arbre": "vegetation/arbre.glb",
	"arbre_automne": "vegetation/arbre_automne.glb",
	"arbre_majestueux": "vegetation/arbre_majestueux.glb",
	"buisson": "vegetation/buisson.glb",
	"bosquet": "vegetation/bosquet.glb",
	"haie": "vegetation/haie.glb",
}

const ROCKS := {
	"rocher": "terrain/rocher.glb",
	"gros_rocher": "terrain/gros_rocher.glb",
	"falaise": "terrain/falaise.glb",
}

const FENCES := {
	"cloture": "props/cloture_basse.glb",
	"barriere": "props/barriere.glb",
	"palissade": "props/palissade.glb",
}

## Marge de pose entre deux bâtiments (cases) : garantit une allée lisible.
const BUILDING_GAP := 0.55
## Marge de pose entre deux décors (cases).
const PROP_GAP := 0.14

## Les quatre orientations d'un îlot : `dir` = normale extérieure de la rangée,
## `rotation` = lacet de l'élément pour que la façade (+Z local) regarde la rue.
const BLOCK_SIDES := [
	{"dir": Vector2(0.0, -1.0), "rotation": 180.0},
	{"dir": Vector2(0.0, 1.0), "rotation": 0.0},
	{"dir": Vector2(-1.0, 0.0), "rotation": 90.0},
	{"dir": Vector2(1.0, 0.0), "rotation": 270.0},
]

## Cache des dimensions du manifeste (Vector3 : x = largeur, y = hauteur, z = profondeur).
static var _dims_cache: Dictionary = {}

# ===========================================================================
# Contexte d'allocation
# ===========================================================================

class Context extends RefCounted:
	var width: int = 0
	var height: int = 0
	var rng: RandomNumberGenerator
	var density: float = 1.0
	var plan: Dictionary = {}
	var occupied: Array = []          # Rect2 (bord de case) de tous les éléments au sol
	var reserved: Array = []          # Rect2 (place) interdits aux bâtiments
	var streets: Array = []           # Rect2 des rues (peinture + alignement)
	var blocks: Array = []            # Rect2 des îlots
	var margin_x: int = 2
	var margin_y: int = 2
	var street_w: int = 2
	var city_x0: float = 0.0
	var city_x1: float = 0.0
	var city_y0: float = 0.0
	var city_y1: float = 0.0
	var approach_x: float = 0.0
	var approach_y: float = 0.0
	var count: int = 0
	var max_count: int = 220
	var central_x: float = 0.0
	var central_y: float = 0.0
	var plaza: Rect2 = Rect2()


# ===========================================================================
# API publique
# ===========================================================================

## Plan complet de cité (mêmes clés que les autres styles + `buildings`).
## `width`/`height` sont en cases ; aucune position n'est décalée (l'appelant
## ajoute `origin` via `ProceduralSceneGenerator._offset_plan`).
static func generate(width: int, height: int, seed: int, density: float = 1.0) -> Dictionary:
	var plan := {
		"style": "cite",
		"houses": [],
		"paths": [],
		"props": [],
		"fences": [],
		"flowerZones": [],
		"rocks": [],
		"buildings": [],
	}
	if width < 8 or height < 8:
		return plan
	var ctx := Context.new()
	ctx.width = width
	ctx.height = height
	ctx.density = clampf(density, 0.3, 2.0)
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = seed
	ctx.plan = plan
	ctx.max_count = max_elements_for(width, height)
	if width < 18 or height < 15:
		_generate_burg(ctx)
	else:
		_generate_city(ctx)
	return plan


## Nombre maximal d'éléments pour une carte (borné, exposé pour la doc/les tests).
static func max_elements_for(width: int, height: int) -> int:
	return clampi(80 + int(float(width * height) * 0.115), 100, MAX_ELEMENTS_HARD)


## Empreinte (cases) d'un asset d'après le manifeste, ordre [X, Z].
static func asset_footprint(rel_path: String) -> Vector2:
	var dims := _dims(rel_path)
	return Vector2(dims.x, dims.z)


## Hauteur (cases) d'un asset d'après le manifeste.
static func asset_height(rel_path: String) -> float:
	return _dims(rel_path).y


# ===========================================================================
# Métadonnées du manifeste
# ===========================================================================

static func asset(rel_path: String) -> String:
	return ASSET_ROOT + rel_path

## Dimensions réelles (cases) : x = largeur, y = hauteur, z = profondeur.
## Le manifeste Blender stocke [X, Z, Y] : on remet la hauteur en `y`.
static func _dims(rel_path: String) -> Vector3:
	if _dims_cache.has(rel_path):
		return _dims_cache[rel_path]
	var out := Vector3(2.0, 2.0, 2.0)
	var entry: Dictionary = AssetLibraryScript.get_object3d_meta(asset(rel_path))
	if not entry.is_empty():
		var raw = entry.get("dimensions_cells", [])
		if raw is Array and (raw as Array).size() >= 3:
			var arr: Array = raw
			var candidate := Vector3(
				maxf(0.1, float(arr[0])),
				maxf(0.1, float(arr[2])),
				maxf(0.1, float(arr[1]))
			)
			if candidate.length() > 0.2:
				out = candidate
	_dims_cache[rel_path] = out
	return out


# ===========================================================================
# Petits helpers géométriques
# ===========================================================================

## Rectangle (bord de case) occupé par un élément de pivot `(x, y)` et d'empreinte `w × d`.
static func _elem_rect(x: float, y: float, w: float, d: float) -> Rect2:
	return Rect2(x + 0.5 - w * 0.5, y + 0.5 - d * 0.5, w, d)


static func _hits(rect: Rect2, others: Array, grow: float = 0.0) -> bool:
	for other_variant in others:
		if (other_variant as Rect2).grow(grow).intersects(rect):
			return true
	return false


static func _fits(rect: Rect2, container: Rect2, grow: float = 0.0) -> bool:
	return container.grow(grow).encloses(rect)


static func _pick_weighted(rng: RandomNumberGenerator, pool: Array) -> String:
	var total := 0.0
	for entry_variant in pool:
		total += float((entry_variant as Array)[1])
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for entry_variant in pool:
		var entry: Array = entry_variant
		roll -= float(entry[1])
		if roll <= 0.0:
			return str(entry[0])
	return str((pool[pool.size() - 1] as Array)[0])


## Une rotation en degrés fait-elle permuter largeur et profondeur de l'empreinte ?
static func _swaps_axes(rotation: float) -> bool:
	var r := fposmod(rotation, 180.0)
	return absf(r - 90.0) < 1.0


static func _can_add(ctx: Context) -> bool:
	return ctx.count < ctx.max_count


# ===========================================================================
# Cité complète
# ===========================================================================

static func _generate_city(ctx: Context) -> void:
	_layout_grid(ctx)
	_paint_streets(ctx)
	_place_plaza(ctx)
	_place_corner_towers(ctx)
	_fill_blocks(ctx)
	_furnish_plaza(ctx)
	_furnish_streets(ctx)
	# Rochers puis clôtures : la végétation remplit ce qui reste des marges.
	_place_margin_rocks(ctx)
	_place_margin_fences(ctx)
	_plant_margins(ctx)


static func _layout_grid(ctx: Context) -> void:
	var w := ctx.width
	var h := ctx.height
	var margin := 2 if (w >= 22 and h >= 18) else 1
	# Rues larges pour une lecture « cité » (3 cases sur les grandes cartes).
	var sw := 3 if (w >= 38 and h >= 26) else (2 if (w >= 26 and h >= 20) else 1)
	ctx.margin_x = margin
	ctx.margin_y = margin
	ctx.street_w = sw
	var nc := clampi(int(round(float(w - 2 * margin) / 15.0)), 1, 4)
	var nr := clampi(int(round(float(h - 2 * margin) / 15.0)), 1, 3)
	var bw := int((w - 2 * margin - (nc + 1) * sw) / nc)
	while nc > 1 and bw < 5:
		nc -= 1
		bw = int((w - 2 * margin - (nc + 1) * sw) / nc)
	bw = maxi(4, bw)
	var bh := int((h - 2 * margin - (nr + 1) * sw) / nr)
	while nr > 1 and bh < 5:
		nr -= 1
		bh = int((h - 2 * margin - (nr + 1) * sw) / nr)
	bh = maxi(4, bh)

	var leftover_x := w - 2 * margin - (nc + 1) * sw - nc * bw
	# Un bloc qui mange toute la marge : on récupère 1 case de chaque côté pour
	# garder une ceinture (tours, clôtures, végétation).
	if leftover_x == 0 and bw > 8:
		bw -= 1
		leftover_x = nc
	var x0 := margin + int(leftover_x / 2)
	var leftover_y := h - 2 * margin - (nr + 1) * sw - nr * bh
	if leftover_y == 0 and bh > 8:
		bh -= 1
		leftover_y = nr
	var y0 := margin + int(leftover_y / 2)

	# Rues verticales + colonnes d'îlots.
	var block_xs: Array = []
	var x_cursor := x0
	for i in range(nc + 1):
		ctx.streets.append(Rect2(x_cursor, y0, sw, h - 2 * margin - leftover_y))
		x_cursor += sw
		if i < nc:
			block_xs.append(x_cursor)
			x_cursor += bw
	ctx.city_x0 = float(x0)
	ctx.city_x1 = float(x_cursor)
	# Rues horizontales + rangées d'îlots.
	var block_ys: Array = []
	var y_cursor := y0
	for j in range(nr + 1):
		ctx.streets.append(Rect2(x0, y_cursor, x_cursor - x0, sw))
		y_cursor += sw
		if j < nr:
			block_ys.append(y_cursor)
			y_cursor += bh
	ctx.city_y0 = float(y0)
	ctx.city_y1 = float(y_cursor)

	for bx_variant in block_xs:
		for by_variant in block_ys:
			ctx.blocks.append(Rect2(float(bx_variant), float(by_variant), bw, bh))

	ctx.central_x = float(w) * 0.5
	ctx.central_y = float(h) * 0.5
	# Rues d'approche : on prolonge les rues les plus centrales (jamais à travers
	# un îlot) jusqu'aux bords de carte.
	ctx.approach_x = _nearest_vertical_street_center(ctx)
	ctx.approach_y = _nearest_horizontal_street_center(ctx)
	var pw := float(clampi(bw + sw, 6, 11))
	var ph := float(clampi(int(float(bh) * 0.8), 5, 8))
	ctx.plaza = Rect2(ctx.central_x - pw * 0.5, ctx.central_y - ph * 0.5, pw, ph)
	# La place est interdite aux bâtiments (elle reçoit fontaine, étals, bancs…).
	ctx.reserved.append(ctx.plaza)


static func _nearest_vertical_street_center(ctx: Context) -> float:
	var best := ctx.central_x
	var best_distance := INF
	for street_variant in ctx.streets:
		var street: Rect2 = street_variant
		if street.size.y <= street.size.x:
			continue
		var distance := absf(street.get_center().x - ctx.central_x)
		if distance < best_distance:
			best_distance = distance
			best = street.get_center().x
	return best


static func _nearest_horizontal_street_center(ctx: Context) -> float:
	var best := ctx.central_y
	var best_distance := INF
	for street_variant in ctx.streets:
		var street: Rect2 = street_variant
		if street.size.x <= street.size.y:
			continue
		var distance := absf(street.get_center().y - ctx.central_y)
		if distance < best_distance:
			best_distance = distance
			best = street.get_center().y
	return best


## Peint la chaussée du damier en **pavé** (pierre) et les quatre routes
## d'approche en terre. La place est peinte en dernier (elle recouvre les rues).
static func _paint_streets(ctx: Context) -> void:
	var paths: Array = ctx.plan["paths"]
	var w := float(ctx.width)
	var h := float(ctx.height)
	var half_street := float(ctx.street_w) * 0.5
	for street_variant in ctx.streets:
		var street: Rect2 = street_variant
		paths.append({"rect": street, "material": "stone"})
	# Approches : de la ceinture jusqu'au bord de carte, dans l'axe des rues.
	paths.append({"rect": Rect2(ctx.approach_x - half_street, 0.0,
		float(ctx.street_w), ctx.city_y0), "material": "dirt"})
	paths.append({"rect": Rect2(ctx.approach_x - half_street, ctx.city_y1,
		float(ctx.street_w), h - ctx.city_y1), "material": "dirt"})
	paths.append({"rect": Rect2(0.0, ctx.approach_y - half_street,
		ctx.city_x0, float(ctx.street_w)), "material": "dirt"})
	paths.append({"rect": Rect2(ctx.city_x1, ctx.approach_y - half_street,
		w - ctx.city_x1, float(ctx.street_w)), "material": "dirt"})
	# Place : pavée, peinte après les rues.
	ctx.plan["paths"].append({"rect": ctx.plaza, "material": "stone"})


static func _place_plaza(_ctx: Context) -> void:
	# La place n'est qu'un sol réservé (interdit aux bâtiments) : son mobilier
	# est posé par `_furnish_plaza`, qui gère lui-même les chevauchements.
	pass


# ===========================================================================
# Îlots : rangées de bâtiments tournés vers les rues
# ===========================================================================

static func _fill_blocks(ctx: Context) -> void:
	for block_variant in ctx.blocks:
		_fill_block(ctx, block_variant as Rect2)


static func _fill_block(ctx: Context, block: Rect2) -> void:
	var central := block.get_center().distance_to(Vector2(ctx.central_x, ctx.central_y)) < 10.0
	# Un édifice civique par îlot, centré sur une façade : donne le caractère de
	# « cité » (chapelle, manoir, marché, forge…) et des façades hautes à habiller.
	_fill_block_civic(ctx, block, central)
	# Puis les rangées de bâtiments de part et d'autre, alignées sur les rues.
	for side_variant in BLOCK_SIDES:
		_fill_block_side(ctx, block, side_variant as Dictionary, central)
	_fill_block_courtyard(ctx, block)


## Pose un bâtiment civique centré sur le bord d'un îlot (façade sur la rue).
static func _fill_block_civic(ctx: Context, block: Rect2, central: bool) -> void:
	if not _can_add(ctx):
		return
	var rng := ctx.rng
	var order: Array = [0, 1, 2, 3]
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var pool: Array = []
	if central:
		pool = [
			[BUILDINGS["chapelle"], 2.0],
			[BUILDINGS["manoir"], 2.0],
			[BUILDINGS["marche_couvert"], 2.0],
			[BUILDINGS["maison_etage"], 3.0],
			[BUILDINGS["forge"], 1.5],
		]
	else:
		pool = [
			[BUILDINGS["grange"], 2.0],
			[BUILDINGS["ecurie"], 2.0],
			[BUILDINGS["forge"], 2.0],
			[BUILDINGS["maison_etage"], 2.0],
			[BUILDINGS["manoir"], 1.0],
		]
	var rel := _pick_weighted(rng, pool)
	if rel.is_empty():
		return
	var dims := _dims(rel)
	for side_index_variant in order:
		var side: Dictionary = BLOCK_SIDES[int(side_index_variant)]
		var dir: Vector2 = side["dir"]
		var rotation := float(side["rotation"])
		var inward := -dir
		var horizontal := absf(dir.y) > 0.5
		var along_center := block.get_center().x if horizontal else block.get_center().y
		var edge := 0.0
		if horizontal:
			edge = block.position.y if dir.y < 0.0 else block.end.y
		else:
			edge = block.position.x if dir.x < 0.0 else block.end.x
		var center := Vector2.ZERO
		if horizontal:
			center.x = along_center
			center.y = edge + inward.y * dims.z * 0.5
		else:
			center.y = along_center
			center.x = edge + inward.x * dims.z * 0.5
		var fw := dims.x if horizontal else dims.z
		var fd := dims.z if horizontal else dims.x
		var rect := Rect2(center.x - fw * 0.5, center.y - fd * 0.5, fw, fd)
		var valid := _fits(rect, block, 0.08) \
			and not _hits(rect, ctx.reserved, 0.05) \
			and not _hits(rect, ctx.occupied, BUILDING_GAP)
		if not valid:
			continue
		if _append_building(ctx, rel, center, rotation, fw, fd):
			ctx.occupied.append(rect)
			return


static func _fill_block_side(ctx: Context, block: Rect2, side: Dictionary,
		central: bool) -> void:
	var rng := ctx.rng
	var dir: Vector2 = side["dir"]
	var rotation := float(side["rotation"])
	var inward := -dir
	var horizontal := absf(dir.y) > 0.5
	var along_start := 0.0
	var along_end := 0.0
	if horizontal:
		along_start = block.position.x + 0.55
		along_end = block.end.x - 0.55
	else:
		along_start = block.position.y + 0.55
		along_end = block.end.y - 0.55
	if along_end - along_start < 1.4:
		return
	var edge := 0.0
	if horizontal:
		edge = block.position.y if dir.y < 0.0 else block.end.y
	else:
		edge = block.position.x if dir.x < 0.0 else block.end.x

	var cursor := along_start + rng.randf_range(0.0, 0.7)
	var placed := 0
	var guard := 0
	while placed < 3 and cursor < along_end - 1.2 and guard < 14:
		guard += 1
		if not _can_add(ctx):
			return
		var rel := _pick_building(ctx, central)
		var dims := _dims(rel)
		var along_dim := dims.x
		var depth_dim := dims.z
		if cursor + along_dim > along_end:
			break
		var center := Vector2.ZERO
		if horizontal:
			center.x = cursor + along_dim * 0.5
			center.y = edge + inward.y * depth_dim * 0.5
		else:
			center.y = cursor + along_dim * 0.5
			center.x = edge + inward.x * depth_dim * 0.5
		var fw := along_dim if horizontal else depth_dim
		var fd := depth_dim if horizontal else along_dim
		var rect := Rect2(center.x - fw * 0.5, center.y - fd * 0.5, fw, fd)
		# Les façades sont posées **sur** le bord de l'îlot (rue) : on tolère un
		# léger débord de l'emprise (jupe de raccord) plutôt que de reculer.
		var valid := _fits(rect, block, 0.08) \
			and not _hits(rect, ctx.reserved, 0.05) \
			and not _hits(rect, ctx.occupied, BUILDING_GAP)
		if not valid:
			cursor += 0.45
			continue
		if _append_building(ctx, rel, center, rotation, fw, fd):
			ctx.occupied.append(rect)
			placed += 1
			# Allée d'une case entre bâtiments : la ville respire et reste lisible.
			cursor += along_dim + rng.randf_range(1.0, 1.35)
		else:
			cursor += 0.6


## Choix d'un bâtiment : les îlots proches du centre reçoivent les bâtiments
## civiques (chapelle, manoir, marché, forge), la périphérie les habitations.
static func _pick_building(ctx: Context, central: bool) -> String:
	if central:
		var pool: Array = [
			[BUILDINGS["maison_etage"], 16.0],
			[BUILDINGS["maison_grande"], 15.0],
			[BUILDINGS["maison"], 14.0],
			[BUILDINGS["manoir"], 6.0],
			[BUILDINGS["marche_couvert"], 7.0],
			[BUILDINGS["chapelle"], 5.0],
			[BUILDINGS["forge"], 6.0],
			[BUILDINGS["maison_petite"], 6.0],
		]
		return _pick_weighted(ctx.rng, pool)
	var outer: Array = [
		[BUILDINGS["maison"], 28.0],
		[BUILDINGS["maison_petite"], 20.0],
		[BUILDINGS["maison_grande"], 12.0],
		[BUILDINGS["grange"], 8.0],
		[BUILDINGS["ecurie"], 7.0],
		[BUILDINGS["forge"], 5.0],
		[BUILDINGS["maison_etage"], 9.0],
		[BUILDINGS["manoir"], 3.0],
	]
	return _pick_weighted(ctx.rng, outer)


## Ajoute un bâtiment GLB + ses accents de toit et de façade. `fw`/`fd` sont
## l'empreinte au sol **dans le repère de la carte** (déjà permutée si rotation).
static func _append_building(ctx: Context, rel: String, center: Vector2,
		rotation: float, fw: float, fd: float) -> bool:
	if not _can_add(ctx):
		return false
	var entry := {
		"asset": asset(rel),
		"x": center.x - 0.5,
		"y": center.y - 0.5,
		"rotation": rotation,
		"scale": 1.0,
		"w": fw,
		"h": fd,
		"label": LABEL_BUILDING,
		"roofs": [],
		"walls": [],
	}
	ctx.count += 1
	_add_roof_accents(ctx, entry, rel)
	_add_walls(ctx, entry, rel)
	ctx.plan["buildings"].append(entry)
	return true


# ===========================================================================
# Accents de toiture (anchor="roof")
# ===========================================================================

## Les bâtiments GLB ont **déjà leur toit cuit dans le mesh** : on n'empile donc
## jamais un module de toiture complet (double toit / effet « crêpes »). On pose
## seulement des accents discrets sur le faîtage.
static func _add_roof_accents(ctx: Context, entry: Dictionary, rel: String) -> void:
	var rng := ctx.rng
	var name := rel.get_file().get_basename()
	var bdims := _dims(rel)
	var building_top := bdims.y
	var density_factor := clampf(ctx.density, 0.6, 1.35)
	var accent := ""
	var elevation := building_top - 0.04
	var scale_r := clampf(rng.randf_range(0.95, 1.15), 0.8, 1.2)
	var forward := Vector2(0.0, 1.0).rotated(deg_to_rad(float(entry["rotation"])))
	var offset_along_roof := 0.0
	match name:
		"forge":
			# Fumée de forge : la seule cheminée vraiment justifiée.
			if rng.randf() < 0.8 * density_factor:
				accent = ROOF_ACCENTS["cheminee"]
				scale_r = clampf(rng.randf_range(0.45, 0.55), 0.4, 0.6)
				elevation = maxf(0.2, building_top - 0.03)
		"maison", "maison_grande", "maison_petite", "maison_etage", "grange", "ecurie":
			# Lucarne de toit : accent architectural discret, sans fumée blanche.
			if rng.randf() < 0.24 * density_factor:
				accent = ROOF_ACCENTS["lucarne"]
				# Posée sur le pan avant du toit, pas sur le faîtage.
				offset_along_roof = bdims.z * 0.16
				elevation = maxf(0.25, building_top * 0.78)
		_:
			accent = ""
	if accent.is_empty() or not _can_add(ctx):
		return
	var rotation := float(entry["rotation"])
	var roofs: Array = entry["roofs"]
	roofs.append({
		"asset": asset(accent),
		"x": float(entry["x"]) + forward.x * offset_along_roof \
			+ rng.randf_range(-0.12, 0.12),
		"y": float(entry["y"]) + forward.y * offset_along_roof \
			+ rng.randf_range(-0.12, 0.12),
		"rotation": rotation,
		"scale": scale_r,
		"elevation": elevation,
		"w": _dims(accent).x,
		"h": _dims(accent).z,
		"label": LABEL_ROOF,
	})
	ctx.count += 1


# ===========================================================================
# Modules de façade (anchor="wall")
# ===========================================================================

## Hauteur minimale (cases) pour qu'un module de façade tienne sur le mur sans
## dépasser du toit — les GLB de modules sont livrés à leur hauteur de pose.
const WALL_MIN_HEIGHT := {
	"porte": 2.30,
	"fenetre": 2.15,
	"balcon": 2.05,
	"colombage": 1.90,
}

static func _add_walls(ctx: Context, entry: Dictionary, rel: String) -> void:
	var rng := ctx.rng
	var name := rel.get_file().get_basename()
	var bdims := _dims(rel)
	var nw := bdims.x
	var nd := bdims.z
	var height := bdims.y
	var density_factor := clampf(ctx.density, 0.6, 1.35)
	var rotation := float(entry["rotation"])
	var front := Vector2(0.0, 1.0).rotated(deg_to_rad(rotation))
	var lateral := Vector2(1.0, 0.0).rotated(deg_to_rad(rotation))
	var front_half := nd * 0.5
	var base_x := float(entry["x"])
	var base_y := float(entry["y"])
	# Les GLB de bâtiments ont déjà porte/fenêtres/colombages **cuits dans le
	# mesh** : on n'ajoute qu'un porche discret (porte + auvent, au sol) et un
	# panneau de colombage, jamais des fenêtres/balcons suspendus (ils
	# « flotteraient » sur les façades déjà détaillées).
	var door_chance := 0.0
	var timber_chance := 0.0
	match name:
		"maison_etage":
			door_chance = 0.7
		"manoir", "chapelle":
			door_chance = 0.7
		"forge", "marche_couvert":
			door_chance = 0.65
		"grange", "ecurie":
			door_chance = 0.55
			timber_chance = 0.5
		"maison_grande":
			timber_chance = 0.35
		_:
			door_chance = 0.0
	if door_chance > 0.0 and height >= float(WALL_MIN_HEIGHT["porte"]) \
			and rng.randf() < door_chance * density_factor:
		_try_add_wall(ctx, entry, "porte", base_x, base_y, front, lateral,
			front_half, nw, 0.0, rotation)
	if timber_chance > 0.0 and height >= float(WALL_MIN_HEIGHT["colombage"]) \
			and rng.randf() < timber_chance * density_factor:
		_try_add_wall(ctx, entry, "colombage", base_x, base_y, front, lateral,
			front_half, nw, 0.0, rotation)


## Pose un module de façade sur la face avant du bâtiment : dos contre le mur,
## centre décalé de la profondeur du module. L'origine d'un module `wall` est au
## pied du mur ; la géométrie est déjà à sa hauteur de pose.
static func _try_add_wall(ctx: Context, entry: Dictionary, module_id: String,
		base_x: float, base_y: float, front: Vector2, lateral: Vector2,
		front_half: float, building_width: float, wanted_offset: float,
		rotation: float) -> void:
	if not _can_add(ctx):
		return
	var rel: String = WALL_MODULES[module_id]
	var dims := _dims(rel)
	var module_w := dims.x
	var module_d := dims.z
	var limit := maxf(0.0, building_width * 0.5 - module_w * 0.5 * 0.7)
	var offset := clampf(wanted_offset, -limit, limit)
	var back := module_d * 0.5
	var x := base_x + front.x * (front_half + back) + lateral.x * offset
	var y := base_y + front.y * (front_half + back) + lateral.y * offset
	var fw := module_w
	var fd := module_d
	if _swaps_axes(rotation):
		fw = module_d
		fd = module_w
	var walls: Array = entry["walls"]
	walls.append({
		"asset": asset(rel),
		"x": x,
		"y": y,
		"rotation": rotation,
		"scale": 1.0,
		"elevation": 0.0,
		# Décalage latéral le long de la façade : l'application recalcule la
		# position exacte à partir de l'AABB réelle du module (le pivot d'un
		# module `wall` n'est pas toujours au nu du mur).
		"offset": offset,
		"w": fw,
		"h": fd,
		"label": LABEL_WALL,
	})
	ctx.count += 1


# ===========================================================================
# Cours intérieures
# ===========================================================================

static func _fill_block_courtyard(ctx: Context, block: Rect2) -> void:
	var rng := ctx.rng
	var inner := block.grow(-2.1)
	if inner.size.x < 1.2 or inner.size.y < 1.2:
		return
	var attempts := 3
	for i in range(attempts):
		if not _can_add(ctx):
			return
		var pos := Vector2(
			rng.randf_range(inner.position.x + 0.6, inner.end.x - 0.6),
			rng.randf_range(inner.position.y + 0.6, inner.end.y - 0.6)
		)
		var roll := rng.randf()
		if i == 0 or roll < 0.34:
			_add_prop(ctx, VEGETATION["arbre"], pos, rng.randf_range(0.9, 1.2),
				rng.randf_range(0.0, 360.0), LABEL_PROP)
		elif roll < 0.62:
			_add_prop(ctx, VEGETATION["buisson"], pos, rng.randf_range(0.8, 1.1),
				rng.randf_range(0.0, 360.0), LABEL_PROP)
		elif roll < 0.8:
			_add_prop(ctx, PROPS["banc"], pos, 1.0, rng.randf_range(0.0, 360.0), LABEL_PROP)
		elif roll < 0.92:
			_add_prop(ctx, PROPS["tonneau"], pos, 0.95, rng.randf_range(0.0, 360.0), LABEL_PROP)
		else:
			_add_prop(ctx, PROPS["tas_de_bois"], pos, 0.95, rng.randf_range(0.0, 360.0), LABEL_PROP)


# ===========================================================================
# Place centrale
# ===========================================================================

static func _furnish_plaza(ctx: Context) -> void:
	var rng := ctx.rng
	var c := ctx.plaza.get_center()
	var half_w := ctx.plaza.size.x * 0.5
	var half_h := ctx.plaza.size.y * 0.5
	# Point d'eau central : fontaine (ou puits couvert, plus rustique).
	var water_asset := PROPS["fontaine"] if rng.randf() < 0.6 else PROPS["puits"]
	_add_prop(ctx, water_asset, c, 1.0, 0.0, LABEL_PROP)
	# Étals de marché autour du point d'eau.
	for side in [-1.0, 1.0]:
		_add_prop(ctx, PROPS["etal"], c + Vector2(side * minf(half_w - 1.6, 2.8), 0.0),
			1.0, 90.0 if side > 0.0 else 270.0, LABEL_PROP)
	# Bancs, bannières, lanternes sur les pourtours.
	var ring_x := maxf(1.8, half_w - 1.2)
	var ring_y := maxf(1.4, half_h - 1.1)
	for side in [-1.0, 1.0]:
		_add_prop(ctx, PROPS["banc"], c + Vector2(0.0, side * ring_y), 1.0,
			side * 90.0, LABEL_PROP)
		_add_prop(ctx, PROPS["banniere"], c + Vector2(side * ring_x, -ring_y * 0.55),
			1.0, 0.0, LABEL_PROP)
		_add_prop(ctx, PROPS["lanterne"], c + Vector2(side * ring_x, ring_y * 0.6),
			1.0, 0.0, LABEL_PROP)
		_add_prop(ctx, VEGETATION["arbre_automne"],
			c + Vector2(side * ring_x * 0.8, ring_y * 0.95), rng.randf_range(0.95, 1.15),
			rng.randf_range(0.0, 360.0), LABEL_PROP)
	# Petites marchandises éparses sur le pavé.
	var extras: Array = [PROPS["charrette"], PROPS["tonneau"], PROPS["caisse"],
		PROPS["caisse_grande"], PROPS["etal"]]
	for i in range(4):
		var angle := TAU * (float(i) + 0.35) / 4.0 + rng.randf_range(-0.25, 0.25)
		var pos := c + Vector2(cos(angle) * half_w * 0.62, sin(angle) * half_h * 0.62)
		_add_prop(ctx, str(extras[rng.randi() % extras.size()]), pos,
			rng.randf_range(0.9, 1.05), rng.randf_range(0.0, 360.0), LABEL_PROP)
	# Deux étals supplémentaires face à face (vie de la place, cf. revue Lead).
	for side in [-1.0, 1.0]:
		_add_prop(ctx, PROPS["etal"], c + Vector2(0.0, side * maxf(1.6, half_h - 1.5)),
			1.0, 0.0 if side < 0.0 else 180.0, LABEL_PROP)


# ===========================================================================
# Mobilier de rue
# ===========================================================================

static func _furnish_streets(ctx: Context) -> void:
	var rng := ctx.rng
	# Charrettes et tonneaux près de quelques carrefours.
	for i in range(mini(6, ctx.streets.size())):
		if not _can_add(ctx):
			return
		var street: Rect2 = ctx.streets[(i * 5 + 3) % ctx.streets.size()]
		var pos := street.position + Vector2(
			rng.randf_range(1.0, maxf(1.2, street.size.x - 1.0)),
			rng.randf_range(0.7, maxf(0.8, street.size.y - 0.7)))
		var roll := rng.randf()
		if roll < 0.4:
			_add_prop(ctx, PROPS["charrette"], pos, rng.randf_range(0.9, 1.0),
				rng.randf_range(0.0, 360.0), LABEL_PROP)
		elif roll < 0.75:
			_add_prop(ctx, PROPS["tonneau"], pos, rng.randf_range(0.85, 1.0),
				rng.randf_range(0.0, 360.0), LABEL_PROP)
		else:
			_add_prop(ctx, PROPS["caisse"], pos, rng.randf_range(0.85, 1.0),
				rng.randf_range(0.0, 360.0), LABEL_PROP)
	# Alignement de lanternes sur les deux grandes avenues (les trottoirs se
	# lisent d'un coup d'œil, comme dans une vraie rue).
	_lantern_row(ctx, ctx.approach_x, true)
	_lantern_row(ctx, ctx.approach_y, false)


## Quelques lanternes alignées le long d'une avenue (alternance des trottoirs),
## pieds dans la chaussée pavée : 4 par avenue, assez pour lire la rue sans
## transformer la cité en boutique de luminaires.
static func _lantern_row(ctx: Context, lane_center: float, vertical: bool) -> void:
	if not _can_add(ctx):
		return
	var half_street := float(ctx.street_w) * 0.5
	var sidewalk := maxf(0.45, half_street - 0.5)
	var start := ctx.city_y0 + 2.5 if vertical else ctx.city_x0 + 2.5
	var end := ctx.city_y1 - 1.5 if vertical else ctx.city_x1 - 1.5
	var cursor := start
	var index := 0
	while cursor < end and index < 4:
		if not _can_add(ctx):
			return
		var side := -1.0 if index % 2 == 0 else 1.0
		var pos := Vector2(lane_center + side * sidewalk, cursor) if vertical \
			else Vector2(cursor, lane_center + side * sidewalk)
		_add_prop(ctx, PROPS["lanterne"], pos, 1.0, 0.0, LABEL_PROP)
		cursor += 8.0
		index += 1


# ===========================================================================
# Angles, ceinture, végétation et rochers
# ===========================================================================

static func _place_corner_towers(ctx: Context) -> void:
	var w := float(ctx.width)
	var h := float(ctx.height)
	# Marge de 1,5 case entre le centre de la tour et le bord de carte, plus la
	# demi-empreinte : aucune tour rognée par la dalle de la carte.
	var min_edge := 1.5
	var defs: Array = [
		[BUILDINGS["tour_grande"], 0.0],
		[BUILDINGS["tour"], 0.0],
		[BUILDINGS["tour"], 180.0],
		[BUILDINGS["tour_grande"], 180.0],
	]
	var placed_index := 0
	for def_variant in defs:
		if not _can_add(ctx):
			return
		var def: Array = def_variant
		var rel := str(def[0])
		var rotation := float(def[1])
		var dims := _dims(rel)
		var fw := dims.z if _swaps_axes(rotation) else dims.x
		var fd := dims.x if _swaps_axes(rotation) else dims.z
		var inset := min_edge + maxf(fw, fd) * 0.5
		var center := Vector2.ZERO
		match placed_index:
			0:
				center = Vector2(inset, inset)
			1:
				center = Vector2(w - inset, inset)
			2:
				center = Vector2(inset, h - inset)
			_:
				center = Vector2(w - inset, h - inset)
		placed_index += 1
		var rect := Rect2(center.x - fw * 0.5, center.y - fd * 0.5, fw, fd)
		var inside := rect.position.x >= 0.0 and rect.position.y >= 0.0 \
			and rect.end.x <= w and rect.end.y <= h
		if not inside:
			continue
		var entry := {
			"asset": asset(rel),
			"x": center.x - 0.5,
			"y": center.y - 0.5,
			"rotation": rotation,
			"scale": 1.0,
			"w": fw,
			"h": fd,
			"label": LABEL_BUILDING,
			"roofs": [],
			"walls": [],
		}
		ctx.count += 1
		ctx.plan["buildings"].append(entry)
		ctx.occupied.append(rect)


static func _plant_margins(ctx: Context) -> void:
	var rng := ctx.rng
	var w := float(ctx.width)
	var h := float(ctx.height)
	var mx := float(ctx.margin_x)
	var my := float(ctx.margin_y)
	var bands: Array = [
		Rect2(0.4, 0.4, w - 0.8, my - 0.2),          # haut
		Rect2(0.4, h - my + 0.2, w - 0.8, my - 0.6), # bas
		Rect2(0.4, my, mx - 0.2, maxf(1.0, h - 2.0 * my)),   # gauche
		Rect2(w - mx + 0.2, my, mx - 0.6, maxf(1.0, h - 2.0 * my)), # droite
	]
	var target := 12 + int(float(ctx.width * ctx.height) * 0.005 * ctx.density)
	var placed := 0
	var guard := 0
	while placed < target and guard < target * 6:
		guard += 1
		if not _can_add(ctx):
			return
		var band: Rect2 = bands[rng.randi() % bands.size()]
		if band.size.x < 0.8 or band.size.y < 0.8:
			continue
		var pos := Vector2(
			rng.randf_range(band.position.x + 0.4, band.end.x - 0.4),
			rng.randf_range(band.position.y + 0.4, band.end.y - 0.4)
		)
		var roll := rng.randf()
		var rel := ""
		var scale_v := rng.randf_range(0.9, 1.25)
		if roll < 0.5:
			rel = VEGETATION["arbre"] if rng.randf() < 0.7 else VEGETATION["arbre_automne"]
		elif roll < 0.78:
			rel = VEGETATION["buisson"]
		elif roll < 0.9:
			rel = VEGETATION["haie"]
			scale_v = 1.0
		else:
			rel = VEGETATION["arbre_majestueux"]
			scale_v = rng.randf_range(0.85, 1.0)
		if _add_prop(ctx, rel, pos, scale_v, rng.randf_range(0.0, 360.0), LABEL_PROP):
			placed += 1


static func _place_margin_rocks(ctx: Context) -> void:
	var rng := ctx.rng
	var w := float(ctx.width)
	var h := float(ctx.height)
	var candidates: Array = [
		[ROCKS["falaise"], Vector2(float(ctx.margin_x) * 0.5, h * 0.32)],
		[ROCKS["falaise"], Vector2(w - float(ctx.margin_x) * 0.5, h * 0.7)],
		[ROCKS["gros_rocher"], Vector2(w * 0.24, float(ctx.margin_y) * 0.5)],
		[ROCKS["gros_rocher"], Vector2(w * 0.78, h - float(ctx.margin_y) * 0.5)],
		[ROCKS["rocher"], Vector2(w * 0.62, float(ctx.margin_y) * 0.5)],
		[ROCKS["rocher"], Vector2(w * 0.12, h - float(ctx.margin_y) * 0.5)],
		[ROCKS["rocher"], Vector2(w - float(ctx.margin_x) * 0.5, h * 0.2)],
	]
	for candidate_variant in candidates:
		if not _can_add(ctx):
			return
		var candidate: Array = candidate_variant
		var rel := str(candidate[0])
		var pos: Vector2 = candidate[1]
		if pos.x < 0.3 or pos.y < 0.3 or pos.x > w - 0.3 or pos.y > h - 0.3:
			continue
		_add_prop(ctx, rel, pos, rng.randf_range(0.95, 1.1), rng.randf_range(0.0, 360.0), LABEL_PROP)


static func _place_margin_fences(ctx: Context) -> void:
	var rng := ctx.rng
	var w := float(ctx.width)
	var h := float(ctx.height)
	var approach_x := ctx.approach_x
	var approach_y := ctx.approach_y
	var routes: Array = [
		{"from": Vector2(1.4, 0.62), "to": Vector2(w - 1.4, 0.62), "gap": approach_x},
		{"from": Vector2(1.4, h - 0.62), "to": Vector2(w - 1.4, h - 0.62), "gap": approach_x},
		{"from": Vector2(0.62, 1.4), "to": Vector2(0.62, h - 1.4), "gap": approach_y},
		{"from": Vector2(w - 0.62, 1.4), "to": Vector2(w - 0.62, h - 1.4), "gap": approach_y},
	]
	for route_variant in routes:
		var route: Dictionary = route_variant
		var from: Vector2 = route["from"]
		var to: Vector2 = route["to"]
		var gap_coord := float(route["gap"])
		var horizontal := absf(to.x - from.x) > absf(to.y - from.y)
		var length := from.distance_to(to)
		if length < 3.0:
			continue
		var direction := (to - from).normalized()
		var cursor := 1.1
		while cursor < length - 1.1:
			if not _can_add(ctx):
				return
			var pos := from + direction * cursor
			var along_gap := absf(pos.x - gap_coord) if horizontal else absf(pos.y - gap_coord)
			if along_gap < float(ctx.street_w) + 1.0:
				cursor += 1.4
				continue
			var rel := FENCES["cloture"] if rng.randf() < 0.7 else FENCES["barriere"]
			var rotation := 90.0 if not horizontal else 0.0
			if _add_prop(ctx, rel, pos, 1.0, rotation, LABEL_PROP):
				cursor += rng.randf_range(3.4, 4.2)
			else:
				cursor += 1.0


# ===========================================================================
# Burg (petites zones : 8 × 8 jusqu'à ~17 × 14)
# ===========================================================================

static func _generate_burg(ctx: Context) -> void:
	var rng := ctx.rng
	var w := ctx.width
	var h := ctx.height
	ctx.margin_x = 1
	ctx.margin_y = 1
	ctx.street_w = 1
	ctx.central_x = float(w) * 0.5
	ctx.central_y = float(h) * 0.5
	# Une seule rue en écharpe au centre, peinte en terre.
	var street := Rect2(1.0, ctx.central_y - 0.5, float(w) - 2.0, 1.0)
	ctx.plan["paths"].append({"rect": street, "material": "dirt"})
	ctx.streets.append(street)
	# Deux bâtiments de part et d'autre de la rue, s'ils tiennent.
	var rows: Array = [
		{"y": ctx.central_y - 1.9, "rotation": 0.0},
		{"y": ctx.central_y + 1.9, "rotation": 180.0},
	]
	for row_variant in rows:
		var row: Dictionary = row_variant
		var x := 2.0
		while x < float(w) - 2.2 and _can_add(ctx):
			var rel := _pick_building(ctx, false)
			var dims := _dims(rel)
			var center := Vector2(x + dims.x * 0.5, float(row["y"]))
			var rect := Rect2(center.x - dims.x * 0.5, center.y - dims.z * 0.5,
				dims.x, dims.z)
			if rect.position.x < 0.4 or rect.end.x > float(w) - 0.4 \
					or rect.position.y < 0.2 or rect.end.y > float(h) - 0.2:
				x += 0.8
				continue
			if _hits(rect, ctx.occupied, 0.35):
				x += 0.8
				continue
			if _append_building(ctx, rel, center, float(row["rotation"]),
					dims.x, dims.z):
				ctx.occupied.append(rect)
				x += dims.x + 1.0
			else:
				x += 0.8
	# Puits (ou fontaine) au milieu de la rue, plus deux arbres et une clôture.
	var center := Vector2(ctx.central_x, ctx.central_y)
	_add_prop(ctx, PROPS["puits"], center, 1.0, 0.0, LABEL_PROP)
	_add_prop(ctx, VEGETATION["arbre"], center + Vector2(-2.4, -2.2),
		rng.randf_range(0.9, 1.1), rng.randf_range(0.0, 360.0), LABEL_PROP)
	_add_prop(ctx, VEGETATION["arbre"], center + Vector2(2.4, 2.2),
		rng.randf_range(0.9, 1.1), rng.randf_range(0.0, 360.0), LABEL_PROP)
	_add_prop(ctx, PROPS["banc"], center + Vector2(1.6, 0.0), 1.0, 0.0, LABEL_PROP)
	_add_prop(ctx, PROPS["lanterne"], center + Vector2(-1.6, 0.0), 1.0, 0.0, LABEL_PROP)
	# Ceinture : quelques rochers et buissons sur les bords restés libres.
	for i in range(4):
		if not _can_add(ctx):
			return
		var pos := Vector2(rng.randf_range(0.6, float(w) - 0.6),
			rng.randf_range(0.6, float(h) - 0.6))
		if _hits(_elem_rect(pos.x, pos.y, 1.1, 1.1), ctx.occupied, 0.2):
			continue
		_add_prop(ctx, ROCKS["rocher"] if i % 2 == 0 else VEGETATION["buisson"],
			pos, rng.randf_range(0.9, 1.1), rng.randf_range(0.0, 360.0), LABEL_PROP)


# ===========================================================================
# Ajout de décor générique
# ===========================================================================

## Ajoute un prop GLB au plan s'il tient dans la carte et ne chevauche rien.
## `pos` est en coordonnées de bord de case (centre de l'élément = pos - 0.5).
static func _add_prop(ctx: Context, rel: String, pos: Vector2, scale_v: float,
		rotation: float, label: String) -> bool:
	if not _can_add(ctx):
		return false
	if rel.is_empty():
		return false
	var dims := _dims(rel)
	var fp := Vector2(dims.x, dims.z) * scale_v
	if _swaps_axes(rotation):
		fp = Vector2(dims.z, dims.x) * scale_v
	var rect := Rect2(pos.x - fp.x * 0.5, pos.y - fp.y * 0.5, fp.x, fp.y)
	if rect.position.x < 0.05 or rect.position.y < 0.05 \
			or rect.end.x > float(ctx.width) - 0.05 \
			or rect.end.y > float(ctx.height) - 0.05:
		return false
	if _hits(rect, ctx.occupied, PROP_GAP):
		return false
	ctx.occupied.append(rect)
	ctx.plan["props"].append({
		"asset": asset(rel),
		"x": pos.x - 0.5,
		"y": pos.y - 0.5,
		"rotation": rotation,
		"scale": scale_v,
		"label": label,
	})
	ctx.count += 1
	return true

# ===========================================================================
# Conversion pure plan -> elements de document (sans editeur)
# ===========================================================================
#
# Cette section est la SEULE implementation de la conversion d'un plan de scene
# en elements de document. Elle est utilisee :
#   - par l'editeur (`map_editor_construction._apply_scene_*`), qui ajoute les
#     elements au document via `doc.add_element` ;
#   - par `MapData._build_demo_catalog()`, qui materialise la carte demo
#     « Cite des Saules » sans ouvrir l'editeur (meme code => meme resultat).
# Aucune dependance a l'editeur : on peut l'appeler en headless.

const KIND_MESH := "mesh"
## Bande de hauteur (cases) ou mesurer le nu de mur reel d'un batiment.
const WALL_BAND_MIN_CELLS := 0.35

## Cache par asset : {bounds: Vector3, aabb: AABB, vertices: PackedVector3Array}.
static var _mesh_data_cache: Dictionary = {}
static var _wall_bounds_cache: Dictionary = {}

## Dimensions du manifeste pour un chemin d'asset complet (res://...).
static func asset_dims(asset_path: String) -> Vector3:
	var entry: Dictionary = AssetLibraryScript.get_object3d_meta(asset_path)
	if not entry.is_empty():
		var raw = entry.get("dimensions_cells", [])
		if raw is Array and (raw as Array).size() >= 3:
			var arr: Array = raw
			return Vector3(maxf(0.1, float(arr[0])), maxf(0.1, float(arr[2])),
				maxf(0.1, float(arr[1])))
	return Vector3(1.0, 1.0, 1.0)

## Donnees geometriques d'un GLB : AABB + dimensions reelles + sommets (contour
## encre exclu). Une seule instanciation par asset, memoisee.
static func _mesh_data(asset_path: String) -> Dictionary:
	if _mesh_data_cache.has(asset_path):
		return _mesh_data_cache[asset_path]
	var data := {"bounds": Vector3.ZERO, "aabb": AABB(), "vertices": PackedVector3Array()}
	var inst: Node3D = AssetLibraryScript.instantiate_object3d_scene(asset_path)
	if inst != null:
		var boxes: Array = []
		var vertices := PackedVector3Array()
		_collect_geometry(inst, Transform3D.IDENTITY, boxes, vertices)
		var merged := AABB()
		var first := true
		for box_variant in boxes:
			merged = box_variant if first else merged.merge(box_variant)
			first = false
		if not first and merged.size.length() > 0.0:
			data["aabb"] = merged
			data["bounds"] = merged.size
		data["vertices"] = vertices
		inst.free()
	_mesh_data_cache[asset_path] = data
	return data

static func _collect_geometry(node: Node, xform: Transform3D, boxes: Array,
		vertices: PackedVector3Array) -> void:
	var next := xform
	if node is Node3D:
		next = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if not String(mesh_instance.name).ends_with("_outline") and mesh_instance.mesh != null:
			boxes.append(next * mesh_instance.get_aabb())
			var mesh := mesh_instance.mesh
			for surface in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					vertices.append(next * vertex)
	for child in node.get_children():
		_collect_geometry(child, next, boxes, vertices)

## Dimensions reelles (cases) de la boite englobante d'un GLB.
static func mesh_bounds_cells(asset_path: String) -> Vector3:
	if asset_path.is_empty() or not asset_path.begins_with("res://"):
		return Vector3.ZERO
	return _mesh_data(asset_path)["bounds"]

## Empreinte (cases) d'un element : dimensions reelles si disponibles, sinon
## valeurs de repli du plan (rotation permute largeur/profondeur).
static func element_footprint(asset_path: String, rotation: float, scale_v: float,
		fallback: Dictionary = {}) -> Vector2:
	var bounds := mesh_bounds_cells(asset_path)
	if bounds == Vector3.ZERO:
		var dims := Vector3(float(fallback.get("w", 1.0)), 1.0,
			float(fallback.get("h", 1.0)))
		if asset_path.begins_with("res://"):
			dims = asset_dims(asset_path)
		bounds = Vector3(maxf(0.1, dims.x), maxf(0.1, dims.y), maxf(0.1, dims.z))
	var w := bounds.x
	var d := bounds.z
	if _swaps_axes(rotation):
		var tmp := w
		w = d
		d = tmp
	return Vector2(maxf(0.2, w * scale_v), maxf(0.2, d * scale_v))

## AABB horizontale (cases) des sommets dans une bande de hauteur : vrai nu de
## mur d'un batiment, au-dessus de la jupe de raccord et sous les toits.
static func mesh_wall_bounds_cells(asset_path: String, scale_v: float,
		min_y: float, max_y: float) -> AABB:
	if asset_path.is_empty():
		return AABB()
	var cache_key := "%s|%.3f|%.2f|%.2f" % [asset_path, scale_v, min_y, max_y]
	if _wall_bounds_cache.has(cache_key):
		return _wall_bounds_cache[cache_key]
	var data := _mesh_data(asset_path)
	var min_v := Vector3.ZERO
	var max_v := Vector3.ZERO
	var found := false
	for vertex in (data["vertices"] as PackedVector3Array):
		if vertex.y < min_y or vertex.y > max_y:
			continue
		if not found:
			min_v = vertex
			max_v = vertex
			found = true
		else:
			min_v = min_v.min(vertex)
			max_v = max_v.max(vertex)
	var out := AABB()
	if found:
		out = AABB(min_v * scale_v, (max_v - min_v) * scale_v)
	_wall_bounds_cache[cache_key] = out
	return out

static func _wall_band_max(asset_path: String, scale_v: float) -> float:
	return maxf(0.8, mesh_bounds_cells(asset_path).y * scale_v * 0.55)

# --- Batiments + accents de toit + facades ---------------------------------

## Elements de document pour les batiments GLB du plan (`buildings`), avec leurs
## accents de toit (elevation > 0) et leurs modules de facade ancres sur le vrai
## nu de mur. Renvoie {elements, counts}.
static func build_building_elements(plan: Dictionary, map_width: int,
		map_height: int) -> Dictionary:
	var out := {"elements": [], "counts": {"buildings": 0, "roofs": 0, "walls": 0}}
	var width := float(map_width)
	var height := float(map_height)
	for building_variant in plan.get("buildings", []):
		var building: Dictionary = building_variant
		var asset := str(building.get("asset", ""))
		if asset.is_empty() or not ResourceLoader.exists(asset):
			continue
		var x := float(building.get("x", 0.0))
		var y := float(building.get("y", 0.0))
		if x < -0.5 or y < -0.5 or x > width + 0.5 or y > height + 0.5:
			continue
		var rotation := float(building.get("rotation", 0.0))
		var scale_v := maxf(0.1, float(building.get("scale", 1.0)))
		var footprint := element_footprint(asset, rotation, scale_v, building)
		out["elements"].append({"elem": {
			"x": x, "y": y,
			"w": footprint.x, "h": footprint.y,
			"asset": asset,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": str(building.get("label", LABEL_BUILDING)),
			"layer": 1,
			"display": {"rotation": rotation, "scale": scale_v},
		}, "kind": KIND_MESH, "note": "Bâtiment GLB de scène"})
		out["counts"]["buildings"] = int(out["counts"]["buildings"]) + 1
		for roof_variant in building.get("roofs", []):
			var roof: Dictionary = roof_variant
			var roof_asset := str(roof.get("asset", ""))
			if roof_asset.is_empty() or not ResourceLoader.exists(roof_asset):
				continue
			var roof_rotation := float(roof.get("rotation", rotation))
			var roof_scale := maxf(0.1, float(roof.get("scale", 1.0)))
			var roof_footprint := element_footprint(roof_asset, roof_rotation,
				roof_scale, roof)
			out["elements"].append({"elem": {
				"x": float(roof.get("x", x)), "y": float(roof.get("y", y)),
				"w": roof_footprint.x, "h": roof_footprint.y,
				"asset": roof_asset,
				"elevation": maxf(0.0, float(roof.get("elevation", 0.0))),
				"followTerrain": true, "tiltToTerrain": false,
				"label": str(roof.get("label", LABEL_ROOF)),
				"layer": 1,
				"display": {"rotation": roof_rotation, "scale": roof_scale},
			}, "kind": KIND_MESH, "note": "Toiture de scène"})
			out["counts"]["roofs"] = int(out["counts"]["roofs"]) + 1
		for wall_variant in building.get("walls", []):
			var wall: Dictionary = wall_variant
			var wall_asset := str(wall.get("asset", ""))
			if wall_asset.is_empty() or not ResourceLoader.exists(wall_asset):
				continue
			var wall_rotation := float(wall.get("rotation", rotation))
			var wall_scale := maxf(0.1, float(wall.get("scale", 1.0)))
			var wall_footprint := element_footprint(wall_asset, wall_rotation,
				wall_scale, wall)
			var wall_x := float(wall.get("x", x))
			var wall_y := float(wall.get("y", y))
			if wall.has("offset"):
				# Ancrage sur la facade reelle : mesure du nu de mur, sinon on
				# omet le module (mieux vaut 10 modules bien poses que 20 flottants).
				var wall_bounds := mesh_wall_bounds_cells(asset, scale_v,
					WALL_BAND_MIN_CELLS, _wall_band_max(asset, scale_v))
				if wall_bounds == AABB():
					continue
				var module_dims := asset_dims(wall_asset)
				var module_w := module_dims.x * wall_scale
				var wall_width := wall_bounds.size.x
				var lateral_offset := float(wall.get("offset", 0.0)) * scale_v
				if absf(lateral_offset) + module_w * 0.5 > wall_width * 0.5 + 0.05:
					continue
				var wall_front_half := wall_bounds.position.z + wall_bounds.size.z
				if wall_front_half < 0.25:
					continue
				var front := Vector2(0.0, 1.0).rotated(deg_to_rad(rotation))
				var lateral := Vector2(1.0, 0.0).rotated(deg_to_rad(rotation))
				var back := module_dims.z * 0.5 * wall_scale
				wall_x = x + front.x * (wall_front_half + back) + lateral.x * lateral_offset
				wall_y = y + front.y * (wall_front_half + back) + lateral.y * lateral_offset
			out["elements"].append({"elem": {
				"x": wall_x, "y": wall_y,
				"w": wall_footprint.x, "h": wall_footprint.y,
				"asset": wall_asset,
				"elevation": maxf(0.0, float(wall.get("elevation", 0.0))),
				"followTerrain": true, "tiltToTerrain": false,
				"label": str(wall.get("label", LABEL_WALL)),
				"layer": 1,
				"display": {"rotation": wall_rotation, "scale": wall_scale},
			}, "kind": KIND_MESH, "note": "Façade de scène"})
			out["counts"]["walls"] = int(out["counts"]["walls"]) + 1
	return out

# --- Sols (rues, place, chemins) -------------------------------------------

## Matiere de terrain (0=herbe, 1=terre, 2=pierre, 3=neige, 4=sable).
static func material_id(material_name: String) -> int:
	match material_name:
		"stone", "paved", "pave":
			return 2
		"grass", "herbe":
			return 0
		"sand", "sable":
			return 4
		"snow", "neige":
			return 3
		_:
			return 1

## Peinture du sol du plan : {Vector2i: material}. Deux formes d'entrees :
## `{rect, material?}` (rues/place) et `{from, to, width?, material?}` (tracés).
static func build_terrain_paint(plan: Dictionary, map_width: int,
		map_height: int) -> Dictionary:
	var out: Dictionary = {}
	for path_variant in plan.get("paths", []):
		var path: Dictionary = path_variant
		var material := material_id(str(path.get("material", "")))
		if path.has("rect"):
			var area: Rect2 = path["rect"]
			var x0 := maxi(0, int(floor(area.position.x)))
			var y0 := maxi(0, int(floor(area.position.y)))
			var x1 := mini(map_width - 1, int(ceil(area.end.x)) - 1)
			var y1 := mini(map_height - 1, int(ceil(area.end.y)) - 1)
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					out[Vector2i(cx, cy)] = material
			continue
		var from: Vector2 = path.get("from", Vector2.ZERO)
		var to: Vector2 = path.get("to", Vector2.ZERO)
		var path_width := maxi(1, int(round(float(path.get("width", 1)))))
		var half_low := path_width / 2
		var half_high := path_width - 1 - half_low
		var steps := maxi(1, int(ceil(from.distance_to(to) * 2.0)))
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var cell := Vector2(round(lerpf(from.x, to.x, t)),
				round(lerpf(from.y, to.y, t)))
			for oy in range(-half_low, half_high + 1):
				for ox in range(-half_low, half_high + 1):
					var px := int(cell.x) + ox
					var py := int(cell.y) + oy
					if px < 0 or py < 0 or px >= map_width or py >= map_height:
						continue
					out[Vector2i(px, py)] = material
	return out

# --- Decors, rochers, clotures, zones fleuries -----------------------------

## Elements de document pour les props du plan (`props`).
static func build_prop_elements(plan: Dictionary) -> Array:
	var elements: Array = []
	for prop_variant in plan.get("props", []):
		var prop: Dictionary = prop_variant
		var asset := str(prop.get("asset", ""))
		if asset.is_empty() or (not asset.begins_with("procedural://") \
				and not ResourceLoader.exists(asset)):
			continue
		var scale_v := maxf(0.1, float(prop.get("scale", 1.0)))
		var rotation := float(prop.get("rotation", 0.0))
		var footprint: Vector2
		if asset.begins_with("procedural://"):
			footprint = Vector2(2.0, 2.0)
		else:
			var dims := asset_dims(asset)
			footprint = Vector2(maxf(0.3, dims.x), maxf(0.3, dims.z))
		if _swaps_axes(rotation):
			footprint = Vector2(footprint.y, footprint.x)
		elements.append({"elem": {
			"x": float(prop.get("x", 0.0)), "y": float(prop.get("y", 0.0)),
			"w": footprint.x * scale_v, "h": footprint.y * scale_v,
			"asset": asset,
			"height": 1.8 if asset == "procedural://tent" else 1.0,
			"elevation": maxf(0.0, float(prop.get("elevation", 0.0))),
			"followTerrain": bool(prop.get("followTerrain", true)),
			"tiltToTerrain": bool(prop.get("tiltToTerrain", true)),
			"label": str(prop.get("label", "Décor de scène")), "layer": 1,
			"display": {"rotation": rotation, "scale": scale_v},
		}, "kind": KIND_MESH, "note": "Décor de scène"})
	return elements

## Elements de document pour les rochers empiles du plan (`rocks`).
static func build_rock_elements(plan: Dictionary, map_width: int,
		map_height: int) -> Array:
	var elements: Array = []
	for rock_variant in plan.get("rocks", []):
		var rock: Dictionary = rock_variant
		var asset := str(rock.get("asset", ""))
		if asset.is_empty() or not ResourceLoader.exists(asset):
			continue
		var x := float(rock.get("x", 0.0))
		var y := float(rock.get("y", 0.0))
		if x < 0.0 or y < 0.0 or x > float(map_width) or y > float(map_height):
			continue
		var scale_v := maxf(0.1, float(rock.get("scale", 1.0)))
		var natural := element_footprint(asset, 0.0, 1.0, rock)
		var elevation := maxf(0.0, float(rock.get("elevation", 0.0)))
		elements.append({"elem": {
			"x": x, "y": y,
			"w": maxf(0.2, natural.x * scale_v), "h": maxf(0.2, natural.y * scale_v),
			"asset": asset,
			"elevation": elevation,
			"followTerrain": elevation <= 0.001,
			"tiltToTerrain": false,
			"label": "Rocher généré", "layer": 1,
			"display": {"rotation": float(rock.get("rotation", 0.0)), "scale": scale_v},
		}, "kind": KIND_MESH, "note": "Rocher généré"})
	return elements

## Elements de document pour les clotures procedurales du plan (`fences`).
static func build_fence_elements(plan: Dictionary) -> Array:
	var elements: Array = []
	for fence_variant in plan.get("fences", []):
		var points: Array = fence_variant
		if points.size() < 2:
			continue
		var min_p: Vector2 = points[0]
		var max_p: Vector2 = points[0]
		for p_variant in points:
			var p: Vector2 = p_variant
			min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
			max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
		var fence_center := (min_p + max_p) * 0.5
		var local: Array = []
		for p_variant in points:
			var p: Vector2 = (p_variant as Vector2) - fence_center
			local.append([p.x, p.y])
		elements.append({"elem": {
			"x": fence_center.x, "y": fence_center.y,
			"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
			"asset": "procedural://fence",
			"points": local, "height": 0.8, "spacing": 0.9,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Clôture de scène", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
		}, "kind": KIND_MESH, "note": "Clôture de scène"})
	return elements

## Elements de document pour les zones fleuries du plan (`flowerZones`).
static func build_flower_elements(plan: Dictionary, seed_base: int = 0) -> Array:
	var elements: Array = []
	for zone_variant in plan.get("flowerZones", []):
		var zone: Dictionary = zone_variant
		var rect: Rect2 = zone.get("rect", Rect2())
		if rect.size.x < 0.5 or rect.size.y < 0.5:
			continue
		var center := rect.get_center()
		var local: Array = [
			[rect.position.x - center.x, rect.position.y - center.y],
			[rect.end.x - center.x, rect.position.y - center.y],
			[rect.end.x - center.x, rect.end.y - center.y],
			[rect.position.x - center.x, rect.end.y - center.y],
		]
		elements.append({"elem": {
			"x": center.x, "y": center.y,
			"w": rect.size.x, "h": rect.size.y,
			"asset": "procedural://flower_zone",
			"points": local,
			"flowerType": str(zone.get("type", "marguerite")),
			"density": float(zone.get("density", 4.0)),
			"size": 0.3, "seed": seed_base + elements.size(),
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Zone fleurie de scène", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
		}, "kind": KIND_MESH, "note": "Zone fleurie de scène"})
	return elements

## Conversion complete d'un plan de scene en elements de document + peinture du
## sol. C'est LE point d'entree partage editeur / carte demo du Hub.
## Renvoie {elements: [{elem, kind, note}], terrain: {Vector2i: int}, counts}.
static func build_city_elements(plan: Dictionary, map_width: int,
		map_height: int) -> Dictionary:
	var buildings := build_building_elements(plan, map_width, map_height)
	var props := build_prop_elements(plan)
	var rocks := build_rock_elements(plan, map_width, map_height)
	var fences := build_fence_elements(plan)
	var flowers := build_flower_elements(plan)
	var terrain := build_terrain_paint(plan, map_width, map_height)
	var elements: Array = []
	elements.append_array(buildings["elements"])
	elements.append_array(props)
	elements.append_array(rocks)
	elements.append_array(fences)
	elements.append_array(flowers)
	var counts := {
		"paths": terrain.size(),
		"houses": 0,
		"buildings": int(buildings["counts"]["buildings"]),
		"roofs": int(buildings["counts"]["roofs"]),
		"walls": int(buildings["counts"]["walls"]),
		"fences": fences.size(),
		"flowers": flowers.size(),
		"rocks": rocks.size(),
		"props": props.size(),
	}
	return {"elements": elements, "terrain": terrain, "counts": counts}
