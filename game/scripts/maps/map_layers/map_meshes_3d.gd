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
const ProceduralFlowerZoneScript := preload("res://scripts/maps/construction/procedural_flower_zone.gd")
const ProceduralRoofMeshScript := preload("res://scripts/maps/construction/procedural_roof_mesh.gd")
const ProceduralWallShader := preload("res://shaders/procedural_wall.gdshader")
const ProceduralRoofShader := preload("res://shaders/procedural_roof.gdshader")
const PathRibbonShader := preload("res://shaders/path_ribbon.gdshader")
const ProceduralFloorMeshScript := preload("res://scripts/maps/construction/procedural_floor_mesh.gd")
const ProceduralFenceMeshScript := preload("res://scripts/maps/construction/procedural_fence_mesh.gd")
const ProceduralPathMeshScript := preload("res://scripts/maps/construction/procedural_path_mesh.gd")
const ProceduralTentMeshScript := preload("res://scripts/maps/construction/procedural_tent_mesh.gd")
const ProceduralCampfireMeshScript := preload("res://scripts/maps/construction/procedural_campfire_mesh.gd")
const ProceduralPolyRoofScript := preload("res://scripts/maps/construction/procedural_poly_roof.gd")
const ProceduralRockMeshScript := preload("res://scripts/maps/construction/procedural_rock_mesh.gd")

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
## id → transparence d'occlusion courante (pour éviter les changements inutiles).
var _occlusion_alpha: Dictionary = {}
## id → cible de fondu d'occlusion.
var _occlusion_targets: Dictionary = {}
## Lumières de feu de camp à faire scintiller.
var _fire_lights: Array = []
var _fire_time: float = 0.0
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
	_fire_lights.clear()
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
		var visual: Node = node.get_meta("visual", null) if node.has_meta("visual") else null
		if visual is MeshInstance3D and visual.has_meta("flat_mesh"):
			_rebake_procedural_visual(visual as MeshInstance3D, entry)
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
	# Les chemins texturés sont déjà posés au ras du terrain : pas d'ombre ajoutée.
	if not (visual is Node and visual.has_meta("world_space")):
		_add_contact_shadow(root, visual, _is_inclined(mesh))
	root.set_meta("fallback", fallback)
	# Décor léger : culling de distance pour les grandes cartes.
	if asset_path.contains("/vegetation/") or asset_path.contains("/props/"):
		_set_visibility_range(visual, 90.0)
	return root

