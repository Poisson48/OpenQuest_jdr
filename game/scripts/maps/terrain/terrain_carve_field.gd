extends RefCounted
class_name TerrainCarveField

## Champ scalaire « terre / vide » du terrain creusé (Voie B — creusements
## volumétriques, cf. `docs/RAPPORT_TERRAIN_DEFORMABLE.md`).
##
## Le champ combine :
##   • le **heightfield de base** (`terrainHeights`, une hauteur par case) ;
##   • des **primitives SDF** éditables (`map_data["terrainCarves"]`) :
##       - `op = "subtract"` : creuse (trou, puits, grotte, tunnel) ;
##       - `op = "union"`    : remblaye (ajoute de la terre, talus, remblai).
##
## Convention : `sample(p) >= 0` = matière (solide), `< 0` = vide. Toutes les
## coordonnées publiques sont **en cases** (même repère que `terrainHeights`) ;
## le monde multiplie par `cell_size`.
##
## Le heightfield est échantillonné **exactement** comme le maillage de sol
## (`MapGround3D._vertex_height_at` : moyenne des cases adjacentes aux sommets
## puis interpolation bilinéaire) afin que le maillage Marching Cubes des
## creusements raccorde avec le maillage heightfield le long des bords de
## cluster. La convention de placement des objets (interpolation bilinéaire des
## hauteurs de cases, `ComplexMapEngine3D.terrain_height_at`) est conservée via
## `cell_bilinear()` : aucun objet ne bouge sur une carte sans creusement.
##
## Requêtes fournies :
##   • `sample(p)`          — champ scalaire (SDF approché) ;
##   • `top_surface_at()`   — sol visible depuis le dessus, creusements compris ;
##   • `normal_at()`        — normale de surface (gradient du champ) ;
##   • `raycast()`          — marche de rayon + bissection (picking terrain).

const OP_SUBTRACT := "subtract"
const OP_UNION := "union"
const SHAPE_SPHERE := "sphere"
const SHAPE_CAPSULE := "capsule"
const SHAPE_BOX := "box"
const VALID_OPS := [OP_SUBTRACT, OP_UNION]
const VALID_SHAPES := [SHAPE_SPHERE, SHAPE_CAPSULE, SHAPE_BOX]
## Lissage de jonction par défaut, en cases (rayon de transition du smooth-min).
const DEFAULT_SMOOTH := 0.30
const SMOOTH_RANGE := 2.0
## Profondeur mini/maxi des prims (cases) — garde-fous cohérents avec le
## clamp [-2, 12] des hauteurs.
const PRIM_MIN_Y := -12.0
const PRIM_MAX_Y := 24.0
const PRIM_MAX_RADIUS := 32.0
const PROBE_EPS := 0.001
## Pas de la descente de colonne (cases) pour `top_surface_at`.
const SCAN_STEP := 0.1
## Pas de marche de rayon (cases) pour `raycast`.
const RAY_STEP := 0.2

var _heights: Array = []
var _w: int = 0
var _h: int = 0
var _carves: Array = []          # dictionnaires normalisés (forme stockée)
## Formes internes en tableaux typés — `sample()` est le point chaud (des
## dizaines de milliers d'appels par rebuild MC) : aucun dictionnaire, aucune
## conversion de chaîne dans la boucle. 9 flottants par primitive :
##   sphere  : cx,cy,cz,r,-,-,-,-,smooth
##   capsule : ax,ay,az,bx,by,bz,r,-,smooth
##   box     : cx,cy,cz,hx,hy,hz,cos(yaw),sin(yaw),smooth
const PRIM_STRIDE := 9
var _op_codes := PackedInt32Array()    # 0 = subtract (creuser), 1 = union (remblayer)
var _shape_codes := PackedInt32Array() # 0 = sphere, 1 = capsule, 2 = box
var _params := PackedFloat32Array()
var _prim_bounds: Array = []     # AABB par primitive (même ordre)
var _scan_bottom: float = -4.0
# --- Sculpture volumétrique (déplacement lissé, façon argile) --------------
# Grille 3D de **déplacement** `G` (cases) : le champ devient
# `F(p) = height_at(x,z) + G(p) - p.y` (combiné aux primitives). Les brosses
# y accumulent un noyau doux `(1-d²/R²)²` — la surface se déforme en
# continu (terraforming), sans jamais former de « boules ». G > 0 : matière
# ajoutée (butte, surplomb) ; G < 0 : matière retirée (fosse, tunnel).
## Résolution de la grille de sculpture (voxels par case).
const SCULPT_RES := 2
## Étendue verticale de la grille (cases) : hauteurs (-2..12) + carves +
## surplombs sculptés.
const SCULPT_Y0 := -8.0
const SCULPT_Y1 := 24.0
## Quantification JSON (1/64 de case par pas) pour la sérialisation.
const SCULPT_QUANT := 64.0
## Côté des chunks de sérialisation (voxels).
const SCULPT_CHUNK := 8
var _sculpt: PackedFloat32Array = PackedFloat32Array()
var _sculpt_dims := Vector3i.ZERO
## Cache des hauteurs de sommets `(w+1)*(h+1)` — les échantillonnages MC et
## pinceaux appellent `height_at` des dizaines de milliers de fois ; recalculer
## les moyennes 2×2 à chaque appel coûtait ~16 lectures de case par échantillon.
var _vertex_cache: PackedFloat32Array = PackedFloat32Array()

# ===========================================================================
# Normalisation des primitives (forme stockée dans map_data / JSON)
# ===========================================================================

## Normalise une primitive de creusement. Champs reconnus :
##   id (String), op ("subtract"|"union"), shape ("sphere"|"capsule"|"box"),
##   center [x,y,z] (sphere/box), a & b [x,y,z] (capsule), radius (sphere/
##   capsule), half [hx,hy,hz] (box), yaw (degrés, box), smooth (cases),
##   note (String). Toute valeur absente/illogique prend un défaut sûr ;
##   renvoie un dictionnaire **sérialisable JSON** (tableaux de floats).
static func normalize_carve(entry: Dictionary) -> Dictionary:
	var out := {}
	var id := str(entry.get("id", "")).strip_edges()
	if id.is_empty():
		id = "carve_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	out["id"] = id
	var op := str(entry.get("op", OP_SUBTRACT)).strip_edges().to_lower()
	out["op"] = OP_UNION if op == OP_UNION else OP_SUBTRACT
	var shape := str(entry.get("shape", SHAPE_SPHERE)).strip_edges().to_lower()
	if not VALID_SHAPES.has(shape):
		shape = SHAPE_SPHERE
	out["shape"] = shape
	out["smooth"] = clampf(float(entry.get("smooth", DEFAULT_SMOOTH)), 0.0, SMOOTH_RANGE)
	out["note"] = str(entry.get("note", ""))
	match shape:
		SHAPE_CAPSULE:
			out["a"] = _clamp_vec(_read_vec(entry.get("a"), Vector3.ZERO))
			out["b"] = _clamp_vec(_read_vec(entry.get("b"), Vector3(0.0, -1.0, 0.0)))
			out["radius"] = clampf(float(entry.get("radius", 0.5)), 0.05, PRIM_MAX_RADIUS)
		SHAPE_BOX:
			out["center"] = _clamp_vec(_read_vec(entry.get("center"), Vector3.ZERO))
			var half := _read_vec(entry.get("half"), Vector3(0.5, 0.5, 0.5))
			out["half"] = Vector3(
				clampf(absf(half.x), 0.05, PRIM_MAX_RADIUS),
				clampf(absf(half.y), 0.05, PRIM_MAX_RADIUS),
				clampf(absf(half.z), 0.05, PRIM_MAX_RADIUS)
			)
			out["yaw"] = fmod(float(entry.get("yaw", 0.0)), 360.0)
		_:
			out["center"] = _clamp_vec(_read_vec(entry.get("center"), Vector3.ZERO))
			out["radius"] = clampf(float(entry.get("radius", 0.5)), 0.05, PRIM_MAX_RADIUS)
	return out

