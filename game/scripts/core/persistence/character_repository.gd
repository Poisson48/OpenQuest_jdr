extends RefCounted
class_name CharacterRepository

## Repository de persistance des personnages (`user://characters.json`).
##
## CRUD complet avec normalisation et validation par format de quête.
## Utilise `JsonStore` pour les entrées/sorties ; pur (pas de Node).

const JsonStore = preload("res://scripts/core/persistence/json_store.gd")

const CHARACTERS_PATH := "user://characters.json"

## Émis après toute modification de la liste des personnages.
signal changed

## Liste interne des personnages chargés.
var _characters: Array = []

## Charge tous les personnages depuis le disque.
func load_all() -> void:
	_characters = JsonStore.load_file(CHARACTERS_PATH)
	if _characters == null or not (_characters is Array):
		_characters = []

## Sauvegarde tous les personnages sur le disque.
func save_all() -> void:
	JsonStore.save_file(CHARACTERS_PATH, _characters)
	changed.emit()

## Retourne la liste complète des personnages.
func get_all() -> Array:
	return _characters

## Retourne les personnages filtrés par roster ("" = tous).
func get_by_roster(roster: String = "") -> Array:
	if roster == "":
		return _characters
	return _characters.filter(func(c): return c.get("roster", "general") == roster)

## Retourne un personnage par son ID, ou un Dictionary vide.
func get_by_id(id: String) -> Dictionary:
	for c in _characters:
		if c.get("id", "") == id:
			return c
	return {}

## Insère ou met à jour un personnage. Normalise avant insertion.
func save_character(char_dict: Dictionary) -> void:
	var normalized := normalize_character(char_dict)
	var idx := _characters.find_custom(func(c): return c.get("id", "") == normalized.get("id", ""))
	if idx >= 0:
		_characters[idx] = normalized
	else:
		_characters.append(normalized)
	save_all()

## Supprime un personnage par son ID. Retourne `true` si supprimé.
func delete_character(id: String) -> bool:
	var idx := _characters.find_custom(func(c): return c.get("id", "") == id)
	if idx < 0:
		return false
	_characters.remove_at(idx)
	save_all()
	return true

## Normalise un Dictionary personnage : clés manquantes, types, valeurs par défaut.
static func normalize_character(entity: Dictionary) -> Dictionary:
	var out := entity.duplicate(true)
	out["id"] = out.get("id", JsonStore.generate_id("char"))
	out["name"] = out.get("name", "Sans nom")
	out["race"] = out.get("race", "")
	out["class"] = out.get("class", "")
	out["roster"] = out.get("roster", "general")
	out["hp"] = int(out.get("hp", 10))
	out["ac"] = int(out.get("ac", 10))
	out["backstory"] = out.get("backstory", "")
	if not out.has("stats") or not out["stats"] is Dictionary:
		out["stats"] = { "str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10 }
	return out

## Retourne `true` si le personnage est valide pour le format de quête donné.
static func is_valid_for_format(entity: Dictionary, quest_format: String) -> bool:
	var roster: String = entity.get("roster", "general")
	match quest_format:
		"investigation":
			return roster == "investigation"
		"oneshot", "long":
			return roster == "general" or roster == ""
		_:
			return true

## Retourne les personnages valides pour un format de quête.
func get_for_quest_format(quest_format: String) -> Array:
	return _characters.filter(func(c): return is_valid_for_format(c, quest_format))
