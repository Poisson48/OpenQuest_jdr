extends RefCounted
class_name BotRepository

## Repository de persistance des bots (`user://bots.json`).
##
## CRUD bots + liste des IDs supprimés dans `user://bots_removed.json`.

const JsonStore = preload("res://scripts/core/persistence/json_store.gd")

const BOTS_PATH := "user://bots.json"
const REMOVED_PATH := "user://bots_removed.json"

## Émis après toute modification de la liste des bots.
signal changed

var _bots: Array = []
var _removed_ids: Array = []

## Charge les bots et la liste des suppressions depuis le disque.
func load_all() -> void:
	_bots = JsonStore.load_file(BOTS_PATH)
	if _bots == null or not (_bots is Array):
		_bots = []
	_removed_ids = JsonStore.load_file(REMOVED_PATH)
	if _removed_ids == null or not (_removed_ids is Array):
		_removed_ids = []

## Sauvegarde les bots sur le disque.
func save_all() -> void:
	JsonStore.save_file(BOTS_PATH, _bots)
	changed.emit()

## Sauvegarde la liste des IDs supprimés.
func save_removed() -> void:
	JsonStore.save_file(REMOVED_PATH, _removed_ids)

## Retourne tous les bots.
func get_all() -> Array:
	return _bots

## Retourne un bot par son ID, ou un Dictionary vide.
func get_by_id(id: String) -> Dictionary:
	for b in _bots:
		if b.get("id", "") == id:
			return b
	return {}

## Insère ou met à jour un bot.
func save_bot(bot_dict: Dictionary) -> void:
	var idx := _bots.find_custom(func(b): return b.get("id", "") == bot_dict.get("id", ""))
	if idx >= 0:
		_bots[idx] = bot_dict
	else:
		_bots.append(bot_dict)
	save_all()

## Supprime un bot et archive son ID. Retourne `true` si supprimé.
func delete_bot(id: String) -> bool:
	var idx := _bots.find_custom(func(b): return b.get("id", "") == id)
	if idx < 0:
		return false
	_bots.remove_at(idx)
	if id not in _removed_ids:
		_removed_ids.append(id)
	save_removed()
	save_all()
	return true

## Retourne les bots modifiables (pas de doublon embarqué), filtrés par roster.
func get_editable(roster: String = "") -> Array:
	return _bots.filter(func(b):
		if b.get("isCustom", false) == false:
			return false
		if roster != "" and b.get("roster", "general") != roster:
			return false
		return true
	)

## Retourne `true` si le bot est modifiable.
func is_editable(id: String) -> bool:
	var b := get_by_id(id)
	return b.get("isCustom", false) == true

## Retourne `true` si le bot est un bot d'enquête.
static func is_investigation_bot(bot: Dictionary) -> bool:
	return bot.get("roster", "general") == "investigation"

## Retourne les bots valides pour un format de quête.
static func is_valid_for_format(bot: Dictionary, quest_format: String) -> bool:
	match quest_format:
		"investigation":
			return is_investigation_bot(bot)
		"oneshot", "long":
			return not is_investigation_bot(bot)
		_:
			return true

## Retourne les bots valides pour un format de quête donné.
func get_for_quest_format(quest_format: String) -> Array:
	return _bots.filter(func(b): return is_valid_for_format(b, quest_format))

## Retourne la liste des IDs supprimés.
func get_removed_ids() -> Array:
	return _removed_ids
