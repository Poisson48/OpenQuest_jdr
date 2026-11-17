extends RefCounted

## Persistance de partie (lot 2 du refactor, phase 2.5) — logique **pure**.
##
## Extrait de `game/scripts/autoload/game_data.gd` : lecture/écriture JSON,
## normalisation et manipulation de la liste `saved_games`, décision de
## sauvegarde, métadonnées de scénario, migration de l'ancien fichier
## `active_game.json`.
##
## Aucune dépendance `Node` ni autoload : le module reçoit les chemins
## (`user://…`) et les dictionnaires en paramètres, et ne mute que ce qu'on lui
## passe. `GameData` conserve les façades publiques (`save_active_game`,
## `load_game_by_id`, `delete_game`, `get_playing_games`, …) et reste le seul à
## émettre `active_game_updated`.

## Décisions de `save_active_game` (voir `save_decision`).
const SAVE_EMIT := "emit"
const SAVE_DELETE := "delete"
const SAVE_UPSERT := "upsert"


# --- Fichiers JSON ----------------------------------------------------------

## Lit un fichier JSON ; `null` si absent, vide ou invalide (même contrat que
## l'ancien `GameData._load_json_file`).
static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var content := file.get_as_text()
	if content.strip_edges().is_empty():
		# Fichier vide (ex. écriture interrompue au 1er boot) — pas une erreur.
		return null
	var json := JSON.new()
	var error := json.parse(content)
	if error != OK:
		push_warning("Erreur lecture JSON (%s) : %s" % [path, json.get_error_message()])
		return null
	return json.data


## Écrit un fichier JSON (indenté tabulation, comme avant).
static func save_json(path: String, data: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Impossible d'écrire le fichier : %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


static func remove_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# --- Liste des parties sauvegardées ----------------------------------------

## Ne garde que les entrées jouables (même filtre que `load_active_game`).
static func normalize_saved_games_list(games: Array) -> Array:
	var result: Array = []
	for g in games:
		if g is Dictionary and g.get("status", "") == "playing":
			result.append(g)
	return result


## Retrouve une entrée par id (référence directe, pas une copie). Comparaison
## volontairement non convertie : même contrat que l'ancien `load_game_by_id`.
static func find_game(saved_games: Array, game_id: String) -> Dictionary:
	for g in saved_games:
		if g is Dictionary and g.get("id") == game_id:
			return g
	return {}


## Insère ou remplace l'entrée d'id `game["id"]`. `false` si l'id est vide.
static func upsert_game(saved_games: Array, game: Dictionary) -> bool:
	var game_id := str(game.get("id", ""))
	if game_id.is_empty():
		return false
	for i in range(saved_games.size()):
		if saved_games[i].get("id") == game.get("id"):
			saved_games[i] = game
			return true
	saved_games.append(game)
	return true


## Supprime toutes les entrées de l'id donné. `true` si au moins une a été retirée.
static func remove_game(saved_games: Array, game_id: String) -> bool:
	if game_id.is_empty():
		return false
	var removed := false
	for i in range(saved_games.size() - 1, -1, -1):
		if saved_games[i].get("id") == game_id:
			saved_games.remove_at(i)
			removed = true
	return removed


## Parties au statut `playing` (contrat de `get_playing_games`).
static func playing_games(saved_games: Array) -> Array:
	var result: Array = []
	for g in saved_games:
		if g.get("status", "") == "playing":
			result.append(g)
	return result


# --- Décisions de sauvegarde ------------------------------------------------

## Décision de `save_active_game` selon l'état de la partie :
## vide ou statut inconnu -> `SAVE_EMIT` (émettre seulement), `ended` ->
## `SAVE_DELETE`, `playing`/`completed` -> `SAVE_UPSERT`.
static func save_decision(game: Dictionary) -> String:
	if game.is_empty():
		return SAVE_EMIT
	var status := str(game.get("status", "playing"))
	if status == "ended":
		return SAVE_DELETE
	if status == "playing" or status == "completed":
		return SAVE_UPSERT
	return SAVE_EMIT


## Horodate la partie active avant duplication (même champ `updatedAt` qu'avant).
static func touch(game: Dictionary) -> void:
	game["updatedAt"] = Time.get_unix_time_from_system()


## Recopie le titre du scénario dans la partie (le scénario est résolu par
## l'appelant, `GameData`). Même contrat que `sync_game_scenario_metadata`.
static func apply_scenario_metadata(game: Dictionary, scenario: Dictionary) -> Dictionary:
	if game.is_empty() or scenario.is_empty():
		return game
	game["scenarioTitle"] = scenario.get("title", "Aventure")
	return game


# --- Migration de l'ancien fichier unique ----------------------------------

## Migre `active_game.json` (ancien format) vers la liste `saved_games` et
## supprime l'ancien fichier. `id_generator` n'est appelé que si l'ancien état
## n'a pas d'id (Callable sans argument retournant un id, ex. `generate_id`).
static func migrate_legacy_active_game(
	legacy_path: String,
	saved_games: Array,
	saved_games_path: String,
	id_generator: Callable
) -> void:
	if not FileAccess.file_exists(legacy_path):
		return
	var legacy = load_json(legacy_path)
	if legacy is Dictionary and legacy.get("status", "") == "playing":
		if not legacy.has("id") or str(legacy["id"]).is_empty():
			legacy["id"] = id_generator.call()
		if upsert_game(saved_games, legacy):
			save_json(saved_games_path, saved_games)
	remove_file_if_exists(legacy_path)
