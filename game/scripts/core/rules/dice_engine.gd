extends RefCounted
class_name DiceEngine

## Moteur de dés OpenQuest — logique pure, testable en headless, sans dépendance
## au rendu ni au réseau.
##
## Grammaire v1 (spec du projet, réimplémentée pour notre jeu) :
##
##   expression  = comparison ;
##   comparison  = sum { ( ">=" | "<=" | ">" | "<" | "=" | "!=" ) sum [ weights ] } ;
##   weights     = "{" integer ":" integer { "," integer ":" integer } "}" ;
##   sum         = term { ( "+" | "-" ) term } ;
##   term        = unary { ( "*" | "/" ) unary } ;
##   unary       = { "-" } primary ;
##   primary     = dice | integer | "(" expression ")" ;
##   dice        = [ integer ] "d" ( integer | "%" ) { modifier } [ "[" tags "]" ] ;
##   modifier    = "keeph" n | "keepl" n | "adv" | "disadv" | "expl"
##               | "reroll" | "min" n | "max" n ;
##   tags        = ident { "," ident } ;
##
## Résultat : arbre `{kind: number|dice|comparison, total, ...}` + champs de
## compatibilité (`rolls`, `modifier`) pour les appelants historiques.
##
## RNG injectable : `opts.rng` (Callable(min,max)->int), `opts.seed` (int) ou
## `opts.rolls` (Array de valeurs imposées, pour les tests déterministes).

const MAX_DICE_TOTAL := 500
const MAX_DICE_COUNT := 100
const MAX_SIDES := 1000
const MAX_FORMULA_LENGTH := 255
const MAX_EXPLOSIONS_PER_DIE := 20
const MAX_PARSE_DEPTH := 32
const MAX_WEIGHT_ENTRIES := 64

const MODIFIER_NAMES := ["keeph", "keepl", "adv", "disadv", "expl", "reroll", "min", "max"]
const COMPARISON_OPS := [">=", "<=", ">", "<", "=", "==", "!="]

# ===========================================================================
# API publique
# ===========================================================================

## Lance `formula` et retourne un résultat (ou une erreur : `{"ok": false, "error": ...}`).
static func roll(formula: String, opts: Dictionary = {}) -> Dictionary:
	var src := formula.strip_edges()
	if src.is_empty():
		return _error(formula, "Formule vide.")
	if src.length() > MAX_FORMULA_LENGTH:
		return _error(formula, "Formule trop longue (max %d)." % MAX_FORMULA_LENGTH)

	var toks := _lex(src.to_lower())
	if toks.is_empty():
		return _error(formula, "Formule invalide.")

	var parser := {"toks": toks, "i": 0, "error": "", "depth": 0}
	var ast := _parse_expression(parser)
	if str(parser["error"]) != "":
		return _error(formula, str(parser["error"]))
	var index := int(parser["i"])
	if index < toks.size():
		var leftover: Dictionary = toks[index]
		return _error(formula, "Symbole inattendu : '%s'." % str(leftover.get("v", "?")))

	var ctx := {"rng": _make_rng(opts), "rolled": [0], "error": ""}
	var node := _eval(ast, ctx)
	if str(ctx["error"]) != "":
		return _error(formula, str(ctx["error"]))

	var res: Dictionary = node.duplicate(true)
	res["ok"] = true
	res["formula"] = src
	if not res.has("tags"):
		res["tags"] = []
	var rolls := _collect_rolls(node)
	res["rolls"] = rolls
	var rolls_sum := 0
	for v in rolls:
		rolls_sum += int(v)
	res["modifier"] = 0 if str(node.get("kind", "")) == "comparison" else int(node.get("total", 0)) - rolls_sum
	return res

