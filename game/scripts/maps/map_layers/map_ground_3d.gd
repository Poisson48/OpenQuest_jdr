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
## 2 = pierre, 3 = neige, 4 = sable) : si le tableau est dimensionné, le sol
## utilise le shader `terrain_splat.gdshader` — cinq textures seamless
## `game/assets/terrain/` (`grass.png`, `dirt.png`, `stone.png`, `snow.png`,
## `sand.png`, tuilées 2 cases) mélangées par **deux textures de splat**
## `width × height` (splat 1 : R = herbe, G = terre, B = pierre ; splat 2 :
## R = neige, G = sable), avec un second jeu d'UV (UV2, 0..1 sur la carte) et un
## filtrage linéaire qui adoucit les frontières. Les trois premières matières
## gardent exactement leur rendu historique (splat 2 nul). Les vertex colors ne
## portent alors que l'ombrage de pente (gris neutre) et le tout reste
## **éclairé** (spatial). Sans matières (ou sans textures), on retrouve le
## matériau actuel : texture de détail d'herbe + vertex colors de palette.
##
## **`illustrated`** — legacy / carte à fond peint : exactement l'ancien
## comportement, un quad XZ texturé (ratio du PNG) et, en mode nuit (brouillard),
## le shader de révélation jour/nuit avec masque de lumières. **Aucune
## déformation** : le relief n'est pas rendu, même si des hauteurs existent
## (elles restent des données logiques pour la pose des objets et le picking).
##
## **Jupe de falaise** (`terrain3d` uniquement) : un anneau de falaises
## verticales sur le pourtour de la grille donne à la carte l'allure d'un
## plateau/îlot (façon Dofus) au lieu de flotter sur le fond noir. Le sommet
## suit exactement les hauteurs des sommets de bord, la paroi descend de
## `CLIFF_DEPTH_CELLS` cases sous le niveau local, les normales pointent vers
## l'extérieur et un matériau roche éclairé (rugosité 1, vertex colors en
## strates) la rend lisible. Un **rebord horizontal** (« lip », large de
## `CLIFF_LIP_CELLS` case) prolonge le sommet vers l'extérieur avec des normales
## vers le haut et une roche plus claire : il rend le contour de la carte
## visible même en vue quasi top-down (où la paroi n'est qu'une ligne de
## profil). Le sommet de la paroi est décalé de `CLIFF_OUTSET_CELLS` vers
## l'extérieur pour éviter le z-fighting avec le terrain, le lip part de la
## limite de la carte pour couvrir le raccord. Aucune ombre portée. Aucune jupe
## en mode `illustrated`, et tout se reconstruit avec le maillage (configure /
## set_terrain_heights).

const NIGHT_SHADER := preload("res://shaders/map_night_reveal.gdshader")
const TERRAIN_SPLAT_SHADER := preload("res://shaders/terrain_splat.gdshader")
## Dossier des textures de matières (tuilables, générées par le pipeline Blender).
const TERRAIN_TEXTURE_DIR := "res://assets/terrain/"
## Matières du sol (mêmes valeurs que le document / `MapData`).
const MATERIAL_GRASS := 0
const MATERIAL_DIRT := 1
const MATERIAL_STONE := 2
const MATERIAL_SNOW := 3
const MATERIAL_SAND := 4
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
## Jupe de falaise autour des cartes `terrain3d` (îlot façon Dofus).
## Profondeur de la paroi sous le niveau local, en cases.
const CLIFF_DEPTH_CELLS := 2.5
## Décalage du sommet vers l'extérieur, en cases (anti z-fighting).
const CLIFF_OUTSET_CELLS := 0.02
## Couleur de base de la roche de falaise (brun-gris terreux).
const CLIFF_ROCK := Color(0.38, 0.34, 0.29)
## Roche éclaircie pour les strates.
const CLIFF_ROCK_LIGHT := Color(0.54, 0.49, 0.42)
## Éclaircissement des strates (maximum ajouté à la couleur de base).
const CLIFF_STRATA_GAIN := 0.16
## Rebord horizontal au sommet de la falaise (visible en vue de dessus).
## Largeur du rebord vers l'extérieur, en cases.
const CLIFF_LIP_CELLS := 0.45
## Roche du rebord, un peu plus claire que la paroi pour marquer le contour.
const CLIFF_LIP := Color(0.46, 0.41, 0.34)
## Variation douce de couleur du rebord (±).
const CLIFF_LIP_VARIATION := 0.04

