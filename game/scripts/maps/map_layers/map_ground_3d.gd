extends Node3D
class_name MapGround3D

## Sol de la carte 2.5D — deux modes, choisis par `map_data["groundMode"]`
## (résolu par `MapData.get_ground_mode()` et passé à `configure()`) :
##
## **`terrain3d`** — vrai terrain 3D simple (défaut des cartes sans fond peint).
## Heightfield de `(width+1) * (height+1)` sommets (deux triangles par case)
## construit depuis `terrainHeights` (une hauteur par case, en cases) : les
## sommets sont posés sur la grille de cases (`i * cell_size`, `j * cell_size`),
## leur hauteur est la moyenne des cases adjacentes (interpolation bilinéaire
## aux bords) et les normales sont calculées. Le matériau est **éclairé**
## (rugosité 1, métallique 0). Même sans relief (hauteurs nulles), c'est un vrai
## maillage 3D qui reçoit la lumière. La nuit, le même terrain est simplement
## teinté sombre (albédo multiplié) : **le relief reste visible**.
##
## **Matières du sol** (`map_data["terrainMaterials"]`, 0 = herbe, 1 = terre,
## 2 = pierre) : si le tableau est dimensionné, le sol utilise le shader
## `terrain_splat.gdshader` — trois textures seamless `game/assets/terrain/`
## (`grass.png`, `dirt.png`, `stone.png`, tuilées 2 cases) mélangées par une
## **texture de splat** `width × height` (R = herbe, G = terre, B = pierre),
## avec un second jeu d'UV (UV2, 0..1 sur la carte) et un filtrage linéaire qui
## adoucit les frontières. Les vertex colors ne portent alors que l'ombrage de
## pente (gris neutre) et le tout reste **éclairé** (spatial). Sans matières (ou
## sans textures), on retrouve le matériau actuel : texture de détail d'herbe +
## vertex colors de palette.
##
## **`illustrated`** — legacy / carte à fond peint : exactement l'ancien
## comportement, un quad XZ texturé (ratio du PNG) et, en mode nuit (brouillard),
## le shader de révélation jour/nuit avec masque de lumières. **Aucune
## déformation** : le relief n'est pas rendu, même si des hauteurs existent
## (elles restent des données logiques pour la pose des objets et le picking).

const NIGHT_SHADER := preload("res://shaders/map_night_reveal.gdshader")
const TERRAIN_SPLAT_SHADER := preload("res://shaders/terrain_splat.gdshader")
## Dossier des textures de matières (tuilables, générées par le pipeline Blender).
const TERRAIN_TEXTURE_DIR := "res://assets/terrain/"
## Matières du sol (mêmes valeurs que le document).
const MATERIAL_GRASS := 0
const MATERIAL_DIRT := 1
const MATERIAL_STONE := 2
const MASK_PX_PER_CELL := 8
const MAX_MASK_SIDE := 1024
## Modes de sol (mêmes valeurs que `MapData.GROUND_*`).
const GROUND_MODE_TERRAIN3D := "terrain3d"
const GROUND_MODE_ILLUSTRATED := "illustrated"
## Nombre de cases couvertes par une répétition de la texture de détail du sol.
const TERRAIN_TILE_CELLS := 2.0
## Un tableau de hauteurs n'est « relief » que si une case dépasse ce seuil.
const TERRAIN_RELIEF_EPSILON := 0.001
## Palette du terrain 3D (couleurs sRGB).
const TERRAIN_GRASS := Color(0.36, 0.52, 0.27)
const TERRAIN_EARTH := Color(0.50, 0.39, 0.26)
const TERRAIN_ROCK := Color(0.55, 0.54, 0.50)
## Teinte d'albédo du terrain la nuit (le vertex color est multiplié).
const TERRAIN_NIGHT_TINT := Color(0.32, 0.36, 0.48)
## Amplitude de la variation de couleur par sommet (±).
const TERRAIN_VARIATION := 0.055

