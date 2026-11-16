extends Node3D
class_name MapWater3D

## Plan d'eau (lac, étang, douve) de la carte 2.5D — mode `terrain3d`.
##
## Contrat de données (fourni par le document via `map_data["waterLevel"]`) :
## hauteur du plan d'eau en **cases**, dans le même repère que
## `terrainHeights`. `-1.0` (défaut) = pas d'eau ; toute valeur `>= 0` affiche
## un plan d'eau **si au moins une case de terrain est sous ce niveau** (sinon
## aucun nœud n'est rendu : une flaque au niveau du sol n'a pas de sens).
##
## Rendu : un quad horizontal qui couvre l'emprise de la carte avec une marge
## de `WATER_MARGIN_CELLS` case de chaque côté, positionné à
## `waterLevel * cell_size` en Y. Le matériau est un `ShaderMaterial` translucide
## (`water_surface.gdshader`) : ondulations animées (`TIME`), normales douces,
## bleu-vert avec profondeur, écume de rive. La profondeur est fournie par une
## texture générée ici à partir du sol visible du terrain (une case = un texel,
## R = profondeur normalisée, G = masque d'eau) : rive claire, large sombre. La
## nuit, une teinte sombre est appliquée (`night_tint`).
##
## Creusements volumétriques (Voie B, `map_data["terrainCarves"]`) : la
## profondeur et le masque G sont calculés depuis le sol visible
## (`TerrainCarveField.top_surface_at`) : l'eau n'est visible que sur les cases
## dont le sol visible est **sous** le niveau (le shader masque le reste, ex.
## sol d'une grotte sèche au-dessus du plan d'eau). Sans creusement, le sol
## visible est exactement la hauteur de case : aucun changement de rendu.
##
## Le calque est purement décoratif : aucune collision. Le moteur l'instancie et
## le retire en mode `illustrated`.

const WATER_SHADER := preload("res://shaders/water_surface.gdshader")
## Marge du plan d'eau de chaque côté de la carte, en cases.
const WATER_MARGIN_CELLS := 0.05
## Niveau par défaut : pas d'eau.
const NO_WATER_LEVEL := -1.0
## Seuil sous lequel une case est considérée à la surface (pas immergée).
const WATER_EPSILON := 0.001
## Couleurs (sRGB) et réglages par défaut du shader.
const SHALLOW_COLOR := Color(0.20, 0.47, 0.48)
const DEEP_COLOR := Color(0.05, 0.20, 0.28)
const FOAM_COLOR := Color(0.78, 0.88, 0.88)
const NIGHT_TINT := Color(0.28, 0.34, 0.46)
const BASE_ALPHA := 0.78
const ALPHA_DEPTH := 0.10
## Rivières : facteur appliqué au `flow_speed` des données de carte pour la
## DÉRIVE VISIBLE du motif. Le ruban est animé dans son propre repère (le long
## du tracé) en coordonnées monde normalisées ; sans ce facteur la texture
## « défile à toute vitesse » (le bruit de détail est à haute fréquence).
## 0 = eau figée, 1 = vitesse brute (rapide). 0,10 = courant lisible et calme.
const RIVER_FLOW_VISUAL_SCALE := 0.10
## Canaux : bassin polygonal AVEC `flow_dir` déclaré — le courant se lit, mais
## la dérive reste tempérée (0,18 du `flow_speed` des données).
const CANAL_FLOW_VISUAL_SCALE := 0.18
## Lacs : c'est un lac, l'eau doit à peine bouger. Dépendance du motif quasi
## nulle (0,025 du `flow_speed`) : un frémissement, pas un courant. La houle et
## les scintillements continuent d'animer la surface par ailleurs.
const LAKE_FLOW_VISUAL_SCALE := 0.025

## Décor de surface (lentilles d'eau + nénuphars), posé sur le plan d'eau.
## Densités (probabilité par case immergée) et bornes de performance.
const DUCKWEED_COLOR := Color(0.30, 0.54, 0.25)
const LILY_PAD_COLOR := Color(0.16, 0.42, 0.20)
const DUCKWEED_DENSITY := 0.26
const LILY_DENSITY := 0.05
const DUCKWEED_MAX := 2400
const LILY_MAX := 360
## Profondeur (en cases) en-deçà de laquelle un nénuphar peut pousser (rive).
const LILY_SHALLOW_DEPTH := 0.22

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _depth_texture: ImageTexture = null
var _depth_image: Image = null
## Texture de BERGE (1 = eau, dégradé = terre mouillée) pour le shader du
## terrain : construite en même temps que les bassins.
var _shore_texture: ImageTexture = null
## CARTE D'EAU combinée (résolution carte = une case par texel) pour le shader
## du terrain : R = profondeur normalisée (0..1, max sur les bassins),
## G = masque d'eau (1 = sous l'eau), B = 0, A = 1. Construite dans le MÊME
## passage que la texture de berge (même boucle sur les images des bassins) :
## elle porte aux caustiques animées et à l'absorption par profondeur du lit.
var _water_map_texture: ImageTexture = null
var _water_level: float = NO_WATER_LEVEL
var _cell_size: float = 1.0
var _map_w: int = 0
var _map_h: int = 0
var _terrain_heights: Array = []
## Creusements volumétriques normalisés (Voie B), fournis par le moteur.
var _terrain_carves: Array = []
## Sculpture volumétrique (déplacement lissé) — le champ la combine au sol.
var _terrain_sculpt: Dictionary = {}
# --- Bassins multiples (lacs, mares, rivières, cascades) --------------------
## `map_data["waterBodies"]` normalisé : chacun a son niveau et son emprise ;
## l'eau ne remplit que les creux sous son niveau (masque du sol visible).
var _water_bodies: Array = []
## Un MeshInstance3D par bassin (matériaux et niveaux indépendants).
var _body_nodes: Array = []
## Brume de pied de cascade (finition CS2) : un MeshInstance3D par bassin de
## rivière qui porte des chutes (tous ses quads dans le MÊME maillage → un seul
## draw call par bassin). Le matériau de brume est partagé ; `_mist_enabled`
## pilote l'uniform `mist_enabled` (0 = aucune brume, rendu précédent exact).
var _mist_nodes: Array = []
var _mist_material: ShaderMaterial = null
var _mist_quad_count: int = 0
var _mist_enabled: bool = true
## Nombre de rideaux de chute construits au dernier rebuild (diagnostic/tests).
var _fall_count: int = 0
## Éclairage double du lit réfracté (finition CS2) : force de l'ambiance
## d'eau posée sur les matériaux de surface (0 = rendu précédent exact).
var _bed_ambient_lift: float = BED_AMBIENT_LIFT
## Adoucissement des nez de ruban vus de très haut (finition CS2), appliqué à
## tous les matériaux de ruban (0 = rendu précédent exact).
var _tip_soften_distance: float = TIP_SOFTEN_DISTANCE
## Champ « terre/vide » (hauteurs + creusements), construit paresseusement.
## Creusements volumétriques (Voie B) — préchargement explicite (fiable en
## headless, indépendant du cache global `class_name`).
const TerrainCarveField := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
var _terrain_field: TerrainCarveField = null
var _night_mode: bool = false
var _active: bool = false
## Nombre de cases immergées (h < waterLevel) au dernier rebuild.
var _submerged_count: int = 0
## Profondeur maximale observée (en cases), pour normaliser la texture.
var _max_depth: float = 0.0
## État du dernier rebuild (pour ignorer les mises à jour sans changement).
var _has_config: bool = false
## Décor de surface : lentilles d'eau + nénuphars (MultiMesh pour la perf).
var _duckweed_mmi: MultiMeshInstance3D
var _lily_mmi: MultiMeshInstance3D
var _decor_seed: int = 1
var _decor_density: float = 1.0
var _duckweed_count: int = 0
var _lily_count: int = 0

func _ready() -> void:
	_ensure_mesh_instance()
	_ensure_decor()

func _ensure_mesh_instance() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visible = false
	add_child(_mesh_instance)

## Configure le plan d'eau. `water_level` est exprimé en **cases** (même repère
## que `terrain_heights`). Le plan n'est rendu que si le niveau est au-dessus
## du sentinelle `NO_WATER_LEVEL` (-1.0) et qu'au moins une case est immergée.
## qu'au moins une case de terrain est en dessous. `terrain_carves` porte les
## creusements volumétriques normalisés (Voie B) : profondeur et masque G
## suivent alors le sol visible (`TerrainCarveField`).
func configure(
	map_width: int,
	map_height: int,
	cell_size: float,
	water_level: float,
	terrain_heights: Array = [],
	night_mode: bool = false,
	decor_seed: int = 1,
	decor_density: float = 1.0,
	terrain_carves: Array = [],
	terrain_sculpt: Dictionary = {},
	water_bodies: Array = []
) -> void:
	var next_heights: Array = terrain_heights if terrain_heights is Array else []
	var next_carves: Array = terrain_carves if terrain_carves is Array else []
	var next_sculpt: Dictionary = terrain_sculpt if terrain_sculpt is Dictionary else {}
	var next_bodies: Array = water_bodies if water_bodies is Array else []
	var next_level := float(water_level)
	var next_w := maxi(0, map_width)
	var next_h := maxi(0, map_height)
	var next_cell := cell_size if cell_size > 0.0 else 1.0
	var next_decor_density := clampf(decor_density, 0.0, 4.0)
	if _has_config \
			and next_w == _map_w and next_h == _map_h \
			and is_equal_approx(next_cell, _cell_size) \
			and is_equal_approx(next_level, _water_level) \
			and _arrays_equal(next_heights, _terrain_heights) \
			and _carves_equal(next_carves, _terrain_carves) \
			and str(next_sculpt) == str(_terrain_sculpt) \
			and str(next_bodies) == str(_water_bodies) \
			and night_mode == _night_mode \
			and decor_seed == _decor_seed \
			and is_equal_approx(next_decor_density, _decor_density):
		return
	_map_w = next_w
	_map_h = next_h
	_cell_size = next_cell
	_water_level = next_level
	# Copie : le document édite ses tableaux en place (détection des changements).
	_terrain_heights = next_heights.duplicate()
	_terrain_carves = next_carves
	_terrain_sculpt = next_sculpt
	_water_bodies = next_bodies
	_terrain_field = null
	_night_mode = night_mode
	_decor_seed = decor_seed
	_decor_density = next_decor_density
	_has_config = true
	_rebuild()

## Retire complètement l'eau (mode illustré, ou carte sans plan d'eau).
func clear() -> void:
	_active = false
	_submerged_count = 0
	_max_depth = 0.0
	_depth_texture = null
	_depth_image = null
	_shore_texture = null
	_water_map_texture = null
	_terrain_carves = []
	_terrain_field = null
	_has_config = false
	_clear_body_nodes()
	_clear_mist_nodes()
	_fall_count = 0
	_clear_decor()
	if _mesh_instance != null:
		_mesh_instance.mesh = null
		_mesh_instance.visible = false
	visible = false

## Change le niveau d'eau (en cases), sans reconfigurer dimensions/hauteurs.
func set_water_level(level: float) -> void:
	_water_level = float(level)
	if _has_config:
		_rebuild()

## Met à jour les hauteurs de terrain (relief peint) et recalcule l'immersion.
func set_terrain_heights(terrain_heights: Array) -> void:
	_terrain_heights = terrain_heights.duplicate() if terrain_heights is Array else []
	_terrain_field = null
	if _has_config:
		_rebuild()

## Met à jour les creusements volumétriques (Voie B, déjà normalisés) et
## recalcule l'immersion (profondeur + masque d'eau).
func set_terrain_carves(terrain_carves: Array) -> void:
	_terrain_carves = terrain_carves if terrain_carves is Array else []
	_terrain_field = null
	if _has_config:
		_rebuild()

## Met à jour les bassins d'eau (lacs, mares, rivières) et reconstruit.
func set_water_bodies(water_bodies: Array) -> void:
	_water_bodies = water_bodies if water_bodies is Array else []
	if _has_config:
		_rebuild()

## Active / désactive la teinte de nuit (simple mise à jour du shader, pas de
## rebuild O(w×h) : la profondeur et les multimeshes n'ont pas changé).
func set_night_mode(on: bool) -> void:
	if _night_mode == on:
		return
	_night_mode = on
	if _material != null:
		_material.set_shader_parameter("night_tint", NIGHT_TINT if _night_mode else Color.WHITE)
	for node in _body_nodes:
		if node != null and is_instance_valid(node):
			var mats: Array = []
			if node.material_override is ShaderMaterial:
				mats.append(node.material_override)
			if node.mesh is ArrayMesh:
				for si in range((node.mesh as ArrayMesh).get_surface_count()):
					var sm = (node.mesh as ArrayMesh).surface_get_material(si)
					if sm is ShaderMaterial:
						mats.append(sm)
			for m in mats:
				# Les matériaux de surface portent `night_tint` en couleur
				# (shader d'eau) ; le shader de chute attend un float 0..1.
				if (m as ShaderMaterial).get_shader_parameter("fall_speed") != null:
					(m as ShaderMaterial).set_shader_parameter("night_tint",
						1.0 if _night_mode else 0.0)
				else:
					(m as ShaderMaterial).set_shader_parameter("night_tint",
						NIGHT_TINT if _night_mode else Color.WHITE)
	# Brume de pied de cascade (finition CS2) : même logique de nuit (le shader
	# de brume attend un float 0..1, comme celui de chute).
	if _mist_material != null:
		_mist_material.set_shader_parameter("night_tint",
			1.0 if _night_mode else 0.0)

