extends Node3D
class_name MapBackdrop3D

## Fond de plateau derrière la carte 2.5D (mode `terrain3d` uniquement).
##
## La jupe de falaise donne un « îlot » à la carte ; ce grand plan horizontal
## posé **sous** la jupe évite le vide noir autour. Il ne porte aucune texture :
## un `ShaderMaterial` procédural (`render_mode unshaded`) peint un dégradé
## radial — centre brun-terreux sombre → bleu-gris froid → bord presque noir —
## avec un grain et des bandes très douces. Pas d'ombre portée, pas de collision,
## `render_priority` très bas. La nuit, une teinte froide assombrit le fond.
##
## Dimensions : plan de `max(width, height) * cell_size * SIZE_FACTOR` de côté
## (carré), centré sur la carte, à
## `y = -(CLIFF_DEPTH_CELLS + Y_GAP_CELLS) * cell_size` (sous la jupe de
## falaise). Aucun fond en mode `illustrated` (le moteur retire le calque).

## Doit rester cohérent avec `MapGround3D.CLIFF_DEPTH_CELLS`.
const CLIFF_DEPTH_CELLS := 2.5
## Marge entre le bas de la jupe et le fond, en cases.
const Y_GAP_CELLS := 0.5
## Le plan fait `max(width, height) * cell_size * SIZE_FACTOR` de côté.
const SIZE_FACTOR := 4.0

## Couleurs du dégradé (sRGB) : centre terreux, milieu bleu-gris, bord noir.
const CENTER_COLOR := Color(0.145, 0.125, 0.110)
const MID_COLOR := Color(0.085, 0.100, 0.130)
const EDGE_COLOR := Color(0.012, 0.013, 0.020)
## Teinte de nuit (assombrit et refroidit le fond).
const NIGHT_TINT := Color(0.30, 0.34, 0.46)
## Grain et bandes très douces (désactivés : le fond doit rester lisse).
const GRAIN_STRENGTH := 0.0
const BAND_STRENGTH := 0.0

## Shader procédural inline (aucun fichier shader externe demandé).
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 center_color : source_color = vec4(0.145, 0.125, 0.110, 1.0);
uniform vec4 mid_color : source_color = vec4(0.085, 0.100, 0.130, 1.0);
uniform vec4 edge_color : source_color = vec4(0.012, 0.013, 0.020, 1.0);
uniform vec4 night_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float grain_strength : hint_range(0.0, 0.2) = 0.035;
uniform float band_strength : hint_range(0.0, 0.2) = 0.02;