## Normalise une liste de primitives (les entrées invalides sont ignorées).
static func normalize_carves(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		if entry is Dictionary:
			out.append(normalize_carve(entry))
	return out

## Copie JSON-sûre (Vector3 → tableaux) pour la sérialisation.
static func to_json_carve(entry: Dictionary) -> Dictionary:
	var out := entry.duplicate(true)
	for key in ["center", "a", "b", "half"]:
		if out.has(key) and out[key] is Vector3:
			var v: Vector3 = out[key]
			out[key] = [v.x, v.y, v.z]
	return out

static func to_json_carves(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if entry is Dictionary:
			out.append(to_json_carve(entry))
	return out

static func _read_vec(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func _clamp_vec(v: Vector3) -> Vector3:
	return Vector3(
		clampf(v.x, -256.0, 256.0),
		clampf(v.y, PRIM_MIN_Y, PRIM_MAX_Y),
		clampf(v.z, -256.0, 256.0)
	)

## AABB englobante (cases) d'une primitive normalisée : {x0,y0,z0,x1,y1,z1}.
static func bounds_of(entry: Dictionary) -> Dictionary:
	var shape := str(entry.get("shape", SHAPE_SPHERE))
	match shape:
		SHAPE_CAPSULE:
			var a := _read_vec(entry.get("a"), Vector3.ZERO)
			var b := _read_vec(entry.get("b"), Vector3.ZERO)
			var r := float(entry.get("radius", 0.5))
			return {
				"x0": minf(a.x, b.x) - r, "x1": maxf(a.x, b.x) + r,
				"y0": minf(a.y, b.y) - r, "y1": maxf(a.y, b.y) + r,
				"z0": minf(a.z, b.z) - r, "z1": maxf(a.z, b.z) + r,
			}
		SHAPE_BOX:
			var c := _read_vec(entry.get("center"), Vector3.ZERO)
			var half := _read_vec(entry.get("half"), Vector3(0.5, 0.5, 0.5))
			var yaw := deg_to_rad(float(entry.get("yaw", 0.0)))
			# Demi-extension XZ après rotation (borne conservative).
			var rx := absf(cos(yaw)) * half.x + absf(sin(yaw)) * half.z
			var rz := absf(sin(yaw)) * half.x + absf(cos(yaw)) * half.z
			return {
				"x0": c.x - rx, "x1": c.x + rx,
				"y0": c.y - half.y, "y1": c.y + half.y,
				"z0": c.z - rz, "z1": c.z + rz,
			}
		_:
			var c2 := _read_vec(entry.get("center"), Vector3.ZERO)
			var r2 := float(entry.get("radius", 0.5))
			return {
				"x0": c2.x - r2, "x1": c2.x + r2,
				"y0": c2.y - r2, "y1": c2.y + r2,
				"z0": c2.z - r2, "z1": c2.z + r2,
			}

# ===========================================================================
# Construction / mise à jour
# ===========================================================================

## Construit un champ pour (hauteurs de cases, largeur, hauteur, carves,
## sculpture). (Constructeur plutôt que factory : la classe est préchargée par
## les consommateurs, indépendamment du cache global `class_name`.)
func _init(heights: Array = [], map_w: int = 0, map_h: int = 0,
		carves: Array = [], sculpt: Dictionary = {}) -> void:
	set_data(heights, map_w, map_h, carves)
	if sculpt is Dictionary and not (sculpt as Dictionary).is_empty():
		set_sculpt(sculpt)

func set_data(heights: Array, map_w: int, map_h: int, carves: Array = []) -> void:
	_heights = heights if heights is Array else []
	_w = maxi(0, map_w)
	_h = maxi(0, map_h)
	_rebuild_vertex_cache()
	set_carves(carves)

# ---------------------------------------------------------------------------
# Sculpture volumétrique (grille de déplacement)
# ---------------------------------------------------------------------------

## Alloue la grille de sculpture (dense, paresseuse) aux dimensions de la carte.
func _ensure_sculpt() -> void:
	var dims := Vector3i(
		maxi(1, _w * SCULPT_RES),
		maxi(1, int((SCULPT_Y1 - SCULPT_Y0) * SCULPT_RES)),
		maxi(1, _h * SCULPT_RES))
	if _sculpt.size() == dims.x * dims.y * dims.z:
		return
	_sculpt.resize(dims.x * dims.y * dims.z)
	_sculpt.fill(0.0)
	_sculpt_dims = dims

## Déplacement `G` (cases) en un point, trilinéaire — 0 hors grille.
## Les voxels sont échantillonnés à leur CENTRE (`i` couvre `[i/res,(i+1)/res]`
## mais porte la valeur du centre `(i+0.5)/res`).
func sculpt_at(p: Vector3) -> float:
	if _sculpt.is_empty():
		return 0.0
	var fx := p.x * SCULPT_RES - 0.5
	var fy := (p.y - SCULPT_Y0) * SCULPT_RES - 0.5
	var fz := p.z * SCULPT_RES - 0.5
	if fx < 0.0 or fy < 0.0 or fz < 0.0:
		return 0.0
	var x0 := floori(fx)
	var y0 := floori(fy)
	var z0 := floori(fz)
	if x0 >= _sculpt_dims.x - 1 or y0 >= _sculpt_dims.y - 1 or z0 >= _sculpt_dims.z - 1:
		return 0.0
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var tz := fz - float(z0)
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var base := x0 + y0 * s + z0 * t
	var c000 := _sculpt[base]
	var c100 := _sculpt[base + 1]
	var c010 := _sculpt[base + s]
	var c110 := _sculpt[base + s + 1]
	var c001 := _sculpt[base + t]
	var c101 := _sculpt[base + t + 1]
	var c011 := _sculpt[base + t + s]
	var c111 := _sculpt[base + t + s + 1]
	var c00 := lerpf(c000, c100, tx)
	var c10 := lerpf(c010, c110, tx)
	var c01 := lerpf(c001, c101, tx)
	var c11 := lerpf(c011, c111, tx)
	return lerpf(lerpf(c00, c10, ty), lerpf(c01, c11, ty), tz)

## Vrai si une sculpture existe (le déplacement n'est plus nul quelque part).
func has_sculpt() -> bool:
	for v in _sculpt:
		if absf(float(v)) > 0.0005:
			return true
	return false

## Courbes de dégradé façon Blender (t = distance/rayon ∈ [0,1]) :
## 0 = Doux (défaut, historique), 1 = Sphère, 2 = Racine, 3 = Net,
## 4 = Linéaire, 5 = Constant.
static func _falloff_curve(falloff: int, t: float) -> float:
	if t >= 1.0:
		return 0.0
	match falloff:
		1:
			return sqrt(1.0 - t * t)
		2:
			return sqrt(1.0 - t)
		3:
			return (1.0 - t) * (1.0 - t)
		4:
			return 1.0 - t
		5:
			return 1.0
		_:
			var q := 1.0 - t * t
			return q * q

## Tampon de sculpture : déplace **toute la colonne** (x, z) dans le rayon de
## `strength × dégradé doux`. La surface monte/descend d'exactement cette
## valeur à chaque pas — comme les brosses de terrain de Planet Zoo et la
## brosse Draw de Blender : les passages successifs s'accumulent **sans
## plafond ni rendement décroissant**, ce qui permet de monter une montagne
## en insistant. `kernel` : 0 = rond (Draw), 1 = plateau (Clay), 2 = rectangle
## orienté `angle` (Clay Strips), 3 = étroit (Draw Sharp). `falloff` : courbe
## du noyau rond (voir `_falloff_curve`). `smooth_after` : auto-lissage léger
## du pourtour dans le même pas d'undo (comme l'Auto-Smooth de Blender).
func sculpt_stamp(center: Vector3, radius: float, strength: float,
		kernel: int = 0, angle: float = 0.0, falloff: int = 0,
		smooth_after: float = 0.0) -> Array:
	_ensure_sculpt()
	var r := maxf(0.15, radius)
	if absf(strength) < 0.00001:
		return []
	var touched := {}
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r) * SCULPT_RES))
	var r2 := r * r
	var ca := cos(angle)
	var sa := sin(angle)
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		var dz := pz - center.z
		for x in range(x_min, x_max + 1):
			var px := (float(x) + 0.5) / SCULPT_RES
			var dx := px - center.x
			var k := 0.0
			match kernel:
				1:
					# Argile : profil en plateau (dépôt franc au centre,
					# lissé sur le pourtour).
					var d: float = sqrt(dx * dx + dz * dz) / r
					if d < 1.0:
						k = 1.0 - smoothstep(0.55, 1.0, d)
				2:
					# Bandes d'argile : rectangle étiré le long de l'orientation
					# (une bande, pas un carré).
					var lx := ca * dx + sa * dz
					var lz := -sa * dx + ca * dz
					var across := r * 0.45
					if absf(lx) < r and absf(lz) < across:
						k = (1.0 - smoothstep(0.7, 1.0, absf(lx) / r)) \
							* (1.0 - smoothstep(0.7, 1.0, absf(lz) / across))
				3:
					# Dessin net (Draw Sharp) : noyau étroit à parois raides
					# (la hauteur décroît en puissance — traits fins).
					var d: float = sqrt(dx * dx + dz * dz) / r
					if d < 1.0:
						k = pow(1.0 - d, 2.5)
				_:
					var d2 := dx * dx + dz * dz
					if d2 < r2:
						k = _falloff_curve(falloff, sqrt(d2) / r)
			if k <= 0.0001:
				continue
			var delta := strength * k
			# Toute la colonne est déplacée : le point fixe de la surface
			# (base + G = y) monte alors d'exactement `delta` — pas de
			# rendement décroissant quand on repasse sur la même zone.
			for y in range(_sculpt_dims.y):
				var idx := x + y * s + z * t
				var old := _sculpt[idx]
				_sculpt[idx] = clampf(old + delta, -12.0, 12.0)
				if not touched.has(idx):
					touched[idx] = old
	if smooth_after > 0.0001:
		# Auto-lissage (comme l'Auto-Smooth de Blender) : léger flou latéral
		# du pourtour, dans le MÊME pas d'undo que le tampon.
		for z in range(z_min, z_max + 1):
			var pz := (float(z) + 0.5) / SCULPT_RES
			var dz := pz - center.z
			for x in range(x_min, x_max + 1):
				var px := (float(x) + 0.5) / SCULPT_RES
				var dx := px - center.x
				var d := sqrt(dx * dx + dz * dz) / r
				if d >= 1.0:
					continue
				var w := smooth_after * (1.0 - d * d)
				for y in range(_sculpt_dims.y):
					var idx := x + y * s + z * t
					var avg := _sculpt_neighbor_avg(x, y, z, true)
					var old2 := _sculpt[idx]
					var want := lerpf(old2, avg, clampf(w, 0.0, 1.0))
					if want != old2:
						if not touched.has(idx):
							touched[idx] = old2
						_sculpt[idx] = want
	return _snapshot_delta(touched)