func get_water_level() -> float:
	return _water_level

## Vrai si un plan d'eau est effectivement rendu (niveau >= 0 + cases immergées).
func is_active() -> bool:
	return _active

## Hauteur monde de la surface de l'eau (0 si pas d'eau configurée).
func get_surface_y() -> float:
	if _water_level <= NO_WATER_LEVEL + 0.001:
		return 0.0
	return _water_level * _cell_size

func get_map_size() -> Vector2i:
	return Vector2i(_map_w, _map_h)

## Emprise monde du plan d'eau, marge comprise.
func get_water_extent() -> Vector2:
	var margin := WATER_MARGIN_CELLS * _cell_size
	return Vector2(
		float(_map_w) * _cell_size + 2.0 * margin,
		float(_map_h) * _cell_size + 2.0 * margin
	)

func get_submerged_cell_count() -> int:
	return _submerged_count

func get_max_depth() -> float:
	return _max_depth

## Hauteur du terrain d'une case, en cases (0 hors carte / sans données).
func get_cell_height(cx: int, cy: int) -> float:
	if cx < 0 or cy < 0 or cx >= _map_w or cy >= _map_h:
		return 0.0
	var idx := cy * _map_w + cx
	if idx < 0 or idx >= _terrain_heights.size():
		return 0.0
	return float(_terrain_heights[idx])

## Sol visible depuis le dessus d'une case, en cases (Voie B) : creusements
## volumétriques compris. Sans creusement, strictement égal à
## `get_cell_height` (valeur historique, aucun décalage).
func get_cell_top_surface(cx: int, cy: int) -> float:
	if cx < 0 or cy < 0 or cx >= _map_w or cy >= _map_h:
		return 0.0
	return _ensure_terrain_field().top_surface_at(float(cx), float(cy))

## Champ « terre/vide » (hauteurs + creusements), construit à la demande.
func _ensure_terrain_field() -> TerrainCarveField:
	if _terrain_field == null:
		_terrain_field = TerrainCarveField.new(
			_terrain_heights, _map_w, _map_h, _terrain_carves, _terrain_sculpt)
	return _terrain_field

## Vrai si la case est sous le niveau de l'eau (sol visible creusé compris).
func is_cell_submerged(cx: int, cy: int) -> bool:
	if _water_level <= NO_WATER_LEVEL + 0.001:
		return false
	if cx < 0 or cy < 0 or cx >= _map_w or cy >= _map_h:
		return false
	return get_cell_top_surface(cx, cy) < _water_level - WATER_EPSILON

## Texture de profondeur du plan d'eau (R = profondeur normalisée, 1 = plus
## profond ; G = masque d'eau, 1 = case visible), null si pas d'eau.
func get_depth_texture() -> ImageTexture:
	return _depth_texture

## Image CPU de la texture de profondeur (fiable pour les tests/tools).
func get_depth_image() -> Image:
	return _depth_image

func get_water_material() -> ShaderMaterial:
	return _material

## Reconstruit (ou retire) le plan d'eau à partir de l'état courant.
func _rebuild() -> void:
	_ensure_mesh_instance()
	# Bassins multiples (lacs, mares, rivières) : pipeline dédié — chacun a son
	# niveau et son sens d'écoulement, l'eau ne remplit que les creux.
	if not _water_bodies.is_empty() and _map_w > 0 and _map_h > 0:
		_rebuild_bodies()
		return
	if _map_w <= 0 or _map_h <= 0 or _water_level <= NO_WATER_LEVEL + 0.001:
		_deactivate()
		return
	var submerged := 0
	var max_depth := 0.0
	for y in range(_map_h):
		for x in range(_map_w):
			# Profondeur mesurée depuis le sol visible (creusements compris).
			var depth := _water_level - get_cell_top_surface(x, y)
			if depth > WATER_EPSILON:
				submerged += 1
				max_depth = maxf(max_depth, depth)
	_submerged_count = submerged
	_max_depth = max_depth
	if submerged == 0 or max_depth <= WATER_EPSILON:
		# Niveau >= 0 mais aucune case immergée : rien à afficher.
		_deactivate()
		return

	_build_depth_texture(max_depth)
	# Carte d'eau : construite depuis les images des BASSINS uniquement (même
	# passage que la texture de berge). Le plan historique n'en fournit pas :
	# on invalide toute carte héritée d'une config précédente (règle d'or :
	# sans masque d'eau, le terrain est strictement inchangé).
	_water_map_texture = null
	_build_material()
	_mesh_instance.mesh = _build_plane_mesh()
	_mesh_instance.position = Vector3(0.0, get_surface_y(), 0.0)
	_mesh_instance.visible = true
	visible = true
	_active = true
	_rebuild_decor()

func _deactivate() -> void:
	_active = false
	_submerged_count = 0
	_max_depth = 0.0
	_depth_texture = null
	_depth_image = null
	_shore_texture = null
	_water_map_texture = null
	_clear_decor()
	_clear_body_nodes()
	_clear_mist_nodes()
	_fall_count = 0
	if _mesh_instance != null:
		_mesh_instance.mesh = null
		_mesh_instance.visible = false
	visible = false

