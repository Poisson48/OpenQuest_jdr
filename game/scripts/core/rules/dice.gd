extends RefCounted
class_name Dice

## Façade historique du moteur de dés (conservée pour les appelants existants).
##
## La logique vit dans `res://scripts/core/rules/dice_engine.gd` : grammaire
## enrichie (modificateurs keepl/keeph/adv/disadv/expl/reroll1/min/max, tests de
## dés à poids, tags) et RNG injectable. Formules de base toujours supportées :
## "1d20", "2d6+3", "1d8-1", "d%".

const DiceEngineScript := preload("res://scripts/core/rules/dice_engine.gd")

## Lance les dés décrits par `formula`.
## `opts` optionnel : {"rng": Callable, "seed": int, "rolls": Array} (tests).
static func roll(formula: String, opts: Dictionary = {}) -> Dictionary:
	return DiceEngineScript.roll(formula, opts)

## Formate un résultat en texte lisible (BBCode Godot).
static func format(result: Dictionary) -> String:
	return DiceEngineScript.format(result)