## Lissage local (flou du déplacement) dans la boule — brosse « Lisser ».
func sculpt_smooth(center: Vector3, radius: float) -> Array:
	_ensure_sculpt()
	var r := maxf(0.15, radius)
	var touched := {}
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r) * SCULPT_RES))
	var y_min := maxi(0, floori((center.y - r - SCULPT_Y0) * SCULPT_RES))
	var y_max := mini(_sculpt_dims.y - 1, ceili((center.y + r - SCULPT_Y0) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r) * SCULPT_RES))
	var r2 := r * r
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		for y in range(y_min, y_max + 1):
			var py := SCULPT_Y0 + (float(y) + 0.5) / SCULPT_RES
			var row := y * s + z * t
			for x in range(x_min, x_max + 1):
				var px := (float(x) + 0.5) / SCULPT_RES
				var d2 := (px - center.x) * (px - center.x) \
					+ (py - center.y) * (py - center.y) \
					+ (pz - center.z) * (pz - center.z)
				if d2 >= r2:
					continue
				var k := 1.0 - d2 / r2
				var idx := row + x
				var avg := _sculpt_neighbor_avg(x, y, z)
				var old := _sculpt[idx]
				_sculpt[idx] = lerpf(old, avg, clampf(k, 0.0, 1.0) * 0.7)
				if not touched.has(idx):
					touched[idx] = old
	return _snapshot_delta(touched)

## Met à jour les hauteurs de base (rafraîchit le cache des sommets) — utile
## après un pinceau de relief classique avant une opération « Aplatir ».
func update_heights(heights: Array) -> void:
	_heights = heights if heights is Array else []
	_rebuild_vertex_cache()

# ---------------------------------------------------------------------------
# Brosses « famille but » (Scrape, Fill, Pinch, Layer) — la surface converge
# vers une hauteur cible selon des directions différentes. Inspirées des
# brosses Flatten / Scrape / Fill / Crease / Layer de Blender.
# ---------------------------------------------------------------------------

## Raboter (Scrape) : n'abaisse QUE ce qui dépasse la cible — les creux sont
## conservés. Idéal pour écrêter une crête ou aplatir un sommet.
func sculpt_scrape(center: Vector3, radius: float, target_y: float,
		strength: float) -> Array:
	return _sculpt_blend_toward(center, radius, strength, 0, target_y)

## Remplir (Fill) : ne relève QUE ce qui est sous la cible — les sommets sont
## conservés. Idéal pour combler des crevasses sans écraser les reliefs.
func sculpt_fill(center: Vector3, radius: float, target_y: float,
		strength: float) -> Array:
	return _sculpt_blend_toward(center, radius, strength, 1, target_y)

## Pincer / Crête (Pinch / Crease) : attire la surface vers la hauteur du
## point central — crée une crête nette ou un pli sous le curseur.
func sculpt_pinch(center: Vector3, radius: float, strength: float) -> Array:
	var target := top_surface_at(center.x, center.z)
	return _sculpt_blend_toward(center, radius, strength, 2, target)

## Couche (Layer) : relève/abaisse **jusqu'à** la cible, jamais au-delà —
## empile des couches de hauteur fixe (le trait vise `target_y`).
func sculpt_layer(center: Vector3, radius: float, target_y: float,
		strength: float) -> Array:
	return _sculpt_blend_toward(center, radius, strength, 3, target_y)

## Bandes d'argile (Clay Strips) : ajout à noyau **rectangulaire** orienté.
func sculpt_clay_strips(center: Vector3, radius: float, strength: float,
		angle: float) -> Array:
	return sculpt_stamp(center, radius, strength, 2, angle)

# ---------------------------------------------------------------------------
# Brosses de déformation (Grab, Snake Hook, Thumb, Élastique, Inflate, Blob) :
# le champ est **remappé** — `G'(p) = mélange(G(p), G(p - déplacement(p)))`.
# La matière est tirée / poussée / compressée au lieu d'être ajoutée.
# ---------------------------------------------------------------------------

## Déformation par translation (Grab / Pouce / Élastique) : la matière dans la
## boule suit `disp` avec un dégradé doux. `shape` : 0 = boule (Grab, Pouce),
## 2 = élastique (dégradé large, tire plus fort au centre).
func sculpt_warp(center: Vector3, radius: float, disp: Vector3,
		shape: int = 0) -> Array:
	return _sculpt_warp_impl(center, radius, disp, shape, Vector3.INF)

