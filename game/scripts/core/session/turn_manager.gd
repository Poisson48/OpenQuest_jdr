extends RefCounted
class_name TurnManager

## Gestion des tours de jeu — logique pure, sans dépendance Node.
##
## Travaille directement sur le dictionnaire `active_game` (partagé par référence).
## Responsabilités : membres jouables, membre actif, droit d'agir, avancée de tour.

## Retourne les membres jouables (humains + bots avec stats) du groupe.
static func get_playable_members(game: Dictionary) -> Array:
	var party: Array = game.get("party", [])
	return party.filter(func(m): return m.get("playable", true))

## Retourne le membre actuellement actif, ou un Dictionary vide.
static func get_active_member(game: Dictionary) -> Dictionary:
	var members := get_playable_members(game)
	var idx: int = game.get("active_member_index", 0)
	if idx < 0 or idx >= members.size():
		return {}
	return members[idx]

## Retourne `true` si le membre identifié par `client_id` peut agir.
static func can_member_act(game: Dictionary, client_id: String) -> bool:
	if game.get("waiting_for_gm", false):
		return false
	var active := get_active_member(game)
	if active.is_empty():
		return false
	return active.get("client_id", active.get("id", "")) == client_id

## Passe au membre suivant. Met à jour `active_member_index` dans `game`.
static func next_turn(game: Dictionary) -> void:
	var members := get_playable_members(game)
	if members.is_empty():
		return
	var idx: int = game.get("active_member_index", 0)
	game["active_member_index"] = (idx + 1) % members.size()

## Force l'avancée au membre suivant (alias de `next_turn` pour la lisibilité).
static func advance_player_turn(game: Dictionary) -> void:
	next_turn(game)

## Définit l'état d'attente du MJ.
static func set_waiting_for_gm(game: Dictionary, waiting: bool) -> void:
	game["waiting_for_gm"] = waiting

## Retourne `true` si la partie attend une décision du MJ.
static func is_waiting_for_gm(game: Dictionary) -> bool:
	return game.get("waiting_for_gm", false)

## Ajoute une entrée au journal de la partie.
static func add_log_entry(game: Dictionary, author: String, text: String, type: String = "player") -> void:
	if not game.has("log") or not game["log"] is Array:
		game["log"] = []
	game["log"].append({
		"author": author,
		"text": text,
		"type": type,
		"ts": Time.get_unix_time_from_system(),
	})

## Applique une action joueur au journal et marque l'attente MJ si nécessaire.
static func apply_player_action(game: Dictionary, author: String, action: String) -> void:
	add_log_entry(game, author, action, "player")
	set_waiting_for_gm(game, true)
