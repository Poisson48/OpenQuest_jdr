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
## `MapRenderStyleScript.atmosphere_color()` (facteur léger) en preset classique.
##
## **Preset qualité `cinema`** (`map_data["qualityPreset"] = "cinema"`, opt-in) :
## le rendu CS2 s'active pour les objets **importés** (GLB) —
##   • `cast_shadow = ON` sur les maillages (jamais la coque `*_outline`, jamais
##     la cheminée/les lames plates procédurales) : les objets projettent une
##     vraie ombre portée sur le sol/terrain, éclairée par le soleil doux ;
##   • matériaux passés en **PBR éclairé** (`SHADING_MODE_PER_PIXEL`) en
##     conservant albedo + vertex colors + textures, mats (roughness plancher),
##     avec une légère **perspective aérienne** (`quality_aerial_tint`) qui
##     désature/éclaircit les objets du fond de carte ;
##   • **ombre de contact peinte atténuée** (le soleil projette la vraie) ;
##   • **budget d'ombres par distance** (`shadowDistance`, défaut 70 cases) :
##     seuls les objets proches du point visé projettent, réévaluation au
##     mouvement caméra sur les nœuds vivants (aucune reconstruction), avec
##     hystérésis anti-clignotement.
## En preset `classique` (défaut, clé absente), le comportement est strictement
## identique à l'historique : aucun cast shadow, matériaux non éclairés.

const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")
## Chargement des objets 3D : GLB livrés (importés par Godot, via ResourceLoader)
## ET GLB utilisateur déposés dans user:// (non importés, via GLTFDocument).
const MapAssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const ProceduralWallMeshScript := preload("res://scripts/maps/construction/procedural_wall_mesh.gd")
const ProceduralRockWallMeshScript := preload("res://scripts/maps/construction/procedural_rock_wall_mesh.gd")
const ProceduralFlowerZoneScript := preload("res://scripts/maps/construction/procedural_flower_zone.gd")
const ProceduralRoofMeshScript := preload("res://scripts/maps/construction/procedural_roof_mesh.gd")
const ProceduralWallShader := preload("res://shaders/procedural_wall.gdshader")
const ProceduralRoofShader := preload("res://shaders/procedural_roof.gdshader")
const PathRibbonShader := preload("res://shaders/path_ribbon.gdshader")
## Végétation en cartouches alpha (roseaux, buissons, haies, nénuphars…).
## Deux variantes : éclairée (cinema) et non éclairée (classique).
const VegetationCardShader := preload("res://shaders/vegetation_card.gdshader")
const VegetationCardUnshadedShader := preload("res://shaders/vegetation_card_unshaded.gdshader")
const ProceduralFloorMeshScript := preload("res://scripts/maps/construction/procedural_floor_mesh.gd")
const ProceduralFenceMeshScript := preload("res://scripts/maps/construction/procedural_fence_mesh.gd")
const ProceduralPathMeshScript := preload("res://scripts/maps/construction/procedural_path_mesh.gd")
const ProceduralTentMeshScript := preload("res://scripts/maps/construction/procedural_tent_mesh.gd")
const ProceduralCampfireMeshScript := preload("res://scripts/maps/construction/procedural_campfire_mesh.gd")
const ProceduralPolyRoofScript := preload("res://scripts/maps/construction/procedural_poly_roof.gd")
const ProceduralRockMeshScript := preload("res://scripts/maps/construction/procedural_rock_mesh.gd")
const ProceduralBridgeMeshScript := preload("res://scripts/maps/construction/procedural_bridge_mesh.gd")

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
## Clés de matériau prises en charge par le passage PBR du preset qualité.
const MIN_LIT_ROUGHNESS := 0.86
## Hystérésis du budget d'ombres : un objet allumé reste allumé jusqu'à ce qu'il
## dépasse `budget × ce facteur` (évite le clignotement au déplacement caméra).
const SHADOW_BUDGET_HYSTERESIS := 1.15

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
var _bridge_decks: Dictionary = {}
## Relief : hauteurs par case (tableau plat, convention grille centrée case).
var _terrain_heights: Array = []
## Creusements volumétriques (Voie B) + champ terre/vide associé.
const TerrainCarveField := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
var _terrain_carves: Array = []
var _terrain_sculpt: Dictionary = {}
var _terrain_field: TerrainCarveField = null
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
## Preset qualité actif (`classique` / `cinema`) — opt-in.
var _quality_preset: String = MapRenderStyleScript.QUALITY_CLASSIQUE
## Preset qualité « cinéma » : ombres portées réelles + matériaux PBR éclairés.
var _cinema_quality: bool = false
## Facteur d'ombre de contact (1.0 = historique, 0.45 en cinéma).
var _contact_shadow_scale: float = 1.0
## Roughness plancher des matériaux importés en cinéma (0 = aucun plancher).
var _material_roughness_min: float = 0.0
## Combinaison de matériaux du style (preset qualité inclus) pour la teinte de
## profondeur des matériaux importés.
var _style_cfg: Dictionary = {}
## Hauteur de carte (cases) pour la perspective aérienne des objets.
var _map_height: int = 1
## Texture radiale partagée par toutes les ombres de contact du calque.
var _shadow_texture: GradientTexture2D = null
## Opacité centrale de la texture d'ombre partagée (pour la régénérer quand le
## preset qualité atténue l'ombre de contact).
var _shadow_texture_opacity: float = -1.0
## Budget d'ombres en cases (`shadowDistance`, -1 = illimité) : seuls les objets
## proches du point visé projettent une ombre. Voir `update_shadow_budget()`.
var _shadow_budget_cells: float = -1.0
## Dernier point visé (monde, xz) connu pour le budget d'ombres.
var _shadow_budget_focus: Vector2 = Vector2.INF
## id → nœuds `GeometryInstance3D` qui projettent une ombre (mesh + aucun
## contour), pour allumer/éteindre le cast sans reconstruire les objets.
var _shadow_casters: Dictionary = {}
## Nombre d'objets projetant actuellement une ombre (tests/perf).
var _active_shadow_casters: int = 0