func _set_visibility_range(node: Node, distance: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = distance
		(node as GeometryInstance3D).visibility_range_end_margin = 5.0
	for child in node.get_children():
		_set_visibility_range(child, distance)

func _build_procedural_visual(mesh: Dictionary) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	var asset := str(mesh.get("asset", ""))
	var material := StandardMaterial3D.new()
	if asset == "procedural://rock":
		mesh_instance.name = "ProceduralRock"
		mesh_instance.mesh = ProceduralRockMeshScript.build(
			int(mesh.get("seed", 1)), int(mesh.get("detail", 14))
		)
		material.albedo_color = Color("#7d7668")
		material.roughness = 0.98
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif asset == "procedural://poly_roof":
		mesh_instance.name = "ProceduralPolyRoof"
		mesh_instance.mesh = ProceduralPolyRoofScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.85
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif asset == "procedural://campfire":
		mesh_instance.name = "ProceduralCampfire"
		mesh_instance.mesh = ProceduralCampfireMeshScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.9
		material.emission_enabled = true
		material.emission = Color("#e07a2f")
		material.emission_energy_multiplier = 0.6
		var fire_light := OmniLight3D.new()
		fire_light.position = Vector3(0.0, 0.55, 0.0)
		fire_light.light_color = Color("#ff9a4a")
		fire_light.light_energy = 1.5
		fire_light.omni_range = 3.2
		fire_light.shadow_enabled = false
		mesh_instance.add_child(fire_light)
		_fire_lights.append(fire_light)
	elif asset == "procedural://tent":
		mesh_instance.name = "ProceduralTent"
		mesh_instance.mesh = ProceduralTentMeshScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif asset == "procedural://path_texture":
		mesh_instance.name = "ProceduralPathTextured"
		mesh_instance.mesh = _build_textured_path_mesh(mesh)
		mesh_instance.set_meta("terrain_baked", true)
		mesh_instance.set_meta("world_space", true)
		var path_mat := ShaderMaterial.new()
		path_mat.shader = PathRibbonShader
		path_mat.set_shader_parameter("albedo_tex", _path_material_texture(int(mesh.get("material", 1))))
		path_mat.set_shader_parameter("tint", _path_material_tint(int(mesh.get("material", 1))))
		path_mat.set_shader_parameter("tex_scale", 1.0)
		mesh_instance.material_override = path_mat
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mesh_instance
	elif asset == "procedural://path":
		mesh_instance.name = "ProceduralPath"
		mesh_instance.mesh = ProceduralPathMeshScript.build_from_element(mesh, _path_detail_for(mesh))
		material.albedo_color = Color.html(str(mesh.get("color", "#8a7654"))).darkened(0.12)
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif asset == "procedural://fence":
		mesh_instance.name = "ProceduralFence"
		mesh_instance.mesh = ProceduralFenceMeshScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.9
	elif asset == "procedural://floor":
		mesh_instance.name = "ProceduralFloor"
		mesh_instance.mesh = ProceduralFloorMeshScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.9
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif asset == "procedural://flower_zone":
		mesh_instance.name = "ProceduralFlowerZone"
		mesh_instance.mesh = ProceduralFlowerZoneScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.9
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif asset == "procedural://roof":
		mesh_instance.name = "ProceduralRoof"
		mesh_instance.mesh = ProceduralRoofMeshScript.build_from_element(mesh)
		var roof_material := ShaderMaterial.new()
		roof_material.shader = ProceduralRoofShader
		mesh_instance.material_override = roof_material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mesh_instance
	else:
		mesh_instance.name = "ProceduralWall"
		mesh_instance.mesh = ProceduralWallMeshScript.build_from_element(mesh)
		var wall_material := ShaderMaterial.new()
		wall_material.shader = ProceduralWallShader
		wall_material.set_shader_parameter("base_color", Color.html(str(mesh.get("color", "#a89d88"))))
		mesh_instance.material_override = wall_material
		_conform_procedural_mesh(mesh_instance, mesh)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mesh_instance
	mesh_instance.material_override = material
	_conform_procedural_mesh(mesh_instance, mesh)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Petits décors procéduraux : culling de distance pour les grandes cartes.
	if asset in ["procedural://flower_zone", "procedural://tent", "procedural://campfire"]:
		mesh_instance.visibility_range_end = 70.0
		mesh_instance.visibility_range_end_margin = 5.0
	return mesh_instance

## Estompe les murs/bâtiments situés entre la caméra et le personnage, pour
## qu'il ne disparaisse pas derrière une façade. Approximation par distance au
## segment caméra → personnage, sans raycast physique.
func set_occlusion_fade(camera_pos: Vector3, target_pos: Vector3) -> void:
	var from := camera_pos
	var to := target_pos
	var segment := to - from
	var length_sq := segment.length_squared()
	if length_sq < 0.01:
		return
	for id_variant in _nodes.keys():
		var id := str(id_variant)
		var root = _nodes.get(id)
		if root == null or not is_instance_valid(root):
			continue
		var entry: Dictionary = _mesh_entries.get(id, {}) if _mesh_entries.get(id) is Dictionary else {}
		var asset := str(entry.get("asset", "")).to_lower()
		var alpha := 0.0
		if _is_occludable_asset(asset):
			var center: Vector3 = root.global_position
			var t := clampf((center - from).dot(segment) / length_sq, 0.0, 1.0)
			var closest := from + segment * t
			var distance := center.distance_to(closest)
			if t > 0.04 and t < 0.96 and distance < 1.1:
				alpha = 0.42
		_occlusion_targets[id] = alpha

func _process(delta: float) -> void:
	if not _fire_lights.is_empty():
		_fire_time += delta
		for i in range(_fire_lights.size()):
			var light = _fire_lights[i]
			if light == null or not is_instance_valid(light):
				continue
			light.light_energy = 1.35 + 0.22 * sin(_fire_time * 8.0 + float(i) * 1.7)
	if _occlusion_targets.is_empty():
		return
	for id_variant in _occlusion_targets.keys():
		var id := str(id_variant)
		var root = _nodes.get(id)
		if root == null or not is_instance_valid(root):
			_occlusion_targets.erase(id)
			continue
		var target := float(_occlusion_targets[id])
		var current := float(root.get_meta("occlusion_alpha", target))
		var next := lerpf(current, target, clampf(delta * 10.0, 0.0, 1.0))
		if absf(next - target) < 0.01:
			next = target
		_apply_visual_transparency(root, next)

## Fait suivre le relief aux meshes procéduraux : chaque sommet est décalé à la
## hauteur du terrain sous sa position, en conservant sa hauteur relative.
func _conform_procedural_mesh(mesh_instance: MeshInstance3D, mesh: Dictionary) -> void:
	if not _follows_terrain(mesh) or not _terrain_relief:
		return
	if mesh_instance.has_meta("world_space"):
		return
	var source: ArrayMesh = null
	if mesh_instance.has_meta("flat_mesh"):
		source = mesh_instance.get_meta("flat_mesh") as ArrayMesh
	if source == null:
		source = mesh_instance.mesh as ArrayMesh
	if source == null:
		return
	if not mesh_instance.has_meta("flat_mesh"):
		mesh_instance.set_meta("flat_mesh", source)
	var center := Vector2(float(mesh.get("x", 0.0)), float(mesh.get("y", 0.0)))
	var result := ArrayMesh.new()
	for s in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var colors: PackedColorArray
		if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			colors = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
			indices = arrays[Mesh.ARRAY_INDEX]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var tri_count := indices.size() if not indices.is_empty() else vertices.size()
		for k in range(0, tri_count, 3):
			for n in range(3):
				var vi := indices[k + n] if not indices.is_empty() else k + n
				if vi < 0 or vi >= vertices.size():
					continue
				var v := vertices[vi]
				# La racine est posée au centre de case (+0.5) : on échantillonne
				# le terrain aux coordonnées grille réelles du sommet.
				var gx := center.x + 0.5 + v.x
				var gy := center.y + 0.5 + v.z
				# Hauteur absolue du terrain : la racine sera posée à y=0.
				v.y = _terrain_surface_height_at(gx, gy) + v.y
				if vi < colors.size():
					st.set_color(colors[vi])
				else:
					st.set_color(Color.WHITE)
				st.add_vertex(v)
		st.generate_normals()
		st.commit(result)
	mesh_instance.mesh = result
	mesh_instance.set_meta("terrain_baked", true)

## Après un changement de relief, repart du mesh plat d'origine puis le
## reconforme aux nouvelles hauteurs (clôture qui reste posée sur la colline).
func _rebake_procedural_visual(mesh_instance: MeshInstance3D, entry: Dictionary) -> void:
	if str(entry.get("asset", "")) == "procedural://path_texture":
		var rebuilt_texture := _build_textured_path_mesh(entry)
		mesh_instance.mesh = rebuilt_texture
		mesh_instance.set_meta("flat_mesh", rebuilt_texture)
		mesh_instance.set_meta("terrain_baked", true)
		return
	if str(entry.get("asset", "")) == "procedural://path":
		var rebuilt: ArrayMesh = ProceduralPathMeshScript.build_from_element(entry, _path_detail_for(entry))
		mesh_instance.mesh = rebuilt
		mesh_instance.set_meta("flat_mesh", rebuilt)
		mesh_instance.remove_meta("terrain_baked")
		if _terrain_relief and _follows_terrain(entry):
			_conform_procedural_mesh(mesh_instance, entry)
		return
	var flat := mesh_instance.get_meta("flat_mesh", null) as ArrayMesh
	if flat == null:
		return
	mesh_instance.mesh = flat
	mesh_instance.remove_meta("terrain_baked")
	if _terrain_relief and _follows_terrain(entry):
		_conform_procedural_mesh(mesh_instance, entry)

## Plus le terrain est pentu/accidenté sous le chemin, plus on subdivise.
func _path_detail_for(mesh: Dictionary) -> int:
	if not _terrain_relief:
		return 1
	var points: Array = mesh.get("points", [])
	if points.size() < 2:
		return 1
	var center := Vector2(float(mesh.get("x", 0.0)), float(mesh.get("y", 0.0)))
	var width := maxf(0.3, float(mesh.get("width", 1.2)))
	var roughness := 0.0
	var prev_h := 0.0
	for i in range(points.size()):
		var p := _mesh_point_to_vector(points[i]) + center + Vector2(0.5, 0.5)
		var h := _terrain_surface_height_at(p.x, p.y)
		if i > 0:
			roughness = maxf(roughness, absf(h - prev_h))
		prev_h = h
		var normal := _terrain_normal_at(p.x, p.y)
		roughness = maxf(roughness, (1.0 - normal.y) * width * 0.8)
	return clampi(1 + int(round(roughness * 9.0)), 1, 4)

func _mesh_point_to_vector(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

## Chemin texturé : ruban cuit en coordonnées **monde**, UV.x le long du tracé,
## UV.y en travers. Subdivisé en largeur pour que le centre soit opaque et les
## bords semi-transparents (COLOR.a) estompés par le shader `path_ribbon`.
const PATH_ACROSS := 4

func _build_textured_path_mesh(mesh: Dictionary) -> ArrayMesh:
	var raw_points: Array = mesh.get("points", [])
	if raw_points.size() < 2:
		return ArrayMesh.new()
	var width := maxf(0.3, float(mesh.get("width", 1.2)))
	var detail := clampi(_path_detail_for(mesh), 1, 4)
	var seed := int(mesh.get("seed", 1))
	var tile_length := 2.0

	var samples: Array[Vector2] = []
	for i in range(raw_points.size() - 1):
		var a := _mesh_point_to_vector(raw_points[i])
		var b := _mesh_point_to_vector(raw_points[i + 1])
		for k in range(detail):
			samples.append(a.lerp(b, float(k) / float(detail)))
	samples.append(_mesh_point_to_vector(raw_points[raw_points.size() - 1]))
	if samples.size() < 2:
		return ArrayMesh.new()

	# Longueur du tracé en cases, convertie en UV.x en unités monde.
	var distances: Array[float] = []
	var total := 0.0
	for i in range(samples.size()):
		if i > 0:
			total += samples[i - 1].distance_to(samples[i])
		distances.append(total)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_cross: Array = []
	var prev_u := 0.0
	for i in range(samples.size()):
		var dir := _path_dir_at(samples, i)
		var nrm := Vector2(-dir.y, dir.x)
		var u := distances[i] / tile_length
		var wl := 1.0 + 0.12 * sin(u * 9.0 + float(seed) * 0.7)
		var wr := 1.0 + 0.12 * sin(u * 11.0 + 1.9 + float(seed) * 0.5)
		var lp := samples[i] + nrm * width * 0.5 * wl
		var rp := samples[i] - nrm * width * 0.5 * wr
		# Points répartis en travers du ruban : le centre (s≈0.5) est opaque,
		# les bords (s=0 / s=1) fondent dans le terrain.
		var cross: Array = []
		for a in range(PATH_ACROSS):
			var t := float(a) / float(PATH_ACROSS - 1)
			var p := lp.lerp(rp, t)
			var w := _grid_point_to_world(p)
			# Le maillage rendu du terrain a ses sommets aux COINS des cases :
			# un point de grille `p` (centre de case) est donc au coin `p + 0.5`.
			var h := _terrain_surface_height_at(p.x + 0.5, p.y + 0.5) * _cell_size + 0.035
			cross.append({"pos": Vector3(w.x, h, w.y), "s": t})
		if i > 0:
			for a in range(PATH_ACROSS - 1):
				_add_path_strip(st,
					prev_cross[a]["pos"], prev_cross[a + 1]["pos"],
					cross[a + 1]["pos"], cross[a]["pos"],
					prev_u, u, prev_cross[a]["s"], prev_cross[a + 1]["s"], seed)
		prev_cross = cross
		prev_u = u
	st.generate_normals()
	return st.commit()

## Grille (centre de case) → coordonnées monde (le terrain est dessiné en unités
## monde, sommet de coin à `i * cell`, centre de case à `(i + 0.5) * cell`).
func _grid_point_to_world(p: Vector2) -> Vector2:
	return Vector2((p.x + 0.5) * _cell_size, (p.y + 0.5) * _cell_size)

## Quad entre deux sections transversales : `pl`/`pr` = section précédente
## (s0/s1), `r`/`l` = section courante (s1/s0).
func _add_path_strip(st: SurfaceTool, pl: Vector3, pr: Vector3, r: Vector3, l: Vector3,
		u0: float, u1: float, s0: float, s1: float, seed: int) -> void:
	_add_path_vertex(st, pl, Vector2(u0, s0), seed)
	_add_path_vertex(st, pr, Vector2(u0, s1), seed)
	_add_path_vertex(st, r, Vector2(u1, s1), seed)
	_add_path_vertex(st, pl, Vector2(u0, s0), seed)
	_add_path_vertex(st, r, Vector2(u1, s1), seed)
	_add_path_vertex(st, l, Vector2(u1, s0), seed)

func _add_path_vertex(st: SurfaceTool, pos: Vector3, uv: Vector2, seed: int) -> void:
	st.set_uv(uv)
	st.set_color(Color(1.0, 1.0, 1.0, _path_edge_alpha(uv.y, uv.x, seed)))
	st.add_vertex(pos)

## Alpha du bord : 1 au centre du ruban, 0 sur les bords, avec une frontière
## sinusoïdale qui ne suit pas une ligne droite le long du tracé.
func _path_edge_alpha(s: float, u: float, seed: int) -> float:
	var d := absf(s - 0.5) * 2.0
	var edge := clampf(
		0.72 + 0.07 * sin(u * 19.0 + float(seed) * 0.7) + 0.04 * sin(u * 37.0 + float(seed) * 1.3),
		0.55, 0.92
	)
	return 1.0 - smoothstep(edge, 1.0, d)

## Texture de chemin selon la matière : 1 = terre, 2 = pierre, 4 = sable.
func _path_material_texture(material_id: int) -> Texture2D:
	var path := "res://assets/terrain/dirt.png"
	match material_id:
		2:
			path = "res://assets/terrain/stone.png"
		4:
			path = "res://assets/terrain/sand.png"
	return load(path) as Texture2D

## Teinte de la matière de chemin (la texture de base reste reconnaissable).
func _path_material_tint(material_id: int) -> Color:
	match material_id:
		2:
			return Color(0.93, 0.91, 0.87)
		4:
			return Color(1.0, 0.96, 0.82)
	return Color(1.0, 1.0, 1.0)

func _path_dir_at(points: Array, index: int) -> Vector2:
	var a: Vector2
	var b: Vector2
	if index <= 0:
		a = points[0]
		b = points[1]
	elif index >= points.size() - 1:
		a = points[points.size() - 2]
		b = points[points.size() - 1]
	else:
		a = points[index - 1]
		b = points[index + 1]
	var d := b - a
	return d.normalized() if d.length() > 0.001 else Vector2.RIGHT

## Hauteur de la surface **rendue** du terrain (maillage à un sommet par nœud,
## moyennes de coins), et non la hauteur des centres de cases : indispensable
## pour que chemins, clôtures et rochers ne flottent pas sur les pentes.
func _terrain_surface_height_at(gx: float, gy: float) -> float:
	if not _terrain_relief or _terrain_w <= 0 or _terrain_h <= 0:
		return 0.0
	var x0 := floori(gx)
	var y0 := floori(gy)
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	var h00 := _terrain_vertex_height(x0, y0)
	var h10 := _terrain_vertex_height(x0 + 1, y0)
	var h01 := _terrain_vertex_height(x0, y0 + 1)
	var h11 := _terrain_vertex_height(x0 + 1, y0 + 1)
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)

func _terrain_vertex_height(i: int, j: int) -> float:
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
			var idx: int = cy * _terrain_w + cx
			if idx >= 0 and idx < _terrain_heights.size():
				total += float(_terrain_heights[idx])
				samples += 1
	return total / float(maxi(1, samples))

func _is_occludable_asset(asset: String) -> bool:
	for fragment in ["mur", "maison", "tour", "forge", "chapelle", "grange", "ecurie", "manoir", "marche", "toit"]:
		if asset.contains(fragment):
			return true
	return false

func _apply_visual_transparency(root: Node, alpha: float) -> void:
	if root.has_meta("occlusion_alpha") and is_equal_approx(float(root.get_meta("occlusion_alpha")), alpha):
		return
	root.set_meta("occlusion_alpha", alpha)
	_set_transparency_recursive(root, alpha)

func _set_transparency_recursive(node: Node, alpha: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = alpha
	for child in node.get_children():
		_set_transparency_recursive(child, alpha)

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
	var visual_node: Node = root.get_meta("visual", null) if root.has_meta("visual") else null
	# Mesh déjà cuit en coordonnées monde (chemin texturé) : aucune translation
	# ni mise à l'échelle de la racine — les sommets sont directement dans le
	# repère du monde (comme le terrain lui-même).
	if visual_node != null and visual_node.has_meta("world_space"):
		root.position = Vector3.ZERO
		root.rotation_degrees = Vector3.ZERO
		root.scale = Vector3.ONE
		return
	var display: Dictionary = mesh.get("display", {}) if mesh.get("display") is Dictionary else {}
	var display_scale := maxf(0.01, float(display.get("scale", 1.0)))
	var gx := float(mesh.get("x", 0.0))
	var gy := float(mesh.get("y", 0.0))
	var elevation := float(mesh.get("elevation", 0.0)) * _cell_size
	var terrain_baked := visual_node != null and visual_node.has_meta("terrain_baked")
	var base_y := 0.0 if terrain_baked else (_terrain_base_y(mesh) if _follows_terrain(mesh) else 0.0)
	var yaw := -float(display.get("rotation", 0.0))
	var visual: Node = visual_node
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
