extends StaticBody3D
class_name MapToken3D

## Token 3D — cylindre + Sprite3D portrait, ombres réelles, drag par raycast.

signal drag_finished(token_id: String, gx: float, gy: float)
signal selected(token_id: String)

var token_data: Dictionary = {}
var cell_size: float = 1.0
var snap_to_grid: bool = true
var readonly: bool = false
var party: Array = []
var selected_state: bool = false

var _sprite: Sprite3D
var _mesh: MeshInstance3D
var _selection_ring: MeshInstance3D
var _dragging: bool = false

func setup(data: Dictionary, c_size: float, p_party: Array, p_readonly: bool) -> void:
	token_data = data.duplicate(true)
	cell_size = c_size
	party = p_party
	readonly = p_readonly
	_build_visuals()
	_sync_position()

func _build_visuals() -> void:
	for child in get_children():
		child.queue_free()

	var cyl := CylinderMesh.new()
	cyl.top_radius = cell_size * 0.32
	cyl.bottom_radius = cell_size * 0.36
	cyl.height = cell_size * 0.55
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cyl
	_mesh.position.y = cyl.height * 0.5
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = _token_color()
	body_mat.roughness = 0.55
	body_mat.metallic = 0.15
	_mesh.material_override = body_mat
	add_child(_mesh)

	_sprite = Sprite3D.new()
	_sprite.texture = _make_portrait_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.pixel_size = cell_size * 0.0045
	_sprite.position.y = cyl.height + cell_size * 0.08
	_sprite.modulate = Color(1, 1, 1, 0.95)
	add_child(_sprite)

	var ring := TorusMesh.new()
	ring.inner_radius = cell_size * 0.38
	ring.outer_radius = cell_size * 0.42
	ring.rings = 16
	ring.ring_segments = 24
	_selection_ring = MeshInstance3D.new()
	_selection_ring.mesh = ring
	_selection_ring.position.y = 0.04
	_selection_ring.rotation_degrees = Vector3(90, 0, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.88, 0.3, 0.85)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.85, 0.2)
	ring_mat.emission_energy_multiplier = 1.2
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring.material_override = ring_mat
	_selection_ring.visible = false
	add_child(_selection_ring)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = cell_size * 0.34
	capsule.height = cell_size * 0.6
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)

func set_selected(on: bool) -> void:
	selected_state = on
	if _selection_ring:
		_selection_ring.visible = on
	if _mesh and _mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.emission_enabled = on
		mat.emission = _token_color().lightened(0.4) if on else Color.BLACK
		mat.emission_energy_multiplier = 0.6 if on else 0.0
		if on:
			position.y = cell_size * 0.12
		else:
			position.y = 0.0

func get_token_id() -> String:
	return str(token_data.get("id", ""))

func begin_drag() -> void:
	if readonly:
		return
	_dragging = true
	selected.emit(get_token_id())

func end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_commit_position()

func update_drag_world(world_pos: Vector3) -> void:
	if not _dragging:
		return
	position.x = world_pos.x
	position.z = world_pos.z
	if selected_state:
		position.y = cell_size * 0.12

func is_dragging() -> bool:
	return _dragging

func _sync_position() -> void:
	var gx := float(token_data.get("x", 0))
	var gy := float(token_data.get("y", 0))
	position = _grid_to_world(gx, gy)
	if selected_state:
		position.y = cell_size * 0.12

func _grid_to_world(gx: float, gy: float) -> Vector3:
	return Vector3(gx * cell_size + cell_size * 0.5, 0.0, gy * cell_size + cell_size * 0.5)

func _commit_position() -> void:
	var gx := (position.x - cell_size * 0.5) / cell_size
	var gy := (position.z - cell_size * 0.5) / cell_size
	if snap_to_grid:
		gx = roundf(gx)
		gy = roundf(gy)
	token_data["x"] = gx
	token_data["y"] = gy
	_sync_position()
	drag_finished.emit(get_token_id(), gx, gy)

func _token_color() -> Color:
	if token_data.get("kind") == "member":
		return MapData.get_member_color(str(token_data.get("memberId", "")), party)
	return Color(0.35, 0.28, 0.2)

func _token_icon() -> String:
	if token_data.get("kind") == "member":
		var mid := str(token_data.get("memberId", ""))
		for m in party:
			if m.get("id") == mid:
				var name: String = str(m.get("name", "?"))
				return name.substr(0, 1).to_upper()
		return "?"
	var marker: String = str(token_data.get("markerType", ""))
	if not marker.is_empty() and MapData.MARKERS.has(marker):
		return MapData.MARKERS[marker]
	return "●"

func _make_portrait_texture() -> Texture2D:
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := _token_color()
	# Disque portrait
	for y in range(sz):
		for x in range(sz):
			var dx := float(x - sz / 2) / float(sz / 2)
			var dy := float(y - sz / 2) / float(sz / 2)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col.lightened(0.08))
	# Bordure
	for y in range(sz):
		for x in range(sz):
			var dx := float(x - sz / 2) / float(sz / 2)
			var dy := float(y - sz / 2) / float(sz / 2)
			var d := sqrt(dx * dx + dy * dy)
			if d > 0.88 and d <= 1.0:
				img.set_pixel(x, y, Color(0.15, 0.12, 0.1, 1.0))
	return ImageTexture.create_from_image(img)