## Formate un résultat en texte lisible (BBCode Godot accepté par la session).
static func format(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "Erreur : %s" % str(result.get("error", "formule invalide"))
	var kind := str(result.get("kind", ""))
	var total := int(result.get("total", 0))
	var formula := str(result.get("formula", ""))
	var text := ""
	if kind == "comparison":
		var left_kind := str((result.get("left", {}) as Dictionary).get("kind", ""))
		if left_kind == "dice":
			text = "🎲 [b]%d succès[/b]" % total
			if int(result.get("failure", 0)) > 0:
				text += " / %d échec(s)" % int(result.get("failure", 0))
			text += " (%s)" % formula
		else:
			var target := int((result.get("right", {}) as Dictionary).get("total", 0))
			var verdict := "réussite" if int(result.get("success", 0)) >= 1 else "échec"
			text = "🎲 [b]%d[/b] vs %d — %s (%s)" % [total, target, verdict, formula]
	else:
		text = "🎲 [b]%d[/b] (%s)" % [total, formula]
	text += _format_dice_detail(result)
	var tags: Array = result.get("tags", [])
	if not tags.is_empty():
		var tag_parts: Array[String] = []
		for t in tags:
			tag_parts.append(str(t))
		text += " [%s]" % ", ".join(tag_parts)
	return text

# ===========================================================================
# Lexer
# ===========================================================================

static func _lex(src: String) -> Array:
	var toks: Array = []
	var i := 0
	var n := src.length()
	while i < n:
		var ch := src[i]
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			i += 1
			continue
		if _is_digit(ch):
			var start_int := i
			while i < n and _is_digit(src[i]):
				i += 1
			toks.append({"t": "int", "v": int(src.substr(start_int, i - start_int))})
			continue
		if _is_alpha(ch):
			var start_word := i
			while i < n and _is_alpha(src[i]):
				i += 1
			toks.append({"t": "word", "v": src.substr(start_word, i - start_word)})
			continue
		var two := src.substr(i, 2)
		if two == ">=" or two == "<=" or two == "!=" or two == "==":
			toks.append({"t": "op", "v": two})
			i += 2
			continue
		if ch in ["+", "-", "*", "/", ">", "<", "=", "(", ")", "[", "]", "{", "}", ",", ":", "%"]:
			toks.append({"t": "op", "v": ch})
			i += 1
			continue
		return []
	return toks

static func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"

static func _is_alpha(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"

# ===========================================================================
# Parser (descente récursive)
# ===========================================================================

static func _peek(p: Dictionary) -> Dictionary:
	var toks: Array = p["toks"]
	var i := int(p["i"])
	if i >= toks.size():
		return {"t": "eof", "v": ""}
	return toks[i]

static func _advance(p: Dictionary) -> Dictionary:
	var tok := _peek(p)
	p["i"] = int(p["i"]) + 1
	return tok

static func _is_op(p: Dictionary, v: String) -> bool:
	var tok := _peek(p)
	return str(tok.get("t", "")) == "op" and str(tok.get("v", "")) == v

static func _parse_expression(p: Dictionary) -> Dictionary:
	if int(p["depth"]) > MAX_PARSE_DEPTH:
		p["error"] = "Expression trop profonde."
		return {}
	p["depth"] = int(p["depth"]) + 1

	var left := _parse_sum(p)
	if str(p["error"]) != "":
		return {}
	var tok := _peek(p)
	if str(tok.get("t", "")) == "op" and str(tok.get("v", "")) in COMPARISON_OPS:
		var op := str(_advance(p)["v"])
		var right := _parse_sum(p)
		if str(p["error"]) != "":
			return {}
		var weights: Dictionary = {}
		if _is_op(p, "{"):
			_advance(p)
			var entries := 0
			while not _is_op(p, "}"):
				var key_tok := _advance(p)
				if str(key_tok.get("t", "")) != "int":
					p["error"] = "Poids invalide : {face:poids} attendu."
					return {}
				if not _is_op(p, ":"):
					p["error"] = "Poids invalide : ':' attendu."
					return {}
				_advance(p)
				var val_tok := _advance(p)
				if str(val_tok.get("t", "")) != "int":
					p["error"] = "Poids invalide : poids entier attendu."
					return {}
				weights[int(key_tok["v"])] = int(val_tok["v"])
				entries += 1
				if entries > MAX_WEIGHT_ENTRIES:
					p["error"] = "Trop d'entrées de poids (max %d)." % MAX_WEIGHT_ENTRIES
					return {}
				if _is_op(p, ","):
					_advance(p)
					continue
				break
			if not _is_op(p, "}"):
				p["error"] = "Poids non fermés : '}' attendu."
				return {}
			_advance(p)
		var cmp := {"t": "cmp", "op": op, "l": left, "r": right, "weights": weights}
		p["depth"] = int(p["depth"]) - 1
		return cmp

	p["depth"] = int(p["depth"]) - 1
	return left

static func _parse_sum(p: Dictionary) -> Dictionary:
	var left := _parse_term(p)
	while str(p["error"]) == "" and _peek(p).get("t", "") == "op" and str(_peek(p)["v"]) in ["+", "-"]:
		var op := str(_advance(p)["v"])
		var right := _parse_term(p)
		if str(p["error"]) != "":
			return {}
		left = {"t": "bin", "op": op, "l": left, "r": right}
	return left

static func _parse_term(p: Dictionary) -> Dictionary:
	var left := _parse_unary(p)
	while str(p["error"]) == "" and _peek(p).get("t", "") == "op" and str(_peek(p)["v"]) in ["*", "/"]:
		var op := str(_advance(p)["v"])
		var right := _parse_unary(p)
		if str(p["error"]) != "":
			return {}
		left = {"t": "bin", "op": op, "l": left, "r": right}
	return left

static func _parse_unary(p: Dictionary) -> Dictionary:
	if _is_op(p, "-"):
		_advance(p)
		var inner := _parse_unary(p)
		if str(p["error"]) != "":
			return {}
		return {"t": "neg", "v": inner}
	return _parse_primary(p)

static func _parse_primary(p: Dictionary) -> Dictionary:
	var tok := _peek(p)
	if str(tok.get("t", "")) == "int":
		var count := int(_advance(p)["v"])
		if _peek(p).get("t", "") == "word" and str(_peek(p)["v"]) == "d":
			return _parse_dice(p, count)
		return {"t": "num", "v": count}
	if str(tok.get("t", "")) == "word" and str(tok["v"]) == "d":
		return _parse_dice(p, 1)
	if _is_op(p, "("):
		_advance(p)
		var inner := _parse_expression(p)
		if str(p["error"]) != "":
			return {}
		if not _is_op(p, ")"):
			p["error"] = "Parenthèse non fermée."
			return {}
		_advance(p)
		return inner
	p["error"] = "Symbole inattendu : '%s'." % str(tok.get("v", "?"))
	return {}

static func _parse_dice(p: Dictionary, count: int) -> Dictionary:
	_advance(p) # 'd'
	var sides := 0
	var tok := _peek(p)
	if str(tok.get("t", "")) == "int":
		sides = int(_advance(p)["v"])
	elif _is_op(p, "%"):
		_advance(p)
		sides = 100
	else:
		p["error"] = "Dé sans nombre de faces (ex. 1d6)."
		return {}

	var mods: Array = []
	while _peek(p).get("t", "") == "word" and str(_peek(p)["v"]) in MODIFIER_NAMES:
		var mod_name := str(_advance(p)["v"])
		var mod_value := 0
		if _peek(p).get("t", "") == "int":
			mod_value = int(_advance(p)["v"])
		if mod_name in ["keeph", "keepl", "min", "max"] and mod_value <= 0:
			p["error"] = "Modificateur '%s' : valeur positive attendue." % mod_name
			return {}
		mods.append({"name": mod_name, "value": mod_value})

	var tags: Array = []
	if _is_op(p, "["):
		_advance(p)
		while true:
			var tag_tok := _advance(p)
			if str(tag_tok.get("t", "")) != "word":
				p["error"] = "Tag invalide (identifiant attendu)."
				return {}
			tags.append(str(tag_tok["v"]))
			if _is_op(p, ","):
				_advance(p)
				continue
			break
		if not _is_op(p, "]"):
			p["error"] = "Tag non fermé : ']' attendu."
			return {}
		_advance(p)

	if count < 1 or count > MAX_DICE_COUNT:
		p["error"] = "Nombre de dés hors limites (1-%d)." % MAX_DICE_COUNT
		return {}
	if sides < 2 or sides > MAX_SIDES:
		p["error"] = "Nombre de faces hors limites (2-%d)." % MAX_SIDES
		return {}
	return {"t": "dice", "count": count, "sides": sides, "mods": mods, "tags": tags}

# ===========================================================================
# Évaluation
# ===========================================================================

static func _eval(node: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind := str(node.get("t", ""))
	if kind == "num":
		return {"kind": "number", "total": int(node["v"])}
	if kind == "neg":
		var inner := _eval(node["v"], ctx)
		if str(ctx["error"]) != "":
			return {}
		return {"kind": "number", "total": -int(inner["total"]), "children": [inner]}
	if kind == "bin":
		var left := _eval(node["l"], ctx)
		if str(ctx["error"]) != "":
			return {}
		var right := _eval(node["r"], ctx)
		if str(ctx["error"]) != "":
			return {}
		var op := str(node["op"])
		var total := 0
		if op == "+":
			total = int(left["total"]) + int(right["total"])
		elif op == "-":
			total = int(left["total"]) - int(right["total"])
		elif op == "*":
			total = int(left["total"]) * int(right["total"])
		else:
			if int(right["total"]) == 0:
				_fail(ctx, "Division par zéro.")
				return {}
			total = int(left["total"]) / int(right["total"])
		return {"kind": "number", "total": total, "children": [left, right], "op": op}
	if kind == "dice":
		return _eval_dice(node, ctx)
	if kind == "cmp":
		var left := _eval(node["l"], ctx)
		if str(ctx["error"]) != "":
			return {}
		var right := _eval(node["r"], ctx)
		if str(ctx["error"]) != "":
			return {}
		return _eval_comparison(str(node["op"]), left, right, node.get("weights", {}))
	_fail(ctx, "Nœud interne inconnu.")
	return {}

static func _eval_dice(node: Dictionary, ctx: Dictionary) -> Dictionary:
	var count := int(node["count"])
	var sides := int(node["sides"])
	var mods: Array = node.get("mods", [])

	var has_adv := _has_mod(mods, "adv")
	var has_disadv := _has_mod(mods, "disadv")
	var roll_count := count * (2 if (has_adv or has_disadv) else 1)

	var values: Array[int] = []
	for _i in roll_count:
		var v := _roll(sides, ctx)
		if str(ctx["error"]) != "":
			return {}
		values.append(v)

	if _has_mod(mods, "expl"):
		var queue: Array = []
		for i in values.size():
			queue.append(i)
		var q := 0
		while q < queue.size():
			var die_index := int(queue[q])
			q += 1
			var guard := 0
			while values[die_index] == sides and guard < MAX_EXPLOSIONS_PER_DIE:
				var bonus := _roll(sides, ctx)
				if str(ctx["error"]) != "":
					return {}
				values.append(bonus)
				queue.append(values.size() - 1)
				die_index = values.size() - 1
				guard += 1

	if _has_mod(mods, "reroll"):
		for i in values.size():
			if values[i] == 1:
				var rerolled := _roll(sides, ctx)
				if str(ctx["error"]) != "":
					return {}
				values[i] = rerolled

	for m in mods:
		var mod_name := str(m.get("name", ""))
		var mod_value := int(m.get("value", 0))
		if mod_name == "min":
			for i in values.size():
				values[i] = maxi(values[i], mod_value)
		elif mod_name == "max":
			for i in values.size():
				values[i] = mini(values[i], mod_value)

	var keep_count := -1
	var keep_high := true
	for m in mods:
		var mod_name := str(m.get("name", ""))
		if mod_name == "keeph":
			keep_count = int(m.get("value", 0))
			keep_high = true
		elif mod_name == "keepl":
			keep_count = int(m.get("value", 0))
			keep_high = false
	if has_adv and not has_disadv:
		keep_count = count
		keep_high = true
	elif has_disadv and not has_adv:
		keep_count = count
		keep_high = false

	var kept: Array[int] = []
	var dropped: Array[int] = []
	if keep_count >= 0 and keep_count < values.size():
		var order: Array = range(values.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			if values[a] == values[b]:
				return a < b
			if keep_high:
				return values[a] > values[b]
			return values[a] < values[b])
		var keep_set: Dictionary = {}
		for k in keep_count:
			keep_set[int(order[k])] = true
		for i in values.size():
			if keep_set.has(i):
				kept.append(values[i])
			else:
				dropped.append(values[i])
	else:
		kept = values.duplicate()

	var total := 0
	for v in kept:
		total += v
	return {
		"kind": "dice",
		"sides": sides,
		"count": count,
		"values": values.duplicate(),
		"kept": kept,
		"dropped": dropped,
		"tags": (node.get("tags", []) as Array).duplicate(),
		"total": total,
	}

static func _eval_comparison(op: String, left: Dictionary, right: Dictionary, weights: Dictionary) -> Dictionary:
	var target := int(right.get("total", 0))
	if str(left.get("kind", "")) == "dice":
		var success := 0
		var failure := 0
		var pool: Array = left.get("kept", [])
		for v in pool:
			var face := int(v)
			if _compare(face, op, target):
				success += int(weights.get(face, 1))
			else:
				failure += 1
		return {
			"kind": "comparison",
			"op": op,
			"left": left,
			"right": right,
			"success": success,
			"failure": failure,
			"total": success,
		}
	var cond := _compare(int(left.get("total", 0)), op, target)
	return {
		"kind": "comparison",
		"op": op,
		"left": left,
		"right": right,
		"success": 1 if cond else 0,
		"failure": 0 if cond else 1,
		"total": int(left.get("total", 0)),
	}

static func _compare(a: int, op: String, b: int) -> bool:
	if op == ">=":
		return a >= b
	if op == "<=":
		return a <= b
	if op == ">":
		return a > b
	if op == "<":
		return a < b
	if op == "=" or op == "==":
		return a == b
	if op == "!=":
		return a != b
	return false

static func _roll(sides: int, ctx: Dictionary) -> int:
	var rolled: Array = ctx["rolled"]
	if int(rolled[0]) >= MAX_DICE_TOTAL:
		_fail(ctx, "Trop de dés lancés (max %d)." % MAX_DICE_TOTAL)
		return 0
	var rng_callable: Callable = ctx["rng"]
	var value := int(rng_callable.call(1, sides))
	rolled[0] = int(rolled[0]) + 1
	if value < 1 or value > sides:
		_fail(ctx, "Séquence de dés invalide ou épuisée.")
		return 0
	return value

static func _has_mod(mods: Array, name: String) -> bool:
	for m in mods:
		if str(m.get("name", "")) == name:
			return true
	return false

static func _make_rng(opts: Dictionary) -> Callable:
	if opts.has("rng") and opts["rng"] is Callable:
		return opts["rng"]
	if opts.has("rolls"):
		var queue: Array = (opts["rolls"] as Array).duplicate()
		return func(_min_v: int, _max_v: int) -> int:
			if queue.is_empty():
				return 0
			return int(queue.pop_front())
	if opts.has("seed"):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(opts["seed"])
		return func(min_v: int, max_v: int) -> int:
			return rng.randi_range(min_v, max_v)
	return func(min_v: int, max_v: int) -> int:
		return randi_range(min_v, max_v)

# ===========================================================================
# Assemblage / formatage
# ===========================================================================

static func _collect_rolls(node: Dictionary) -> Array:
	var out: Array = []
	var kind := str(node.get("kind", ""))
	if kind == "dice":
		for v in node.get("kept", []):
			out.append(int(v))
	elif kind == "comparison":
		out.append_array(_collect_rolls(node.get("left", {})))
		out.append_array(_collect_rolls(node.get("right", {})))
	else:
		for child in node.get("children", []):
			out.append_array(_collect_rolls(child))
	return out

static func _format_dice_detail(node: Dictionary) -> String:
	var kind := str(node.get("kind", ""))
	if kind == "dice":
		var dropped: Array = node.get("dropped", [])
		var shown: Array = node.get("kept", []) if not dropped.is_empty() else node.get("values", [])
		if shown.is_empty():
			return ""
		var parts: Array[String] = []
		for v in shown:
			parts.append(str(int(v)))
		var text := " — dés : " + ", ".join(parts)
		if not dropped.is_empty():
			var dropped_parts: Array[String] = []
			for v in dropped:
				dropped_parts.append(str(int(v)))
			text += " (défaussés : %s)" % ", ".join(dropped_parts)
		return text
	if kind == "comparison":
		return _format_dice_detail(node.get("left", {}))
	var out := ""
	for child in node.get("children", []):
		var part := _format_dice_detail(child)
		if part != "":
			out += part
	return out

static func _error(formula: String, message: String) -> Dictionary:
	return {"ok": false, "error": message, "formula": formula}

static func _fail(ctx: Dictionary, message: String) -> void:
	if str(ctx["error"]) == "":
		ctx["error"] = message