## Quad horizontal couvrant la carte + marge. UV2 = coordonnées monde
## normalisées par l'emprise de la carte (0..1 sur la grille width×height), ce
## qui aligne la texture de profondeur sur les cases ; la marge dépasse
## légèrement (échantillonnage clampé sur le bord).
func _build_plane_mesh() -> ArrayMesh:
	var margin := WATER_MARGIN_CELLS * _cell_size
	var x0 := -margin
	var x1 := float(_map_w) * _cell_size + margin
	var z0 := -margin
	var z1 := float(_map_h) * _cell_size + margin
	var inv_w := 1.0 / maxf(float(_map_w) * _cell_size, 0.0001)
	var inv_h := 1.0 / maxf(float(_map_h) * _cell_size, 0.0001)
	var verts := PackedVector3Array([
		Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0),
		Vector3(x0, 0.0, z1), Vector3(x1, 0.0, z1),
	])
	var normals := PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
	])
	var uv2s := PackedVector2Array([
		Vector2(x0 * inv_w, z0 * inv_h),
		Vector2(x1 * inv_w, z0 * inv_h),
		Vector2(x0 * inv_w, z1 * inv_h),
		Vector2(x1 * inv_w, z1 * inv_h),
	])
	var indices := PackedInt32Array([0, 1, 2, 1, 3, 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Construit / met à jour la texture de profondeur (une case = un texel) :
## R = profondeur normalisée (0 à la rive, 1 au plus profond) depuis le sol
## visible, G = masque d'eau (1.0 si le sol visible est sous le niveau — eau
## visible, 0.0 sinon : le shader ne rend rien sur ces cases), B = 0, A = 1.
## Sans creusement, le masque vaut 1 partout où la profondeur est > 0.
func _build_depth_texture(max_depth: float) -> void:
	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var inv_depth := 1.0 / maxf(max_depth, WATER_EPSILON)
	for y in range(_map_h):
		for x in range(_map_w):
			var depth := _water_level - get_cell_top_surface(x, y)
			var value := 0.0
			var mask := 0.0
			if depth > WATER_EPSILON:
				value = clampf(depth * inv_depth, 0.0, 1.0)
				mask = 1.0
			elif _terrain_carves.is_empty():
				# Sans creusement : masque plein → aucun discard, rendu
				# strictement identique à l'ancien shader (marge et rives).
				mask = 1.0
			img.set_pixel(x, y, Color(value, mask, 0.0, 1.0))
	_depth_image = img
	if _depth_texture == null \
			or _depth_texture.get_width() != _map_w \
			or _depth_texture.get_height() != _map_h:
		_depth_texture = ImageTexture.create_from_image(img)
	else:
		_depth_texture.update(img)

## Matériau du plan d'eau : shader translucide animé, teinté la nuit.
func _build_material() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = WATER_SHADER
	_material.set_shader_parameter("depth_map", _depth_texture)
	_material.set_shader_parameter("shallow_color", SHALLOW_COLOR)
	_material.set_shader_parameter("deep_color", DEEP_COLOR)
	_material.set_shader_parameter("foam_color", FOAM_COLOR)
	_material.set_shader_parameter("night_tint", NIGHT_TINT if _night_mode else Color.WHITE)
	_material.set_shader_parameter("base_alpha", BASE_ALPHA)
	_material.set_shader_parameter("alpha_depth", ALPHA_DEPTH)
	_material.set_shader_parameter("wave_strength", 0.08)
	_material.set_shader_parameter("wave_speed", 0.9)
	_material.set_shader_parameter("foam_strength", 1.0)
	_material.set_shader_parameter("foam_width", 0.12)
	# Éclairage double du lit réfracté (finition CS2) : uniform exposé même sur
	# le plan historique (0 = rendu précédent exact, A/B réversible).
	_material.set_shader_parameter("bed_ambient_lift", _bed_ambient_lift)
	_mesh_instance.material_override = _material

# ===========================================================================
# Bassins d'eau multiples : lacs, mares, rivières, cascades
# ===========================================================================
#
# Chaque bassin (`map_data["waterBodies"]`) porte son niveau et son emprise :
# l'eau n'est visible que là où le **sol visible** (creusements et sculpture
# compris) est sous ce niveau — creuser un bassin y fait aussitôt apparaître
# l'eau, exactement comme un lac qui remplit une cuvette. Les rivières suivent
# leur tracé : les dénivelés deviennent des **cascades** (plans verticaux dont
# le shader s'écoule vers le bas), et la surface dérive le long du sens
# d'écoulement (uniforme `flow_dir` du shader).

## Dénivelé (cases) à partir duquel un segment de rivière devient une cascade.
const FALL_MIN_DROP := 0.75
## Pente du sol visible (cases de dénivelé par case horizontale) à partir de
## laquelle le ressaut est une CHUTE : en deçà, c'est une simple pente douce
## que le ruban d'eau courante suffit à draper.
const FALL_MIN_SLOPE := 1.2
## Rayon (cases) de la fenêtre de lissage des directions latérales du ruban :
## la rotation d'un coude se répartit sur ±`SIDE_SMOOTH_RADIUS` cases, donc la
## silhouette du virage décrit un ARC au lieu de deux bords rectilignes qui se
## coupent en un coin marqué.
const SIDE_SMOOTH_RADIUS := 0.7
## Pas de sous-échantillonnage minimal (cases) dans les virages serrés : le
## ruban gagne des sommets aux fortes courbures (le tracé ne bouge pas, le
## masque de profondeur est inchangé).
const CURVE_STEP_MIN := 0.08
const WATER_FALL_SHADER_PATH := "res://shaders/water_fall.gdshader"
# --- Finitions CS2 (A/B réversible : valeur de repli = état exact précédent) --
## Brume/écume volumétrique au pied des cascades (voile bas animé qui se
## dissipe avec la hauteur) — uniform `mist_enabled` du shader de brume.
const WATER_MIST_SHADER_PATH := "res://shaders/water_mist.gdshader"
## Budget BORNÉ de quads de brume par carte (2 quads par chute) : garde-fou
## de performance, aucun système de particules n'est alloué.
const MIST_MAX_QUADS := 64
## Hauteur du voile vertical, en cases : proportionnelle au ressaut mais
## bornée pour que la brume reste basse (elle ne monte pas la falaise).
const MIST_HEIGHT_MIN := 0.35
const MIST_HEIGHT_MAX := 1.2
## Élargissement du voile par rapport à la largeur du pied de chute : la brume
## déborde de la nappe.
const MIST_VEIL_WIDEN := 1.6
## Longueur de la nappe de brume horizontale (vers l'aval), en largeurs de lit.
const MIST_APRON_LEN := 1.2
## Éclairage double du lit réfracté (ambiance/diffusion, uniform
## `bed_ambient_lift` des shaders d'eau et de terrain). 1 = finition active.
const BED_AMBIENT_LIFT := 1.0
## Adoucissement des nez de ruban vus de très haut (uniform
## `tip_soften_distance` du shader d'eau ; masque de pointe en COLOR.b).
const TIP_SOFTEN_DISTANCE := 1.0
## Distance (cases) sur laquelle le masque de pointe s'éteint le long du ruban :
## au-delà, le chenal n'est plus considéré comme une pointe.
const TIP_MASK_RANGE := 4.5

## Nombre de bassins rendus (0 si l'eau utilise le plan historique).
func get_body_count() -> int:
	return _body_nodes.size()

func _clear_body_nodes() -> void:
	for node in _body_nodes:
		if node != null and is_instance_valid(node):
			node.hide()
			node.queue_free()
	_body_nodes = []

## Ajoute un maillage de bassin comme enfant (un nœud par bassin : niveaux et
## matériaux indépendants).
func _add_body_node(mesh: ArrayMesh, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_body_nodes.append(node)
	return node

# ===========================================================================
# Finitions CS2 — brume de pied de cascade (A/B `mist_enabled`)
# ===========================================================================
#
# Chaque chute reçoit DEUX quads de brume (voile vertical + nappe horizontale
# basse) accumulés dans UN maillage par bassin : un seul draw call, maillage
# non éclairé sans écriture de profondeur, budget borné par `MIST_MAX_QUADS`.
# `set_mist_enabled(0)` éteint l'uniform (discard) ET masque les nœuds : le
# rendu est alors strictement l'état précédent de la finition.

func _clear_mist_nodes() -> void:
	for node in _mist_nodes:
		if node != null and is_instance_valid(node):
			node.hide()
			node.queue_free()
	_mist_nodes = []
	_mist_quad_count = 0

## Ajoute un maillage de brume comme enfant (hors `_body_nodes` : le nombre de
## bassins et leurs surfaces restent inchangés).
func _add_mist_node(mesh: ArrayMesh) -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return
	if _mist_material == null:
		_mist_material = _make_mist_material()
	if _mist_material == null:
		# Shader de brume absent du projet : pas de brume plutôt qu'un
		# matériau par défaut opaque au pied des chutes.
		return
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mist_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = _mist_enabled
	add_child(node)
	_mist_nodes.append(node)

## Active / désactive la brume de pied de cascade (finition CS2, A/B) :
## `false` = uniform `mist_enabled` à 0 (discard) et nœuds masqués — rendu
## EXACTEMENT identique à l'état précédent.
func set_mist_enabled(on: bool) -> void:
	_mist_enabled = on
	if _mist_material != null:
		_mist_material.set_shader_parameter("mist_enabled", 1.0 if on else 0.0)
	for node in _mist_nodes:
		if node != null and is_instance_valid(node):
			node.visible = on

func is_mist_enabled() -> bool:
	return _mist_enabled

## Nombre de nœuds de brume (0 ou 1 par bassin de rivière avec chutes).
func get_mist_count() -> int:
	return _mist_nodes.size()

## Nombre de quads de brume construits (2 par chute, borné par MIST_MAX_QUADS).
func get_mist_quad_count() -> int:
	return _mist_quad_count

## Matériau de brume partagé (null tant qu'aucune chute n'a produit de brume).
func get_mist_material() -> ShaderMaterial:
	return _mist_material

## Nombre de rideaux de chute du dernier rebuild (API de test/diagnostic).
func get_fall_count() -> int:
	return _fall_count

# ===========================================================================
# Finitions CS2 — éclairage double du lit et nez de ruban (A/B)
# ===========================================================================

## Éclairage double du lit réfracté (finition CS2) : règle `bed_ambient_lift`
## sur tous les matériaux de surface d'eau (lacs + rivières). 0 = rendu
## EXACTEMENT précédent (A/B réversible, prouvé par captures off/on).
func set_bed_ambient_lift(amount: float) -> void:
	_bed_ambient_lift = clampf(amount, 0.0, 2.0)
	if _material != null:
		_material.set_shader_parameter("bed_ambient_lift", _bed_ambient_lift)
	for mat in _surface_materials():
		mat.set_shader_parameter("bed_ambient_lift", _bed_ambient_lift)

func get_bed_ambient_lift() -> float:
	return _bed_ambient_lift

## Adoucissement des nez de ruban vus de très haut (finition CS2) : règle
## `tip_soften_distance` sur tous les matériaux de ruban. 0 = rendu
## EXACTEMENT précédent (A/B réversible, prouvé par captures off/on).
func set_tip_soften(amount: float) -> void:
	_tip_soften_distance = clampf(amount, 0.0, 1.0)
	for mat in _surface_materials():
		mat.set_shader_parameter("tip_soften_distance", _tip_soften_distance)

func get_tip_soften() -> float:
	return _tip_soften_distance

## Matériaux de SURFACE d'eau des bassins (les matériaux de chute et de brume
## n'ont pas ces uniforms et sont ignorés).
func _surface_materials() -> Array:
	var mats: Array = []
	for node in _body_nodes:
		if node == null or not is_instance_valid(node):
			continue
		if node.material_override is ShaderMaterial:
			mats.append(node.material_override)
		if node.mesh is ArrayMesh:
			for si in range((node.mesh as ArrayMesh).get_surface_count()):
				var sm = (node.mesh as ArrayMesh).surface_get_material(si)
				if sm is ShaderMaterial and not mats.has(sm):
					mats.append(sm)
	return mats

## Reconstruit tous les bassins (lacs polygonaux + rivières/cascades).
func _rebuild_bodies() -> void:
	_clear_body_nodes()
	_clear_mist_nodes()
	_fall_count = 0
	_mesh_instance.mesh = null
	_mesh_instance.visible = false
	var submerged := 0
	var max_depth := 0.0
	var first: Dictionary = {}
	var depth_images: Array = []
	var footprints: Array = []
	var mist_meshes: Array = []
	for body in _water_bodies:
		if not (body is Dictionary):
			continue
		var kind := str((body as Dictionary).get("kind", "lake"))
		var is_river := kind == "river" \
			or ((body as Dictionary).get("path") is Array \
				and ((body as Dictionary)["path"] as Array).size() >= 2)
		var built := _build_river_body(body) if is_river else _build_lake_body(body)
		if built.is_empty():
			continue
		var dimg = built.get("image", null)
		if dimg is Image:
			depth_images.append(dimg)
			footprints.append(built.get("footprint", null))
		var mist_mesh = built.get("mist", null)
		if mist_mesh is ArrayMesh:
			mist_meshes.append(mist_mesh)
		submerged += int(built.get("submerged", 0))
		max_depth = maxf(max_depth, float(built.get("max_depth", 0.0)))
		_fall_count += int(built.get("falls", 0))
		_mist_quad_count += int(built.get("mist_quads", 0))
		if first.is_empty():
			first = built
	for mesh in mist_meshes:
		_add_mist_node(mesh)
	_build_shore_texture(depth_images, footprints)
	_submerged_count = submerged
	_max_depth = max_depth
	if first.is_empty():
		_active = false
		_depth_texture = null
		_depth_image = null
		_clear_decor()
		visible = false
		return
	# API historique : exposée sur le premier bassin (tests, moteur, outils).
	_material = first.get("material")
	_depth_texture = first.get("texture")
	_depth_image = first.get("image")
	_active = true
	visible = true
	_rebuild_decor()

## Texture de BERGE + CARTE D'EAU pour le shader du terrain, construites dans
## le MÊME passage (même boucle sur les images de profondeur des bassins) :
##   • berge : 1 = eau, dégradé = terre mouillée (union des bassins, dilatée
##     de ~2 cases) ;
##   • carte d'eau (résolution carte) : R = profondeur normalisée (0..1, max
##     sur les bassins), G = masque d'eau (1 = sous l'eau), B = 0, A = 1.
##     Le masque est INTERSECTÉ avec l'empreinte visible de chaque bassin
##     (`footprints` = maillage de la nappe : polygone du lac, ruban de la
##     rivière) : seules les cases réellement recouvertes par la surface
##     d'eau sont « sous l'eau » — la berge haute d'un lit de rivière en
##     pente (profondeur théorique mais hors nappe) reste hors masque.
func _build_shore_texture(images: Array, footprints: Array = []) -> void:
	_shore_texture = null
	_water_map_texture = null
	if images.is_empty():
		return
	var occ := PackedFloat32Array()
	occ.resize(_map_w * _map_h)
	occ.fill(0.0)
	# Carte d'eau : profondeur normalisée combinée au MAX sur les bassins et
	# masque d'eau (1 = au moins un bassin recouvre la case).
	var wdepth := PackedFloat32Array()
	wdepth.resize(_map_w * _map_h)
	wdepth.fill(0.0)
	var wmask := PackedFloat32Array()
	wmask.resize(_map_w * _map_h)
	wmask.fill(0.0)
	for bi in range(images.size()):
		var img: Image = images[bi]
		var fimg: Image = null
		if bi < footprints.size() and footprints[bi] is Image:
			fimg = footprints[bi]
		var w := img.get_width()
		var h := img.get_height()
		var sx := float(_map_w) / float(maxi(1, w))
		var sz := float(_map_h) / float(maxi(1, h))
		for tz in range(h):
			for tx in range(w):
				var px := img.get_pixel(tx, tz)
				if px.g >= 0.5:
					var cx := clampi(int(float(tx) * sx), 0, _map_w - 1)
					var cz := clampi(int(float(tz) * sz), 0, _map_h - 1)
					# BERGE : masque brut des bassins, inchangé (la bande
					# mouillée mord volontairement au-delà de la nappe).
					occ[cz * _map_w + cx] = 1.0
					# CARTE D'EAU : sous l'eau = masque ET nappe visible.
					if fimg != null and fimg.get_pixel(tx, tz).g < 0.5:
						continue
					# R = profondeur normalisée du bassin (déjà 0..1 dans son
					# image), combinée au MAX là où plusieurs bassins se
					# recouvrent ; G = masque d'eau.
					wdepth[cz * _map_w + cx] = maxf(wdepth[cz * _map_w + cx], px.r)
					wmask[cz * _map_w + cx] = 1.0
	# Dilate : la bande mouillée mord sur la berge (2 passes, atténuation).
	for _pass in range(2):
		var nxt := occ.duplicate()
		for cz in range(_map_h):
			for cx in range(_map_w):
				var best: float = occ[cz * _map_w + cx]
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nx := cx + dx
						var nz := cz + dz
						if nx < 0 or nx >= _map_w or nz < 0 or nz >= _map_h:
							continue
						best = maxf(best, occ[nz * _map_w + nx] * 0.72)
				nxt[cz * _map_w + cx] = best
		occ = nxt
	var img2 := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var wimg := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	for cz in range(_map_h):
		for cx in range(_map_w):
			var v: float = occ[cz * _map_w + cx]
			img2.set_pixel(cx, cz, Color(v, 0.0, 0.0, 1.0))
			wimg.set_pixel(cx, cz, Color(
				wdepth[cz * _map_w + cx], wmask[cz * _map_w + cx], 0.0, 1.0))
	_shore_texture = ImageTexture.create_from_image(img2)
	_water_map_texture = ImageTexture.create_from_image(wimg)

## Texture de berge (null si aucun bassin d'eau).
func get_shore_texture() -> ImageTexture:
	return _shore_texture

## Carte d'eau combinée pour le shader du terrain (R = profondeur normalisée,
## G = masque d'eau), null si aucun bassin d'eau. C'est elle qui porte les
## caustiques animées et l'absorption par profondeur du lit sous l'eau.
func get_water_map_texture() -> ImageTexture:
	return _water_map_texture

## Construit un bassin **lac/mare** : polygone de cases, rempli jusqu'à `level`.
func _build_lake_body(body: Dictionary) -> Dictionary:
	var level := float((body as Dictionary).get("level", 0.0))
	var area_raw = (body as Dictionary).get("area", [])
	if not (area_raw is Array):
		return {}
	var poly := PackedVector2Array()
	for p in (area_raw as Array):
		if p is Array and (p as Array).size() >= 2:
			poly.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
	if poly.size() < 3:
		return {}
	var mesh := _build_polygon_water_mesh(poly, level * _cell_size)
	if mesh == null or mesh.get_surface_count() == 0:
		return {}
	# Immersion : les cases du polygone dont le sol visible est sous le niveau.
	var submerged := 0
	var max_depth := 0.0
	var bbox := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bbox = bbox.expand(p)
	var x0 := maxi(0, int(floorf(bbox.position.x)))
	var x1 := mini(_map_w, int(ceili(bbox.end.x)))
	var y0 := maxi(0, int(floorf(bbox.position.y)))
	var y1 := mini(_map_h, int(ceili(bbox.end.y)))
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if not _point_in_poly(Vector2(float(cx), float(cy)), poly):
				continue
			var depth := level - get_cell_top_surface(cx, cy)
			if depth > WATER_EPSILON:
				submerged += 1
				max_depth = maxf(max_depth, depth)
	if submerged == 0:
		return {}
	var depth_data := _make_body_depth(level, max_depth, poly)
	var speed := float((body as Dictionary).get("flow_speed", 0.10))
	# Direction de courant optionnelle (canaux) : coordonnées monde
	# normalisées, comme l'UV2 du shader. Défaut historique (1, 0).
	var flow_dir := Vector2(1.0, 0.0)
	var raw_dir = (body as Dictionary).get("flow_dir", null)
	if raw_dir is Array and (raw_dir as Array).size() >= 2:
		flow_dir = Vector2(float((raw_dir as Array)[0]), float((raw_dir as Array)[1]))
	var flow_strength := float((body as Dictionary).get("flow_strength", -1.0))
	# Échelle de dérive visuelle : un canal (flow_dir explicite) peut se lire,
	# un lac doit à peine bouger. Surchargeable par bassin (`flow_visual_scale`).
	var visual_scale := float((body as Dictionary).get("flow_visual_scale", -1.0))
	if visual_scale < 0.0:
		var has_dir := raw_dir is Array and (raw_dir as Array).size() >= 2
		visual_scale = CANAL_FLOW_VISUAL_SCALE if has_dir else LAKE_FLOW_VISUAL_SCALE
	var mat := _make_body_material(depth_data["texture"],
		flow_dir, speed, 0.0, Vector2.ZERO, flow_strength, visual_scale)
	_add_body_node(mesh, mat)
	return {
		"mesh": mesh, "material": mat,
		"texture": depth_data["texture"], "image": depth_data["image"],
		"footprint": _make_poly_footprint(poly, level),
		"submerged": submerged, "max_depth": max_depth, "level": level,
	}

## Construit un bassin **rivière** : ruban le long du tracé (points
## [x, niveau, z] en cases). Les segments qui chutent de plus de
## `FALL_MIN_DROP` deviennent des cascades (plans verticaux, surface dédiée du
## maillage avec le shader de chute qui s'écoule vers le bas). Le shader de
## surface dérive le long du tracé (`flow_dir = (0, 1)`, UV.v = l'aval).
func _build_river_body(body: Dictionary) -> Dictionary:
	var path_raw = (body as Dictionary).get("path", [])
	if not (path_raw is Array):
		return {}
	var pts: Array = []
	for p in (path_raw as Array):
		if p is Array and (p as Array).size() >= 3:
			pts.append(Vector3(float((p as Array)[0]), float((p as Array)[1]),
				float((p as Array)[2])))
	if pts.size() < 2:
		return {}
	var width := maxf(0.25, float((body as Dictionary).get("width", 1.2)))
	# Profondeur d'eau du lit : la nappe se cale au-dessus du FOND du lit
	# creusé (et non au ras de la surface) — elle remplit donc le creux.
	var water_depth := maxf(0.04, float((body as Dictionary).get("depth", 0.25)))
	# Largeur du MAILLAGE un peu plus grande que le lit : la nappe déborde sur
	# les berges, le terrain la découpe → rives naturelles (pas de bande collée).
	# Pas trop large : dans les virages serrés le ruban se replierait sur
	# lui-même (triangles parasites).
	var geo_width := width + 0.6
	var cell := _cell_size
	# 1) Lisse le TRACÉ : les points de contrôle sont anguleux — une rivière
	#    fait des méandres ronds, pas des segments cassés.
	if pts.size() >= 3:
		var sm: Array = pts.duplicate()
		for _pass in range(5):
			var out: Array = [pts[0]]
			for i in range(1, sm.size() - 1):
				var a: Vector3 = sm[i - 1]
				var b: Vector3 = sm[i]
				var c: Vector3 = sm[i + 1]
				out.append(Vector3((a.x + 2.0 * b.x + c.x) * 0.25, b.y,
					(a.z + 2.0 * b.z + c.z) * 0.25))
			out.append(pts[pts.size() - 1])
			sm = out
		pts = sm
	# 1bis) Coudes en ÉPINGLE : un tracé qui revient sur lui-même replie le
	#        ruban sur lui-même (z-fighting sombre au coude). On retire les
	#        pointes de demi-tour, puis on relisse.
	for _pass in range(2):
		if pts.size() < 4:
			break
		var kept: Array = [pts[0]]
		for i in range(1, pts.size() - 1):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var d0 := Vector2(b.x - a.x, b.z - a.z)
			var d1 := Vector2(c.x - b.x, c.z - b.z)
			if d0.length() > 0.001 and d1.length() > 0.001 \
					and d0.normalized().dot(d1.normalized()) < -0.3:
				continue
			kept.append(b)
		kept.append(pts[pts.size() - 1])
		pts = kept
		var sm2: Array = pts.duplicate()
		for _p2 in range(3):
			var out2: Array = [pts[0]]
			for i in range(1, sm2.size() - 1):
				var a2: Vector3 = sm2[i - 1]
				var b2: Vector3 = sm2[i]
				var c2: Vector3 = sm2[i + 1]
				out2.append(Vector3((a2.x + 2.0 * b2.x + c2.x) * 0.25, b2.y,
					(a2.z + 2.0 * b2.z + c2.z) * 0.25))
			out2.append(pts[pts.size() - 1])
			sm2 = out2
		pts = sm2
	# 2) Ré-échantillonnage dense : niveau d'eau = sol réel sous le lit
	#    (creusements/sculpture compris) + profondeur d'eau.
	var dense: Array = []
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var flat_ab := Vector2(b.x - a.x, b.z - a.z)
		var steps := maxi(1, ceili(flat_ab.length() / 0.25))
		for s in range(steps):
			var t := float(s) / float(steps)
			var p := a.lerp(b, t)
			p.y = _terrain_top_at(p.x, p.z) + water_depth
			dense.append(p)
	var tail: Vector3 = pts[pts.size() - 1]
	tail.y = _terrain_top_at(tail.x, tail.z) + water_depth
	dense.append(tail)
	# 3) Surface LISSE (fenêtre large) : une rivière a une pente continue,
	#    elle n'épouse pas les ondulations du fond.
	var win := 4
	for _pass in range(2):
		var ys2 := PackedFloat32Array()
		ys2.resize(dense.size())
		for i in range(dense.size()):
			var acc := 0.0
			var cnt := 0
			for k in range(-win, win + 1):
				var j := clampi(i + k, 0, dense.size() - 1)
				acc += (dense[j] as Vector3).y
				cnt += 1
			ys2[i] = acc / float(cnt)
		for i in range(dense.size()):
			var p: Vector3 = dense[i]
			p.y = ys2[i]
			dense[i] = p
	# 4) Plancher minimal : la nappe ne passe pas SOUS le sol de son axe —
	#    mais elle reste encaissée (pas de bande posée sur l'herbe).
	for i in range(dense.size()):
		var p: Vector3 = dense[i]
		p.y = maxf(p.y, _terrain_top_at(p.x, p.z) + 0.04)
		dense[i] = p
	# 5) Coupe les points hors carte (le tracé peut déborder du plateau) : sans
	# ça la nappe file en longue bande plate au-delà de la carte.
	var clipped: Array = []
	for p in dense:
		if p.x < 0.05 or p.x > float(_map_w) - 0.05 \
				or p.z < 0.05 or p.z > float(_map_h) - 0.05:
			continue
		clipped.append(p)
	if clipped.size() >= 2:
		dense = clipped
	if dense.size() < 2:
		return {}
	# Extrémités EFFILÉES : la rivière s'affine en pointe au lieu d'être
	# coupée au carré. Largeur du maillage par point.
	var widths := PackedFloat32Array()
	widths.resize(dense.size())
	var total_len := 0.0
	var runs := PackedFloat32Array()
	runs.resize(dense.size())
	for i in range(1, dense.size()):
		var pa: Vector3 = dense[i - 1]
		var pb: Vector3 = dense[i]
		total_len += Vector2(pb.x - pa.x, pb.z - pa.z).length()
		runs[i] = total_len
	for i in range(dense.size()):
		var from_start: float = runs[i]
		var from_end: float = total_len - runs[i]
		var taper := clampf(minf(from_start, from_end) / 1.2, 0.0, 1.0)
		widths[i] = maxf(0.10, geo_width * (0.20 + 0.80 * taper))
	# 5bis) Sous-échantillonnage aux FORTES COURBURES : les segments voisins
	#       d'un coude sont découpés plus fin (`CURVE_STEP_MIN` au plus serré),
	#       `y` et largeurs interpolés linéairement. Le tracé lui-même ne bouge
	#       pas : le masque de profondeur (rastérisé sur le même tracé) reste
	#       strictement identique, et la densité de sommets obtenue permet au
	#       lissage latéral (`_path_side`) de dessiner un vrai arc au coude.
	var refined := _subdivide_curvature(dense, widths)
	dense = refined["dense"]
	widths = refined["widths"]
	# Surface 0 = eau courante (ruban + bourrelets), surface 1 = cascades.
	var s0 := _empty_surface_arrays()
	var s1 := _empty_surface_arrays()
	# --- Chutes : repérage sur le SOL VISIBLE (heightfield du terrain) -------
	# `dense.y` suit la surface de POSE lissée (convention historique, utilisée
	# par le ruban d'eau courante) ; le sol réellement rendu est le heightfield
	# à sommets moyennés (`height_at`), décalé d'une demi-case sur les ressauts.
	# Une nappe calée sur `dense.y` s'enfouit donc dans la falaise : on repère
	# les descentes raides du maillage et on accroche le rideau dessus.
	var ground_y := PackedFloat32Array()
	ground_y.resize(dense.size())
	var field := _ensure_terrain_field()
	for gi in range(dense.size()):
		var gp: Vector3 = dense[gi]
		ground_y[gi] = field.height_at(gp.x, gp.z) + water_depth
	# Chaque entrée = [indice du point de crête, indice du point de pied] ; le
	# rideau couvre d'un bord du plateau à l'autre, d'un seul tenant.
	var falls: Array = []
	var fi := 0
	while fi < dense.size() - 1:
		var fa: Vector3 = dense[fi]
		var fb: Vector3 = dense[fi + 1]
		var f_flat := Vector2(fb.x - fa.x, fb.z - fa.z).length()
		var f_drop := ground_y[fi] - ground_y[fi + 1]
		if f_drop <= 0.0 or f_drop / maxf(f_flat, 0.001) < FALL_MIN_SLOPE:
			fi += 1
			continue
		var start_i := fi
		var end_i := fi
		var total_drop := 0.0
		while end_i < dense.size() - 1:
			var e0: Vector3 = dense[end_i]
			var e1: Vector3 = dense[end_i + 1]
			var e_flat := Vector2(e1.x - e0.x, e1.z - e0.z).length()
			var e_drop := ground_y[end_i] - ground_y[end_i + 1]
			if e_drop <= 0.0 \
					or e_drop / maxf(e_flat, 0.001) < FALL_MIN_SLOPE * 0.55:
				break
			total_drop += e_drop
			end_i += 1
		if total_drop >= FALL_MIN_DROP:
			# Un point de plateau en amont (crête) et un point de plaine en
			# aval (pied) : le rideau joint les deux nappes sans trou.
			falls.append([maxi(0, start_i - 1), mini(dense.size() - 1, end_i + 1)])
			fi = end_i + 1
		else:
			fi = maxi(fi + 1, end_i)
	var inv_w := 1.0 / maxf(float(_map_w) * cell, 0.0001)
	var inv_h := 1.0 / maxf(float(_map_h) * cell, 0.0001)
	var v_run := 0.0
	var fall_faces := 0
	var level_sum := 0.0
	var in_fall := false
	# --- Mousse de RIVE par sommet (canal VERT lu par le shader d'eau) ------
	# 1.0 là où le terrain referme la nappe au-delà du bord du maillage
	# (tranchée, berge qui masque la coupe du masque) ; atténué fortement sur
	# un bord LIBRE (maillage posé à nu : biefs sans tranchée, abords de
	# chute, bourrelet de pied). Sans cette distinction, la mousse de rive
	# suivait la coupe échelonnée du masque sur le maillage libre : bandes
	# pâles en échelles le long des bords latéraux du ruban.
	var shore_gate := func(centers: Array, sides: Array) -> Array:
		var gates: Array = []
		for k in range(4):
			var c: Vector3 = centers[k]
			var sd: Vector2 = sides[k]
			var closes := -1000.0
			for probe in [1.3, 1.7, 2.2]:
				closes = maxf(closes,
					_visible_ground_at(c.x + sd.x * probe, c.z + sd.y * probe) - c.y)
			gates.append(0.15 + 0.85 * smoothstep(-0.02, 0.12, closes))
		return gates
	# Distance de chaque point du tracé à l'extrémité la plus proche (cases) :
	# base du fondu d'alpha en bout de ruban (nez effilé adouci, la continuité
	# du milieu du chenal est intacte).
	var tip_dist := PackedFloat32Array()
	tip_dist.resize(dense.size())
	var run_len := 0.0
	for i in range(1, dense.size()):
		var pa: Vector3 = dense[i - 1]
		var pb: Vector3 = dense[i]
		run_len += Vector2(pb.x - pa.x, pb.z - pa.z).length()
		tip_dist[i] = run_len
	for i in range(dense.size()):
		tip_dist[i] = minf(tip_dist[i], run_len - tip_dist[i])
	# MASQUE DE POINTE (finition CS2, canal BLEU de la couleur de sommet) :
	# 1 au nez effilé, décroissance douce sur `TIP_MASK_RANGE` cases, 0 au cœur
	# du chenal. Le shader d'eau s'en sert pour éteindre l'alpha des pointes
	# quand la caméra est très haute (vue d'ensemble) — le fond du ruban garde
	# exactement son ancien fondu d'alpha (canal R), la continuité est intacte.
	var tip_mask := PackedFloat32Array()
	tip_mask.resize(dense.size())
	for i in range(dense.size()):
		tip_mask[i] = 1.0 - smoothstep(0.0, TIP_MASK_RANGE, tip_dist[i])
	for i in range(dense.size() - 1):
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[i + 1]
		var delta := b - a
		var flat := Vector2(delta.x, delta.z)
		if flat.length() < 0.001 and absf(delta.y) < 0.001:
			continue
		# Largeurs par bissectrice : les quads se rejoignent exactement dans
		# les virages (plus de déchirures aux coudes).
		var side_a := _path_side(dense, i, widths[i])
		var side_b := _path_side(dense, i + 1, widths[i + 1])
		var seg_len := maxf(flat.length(), 0.001) * cell
		level_sum += (a.y + b.y) * 0.5
		if absf(delta.y) < FALL_MIN_DROP:
			in_fall = false
			# Segment d'eau courante (éventuellement en pente douce).
			var quad_centers := [a, a, b, b]
			var quad_sides := [-side_a, side_a, -side_b, side_b]
			var fades := _visibility_fades(quad_centers, quad_sides)
			# Bout de ruban : l'alpha s'amenuise sur le dernier mètre de chaque
			# extrémité (le nez effilé, trop franc vu de dessus) ; le milieu du
			# chenal n'est pas touché — continuité de la rivière intacte.
			var tip_a := smoothstep(0.0, 1.2, tip_dist[i])
			var tip_b := smoothstep(0.0, 1.2, tip_dist[i + 1])
			fades[0] = float(fades[0]) * tip_a
			fades[1] = float(fades[1]) * tip_a
			fades[2] = float(fades[2]) * tip_b
			fades[3] = float(fades[3]) * tip_b
			_append_quad(s0, quad_centers, quad_sides,
				[Vector2(0.0, v_run), Vector2(1.0, v_run),
					Vector2(0.0, v_run + seg_len), Vector2(1.0, v_run + seg_len)],
				Vector3.UP, cell, inv_w, inv_h, fades,
				shore_gate.call(quad_centers, quad_sides),
				[tip_mask[i], tip_mask[i], tip_mask[i + 1], tip_mask[i + 1]])
			v_run += seg_len
		else:
			if in_fall:
				# Au milieu d'une chute déjà couverte par son rideau.
				v_run += seg_len
				continue
			# DÉBUT d'une chute : le ruban d'eau courante s'interrompt ; le
			# rideau et son bourrelet sont posés plus bas, sur le maillage.
			v_run += seg_len
			in_fall = true
	# --- BRUME DE PIED DE CASCADE (finition CS2) ---------------------------
	# Deux quads par chute, accumulés dans UNE surface (un seul draw call) :
	#   • un voile VERTICAL du pied vers le haut, qui se dissipe avec la
	#     hauteur (`UV.y`) — la colonne d'éclaboussure ;
	#   • une nappe HORIZONTALE basse qui déborde vers l'aval — la brume
	#     plaquée au sol, lisible même avec la caméra zénithale de la carte.
	# Budget borné par `MIST_MAX_QUADS` ; `set_mist_enabled(false)` éteint
	# l'uniform (discard) et masque le nœud → rendu précédent exact (A/B).
	var mist := _empty_mist_surface()
	var mist_quads := 0
	# --- Rideaux de chute : UNE seule nappe par ressaut, accrochée à la paroi
	# visible, du bord du plateau jusqu'au pied. Le pied s'écarte légèrement
	# vers l'aval (la lame d'eau ressort) et s'évase : la silhouette n'est pas
	# un panneau rectangle, et les bords se fondent dans l'écume.
	for fall in falls:
		var i0 := int(fall[0])
		var i1 := int(fall[1])
		if i1 <= i0:
			continue
		var top: Vector3 = dense[i0]
		var bot: Vector3 = dense[i1]
		var flat_vec := Vector2(bot.x - top.x, bot.z - top.z)
		if flat_vec.length() <= 0.001:
			continue
		var fall_dir := flat_vec.normalized()
		# Rideau TRAPÉZOÏDAL : un peu plus étroit à la crête (le seuil borde le
		# chenal), il s'évase légèrement vers le pied — la silhouette n'est plus
		# un panneau rectangulaire à coins vifs.
		var top_side := _path_side(dense, i0, widths[i0] * 0.96)
		var bot_side := _path_side(dense, i1, widths[i1] * 1.05)
		# Le pied se décolle un peu de la paroi (aval) : la lame tombe au lieu
		# d'être plaquée comme une peinture.
		var lean := minf(flat_vec.length() * 0.22, 0.55)
		# CRÊTE : on se cale sur le niveau de la rivière amont (surface lissée)
		# pour un raccord sans marche ; PIED : sur le niveau de la plaine aval.
		# Le rideau baigne ainsi dans les deux nappes, sans lèvre qui dépasse.
		var top_y := minf(top.y + 0.03, ground_y[i0] + 0.06)
		var bot_y := ground_y[i1] + 0.02
		var top_c := Vector3(top.x, top_y, top.z)
		var bot_c := Vector3(bot.x + fall_dir.x * lean, bot_y,
			bot.z + fall_dir.y * lean)
		_append_quad(s1,
			[top_c, top_c, bot_c, bot_c],
			[-top_side, top_side, -bot_side, bot_side],
			[Vector2(0.0, 1.0), Vector2(1.0, 1.0),
				Vector2(0.0, 0.0), Vector2(1.0, 0.0)],
			Vector3(fall_dir.x, 0.0, fall_dir.y), cell, inv_w, inv_h)
		# BOURRELET de pied : anneau d'eau EFFILÉ à la surface du bief aval,
		# juste devant le rideau — large au contact de la chute, effilé vers
		# l'aval et fondu de partout (opacité par couleur de sommet). Il reste
		# DANS le masque de profondeur (demi-largeur < 1.2 texel-case) : c'est
		# son propre bord adouci qui ferme la nappe, jamais la coupe droite du
		# masque (qui allumait une bande d'écume rectiligne de chaque côté).
		# Il porte l'écume d'impact du shader de surface et se pose au niveau
		# du bassin, pas au milieu de la pente.
		var apron_y := ground_y[i1] + 0.04
		var apron_len := width * 0.60
		var apron_end := Vector2(bot_c.x, bot_c.z) + fall_dir * apron_len
		var nose_side := bot_side * 0.20
		# Bourrelet posé à NU (pas de tranchée) : la mousse de rive y est
		# fortement atténuée (canal vert) pour ne pas allumer de bandes pâles
		# échelonnées le long de ses bords ; l'écume d'impact (crêtes) reste.
		var apron_centers := [Vector3(bot_c.x, apron_y, bot_c.z),
			Vector3(bot_c.x, apron_y, bot_c.z),
			Vector3(apron_end.x, apron_y, apron_end.y),
			Vector3(apron_end.x, apron_y, apron_end.y)]
		var apron_sides := [-bot_side * 0.92, bot_side * 0.92, -nose_side, nose_side]
		_append_quad(s0, apron_centers, apron_sides,
			[Vector2(0.0, v_run), Vector2(1.0, v_run),
				Vector2(0.0, v_run + apron_len * cell),
				Vector2(1.0, v_run + apron_len * cell)],
			Vector3.UP, cell, inv_w, inv_h,
			[0.45, 0.45, 0.10, 0.10],
			shore_gate.call(apron_centers, apron_sides))
		v_run += apron_len * cell
		fall_faces += 1
		# --- BRUME DE PIED : voile vertical + nappe horizontale basse -------
		# Hauteur proportionnelle au ressaut, bornée (une brume basse ne monte
		# pas la falaise) ; largeur un peu plus grande que le pied de chute.
		if mist_quads < MIST_MAX_QUADS:
			var mist_h := clampf((top_y - bot_y) * 0.55,
				MIST_HEIGHT_MIN, MIST_HEIGHT_MAX)
			var veil_side := bot_side * MIST_VEIL_WIDEN
			var veil_top_side := bot_side * 1.05
			var base_c := Vector3(bot_c.x, bot_y - 0.02, bot_c.z)
			var head_c := Vector3(bot_c.x, bot_y + mist_h, bot_c.z)
			_append_mist_quad(mist,
				[base_c - Vector3(veil_side.x, 0.0, veil_side.y),
					base_c + Vector3(veil_side.x, 0.0, veil_side.y),
					head_c - Vector3(veil_top_side.x, 0.0, veil_top_side.y),
					head_c + Vector3(veil_top_side.x, 0.0, veil_top_side.y)],
				Vector3(fall_dir.x, 0.0, fall_dir.y), cell)
			mist_quads += 1
		if mist_quads < MIST_MAX_QUADS:
			var ap_start := Vector2(bot_c.x, bot_c.z) + fall_dir * (width * 0.08)
			var ap_end := ap_start + fall_dir * (width * MIST_APRON_LEN + 0.5)
			var ap_y := bot_y + 0.03
			var ap_start_side := bot_side * 1.7
			var ap_end_side := bot_side * 0.55
			_append_mist_quad(mist,
				[Vector3(ap_start.x, ap_y, ap_start.y)
						- Vector3(ap_start_side.x, 0.0, ap_start_side.y),
					Vector3(ap_start.x, ap_y, ap_start.y)
						+ Vector3(ap_start_side.x, 0.0, ap_start_side.y),
					Vector3(ap_end.x, ap_y, ap_end.y)
						- Vector3(ap_end_side.x, 0.0, ap_end_side.y),
					Vector3(ap_end.x, ap_y, ap_end.y)
						+ Vector3(ap_end_side.x, 0.0, ap_end_side.y)],
				Vector3.UP, cell)
			mist_quads += 1
	var arrays0 := _finish_surface_arrays(s0)
	var arrays1 := _finish_surface_arrays(s1)
	# NB : `_finish_surface_arrays` renvoie un tableau VIDE (pas null) sans
	# géométrie — tester `is_empty()`, sinon `add_surface_from_arrays([])`.
	if arrays0.is_empty() and arrays1.is_empty():
		return {}
	# Profondeur/masque **par cellule** le long du lit : chaque case du tracé
	# reçoit le niveau d'eau local, la profondeur = niveau − sol visible. La
	# nappe a ainsi de vraies rives et un dégradé d'eau sur toute la descente.
	var level := level_sum / float(maxi(1, dense.size() - 1))
	var depth_data := _make_river_depth(dense, geo_width)
	var speed := float((body as Dictionary).get("flow_speed", 0.35))
	# Bords de ruban FONDUS : l'alpha s'amenuise sur le dernier tiers de la
	# largeur, de chaque côté — la nappe s'achève en lame d'eau qui lappe la
	# berge au lieu d'un bord de maillage franc (silhouette vue de dessus
	# adoucie, cœur du chenal intact).
	# Déplacement du motif DANS LE REPÈRE DU RUBAN (le long du tracé), remis à
	# l'échelle monde normalisée pour garder les fréquences d'un lac.
	var ribbon_flow := Vector2(
		geo_width / maxf(float(_map_w) * cell, 0.0001),
		1.0 / maxf(float(_map_h) * cell, 0.0001))
	var mat := _make_body_material(depth_data["texture"], Vector2(0.0, 1.0), speed, 0.72,
		ribbon_flow)
	var mesh := ArrayMesh.new()
	if not arrays0.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays0)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	if not arrays1.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays1)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _make_fall_material())
	# Matériaux portés par les SURFACES — un `material_override` au niveau du
	# nœud écraserait le shader de chute de la surface dédiée (la nappe
	# repassait en shader d'eau → masquée par le discard du terrain).
	_add_body_node(mesh, null)
	return {
		"mesh": mesh, "material": mat,
		"texture": depth_data["texture"], "image": depth_data["image"],
		"footprint": _make_river_footprint(dense, widths),
		"submerged": 1, "max_depth": maxf(level - _lowest_point(dense), WATER_EPSILON),
		"level": level, "falls": fall_faces,
		"mist": _finish_mist_surface(mist), "mist_quads": mist_quads,
	}

