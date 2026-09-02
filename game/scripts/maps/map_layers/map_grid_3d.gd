extends Node3D
class_name MapGrid3D

## Grille 3D — lignes au-dessus du sol (mode top-down).

var _mesh_instance: MeshInstance3D

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

func configure(cfg: Dictionary, width: int, height: int, cell_size: float) -> void:
	if not bool(cfg.get("enabled", true)):
		_mesh_instance.mesh = null
		return
	var color: Color = Color.html(str(cfg.get("color", "#ffffff")))
	color.a = float(cfg.get("opacity", 0.14))
	var w := float(width) * cell_size
	var h := float(height) * cell_size
	var y := 0.03
	var lines := PackedVector3Array()
	for x in range(width + 1):
		var lx := float(x) * cell_size
		lines.append(Vector3(lx, y, 0.0))
		lines.append(Vector3(lx, y, h))
	for y_idx in range(height + 1):
		var ly := float(y_idx) * cell_size
		lines.append(Vector3(0.0, y, ly))
		lines.append(Vector3(w, y, ly))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = mat