## Serpent (Snake Hook) : tire la matière le long du segment [anchor → centre]
## — étire une langue de terre en suivant le trait.
func sculpt_snake(center: Vector3, radius: float, disp: Vector3,
		anchor: Vector3) -> Array:
	return _sculpt_warp_impl(center, radius, disp, 1, anchor)

## Gonfler / Dégonfler (Inflate / Deflate) : dilate (ou contracte) la matière
## **horizontalement** autour du curseur — le signe de `strength` fait le sens.
func sculpt_inflate(center: Vector3, radius: float, strength: float) -> Array:
	return _sculpt_warp_impl(center, radius, Vector3(strength, 0.0, 0.0), 3, Vector3.INF)

## Boule (Blob) : dilate la matière dans **toutes** les directions et gonfle
## le volume (le sommet monte ET s'élargit) — dilatation + relevé, en un seul
## pas d'undo.
func sculpt_blob(center: Vector3, radius: float, strength: float) -> Array:
	var w := _sculpt_warp_impl(center, radius, Vector3(strength, 0.0, 0.0), 3, Vector3.INF)
	var s := sculpt_stamp(center, radius, strength * 0.5)
	if w.is_empty():
		return s
	if s.is_empty():
		return w
	# Un seul delta : avant = état initial, après = état final des deux passes.
	var before: Dictionary = {}
	for key in w[0].keys():
		before[key] = w[0][key]
	var after: Dictionary = {}
	for key in w[1].keys():
		after[key] = w[1][key]
	for key in s[1].keys():
		after[key] = s[1][key]
	for key in s[0].keys():
		if not before.has(key):
			before[key] = s[0][key]
	return [before, after]

# ---------------------------------------------------------------------------
# Dernière famille : Bords (Boundary), Simplifier (Simplify), Pivoter (Pose),
# Drapé (Cloth) — les deux derniers sont les équivalents TERRAIN des brosses
# Pose (squelette) et Cloth (simulation) de Blender : voir SCULPTURE_BLENDER.md.
# ---------------------------------------------------------------------------

## Bords (Boundary) : lissage **latéral** — assouplit les pourtours, les
## parois et les raccords sans aplatir les hauteurs (contrairement à Smooth).
func sculpt_boundary(center: Vector3, radius: float) -> Array:
	return _sculpt_blur(center, radius, 0.7, true)

## Simplifier (Simplify) : réduit le détail — lissage renforcé (deux passes)
## + quantification du déplacement (les micro-reliefs disparaissent, la forme
## générale reste).
func sculpt_simplify(center: Vector3, radius: float) -> Array:
	var d := _sculpt_blur(center, radius, 0.85, false)
	_sculpt_blur(center, radius, 0.85, false)
	_quantize_region(center, radius)
	return d

## Pivoter (équivalent terrain de Pose) : fait pivoter la matière autour de
## l'axe vertical du curseur — tord un relief, crée une spirale.
func sculpt_pose(center: Vector3, radius: float, angle: float) -> Array:
	return _sculpt_warp_impl(center, radius, Vector3(angle, 0.0, 0.0), 5, Vector3.INF)

## Drapé (équivalent terrain de Cloth) : la matière **s'affaisse** vers les
## creux voisins — plis doux, tassement naturel des bosses.
func sculpt_cloth(center: Vector3, radius: float, strength: float) -> Array:
	return _sculpt_blur(center, radius, clampf(strength, 0.0, 1.0), false, true)

## Flou du champ dans la boule. `lateral_only` : moyenne latérale (bords) ;
## `sag` : biais vers le bas (drapé).
func _sculpt_blur(center: Vector3, radius: float, strength: float,
		lateral_only: bool, sag: bool = false) -> Array:
	_ensure_sculpt()
	var r := maxf(0.15, radius)
	var touched := {}
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r) * SCULPT_RES))
	var y_min := maxi(0, floori((center.y - r - SCULPT_Y0) * SCULPT_RES))
	var y_max := mini(_sculpt_dims.y - 1, ceili((center.y + r - SCULPT_Y0) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r) * SCULPT_RES))
	var r2 := r * r
	var targets := PackedFloat32Array()
	var indices := PackedInt32Array()
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		for y in range(y_min, y_max + 1):
			var py := SCULPT_Y0 + (float(y) + 0.5) / SCULPT_RES
			var row := y * s + z * t
			for x in range(x_min, x_max + 1):
				var px := (float(x) + 0.5) / SCULPT_RES
				var d2 := (px - center.x) * (px - center.x) \
					+ (py - center.y) * (py - center.y) \
					+ (pz - center.z) * (pz - center.z)
				if d2 >= r2:
					continue
				var k := 1.0 - d2 / r2
				k = k * k
				var avg := _sculpt_neighbor_avg(x, y, z, lateral_only)
				var idx := row + x
				var cur := _sculpt[idx]
				var want := lerpf(cur, avg, clampf(k * strength, 0.0, 1.0))
				if sag:
					# Biais vers le bas : les bosses s'affaissent.
					want = lerpf(want, minf(cur, avg), clampf(k * strength * 0.5, 0.0, 1.0))
				targets.append(want)
				indices.append(idx)
				touched[idx] = cur
	for i in range(targets.size()):
		_sculpt[indices[i]] = clampf(targets[i], -12.0, 12.0)
	return _snapshot_delta(touched)

## Quantifie le déplacement dans la boule (Simplifier) : pas de 0.02 case.
func _quantize_region(center: Vector3, radius: float) -> void:
	var r := maxf(0.15, radius)
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r) * SCULPT_RES))
	var y_min := maxi(0, floori((center.y - r - SCULPT_Y0) * SCULPT_RES))
	var y_max := mini(_sculpt_dims.y - 1, ceili((center.y + r - SCULPT_Y0) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r) * SCULPT_RES))
	var r2 := r * r
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		for y in range(y_min, y_max + 1):
			var py := SCULPT_Y0 + (float(y) + 0.5) / SCULPT_RES
			var row := y * s + z * t
			for x in range(x_min, x_max + 1):
				var px := (float(x) + 0.5) / SCULPT_RES
				var d2 := (px - center.x) * (px - center.x) \
					+ (py - center.y) * (py - center.y) \
					+ (pz - center.z) * (pz - center.z)
				if d2 >= r2:
					continue
				var idx := row + x
				_sculpt[idx] = snappedf(_sculpt[idx], 0.02)

