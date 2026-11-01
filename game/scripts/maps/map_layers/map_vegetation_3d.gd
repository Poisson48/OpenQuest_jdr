extends Node3D
class_name MapVegetation3D

## Végétation procédurale de la carte 2.5D (`terrain3d` uniquement).
##
## But : casser la platitude du sol peint en semant des **touffes d'herbe** et
## quelques **fleurs** sur les cases d'herbe, façon Dofus (rendu stylisé, lisible
## de haut). Tout est **déterministe** (hash entier par case) : la végétation ne
## « saute » pas d'un refresh à l'autre, et les tests peuvent compter les
## instances.
##
## Rendu : deux `MultiMeshInstance3D` (touffes + fleurs) construits avec des
## quads croisés à dégradé de couleur, matériau `unshaded` avec **vent doux**
## (shader inline, ondulation sinusoïdale par instance), couleurs d'instance
## variées, aucune ombre portée, aucune collision. Les cases non-herbe et les
## cases immergées (sous `water_level`) sont ignorées. La nuit, `albedo_tint`
## assombrit/refroidit l'ensemble.

## Densité de touffes par case d'herbe (0..1).
const TUFT_DENSITY := 0.85
## Densité de fleurs par case d'herbe (0..1).
const FLOWER_DENSITY := 0.18
## Densité de buissons par case d'herbe (0..1).
const BUSH_DENSITY := 0.16
## Garde-fou de performance : nombre max d'instances par catégorie.
const MAX_TUFTS := 5000
const MAX_FLOWERS := 1800
const MAX_BUSHES := 900
const MATERIAL_GRASS := 0
## Teinte de nuit (même logique que le sol).
const NIGHT_TINT := Color(0.40, 0.44, 0.58)
## Couleurs d'instance des touffes (verts Valbois lumineux, variation douce).
const TUFT_COLORS := [
	Color(0.34, 0.56, 0.20),
	Color(0.28, 0.48, 0.16),
	Color(0.40, 0.62, 0.24),
	Color(0.24, 0.44, 0.14),
	Color(0.36, 0.58, 0.22),
]
## Couleurs d'instance des fleurs : blanc/crème, jaune, rose, bleu, orange.
const FLOWER_COLORS := [
	Color(0.98, 0.96, 0.86),
	Color(0.99, 0.88, 0.36),
	Color(0.96, 0.62, 0.74),
	Color(0.70, 0.76, 1.00),
	Color(0.99, 0.70, 0.40),
	Color(0.90, 0.84, 1.00),
]
## Couleurs d'instance des buissons (verts plus sombres, volume).
const BUSH_COLORS := [
	Color(0.30, 0.46, 0.20),
	Color(0.36, 0.52, 0.24),
	Color(0.26, 0.42, 0.18),
]

## Shader inline : albédo unshaded + vent (balancement par instance).
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wind_strength : hint_range(0.0, 0.4) = 0.05;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.6;

void vertex() {
	// UV.y : 1 en haut de la touffe, 0 au pied → le vent plie le haut.
	float sway = sin(TIME * wind_speed + MODEL_MATRIX[3].x * 0.8 + MODEL_MATRIX[3].z * 1.1);
	float gust = sin(TIME * wind_speed * 0.37 + MODEL_MATRIX[3].x * 0.31);
	VERTEX.x += sway * wind_strength * UV.y;
	VERTEX.z += (sway * 0.6 + gust * 0.4) * wind_strength * 0.6 * UV.y;
}

