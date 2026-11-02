extends RefCounted

## Construction de carte 2.5D — extrait de `map_complex_editor.gd`.
##
## Regroupe tout le « cœur construction » : murs 3D modulaires (chaînes, coins,
## jonctions, étirement), pièce 3D, maison rapide, toit, dallage, porte/fenêtre,
## clôture, chemin, escalier, meubles, intérieurs liés, tracé organique et
## végétation au pinceau, + helpers AABB / dimensions / aimantation de modules.
##
## Le module reçoit une référence à l'éditeur (`setup`) : pas de dépendance
## circulaire. Il lit/écrit l'état de l'éditeur (options d'outils, caches, doc,
## statut, signaux) via `_ed`. L'éditeur garde des wrappers fins pour les
## fonctions utilisées par les tests.

const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")
const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")
const OrganicPathScript := preload("res://scripts/maps/construction/organic_path.gd")
const OrganicScatterScript := preload("res://scripts/maps/construction/organic_scatter.gd")
const WaveFunctionCollapseScript := preload("res://scripts/maps/construction/wave_function_collapse.gd")
const ProceduralSceneGeneratorScript := preload("res://scripts/maps/construction/procedural_scene_generator.gd")

const ROOF_STYLES := [
	{"label": "Tuiles (2 pans)", "path": "res://assets/objects3d/buildings/toit_2pentes.glb"},
	{"label": "Chaume", "path": "res://assets/objects3d/buildings/toit_chaume.glb"},
	{"label": "Croupe", "path": "res://assets/objects3d/buildings/toit_croupe.glb"},
	{"label": "Appentis", "path": "res://assets/objects3d/buildings/toit_appentis.glb"},
]
const FLOOR_MATERIALS := [
	{"label": "Pierre", "id": 2}, {"label": "Terre", "id": 1},
	{"label": "Herbe", "id": 0}, {"label": "Sable", "id": 4}, {"label": "Neige", "id": 3},
]
const FENCE_STYLES := [
	{"label": "Barrière", "path": "res://assets/objects3d/props/barriere.glb"},
	{"label": "Clôture basse", "path": "res://assets/objects3d/props/cloture_basse.glb"},
	{"label": "Palissade", "path": "res://assets/objects3d/props/palissade.glb"},
]
## Styles du tracé organique (freehand) — modules orientés sur la tangente.
const ORGANIC_STYLES := [
	{"label": "Mur 3D", "path": "res://assets/objects3d/buildings/mur.glb"},
	{"label": "Clôture basse", "path": "res://assets/objects3d/props/cloture_basse.glb"},
	{"label": "Palissade", "path": "res://assets/objects3d/props/palissade.glb"},
	{"label": "Barrière", "path": "res://assets/objects3d/props/barriere.glb"},
]
const FURNITURE_PRESETS := [	{"id": "salle", "label": "Salle commune", "items": [
		["table_tabourets", 0.0, 0.0, 0.0], ["banc", 1.9, 0.7, 90.0],
		["tonneau", -1.7, 0.8, 0.0], ["tapis", 0.0, 1.5, 0.0],
	]},
	{"id": "chambre", "label": "Chambre", "items": [
		["lit", 0.0, 0.0, 0.0], ["caisse", 1.6, 0.6, 0.0], ["tapis", -1.2, 1.0, 0.0],
	]},
	{"id": "comptoir", "label": "Comptoir", "items": [
		["comptoir", 0.0, 0.0, 0.0], ["tonneau", -1.5, 0.8, 0.0],
		["tonneau_couche", 1.5, 0.8, 20.0], ["banniere", 0.0, -1.4, 0.0],
	]},
	{"id": "campement", "label": "Campement", "items": [
		["botte_foin", 0.0, 0.0, 0.0], ["tas_de_bois", 1.4, 0.6, 0.0],
		["banc", -1.3, 0.7, 90.0], ["tonneau", 0.2, 1.5, 0.0],
	]},
]

## Murs 3D modulaires : le module « mur » fait ~2,36 cases, le coin L ~2,1 × 1,7.
## Le pavage d'une rangée est exact (dernier module ajusté) pour que les
## extrémités tombent pile sur les voisines, quel que soit le tracé.
const WALL_ASSET := "res://assets/objects3d/buildings/mur.glb"
const WALL_CORNER_ASSET := "res://assets/objects3d/buildings/mur_coin.glb"
## Rayon d'accroche d'une extrémité de mur sur le réseau existant (cases).
const WALL_SNAP_RADIUS := 0.85
## Tolérance pour considérer que deux murs partagent une extrémité (cases).
const WALL_JOIN_EPS := 0.4
## Longueur minimale d'un module / d'une rangée de murs (cases).
const WALL_MIN_LENGTH := 0.5
const WALL_MIN_SEGMENT := 0.4
const STACK_EPSILON := 0.012
## Longueur maximale d'un module étiré à la poignée (garde-fou, cases).
const WALL_MAX_SEGMENT := 120.0

## Éditeur propriétaire (Control) — non typé pour éviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor
func _create_wall(from: Vector2, to: Vector2) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.4:
		return
	var id: String = _ed.doc.add_element({
		"x": (from.x + to.x) * 0.5, "y": (from.y + to.y) * 0.5,
		"w": length, "h": 0.25,
		"height": 1.4,
		"color": "#4a423a",
		"blocksSight": true,
		"label": "Mur",
		"layer": 2,
		"display": {"rotation": rad_to_deg(delta.angle())},
	}, DocumentScript.KIND_WALL, "Mur")
	_ed.doc.select_only(id)

# ===========================================================================
# Murs 3D continus (façon Tiny Glade / Sims)
# ===========================================================================
#
# Principe : un tracé de mur est toujours posé **sur** le réseau existant.
#   1. Chaque extrémité s'aimante à l'extrémité d'un mur (prolongement ou coin L)
#      ou sur son flanc (jonction T) ;
#   2. la rangée est pavée exactement entre les deux extrémités aimantées : le
#      module vaut `longueur / nombre`, donc pas de trou ni de débordement ;
#   3. un coin L (`mur_coin.glb`) est posé automatiquement aux jonctions qui
#      changent de direction, avec la même convention de rotation que la Pièce 3D ;
#   4. un module qui recouvrirait un mur déjà posé est ignoré (pas de doublon).

func _is_wall_mesh(elem: Dictionary) -> bool:
	if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
		return false
	return str(elem.get("asset", "")).ends_with("mur.glb")

func _wall_length(elem: Dictionary) -> float:
	var length := float(elem.get("sizeX", 0.0))
	if length > 0.0:
		return length
	return maxf(0.5, _mesh_bounds_cells(str(elem.get("asset", WALL_ASSET)), 1.0).x)

func _wall_rotation_rad(elem: Dictionary) -> float:
	var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
	return deg_to_rad(float(display.get("rotation", 0.0)))

## Extrémités monde `[a, b]` d'un module de mur.
func _wall_endpoints(elem: Dictionary) -> Array:
	var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	var rad := _wall_rotation_rad(elem)
	var along := Vector2(cos(rad), sin(rad))
	var half := _wall_length(elem) * 0.5
	return [center - along * half, center + along * half]

## Aimantation d'un point sur le réseau de murs 3D.
## Renvoie `{point, kind: "free"|"endpoint"|"side", id, wall, host_dir}`.
## `host_dir` pointe depuis la jonction vers le centre du mur hôte.
func _snap_wall_point(point: Vector2, exclude_ids: Array = []) -> Dictionary:
	var best := {
		"point": point, "kind": "free", "id": "",
		"wall": {}, "host_dir": Vector2.ZERO,
	}
	var best_distance := WALL_SNAP_RADIUS
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if not _is_wall_mesh(elem):
			continue
		var elem_id := str(elem.get("id", ""))
		if exclude_ids.has(elem_id):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var rad := _wall_rotation_rad(elem)
		var along := Vector2(cos(rad), sin(rad))
		# 1) Extrémité : prolongement (aligné) ou coin L (changement de direction).
		for endpoint_variant in _wall_endpoints(elem):
			var endpoint: Vector2 = endpoint_variant
			var distance := point.distance_to(endpoint)
			if distance < best_distance:
				best_distance = distance
				var host_dir := along if (center - endpoint).dot(along) >= 0.0 else -along
				best = {
					"point": endpoint, "kind": "endpoint", "id": elem_id,
					"wall": elem, "host_dir": host_dir,
				}
		# 2) Flanc : jonction en T (le point tombe sur la ligne médiane du mur).
		var half_length := _wall_length(elem) * 0.5
		var offset := point - center
		var along_offset := clampf(offset.dot(along), -half_length, half_length)
		var side_point := center + along * along_offset
		var side_distance := point.distance_to(side_point)
		if side_distance < best_distance:
			best_distance = side_distance
			best = {
				"point": side_point, "kind": "side", "id": elem_id,
				"wall": elem, "host_dir": along,
			}
	return best

func _snap_wall_endpoint(point: Vector2) -> Vector2:
	return _snap_wall_point(point).get("point", point)

## Plan d'une rangée : extrémités aimantées + pavage exact. Renvoie `valid=false`
## si le tracé est trop court. Utilisé aussi par l'aperçu et le statut.
func _wall_chain_plan(from: Vector2, to: Vector2) -> Dictionary:
	var snap_from := _snap_wall_point(from)
	var snap_to := _snap_wall_point(to)
	var a: Vector2 = snap_from.get("point", from)
	var b: Vector2 = snap_to.get("point", to)
	var delta := b - a
	var total := delta.length()
	var bounds := _mesh_bounds_cells(WALL_ASSET, 1.0)
	var nominal := maxf(1.0, bounds.x)
	var plan := {
		"valid": total >= WALL_MIN_LENGTH,
		"from": a, "to": b, "delta": delta, "total": total,
		"count": 1, "segment_len": total,
		"nominal_len": nominal, "depth": maxf(0.3, bounds.z),
		"rotation": rad_to_deg(atan2(delta.y, delta.x)),
		"start_snap": str(snap_from.get("kind", "free")),
		"end_snap": str(snap_to.get("kind", "free")),
		"start_wall": snap_from.get("wall", {}),
		"end_wall": snap_to.get("wall", {}),
		"start_host_dir": snap_from.get("host_dir", Vector2.ZERO),
		"end_host_dir": snap_to.get("host_dir", Vector2.ZERO),
	}
	if not bool(plan["valid"]):
		return plan
	var count := maxi(1, int(round(total / nominal)))
	plan["count"] = count
	plan["segment_len"] = total / float(count)
	return plan

## Coins L à poser pour un plan : uniquement quand une extrémité s'aimante sur
## l'extrémité d'un mur hôte **non aligné** (un prolongement ne demande pas de coin).
func _wall_chain_corner_specs(plan: Dictionary) -> Array:
	var specs: Array = []
	if not bool(plan.get("valid", false)):
		return specs
	var delta: Vector2 = plan.get("delta", Vector2.ZERO)
	if delta.length() < 0.001:
		return specs
	var axis := delta.normalized()
	if str(plan.get("start_snap", "")) == "endpoint" and not (plan.get("start_wall", {}) as Dictionary).is_empty():
		var start_dir: Vector2 = plan.get("start_host_dir", Vector2.ZERO)
		if start_dir.length() > 0.1 and absf(axis.dot(start_dir)) < 0.5:
			specs.append({"point": plan["from"], "dir_a": axis, "dir_b": start_dir})
	if str(plan.get("end_snap", "")) == "endpoint" and not (plan.get("end_wall", {}) as Dictionary).is_empty():
		var end_dir: Vector2 = plan.get("end_host_dir", Vector2.ZERO)
		if end_dir.length() > 0.1 and absf(axis.dot(end_dir)) < 0.5:
			specs.append({"point": plan["to"], "dir_a": -axis, "dir_b": end_dir})
	return specs

## Rotation du coin L (`mur_coin.glb`) pour couvrir deux directions sortantes.
## Au repos (rotation 0) ses deux bras regardent vers -X et -Y, comme la Pièce 3D.
func _wall_corner_rotation(dir_a: Vector2, dir_b: Vector2) -> float:
	var candidates: Array = [0.0, 90.0, 180.0, 270.0]
	if dir_a.length() > 0.01:
		candidates.append(rad_to_deg(atan2(-dir_a.y, -dir_a.x)))
	if dir_b.length() > 0.01:
		candidates.append(rad_to_deg(atan2(-dir_b.y, -dir_b.x)))
	var best_rotation := 0.0
	var best_score := -10.0
	for candidate_variant in candidates:
		var rotation := float(candidate_variant)
		var rad := deg_to_rad(rotation)
		var arm_x := Vector2(-1.0, 0.0).rotated(rad)
		var arm_y := Vector2(0.0, -1.0).rotated(rad)
		var score := maxf(arm_x.dot(dir_a) + arm_y.dot(dir_b),
			arm_x.dot(dir_b) + arm_y.dot(dir_a))
		if score > best_score:
			best_score = score
			best_rotation = rotation
	return best_rotation

