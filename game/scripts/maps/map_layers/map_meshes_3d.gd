extends Node3D
class_name MapMeshes3D

## Objets 3D génériques (kind « mesh ») posés sur la carte 2.5D.
##
## Chaque entrée de `map_data["meshes"]` référence une scène 3D importée
## (`res://assets/objects3d/<catégorie>/<nom>.glb`), instanciée telle quelle
## puis positionnée sur la grille :
##   • `x` / `y` en cases — le pivot de l'objet est posé au centre de la case ;
##   • `elevation` en cases — hauteur du pied de l'objet au-dessus du sol ;
##   • `display.rotation` en degrés (convention des décors : lacet inversé) ;
##   • `display.scale` — facteur appliqué en plus de la taille de case.
##
## L'échelle racine vaut `cell_size * display.scale` : un modèle 3D dont une
## unité = une case se pose donc directement sur la grille.
##
## **Fallback** : si l'asset est vide, introuvable ou illisible (typiquement en
## headless avant import des GLB), une boîte neutre est posée au sol à la place
## pour que la carte reste lisible et testable sans dépendre d'un asset.
##
## **Relief de terrain (M6, façon Rust / Fallout 76)** : si
## `map_data["terrainHeights"]` a un relief non nul, chaque objet **suit le sol**
## (option `followTerrain`, défaut `true`) :
##   • échantillonnage de la hauteur au centre et aux 4 coins de l'empreinte
##     (`w`/`h` en cases) et pose de la racine sur la hauteur **maximale**
##     (`base_y`), pour ne jamais s'enterrer ; un objet **droit** (bâtiment) se
##     pose sur la hauteur moyenne de son empreinte et reste vertical ;
##   • si `tiltToTerrain = true` (rochers, arbres…) et au-delà de
##     `SLOPE_INCLINE_THRESHOLD_DEG` de pente, l'objet est incliné pour aligner
##     son axe +Y sur `terrain_normal_at`, en conservant le lacet
##     `display.rotation` ;
##   • l'ombre de contact reste horizontale et se pose à `base_y + 0.02` monde.
## `followTerrain = false` → comportement historique (pied sur le plan y=0).
##
## **Ombre de contact peinte** : chaque mesh reçoit un quad horizontal à peine
## au-dessus du sol, avec un dégradé radial alpha, dimensionné sur l'empreinte
## XZ de l'objet. Sans elle, un objet posé sur une illustration 2.5D « flotte ».
##
## **Ambiance** : seul le volume de substitution est teinté par
## `MapRenderStyleScript.atmosphere_color()` (facteur léger) — teinter les
## matériaux importés des GLB demanderait de dupliquer chaque matériau de la
## scène (risque de casser les shaders/ressources importés) : laissé en TODO
## phase 2, voir `_build_fallback()`.
##
## Ombres coupées (rendu 2.5D léger) et aucune collision : ce calque est
## purement décoratif.

const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")
## Chargement des objets 3D : GLB livrés (importés par Godot, via ResourceLoader)
## ET GLB utilisateur déposés dans user:// (non importés, via GLTFDocument).
const MapAssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const ProceduralWallMeshScript := preload("res://scripts/maps/construction/procedural_wall_mesh.gd")

## Couleur neutre du volume de substitution (#8a7a60).
const FALLBACK_COLOR := Color(0.541176, 0.478431, 0.376471)
## Dimensions du volume de substitution, en unités locales (cases).
const FALLBACK_BOX_SIZE := Vector3(0.9, 1.0, 0.9)
## Hauteur monde de l'ombre de contact au-dessus du sol (unités monde).
const CONTACT_SHADOW_HEIGHT := 0.02
## Opacité au centre de l'ombre de contact (dégradé doux vers les bords).
const CONTACT_SHADOW_OPACITY := 0.25
## Pente (en degrés) au-delà de laquelle l'objet s'incline sur le terrain.
const SLOPE_INCLINE_THRESHOLD_DEG := 8.0
## Seuil sous lequel une case de relief est considérée comme plate.
const TERRAIN_RELIEF_EPSILON := 0.001