var _mesh_instance: MeshInstance3D
var _extent: Vector2 = Vector2.ZERO
var _light_mask_tex: ImageTexture
## Shader jour/nuit actif (mode `illustrated` uniquement).
var _night_active: bool = false
## Carte en mode nuit (le terrain3d est alors teinté sombre).
var _night_mode_enabled: bool = false
## Dernier `configure` : permet de reconstruire le maillage seul quand seules
## les hauteurs changent (`set_terrain_heights`, pinceau de relief).
var _cfg: Dictionary = {}
## Mode de sol effectif (`terrain3d` ou `illustrated`).
var _ground_mode: String = GROUND_MODE_ILLUSTRATED
## Hauteurs du terrain : tableau plat, une hauteur par case, en cases.
var _terrain_heights: Array = []
var _terrain_w: int = 0
var _terrain_h: int = 0
## Matières du sol : tableau plat d'entiers (0 herbe, 1 terre, 2 pierre).
var _terrain_materials: Array = []
## Texture de splat (RGBA, width × height) quand les matières sont actives.
var _splat_texture: ImageTexture = null
## Image CPU correspondante : source fiable pour les tests/tools et les mises à
## jour successives (`ImageTexture.update` ne garantit pas la lecture inverse).
var _splat_image: Image = null
var _splat_active: bool = false
## Textures de matières (chargées à la demande) : "grass" / "dirt" / "stone".
var _terrain_textures: Dictionary = {}
## Bornes des hauteurs (pour la palette du terrain3d).
var _terrain_min: float = 0.0
var _terrain_max: float = 0.0

func _ready() -> void:
	_ensure_mesh_instance()

func _ensure_mesh_instance() -> void:
	if _mesh_instance != null and is_instance_valid(_mesh_instance):
		return
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
	night_ambient: float = 0.22,
	terrain_heights: Array = [],
	ground_mode: String = "",
	terrain_materials: Array = []
) -> void:
	_cfg = {
		"texture": texture,
		"map_width": map_width,
		"map_height": map_height,
		"cell_size": cell_size,
		"unshaded": unshaded,
		"night_texture": night_texture,
		"night_mode": night_mode,
		"light_sources": light_sources,
		"light_revealed": light_revealed,
		"night_ambient": night_ambient,
		"terrain_heights": terrain_heights,
		"ground_mode": ground_mode,
		"terrain_materials": terrain_materials,
	}
	_apply_config()

## Met à jour les hauteurs **sans recharger le fond** (retour visuel du pinceau
## de relief dans l'éditeur) : reconstruit le maillage du sol. Si les hauteurs
## n'ont pas changé (peinture de matières seule), ne fait rien : le splat est
## mis à jour séparément par `set_terrain_materials`.
func set_terrain_heights(heights: Array) -> void:
	var next: Array = heights if heights is Array else []
	_cfg["terrain_heights"] = next
	if not _cfg.has("map_width"):
		_terrain_heights = next
		return
	if _arrays_equal(_terrain_heights, next):
		return
	_apply_config()

## Met à jour les **matières du sol** sans reconstruire le viewport : met à jour
## la texture de splat (peinture fluide) et bascule le matériau seulement si
## l'activation du splat change (matières présentes/absentes, textures).
func set_terrain_materials(materials: Array) -> void:
	_cfg["terrain_materials"] = materials if materials is Array else []
	if not _cfg.has("map_width"):
		return
	if not is_terrain3d():
		# Mode illustré : les matières ne sont pas rendues.
		_terrain_materials = []
		return
	var next := _normalize_materials(_cfg["terrain_materials"])
	var next_active := _compute_splat_active_for(next)
	if next_active != _splat_active:
		# Bascule shader ↔ matériau de repli : le maillage doit être reconstruit
		# (les couleurs de sommet changent : palette ou ombrage neutre).
		_apply_config()
		return
	if _arrays_equal(_terrain_materials, next):
		return
	_terrain_materials = next
	if _splat_active:
		_update_splat_texture()
		var mat := _mesh_instance.material_override
		if mat is ShaderMaterial:
			(mat as ShaderMaterial).set_shader_parameter("splat_tex", _splat_texture)

## Vrai si le shader de matières (splat) est actif sur le terrain3d.
func is_splat_active() -> bool:
	return _splat_active

