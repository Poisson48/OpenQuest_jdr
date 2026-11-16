extends RefCounted
class_name ProceduralRockFormation

## Planificateur pur de **formations rocheuses** pour les cartes 2.5D.
##
## Il compose une formation naturelle à partir des assets du catalogue, sans
## toucher au document ni au rendu :
##   • `bloc_rocheux_{socle,bloc,coin,couronne}` (rochers Tripo3D retravaillés,
##     task-3) pour la silhouette et les assises empilées (2 à 3 max : ce n'est
##     PAS un mur) ;
##   • `caillou_{galet_rond,galet_ovale,eclat_plat,gravier}` pour l'éboulis ;
##   • `rocher`, `gros_rocher`, `falaise` pour la variété « style projet » ;
##   • `buisson` / `roseaux` pour l'ancrage organique.
##
## Le plan renvoie des placements **prêts pour `doc.add_element` (kind mesh)** :
## `{asset, x, y, scale, rotation, elevation, label, row, role, w, h}`.
## `x`/`y` suivent la convention des plans de scène (`x + 0.5` = centre de
## l'élément en cases). `elevation` est en cases (0 = posé au sol).
##
## Garanties : déterministe (même graine ⇒ même plan), tout dans la carte,
## **aucun chevauchement des empreintes au sol** (les assises hautes sont
## contenues dans leur support), budget d'éléments borné et paramétrable.

const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

const TERRAIN_DIR := "res://assets/objects3d/terrain/"
const VEGETATION_DIR := "res://assets/objects3d/vegetation/"

# ---------------------------------------------------------------------------
# Kinds
# ---------------------------------------------------------------------------

const KIND_AFFLEUREMENT := "affleurement"
const KIND_EBOUIS := "eboulis"
const KIND_CARRIERE := "carriere"
const KIND_IDS := [KIND_AFFLEUREMENT, KIND_EBOUIS, KIND_CARRIERE]
const KIND_LABELS := {
	KIND_AFFLEUREMENT: "Affleurement",
	KIND_EBOUIS: "Éboulis",
	KIND_CARRIERE: "Carrière",
}
const KIND_LABEL_ELEMENT := {
	KIND_AFFLEUREMENT: "Affleurement rocheux",
	KIND_EBOUIS: "Éboulis rocheux",
	KIND_CARRIERE: "Carrière rocheuse",
}

# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------

## Rochers Tripo3D livrés par task-3.
const TRIPO_SOCLE := "bloc_rocheux_socle"
const TRIPO_BLOC := "bloc_rocheux_bloc"
const TRIPO_COIN := "bloc_rocheux_coin"
const TRIPO_COURONNE := "bloc_rocheux_couronne"
const TRIPO_ASSETS := [TRIPO_SOCLE, TRIPO_BLOC, TRIPO_COIN, TRIPO_COURONNE]

## Cailloux procéduraux du kit (éboulis).
const PEBBLE_ROND := "caillou_galet_rond"
const PEBBLE_OVALE := "caillou_galet_ovale"
const PEBBLE_ECLAT := "caillou_eclat_plat"
const PEBBLE_GRAVIER := "caillou_gravier"
const PEBBLE_ASSETS := [PEBBLE_ROND, PEBBLE_OVALE, PEBBLE_ECLAT, PEBBLE_GRAVIER]

## Rochers du kit historique, pour varier la silhouette.
const KIT_ROCHE := "rocher"
const KIT_GROS := "gros_rocher"
const KIT_FALAISE := "falaise"
const KIT_ROCK_ASSETS := [KIT_ROCHE, KIT_GROS, KIT_FALAISE]

const VEGETATION_ASSETS := ["buisson", "roseaux"]

const LABEL_ROCK := "Rocher de formation"
const LABEL_SCREE := "Éboulis de formation"
const LABEL_VEGETATION := "Végétation de formation"

# ---------------------------------------------------------------------------
# Bornes et conventions
# ---------------------------------------------------------------------------

