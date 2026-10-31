class_name WorldNavigation
extends RefCounted

## Navigation par les bords entre zones d'un monde façon Dofus (zones de tailles
## différentes). Logique pure, testable en headless : ne touche ni à la session
## ni au rendu.
##
## Convention de coordonnées : positions **en cases centrées** (comme les tokens
## et `editor_pointer_*`), `x` ∈ [0, w-1], `y` ∈ [0, h-1]. Les conversions vers
## les coordonnées de bord de [WorldZones] se font avec +0.5 / -0.5.

const WorldZonesScript := preload("res://scripts/maps/world/world_zones.gd")

## Toutes les zones d'un monde (cartes complexes portant un `worldId`).
static func zones_for_world(maps: Array, world_id: String) -> Array:
	var out: Array = []
	for map_variant in maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("renderMode", "")) != "complex":
			continue
		if not world_id.is_empty() and str(map.get("worldId", "")) != world_id:
			continue
		var zone: Dictionary = WorldZonesScript.zone_from_map(map)
		if int(zone.get("w", 0)) <= 0 or int(zone.get("h", 0)) <= 0:
			continue
		out.append(zone)
	return out

static func _zone_by_id(zones: Array, zone_id: String) -> Dictionary:
	for zone_variant in zones:
		if str((zone_variant as Dictionary).get("id", "")) == zone_id:
			return zone_variant
	return {}

## Voisin d'une zone sur un côté, à partir des liens explicites (`edges`) sinon
## de l'auto-détection des bords. Renvoie `{target, offset}` (target vide si aucun).
static func neighbor_on_side(zones: Array, zone: Dictionary, side: String) -> Dictionary:
	var edges: Dictionary = zone.get("edges", {}) if zone.get("edges") is Dictionary else {}
	var edge: Dictionary = edges.get(side, {}) if edges.get(side) is Dictionary else {}
	var target := str(edge.get("target", ""))
	if not target.is_empty():
		return {"target": target, "offset": int(edge.get("offset", 0))}
	# Repli : auto-détection sur l'ensemble du monde.
	var detected: Dictionary = WorldZonesScript.auto_detect_edges(zones)
	var by_zone: Dictionary = detected.get(str(zone.get("id", "")), {})
	var auto: Dictionary = by_zone.get(side, {}) if by_zone.get(side) is Dictionary else {}
	return {"target": str(auto.get("target", "")), "offset": int(auto.get("offset", 0))}

## Côté de carte franchi pour une position de case (centrée). Vide si la position
## est à l'intérieur de la carte.
static func edge_side_for_position(map_data: Dictionary, pos: Vector2) -> String:
	var w := float(map_data.get("width", 0))
	var h := float(map_data.get("height", 0))
	if w <= 0.0 or h <= 0.0:
		return ""
	if pos.x < 0.0:
		return "west"
	if pos.x > w - 1.0:
		return "east"
	if pos.y < 0.0:
		return "north"
	if pos.y > h - 1.0:
		return "south"
	return ""

## Résout une transition de bord :
## `{ok, target_map_id, position, target_zone}`. `local_pos` en cases centrées.
static func resolve_edge_transition(
		maps: Array,
		current_map_id: String,
		side: String,
		local_pos: Vector2
) -> Dictionary:
	if not side in ["north", "south", "east", "west"]:
		return {"ok": false}
	var current_map: Dictionary = {}
	for map_variant in maps:
		if map_variant is Dictionary and str((map_variant as Dictionary).get("id", "")) == current_map_id:
			current_map = map_variant
			break
	if current_map.is_empty():
		return {"ok": false}
	var world_id := str(current_map.get("worldId", ""))
	var zones: Array = zones_for_world(maps, world_id)
	var zone: Dictionary = _zone_by_id(zones, current_map_id)
	if zone.is_empty():
		return {"ok": false}
	var neighbor_info: Dictionary = neighbor_on_side(zones, zone, side)
	var target_id := str(neighbor_info.get("target", ""))
	if target_id.is_empty():
		return {"ok": false}
	var target_zone: Dictionary = _zone_by_id(zones, target_id)
	if target_zone.is_empty():
		return {"ok": false}
	var offset := int(neighbor_info.get("offset", 0))
	# Coordonnées de bord (0..w / 0..h) ↔ cases centrées.
	var border_local := local_pos + Vector2(0.5, 0.5)
	var target_border := WorldZonesScript.mirror_position(zone, side, border_local, target_zone, offset)
	var target_pos := target_border - Vector2(0.5, 0.5)
	var tw := maxf(0.0, float(target_zone.get("w", 1)) - 1.0)
	var th := maxf(0.0, float(target_zone.get("h", 1)) - 1.0)
	target_pos.x = clampf(target_pos.x, 0.0, tw)
	target_pos.y = clampf(target_pos.y, 0.0, th)
	return {
		"ok": true,
		"target_map_id": target_id,
		"position": target_pos,
		"target_zone": target_zone,
	}

## Vrai si la carte a au moins un bord relié à une zone voisine.
static func can_cross(maps: Array, map_id: String) -> bool:
	var current_map: Dictionary = {}
	for map_variant in maps:
		if map_variant is Dictionary and str((map_variant as Dictionary).get("id", "")) == map_id:
			current_map = map_variant
			break
	if current_map.is_empty():
		return false
	var zones: Array = zones_for_world(maps, str(current_map.get("worldId", "")))
	var zone: Dictionary = _zone_by_id(zones, map_id)
	if zone.is_empty():
		return false
	for side in ["north", "south", "east", "west"]:
		if not str(neighbor_on_side(zones, zone, side).get("target", "")).is_empty():
			return true
	return false
