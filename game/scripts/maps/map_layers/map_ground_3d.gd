extends Node3D
class_name MapGround3D

## Sol 3D texturé. Quad XZ avec UV explicites (évite le PlaneMesh qui
## disparaît en caméra ortho vue de dessus).

var _mesh_instance: MeshInstance3D
var _extent: Vector2 = Vector2.ZERO

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

func configure(texture: Texture2D, map_width: int, map_height: int, cell_size: float, unshaded: bool = false) -> void:
	var w := float(map_width) * cell_size
	var h := float(map_height) * cell_size
	_extent = Vector2(w, h)
	_mesh_instance.mesh = _make_ground_quad(w, h)
	_mesh_instance.position = Vector3.ZERO
	_mesh_instance.rotation_degrees = Vector3.ZERO

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_instance.material_override = mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if unshaded else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## Quad sur le plan XZ, normale +Y.
## UV : (0,0) = coin monde (0,0) = coin haut-gauche de l'illustration
## quand la caméra ortho regarde vers -Y (écran : +X à droite, -Z en haut).
## Donc V croît avec +Z (vers le bas de l'écran) = bas de l'image.
func _make_ground_quad(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 0---1
	# | / |
	# 2---3   (vue depuis +Y ; 0 = (0,0,0), 3 = (w,0,h))
	var verts := [
		Vector3(0, 0, 0), Vector3(w, 0, 0),
		Vector3(0, 0, h), Vector3(w, 0, h),
	]
	# Image : U→droite, V→bas. Monde : +X→droite écran, +Z→bas écran.
	var uvs := [
		Vector2(0, 0), Vector2(1, 0),
		Vector2(0, 1), Vector2(1, 1),
	]
	var indices := [0, 1, 2, 1, 3, 2]
	for i in indices:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	# Dos (normale -Y) pour CULL_DISABLED / éclairage inverse.
	var back := [0, 2, 1, 1, 2, 3]
	for i in back:
		st.set_normal(Vector3.DOWN)
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	return st.commit()

func get_map_extent() -> Vector2:
	return _extent