var _mesh_instance: MeshInstance3D
## Jupe de falaise : mesh séparé (matériau roche) construit en terrain3d.
var _cliff_instance: MeshInstance3D
var _cliff_active: bool = false
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
var _terrain_detail: int = 1
var _terrain_w: int = 0
var _terrain_h: int = 0
## Matières du sol : tableau plat d'entiers (0 herbe, 1 terre, 2 pierre,
## 3 neige, 4 sable).
var _terrain_materials: Array = []
## Texture de splat 1 (RGBA, width × height) : R herbe, G terre, B pierre.
var _splat_texture: ImageTexture = null
## Image CPU correspondante : source fiable pour les tests/tools et les mises à
## jour successives (`ImageTexture.update` ne garantit pas la lecture inverse).
var _splat_image: Image = null
## Texture de splat 2 (RGBA) : R neige, G sable.
var _splat2_texture: ImageTexture = null
var _splat2_image: Image = null
var _splat_active: bool = false
## Textures de matières (chargées à la demande) :
## "grass" / "dirt" / "stone" / "snow" / "sand".
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
	_ensure_cliff_instance()

func _ensure_cliff_instance() -> void:
	if _cliff_instance != null and is_instance_valid(_cliff_instance):
		return
	_cliff_instance = MeshInstance3D.new()
	_cliff_instance.name = "CliffSkirt"
	_cliff_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cliff_instance.visible = false
	add_child(_cliff_instance)

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
	terrain_materials: Array = [],
	terrain_detail: int = 1
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
		"terrain_detail": terrain_detail,
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
			(mat as ShaderMaterial).set_shader_parameter("splat2_tex", _splat2_texture)

## Vrai si le shader de matières (splat) est actif sur le terrain3d.
func is_splat_active() -> bool:
	return _splat_active

## Copie des matières du sol (vide si la carte n'en fournit pas).
func get_terrain_materials() -> Array:
	return _terrain_materials.duplicate()

## Texture de splat 1 (R herbe, G terre, B pierre) — null si inactif.
func get_splat_texture() -> ImageTexture:
	return _splat_texture

## Image CPU du splat 1 (toujours à jour, contrairement à `get_image()` d'une
## `ImageTexture` mise à jour) — pour les outils et les tests.
func get_splat_image() -> Image:
	return _splat_image

## Texture de splat 2 (R neige, G sable) — null si inactif.
func get_splat2_texture() -> ImageTexture:
	return _splat2_texture

## Image CPU du splat 2 (neige/sable).
func get_splat2_image() -> Image:
	return _splat2_image

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
	_ensure_cliff_instance()
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
	_terrain_detail = clampi(int(_cfg.get("terrain_detail", 1)), 1, 4)
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
			_splat2_texture = null
			_splat2_image = null
		_rebuild_cliff(cell_size, night_mode)
		return

	# Mode illustré (legacy) : quad plat, ratio du PNG, aucune déformation.
	_clear_cliff()
	_splat_active = false
	_splat_texture = null
	_splat_image = null
	_splat2_texture = null
	_splat2_image = null
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
## mélange les cinq textures tuilées (UV) via les deux splats (UV2) et multiplie
## par les vertex colors d'ombrage ; il reste éclairé (spatial). `albedo_tint`
## porte la teinte de nuit.
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
		shader_mat.set_shader_parameter("snow_tex", _terrain_textures.get("snow"))
		shader_mat.set_shader_parameter("sand_tex", _terrain_textures.get("sand"))
		shader_mat.set_shader_parameter("splat_tex", _splat_texture)
		shader_mat.set_shader_parameter("splat2_tex", _splat2_texture)
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

## Matières normalisées (0..4), dimensionnées width*height. Tableau absent ou
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
		materials[i] = clampi(int((raw as Array)[i]), MATERIAL_GRASS, MATERIAL_SAND)
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

