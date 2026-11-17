extends RefCounted
class_name Formula

## Langage de formules des fiches déclaratives (lot 5).
##
## Réimplémentation maison (aucune dépendance, aucun JS embarqué) d'un petit
## langage d'expressions pour les valeurs dérivées et les jets :
##
##   expression := or
##   or         := and ( "||" and )*
##   and        := comparison ( "&&" comparison )*
##   comparison := sum ( ( ">=" | "<=" | ">" | "<" | "=" | "!=" ) sum )?
##   sum        := term ( ( "+" | "-" ) term )*
##   term       := unary ( ( "*" | "/" | "%" ) unary )*
##   unary      := ( "-" | "!" ) unary | primary
##   primary    := number | string | ref | function "(" args ")" | "(" expression ")"
##   ref        := "@" ident     (champ de fiche)
##               | "$" ident     (variable de contexte / runtime)
##   function   := "if" | "round" | "floor" | "ceil" | "abs"
##               | "min" | "max" | "sum" | "avg"
##
## Le résultat est toujours un Dictionary : `{"ok": bool, "value": Variant,
## "error": String}`. Les erreurs sont en français (destinées au MJ/joueur).

const MAX_DEPTH := 32
const MAX_EXPRESSION_LENGTH := 512

const FUNCTIONS := ["if", "round", "floor", "ceil", "abs", "min", "max", "sum", "avg"]

# ===========================================================================
# API
# ===========================================================================

## Évalue une expression avec `context = {"fields": {...}, "vars": {...}}`.
static func evaluate(expression: String, context: Dictionary = {}) -> Dictionary:
	var parsed := parse(expression)
	if not bool(parsed.get("ok", false)):
		return parsed
	var eval_context := {
		"fields": context.get("fields", {}) if context.get("fields") is Dictionary else {},
		"vars": context.get("vars", {}) if context.get("vars") is Dictionary else {},
	}
	return _eval(parsed["ast"], eval_context, 0)

## Vérifie la syntaxe sans évaluer : `{"ok": bool, "error": String}`.
static func parse_check(expression: String) -> Dictionary:
	var parsed := parse(expression)
	if not bool(parsed.get("ok", false)):
		return { "ok": false, "error": str(parsed.get("error", "Expression invalide.")) }
	return { "ok": true, "error": "" }

## Références utilisées : [{kind: "field"|"var", name}], sans doublon.
static func collect_refs(expression: String) -> Array:
	var parsed := parse(expression)
	if not bool(parsed.get("ok", false)):
		return []
	var refs: Dictionary = {}
	_collect(parsed["ast"], refs)
	var out: Array = []
	for key in refs.keys():
		out.append({"kind": str(refs[key]["kind"]), "name": str(refs[key]["name"])})
	return out

## Remplace les références de champ par leurs valeurs (garde les littéraux de dés).
## Ex. `"1d20 + @mod_str"` avec mod_str = 3 → `"1d20 + 3"`.
static func expand(expression: String, values: Dictionary) -> Dictionary:
	var parsed := parse(expression)
	if not bool(parsed.get("ok", false)):
		return parsed
	var missing: Array = []
	var text := _expand_ast(parsed["ast"], values, missing)
	if not missing.is_empty():
		return {
			"ok": false,
			"error": "Référence inconnue : %s." % ", ".join(missing),
			"value": "",
		}
	return { "ok": true, "value": text, "error": "" }

static func format_number(value: Variant) -> String:
	if value is bool:
		return "1" if value else "0"
	var number := float(value)
	if is_equal_approx(number, roundf(number)):
		return str(roundi(number))
	return str(snappedf(number, 0.001))

# ===========================================================================
# Tokenizer
# ===========================================================================

static func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"