## Copie des matières du sol (vide si la carte n'en fournit pas).
func get_terrain_materials() -> Array:
	return _terrain_materials.duplicate()

## Texture de splat courante (null si les matières ne sont pas actives).
func get_splat_texture() -> ImageTexture:
	return _splat_texture

## Image CPU du splat (toujours à jour, contrairement à `get_image()` d'une
## `ImageTexture` mise à jour) — pour les outils et les tests.
func get_splat_image() -> Image:
	return _splat_image

## Change le mode de sol à chaud (le moteur recharge ensuite ses paramètres).
func set_ground_mode(mode: String) -> void:
	_cfg["ground_mode"] = _normalize_ground_mode(mode)
	if _cfg.has("map_width"):
		_apply_config()

static func _normalize_ground_mode(mode: String) -> String:
	var m := mode.strip_edges().to_lower()
	if m == GROUND_MODE_TERRAIN3D or m == GROUND_MODE_ILLUSTRATED:
		return m
	# Appel historique sans mode : on garde le sol illustré (compatibilité).
	return GROUND_MODE_ILLUSTRATED

func get_ground_mode() -> String:
	return _ground_mode

func is_terrain3d() -> bool:
	return _ground_mode == GROUND_MODE_TERRAIN3D

## Vrai si le sol est le vrai terrain 3D (heightfield), même à plat.
## (Nom historique : « relief actif » signifiait autrefois « hauteurs non
## nulles rendues » ; le mode terrain3d rend toujours un maillage 3D.)
func is_relief_active() -> bool:
	return is_terrain3d()

## Vrai si la carte a un relief non nul (au moins une case ≠ 0).
func has_terrain_relief() -> bool:
	return _compute_has_relief()

## Vrai si la carte est en mode nuit (terrain3d teinté / shader illustré).
func is_night_mode_enabled() -> bool:
	return _night_mode_enabled

func _compute_has_relief() -> bool:
	if _terrain_w <= 0 or _terrain_h <= 0:
		return false
	if _terrain_heights.size() != _terrain_w * _terrain_h:
		return false
	for value in _terrain_heights:
		if absf(float(value)) > TERRAIN_RELIEF_EPSILON:
			return true
	return false

func _apply_config() -> void:
	if _cfg.is_empty():
		return
	_ensure_mesh_instance()
	var texture: Texture2D = _cfg.get("texture")
	var night_texture: Texture2D = _cfg.get("night_texture")
	var map_width: int = int(_cfg.get("map_width", 1))
	var map_height: int = int(_cfg.get("map_height", 1))
	var cell_size: float = float(_cfg.get("cell_size", 1.0))
	var unshaded: bool = bool(_cfg.get("unshaded", false))
	var night_mode: bool = bool(_cfg.get("night_mode", false))
	_ground_mode = _normalize_ground_mode(str(_cfg.get("ground_mode", "")))
	_terrain_w = maxi(0, map_width)
	_terrain_h = maxi(0, map_height)
	var raw_heights = _cfg.get("terrain_heights", [])
	_terrain_heights = raw_heights if raw_heights is Array else []
	_night_mode_enabled = night_mode
	_night_active = false

	if _ground_mode == GROUND_MODE_TERRAIN3D:
		# Terrain 3D : extent = grille de cases (width × height), cases carrées.
		_extent = Vector2(float(_terrain_w) * cell_size, float(_terrain_h) * cell_size)
		_compute_terrain_bounds()
		_terrain_materials = _normalize_materials(_cfg.get("terrain_materials", []))
		_splat_active = _compute_splat_active()
		_mesh_instance.mesh = _make_terrain_mesh(cell_size)
		_mesh_instance.position = Vector3.ZERO
		_mesh_instance.rotation_degrees = Vector3.ZERO
		if _splat_active:
			_update_splat_texture()
		_apply_terrain_material(night_mode)
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not _splat_active:
			_splat_texture = null
			_splat_image = null
		return

	# Mode illustré (legacy) : quad plat, ratio du PNG, aucune déformation.
	_splat_active = false
	_splat_texture = null
	_splat_image = null
	_terrain_materials = []
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
			_cfg.get("light_sources", []), _cfg.get("light_revealed", []),
			float(_cfg.get("night_ambient", 0.22))
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

