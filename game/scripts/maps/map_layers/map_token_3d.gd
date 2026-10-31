extends StaticBody3D
class_name MapToken3D

## Token — cylindre VTT, découpe dressée (diorama/DD2), ou **pion** façon
## pièce d'échecs sur le plateau (vue table) : révolution LatheMesh teintée
## à la couleur du joueur, qu'on pose / déplace comme une figurine.
##
## **Relief (M6)** : le pied (racine) est posé à
## `terrain_height_at(x, y) * cell_size` pour ne pas flotter sur une butte. Les
## découpes 2D **ne sont pas inclinées** (elles restent verticales) : seule la
## hauteur suit le sol.

signal drag_finished(token_id: String, gx: float, gy: float)
signal selected(token_id: String)

const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")

## Seuil sous lequel une case de relief est considérée comme plate.
const TERRAIN_RELIEF_EPSILON := 0.001

var token_data: Dictionary = {}
var cell_size: float = 1.0
var snap_to_grid: bool = true
var readonly: bool = false
var party: Array = []
var selected_state: bool = false
var diorama_mode: bool = false
var pawn_mode: bool = false
## Figurine 3D (GLB) utilisée en mode diorama/2.5D à la place de la découpe 2D.
var figurine_asset: String = ""
var _fig_aabb_acc := AABB()
var _fig_aabb_has := false

var _sprite: Sprite3D
var _mesh: MeshInstance3D
var _cutout: MeshInstance3D
var _shadow: MeshInstance3D
var _selection_ring: MeshInstance3D
var _dragging: bool = false
var _fig_root: Node3D
var _fig_base_position := Vector3.ZERO
var _fig_base_rotation_y := 0.0
var _idle_time: float = 0.0
var _idle_phase: float = 0.0
var _overlay_texture: Texture2D = null
var _overlay_height: float = 1.0
## Relief : hauteurs par case (tableau plat, convention grille centrée case).
var _terrain_heights: Array = []
var _terrain_w: int = 0
var _terrain_h: int = 0
var _terrain_relief: bool = false

func setup(
	data: Dictionary,
	c_size: float,
	p_party: Array,
	p_readonly: bool,
	p_diorama: bool = false,
	terrain_heights: Array = [],
	map_size: Vector2i = Vector2i.ZERO
) -> void:
	token_data = data.duplicate(true)
	cell_size = c_size
	party = p_party
	readonly = p_readonly
	diorama_mode = p_diorama
	set_terrain_heights(terrain_heights, map_size)
	_build_visuals()
	_sync_position()

## Met à jour le relief et repose le token sans reconstruire son visuel
## (pinceau de relief de l'éditeur : `ComplexMapEngine3D.refresh_terrain`).
func set_terrain_heights(terrain_heights: Array, map_size: Vector2i = Vector2i.ZERO) -> void:
	_terrain_heights = terrain_heights if terrain_heights is Array else []
	if map_size.x > 0:
		_terrain_w = map_size.x
	if map_size.y > 0:
		_terrain_h = map_size.y
	_terrain_relief = false
	if _terrain_w <= 0 or _terrain_h <= 0 or _terrain_heights.size() != _terrain_w * _terrain_h:
		_terrain_heights = []
		return
	for value in _terrain_heights:
		if absf(float(value)) > TERRAIN_RELIEF_EPSILON:
			_terrain_relief = true
			break
	if is_inside_tree():
		_sync_position()

## Hauteur du terrain (en cases) aux coordonnées grille **centrées case** —
## même convention que `ComplexMapEngine3D.terrain_height_at`.
func _terrain_height_at(gx: float, gy: float) -> float:
	if not _terrain_relief or _terrain_heights.is_empty():
		return 0.0
	if gx < -0.5 or gy < -0.5 or gx > float(_terrain_w) - 0.5 or gy > float(_terrain_h) - 0.5:
		return 0.0
	var sx := clampf(gx, 0.0, float(_terrain_w - 1))
	var sy := clampf(gy, 0.0, float(_terrain_h - 1))
	var x0 := floori(sx)
	var y0 := floori(sy)
	var x1 := mini(x0 + 1, _terrain_w - 1)
	var y1 := mini(y0 + 1, _terrain_h - 1)
	var fx := sx - float(x0)
	var fy := sy - float(y0)
	var h00 := float(_terrain_heights[y0 * _terrain_w + x0])
	var h10 := float(_terrain_heights[y0 * _terrain_w + x1])
	var h01 := float(_terrain_heights[y1 * _terrain_w + x0])
	var h11 := float(_terrain_heights[y1 * _terrain_w + x1])
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

## Hauteur monde du pied du token (0 sur terrain plat).
func _terrain_base_y(gx: float, gy: float) -> float:
	if not _terrain_relief:
		return 0.0
	return _terrain_height_at(gx, gy) * cell_size