static func _is_alpha(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"

static func _lex(source: String) -> Array:
	var tokens: Array = []
	var i := 0
	var length := source.length()
	while i < length:
		var ch := source[i]
		if ch == " " or ch == "\t" or ch == "\n" or ch == "\r":
			i += 1
			continue
		if _is_digit(ch) or (ch == "." and i + 1 < length and _is_digit(source[i + 1])):
			var start := i
			var seen_dot := false
			while i < length and (_is_digit(source[i]) or (source[i] == "." and not seen_dot)):
				if source[i] == ".":
					seen_dot = true
				i += 1
			var text := source.substr(start, i - start)
			tokens.append({"t": "number", "v": float(text), "text": text})
			continue
		if ch == "@" or ch == "$":
			var kind := "field" if ch == "@" else "var"
			i += 1
			var start_name := i
			while i < length and (_is_alpha(source[i]) or _is_digit(source[i])):
				i += 1
			if i == start_name:
				return []
			tokens.append({"t": "ref", "kind": kind, "v": source.substr(start_name, i - start_name)})
			continue
		if _is_alpha(ch):
			var start_ident := i
			while i < length and (_is_alpha(source[i]) or _is_digit(source[i])):
				i += 1
			tokens.append({"t": "ident", "v": source.substr(start_ident, i - start_ident)})
			continue
		if ch == "\"":
			i += 1
			var buffer := ""
			var closed := false
			while i < length:
				var c := source[i]
				if c == "\\" and i + 1 < length:
					buffer += source[i + 1]
					i += 2
					continue
				if c == "\"":
					closed = true
					i += 1
					break
				buffer += c
				i += 1
			if not closed:
				return []
			tokens.append({"t": "string", "v": buffer})
			continue
		var two := source.substr(i, 2)
		if two == ">=" or two == "<=" or two == "!=" or two == "==" or two == "&&" or two == "||":
			tokens.append({"t": "op", "v": two})
			i += 2
			continue
		if ch in ["+", "-", "*", "/", "%", ">", "<", "=", "!", "(", ")", ","]:
			tokens.append({"t": "op", "v": ch})
			i += 1
			continue
		return []
	return tokens

# ===========================================================================
# Parser (produit un AST)
# ===========================================================================

static func parse(expression: String) -> Dictionary:
	var source := expression.strip_edges()
	if source.is_empty():
		return { "ok": false, "error": "Expression vide." }
	if source.length() > MAX_EXPRESSION_LENGTH:
		return { "ok": false, "error": "Expression trop longue (max %d)." % MAX_EXPRESSION_LENGTH }
	var tokens := _lex(source)
	if tokens.is_empty():
		return { "ok": false, "error": "Expression invalide." }
	var parser := { "tokens": tokens, "i": 0, "error": "", "depth": 0 }
	var ast := _parse_or(parser)
	if str(parser["error"]) != "":
		return { "ok": false, "error": str(parser["error"]) }
	if int(parser["i"]) < tokens.size():
		return { "ok": false, "error": "Symbole inattendu en fin d'expression." }
	return { "ok": true, "ast": ast, "error": "" }

static func _peek(parser: Dictionary) -> Dictionary:
	var tokens: Array = parser["tokens"]
	var index := int(parser["i"])
	if index >= tokens.size():
		return { "t": "eof", "v": "" }
	return tokens[index]

static func _advance(parser: Dictionary) -> Dictionary:
	var token := _peek(parser)
	parser["i"] = int(parser["i"]) + 1
	return token

static func _is_op(parser: Dictionary, value: String) -> bool:
	var token := _peek(parser)
	return str(token.get("t", "")) == "op" and str(token.get("v", "")) == value

static func _parse_or(parser: Dictionary) -> Dictionary:
	var left := _parse_and(parser)
	while str(parser["error"]) == "" and _is_op(parser, "||"):
		_advance(parser)
		var right := _parse_and(parser)
		left = { "t": "logic", "op": "||", "l": left, "r": right }
	return left

static func _parse_and(parser: Dictionary) -> Dictionary:
	var left := _parse_comparison(parser)
	while str(parser["error"]) == "" and _is_op(parser, "&&"):
		_advance(parser)
		var right := _parse_comparison(parser)
		left = { "t": "logic", "op": "&&", "l": left, "r": right }
	return left

static func _parse_comparison(parser: Dictionary) -> Dictionary:
	var left := _parse_sum(parser)
	if str(parser["error"]) != "":
		return left
	var token := _peek(parser)
	if str(token.get("t", "")) == "op" and str(token.get("v", "")) in [">=", "<=", ">", "<", "=", "==", "!="]:
		var op := str(_advance(parser)["v"])
		if op == "==":
			op = "="
		var right := _parse_sum(parser)
		return { "t": "cmp", "op": op, "l": left, "r": right }
	return left

static func _parse_sum(parser: Dictionary) -> Dictionary:
	var left := _parse_term(parser)
	while str(parser["error"]) == "" and (_is_op(parser, "+") or _is_op(parser, "-")):
		var op := str(_advance(parser)["v"])
		var right := _parse_term(parser)
		left = { "t": "bin", "op": op, "l": left, "r": right }
	return left

static func _parse_term(parser: Dictionary) -> Dictionary:
	var left := _parse_unary(parser)
	while str(parser["error"]) == "" and (_is_op(parser, "*") or _is_op(parser, "/") or _is_op(parser, "%")):
		var op := str(_advance(parser)["v"])
		var right := _parse_unary(parser)
		left = { "t": "bin", "op": op, "l": left, "r": right }
	return left

static func _parse_unary(parser: Dictionary) -> Dictionary:
	if _is_op(parser, "-") or _is_op(parser, "!"):
		var op := str(_advance(parser)["v"])
		var inner := _parse_unary(parser)
		return { "t": "un", "op": op, "a": inner }
	return _parse_primary(parser)

static func _parse_primary(parser: Dictionary) -> Dictionary:
	var token := _peek(parser)
	if str(token.get("t", "")) == "number":
		_advance(parser)
		return { "t": "num", "v": float(token["v"]) }
	if str(token.get("t", "")) == "string":
		_advance(parser)
		return { "t": "str", "v": str(token["v"]) }
	if str(token.get("t", "")) == "ref":
		_advance(parser)
		return { "t": "ref", "kind": str(token["kind"]), "v": str(token["v"]) }
	if str(token.get("t", "")) == "ident":
		return _parse_call(parser)
	if _is_op(parser, "("):
		_advance(parser)
		var inner := _parse_or(parser)
		if not _is_op(parser, ")"):
			parser["error"] = "Parenthèse non fermée."
			return inner
		_advance(parser)
		return inner
	parser["error"] = "Symbole inattendu : '%s'." % str(token.get("v", "?"))
	return { "t": "num", "v": 0.0 }

static func _parse_call(parser: Dictionary) -> Dictionary:
	var name_token := _advance(parser)
	var name := str(name_token["v"])
	if not FUNCTIONS.has(name):
		parser["error"] = "Fonction inconnue : '%s'." % name
		return { "t": "num", "v": 0.0 }
	if not _is_op(parser, "("):
		parser["error"] = "Parenthèse attendue après '%s'." % name
		return { "t": "num", "v": 0.0 }
	_advance(parser)
	var args: Array = []
	if not _is_op(parser, ")"):
		while true:
			args.append(_parse_or(parser))
			if str(parser["error"]) != "":
				return { "t": "num", "v": 0.0 }
			if _is_op(parser, ","):
				_advance(parser)
				continue
			break
	if not _is_op(parser, ")"):
		parser["error"] = "Parenthèse non fermée après '%s'." % name
		return { "t": "num", "v": 0.0 }
	_advance(parser)
	return { "t": "fn", "name": name, "args": args }

# ===========================================================================
# Évaluation
# ===========================================================================

static func _eval(node: Dictionary, context: Dictionary, depth: int) -> Dictionary:
	if depth > MAX_DEPTH:
		return { "ok": false, "error": "Expression trop profonde.", "value": 0 }
	var kind := str(node.get("t", ""))
	if kind == "num" or kind == "str":
		return { "ok": true, "value": node["v"], "error": "" }
	if kind == "ref":
		return _eval_ref(node, context)
	if kind == "un":
		var inner := _eval(node["a"], context, depth + 1)
		if not bool(inner["ok"]):
			return inner
		if str(node["op"]) == "-":
			var number := _to_number(inner["value"])
			if not bool(number["ok"]):
				return number
			return { "ok": true, "value": -float(number["value"]), "error": "" }
		return { "ok": true, "value": not _truthy(inner["value"]), "error": "" }
	if kind == "logic":
		var left := _eval(node["l"], context, depth + 1)
		if not bool(left["ok"]):
			return left
		if str(node["op"]) == "&&":
			if not _truthy(left["value"]):
				return { "ok": true, "value": false, "error": "" }
			var right_and := _eval(node["r"], context, depth + 1)
			if not bool(right_and["ok"]):
				return right_and
			return { "ok": true, "value": _truthy(right_and["value"]), "error": "" }
		if _truthy(left["value"]):
			return { "ok": true, "value": true, "error": "" }
		var right_or := _eval(node["r"], context, depth + 1)
		if not bool(right_or["ok"]):
			return right_or
		return { "ok": true, "value": _truthy(right_or["value"]), "error": "" }
	if kind == "cmp":
		return _eval_comparison(node, context, depth)
	if kind == "bin":
		return _eval_binary(node, context, depth)
	if kind == "fn":
		return _eval_function(node, context, depth)
	return { "ok": false, "error": "Nœud interne inconnu.", "value": 0 }

static func _eval_ref(node: Dictionary, context: Dictionary) -> Dictionary:
	var name := str(node["v"])
	var bag: Dictionary = context["fields"] if str(node["kind"]) == "field" else context["vars"]
	if not bag.has(name):
		return { "ok": false, "error": "Référence inconnue : '%s%s'." % ["@" if str(node["kind"]) == "field" else "$", name], "value": 0 }
	return { "ok": true, "value": bag[name], "error": "" }

static func _eval_comparison(node: Dictionary, context: Dictionary, depth: int) -> Dictionary:
	var left := _eval(node["l"], context, depth + 1)
	if not bool(left["ok"]):
		return left
	var right := _eval(node["r"], context, depth + 1)
	if not bool(right["ok"]):
		return right
	var op := str(node["op"])
	if left["value"] is String or right["value"] is String:
		var left_text := str(left["value"])
		var right_text := str(right["value"])
		var result := false
		if op == "=":
			result = left_text == right_text
		elif op == "!=":
			result = left_text != right_text
		elif op == ">":
			result = left_text > right_text
		elif op == "<":
			result = left_text < right_text
		elif op == ">=":
			result = left_text >= right_text
		elif op == "<=":
			result = left_text <= right_text
		return { "ok": true, "value": result, "error": "" }
	var left_number := _to_number(left["value"])
	if not bool(left_number["ok"]):
		return left_number
	var right_number := _to_number(right["value"])
	if not bool(right_number["ok"]):
		return right_number
	var a := float(left_number["value"])
	var b := float(right_number["value"])
	var comparison := false
	if op == "=":
		comparison = is_equal_approx(a, b)
	elif op == "!=":
		comparison = not is_equal_approx(a, b)
	elif op == ">":
		comparison = a > b
	elif op == "<":
		comparison = a < b
	elif op == ">=":
		comparison = a >= b
	elif op == "<=":
		comparison = a <= b
	return { "ok": true, "value": comparison, "error": "" }

static func _eval_binary(node: Dictionary, context: Dictionary, depth: int) -> Dictionary:
	var left := _eval(node["l"], context, depth + 1)
	if not bool(left["ok"]):
		return left
	var right := _eval(node["r"], context, depth + 1)
	if not bool(right["ok"]):
		return right
	var op := str(node["op"])
	if op == "+" and left["value"] is String and right["value"] is String:
		return { "ok": true, "value": str(left["value"]) + str(right["value"]), "error": "" }
	var left_number := _to_number(left["value"])
	if not bool(left_number["ok"]):
		return left_number
	var right_number := _to_number(right["value"])
	if not bool(right_number["ok"]):
		return right_number
	var a := float(left_number["value"])
	var b := float(right_number["value"])
	if op == "+":
		return { "ok": true, "value": a + b, "error": "" }
	if op == "-":
		return { "ok": true, "value": a - b, "error": "" }
	if op == "*":
		return { "ok": true, "value": a * b, "error": "" }
	if b == 0.0:
		return { "ok": false, "error": "Division par zéro.", "value": 0 }
	if op == "/":
		return { "ok": true, "value": a / b, "error": "" }
	return { "ok": true, "value": fmod(a, b), "error": "" }

static func _eval_function(node: Dictionary, context: Dictionary, depth: int) -> Dictionary:
	var name := str(node["name"])
	var args: Array = node["args"]
	if name == "if":
		if args.size() != 3:
			return { "ok": false, "error": "if() attend 3 arguments.", "value": 0 }
		var condition := _eval(args[0], context, depth + 1)
		if not bool(condition["ok"]):
			return condition
		var branch: Dictionary = args[1] if _truthy(condition["value"]) else args[2]
		return _eval(branch, context, depth + 1)

	var values: Array = []
	for argument in args:
		var evaluated := _eval(argument, context, depth + 1)
		if not bool(evaluated["ok"]):
			return evaluated
		var number := _to_number(evaluated["value"])
		if not bool(number["ok"]):
			return number
		values.append(float(number["value"]))

	if name == "min" or name == "max" or name == "sum" or name == "avg":
		if values.is_empty():
			return { "ok": false, "error": "%s() attend au moins un argument." % name, "value": 0 }
	if name == "round":
		return { "ok": true, "value": float(roundi(_first(values))), "error": "" }
	if name == "floor":
		return { "ok": true, "value": float(floori(_first(values))), "error": "" }
	if name == "ceil":
		return { "ok": true, "value": float(ceili(_first(values))), "error": "" }
	if name == "abs":
		return { "ok": true, "value": absf(_first(values)), "error": "" }
	if name == "min":
		var result := float(values[0])
		for value in values:
			result = minf(result, float(value))
		return { "ok": true, "value": result, "error": "" }
	if name == "max":
		var result_max := float(values[0])
		for value in values:
			result_max = maxf(result_max, float(value))
		return { "ok": true, "value": result_max, "error": "" }
	if name == "sum":
		var total := 0.0
		for value in values:
			total += float(value)
		return { "ok": true, "value": total, "error": "" }
	var average := 0.0
	for value in values:
		average += float(value)
	return { "ok": true, "value": average / float(values.size()), "error": "" }

static func _first(values: Array) -> float:
	if values.is_empty():
		return 0.0
	return float(values[0])

static func _to_number(value: Variant) -> Dictionary:
	if value is bool:
		return { "ok": true, "value": 1.0 if value else 0.0, "error": "" }
	if value is int or value is float:
		return { "ok": true, "value": float(value), "error": "" }
	return { "ok": false, "error": "Valeur non numérique : '%s'." % str(value), "value": 0 }

static func _truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return float(value) != 0.0
	if value is String:
		return not str(value).is_empty()
	return value != null

# ===========================================================================
# Collecte / expansion des références
# ===========================================================================

static func _collect(node: Dictionary, out: Dictionary) -> void:
	var kind := str(node.get("t", ""))
	if kind == "ref":
		var ref_kind := str(node["kind"])
		var name := str(node["v"])
		if not out.has(ref_kind + ":" + name):
			out[ref_kind + ":" + name] = { "kind": ref_kind, "name": name }
		return
	if kind == "un":
		_collect(node["a"], out)
		return
	if kind == "logic" or kind == "bin" or kind == "cmp":
		_collect(node["l"], out)
		_collect(node["r"], out)
		return
	if kind == "fn":
		for argument in node["args"]:
			_collect(argument, out)

static func _expand_ast(node: Dictionary, values: Dictionary, missing: Array) -> String:
	var kind := str(node.get("t", ""))
	if kind == "num":
		return format_number(node["v"])
	if kind == "str":
		return str(node["v"])
	if kind == "ref":
		var name := str(node["v"])
		if str(node["kind"]) == "field":
			if not values.has(name):
				missing.append("@" + name)
				return "0"
			return format_number(values[name])
		return "$" + name
	if kind == "un":
		return str(node["op"]) + _expand_ast(node["a"], values, missing)
	if kind == "logic" or kind == "bin" or kind == "cmp":
		return "(%s %s %s)" % [
			_expand_ast(node["l"], values, missing),
			str(node["op"]),
			_expand_ast(node["r"], values, missing),
		]
	if kind == "fn":
		var parts: Array = []
		for argument in node["args"]:
			parts.append(_expand_ast(argument, values, missing))
		return "%s(%s)" % [str(node["name"]), ", ".join(parts)]
	return ""