## Matériau du terrain 3D.
##
## Si les matières sont actives : `ShaderMaterial` `terrain_splat.gdshader` qui
## mélange les trois textures tuilées (UV) via le splat (UV2) et multiplie par
## les vertex colors d'ombrage ; il reste éclairé (spatial). `albedo_tint` porte
## la teinte de nuit.
##
## Sinon (pas de matières / textures absentes) : matériau de repli actuel —
## texture de détail d'herbe tuilable (si livrée) + vertex colors de palette.
func _apply_terrain_material(night_mode: bool) -> void:
	if _splat_active:
		var shader_mat := ShaderMaterial.new()
		shader_mat.shader = TERRAIN_SPLAT_SHADER
		shader_mat.set_shader_parameter("grass_tex", _terrain_textures.get("grass"))
		shader_mat.set_shader_parameter("dirt_tex", _terrain_textures.get("dirt"))
		shader_mat.set_shader_parameter("stone_tex", _terrain_textures.get("stone"))
		shader_mat.set_shader_parameter("splat_tex", _splat_texture)
		shader_mat.set_shader_parameter(
			"albedo_tint", TERRAIN_NIGHT_TINT if night_mode else Color.WHITE
		)
		shader_mat.set_shader_parameter("vertex_color_strength", 1.0)
		shader_mat.set_shader_parameter("blend_sharpness", 1.0)
		_mesh_instance.material_override = shader_mat
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TERRAIN_NIGHT_TINT if night_mode else Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var detail := _load_terrain_detail_texture()
	if detail != null:
		mat.albedo_texture = detail
		mat.texture_repeat = true
	_mesh_instance.material_override = mat

## Texture de détail du terrain (facultative) : bruit de sol peint, tuilé.
func _load_terrain_detail_texture() -> Texture2D:
	var path := "res://assets/terrain/grass.png"
	if not (ResourceLoader.exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))):
		return null
	var res = load(path) if ResourceLoader.exists(path) else null
	if res is Texture2D:
		return res
	return null

# ---------------------------------------------------------------------------
# Matières du sol (splat herbe / terre / pierre)
# ---------------------------------------------------------------------------

## Matières normalisées (0..2), dimensionnées width*height. Tableau absent ou
## mal dimensionné → vide (matériau de repli).
func _normalize_materials(raw: Variant) -> Array:
	var materials: Array = []
	if _terrain_w <= 0 or _terrain_h <= 0:
		return materials
	var expected: int = _terrain_w * _terrain_h
	if not (raw is Array) or (raw as Array).size() != expected:
		return materials
	materials.resize(expected)
	for i in range(expected):
		materials[i] = clampi(int((raw as Array)[i]), MATERIAL_GRASS, MATERIAL_STONE)
	return materials

## Vrai si un splat peut être rendu avec ces matières (textures disponibles).
func _compute_splat_active_for(materials: Array) -> bool:
	if not is_terrain3d() or _terrain_w <= 0 or _terrain_h <= 0:
		return false
	if materials.size() != _terrain_w * _terrain_h:
		return false
	return _ensure_terrain_textures()

func _compute_splat_active() -> bool:
	return _compute_splat_active_for(_terrain_materials)

## Charge (une seule fois) les trois textures de matières. Faux si l'une manque.
func _ensure_terrain_textures() -> bool:
	for name in ["grass", "dirt", "stone"]:
		if not _terrain_textures.has(name):
			_terrain_textures[name] = _load_terrain_texture(name)
		if _terrain_textures[name] == null:
			return false
	return true

## Charge une texture de matière : PNG source (mipmaps générées pour le
## minification) puis repli sur la ressource importée.
func _load_terrain_texture(texture_name: String) -> Texture2D:
	var path := TERRAIN_TEXTURE_DIR + texture_name + ".png"
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	push_warning("[MapGround3D] texture de matière manquante : %s" % path)
	return null

