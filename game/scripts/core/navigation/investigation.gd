extends RefCounted
class_name Investigation

## Indices d'enquête — extraction de `game_data.gd` (lignes ~2803-2940).
##
## Gère l'initialisation, la révélation et la progression des indices
## d'enquête dans les cartes de type investigation. Logique pure.

## Initialise les indices d'enquête pour toutes les cartes de la partie.
static func init_investigation_clues_for_game(game: Dictionary) -> void:
	var map_play: Dictionary = game.get("map_play", {})
	for map_id in map_play.keys():
		init_investigation_clues(game, map_id)

## Initialise les indices d'enquête pour une carte donnée.
static func init_investigation_clues(game: Dictionary, map_id: String, map_data: Dictionary = {}) -> void:
	var entry := _map_play_entry(game, map_id)
	if entry.has("investigation_clues"):
		return
	var clues: Array = []
	for marker in map_data.get("markers", []):
		if not marker is Dictionary:
			continue
		if marker.get("type", "") == "clue" or marker.get("type", "") == "indice":
			clues.append({
				"x": int(marker.get("x", 0)),
				"y": int(marker.get("y", 0)),
				"revealed": false,
				"label": marker.get("label", "Indice"),
			})
	entry["investigation_clues"] = clues

## Révèle les indices dans un rayon autour de (cx, cy). Retourne le nombre révélés.
static func reveal_investigation_near(game: Dictionary, map_id: String, cx: int, cy: int, radius: int = 1) -> int:
	var entry := _map_play_entry(game, map_id)
	var clues: Array = entry.get("investigation_clues", [])
	var count := 0
	for clue in clues:
		if clue.get("revealed", false):
			continue
		var x := int(clue.get("x", 0))
		var y := int(clue.get("y", 0))
		if absi(x - cx) <= radius and absi(y - cy) <= radius:
			clue["revealed"] = true
			count += 1
	return count

## Révèle les `count` prochains indices non révélés.
static func reveal_next_investigation_clues(game: Dictionary, map_id: String, count: int = 1) -> int:
	var entry := _map_play_entry(game, map_id)
	var clues: Array = entry.get("investigation_clues", [])
	var revealed := 0
	for clue in clues:
		if revealed >= count:
			break
		if not clue.get("revealed", false):
			clue["revealed"] = true
			revealed += 1
	return revealed

## Tente de révéler un indice à partir d'une action textuelle.
static func maybe_reveal_investigation_from_action(game: Dictionary, map_id: String, action_text: String, _map_data: Dictionary = {}) -> int:
	var text := action_text.strip_edges().to_lower()
	var keywords := ["inspect", "fouille", "cherche", "examine", "observe", "indice", "clue", "piste"]
	for kw in keywords:
		if kw in text:
			var entry := _map_play_entry(game, map_id)
			for clue in entry.get("investigation_clues", []):
				if not clue.get("revealed", false):
					clue["revealed"] = true
					return 1
			return 0
	return 0

## Retourne les indices révélés pour une carte.
static func get_revealed_clues(game: Dictionary, map_id: String) -> Array:
	var entry := _map_play_entry(game, map_id)
	var clues: Array = entry.get("investigation_clues", [])
	return clues.filter(func(c): return c.get("revealed", false))

## Retourne tous les indices (révélés ou non) pour une carte.
static func get_all_clues(game: Dictionary, map_id: String) -> Array:
	var entry := _map_play_entry(game, map_id)
	return entry.get("investigation_clues", [])

# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

static func _map_play_entry(game: Dictionary, map_id: String) -> Dictionary:
	if not game.has("map_play") or not game["map_play"] is Dictionary:
		game["map_play"] = {}
	if not game["map_play"].has(map_id) or not game["map_play"][map_id] is Dictionary:
		game["map_play"][map_id] = {}
	return game["map_play"][map_id]
