class_name WorldZones
extends RefCounted

## Modèle de monde en zones rectangulaires, façon Dofus, avec zones de tailles
## différentes.
##
## Une zone **est** une carte existante : on stocke sa position et sa taille sur
## le plan du monde (en cases) ainsi que ses liens de bords. Le plan du monde est
## un plan 2D de cases ; le coin haut-gauche d'une zone est `(x, y)` et ses cases
## vont de `x` à `x + w - 1` sur l'axe X et de `y` à `y + h - 1` sur l'axe Y.
##
## Zone = `{id, title, x, y, w, h, edges}` avec :
## - `x`, `y`, `w`, `h` : entiers, en cases, sur le plan du monde ;
## - `edges` : `{north: {target, offset}, south: ..., east: ..., west: ...}`
##   où `target` est l'identifiant de la zone voisine (chaîne vide si aucun lien)
##   et `offset` le décalage signé, en cases, entre le début du bord de cette zone
##   et le début du bord du voisin (voir [method auto_detect_edges]).
##
## Toutes les fonctions sont statiques et pures : aucun autoload, aucun état, ce
## qui permet de les tester en headless. Ce fichier ne fait que le modèle ; la
## session et l'éditeur s'appuient dessus.

## Les quatre côtés, dans l'ordre d'itération stable utilisé partout.
const SIDES := ["north", "south", "east", "west"]

# ===========================================================================
# Construction d'une zone depuis une carte
# ===========================================================================

## Construit une zone à partir des données d'une carte (`map_data`).
##
## Lit `zoneX`, `zoneY`, `zoneW`, `zoneH` et `edges`. `w`/`h` retombent sur
## `width`/`height` de la carte quand `zoneW`/`zoneH` sont absents ; `x`/`y`
## valent 0 par défaut. `edges` est toujours normalisé sur les quatre côtés.
static func zone_from_map(map_data: Dictionary) -> Dictionary:
	var zone_w := int(map_data.get("zoneW", map_data.get("width", 0)))
	var zone_h := int(map_data.get("zoneH", map_data.get("height", 0)))
	return {
		"id": str(map_data.get("id", "")),
		"title": str(map_data.get("title", map_data.get("name", ""))),
		"x": int(map_data.get("zoneX", 0)),
		"y": int(map_data.get("zoneY", 0)),
		"w": zone_w,
		"h": zone_h,
		"edges": _normalize_edges(map_data.get("edges", {})),
	}

## Construit une zone avec une position et une taille imposées sur le plan du
## monde, en reprenant l'identité et les liens de `map_data`.
##
## Utile pour poser / redimensionner une zone dans l'éditeur de monde.
static func make_zone(map_data: Dictionary, x: int, y: int, w: int, h: int) -> Dictionary:
	var zone := zone_from_map(map_data)
	zone["x"] = x
	zone["y"] = y
	zone["w"] = w
	zone["h"] = h
	return zone

## Patch à appliquer à la carte pour y enregistrer la position, la taille et les
## liens de la zone : `{zoneX, zoneY, zoneW, zoneH, edges}`.
##
## Exemple : `map_data.merge(WorldZones.map_to_zone_patch(zone), true)`.
static func map_to_zone_patch(zone: Dictionary) -> Dictionary:
	return {
		"zoneX": int(zone.get("x", 0)),
		"zoneY": int(zone.get("y", 0)),
		"zoneW": int(zone.get("w", 0)),
		"zoneH": int(zone.get("h", 0)),
		"edges": _normalize_edges(zone.get("edges", {})),
	}

# ===========================================================================
# Plan du monde
# ===========================================================================

## Rectangle englobant toutes les zones sur le plan du monde, en cases.
##
## Renvoie un `Rect2i` vide (`Rect2i()`) si la liste est vide.
static func world_bounds(zones: Array) -> Rect2i:
	if zones.is_empty():
		return Rect2i()
	var first: Rect2i = _zone_rect(zones[0])
	var min_x := first.position.x
	var min_y := first.position.y
	var max_x := first.end.x
	var max_y := first.end.y
	for zone_variant in zones:
		var rect: Rect2i = _zone_rect(zone_variant)
		min_x = mini(min_x, rect.position.x)
		min_y = mini(min_y, rect.position.y)
		max_x = maxi(max_x, rect.end.x)
		max_y = maxi(max_y, rect.end.y)
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)

