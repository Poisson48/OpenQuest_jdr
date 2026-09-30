extends RefCounted
class_name SaveGameRepository

## Repository de persistance des parties sauvegardées.
##
## Deux fichiers :
##  - `user://active_game.json`  : la partie en cours (ou `{}`)
##  - `user://saved_games.json`  : liste des parties jouables/reprises

const JsonStore = preload("res://scripts/core/persistence/json_store.gd")

const ACTIVE_GAME_PATH := "user://active_game.json"
const SAVED_GAMES_PATH := "user://saved_games.json"

## Émis après toute modification de l'état de partie ou de la liste.
signal changed

var _active_game: Dictionary = {}
var _saved_games: Array = []

## Charge l'état de partie et la liste des sauvegardes depuis le disque.
func load_all() -> void:
	var active: Variant = JsonStore.load_file(ACTIVE_GAME_PATH)
	_active_game = active if active is Dictionary else {}
	var saved: Variant = JsonStore.load_file(SAVED_GAMES_PATH)
	_saved_games = saved if saved is Array else []

## Sauvegarde la partie active sur le disque.
func save_active() -> void:
	JsonStore.save_file(ACTIVE_GAME_PATH, _active_game)
	changed.emit()

## Sauvegarde la liste des parties jouables.
func save_saved_games() -> void:
	JsonStore.save_file(SAVED_GAMES_PATH, _saved_games)
	changed.emit()

## Retourne la partie active courante (peut être vide).
func get_active_game() -> Dictionary:
	return _active_game

## Définit la partie active et la persiste.
func set_active_game(state: Dictionary) -> void:
	_active_game = state
	save_active()

## Retourne `true` si une partie active existe.
func has_active_game() -> bool:
	return not _active_game.is_empty()

## Efface la partie active.
func clear_active_game() -> void:
	_active_game = {}
	save_active()

## Retourne la liste des parties jouables normalisée.
func get_saved_games() -> Array:
	return _saved_games

## Insère ou met à jour une entrée dans la liste des parties jouables.
## L'entrée est identifiée par `game_id`.
func upsert_saved_game(game: Dictionary) -> void:
	var gid: String = game.get("game_id", game.get("id", ""))
	if gid == "":
		return
	var idx := _saved_games.find_custom(func(g): return g.get("game_id", g.get("id", "")) == gid)
	if idx >= 0:
		_saved_games[idx] = game
	else:
		_saved_games.append(game)
	save_saved_games()

## Supprime une partie jouable par son ID. Retourne `true` si supprimée.
func delete_saved_game(game_id: String) -> bool:
	var idx := _saved_games.find_custom(func(g): return g.get("game_id", g.get("id", "")) == game_id)
	if idx < 0:
		return false
	_saved_games.remove_at(idx)
	save_saved_games()
	return true

## Charge une partie sauvegardée comme partie active par son ID.
## Retourne `true` si la partie a été trouvée et activée.
func load_by_id(game_id: String) -> bool:
	for g in _saved_games:
		if g.get("game_id", g.get("id", "")) == game_id:
			_active_game = g.duplicate(true)
			save_active()
			return true
	return false

## Efface toutes les parties sauvegardées et la partie active.
func clear_all() -> void:
	_saved_games = []
	_active_game = {}
	save_saved_games()
	save_active()

## Retourne les parties jouables (statut "playing").
func get_playing_games() -> Array:
	return _saved_games.filter(func(g): return g.get("status", "playing") == "playing")