## Sol visible (en cases) sous une position du tracé — la rivière le drape.
func _terrain_top_at(x: float, z: float) -> float:
	return _ensure_terrain_field().top_surface_at(x, z)

## Sol VISIBLE RENDU (en cases) sous (x, z) — référence des MASQUES d'eau.
##
## Sur une colonne intacte, `top_surface_at` renvoie la bilinéaire de pose
## historique, alors que le maillage de sol rendu est `height_at` (sommets
## moyennés) : sur un ressaut, le maillage monte d'une demi-case AU-DESSUS de
## la bilinéaire et découpe la nappe en un bord rectangulaire dur. Le masque de
## profondeur doit donc mesurer la profondeur face au VRAI sol visible — c'est
## le shader (fondue d'alpha + liseré de rive) qui dessine alors la ligne
## d'eau, au lieu du bord géométrique du maillage. Sur une colonne creusée ou
## sculptée, `top_surface_at` est déjà le sol visible (scan du champ) : on le
## garde tel quel, l'eau remplit toujours les creux.
func _visible_ground_at(x: float, z: float) -> float:
	var field := _ensure_terrain_field()
	var top := field.top_surface_at(x, z)
	if is_equal_approx(top, field.cell_bilinear(x, z)):
		return maxf(top, field.height_at(x, z))
	return top