## Zone contenant la case `cell`, ou `{}` si aucune.
##
## En cas de monde invalide (zones qui se chevauchent), la première zone de la
## liste l'emporte ; [method validate] signale ce cas.
static func zone_at(zones: Array, cell: Vector2i) -> Dictionary:
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var rect: Rect2i = _zone_rect(zone)
		if cell.x >= rect.position.x and cell.x < rect.end.x \
				and cell.y >= rect.position.y and cell.y < rect.end.y:
			return zone
	return {}

# ===========================================================================
# Voisinage et bords
# ===========================================================================

## Détecte automatiquement les voisins de bord de chaque zone.
##
## Deux zones sont voisines si leurs rectangles se touchent sur un côté **sans se
## chevaucher** et si le recouvrement sur ce côté fait **au moins 1 case**. Un
## simple contact de coin (diagonale) n'est donc pas un lien.
##
## Renvoie `{zone_id: {side: {target: id, offset: int}}}` pour les seuls côtés
## reliés. `offset` est le décalage signé, en cases, entre le début du bord de la
## zone et le début du bord du voisin le long de ce bord :
## - pour `east`/`west` : `offset = voisin.y - zone.y` ;
## - pour `north`/`south` : `offset = voisin.x - zone.x`.
##
## Un offset positif signifie que le voisin commence `offset` cases après le
## début du bord de la zone ; il est négatif quand il commence avant. C'est ce
## décalage qui permet de gérer des zones de tailles différentes
## (cf. [method mirror_position]).
##
## Si plusieurs voisins se disputent le même côté (monde en escalier, cas
## limite), c'est le plus grand recouvrement qui l'emporte.
static func auto_detect_edges(zones: Array) -> Dictionary:
	var best: Dictionary = {}
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		best[str(zone.get("id", ""))] = {}

	for i in range(zones.size()):
		for j in range(i + 1, zones.size()):
			var a: Dictionary = zones[i]
			var b: Dictionary = zones[j]
			var candidate_ab := _touching_side(a, b)
			if not candidate_ab.is_empty():
				_keep_best_edge(best, a, candidate_ab, b)
			var candidate_ba := _touching_side(b, a)
			if not candidate_ba.is_empty():
				_keep_best_edge(best, b, candidate_ba, a)

	var result: Dictionary = {}
	for zone_id in best:
		var sides: Dictionary = {}
		var entries: Dictionary = best[zone_id]
		for side in SIDES:
			if not entries.has(side):
				continue
			var entry: Dictionary = entries[side]
			sides[side] = {
				"target": str(entry.get("target", "")),
				"offset": int(entry.get("offset", 0)),
			}
		result[zone_id] = sides
	return result

## Liens de bord explicites d'une zone, résolus contre la liste des zones.
##
## Renvoie `{side: {target: id, offset: int, zone: Dictionary}}` pour les côtés
## qui déclarent une cible non vide. `zone` vaut `{}` si la cible est absente du
## monde (lien cassé, signalé par [method validate]).
static func neighbors_of(zones: Array, zone_id: String) -> Dictionary:
	var zone := find_zone(zones, zone_id)
	if zone.is_empty():
		return {}
	var edges := _normalize_edges(zone.get("edges", {}))
	var result: Dictionary = {}
	for side in SIDES:
		var edge: Dictionary = edges[side]
		var target := str(edge.get("target", ""))
		if target.is_empty():
			continue
		result[side] = {
			"target": target,
			"offset": int(edge.get("offset", 0)),
			"zone": find_zone(zones, target),
		}
	return result

## Position dans la zone voisine quand on franchit `side` depuis `local`.
##
## `local` est exprimée en cases dans la zone courante (0..w / 0..h) ; on prend
## le point au bord, on le projette sur le plan du monde puis on le ramène dans
## la zone voisine. La coordonnée sur l'axe du franchissement devient la nouvelle
## entrée : 0 en sortant par `east` ou `south` (on entre par le bord ouest/nord du
## voisin), `w`/`h` du voisin en sortant par `west` ou `north`.
##
## La coordonnée le long du bord est translatée par `offset` (même convention que
## [method auto_detect_edges]) puis **clampée** dans la zone cible : c'est ce qui
## gère proprement des zones de tailles différentes ou des recouvrements
## partiels. L'aller-retour est exact pour tout point situé sur le bord partagé.
static func mirror_position(
	zone: Dictionary,
	side: String,
	local: Vector2,
	neighbor: Dictionary,
	offset: int
) -> Vector2:
	var neighbor_w := int(neighbor.get("w", 0))
	var neighbor_h := int(neighbor.get("h", 0))
	var delta := float(offset)
	match side:
		"east":
			return Vector2(0.0, clampf(local.y - delta, 0.0, float(neighbor_h)))
		"west":
			return Vector2(float(neighbor_w), clampf(local.y - delta, 0.0, float(neighbor_h)))
		"south":
			return Vector2(clampf(local.x - delta, 0.0, float(neighbor_w)), 0.0)
		"north":
			return Vector2(clampf(local.x - delta, 0.0, float(neighbor_w)), float(neighbor_h))
	return local

