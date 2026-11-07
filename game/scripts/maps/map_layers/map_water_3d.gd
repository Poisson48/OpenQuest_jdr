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
	_terrain_heights = next_heights
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
	_terrain_carves = []
	_terrain_field = null
	_has_config = false
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
	_terrain_heights = terrain_heights if terrain_heights is Array else []
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
	_clear_decor()
	_clear_body_nodes()
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
const WATER_FALL_SHADER_PATH := "res://shaders/water_fall.gdshader"

## Nombre de bassins rendus (0 si l'eau utilise le plan historique).
func get_body_count() -> int:
	return _body_nodes.size()

func _clear_body_nodes() -> void:
	for node in _body_nodes:
		if node != null and is_instance_valid(node):
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

## Reconstruit tous les bassins (lacs polygonaux + rivières/cascades).
func _rebuild_bodies() -> void:
	_clear_body_nodes()
	_mesh_instance.mesh = null
	_mesh_instance.visible = false
	var submerged := 0
	var max_depth := 0.0
	var first: Dictionary = {}
	var depth_images: Array = []
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
		submerged += int(built.get("submerged", 0))
		max_depth = maxf(max_depth, float(built.get("max_depth", 0.0)))
		if first.is_empty():
			first = built
	_build_shore_texture(depth_images)
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

## Texture de BERGE pour le shader du terrain : 1 = eau, dégradé = terre
## mouillée. Union des bassins, dilatée de ~2 cases (bande de berge).
func _build_shore_texture(images: Array) -> void:
	_shore_texture = null
	if images.is_empty():
		return
	var occ := PackedFloat32Array()
	occ.resize(_map_w * _map_h)
	occ.fill(0.0)
	for dimg in images:
		var img: Image = dimg
		var w := img.get_width()
		var h := img.get_height()
		var sx := float(_map_w) / float(maxi(1, w))
		var sz := float(_map_h) / float(maxi(1, h))
		for tz in range(h):
			for tx in range(w):
				if img.get_pixel(tx, tz).g >= 0.5:
					var cx := clampi(int(float(tx) * sx), 0, _map_w - 1)
					var cz := clampi(int(float(tz) * sz), 0, _map_h - 1)
					occ[cz * _map_w + cx] = 1.0
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
	for cz in range(_map_h):
		for cx in range(_map_w):
			var v: float = occ[cz * _map_w + cx]
			img2.set_pixel(cx, cz, Color(v, 0.0, 0.0, 1.0))
	_shore_texture = ImageTexture.create_from_image(img2)