## Sous-échantillonne le ruban aux FORTES COURBURES : chaque segment voisin
## d'un coude est découpé jusqu'à `CURVE_STEP_MIN` cases, `y` et largeurs
## interpolés linéairement entre les points existants. Le tracé lui-même ne
## bouge pas (les points ajoutés sont exactement sur les segments) : le masque
## de profondeur reste identique, seuls les sommets du MAILLAGE se densifient —
## condition pour que le lissage latéral dessine un arc régulier au coude.
func _subdivide_curvature(dense: Array, widths: PackedFloat32Array) -> Dictionary:
	if dense.size() < 2:
		return {"dense": dense, "widths": widths}
	# Angle de virage (radians, repère XZ) au voisinage de chaque point.
	var turns := PackedFloat32Array()
	turns.resize(dense.size())
	for i in range(dense.size()):
		var d0 := Vector2.ZERO
		var d1 := Vector2.ZERO
		if i > 0:
			var pa0: Vector3 = dense[i - 1]
			var pb0: Vector3 = dense[i]
			d0 = Vector2(pb0.x - pa0.x, pb0.z - pa0.z)
		if i < dense.size() - 1:
			var pb1: Vector3 = dense[i]
			var pc1: Vector3 = dense[i + 1]
			d1 = Vector2(pc1.x - pb1.x, pc1.z - pb1.z)
		if d0.length() > 0.001 and d1.length() > 0.001:
			turns[i] = acos(clampf(d0.normalized().dot(d1.normalized()), -1.0, 1.0))
	var out: Array = []
	var out_w := PackedFloat32Array()
	out.append(dense[0])
	out_w.append(widths[0])
	for i in range(dense.size() - 1):
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		var theta := maxf(turns[i], turns[i + 1])
		var step := clampf(0.25 / (1.0 + 3.0 * theta), CURVE_STEP_MIN, 0.25)
		var n := maxi(1, ceili(seg / step))
		for k in range(1, n):
			var t := float(k) / float(n)
			out.append(a.lerp(b, t))
			out_w.append(lerpf(widths[i], widths[i + 1], t))
		out.append(b)
		out_w.append(widths[i + 1])
	return {"dense": out, "widths": out_w}