# ===========================================================================
# Validation
# ===========================================================================

## Vérifie la cohérence d'un monde de zones et renvoie les erreurs en français.
##
## Contrôles :
## - zone sans identifiant ou identifiant dupliqué ;
## - `w`/`h` <= 0, ou taille incohérente avec la carte quand la zone porte une
##   taille de carte déclarative (`mapW`/`mapH`, ou `width`/`height`) ;
## - deux zones qui se chevauchent (intérieur commun) ;
## - lien explicite vers une zone absente ;
## - lien explicite vers une zone qui n'est pas adjacente sur ce bord.
##
## Une liste vide signifie un monde valide.
static func validate(zones: Array) -> Array[String]:
	var errors: Array[String] = []
	var by_id: Dictionary = {}

	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var zone_id := str(zone.get("id", ""))
		var x := int(zone.get("x", 0))
		var y := int(zone.get("y", 0))
		var w := int(zone.get("w", 0))
		var h := int(zone.get("h", 0))

		if zone_id.is_empty():
			errors.append("Zone sans identifiant à la position (%d, %d)." % [x, y])
		elif by_id.has(zone_id):
			errors.append("Identifiant de zone dupliqué : '%s'." % zone_id)
		else:
			by_id[zone_id] = zone

		if w <= 0 or h <= 0:
			errors.append("Zone '%s' : taille invalide %d×%d." % [zone_id, w, h])

		var declared_w := _declared_map_size(zone, "W")
		if declared_w >= 0 and declared_w != w:
			errors.append(
				"Zone '%s' : taille incohérente avec sa carte (w=%d, carte=%d)."
				% [zone_id, w, declared_w]
			)
		var declared_h := _declared_map_size(zone, "H")
		if declared_h >= 0 and declared_h != h:
			errors.append(
				"Zone '%s' : taille incohérente avec sa carte (h=%d, carte=%d)."
				% [zone_id, h, declared_h]
			)

	# Chevauchements (intérieur commun, les bords partagés sont autorisés).
	for i in range(zones.size()):
		for j in range(i + 1, zones.size()):
			var a: Dictionary = zones[i]
			var b: Dictionary = zones[j]
			if _rects_overlap(a, b):
				errors.append(
					"Zones '%s' et '%s' se chevauchent." % [
						str(a.get("id", "")), str(b.get("id", ""))
					]
				)

	# Liens explicites.
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var zone_id := str(zone.get("id", ""))
		var edges := _normalize_edges(zone.get("edges", {}))
		for side in SIDES:
			var edge: Dictionary = edges[side]
			var target := str(edge.get("target", ""))
			if target.is_empty():
				continue
			if not by_id.has(target):
				errors.append(
					"Zone '%s' : lien %s vers la zone absente '%s'." % [zone_id, side, target]
				)
				continue
			var other: Dictionary = by_id[target]
			var touching := _touching_side(zone, other)
			if touching.is_empty() or str(touching.get("side", "")) != side:
				errors.append(
					"Zone '%s' : lien %s vers '%s' alors que les zones ne sont pas adjacentes sur ce bord."
					% [zone_id, side, target]
				)

	return errors

# ===========================================================================
# Utilitaires internes
# ===========================================================================

## Retrouve une zone par identifiant ; `{}` si absente.
static func find_zone(zones: Array, zone_id: String) -> Dictionary:
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		if str(zone.get("id", "")) == zone_id:
			return zone
	return {}

## Rectangle d'une zone en coordonnées de cases.
static func _zone_rect(zone: Dictionary) -> Rect2i:
	return Rect2i(
		int(zone.get("x", 0)),
		int(zone.get("y", 0)),
		int(zone.get("w", 0)),
		int(zone.get("h", 0))
	)

## Longueur du recouvrement de deux intervalles 1D ; 0 s'ils ne se touchent pas.
static func _overlap_len(a_start: int, a_len: int, b_start: int, b_len: int) -> int:
	var start := maxi(a_start, b_start)
	var end := mini(a_start + a_len, b_start + b_len)
	return maxi(0, end - start)