var _cell_size: float = 1.0
## id → nœud racine (Node3D) du mesh, pour le déplacement live.
var _nodes: Dictionary = {}
## id → donnée source du mesh (pour reposer au sol sur relief en drag live).
var _mesh_entries: Dictionary = {}
## Relief : hauteurs par case (tableau plat, convention grille centrée case).
var _terrain_heights: Array = []
var _terrain_w: int = 0
var _terrain_h: int = 0
var _terrain_relief: bool = false
## Teinte d'ambiance du style de rendu (diorama/VTT), pour le fallback.
var _atmosphere: Color = Color(0.10, 0.10, 0.14)
var _has_atmosphere: bool = false
## Rendu non éclairé : en 2.5D l'illustration porte déjà l'éclairage, et les
## matériaux importés (PBR) assombriraient l'objet par rapport au décor peint.
## Les couleurs/AO viennent des vertex colors exportés par Blender.
var _unshaded: bool = true
## Texture radiale partagée par toutes les ombres de contact du calque.
var _shadow_texture: GradientTexture2D = null

## Reconstruit le calque. `map_data` est accepté pour cohérence avec les autres
## calques (MapProps3D) ; il sert à la teinte d'ambiance du fallback et à savoir
## si le style éclaire les objets (VTT) ou non (diorama/DD2, rendu peint).
func configure(meshes: Array, cell_size: float, map_data: Dictionary = {}) -> void:
	_cell_size = cell_size if cell_size > 0.0 else 1.0
	_has_atmosphere = not map_data.is_empty()
	_atmosphere = MapRenderStyleScript.atmosphere_color(map_data) if _has_atmosphere else Color(0.10, 0.10, 0.14)
	_unshaded = not bool(MapRenderStyleScript.config(map_data).get("litProps", false))
	_read_terrain(map_data)
	for child in get_children():
		remove_child(child)
		child.free()
	_nodes.clear()
	_mesh_entries.clear()
	for mesh_variant in meshes:
		if not mesh_variant is Dictionary:
			continue
		var mesh: Dictionary = mesh_variant
		if bool(mesh.get("hidden", false)):
			continue
		var node := _build_mesh(mesh)
		if node == null:
			continue
		add_child(node)
		_nodes[str(mesh.get("id", ""))] = node
		_mesh_entries[str(mesh.get("id", ""))] = mesh.duplicate(true)

## Met à jour le relief **sans reconstruire les objets** (pinceau de relief de
## l'éditeur, appelé à chaque mouvement : les GLB ne sont pas réinstanciés).
## Repose les racines existantes sur les nouvelles hauteurs et réévalue
## l'inclinaison + l'ombre de contact.
func set_terrain_heights(terrain_heights: Array, map_size: Vector2i = Vector2i.ZERO) -> void:
	var data := {
		"width": map_size.x if map_size.x > 0 else _terrain_w,
		"height": map_size.y if map_size.y > 0 else _terrain_h,
		"terrainHeights": terrain_heights,
	}
	_read_terrain(data)
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var entry: Dictionary = _mesh_entries.get(id, {})
		if node == null or not is_instance_valid(node) or entry.is_empty():
			continue
		_place_root(node, entry)
		var shadow := _find_child_with_meta(node, "contact_shadow")
		if shadow is Node3D:
			_repose_contact_shadow(node, shadow as Node3D, _is_inclined(entry))

## Lit le relief fourni par le document (`terrainHeights` + dimensions carte).
## Tableau absent / mal dimensionné → terrain plat (comportement historique).
func _read_terrain(map_data: Dictionary) -> void:
	_terrain_heights = []
	_terrain_w = maxi(0, int(map_data.get("width", 0)))
	_terrain_h = maxi(0, int(map_data.get("height", 0)))
	_terrain_relief = false
	if _terrain_w <= 0 or _terrain_h <= 0:
		return
	var raw = map_data.get("terrainHeights", [])
	if not (raw is Array) or (raw as Array).size() != _terrain_w * _terrain_h:
		return
	_terrain_heights = raw
	for value in _terrain_heights:
		if absf(float(value)) > TERRAIN_RELIEF_EPSILON:
			_terrain_relief = true
			return

## Hauteur du terrain (en cases) aux coordonnées grille **centrées case** —
## même convention que `ComplexMapEngine3D.terrain_height_at` (entier = centre
## de case, interpolation bilinéaire entre centres, 0 hors carte).
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

