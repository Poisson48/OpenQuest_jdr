extends RefCounted
class_name Ruleset

## Fiches déclaratives (lot 5) : un « ruleset » décrit **sans code** les champs
## d'une fiche, ses valeurs dérivées, ses jets et ses tables. Aucune ligne de
## code n'est nécessaire pour ajouter un système — c'est l'idée retenue de
## l'étude de Let's Role, réimplémentée sur notre format JSON et notre langage de
## formules (`formula.gd`), sans exécution de JavaScript.
##
## Contrat : `data/schemas/ruleset.json`. Exemples : `data/rulesets/*.json`.

const FormulaScript := preload("res://scripts/core/rules/formula.gd")

const FIELD_TYPES := ["int", "float", "bool", "string"]

## Valide un ruleset : `{"ok": bool, "errors": [String]}`.
static func validate(ruleset: Dictionary) -> Dictionary:
	var errors: Array = []
	if not ruleset.has("id") or str(ruleset.get("id", "")).strip_edges().is_empty():
		errors.append("Champ 'id' manquant.")
	if str(ruleset.get("title", "")).strip_edges().is_empty():
		errors.append("Champ 'title' manquant.")

	var field_ids: Dictionary = {}
	var field_defs: Dictionary = {}
	var fields: Array = ruleset.get("fields", []) if ruleset.get("fields") is Array else []
	for field_variant in fields:
		if not field_variant is Dictionary:
			errors.append("Champ de fiche invalide.")
			continue
		var field: Dictionary = field_variant
		var field_id := str(field.get("id", "")).strip_edges()
		if field_id.is_empty():
			errors.append("Champ de fiche sans 'id'.")
			continue
		if field_ids.has(field_id):
			errors.append("Champ de fiche dupliqué : '%s'." % field_id)
		field_ids[field_id] = true
		field_defs[field_id] = field
		var field_type := str(field.get("type", "int"))
		if not FIELD_TYPES.has(field_type):
			errors.append("Champ '%s' : type inconnu '%s'." % [field_id, field_type])

	var derived_defs: Dictionary = {}
	var derived: Array = ruleset.get("derived", []) if ruleset.get("derived") is Array else []
	for derived_variant in derived:
		if not derived_variant is Dictionary:
			errors.append("Valeur dérivée invalide.")
			continue
		var entry: Dictionary = derived_variant
		var derived_id := str(entry.get("id", "")).strip_edges()
		if derived_id.is_empty():
			errors.append("Valeur dérivée sans 'id'.")
			continue
		if field_ids.has(derived_id):
			errors.append("Valeur dérivée '%s' en conflit avec un champ." % derived_id)
		if derived_defs.has(derived_id):
			errors.append("Valeur dérivée dupliquée : '%s'." % derived_id)
		derived_defs[derived_id] = entry

	# Deuxième passe : une valeur dérivée peut référencer une autre valeur
	# dérivée déclarée plus loin — on valide les références une fois l'ensemble
	# des identifiants connus (sinon tout ordre autre qu'alphabétique échouerait).
	for derived_variant in derived:
		if not derived_variant is Dictionary:
			continue
		var entry: Dictionary = derived_variant
		var derived_id := str(entry.get("id", "")).strip_edges()
		if derived_id.is_empty() or not derived_defs.has(derived_id):
			continue
		var formula := str(entry.get("formula", ""))
		var syntax := FormulaScript.parse_check(formula)
		if not bool(syntax["ok"]):
			errors.append("Dérivé '%s' : %s" % [derived_id, str(syntax["error"])])
			continue
		for ref in FormulaScript.collect_refs(formula):
			var ref_kind := str(ref.get("kind", ""))
			var ref_name := str(ref.get("name", ""))
			if ref_kind == "field" and not field_ids.has(ref_name) and not derived_defs.has(ref_name):
				errors.append("Dérivé '%s' : référence inconnue '@%s'." % [derived_id, ref_name])

	var roll_ids: Dictionary = {}
	var rolls: Array = ruleset.get("rolls", []) if ruleset.get("rolls") is Array else []
	for roll_variant in rolls:
		if not roll_variant is Dictionary:
			errors.append("Jet invalide.")
			continue
		var roll: Dictionary = roll_variant
		var roll_id := str(roll.get("id", "")).strip_edges()
		if roll_id.is_empty():
			errors.append("Jet sans 'id'.")
			continue
		if roll_ids.has(roll_id):
			errors.append("Jet dupliqué : '%s'." % roll_id)
		roll_ids[roll_id] = true
		var roll_formula := str(roll.get("formula", ""))
		if roll_formula.strip_edges().is_empty():
			errors.append("Jet '%s' : formule vide." % roll_id)
			continue
		for ref_name in _scan_field_refs(roll_formula):
			if not field_ids.has(ref_name) and not derived_defs.has(ref_name):
				errors.append("Jet '%s' : référence inconnue '@%s'." % [roll_id, ref_name])

	var table_ids: Dictionary = {}
	var tables: Array = ruleset.get("tables", []) if ruleset.get("tables") is Array else []
	for table_variant in tables:
		if not table_variant is Dictionary:
			errors.append("Table invalide.")
			continue
		var table: Dictionary = table_variant
		var table_id := str(table.get("id", "")).strip_edges()
		if table_id.is_empty():
			errors.append("Table sans 'id'.")
			continue
		if table_ids.has(table_id):
			errors.append("Table dupliquée : '%s'." % table_id)
		table_ids[table_id] = true

	return { "ok": errors.is_empty(), "errors": errors }

