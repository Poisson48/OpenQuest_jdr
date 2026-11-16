extends RefCounted
class_name ProceduralRockWall

## Planificateur déterministe pour un mur/affleurement de rochers empilés.
##
## Il ne fabrique pas de géométrie : il compose des instances GLB à partir de
## quatre rôles complémentaires du kit `terrain/rocher_*.glb`. La composition
## est reproductible : même graine + même longueur ⇒ mêmes placements.
##
## Rôles :
## - foundation : socle large (rangée basse) ;
## - wedge      : coin qui casse les joints réguliers ;
## - block      : bloc d'assemblage ;
## - cap        : couronnement plat (dernière rangée).

const ROLE_FOUNDATION := "foundation"
const ROLE_WEDGE := "wedge"
const ROLE_BLOCK := "block"
const ROLE_CAP := "cap"

## Nom des variantes Blender (utilisé par les rendus de revue).
const DEFAULT_ASSET_KEYS := {
	ROLE_FOUNDATION: "rocher_socle",
	ROLE_WEDGE: "rocher_coin",
	ROLE_BLOCK: "rocher_bloc",
	ROLE_CAP: "rocher_couronne",
}

## Chemins des assets livrés dans la bibliothèque de l'éditeur.
## On réutilise les rochers **du projet**, dans le style 2.5D (vertex colors +
## contour encre) : les rochers générés par IA, trop plats, ne s'empilent pas.
const DEFAULT_ASSET_PATHS := {
	ROLE_FOUNDATION: "res://assets/objects3d/terrain/gros_rocher.glb",
	ROLE_WEDGE: "res://assets/objects3d/terrain/rocher.glb",
	ROLE_BLOCK: "res://assets/objects3d/terrain/rocher.glb",
	ROLE_CAP: "res://assets/objects3d/terrain/falaise.glb",
}

## Hauteur d'une rangée, en cases (les pierres se recouvrent légèrement).
const ROW_STEP := 0.48
const BASE_SPACING := 0.82

## Placement 2D en cases, prêt pour `doc.add_element` (kind mesh).
## Chaque entrée : {role, asset, x, y, elevation, rotation, scale, row, slot}.
static func build_run_cells(origin: Vector2, direction: Vector2, length_cells: float,
		rows: int, seed: int, asset_paths: Dictionary = DEFAULT_ASSET_PATHS) -> Array:
	var placements := _layout(direction, length_cells, rows, seed)
	var out: Array = []
	for item_variant in placements:
		var item: Dictionary = item_variant
		var role := str(item["role"])
		out.append({
			"role": role,
			"asset": str(asset_paths.get(role, DEFAULT_ASSET_PATHS[role])),
			"x": origin.x + float(item["offset"].x),
			"y": origin.y + float(item["offset"].y),
			"elevation": float(item["row"]) * ROW_STEP,
			"rotation": float(item["yaw_degrees"]),
			"scale": float(item["scale"]),
			"row": int(item["row"]),
			"slot": int(item["slot"]),
		})
	return out

## Placement 3D en unités monde (murs à la main, hors grille de cases).
static func build_run(origin: Vector3, direction: Vector3, length: float,
		rows: int, seed: int, asset_keys: Dictionary = DEFAULT_ASSET_KEYS) -> Array:
	var along := Vector2(direction.x, direction.z)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	else:
		along = along.normalized()
	var out: Array = []
	for item_variant in _layout(along, length, rows, seed):
		var item: Dictionary = item_variant
		var role := str(item["role"])
		var offset: Vector2 = item["offset"]
		out.append({
			"role": role,
			"asset_key": str(asset_keys.get(role, role)),
			"position": Vector3(origin.x + offset.x,
				origin.y + float(item["row"]) * ROW_STEP, origin.z + offset.y),
			"yaw_degrees": float(item["yaw_degrees"]),
			"scale": float(item["scale"]),
			"row": int(item["row"]),
			"slot": int(item["slot"]),
		})
	return out

## Composition commune : rangées décalées, rôles par assise, variations bornées.
## `offset` est exprimé dans le plan (le long du mur, latéralement).
static func _layout(direction: Vector2, length: float, rows: int, seed: int) -> Array:
	var out: Array = []
	if length < 0.35 or rows <= 0:
		return out
	var along := direction
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	else:
		along = along.normalized()
	var side := Vector2(-along.y, along.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for row in range(rows):
		var is_cap := row == rows - 1 and rows > 1
		var role := ROLE_CAP if is_cap else (ROLE_FOUNDATION if row == 0 else ROLE_BLOCK)
		var row_spacing := BASE_SPACING * rng.randf_range(0.92, 1.08)
		var slot_count := maxi(1, int(ceil(length / row_spacing)))
		var actual_spacing := length / float(slot_count)
		# Décalage d'un demi-joint sur les rangées impaires : aucun alignement
		# vertical artificiel entre les pierres.
		var stagger := (0.5 * actual_spacing if row % 2 == 1 else 0.0)
		for slot in range(slot_count):
			var distance := minf(length - actual_spacing * 0.5,
				actual_spacing * (float(slot) + 0.5) + stagger)
			if distance < actual_spacing * 0.22:
				continue
			var local_role := role
			# Les coins uniquement au milieu : ils brisent les joints sans rendre
			# la base ou le couronnement instables.
			if row > 0 and not is_cap and rng.randf() < 0.28:
				local_role = ROLE_WEDGE
			var side_jitter := rng.randf_range(-0.075, 0.075)
			out.append({
				"role": local_role,
				"offset": along * distance + side * side_jitter,
				"scale": rng.randf_range(0.88, 1.08),
				"yaw_degrees": rad_to_deg(atan2(along.y, along.x)) + rng.randf_range(-9.0, 9.0),
				"row": row,
				"slot": slot,
			})
	return out