## Construit / met à jour la texture de splat : une case = un texel,
## R = herbe, G = terre, B = pierre (A = 1). Le filtrage linéaire du shader
## adoucit les frontières entre matières.
func _update_splat_texture() -> void:
	if not _splat_active or _terrain_w <= 0 or _terrain_h <= 0:
		return
	var img := Image.create(_terrain_w, _terrain_h, false, Image.FORMAT_RGBA8)
	for y in range(_terrain_h):
		for x in range(_terrain_w):
			var idx := y * _terrain_w + x
			var material := MATERIAL_GRASS
			if idx >= 0 and idx < _terrain_materials.size():
				material = int(_terrain_materials[idx])
			img.set_pixel(x, y, _material_splat_color(material))
	_splat_image = img
	if _splat_texture == null \
			or _splat_texture.get_width() != _terrain_w \
			or _splat_texture.get_height() != _terrain_h:
		_splat_texture = ImageTexture.create_from_image(img)
	else:
		_splat_texture.update(img)

## Couleur de splat d'une matière (poids pleins dans un canal).
func _material_splat_color(material: int) -> Color:
	match material:
		MATERIAL_DIRT:
			return Color(0.0, 1.0, 0.0, 1.0)
		MATERIAL_STONE:
			return Color(0.0, 0.0, 1.0, 1.0)
		_:
			return Color(1.0, 0.0, 0.0, 1.0)

## Vrai si deux tableaux plats (heights ou materials) ont le même contenu.
func _arrays_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if typeof(a[i]) == TYPE_FLOAT or typeof(b[i]) == TYPE_FLOAT:
			if not is_equal_approx(float(a[i]), float(b[i])):
				return false
		elif a[i] != b[i]:
			return false
	return true

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

## Terrain 3D : grille indexée `(w+1) * (h+1)` sommets, deux triangles par
## case. Hauteur d'un sommet = moyenne des cases adjacentes (donc interpolation
## bilinéaire aux bords entre centres de cases), normales calculées, couleurs
## de sommet herbe/terre/roche.
func _make_terrain_mesh(cell_size: float) -> ArrayMesh:
	var w := _terrain_w
	var h := _terrain_h
	var cols := w + 1
	var rows := h + 1
	var count := cols * rows
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	## UV2 : 0..1 sur toute la carte, pour la texture de splat des matières.
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	verts.resize(count)
	normals.resize(count)
	uvs.resize(count)
	uv2s.resize(count)
	colors.resize(count)

	# Hauteurs aux sommets (moyenne des cases adjacentes).
	var heights := PackedFloat32Array()
	heights.resize(count)
	for j in range(rows):
		for i in range(cols):
			var total := 0.0
			var samples := 0
			for oy in range(-1, 1):
				var cy := j + oy
				if cy < 0 or cy >= h:
					continue
				for ox in range(-1, 1):
					var cx := i + ox
					if cx < 0 or cx >= w:
						continue
					total += _cell_height(cx, cy)
					samples += 1
			heights[j * cols + i] = total / float(maxi(1, samples))

	for j in range(rows):
		for i in range(cols):
			var idx := j * cols + i
			var hv := heights[idx]
			verts[idx] = Vector3(float(i) * cell_size, hv * cell_size, float(j) * cell_size)
			uvs[idx] = Vector2(
				float(i) / TERRAIN_TILE_CELLS,
				float(j) / TERRAIN_TILE_CELLS
			)
			uv2s[idx] = Vector2(
				float(i) / float(maxi(1, w)),
				float(j) / float(maxi(1, h))
			)
			var x0 := maxi(i - 1, 0)
			var x1 := mini(i + 1, w)
			var z0 := maxi(j - 1, 0)
			var z1 := mini(j + 1, h)
			var dhdx := (heights[j * cols + x1] - heights[j * cols + x0]) / float(maxi(1, x1 - x0))
			var dhdz := (heights[z1 * cols + i] - heights[z0 * cols + i]) / float(maxi(1, z1 - z0))
			var normal := Vector3(-dhdx, 1.0, -dhdz).normalized()
			normals[idx] = normal
			# Splat actif : les textures portent la couleur des matières, les
			# vertex colors ne gardent que l'ombrage de pente (gris neutre).
			# Repli : palette herbe/terre/roche actuelle.
			if _splat_active:
				colors[idx] = _terrain_vertex_shade(normal, i, j)
			else:
				colors[idx] = _terrain_vertex_color(hv, normal, i, j)

	var indices := PackedInt32Array()
	indices.resize(w * h * 6)
	var n := 0
	for j in range(h):
		for i in range(w):
			var a := j * cols + i
			var b := a + 1
			var c := (j + 1) * cols + i
			var d := c + 1
			indices[n] = a
			indices[n + 1] = b
			indices[n + 2] = c
			indices[n + 3] = b
			indices[n + 4] = d
			indices[n + 5] = c
			n += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Couleur d'un sommet du terrain : herbe au plat, terre sur les pentes douces
