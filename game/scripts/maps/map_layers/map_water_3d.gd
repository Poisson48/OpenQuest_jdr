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
## texture générée ici à partir des hauteurs de terrain (une case = un texel,
## R = profondeur normalisée) : rive claire, large sombre. La nuit, une teinte
## sombre est appliquée (`night_tint`).
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

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _depth_texture: ImageTexture = null
var _depth_image: Image = null
var _water_level: float = NO_WATER_LEVEL
var _cell_size: float = 1.0
var _map_w: int = 0
var _map_h: int = 0
var _terrain_heights: Array = []
var _night_mode: bool = false
var _active: bool = false
## Nombre de cases immergées (h < waterLevel) au dernier rebuild.
var _submerged_count: int = 0
## Profondeur maximale observée (en cases), pour normaliser la texture.
var _max_depth: float = 0.0
## État du dernier rebuild (pour ignorer les mises à jour sans changement).
var _has_config: bool = false

func _ready() -> void:
	_ensure_mesh_instance()

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
## qu'au moins une case de terrain est en dessous.
func configure(
	map_width: int,
	map_height: int,
	cell_size: float,
	water_level: float,
	terrain_heights: Array = [],
	night_mode: bool = false
) -> void:
	var next_heights: Array = terrain_heights if terrain_heights is Array else []
	var next_level := float(water_level)
	var next_w := maxi(0, map_width)
	var next_h := maxi(0, map_height)
	var next_cell := cell_size if cell_size > 0.0 else 1.0
	if _has_config \
			and next_w == _map_w and next_h == _map_h \
			and is_equal_approx(next_cell, _cell_size) \
			and is_equal_approx(next_level, _water_level) \
			and _arrays_equal(next_heights, _terrain_heights) \
			and night_mode == _night_mode:
		return
	_map_w = next_w
	_map_h = next_h
	_cell_size = next_cell
	_water_level = next_level
	_terrain_heights = next_heights
	_night_mode = night_mode
	_has_config = true
	_rebuild()

## Retire complètement l'eau (mode illustré, ou carte sans plan d'eau).
func clear() -> void:
	_active = false
	_submerged_count = 0
	_max_depth = 0.0
	_depth_texture = null
	_depth_image = null
	_has_config = false
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
	if _has_config:
		_rebuild()

## Active / désactive la teinte de nuit.
func set_night_mode(on: bool) -> void:
	if _night_mode == on:
		return
	_night_mode = on
	if _has_config:
		_rebuild()

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

## Vrai si la case est sous le niveau de l'eau.
func is_cell_submerged(cx: int, cy: int) -> bool:
	if _water_level <= NO_WATER_LEVEL + 0.001:
		return false
	if cx < 0 or cy < 0 or cx >= _map_w or cy >= _map_h:
		return false
	return get_cell_height(cx, cy) < _water_level - WATER_EPSILON

## Texture de profondeur du plan d'eau (R = profondeur normalisée, 1 = plus
## profond), null si pas d'eau.
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
	if _map_w <= 0 or _map_h <= 0 or _water_level <= NO_WATER_LEVEL + 0.001:
		_deactivate()
		return
	var submerged := 0
	var max_depth := 0.0
	for y in range(_map_h):
		for x in range(_map_w):
			var depth := _water_level - get_cell_height(x, y)
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

func _deactivate() -> void:
	_active = false
	_submerged_count = 0
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

## Construit / met à jour la texture de profondeur (une case = un texel,
## R = profondeur normalisée : 0 à la rive, 1 au plus profond).
func _build_depth_texture(max_depth: float) -> void:
	var img := Image.create(_map_w, _map_h, false, Image.FORMAT_RGBA8)
	var inv_depth := 1.0 / maxf(max_depth, WATER_EPSILON)
	for y in range(_map_h):
		for x in range(_map_w):
			var depth := _water_level - get_cell_height(x, y)
			var value := 0.0
			if depth > WATER_EPSILON:
				value = clampf(depth * inv_depth, 0.0, 1.0)
			img.set_pixel(x, y, Color(value, value, value, 1.0))
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