## Demi-largeur latérale d'un ruban au point `i`.
##
## La direction latérale est perpendiculaire à la tangente LOCALE LISSÉE sur
## une fenêtre glissante (`SIDE_SMOOTH_RADIUS` cases dans chaque sens) : les
## quads voisins partagent exactement le même vecteur latéral (aucune déchirure
## aux joints) et la rotation d'un virage se répartit sur plusieurs sommets —
## la silhouette du coude décrit un ARC au lieu de deux bords rectilignes qui
## se coupent en un coin marqué. Le MITER est limité deux fois : `shrink`
## resserre le ruban selon l'angle du virage (mesuré sur la fenêtre), et le
## rayon de courbure borne la demi-largeur — le ruban ne se replie jamais sur
## lui-même dans un virage serré.
func _path_side(dense: Array, i: int, width: float) -> Vector2:
	var back := Vector2.ZERO
	var fwd := Vector2.ZERO
	var dist := 0.0
	var j := i
	while j > 0 and dist < SIDE_SMOOTH_RADIUS:
		var pa: Vector3 = dense[j - 1]
		var pb: Vector3 = dense[j]
		var dv := Vector2(pb.x - pa.x, pb.z - pa.z)
		var seg := dv.length()
		if seg > 0.001:
			back += dv.normalized() * minf(seg, SIDE_SMOOTH_RADIUS - dist)
			dist += seg
		j -= 1
	dist = 0.0
	j = i
	while j < dense.size() - 1 and dist < SIDE_SMOOTH_RADIUS:
		var pa: Vector3 = dense[j]
		var pb: Vector3 = dense[j + 1]
		var dv := Vector2(pb.x - pa.x, pb.z - pa.z)
		var seg := dv.length()
		if seg > 0.001:
			fwd += dv.normalized() * minf(seg, SIDE_SMOOTH_RADIUS - dist)
			dist += seg
		j += 1
	var d := back + fwd
	# Virage en épingle : les deux sens s'annulent → prendre la direction
	# entrante (sinon le ruban se replie).
	if d.length() <= 0.001:
		if back.length() > 0.001:
			d = back
		elif fwd.length() > 0.001:
			d = fwd
		else:
			d = Vector2.RIGHT
	# Angle du virage sur la fenêtre (radians) : base du miter limit.
	var turn := 0.0
	if back.length() > 0.001 and fwd.length() > 0.001:
		turn = acos(clampf(back.normalized().dot(fwd.normalized()), -1.0, 1.0))
	var shrink := 1.0
	if turn > 0.0:
		shrink = 0.45 + 0.55 * clampf((cos(turn) + 1.0) * 0.5, 0.0, 1.0)
	var half := width * 0.5 * shrink
	# Miter limit : la demi-largeur ne dépasse jamais le rayon de courbure du
	# virage (fenêtre / angle) — jamais de repli ni de pointe au coude.
	if turn > 0.001:
		half = minf(half, (2.0 * SIDE_SMOOTH_RADIUS) / turn * 0.85)
	return Vector2(-d.y, d.x).normalized() * half

## Opacité par sommet d'un quad de ruban : la nappe s'amenuise là où elle
## affleure le sol visible rendu, et disparaît juste avant que le maillage de
## terrain ne la recouvre (talus, ressauts — la nappe de pose y plonge sous le
## sol rendu). La ligne d'eau devient un DÉGRADÉ d'alpha, jamais le bord
## rectangulaire du maillage de terrain.
func _visibility_fades(centers: Array, sides: Array) -> Array:
	var fades: Array = []
	for k in range(4):
		var c: Vector3 = centers[k]
		var sd: Vector2 = sides[k]
		var depth := c.y - _visible_ground_at(c.x + sd.x, c.z + sd.y)
		fades.append(smoothstep(-0.03, 0.18, depth))
	return fades

## Tableaux vides d'une surface (accumulateur des quads).
func _empty_surface_arrays() -> Dictionary:
	return {
		"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"uvs": PackedVector2Array(), "uv2s": PackedVector2Array(),
		"colors": PackedColorArray(), "indices": PackedInt32Array(),
	}

## Ajoute un quad (4 coins : centre + demi-largeur latérale) à une surface.
## `fades` porte l'OPACITÉ par sommet (canal R de la couleur de sommet, lue
## par le shader d'eau) : 1.0 partout sauf aux extrémités à fondre.
## `foam_fades` porte la MOUSSE DE RIVE par sommet (canal VERT) : 1.0 là où
## le terrain referme la nappe (berge, tranchée), atténué sur les bords
## libres (bandes pâles échelonnées sinon) — vide = 1.0 partout.
## `tip_fades` porte le MASQUE DE POINTE par sommet (canal BLEU, finition CS2) :
## 1.0 au nez effilé du ruban, 0.0 au cœur du chenal — le shader d'eau s'en
## sert pour éteindre l'alpha des pointes vues de très haut. Vide = 0 partout.
## NOTE Godot : un PackedArray sorti d'un Dictionary est **copié** par `as` ou
## par un `var` typé — on mutte donc toujours via `s["..."]` directement.
func _append_quad(s: Dictionary, centers: Array, sides: Array, uvs: Array,
		normal: Vector3, cell: float, inv_w: float, inv_h: float,
		fades: Array = [1.0, 1.0, 1.0, 1.0],
		foam_fades: Array = [],
		tip_fades: Array = []) -> void:
	var base: int = s["verts"].size()
	for k in range(4):
		var c: Vector3 = centers[k]
		var sd: Vector2 = sides[k]
		var v := Vector3((c.x + sd.x) * cell, c.y * cell, (c.z + sd.y) * cell)
		s["verts"].append(v)
		s["normals"].append(normal)
		s["uvs"].append(uvs[k])
		s["uv2s"].append(Vector2(v.x * inv_w, v.z * inv_h))
		var fade := clampf(float(fades[k]), 0.0, 1.0)
		var foam_gate := 1.0
		if k < foam_fades.size():
			foam_gate = clampf(float(foam_fades[k]), 0.0, 1.0)
		var tip := 0.0
		if k < tip_fades.size():
			tip = clampf(float(tip_fades[k]), 0.0, 1.0)
		s["colors"].append(Color(fade, foam_gate, tip, 1.0))
	s["indices"].append_array(PackedInt32Array([
		base, base + 2, base + 1, base + 1, base + 2, base + 3]))

func _finish_surface_arrays(s: Dictionary) -> Array:
	if s["indices"].is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = s["verts"]
	arrays[Mesh.ARRAY_NORMAL] = s["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = s["uvs"]
	arrays[Mesh.ARRAY_TEX_UV2] = s["uv2s"]
	arrays[Mesh.ARRAY_COLOR] = s["colors"]
	arrays[Mesh.ARRAY_INDEX] = s["indices"]
	return arrays

## Matériau de cascade (chute animée vers le bas, écume aux deux extrémités).
func _make_fall_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists(WATER_FALL_SHADER_PATH):
		mat.shader = load(WATER_FALL_SHADER_PATH)
	else:
		mat.shader = WATER_SHADER
	mat.set_shader_parameter("fall_speed", 1.6)
	# Teinte SATURÉE : une chute pâle se lave en blanc sous la lumière.
	mat.set_shader_parameter("water_tint", Color(0.12, 0.34, 0.42))
	mat.set_shader_parameter("foam_color", Color(0.82, 0.92, 0.95))
	mat.set_shader_parameter("night_tint", 1.0 if _night_mode else 0.0)
	return mat

## Matériau de BRUME de pied de cascade (finition CS2) : voile bas animé,
## non éclairé, transparent, sans écriture de profondeur. `mist_enabled = 0`
## (discard) → rendu strictement identique à l'état précédent (A/B).
## Si le shader est absent du projet, aucune brume n'est construite : on ne
## retombe jamais sur le shader d'eau (qui exigerait une texture de profondeur).
func _make_mist_material() -> ShaderMaterial:
	if not ResourceLoader.exists(WATER_MIST_SHADER_PATH):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(WATER_MIST_SHADER_PATH)
	mat.set_shader_parameter("mist_color", Color(0.82, 0.89, 0.92))
	mat.set_shader_parameter("mist_density", 0.48)
	mat.set_shader_parameter("mist_speed", 0.35)
	mat.set_shader_parameter("mist_scale", 2.4)
	mat.set_shader_parameter("night_tint", 1.0 if _night_mode else 0.0)
	mat.set_shader_parameter("mist_enabled", 1.0 if _mist_enabled else 0.0)
	return mat

## Accumulateur d'une surface de brume (quads indépendants, unshaded).
func _empty_mist_surface() -> Dictionary:
	return {
		"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"uvs": PackedVector2Array(), "indices": PackedInt32Array(),
	}

## Ajoute un quad de BRUME (coins en CASES, multipliés par `cell`). L'ordre des
## coins suit celui des surfaces d'eau : [bas-gauche, bas-droite, haut-gauche,
## haut-droite] ; UV.v = 0 au contact (pied), 1 au sommet / au loin — c'est `v`
## qui porte la dissipation avec la hauteur dans le shader.
func _append_mist_quad(s: Dictionary, corners: Array, normal: Vector3,
		cell: float) -> void:
	if corners.size() < 4:
		return
	var uvs: Array = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0),
		Vector2(0.0, 1.0), Vector2(1.0, 1.0),
	]
	var base: int = s["verts"].size()
	for k in range(4):
		var c: Vector3 = corners[k]
		s["verts"].append(Vector3(c.x * cell, c.y * cell, c.z * cell))
		s["normals"].append(normal)
		s["uvs"].append(uvs[k])
	s["indices"].append_array(PackedInt32Array([
		base, base + 2, base + 1, base + 1, base + 2, base + 3]))