## Normale du terrain aux coordonnées grille (voir `terrain_normal_at` moteur).
func _terrain_normal_at(gx: float, gy: float) -> Vector3:
	if not _terrain_relief:
		return Vector3.UP
	const STEP := 0.5
	var dhdx := (_terrain_height_at(gx + STEP, gy) - _terrain_height_at(gx - STEP, gy)) / (2.0 * STEP)
	var dhdz := (_terrain_height_at(gx, gy + STEP) - _terrain_height_at(gx, gy - STEP)) / (2.0 * STEP)
	if absf(dhdx) < TERRAIN_RELIEF_EPSILON and absf(dhdz) < TERRAIN_RELIEF_EPSILON:
		return Vector3.UP
	return Vector3(-dhdx, 1.0, -dhdz).normalized()

## Pente en degrés à partir d'une normale (0 = plat).
func _slope_degrees(normal: Vector3) -> float:
	return rad_to_deg(acos(clampf(normal.normalized().y, -1.0, 1.0)))

## Empreinte au sol du mesh, en cases (centre + 4 coins échantillonnés).
func _mesh_footprint(mesh: Dictionary) -> Vector2:
	return Vector2(
		maxf(0.01, float(mesh.get("w", 1.0))),
		maxf(0.01, float(mesh.get("h", 1.0)))
	)

## Hauteur monde de la base sur le terrain. Objet **incliné** : max des hauteurs
## sous l'empreinte (le point haut porte l'objet). Objet **droit** (bâtiments) :
## moyenne des hauteurs, pour s'asseoir dans la pente sans flotter d'un côté.
func _terrain_base_y(mesh: Dictionary) -> float:
	if not _terrain_relief:
		return 0.0
	var gx := float(mesh.get("x", 0.0))
	var gy := float(mesh.get("y", 0.0))
	var footprint := _mesh_footprint(mesh)
	var half := footprint * 0.5
	var samples := [
		_terrain_height_at(gx, gy),
		_terrain_height_at(gx - half.x, gy - half.y),
		_terrain_height_at(gx + half.x, gy - half.y),
		_terrain_height_at(gx - half.x, gy + half.y),
		_terrain_height_at(gx + half.x, gy + half.y),
	]
	if _is_inclined(mesh):
		var best := 0.0
		for value in samples:
			best = maxf(best, float(value))
		return best * _cell_size
	var total := 0.0
	for value in samples:
		total += float(value)
	return (total / float(samples.size())) * _cell_size

## Repère de rotation qui aligne +Y sur `up` (normale du terrain) en conservant
## le lacet demandé autour de cet axe.
func _basis_with_up(up: Vector3, yaw: float) -> Basis:
	var up_n := up.normalized()
	var forward := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
	forward = forward - up_n * forward.dot(up_n)
	if forward.length() < 0.001:
		forward = Vector3(0, 0, 1) - up_n * up_n.z
		if forward.length() < 0.001:
			forward = Vector3(1, 0, 0)
	forward = forward.normalized()
	var right := up_n.cross(forward).normalized()
	return Basis(right, up_n, right.cross(up_n))