const DEFAULT_MAP_WIDTH := 40
const DEFAULT_MAP_HEIGHT := 30
const DEFAULT_MAX_ELEMENTS := 28
## Nombre d'assises maximum d'une formation (le mur empilable reste ailleurs).
const MAX_ROWS := 3
const MIN_SCALE := 0.35
const MAX_SCALE := 1.35
const MIN_ELEVATION := 0.0
const MAX_ELEVATION := 4.0
## Enfoncement (cases) d'une assise haute dans son support : les sommets des
## rochers Tripo sont bombés, un léger recouvrement évite tout flottement.
const STACK_SINK := 0.12
## Marge minimale entre deux empreintes au sol (cases) : garantit l'absence de
## chevauchement visible d'un rocher sur l'autre.
const CLEARANCE := 0.06
## Marge par rapport aux bords de la carte.
const EDGE_MARGIN := 0.04
const MAX_ELEMENTS_HARD := 48
## Replis si le manifeste ne connaît pas l'asset (les cailloux n'y figurent pas).
## Vector3(x = largeur, y = hauteur, z = profondeur), en cases.
const FALLBACK_DIMS := {
	"caillou_galet_rond": Vector3(0.400, 0.198, 0.421),
	"caillou_galet_ovale": Vector3(0.290, 0.122, 0.226),
	"caillou_eclat_plat": Vector3(0.200, 0.128, 0.236),
	"caillou_gravier": Vector3(0.140, 0.086, 0.139),
	"rocher": Vector3(1.446, 0.866, 1.180),
	"gros_rocher": Vector3(2.120, 1.364, 1.884),
	"falaise": Vector3(2.319, 2.004, 2.309),
	"bloc_rocheux_socle": Vector3(1.857, 1.111, 2.050),
	"bloc_rocheux_bloc": Vector3(1.713, 0.630, 1.950),
	"bloc_rocheux_coin": Vector3(1.462, 1.414, 1.750),
	"bloc_rocheux_couronne": Vector3(1.530, 0.466, 2.000),
	"buisson": Vector3(1.230, 0.780, 1.070),
	"roseaux": Vector3(1.440, 1.740, 1.170),
}

## Cache des dimensions (une lecture de manifeste par asset).
static var _dims_cache: Dictionary = {}


# ===========================================================================
# API publique
# ===========================================================================

## Identifiants des formations disponibles.
static func kind_ids() -> Array:
	return KIND_IDS.duplicate()


## Libellé lisible d'un kind (replis sur l'identifiant brut).
static func kind_label(kind: String) -> String:
	return str(KIND_LABELS.get(kind, kind))


## Bornes cardinales d'une formation pour une carte donnée.
static func max_elements_for(kind: String, density: float = 1.0) -> int:
	var base := DEFAULT_MAX_ELEMENTS
	match kind:
		KIND_AFFLEUREMENT:
			base = 24
		KIND_EBOUIS:
			base = 28
		KIND_CARRIERE:
			base = 30
	return clampi(int(round(float(base) * clampf(density, 0.3, 2.0))), 6, MAX_ELEMENTS_HARD)


## Chemin GLB livré d'un nom d'asset (`bloc_rocheux_socle` ou chemin complet).
static func asset_path(asset: String) -> String:
	var name := asset_name(asset)
	if asset.begins_with("res://"):
		return asset
	if VEGETATION_ASSETS.has(name):
		return VEGETATION_DIR + name + ".glb"
	return TERRAIN_DIR + name + ".glb"


static func asset_name(asset: String) -> String:
	return asset.get_file().get_basename() if asset.contains("/") else asset


## Dimensions (cases) d'un asset : x = largeur, y = hauteur, z = profondeur.
static func asset_dims(asset: String) -> Vector3:
	var name := asset_name(asset)
	if _dims_cache.has(name):
		return _dims_cache[name]
	var out: Vector3 = FALLBACK_DIMS.get(name, Vector3(1.5, 1.0, 1.5))
	var meta: Dictionary = AssetLibraryScript.get_object3d_meta(asset_path(name))
	var raw = meta.get("dimensions_cells", [])
	# Le manifeste Blender stocke [X, Z, Y] : on remet la hauteur en `y`.
	if raw is Array and (raw as Array).size() >= 3:
		var arr: Array = raw
		var candidate := Vector3(
			maxf(0.05, float(arr[0])),
			maxf(0.05, float(arr[2])),
			maxf(0.05, float(arr[1]))
		)
		if candidate.length() > 0.1:
			out = candidate
	_dims_cache[name] = out
	return out


## Empreinte (cases) au sol : largeur × profondeur.
static func asset_footprint(asset: String) -> Vector2:
	var dims := asset_dims(asset)
	return Vector2(dims.x, dims.z)