## Normalise `edges` : les quatre côtés toujours présents, `target` en chaîne et
## `offset` en entier. Accepte un dictionnaire `{target, offset}`, une simple
## chaîne (cible sans offset) ou l'absence de valeur.
static func _normalize_edges(value: Variant) -> Dictionary:
	var source: Dictionary = {}
	if value is Dictionary:
		source = value
	var edges: Dictionary = {}
	for side in SIDES:
		var edge: Dictionary = {"target": "", "offset": 0}
		if source.has(side):
			var raw: Variant = source[side]
			if raw is Dictionary:
				var raw_edge: Dictionary = raw
				edge["target"] = str(raw_edge.get("target", ""))
				edge["offset"] = int(raw_edge.get("offset", 0))
			elif raw is String and not str(raw).is_empty():
				edge["target"] = str(raw)
		edges[side] = edge
	return edges

## Côté de `zone` qui touche `other` sur au moins 1 case, sans chevauchement.
##
## Renvoie `{side, offset, overlap}` ou `{}`. Deux rectangles qui ne partagent
## qu'un coin ne renvoient rien (pas de lien diagonal).
static func _touching_side(zone: Dictionary, other: Dictionary) -> Dictionary:
	var zx := int(zone.get("x", 0))
	var zy := int(zone.get("y", 0))
	var zw := int(zone.get("w", 0))
	var zh := int(zone.get("h", 0))
	var ox := int(other.get("x", 0))
	var oy := int(other.get("y", 0))
	var ow := int(other.get("w", 0))
	var oh := int(other.get("h", 0))

	# Le voisin est à l'est : le bord est vertical, l'offset se lit sur Y.
	if zx + zw == ox:
		var overlap_y := _overlap_len(zy, zh, oy, oh)
		if overlap_y > 0:
			return {"side": "east", "offset": oy - zy, "overlap": overlap_y}
	# Le voisin est à l'ouest.
	if ox + ow == zx:
		var overlap_y_west := _overlap_len(zy, zh, oy, oh)
		if overlap_y_west > 0:
			return {"side": "west", "offset": oy - zy, "overlap": overlap_y_west}
	# Le voisin est au sud : le bord est horizontal, l'offset se lit sur X.
	if zy + zh == oy:
		var overlap_x := _overlap_len(zx, zw, ox, ow)
		if overlap_x > 0:
			return {"side": "south", "offset": ox - zx, "overlap": overlap_x}
	# Le voisin est au nord.
	if oy + oh == zy:
		var overlap_x_north := _overlap_len(zx, zw, ox, ow)
		if overlap_x_north > 0:
			return {"side": "north", "offset": ox - zx, "overlap": overlap_x_north}
	return {}

## Enregistre un candidat de lien en gardant le plus grand recouvrement par côté.
static func _keep_best_edge(
	best: Dictionary, zone: Dictionary, candidate: Dictionary, other: Dictionary
) -> void:
	var zone_id := str(zone.get("id", ""))
	if not best.has(zone_id):
		best[zone_id] = {}
	var sides: Dictionary = best[zone_id]
	var side := str(candidate.get("side", ""))
	var overlap := int(candidate.get("overlap", 0))
	if sides.has(side):
		var existing: Dictionary = sides[side]
		if int(existing.get("overlap", 0)) >= overlap:
			return
	sides[side] = {
		"target": str(other.get("id", "")),
		"offset": int(candidate.get("offset", 0)),
		"overlap": overlap,
	}

## Deux rectangles ont-ils un intérieur commun (bords partagés exclus) ?
static func _rects_overlap(a: Dictionary, b: Dictionary) -> bool:
	var overlap_x := _overlap_len(
		int(a.get("x", 0)), int(a.get("w", 0)), int(b.get("x", 0)), int(b.get("w", 0))
	)
	var overlap_y := _overlap_len(
		int(a.get("y", 0)), int(a.get("h", 0)), int(b.get("y", 0)), int(b.get("h", 0))
	)
	return overlap_x > 0 and overlap_y > 0

## Taille de carte déclarative portée par une zone (`-1` si absente).
##
## `axis` vaut `"W"` ou `"H"`. On accepte `mapW`/`mapH` (zone enrichie) ou
## `width`/`height` (carte brute), pour pouvoir vérifier l'égalité `zone.w/h`.
static func _declared_map_size(zone: Dictionary, axis: String) -> int:
	var map_key := "map" + axis
	if zone.has(map_key):
		return int(zone[map_key])
	var raw_key := "width" if axis == "W" else "height"
	if zone.has(raw_key):
		return int(zone[raw_key])
	return -1