## Repose le token sur la hauteur du terrain courant (après un déplacement).
func apply_terrain_y() -> void:
	var gx := (position.x - cell_size * 0.5) / cell_size
	var gy := (position.z - cell_size * 0.5) / cell_size
	var lift := 0.0
	if selected_state:
		lift = cell_size * (0.06 if diorama_mode else 0.12)
	position.y = _terrain_base_y(gx, gy) + lift

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

	if pawn_mode:
		_build_pawn_visuals()
	elif diorama_mode:
		_build_diorama_visuals()
	else:
		_build_vtt_visuals()

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# Hitbox large : le calque 2D est grand ; le raycast 3D reste un filet de secours.
	var wide := diorama_mode and not pawn_mode
	capsule.radius = cell_size * (0.55 if wide else 0.34)
	capsule.height = cell_size * (1.6 if wide else 0.6)
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)

func _build_diorama_visuals() -> void:
	# Figurine 3D du kit (PNJ) : rendu volume à la place de la découpe 2D.
	if not figurine_asset.is_empty() and _add_figurine_visuals():
		return
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
	return diorama_mode and not pawn_mode and _overlay_texture != null

## Bascule « pion posé sur le plateau » (vue table) — reconstruit le visuel.
func set_pawn_mode(on: bool) -> void:
	if pawn_mode == on:
		return
	pawn_mode = on
	_build_visuals()
	_sync_position()
	if selected_state:
		set_selected(true)

## Choisit une figurine 3D (GLB) pour ce token en mode 2.5D/diorama.
func set_figurine_asset(path: String) -> void:
	if figurine_asset == path:
		return
	figurine_asset = path
	_build_visuals()
	_sync_position()
	if selected_state:
		set_selected(true)

func has_figurine() -> bool:
	return not figurine_asset.is_empty() and _cutout == null and _overlay_texture == null \
		and get_child_count() > 0

## Instancie la figurine, la met à l'échelle (≈1,15 case de haut), centrée sur la
## case, avec socle coloré + ombre de contact + disque de sélection.
func _add_figurine_visuals() -> bool:
	var scene = AssetLibraryScript.instantiate_object3d_scene(figurine_asset)
	if not (scene is Node3D):
		return false
	var fig: Node3D = scene
	var aabb := _compute_node_aabb(fig)
	var base_height := maxf(aabb.size.y, 0.01)
	var factor := (cell_size * 1.15) / base_height
	fig.scale = Vector3.ONE * factor
	var center := aabb.get_center()
	fig.position = Vector3(-center.x * factor, -aabb.position.y * factor, -center.z * factor)
	add_child(fig)
	# Respiration discrète de la figurine (idle), déphasée par token.
	_fig_root = fig
	_fig_base_position = fig.position
	_fig_base_rotation_y = fig.rotation_degrees.y
	_idle_time = 0.0
	_idle_phase = float(abs(hash(str(token_data.get("id", "")))) % 628) / 100.0
	# Nom flottant au-dessus de la figurine (façon Dofus).
	var label_text := str(token_data.get("label", "")).strip_edges()
	if not label_text.is_empty():
		var name_label := Label3D.new()
		name_label.text = label_text
		name_label.font_size = 64
		name_label.outline_size = 15
		name_label.pixel_size = 0.0045
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.render_priority = 12
		name_label.modulate = Color(1.0, 0.97, 0.88, 0.95)
		name_label.outline_modulate = Color(0, 0, 0, 0.85)
		name_label.position = Vector3(0, cell_size * 1.7, 0)
		add_child(name_label)
	# Socle coloré du joueur (identification).
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = cell_size * 0.34
	base_mesh.bottom_radius = cell_size * 0.36
	base_mesh.height = cell_size * 0.05
	base.mesh = base_mesh
	base.position.y = cell_size * 0.025
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = _token_color()
	base_mat.roughness = 0.6
	base.material_override = base_mat
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)
	# Ombre de contact.
	_shadow = MeshInstance3D.new()
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = cell_size * 0.32
	shadow_mesh.bottom_radius = cell_size * 0.32
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
	_add_selection_disc()
	return true

## Respiration / balancement léger des figurines pour qu'elles paraissent vivantes.
func _process(delta: float) -> void:
	_idle_time += delta
	if _selection_ring != null and selected_state:
		var pulse := 1.0 + sin(_idle_time * 3.0) * 0.06
		_selection_ring.scale = Vector3(pulse, 1.0, pulse)
	elif _selection_ring != null:
		_selection_ring.scale = Vector3.ONE
	if _fig_root == null or _dragging:
		return
	var t := _idle_time * 1.8 + _idle_phase
	_fig_root.position.y = _fig_base_position.y + sin(t) * cell_size * 0.012
	_fig_root.rotation_degrees.y = _fig_base_rotation_y + sin(t * 0.55) * 1.8