## Reconstruit le calque. `map_data` est accepté pour cohérence avec les autres
## calques (MapProps3D) ; il sert à la teinte d'ambiance du fallback et à savoir
## si le style éclaire les objets (VTT) ou non (diorama/DD2, rendu peint).
func configure(meshes: Array, cell_size: float, map_data: Dictionary = {}) -> void:
	_cell_size = cell_size if cell_size > 0.0 else 1.0
	_has_atmosphere = not map_data.is_empty()
	_atmosphere = MapRenderStyleScript.atmosphere_color(map_data) if _has_atmosphere else Color(0.10, 0.10, 0.14)
	_style_cfg = MapRenderStyleScript.config(map_data) if _has_atmosphere else {}
	_unshaded = not bool(_style_cfg.get("litProps", false))
	_quality_preset = MapRenderStyleScript.quality_preset(map_data) if _has_atmosphere \
		else MapRenderStyleScript.QUALITY_CLASSIQUE
	_cinema_quality = _quality_preset == MapRenderStyleScript.QUALITY_CINEMA \
		and bool(_style_cfg.get("cinemaQuality", false)) and not _unshaded
	_contact_shadow_scale = clampf(float(_style_cfg.get("contactShadowScale", 1.0)), 0.0, 2.0)
	_material_roughness_min = maxf(
		MIN_LIT_ROUGHNESS if _cinema_quality else 0.0,
		float(_style_cfg.get("materialRoughnessMin", 0.0)))
	# Budget d'ombres : -1 (ou absent) = illimité, sinon distance en cases.
	_shadow_budget_cells = float(_style_cfg.get("shadowDistance", -1.0))
	_shadow_budget_focus = Vector2.INF
	_active_shadow_casters = 0
	_map_height = maxi(1, int(map_data.get("height", 1)))
	_read_terrain(map_data)
	for child in get_children():
		remove_child(child)
		child.free()
	_nodes.clear()
	_mesh_entries.clear()
	_bridge_decks.clear()
	_fire_lights.clear()
	_shadow_casters.clear()
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
	_active_shadow_casters = _shadow_casters.size()

