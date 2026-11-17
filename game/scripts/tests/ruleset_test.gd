extends SceneTree

## Tests des fiches déclaratives (lot 5) : validation d'un ruleset, valeurs
## dérivées (dépendances, cycles), expansion des jets, et langage de formules.
##
##   godot --headless --path game -s res://scripts/tests/ruleset_test.gd

const FormulaScript := preload("res://scripts/core/rules/formula.gd")
const RulesetScript := preload("res://scripts/core/rules/ruleset.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	_test_formula()
	_test_validate()
	_test_build_simple()
	_test_build_dnd()
	_test_expand_rolls()
	_test_errors()
	_test_inline_ruleset()

	if _failed:
		quit(1)
		return
	print("ruleset_test:PASS")
	quit(0)

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("ruleset_test:FAIL at ", name)
		_failed = true

func _assert_number(name: String, actual, expected: float) -> void:
	_assert(name, absf(float(actual) - expected) < 0.001)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

func _simple_ruleset() -> Dictionary:
	return _load_json("res://data/rulesets/naheulbeuk_simple.json")

func _dnd_ruleset() -> Dictionary:
	return _load_json("res://data/rulesets/dnd_complete.json")

# ---------------------------------------------------------------------------

func _test_formula() -> void:
	var arithmetic: Dictionary = FormulaScript.evaluate("1 + 2 * 3", {})
	_assert("formula_arithmetic", bool(arithmetic["ok"]))
	_assert_number("formula_arithmetic_value", arithmetic["value"], 7.0)

	_assert_number("formula_parentheses", FormulaScript.evaluate("(1 + 2) * 3", {})["value"], 9.0)
	_assert_number("formula_modulo", FormulaScript.evaluate("7 % 4", {})["value"], 3.0)

	var refs: Dictionary = FormulaScript.evaluate("@a + $b", {
		"fields": {"a": 4},
		"vars": {"b": 6},
	})
	_assert("formula_refs_ok", bool(refs["ok"]))
	_assert_number("formula_refs_value", refs["value"], 10.0)

	_assert("formula_missing_ref", not bool(FormulaScript.evaluate("@inconnu", {})["ok"]))
	_assert("formula_unknown_function", not bool(FormulaScript.evaluate("foo(1)", {})["ok"]))
	_assert("formula_div_zero", not bool(FormulaScript.evaluate("1 / 0", {})["ok"]))
	_assert("formula_empty", not bool(FormulaScript.evaluate("", {})["ok"]))
	_assert("formula_unbalanced", not bool(FormulaScript.evaluate("(1 + 2", {})["ok"]))

	var conditional: Dictionary = FormulaScript.evaluate("if(3 > 2, \"oui\", \"non\")", {})
	_assert("formula_if", bool(conditional["ok"]) and str(conditional["value"]) == "oui")

	_assert("formula_logic", bool(FormulaScript.evaluate("@a > 2 && @a < 10", {"fields": {"a": 5}})["value"]))
	_assert("formula_concat", str(FormulaScript.evaluate("\"a\" + \"b\"", {})["value"]) == "ab")
	_assert_number("formula_floor", FormulaScript.evaluate("floor(3.9)", {})["value"], 3.0)
	_assert_number("formula_ceil", FormulaScript.evaluate("ceil(3.1)", {})["value"], 4.0)
	_assert_number("formula_round", FormulaScript.evaluate("round(3.6)", {})["value"], 4.0)
	_assert_number("formula_min_max", FormulaScript.evaluate("min(4, 9, 2) + max(1, 3)", {})["value"], 5.0)
	_assert_number("formula_sum_avg", FormulaScript.evaluate("sum(2, 4, 6) + avg(2, 4)", {})["value"], 15.0)

	var collected: Array = FormulaScript.collect_refs("@a + $b + @c")
	_assert("formula_collect_count", collected.size() == 3)
	_assert("formula_format_int", FormulaScript.format_number(3.0) == "3")
	_assert("formula_format_float", FormulaScript.format_number(3.5) == "3.5")

func _test_validate() -> void:
	var simple := _simple_ruleset()
	_assert("validate_simple_loaded", not simple.is_empty())
	_assert("validate_simple", bool(RulesetScript.validate(simple)["ok"]))
	var dnd := _dnd_ruleset()
	_assert("validate_dnd_loaded", not dnd.is_empty())
	_assert("validate_dnd", bool(RulesetScript.validate(dnd)["ok"]))

	var bad_missing_id := { "title": "Sans id" }
	_assert("validate_missing_id", not bool(RulesetScript.validate(bad_missing_id)["ok"]))

	var bad_ref := {
		"id": "bad", "title": "Bad",
		"fields": [{ "id": "a" }],
		"derived": [{ "id": "x", "formula": "@inconnu + 1" }],
	}
	var bad_ref_report: Dictionary = RulesetScript.validate(bad_ref)
	_assert("validate_unknown_ref", not bool(bad_ref_report["ok"]))
	_assert("validate_unknown_ref_message", _errors_text(bad_ref_report).contains("inconnue"))

	var bad_fn := {
		"id": "bad", "title": "Bad",
		"fields": [{ "id": "a" }],
		"derived": [{ "id": "x", "formula": "foo(@a)" }],
	}
	_assert("validate_unknown_function", not bool(RulesetScript.validate(bad_fn)["ok"]))

	var bad_roll := {
		"id": "bad", "title": "Bad",
		"fields": [{ "id": "a" }],
		"rolls": [{ "id": "r", "formula": "1d20 + @inconnu" }],
	}
	_assert("validate_roll_unknown_ref", not bool(RulesetScript.validate(bad_roll)["ok"]))

func _errors_text(report: Dictionary) -> String:
	var out := ""
	for error in report.get("errors", []):
		out += str(error) + " "
	return out

func _test_build_simple() -> void:
	var simple := _simple_ruleset()
	var built: Dictionary = RulesetScript.build(simple, {
		"str": 14, "ruse": 12, "robustesse": 13, "charisme": 9,
	})
	_assert("build_simple_ok", bool(built["ok"]))
	var values: Dictionary = built.get("values", {})
	_assert_number("simple_mod_str", values.get("mod_str", -99), 2.0)
	_assert_number("simple_mod_ruse", values.get("mod_ruse", -99), 1.0)
	_assert_number("simple_defense", values.get("defense", -99), 11.0)
	_assert_number("simple_pv_max", values.get("pv_max", -99), 7.0)
	_assert_number("simple_initiative", values.get("initiative", -99), 13.0)

	var defaults: Dictionary = RulesetScript.build(simple)
	_assert("build_simple_defaults_ok", bool(defaults["ok"]))
	_assert_number("simple_default_mod", (defaults["values"] as Dictionary).get("mod_str", -99), 0.0)
	_assert_number("simple_default_pv", (defaults["values"] as Dictionary).get("pv_max", -99), 6.0)

func _test_build_dnd() -> void:
	var dnd := _dnd_ruleset()
	var built: Dictionary = RulesetScript.build(dnd, {
		"str": 16, "dex": 14, "con": 15, "intel": 8, "level": 3, "proficiency": 2,
	})
	_assert("build_dnd_ok", bool(built["ok"]))
	var values: Dictionary = built.get("values", {})
	_assert_number("dnd_mod_str", values.get("mod_str", -99), 3.0)
	_assert_number("dnd_mod_dex", values.get("mod_dex", -99), 2.0)
	_assert_number("dnd_mod_con", values.get("mod_con", -99), 2.0)
	_assert_number("dnd_mod_intel", values.get("mod_intel", -99), -1.0)
	_assert_number("dnd_ac", values.get("ac", -99), 12.0)
	_assert_number("dnd_pv_max", values.get("pv_max", -99), 24.0)
	_assert_number("dnd_attaque_bonus", values.get("attaque_bonus", -99), 5.0)
	_assert_number("dnd_save_dc", values.get("save_dc", -99), 9.0)

func _test_expand_rolls() -> void:
	var simple := _simple_ruleset()
	var built: Dictionary = RulesetScript.build(simple, { "str": 14 })
	var values: Dictionary = built.get("values", {})

	var attack: Dictionary = RulesetScript.expand_roll(simple, "attaque", values)
	_assert("roll_attaque_ok", bool(attack["ok"]))
	_assert("roll_attaque_formula", str(attack.get("formula", "")) == "1d20 + 2")
	_assert("roll_attaque_label", str(attack.get("label", "")) == "Attaque")
	_assert("roll_attaque_visibility", str(attack.get("visibility", "")) == "table")

	var damage: Dictionary = RulesetScript.expand_roll(simple, "degats", values)
	_assert("roll_degats_formula", str(damage.get("formula", "")) == "1d6 + 2[degats]")

	var unknown: Dictionary = RulesetScript.expand_roll(simple, "inconnu", values)
	_assert("roll_unknown", not bool(unknown["ok"]))

	var dnd := _dnd_ruleset()
	var dnd_built: Dictionary = RulesetScript.build(dnd, { "str": 16, "proficiency": 2 })
	var dnd_values: Dictionary = dnd_built["values"]
	var dnd_attack: Dictionary = RulesetScript.expand_roll(dnd, "attaque", dnd_values)
	_assert("roll_dnd_attaque", str(dnd_attack.get("formula", "")) == "1d20 + 5")

	# La formule étendue doit être acceptée par le moteur de dés (lot 1).
	var dice: GDScript = load("res://scripts/core/rules/dice_engine.gd") as GDScript
	var rolled: Dictionary = dice.roll(str(dnd_attack.get("formula", "")), { "rolls": [13] })
	_assert("roll_dnd_dice_ok", bool(rolled.get("ok", false)))
	_assert("roll_dnd_dice_total", int(rolled.get("total", -1)) == 18)

func _test_errors() -> void:
	var cycle := {
		"id": "cycle", "title": "Cycle",
		"fields": [{ "id": "a", "type": "int", "default": 1 }],
		"derived": [
			{ "id": "x", "formula": "@y + 1" },
			{ "id": "y", "formula": "@x + 1" },
		],
	}
	_assert("cycle_valid_syntax", bool(RulesetScript.validate(cycle)["ok"]))
	var cycle_built: Dictionary = RulesetScript.build(cycle)
	_assert("cycle_detected", not bool(cycle_built["ok"]))
	_assert("cycle_message", str(cycle_built.get("error", "")).contains("circulaire"))

	var div_zero := {
		"id": "div", "title": "Div",
		"fields": [{ "id": "a", "type": "int", "default": 4 }],
		"derived": [{ "id": "z", "formula": "@a / 0" }],
	}
	var div_built: Dictionary = RulesetScript.build(div_zero)
	_assert("div_zero_detected", not bool(div_built["ok"]))
	_assert("div_zero_message", str(div_built.get("error", "")).contains("Division par zéro"))

func _test_inline_ruleset() -> void:
	# Un ruleset défini **sans code** (inline) : le but du lot 5.
	var ruleset := {
		"id": "inline-test", "title": "Inline",
		"fields": [
			{ "id": "a", "type": "int", "default": 5 },
			{ "id": "b", "type": "int", "default": 7 },
		],
		"derived": [
			{ "id": "bonus", "formula": "if(@a >= 12, 2, 0)" },
			{ "id": "avg_ab", "formula": "avg(@a, @b)" },
			{ "id": "sum_ab", "formula": "sum(@a, @b)" },
			{ "id": "clamp", "formula": "min(10, max(0, @a - @b))" },
			{ "id": "derived_of_derived", "formula": "@bonus * 10 + @clamp" },
		],
		"rolls": [{ "id": "r", "formula": "1d20 + @bonus" }],
	}
	_assert("inline_valid", bool(RulesetScript.validate(ruleset)["ok"]))
	var built: Dictionary = RulesetScript.build(ruleset, { "a": 12, "b": 3 })
	_assert("inline_build", bool(built["ok"]))
	var values: Dictionary = built.get("values", {})
	_assert_number("inline_bonus", values.get("bonus", -99), 2.0)
	_assert_number("inline_avg", values.get("avg_ab", -99), 7.5)
	_assert_number("inline_sum", values.get("sum_ab", -99), 15.0)
	_assert_number("inline_clamp", values.get("clamp", -99), 9.0)
	_assert_number("inline_chained", values.get("derived_of_derived", -99), 29.0)

	var expanded: Dictionary = RulesetScript.expand_roll(ruleset, "r", values)
	_assert("inline_roll", str(expanded.get("formula", "")) == "1d20 + 2")
