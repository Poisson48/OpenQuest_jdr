extends SceneTree

## Test headless du moteur de dés (étape 1 du plan d'adaptation).
##
## Vérifie la grammaire, l'arbre de résultat, les modificateurs, les tests de dés
## à poids, les erreurs et la reproductibilité du RNG, à partir des cas partagés
## `res://data/tests/dice_cases.json` (les mêmes que côté serveur TS).
##
##   godot --headless --path game -s res://scripts/tests/dice_engine_test.gd

const DiceEngineScript := preload("res://scripts/core/rules/dice_engine.gd")

const CASES_PATH := "res://data/tests/dice_cases.json"
const TEST_NAME := "dice_engine_test"

var _checks := 0
var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	var cases := _load_cases()
	if cases.is_empty():
		_fail("cas de test introuvables ou invalides (%s)" % CASES_PATH)
		_finish()
		return

	for case in cases:
		_run_case(case)

	_check_determinism()
	_check_format()
	_check_limits()
	_finish()

# ---------------------------------------------------------------------------
# Cas partagés
# ---------------------------------------------------------------------------

func _load_cases() -> Array:
	if not FileAccess.file_exists(CASES_PATH):
		return []
	var file := FileAccess.open(CASES_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	return parsed.get("cases", [])

func _run_case(case: Dictionary) -> void:
	var case_name := str(case.get("name", "?"))
	var formula := str(case.get("formula", ""))
	var rolls := _to_int_array(case.get("rolls", []))
	var result := DiceEngineScript.roll(formula, {"rolls": rolls})
	var expect: Dictionary = case.get("expect", {})

	for key in expect.keys():
		var expected = expect[key]
		match str(key):
			"ok":
				_check(case_name, "ok", bool(result.get("ok", false)), bool(expected))
			"kind":
				_check(case_name, "kind", str(result.get("kind", "")), str(expected))
			"total":
				_check(case_name, "total", int(result.get("total", -999999)), int(expected))
			"modifier":
				_check(case_name, "modifier", int(result.get("modifier", -999999)), int(expected))
			"success":
				_check(case_name, "success", int(result.get("success", -999999)), int(expected))
			"failure":
				_check(case_name, "failure", int(result.get("failure", -999999)), int(expected))
			"rolls":
				_check_array(case_name, "rolls", result.get("rolls", []), _to_int_array(expected))
			"kept":
				_check_array(case_name, "kept", result.get("kept", []), _to_int_array(expected))
			"dropped":
				_check_array(case_name, "dropped", result.get("dropped", []), _to_int_array(expected))
			"tags":
				_check_array(case_name, "tags", result.get("tags", []), expected)
			_:
				_check(case_name, str(key), result.get(key), expected)

	if not bool(expect.get("ok", true)):
		_check(case_name, "message d'erreur", str(result.get("error", "")).is_empty(), false)

# ---------------------------------------------------------------------------
# Vérifications transverses
# ---------------------------------------------------------------------------

func _check_determinism() -> void:
	var a := DiceEngineScript.roll("4d6keeph3[degats]", {"rolls": [3, 5, 1, 6]})
	var b := DiceEngineScript.roll("4d6keeph3[degats]", {"rolls": [3, 5, 1, 6]})
	_check("determinism", "même séquence = même résultat", str(a) == str(b), true)

	var seeded_a := DiceEngineScript.roll("10d100", {"seed": 4242})
	var seeded_b := DiceEngineScript.roll("10d100", {"seed": 4242})
	_check("determinism", "même seed = même résultat", str(seeded_a) == str(seeded_b), true)
	_check("determinism", "seed produit 10 dés", (seeded_a.get("values", []) as Array).size(), 10)

	var empty_seq := DiceEngineScript.roll("1d6", {"rolls": []})
	_check("determinism", "séquence épuisée = erreur", bool(empty_seq.get("ok", true)), false)

func _check_format() -> void:
	var result := DiceEngineScript.roll("4d6keeph3", {"rolls": [3, 5, 1, 6]})
	var text := DiceEngineScript.format(result)
	_check("format", "total présent", text.contains("14"), true)
	_check("format", "dés retenus", text.contains("3, 5, 6"), true)
	_check("format", "défaussés présents", text.contains("défaussés : 1"), true)
	_check("format", "erreur formatée", DiceEngineScript.format(DiceEngineScript.roll("abc")), "Erreur : Symbole inattendu : 'abc'.")
	var sum_cmp := DiceEngineScript.format(DiceEngineScript.roll("1d20+5>=15", {"rolls": [10]}))
	_check("format", "comparaison de sommes = réussite", sum_cmp.contains("réussite"), true)
	_check("format", "comparaison de sommes sans faux succès", sum_cmp.contains("succès"), false)
	var pool := DiceEngineScript.format(DiceEngineScript.roll("5d10>=6", {"rolls": [1, 6, 7, 10, 3]}))
	_check("format", "test de dés = succès", pool.contains("3 succès"), true)

func _check_limits() -> void:
	var too_many := DiceEngineScript.roll("101d6")
	_check("limits", "101d6 refusé", bool(too_many.get("ok", true)), false)
	var big_pool := DiceEngineScript.roll("100d6")
	_check("limits", "100d6 accepté", bool(big_pool.get("ok", false)), true)
	var too_deep := DiceEngineScript.roll("(".repeat(40) + "1d6" + ")".repeat(40))
	_check("limits", "profondeur bornée", bool(too_deep.get("ok", true)), false)
	var long_formula := DiceEngineScript.roll("1d6" + "+1".repeat(200))
	_check("limits", "formule trop longue refusée", bool(long_formula.get("ok", true)), false)
	var zero_div := DiceEngineScript.roll("2d6/0", {"rolls": [3, 4]})
	_check("limits", "division par zéro refusée", bool(zero_div.get("ok", true)), false)

# ---------------------------------------------------------------------------
# Outillage
# ---------------------------------------------------------------------------

func _to_int_array(value) -> Array:
	var out: Array = []
	if value is Array:
		for v in value:
			out.append(int(v))
	return out

func _check(case_name: String, key: String, actual, expected) -> void:
	_checks += 1
	if str(actual) != str(expected):
		_failures += 1
		print("%s:FAIL %s.%s attendu=%s obtenu=%s" % [TEST_NAME, case_name, key, str(expected), str(actual)])

func _check_array(case_name: String, key: String, actual, expected) -> void:
	_checks += 1
	var actual_array: Array = actual if actual is Array else []
	var expected_array: Array = expected if expected is Array else []
	if actual_array.size() != expected_array.size():
		_failures += 1
		print("%s:FAIL %s.%s taille attendue=%d obtenue=%d (%s vs %s)" % [
			TEST_NAME, case_name, key, expected_array.size(), actual_array.size(),
			str(expected_array), str(actual_array),
		])
		return
	for i in actual_array.size():
		if str(actual_array[i]) != str(expected_array[i]):
			_failures += 1
			print("%s:FAIL %s.%s[%d] attendu=%s obtenu=%s" % [
				TEST_NAME, case_name, key, i, str(expected_array[i]), str(actual_array[i]),
			])
			return

func _fail(message: String) -> void:
	_failures += 1
	print("%s:FAIL %s" % [TEST_NAME, message])

func _finish() -> void:
	if _failures > 0:
		print("%s:FAIL %d échec(s) sur %d vérifications" % [TEST_NAME, _failures, _checks])
		quit(1)
		return
	print("%s:PASS %d vérifications" % [TEST_NAME, _checks])
	quit(0)