## Finalise un maillage de brume (null si aucune chute/quad).
func _finish_mist_surface(s: Dictionary) -> ArrayMesh:
	if s["indices"].is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = s["verts"]
	arrays[Mesh.ARRAY_NORMAL] = s["normals"]
	arrays[Mesh.ARRAY_TEX_UV] = s["uvs"]
	arrays[Mesh.ARRAY_INDEX] = s["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _lowest_point(pts: Array) -> float:
	var low := INF
	for p in pts:
		low = minf(low, (p as Vector3).y)
	return low if low < INF else 0.0

## Empreinte VISIBLE du maillage d'un lac (résolution carte) : 1 = la case est
## couverte par le plan polygonal du bassin ET son sol visible est sous le
## niveau (nappe réellement rendue). Sert à restreindre la carte d'eau aux
## cases recouvertes par la surface visible — une case dont le sol affleure ou
## dépasse la ligne de flottaison (fondus de nappe, ressauts) n'est pas « sous
## l'eau » à l'écran (règle d'or : pas d'effet hors de la nappe visible).
func _make_poly_footprint(poly: PackedVector2Array, level: float) -> Image:
	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var bbox := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bbox = bbox.expand(p)
	var x0 := maxi(0, int(floorf(bbox.position.x)))
	var x1 := mini(_map_w, int(ceili(bbox.end.x)))
	var y0 := maxi(0, int(floorf(bbox.position.y)))
	var y1 := mini(_map_h, int(ceili(bbox.end.y)))
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if not _point_in_poly(Vector2(float(cx), float(cy)), poly):
				continue
			if level - _visible_ground_at(float(cx), float(cy)) <= 0.05:
				continue
			img.set_pixel(cx, cy, Color(0.0, 1.0, 0.0, 1.0))
	return img

## Empreinte VISIBLE du ruban de rivière (4 texels/case, même résolution que
## `_make_river_depth`) : 1 = le texel du lit est couvert par le maillage de
## la nappe (demi-largeur locale `widths[i]/2` du ruban) ET son sol visible
## est sous le niveau local (les fondus de nappe effacent la surface au-delà).
## Au-delà de cette empreinte, la profondeur « théorique » du lissage peut
## dépasser le sol local sans qu'aucune eau ne soit visible : ces cases restent
## hors masque.
func _make_river_footprint(dense: Array, widths: PackedFloat32Array) -> Image:
	var res := 4
	var tw := _map_w * res
	var th := _map_h * res
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var inv_res := 1.0 / float(res)
	for i in range(dense.size() - 1):
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[i + 1]
		var hw_a := widths[i] * 0.5
		var hw_b := widths[i + 1] * 0.5
		var half := maxf(hw_a, hw_b)
		var x0 := maxi(0, floori((minf(a.x, b.x) - half) * float(res)))
		var x1 := mini(tw - 1, ceili((maxf(a.x, b.x) + half) * float(res)))
		var z0 := maxi(0, floori((minf(a.z, b.z) - half) * float(res)))
		var z1 := mini(th - 1, ceili((maxf(a.z, b.z) + half) * float(res)))
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var len2 := maxf(ab.length_squared(), 0.0001)
		for tz in range(z0, z1 + 1):
			for tx in range(x0, x1 + 1):
				var p := Vector2((float(tx) + 0.5) * inv_res,
					(float(tz) + 0.5) * inv_res)
				var t := clampf((p - Vector2(a.x, a.z)).dot(ab) / len2, 0.0, 1.0)
				var closest := Vector2(a.x, a.z) + ab * t
				if p.distance_to(closest) > lerpf(hw_a, hw_b, t):
					continue
				var level_y := lerpf(a.y, b.y, t)
				if level_y - _visible_ground_at(p.x, p.y) <= 0.05:
					continue
				img.set_pixel(tx, tz, Color(0.0, 1.0, 0.0, 1.0))
	return img

## Texture de profondeur **par bassin** (R = profondeur normalisée depuis le
## niveau du bassin, G = masque : 1 uniquement là où le sol visible est sous ce
## niveau — c'est ce qui fait « remplir les creux » et évite l'eau dans les
## grottes sèches). `poly` confine le bassin à son emprise : une cuvette
## étrangère au même niveau (autre mare, terrain creusé plus loin) reste à sec.
func _make_body_depth(level: float, max_depth: float,
		poly: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var inv_depth := 1.0 / maxf(max_depth, WATER_EPSILON)
	var confined := poly.size() >= 3
	for y in range(_map_h):
		for x in range(_map_w):
			if confined and not _point_in_poly(Vector2(float(x) + 0.5, float(y) + 0.5), poly):
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
				continue
			var depth := level - get_cell_top_surface(x, y)
			var value := 0.0
			var mask := 0.0
			if depth > WATER_EPSILON:
				value = clampf(depth * inv_depth, 0.0, 1.0)
				mask = 1.0
			img.set_pixel(x, y, Color(value, mask, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return {"image": img, "texture": tex}

## Profondeur/masque d'une rivière à HAUTE RÉSOLUTION (4 texels par case) :
## chaque texel du lit reçoit le niveau d'eau local (interpolé le long du
## tracé), la profondeur = niveau − sol visible échantillonné en sub-cellule.
## Résultat : des rives NETTES (la texture 1 texel/case ba vait sur une case
## entière → bande floue) et un dégradé d'eau correct sur toute la descente.
func _make_river_depth(dense: Array, width: float) -> Dictionary:
	var res := 4
	var tw := _map_w * res
	var th := _map_h * res
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	var levels := PackedFloat32Array()
	levels.resize(tw * th)
	levels.fill(-INF)
	var half := maxf(0.3, width * 0.5 + 0.1)
	var inv_res := 1.0 / float(res)
	var field := _ensure_terrain_field()
	# Rasterise le lit : les texels à moins de `half` du tracé prennent le
	# niveau interpolé du segment le plus proche.
	for i in range(dense.size() - 1):
		var a: Vector3 = dense[i]
		var b: Vector3 = dense[i + 1]
		var x0 := maxi(0, floori((minf(a.x, b.x) - half) * float(res)))
		var x1 := mini(tw - 1, ceili((maxf(a.x, b.x) + half) * float(res)))
		var z0 := maxi(0, floori((minf(a.z, b.z) - half) * float(res)))
		var z1 := mini(th - 1, ceili((maxf(a.z, b.z) + half) * float(res)))
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var len2 := maxf(ab.length_squared(), 0.0001)
		for tz in range(z0, z1 + 1):
			for tx in range(x0, x1 + 1):
				var p := Vector2((float(tx) + 0.5) * inv_res,
					(float(tz) + 0.5) * inv_res)
				var t := clampf((p - Vector2(a.x, a.z)).dot(ab) / len2, 0.0, 1.0)
				var closest := Vector2(a.x, a.z) + ab * t
				if p.distance_to(closest) > half:
					continue
				var idx := tz * tw + tx
				levels[idx] = maxf(levels[idx], lerpf(a.y, b.y, t))
	var max_depth := WATER_EPSILON
	for tz in range(th):
		for tx in range(tw):
			var idx := tz * tw + tx
			if levels[idx] == -INF:
				continue
			var wx := (float(tx) + 0.5) * inv_res
			var wz := (float(tz) + 0.5) * inv_res
			# Profondeur face au sol de pose (masque historique inchangé).
			max_depth = maxf(max_depth, levels[idx] - field.top_surface_at(wx, wz))
	var inv_depth := 1.0 / maxf(max_depth, 0.02)
	for tz in range(th):
		for tx in range(tw):
			var idx := tz * tw + tx
			var value := 0.0
			var mask := 0.0
			if levels[idx] != -INF:
				# Masque par PROFONDEUR : l'eau n'apparaît que là où le sol
				# est SOUS le niveau — c'est le terrain qui dessine les rives
				# (le maillage déborde, la nappe est découpée au bord). Le
				# masque garde la convention historique (`top_surface_at`) :
				# c'est le SHADER (opacité par sommet + fondus de bord) qui
				# adoucit la ligne d'eau, jamais le masque lui-même.
				var wx := (float(tx) + 0.5) * inv_res
				var wz := (float(tz) + 0.5) * inv_res
				var depth := levels[idx] - field.top_surface_at(wx, wz)
				if depth > 0.015:
					mask = 1.0
					value = clampf(depth * inv_depth, 0.0, 1.0)
			img.set_pixel(tx, tz, Color(value, mask, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return {"image": img, "texture": tex}

## Matériau de surface d'un bassin : copie du shader d'eau avec le sens
## d'écoulement (les vagues dérivent le long de `flow_dir`). `edge_softness`
## atténue l'alpha sur les bords latéraux du ruban (rivières).
##
## Réglages « qualité CS2 » : mousse de contact, micro-vagues, lisibilité du
## lit et scintillement se règlent ici — l'échelle de détail n'est pas la même
## sur un lac que sur un ruban de rivière. Les uniforms non posés gardent les
## valeurs par défaut du shader.
func _make_body_material(depth_texture: ImageTexture,
		flow_dir: Vector2, flow_speed: float,
		edge_softness: float = 0.0,
		ribbon_flow: Vector2 = Vector2.ZERO,
		flow_strength_override: float = -1.0,
		flow_visual_override: float = -1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("depth_map", depth_texture)
	# Lac : teinte historique, surface plutôt calme avec une dérive lente (le
	# vent anime l'eau, sans courant marqué), mousse de rive discrète mais
	# lisible, caustiques visibles sur le lit des hauts-fonds.
	var shallow := SHALLOW_COLOR
	var deep := DEEP_COLOR
	var foam := 0.62
	var foam_w := 0.05
	var wave_strength := 0.08
	var wave_speed := 0.8
	var flow_strength := 0.65
	var foam_scale := 1.8
	var glint := 0.9
	var caustic := 0.45
	var bed := Color(0.44, 0.48, 0.31)
	# Ciel réfléchi (dégradé) et extinction par profondeur : l'eau d'un lac est
	# plus « dense » en profondeur qu'un ruisseau peu profond. L'horizon reste
	# teinté ciel (pas blanc) : le reflet de rase est lisible sans laver la
	# surface.
	var sky := Color(0.52, 0.66, 0.76)
	var horizon := Color(0.76, 0.83, 0.87)
	var extinction := 2.2
	var depth_bias := 0.0
	# Sonde de contact (texels) : le masque du lac a 1 texel/case. Rayon réduit
	# (~0,6 texel) : le liseré de mousse reste lisible à la rive mais FIN, et
	# sa largeur en cases suit la pente locale du fond (portée bornée par la
	# profondeur dans le shader) — plus d'anneau blanc épais et uniforme.
	var shore_texels := 0.6
	var sky_reflect := 0.24
	# Réflexion ÉCRAN (screen-space) : le décor (berges, falaises) se mire
	# dans la surface avec le poids Fresnel. Lac : reflet doux (0.35) qui
	# colore la rive proche sans laver l'eau.
	var reflect_on := 1.0
	var reflect_str := 0.35
	# Réfraction ÉCRAN (screen-space) : le lit déjà rendu transparaît dans les
	# hauts-fonds, déformé par les micro-vagues. Lac : distorsion douce (0.35),
	# le fond du haut-fond se lit sans « loupe » qui tord le sable.
	var refr_on := 1.0
	var refr_str := 0.35
	# Rivière (ruban animé) : teinte un peu plus vive, mousse de contact plus
	# fine et plus marquée le long des berges, dérive pleine dans le sens du
	# courant, caustiques plus discrètes (lit plus profond et plus ombré).
	if edge_softness > 0.0:
		shallow = Color(0.24, 0.55, 0.58)
		deep = Color(0.05, 0.18, 0.30)
		foam = 0.75
		foam_w = 0.07
		wave_strength = 0.18
		wave_speed = 1.1
		flow_strength = 1.0
	# Un canal (lac polygonal) peut demander une dérive plus marquée dans SA
	# direction, sans passer par les réglages du ruban de rivière.
	if flow_strength_override >= 0.0:
		flow_strength = clampf(flow_strength_override, 0.0, 1.0)
		foam_scale = 2.4
		glint = 1.0
		caustic = 0.28
		bed = Color(0.40, 0.44, 0.30)
		sky = Color(0.58, 0.70, 0.78)
		horizon = Color(0.76, 0.83, 0.87)
		# Eau courante mince : le fond reste lisible plus longtemps (la
		# profondeur normalisée du ruban est proche de 1 partout).
		extinction = 1.6
		depth_bias = -0.28
		# Masque de rivière à 4 texels/case : rayon de 1,2 texel — liseré fin
		# (~0,2 unité monde) de chaque côté du chenal, portée bornée par la
		# profondeur locale (bandes pâles échelonnées sinon sur les bords
		# libres du ruban, surtout près des chutes).
		shore_texels = 1.2
		sky_reflect = 0.22
		# Ruban étroit entre des berges proches : reflet écran présent mais
		# discret (0.32), pour que les rives se lisent dans le chenal sans
		# laver la clarté du flux.
		reflect_str = 0.32
		# Rivière claire et agitée : distorsion du lit un peu plus marquée
		# (0.40) — le courant plisse nettement le fond du chenal.
		refr_str = 0.40
		# DÉRIVE CALME : le `flow_speed` des données reste la vitesse de courant
		# « donnée » (le test la lit telle quelle) ; c'est la dérive VISIBLE du
		# motif qui est tempérée par `flow_visual_scale` (uniform du shader,
		# posé plus bas pour les rubans de rivière).
	mat.set_shader_parameter("shallow_color", shallow)
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("foam_color", FOAM_COLOR)
	mat.set_shader_parameter("bed_color", bed)
	mat.set_shader_parameter("sky_color", sky)
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("depth_extinction", extinction)
	mat.set_shader_parameter("depth_bias", depth_bias)
	mat.set_shader_parameter("night_tint", NIGHT_TINT if _night_mode else Color.WHITE)
	mat.set_shader_parameter("base_alpha", BASE_ALPHA)
	mat.set_shader_parameter("alpha_depth", ALPHA_DEPTH)
	mat.set_shader_parameter("wave_strength", wave_strength)
	mat.set_shader_parameter("wave_speed", wave_speed)
	mat.set_shader_parameter("foam_strength", foam)
	mat.set_shader_parameter("foam_width", foam_w)
	mat.set_shader_parameter("foam_scale", foam_scale)
	mat.set_shader_parameter("glint_strength", glint)
	mat.set_shader_parameter("caustic_strength", caustic)
	mat.set_shader_parameter("flow_dir", flow_dir)
	mat.set_shader_parameter("flow_speed", flow_speed)
	mat.set_shader_parameter("flow_strength", flow_strength)
	# Rivières : le motif dérive DANS LE REPÈRE DU RUBAN (u en travers, v le
	# long du tracé, ramenés à l'échelle monde normalisée) → le courant suit
	# les méandres au lieu de défiler dans une direction monde fixe.
	if ribbon_flow != Vector2.ZERO:
		mat.set_shader_parameter("flow_ribbon", 1.0)
		mat.set_shader_parameter("flow_ribbon_u_scale", ribbon_flow.x)
		mat.set_shader_parameter("flow_ribbon_v_scale", ribbon_flow.y)
		# Dépendance VISUELLE calmée (le `flow_speed` des données est conservé).
		mat.set_shader_parameter("flow_visual_scale", RIVER_FLOW_VISUAL_SCALE)
	else:
		# Lac / canal : dérive discrète (un canal se lit, un lac frémit à peine).
		mat.set_shader_parameter("flow_visual_scale",
			flow_visual_override if flow_visual_override >= 0.0 else LAKE_FLOW_VISUAL_SCALE)
	mat.set_shader_parameter("edge_softness", edge_softness)
	# Liseré de mousse de contact (rayon de sonde en texels) et reflet de ciel.
	mat.set_shader_parameter("shore_texels", shore_texels)
	mat.set_shader_parameter("sky_reflect", sky_reflect)
	# Réflexion écran (screen-space) : activée par défaut, `reflect_on = 0`
	# rend exactement l'ancien rendu (A/B réversible) ; `reflect_str` dose le
	# mélange décor/ciel réfléchi.
	mat.set_shader_parameter("reflection_enabled", reflect_on)
	mat.set_shader_parameter("reflection_strength", reflect_str)
	# Réfraction écran (screen-space) : activée par défaut, `refr_on = 0`
	# rend exactement l'état précédent (A/B réversible) ; `refr_str` dose la
	# distorsion du lit réfracté dans les hauts-fonds.
	mat.set_shader_parameter("refraction_enabled", refr_on)
	mat.set_shader_parameter("refraction_strength", refr_str)
	# FINITIONS CS2 (A/B réversible : 0 = état exact précédent).
	# — Éclairage double du lit réfracté : ambiance/diffusion d'eau déposée
	#   sur le lit des hauts-fonds, à côté des caustiques directes.
	mat.set_shader_parameter("bed_ambient_lift", _bed_ambient_lift)
	# — Adoucissement des nez de ruban vus de très haut : l'alpha s'éteint sur
	#   la pointe (masque COLOR.b) quand l'empreinte écran grandit (caméra
	#   haute / carte dézoomée). Les lacs n'ont pas de pointe (edge_softness
	#   nul) : l'effet ne les touche pas.
	mat.set_shader_parameter("tip_soften_distance", _tip_soften_distance)
	mat.set_shader_parameter("tip_soften_lo", 0.025)
	mat.set_shader_parameter("tip_soften_hi", 0.075)
	# Taille d'un texel de profondeur (UV) : le shader sonde le masque d'eau
	# voisin pour placer la mousse de contact au VRAI bord terre/eau.
	var tex_size := depth_texture.get_size()
	mat.set_shader_parameter("depth_texel", Vector2(
		1.0 / maxf(1.0, tex_size.x), 1.0 / maxf(1.0, tex_size.y)))
	return mat

## Maillage d'un plan de bassin (polygone de cases à hauteur `y_world`),
## triangulé par découpe d'oreilles (polygone simple, concave accepté).
func _build_polygon_water_mesh(poly: PackedVector2Array, y_world: float) -> ArrayMesh:
	var tris := _triangulate_polygon(poly)
	if tris.is_empty():
		return null
	var cell := _cell_size
	var inv_w := 1.0 / maxf(float(_map_w) * cell, 0.0001)
	var inv_h := 1.0 / maxf(float(_map_h) * cell, 0.0001)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	for p in poly:
		var wx := p.x * cell
		var wz := p.y * cell
		verts.append(Vector3(wx, y_world, wz))
		normals.append(Vector3.UP)
		uvs.append(Vector2(p.x, p.y))
		uv2s.append(Vector2(wx * inv_w, wz * inv_h))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = tris
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Découpe d'oreilles (ear clipping) : renvoie les triplets d'indices.
func _triangulate_polygon(poly: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var idx := PackedInt32Array()
	for i in range(poly.size()):
		idx.append(i)
	# Sens constant (aire signée) pour les tests d'oreille.
	var area2 := 0.0
	for i in range(poly.size()):
		var j := (i + 1) % poly.size()
		area2 += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	var guard := poly.size() * poly.size() + 8
	while idx.size() > 3 and guard > 0:
		guard -= 1
		var clipped := false
		for i in range(idx.size()):
			var i0 := idx[(i + idx.size() - 1) % idx.size()]
			var i1 := idx[i]
			var i2 := idx[(i + 1) % idx.size()]
			if not _is_ear(poly, idx, i0, i1, i2, area2):
				continue
			out.append(i0)
			out.append(i1)
			out.append(i2)
			idx.remove_at(i)
			clipped = true
			break
		if not clipped:
			break
	if idx.size() == 3:
		out.append(idx[0])
		out.append(idx[1])
		out.append(idx[2])
	elif idx.size() > 3:
		# Résidu non découpable (auto-intersection) : éventail depuis le centre.
		var center := Vector2.ZERO
		for p in poly:
			center += p
		center /= float(poly.size())
		for i in range(idx.size()):
			out.append(idx[i])
			out.append(idx[(i + 1) % idx.size()])
			out.append(idx[0])
	return out

func _is_ear(poly: PackedVector2Array, idx: PackedInt32Array,
		i0: int, i1: int, i2: int, area2: float) -> bool:
	var a := poly[i0]
	var b := poly[i1]
	var c := poly[i2]
	var cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	# Convexe dans le sens du polygone.
	if area2 > 0.0 and cross <= 0.0:
		return false
	if area2 < 0.0 and cross >= 0.0:
		return false
	# Aucun autre sommet à l'intérieur de l'oreille.
	for k in idx:
		if k == i0 or k == i1 or k == i2:
			continue
		var p := poly[k]
		var d1 := (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
		var d2 := (c.x - b.x) * (p.y - b.y) - (c.y - b.y) * (p.x - b.x)
		var d3 := (a.x - c.x) * (p.y - c.y) - (a.y - c.y) * (p.x - c.x)
		if (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) \
				or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0):
			return false
	return true

## Point dans un polygone — sélection des cases du bassin. Délégué à
## `Geometry2D` : la version « ray-casting » maison divisait par
## `max(pj.y - pi.y, eps)`, ce qui faussait le test dès que l'arête descendait
## (bassin à moitié à sec, masque d'eau incomplet).
func _point_in_poly(point: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, poly)

# ===========================================================================
# Décor de surface : lentilles d'eau + nénuphars (MultiMesh, déterministe)
# ===========================================================================

func _ensure_decor() -> void:
	if _duckweed_mmi == null or not is_instance_valid(_duckweed_mmi):
		_duckweed_mmi = MultiMeshInstance3D.new()
		_duckweed_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_duckweed_mmi.visible = false
		add_child(_duckweed_mmi)
	if _lily_mmi == null or not is_instance_valid(_lily_mmi):
		_lily_mmi = MultiMeshInstance3D.new()
		_lily_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lily_mmi.visible = false
		add_child(_lily_mmi)

func _clear_decor() -> void:
	_duckweed_count = 0
	_lily_count = 0
	if _duckweed_mmi != null and is_instance_valid(_duckweed_mmi):
		_duckweed_mmi.multimesh = null
		_duckweed_mmi.visible = false
	if _lily_mmi != null and is_instance_valid(_lily_mmi):
		_lily_mmi.multimesh = null
		_lily_mmi.visible = false

## Nombre de lentilles d'eau posées (0 si pas d'eau ou pas de décor).
func get_duckweed_count() -> int:
	return _duckweed_count

## Nombre de nénuphars posés (0 si pas d'eau ou pas de décor).
func get_lily_count() -> int:
	return _lily_count

func _rebuild_decor() -> void:
	_ensure_decor()
	_duckweed_count = 0
	_lily_count = 0
	if _water_level <= NO_WATER_LEVEL + 0.001 or _submerged_count == 0:
		_clear_decor()
		return
	var surface_y := get_surface_y()
	var cell := _cell_size
	var off := cell * 0.02
	var duck: Array[Transform3D] = []
	var lilies: Array[Transform3D] = []
	var shallow_cells: Array = []
	for cy in range(_map_h):
		for cx in range(_map_w):
			# Sol visible (creusements compris) : rien sur une case masquée,
			# même règle que le masque G de la texture de profondeur.
			var h := get_cell_top_surface(cx, cy)
			if h >= _water_level - WATER_EPSILON:
				continue
			var depth := _water_level - h
			if depth <= LILY_SHALLOW_DEPTH:
				shallow_cells.append(Vector2i(cx, cy))
			var r1 := _hash01(cx, cy, _decor_seed * 3 + 1)
			var r2 := _hash01(cx, cy, _decor_seed * 3 + 2)
			var r3 := _hash01(cx, cy, _decor_seed * 3 + 3)
			# Lentilles d'eau : petites pastilles vertes, parfois en grappes.
			if r1 < DUCKWEED_DENSITY * _decor_density and duck.size() < DUCKWEED_MAX:
				var cluster := 1 + int(r2 * 3.0)
				for k in range(cluster):
					if duck.size() >= DUCKWEED_MAX:
						break
					var jx := _hash01(cx, cy, _decor_seed * 5 + 11 + k)
					var jz := _hash01(cx, cy, _decor_seed * 5 + 17 + k)
					var px := (float(cx) + jx) * cell
					var pz := (float(cy) + jz) * cell
					var radius := lerpf(0.05, 0.11, _hash01(cx, cy, _decor_seed * 7 + k)) * cell
					var yaw := _hash01(cx, cy, _decor_seed * 7 + 31 + k) * TAU
					duck.append(Transform3D(
						Basis(Vector3.UP, yaw).scaled(Vector3.ONE * radius),
						Vector3(px, surface_y + off, pz)))
			# Nénuphars : larges feuilles sur les eaux peu profondes (rive).
			if depth <= LILY_SHALLOW_DEPTH and r2 < LILY_DENSITY * _decor_density and lilies.size() < LILY_MAX:
				var radius := lerpf(0.16, 0.26, r3) * cell
				var yaw := _hash01(cx, cy, _decor_seed * 7 + 5) * TAU
				lilies.append(Transform3D(
					Basis(Vector3.UP, yaw).scaled(Vector3.ONE * radius),
					Vector3((float(cx) + 0.5) * cell, surface_y + off, (float(cy) + 0.5) * cell)))
	# Garantie déterministe : s'il y a des hauts-fonds mais aucun nénuphar,
	# on en place un seul au « meilleur » emplacement (évite un étang vide).
	# Sauf densité nulle : dans ce cas on ne veut AUCUN décor.
	if _decor_density > 0.0 and lilies.is_empty() and not shallow_cells.is_empty() and _map_w > 0:
		var pick: Vector2i = shallow_cells[0]
		var best := -1.0
		for cand in shallow_cells:
			var cc: Vector2i = cand
			var score := _hash01(cc.x, cc.y, _decor_seed * 7 + 5)
			if score > best:
				best = score
				pick = cc
		var radius := lerpf(0.16, 0.24, best) * cell
		var yaw := _hash01(pick.x, pick.y, _decor_seed * 11 + 2) * TAU
		lilies.append(Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * radius),
			Vector3((float(pick.x) + 0.5) * cell, surface_y + off, (float(pick.y) + 0.5) * cell)))
	_set_multimesh(_duckweed_mmi, duck, DUCKWEED_COLOR)
	_set_multimesh(_lily_mmi, lilies, LILY_PAD_COLOR)
	_duckweed_count = duck.size()
	_lily_count = lilies.size()

func _set_multimesh(mmi: MultiMeshInstance3D, transforms: Array[Transform3D], color: Color) -> void:
	if transforms.is_empty():
		mmi.multimesh = null
		mmi.visible = false
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _disc_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	mmi.multimesh = mm
	if mmi.material_override == null or not (mmi.material_override is StandardMaterial3D):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mmi.material_override = mat
	(mmi.material_override as StandardMaterial3D).albedo_color = color
	mmi.visible = true

## Pastille plate (disque) de rayon 1, face +Y — mise à l'échelle par instance.
var _disc_mesh_cache: ArrayMesh = null
func _disc_mesh() -> ArrayMesh:
	if _disc_mesh_cache != null:
		return _disc_mesh_cache
	const SEGMENTS := 12
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		verts.append(Vector3(cos(a), 0.0, sin(a)))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))
	for i in range(SEGMENTS):
		indices.append(0)
		indices.append(1 + ((i + 1) % SEGMENTS))
		indices.append(1 + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_disc_mesh_cache = ArrayMesh.new()
	_disc_mesh_cache.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _disc_mesh_cache

## Hash déterministe 0..1, stable d'un rebuild à l'autre pour une même graine.
func _hash01(x: int, y: int, seed: int) -> float:
	var n: int = (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	n = (n ^ (n >> 13)) & 0xffffffff
	n = (n * 1274126177) & 0x7fffffff
	return float(n) / 2147483647.0

## Vrai si deux tableaux plats ont le même contenu.
func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if typeof(a[i]) == TYPE_FLOAT or typeof(b[i]) == TYPE_FLOAT:
			if not is_equal_approx(float(a[i]), float(b[i])):
				return false
		elif a[i] != b[i]:
			return false
	return true

## Vrai si deux listes de creusements (déjà normalisées) ont le même contenu
## (même convention que `MapGround3D._carves_equal`).
func _carves_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var da: Dictionary = a[i]
		var db: Dictionary = b[i]
		for key in da.keys():
			if not db.has(key):
				return false
			if da[key] is Vector3:
				if not (db[key] is Vector3) or (da[key] as Vector3).distance_to(db[key]) > 0.00001:
					return false
			elif da[key] is Array:
				if not (db[key] is Array) or str(da[key]) != str(db[key]):
					return false
			elif da[key] != db[key]:
				return false
	return true