## Charge (une seule fois) les cinq textures de matières. Faux si l'une manque.
func _ensure_terrain_textures() -> bool:
	for name in ["grass", "dirt", "stone", "snow", "sand"]:
		if not _terrain_textures.has(name):
			_terrain_textures[name] = _load_terrain_texture(name)
		if _terrain_textures[name] == null:
			return false
	# Matière « terre de chemin » générée par IA : utilisée si elle est livrée.
	if not _terrain_textures.has("dirt_ai"):
		_terrain_textures["dirt_ai"] = _load_terrain_texture("dirt_ai")
	if _terrain_textures["dirt_ai"] != null:
		_terrain_textures["dirt"] = _terrain_textures["dirt_ai"]
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

## Construit / met à jour les **deux** textures de splat (une case = un texel) :
##   • splat 1 : R = herbe, G = terre, B = pierre (A = 1) — encodage historique
##     strictement inchangé ;
##   • splat 2 : R = neige, G = sable.
## Le filtrage linéaire du shader adoucit les frontières entre matières.
func _update_splat_texture() -> void:
	if not _splat_active or _terrain_w <= 0 or _terrain_h <= 0:
		return
	var img1 := Image.create(_terrain_w, _terrain_h, false, Image.FORMAT_RGBA8)
	var img2 := Image.create(_terrain_w, _terrain_h, false, Image.FORMAT_RGBA8)
	for y in range(_terrain_h):
		for x in range(_terrain_w):
			var idx := y * _terrain_w + x
			var material := MATERIAL_GRASS
			if idx >= 0 and idx < _terrain_materials.size():
				material = int(_terrain_materials[idx])
			img1.set_pixel(x, y, _material_splat_color(material))
			img2.set_pixel(x, y, _material_splat2_color(material))
	_splat_image = img1
	_splat2_image = img2
	if _splat_texture == null \
			or _splat_texture.get_width() != _terrain_w \
			or _splat_texture.get_height() != _terrain_h:
		_splat_texture = ImageTexture.create_from_image(img1)
	else:
		_splat_texture.update(img1)
	if _splat2_texture == null \
			or _splat2_texture.get_width() != _terrain_w \
			or _splat2_texture.get_height() != _terrain_h:
		_splat2_texture = ImageTexture.create_from_image(img2)
	else:
		_splat2_texture.update(img2)

## Couleur de la texture de splat 1 : R = herbe, G = terre, B = pierre.
func _material_splat_color(material: int) -> Color:
	match material:
		MATERIAL_DIRT:
			return Color(0.0, 1.0, 0.0, 1.0)
		MATERIAL_STONE:
			return Color(0.0, 0.0, 1.0, 1.0)
		MATERIAL_SNOW, MATERIAL_SAND:
			# Neige/sable : aucun poids dans le splat 1 (tout est dans le splat 2).
			return Color(0.0, 0.0, 0.0, 1.0)
		_:
			return Color(1.0, 0.0, 0.0, 1.0)