## Texture de berge (null si aucun bassin d'eau).
func get_shore_texture() -> ImageTexture:
	return _shore_texture

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
	var depth_data := _make_body_depth(level, max_depth)
	var speed := float((body as Dictionary).get("flow_speed", 0.10))
	var mat := _make_body_material(depth_data["texture"],
		Vector2(1.0, 0.0), speed)
	_add_body_node(mesh, mat)
	return {
		"mesh": mesh, "material": mat,
		"texture": depth_data["texture"], "image": depth_data["image"],
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
	# Surface 0 = eau courante (ruban + bourrelets), surface 1 = cascades.
	var s0 := _empty_surface_arrays()
	var s1 := _empty_surface_arrays()
	var inv_w := 1.0 / maxf(float(_map_w) * cell, 0.0001)
	var inv_h := 1.0 / maxf(float(_map_h) * cell, 0.0001)
	var v_run := 0.0
	var fall_faces := 0
	var level_sum := 0.0
	var in_fall := false
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
			_append_quad(s0,
				[a, a, b, b],
				[-side_a, side_a, -side_b, side_b],
				[Vector2(0.0, v_run), Vector2(1.0, v_run),
					Vector2(0.0, v_run + seg_len), Vector2(1.0, v_run + seg_len)],
				Vector3.UP, cell, inv_w, inv_h)
			v_run += seg_len
		else:
			if in_fall:
				# Au milieu d'une chute déjà couverte par sa nappe unique.
				v_run += seg_len
				continue
			# DÉBUT d'une chute : repérer la fin du groupe de segments qui
			# descendent, puis poser UNE SEULE nappe du haut du saut au bas.
			var j := i
			while j < dense.size() - 1:
				var dj: Vector3 = (dense[j + 1] as Vector3) - (dense[j] as Vector3)
				if absf(dj.y) < FALL_MIN_DROP:
					break
				j += 1
			var hi: Vector3 = dense[i]
			var lo: Vector3 = dense[j + 1]
			if lo.y > hi.y:
				var tmp := hi
				hi = lo
				lo = tmp
			var top_side := _path_side(dense, i, widths[i])
			var bot_side := _path_side(dense, j + 1, widths[j + 1])
			var dir := flat.normalized()
			# Nappe unique : paroi du haut jusqu'au pied, légèrement arc-boutée
			# vers l'aval — une cascade, pas une pile de panneaux.
			var foot: Vector3 = lo + Vector3(dir.x, 0.0, dir.y) * 0.18
			_append_quad(s1,
				[hi, hi, foot, foot],
				[-top_side, top_side, -bot_side, bot_side],
				[Vector2(0.0, 1.0), Vector2(1.0, 1.0),
					Vector2(0.0, 0.0), Vector2(1.0, 0.0)],
				Vector3(dir.x, 0.0, dir.y), cell, inv_w, inv_h)
			# Bourrelet d'arrivée au pied de la chute.
			var apron := Vector2(lo.x, lo.z) + dir * (width * 0.35)
			_append_quad(s0,
				[lo, lo, Vector3(apron.x, lo.y, apron.y), Vector3(apron.x, lo.y, apron.y)],
				[-bot_side, bot_side, -bot_side, bot_side],
				[Vector2(0.0, v_run), Vector2(1.0, v_run),
					Vector2(0.0, v_run + width * 0.35 * cell),
					Vector2(1.0, v_run + width * 0.35 * cell)],
				Vector3.UP, cell, inv_w, inv_h)
			v_run += seg_len
			fall_faces += 1
			in_fall = true
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
	var mat := _make_body_material(depth_data["texture"], Vector2(0.0, 1.0), speed, 0.15)
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
		"submerged": 1, "max_depth": maxf(level - _lowest_point(dense), WATER_EPSILON),
		"level": level, "falls": fall_faces,
	}

## Sol visible (en cases) sous une position du tracé — la rivière le drape.
func _terrain_top_at(x: float, z: float) -> float:
	return _ensure_terrain_field().top_surface_at(x, z)

## Demi-largeur latérale d'un ruban au point `i` : perpendiculaire à la
## bissectrice des directions voisines — les quads se rejoignent exactement
## dans les virages.
func _path_side(dense: Array, i: int, width: float) -> Vector2:
	var d := Vector2.ZERO
	if i > 0:
		var prev: Vector3 = dense[i - 1]
		var here: Vector3 = dense[i]
		var dv := Vector2(here.x - prev.x, here.z - prev.z)
		if dv.length() > 0.001:
			d += dv.normalized()
	if i < dense.size() - 1:
		var here: Vector3 = dense[i]
		var next: Vector3 = dense[i + 1]
		var dv := Vector2(next.x - here.x, next.z - here.z)
		if dv.length() > 0.001:
			d += dv.normalized()
	# Virage en épingle : les deux directions s'annulent → prendre la
	# perpendiculaire du segment ENTRANT (sinon le ruban se replie).
	if d.length() <= 0.001:
		if i > 0:
			var prev2: Vector3 = dense[i - 1]
			var here2: Vector3 = dense[i]
			var dv2 := Vector2(here2.x - prev2.x, here2.z - prev2.z)
			if dv2.length() > 0.001:
				d = dv2.normalized()
		if d.length() <= 0.001:
			d = Vector2.RIGHT
	# Réduction de largeur dans les virages serrés : au-delà d'un certain
	# angle, le ruban se replierait sur lui-même (triangles parasites).
	var shrink := 1.0
	if i > 0 and i < dense.size() - 1:
		var pa: Vector3 = dense[i - 1]
		var pb: Vector3 = dense[i]
		var pc: Vector3 = dense[i + 1]
		var d0 := Vector2(pb.x - pa.x, pb.z - pa.z)
		var d1 := Vector2(pc.x - pb.x, pc.z - pb.z)
		if d0.length() > 0.001 and d1.length() > 0.001:
			var turn := clampf((d0.normalized().dot(d1.normalized()) + 1.0) * 0.5, 0.0, 1.0)
			shrink = 0.45 + 0.55 * turn
	return Vector2(-d.y, d.x).normalized() * (width * 0.5 * shrink)