## Pose (ou réutilise) un coin de mur à une jonction. Renvoie son id.
func _add_wall_junction_corner(point: Vector2, dir_a: Vector2, dir_b: Vector2,
		elevation: float = 0.0) -> String:
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		if not str(elem.get("asset", "")).ends_with("mur_coin.glb"):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		if center.distance_to(point) <= 0.2 \
				and absf(float(elem.get("elevation", 0.0)) - elevation) <= 0.05:
			return str(elem.get("id", ""))
	var bounds := _mesh_bounds_cells(WALL_CORNER_ASSET, 1.0)
	return _ed.doc.add_element({
		"x": point.x, "y": point.y,
		"w": bounds.x, "h": bounds.z,
		"sizeX": bounds.x, "sizeY": _ed._wall_height, "sizeZ": bounds.z,
		"asset": WALL_CORNER_ASSET,
		"elevation": elevation, "followTerrain": true, "tiltToTerrain": false,
		"label": "Coin de mur 3D", "layer": 1,
		"display": {"rotation": _wall_corner_rotation(dir_a, dir_b), "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Coin de mur 3D")

## Retour de construction pendant le tracé : nombre de modules, longueur,
## accroches actives et coin L prévu. Branché sur le statut et l'aperçu.
func _update_wall_draw_status(from: Vector2, to: Vector2) -> void:
	var plan := _wall_chain_plan(from, to)
	if not bool(plan.get("valid", false)):
		_ed._set_status("Mur 3D : tracé trop court (%.2f case)." % (to - from).length())
		return
	var snaps: Array = []
	if str(plan.get("start_snap", "free")) != "free":
		snaps.append("accroche départ")
	if str(plan.get("end_snap", "free")) != "free":
		snaps.append("accroche fin")
	var corners := _wall_chain_corner_specs(plan)
	var extra := ""
	if not snaps.is_empty():
		extra += " · " + ", ".join(snaps)
	if not corners.is_empty():
		extra += " · coin L"
	_ed._set_status("Mur 3D : %d segment(s) de %.2f · hauteur %.2f%s" % [
		int(plan["count"]), float(plan["segment_len"]), _ed._wall_height, extra])

## Vrai si un module de mur déjà posé recouvre ce segment (évite les doublons).
## Un mur de hauteur différente n'est pas considéré comme un doublon : on peut
## volontairement superposer un module plus haut ou plus bas au même endroit.
func _wall_segment_overlaps(center: Vector2, rotation_deg: float, length: float,
		height: float = -1.0) -> bool:
	var rad := deg_to_rad(rotation_deg)
	var axis := Vector2(cos(rad), sin(rad))
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if not _is_wall_mesh(elem):
			continue
		if height >= 0.0 and absf(float(elem.get("sizeY", 0.0)) - height) > 0.05:
			continue
		var other_axis := Vector2(cos(_wall_rotation_rad(elem)), sin(_wall_rotation_rad(elem)))
		if absf(other_axis.dot(axis)) < 0.98:
			continue
		var other_center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var offset := center - other_center
		var along := offset.dot(axis)
		var perpendicular := absf(offset.dot(Vector2(-axis.y, axis.x)))
		if perpendicular > 0.2:
			continue
		var other_length := _wall_length(elem)
		var overlap := minf(along + length * 0.5, other_length * 0.5) \
			- maxf(along - length * 0.5, -other_length * 0.5)
		if overlap > 0.2:
			return true
	return false

## Mur continu lissé : un seul panneau étiré sur tout le tracé, sans les
## micro-segments qui donnaient un aspect « escalier » aux angles.
func _create_mesh_wall_smooth(from: Vector2, to: Vector2, elevation: float = 0.0) -> void:
	var plan := _wall_chain_plan(from, to)
	if not bool(plan.get("valid", false)):
		_ed._set_status("Tracé de mur trop court.")
		return
	var total := float(plan["total"])
	var depth := float(plan["depth"])
	var rotation := float(plan["rotation"])
	var start: Vector2 = plan["from"]
	var end: Vector2 = plan["to"]
	var center := (start + end) * 0.5
	_ed.doc.begin_transaction()
	var id: String = _ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": total, "h": depth,
		"sizeX": total, "sizeY": _ed._wall_height, "sizeZ": depth,
		"asset": WALL_ASSET,
		"elevation": elevation, "followTerrain": true, "tiltToTerrain": false,
		"label": "Mur 3D", "layer": 1,
		"display": {"rotation": rotation, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Mur 3D")
	var ids: Array = [id]
	for corner_variant in _wall_chain_corner_specs(plan):
		var corner: Dictionary = corner_variant
		var corner_id := _add_wall_junction_corner(
			corner["point"], corner["dir_a"], corner["dir_b"], elevation)
		if not corner_id.is_empty() and not ids.has(corner_id):
			ids.append(corner_id)
	_ed.doc.set_selection(ids)
	_ed.doc.commit_transaction()
	_ed._set_status("Mur 3D lissé : %.2f case(s) · hauteur %.2f." % [total, _ed._wall_height])

## Construction « Sims » : une rangée de murs 3D modulaires le long du tracé.
## Les extrémités s'aimantent au réseau existant, la rangée est pavée exactement
## et les coins L sont posés automatiquement.
func _create_mesh_wall_chain(from: Vector2, to: Vector2) -> void:
	var plan := _wall_chain_plan(from, to)
	if not bool(plan.get("valid", false)):
		_ed._set_status("Tracé de mur trop court.")
		return
	var segment_len := float(plan["segment_len"])
	var depth := float(plan["depth"])
	var rotation := float(plan["rotation"])
	var count := int(plan["count"])
	var start: Vector2 = plan["from"]
	var delta: Vector2 = plan["to"] - start
	var ids: Array = []
	var skipped := 0
	_ed.doc.begin_transaction()
	for index in range(count):
		var t := (float(index) + 0.5) / float(count)
		var pos := start + delta * t
		if _wall_segment_overlaps(pos, rotation, segment_len, _ed._wall_height):
			skipped += 1
			continue
		var id: String = _ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": segment_len, "h": depth,
			"sizeX": segment_len, "sizeY": _ed._wall_height, "sizeZ": depth,
			"asset": WALL_ASSET,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Mur 3D", "layer": 1,
			"display": {"rotation": rotation, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Mur 3D")
		ids.append(id)
	var corner_specs := _wall_chain_corner_specs(plan)
	for corner_variant in corner_specs:
		var corner: Dictionary = corner_variant
		var corner_id := _add_wall_junction_corner(
			corner["point"], corner["dir_a"], corner["dir_b"])
		if not corner_id.is_empty() and not ids.has(corner_id):
			ids.append(corner_id)
	_ed.doc.set_selection(ids)
	_ed.doc.commit_transaction()
	var parts: Array = ["%d segment(s)" % (count - skipped)]
	if not corner_specs.is_empty():
		parts.append("%d coin(s) L" % corner_specs.size())
	if skipped > 0:
		parts.append("%d déjà posé(s)" % skipped)
	_ed._set_status("Mur 3D : %s · hauteur %.2f." % [" · ".join(parts), _ed._wall_height])

## Construit une pièce fermée : quatre rangées raccordées. Les coins L sont
## posés automatiquement par les jonctions (plus de coins manuels en double).
## Aplatit l'emprise d'un bâtiment avant d'y poser murs/toit. La hauteur cible
## est la moyenne des coins et du centre, pour ne pas enterrer le bâtiment.
func _flatten_build_footprint(from: Vector2, to: Vector2) -> void:
	if not _ed._flatten_build_footprint:
		return
	var rect := Rect2(Vector2(minf(from.x, to.x), minf(from.y, to.y)),
		Vector2(absf(to.x - from.x), absf(to.y - from.y)))
	var center := (from + to) * 0.5
	var samples: Array = [
		Vector2(rect.position.x, rect.position.y),
		Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y),
		Vector2(rect.end.x, rect.end.y),
		center,
	]
	var total := 0.0
	for sample_variant in samples:
		var sample: Vector2 = sample_variant
		total += _ed.doc.terrain_height(int(round(sample.x)), int(round(sample.y)))
	var target := total / float(samples.size())
	_ed.doc.flatten_terrain_rect(rect, target, "Emprise du bâtiment")

func _create_mesh_room(from: Vector2, to: Vector2, elevation: float = 0.0) -> void:
	var x0 := minf(from.x, to.x)
	var x1 := maxf(from.x, to.x)
	var y0 := minf(from.y, to.y)
	var y1 := maxf(from.y, to.y)
	if x1 - x0 < 1.5 or y1 - y0 < 1.5:
		_ed._set_status("Pièce trop petite (minimum 1,5 × 1,5).")
		return
	if elevation <= 0.01:
		_flatten_build_footprint(from, to)
	var ids: Array = []
	_create_mesh_wall_smooth(Vector2(x0, y0), Vector2(x1, y0), elevation)
	ids.append_array(_ed.doc.selection())
	_create_mesh_wall_smooth(Vector2(x1, y0), Vector2(x1, y1), elevation)
	ids.append_array(_ed.doc.selection())
	_create_mesh_wall_smooth(Vector2(x1, y1), Vector2(x0, y1), elevation)
	ids.append_array(_ed.doc.selection())
	_create_mesh_wall_smooth(Vector2(x0, y1), Vector2(x0, y0), elevation)
	ids.append_array(_ed.doc.selection())
	_ed.doc.set_selection(ids)
	_ed._set_status("Pièce 3D construite : 4 panneaux lissés + coins.")

# ===========================================================================
# Édition directe des murs (poignées)
# ===========================================================================

## Murs dont une extrémité touche une extrémité de `elem` (raccords partagés).
func _wall_attached_ids(elem: Dictionary) -> Array:
	var ids: Array = []
	var self_id := str(elem.get("id", ""))
	for endpoint_variant in _wall_endpoints(elem):
		var endpoint: Vector2 = endpoint_variant
		for other_variant in _ed.doc.elements_sorted():
			var other: Dictionary = other_variant
			if not _is_wall_mesh(other):
				continue
			var other_id := str(other.get("id", ""))
			if other_id == self_id or ids.has(other_id):
				continue
			for other_end_variant in _wall_endpoints(other):
				if (other_end_variant as Vector2).distance_to(endpoint) <= WALL_JOIN_EPS:
					ids.append(other_id)
					break
	return ids

## Étirement d'un mur à la poignée : l'extrémité opposée reste fixe (au lieu de
## dilater les deux), l'extrémité tirée s'aimante au réseau et les murs alignés
## qui partagent cette extrémité suivent (prolongement connecté). La hauteur et
## l'épaisseur du mur sont préservées : les raccords ne cassent pas.
func _apply_wall_handle_resize(id: String, elem: Dictionary, grid: Vector2) -> void:
	var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	var rad := _wall_rotation_rad(elem)
	var axis := Vector2(cos(rad), sin(rad))
	var length := _wall_length(elem)
	var natural := _mesh_bounds_cells(str(elem.get("asset", WALL_ASSET)), 1.0)
	var height := float(elem.get("sizeY", 0.0))
	if height <= 0.0:
		height = natural.y
	var depth := float(elem.get("sizeZ", 0.0))
	if depth <= 0.0:
		depth = maxf(0.3, natural.z)
	var corner = clampi(int(_ed._handle_state.get("corner", 0)), 0, 3)
	var half_w := length * 0.5
	var half_h := maxf(0.1, float(elem.get("h", depth)) * 0.5)
	var corner_offsets := [
		Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
		Vector2(half_w, half_h), Vector2(-half_w, half_h),
	]
	var local_corner: Vector2 = (corner_offsets[corner] as Vector2).rotated(rad)
	var side := 1.0 if local_corner.dot(axis) >= 0.0 else -1.0
	var pull_dir := axis * side
	var fixed_end := center - pull_dir * length * 0.5
	var old_end := center + pull_dir * length * 0.5
	var attached := _wall_attached_ids(elem)
	var skip_ids: Array = [id]
	skip_ids.append_array(attached)
	var new_length := clampf((grid - fixed_end).dot(pull_dir),
		WALL_MIN_SEGMENT, WALL_MAX_SEGMENT)
	var snap := _snap_wall_point(fixed_end + pull_dir * new_length, skip_ids)
	var snapped_type := str(snap.get("kind", "free"))
	if snapped_type != "free":
		new_length = clampf((snap.get("point", fixed_end) - fixed_end).dot(pull_dir),
			WALL_MIN_SEGMENT, WALL_MAX_SEGMENT)
	var new_end := fixed_end + pull_dir * new_length
	var new_center := fixed_end + pull_dir * new_length * 0.5
	_ed.doc.set_live_fields(id, {
		"x": new_center.x, "y": new_center.y,
		"w": new_length, "sizeX": new_length,
		"sizeY": height, "sizeZ": depth,
	})
	# Prolongement connecté : les murs alignés partagent l'extrémité déplacée.
	for attached_variant in attached:
		_move_attached_wall(str(attached_variant), old_end, new_end, id)
	var note := " · accroche" if snapped_type != "free" else ""
	if not attached.is_empty():
		note += " · %d mur(s) raccordé(s)" % attached.size()
	_ed._set_status("Mur : %.2f case(s), hauteur %.2f%s." % [new_length, height, note])

## Déplace l'extrémité d'un mur voisin aligné (prolongement/raccourci connecté).
func _move_attached_wall(wall_id: String, old_point: Vector2, new_point: Vector2, self_id: String) -> void:
	var elem: Dictionary = _ed.doc.get_element(wall_id)
	if elem.is_empty() or not _is_wall_mesh(elem):
		return
	var self_elem: Dictionary = _ed.doc.get_element(self_id)
	var self_axis := Vector2(cos(_wall_rotation_rad(self_elem)), sin(_wall_rotation_rad(self_elem)))
	var endpoints := _wall_endpoints(elem)
	var near_index := -1
	for index in range(2):
		if (endpoints[index] as Vector2).distance_to(old_point) <= WALL_JOIN_EPS:
			near_index = index
			break
	if near_index < 0:
		return
	var axis := Vector2(cos(_wall_rotation_rad(elem)), sin(_wall_rotation_rad(elem)))
	# Seuls les murs quasi alignés suivent : un mur perpendiculaire garde son
	# orientation (le raccord en angle sera retravaillé par les coins).
	if absf(axis.dot(self_axis)) < 0.9:
		return
	var other_end: Vector2 = endpoints[1 - near_index]
	var near_end: Vector2 = endpoints[near_index]
	var toward_near := 1.0 if (near_end - other_end).dot(axis) >= 0.0 else -1.0
	var direction := axis * toward_near
	var new_length := clampf((new_point - other_end).dot(direction),
		WALL_MIN_SEGMENT, WALL_MAX_SEGMENT)
	var new_center := other_end + direction * new_length * 0.5
	_ed.doc.set_live_fields(wall_id, {
		"x": new_center.x, "y": new_center.y,
		"w": new_length, "sizeX": new_length,
	})

## Maison rapide : enchaîne murs, dallage, toit et porte.
func _create_mesh_house(from: Vector2, to: Vector2) -> void:
	var x0 := minf(from.x, to.x)
	var x1 := maxf(from.x, to.x)
	var y0 := minf(from.y, to.y)
	var y1 := maxf(from.y, to.y)
	if x1 - x0 < 2.0 or y1 - y0 < 2.0:
		_ed._set_status("Maison rapide : rectangle trop petit (2 × 2 minimum).")
		return
	var previous_roof = _ed._roof_height
	_ed._roof_height = maxf(_ed._roof_height, _ed._wall_height - 0.15)
	_create_mesh_room(from, to)
	_create_floor(from, to)
	for floor_index in range(1, _ed._house_floors):
		var floor_elevation: float = _ed._wall_height * float(floor_index)
		_create_mesh_room(from, to, floor_elevation)
		if _ed._house_auto_windows:
			var mid_y := (y0 + y1) * 0.5
			_insert_window(Vector2(x0, mid_y), floor_elevation)
			_insert_window(Vector2(x1, mid_y), floor_elevation)
		var slab_id: String = _ed.doc.add_element({
			"x": (x0 + x1) * 0.5, "y": (y0 + y1) * 0.5,
			"w": maxf(1.0, x1 - x0), "h": maxf(1.0, y1 - y0),
			"asset": "procedural://floor",
			"thickness": 0.14,
			"elevation": floor_elevation - 0.14,
			"followTerrain": false, "tiltToTerrain": false,
			"label": "Dalle d'étage", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Dalle d'étage")
		if slab_id.is_empty():
			continue
	var roof_offset: float = _ed._wall_height * float(maxi(0, _ed._house_floors - 1))
	if _ed._house_proc_roof:
		_create_procedural_roof(from, to, roof_offset)
	else:
		_create_mesh_roof(from, to, roof_offset)
	# Porte au centre du mur avant (côté +Y).
	_insert_door(Vector2((x0 + x1) * 0.5, y1))
	if _ed._house_auto_windows:
		var mid_y := (y0 + y1) * 0.5
		_insert_window(Vector2(x0, mid_y))
		_insert_window(Vector2(x1, mid_y))
	if _ed._house_auto_interior:
		_create_interior_at(Vector2((x0 + x1) * 0.5, y1))
	_ed._roof_height = previous_roof
	_ed._set_status("Maison rapide construite : %d étage(s), murs, dallage, toit%s." % [
		_ed._house_floors,
		", porte, fenêtres et intérieur lié" if _ed._house_auto_interior and _ed._house_auto_windows
		else (", porte et intérieur lié" if _ed._house_auto_interior
		else (", porte et fenêtres" if _ed._house_auto_windows else " et porte")),
	])

## Chemin de terre : peint les cases le long du tracé, largeur réglable.
func _create_path(from: Vector2, to: Vector2) -> void:
	var w = int(_ed.doc.map_data.get("width", 0))
	var h = int(_ed.doc.map_data.get("height", 0))
	var dx := to.x - from.x
	var dy := to.y - from.y
	var steps := maxi(1, int(ceil(maxf(absf(dx), absf(dy)) * 2.0)))
	var touched := {}
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var cx := int(round(from.x + dx * t))
		var cy := int(round(from.y + dy * t))
		for ox in range(-_ed._path_width + 1, _ed._path_width):
			for oy in range(-_ed._path_width + 1, _ed._path_width):
				var px := cx + ox
				var py := cy + oy
				if px < 0 or py < 0 or px >= w or py >= h:
					continue
				touched[Vector2i(px, py)] = true
	if touched.is_empty():
		return
	_ed.doc.begin_transaction()
	for cell_variant in touched.keys():
		var cell: Vector2i = cell_variant
		_ed.doc.set_terrain_material(cell.x, cell.y, _ed._path_material, "Chemin")
	_ed.doc.commit_transaction()
	_ed._set_status("Chemin : %d case(s) peinte(s)." % touched.size())
func _create_mesh_fence(from: Vector2, to: Vector2) -> void:
	var delta := to - from
	var total := delta.length()
	if total < 0.5:
		_ed._set_status("Clôture : tracé trop court.")
		return
	var bounds = _mesh_bounds_cells(_ed._fence_asset, 1.0)
	var nominal_len := maxf(1.0, bounds.x)
	var depth := maxf(0.25, bounds.z)
	var rotation := rad_to_deg(atan2(delta.y, delta.x))
	var count := maxi(1, int(round(total / nominal_len)))
	# Pavage exact : la clôture couvre le tracé sans trou ni débordement.
	var segment_len := total / float(count)
	var ids: Array = []
	_ed.doc.begin_transaction()
	for index in range(count):
		var t := (float(index) + 0.5) / float(count)
		var pos := from + delta * t
		var id: String = _ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": segment_len, "h": depth,
			"asset": _ed._fence_asset,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Clôture", "layer": 1,
			"display": {"rotation": rotation, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Clôture")
		ids.append(id)
	_ed.doc.set_selection(ids)
	_ed.doc.commit_transaction()
	_ed._set_status("Clôture : %d segment(s)." % count)

# ===========================================================================
# Tracé organique (freehand, façon Tiny Glade)
# ===========================================================================

func _organic_style_label() -> String:
	for style_variant in ORGANIC_STYLES:
		var style: Dictionary = style_variant
		if str(style["path"]) == _ed._organic_asset:
			return str(style["label"])
	return _ed._organic_asset.get_file().get_basename().capitalize()

func _organic_module_depth(asset: String) -> float:
	return maxf(0.2, _mesh_bounds_cells(asset, 1.0).z)

func _organic_module_height(asset: String) -> float:
	if asset.ends_with("mur.glb"):
		return _ed._wall_height
	var natural := _mesh_bounds_cells(asset, 1.0)
	return natural.y if natural.y > 0.1 else _ed._wall_height

## Accroche début/fin du tracé au réseau de murs existant (mur 3D uniquement).
func _snap_organic_endpoints(points: Array, asset: String) -> Array:
	var out: Array = points.duplicate()
	if not asset.ends_with("mur.glb") or out.size() < 2:
		return out
	out[0] = _snap_wall_endpoint(out[0])
	out[out.size() - 1] = _snap_wall_endpoint(out[out.size() - 1])
	return out

## Construit une courbe organique en modules orientés tangente.
## Renvoie les ids des modules (transaction unique, sélection finale).
func _build_organic_chain(points: Array) -> Array:
	var ids: Array = []
	if points.size() < 2:
		return ids
	var asset = _ed._organic_asset
	var depth := _organic_module_depth(asset)
	var height := _organic_module_height(asset)
	var nominal := maxf(0.8, _mesh_bounds_cells(asset, 1.0).x)
	var spacing = _ed._organic_spacing if _ed._organic_spacing > 0.0 else nominal
	var snapped := _snap_organic_endpoints(points, asset)
	var modules := OrganicPathScript.build_chain(snapped, {
		"smoothing": _ed._organic_smoothing,
		"spacing": spacing,
		"nominal_length": nominal,
		"nominal_depth": depth,
	})
	if modules.is_empty():
		_ed._set_status("Tracé organique : geste trop court.")
		return ids
	var label := "%s (organique)" % _organic_style_label()
	_ed.doc.begin_transaction()
	for module_variant in modules:
		var module: Dictionary = module_variant
		var id: String = _ed.doc.add_element({
			"x": float(module["x"]), "y": float(module["y"]),
			"w": float(module["length"]), "h": depth,
			"sizeX": float(module["length"]), "sizeY": height, "sizeZ": depth,
			"asset": asset,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": label, "layer": 1,
			"display": {"rotation": float(module["rotation"]), "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Tracé organique")
		ids.append(id)
	_ed.doc.set_selection(ids)
	_ed.doc.commit_transaction()
	return ids

## Mur procédural : une seule entrée de mesh dont le tracé devient un vrai
## ruban maillé (mitres), au lieu d'une suite de modules GLB.
func _build_procedural_wall(raw_points: Array) -> String:
	var curve := OrganicPathScript.path_points(raw_points, {
		"smoothing": _ed._organic_smoothing,
		"spacing": 0.35,
		"nominal_length": 0.5,
	})
	if curve.size() < 2:
		return ""
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for point_variant in curve:
		var p: Vector2 = point_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for point_variant in curve:
		var p: Vector2 = point_variant - center
		local.append([p.x, p.y])
	var id: String = _ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x),
		"h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://wall",
		"points": local,
		"height": maxf(0.5, _ed._wall_height),
		"thickness": 0.7,
		"bevel": 0.12,
		"color": _ed._proc_wall_color,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": "Mur procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Mur procédural")
	_ed.doc.select_only(id)
	return id

func _build_procedural_fence(raw_points: Array) -> String:
	var curve := OrganicPathScript.path_points(raw_points, {
		"smoothing": _ed._organic_smoothing,
		"spacing": 0.3,
		"nominal_length": 0.5,
	})
	if curve.size() < 2:
		return ""
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for point_variant in curve:
		var p: Vector2 = point_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for point_variant in curve:
		var p: Vector2 = point_variant - center
		local.append([p.x, p.y])
	var id: String = _ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x),
		"h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://fence",
		"points": local,
		"height": _ed._proc_fence_height,
		"spacing": _ed._proc_fence_spacing,
		"fenceTone": _ed._proc_fence_tone,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": "Clôture procédurale", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Clôture procédurale")
	_ed.doc.select_only(id)
	return id

func _build_procedural_path(raw_points: Array) -> String:
	var curve := OrganicPathScript.path_points(raw_points, {
		"smoothing": _ed._organic_smoothing,
		"spacing": 0.4,
		"nominal_length": 0.5,
	})
	if curve.size() < 2:
		return ""
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for point_variant in curve:
		var p: Vector2 = point_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for point_variant in curve:
		var p: Vector2 = point_variant - center
		local.append([p.x, p.y])
	var id: String = _ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x),
		"h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://path",
		"points": local,
		"width": maxf(0.3, _ed._proc_path_width),
		"color": _ed._proc_path_color,
		"elevation": 0.01, "followTerrain": true, "tiltToTerrain": false,
		"label": "Chemin procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Chemin procédural")
	_ed.doc.select_only(id)
	return id

func _build_procedural_poly_roof(raw_points: Array) -> String:
	if raw_points.size() < 3:
		return ""
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p_variant in raw_points:
		var p: Vector2 = p_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for p_variant in raw_points:
		var p: Vector2 = (p_variant as Vector2) - center
		local.append([p.x, p.y])
	var id: String = _ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://poly_roof",
		"points": local,
		"height": _ed._proc_poly_roof_height,
		"color": "#a84f3f",
		"elevation": _ed._roof_height, "followTerrain": false, "tiltToTerrain": false,
		"label": "Toit libre", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Toit libre")
	_ed.doc.select_only(id)
	return id

func _finish_organic_stroke() -> void:
	var points: Array = _ed._organic_points.duplicate()
	_ed._organic_points.clear()
	_ed._overlay.polygon_points.clear()
	_ed._press_mode = "none"
	if points.size() < 2:
		_ed._set_status("Tracé organique : geste trop court (clic-glissez pour dessiner).")
		_ed._refresh_overlay()
		return
	var length := OrganicPathScript.total_length(points)
	if length < 0.8:
		_ed._set_status("Tracé organique : %.2f case — tracé trop court." % length)
		_ed._refresh_overlay()
		return
	if _ed._tool == ToolsScript.PROC_WALL:
		var proc_id := _build_procedural_wall(points)
		if not proc_id.is_empty():
			_ed._set_status("Mur procédural : %.2f case(s), mesh continu." % length)
			_ed._sync_engine()
		_ed._refresh_panels()
		_ed._refresh_overlay()
		return
	if _ed._tool == ToolsScript.PROC_FENCE:
		var fence_id := _build_procedural_fence(points)
		if not fence_id.is_empty():
			_ed._set_status("Clôture procédurale : %.2f case(s), poteaux et lisses." % length)
			_ed._sync_engine()
		_ed._refresh_panels()
		_ed._refresh_overlay()
		return
	if _ed._tool == ToolsScript.PROC_PATH:
		var path_id := _build_procedural_path(points)
		if not path_id.is_empty():
			_ed._set_status("Chemin procédural : %.2f case(s), ruban continu." % length)
			_ed._sync_engine()
		_ed._refresh_panels()
		_ed._refresh_overlay()
		return
	if _ed._tool == ToolsScript.PROC_POLY_ROOF:
		var roof_id := _build_procedural_poly_roof(points)
		if not roof_id.is_empty():
			_ed._set_status("Toit libre : %d point(s), pans triangulés." % points.size())
			_ed._sync_engine()
		_ed._refresh_panels()
		_ed._refresh_overlay()
		return
	var ids := _build_organic_chain(points)
	if not ids.is_empty():
		_ed._set_status("Tracé organique : %d module(s) · %.2f case(s) · %s." % [
			ids.size(), length, _organic_style_label()])
		_ed._sync_engine()
	_ed._refresh_panels()
	_ed._refresh_overlay()

func _preview_organic_status() -> void:
	var length = OrganicPathScript.total_length(_ed._organic_points)
	_ed._set_status("Tracé organique : %d point(s) · %.2f case(s) · relâchez pour construire." % [
		_ed._organic_points.size(), length])

# ===========================================================================
# Décor auto / végétation au pinceau
# ===========================================================================

func _scatter_assets() -> Array:
	return OrganicScatterScript.mode_asset_paths(_ed._scatter_mode)

func _scatter_cell_key(cell: Vector2i) -> String:
	return OrganicScatterScript.cell_key(cell)

func _scatter_cell_is_water(cell: Vector2i) -> bool:
	var water = float(_ed.doc.map_data.get("waterLevel", -1.0))
	if water < 0.0:
		return false
	var heights_variant = _ed.doc.map_data.get("terrainHeights", [])
	if not heights_variant is Array:
		return false
	var width = int(_ed.doc.map_data.get("width", 0))
	var heights: Array = heights_variant
	var index = cell.y * width + cell.x
	if index < 0 or index >= heights.size():
		return false
	return float(heights[index]) < water - 0.001

func _scatter_cell_available(cell: Vector2i) -> bool:
	var width = int(_ed.doc.map_data.get("width", 0))
	var height = int(_ed.doc.map_data.get("height", 0))
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	if _ed._scatter_occupied.has(_scatter_cell_key(cell)):
		return false
	if _scatter_cell_is_water(cell):
		return false
	return true

## Prépare un trait : graine déterministe, cases déjà occupées (_ed.doc + eau).
func _scatter_prepare_stroke() -> void:
	_ed._scatter_active = true
	_ed._scatter_ids = []
	_ed._scatter_occupied.clear()
	for elem_variant in _ed.doc.elements_of_kind(DocumentScript.KIND_MESH):
		var elem: Dictionary = elem_variant
		var cell := Vector2i(int(round(float(elem.get("x", 0.0)))),
			int(round(float(elem.get("y", 0.0)))))
		_ed._scatter_occupied[_scatter_cell_key(cell)] = true
	_ed._scatter_rng = RandomNumberGenerator.new()
	var seed_value = _ed._scatter_seed
	if seed_value == 0:
		seed_value = int(Time.get_ticks_usec())
	_ed._scatter_rng.seed = seed_value

func _start_scatter_stroke(grid: Vector2) -> void:
	_scatter_prepare_stroke()
	_ed._scatter_last_point = grid
	_ed.doc.begin_transaction()
	_scatter_stamp(grid)
	_ed._set_status("Décor auto : %s — glissez pour disperser (%d objet(s))." % [
		OrganicScatterScript.mode_label(_ed._scatter_mode), _ed._scatter_ids.size()])

func _continue_scatter_stroke(grid: Vector2) -> void:
	if not _ed._scatter_active:
		return
	_scatter_walk(_ed._scatter_last_point, grid)
	_ed._set_status("Décor auto : %d objet(s) — relâchez pour terminer." % _ed._scatter_ids.size())

func _scatter_walk(from: Vector2, to: Vector2) -> void:
	var distance := from.distance_to(to)
	if distance < 0.01:
		return
	var step = maxf(0.2, 0.75 / clampf(_ed._scatter_density, 0.2, 4.0))
	var stamps := maxi(1, int(ceil(distance / step)))
	for i in range(1, stamps + 1):
		_scatter_stamp(from.lerp(to, float(i) / float(stamps)))
	_ed._scatter_last_point = to

func _scatter_stamp(point: Vector2) -> void:
	if _scatter_assets().is_empty():
		return
	if _ed._scatter_zone_mode:
		_scatter_stamp_zone(point)
		return
	var per_stamp = maxi(1, int(round(_ed._scatter_density * 0.8)))
	for _i in range(per_stamp):
		var angle = _ed._scatter_rng.randf_range(0.0, TAU)
		var radius = sqrt(_ed._scatter_rng.randf()) * maxf(0.0, _ed._scatter_radius)
		_scatter_try_place(point + Vector2(cos(angle), sin(angle)) * radius, point)

## Mode « dans la zone » : remplit un disque de cases autour du pinceau.
func _scatter_stamp_zone(point: Vector2) -> void:
	var center := Vector2i(int(round(point.x)), int(round(point.y)))
	var radius = maxf(1.0, _ed._scatter_radius)
	var reach := int(ceil(radius))
	var chance = clampf(_ed._scatter_density * 0.35, 0.05, 0.9)
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			if Vector2(float(dx), float(dy)).length() > radius:
				continue
			if _ed._scatter_rng.randf() > chance:
				continue
			var jitter = Vector2(_ed._scatter_rng.randf_range(-0.4, 0.4),
				_ed._scatter_rng.randf_range(-0.4, 0.4))
			_scatter_try_place(Vector2(center.x + dx, center.y + dy) + jitter, point)

func _scatter_try_place(position: Vector2, _anchor: Vector2) -> void:
	var cell := Vector2i(int(round(position.x)), int(round(position.y)))
	if not _scatter_cell_available(cell):
		return
	var assets := _scatter_assets()
	if assets.is_empty():
		return
	var asset = str(assets[_ed._scatter_rng.randi_range(0, assets.size() - 1)])
	var scale = maxf(0.2, _ed._scatter_size * _ed._scatter_rng.randf_range(0.85, 1.15))
	var rotation = _ed._scatter_rng.randf_range(0.0, 360.0)
	var id := _place_scatter_item(asset, position, rotation, scale)
	if id.is_empty():
		return
	_ed._scatter_occupied[_scatter_cell_key(cell)] = true
	_ed._scatter_ids.append(id)

func _place_scatter_item(asset: String, position: Vector2, rotation: float,
		scale: float) -> String:
	if not ResourceLoader.exists(asset) \
			and not FileAccess.file_exists(ProjectSettings.globalize_path(asset)):
		return ""
	var natural := _mesh_bounds_cells(asset, 1.0)
	var width := maxf(0.2, natural.x * scale)
	var depth := maxf(0.2, natural.z * scale)
	var label := asset.get_file().get_basename().replace("_", " ").capitalize()
	var id: String = _ed.doc.add_element({
		"x": position.x, "y": position.y,
		"w": width, "h": depth,
		"sizeX": maxf(0.05, natural.x), "sizeY": maxf(0.05, natural.y),
		"sizeZ": maxf(0.05, natural.z),
		"asset": asset,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": label, "layer": 1,
		"display": {"rotation": rotation, "scale": scale},
	}, DocumentScript.KIND_MESH, "Décor auto")
	return id

func _finish_scatter_stroke() -> void:
	if not _ed._scatter_active:
		_ed._press_mode = "none"
		return
	_ed._scatter_active = false
	_ed.doc.commit_transaction()
	_ed._press_mode = "none"
	var count = _ed._scatter_ids.size()
	_ed._scatter_ids = []
	if count > 0:
		_ed._set_status("Décor auto : %d objet(s) · %s · annulable en un geste." % [
			count, OrganicScatterScript.mode_label(_ed._scatter_mode)])
		_ed._sync_engine()
	else:
		_ed._set_status("Décor auto : aucun objet posé (cases occupées, eau ou hors carte).")
	_ed._refresh_overlay()

## Trait complet sur une polyligne (démo + tests) : une seule transaction.
func _scatter_stroke_points(points: Array) -> Array:
	var ids: Array = []
	if points.is_empty():
		return ids
	_scatter_prepare_stroke()
	_ed.doc.begin_transaction()
	_ed._scatter_last_point = points[0]
	_scatter_stamp(points[0])
	for i in range(1, points.size()):
		_scatter_walk(points[i - 1], points[i])
	ids = _ed._scatter_ids.duplicate()
	_finish_scatter_stroke()
	return ids

## Pose un escalier extérieur, adossé au mur 3D le plus proche si possible.
func _insert_stairs(grid: Vector2) -> void:
	var wall: Dictionary = {}
	var best := 2.5
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		if not str(elem.get("asset", "")).ends_with("mur.glb"):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var distance := center.distance_to(grid)
		if distance < best:
			best = distance
			wall = elem
	var asset := "res://assets/objects3d/buildings/escalier_exterieur.glb"
	var bounds := _mesh_aabb_cells(asset, 1.0)
	var rotation = _ed._mesh_rotation
	var pos := grid
	var elevation := 0.0
	var follow := true
	if not wall.is_empty():
		var display: Dictionary = wall.get("display", {}) if wall.get("display") is Dictionary else {}
		rotation = float(display.get("rotation", 0.0))
		var natural := _mesh_bounds_cells(str(wall.get("asset", "")), 1.0)
		var depth := float(wall.get("sizeZ", 0.0))
		if depth <= 0.0:
			depth = natural.z
		var rad := deg_to_rad(rotation)
		var front := Vector2(-sin(rad), cos(rad))
		var back_offset := maxf(0.0, -bounds.position.z)
		pos = Vector2(float(wall.get("x", grid.x)), float(wall.get("y", grid.y))) \
			+ front * (depth * 0.5 + back_offset)
		follow = bool(wall.get("followTerrain", true))
		elevation = float(wall.get("elevation", 0.0))
	var id: String = _ed.doc.add_element({
		"x": pos.x, "y": pos.y,
		"w": bounds.size.x, "h": bounds.size.z,
		"asset": asset, "elevation": elevation,
		"followTerrain": follow, "tiltToTerrain": false,
		"label": "Escalier extérieur", "layer": 1,
		"display": {"rotation": rotation, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Escalier")
	_ed.doc.select_only(id)
	_ed._set_status("Escalier 3D posé%s." % (" contre la façade" if not wall.is_empty() else " libre"))

## Crée le lieu d'entrée d'une porte 3D, sa carte intérieure indépendante
## (12 × 9, pièce de départ) et ouvre cette carte.
func _create_interior_at(grid: Vector2) -> void:
	var door: Dictionary = {}
	var best := 3.0
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		if not str(elem.get("asset", "")).ends_with("porte_auvent.glb"):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var distance := center.distance_to(grid)
		if distance < best:
			best = distance
			door = elem
	if door.is_empty():
		_ed._set_status("Intérieur : cliquez sur une porte 3D (🚪 Porte 3D).")
		return
	var parent_id = str(_ed.doc.map_data.get("id", ""))
	if parent_id.is_empty():
		return
	var door_center := Vector2(float(door.get("x", grid.x)), float(door.get("y", grid.y)))
	# Si un lieu lié existe déjà à cet endroit, on l'ouvre au lieu de dupliquer.
	for area_variant in _ed.doc.map_data.get("areas", []):
		if not area_variant is Dictionary:
			continue
		var area: Dictionary = area_variant
		var target := str(area.get("targetMapId", ""))
		if target.is_empty():
			continue
		var area_center := Vector2(float(area.get("x", 0.0)), float(area.get("y", 0.0)))
		if area_center.distance_to(door_center) <= 3.0:
			_ed._set_status("Intérieur déjà lié : ouverture de « %s »." % area.get("label", "lieu"))
			_open_interior_map(target)
			return
	var label := "Intérieur de maison"
	var area_id: String = _ed.doc.add_element({
		"x": door_center.x, "y": door_center.y,
		"w": 2.4, "h": 2.4,
		"shape": "rect",
		"category": "building",
		"icon": "🚪",
		"label": label,
		"targetMapId": "",
		"showCallout": true,
		"labelOffset": {"x": 0.0, "y": -2.0},
		"layer": 5,
	}, DocumentScript.KIND_AREA, "Lieu d'intérieur")
	_ed.save_now()
	var child := MapData.create_child_map_for_area(parent_id, area_id, 12, 9)
	if child.is_empty():
		_ed._set_status("Intérieur : impossible de créer la carte enfant.")
		return
	var child_id := str(child.get("id", ""))
	_build_starter_interior(child, parent_id)
	# Recharge le parent pour récupérer targetMapId, puis sélectionne le lieu.
	_ed.doc.load_map(MapData.get_by_id(parent_id))
	_ed._sync_settings_ui()
	_ed.doc.select_only(area_id)
	_ed._refresh_panels()
	_ed._refresh_breadcrumb()
	_ed._refresh_overlay()
	_ed._set_status("Intérieur créé (12 × 9). Ouverture de la carte intérieure…")
	_open_interior_map(child_id)

func _open_interior_map(map_id: String) -> void:
	if map_id.is_empty() or MapData.get_by_id(map_id).is_empty():
		return
	if not _ed.open_map_requested.get_connections().is_empty():
		_ed.open_map_requested.emit(map_id)
		return
	_ed.load_map(MapData.get_by_id(map_id))
	_ed._set_tool(ToolsScript.SELECT)

## Construit une petite pièce de départ dans la carte intérieure.
func _build_starter_interior(child: Dictionary, parent_id: String) -> void:
	var w := int(child.get("width", 12))
	var h := int(child.get("height", 9))
	child["fogEnabled"] = false
	child["ambientFx"] = "dust"
	child["renderStyle"] = str(_ed.doc.map_data.get("renderStyle", "2.5d"))
	child["groundMode"] = "terrain3d"
	var materials: Array = []
	materials.resize(w * h)
	materials.fill(2)
	var heights: Array = []
	heights.resize(w * h)
	heights.fill(0.0)
	var meshes: Array = []
	var x0 := 2.0
	var x1 := float(w - 2)
	var y0 := 2.0
	var y1 := float(h - 2)
	var wall_height := 2.2
	_append_interior_wall_chain(meshes, Vector2(x0, y0), Vector2(x1, y0), wall_height)
	_append_interior_wall_chain(meshes, Vector2(x1, y0), Vector2(x1, y1), wall_height)
	_append_interior_wall_chain(meshes, Vector2(x1, y1), Vector2(x0, y1), wall_height)
	_append_interior_wall_chain(meshes, Vector2(x0, y1), Vector2(x0, y0), wall_height)
	var corner_asset := "res://assets/objects3d/buildings/mur_coin.glb"
	var corner_bounds := _mesh_bounds_cells(corner_asset, 1.0)
	for corner_variant in [
		[Vector2(x0, y0), 180.0], [Vector2(x1, y0), 270.0],
		[Vector2(x1, y1), 0.0], [Vector2(x0, y1), 90.0],
	]:
		var corner: Array = corner_variant
		_append_interior_mesh(meshes, corner_asset, corner[0],
			corner_bounds.x, corner_bounds.z, wall_height, float(corner[1]), "Coin de mur 3D")
	var door_asset := "res://assets/objects3d/buildings/porte_auvent.glb"
	var door_bounds := _mesh_aabb_cells(door_asset, 1.0)
	_append_interior_mesh(meshes, door_asset, Vector2((x0 + x1) * 0.5, y1),
		door_bounds.size.x, door_bounds.size.z, door_bounds.size.y, 0.0, "Porte à auvent")
	var table_asset := "res://assets/objects3d/props/table_tabourets.glb"
	if ResourceLoader.exists(table_asset):
		var table_bounds := _mesh_aabb_cells(table_asset, 1.0)
		_append_interior_mesh(meshes, table_asset, Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5),
			table_bounds.size.x, table_bounds.size.z, table_bounds.size.y, 0.0, "Table")
	child["terrainMaterials"] = materials
	child["terrainHeights"] = heights
	child["meshes"] = meshes
	child["areas"] = [{
		"id": MapData.generate_id("area"),
		"x": (x0 + x1) * 0.5, "y": float(h) - 1.0,
		"w": 2.4, "h": 1.2, "shape": "rect", "category": "exit",
		"icon": "⬅", "label": "Sortie", "targetMapId": parent_id,
		"showCallout": true, "labelOffset": {"x": 0.0, "y": 1.2}, "layer": 5,
	}]
	MapData.update_map(child)

func _append_interior_mesh(meshes: Array, asset: String, pos: Vector2,
		size_x: float, size_z: float, height: float, rotation: float, label: String) -> void:
	meshes.append({
		"id": MapData.generate_id("mesh"),
		"kind": DocumentScript.KIND_MESH,
		"x": pos.x, "y": pos.y,
		"w": size_x, "h": size_z,
		"sizeX": size_x, "sizeY": height, "sizeZ": size_z,
		"asset": asset, "elevation": 0.0,
		"followTerrain": true, "tiltToTerrain": false,
		"label": label, "layer": 1,
		"display": {"rotation": rotation, "scale": 1.0},
	})

func _append_interior_wall_chain(meshes: Array, from: Vector2, to: Vector2, height: float) -> void:
	var delta := to - from
	var total := delta.length()
	if total < 0.5:
		return
	var asset := "res://assets/objects3d/buildings/mur.glb"
	var bounds := _mesh_bounds_cells(asset, 1.0)
	var segment_len := maxf(0.5, bounds.x)
	var depth := maxf(0.2, bounds.z)
	var rotation := rad_to_deg(atan2(delta.y, delta.x))
	var count := maxi(1, int(round(total / segment_len)))
	for index in range(count):
		var t := (float(index) + 0.5) / float(count)
		_append_interior_mesh(meshes, asset, from + delta * t,
			total / float(count), depth, height, rotation, "Mur 3D")

func _insert_furniture(grid: Vector2) -> void:
	var preset: Dictionary = {}
	for preset_variant in FURNITURE_PRESETS:
		var candidate: Dictionary = preset_variant
		if str(candidate["id"]) == _ed._furnish_preset:
			preset = candidate
			break
	if preset.is_empty():
		return
	var ids: Array = []
	_ed.doc.begin_transaction()
	for item_variant in preset.get("items", []):
		var item: Array = item_variant
		var asset_name := str(item[0])
		var path := "res://assets/objects3d/props/%s.glb" % asset_name
		if not ResourceLoader.exists(path):
			path = "res://assets/objects3d/vegetation/%s.glb" % asset_name
		if not ResourceLoader.exists(path):
			continue
		var bounds := _mesh_bounds_cells(path, 1.0)
		var pos := Vector2(grid.x + float(item[1]), grid.y + float(item[2]))
		var id: String = _ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": maxf(0.4, bounds.x), "h": maxf(0.4, bounds.z),
			"asset": path, "elevation": 0.0,
			"followTerrain": true, "tiltToTerrain": false,
			"label": asset_name.capitalize(), "layer": 1,
			"display": {"rotation": float(item[3]), "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Mobilier")
		ids.append(id)
	_ed.doc.set_selection(ids)
	_ed.doc.commit_transaction()
	_ed._set_status("Meublé : %s (%d objets)." % [str(preset["label"]), ids.size()])
func _insert_window(grid: Vector2, target_elevation: float = -9999.0) -> void:
	var wall: Dictionary = {}
	var best := 2.5
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		if not str(elem.get("asset", "")).ends_with("mur.glb"):
			continue
		if target_elevation > -9998.0 \
				and absf(float(elem.get("elevation", 0.0)) - target_elevation) > 0.2:
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var distance := center.distance_to(grid)
		if distance < best:
			best = distance
			wall = elem
	if wall.is_empty():
		var proc_window := _nearest_procedural_wall(grid)
		if not proc_window.is_empty():
			_insert_window_procedural(proc_window, grid)
			return
		_ed._set_status("Fenêtre 3D : cliquez près d'un mur 3D.")
		return
	var display: Dictionary = wall.get("display", {}) if wall.get("display") is Dictionary else {}
	var rotation := float(display.get("rotation", 0.0))
	var natural := _mesh_bounds_cells(str(wall.get("asset", "")), 1.0)
	var depth := float(wall.get("sizeZ", 0.0))
	if depth <= 0.0:
		depth = natural.z
	var rad := deg_to_rad(rotation)
	var front := Vector2(-sin(rad), cos(rad))
	var window_asset := "res://assets/objects3d/buildings/fenetre_volets.glb"
	var win_bounds := _mesh_aabb_cells(window_asset, 1.0)
	var back_offset := maxf(0.0, -win_bounds.position.z)
	if back_offset <= 0.001:
		back_offset = maxf(0.0, win_bounds.size.z * 0.5)
	var center := Vector2(float(wall.get("x", grid.x)), float(wall.get("y", grid.y)))
	var offset := depth * 0.5 + back_offset
	var wall_asset := str(wall.get("asset", ""))
	var wall_elevation := float(wall.get("elevation", 0.0))
	var wall_length := float(wall.get("sizeX", 0.0))
	if wall_length <= 0.0:
		wall_length = natural.x
	var wall_height := float(wall.get("sizeY", 0.0))
	if wall_height <= 0.0:
		wall_height = natural.y
	var window_bottom := 1.0
	var window_top := window_bottom + win_bounds.size.y
	var gap := win_bounds.size.x + 0.2
	var can_cut := wall_height >= window_top + 0.15 and wall_length >= gap + 0.2
	if can_cut:
		var wall_id := str(wall.get("id", ""))
		var follow := bool(wall.get("followTerrain", true))
		var elevation := float(wall.get("elevation", 0.0))
		var layer := int(wall.get("layer", 1))
		var along := Vector2(cos(rad), sin(rad))
		var piece_len := (wall_length - gap) * 0.5
		_ed.doc.begin_transaction()
		_ed.doc.remove_element(wall_id)
		for side in [-1.0, 1.0]:
			var pos := center + along * (float(side) * (gap * 0.5 + piece_len * 0.5))
			_ed.doc.add_element({
				"x": pos.x, "y": pos.y, "w": piece_len, "h": depth,
				"sizeX": piece_len, "sizeY": wall_height, "sizeZ": depth,
				"asset": wall_asset, "elevation": elevation,
				"followTerrain": follow, "tiltToTerrain": false,
				"label": "Mur 3D", "layer": layer,
				"display": {"rotation": rotation, "scale": 1.0},
			}, DocumentScript.KIND_MESH, "Mur 3D")
		# Appui sous la fenêtre.
		_ed.doc.add_element({
			"x": center.x, "y": center.y, "w": gap, "h": depth,
			"sizeX": gap, "sizeY": window_bottom, "sizeZ": depth,
			"asset": wall_asset, "elevation": elevation,
			"followTerrain": follow, "tiltToTerrain": false,
			"label": "Mur 3D", "layer": layer,
			"display": {"rotation": rotation, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Mur 3D")
		# Linteau au-dessus.
		var lintel_h := wall_height - window_top
		if lintel_h > 0.05:
			_ed.doc.add_element({
				"x": center.x, "y": center.y, "w": gap, "h": depth,
				"sizeX": gap, "sizeY": lintel_h, "sizeZ": depth,
				"asset": wall_asset, "elevation": elevation + window_top,
				"followTerrain": follow, "tiltToTerrain": false,
				"label": "Mur 3D", "layer": layer,
				"display": {"rotation": rotation, "scale": 1.0},
			}, DocumentScript.KIND_MESH, "Mur 3D")
	var id: String = _ed.doc.add_element({
		"x": center.x + front.x * offset, "y": center.y + front.y * offset,
		"w": win_bounds.size.x, "h": win_bounds.size.z,
		"asset": window_asset, "elevation": wall_elevation + window_bottom - win_bounds.position.y if can_cut else wall_elevation,
		"followTerrain": bool(wall.get("followTerrain", true)), "tiltToTerrain": false,
		"label": "Fenêtre à volets", "layer": int(wall.get("layer", 1)),
		"display": {"rotation": rotation, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Fenêtre")
	if can_cut:
		_ed.doc.commit_transaction()
	_ed.doc.select_only(id)
	_ed._set_status("Fenêtre 3D posée%s." % (" avec ouverture réelle" if can_cut else " sur la façade (mur trop bas pour une ouverture)"))

## Fenêtre dans un mur procédural : montants + appui + linteau procéduraux.
func _insert_window_procedural(wall: Dictionary, grid: Vector2) -> void:
	var points := _procedural_world_points(wall)
	if points.size() < 2:
		return
	var total := 0.0
	for i in range(points.size() - 1):
		total += (points[i] as Vector2).distance_to(points[i + 1])
	var window_asset := "res://assets/objects3d/buildings/fenetre_volets.glb"
	var win_bounds := _mesh_aabb_cells(window_asset, 1.0)
	var gap := win_bounds.size.x + 0.2
	var wall_height := float(wall.get("height", 2.2))
	var window_bottom := 1.0
	var window_top := window_bottom + win_bounds.size.y
	if wall_height < window_top + 0.15 or total < gap + 0.8:
		_ed._set_status("Fenêtre 3D : mur procédural trop bas/court pour une ouverture.")
		return
	var best_s := 0.0
	var best_d := INF
	var walked := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.000001:
			continue
		var t := clampf((grid - a).dot(ab) / len_sq, 0.0, 1.0)
		var d := grid.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_s = walked + sqrt(len_sq) * t
		walked += sqrt(len_sq)
	var start := clampf(best_s - gap * 0.5, 0.0, total)
	var end := clampf(best_s + gap * 0.5, 0.0, total)
	var left := _slice_polyline(points, 0.0, start)
	var right := _slice_polyline(points, end, total)
	var opening_center := _point_on_polyline(points, best_s)
	var tangent := _point_on_polyline(points, minf(best_s + 0.1, total)) - _point_on_polyline(points, maxf(best_s - 0.1, 0.0))
	var rotation := rad_to_deg(atan2(tangent.y, tangent.x))
	var sill_template: Dictionary = wall.duplicate(true)
	sill_template["height"] = window_bottom
	sill_template["elevation"] = float(wall.get("elevation", 0.0))
	var lintel_template: Dictionary = wall.duplicate(true)
	lintel_template["height"] = wall_height - window_top
	lintel_template["elevation"] = float(wall.get("elevation", 0.0)) + window_top
	_ed.doc.begin_transaction()
	_ed.doc.remove_element(str(wall.get("id", "")))
	_add_procedural_wall_run(left, wall)
	_add_procedural_wall_run(right, wall)
	_add_procedural_wall_run([
		_point_on_polyline(points, start), _point_on_polyline(points, end),
	], sill_template)
	_add_procedural_wall_run([
		_point_on_polyline(points, start), _point_on_polyline(points, end),
	], lintel_template)
	var window_id: String = _ed.doc.add_element({
		"x": opening_center.x, "y": opening_center.y,
		"w": win_bounds.size.x, "h": win_bounds.size.z,
		"asset": window_asset,
		"elevation": float(wall.get("elevation", 0.0)) + window_bottom - win_bounds.position.y,
		"followTerrain": true, "tiltToTerrain": false,
		"label": "Fenêtre à volets", "layer": 1,
		"display": {"rotation": rotation, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Fenêtre")
	_ed.doc.select_only(window_id)
	_ed.doc.commit_transaction()
	_ed._sync_engine()
	_ed._set_status("Fenêtre 3D insérée dans le mur procédural : ouverture %.2f." % gap)

func _insert_door(grid: Vector2) -> void:
	var wall: Dictionary = {}
	var best := 2.5
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		if not str(elem.get("asset", "")).ends_with("mur.glb"):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var distance := center.distance_to(grid)
		if distance < best:
			best = distance
			wall = elem
	if wall.is_empty():
		var proc_wall := _nearest_procedural_wall(grid)
		if not proc_wall.is_empty():
			_insert_door_procedural(proc_wall, grid)
			return
		_ed._set_status("Porte 3D : cliquez près d'un mur 3D.")
		return
	var display: Dictionary = wall.get("display", {}) if wall.get("display") is Dictionary else {}
	var rotation := float(display.get("rotation", 0.0))
	var wall_asset := str(wall.get("asset", ""))
	var natural := _mesh_bounds_cells(wall_asset, 1.0)
	var length := float(wall.get("sizeX", 0.0))
	if length <= 0.0:
		length = natural.x
	var height := float(wall.get("sizeY", 0.0))
	if height <= 0.0:
		height = natural.y
	var depth := float(wall.get("sizeZ", 0.0))
	if depth <= 0.0:
		depth = natural.z
	var door_asset := "res://assets/objects3d/buildings/porte_auvent.glb"
	var door_bounds := _mesh_bounds_cells(door_asset, 1.0)
	var gap := maxf(1.0, door_bounds.x)
	if length < gap + 0.6:
		_ed._set_status("Porte 3D : mur trop court pour une ouverture.")
		return
	var center := Vector2(float(wall.get("x", grid.x)), float(wall.get("y", grid.y)))
	var rad := deg_to_rad(rotation)
	var along := Vector2(cos(rad), sin(rad))
	var front := Vector2(-sin(rad), cos(rad))
	var piece_len := (length - gap) * 0.5
	var wall_id := str(wall.get("id", ""))
	var follow := bool(wall.get("followTerrain", true))
	var elevation := float(wall.get("elevation", 0.0))
	var layer := int(wall.get("layer", 1))
	_ed.doc.begin_transaction()
	_ed.doc.remove_element(wall_id)
	for side in [-1.0, 1.0]:
		var pos := center + along * (float(side) * (gap * 0.5 + piece_len * 0.5))
		_ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": piece_len, "h": depth,
			"sizeX": piece_len, "sizeY": height, "sizeZ": depth,
			"asset": wall_asset, "elevation": elevation,
			"followTerrain": follow, "tiltToTerrain": false,
			"label": "Mur 3D", "layer": layer,
			"display": {"rotation": rotation, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Mur 3D")
	var door_id: String = _ed.doc.add_element({
		"x": center.x + front.x * 0.02, "y": center.y + front.y * 0.02,
		"w": gap, "h": depth,
		"sizeX": door_bounds.x,
		"sizeY": minf(door_bounds.y, height * 0.82),
		"sizeZ": door_bounds.z,
		"asset": door_asset, "elevation": elevation,
		"followTerrain": follow, "tiltToTerrain": false,
		"label": "Porte à auvent", "layer": layer,
		"display": {"rotation": rotation, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Porte")
	_ed.doc.select_only(door_id)
	_ed.doc.commit_transaction()
	_ed._set_status("Porte 3D insérée : ouverture %.2f, deux montants." % gap)
## --- Ouverture de porte dans un mur procédural ---------------------------
func _nearest_procedural_wall(grid: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := 2.5
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		if str(elem.get("asset", "")) != "procedural://wall":
			continue
		var points := _procedural_world_points(elem)
		if points.size() < 2:
			continue
		for i in range(points.size() - 1):
			var distance := _distance_to_segment(grid, points[i], points[i + 1])
			if distance < best_distance:
				best_distance = distance
				best = elem
	return best

func _procedural_world_points(elem: Dictionary) -> Array:
	var origin := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	var out: Array = []
	for p in elem.get("points", []):
		var local := Vector2.ZERO
		if p is Vector2:
			local = p
		elif p is Array and (p as Array).size() >= 2:
			local = Vector2(float(p[0]), float(p[1]))
		out.append(origin + local)
	return out

func _insert_door_procedural(wall: Dictionary, grid: Vector2) -> void:
	var points := _procedural_world_points(wall)
	if points.size() < 2:
		return
	var total := 0.0
	for i in range(points.size() - 1):
		total += (points[i] as Vector2).distance_to(points[i + 1])
	var door_asset := "res://assets/objects3d/buildings/porte_auvent.glb"
	var door_bounds := _mesh_bounds_cells(door_asset, 1.0)
	var gap := maxf(1.0, door_bounds.x)
	if total < gap + 0.8:
		_ed._set_status("Porte 3D : mur procédural trop court pour une ouverture.")
		return
	# Distance curviligne du point le plus proche du clic.
	var best_s := 0.0
	var best_d := INF
	var walked := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.000001:
			continue
		var t := clampf((grid - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := a + ab * t
		var d := grid.distance_to(closest)
		if d < best_d:
			best_d = d
			best_s = walked + sqrt(len_sq) * t
		walked += sqrt(len_sq)
	var start := clampf(best_s - gap * 0.5, 0.0, total)
	var end := clampf(best_s + gap * 0.5, 0.0, total)
	var left := _slice_polyline(points, 0.0, start)
	var right := _slice_polyline(points, end, total)
	var opening_center := _point_on_polyline(points, best_s)
	var tangent := _point_on_polyline(points, minf(best_s + 0.1, total)) - _point_on_polyline(points, maxf(best_s - 0.1, 0.0))
	var rotation := rad_to_deg(atan2(tangent.y, tangent.x))
	_ed.doc.begin_transaction()
	_ed.doc.remove_element(str(wall.get("id", "")))
	_add_procedural_wall_run(left, wall)
	_add_procedural_wall_run(right, wall)
	var door_id: String = _ed.doc.add_element({
		"x": opening_center.x, "y": opening_center.y,
		"w": gap, "h": maxf(0.4, door_bounds.z),
		"sizeX": door_bounds.x, "sizeY": minf(door_bounds.y, float(wall.get("height", 2.2)) * 0.82),
		"sizeZ": door_bounds.z,
		"asset": door_asset,
		"elevation": float(wall.get("elevation", 0.0)),
		"followTerrain": true, "tiltToTerrain": false,
		"label": "Porte à auvent", "layer": 1,
		"display": {"rotation": rotation, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Porte")
	_ed.doc.select_only(door_id)
	_ed.doc.commit_transaction()
	_ed._sync_engine()
	_ed._set_status("Porte 3D insérée dans le mur procédural : ouverture %.2f." % gap)

func _add_procedural_wall_run(points: Array, template: Dictionary) -> void:
	if points.size() < 2:
		return
	var min_p: Vector2 = points[0]
	var max_p: Vector2 = points[0]
	for p_variant in points:
		var p: Vector2 = p_variant
		min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
		max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
	var center := (min_p + max_p) * 0.5
	var local: Array = []
	for p_variant in points:
		var p: Vector2 = (p_variant as Vector2) - center
		local.append([p.x, p.y])
	_ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
		"asset": "procedural://wall", "points": local,
		"height": float(template.get("height", 2.2)),
		"thickness": float(template.get("thickness", 0.7)),
		"bevel": float(template.get("bevel", 0.12)),
		"color": str(template.get("color", "#a89d88")),
		"elevation": float(template.get("elevation", 0.0)),
		"followTerrain": true, "tiltToTerrain": false,
		"label": "Mur procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Mur procédural")

func _slice_polyline(points: Array, start: float, end: float) -> Array:
	if end <= start:
		return []
	var out: Array = []
	var walked := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.0001:
			continue
		var s0 := walked
		var s1 := walked + seg_len
		var from := maxf(start, s0)
		var to := minf(end, s1)
		if to > from:
			var p0 := a.lerp(b, (from - s0) / seg_len)
			var p1 := a.lerp(b, (to - s0) / seg_len)
			if out.is_empty() or (out[out.size() - 1] as Vector2).distance_to(p0) > 0.001:
				out.append(p0)
			out.append(p1)
		walked = s1
	return out

func _point_on_polyline(points: Array, distance: float) -> Vector2:
	var walked := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg_len := a.distance_to(b)
		if distance <= walked + seg_len:
			return a.lerp(b, clampf((distance - walked) / maxf(0.0001, seg_len), 0.0, 1.0))
		walked += seg_len
	return points[points.size() - 1]

func _create_mesh_roof(from: Vector2, to: Vector2, elevation_offset: float = 0.0) -> void:
	var x0 := minf(from.x, to.x)
	var x1 := maxf(from.x, to.x)
	var y0 := minf(from.y, to.y)
	var y1 := maxf(from.y, to.y)
	var width := x1 - x0
	var depth := y1 - y0
	if width < 1.0 or depth < 1.0:
		_ed._set_status("Zone de toit trop petite.")
		return
	var asset = _ed._roof_asset
	var bounds := _mesh_bounds_cells(asset, 1.0)
	var tile_w := maxf(1.0, bounds.x)
	var tile_d := maxf(1.0, bounds.z)
	var cols := maxi(1, int(ceil(width / tile_w)))
	var rows := maxi(1, int(ceil(depth / tile_d)))
	var step_x := width / float(cols)
	var step_y := depth / float(rows)
	var ids: Array = []
	_ed.doc.begin_transaction()
	for row in range(rows):
		for col in range(cols):
			var pos := Vector2(x0 + (float(col) + 0.5) * step_x,
				y0 + (float(row) + 0.5) * step_y)
			var id: String = _ed.doc.add_element({
				"x": pos.x, "y": pos.y,
				"w": tile_w, "h": tile_d,
				"asset": asset,
				"elevation": _ed._roof_height + elevation_offset, "followTerrain": false, "tiltToTerrain": false,
				"label": "Toit 3D", "layer": 1,
				"display": {"rotation": 0.0, "scale": 1.0},
			}, DocumentScript.KIND_MESH, "Toit 3D")
			ids.append(id)
	_ed.doc.set_selection(ids)
	_ed.doc.commit_transaction()
	_ed._set_status("Toit 3D : %d tuile(s), hauteur %.2f." % [ids.size(), _ed._roof_height])

## Toit procédural : un seul mesh généré depuis l'emprise, avec débord.
func _create_procedural_roof(from: Vector2, to: Vector2, elevation_offset: float = 0.0) -> void:
	var x0 := minf(from.x, to.x)
	var x1 := maxf(from.x, to.x)
	var y0 := minf(from.y, to.y)
	var y1 := maxf(from.y, to.y)
	var width := x1 - x0
	var depth := y1 - y0
	if width < 1.0 or depth < 1.0:
		_ed._set_status("Zone de toit trop petite.")
		return
	var center := Vector2((x0 + x1) * 0.5, (y0 + y1) * 0.5)
	_ed.doc.begin_transaction()
	var id: String = _ed.doc.add_element({
		"x": center.x, "y": center.y,
		"w": width, "h": depth,
		"asset": "procedural://roof",
		"roofHeight": _ed._proc_roof_height,
		"overhang": _ed._proc_roof_overhang,
		"roofStyle": _ed._proc_roof_style,
		"roofTone": _ed._proc_roof_tone,
		"color": "#a84f3f",
		"elevation": _ed._roof_height + elevation_offset,
		"followTerrain": false, "tiltToTerrain": false,
		"label": "Toit procédural", "layer": 1,
		"display": {"rotation": 0.0, "scale": 1.0},
	}, DocumentScript.KIND_MESH, "Toit procédural")
	_ed.doc.set_selection([id])
	_ed.doc.commit_transaction()
	_ed._sync_engine()
	_ed._set_status("Toit procédural : %.1f × %.1f cases, hauteur %.2f." % [
		width, depth, _ed._proc_roof_height])

## Dallage : peint le sol intérieur en pierre et le nivelle (option).
func _create_floor(from: Vector2, to: Vector2) -> void:
	var w = int(_ed.doc.map_data.get("width", 0))
	var h = int(_ed.doc.map_data.get("height", 0))
	var x0 := clampi(int(floor(minf(from.x, to.x))), 0, w - 1)
	var x1 := clampi(int(ceil(maxf(from.x, to.x))) - 1, 0, w - 1)
	var y0 := clampi(int(floor(minf(from.y, to.y))), 0, h - 1)
	var y1 := clampi(int(ceil(maxf(from.y, to.y))) - 1, 0, h - 1)
	if x1 < x0 or y1 < y0:
		return
	var count := 0
	_ed.doc.begin_transaction()
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			_ed.doc.set_terrain_material(cx, cy, _ed._floor_material, "Dallage")
			if _ed._floor_flatten:
				_ed.doc.set_terrain_height(cx, cy, 0.0, "Dallage")
			count += 1
	_ed.doc.commit_transaction()
	_ed._set_status("Dallage : %d case(s) en %s%s." % [count, _floor_material_label(), ", sol nivelé" if _ed._floor_flatten else ""])

func _floor_material_label() -> String:
	for material_variant in FLOOR_MATERIALS:
		var material: Dictionary = material_variant
		if int(material["id"]) == _ed._floor_material:
			return str(material["label"]).to_lower()
	return "pierre"

## Pose un décor à l'échelle de son asset : une maison garde ses proportions,
## on ne se retrouve pas avec une charrette carrée.
func _create_prop(grid: Vector2) -> void:
	if _ed._prop_asset.is_empty():
		_ed._set_status("Choisissez d'abord un décor dans la bibliothèque (onglet Biblio).")
		return
	var ratio = AssetLibraryScript.aspect_ratio(_ed._prop_asset)
	var height = maxf(0.25, _ed._prop_size)
	var width := maxf(0.25, height * ratio)
	var asset = AssetLibraryScript.get_asset(_ed._prop_asset)
	# Carte illustrée top-down : forcer à plat pour rester visible (sinon tranche).
	var standing = _ed._prop_standing and not MapRenderStyleScript.prefer_flat_props(_ed.doc.map_data)
	var id: String = _ed.doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": width, "h": height,
		"asset": _ed._prop_asset,
		"standing": standing,
		"billboard": standing,
		"lit": false,
		"elevation": 0.0,
		"label": str(asset.get("name", _ed._prop_asset.get_file().get_basename())),
		"layer": 1,
		"display": {"rotation": _ed._prop_rotation},
	}, DocumentScript.KIND_PROP, "Décor")
	_ed.doc.select_only(id)

## Pose un objet 3D générique (mesh GLB) sur la carte 2.5D.
## Décor contextuel : clique près d'un mur, l'éditeur sème buissons/rochers le
## long de ses abords, sur les deux faces, avec une graine déterministe.
## Génère une scène complète (village/forêt/camp) à partir d'une graine.
## Les chemins sont peints, les maisons construites avec l'outil Maison rapide,
## le décor posé comme objets 3D.
## Peint des plaques de sol organiques (herbe / terre / pierre) avec WFC.
## Donne immédiatement une carte moins « damier » avant la génération de scène.
func apply_wfc_ground(style_id: String) -> int:
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	if width < 4 or height < 4:
		return 0
	var weights := [8.0, 2.0, 0.6] if style_id == "village" else ([7.0, 2.0, 1.4] if style_id == "forest" else [5.0, 3.0, 1.2])
	# 0 herbe, 1 terre, 2 pierre — règles symétriques.
	var adjacency := [
		[[0, 1], [0, 1, 2], [1, 2]],
		[[0, 1], [0, 1, 2], [1, 2]],
		[[0, 1], [0, 1, 2], [1, 2]],
		[[0, 1], [0, 1, 2], [1, 2]],
	]
	var wfc = WaveFunctionCollapseScript.new()
	wfc.configure(weights, adjacency, _ed._scene_seed + 73)
	var grid: Array = wfc.generate(width, height)
	if grid.is_empty():
		return 0
	var changed := 0
	_ed.doc.begin_transaction()
	for y in range(height):
		for x in range(width):
			if _ed.doc.terrain_material(x, y) != DocumentScript.MATERIAL_GRASS:
				continue
			var tile := int(grid[y * width + x])
			if tile == 1:
				_ed.doc.set_terrain_material(x, y, DocumentScript.MATERIAL_DIRT, "WFC")
				changed += 1
			elif tile == 2:
				_ed.doc.set_terrain_material(x, y, DocumentScript.MATERIAL_STONE, "WFC")
				changed += 1
	_ed.doc.commit_transaction()
	return changed

## Ajoute des rochers Marching Cubes autour de la scène (décor organique).
func add_procedural_rocks(count: int = 4) -> int:
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	if width < 4 or height < 4 or count <= 0:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _ed._scene_seed + 991
	var added := 0
	_ed.doc.begin_transaction()
	for _i in range(count):
		var x := rng.randf_range(1.5, float(width) - 1.5)
		var y := rng.randf_range(1.5, float(height) - 1.5)
		var id: String = _ed.doc.add_element({
			"x": x, "y": y, "w": 1.4, "h": 1.4,
			"asset": "procedural://rock",
			"seed": rng.randi() % 100000,
			"detail": 12,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Rocher procédural", "layer": 1,
			"display": {
				"rotation": rng.randf_range(0.0, 360.0),
				"scale": rng.randf_range(0.75, 1.25),
			},
		}, DocumentScript.KIND_MESH, "Rocher procédural")
		if not id.is_empty():
			added += 1
	_ed.doc.commit_transaction()
	return added

func _generate_scene(_grid: Vector2) -> void:
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	if width < 8 or height < 8:
		_ed._set_status("Scène : carte trop petite (8 × 8 minimum).")
		return
	var plan: Dictionary = ProceduralSceneGeneratorScript.generate(
		_ed._scene_style, width, height, _ed._scene_seed, _ed._scene_density
	)
	_apply_scene_plan(plan)

## Applique un plan généré (scène complète ou zone).
func _apply_scene_plan(plan: Dictionary) -> Dictionary:
	var counts := {
		"paths": _apply_scene_paths(plan),
		"houses": _apply_scene_houses(plan),
		"fences": _apply_scene_fences(plan),
		"flowers": _apply_scene_flower_zones(plan),
		"props": _apply_scene_props(plan),
	}
	_finalize_scene_status(counts)
	return counts

func _generate_scene_area(from: Vector2, to: Vector2) -> void:
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	var area := Rect2(Vector2(minf(from.x, to.x), minf(from.y, to.y)),
		Vector2(absf(to.x - from.x), absf(to.y - from.y)))
	if area.size.x < 8.0 or area.size.y < 8.0:
		_ed._set_status("Esquisse : dessinez une zone d'au moins 8 × 8 cases.")
		return
	var plan: Dictionary = ProceduralSceneGeneratorScript.generate_in_area(
		_ed._scene_style, width, height, area, _ed._scene_seed, _ed._scene_density
	)
	_apply_scene_plan(plan)

func _apply_scene_paths(plan: Dictionary) -> int:
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	var count := 0
	for path_variant in plan.get("paths", []):
		var path_data: Dictionary = path_variant
		var from: Vector2 = path_data.get("from", Vector2.ZERO)
		var to: Vector2 = path_data.get("to", Vector2.ZERO)
		var steps := maxi(1, int(ceil(from.distance_to(to) * 2.0)))
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var cell := Vector2(round(lerpf(from.x, to.x, t)), round(lerpf(from.y, to.y, t)))
			if cell.x >= 0.0 and cell.y >= 0.0 and cell.x < width and cell.y < height:
				_ed.doc.set_terrain_material(int(cell.x), int(cell.y), DocumentScript.MATERIAL_DIRT, "Scène")
				count += 1
	return count

func _apply_scene_houses(plan: Dictionary) -> int:
	var count := 0
	for rect_variant in plan.get("houses", []):
		var rect: Rect2 = rect_variant
		_create_mesh_house(rect.position, rect.end)
		count += 1
	return count

func _apply_scene_fences(plan: Dictionary) -> int:
	var count := 0
	for fence_variant in plan.get("fences", []):
		var points: Array = fence_variant
		if points.size() < 2:
			continue
		var min_p: Vector2 = points[0]
		var max_p: Vector2 = points[0]
		for p_variant in points:
			var p: Vector2 = p_variant
			min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
			max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
		var fence_center := (min_p + max_p) * 0.5
		var local: Array = []
		for p_variant in points:
			var p: Vector2 = (p_variant as Vector2) - fence_center
			local.append([p.x, p.y])
		_ed.doc.add_element({
			"x": fence_center.x, "y": fence_center.y,
			"w": maxf(0.5, max_p.x - min_p.x), "h": maxf(0.5, max_p.y - min_p.y),
			"asset": "procedural://fence",
			"points": local, "height": 0.8, "spacing": 0.9,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Clôture de scène", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Clôture de scène")
		count += 1
	return count

func _apply_scene_flower_zones(plan: Dictionary) -> int:
	var count := 0
	for zone_variant in plan.get("flowerZones", []):
		var zone: Dictionary = zone_variant
		var rect: Rect2 = zone.get("rect", Rect2())
		if rect.size.x < 0.5 or rect.size.y < 0.5:
			continue
		var center := rect.get_center()
		var local: Array = [
			[rect.position.x - center.x, rect.position.y - center.y],
			[rect.end.x - center.x, rect.position.y - center.y],
			[rect.end.x - center.x, rect.end.y - center.y],
			[rect.position.x - center.x, rect.end.y - center.y],
		]
		_ed.doc.add_element({
			"x": center.x, "y": center.y,
			"w": rect.size.x, "h": rect.size.y,
			"asset": "procedural://flower_zone",
			"points": local,
			"flowerType": str(zone.get("type", "marguerite")),
			"density": float(zone.get("density", 4.0)),
			"size": 0.3, "seed": _ed._scene_seed + count,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
			"label": "Zone fleurie de scène", "layer": 1,
			"display": {"rotation": 0.0, "scale": 1.0},
		}, DocumentScript.KIND_MESH, "Zone fleurie de scène")
		count += 1
	return count

func _apply_scene_props(plan: Dictionary) -> int:
	var count := 0
	for prop_variant in plan.get("props", []):
		var prop: Dictionary = prop_variant
		var asset := str(prop.get("asset", ""))
		if asset.is_empty() or (not asset.begins_with("procedural://") and not ResourceLoader.exists(asset)):
			continue
		var scale_v := maxf(0.1, float(prop.get("scale", 1.0)))
		var footprint: Vector2
		if asset.begins_with("procedural://"):
			footprint = Vector2(2.0, 2.0)
		else:
			var natural_bounds := _mesh_bounds_cells(asset, 1.0)
			footprint = Vector2(maxf(0.3, natural_bounds.x), maxf(0.3, natural_bounds.z))
		_ed.doc.add_element({
			"x": float(prop.get("x", 0.0)), "y": float(prop.get("y", 0.0)),
			"w": footprint.x * scale_v, "h": footprint.y * scale_v,
			"asset": asset,
			"height": 1.8 if asset == "procedural://tent" else 1.0,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": true,
			"label": "Décor de scène", "layer": 1,
			"display": {"rotation": 0.0, "scale": scale_v},
		}, DocumentScript.KIND_MESH, "Décor de scène")
		count += 1
	return count

func _finalize_scene_status(counts: Dictionary) -> void:
	_ed._set_status("Scène %s générée : %d maison(s), %d case(s) de chemin, %d clôture(s), %d zone(s) fleurie(s), %d décor(s)." % [
		ProceduralSceneGeneratorScript.style_label(_ed._scene_style),
		int(counts.get("houses", 0)), int(counts.get("paths", 0)),
		int(counts.get("fences", 0)), int(counts.get("flowers", 0)),
		int(counts.get("props", 0))])
	_ed._sync_engine()

func _decorate_context(grid: Vector2) -> void:
	var wall := _nearest_wall_element(grid, _ed._context_decor_radius)
	if wall.is_empty():
		if _decorate_path_context(grid):
			return
		if _decorate_water_context(grid):
			return
		_ed._set_status("Décor contextuel : aucun mur, chemin ou berge à proximité.")
		return
	_decorate_wall_context(wall)

## Sème le décor d'un mur identifié et renvoie le nombre d'éléments créés.
func _decorate_wall_context(wall: Dictionary) -> int:
	var endpoints := _wall_endpoints(wall)
	if endpoints.size() < 2:
		return 0
	var a: Vector2 = endpoints[0]
	var b: Vector2 = endpoints[1]
	var length := a.distance_to(b)
	if length < 0.5:
		return 0
	var dir := (b - a).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var thickness := maxf(0.35, float(wall.get("h", 0.7)))
	var wall_id := str(wall.get("id", ""))
	var assets := [
		"res://assets/objects3d/vegetation/buisson.glb",
		"res://assets/objects3d/terrain/rocher.glb",
		"res://assets/objects3d/vegetation/haie.glb",
	]
	var count := clampi(int(round(length * _ed._context_decor_density)), 1, 8)
	_ed._context_decor_seed = (_ed._context_decor_seed * 1664525 + 1013904223) % 2147483647
	var rng := RandomNumberGenerator.new()
	rng.seed = _ed._context_decor_seed
	var ids: Array = []
	_ed.doc.begin_transaction()
	for i in range(count):
		var t := (float(i) + 0.5) / float(count)
		var base := a.lerp(b, t)
		var side := 1.0 if rng.randi() % 2 == 0 else -1.0
		var offset := thickness * 0.5 + rng.randf_range(0.25, 0.9)
		var pos := base + normal * side * offset
		if pos.x < 0.0 or pos.y < 0.0 \
				or pos.x >= float(_ed.doc.map_data.get("width", 0)) \
				or pos.y >= float(_ed.doc.map_data.get("height", 0)):
			continue
		var asset: String = str(assets[rng.randi() % assets.size()])
		if not ResourceLoader.exists(asset):
			continue
		var bounds := _mesh_bounds_cells(asset, 1.0)
		var footprint := Vector2(maxf(0.3, bounds.x), maxf(0.3, bounds.z))
		var id: String = _ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": footprint.x, "h": footprint.y,
			"asset": asset,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": true,
			"label": "Décor contextuel", "layer": 1,
			"decorSource": wall_id,
			"display": {
				"rotation": rng.randf_range(0.0, 360.0),
				"scale": rng.randf_range(0.75, 1.15),
			},
		}, DocumentScript.KIND_MESH, "Décor contextuel")
		ids.append(id)
	_ed.doc.commit_transaction()
	_ed.doc.set_selection(ids)
	_ed._set_status("Décor contextuel : %d élément(s) semés le long du mur." % ids.size())
	return ids.size()

## Recalcule le décor associé à des murs déplacés/redimensionnés.
func _refresh_context_decor_for_walls(wall_ids: Array) -> void:
	var wanted: Dictionary = {}
	for id_variant in wall_ids:
		wanted[str(id_variant)] = true
	if wanted.is_empty():
		return
	var old_decor: Array = []
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		var source := str(elem.get("decorSource", ""))
		if wanted.has(source):
			old_decor.append(str(elem.get("id", "")))
	if old_decor.is_empty():
		return
	_ed.doc.remove_elements(old_decor)
	for id_variant in wall_ids:
		var wall: Dictionary = _ed.doc.get_element(str(id_variant))
		if wall.is_empty():
			continue
		var asset := str(wall.get("asset", "")).to_lower()
		if asset.contains("mur") or asset.contains("wall"):
			_decorate_wall_context(wall)
	_ed._set_status("Décor contextuel recalculé pour %d mur(s)." % wall_ids.size())

## Décor de chemin : cherche une bordure de terre/chemin et sème herbes hautes
## (buissons, rochers, haies) côté prairie.
func _decorate_path_context(grid: Vector2) -> bool:
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	var best_cell := Vector2.INF
	var best_distance: float = _ed._context_decor_radius
	var radius := int(ceil(_ed._context_decor_radius))
	for cy in range(int(floor(grid.y)) - radius, int(ceil(grid.y)) + radius + 1):
		for cx in range(int(floor(grid.x)) - radius, int(ceil(grid.x)) + radius + 1):
			if cx < 0 or cy < 0 or cx >= width or cy >= height:
				continue
			if _ed.doc.terrain_material(cx, cy) != DocumentScript.MATERIAL_DIRT:
				continue
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + offset.x
				var ny: int = cy + offset.y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				if _ed.doc.terrain_material(nx, ny) == DocumentScript.MATERIAL_DIRT:
					continue
				var candidate := Vector2(nx, ny)
				var distance := candidate.distance_to(grid)
				if distance < best_distance:
					best_distance = distance
					best_cell = candidate
	if best_cell == Vector2.INF:
		return false
	var assets := [
		"res://assets/objects3d/vegetation/buisson.glb",
		"res://assets/objects3d/terrain/rocher.glb",
		"res://assets/objects3d/vegetation/haie.glb",
	]
	var count := clampi(int(round(3.0 * _ed._context_decor_density)), 1, 6)
	_ed._context_decor_seed = (_ed._context_decor_seed * 1664525 + 1013904223) % 2147483647
	var rng := RandomNumberGenerator.new()
	rng.seed = _ed._context_decor_seed
	var ids: Array = []
	_ed.doc.begin_transaction()
	for _i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.2, 0.9)
		var pos := best_cell + Vector2(cos(angle), sin(angle)) * distance
		if pos.x < 0.0 or pos.y < 0.0 or pos.x >= float(width) or pos.y >= float(height):
			continue
		var asset: String = str(assets[rng.randi() % assets.size()])
		if not ResourceLoader.exists(asset):
			continue
		var bounds := _mesh_bounds_cells(asset, 1.0)
		var footprint := Vector2(maxf(0.25, bounds.x), maxf(0.25, bounds.z))
		var id: String = _ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": footprint.x, "h": footprint.y,
			"asset": asset,
			"elevation": 0.0, "followTerrain": true, "tiltToTerrain": true,
			"label": "Décor contextuel", "layer": 1,
			"display": {
				"rotation": rng.randf_range(0.0, 360.0),
				"scale": rng.randf_range(0.8, 1.15),
			},
		}, DocumentScript.KIND_MESH, "Décor de chemin")
		ids.append(id)
	_ed.doc.commit_transaction()
	_ed.doc.set_selection(ids)
	_ed._set_status("Décor contextuel : %d élément(s) semés sur le bord du chemin." % ids.size())
	return true

## Décor de berge : si le clic est près d'une rive, sème roseaux et nénuphars.
func _decorate_water_context(grid: Vector2) -> bool:
	var water_level := float(_ed.doc.map_data.get("waterLevel", -1.0))
	if water_level < 0.0:
		return false
	var width := int(_ed.doc.map_data.get("width", 0))
	var height := int(_ed.doc.map_data.get("height", 0))
	var best_cell := Vector2.INF
	var best_distance: float = _ed._context_decor_radius
	var radius := int(ceil(_ed._context_decor_radius))
	for cy in range(int(floor(grid.y)) - radius, int(ceil(grid.y)) + radius + 1):
		for cx in range(int(floor(grid.x)) - radius, int(ceil(grid.x)) + radius + 1):
			if cx < 0 or cy < 0 or cx >= width or cy >= height:
				continue
			if _ed.doc.terrain_height(cx, cy) < water_level - 0.001:
				continue
			var is_shore := false
			for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + offset.x
				var ny: int = cy + offset.y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				if _ed.doc.terrain_height(nx, ny) < water_level - 0.001:
					is_shore = true
					break
			if not is_shore:
				continue
			var distance := Vector2(cx, cy).distance_to(grid)
			if distance < best_distance:
				best_distance = distance
				best_cell = Vector2(cx, cy)
	if best_cell == Vector2.INF:
		return false
	var assets := [
		"res://assets/objects3d/vegetation/roseaux.glb",
		"res://assets/objects3d/vegetation/nenuphars.glb",
	]
	var count := clampi(int(round(4.0 * _ed._context_decor_density)), 1, 8)
	_ed._context_decor_seed = (_ed._context_decor_seed * 1664525 + 1013904223) % 2147483647
	var rng := RandomNumberGenerator.new()
	rng.seed = _ed._context_decor_seed
	var ids: Array = []
	_ed.doc.begin_transaction()
	for _i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(0.15, 0.8)
		var pos := best_cell + Vector2(cos(angle), sin(angle)) * distance
		if pos.x < 0.0 or pos.y < 0.0 or pos.x >= float(width) or pos.y >= float(height):
			continue
		var asset: String = str(assets[rng.randi() % assets.size()])
		if not ResourceLoader.exists(asset):
			continue
		var bounds := _mesh_bounds_cells(asset, 1.0)
		var footprint := Vector2(maxf(0.25, bounds.x), maxf(0.25, bounds.z))
		var id: String = _ed.doc.add_element({
			"x": pos.x, "y": pos.y,
			"w": footprint.x, "h": footprint.y,
			"asset": asset,
			"elevation": 0.0, "followTerrain": true,
			"tiltToTerrain": asset.contains("roseaux"),
			"label": "Décor contextuel", "layer": 1,
			"display": {
				"rotation": rng.randf_range(0.0, 360.0),
				"scale": rng.randf_range(0.8, 1.2),
			},
		}, DocumentScript.KIND_MESH, "Décor de berge")
		ids.append(id)
	_ed.doc.commit_transaction()
	_ed.doc.set_selection(ids)
	_ed._set_status("Décor contextuel : %d élément(s) semés sur la berge." % ids.size())
	return true

func _nearest_wall_element(grid: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := radius
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		var asset := str(elem.get("asset", "")).to_lower()
		if not (asset.contains("mur") or asset.contains("wall")):
			continue
		var endpoints := _wall_endpoints(elem)
		if endpoints.size() < 2:
			continue
		var distance: float = _distance_to_segment(grid, endpoints[0], endpoints[1])
		if distance < best_distance:
			best_distance = distance
			best = elem
	return best

static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _create_mesh(grid: Vector2) -> void:
	if _ed._mesh_asset.is_empty():
		_ed._set_status("Choisissez d'abord un objet 3D dans la bibliothèque (onglet Biblio → Objets 3D).")
		return
	var asset = AssetLibraryScript.get_object3d_asset(_ed._mesh_asset)
	var bounds = _mesh_bounds_cells(_ed._mesh_asset)
	var footprint := Vector2(maxf(0.5, bounds.x), maxf(0.5, bounds.z))
	var placement = {"x": grid.x, "y": grid.y, "elevation": 0.0, "rotation": _ed._mesh_rotation}
	if _ed._mesh_snap_modules:
		var snapped = _snap_module_placement(_ed._mesh_asset, grid)
		if not snapped.is_empty():
			placement = snapped
	# Empilement automatique : si l'emprise touche le dessus d'un objet posé,
	# le nouvel objet se pose à sa hauteur (table -> lanterne, caisse -> caisse).
	# Les modules muraux/toits/portes restent au sol ou sur leur ancre.
	if _ed._auto_stack and _auto_stack_asset(_ed._mesh_asset):
		var stack_top := _stack_top_at(
			Vector2(float(placement["x"]), float(placement["y"])),
			footprint
		)
		if stack_top > float(placement.get("elevation", 0.0)) + 0.02:
			placement["elevation"] = stack_top + STACK_EPSILON
	var id: String = _ed.doc.add_element({
		"x": placement["x"], "y": placement["y"],
		"w": footprint.x, "h": footprint.y,
		"sizeX": footprint.x, "sizeY": maxf(0.2, bounds.y), "sizeZ": footprint.y,
		"asset": _ed._mesh_asset,
		"elevation": float(placement.get("elevation", 0.0)),
		"followTerrain": true,
		"tiltToTerrain": _ed._mesh_tilt_default(asset),
		"label": str(asset.get("name", _ed._mesh_asset.get_file().get_basename())),
		"layer": 1,
		"display": {"rotation": float(placement.get("rotation", _ed._mesh_rotation)), "scale": _ed._mesh_scale},
	}, DocumentScript.KIND_MESH, "Objet 3D")
	_ed.doc.select_only(id)
	if float(placement.get("elevation", 0.0)) > 0.1:
		_ed._set_status("Objet empilé à %.2f case(s)." % float(placement["elevation"]))
	elif placement.has("snapped_to"):
		_ed._set_status("Module aimanté sur « %s »." % str(placement.get("snapped_to", "bâtiment")))

## Vrai si cet asset peut être empilé automatiquement. Les modules de
## construction (murs, toits, portes, fenêtres) ont leurs propres ancrages.
func _auto_stack_asset(asset: String) -> bool:
	var lower := asset.to_lower()
	if lower.begins_with("procedural://"):
		return false
	for fragment in ["mur", "toit", "porte", "fenetre", "window", "door", "roof", "wall"]:
		if lower.contains(fragment):
			return false
	return true

## Dessus de l'objet posé qui recouvre le plus l'emprise donnée (en cases).
## Sert à l'empilement automatique : une lanterne se pose sur une table, une
## caisse sur une autre sans réglage manuel de l'élévation.
func _stack_top_at(pos: Vector2, footprint: Vector2) -> float:
	var rect := Rect2(pos - footprint * 0.5, footprint)
	var best := 0.0
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		var asset := str(elem.get("asset", ""))
		if asset.begins_with("procedural://"):
			continue
		if asset.contains("mur") or asset.contains("toit") or asset.contains("fenetre") or asset.contains("porte"):
			continue
		var ew := maxf(0.1, float(elem.get("w", 1.0)))
		var eh := maxf(0.1, float(elem.get("h", 1.0)))
		var er := Rect2(
			Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0))) - Vector2(ew, eh) * 0.5,
			Vector2(ew, eh)
		)
		if not rect.intersects(er):
			continue
		var height := float(elem.get("sizeY", 0.0))
		if height <= 0.0:
			height = _mesh_bounds_cells(asset, 1.0).y
		var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
		var display_scale := maxf(0.01, float(display.get("scale", 1.0)))
		var top := float(elem.get("elevation", 0.0)) + maxf(0.2, height) * display_scale
		best = maxf(best, top)
	return best

## Positionne automatiquement un module de toit/façade sur le bâtiment le plus
## proche (manifeste Blender : anchor `roof` / `wall`, dimensions, hauteur).
func _snap_module_placement(asset_path: String, grid: Vector2) -> Dictionary:
	var meta: Dictionary = AssetLibraryScript.get_object3d_meta(asset_path)
	if meta.is_empty():
		return {}
	var anchor := str(meta.get("anchor", "base"))
	if anchor != "roof" and anchor != "wall":
		return {}
	var best: Dictionary = {}
	var best_distance := 999.0
	for elem_variant in _ed.doc.elements_sorted():
		var elem: Dictionary = elem_variant
		if str(elem.get("kind", "")) != DocumentScript.KIND_MESH:
			continue
		var other_path := str(elem.get("asset", ""))
		var other_meta: Dictionary = AssetLibraryScript.get_object3d_meta(other_path)
		if other_meta.is_empty():
			continue
		if str(other_meta.get("anchor", "base")) != "base":
			continue
		if str(other_meta.get("category", "")) != "buildings":
			continue
		var other_name := str(other_meta.get("name", "")).to_lower()
		if other_name.begins_with("toit") or other_name.begins_with("cheminee") \
				or other_name.begins_with("clocheton") or other_name.begins_with("pnj_"):
			continue
		var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		var distance := center.distance_to(grid)
		if distance < best_distance:
			best_distance = distance
			best = elem
	if best.is_empty() or best_distance > 9.0:
		return {}
	var dims: Array = meta.get("dimensions_cells", [1.0, 1.0, 0.8])
	var mod_depth := float(dims[1]) if dims.size() > 1 else 1.0
	var mod_height := float(dims[2]) if dims.size() > 2 else 0.8
	var building_h := float(best.get("sizeY", 1.5))
	var building_h_foot := float(best.get("h", 1.0))
	var label := str(best.get("label", best.get("asset", "")))
	var building_display: Dictionary = best.get("display", {}) if best.get("display") is Dictionary else {}
	var building_rotation := float(building_display.get("rotation", 0.0))
	if anchor == "roof":
		return {
			"x": float(best.get("x", grid.x)),
			"y": float(best.get("y", grid.y)),
			"elevation": maxf(0.2, building_h - mod_height * 0.2),
			"rotation": building_rotation,
			"snapped_to": label,
		}
	# Façade : sur le mur du bâtiment le plus proche du clic, en héritant de sa
	# rotation. On choisit le côté (avant/arrière/gauche/droite) dont la normale
	# est la plus proche du point cliqué, et on colle le dos du module au mur.
	var building_w_foot := float(best.get("w", 1.0))
	var offset := grid - Vector2(float(best.get("x", grid.x)), float(best.get("y", grid.y)))
	var rotation_rad := deg_to_rad(building_rotation)
	var sides: Array = [
		{"base_dir": Vector2(0, 1), "base_angle": 0.0, "half": building_h_foot * 0.5},
		{"base_dir": Vector2(1, 0), "base_angle": -90.0, "half": building_w_foot * 0.5},
		{"base_dir": Vector2(0, -1), "base_angle": 180.0, "half": building_h_foot * 0.5},
		{"base_dir": Vector2(-1, 0), "base_angle": 90.0, "half": building_w_foot * 0.5},
	]
	var side_dir := Vector2(0, 1).rotated(rotation_rad)
	var side_angle := building_rotation
	var side_half := building_h_foot * 0.5
	var best_projection := 0.01
	for side_variant in sides:
		var side: Dictionary = side_variant
		var world_dir: Vector2 = (side["base_dir"] as Vector2).rotated(rotation_rad)
		var projection := offset.dot(world_dir)
		if projection > best_projection:
			best_projection = projection
			side_dir = world_dir
			side_angle = float(side["base_angle"]) + building_rotation
			side_half = float(side["half"])
	# Dos du module : position du point le plus en arrière dans son repère local
	# (les GLB de façade n'ont pas forcément leur pivot au nu du mur).
	var module_aabb = _mesh_aabb_cells(asset_path, _ed._mesh_scale)
	var back_offset := maxf(0.0, -module_aabb.position.z)
	if back_offset <= 0.001:
		back_offset = mod_depth * 0.5
	var wall_face := Vector2(float(best.get("x", grid.x)), float(best.get("y", grid.y))) \
		+ side_dir * side_half
	return {
		"x": wall_face.x + side_dir.x * back_offset,
		"y": wall_face.y + side_dir.y * back_offset,
		"elevation": 0.0,
		"rotation": side_angle,
		"snapped_to": label,
	}

## Dimensions réelles d'un mesh (cases) : sizeX/Y/Z s'ils existent, sinon les
## dimensions naturelles du GLB multipliées par display.scale.
func _mesh_actual_dimensions(elem: Dictionary) -> Vector3:
	var asset_path := str(elem.get("asset", ""))
	var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
	var display_scale := maxf(0.01, float(display.get("scale", 1.0)))
	var natural := _mesh_bounds_cells(asset_path, 1.0)
	var out := natural * display_scale
	var sx := float(elem.get("sizeX", 0.0))
	var sy := float(elem.get("sizeY", 0.0))
	var sz := float(elem.get("sizeZ", 0.0))
	if sx > 0.0:
		out.x = sx
	if sy > 0.0:
		out.y = sy
	if sz > 0.0:
		out.z = sz
	return out

## Dimensions (en cases) de la boîte englobante du GLB, échelle de pose incluse.
func _mesh_aabb_cells(asset_path: String, scale_factor: float = -1.0) -> AABB:
	if asset_path.is_empty():
		return AABB()
	var factor = _ed._mesh_scale if scale_factor < 0.0 else scale_factor
	var cache_key := "a:%s|%.3f" % [asset_path, factor]
	if _ed._mesh_aabb_cache.has(cache_key):
		return _ed._mesh_aabb_cache[cache_key]
	var out := AABB()
	var inst: Node3D = AssetLibraryScript.instantiate_object3d_scene(asset_path)
	if inst != null:
		var bounds: Array = []
		_collect_mesh_aabbs(inst, Transform3D.IDENTITY, bounds)
		var first := true
		var merged := AABB()
		for aabb_variant in bounds:
			var aabb: AABB = aabb_variant
			merged = aabb if first else merged.merge(aabb)
			first = false
		if not first:
			out = AABB(merged.position * factor, merged.size * factor)
		inst.free()
	_ed._mesh_aabb_cache[cache_key] = out
	return out

## Dimensions (en cases) de la boîte englobante du GLB, échelle de pose incluse.
func _mesh_bounds_cells(asset_path: String, scale_factor: float = -1.0) -> Vector3:
	if asset_path.is_empty():
		return Vector3.ZERO
	var factor = _ed._mesh_scale if scale_factor < 0.0 else scale_factor
	var cache_key := "b:%s|%.3f" % [asset_path, factor]
	if _ed._mesh_footprint_cache.has(cache_key):
		return _ed._mesh_footprint_cache[cache_key]
	var out := Vector3.ZERO
	var inst: Node3D = AssetLibraryScript.instantiate_object3d_scene(asset_path)
	if inst != null:
		var bounds: Array = []
		_collect_mesh_aabbs(inst, Transform3D.IDENTITY, bounds)
		var first := true
		var merged := AABB()
		for aabb_variant in bounds:
			var aabb: AABB = aabb_variant
			merged = aabb if first else merged.merge(aabb)
			first = false
		if not first and merged.size.length() > 0.0:
			out = merged.size * factor
		inst.free()
	_ed._mesh_footprint_cache[cache_key] = out
	return out

## Empreinte au sol (en cases) déduite de la boîte englobante du GLB : le MJ
## n'a aucune dimension à saisir et la sélection colle au modèle.
func _mesh_footprint_cells(asset_path: String, scale_factor: float = -1.0) -> Vector2:
	var bounds := _mesh_bounds_cells(asset_path, scale_factor)
	if bounds == Vector3.ZERO:
		return Vector2.ONE
	return Vector2(maxf(0.5, bounds.x), maxf(0.5, bounds.z))

func _collect_mesh_aabbs(node: Node, xform: Transform3D, out: Array) -> void:
	var next_xform := xform
	if node is Node3D:
		next_xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		out.append(next_xform * (node as MeshInstance3D).get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, next_xform, out)