func _build_mesh(mesh: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(mesh.get("id", "mesh")) if not str(mesh.get("id", "")).is_empty() else "Mesh"
	var asset_path := str(mesh.get("asset", ""))
	var visual: Node = null
	if asset_path.begins_with("procedural://"):
		var visual_mesh := _build_procedural_visual(mesh)
		if visual_mesh != null:
			visual = visual_mesh
	else:
		visual = _instantiate_asset(asset_path)
	var fallback := visual == null
	if fallback:
		visual = _build_fallback()
	root.add_child(visual)
	root.set_meta("visual", visual)
	_place_root(root, mesh)
	# Lanterne : petite lumière d'ambiance au sommet (le GLB porte déjà
	# l'émission du verre, on ajoute juste la lueur qui éclaire le sol).
	if str(mesh.get("asset", "")).contains("lanterne"):
		var light := OmniLight3D.new()
		var top := _visual_aabb(visual).size.y
		light.position = Vector3(0.0, top * 0.85, 0.0)
		light.light_color = Color(1.0, 0.78, 0.45)
		light.light_energy = 1.4
		light.omni_range = 3.2
		light.shadow_enabled = false
		root.add_child(light)
	# Rendu 2.5D léger : aucune ombre portée, aucune collision.
	_sanitize_visual(visual)
	# Ombre de contact peinte : ancre l'objet sur le décor (pas d'effet « flottant »).
	_add_contact_shadow(root, visual, _is_inclined(mesh))
	root.set_meta("fallback", fallback)
	return root

func _build_procedural_visual(mesh: Dictionary) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ProceduralWall"
	mesh_instance.mesh = ProceduralWallMeshScript.build_from_element(mesh)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(str(mesh.get("color", "#a89d88")))
	material.roughness = 0.92
	material.metallic = 0.0
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance

## Facteurs d'échelle par axe pour obtenir les dimensions déclarées (en cases).
## `sizeX`/`sizeY`/`sizeZ` permettent de redimensionner un objet 3D par axe
## (calculées depuis l'AABB du GLB à la pose, éditables dans l'inspecteur).
func _mesh_dimensions(mesh: Dictionary, visual: Node) -> Vector3:
	var sx := float(mesh.get("sizeX", 0.0))
	var sy := float(mesh.get("sizeY", 0.0))
	var sz := float(mesh.get("sizeZ", 0.0))
	if sx <= 0.0 and sy <= 0.0 and sz <= 0.0:
		return Vector3.ZERO
	var display: Dictionary = mesh.get("display", {}) if mesh.get("display") is Dictionary else {}
	var display_scale := maxf(0.01, float(display.get("scale", 1.0)))
	var natural := _visual_aabb(visual).size
	var out := Vector3.ONE * display_scale
	if sx > 0.0:
		out.x = sx / maxf(0.001, natural.x)
	if sy > 0.0:
		out.y = sy / maxf(0.001, natural.y)
	if sz > 0.0:
		out.z = sz / maxf(0.001, natural.z)
	return out

## Pose / repose la racine d'un mesh : pied sur le terrain (hauteur **moyenne**
## de l'empreinte pour un bâtiment droit, **maximale** pour un objet incliné via
## `tiltToTerrain`), élévation, puis inclinaison si la pente dépasse le seuil.
func _place_root(root: Node3D, mesh: Dictionary) -> void:
	var display: Dictionary = mesh.get("display", {}) if mesh.get("display") is Dictionary else {}
	var display_scale := maxf(0.01, float(display.get("scale", 1.0)))
	var gx := float(mesh.get("x", 0.0))
	var gy := float(mesh.get("y", 0.0))
	var elevation := float(mesh.get("elevation", 0.0)) * _cell_size
	var base_y := _terrain_base_y(mesh) if _follows_terrain(mesh) else 0.0
	var yaw := -float(display.get("rotation", 0.0))
	var visual: Node = root.get_meta("visual", null) if root.has_meta("visual") else null
	var dimensions := _mesh_dimensions(mesh, visual) if visual != null else Vector3.ZERO
	var scale_vec: Vector3
	if dimensions == Vector3.ZERO:
		scale_vec = Vector3.ONE * _cell_size * display_scale
	else:
		# Dimensions en cases ; l'unité de l'asset vaut 1 case (world = cases * cell).
		scale_vec = dimensions * _cell_size
	root.position = Vector3(
		gx * _cell_size + _cell_size * 0.5,
		base_y + elevation,
		gy * _cell_size + _cell_size * 0.5
	)
	if _is_inclined(mesh):
		var normal := _terrain_normal_at(gx, gy)
		var basis := _basis_with_up(normal, deg_to_rad(yaw))
		root.transform = Transform3D(basis.scaled(scale_vec), root.position)
	else:
		root.rotation_degrees = Vector3(0.0, yaw, 0.0)
		root.scale = scale_vec

## Vrai si ce mesh doit suivre le terrain (option par objet, défaut oui).
func _follows_terrain(mesh: Dictionary) -> bool:
	return _terrain_relief and bool(mesh.get("followTerrain", true))

## Vrai si le mesh doit être incliné : relief suivi + option `tiltToTerrain`
## activée (défaut false : les bâtiments restent droits, même en pente) + pente > seuil.
func _is_inclined(mesh: Dictionary) -> bool:
	if not _follows_terrain(mesh):
		return false
	if not bool(mesh.get("tiltToTerrain", false)):
		return false
	var normal := _terrain_normal_at(float(mesh.get("x", 0.0)), float(mesh.get("y", 0.0)))
	return _slope_degrees(normal) > SLOPE_INCLINE_THRESHOLD_DEG

## Instancie l'asset comme scène 3D, qu'il soit livré et importé par Godot
## (res://) ou importé par l'utilisateur dans user:// (GLTFDocument/GLTFState).
## Renvoie null si vide / introuvable / illisible / non-3D (fallback).
func _instantiate_asset(asset_path: String) -> Node3D:
	var path := asset_path.strip_edges()
	if path.is_empty():
		return null
	return MapAssetLibraryScript.instantiate_object3d_scene(path)

## Volume de substitution : boîte neutre non éclairée, pied au sol, dimensionnée
## en unités locales (donc mise à l'échelle par la racine comme un vrai asset).
func _build_fallback() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = FALLBACK_BOX_SIZE
	mesh_instance.mesh = box
	# Le pivot de la boîte est en son centre : on la remonte d'une demi-hauteur
	# pour que sa base repose exactement sur le plan du sol.
	mesh_instance.position.y = box.size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _fallback_color()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.roughness = 1.0
	mesh_instance.material_override = mat
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.set_meta("fallback", true)
	return mesh_instance

## Teinte du volume de substitution : couleur neutre légèrement fondue dans
## l'ambiance du style, pour que le fallback reste cohérent avec le décor peint.
## TODO phase 2 : appliquer la même logique (`depth_tint`) aux matériaux
## *importés* des GLB — cela exige de dupliquer chaque matériau de la scène et
## donc de risquer de casser les shaders/ressources partagées importées.
func _fallback_color() -> Color:
	if not _has_atmosphere:
		return FALLBACK_COLOR
	return FALLBACK_COLOR.lerp(_atmosphere, 0.15)

## Ajoute l'ombre de contact peinte : quad horizontal alpha, dégradé radial,
## centré sur l'empreinte XZ réelle du mesh, posé à `CONTACT_SHADOW_HEIGHT`
## unités monde au-dessus de la **base de l'objet** (donc au-dessus du terrain,
## pas du plan y=0). Sur une pente, l'ombre reste horizontale (le parent est
## incliné : on contre-rotations dans son repère).
func _add_contact_shadow(root: Node3D, visual: Node, inclined: bool = false) -> void:
	var bounds := _visual_aabb(visual)
	var footprint := Vector2(bounds.size.x, bounds.size.z)
	if footprint.x <= 0.001 or footprint.y <= 0.001:
		# Scène sans géométrie mesurable : empreinte par défaut d'une case.
		footprint = Vector2(FALLBACK_BOX_SIZE.x, FALLBACK_BOX_SIZE.z)
	var center := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.z + bounds.size.z * 0.5)

	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = footprint
	shadow.mesh = quad
	# Quad XY → couché sur XZ, face vers le haut (même convention que les décors
	# à plat de MapProps3D).
	shadow.material_override = _contact_shadow_material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.set_meta("contact_shadow", true)
	shadow.set_meta("contact_center", center)
	shadow.set_meta("shadow_inclined", inclined)
	root.add_child(shadow)
	_repose_contact_shadow(root, shadow, inclined)

