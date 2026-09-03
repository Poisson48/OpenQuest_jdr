extends Node3D
class_name MapWalls3D

## Murs 3D — volumes pleins projetant de vraies ombres sur la battlemap.
## Un mur est décrit en coordonnées grille : centre (x, y), longueur `w`,
## épaisseur `h`, hauteur `height` et angle `display.rotation` en degrés.

var _cell_size: float = 1.0

func configure(walls: Array, cell_size: float) -> void:
	_cell_size = cell_size
	for child in get_children():
		child.queue_free()
	for wall_variant in walls:
		if not wall_variant is Dictionary:
			continue
		var wall: Dictionary = wall_variant
		if bool(wall.get("hidden", false)):
			continue
		_add_wall(wall)

func _add_wall(wall: Dictionary) -> void:
	var length := maxf(0.2, float(wall.get("w", 1.0))) * _cell_size
	var thickness := maxf(0.05, float(wall.get("h", 0.25))) * _cell_size
	var height := maxf(0.1, float(wall.get("height", 1.4))) * _cell_size
	var box := BoxMesh.new()
	box.size = Vector3(length, height, thickness)

	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position = Vector3(
		float(wall.get("x", 0.0)) * _cell_size + _cell_size * 0.5,
		height * 0.5,
		float(wall.get("y", 0.0)) * _cell_size + _cell_size * 0.5
	)
	var display: Dictionary = wall.get("display", {}) if wall.get("display") is Dictionary else {}
	mesh.rotation_degrees = Vector3(0.0, -float(display.get("rotation", 0.0)), 0.0)

	var mat := StandardMaterial3D.new()
	var tint := str(wall.get("color", "#4a423a"))
	mat.albedo_color = Color.html(tint) if not tint.is_empty() else Color(0.29, 0.26, 0.23)
	var opacity := float(display.get("opacity", 1.0))
	if opacity < 1.0:
		mat.albedo_color.a = opacity
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.88
	mat.metallic = 0.02
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
