extends RefCounted
class_name Dice

## Moteur de dés — logique de jeu pure, alignée avec `server/src/dice.ts`.
##
## Formules supportées : "1d20", "2d6+3", "1d8-1", "d%", etc.

## Lance les dés décrits par `formula` et retourne un Dictionary :
## { total: int, rolls: Array[int], formula: String, modifier: int }
static func roll(formula: String) -> Dictionary:
	var pattern := RegEx.new()
	pattern.compile("^(\\d*)d(\\d+|[%%])([+-]\\d+)?$")
	var m := pattern.search(formula.strip_edges())
	if m == null:
		return { "total": 0, "rolls": [], "formula": formula, "modifier": 0, "error": "formule invalide" }

	var count_str := m.get_string(1)
	var count := int(count_str) if count_str != "" else 1
	var sides_str := m.get_string(2)
	var sides := 100 if sides_str == "%" else int(sides_str)
	var modifier := int(m.get_string(3)) if m.get_string(3) != "" else 0

	var rolls: Array[int] = []
	var total := modifier
	for i in count:
		var r := randi_range(1, sides)
		rolls.append(r)
		total += r

	return {
		"total": total,
		"rolls": rolls,
		"formula": formula,
		"modifier": modifier,
	}

## Formate le résultat d'un lancer en texte lisible.
static func format(result: Dictionary) -> String:
	if result.has("error"):
		return "Erreur : %s" % result["error"]
	var rolls: Array = result.get("rolls", [])
	var mod: int = result.get("modifier", 0)
	var parts: Array[String] = []
	for r in rolls:
		parts.append(str(r))
	var expr := " + ".join(parts)
	if mod != 0:
		expr += " %+d" % mod
	return "%s = %d" % [expr, result["total"]]
