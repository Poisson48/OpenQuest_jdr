extends StaticBody3D
class_name MapToken3D

## Token — cylindre VTT, ou découpe dressée en mode diorama (DD2).

signal drag_finished(token_id: String, gx: float, gy: float)
signal selected(token_id: String)

var token_data: Dictionary = {}
var cell_size: float = 1.0
var snap_to_grid: bool = true
var readonly: bool = false
var party: Array = []
var selected_state: bool = false
var diorama_mode: bool = false

var _sprite: Sprite3D
var _mesh: MeshInstance3D
var _cutout: MeshInstance3D
var _shadow: MeshInstance3D
var _selection_ring: MeshInstance3D
var _dragging: bool = false
var _overlay_texture: Texture2D = null
var _overlay_height: float = 1.0

func setup(data: Dictionary, c_size: float, p_party: Array, p_readonly: bool, p_diorama: bool = false) -> void:
	token_data = data.duplicate(true)
	cell_size = c_size
	party = p_party
	readonly = p_readonly
	diorama_mode = p_diorama
	_build_visuals()
	_sync_position()

func _build_visuals() -> void:
	for child in get_children():
		child.queue_free()
	_sprite = null
	_mesh = null
	_cutout = null
	_shadow = null
	_selection_ring = null
	_overlay_texture = null
	_overlay_height = cell_size * 1.9

	if diorama_mode:
		_build_diorama_visuals()
	else:
		_build_vtt_visuals()

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# Hitbox large : le calque 2D est grand ; le raycast 3D reste un filet de secours.
	capsule.radius = cell_size * (0.55 if diorama_mode else 0.34)
	capsule.height = cell_size * (1.6 if diorama_mode else 0.6)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)

func _build_diorama_visuals() -> void:
	# Ombre 3D discrète au sol (le perso lui-même est un calque 2D overlay).
	_shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = cell_size * 0.26
	shadow_mesh.bottom_radius = cell_size * 0.26
	shadow_mesh.height = 0.018
	_shadow.mesh = shadow_mesh
	_shadow.position = Vector3(0, 0.01, 0)
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.4)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.render_priority = -40
	_shadow.material_override = shadow_mat
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	# Texture pour le calque 2D (pas de Sprite3D : sinon sous le fond illustré).
	_overlay_texture = _make_cutout_texture()
	_overlay_height = cell_size * 1.9
	# Pas d'anneau de sélection 3D : il traverse le calque et fait une barre parasite.

func uses_overlay_layer() -> bool:
	return diorama_mode and _overlay_texture != null

func get_overlay_texture() -> Texture2D:
	return _overlay_texture

func get_overlay_height() -> float:
	return _overlay_height

func get_overlay_anchor_world() -> Vector3:
	# Pied du perso (ombre au sol).
	return global_position + Vector3(0.0, 0.02, 0.0)

func _build_vtt_visuals() -> void:
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
	var portrait := _make_portrait_texture()
	_sprite.texture = portrait
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var portrait_px: int = maxi(1, portrait.get_width()) if portrait != null else 128
	_sprite.pixel_size = (cell_size * 0.8) / float(portrait_px)
	_sprite.position.y = cyl.height + cell_size * 0.08
	_sprite.modulate = Color(1, 1, 1, 0.95)
	add_child(_sprite)

	_add_selection_ring(0.04)

func _add_selection_ring(y: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = cell_size * 0.38
	ring.outer_radius = cell_size * 0.42
	ring.rings = 16
	ring.ring_segments = 24
	_selection_ring = MeshInstance3D.new()
	_selection_ring.mesh = ring
	_selection_ring.position.y = y
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

## Disque au sol discret (pas d'émission = pas de barre jaune sur le perso).
func _add_selection_disc() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = cell_size * 0.36
	disc.bottom_radius = cell_size * 0.36
	disc.height = 0.02
	_selection_ring = MeshInstance3D.new()
	_selection_ring.mesh = disc
	_selection_ring.position.y = 0.015
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.95, 0.78, 0.25, 0.35)
	ring_mat.emission_enabled = false
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.render_priority = -20
	_selection_ring.material_override = ring_mat
	_selection_ring.visible = false
	add_child(_selection_ring)

func set_selected(on: bool) -> void:
	selected_state = on
	if _selection_ring:
		_selection_ring.visible = on
	if diorama_mode:
		position.y = cell_size * 0.03 if on else 0.0
		return
	if _mesh and _mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.emission_enabled = on
		mat.emission = _token_color().lightened(0.4) if on else Color.BLACK
		mat.emission_energy_multiplier = 0.6 if on else 0.0
		position.y = cell_size * 0.12 if on else 0.0

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
		position.y = cell_size * (0.06 if diorama_mode else 0.12)

func is_dragging() -> bool:
	return _dragging

func _sync_position() -> void:
	var gx := float(token_data.get("x", 0))
	var gy := float(token_data.get("y", 0))
	position = _grid_to_world(gx, gy)
	if selected_state:
		position.y = cell_size * (0.06 if diorama_mode else 0.12)

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

func _resolve_image_path() -> String:
	var image_path := str(token_data.get("image", "")).strip_edges()
	if not image_path.is_empty():
		return image_path
	# Portrait porté par la fiche perso.
	var mid := str(token_data.get("memberId", ""))
	if mid.is_empty():
		return ""
	for m_variant in party:
		var m: Dictionary = m_variant
		if str(m.get("id", "")) != mid:
			continue
		var p := str(m.get("portrait", m.get("image", ""))).strip_edges()
		return p
	return ""

func _make_cutout_texture() -> Texture2D:
	var image_path := _resolve_image_path()
	if not image_path.is_empty():
		var cutout := MapData.load_token_cutout(image_path, 256)
		if cutout != null:
			return cutout
	return _make_portrait_texture()

func _make_portrait_texture() -> Texture2D:
	var image_path := _resolve_image_path()
	if not image_path.is_empty():
		var portrait := MapData.load_token_portrait(image_path, _token_color().darkened(0.55))
		if portrait != null:
			return portrait
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := _token_color()
	for y in range(sz):
		for x in range(sz):
			var dx := float(x - sz / 2) / float(sz / 2)
			var dy := float(y - sz / 2) / float(sz / 2)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col.lightened(0.08))
	for y in range(sz):
		for x in range(sz):
			var dx := float(x - sz / 2) / float(sz / 2)
			var dy := float(y - sz / 2) / float(sz / 2)
			var d := sqrt(dx * dx + dy * dy)
			if d > 0.88 and d <= 1.0:
				img.set_pixel(x, y, Color(0.15, 0.12, 0.1, 1.0))
	# Initiale
	return ImageTexture.create_from_image(img)