## Couleur de la texture de splat 2 : R = neige, G = sable.
func _material_splat2_color(material: int) -> Color:
	match material:
		MATERIAL_SNOW:
			return Color(1.0, 0.0, 0.0, 1.0)
		MATERIAL_SAND:
			return Color(0.0, 1.0, 0.0, 1.0)
		_:
			return Color(0.0, 0.0, 0.0, 1.0)

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
	var detail := clampi(_terrain_detail, 1, 4)
	var cols := w * detail + 1
	var rows := h * detail + 1
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

	# Hauteurs échantillonnées à la résolution de détail (bilinéaire).
	var heights := PackedFloat32Array()
	heights.resize(count)
	for j in range(rows):
		for i in range(cols):
			heights[j * cols + i] = _vertex_height_at(float(i) / float(detail), float(j) / float(detail))

	for j in range(rows):
		for i in range(cols):
			var idx := j * cols + i
			var hv := heights[idx]
			var gx := float(i) / float(detail)
			var gy := float(j) / float(detail)
			verts[idx] = Vector3(gx * cell_size, hv * cell_size, gy * cell_size)
			uvs[idx] = Vector2(gx / TERRAIN_TILE_CELLS, gy / TERRAIN_TILE_CELLS)
			uv2s[idx] = Vector2(
				gx / float(maxi(1, w)),
				gy / float(maxi(1, h))
			)
			var x0 := maxi(i - 1, 0)
			var x1 := mini(i + 1, cols - 1)
			var z0 := maxi(j - 1, 0)
			var z1 := mini(j + 1, rows - 1)
			var dhdx := (heights[j * cols + x1] - heights[j * cols + x0]) / maxf(0.001, float(x1 - x0) / float(detail))
			var dhdz := (heights[z1 * cols + i] - heights[z0 * cols + i]) / maxf(0.001, float(z1 - z0) / float(detail))
			var normal := Vector3(-dhdx, 1.0, -dhdz).normalized()
			normals[idx] = normal
			if _splat_active:
				colors[idx] = _terrain_vertex_shade(normal, int(floor(gx)), int(floor(gy)))
			else:
				colors[idx] = _terrain_vertex_color(hv, normal, int(floor(gx)), int(floor(gy)))

	var cell_cols := cols - 1
	var cell_rows := rows - 1
	var indices := PackedInt32Array()
	indices.resize(cell_cols * cell_rows * 6)
	var n := 0
	for j in range(cell_rows):
		for i in range(cell_cols):
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

