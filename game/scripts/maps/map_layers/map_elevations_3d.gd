extends Node3D
class_name MapElevations3D

## Plateformes surélevées 3D + overlays PNG pour battlemaps multi-niveaux.

var _nodes: Array = []

func configure(map_data: Dictionary, cell_size: float) -> void:
	for child in get_children():
		child.queue_free()
	_nodes.clear()

	var layers: Array = map_data.get("elevationLayers", [])
	if layers is not Array:
		return

	for layer_def in layers:
		if not layer_def is Dictionary:
			continue
		var path: String = str(layer_def.get("image", "")).strip_edges()
		if not path.is_empty():
			_add_image_overlay(layer_def, path, cell_size)
		elif layer_def.get("platform") is Dictionary:
			_add_platform_mesh(layer_def, cell_size)

func _add_image_overlay(layer_def: Dictionary, path: String, cell_size: float) -> void:
	var tex := MapData.load_background_texture({"backgroundImage": path})
	if tex == null:
		return
	var map_w: int = int(layer_def.get("mapWidth", 16))
	var map_h: int = int(layer_def.get("mapHeight", 12))
	if map_w <= 0:
		map_w = 16
	if map_h <= 0:
		map_h = 12
	var w := float(map_w) * cell_size
	var h := float(map_h) * cell_size
	var elev := float(layer_def.get("elevation", 0.15))
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = Vector3(w * 0.5, elev, h * 0.5)
	mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, float(layer_def.get("opacity", 0.92)))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	mesh.material_override = mat
	var off: Dictionary = layer_def.get("offset", {"x": 0, "y": 0})
	if off is Dictionary:
		mesh.position.x += float(off.get("x", 0)) * cell_size
		mesh.position.z += float(off.get("y", 0)) * cell_size
	add_child(mesh)
	_nodes.append(mesh)

func _add_platform_mesh(layer_def: Dictionary, cell_size: float) -> void:
	var plat: Dictionary = layer_def.get("platform", {})
	var px := float(plat.get("x", 0))
	var py := float(plat.get("y", 0))
	var pw := float(plat.get("w", 2))
	var ph := float(plat.get("h", 2))
	var elev := float(layer_def.get("elevation", 1.0)) * cell_size * 0.12
	var w := pw * cell_size
	var h := ph * cell_size
	var plane := PlaneMesh.new()
	plane.size = Vector2(w, h)
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = Vector3(
		px * cell_size + w * 0.5,
		elev,
		py * cell_size + h * 0.5
	)
	mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html(str(layer_def.get("tint", "#8a7a60")))
	mat.albedo_color.a = float(layer_def.get("opacity", 0.35))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.85
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
	_nodes.append(mesh)