## Tableaux vides d'une surface (accumulateur des quads).
func _empty_surface_arrays() -> Dictionary:
	return {
		"verts": PackedVector3Array(), "normals": PackedVector3Array(),
		"uvs": PackedVector2Array(), "uv2s": PackedVector2Array(),
		"indices": PackedInt32Array(),
	}

## Ajoute un quad (4 coins : centre + demi-largeur latérale) à une surface.
## NOTE Godot : un PackedArray sorti d'un Dictionary est **copié** par `as` ou
## par un `var` typé — on mutte donc toujours via `s["..."]` directement.
func _append_quad(s: Dictionary, centers: Array, sides: Array, uvs: Array,
		normal: Vector3, cell: float, inv_w: float, inv_h: float) -> void:
	var base: int = s["verts"].size()
	for k in range(4):
		var c: Vector3 = centers[k]
		var sd: Vector2 = sides[k]
		var v := Vector3((c.x + sd.x) * cell, c.y * cell, (c.z + sd.y) * cell)
		s["verts"].append(v)
		s["normals"].append(normal)
		s["uvs"].append(uvs[k])
		s["uv2s"].append(Vector2(v.x * inv_w, v.z * inv_h))
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

func _lowest_point(pts: Array) -> float:
	var low := INF
	for p in pts:
		low = minf(low, (p as Vector3).y)
	return low if low < INF else 0.0

## Texture de profondeur **par bassin** (R = profondeur normalisée depuis le
## niveau du bassin, G = masque : 1 uniquement là où le sol visible est sous ce
## niveau — c'est ce qui fait « remplir les creux » et évite l'eau dans les
## grottes sèches).
func _make_body_depth(level: float, max_depth: float) -> Dictionary:
	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var inv_depth := 1.0 / maxf(max_depth, WATER_EPSILON)
	for y in range(_map_h):
		for x in range(_map_w):
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
				# (le maillage déborde, la nappe est découpée au bord).
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
func _make_body_material(depth_texture: ImageTexture,
		flow_dir: Vector2, flow_speed: float,
		edge_softness: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("depth_map", depth_texture)
	# Rivière (ruban animé) : teinte un peu plus vive et écume presque nulle
	# (eau calme) ; les lacs gardent la teinte historique.
	var shallow := SHALLOW_COLOR
	var deep := DEEP_COLOR
	var foam := 1.0
	var foam_w := 0.12
	if edge_softness > 0.0:
		shallow = Color(0.24, 0.55, 0.58)
		deep = Color(0.05, 0.18, 0.30)
		foam = 0.15
		foam_w = 0.035
	mat.set_shader_parameter("shallow_color", shallow)
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("foam_color", FOAM_COLOR)
	mat.set_shader_parameter("night_tint", NIGHT_TINT if _night_mode else Color.WHITE)
	mat.set_shader_parameter("base_alpha", BASE_ALPHA)
	mat.set_shader_parameter("alpha_depth", ALPHA_DEPTH)
	mat.set_shader_parameter("wave_strength", 0.08)
	mat.set_shader_parameter("wave_speed", 0.9)
	mat.set_shader_parameter("foam_strength", foam)
	mat.set_shader_parameter("foam_width", foam_w)
	mat.set_shader_parameter("flow_dir", flow_dir)
	mat.set_shader_parameter("flow_speed", flow_speed)
	mat.set_shader_parameter("flow_strength", 1.0)
	mat.set_shader_parameter("edge_softness", edge_softness)
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

## Point dans un polygone (ray-casting) — sélection des cases du bassin.
func _point_in_poly(point: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in range(poly.size()):
		var pi := poly[i]
		var pj := poly[j]
		if ((pi.y > point.y) != (pj.y > point.y)) \
				and (point.x < (pj.x - pi.x) * (point.y - pi.y) / maxf(pj.y - pi.y, 0.00001) + pi.x):
			inside = not inside
		j = i
	return inside

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
