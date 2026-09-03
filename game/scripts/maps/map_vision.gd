extends RefCounted
class_name MapVision

## Ligne de vue et occlusion par les murs.
##
## Tout est calculé en **coordonnées grille** (mêmes unités que `x`/`y` des
## éléments), sans dépendance au rendu : le module est donc utilisable côté
## éditeur pour l'aperçu, côté session pour le brouillard dynamique, et
## testable seul.
##
## Un mur est décrit par son centre, sa longueur `w`, son angle
## `display.rotation` (degrés) et son drapeau `blocksSight`. Une porte est un
## mur avec `isDoor = true` : elle ne bloque plus rien une fois `open`.

## Marge appliquée à l'extrémité du rayon : une case dont le mur borde le bord
## reste visible (on voit le mur qui nous fait face).
const RAY_END_EPSILON := 0.04

## Rayon de vision par défaut d'un token, en cases.
const DEFAULT_VISION_RADIUS := 8.0

# ===========================================================================
# Extraction des segments bloquants
# ===========================================================================

## Segments de murs sous forme [{a, b, door, open, blocks}].
static func wall_segments(map_data: Dictionary, blocking_only: bool = true) -> Array:
	var out: Array = []
	var walls = map_data.get("walls", [])
	if not walls is Array:
		return out
	for wall_variant in walls:
		if not wall_variant is Dictionary:
			continue
		var wall: Dictionary = wall_variant
		var segment := segment_of(wall)
		if segment.is_empty():
			continue
		if blocking_only and not bool(segment["blocks"]):
			continue
		out.append(segment)
	return out

## Segment d'un mur unique, ou {} si sa longueur est nulle.
static func segment_of(wall: Dictionary) -> Dictionary:
	var length := float(wall.get("w", 0.0))
	if length <= 0.001:
		return {}
	var display: Dictionary = wall.get("display", {}) if wall.get("display") is Dictionary else {}
	var angle := deg_to_rad(float(display.get("rotation", 0.0)))
	var dir := Vector2(cos(angle), sin(angle)) * (length * 0.5)
	var center := Vector2(float(wall.get("x", 0.0)), float(wall.get("y", 0.0)))
	var is_door := bool(wall.get("isDoor", false))
	var is_open := bool(wall.get("open", false))
	var blocks_sight := bool(wall.get("blocksSight", true))
	if bool(wall.get("hidden", false)):
		blocks_sight = false
	if is_door and is_open:
		blocks_sight = false
	return {
		"a": center - dir,
		"b": center + dir,
		"door": is_door,
		"open": is_open,
		"blocks": blocks_sight,
		"id": str(wall.get("id", "")),
	}

# ===========================================================================
# Ligne de vue
# ===========================================================================

## Vrai si aucun segment ne coupe le trajet `from` → `to`.
static func is_clear(segments: Array, from: Vector2, to: Vector2) -> bool:
	# On raccourcit très légèrement le rayon côté cible : un mur posé
	# exactement sur la case visée ne doit pas la rendre invisible.
	var target := to
	var delta := to - from
	var distance := delta.length()
	if distance > RAY_END_EPSILON:
		target = to - delta / distance * RAY_END_EPSILON
	for segment_variant in segments:
		var segment: Dictionary = segment_variant
		if Geometry2D.segment_intersects_segment(from, target, segment["a"], segment["b"]) != null:
			return false
	return true

## Ligne de vue entre deux positions grille, murs de `map_data` pris en compte.
static func has_line_of_sight(map_data: Dictionary, from: Vector2, to: Vector2) -> bool:
	return is_clear(wall_segments(map_data), from, to)

# ===========================================================================
# Champ de vision
# ===========================================================================

## Cases visibles depuis `origin` dans un rayon donné, sous forme ["x,y", …].
static func visible_cells(map_data: Dictionary, origin: Vector2, radius: float = DEFAULT_VISION_RADIUS) -> Array:
	return visible_cells_multi(map_data, [{"pos": origin, "radius": radius}])

