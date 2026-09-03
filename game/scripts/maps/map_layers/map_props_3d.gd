extends Node3D
class_name MapProps3D

## Décors posés sur la carte : bâtiments, charrettes, mobilier, végétation.
##
## Deux façons de poser une image :
##   • **à plat** (`standing = false`) — sols, chemins, tapis, ombres portées ;
##     l'image épouse le terrain.
##   • **dressée** (`standing = true`) — bâtiments, arbres, charrettes ; l'image
##     se tient debout et fait toujours face à la caméra, comme un décor de
##     théâtre. C'est ce qui donne du relief à une carte illustrée.
##
## Le rendu est **non éclairé** par défaut : l'illustration porte déjà ses
## propres ombres, un éclairage 3D par-dessus la salirait.

const MapAssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

var _cell_size: float = 1.0
var _nodes: Dictionary = {}

func configure(props: Array, cell_size: float) -> void:
	_cell_size = cell_size
	for child in get_children():
		child.queue_free()
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
	var standing := bool(prop.get("standing", true))

	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	mesh.mesh = quad
	mesh.material_override = _make_material(texture, prop, display)

	var elevation := float(prop.get("elevation", 0.0)) * _cell_size
	var root := Node3D.new()
	root.position = Vector3(
		float(prop.get("x", 0.0)) * _cell_size + _cell_size * 0.5,
		elevation,
		float(prop.get("y", 0.0)) * _cell_size + _cell_size * 0.5
	)

	if standing:
		# Le pied de l'image repose sur la case, le reste s'élève : une maison
		# posée en (10, 8) a sa base en (10, 8), pas son centre.
		mesh.position.y = height * 0.5
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.rotation_degrees.y = -float(display.get("rotation", 0.0))
		var billboard := bool(prop.get("billboard", true))
		if billboard:
			var mat: StandardMaterial3D = mesh.material_override
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			mat.billboard_keep_scale = true
	else:
		mesh.rotation_degrees = Vector3(-90.0, -float(display.get("rotation", 0.0)), 0.0)
		# Un décalage minuscule par calque évite le z-fighting avec le sol.
		mesh.position.y = 0.01 + float(int(prop.get("layer", 1))) * 0.004 + float(prop.get("zOrder", 0.0)) * 0.2

	root.add_child(mesh)
	return root

func _make_material(texture: Texture2D, prop: Dictionary, display: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.alpha_scissor_threshold = 0.02

	# Teinte, opacité et luminosité, comme pour les autres éléments.
	var tint_hex := str(display.get("tint", "")).strip_edges()
	var tint := Color.html(tint_hex) if not tint_hex.is_empty() else Color.WHITE
	var brightness := float(display.get("brightness", 0.0))
	if brightness > 0.0:
		tint = tint.lightened(clampf(brightness, 0.0, 1.0))
	elif brightness < 0.0:
		tint = tint.darkened(clampf(-brightness, 0.0, 1.0))
	tint.a = clampf(float(display.get("opacity", 1.0)), 0.0, 1.0)
	mat.albedo_color = tint

	if bool(prop.get("lit", false)):
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 0.9
	else:
		# L'illustration porte déjà sa lumière : on la restitue telle quelle.
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
	node.position.x = gx * _cell_size + _cell_size * 0.5
	node.position.z = gy * _cell_size + _cell_size * 0.5

func has_prop(prop_id: String) -> bool:
	return _nodes.has(prop_id)
