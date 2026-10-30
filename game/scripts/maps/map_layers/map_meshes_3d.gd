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

## Couleur neutre du volume de substitution (#8a7a60).
const FALLBACK_COLOR := Color(0.541176, 0.478431, 0.376471)
## Dimensions du volume de substitution, en unités locales (cases).
const FALLBACK_BOX_SIZE := Vector3(0.9, 1.0, 0.9)
## Hauteur monde de l'ombre de contact au-dessus du sol (unités monde).
const CONTACT_SHADOW_HEIGHT := 0.02
## Opacité au centre de l'ombre de contact (dégradé doux vers les bords).
const CONTACT_SHADOW_OPACITY := 0.25

var _cell_size: float = 1.0
## id → nœud racine (Node3D) du mesh, pour le déplacement live.
var _nodes: Dictionary = {}
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
	for child in get_children():
		remove_child(child)
		child.free()
	_nodes.clear()
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

func _build_mesh(mesh: Dictionary) -> Node3D:
	var display: Dictionary = mesh.get("display", {}) if mesh.get("display") is Dictionary else {}
	var display_scale := maxf(0.01, float(display.get("scale", 1.0)))
	var elevation := float(mesh.get("elevation", 0.0)) * _cell_size

	var root := Node3D.new()
	root.name = str(mesh.get("id", "mesh")) if not str(mesh.get("id", "")).is_empty() else "Mesh"
	root.position = Vector3(
		float(mesh.get("x", 0.0)) * _cell_size + _cell_size * 0.5,
		elevation,
		float(mesh.get("y", 0.0)) * _cell_size + _cell_size * 0.5
	)
	root.rotation_degrees.y = -float(display.get("rotation", 0.0))
	root.scale = Vector3.ONE * _cell_size * display_scale

	var visual := _instantiate_asset(str(mesh.get("asset", "")))
	var fallback := visual == null
	if fallback:
		visual = _build_fallback()
	root.add_child(visual)
	# Rendu 2.5D léger : aucune ombre portée, aucune collision.
	_sanitize_visual(visual)
	# Ombre de contact peinte : ancre l'objet sur le décor (pas d'effet « flottant »).
	_add_contact_shadow(root, visual)
	root.set_meta("fallback", fallback)
	return root

## Instancie l'asset comme scène 3D. Renvoie null si vide / introuvable /
## illisible / non-PackedScene (fallback).
func _instantiate_asset(asset_path: String) -> Node3D:
	var path := asset_path.strip_edges()
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource == null or not resource is PackedScene:
		return null
	var instance: Node = (resource as PackedScene).instantiate()
	if instance == null:
		return null
	var visual := instance as Node3D
	if visual == null:
		instance.free()
		return null
	return visual

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
## centré sur l'empreinte XZ réelle du mesh. `y` est compensé par l'échelle
## racine pour rester à ~CONTACT_SHADOW_HEIGHT unités monde au-dessus du sol.
func _add_contact_shadow(root: Node3D, visual: Node) -> void:
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
	shadow.rotation_degrees.x = -90.0
	# Le parent est mis à l'échelle : compenser pour un décalage monde constant.
	var scale_y := maxf(absf(root.scale.y), 0.001)
	shadow.position = Vector3(center.x, CONTACT_SHADOW_HEIGHT / scale_y, center.y)
	shadow.material_override = _contact_shadow_material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.set_meta("contact_shadow", true)
	root.add_child(shadow)

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
func set_mesh_position(mesh_id: String, gx: float, gy: float) -> void:
	if not _nodes.has(mesh_id):
		return
	var node: Node3D = _nodes[mesh_id]
	node.position.x = gx * _cell_size + _cell_size * 0.5
	node.position.z = gy * _cell_size + _cell_size * 0.5

func has_mesh(mesh_id: String) -> bool:
	return _nodes.has(mesh_id)

## Vrai si le mesh `mesh_id` est rendu par le volume de substitution.
func is_fallback(mesh_id: String) -> bool:
	if not _nodes.has(mesh_id):
		return false
	return bool((_nodes[mesh_id] as Node).get_meta("fallback", false))
