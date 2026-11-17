extends RefCounted

## Roster / groupe de session (lot 3 du refactor, phase 2.7) — logique **pure**.
##
## Extrait de `game/scripts/autoload/game_data.gd` : accès aux membres jouables,
## membre actif, inventaires de session, résumé de groupe et filtres de
## personnages par roster/format. Aucune dépendance `Node` ni autoload : chaque
## fonction reçoit le dictionnaire de partie (`active_game`) ou la liste
## d'entités à filtrer.
##
## Les dictionnaires retournés sont des **références** vers `game["party"]`
## (comme avant l'extraction) : les appelants peuvent les muter en place.

const QUEST_FORMAT_INVESTIGATION := "investigation"


## Membres qui peuvent jouer : les humains, ou tout le groupe s'il n'y a que
## des bots / entités sans `isHuman` (même contrat que `get_playable_members`).
static func playable_members(game: Dictionary) -> Array:
	if game.is_empty():
		return []
	var party: Array = game.get("party", [])
	var humans: Array = []
	for member in party:
		if member.get("isHuman", false):
			humans.append(member)
	if humans.is_empty():
		return party.duplicate()
	return humans


## Membre actif : en solo, le premier humain ; sinon l'index `turnIndex` dans
## les jouables (même contrat que `get_active_member`).
static func active_member(game: Dictionary) -> Dictionary:
	var party: Array = game.get("party", [])
	if party.is_empty():
		return {}
	var playable := playable_members(game)
	var mode: String = game.get("mode", "solo")
	if mode == "solo":
		for member in playable:
			if member.get("isHuman", false):
				return member
		if not playable.is_empty():
			return playable[0]
		return party[0]
	var turn_idx: int = int(game.get("turnIndex", 0))
	if playable.is_empty():
		return party[turn_idx % party.size()]
	return playable[turn_idx % playable.size()]


## Membre du groupe par id (référence directe), `{}` si absent.
static func find_member(game: Dictionary, member_id: String) -> Dictionary:
	for m in game.get("party", []):
		if m.get("id") == member_id:
			return m
	return {}


## Id d'un membre par nom (comparaison insensible à la casse/espaces).
static func find_member_id_by_name(game: Dictionary, member_name: String) -> String:
	var needle := member_name.strip_edges().to_lower()
	for m in game.get("party", []):
		if str(m.get("name", "")).strip_edges().to_lower() == needle:
			return str(m.get("id", ""))
	return ""


## Garantit un `inventory` (Array) sur chaque membre du groupe.
static func ensure_inventories(game: Dictionary) -> void:
	if game.is_empty():
		return
	var party: Array = game.get("party", [])
	for i in range(party.size()):
		if typeof(party[i]) != TYPE_DICTIONARY:
			continue
		if not party[i].has("inventory") or typeof(party[i]["inventory"]) != TYPE_ARRAY:
			party[i]["inventory"] = []
	game["party"] = party


## Inventaire d'un membre (`[]` si le membre est absent).
static func member_inventory(game: Dictionary, member_id: String) -> Array:
	var member := find_member(game, member_id)
	if member.is_empty():
		return []
	var inv = member.get("inventory", [])
	return inv if typeof(inv) == TYPE_ARRAY else []


## Résumé lisible du groupe : noms joints, puis « + N autres » au-delà de 3.
static func party_summary(game: Dictionary) -> String:
	var party: Array = game.get("party", [])
	if party.is_empty():
		return "Groupe vide"
	var names: Array = []
	for m in party:
		names.append(m.get("name", "?"))
	if names.size() <= 3:
		return ", ".join(names)
	return "%s + %d autres" % [names[0], names.size() - 1]


# --- Filtres de personnages ------------------------------------------------

## Personnages du roster demandé (`""` = tous).
static func filter_characters_by_roster(characters: Array, roster: String) -> Array:
	if roster.is_empty():
		return characters
	var result: Array = []
	for c in characters:
		var r = c.get("roster", "general")
		if r == roster:
			result.append(c)
	return result


## Un personnage est valide pour un format si son roster « enquête » correspond.
static func is_character_valid_for_format(char: Dictionary, quest_format: String) -> bool:
	if char.is_empty():
		return false
	var is_inv := quest_format == QUEST_FORMAT_INVESTIGATION
	return (char.get("roster", "general") == QUEST_FORMAT_INVESTIGATION) == is_inv


## Personnages jouables pour un format de quête.
static func characters_for_quest_format(characters: Array, quest_format: String) -> Array:
	var result: Array = []
	for c in characters:
		if is_character_valid_for_format(c, quest_format):
			result.append(c)
	return result
