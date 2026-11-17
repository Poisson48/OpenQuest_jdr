extends SceneTree

## Test PUR de `core/maps/dirty_layers.gd` (aucun nœud 3D, aucun autoload).
##
## Vérifie la table kind → couches, les fermetures de dépendances, la déduplication
## et surtout le **repli sûr** : une couche ou un kind inconnu doit toujours se
## résoudre en `["all"]` (rebuild complet), jamais en « rien » — une couche
## oubliée laisserait un objet fantôme jusqu'au prochain rebuild complet.
##
## PASS = `dirty_layers_test:PASS`.

const DirtyLayersScript := preload("res://scripts/core/maps/dirty_layers.gd")

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_constants()
	_test_known_kinds()
	_test_unknown_inputs()
	_test_closures()
	_test_union_and_sort()
	_test_consistency()
	_report()


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures.append(label if detail.is_empty() else "%s (%s)" % [label, detail])


## Égalité d'ensembles (l'ordre de `resolve` suit l'entrée, on compare en triant).
func _same_set(a: PackedStringArray, b: PackedStringArray) -> bool:
	if a.size() != b.size():
		return false
	for value in a:
		if not b.has(value):
			return false
	return true


func _test_constants() -> void:
	var all_layers: Array = DirtyLayersScript.ALL_LAYERS
	_check("ALL_LAYERS non vide", not all_layers.is_empty())
	var seen := {}
	for layer in all_layers:
		var name := str(layer)
		_check("couche connue " + name, DirtyLayersScript.is_known(name))
		_check("couche unique " + name, not seen.has(name))
		seen[name] = true
		_check("pas 'all' dans ALL_LAYERS", name != DirtyLayersScript.ALL)
	_check("all connu", DirtyLayersScript.is_known(DirtyLayersScript.ALL))
	_check("inconnu non connu", not DirtyLayersScript.is_known("bidon"))
	_check("all()", _same_set(DirtyLayersScript.all(), PackedStringArray(["all"])))
	_check("is_all(all)", DirtyLayersScript.is_all(DirtyLayersScript.all()))
	_check("is_all(vide) faux", not DirtyLayersScript.is_all(PackedStringArray()))


## Une entrée par kind du document : couches attendues par le design §4.
func _test_known_kinds() -> void:
	var expected := {
		"mesh": PackedStringArray(["meshes"]),
		"prop": PackedStringArray(["props"]),
		"wall": PackedStringArray(["walls", "meshes"]),
		"water": PackedStringArray(["water"]),
		"token": PackedStringArray(["tokens"]),
		"effect": PackedStringArray(["effects"]),
		"zone": PackedStringArray(["zones"]),
		"elevation": PackedStringArray(["elevations", "water"]),
		"light": PackedStringArray(["lights", "world_env"]),
		"marker": PackedStringArray(),
		"note": PackedStringArray(),
		"link": PackedStringArray(),
		"area": PackedStringArray(),
		"overlay": PackedStringArray(),
		"platform": PackedStringArray(),
	}
	for kind in expected.keys():
		var got: PackedStringArray = DirtyLayersScript.layers_for_kind(str(kind))
		_check("kind %s → %s (obtenu %s)" % [kind, expected[kind], got],
			_same_set(got, expected[kind]))
	# Le terrain n'est pas une couche simple : on vérifie la fermeture complète.
	var terrain: PackedStringArray = DirtyLayersScript.layers_for_kind("terrain")
	_check("kind terrain → 5 couches (obtenu %s)" % terrain, terrain.size() == 5)
	for layer in [DirtyLayersScript.GROUND, DirtyLayersScript.WATER,
			DirtyLayersScript.VEGETATION, DirtyLayersScript.PROPS, DirtyLayersScript.MESHES]:
		_check("kind terrain inclut " + str(layer), terrain.has(str(layer)))


func _test_unknown_inputs() -> void:
	var unknown_kind: PackedStringArray = DirtyLayersScript.layers_for_kind("kivivraimentpas")
	_check("kind inconnu → all", _same_set(unknown_kind, DirtyLayersScript.all()))
	var unknown_layer: PackedStringArray = DirtyLayersScript.resolve(PackedStringArray(["inconnue"]))
	_check("couche inconnue → all", _same_set(unknown_layer, DirtyLayersScript.all()))
	var mixed: PackedStringArray = DirtyLayersScript.resolve(
		PackedStringArray(["meshes", "inconnue"]))
	_check("mélange avec inconnue → all", _same_set(mixed, DirtyLayersScript.all()))
	var explicit_all: PackedStringArray = DirtyLayersScript.resolve(
		PackedStringArray(["meshes", "all"]))
	_check("mélange avec all → all", _same_set(explicit_all, DirtyLayersScript.all()))
	var empty: PackedStringArray = DirtyLayersScript.resolve(PackedStringArray())
	_check("resolve(vide) reste vide", empty.is_empty())
	_check("resolve(vide) n'est pas all", not DirtyLayersScript.is_all(empty))