float backdrop_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 d = uv - vec2(0.5);
	float radius = clamp(length(d) * 2.0, 0.0, 1.0);
	vec3 col = mix(center_color.rgb, mid_color.rgb, smoothstep(0.0, 0.42, radius));
	col = mix(col, edge_color.rgb, smoothstep(0.42, 1.0, radius));
	// Grain doux (pas de texture externe) + bandes très douces.
	float grain = backdrop_hash(floor(uv * 512.0)) - 0.5;
	col += grain * grain_strength * (1.0 - radius * 0.6);
	float bands = sin((uv.x + uv.y) * 18.0 + sin(uv.x * 7.0) * 2.0) * 0.5 + 0.5;
	col += (bands - 0.5) * band_strength;
	ALBEDO = max(col, vec3(0.0)) * night_tint.rgb;
}
"""

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _shader: Shader
var _active: bool = false
var _map_w: int = 0
var _map_h: int = 0
var _cell_size: float = 1.0
var _night_mode: bool = false
var _has_config: bool = false
var _size_world: float = 0.0
## Palette optionnelle (preset lumineux type Tiny Glade) : centre/milieu/bord.
var _palette: Dictionary = {}

func _ready() -> void:
	_ensure_mesh_instance()

func _ensure_mesh_instance() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BackdropPlane"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.visible = false
	add_child(_mesh_instance)

## Configure le fond. Aucun fond si dimensions invalides (désactivé).
## `palette` (optionnelle) : {"center": Color, "mid": Color, "edge": Color} pour
## un preset lumineux (prairie pastel) ; vide = palette sombre historique.
## No-op si paramètres identiques (le refresh ne reconstruit pas inutilement).
func configure(
	map_width: int,
	map_height: int,
	cell_size: float,
	night_mode: bool = false,
	palette: Dictionary = {}
) -> void:
	var next_w := maxi(0, map_width)
	var next_h := maxi(0, map_height)
	var next_cell := cell_size if cell_size > 0.0 else 1.0
	var next_palette := palette.duplicate() if palette is Dictionary else {}
	if _has_config \
			and next_w == _map_w and next_h == _map_h \
			and is_equal_approx(next_cell, _cell_size) \
			and night_mode == _night_mode \
			and next_palette == _palette:
		return
	_map_w = next_w
	_map_h = next_h
	_cell_size = next_cell
	_night_mode = night_mode
	_palette = next_palette
	_has_config = true
	_rebuild()

## Change la palette du fond à chaud (rebuild si différente).
func set_palette(palette: Dictionary) -> void:
	var next := palette.duplicate() if palette is Dictionary else {}
	if next == _palette:
		return
	_palette = next
	if _has_config:
		_rebuild()

func get_palette() -> Dictionary:
	return _palette.duplicate()

func set_night_mode(on: bool) -> void:
	if _night_mode == on:
		return
	_night_mode = on
	if _has_config:
		_rebuild()

func is_active() -> bool:
	return _active

## Retire le fond (mode illustré).
func clear() -> void:
	_active = false
	_has_config = false
	_size_world = 0.0
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		_mesh_instance.mesh = null
		_mesh_instance.visible = false
	visible = false

## Hauteur monde du plan (sous la jupe de falaise).
func get_backdrop_y() -> float:
	return -(CLIFF_DEPTH_CELLS + Y_GAP_CELLS) * _cell_size

## Côté monde du plan carré.
func get_backdrop_size() -> float:
	return _size_world

func get_material() -> ShaderMaterial:
	return _material

func get_mesh_instance() -> MeshInstance3D:
	return _mesh_instance

## État des derniers paramètres.
func get_map_size() -> Vector2i:
	return Vector2i(_map_w, _map_h)

func get_night_mode() -> bool:
	return _night_mode

func _rebuild() -> void:
	_ensure_mesh_instance()
	if _map_w <= 0 or _map_h <= 0:
		clear()
		return
	var map_world := float(_map_w) * _cell_size
	var map_h_world := float(_map_h) * _cell_size
	# Carré assez large pour déborder de beaucoup autour de la jupe.
	_size_world = maxf(map_world, map_h_world) * SIZE_FACTOR
	var quad := QuadMesh.new()
	quad.size = Vector2(_size_world, _size_world)
	_mesh_instance.mesh = quad
	_mesh_instance.position = Vector3(
		map_world * 0.5,
		get_backdrop_y(),
		map_h_world * 0.5
	)
	# QuadMesh est dans le plan XY : rotation -90° pour le coucher sur XZ.
	_mesh_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_mesh_instance.material_override = _build_material()
	_mesh_instance.visible = true
	visible = true
	_active = true

func _build_material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = _shader
	_material.set_shader_parameter("center_color", _palette_color("center", CENTER_COLOR))
	_material.set_shader_parameter("mid_color", _palette_color("mid", MID_COLOR))
	_material.set_shader_parameter("edge_color", _palette_color("edge", EDGE_COLOR))
	_material.set_shader_parameter("night_tint", NIGHT_TINT if _night_mode else Color.WHITE)
	_material.set_shader_parameter("grain_strength", GRAIN_STRENGTH)
	_material.set_shader_parameter("band_strength", BAND_STRENGTH)
	# Très bas : le fond passe avant tout le reste de la carte.
	_material.render_priority = -120
	return _material

func _palette_color(key: String, fallback: Color) -> Color:
	var value = _palette.get(key, null)
	return value if value is Color else fallback
