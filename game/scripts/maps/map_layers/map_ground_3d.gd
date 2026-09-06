extends Node3D
class_name MapGround3D

## Sol 3D texturé. Quad XZ avec UV explicites.
## Mode nuit (façon brouillard) : texture nuit en base, masque de lumières
## révélant la texture jour avec falloff doux.

const NIGHT_SHADER := preload("res://shaders/map_night_reveal.gdshader")
const MASK_PX_PER_CELL := 8
const MAX_MASK_SIDE := 1024

var _mesh_instance: MeshInstance3D
var _extent: Vector2 = Vector2.ZERO
var _light_mask_tex: ImageTexture
var _night_active: bool = false

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

func configure(
	texture: Texture2D,
	map_width: int,
	map_height: int,
	cell_size: float,
	unshaded: bool = false,
	night_texture: Texture2D = null,
	night_mode: bool = false,
	light_sources: Array = [],
	light_revealed: Array = [],
	night_ambient: float = 0.22
) -> void:
	var w := float(map_width) * cell_size
	var h := float(map_height) * cell_size
	# Le quad a le même ratio que le PNG : l'illustration n'est ni croppée ni étirée.
	var aspect_tex: Texture2D = texture if texture != null else night_texture
	if aspect_tex != null and aspect_tex.get_height() > 0:
		var img_aspect := float(aspect_tex.get_width()) / float(aspect_tex.get_height())
		if img_aspect > 0.01:
			h = w / img_aspect
	_extent = Vector2(w, h)
	_mesh_instance.mesh = _make_ground_quad(w, h)
	_mesh_instance.position = Vector3.ZERO
	_mesh_instance.rotation_degrees = Vector3.ZERO

	_night_active = night_mode and texture != null and night_texture != null
	if _night_active:
		_apply_night_material(
			texture, night_texture, map_width, map_height,
			light_sources, light_revealed, night_ambient
		)
	else:
		_apply_day_material(texture if texture != null else night_texture, unshaded)

	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if (unshaded or _night_active) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func update_light_mask(
	map_width: int,
	map_height: int,
	light_sources: Array,
	light_revealed: Array,
	night_ambient: float = -1.0
) -> void:
	if not _night_active or _mesh_instance == null:
		return
	var mat := _mesh_instance.material_override
	if not (mat is ShaderMaterial):
		return
	var mask := _build_light_mask(map_width, map_height, light_sources, light_revealed)
	(mat as ShaderMaterial).set_shader_parameter("light_mask", mask)
	if night_ambient >= 0.0:
		(mat as ShaderMaterial).set_shader_parameter("night_ambient", clampf(night_ambient, 0.05, 1.0))

func is_night_active() -> bool:
	return _night_active

func _apply_day_material(texture: Texture2D, unshaded: bool) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.texture_repeat = false
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_instance.material_override = mat

func _apply_night_material(
	day_tex: Texture2D,
	night_tex: Texture2D,
	map_width: int,
	map_height: int,
	light_sources: Array,
	light_revealed: Array,
	night_ambient: float
) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = NIGHT_SHADER
	mat.set_shader_parameter("day_tex", day_tex)
	mat.set_shader_parameter("night_tex", night_tex)
	mat.set_shader_parameter("night_ambient", clampf(night_ambient, 0.05, 1.0))
	mat.set_shader_parameter("reveal_gamma", 1.15)
	mat.set_shader_parameter(
		"light_mask",
		_build_light_mask(map_width, map_height, light_sources, light_revealed)
	)
	_mesh_instance.material_override = mat

## Masque R8 : 0 = nuit (comme brouillard), 1 = jour révélé.
## Sources live + cases `lightRevealed` persistantes (façon fogRevealed).
func _build_light_mask(
	map_width: int,
	map_height: int,
	light_sources: Array,
	light_revealed: Array
) -> ImageTexture:
	var mw := maxi(1, map_width)
	var mh := maxi(1, map_height)
	var scale := MASK_PX_PER_CELL
	var tw := mini(MAX_MASK_SIDE, mw * scale)
	var th := mini(MAX_MASK_SIDE, mh * scale)
	# Recalcule scale si clamp
	var sx := float(tw) / float(mw)
	var sy := float(th) / float(mh)
	var img := Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))

	# Cases explorées persistantes (soft blob ~0.65 case).
	for key_variant in light_revealed:
		var key := str(key_variant)
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var cx := float(parts[0].to_int()) + 0.5
		var cy := float(parts[1].to_int()) + 0.5
		_stamp_soft_circle(img, cx * sx, cy * sy, maxf(sx, sy) * 0.75, 0.85)

	# Lumières live (rayon en cases, falloff smoothstep).
	for src_variant in light_sources:
		if not src_variant is Dictionary:
			continue
		var src: Dictionary = src_variant
		if bool(src.get("hidden", false)):
			continue
		var lx := float(src.get("x", 0.0)) + 0.5
		var ly := float(src.get("y", 0.0)) + 0.5
		var radius := maxf(0.35, float(src.get("radius", 3.0)))
		var energy := clampf(float(src.get("energy", 1.6)) / 1.6, 0.35, 1.35)
		_stamp_soft_circle(img, lx * sx, ly * sy, radius * maxf(sx, sy), energy)

	if _light_mask_tex == null:
		_light_mask_tex = ImageTexture.create_from_image(img)
	else:
		_light_mask_tex.update(img)
	return _light_mask_tex

func _stamp_soft_circle(img: Image, cx: float, cy: float, radius_px: float, strength: float) -> void:
	var r := maxf(1.0, radius_px)
	var r2 := r * r
	var x0 := maxi(0, int(floor(cx - r - 1.0)))
	var y0 := maxi(0, int(floor(cy - r - 1.0)))
	var x1 := mini(img.get_width() - 1, int(ceil(cx + r + 1.0)))
	var y1 := mini(img.get_height() - 1, int(ceil(cy + r + 1.0)))
	var s := clampf(strength, 0.0, 1.5)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - cx
			var dy := float(y) + 0.5 - cy
			var d2 := dx * dx + dy * dy
			if d2 > r2:
				continue
			var t := sqrt(d2) / r
			# smoothstep inverse : centre 1 → bord 0
			var fall := 1.0 - t
			fall = fall * fall * (3.0 - 2.0 * fall)
			var v := clampf(fall * s, 0.0, 1.0)
			var cur := img.get_pixel(x, y).r
			if v > cur:
				img.set_pixel(x, y, Color(v, 0, 0, 1))

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