func _sculpt_warp_impl(center: Vector3, radius: float, disp: Vector3,
		shape: int, anchor: Vector3) -> Array:
	_ensure_sculpt()
	var r := maxf(0.15, radius)
	if disp.length() < 0.00001:
		return []
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r - absf(disp.x) - 0.1) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r + absf(disp.x) + 0.1) * SCULPT_RES))
	var y_min := maxi(0, floori((center.y - r - absf(disp.y) - SCULPT_Y0 - 0.1) * SCULPT_RES))
	var y_max := mini(_sculpt_dims.y - 1, ceili((center.y + r + absf(disp.y) - SCULPT_Y0 + 0.1) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r - absf(disp.z) - 0.1) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r + absf(disp.z) + 0.1) * SCULPT_RES))
	# Passe 1 : valeurs cibles lues sur le champ INTACT (aucune écriture).
	var targets := PackedFloat32Array()
	var indices := PackedInt32Array()
	var touched := {}
	var tube_dir := (anchor - center) if shape == 1 and anchor != Vector3.INF else Vector3.ZERO
	var tube_len := maxf(tube_dir.length(), 0.001)
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		for y in range(y_min, y_max + 1):
			var py := SCULPT_Y0 + (float(y) + 0.5) / SCULPT_RES
			var row := y * s + z * t
			for x in range(x_min, x_max + 1):
				var px := (float(x) + 0.5) / SCULPT_RES
				var p := Vector3(px, py, pz)
				var k := 0.0
				match shape:
					1:
						# Tube le long du segment (Snake Hook).
						var rel := p - center
						var along := clampf(rel.dot(tube_dir) / (tube_len * tube_len), 0.0, 1.0)
						var closest := center + tube_dir * along
						var d: float = p.distance_to(closest) / r
						if d < 1.0:
							var q := 1.0 - d
							k = q * q
					3, 4:
						# Dilatation autour du centre (Inflate horizontal,
						# Blob 3D).
						var d: float = (Vector2(p.x - center.x, p.z - center.z).length() / r) \
							if shape == 3 else (p.distance_to(center) / r)
						if d < 1.0:
							var q := 1.0 - d * d
							k = q * q
					_:
						# Boule (Grab / Pouce / Élastique).
						var d: float = p.distance_to(center) / r
						if d < 1.0:
							if shape == 2:
								k = smoothstep(0.0, 1.0, 1.0 - d)
							else:
								var q := 1.0 - d * d
								k = q * q
				if k <= 0.0001:
					continue
				var src: Vector3
				if shape == 3 or shape == 4:
					src = center + (p - center) * (1.0 - disp.x * k)
				elif shape == 5:
					# Pivotement autour de l'axe vertical du curseur (Pose).
					var ang := disp.x * k
					var rel := p - center
					var ca2 := cos(ang)
					var sa2 := sin(ang)
					src = center + Vector3(
						ca2 * rel.x + sa2 * rel.z, rel.y, -sa2 * rel.x + ca2 * rel.z)
				else:
					src = p - disp * k
				var v := sculpt_at(src)
				var idx := row + x
				targets.append(v)
				indices.append(idx)
				touched[idx] = _sculpt[idx]
	# Passe 2 : application (le champ intact a été lu partout).
	for i in range(targets.size()):
		_sculpt[indices[i]] = clampf(targets[i], -12.0, 12.0)
	return _snapshot_delta(touched)

## Boucle commune des brosses « but » : mode 0 = raboter (hauts seulement),
## 1 = remplir (bas seulement), 2 = pincer (cible = hauteur centrale),
## 3 = couche (plafond à la cible).
func _sculpt_blend_toward(center: Vector3, radius: float, strength: float,
		mode: int, target_y: float) -> Array:
	_ensure_sculpt()
	var r := maxf(0.15, radius)
	if strength <= 0.00001:
		return []
	var touched := {}
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r) * SCULPT_RES))
	var r2 := r * r
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		var dz2 := (pz - center.z) * (pz - center.z)
		for x in range(x_min, x_max + 1):
			var px := (float(x) + 0.5) / SCULPT_RES
			var d2 := (px - center.x) * (px - center.x) + dz2
			if d2 >= r2:
				continue
			var k := 1.0 - d2 / r2
			k = k * k
			var goal := target_y - height_at(px, pz)
			var blend := clampf(strength * k, 0.0, 1.0)
			for y in range(_sculpt_dims.y):
				var i := x + y * s + z * t
				var cur := _sculpt[i]
				var want := cur
				match mode:
					0:
						if cur > goal:
							want = lerpf(cur, goal, blend)
					1:
						if cur < goal:
							want = lerpf(cur, goal, blend)
					3:
						if goal > cur:
							want = minf(lerpf(cur, goal, blend), goal)
						else:
							want = maxf(lerpf(cur, goal, blend), goal)
					_:
						want = lerpf(cur, goal, blend)
				want = clampf(want, -12.0, 12.0)
				if want != cur:
					if not touched.has(i):
						touched[i] = cur
					_sculpt[i] = want
	return _snapshot_delta(touched)

## Aplatit vers `target_y` dans la boule (brosse « Aplatir » façon Blender /
## Planet Zoo) : pour chaque colonne, le déplacement `G` tend vers la valeur
## qui pose la surface **exactement** à `target_y` (`G = cible - hauteur_base`,
## puisque `F = height_at + G - y`). Crée plateaux, terrasses et plages.
func sculpt_flatten(center: Vector3, radius: float, target_y: float,
		strength: float) -> Array:
	_ensure_sculpt()
	var r := maxf(0.15, radius)
	if strength <= 0.00001:
		return []
	var touched := {}
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var x_min := maxi(0, floori((center.x - r) * SCULPT_RES))
	var x_max := mini(_sculpt_dims.x - 1, ceili((center.x + r) * SCULPT_RES))
	var y_min := maxi(0, floori((center.y - r - SCULPT_Y0) * SCULPT_RES))
	var y_max := mini(_sculpt_dims.y - 1, ceili((center.y + r - SCULPT_Y0) * SCULPT_RES))
	var z_min := maxi(0, floori((center.z - r) * SCULPT_RES))
	var z_max := mini(_sculpt_dims.z - 1, ceili((center.z + r) * SCULPT_RES))
	var r2 := r * r
	for z in range(z_min, z_max + 1):
		var pz := (float(z) + 0.5) / SCULPT_RES
		for y in range(y_min, y_max + 1):
			var py := SCULPT_Y0 + (float(y) + 0.5) / SCULPT_RES
			var row := y * s + z * t
			for x in range(x_min, x_max + 1):
				var px := (float(x) + 0.5) / SCULPT_RES
				var d2 := (px - center.x) * (px - center.x) \
					+ (py - center.y) * (py - center.y) \
					+ (pz - center.z) * (pz - center.z)
				if d2 >= r2:
					continue
				var k := 1.0 - d2 / r2
				k = k * k
				var goal := target_y - height_at(px, pz)
				var idx := row + x
				var old := _sculpt[idx]
				_sculpt[idx] = clampf(lerpf(old, goal, clampf(strength * k, 0.0, 1.0)), -12.0, 12.0)
				if not touched.has(idx):
					touched[idx] = old
	return _snapshot_delta(touched)

func _sculpt_neighbor_avg(x: int, y: int, z: int, lateral_only: bool = false) -> float:
	var s := _sculpt_dims.x
	var t := _sculpt_dims.x * _sculpt_dims.y
	var total := 0.0
	var count := 0
	for dz in range(-1, 2):
		var zz := z + dz
		if zz < 0 or zz >= _sculpt_dims.z:
			continue
		for dy in range(-1, 2):
			if lateral_only and dy != 0:
				continue
			var yy := y + dy
			if yy < 0 or yy >= _sculpt_dims.y:
				continue
			for dx in range(-1, 2):
				var xx := x + dx
				if xx < 0 or xx >= _sculpt_dims.x:
					continue
				total += _sculpt[xx + yy * s + zz * t]
				count += 1
	return total / float(maxi(1, count))

## Delta {before, after} des voxels touchés (pour l'undo du document).
func _snapshot_delta(touched: Dictionary) -> Array:
	var before := {}
	var after := {}
	for idx in touched.keys():
		before[str(idx)] = float(touched[idx])
		after[str(idx)] = _sculpt[int(idx)]
	return [before, after]

## Applique un delta de sculpture (undo/redo) : `values` = {index_str: float}.
func sculpt_apply_delta(values: Dictionary) -> void:
	_ensure_sculpt()
	for key in values.keys():
		var idx := int(key)
		if idx >= 0 and idx < _sculpt.size():
			_sculpt[idx] = float(values[key])