## Construit les valeurs d'une fiche : défauts + bases, puis dérivés (dépendances
## résolues, références circulaires détectées).
static func build(
	ruleset: Dictionary,
	base_values: Dictionary = {},
	runtime_vars: Dictionary = {}
) -> Dictionary:
	var validation := validate(ruleset)
	if not bool(validation["ok"]):
		return {
			"ok": false,
			"error": _join_list(validation["errors"], "; "),
			"errors": validation["errors"],
			"values": {},
		}

	var values: Dictionary = {}
	var fields: Array = ruleset.get("fields", [])
	for field_variant in fields:
		var field: Dictionary = field_variant
		values[str(field["id"])] = _default_for(field)
	for key in base_values.keys():
		values[str(key)] = base_values[key]

	var derived_defs: Dictionary = {}
	var derived: Array = ruleset.get("derived", [])
	for derived_variant in derived:
		var entry: Dictionary = derived_variant
		derived_defs[str(entry["id"])] = entry

	var state: Dictionary = {}
	var chain: Array = []
	for derived_id in derived_defs.keys():
		var resolution := _resolve_derived(
			str(derived_id), derived_defs, values, runtime_vars, state, chain
		)
		if not bool(resolution["ok"]):
			return {
				"ok": false,
				"error": str(resolution["error"]),
				"errors": [str(resolution["error"])],
				"values": values,
			}
	return { "ok": true, "values": values, "errors": [] }

## Étend la formule d'un jet avec les valeurs de fiche : `1d20 + @mod_str` → `1d20 + 3`.
static func expand_roll(ruleset: Dictionary, roll_id: String, values: Dictionary) -> Dictionary:
	var rolls: Array = ruleset.get("rolls", []) if ruleset.get("rolls") is Array else []
	for roll_variant in rolls:
		if not roll_variant is Dictionary:
			continue
		var roll: Dictionary = roll_variant
		if str(roll.get("id", "")) != roll_id:
			continue
		var formula := str(roll.get("formula", ""))
		var missing: Array = []
		var expanded := _substitute_field_refs(formula, values, missing)
		if not missing.is_empty():
			return {
				"ok": false,
				"error": "Référence inconnue : %s." % _join_list(missing, ", "),
				"formula": "",
			}
		return {
			"ok": true,
			"formula": expanded,
			"label": str(roll.get("label", roll_id)),
			"visibility": str(roll.get("visibility", "table")),
			"error": "",
		}
	return { "ok": false, "error": "Jet inconnu : '%s'." % roll_id, "formula": "" }

## Valeur par défaut d'un champ décrit par le ruleset.
static func field_default(field: Dictionary) -> Variant:
	return _default_for(field)

# ===========================================================================
# Interne
# ===========================================================================

static func _join_list(parts: Array, separator: String) -> String:
	var out := ""
	for part in parts:
		if not out.is_empty():
			out += separator
		out += str(part)
	return out

static func _default_for(field: Dictionary) -> Variant:
	var field_type := str(field.get("type", "int"))
	if field_type == "int":
		return int(field.get("default", 0))
	if field_type == "float":
		return float(field.get("default", 0.0))
	if field_type == "bool":
		return bool(field.get("default", false))
	if field_type == "string":
		return str(field.get("default", ""))
	return 0

static func _resolve_derived(
	derived_id: String,
	derived_defs: Dictionary,
	values: Dictionary,
	runtime_vars: Dictionary,
	state: Dictionary,
	chain: Array
) -> Dictionary:
	var status := int(state.get(derived_id, 0))
	if status == 2:
		return { "ok": true, "error": "" }
	if status == 1:
		return { "ok": false, "error": "Référence circulaire : %s." % _join_list(chain, " → ") }
	state[derived_id] = 1
	chain.append(derived_id)

	var entry: Dictionary = derived_defs[derived_id]
	var formula := str(entry.get("formula", ""))
	# Dépendances vers d'autres dérivés d'abord.
	for ref in FormulaScript.collect_refs(formula):
		if str(ref.get("kind", "")) != "field":
			continue
		var ref_name := str(ref.get("name", ""))
		if not derived_defs.has(ref_name):
			continue
		var dependency := _resolve_derived(
			ref_name, derived_defs, values, runtime_vars, state, chain
		)
		if not bool(dependency["ok"]):
			return dependency

	var evaluated := FormulaScript.evaluate(formula, { "fields": values, "vars": runtime_vars })
	if not bool(evaluated["ok"]):
		return {
			"ok": false,
			"error": "Dérivé '%s' : %s" % [derived_id, str(evaluated.get("error", ""))],
		}
	values[derived_id] = evaluated["value"]
	chain.pop_back()
	state[derived_id] = 2
	return { "ok": true, "error": "" }

static func _scan_field_refs(text: String) -> Array:
	var out: Array = []
	var regex := RegEx.new()
	regex.compile("@([A-Za-z_][A-Za-z0-9_]*)")
	for result in regex.search_all(text):
		var name := result.get_string(1)
		if not out.has(name):
			out.append(name)
	return out

static func _substitute_field_refs(text: String, values: Dictionary, missing: Array) -> String:
	var regex := RegEx.new()
	regex.compile("@([A-Za-z_][A-Za-z0-9_]*)")
	var output := ""
	var cursor := 0
	for result in regex.search_all(text):
		output += text.substr(cursor, result.get_start() - cursor)
		var name := result.get_string(1)
		if values.has(name):
			output += FormulaScript.format_number(values[name])
		else:
			missing.append("@" + name)
			output += "0"
		cursor = result.get_end()
	output += text.substr(cursor)
	return output