void fragment() {
	// COLOR = vertex color (dégradé pied→pointe) × couleur d'instance.
	ALBEDO = COLOR.rgb * albedo_tint.rgb;
}
"""

var _tuft_instance: MultiMeshInstance3D
var _flower_instance: MultiMeshInstance3D
var _bush_instance: MultiMeshInstance3D
var _material: ShaderMaterial
var _tuft_mesh: ArrayMesh
var _flower_mesh: ArrayMesh
var _bush_mesh: Mesh
var _active: bool = false
var _tuft_count: int = 0
var _flower_count: int = 0
var _bush_count: int = 0
var _map_w: int = 0
var _map_h: int = 0
var _cell_size: float = 1.0
var _night_mode: bool = false
var _has_config: bool = false

func _ready() -> void:
	_ensure_instances()

func _ensure_instances() -> void:
	if _tuft_instance != null and is_instance_valid(_tuft_instance):
		return
	_tuft_instance = MultiMeshInstance3D.new()
	_tuft_instance.name = "GrassTufts"
	_tuft_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tuft_instance.visible = false
	add_child(_tuft_instance)
	_flower_instance = MultiMeshInstance3D.new()
	_flower_instance.name = "Wildflowers"
	_flower_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flower_instance.visible = false
	add_child(_flower_instance)
	_bush_instance = MultiMeshInstance3D.new()
	_bush_instance.name = "Bushes"
	_bush_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bush_instance.visible = false
	add_child(_bush_instance)

## Configure la végétation (no-op si paramètres identiques).
## `heights` : tableau plat de hauteurs en cases ; `materials` : IDs de matière ;
## `water_level` : niveau d'eau en cases (-1 = aucune eau).
func configure(
	map_width: int,
	map_height: int,
	cell_size: float,
	heights: Array = [],
	materials: Array = [],
	water_level: float = -1.0,
	night_mode: bool = false,
	enabled: bool = true
) -> void:
	var next_w := maxi(0, map_width)
	var next_h := maxi(0, map_height)
	var next_cell := cell_size if cell_size > 0.0 else 1.0
	var next_water := water_level if water_level >= 0.0 else -1.0
	if _has_config and next_w == _map_w and next_h == _map_h \
			and is_equal_approx(next_cell, _cell_size) \
			and is_equal_approx(next_water, _water_level) \
			and night_mode == _night_mode and enabled == _last_enabled \
			and _arrays_equal(heights, _last_heights) \
			and _arrays_equal(materials, _last_materials):
		return
	_has_config = true
	_last_enabled = enabled
	_map_w = next_w
	_map_h = next_h
	_cell_size = next_cell
	_night_mode = night_mode
	_water_level = next_water
	_last_heights = heights.duplicate() if heights is Array else []
	_last_materials = materials.duplicate() if materials is Array else []
	if not enabled or next_w <= 0 or next_h <= 0:
		clear()
		return
	_rebuild(_last_heights, _last_materials)

func set_night_mode(on: bool) -> void:
	if _night_mode == on:
		return
	_night_mode = on
	if _has_config and _active:
		_apply_tint()

func is_active() -> bool:
	return _active

## Nombre total d'instances (touffes + fleurs + buissons).
func get_vegetation_count() -> int:
	return _tuft_count + _flower_count + _bush_count

func get_tuft_count() -> int:
	return _tuft_count

func get_flower_count() -> int:
	return _flower_count

func get_bush_count() -> int:
	return _bush_count

func get_tuft_multimesh() -> MultiMesh:
	if _tuft_instance == null:
		return null
	return _tuft_instance.multimesh

func get_flower_multimesh() -> MultiMesh:
	if _flower_instance == null:
		return null
	return _flower_instance.multimesh

func get_bush_multimesh() -> MultiMesh:
	if _bush_instance == null:
		return null
	return _bush_instance.multimesh

func get_material() -> ShaderMaterial:
	return _material

func get_vegetation_mesh_instance() -> MultiMeshInstance3D:
	return _tuft_instance

func clear() -> void:
	_active = false
	_tuft_count = 0
	_flower_count = 0
	_bush_count = 0
	if _tuft_instance != null and is_instance_valid(_tuft_instance):
		_tuft_instance.multimesh = null
		_tuft_instance.visible = false
	if _flower_instance != null and is_instance_valid(_flower_instance):
		_flower_instance.multimesh = null
		_flower_instance.visible = false
	if _bush_instance != null and is_instance_valid(_bush_instance):
		_bush_instance.multimesh = null
		_bush_instance.visible = false
	visible = false

## Mise à jour rapide de la nuit sans reconstruire.
func _apply_tint() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(
		"albedo_tint", NIGHT_TINT if _night_mode else Color.WHITE)

func _rebuild(heights: Array, materials: Array) -> void:
	_ensure_instances()
	var expected: int = _map_w * _map_h
	var has_materials := materials is Array and materials.size() == expected
	var tuft_transforms: Array = []
	var tuft_colors: Array = []
	var flower_transforms: Array = []
	var flower_colors: Array = []
	var bush_transforms: Array = []
	var bush_colors: Array = []
	for y in range(_map_h):
		for x in range(_map_w):
			var idx := y * _map_w + x
			var material := MATERIAL_GRASS
			if has_materials:
				material = int(materials[idx])
			if material != MATERIAL_GRASS:
				continue
			var cell_height := 0.0
			if heights is Array and heights.size() == expected:
				cell_height = float(heights[idx])
			var h := cell_height * _cell_size
			# Case immergée : pas de végétation dans l'eau.
			if _water_level >= 0.0 and cell_height < _water_level:
				continue
			var base := Vector3(
				(float(x) + 0.5) * _cell_size,
				h,
				(float(y) + 0.5) * _cell_size
			)
			if _hash01(x, y, 11) < TUFT_DENSITY and tuft_transforms.size() < MAX_TUFTS:
				var jitter := Vector3(
					(_hash01(x, y, 12) - 0.5) * _cell_size * 0.55,
					0.0,
					(_hash01(x, y, 13) - 0.5) * _cell_size * 0.55
				)
				var scale := 0.75 + _hash01(x, y, 14) * 0.6
				var basis := Basis(Vector3.UP, _hash01(x, y, 15) * TAU).scaled(
					Vector3(scale, scale, scale))
				tuft_transforms.append(Transform3D(basis, base + jitter))
				tuft_colors.append(TUFT_COLORS[int(_hash01(x, y, 16) * TUFT_COLORS.size()) % TUFT_COLORS.size()])
			if _hash01(x, y, 21) < FLOWER_DENSITY and flower_transforms.size() < MAX_FLOWERS:
				var fj := Vector3(
					(_hash01(x, y, 22) - 0.5) * _cell_size * 0.6,
					0.0,
					(_hash01(x, y, 23) - 0.5) * _cell_size * 0.6
				)
				var fscale := 0.75 + _hash01(x, y, 24) * 0.5
				var fbasis := Basis(Vector3.UP, _hash01(x, y, 25) * TAU).scaled(
					Vector3(fscale, fscale, fscale))
				flower_transforms.append(Transform3D(fbasis, base + fj + Vector3(0.0, 0.02, 0.0)))
				flower_colors.append(FLOWER_COLORS[int(_hash01(x, y, 26) * FLOWER_COLORS.size()) % FLOWER_COLORS.size()])
			if _hash01(x, y, 31) < BUSH_DENSITY and bush_transforms.size() < MAX_BUSHES:
				var bj := Vector3(
					(_hash01(x, y, 32) - 0.5) * _cell_size * 0.5,
					0.0,
					(_hash01(x, y, 33) - 0.5) * _cell_size * 0.5
				)
				var bscale := 0.8 + _hash01(x, y, 34) * 0.7
				var bradius := _cell_size * 0.30
				var bbasis := Basis(Vector3.UP, _hash01(x, y, 35) * TAU).scaled(
					Vector3(bscale, bscale * (0.8 + _hash01(x, y, 36) * 0.5), bscale))
				# Le buisson est posé au sol : la sphère est centrée à mi-hauteur.
				bush_transforms.append(Transform3D(
					bbasis, base + bj + Vector3(0.0, bradius * 0.85, 0.0)))
				bush_colors.append(BUSH_COLORS[int(_hash01(x, y, 37) * BUSH_COLORS.size()) % BUSH_COLORS.size()])
	_tuft_count = tuft_transforms.size()
	_flower_count = flower_transforms.size()
	_bush_count = bush_transforms.size()
	if _tuft_mesh == null:
		_tuft_mesh = _make_tuft_mesh(_cell_size)
	if _flower_mesh == null:
		_flower_mesh = _make_flower_mesh(_cell_size)
	if _bush_mesh == null:
		_bush_mesh = _make_bush_mesh(_cell_size)
	_apply_multimesh(_tuft_instance, tuft_transforms, tuft_colors, _tuft_mesh)
	_apply_multimesh(_flower_instance, flower_transforms, flower_colors, _flower_mesh)
	_apply_multimesh(_bush_instance, bush_transforms, bush_colors, _bush_mesh)
	_active = get_vegetation_count() > 0
	visible = _active
	if _active:
		_apply_tint()
	else:
		_tuft_instance.visible = false
		_flower_instance.visible = false
		_bush_instance.visible = false

func _apply_multimesh(
	instance: MultiMeshInstance3D,
	transforms: Array,
	colors: Array,
	mesh: Mesh
) -> void:
	if transforms.is_empty():
		instance.multimesh = null
		instance.visible = false
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	instance.multimesh = mm
	instance.material_override = _ensure_material()
	instance.visible = true
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ensure_material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("wind_strength", 0.05)
		_material.set_shader_parameter("wind_speed", 1.6)
	_apply_tint()
	return _material

## Touffe : trois quads croisés (volume), dégradé pied sombre → pointe claire.
func _make_tuft_mesh(cell: float) -> ArrayMesh:
	var width := cell * 0.32
	var height := cell * 0.85
	var top_gray := Color(1.0, 1.0, 1.0, 1.0)
	var bottom_gray := Color(0.44, 0.48, 0.38, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in range(3):
		var angle := float(plane) * PI / 3.0
		var right := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.5
		var p0 := -right
		var p1 := right
		var p2 := right + Vector3(0.0, height, 0.0)
		var p3 := -right + Vector3(0.0, height, 0.0)
		_add_quad(st, p0, p1, p2, p3, bottom_gray, top_gray)
	st.generate_normals()
	return st.commit()

## Fleur : petit quad croisé perché sur une tige courte.
func _make_flower_mesh(cell: float) -> ArrayMesh:
	var width := cell * 0.16
	var height := cell * 0.38
	var top_gray := Color(1.0, 1.0, 1.0, 1.0)
	var bottom_gray := Color(0.50, 0.56, 0.44, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in range(3):
		var angle := float(plane) * PI / 3.0
		var right := Vector3(cos(angle), 0.0, sin(angle)) * width * 0.5
		var p0 := -right
		var p1 := right
		var p2 := right + Vector3(0.0, height, 0.0)
		var p3 := -right + Vector3(0.0, height, 0.0)
		_add_quad(st, p0, p1, p2, p3, bottom_gray, top_gray)
	st.generate_normals()
	return st.commit()

## Buisson : petite sphère basse (volume rond) posée sur l'herbe.
func _make_bush_mesh(cell: float) -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = cell * 0.40
	sphere.height = cell * 0.75
	sphere.radial_segments = 10
	sphere.rings = 5
	return sphere

func _add_quad(
	st: SurfaceTool,
	p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
	bottom_color: Color, top_color: Color
) -> void:
	# Deux triangles, UV.y = 0 au pied / 1 à la pointe (vent).
	st.set_color(bottom_color)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_color(bottom_color)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(p1)
	st.set_color(top_color)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p2)
	st.set_color(bottom_color)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(p0)
	st.set_color(top_color)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p2)
	st.set_color(top_color)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(p3)

## Hash déterministe 0..1 (aucun RNG : stable entre deux constructions).
static func _hash01(x: int, y: int, salt: int) -> float:
	var n := (x * 374761393 + y * 668265263 + salt * 1442695041) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	n = n & 0x7fffffff
	return float(n % 100000) / 100000.0

static func _arrays_equal(a: Array, b: Array) -> bool:
	if not (a is Array) or not (b is Array):
		return false
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if typeof(a[i]) == TYPE_FLOAT or typeof(b[i]) == TYPE_FLOAT:
			if not is_equal_approx(float(a[i]), float(b[i])):
				return false
		elif a[i] != b[i]:
			return false
	return true

var _last_heights: Array = []
var _last_materials: Array = []
var _water_level: float = -1.0
var _last_enabled: bool = true
