extends RefCounted
class_name MapFog

## Brouillard de guerre — logique pure sur les cellules explorées.
##
## Travaille directement sur le dictionnaire de carte (`map_data`) et
## l'état de jeu (`game`) sans dépendance Node.

## Retourne la clé textuelle unique d'une cellule (ex: "3,7").
static func cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]

## Retourne la liste des cellules explorées (clés "x,y") pour une carte.
static func get_explored_cells(game: Dictionary, map_id: String) -> Array:
	var entry := _map_play_entry(game, map_id)
	return entry.get("explored", [])

## Marque une cellule comme explorée.
static func reveal_cell(game: Dictionary, map_id: String, x: int, y: int) -> void:
	var entry := _map_play_entry(game, map_id)
	var explored: Array = entry.get("explored", [])
	var key := cell_key(x, y)
	if key not in explored:
		explored.append(key)
	entry["explored"] = explored

## Révèle toutes les cellules dans un rayon autour de (cx, cy).
static func reveal_radius(game: Dictionary, map_id: String, map_data: Dictionary, cx: int, cy: int, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var x := cx + dx
				var y := cy + dy
				if _is_in_bounds(map_data, x, y):
					reveal_cell(game, map_id, x, y)

## Retourne les cellules révélées par le brouillard dynamique (vision).
static func get_fog_revealed_cells(game: Dictionary, map_id: String) -> Array:
	var entry := _map_play_entry(game, map_id)
	return entry.get("fog_revealed", [])

## Initialise le brouillard pour une carte monde (tout est masqué sauf le départ).
static func init_world_map_fog(game: Dictionary, map_id: String, map_data: Dictionary) -> void:
	var entry := _map_play_entry(game, map_id)
	entry["explored"] = []
	entry["fog_revealed"] = []
	var start := _start_point(map_data)
	reveal_world_at(game, map_id, start.x, start.y, 2)

## Révèle les cellules autour d'un point sur une carte monde.
static func reveal_world_at(game: Dictionary, map_id: String, x: int, y: int, radius: int = 2) -> void:
	var entry := _map_play_entry(game, map_id)
	var explored: Array = entry.get("explored", [])
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var key := cell_key(x + dx, y + dy)
				if key not in explored:
					explored.append(key)
	entry["explored"] = explored

# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

static func _map_play_entry(game: Dictionary, map_id: String) -> Dictionary:
	if not game.has("map_play") or not game["map_play"] is Dictionary:
		game["map_play"] = {}
	if not game["map_play"].has(map_id) or not game["map_play"][map_id] is Dictionary:
		game["map_play"][map_id] = {}
	return game["map_play"][map_id]

static func _is_in_bounds(map_data: Dictionary, x: int, y: int) -> bool:
	var grid: Dictionary = map_data.get("grid", {})
	var w := int(grid.get("w", map_data.get("width", 0)))
	var h := int(grid.get("h", map_data.get("height", 0)))
	return x >= 0 and y >= 0 and x < w and y < h

static func _start_point(map_data: Dictionary) -> Vector2i:
	var sp = map_data.get("start_point", {})
	if sp is Dictionary:
		return Vector2i(int(sp.get("x", 0)), int(sp.get("y", 0)))
	return Vector2i.ZERO