## Union des champs de vision de plusieurs sources.
## `sources` : [{ "pos": Vector2, "radius": float }]
static func visible_cells_multi(map_data: Dictionary, sources: Array) -> Array:
	var seen: Dictionary = {}
	if sources.is_empty():
		return []
	var width := int(map_data.get("width", 16))
	var height := int(map_data.get("height", 12))
	var segments := wall_segments(map_data)
	for source_variant in sources:
		var source: Dictionary = source_variant
		var origin: Vector2 = source.get("pos", Vector2.ZERO)
		var radius := float(source.get("radius", DEFAULT_VISION_RADIUS))
		if radius <= 0.0:
			continue
		var min_x: int = maxi(0, int(floorf(origin.x - radius)))
		var max_x: int = mini(width - 1, int(ceilf(origin.x + radius)))
		var min_y: int = maxi(0, int(floorf(origin.y - radius)))
		var max_y: int = mini(height - 1, int(ceilf(origin.y + radius)))
		for cy in range(min_y, max_y + 1):
			for cx in range(min_x, max_x + 1):
				var key := "%d,%d" % [cx, cy]
				if seen.has(key):
					continue
				var target := Vector2(float(cx), float(cy))
				if origin.distance_to(target) > radius:
					continue
				if is_clear(segments, origin, target):
					seen[key] = true
	return seen.keys()

## Sources de vision déduites des tokens.
##
## Par défaut, seuls les tokens rattachés à un membre du groupe éclairent la
## carte : un gobelin embusqué ne doit pas révéler sa propre cachette aux
## joueurs. `providesVision` permet de forcer le comportement dans les deux
## sens (familier qui voit, PJ aveuglé).
static func vision_sources_from_tokens(tokens: Array, default_radius: float = DEFAULT_VISION_RADIUS) -> Array:
	var sources: Array = []
	for token_variant in tokens:
		if not token_variant is Dictionary:
			continue
		var token: Dictionary = token_variant
		if bool(token.get("hidden", false)):
			continue
		if str(token.get("kind", "member")) == "marker":
			continue
		var provides = token.get("providesVision")
		if provides == null:
			provides = not str(token.get("memberId", "")).is_empty()
		if not bool(provides):
			continue
		sources.append({
			"pos": Vector2(float(token.get("x", 0.0)), float(token.get("y", 0.0))),
			"radius": float(token.get("visionRadius", default_radius)),
		})
	return sources

## Sources de vision issues des lumières posées sur la carte.
static func vision_sources_from_lights(map_data: Dictionary) -> Array:
	var sources: Array = []
	var lighting = map_data.get("lighting", {})
	if not lighting is Dictionary:
		return sources
	for source_variant in (lighting as Dictionary).get("sources", []):
		if not source_variant is Dictionary:
			continue
		var light: Dictionary = source_variant
		if bool(light.get("hidden", false)) or not bool(light.get("revealsFog", false)):
			continue
		sources.append({
			"pos": Vector2(float(light.get("x", 0.0)), float(light.get("y", 0.0))),
			"radius": float(light.get("radius", 3.0)),
		})
	return sources

# ===========================================================================
# Portes
# ===========================================================================

## Portes de la carte, avec leur état, pour l'UI MJ.
static func doors(map_data: Dictionary) -> Array:
	var out: Array = []
	var walls = map_data.get("walls", [])
	if not walls is Array:
		return out
	for wall_variant in walls:
		if wall_variant is Dictionary and bool((wall_variant as Dictionary).get("isDoor", false)):
			out.append(wall_variant)
	return out

## Renvoie une copie de `map_data` dont les portes reflètent l'état de session.
## Les portes appartiennent à la définition de carte, mais leur ouverture est un
## fait de partie : on ne modifie donc jamais la carte elle-même.
static func apply_door_states(map_data: Dictionary, door_states: Dictionary) -> Dictionary:
	if door_states.is_empty():
		return map_data
	var walls = map_data.get("walls", [])
	if not walls is Array or (walls as Array).is_empty():
		return map_data
	var patched: Array = []
	var touched := false
	for wall_variant in walls:
		if not wall_variant is Dictionary:
			continue
		var wall: Dictionary = wall_variant
		var id := str(wall.get("id", ""))
		if bool(wall.get("isDoor", false)) and door_states.has(id):
			wall = wall.duplicate(true)
			wall["open"] = bool(door_states[id])
			touched = true
		patched.append(wall)
	if not touched:
		return map_data
	var copy: Dictionary = map_data.duplicate()
	copy["walls"] = patched
	return copy

## Porte la plus proche d'une position, dans un rayon donné.
static func door_near(map_data: Dictionary, pos: Vector2, max_distance: float = 1.0) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := max_distance
	for door_variant in doors(map_data):
		var door: Dictionary = door_variant
		var distance := pos.distance_to(Vector2(float(door.get("x", 0.0)), float(door.get("y", 0.0))))
		if distance <= best_distance:
			best_distance = distance
			best = door
	return best
