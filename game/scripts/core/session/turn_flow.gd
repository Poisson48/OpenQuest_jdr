extends RefCounted

## Flux de tour de la session (lot 3 du refactor, phase 2.6) — logique **pure**.
##
## Extrait de `game/scripts/autoload/game_data.gd` : passage de tour, attente du
## MJ, droits d'action et clôture de partie. Aucune dépendance `Node` ni
## autoload ; les fonctions reçoivent le dictionnaire de partie et le mutent
## comme avant. La persistance (`save_active_game`) et l'émission de
## `active_game_updated` restent dans `GameData`.
##
## Chaque fonction « mutante » retourne `true` si l'appelant doit sauvegarder :
## cela reproduit exactement les `return` anticipés de l'ancien code (pas de
## sauvegarde/signal si la partie est vide).

const Roster = preload("res://scripts/core/party/roster.gd")


static func is_completed(game: Dictionary) -> bool:
	return not game.is_empty() and str(game.get("status", "")) == "completed"


static func is_waiting_for_gm(game: Dictionary) -> bool:
	if game.is_empty():
		return false
	return bool(game.get("waitingForGm", false))


## Pose l'attente MJ ; `true` si la partie est modifiable (donc à sauvegarder).
static func set_waiting_for_gm(game: Dictionary, waiting: bool) -> bool:
	if game.is_empty():
		return false
	game["waitingForGm"] = waiting
	return true


## Tour suivant (rotation simple sur les membres jouables) ; `true` si modifié.
static func next_turn(game: Dictionary) -> bool:
	if game.is_empty():
		return false
	var playable := Roster.playable_members(game)
	if playable.size() <= 1:
		return false
	var idx: int = int(game.get("turnIndex", 0))
	game["turnIndex"] = (idx + 1) % playable.size()
	return true


## Le MJ valide et passe au joueur suivant ; `true` si la partie doit être
## sauvegardée (même contrat que `advance_player_turn` : nettoyer l'attente et
## avancer si plusieurs jouables).
static func advance_player_turn(game: Dictionary) -> bool:
	if game.is_empty():
		return false
	game["waitingForGm"] = false
	var playable := Roster.playable_members(game)
	if playable.size() > 1:
		var idx: int = int(game.get("turnIndex", 0))
		game["turnIndex"] = (idx + 1) % playable.size()
	return true


## Le joueur peut-il agir maintenant ? (même règle que `can_member_act`.)
static func can_member_act(game: Dictionary, client_id: String) -> bool:
	if game.is_empty() or str(game.get("status", "")) == "completed":
		return false
	if is_waiting_for_gm(game):
		return false
	if game.get("gmType", "ai") == "ai":
		return true
	var actor := Roster.active_member(game)
	if actor.is_empty():
		return true
	var actor_client: String = str(actor.get("clientId", ""))
	if actor_client.is_empty():
		return client_id.is_empty()
	return actor_client == client_id


## Conditions de fin de partie : statut `completed` + plus d'attente MJ.
static func mark_completed(game: Dictionary) -> bool:
	if game.is_empty():
		return false
	game["status"] = "completed"
	game["waitingForGm"] = false
	return true


static func gm_display_name(game: Dictionary) -> String:
	if game.is_empty():
		return "MJ"
	return str(game.get("gmName", "MJ"))
