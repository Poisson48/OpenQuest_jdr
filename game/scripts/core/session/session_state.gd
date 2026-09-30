extends RefCounted
class_name SessionState

## État de partie courant — façade sur le dictionnaire `active_game`.
##
## Centralise les opérations sur la partie en cours : journal, tours,
## scènes et navigation. Logique pure, sans dépendance Node.

const TurnManager = preload("res://scripts/core/session/turn_manager.gd")

## Retourne les membres jouables du groupe.
static func get_playable_members(game: Dictionary) -> Array:
	return TurnManager.get_playable_members(game)

## Retourne le membre actuellement actif.
static func get_active_member(game: Dictionary) -> Dictionary:
	return TurnManager.get_active_member(game)

## Ajoute une entrée au journal de la partie.
static func add_log_entry(game: Dictionary, author: String, text: String, type: String = "player") -> void:
	TurnManager.add_log_entry(game, author, text, type)

## Applique une action joueur (journal + attente MJ).
static func apply_player_action(game: Dictionary, author: String, action: String) -> void:
	TurnManager.apply_player_action(game, author, action)

## Passe au membre suivant.
static func next_turn(game: Dictionary) -> void:
	TurnManager.next_turn(game)

## Retourne `true` si la partie attend une décision du MJ.
static func is_waiting_for_gm(game: Dictionary) -> bool:
	return TurnManager.is_waiting_for_gm(game)

# ---------------------------------------------------------------------------
# Scènes et navigation
# ---------------------------------------------------------------------------

## Retourne la scène courante du scénario, ou un Dictionary vide.
static func get_current_scene(game: Dictionary) -> Dictionary:
	var scenario: Dictionary = game.get("scenario", {})
	var scenes: Array = scenario.get("scenes", [])
	var current_id: String = game.get("current_scene_id", "")
	for s in scenes:
		if s.get("id", "") == current_id:
			return s
	return {}

## Passe à la scène suivante selon le graphe de transitions.
## Retourne `true` si une transition a eu lieu.
static func advance_scene(game: Dictionary) -> bool:
	var current := get_current_scene(game)
	if current.is_empty():
		return false
	var transitions: Array = current.get("transitions", [])
	if transitions.is_empty():
		return false
	var next_id: String = transitions[0].get("to", "")
	return go_to_scene(game, next_id)

## Va à une scène spécifique par son ID. Met à jour `current_scene_id`.
static func go_to_scene(game: Dictionary, scene_id: String, _reason: String = "") -> bool:
	var scenario: Dictionary = game.get("scenario", {})
	var scenes: Array = scenario.get("scenes", [])
	for s in scenes:
		if s.get("id", "") == scene_id:
			game["current_scene_id"] = scene_id
			return true
	return false

## Retourne le titre de la scène courante pour l'affichage.
static func get_scene_title(game: Dictionary) -> String:
	var s := get_current_scene(game)
	return s.get("title", "Scène inconnue")

## Retourne les notes de scène pour `scene_id` (ou la scène courante).
static func get_scene_notes(game: Dictionary, scene_id: String = "") -> String:
	if scene_id == "":
		scene_id = game.get("current_scene_id", "")
	var notes: Dictionary = game.get("scene_notes", {})
	return notes.get(scene_id, "")

## Définit les notes de scène.
static func set_scene_notes(game: Dictionary, text: String, scene_id: String = "") -> void:
	if scene_id == "":
		scene_id = game.get("current_scene_id", "")
	if not game.has("scene_notes") or not game["scene_notes"] is Dictionary:
		game["scene_notes"] = {}
	game["scene_notes"][scene_id] = text

## Retourne un résumé de navigation (scène courante, transitions disponibles).
static func get_scene_navigation_summary(game: Dictionary) -> Dictionary:
	var current := get_current_scene(game)
	return {
		"current_scene_id": game.get("current_scene_id", ""),
		"current_title": current.get("title", ""),
		"transitions": current.get("transitions", []),
	}
