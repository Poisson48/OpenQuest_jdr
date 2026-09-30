extends RefCounted
class_name ScenarioRepository

## Repository de persistance des scénarios (`user://scenarios.json`).
##
## Gère le CRUD, la distinction catalogue/brouillon et la publication.
## La liste des IDs supprimés est persistée dans `user://scenarios_removed.json`.

const JsonStore = preload("res://scripts/core/persistence/json_store.gd")

const SCENARIOS_PATH := "user://scenarios.json"
const REMOVED_PATH := "user://scenarios_removed.json"

## Émis après toute modification de la liste des scénarios.
signal changed

var _scenarios: Array = []
var _removed_ids: Array = []

## Charge les scénarios et la liste des suppressions depuis le disque.
func load_all() -> void:
	_scenarios = JsonStore.load_file(SCENARIOS_PATH)
	if _scenarios == null or not (_scenarios is Array):
		_scenarios = []
	_removed_ids = JsonStore.load_file(REMOVED_PATH)
	if _removed_ids == null or not (_removed_ids is Array):
		_removed_ids = []

## Sauvegarde les scénarios sur le disque.
func save_all() -> void:
	JsonStore.save_file(SCENARIOS_PATH, _scenarios)
	changed.emit()

## Sauvegarde la liste des IDs supprimés.
func save_removed() -> void:
	JsonStore.save_file(REMOVED_PATH, _removed_ids)

## Retourne tous les scénarios.
func get_all() -> Array:
	return _scenarios

## Retourne un scénario par son ID, ou un Dictionary vide.
func get_by_id(id: String) -> Dictionary:
	for s in _scenarios:
		if s.get("id", "") == id:
			return s
	return {}

## Insère ou met à jour un scénario.
func save_scenario(scenario_dict: Dictionary) -> void:
	var idx := _scenarios.find_custom(func(s): return s.get("id", "") == scenario_dict.get("id", ""))
	if idx >= 0:
		_scenarios[idx] = scenario_dict
	else:
		_scenarios.append(scenario_dict)
	save_all()

## Supprime un scénario et archive son ID. Retourne `true` si supprimé.
func delete_scenario(id: String) -> bool:
	var idx := _scenarios.find_custom(func(s): return s.get("id", "") == id)
	if idx < 0:
		return false
	_scenarios.remove_at(idx)
	if id not in _removed_ids:
		_removed_ids.append(id)
	save_removed()
	save_all()
	return true

## Retourne `true` si le scénario appartient au catalogue (pas un brouillon).
static func is_catalog(scenario: Dictionary) -> bool:
	return scenario.get("status", "catalog") == "catalog"

## Retourne `true` si le scénario est un brouillon.
static func is_draft(scenario: Dictionary) -> bool:
	return scenario.get("status", "") == "draft"

## Retourne les brouillons, filtrés par format de quête si non vide.
func get_drafts(quest_format: String = "") -> Array:
	return _scenarios.filter(func(s):
		if not is_draft(s):
			return false
		if quest_format != "" and s.get("quest_format", "") != quest_format:
			return false
		return true
	)

## Passe un scénario du statut brouillon à catalogue.
func publish(id: String) -> bool:
	var s := get_by_id(id)
	if s.is_empty():
		return false
	s["status"] = "catalog"
	save_all()
	return true

## Passe un scénario du statut catalogue à brouillon.
func unpublish(id: String) -> bool:
	var s := get_by_id(id)
	if s.is_empty():
		return false
	s["status"] = "draft"
	save_all()
	return true

## Retourne la liste des IDs supprimés.
func get_removed_ids() -> Array:
	return _removed_ids

## Retourne les scénarios valides pour un format de quête.
static func is_valid_for_format(scenario: Dictionary, quest_format: String) -> bool:
	if quest_format == "":
		return true
	return scenario.get("quest_format", "oneshot") == quest_format

## Retourne les scénarios valides pour un format de quête donné.
func get_for_quest_format(quest_format: String) -> Array:
	return _scenarios.filter(func(s): return is_valid_for_format(s, quest_format))