func _test_closures() -> void:
	var terrain: PackedStringArray = DirtyLayersScript.of("terrain")
	_check("of(terrain) → 5", terrain.size() == 5, str(terrain))
	var elevation: PackedStringArray = DirtyLayersScript.of("elevation")
	_check("of(elevation) → elevations+water", _same_set(elevation,
		PackedStringArray(["elevations", "water"])), str(elevation))
	var light: PackedStringArray = DirtyLayersScript.of("light")
	_check("of(light) → lights+world_env", _same_set(light,
		PackedStringArray(["lights", "world_env"])), str(light))
	_check("of(water) → water", _same_set(DirtyLayersScript.of("water"),
		PackedStringArray(["water"])))
	_check("of(meshes) → meshes", _same_set(DirtyLayersScript.of("meshes"),
		PackedStringArray(["meshes"])))
	_check("of(props) → props", _same_set(DirtyLayersScript.of("props"),
		PackedStringArray(["props"])))
	_check("of(tokens) → tokens", _same_set(DirtyLayersScript.of("tokens"),
		PackedStringArray(["tokens"])))
	# Déduplication : une couche demandée deux fois n'apparaît qu'une fois.
	var dupes: PackedStringArray = DirtyLayersScript.resolve(
		PackedStringArray(["water", "water", "fog"]))
	_check("déduplication", _same_set(dupes, PackedStringArray(["water", "fog"])), str(dupes))
	# Dépendance transitivement visible : terrain + elevation → eau une seule fois.
	var combo: PackedStringArray = DirtyLayersScript.resolve(
		PackedStringArray(["terrain", "elevation"]))
	_check("terrain+elevation dédupliqué", combo.count("water") == 1, str(combo))


func _test_union_and_sort() -> void:
	var a: PackedStringArray = PackedStringArray(["meshes"])
	var b: PackedStringArray = PackedStringArray(["props", "walls"])
	var union: PackedStringArray = DirtyLayersScript.union(a, b)
	_check("union simple", _same_set(union, PackedStringArray(["meshes", "props", "walls"])),
		str(union))
	var with_all: PackedStringArray = DirtyLayersScript.union(
		DirtyLayersScript.all(), PackedStringArray(["meshes"]))
	_check("union avec all", _same_set(with_all, DirtyLayersScript.all()))
	var from_empty: PackedStringArray = DirtyLayersScript.union(
		PackedStringArray(), PackedStringArray(["terrain"]))
	_check("union depuis vide = fermeture", from_empty.size() == 5, str(from_empty))
	var union_unknown: PackedStringArray = DirtyLayersScript.union(
		PackedStringArray(["meshes"]), PackedStringArray(["inconnue"]))
	_check("union avec inconnue → all", _same_set(union_unknown, DirtyLayersScript.all()))
	var sorted: PackedStringArray = DirtyLayersScript.sorted_layers(
		PackedStringArray(["fog", "meshes", "ground"]))
	_check("ordre de reconstruction", sorted == PackedStringArray(["ground", "meshes", "fog"]),
		str(sorted))
	_check("describe lisible", DirtyLayersScript.describe(
		PackedStringArray(["meshes"])) == "[meshes]")
	_check("describe vide", DirtyLayersScript.describe(PackedStringArray()) == "[]")


## Test de cohérence (design §4) : aucune faute de frappe dans les tableaux —
## toutes les valeurs référencées sont des couches connues.
func _test_consistency() -> void:
	for kind in DirtyLayersScript.KIND_LAYERS.keys():
		var layers: PackedStringArray = DirtyLayersScript.layers_for_kind(str(kind))
		for layer in layers:
			_check("KIND_LAYERS[%s] → couche connue %s" % [kind, layer],
				DirtyLayersScript.is_known(str(layer)))
		if DirtyLayersScript.KIND_LAYERS[kind] is Array:
			_check("kind %s listé" % kind, true)
	for layer in DirtyLayersScript.CLOSURES.keys():
		var deps: Array = DirtyLayersScript.CLOSURES[layer]
		_check("fermeture %s non vide" % layer, not deps.is_empty())
		for dep in deps:
			_check("CLOSURES[%s] → %s connue" % [layer, dep],
				DirtyLayersScript.is_known(str(dep)))
	# Chaque couche du moteur doit avoir une fermeture explicite (soit elle-même).
	for layer in DirtyLayersScript.ALL_LAYERS:
		_check("fermeture pour %s" % layer, DirtyLayersScript.CLOSURES.has(str(layer)))


func _report() -> void:
	if _failures.is_empty():
		print("dirty_layers_test : %d vérifications" % _checks)
		print("dirty_layers_test:PASS")
		quit(0)
		return
	for failure in _failures:
		printerr("  FAIL ", failure)
	print("dirty_layers_test:FAIL (%d/%d)" % [_failures.size(), _checks])
	quit(1)
