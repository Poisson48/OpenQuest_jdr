extends Node3D
class_name MapProps3D

## Décors posés sur la carte : bâtiments, charrettes, mobilier, végétation.
##
## Deux façons de poser une image :
##   • **à plat** (`standing = false`) — sols, chemins, ou carte illustrée vue
##     de dessus (sinon un billboard dressé serait invisible en tranche) ;
##   • **dressée** (`standing = true`) — bâtiments face caméra (diorama incliné
##     ou VTT avec billboard Y).
##
## `preferFlatProps` (style rendu / fond illustré top-down) force le rendu à plat
## même si l'élément est marqué dressé — pour rester visible sous caméra -Y.

const MapAssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")

var _cell_size: float = 1.0
var _nodes: Dictionary = {}
var _style_cfg: Dictionary = {}
var _map_height: float = 12.0
var _atmosphere: Color = Color(0.10, 0.10, 0.14)
var _prefer_flat: bool = false
## id calque → rang d'empilement (liste des calques, bas → haut).
var _layer_rank: Dictionary = {}

func configure(props: Array, cell_size: float, map_data: Dictionary = {}) -> void:
	_cell_size = cell_size
	_style_cfg = MapRenderStyleScript.config(map_data) if not map_data.is_empty() else MapRenderStyleScript.CONFIGS[MapRenderStyleScript.DIORAMA].duplicate(true)
	_map_height = float(map_data.get("height", 12)) if not map_data.is_empty() else 12.0
	_atmosphere = MapRenderStyleScript.atmosphere_color(map_data) if not map_data.is_empty() else Color(0.10, 0.10, 0.14)
	_prefer_flat = bool(_style_cfg.get("preferFlatProps", false))
	_layer_rank.clear()
	var layers: Array = map_data.get("layers", []) if not map_data.is_empty() else []
	for i in range(layers.size()):
		if layers[i] is Dictionary:
			_layer_rank[int((layers[i] as Dictionary).get("id", i))] = i
	for child in get_children():
		remove_child(child)
		child.free()
	_nodes.clear()
	for prop_variant in props:
		if not prop_variant is Dictionary:
			continue
		var prop: Dictionary = prop_variant
		if bool(prop.get("hidden", false)):
			continue
		var node := _build_prop(prop)
		if node != null:
			add_child(node)
			_nodes[str(prop.get("id", ""))] = node

func _build_prop(prop: Dictionary) -> Node3D:
	var texture := MapAssetLibraryScript.load_texture(str(prop.get("asset", "")))
	if texture == null:
		return null
	var display: Dictionary = prop.get("display", {}) if prop.get("display") is Dictionary else {}
	var scale_factor := maxf(0.05, float(display.get("scale", 1.0)))
	var width := maxf(0.05, float(prop.get("w", 1.0))) * _cell_size * scale_factor
	var height := maxf(0.05, float(prop.get("h", 1.0))) * _cell_size * scale_factor
	var standing := bool(prop.get("standing", true)) and not _prefer_flat
	var layer := int(prop.get("layer", 1))
	var layer_rank := int(_layer_rank.get(layer, layer))
	var gy := float(prop.get("y", 0.0))
	var depth01 := MapRenderStyleScript.depth_ratio(gy, _map_height)
	var parallax := MapRenderStyleScript.parallax_offset(layer_rank, _style_cfg)

	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	mesh.mesh = quad
	mesh.material_override = _make_material(texture, prop, display, depth01, layer_rank)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var elevation := float(prop.get("elevation", 0.0)) * _cell_size
	var root := Node3D.new()
	# Parallaxe : les calques d'arrière-plan reculent un peu en Z caméra
	# (ici : légèrement vers -Y monde pour s'éloigner sous une caméra inclinée).
	root.position = Vector3(
		float(prop.get("x", 0.0)) * _cell_size + _cell_size * 0.5,
		elevation,
		gy * _cell_size + _cell_size * 0.5 + parallax * _cell_size
	)
	root.set_meta("parallax", parallax)
	root.set_meta("flat", not standing)

	if standing:
		# Pied sur la case : la base de l'image repose au sol.
		mesh.position.y = height * 0.5
		root.rotation_degrees.y = -float(display.get("rotation", 0.0))
		var billboard := bool(prop.get("billboard", true))
		if billboard:
			var mat: StandardMaterial3D = mesh.material_override
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.billboard_keep_scale = true
	else:
		# À plat sur XZ, légèrement au-dessus du sol pour éviter le z-fight.
		mesh.rotation_degrees = Vector3(-90.0, -float(display.get("rotation", 0.0)), 0.0)
		mesh.position.y = 0.04 + float(layer_rank) * 0.008 + float(prop.get("zOrder", 0.0)) * 0.2

	root.add_child(mesh)
	return root

func _make_material(texture: Texture2D, prop: Dictionary, display: Dictionary, depth01: float, layer_rank: int = -1) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	# Pré-passe profondeur : les découpes alpha se trient correctement quand
	# elles se chevauchent (bug visible dès qu'on pose un village).
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.alpha_scissor_threshold = 0.02
	var rank := layer_rank if layer_rank >= 0 else int(prop.get("layer", 1))
	mat.render_priority = MapRenderStyleScript.render_priority(rank, depth01)

	var tint_hex := str(display.get("tint", "")).strip_edges()
	var tint := Color.html(tint_hex) if not tint_hex.is_empty() else Color.WHITE
	var brightness := float(display.get("brightness", 0.0))
	if brightness > 0.0:
		tint = tint.lightened(clampf(brightness, 0.0, 1.0))
	elif brightness < 0.0:
		tint = tint.darkened(clampf(-brightness, 0.0, 1.0))
	tint.a = clampf(float(display.get("opacity", 1.0)), 0.0, 1.0)
	# Fondu atmosphérique du lointain (diorama).
	tint = MapRenderStyleScript.depth_tint(tint, depth01, _atmosphere, _style_cfg)
	mat.albedo_color = tint

	var force_lit := bool(prop.get("lit", false))
	var style_lit := bool(_style_cfg.get("litProps", false))
	if force_lit or style_lit:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 0.9
	else:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if bool(display.get("mirrorH", false)):
		mat.uv1_scale.x = -1.0
		mat.uv1_offset.x = 1.0
	if bool(display.get("mirrorV", false)):
		mat.uv1_scale.y = -1.0
		mat.uv1_offset.y = 1.0
	return mat

## Repositionne un décor sans reconstruire la scène (glisser en cours).
func set_prop_position(prop_id: String, gx: float, gy: float) -> void:
	if not _nodes.has(prop_id):
		return
	var node: Node3D = _nodes[prop_id]
	var parallax := float(node.get_meta("parallax", 0.0)) if node.has_meta("parallax") else 0.0
	node.position.x = gx * _cell_size + _cell_size * 0.5
	node.position.z = gy * _cell_size + _cell_size * 0.5 + parallax * _cell_size

func has_prop(prop_id: String) -> bool:
	return _nodes.has(prop_id)