## Repositionne / réoriente l'ombre de contact après un déplacement ou un
## changement de pente. Toujours horizontale en monde, `CONTACT_SHADOW_HEIGHT`
## au-dessus de la base de la racine.
func _repose_contact_shadow(root: Node3D, shadow: Node3D, inclined: bool) -> void:
	var center: Vector2 = shadow.get_meta("contact_center", Vector2.ZERO)
	# Décalage vertical monde constant : compensé par l'échelle/rotation racine.
	var vertical_local: Vector3 = root.transform.basis.inverse() * Vector3(0.0, CONTACT_SHADOW_HEIGHT, 0.0)
	shadow.position = Vector3(
		center.x + vertical_local.x,
		vertical_local.y,
		center.y + vertical_local.z
	)
	var flat_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	if inclined:
		# La racine est inclinée : annuler sa rotation pour garder l'ombre à plat.
		var parent_rot := root.transform.basis.orthonormalized()
		shadow.transform = Transform3D(parent_rot.inverse() * flat_basis, shadow.position)
	else:
		shadow.transform = Transform3D(flat_basis, shadow.position)

## Matériau de l'ombre de contact : dégradé radial noir doux, alpha, non éclairé.
func _contact_shadow_material() -> StandardMaterial3D:
	if _shadow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.0, 0.0, 0.0, CONTACT_SHADOW_OPACITY))
		gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		if gradient.get_point_count() < 3:
			gradient.add_point(0.55, Color(0.0, 0.0, 0.0, CONTACT_SHADOW_OPACITY * 0.55))
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_shadow_texture = tex
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _shadow_texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Très bas : passe avant les matériaux des décors et des meshes.
	mat.render_priority = -16
	return mat

