extends RefCounted
class_name SemanticMove

## Déplacement sémantique — extraction de `game_data.gd` (lignes ~3377-3910).
##
## Analyse le texte d'une action joueur pour détecter une intention de
## déplacement, calculer un delta directionnel ou résoudre une destination
## sémantique (lieu, marqueur, carte). Logique pure, sans dépendance Node.

const PLACE_KEYWORDS := ["vaisseau", "village", "taverne", "temple", "forge", "marché", "crypte", "château", "tour", "puits", "église", "auberge", "place", "forêt", "rivière", "pont", "port", "grotte", "cimetière"]

const CARDINALS := {
	"nord": Vector2i(0, -1),
	"sud": Vector2i(0, 1),
	"est": Vector2i(1, 0),
	"ouest": Vector2i(-1, 0),
	"nord-est": Vector2i(1, -1),
	"nord-ouest": Vector2i(-1, -1),
	"sud-est": Vector2i(1, 1),
	"sud-ouest": Vector2i(-1, 1),
}

## Analyse un texte d'action et retourne un Vector2i de déplacement (ou ZERO).
static func parse_movement_delta(action_text: String) -> Vector2i:
	var text := _normalize(action_text)
	var delta := Vector2i.ZERO
	for dir in CARDINALS:
		if dir in text:
			delta += CARDINALS[dir]
	if delta.length() > 0:
		return _clamp_delta(delta)
	return Vector2i.ZERO

## Retourne `true` si le texte ressemble à une action de déplacement.
static func looks_like_movement_action(action_text: String) -> bool:
	var text := _normalize(action_text)
	if parse_movement_delta(action_text) != Vector2i.ZERO:
		return true
	for word in PLACE_KEYWORDS:
		if word in text:
			return true
	return "me déplace" in text or "aller à" in text

## Retourne `true` si le texte exprime une intention de déplacement vers une destination.
static func has_semantic_destination_intent(action_text: String) -> bool:
	var text := _normalize(action_text)
	return "aller à" in text or "me dirige" in text or "me rends" in text

## Retourne `true` si le texte contient une direction cardinale explicite.
static func has_explicit_cardinal_direction(action_text: String) -> bool:
	var text := _normalize(action_text)
	for dir in CARDINALS:
		if dir in text:
			return true
	return false

## Résout une destination sémantique en coordonnées grille.
static func resolve_semantic_destination(action_text: String, map_data: Dictionary, from_pos: Vector2i) -> Vector2i:
	var text := _normalize(action_text)
	var candidates := _collect_candidates(map_data, text)
	if candidates.is_empty():
		return from_pos
	return _pick_nearest(from_pos, candidates)

## Tente un déplacement automatique depuis une action textuelle.
## Retourne `{ moved: bool, position: Vector2i }`.
static func try_auto_move_from_action(action_text: String, map_data: Dictionary, current_pos: Vector2i) -> Dictionary:
	if not looks_like_movement_action(action_text):
		return { "moved": false, "position": current_pos }
	var delta := parse_movement_delta(action_text)
	if delta != Vector2i.ZERO:
		var new_pos := current_pos + delta
		if _is_walkable(map_data, new_pos):
			return { "moved": true, "position": new_pos }
	var dest := resolve_semantic_destination(action_text, map_data, current_pos)
	if dest != current_pos:
		return { "moved": true, "position": dest }
	return { "moved": false, "position": current_pos }

# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

static func _normalize(text: String) -> String:
	return text.strip_edges().to_lower()

static func _clamp_delta(delta: Vector2i) -> Vector2i:
	return Vector2i(clampi(delta.x, -1, 1), clampi(delta.y, -1, 1))

static func _collect_candidates(map_data: Dictionary, text: String) -> Array:
	var out: Array = []
	for m in map_data.get("markers", []):
		if not m is Dictionary:
			continue
		var label: String = m.get("label", "").to_lower()
		if label != "" and label in text:
			out.append(Vector2i(int(m.get("x", 0)), int(m.get("y", 0))))
	return out

static func _pick_nearest(from: Vector2i, candidates: Array) -> Vector2i:
	if candidates.is_empty():
		return from
	var best: Vector2i = candidates[0]
	var best_dist := _manhattan(from, best)
	for c in candidates:
		var d := _manhattan(from, c)
		if d < best_dist:
			best = c
			best_dist = d
	return best

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _is_walkable(map_data: Dictionary, pos: Vector2i) -> bool:
	var grid: Dictionary = map_data.get("grid", {})
	var w := int(grid.get("w", map_data.get("width", 0)))
	var h := int(grid.get("h", map_data.get("height", 0)))
	if pos.x < 0 or pos.y < 0 or pos.x >= w or pos.y >= h:
		return false
	var tiles: Array = map_data.get("tiles", [])
	var idx := pos.y * w + pos.x
	if idx < tiles.size():
		var tile_id: String = tiles[idx]
		return tile_id != "wall" and tile_id != "water"
	return true