## et dans les creux, roche sur les pentes fortes et les sommets. La composante
## de hauteur est normalisée sur l'amplitude du relief de la carte.
func _terrain_vertex_color(hv: float, normal: Vector3, i: int, j: int) -> Color:
	var slope_deg := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	var span := _terrain_max - _terrain_min
	var height01 := 0.0
	if span > TERRAIN_RELIEF_EPSILON:
		height01 = clampf((hv - _terrain_min) / span, 0.0, 1.0)
	# Roche : pentes fortes, sommets hauts. Terre : pentes douces + bas-fonds.
	var rock := smoothstep(20.0, 38.0, slope_deg)
	rock = maxf(rock, smoothstep(0.72, 1.0, height01) * 0.85)
	var earth := (1.0 - rock) * smoothstep(5.0, 18.0, slope_deg)
	earth = maxf(earth, (1.0 - rock) * (1.0 - smoothstep(0.0, 0.20, height01)) * 0.45)
	var col := TERRAIN_GRASS.lerp(TERRAIN_EARTH, earth).lerp(TERRAIN_ROCK, rock)
	var variation := _terrain_variation(i, j) * TERRAIN_VARIATION
	if variation > 0.0:
		col = col.lightened(variation)
	else:
		col = col.darkened(-variation)
	col.a = 1.0
	return col

## Ombrage neutre d'un sommet quand les matières (splat) portent la couleur :
## 1.0 au plat, ~0.78 sur les pentes fortes, plus une variation douce.
func _terrain_vertex_shade(normal: Vector3, i: int, j: int) -> Color:
	var slope_deg := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	var darken := smoothstep(8.0, 36.0, slope_deg) * 0.22
	var variation := _terrain_variation(i, j) * TERRAIN_VARIATION
	var shade := clampf(1.0 - darken + variation, 0.6, 1.0)
	return Color(shade, shade, shade, 1.0)

## Bruit déterministe (-1..1) pour casser les aplats sans texture.
func _terrain_variation(i: int, j: int) -> float:
	var v := sin(float(i) * 12.9898 + float(j) * 78.233) * 43758.5453
	return (v - floorf(v)) * 2.0 - 1.0

## Bornes des hauteurs (pour normaliser la composante de hauteur des couleurs).
func _compute_terrain_bounds() -> void:
	_terrain_min = 0.0
	_terrain_max = 0.0
	if _terrain_w <= 0 or _terrain_h <= 0:
		return
	if _terrain_heights.size() != _terrain_w * _terrain_h:
		return
	if _terrain_heights.is_empty():
		return
	var first := true
	for value in _terrain_heights:
		var v := float(value)
		if first:
			_terrain_min = v
			_terrain_max = v
			first = false
			continue
		_terrain_min = minf(_terrain_min, v)
		_terrain_max = maxf(_terrain_max, v)

func _cell_height(cx: int, cy: int) -> float:
	if _terrain_w <= 0 or _terrain_h <= 0:
		return 0.0
	if cx < 0 or cy < 0 or cx >= _terrain_w or cy >= _terrain_h:
		return 0.0
	var idx := cy * _terrain_w + cx
	if idx < 0 or idx >= _terrain_heights.size():
		return 0.0
	return float(_terrain_heights[idx])

func get_map_extent() -> Vector2:
	return _extent