## ===========================================================================
# Budget d'ombres par distance (preset cinéma)
# ===========================================================================
#
# Sur une carte dense, `cast_shadow` sur tous les GLB double la passe de
# géométrie (ombres + couleur). Seuls les objets **proches du point visé**
# projettent donc une ombre : `shadowDistance` cases (défaut 70). La bascule se
# fait sur les nœuds vivants (aucune reconstruction) quand la caméra bouge,
# avec hystérésis pour éviter tout clignotement. En `classique`, aucun objet ne
# projette et ce budget est inactif.

## Allume/éteint les ombres des objets selon la distance au point visé (monde,
## xz). `budget_cells` vient du preset (`shadowDistance`) ; -1 = illimité.
## Renvoie le nombre d'objets projetant une ombre.
func update_shadow_budget(focus_world: Vector2) -> int:
	if not _cinema_quality or _shadow_budget_cells < 0.0:
		return _active_shadow_casters
	if not focus_world.is_finite():
		return _active_shadow_casters
	if _shadow_budget_focus.is_finite() and focus_world.distance_to(_shadow_budget_focus) < 0.01:
		return _active_shadow_casters
	_shadow_budget_focus = focus_world
	var budget_world := _shadow_budget_cells * _cell_size
	var hysteresis := budget_world * SHADOW_BUDGET_HYSTERESIS
	var enabled := 0
	for id_variant in _shadow_casters.keys():
		var id := str(id_variant)
		var root: Node3D = _nodes.get(id) as Node3D
		var casters: Array = _shadow_casters[id]
		if root == null or not is_instance_valid(root) or casters.is_empty():
			_shadow_casters.erase(id)
			continue
		var distance := Vector2(root.position.x - focus_world.x,
			root.position.z - focus_world.y).length()
		var currently_on := (casters[0] as GeometryInstance3D).cast_shadow \
			== GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var want_on := currently_on
		if currently_on and distance > hysteresis:
			want_on = false
		elif not currently_on and distance <= budget_world:
			want_on = true
		if want_on != currently_on:
			for caster in casters:
				(caster as GeometryInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_ON if want_on \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if want_on:
			enabled += 1
	_active_shadow_casters = enabled
	return enabled

## Force le budget d'ombres (cases ; -1 = illimité) sans reconstruire la carte.
## Utilisé par les tests, les captures et la mesure de perf (A/B budget serré).
func set_shadow_budget_cells(cells: float) -> void:
	var previous := _shadow_budget_focus
	_shadow_budget_cells = cells
	_shadow_budget_focus = Vector2.INF
	if _shadow_budget_cells < 0.0:
		for id_variant in _shadow_casters.keys():
			for caster in _shadow_casters[id_variant]:
				(caster as GeometryInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_active_shadow_casters = _shadow_casters.size()
		_shadow_budget_focus = previous
		return
	# Budget serré : réapplique autour du dernier point visé connu (sinon on
	# laisse tous les objets allumés jusqu'au premier mouvement caméra).
	if previous.is_finite():
		update_shadow_budget(previous)
	else:
		_shadow_budget_focus = previous

## Budget d'ombres courant en cases (-1 = illimité).
func get_shadow_budget_cells() -> float:
	return _shadow_budget_cells

## Nombre d'objets projetant actuellement une ombre (budget appliqué).
func get_active_shadow_casters() -> int:
	return _active_shadow_casters

## Nombre d'objets capables de projeter une ombre (preset cinéma).
func get_shadow_caster_count() -> int:
	return _shadow_casters.size()

## Met à jour le relief **sans reconstruire les objets** (pinceau de relief de
## l'éditeur, appelé à chaque mouvement : les GLB ne sont pas réinstanciés).
## Repose les racines existantes sur les nouvelles hauteurs et réévalue
## l'inclinaison + l'ombre de contact.
func set_terrain_heights(terrain_heights: Array, map_size: Vector2i = Vector2i.ZERO) -> void:
	var data := {
		"width": map_size.x if map_size.x > 0 else _terrain_w,
		"height": map_size.y if map_size.y > 0 else _terrain_h,
		"terrainHeights": terrain_heights,
		"terrainCarves": _terrain_carves,
	}
	_read_terrain(data)
	_reseat_nodes()

## Met à jour les creusements volumétriques (Voie B) : les objets sont reposés
## sur le sol visible (fond de trou / sol de grotte si concernés).
func set_terrain_carves(carves: Array) -> void:
	_terrain_carves = TerrainCarveField.normalize_carves(carves)
	_terrain_field = TerrainCarveField.new(
		_terrain_heights, _terrain_w, _terrain_h, _terrain_carves, _terrain_sculpt)
	_reseat_nodes()

## Met à jour la sculpture volumétrique (déplacement lissé) : les objets sont
## reposés sur la terre sculptée.
func set_terrain_sculpt(sculpt: Dictionary) -> void:
	_terrain_sculpt = sculpt if sculpt is Dictionary else {}
	_terrain_field = TerrainCarveField.new(
		_terrain_heights, _terrain_w, _terrain_h, _terrain_carves, _terrain_sculpt)
	_reseat_nodes()

## Repose les racines existantes (position, inclinaison, ombre de contact).
func _reseat_nodes() -> void:
	for id in _nodes:
		var node: Node3D = _nodes[id]
		var entry: Dictionary = _mesh_entries.get(id, {})
		if node == null or not is_instance_valid(node) or entry.is_empty():
			continue
		var visual: Node = node.get_meta("visual", null) if node.has_meta("visual") else null
		if visual is MeshInstance3D:
			if _is_bridge(str(entry.get("asset", ""))):
				_rebuild_bridge(visual, entry)
			elif visual.has_meta("flat_mesh"):
				_rebake_procedural_visual(visual, entry)
		_place_root(node, entry)
		var shadow := _find_child_with_meta(node, "contact_shadow")
		if shadow is Node3D:
			_repose_contact_shadow(node, shadow as Node3D, _is_inclined(entry))

## Lit le relief fourni par le document (`terrainHeights` + `terrainCarves` +
## dimensions carte). Tableau absent / mal dimensionné → terrain plat
## (comportement historique).
func _read_terrain(map_data: Dictionary) -> void:
	_terrain_heights = []
	_terrain_w = maxi(0, int(map_data.get("width", 0)))
	_terrain_h = maxi(0, int(map_data.get("height", 0)))
	_terrain_relief = false
	_terrain_carves = TerrainCarveField.normalize_carves(map_data.get("terrainCarves", []))
	_terrain_sculpt = map_data.get("terrainSculpt", {}) \
		if map_data.get("terrainSculpt") is Dictionary else {}
	if _terrain_w > 0 and _terrain_h > 0:
		var raw = map_data.get("terrainHeights", [])
		if (raw is Array) and (raw as Array).size() == _terrain_w * _terrain_h:
			_terrain_heights = raw
			for value in _terrain_heights:
				if absf(float(value)) > TERRAIN_RELIEF_EPSILON:
					_terrain_relief = true
					break
	_terrain_field = TerrainCarveField.new(
		_terrain_heights, _terrain_w, _terrain_h, _terrain_carves, _terrain_sculpt)

## Hauteur du terrain (en cases) aux coordonnées grille **centrées case** —
## même convention que `ComplexMapEngine3D.terrain_height_at` (entier = centre
## de case, interpolation bilinéaire entre centres, 0 hors carte). Avec
## creusements (Voie B) : sol visible depuis le dessus.
func _terrain_height_at(gx: float, gy: float) -> float:
	if not _terrain_carves.is_empty() and _terrain_field != null:
		if gx < -0.5 or gy < -0.5 or gx > float(_terrain_w) - 0.5 or gy > float(_terrain_h) - 0.5:
			return 0.0
		return _terrain_field.top_surface_at(gx, gy)
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
	if not _terrain_carves.is_empty() and _terrain_field != null:
		return _terrain_field.normal_at(gx, gy)
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
	if asset_path.begins_with("procedural://") or _is_bridge(asset_path):
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
	# Rendu 2.5D léger : aucune ombre portée, aucune collision — SAUF preset
	# qualité `cinema` sur les assets réellement importés (GLB) : eux seuls
	# projettent une vraie ombre de soleil (les visuels procéduraux du moteur et
	# la coque d'encre `*_outline` restent sans ombre).
	var imported_asset := not asset_path.begins_with("procedural://") and not _is_bridge(asset_path)
	var cast_sun_shadow := _cinema_quality and imported_asset
	var depth01 := clampf(float(mesh.get("y", 0.0)) / float(maxi(1, _map_height)), 0.0, 1.0)
	_sanitize_visual(visual, cast_sun_shadow, depth01)
	# Budget d'ombres : mémorise les nœuds capables de projeter pour pouvoir
	# les allumer/éteindre selon la distance sans reconstruire l'objet.
	if cast_sun_shadow:
		var casters: Array = []
		_collect_shadow_casters(visual, casters)
		if not casters.is_empty():
			_shadow_casters[str(mesh.get("id", ""))] = casters
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
	elif asset == "procedural://rock_wall":
		mesh_instance.name = "ProceduralRockWall"
		mesh_instance.mesh = ProceduralRockWallMeshScript.build_from_element(mesh)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = material
		_conform_procedural_mesh(mesh_instance, mesh)
		return mesh_instance
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
	elif _is_bridge(asset):
		mesh_instance.name = "ProceduralBridge"
		_rebuild_bridge(mesh_instance, mesh)
		mesh_instance.set_meta("terrain_baked", true)
		mesh_instance.set_meta("world_space", true)
		material.vertex_color_use_as_albedo = true
		material.albedo_color = Color.WHITE
		material.roughness = 0.9
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if _unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mesh_instance.material_override = material
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

static func _is_bridge(asset: String) -> bool:
	return asset in [ProceduralBridgeMeshScript.ASSET, ProceduralBridgeMeshScript.CATALOG_ASSET]

func _rebuild_bridge(visual: MeshInstance3D, entry: Dictionary) -> void:
	var deck := _bridge_mesh_params(entry)
	visual.mesh = ProceduralBridgeMeshScript.build(deck)
	_bridge_decks[str(entry.get("id", ""))] = deck

func update_bridge(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	var root := _nodes.get(id) as Node3D
	if root != null and _is_bridge(str(entry.get("asset", ""))):
		var visual := root.get_meta("visual", null) as MeshInstance3D
		if visual != null:
			_mesh_entries[id] = entry.duplicate(true)
			_rebuild_bridge(visual, entry)

func bridge_height_at(x: float, z: float) -> float:
	var height := -INF
	for deck in _bridge_decks.values():
		height = maxf(height, ProceduralBridgeMeshScript.deck_height_at(deck, Vector2(x, z)))
	return height

func bridge_endpoints(id: String) -> PackedVector3Array:
	if not _bridge_decks.has(id):
		return PackedVector3Array()
	var deck: Dictionary = _bridge_decks[id]
	return PackedVector3Array([deck["start"], deck["end"]])

func raycast_bridges(origin: Vector3, direction: Vector3) -> Vector3:
	var closest := Vector3.INF
	var best := INF
	for deck in _bridge_decks.values():
		var hit := ProceduralBridgeMeshScript.raycast_deck(deck, origin, direction)
		if hit != Vector3.INF:
			var distance := origin.distance_squared_to(hit)
			if distance < best:
				closest = hit
				best = distance
	return closest

## Les deux entrées (outil de construction et objet du catalogue) produisent
## le même tablier, que le moteur utilise aussi pour placer les figurines.
func _bridge_mesh_params(mesh: Dictionary) -> Dictionary:
	var start: Dictionary = mesh.get("start", {}) if mesh.get("start") is Dictionary else {}
	var end: Dictionary = mesh.get("end", {}) if mesh.get("end") is Dictionary else {}
	var a := Vector2(float(start.get("x", 0.0)), float(start.get("y", 0.0)))
	var b := Vector2(float(end.get("x", 0.0)), float(end.get("y", 0.0)))
	var width := float(mesh.get("width", 1.6))
	var from_catalog := str(mesh.get("asset", "")) == ProceduralBridgeMeshScript.CATALOG_ASSET
	if from_catalog:
		var center := Vector2(float(mesh.get("x", 0.0)), float(mesh.get("y", 0.0)))
		var display: Dictionary = mesh.get("display", {}) if mesh.get("display") is Dictionary else {}
		var scale_factor := maxf(0.05, float(display.get("scale", 1.0)))
		var axis := Vector2.from_angle(deg_to_rad(float(display.get("rotation", 0.0))))
		var meta := MapAssetLibraryScript.get_object3d_meta(ProceduralBridgeMeshScript.CATALOG_ASSET)
		var natural: Array = meta.get("dimensions_cells", [2.56, 1.24, 0.84])
		var length := float(mesh.get("sizeX", 0.0))
		if length <= 0.0:
			length = float(natural[0]) * scale_factor
		a = center - axis * length * 0.5
		b = center + axis * length * 0.5
		width = float(mesh.get("sizeZ", 0.0))
		if width <= 0.0:
			width = float(natural[1]) * scale_factor
	var world_a := (a + Vector2(0.5, 0.5)) * _cell_size
	var world_b := (b + Vector2(0.5, 0.5)) * _cell_size
	var height_a := float(start.get("h", 0.0)) * _cell_size
	var height_b := float(end.get("h", 0.0)) * _cell_size
	if bool(mesh.get("followBanks", from_catalog and bool(mesh.get("followTerrain", true)))):
		height_a = _bridge_ground_height(world_a.x, world_a.y)
		height_b = _bridge_ground_height(world_b.x, world_b.y)
	var clearance := (0.045 + float(mesh.get("elevation", 0.0))) * _cell_size
	return {
		"start": Vector3(world_a.x, height_a + clearance, world_a.y),
		"end": Vector3(world_b.x, height_b + clearance, world_b.y),
		"width": maxf(0.4, width) * _cell_size,
		"seed": int(mesh.get("seed", 1)),
		"ground_height": _bridge_ground_height,
	}

func _bridge_ground_height(x: float, z: float) -> float:
	if _terrain_field == null:
		return 0.0
	return _terrain_field.top_surface_at(x / _cell_size, z / _cell_size, true) * _cell_size

func _build_textured_path_mesh(mesh: Dictionary) -> ArrayMesh:
	var raw_points: Array = mesh.get("points", [])
	if raw_points.size() < 2:
		return ArrayMesh.new()
	var width := maxf(0.3, float(mesh.get("width", 1.2)))
	var detail := clampi(_path_detail_for(mesh), 1, 4)
	var seed := int(mesh.get("seed", 1))
	var tile_length := 2.0
	# Empilement vertical des chemins : les rubans coplanaires provoquent du
	# z-fighting (le chemin peint en dernier pouvait passer SOUS le premier).
	# Chaque chemin successif monte de 2 cm, imperceptible mais décisif pour
	# le test de profondeur.
	var path_lift := 0.035 + float(int(mesh.get("pathStack", 0))) * 0.02

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
			var h := _terrain_surface_height_at(p.x + 0.5, p.y + 0.5) * _cell_size + path_lift
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
## Le preset qualité applique en plus, aux matériaux **importés** réels, la
## perspective aérienne (`_apply_lit_materials`), sans modifier les ressources
## partagées : seules des copies par surface sont touchées.
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
## L'opacité est atténuée par le preset qualité (`contactShadowScale` : en
## cinéma le soleil projette la vraie ombre, l'ombre peinte n'est qu'un rappel).
func _contact_shadow_material() -> StandardMaterial3D:
	var opacity := CONTACT_SHADOW_OPACITY * _contact_shadow_scale
	if _shadow_texture == null or not is_equal_approx(_shadow_texture_opacity, opacity):
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.0, 0.0, 0.0, opacity))
		gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
		if gradient.get_point_count() < 3:
			gradient.add_point(0.55, Color(0.0, 0.0, 0.0, opacity * 0.55))
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_shadow_texture = tex
		_shadow_texture_opacity = opacity
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

## Coupe les ombres, neutralise les collisions et règle le matériau des meshes.
##
## • Preset `classique` (historique) : tout `cast_shadow = OFF` ; en 2.5D les
##   matériaux importés passent en non éclairé (palette et AO de Blender,
##   l'illustration porte la lumière) ; en VTT on garde l'éclairage.
## • Preset `cinema` : les meshes importés **projettent** leur ombre (le sol et
##   le terrain la reçoivent), la coque d'encre `*_outline` jamais ; les
##   matériaux passent en PBR éclairé avec teinte de profondeur.
func _sanitize_visual(node: Node, cast_sun_shadow: bool = false, depth01: float = 1.0) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		var allow := cast_sun_shadow and not _is_outline_node(node)
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if allow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is MeshInstance3D:
		if _cinema_quality:
			_apply_lit_materials(node as MeshInstance3D, depth01)
		elif _unshaded:
			_apply_unshaded_materials(node as MeshInstance3D)
	for child in node.get_children():
		_sanitize_visual(child, cast_sun_shadow, depth01)

## Collecte les `GeometryInstance3D` d'un objet qui projettent une ombre (le
## mesh principal, jamais la coque `*_outline` ni l'ombre de contact peinte).
func _collect_shadow_casters(node: Node, out: Array) -> void:
	if node is GeometryInstance3D and not node.has_meta("contact_shadow"):
		if (node as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			out.append(node)
	for child in node.get_children():
		_collect_shadow_casters(child, out)

## Vrai pour la coque d'encre inversée du pipeline Blender (`<nom>_outline`) :
## elle ne doit JAMAIS projeter d'ombre (elle assombrirait l'objet et le sol).
func _is_outline_node(node: Node) -> bool:
	return str(node.name).to_lower().contains("outline")

## Duplique les matériaux par surface et les passe en `UNSHADED`, en activant
## les vertex colors comme albédo (mottling + AO cuits par le pipeline Blender).
## La duplication évite de modifier les ressources partagées entre instances.
func _apply_unshaded_materials(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	var surface_count := mesh_instance.mesh.get_surface_count()
	for i in range(surface_count):
		var source := mesh_instance.get_active_material(i)
		if _is_vegetation_card(source):
			mesh_instance.set_surface_override_material(
				i, _vegetation_card_material(mesh_instance, source as StandardMaterial3D, false))
			continue
		if source is StandardMaterial3D:
			var material: StandardMaterial3D = (source as StandardMaterial3D).duplicate()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.vertex_color_use_as_albedo = true
			material.cull_mode = BaseMaterial3D.CULL_BACK
			mesh_instance.set_surface_override_material(i, material)
		elif source != null:
			# Matériau exotique : on le laisse tel quel plutôt que de le casser.
			pass

## Preset `cinema` : matériaux importés en **PBR éclairé** (méthode CS2), en
## conservant l'albedo/texture et les vertex colors, mats (roughness plancher),
## avec une **perspective aérienne** très légère selon la profondeur de l'objet
## dans la carte (`depth01` = 1 au premier plan, 0 au fond).
## La duplication est indispensable : les matériaux importés sont partagés
## entre instances (et avec la ressource `.scn`), on ne les modifie pas en place.
func _apply_lit_materials(mesh_instance: MeshInstance3D, depth01: float) -> void:
	var haze := MapRenderStyleScript.quality_aerial_color(_style_cfg)
	var haze_amount := MapRenderStyleScript.quality_aerial_amount(depth01, _style_cfg)
	var override := mesh_instance.material_override
	if override is StandardMaterial3D:
		# Fallback (boîte neutre) : matériau porté par `material_override`.
		mesh_instance.material_override = _lit_material(
			override as StandardMaterial3D, haze, haze_amount)
		return
	if mesh_instance.mesh == null:
		return
	var surface_count := mesh_instance.mesh.get_surface_count()
	for i in range(surface_count):
		var source := mesh_instance.get_active_material(i)
		if _is_vegetation_card(source):
			mesh_instance.set_surface_override_material(
				i, _vegetation_card_material(mesh_instance, source as StandardMaterial3D, true))
			continue
		if source is StandardMaterial3D:
			mesh_instance.set_surface_override_material(
				i, _lit_material(source as StandardMaterial3D, haze, haze_amount))

## Copie éclairée d'un matériau importé : PBR (per-pixel), vertex colors en
## albédo, métal nul, roughness plancher et perspective aérienne (l'albédo tend
## vers la brume chaude pour les objets du fond). Les textures, l'émission et
## les réglages exotiques sont conservés.
func _lit_material(source: StandardMaterial3D, haze: Color, haze_amount: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = source.duplicate()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.vertex_color_use_as_albedo = true
	material.metallic = 0.0
	material.metallic_specular = minf(material.metallic_specular, 0.22)
	material.roughness = maxf(material.roughness, _material_roughness_min)
	material.cull_mode = BaseMaterial3D.CULL_BACK
	var base: Color = material.albedo_color
	# La coque d'encre reste sombre même avec la perspective aérienne : on
	# n'éclaircit que très peu les matériaux très sombres (lisibilité du trait).
	var weight := haze_amount * (0.55 if base.get_luminance() < 0.16 else 1.0)
	if weight > 0.0001:
		var faded := base.lerp(haze, clampf(weight, 0.0, 0.5))
		faded.a = base.a
		material.albedo_color = faded
	return material

## Vrai pour un matériau de VÉGÉTATION EN CARTOUCHES ALPHA (généré par
## `tools/blender/build_vegetation_cards.py`) : le glTF porte `alphaMode MASK`
## (donc une transparence alpha-scissor) et une texture à découpe. Ces assets ne
## doivent PAS passer par les matériaux standard (qui forcent le cull back et
## cassent la double face), mais par le shader de végétation (vent + scissor).
func _is_vegetation_card(source: Material) -> bool:
	if not (source is StandardMaterial3D):
		return false
	var material := source as StandardMaterial3D
	if material.albedo_texture == null:
		return false
	if str(material.resource_name).to_lower().contains("_cards"):
		return true
	# Le glTF `alphaMode MASK` devient une transparence alpha-scissor à
	# l'import : c'est la signature fiable des cartouches (aucun autre asset
	# importé n'est transparent).
	return material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED

## Matériau de cartouches : shader éclairé (cinema) ou non éclairé (classique),
## avec vent par sommet proportionnel à la hauteur du cartouche.
func _vegetation_card_material(mesh_instance: MeshInstance3D,
		source: StandardMaterial3D, lit: bool) -> ShaderMaterial:
	var height := 1.0
	if mesh_instance.mesh != null:
		height = maxf(0.15, mesh_instance.mesh.get_aabb().size.y)
	var material := ShaderMaterial.new()
	material.shader = VegetationCardShader if lit else VegetationCardUnshadedShader
	material.set_shader_parameter("albedo_tex", source.albedo_texture)
	material.set_shader_parameter("tint", source.albedo_color)
	material.set_shader_parameter("roughness", maxf(source.roughness, _material_roughness_min))
	material.set_shader_parameter("alpha_cutoff",
		maxf(source.alpha_scissor_threshold, 0.5) if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED else 0.5)
	material.set_shader_parameter("card_height", height)
	# Vent : un peu plus ample sur les grands végétaux (bosquet, roseaux).
	material.set_shader_parameter("wind_strength", clampf(0.035 + height * 0.014, 0.04, 0.09))
	material.set_shader_parameter("wind_speed", 1.35)
	return material

## Repositionne un mesh sans reconstruire la scène (glisser en cours).
## Sur relief, le pied est reposé sur la nouvelle hauteur et l'inclinaison
## réévaluée ; sur terrain plat, comportement historique (x/z seulement).
func set_mesh_position(mesh_id: String, gx: float, gy: float) -> void:
	if not _nodes.has(mesh_id):
		return
	var node: Node3D = _nodes[mesh_id]
	var entry: Dictionary = _mesh_entries.get(mesh_id, {})
	if not entry.is_empty():
		ProceduralBridgeMeshScript.move_entry(entry, gx, gy)
		if _is_bridge(str(entry.get("asset", ""))):
			update_bridge(entry)
			return
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