## Hauteur (cases) d'un asset.
static func asset_height(asset: String) -> float:
	return asset_dims(asset).y


## Empreinte AABB (cases) d'un asset posé avec une rotation donnée : projection
## majorante de la boîte tournée, utilisée pour l'anti-chevauchement.
static func rotated_footprint(asset: String, scale_v: float = 1.0,
		rotation_deg: float = 0.0) -> Vector2:
	var fp := asset_footprint(asset) * maxf(0.01, scale_v)
	var angle := deg_to_rad(rotation_deg)
	var c := absf(cos(angle))
	var s := absf(sin(angle))
	return Vector2(fp.x * c + fp.y * s, fp.x * s + fp.y * c)


## Empreinte au sol (Rect2, coordonnées « bord de case ») d'un élément de plan.
static func element_rect(element: Dictionary) -> Rect2:
	var cx := float(element.get("x", 0.0)) + 0.5
	var cy := float(element.get("y", 0.0)) + 0.5
	var w := float(element.get("w", 0.0))
	var h := float(element.get("h", 0.0))
	return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)


## Signature stable d'un plan (test de déterminisme, debug).
static func signature(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	for element_variant in plan.get("elements", []):
		var element: Dictionary = element_variant
		parts.append("%s|%.3f|%.3f|%.2f|%.3f|%.1f|%d|%s" % [
			str(element.get("asset", "")),
			float(element.get("x", 0.0)),
			float(element.get("y", 0.0)),
			float(element.get("elevation", 0.0)),
			float(element.get("scale", 1.0)),
			float(element.get("rotation", 0.0)),
			int(element.get("row", 0)),
			str(element.get("role", "")),
		])
	return "%s#%d#%s" % [str(plan.get("kind", "")), parts.size(), "\n".join(parts)]


## Génère une formation.
##
## `origin` et `direction` sont en cases (bord de case) ; `length` est la
## longueur de la formation en cases (le long de `direction`). `density` module
## le nombre d'éléments et le budget. `options` accepte :
##   • `map_width`, `map_height` (int) : bornes de la carte (défaut 40 × 30) ;
##   • `max_elements` (int) : plafond explicite du nombre d'éléments.
##
## Renvoie `{valid, kind, label, origin, direction, length, seed, density,
## map_size, elements, bounds, count, budget}`. `valid` est faux pour un kind
## inconnu. Une formation vide (`valid=true`, `elements=[]`) est renvoyée pour
## une longueur ou une densité nulle.
static func generate(kind: String, origin: Vector2, direction: Vector2,
		length_cells: float, seed: int, density: float = 1.0,
		options: Dictionary = {}) -> Dictionary:
	var map_w := maxi(8, int(options.get("map_width", DEFAULT_MAP_WIDTH)))
	var map_h := maxi(8, int(options.get("map_height", DEFAULT_MAP_HEIGHT)))
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	var plan := {
		"valid": KIND_IDS.has(kind),
		"kind": kind,
		"label": kind_label(kind),
		"origin": origin,
		"direction": dir,
		"length": maxf(0.0, length_cells),
		"seed": seed,
		"density": clampf(density, 0.0, 2.0),
		"map_size": Vector2i(map_w, map_h),
		"elements": [],
		"bounds": Rect2(),
		"count": 0,
		"budget": 0,
	}
	if not plan["valid"]:
		return plan
	if density <= 0.0 or length_cells < 0.5:
		return plan

	var ctx := Context.new()
	ctx.kind = kind
	ctx.origin = origin
	ctx.direction = dir
	ctx.side = Vector2(-dir.y, dir.x)
	ctx.length = maxf(0.0, length_cells)
	ctx.density = clampf(density, 0.0, 2.0)
	ctx.map_w = float(map_w)
	ctx.map_h = float(map_h)
	ctx.rng = RandomNumberGenerator.new()
	ctx.rng.seed = seed
	var budget := max_elements_for(kind, ctx.density)
	if options.has("max_elements"):
		budget = mini(budget, maxi(0, int(options["max_elements"])))
	ctx.budget = budget

	match kind:
		KIND_EBOUIS:
			_build_eboulis(ctx)
		KIND_CARRIERE:
			_build_carriere(ctx)
		_:
			_build_affleurement(ctx)

	plan["elements"] = ctx.elements
	plan["count"] = ctx.elements.size()
	plan["budget"] = budget
	var bounds := Rect2()
	for element_variant in ctx.elements:
		var rect := element_rect(element_variant)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	plan["bounds"] = bounds
	return plan


# ===========================================================================
# Contexte interne
# ===========================================================================

class Context extends RefCounted:
	var kind: String = ""
	var origin: Vector2 = Vector2.ZERO
	var direction: Vector2 = Vector2.RIGHT
	var side: Vector2 = Vector2.UP
	var length: float = 0.0
	var density: float = 1.0
	var map_w: float = 1.0
	var map_h: float = 1.0
	var rng: RandomNumberGenerator
	var budget: int = 0
	var elements: Array = []
	## Rect2 (bord de case) des seuls éléments au sol : sert de vérité pour
	## l'anti-chevauchement ; les assises hautes sont contenues dans leur support.
	var occupied: Array = []


# ===========================================================================
# Affleurement : crête de blocs Tripo, assises rares, éboulis et végétation
# ===========================================================================

static func _build_affleurement(ctx: Context) -> void:
	var rng := ctx.rng
	var dir := ctx.direction
	var side := ctx.side
	var ridge := clampf(ctx.length, 2.2, 14.0)
	var base_angle := rad_to_deg(atan2(dir.y, dir.x))
	var target := clampi(int(round(ridge / 2.2 * (0.75 + 0.45 * ctx.density))), 3,
		maxi(3, int(ctx.budget * 0.42)))
	var cursor := 0.0
	var supports: Array = []
	for _i in range(target):
		if not _can_add(ctx):
			break
		var asset := _pick_weighted(rng, [
			[TRIPO_SOCLE, 0.30], [TRIPO_BLOC, 0.34],
			[TRIPO_COURONNE, 0.20], [TRIPO_COIN, 0.16],
		])
		var scale_v := rng.randf_range(0.86, 1.06)
		var rotation := base_angle + rng.randf_range(-16.0, 16.0)
		var fp := rotated_footprint(asset, scale_v, rotation)
		var half_along := 0.5 * (absf(dir.x) * fp.x + absf(dir.y) * fp.y)
		var progress := false
		for attempt in range(6):
			var lateral_range := 0.10 if attempt == 0 else 0.30
			var center := ctx.origin + dir * (cursor + half_along) \
				+ side * rng.randf_range(-lateral_range, lateral_range)
			var rect := _try_add(ctx, asset, center, scale_v, rotation, 0.0, 0,
				"silhouette", LABEL_ROCK)
			if rect.has_area():
				supports.append({
					"asset": asset,
					"rect": rect,
					"top": asset_height(asset) * scale_v,
					"center": center,
					"rotation": rotation,
					"scale": scale_v,
				})
				cursor += 2.0 * half_along + rng.randf_range(0.02, 0.16)
				progress = true
				break
			cursor += 0.30
		if not progress:
			cursor += 0.45

	# Assises empilées (2 à 3 niveaux max) : les gros rochers décoratifs sont
	# trop plats pour un mur, mais suffisants pour une crête naturelle.
	# On n'empile JAMAIS sur `bloc_rocheux_coin` : c'est une arête en biseau,
	# pas une surface d'appui (la dalle posée dessus flotterait).
	var stacked := 0
	for support_variant in supports:
		if not _can_add(ctx) or stacked >= 2:
			break
		var support: Dictionary = support_variant
		if str(support.get("asset", "")) == TRIPO_COIN:
			continue
		if stacked > 0 and rng.randf() > 0.55:
			continue
		var top_asset := _pick_weighted(rng, [
			[TRIPO_COURONNE, 0.40], [TRIPO_BLOC, 0.42], [TRIPO_COIN, 0.18],
		])
		if top_asset == TRIPO_COIN and rng.randf() < 0.5:
			top_asset = TRIPO_BLOC
		var top_scale := float(support["scale"]) * rng.randf_range(0.60, 0.80)
		var top_rotation := float(support["rotation"]) + rng.randf_range(-20.0, 20.0)
		var center: Vector2 = support["center"] \
			+ side * rng.randf_range(-0.10, 0.10) \
			+ dir * rng.randf_range(-0.10, 0.10)
		var elevation := maxf(0.0, float(support["top"]) - STACK_SINK)
		var top_rect := _try_add(ctx, top_asset, center, top_scale, top_rotation,
			elevation, 1, "assise", LABEL_ROCK, support["rect"])
		if not top_rect.has_area():
			continue
		stacked += 1
		# Troisième assise, rare : une petite dalle en couronne.
		if stacked < 3 and rng.randf() < 0.25 and _can_add(ctx):
			var crown_asset := TRIPO_COURONNE if rng.randf() < 0.65 else TRIPO_BLOC
			var crown_scale := top_scale * rng.randf_range(0.62, 0.78)
			var crown_rotation := top_rotation + rng.randf_range(-24.0, 24.0)
			var crown_center := center + side * rng.randf_range(-0.08, 0.08)
			_try_add(ctx, crown_asset, crown_center, crown_scale, crown_rotation,
				elevation + asset_height(top_asset) * top_scale - STACK_SINK * 0.6,
				2, "assise", LABEL_ROCK, top_rect)

	# Variété « style projet » : un rocher du kit à l'un des bouts.
	if rng.randf() < 0.75 and _can_add(ctx):
		var kit_asset := _pick_weighted(rng, [[KIT_GROS, 0.55], [KIT_ROCHE, 0.45]])
		var kit_scale := rng.randf_range(0.55, 0.80)
		var kit_side := 1.0 if rng.randf() < 0.5 else -1.0
		var kit_center := ctx.origin + dir * rng.randf_range(-0.6, 0.6) \
			+ side * kit_side * rng.randf_range(0.9, 1.6)
		_try_add(ctx, kit_asset, kit_center, kit_scale, rng.randf_range(0.0, 360.0),
			0.0, 0, "kit", LABEL_ROCK)

	# Éboulis au pied de la crête, des deux côtés.
	var scree_target := clampi(int(round(ridge * 0.9 * ctx.density)), 2, 12)
	for _i in range(scree_target):
		if not _can_add(ctx):
			break
		var t := rng.randf_range(0.0, ridge)
		var lateral := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.65, 1.9)
		var center := ctx.origin + dir * t + side * lateral
		var pebble := _pick_pebble(rng)
		_try_add(ctx, pebble, center, rng.randf_range(0.80, 1.25),
			rng.randf_range(0.0, 360.0), 0.0, 0, "eboulis", LABEL_SCREE)

	# Ancrage organique : un ou deux buissons/roseaux.
	_place_vegetation(ctx, 2, 1.6, 0.65)