## Boîte englobante des géométries du mesh, exprimée dans le repère de la racine.
func _visual_aabb(visual: Node) -> AABB:
	var boxes: Array = []
	_collect_mesh_aabbs(visual, Transform3D.IDENTITY, boxes)
	if boxes.is_empty():
		return AABB()
	var combined: AABB = boxes[0]
	for i in range(1, boxes.size()):
		combined = combined.merge(boxes[i])
	return combined

func _collect_mesh_aabbs(node: Node, xform: Transform3D, boxes: Array) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			boxes.append(xform * mesh_instance.get_aabb())
	for child in node.get_children():
		var child_xform := xform * (child as Node3D).transform if child is Node3D else xform
		_collect_mesh_aabbs(child, child_xform, boxes)

## Coupe les ombres, neutralise les collisions et, en 2.5D, passe les matériaux
## importés en non éclairé : la palette et l'AO viennent de Blender (vertex
## colors), l'illustration porte déjà la lumière. En VTT, on garde l'éclairage.
func _sanitize_visual(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if _unshaded and node is MeshInstance3D:
		_apply_unshaded_materials(node as MeshInstance3D)
	for child in node.get_children():
		_sanitize_visual(child)

## Duplique les matériaux par surface et les passe en `UNSHADED`, en activant
## les vertex colors comme albédo (mottling + AO cuits par le pipeline Blender).
## La duplication évite de modifier les ressources partagées entre instances.
func _apply_unshaded_materials(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	var surface_count := mesh_instance.mesh.get_surface_count()
	for i in range(surface_count):
		var source := mesh_instance.get_active_material(i)
		if source is StandardMaterial3D:
			var material: StandardMaterial3D = (source as StandardMaterial3D).duplicate()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.vertex_color_use_as_albedo = true
			material.cull_mode = BaseMaterial3D.CULL_BACK
			mesh_instance.set_surface_override_material(i, material)
		elif source != null:
			# Matériau exotique : on le laisse tel quel plutôt que de le casser.
			pass

## Repositionne un mesh sans reconstruire la scène (glisser en cours).
## Sur relief, le pied est reposé sur la nouvelle hauteur et l'inclinaison
## réévaluée ; sur terrain plat, comportement historique (x/z seulement).
func set_mesh_position(mesh_id: String, gx: float, gy: float) -> void:
	if not _nodes.has(mesh_id):
		return
	var node: Node3D = _nodes[mesh_id]
	var entry: Dictionary = _mesh_entries.get(mesh_id, {})
	if not entry.is_empty():
		entry["x"] = gx
		entry["y"] = gy
		_mesh_entries[mesh_id] = entry
		if _terrain_relief:
			_place_root(node, entry)
			var shadow := _find_child_with_meta(node, "contact_shadow")
			if shadow is Node3D:
				_repose_contact_shadow(node, shadow as Node3D, _is_inclined(entry))
			return
	node.position.x = gx * _cell_size + _cell_size * 0.5
	node.position.z = gy * _cell_size + _cell_size * 0.5

## Premier descendant portant le meta demandé (null si absent).
func _find_child_with_meta(node: Node, meta_name: String) -> Node:
	if node == null:
		return null
	for child in node.get_children():
		if child.has_meta(meta_name):
			return child
		var nested := _find_child_with_meta(child, meta_name)
		if nested != null:
			return nested
	return null

func has_mesh(mesh_id: String) -> bool:
	return _nodes.has(mesh_id)

## Vrai si le mesh `mesh_id` est rendu par le volume de substitution.
func is_fallback(mesh_id: String) -> bool:
	if not _nodes.has(mesh_id):
		return false
	return bool((_nodes[mesh_id] as Node).get_meta("fallback", false))