## Sérialisation JSON-sûre : chunks de 8³ voxels quantifiés sur une **échelle
## propre au chunk** (`{"s": échelle, "v": [int8 × 512]}`, valeur = v/127 × s) —
## sans cette échelle, un int8 à pas fixe bridait les montagnes à ±2 cases.
## `{}` si rien n'est sculpté. L'ancien format à plat (÷64) est toujours lu.
func get_sculpt() -> Dictionary:
	if _sculpt.is_empty() or not has_sculpt():
		return {}
	var cs := SCULPT_CHUNK
	var chunks := {}
	var gx := ceili(_sculpt_dims.x / float(cs))
	var gy := ceili(_sculpt_dims.y / float(cs))
	var gz := ceili(_sculpt_dims.z / float(cs))
	for cz in range(gz):
		for cy in range(gy):
			for cx in range(gx):
				if not _chunk_nonzero(cx, cy, cz):
					continue
				var scale := 1.0 / SCULPT_QUANT
				for z in range(cz * cs, mini((cz + 1) * cs, _sculpt_dims.z)):
					for y in range(cy * cs, mini((cy + 1) * cs, _sculpt_dims.y)):
						var row := y * _sculpt_dims.x + z * _sculpt_dims.x * _sculpt_dims.y
						for x in range(cx * cs, mini((cx + 1) * cs, _sculpt_dims.x)):
							scale = maxf(scale, absf(_sculpt[row + x]))
				var data: Array = []
				for z in range(cz * cs, mini((cz + 1) * cs, _sculpt_dims.z)):
					for y in range(cy * cs, mini((cy + 1) * cs, _sculpt_dims.y)):
						var row := y * _sculpt_dims.x + z * _sculpt_dims.x * _sculpt_dims.y
						for x in range(cx * cs, mini((cx + 1) * cs, _sculpt_dims.x)):
							data.append(clampi(int(roundf(_sculpt[row + x] / scale * 127.0)), -127, 127))
				chunks["%d_%d_%d" % [cx, cy, cz]] = {"s": scale, "v": data}
	return {"res": SCULPT_RES, "y0": SCULPT_Y0, "chunks": chunks}

## Charge la sculpture depuis sa forme JSON (grille reconstruite). Accepte le
## format à échelle par chunk et l'ancien format à plat (÷64).
func set_sculpt(data: Dictionary) -> void:
	_ensure_sculpt()
	_sculpt.fill(0.0)
	if data == null or not (data is Dictionary) or (data as Dictionary).is_empty():
		return
	var chunks = data.get("chunks", {})
	if not (chunks is Dictionary):
		return
	var cs := SCULPT_CHUNK
	for key in (chunks as Dictionary).keys():
		var parts := str(key).split("_")
		if parts.size() != 3:
			continue
		var cx := int(parts[0])
		var cy := int(parts[1])
		var cz := int(parts[2])
		var entry = (chunks as Dictionary)[key]
		var values: Array = []
		var scale := 1.0 / SCULPT_QUANT
		if entry is Dictionary:
			scale = maxf(1.0 / SCULPT_QUANT, float(entry.get("s", scale)))
			values = entry.get("v", []) if entry.get("v") is Array else []
		elif entry is Array:
			values = entry
		var i := 0
		for z in range(cz * cs, mini((cz + 1) * cs, _sculpt_dims.z)):
			for y in range(cy * cs, mini((cy + 1) * cs, _sculpt_dims.y)):
				var row := y * _sculpt_dims.x + z * _sculpt_dims.x * _sculpt_dims.y
				for x in range(cx * cs, mini((cx + 1) * cs, _sculpt_dims.x)):
					if i < values.size():
						_sculpt[row + x] = clampf(
							float(values[i]) / 127.0 * scale if entry is Dictionary \
							else float(values[i]) / SCULPT_QUANT,
							-12.0, 12.0)
					i += 1

func _chunk_nonzero(cx: int, cy: int, cz: int) -> bool:
	var cs := SCULPT_CHUNK
	for z in range(cz * cs, mini((cz + 1) * cs, _sculpt_dims.z)):
		for y in range(cy * cs, mini((cy + 1) * cs, _sculpt_dims.y)):
			var row := y * _sculpt_dims.x + z * _sculpt_dims.x * _sculpt_dims.y
			for x in range(cx * cs, mini((cx + 1) * cs, _sculpt_dims.x)):
				if absf(_sculpt[row + x]) > 0.0005:
					return true
	return false

## Régions (cases) où la sculpture est non nulle : emprises des chunks actifs,
## utilisées pour placer les clusters MC (le heightfield y est découpé).
func sculpt_regions() -> Array:
	var out: Array = []
	if _sculpt.is_empty():
		return out
	var cs := SCULPT_CHUNK
	var gx := ceili(_sculpt_dims.x / float(cs))
	var gy := ceili(_sculpt_dims.y / float(cs))
	var gz := ceili(_sculpt_dims.z / float(cs))
	for cz in range(gz):
		for cy in range(gy):
			for cx in range(gx):
				if not _chunk_nonzero(cx, cy, cz):
					continue
				out.append({
					"x0": float(cx * cs) / SCULPT_RES,
					"x1": float((cx + 1) * cs) / SCULPT_RES,
					"y0": SCULPT_Y0 + float(cy * cs) / SCULPT_RES,
					"y1": SCULPT_Y0 + float((cy + 1) * cs) / SCULPT_RES,
					"z0": float(cz * cs) / SCULPT_RES,
					"z1": float((cz + 1) * cs) / SCULPT_RES,
				})
	return out

## Construit le cache des hauteurs de sommets (mêmes valeurs que
## `vertex_height`, calculées une fois pour toutes). Domaine étendu
## `[-1..w+1] × [-1..h+1]` : comme `vertex_height`, toute position hors grille
## vaut 0.0 (les clusters de creusement peuvent déborder de la carte).
func _rebuild_vertex_cache() -> void:
	var stride := _w + 3
	_vertex_cache.resize(stride * (_h + 3))
	for j in range(-1, _h + 2):
		for i in range(-1, _w + 2):
			var value := 0.0
			if i >= 0 and i <= _w and j >= 0 and j <= _h:
				value = vertex_height(i, j)
			_vertex_cache[(j + 1) * stride + (i + 1)] = value

## Remplace les primitives (normalisation + pré-parsing interne typé).
func set_carves(carves: Array) -> void:
	_carves = normalize_carves(carves)
	_op_codes.clear()
	_shape_codes.clear()
	_params.clear()
	_prim_bounds.clear()
	_scan_bottom = -4.0
	if not _heights.is_empty():
		for value in _heights:
			_scan_bottom = minf(_scan_bottom, float(value) - 1.0)
	for entry in _carves:
		var op := 1 if str(entry.get("op", OP_SUBTRACT)) == OP_UNION else 0
		_op_codes.append(op)
		var shape := str(entry.get("shape", SHAPE_SPHERE))
		var smooth := clampf(float(entry.get("smooth", DEFAULT_SMOOTH)), 0.0, SMOOTH_RANGE)
		match shape:
			SHAPE_CAPSULE:
				_shape_codes.append(1)
				var a := _read_vec(entry.get("a"), Vector3.ZERO)
				var b := _read_vec(entry.get("b"), Vector3.ZERO)
				var r := float(entry.get("radius", 0.5))
				_params.append_array(PackedFloat32Array([
					a.x, a.y, a.z, b.x, b.y, b.z, r, 0.0, smooth]))
			SHAPE_BOX:
				_shape_codes.append(2)
				var c := _read_vec(entry.get("center"), Vector3.ZERO)
				var half := _read_vec(entry.get("half"), Vector3(0.5, 0.5, 0.5))
				var yaw := deg_to_rad(float(entry.get("yaw", 0.0)))
				_params.append_array(PackedFloat32Array([
					c.x, c.y, c.z, half.x, half.y, half.z,
					cos(yaw), sin(yaw), smooth]))
			_:
				_shape_codes.append(0)
				var c2 := _read_vec(entry.get("center"), Vector3.ZERO)
				var r2 := float(entry.get("radius", 0.5))
				_params.append_array(PackedFloat32Array([
					c2.x, c2.y, c2.z, r2, 0.0, 0.0, 0.0, 0.0, smooth]))
		var b2 := bounds_of(entry)
		_prim_bounds.append(b2)
		_scan_bottom = minf(_scan_bottom, float(b2["y0"]) - 1.0)

