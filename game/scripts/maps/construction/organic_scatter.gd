extends RefCounted
class_name OrganicScatter

## Dispersion de décor « façon Tiny Glade » : au lieu de poser chaque buisson à
## la main, l'éditeur passe un pinceau le long du geste et ce module calcule des
## positions variées déterministes (même graine → même décor).
##
## Pur : ne connaît ni le document ni le rendu. L'éditeur fournit la liste des
## assets disponibles (chemins `res://…glb`), filtre l'eau / les cases occupées,
## et crée les éléments mesh.

const OrganicPathScript := preload("res://scripts/maps/construction/organic_path.gd")

## Modes de dispersion : libellé + assets candidats (noms de fichiers GLB).
const MODES := {
	"buisson": {"label": "Buissons", "assets": ["buisson"]},
	"haie": {"label": "Haies", "assets": ["haie", "buisson"]},
	"roseaux": {"label": "Roseaux", "assets": ["roseaux"]},
	"arbre": {"label": "Arbres", "assets": ["arbre", "arbre_automne"]},
	"bosquet": {"label": "Bosquets", "assets": ["bosquet", "arbre", "buisson"]},
	"rocher": {"label": "Rochers", "assets": ["rocher", "gros_rocher"]},
	"mix": {"label": "Mélange", "assets": [
		"buisson", "haie", "roseaux", "arbre", "arbre_automne", "bosquet", "rocher",
	]},
}
const MODE_ORDER := ["buisson", "haie", "roseaux", "arbre", "bosquet", "rocher", "mix"]
const VEGETATION_DIR := "res://assets/objects3d/vegetation/"
const TERRAIN_DIR := "res://assets/objects3d/terrain/"
const DEFAULT_SPECKS_PER_SAMPLE := 1
const DEFAULT_SCALE_JITTER := 0.15
const DEFAULT_ROTATION_JITTER := 360.0

static func mode_label(mode_id: String) -> String:
	var mode: Dictionary = MODES.get(mode_id, MODES["mix"])
	return str(mode.get("label", mode_id))

## Chemins GLB disponibles pour un mode (assets introuvables ignorés).
static func mode_asset_paths(mode_id: String) -> Array:
	var mode: Dictionary = MODES.get(mode_id, MODES["mix"])
	var out: Array = []
	for name_variant in mode.get("assets", []):
		var asset_name := str(name_variant)
		for directory_variant in [VEGETATION_DIR, TERRAIN_DIR]:
			var path: String = str(directory_variant) + asset_name + ".glb"
			if ResourceLoader.exists(path) or FileAccess.file_exists(path):
				if not out.has(path):
					out.append(path)
				break
	return out

## Positions candidates le long d'une polyligne (rayon de dispersion autour).
## Déterministe pour une graine donnée. Renvoie `[{position, cell}]`.
static func scatter_along_path(points: Array, spacing: float, radius: float,
		seed: int, specs_per_sample: int = DEFAULT_SPECKS_PER_SAMPLE) -> Array:
	var out: Array = []
	if points.size() < 2:
		return out
	var samples := OrganicPathScript.resample(points, maxf(0.1, spacing))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var exact_spacing := maxf(0.1, spacing)
	var per_sample := maxi(1, specs_per_sample)
	for i in range(samples.size()):
		var sample: Vector2 = samples[i]
		var direction := Vector2.ZERO
		if i + 1 < samples.size():
			direction = ((samples[i + 1] as Vector2) - sample).normalized()
		elif i > 0:
			direction = (sample - (samples[i - 1] as Vector2)).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		for _j in range(per_sample):
			var angle := rng.randf_range(0.0, TAU)
			var distance := sqrt(rng.randf()) * maxf(0.0, radius)
			var jitter := rng.randf_range(-exact_spacing * 0.35, exact_spacing * 0.35)
			var position := sample + direction * jitter \
				+ Vector2(cos(angle), sin(angle)) * distance
			# Léger biais perpendiculaire pour border le tracé plutôt que le couvrir.
			position += perpendicular * rng.randf_range(-radius * 0.25, radius * 0.25)
			out.append({
				"position": position,
				"cell": Vector2i(int(round(position.x)), int(round(position.y))),
			})
	return out

## Positions candidates dans une liste de cases (dispersion de zone).
static func scatter_in_cells(cells: Array, chance: float, radius: float,
		seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var probability := clampf(chance, 0.0, 1.0)
	for cell_variant in cells:
		if not cell_variant is Vector2i:
			continue
		if rng.randf() > probability:
			continue
		var cell: Vector2i = cell_variant
		var position := Vector2(cell.x, cell.y) \
			+ Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
		out.append({
			"position": position,
			"cell": Vector2i(int(round(position.x)), int(round(position.y))),
		})
	return out

## Choisit asset / rotation / échelle pour chaque position. Renvoie
## `[{asset, x, y, rotation, scale}]`, déterministe pour une graine donnée.
static func make_items(positions: Array, asset_paths: Array, seed: int,
		base_scale: float = 1.0, scale_jitter: float = DEFAULT_SCALE_JITTER) -> Array:
	var out: Array = []
	if asset_paths.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for entry_variant in positions:
		var entry: Dictionary = entry_variant
		var position: Vector2 = entry.get("position", Vector2.ZERO)
		var asset := str(asset_paths[rng.randi_range(0, asset_paths.size() - 1)])
		var rotation := rng.randf_range(0.0, DEFAULT_ROTATION_JITTER)
		var scale := maxf(0.05, base_scale
			* rng.randf_range(1.0 - scale_jitter, 1.0 + scale_jitter))
		out.append({
			"asset": asset,
			"x": position.x,
			"y": position.y,
			"rotation": rotation,
			"scale": scale,
			"cell": entry.get("cell", Vector2i(int(round(position.x)), int(round(position.y)))),
		})
	return out

## Clé de case stable pour la déduplication (« éviter deux objets sur la même
## case »). Les positions sont en coordonnées cases de l'éditeur.
static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

## Supprime les doublons de case (garde le premier) et les entrées invalides.
static func dedupe_by_cell(items: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for item_variant in items:
		if not item_variant is Dictionary:
			continue
		var item: Dictionary = item_variant
		var cell: Vector2i = item.get("cell",
			Vector2i(int(round(float(item.get("x", 0.0)))),
				int(round(float(item.get("y", 0.0))))))
		var key := cell_key(cell)
		if seen.has(key):
			continue
		seen[key] = true
		item["cell"] = cell
		out.append(item)
	return out