# ===========================================================================
# Éboulis : cône de pierrailles qui s'élargit depuis l'origine
# ===========================================================================

static func _build_eboulis(ctx: Context) -> void:
	var rng := ctx.rng
	var dir := ctx.direction
	var side := ctx.side
	var fan := clampf(ctx.length, 1.5, 10.0)
	# Gros blocs en amont (ce qui s'est détaché de la paroi).
	var chunks := clampi(int(round(2.5 * ctx.density)), 1, 4)
	for _i in range(chunks):
		if not _can_add(ctx):
			break
		var chunk_asset := _pick_weighted(rng, [
			[TRIPO_BLOC, 0.34], [TRIPO_COURONNE, 0.33],
			[TRIPO_SOCLE, 0.18], [PEBBLE_ROND, 0.15],
		])
		var chunk_scale := rng.randf_range(0.50, 0.75)
		var center := ctx.origin + dir * rng.randf_range(0.3, 1.6) \
			+ side * rng.randf_range(-0.9, 0.9)
		_try_add(ctx, chunk_asset, center, chunk_scale, rng.randf_range(0.0, 360.0),
			0.0, 0, "amont", LABEL_ROCK)
	# Cône de cailloux : plus on s'éloigne, plus la nappe s'élargit.
	var target := clampi(int(round(fan * 3.6 * ctx.density)), 3,
		maxi(3, int(ctx.budget * 0.68)))
	for _i in range(target):
		if not _can_add(ctx):
			break
		var distance := rng.randf_range(0.1, fan)
		var spread := 0.30 + distance * 0.26
		var center := ctx.origin + dir * distance + side * rng.randf_range(-spread, spread)
		var pebble := _pick_pebble(rng)
		_try_add(ctx, pebble, center, rng.randf_range(0.85, 1.35),
			rng.randf_range(0.0, 360.0), 0.0, 0, "eboulis", LABEL_SCREE)
	# Rocher du kit isolé sur un bord, puis végétation de lisière.
	if rng.randf() < 0.60 and _can_add(ctx):
		var kit_center := ctx.origin + dir * rng.randf_range(-0.4, 0.8) \
			+ side * (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(1.4, 2.4)
		_try_add(ctx, KIT_ROCHE, kit_center, rng.randf_range(0.42, 0.58),
			rng.randf_range(0.0, 360.0), 0.0, 0, "kit", LABEL_ROCK)
	_place_vegetation(ctx, 2, 1.8, 0.55)


# ===========================================================================
# Carrière : front de taille en deux assises + éboulis d'abattage
# ===========================================================================

static func _build_carriere(ctx: Context) -> void:
	var rng := ctx.rng
	var dir := ctx.direction
	var side := ctx.side
	var face := clampf(ctx.length, 3.0, 12.0)
	var base_angle := rad_to_deg(atan2(dir.y, dir.x))
	var target := clampi(int(round(face / 2.1 * (0.75 + 0.35 * ctx.density))), 3,
		maxi(3, int(ctx.budget * 0.38)))
	var cursor := 0.0
	var supports: Array = []
	for _i in range(target):
		if not _can_add(ctx):
			break
		var asset := _pick_weighted(rng, [
			[KIT_FALAISE, 0.28], [KIT_GROS, 0.30],
			[TRIPO_SOCLE, 0.26], [TRIPO_COIN, 0.16],
		])
		var scale_v := rng.randf_range(0.86, 1.04)
		var rotation := base_angle + rng.randf_range(-11.0, 11.0)
		var fp := rotated_footprint(asset, scale_v, rotation)
		var half_along := 0.5 * (absf(dir.x) * fp.x + absf(dir.y) * fp.y)
		var progress := false
		for attempt in range(6):
			var lateral_range := 0.08 if attempt == 0 else 0.22
			var center := ctx.origin + dir * (cursor + half_along) \
				+ side * rng.randf_range(-lateral_range, lateral_range) * -1.0
			var rect := _try_add(ctx, asset, center, scale_v, rotation, 0.0, 0,
				"front", LABEL_ROCK)
			if rect.has_area():
				supports.append({
					"asset": asset,
					"rect": rect,
					"top": asset_height(asset) * scale_v,
					"center": center,
					"rotation": rotation,
					"scale": scale_v,
				})
				cursor += 2.0 * half_along + rng.randf_range(0.02, 0.14)
				progress = true
				break
			cursor += 0.30
		if not progress:
			cursor += 0.40

	# Deuxième assise du front de taille (2 niveaux max : une carrière, pas un mur).
	# Comme pour l'affleurement, pas d'empilement sur le coin en biseau.
	var stacked := 0
	for support_variant in supports:
		if not _can_add(ctx) or stacked >= 3:
			break
		var support: Dictionary = support_variant
		if str(support.get("asset", "")) == TRIPO_COIN:
			continue
		if rng.randf() > 0.68:
			continue
		var top_asset := _pick_weighted(rng, [
			[TRIPO_BLOC, 0.45], [TRIPO_COURONNE, 0.40], [TRIPO_COIN, 0.15],
		])
		var top_scale := float(support["scale"]) * rng.randf_range(0.62, 0.82)
		var top_rotation := float(support["rotation"]) + rng.randf_range(-16.0, 16.0)
		var center: Vector2 = support["center"] + side * rng.randf_range(-0.10, 0.10) \
			- ctx.side * 0.06
		var elevation := maxf(0.0, float(support["top"]) - STACK_SINK)
		if _try_add(ctx, top_asset, center, top_scale, top_rotation, elevation, 1,
				"assise", LABEL_ROCK, support["rect"]).has_area():
			stacked += 1

	# Banquette arrière (côté opposé à l'éboulis) : blocs bas pour la profondeur.
	for _i in range(2):
		if not _can_add(ctx):
			break
		var back_asset := _pick_weighted(rng, [[TRIPO_BLOC, 0.5], [TRIPO_COURONNE, 0.5]])
		var back_center := ctx.origin + dir * rng.randf_range(0.4, face) \
			+ side * (-1.0) * rng.randf_range(1.3, 2.4)
		_try_add(ctx, back_asset, back_center, rng.randf_range(0.62, 0.82),
			rng.randf_range(0.0, 360.0), 0.0, 0, "arriere", LABEL_ROCK)

	# Éboulis d'abattage devant le front (côté +side).
	var scree_target := clampi(int(round(face * 2.0 * ctx.density)), 3,
		maxi(3, int(ctx.budget * 0.45)))
	for _i in range(scree_target):
		if not _can_add(ctx):
			break
		var distance := rng.randf_range(0.2, face)
		var lateral := rng.randf_range(0.8, 2.7)
		var center := ctx.origin + dir * distance + side * lateral
		var pebble := _pick_pebble(rng)
		_try_add(ctx, pebble, center, rng.randf_range(0.85, 1.30),
			rng.randf_range(0.0, 360.0), 0.0, 0, "eboulis", LABEL_SCREE)
	# Végétation derrière la banquette (la carrière repousse).
	_place_vegetation(ctx, 2, 2.2, 0.60, -1.0)


# ===========================================================================
# Helpers de placement
# ===========================================================================

static func _can_add(ctx: Context) -> bool:
	return ctx.elements.size() < ctx.budget


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


static func _pick_pebble(rng: RandomNumberGenerator) -> String:
	return _pick_weighted(rng, [
		[PEBBLE_ROND, 0.28], [PEBBLE_OVALE, 0.26],
		[PEBBLE_ECLAT, 0.24], [PEBBLE_GRAVIER, 0.22],
	])


## Ajoute un élément au plan. Renvoie son Rect2 (bord de case) ou un Rect2 vide
## en cas de refus : hors carte, chevauchement au sol, assise non contenue dans
## son support, budget atteint.
static func _try_add(ctx: Context, asset: String, center: Vector2, scale_v: float,
		rotation: float, elevation: float = 0.0, row: int = 0, role: String = "",
		label: String = "", support: Rect2 = Rect2()) -> Rect2:
	if not _can_add(ctx) or asset.is_empty():
		return Rect2()
	if not ResourceLoader.exists(asset_path(asset)) \
			and not FileAccess.file_exists(asset_path(asset)):
		return Rect2()
	var scale_limited := clampf(scale_v, MIN_SCALE, MAX_SCALE)
	var elevation_limited := clampf(elevation, MIN_ELEVATION, MAX_ELEVATION)
	var rotation_wrapped := fposmod(rotation, 360.0)
	var fp := rotated_footprint(asset, scale_limited, rotation_wrapped)
	var rect := Rect2(center - fp * 0.5, fp)
	# Tout doit rester dans la carte, avec une petite marge.
	if rect.position.x < EDGE_MARGIN or rect.position.y < EDGE_MARGIN \
			or rect.end.x > ctx.map_w - EDGE_MARGIN \
			or rect.end.y > ctx.map_h - EDGE_MARGIN:
		return Rect2()
	if elevation_limited <= 0.001:
		if _hits(rect, ctx.occupied, CLEARANCE):
			return Rect2()
		ctx.occupied.append(rect)
	elif not support.has_area() or not support.grow(CLEARANCE).encloses(rect):
		# Une assise haute doit reposer sur son support, sans surplomb flottant.
		return Rect2()
	ctx.elements.append({
		"asset": asset_path(asset),
		"name": asset_name(asset),
		"x": center.x - 0.5,
		"y": center.y - 0.5,
		"w": fp.x,
		"h": fp.y,
		"scale": scale_limited,
		"rotation": rotation_wrapped,
		"elevation": elevation_limited,
		"row": row,
		"role": role,
		"label": label if not label.is_empty() else LABEL_ROCK,
	})
	return rect


static func _hits(rect: Rect2, others: Array, grow: float = 0.0) -> bool:
	for other_variant in others:
		if (other_variant as Rect2).grow(grow).intersects(rect):
			return true
	return false


## Pose un ou deux buissons/roseaux sur le flanc de la formation
## (`side_sign` = -1 pour le côté opposé à la direction latérale).
static func _place_vegetation(ctx: Context, count: int, distance: float,
		chance: float, side_sign: float = 1.0) -> void:
	var rng := ctx.rng
	for _i in range(count):
		if not _can_add(ctx) or rng.randf() > chance:
			continue
		var asset := "buisson" if rng.randf() < 0.7 else "roseaux"
		var center := ctx.origin \
			+ ctx.direction * rng.randf_range(0.0, maxf(0.5, ctx.length)) \
			+ ctx.side * side_sign * rng.randf_range(distance, distance + 1.4)
		var scale_v := rng.randf_range(0.70, 0.95)
		_try_add(ctx, asset, center, scale_v, rng.randf_range(0.0, 360.0),
			0.0, 0, "vegetation", LABEL_VEGETATION)