## AABB combinée d'un nœud 3D et de ses enfants MeshInstance3D.
func _compute_node_aabb(node: Node3D) -> AABB:
	_fig_aabb_has = false
	_fig_aabb_acc = AABB()
	_accumulate_aabb(node, Transform3D.IDENTITY)
	return _fig_aabb_acc

func _accumulate_aabb(node: Node3D, xform: Transform3D) -> void:
	var local := xform * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var aabb: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for i in range(8):
			var point := aabb.get_endpoint(i)
			var world_point := local * point
			if not _fig_aabb_has:
				_fig_aabb_acc = AABB(world_point, Vector3.ZERO)
				_fig_aabb_has = true
			else:
				_fig_aabb_acc = _fig_aabb_acc.expand(world_point)
	for child in node.get_children():
		if child is Node3D:
			_accumulate_aabb(child as Node3D, local)

## Pion façon pièce d'échecs : profil de révolution (socle évasé, col,
## tête sphérique), verni à la couleur du joueur. Se pose / se soulève
## comme une figurine (cf. set_selected / update_drag_world).
## La révolution est tournée à la main (SurfaceTool) — LatheMesh n'existe pas
## dans Godot. Remplaçable plus tard par un vrai modèle Meshy par personnage
## (TableModelLoader.load_obj).
func _build_pawn_visuals() -> void:
	var base_r := cell_size * 0.30
	var h := cell_size * 1.15
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _make_pawn_mesh(base_r, h)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = _token_color()
	body_mat.roughness = 0.32
	body_mat.metallic = 0.08
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = body_mat
	add_child(_mesh)
	_add_selection_ring(0.03)

## Révolution 360° d'un profil pion (x = rayon en fraction de `base_r`,
## y = hauteur en fraction de `h`), triangles + normales générées.
func _make_pawn_mesh(base_r: float, h: float) -> ArrayMesh:
	var prof := [
		Vector2(0.0, 0.0),
		Vector2(0.95, 0.0),
		Vector2(1.0, 0.05),
		Vector2(0.72, 0.12),
		Vector2(0.38, 0.30),
		Vector2(0.30, 0.50),
		Vector2(0.50, 0.60),
		Vector2(0.34, 0.66),
		Vector2(0.52, 0.78),
		Vector2(0.50, 0.88),
		Vector2(0.30, 0.98),
		Vector2(0.0, 1.0),
	]
	var segments := 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(prof.size() - 1):
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[i + 1]
		for s in range(segments):
			var t0 := TAU * float(s) / float(segments)
			var t1 := TAU * float(s + 1) / float(segments)
			var a0 := Vector3(a.x * base_r * cos(t0), a.y * h, a.x * base_r * sin(t0))
			var b0 := Vector3(b.x * base_r * cos(t0), b.y * h, b.x * base_r * sin(t0))
			var b1 := Vector3(b.x * base_r * cos(t1), b.y * h, b.x * base_r * sin(t1))
			var a1 := Vector3(a.x * base_r * cos(t1), a.y * h, a.x * base_r * sin(t1))
			for v: Vector3 in [a0, b0, b1, a0, b1, a1]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func get_overlay_texture() -> Texture2D:
	return _overlay_texture

func get_overlay_height() -> float:
	return _overlay_height

func set_overlay_height(h: float) -> void:
	_overlay_height = maxf(h, 0.05)

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
	if diorama_mode and not pawn_mode:
		position.y = _terrain_base_y_at_world(position) + (cell_size * 0.03 if on else 0.0)
		return
	if _mesh and _mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _mesh.material_override
		mat.emission_enabled = on
		mat.emission = _token_color().lightened(0.4) if on else Color.BLACK
		mat.emission_energy_multiplier = 0.6 if on else 0.0
		position.y = _terrain_base_y_at_world(position) + (cell_size * 0.12 if on else 0.0)

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
	# Le point de sol renvoyé par le moteur tient déjà compte du relief.
	var base_y := world_pos.y if _terrain_relief else 0.0
	if selected_state:
		position.y = base_y + cell_size * (0.06 if diorama_mode else 0.12)
	else:
		position.y = base_y

func is_dragging() -> bool:
	return _dragging

func _sync_position() -> void:
	var gx := float(token_data.get("x", 0))
	var gy := float(token_data.get("y", 0))
	position = _grid_to_world(gx, gy)
	if selected_state:
		position.y = _terrain_base_y(gx, gy) + cell_size * (0.06 if diorama_mode else 0.12)

func _grid_to_world(gx: float, gy: float) -> Vector3:
	return Vector3(
		gx * cell_size + cell_size * 0.5,
		_terrain_base_y(gx, gy),
		gy * cell_size + cell_size * 0.5
	)

## Hauteur du terrain sous une position monde (pour `set_selected`).
func _terrain_base_y_at_world(world: Vector3) -> float:
	if not _terrain_relief:
		return 0.0
	var gx := (world.x - cell_size * 0.5) / cell_size
	var gy := (world.z - cell_size * 0.5) / cell_size
	return _terrain_base_y(gx, gy)

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