func get_carves() -> Array:
	return _carves

func has_carves() -> bool:
	return not _carves.is_empty()

func size() -> Vector2i:
	return Vector2i(_w, _h)

static func _parse_prim(entry: Dictionary) -> Dictionary:
	var prim := {
		"op": str(entry.get("op", OP_SUBTRACT)),
		"shape": str(entry.get("shape", SHAPE_SPHERE)),
		"smooth": clampf(float(entry.get("smooth", DEFAULT_SMOOTH)), 0.0, SMOOTH_RANGE),
	}
	match prim["shape"]:
		SHAPE_CAPSULE:
			prim["a"] = _read_vec(entry.get("a"), Vector3.ZERO)
			prim["b"] = _read_vec(entry.get("b"), Vector3.ZERO)
			prim["radius"] = float(entry.get("radius", 0.5))
		SHAPE_BOX:
			prim["c"] = _read_vec(entry.get("center"), Vector3.ZERO)
			prim["half"] = _read_vec(entry.get("half"), Vector3(0.5, 0.5, 0.5))
			var yaw := deg_to_rad(float(entry.get("yaw", 0.0)))
			prim["cos"] = cos(yaw)
			prim["sin"] = sin(yaw)
		_:
			prim["c"] = _read_vec(entry.get("center"), Vector3.ZERO)
			prim["radius"] = float(entry.get("radius", 0.5))
	return prim

# ===========================================================================
# SDF des primitives
# ===========================================================================

## Distance signée d'un point (cases) à une primitive : négatif à l'intérieur.
static func prim_sdf(prim: Dictionary, p: Vector3) -> float:
	match str(prim.get("shape", SHAPE_SPHERE)):
		SHAPE_CAPSULE:
			var a: Vector3 = prim["a"]
			var b: Vector3 = prim["b"]
			return _segment_distance(p, a, b) - float(prim["radius"])
		SHAPE_BOX:
			var c: Vector3 = prim["c"]
			var half: Vector3 = prim["half"]
			var rel := p - c
			# Rotation inverse autour de Y (yaw).
			var cos_y := float(prim.get("cos", 1.0))
			var sin_y := float(prim.get("sin", 0.0))
			var local := Vector3(
				cos_y * rel.x - sin_y * rel.z,
				rel.y,
				sin_y * rel.x + cos_y * rel.z
			)
			var q := Vector3(
				absf(local.x) - half.x,
				absf(local.y) - half.y,
				absf(local.z) - half.z
			)
			var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
			var inside := minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
			return outside.length() + inside
		_:
			return p.distance_to(prim["c"]) - float(prim["radius"])

static func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.0000001:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Smooth-min polynomial (Jon O'Sullivan) — lisse les raccords creus/terrain.
static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0001:
		return minf(a, b)
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)

# ===========================================================================
# Échantillonnage du champ
# ===========================================================================

## Champ scalaire en un point (cases). `>= 0` = matière. Point chaud : boucle
## typée sans dictionnaire ni conversion de chaîne.
func sample(p: Vector3) -> float:
	var f := height_at(p.x, p.z) - p.y
	if not _sculpt.is_empty():
		f += sculpt_at(p)
	var count := _op_codes.size()
	for i in range(count):
		var base := i * PRIM_STRIDE
		var d := 0.0
		var shape := _shape_codes[i]
		if shape == 0:
			var dx := p.x - _params[base]
			var dy := p.y - _params[base + 1]
			var dz := p.z - _params[base + 2]
			d = sqrt(dx * dx + dy * dy + dz * dz) - _params[base + 3]
		elif shape == 1:
			var ax := _params[base]
			var ay := _params[base + 1]
			var az := _params[base + 2]
			var abx := _params[base + 3] - ax
			var aby := _params[base + 4] - ay
			var abz := _params[base + 5] - az
			var denom := abx * abx + aby * aby + abz * abz
			var t := 0.0
			if denom > 0.0000001:
				t = clampf(((p.x - ax) * abx + (p.y - ay) * aby + (p.z - az) * abz) / denom, 0.0, 1.0)
			var qx := p.x - (ax + abx * t)
			var qy := p.y - (ay + aby * t)
			var qz := p.z - (az + abz * t)
			d = sqrt(qx * qx + qy * qy + qz * qz) - _params[base + 6]
		else:
			var relx := p.x - _params[base]
			var rely := p.y - _params[base + 1]
			var relz := p.z - _params[base + 2]
			var cy := _params[base + 6]
			var sy := _params[base + 7]
			var lx := cy * relx - sy * relz
			var lz := sy * relx + cy * relz
			var qx2 := absf(lx) - _params[base + 3]
			var qy2 := absf(rely) - _params[base + 4]
			var qz2 := absf(lz) - _params[base + 5]
			var ox := maxf(qx2, 0.0)
			var oy := maxf(qy2, 0.0)
			var oz := maxf(qz2, 0.0)
			var inside := minf(maxf(qx2, maxf(qy2, qz2)), 0.0)
			d = sqrt(ox * ox + oy * oy + oz * oz) + inside
		var k := _params[base + 8]
		if _op_codes[i] == 1:
			# Union (remblai) : smax(f, -d, k) = -smin(-f, d, k).
			var a2 := -f
			if k > 0.0001:
				var h := clampf(0.5 + 0.5 * (d - a2) / k, 0.0, 1.0)
				var s := lerpf(d, a2, h) - k * h * (1.0 - h)
				f = -s
			else:
				f = maxf(f, -d)
		else:
			# Creusement : smin(f, d, k) — lisse le raccord creux/terrain.
			if k > 0.0001:
				var h2 := clampf(0.5 + 0.5 * (d - f) / k, 0.0, 1.0)
				f = lerpf(d, f, h2) - k * h2 * (1.0 - h2)
			else:
				f = minf(f, d)
	return f

## Hauteur du maillage de sol en (gx, gy) cases — **même formule que**
## `MapGround3D._vertex_height_at` (moyenne des cases adjacentes aux sommets,
## puis bilinéaire). C'est la surface de référence des maillages. Les valeurs
## de sommets viennent du cache (`_rebuild_vertex_cache`).
func height_at(gx: float, gy: float) -> float:
	if _vertex_cache.size() != (_w + 3) * (_h + 3):
		_rebuild_vertex_cache()
	var stride := _w + 3
	var x0 := clampi(floori(gx), -1, _w + 1)
	var y0 := clampi(floori(gy), -1, _h + 1)
	var fx := clampf(gx - float(x0), 0.0, 1.0)
	var fy := clampf(gy - float(y0), 0.0, 1.0)
	var i1 := mini(x0 + 1, _w + 1)
	var j1 := mini(y0 + 1, _h + 1)
	var h00 := _vertex_cache[(y0 + 1) * stride + (x0 + 1)]
	var h10 := _vertex_cache[(y0 + 1) * stride + (i1 + 1)]
	var h01 := _vertex_cache[(j1 + 1) * stride + (x0 + 1)]
	var h11 := _vertex_cache[(j1 + 1) * stride + (i1 + 1)]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

## Hauteur d'un sommet de grille — **même formule que**
## `MapGround3D._vertex_height` (moyenne des 4 cases adjacentes).
func vertex_height(i: int, j: int) -> float:
	var total := 0.0
	var samples := 0
	for oy in range(-1, 1):
		var cy := j + oy
		if cy < 0 or cy >= _h:
			continue
		for ox in range(-1, 1):
			var cx := i + ox
			if cx < 0 or cx >= _w:
				continue
			total += cell_height(cx, cy)
			samples += 1
	return total / float(maxi(1, samples))

