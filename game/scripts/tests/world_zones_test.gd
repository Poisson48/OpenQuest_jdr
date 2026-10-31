extends SceneTree

## Tests headless du modèle de monde en zones (façon Dofus, tailles différentes).
##
## Monde de référence, en cases, sur le plan 2D :
##   A 12×9 en (0, 0) | B 9×9 en (12, 0)
##   C 15×12 en (0, 9) — sous A et sous une partie de B.
## Vérifie l'auto-détection des bords (offsets compris), l'absence de lien
## diagonal, les recouvrements partiels, les positions miroir (aller-retour et
## clamp), le plan du monde et la validation. Affiche `world_zones_test:PASS` et
## quitte avec le code 0 en cas de succès (`FAIL` + code 1 sinon).

const Zones := preload("res://scripts/maps/world/world_zones.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	_test_zone_from_map_and_patch()
	_test_auto_detect_edges()
	_test_neighbors_of()
	_test_diagonal_and_partial_edges()
	_test_mirror_position()
	_test_world_bounds_and_zone_at()
	_test_validate()

	if _failed:
		quit(1)
		return
	print("world_zones_test:PASS")
	quit(0)

# ===========================================================================
# Construction d'une zone depuis une carte
# ===========================================================================

func _test_zone_from_map_and_patch() -> void:
	# Carte sans métadonnées de zone : w/h retombent sur width/height, x/y = 0.
	var zone: Dictionary = Zones.zone_from_map({
		"id": "map-a", "title": "Forêt", "width": 12, "height": 9,
	})
	_assert("from_map_id", str(zone.get("id", "")) == "map-a")
	_assert("from_map_title", str(zone.get("title", "")) == "Forêt")
	_assert("from_map_default_xy", int(zone.get("x", -1)) == 0 and int(zone.get("y", -1)) == 0)
	_assert("from_map_fallback_size", int(zone.get("w", 0)) == 12 and int(zone.get("h", 0)) == 9)
	_assert("from_map_edges_normalised", _edge_dict(zone.get("edges", {}), "north") == {
		"target": "", "offset": 0,
	})
	var plain_edges: Dictionary = zone.get("edges", {})
	_assert("from_map_edges_four", plain_edges.size() == 4)

	# Carte avec position/taille/liens de zone.
	var zoned_map := {
		"id": "map-b", "title": "Village", "width": 6, "height": 5,
		"zoneX": 3, "zoneY": 2, "zoneW": 6, "zoneH": 5,
		"edges": {
			"north": {"target": "map-a", "offset": 2},
			"south": {"target": "", "offset": 0},
			"west": "map-a",
		},
	}
	var zoned: Dictionary = Zones.zone_from_map(zoned_map)
	_assert("from_map_zoned_xywh",
		int(zoned.get("x", -1)) == 3 and int(zoned.get("y", -1)) == 2
		and int(zoned.get("w", 0)) == 6 and int(zoned.get("h", 0)) == 5)
	var north := _edge_dict(zoned.get("edges", {}), "north")
	_assert("from_map_edge_north", str(north.get("target", "")) == "map-a" and int(north.get("offset", 0)) == 2)
	var east := _edge_dict(zoned.get("edges", {}), "east")
	_assert("from_map_edge_east_empty", str(east.get("target", "")).is_empty())
	var west := _edge_dict(zoned.get("edges", {}), "west")
	_assert("from_map_edge_string_form", str(west.get("target", "")) == "map-a" and int(west.get("offset", 0)) == 0)

	# make_zone impose position et taille, en gardant identité et liens.
	var made: Dictionary = Zones.make_zone(zoned_map, 10, 11, 6, 4)
	_assert("make_zone_xywh",
		int(made.get("x", -1)) == 10 and int(made.get("y", -1)) == 11
		and int(made.get("w", 0)) == 6 and int(made.get("h", 0)) == 4)
	_assert("make_zone_keeps_id", str(made.get("id", "")) == "map-b")
	_assert("make_zone_keeps_edges",
		str(_edge_dict(made.get("edges", {}), "north").get("target", "")) == "map-a")

	# Patch : même contenu que la zone côté plan du monde.
	var patch: Dictionary = Zones.map_to_zone_patch(made)
	_assert("patch_keys", patch.has("zoneX") and patch.has("zoneY")
		and patch.has("zoneW") and patch.has("zoneH") and patch.has("edges"))
	_assert("patch_values",
		int(patch.get("zoneX", -1)) == 10 and int(patch.get("zoneY", -1)) == 11
		and int(patch.get("zoneW", 0)) == 6 and int(patch.get("zoneH", 0)) == 4)

	# Aller-retour carte → zone → patch → carte.
	var applied: Dictionary = zoned_map.duplicate(true)
	applied.merge(patch, true)
	var reloaded: Dictionary = Zones.zone_from_map(applied)
	_assert("roundtrip_identity",
		str(reloaded.get("id", "")) == str(made.get("id", ""))
		and str(reloaded.get("title", "")) == str(made.get("title", "")))
	_assert("roundtrip_xywh",
		int(reloaded.get("x", -1)) == 10 and int(reloaded.get("y", -1)) == 11
		and int(reloaded.get("w", 0)) == 6 and int(reloaded.get("h", 0)) == 4)
	_assert("roundtrip_edges",
		str(_edge_dict(reloaded.get("edges", {}), "north").get("target", "")) == "map-a"
		and int(_edge_dict(reloaded.get("edges", {}), "north").get("offset", 0)) == 2)

# ===========================================================================
# Voisinage automatique
# ===========================================================================

func _test_auto_detect_edges() -> void:
	var world := _world()
	var edges: Dictionary = Zones.auto_detect_edges(world)

	# A ↔ B : est / ouest, même ligne de départ, offset 0.
	_assert("auto_a_east", _edge(edges, "map-a", "east").get("target", "") == "map-b")
	_assert("auto_a_east_offset", int(_edge(edges, "map-a", "east").get("offset", -1)) == 0)
	_assert("auto_b_west", _edge(edges, "map-b", "west").get("target", "") == "map-a")
	_assert("auto_b_west_offset", int(_edge(edges, "map-b", "west").get("offset", -1)) == 0)

	# A ↔ C : sud / nord, même colonne de départ, offset 0.
	_assert("auto_a_south", _edge(edges, "map-a", "south").get("target", "") == "map-c")
	_assert("auto_a_south_offset", int(_edge(edges, "map-a", "south").get("offset", -1)) == 0)
	_assert("auto_c_north", _edge(edges, "map-c", "north").get("target", "") == "map-a")
	_assert("auto_c_north_offset", int(_edge(edges, "map-c", "north").get("offset", -1)) == 0)

	# C nord touche aussi B (2 cases) mais A recouvre 12 cases : priorité au plus
	# grand recouvrement.
	_assert("auto_c_north_prefers_a", _edge(edges, "map-c", "north").get("target", "") != "map-b")

	# B sud touche C sur 2 cases : voisinage partiel détecté, offset négatif.
	var b_south := _edge(edges, "map-b", "south")
	_assert("auto_b_south_partial", str(b_south.get("target", "")) == "map-c")
	_assert("auto_b_south_offset", int(b_south.get("offset", 0)) == -12)

	# Côtés sans voisin : pas de faux lien.
	_assert("auto_a_north_empty", _edge(edges, "map-a", "north").is_empty())
	_assert("auto_a_west_empty", _edge(edges, "map-a", "west").is_empty())
	_assert("auto_b_north_empty", _edge(edges, "map-b", "north").is_empty())
	_assert("auto_b_east_empty", _edge(edges, "map-b", "east").is_empty())
	_assert("auto_c_south_empty", _edge(edges, "map-c", "south").is_empty())
	_assert("auto_c_east_empty", _edge(edges, "map-c", "east").is_empty())
	_assert("auto_c_west_empty", _edge(edges, "map-c", "west").is_empty())

	# Toutes les zones ont une entrée dans la table résultat.
	_assert("auto_all_zones", edges.has("map-a") and edges.has("map-b") and edges.has("map-c"))

# ===========================================================================
# Liens explicites résolus
# ===========================================================================

func _test_neighbors_of() -> void:
	var a: Dictionary = Zones.zone_from_map({
		"id": "map-a", "title": "A", "width": 12, "height": 9,
		"edges": {
			"east": {"target": "map-b", "offset": 0},
			"south": {"target": "", "offset": 0},
		},
	})
	var b: Dictionary = Zones.zone_from_map({
		"id": "map-b", "title": "B", "width": 9, "height": 9,
	})
	var zones := [a, b]
	var links: Dictionary = Zones.neighbors_of(zones, "map-a")
	_assert("neighbors_east_only", links.has("east") and not links.has("south")
		and not links.has("north") and not links.has("west"))
	var east: Dictionary = links.get("east", {})
	_assert("neighbors_east_target", str(east.get("target", "")) == "map-b")
	_assert("neighbors_east_offset", int(east.get("offset", -1)) == 0)
	var resolved: Dictionary = east.get("zone", {})
	_assert("neighbors_east_resolved", str(resolved.get("id", "")) == "map-b"
		and str(resolved.get("title", "")) == "B")

	# Zone inconnue.
	_assert("neighbors_unknown_zone", Zones.neighbors_of(zones, "map-ghost").is_empty())

	# Cible absente : le lien est retourné mais la zone résolue est vide.
	var broken: Dictionary = a.duplicate(true)
	broken["edges"]["west"] = {"target": "map-ghost", "offset": 0}
	var broken_links: Dictionary = Zones.neighbors_of([broken, b], "map-a")
	var west: Dictionary = broken_links.get("west", {})
	_assert("neighbors_broken_target", str(west.get("target", "")) == "map-ghost")
	var unresolved: Dictionary = west.get("zone", {})
	_assert("neighbors_broken_unresolved", unresolved.is_empty())

# ===========================================================================
# Diagonales et recouvrement partiel
# ===========================================================================

func _test_diagonal_and_partial_edges() -> void:
	# Deux zones qui ne partagent qu'un coin : pas de lien (pas de diagonale).
	var f := _zone("map-f", 100, 100, 4, 4)
	var g := _zone("map-g", 104, 104, 4, 4)
	var diagonal: Dictionary = Zones.auto_detect_edges([f, g])
	_assert("diagonal_f_no_edge", _sides(diagonal, "map-f").is_empty())
	_assert("diagonal_g_no_edge", _sides(diagonal, "map-g").is_empty())

	# D 6×4 posée à cheval sur la moitié du bord est de C : lien partiel avec
	# offset de 1 case dans un sens et -1 dans l'autre (tailles différentes).
	var c := _zone("map-c", 0, 9, 15, 12)
	var d := _zone("map-d", 15, 10, 6, 4)
	var partial: Dictionary = Zones.auto_detect_edges([c, d])
	_assert("partial_c_east", _edge(partial, "map-c", "east").get("target", "") == "map-d")
	_assert("partial_c_east_offset", int(_edge(partial, "map-c", "east").get("offset", 0)) == 1)
	_assert("partial_d_west", _edge(partial, "map-d", "west").get("target", "") == "map-c")
	_assert("partial_d_west_offset", int(_edge(partial, "map-d", "west").get("offset", 0)) == -1)
	# Les autres côtés de D ne touchent rien.
	_assert("partial_d_other_sides_empty",
		_edge(partial, "map-d", "north").is_empty()
		and _edge(partial, "map-d", "east").is_empty()
		and _edge(partial, "map-d", "south").is_empty())
	_assert("partial_c_south_empty", _edge(partial, "map-c", "south").is_empty())

# ===========================================================================
# Position miroir
# ===========================================================================

func _test_mirror_position() -> void:
	var world := _world()
	var a: Dictionary = world[0]
	var b: Dictionary = world[1]
	var c: Dictionary = world[2]

	# Est / ouest : on sort de A par l'est, on entre en B par l'ouest.
	_assert("mirror_east", Zones.mirror_position(a, "east", Vector2(12, 5), b, 0) == Vector2(0, 5))
	_assert("mirror_west_back", Zones.mirror_position(b, "west", Vector2(0, 5), a, 0) == Vector2(12, 5))

	# Aller-retour exact pour plusieurs positions le long du bord partagé.
	for y in [3, 5, 7]:
		var forward := Zones.mirror_position(a, "east", Vector2(12, float(y)), b, 0)
		var backward := Zones.mirror_position(b, "west", forward, a, 0)
		_assert("mirror_roundtrip_east_%d" % y, backward == Vector2(12, float(y)))

	# Sud / nord.
	_assert("mirror_south", Zones.mirror_position(a, "south", Vector2(7, 9), c, 0) == Vector2(7, 0))
	_assert("mirror_north_back", Zones.mirror_position(c, "north", Vector2(7, 0), a, 0) == Vector2(7, 9))

	# Recouvrement partiel, tailles différentes : C est → D ouest, offsets ±1.
	# Le recouvrement est en monde y 10..13, soit les cases locales 1..4 de C.
	var d := _zone("map-d", 15, 10, 6, 4)
	_assert("mirror_partial_east",
		Zones.mirror_position(c, "east", Vector2(15, 2), d, 1) == Vector2(0, 1))
	_assert("mirror_partial_west_back",
		Zones.mirror_position(d, "west", Vector2(0, 1), c, -1) == Vector2(15, 2))
	for y in [1, 2, 3, 4]:
		var forward_partial := Zones.mirror_position(c, "east", Vector2(15, float(y)), d, 1)
		var backward_partial := Zones.mirror_position(d, "west", forward_partial, c, -1)
		_assert("mirror_roundtrip_partial_%d" % y, backward_partial == Vector2(15, float(y)))

	# Clamp dans la zone cible quand la position sort du recouvrement.
	_assert("mirror_clamp_start",
		Zones.mirror_position(c, "east", Vector2(15, 0), d, 1) == Vector2(0, 0))
	_assert("mirror_clamp_end",
		Zones.mirror_position(c, "east", Vector2(15, 20), d, 1) == Vector2(0, 4))
	# Clamp sur l'axe X lors d'une sortie sud partielle de B vers C (offset -12).
	_assert("mirror_clamp_x",
		Zones.mirror_position(b, "south", Vector2(4, 9), c, -12) == Vector2(15, 0))

# ===========================================================================
# Plan du monde et cases
# ===========================================================================

func _test_world_bounds_and_zone_at() -> void:
	var world := _world()
	var bounds: Rect2i = Zones.world_bounds(world)
	_assert("bounds_position", bounds.position == Vector2i(0, 0))
	_assert("bounds_size", bounds.size == Vector2i(21, 21))
	_assert("bounds_empty", Zones.world_bounds([]).size == Vector2i(0, 0))

	_assert("zone_at_a_origin", str(Zones.zone_at(world, Vector2i(0, 0)).get("id", "")) == "map-a")
	_assert("zone_at_a_last", str(Zones.zone_at(world, Vector2i(11, 8)).get("id", "")) == "map-a")
	_assert("zone_at_b_origin", str(Zones.zone_at(world, Vector2i(12, 0)).get("id", "")) == "map-b")
	_assert("zone_at_b_last", str(Zones.zone_at(world, Vector2i(20, 8)).get("id", "")) == "map-b")
	_assert("zone_at_c_origin", str(Zones.zone_at(world, Vector2i(0, 9)).get("id", "")) == "map-c")
	_assert("zone_at_c_under_b", str(Zones.zone_at(world, Vector2i(12, 9)).get("id", "")) == "map-c")
	_assert("zone_at_c_last", str(Zones.zone_at(world, Vector2i(14, 20)).get("id", "")) == "map-c")
	_assert("zone_at_outside_x", Zones.zone_at(world, Vector2i(21, 20)).is_empty())
	_assert("zone_at_outside_y", Zones.zone_at(world, Vector2i(0, 21)).is_empty())

	# Avec D, la case (15, 10) lui appartient ; (15, 9) reste hors zone.
	var with_d: Array = world.duplicate()
	with_d.append(_zone("map-d", 15, 10, 6, 4))
	_assert("zone_at_d", str(Zones.zone_at(with_d, Vector2i(15, 10)).get("id", "")) == "map-d")
	_assert("zone_at_d_last", str(Zones.zone_at(with_d, Vector2i(20, 13)).get("id", "")) == "map-d")
	_assert("zone_at_d_outside", Zones.zone_at(with_d, Vector2i(15, 9)).is_empty())

# ===========================================================================
# Validation
# ===========================================================================

func _test_validate() -> void:
	var world := _world()
	_assert("validate_world_valid", Zones.validate(world).is_empty())

	# Chevauchement franc : E posée sur A.
	var e := _zone("map-e", 5, 5, 6, 4)
	var overlap_errors: Array = Zones.validate([world[0], e])
	_assert("validate_overlap", _has_error(overlap_errors, "chevauchent"))

	# Lien cassé : cible absente du monde.
	var a_zone: Dictionary = world[0]
	var b_zone: Dictionary = world[1]
	var c_zone: Dictionary = world[2]
	var broken: Dictionary = a_zone.duplicate(true)
	broken["edges"]["north"] = {"target": "map-fantome", "offset": 0}
	var broken_errors: Array = Zones.validate([broken, b_zone, c_zone])
	_assert("validate_missing_target", _has_error(broken_errors, "absente"))

	# Lien non adjacent : A lie son nord à C, qui est au sud de A.
	var non_adjacent: Dictionary = a_zone.duplicate(true)
	non_adjacent["edges"]["north"] = {"target": "map-c", "offset": 0}
	var adjacent_errors: Array = Zones.validate([non_adjacent, b_zone, c_zone])
	_assert("validate_non_adjacent", _has_error(adjacent_errors, "pas adjacentes"))

	# Taille nulle.
	var flat := _zone("map-flat", 40, 40, 0, 9)
	var size_errors: Array = Zones.validate([flat])
	_assert("validate_bad_size", _has_error(size_errors, "taille invalide"))

	# Taille incohérente avec la carte (mapW déclaratif).
	var mismatched := _zone("map-mismatch", 50, 50, 12, 9)
	mismatched["mapW"] = 10
	var mismatch_errors: Array = Zones.validate([mismatched])
	_assert("validate_map_size", _has_error(mismatch_errors, "incohérente"))

	# Identifiants dupliqués.
	var duplicate_a := _zone("map-a", 60, 60, 3, 3)
	var duplicate_errors: Array = Zones.validate([world[0], duplicate_a])
	_assert("validate_duplicate_id", _has_error(duplicate_errors, "dupliqué"))

# ===========================================================================
# Constructeurs et assertions
# ===========================================================================

## Monde de référence : A 12×9 en (0,0), B 9×9 en (12,0), C 15×12 en (0,9).
func _world() -> Array:
	return [
		_zone("map-a", 0, 0, 12, 9),
		_zone("map-b", 12, 0, 9, 9),
		_zone("map-c", 0, 9, 15, 12),
	]

func _zone(id: String, x: int, y: int, w: int, h: int) -> Dictionary:
	var map_data := {"id": id, "title": id, "width": w, "height": h}
	return Zones.make_zone(map_data, x, y, w, h)

## Entrée `side` de `edges` pour une zone donnée ({side: {target, offset}}).
func _edge(edges: Dictionary, zone_id: String, side: String) -> Dictionary:
	var sides: Dictionary = edges.get(zone_id, {})
	return sides.get(side, {})

## Table des côtés détectés pour une zone (`{}` si aucun).
func _sides(edges: Dictionary, zone_id: String) -> Dictionary:
	return edges.get(zone_id, {})

## Entrée `side` d'une table `edges` normalisée (les quatre côtés présents).
func _edge_dict(edges: Dictionary, side: String) -> Dictionary:
	return edges.get(side, {})

func _has_error(errors: Array, needle: String) -> bool:
	for error in errors:
		if str(error).contains(needle):
			return true
	return false

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("world_zones_test:FAIL at ", name)
		_failed = true
