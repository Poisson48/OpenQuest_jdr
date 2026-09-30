extends RefCounted
class_name Stats

## Règles de statistiques — logique pure, alignée avec `server/src/game_types.ts`.

## Retourne le modificateur D&D 5e correspondant à une valeur de caractéristique.
static func modifier(stat_value: int) -> int:
	return (stat_value - 10) / 2

## Formate un modificateur en chaîne signée : "+3", "-1", "+0".
static func format_modifier(mod: int) -> String:
	if mod >= 0:
		return "+%d" % mod
	return str(mod)

## Résumé textuel compact d'un personnage (pour les cartes de roster).
static func summary(entity: Dictionary) -> String:
	var parts: Array[String] = []
	var name: String = entity.get("name", "?")
	var race: String = entity.get("race", "")
	var klass: String = entity.get("class", "")
	if race != "" or klass != "":
		parts.append("%s (%s %s)" % [name, race, klass].filter(func(s): return str(s).strip_edges() != "").join(" ").strip_edges())
	else:
		parts.append(name)
	var stats: Dictionary = entity.get("stats", {})
	if not stats.is_empty():
		var stat_parts: Array[String] = []
		for key in ["str", "dex", "con", "int", "wis", "cha"]:
			if stats.has(key):
				stat_parts.append("%s %d" % [key.to_upper(), stats[key]])
		parts.append(" | ".join(stat_parts))
	return " — ".join(parts)