## Hauteur interpolée du maillage de terrain (coordonnées grille fractionnaires).
func _vertex_height_at(gx: float, gy: float) -> float:
	var x0 := floori(gx)
	var y0 := floori(gy)
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	var h00 := _vertex_height(x0, y0)
	var h10 := _vertex_height(x0 + 1, y0)
	var h01 := _vertex_height(x0, y0 + 1)
	var h11 := _vertex_height(x0 + 1, y0 + 1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

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

## Hauteur d'un **sommet** de la grille (en cases) : moyenne des cases adjacentes
## (interpolation bilinéaire aux bords). Sert au terrain ET à la jupe de falaise,
## pour que le sommet des falaises suive exactement les hauteurs de bord.
func _vertex_height(i: int, j: int) -> float:
	var total := 0.0
	var samples := 0
	for oy in range(-1, 1):
		var cy := j + oy
		if cy < 0 or cy >= _terrain_h:
			continue
		for ox in range(-1, 1):
			var cx := i + ox
			if cx < 0 or cx >= _terrain_w:
				continue
			total += _cell_height(cx, cy)
			samples += 1
	return total / float(maxi(1, samples))

func _cell_height(cx: int, cy: int) -> float:
	if _terrain_w <= 0 or _terrain_h <= 0:
		return 0.0
	if cx < 0 or cy < 0 or cx >= _terrain_w or cy >= _terrain_h:
		return 0.0
	var idx := cy * _terrain_w + cx
	if idx < 0 or idx >= _terrain_heights.size():
		return 0.0
	return float(_terrain_heights[idx])

## Hauteur du terrain (en cases) d'une case de la grille — exposée pour les
## calques qui doivent détecter une immersion (eau) ou poser des objets.
## 0 hors carte / sans données de relief.
func get_cell_height(cx: int, cy: int) -> float:
	return _cell_height(cx, cy)

## Copie des hauteurs par case ([] si la carte n'en fournit pas).
func get_terrain_heights() -> Array:
	return _terrain_heights.duplicate()

## Taille de la grille du sol en cases.
func get_terrain_size() -> Vector2i:
	return Vector2i(_terrain_w, _terrain_h)

## Nombre de cases dont la hauteur est sous `level` (immersion, en cases).
func count_cells_below(level: float) -> int:
	var count := 0
	for y in range(_terrain_h):
		for x in range(_terrain_w):
			if _cell_height(x, y) < level - TERRAIN_RELIEF_EPSILON:
				count += 1
	return count

# ===========================================================================
# Jupe de falaise (îlot façon Dofus) — terrain3d uniquement
# ===========================================================================

## Vrai si la jupe de falaise est rendue (mode terrain3d uniquement).
func is_cliff_skirt_active() -> bool:
	return _cliff_active

## Profondeur de la falaise sous le niveau local, en cases.
func get_cliff_depth() -> float:
	return CLIFF_DEPTH_CELLS

## Profondeur de la falaise en unités monde (cases × cell_size).
func get_cliff_depth_world() -> float:
	return CLIFF_DEPTH_CELLS * maxf(0.0, float(_cfg.get("cell_size", 1.0)))

## Largeur du rebord horizontal au sommet, en cases.
func get_cliff_lip_width() -> float:
	return CLIFF_LIP_CELLS

## Largeur du rebord horizontal en unités monde (cases × cell_size).
func get_cliff_lip_width_world() -> float:
	return CLIFF_LIP_CELLS * maxf(0.0, float(_cfg.get("cell_size", 1.0)))

## Nœud de la jupe de falaise (null tant que rien n'est construit).
func get_cliff_mesh_instance() -> MeshInstance3D:
	return _cliff_instance

## Maillage de la jupe (null en mode illustré / sans terrain).
func get_cliff_mesh() -> ArrayMesh:
	if _cliff_instance == null:
		return null
	return _cliff_instance.mesh as ArrayMesh

## Nombre de sommets du maillage de falaise (0 si aucune jupe).
func get_cliff_vertex_count() -> int:
	var mesh := get_cliff_mesh()
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size()

## Matériau de la jupe (StandardMaterial3D éclairé, roche + strates).
func get_cliff_material() -> StandardMaterial3D:
	if _cliff_instance == null:
		return null
	return _cliff_instance.material_override as StandardMaterial3D

## Reconstruit la jupe de falaise (appelé à chaque reconstruction du sol).
func _rebuild_cliff(cell_size: float, night_mode: bool) -> void:
	if _cliff_instance == null or not is_instance_valid(_cliff_instance):
		return
	if _terrain_w <= 0 or _terrain_h <= 0:
		_clear_cliff()
		return
	var mesh := _make_cliff_mesh(cell_size)
	if mesh == null:
		_clear_cliff()
		return
	_cliff_instance.mesh = mesh
	_cliff_instance.position = Vector3.ZERO
	_cliff_instance.rotation_degrees = Vector3.ZERO
	_cliff_instance.material_override = _make_cliff_material(night_mode)
	_cliff_instance.visible = true
	_cliff_active = true

func _clear_cliff() -> void:
	_cliff_active = false
	if _cliff_instance != null and is_instance_valid(_cliff_instance):
		_cliff_instance.mesh = null
		_cliff_instance.visible = false

## Anneau de falaises : 4 bandes verticales le long des bords de la grille, plus
## un rebord horizontal (« lip ») au sommet de chaque bande pour rester lisible
## en vue de dessus. Le sommet reprend exactement les hauteurs des sommets de
## bord du terrain (`_vertex_height`), la paroi descend de `CLIFF_DEPTH_CELLS`
## cases. Les sommets de paroi sont décalés de `CLIFF_OUTSET_CELLS` vers
## l'extérieur (z-fighting), le lip part de la limite de la carte et s'étend de
## `CLIFF_LIP_CELLS` case vers l'extérieur, avec des normales vers le haut.
func _make_cliff_mesh(cell_size: float) -> ArrayMesh:
	if _terrain_w <= 0 or _terrain_h <= 0:
		return null
	var depth := CLIFF_DEPTH_CELLS * cell_size
	var outset := CLIFF_OUTSET_CELLS * cell_size
	# Distance externe du rebord (décalage anti z-fighting + largeur du lip).
	var lip_distance := outset + CLIFF_LIP_CELLS * cell_size
	# Arrays simples (référence) : convertis en Packed*Array au commit.
	var verts: Array = []
	var normals: Array = []
	var colors: Array = []
	var indices: Array = []
	_append_cliff_side(verts, normals, colors, indices, "north", cell_size, depth, outset)
	_append_cliff_side(verts, normals, colors, indices, "south", cell_size, depth, outset)
	_append_cliff_side(verts, normals, colors, indices, "west", cell_size, depth, outset)
	_append_cliff_side(verts, normals, colors, indices, "east", cell_size, depth, outset)
	_append_cliff_lip(verts, normals, colors, indices, "north", cell_size, lip_distance)
	_append_cliff_lip(verts, normals, colors, indices, "south", cell_size, lip_distance)
	_append_cliff_lip(verts, normals, colors, indices, "west", cell_size, lip_distance)
	_append_cliff_lip(verts, normals, colors, indices, "east", cell_size, lip_distance)
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(indices)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Ajoute une bande de falaise (un côté de la carte) aux tableaux de géométrie.
func _append_cliff_side(
	verts: Array,
	normals: Array,
	colors: Array,
	indices: Array,
	side: String,
	cell_size: float,
	depth: float,
	outset: float
) -> void:
	var horizontal := side == "north" or side == "south"
	var segment_count := _terrain_w if horizontal else _terrain_h
	# On déborde d'un échantillon de chaque côté pour couvrir les coins.
	var sample_count := segment_count + 3
	var normal := Vector3.ZERO
	match side:
		"north":
			normal = Vector3(0.0, 0.0, -1.0)
		"south":
			normal = Vector3(0.0, 0.0, 1.0)
		"west":
			normal = Vector3(-1.0, 0.0, 0.0)
		"east":
			normal = Vector3(1.0, 0.0, 0.0)
	var first_index := verts.size()
	for s in range(sample_count):
		var along := s - 1
		var along_pos := 0.0
		var top_y := 0.0
		# Décalage d'un échantillon hors carte aux deux extrémités.
		if along < 0:
			along_pos = -outset
		elif along > segment_count:
			along_pos = float(segment_count) * cell_size + outset
		else:
			along_pos = float(along) * cell_size
		if horizontal:
			var edge_j := 0 if side == "north" else _terrain_h
			top_y = _vertex_height(clampi(along, 0, _terrain_w), edge_j) * cell_size
		else:
			var edge_i := 0 if side == "west" else _terrain_w
			top_y = _vertex_height(edge_i, clampi(along, 0, _terrain_h)) * cell_size
		var top_pos := _cliff_side_position(side, along_pos, top_y, outset, cell_size)
		var bottom_pos := Vector3(top_pos.x, top_y - depth, top_pos.z)
		verts.append(top_pos)
		verts.append(bottom_pos)
		normals.append(normal)
		normals.append(normal)
		colors.append(_cliff_vertex_color(top_y, 0.0, along))
		colors.append(_cliff_vertex_color(top_y - depth, 1.0, along))
	for s in range(sample_count - 1):
		var t0 := first_index + s * 2
		var b0 := t0 + 1
		var t1 := t0 + 2
		var b1 := t0 + 3
		indices.append(t0)
		indices.append(b0)
		indices.append(t1)
		indices.append(b0)
		indices.append(b1)
		indices.append(t1)

## Ajoute le **rebord horizontal** d'un côté : bande entre la limite de la carte
## (niveau exact des hauteurs de bord) et `lip_distance` vers l'extérieur.
## Normales vers le haut, couleur roche plus claire que la paroi. Les coins sont
## miterés : le premier/dernier sommet externe recule de `lip_distance` le long
## du bord, ce qui partage l'arête de coin avec la bande perpendiculaire (pas de
## trou ni de recouvrement coplanaire).
func _append_cliff_lip(
	verts: Array,
	normals: Array,
	colors: Array,
	indices: Array,
	side: String,
	cell_size: float,
	lip_distance: float
) -> void:
	var horizontal := side == "north" or side == "south"
	var segment_count := _terrain_w if horizontal else _terrain_h
	var first_index := verts.size()
	for k in range(segment_count + 1):
		var along_pos := float(k) * cell_size
		var top_y := 0.0
		if horizontal:
			var edge_j := 0 if side == "north" else _terrain_h
			top_y = _vertex_height(k, edge_j) * cell_size
		else:
			var edge_i := 0 if side == "west" else _terrain_w
			top_y = _vertex_height(edge_i, k) * cell_size
		var inner := _cliff_lip_inner_position(side, along_pos, top_y, cell_size)
		# Miter : aux extrémités, le sommet externe recule de lip_distance.
		var outer_along := along_pos
		if k == 0:
			outer_along = -lip_distance
		elif k == segment_count:
			outer_along = float(segment_count) * cell_size + lip_distance
		var outer := _cliff_lip_outer_position(side, outer_along, top_y, lip_distance, cell_size)
		verts.append(inner)
		verts.append(outer)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		var col := _cliff_lip_color(top_y, k)
		colors.append(col)
		colors.append(col)
	for k in range(segment_count):
		var i0 := first_index + k * 2
		var o0 := i0 + 1
		var i1 := i0 + 2
		var o1 := i0 + 3
		indices.append(i0)
		indices.append(o0)
		indices.append(i1)
		indices.append(o0)
		indices.append(o1)
		indices.append(i1)

## Position monde du bord **intérieur** du rebord (limite de la carte).
func _cliff_lip_inner_position(side: String, along_pos: float, top_y: float, cell_size: float) -> Vector3:
	match side:
		"north":
			return Vector3(along_pos, top_y, 0.0)
		"south":
			return Vector3(along_pos, top_y, float(_terrain_h) * cell_size)
		"west":
			return Vector3(0.0, top_y, along_pos)
		"east":
			return Vector3(float(_terrain_w) * cell_size, top_y, along_pos)
	return Vector3(along_pos, top_y, 0.0)

## Position monde du bord **extérieur** du rebord.
func _cliff_lip_outer_position(
	side: String,
	along_pos: float,
	top_y: float,
	lip_distance: float,
	cell_size: float
) -> Vector3:
	match side:
		"north":
			return Vector3(along_pos, top_y, -lip_distance)
		"south":
			return Vector3(along_pos, top_y, float(_terrain_h) * cell_size + lip_distance)
		"west":
			return Vector3(-lip_distance, top_y, along_pos)
		"east":
			return Vector3(float(_terrain_w) * cell_size + lip_distance, top_y, along_pos)
	return Vector3(along_pos, top_y, 0.0)

## Couleur du rebord : roche plus claire que la paroi, variation douce.
func _cliff_lip_color(world_y: float, along: int) -> Color:
	var col := CLIFF_LIP
	var variation := _terrain_variation(along, int(world_y * 3.0)) * CLIFF_LIP_VARIATION
	if variation > 0.0:
		col = col.lightened(variation)
	else:
		col = col.darkened(-variation)
	col.a = 1.0
	return col

## Position monde d'un sommet de bande de falaise (X/Z selon le côté, Y fourni).
func _cliff_side_position(side: String, along_pos: float, top_y: float, outset: float, cell_size: float) -> Vector3:
	match side:
		"north":
			return Vector3(along_pos, top_y, -outset)
		"south":
			return Vector3(along_pos, top_y, float(_terrain_h) * cell_size + outset)
		"west":
			return Vector3(-outset, top_y, along_pos)
		"east":
			return Vector3(float(_terrain_w) * cell_size + outset, top_y, along_pos)
	return Vector3(along_pos, top_y, 0.0)

## Couleur d'une strate de falaise : roche brun-gris éclaircie par des strates
## horizontales douces, assombrie en profondeur.
func _cliff_vertex_color(world_y: float, depth_frac: float, along: int) -> Color:
	var strata := sin(world_y * 4.5 + float(along) * 0.8) * 0.5 + 0.5
	var col := CLIFF_ROCK.lerp(CLIFF_ROCK_LIGHT, strata * 0.65)
	var shade := lerpf(1.0, 0.68, clampf(depth_frac, 0.0, 1.0))
	col = Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
	var variation := _terrain_variation(along, int(world_y * 2.0)) * CLIFF_STRATA_GAIN * 0.25
	if variation > 0.0:
		col = col.lightened(variation)
	else:
		col = col.darkened(-variation)
	col.a = 1.0
	return col

## Matériau de la jupe : roche éclairée, vertex colors (strates), cull désactivé.
func _make_cliff_material(night_mode: bool) -> StandardMaterial3D:
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
	return mat

func get_map_extent() -> Vector2:
	return _extent
