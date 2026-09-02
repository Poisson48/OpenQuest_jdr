extends Node3D
class_name MapGround3D

## Sol 3D — MeshInstance3D (PlaneMesh) avec texture battlemap.

var _mesh_instance: MeshInstance3D

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

func configure(texture: Texture2D, map_width: int, map_height: int, cell_size: float) -> void:
	var w := float(map_width) * cell_size
	var h := float(map_height) * cell_size
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	plane.subdivide_width = map_width
	plane.subdivide_depth = map_height
	_mesh_instance.mesh = plane
	_mesh_instance.position = Vector3(w * 0.5, 0.0, h * 0.5)
	_mesh_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mesh_instance.material_override = mat
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func get_map_extent() -> Vector2:
	if _mesh_instance.mesh is PlaneMesh:
		return (_mesh_instance.mesh as PlaneMesh).size
	return Vector2.ZERO