## Hauteur d'une case (0 hors carte).
func cell_height(cx: int, cy: int) -> float:
	if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
		return 0.0
	var idx := cy * _w + cx
	if idx < 0 or idx >= _heights.size():
		return 0.0
	return float(_heights[idx])

## Interpolation bilinéaire « historique » des hauteurs de cases — **même
## formule que** `ComplexMapEngine3D.terrain_height_at` (convention de pose
## des objets ; conservée telle quelle pour ne rien déplacer).
func cell_bilinear(gx: float, gy: float) -> float:
	if _w <= 0 or _h <= 0 or _heights.is_empty():
		return 0.0
	var x0 := floori(gx)
	var y0 := floori(gy)
	var x1 := mini(x0 + 1, _w - 1)
	var y1 := mini(y0 + 1, _h - 1)
	x0 = clampi(x0, 0, _w - 1)
	y0 = clampi(y0, 0, _h - 1)
	var fx := clampf(gx - float(x0), 0.0, 1.0)
	var fy := clampf(gy - float(y0), 0.0, 1.0)
	var h00 := cell_height(x0, y0)
	var h10 := cell_height(x1, y0)
	var h01 := cell_height(x0, y1)
	var h11 := cell_height(x1, y1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

## Sol visible depuis le dessus en (gx, gy) cases, creusements compris :
## la surface de pose historique si elle est encore pleine et sans remblai
## au-dessus ; sinon le sommet de la matière suivante (fond de trou, sol de
## grotte ou **haut d'un remblai** `op = union`).
func top_surface_at(gx: float, gy: float) -> float:
	var base := cell_bilinear(gx, gy)
	if _carves.is_empty() and _sculpt.is_empty():
		return base
	var h_mesh := height_at(gx, gy)
	var add_top := _add_top_over(gx, gy, base)
	if not _sculpt.is_empty():
		# Le sommet sculpté vérifie y - base = G ≤ max G de la colonne : cette
		# borne est GARANTIE au-dessus du sommet — le scan descendant retrouve
		# toujours la surface réelle.
		add_top = maxf(add_top, base + maxf(0.0, _sculpt_column_max(gx, gy, base)))
	if sample(Vector3(gx, h_mesh - PROBE_EPS, gy)) >= 0.0 and add_top <= base:
		# Surface intacte, aucun remblai au-dessus : valeur historique,
		# bit-identique — aucun objet ne bouge hors zone creusée.
		return base
	var from_y := maxf(h_mesh, add_top) + PROBE_EPS
	return _scan_top_solid(gx, gy, from_y)

## Sommet le plus haut d'un remblai (`op = union`) couvrant la colonne (test
## AABB 2D conservative) et dépassant `base` ; `base` s'il n'y en a pas.
func _add_top_over(gx: float, gy: float, base: float) -> float:
	var top := base
	for i in range(_op_codes.size()):
		if _op_codes[i] != 1:
			continue
		var b: Dictionary = _prim_bounds[i]
		if gx < float(b["x0"]) or gx > float(b["x1"]) \
				or gy < float(b["z0"]) or gy > float(b["z1"]):
			continue
		top = maxf(top, float(b["y1"]))
	return top

## Plus grand déplacement `G` de la colonne au-dessus de `from_y` (borne du
## sommet sculpté : `sommet = base + G ≤ base + max G`).
func _sculpt_column_max(gx: float, gy: float, from_y: float) -> float:
	var m := 0.0
	var y := from_y
	while y <= SCULPT_Y1:
		m = maxf(m, sculpt_at(Vector3(gx, y, gy)))
		y += 0.25
	return m

## Premier solide en descendant la colonne (sommet de trou / sol de grotte /
## haut de remblai) : première transition vide → matière, affinée par bissection.
func _scan_top_solid(gx: float, gy: float, from_y: float) -> float:
	var y := from_y
	var prev := sample(Vector3(gx, y, gy))
	var yy := y - SCAN_STEP
	while yy >= _scan_bottom:
		var v := sample(Vector3(gx, yy, gy))
		if prev < 0.0 and v >= 0.0:
			return _bisect_column(gx, gy, yy, y)
		prev = v
		y = yy
		yy -= SCAN_STEP
	return _scan_bottom

func _bisect_column(gx: float, gy: float, lo: float, hi: float) -> float:
	for _i in range(24):
		var mid := (lo + hi) * 0.5
		if sample(Vector3(gx, mid, gy)) >= 0.0:
			lo = mid
		else:
			hi = mid
	return lo

## Normale de surface (vers le haut) en (gx, gy) — gradient du champ au sol.
## Sans creusement, repli sur le gradient de `cell_bilinear` (comportement
## historique du moteur).
func normal_at(gx: float, gy: float) -> Vector3:
	const STEP := 0.05
	if _carves.is_empty():
		var dhdx := (cell_bilinear(gx + STEP, gy) - cell_bilinear(gx - STEP, gy)) / (2.0 * STEP)
		var dhdz := (cell_bilinear(gx, gy + STEP) - cell_bilinear(gx, gy - STEP)) / (2.0 * STEP)
		return Vector3(-dhdx, 1.0, -dhdz).normalized()
	var y := top_surface_at(gx, gy) - 0.02
	var p := Vector3(gx, y, gy)
	var e := 0.05
	var grad := Vector3(
		sample(p + Vector3(e, 0.0, 0.0)) - sample(p - Vector3(e, 0.0, 0.0)),
		sample(p + Vector3(0.0, e, 0.0)) - sample(p - Vector3(0.0, e, 0.0)),
		sample(p + Vector3(0.0, 0.0, e)) - sample(p - Vector3(0.0, 0.0, e))
	) / (2.0 * e)
	if grad.length_squared() < 0.0000001:
		return Vector3.UP
	return (-grad).normalized()

# ===========================================================================
# Picking — marche de rayon
# ===========================================================================

## Intersection d'un rayon (cases) avec la surface du terrain creusé.
## Renvoie `{"position": Vector3, "normal": Vector3, "t": float}` ou `{}`.
## Direction supposée normalisée ; la marche avance de `RAY_STEP` case puis
## affine par bissection — robuste pour toutes les pentes de table.
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 64.0) -> Dictionary:
	if dir.length_squared() < 0.0000001:
		return {}
	var d := dir.normalized()
	var t := 0.0
	var prev := sample(origin)
	if prev >= 0.0:
		# Démarrage dans la matière : on cherche la sortie (bord de carte).
		pass
	while t < max_dist:
		var next_t := t + RAY_STEP
		var v := sample(origin + d * next_t)
		if prev >= 0.0 and v < 0.0:
			var t_hit := _bisect_ray(origin, d, t, next_t)
			return _hit_dict(origin, d, t_hit)
		if prev < 0.0 and v >= 0.0:
			var t_hit2 := _bisect_ray(origin, d, t, next_t)
			return _hit_dict(origin, d, t_hit2)
		prev = v
		t = next_t
	return {}

func _bisect_ray(origin: Vector3, dir: Vector3, t0: float, t1: float) -> float:
	var lo := t0
	var hi := t1
	var v_lo := sample(origin + dir * lo)
	for _i in range(20):
		var mid := (lo + hi) * 0.5
		var v := sample(origin + dir * mid)
		if (v >= 0.0) == (v_lo >= 0.0):
			lo = mid
			v_lo = v
		else:
			hi = mid
	return (lo + hi) * 0.5

func _hit_dict(origin: Vector3, dir: Vector3, t: float) -> Dictionary:
	var p := origin + dir * t
	return {"position": p, "normal": normal_at(p.x, p.z), "t": t}
