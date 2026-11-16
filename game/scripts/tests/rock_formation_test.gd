extends SceneTree

## Tests headless du planificateur de **formations rocheuses**
## (`procedural_rock_formation.gd`) :
##   • API (kinds, libellés, helpers de dimensions) ;
##   • assets réellement livrés (Tripo3D `bloc_rocheux_*`, cailloux, kit) ;
##   • déterminisme (même graine ⇒ plan identique, graines ≠ ⇒ plans ≠) ;
##   • aucun chevauchement d'empreinte au sol, assises contenues dans leur support ;
##   • tout dans la carte, budget borné/paramétrable, bornes de scale/élévation ;
##   • paramètres extrêmes (densité 0, longueur nulle, carte minuscule, kind inconnu).
##
## Pur : aucun rendu, aucun document d'éditeur. À lancer sans `--quit`.

const Formation := preload("res://scripts/maps/construction/procedural_rock_formation.gd")

const MAP_W := 40
const MAP_H := 30
const MAP_OPTIONS := {"map_width": MAP_W, "map_height": MAP_H}
const TOLERANCE := 0.02
const OVERLAP_EPSILON := 0.0001

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_api()
	_test_assets()
	_test_kinds_and_guarantees()
	_test_determinism()
	_test_budget()
	_test_extremes()
	_test_many_seeds()
	if _failed:
		print("rock_formation_test:FAIL")
		quit(1)
		return
	print("rock_formation_test:PASS")
	quit(0)

# ===========================================================================
# API et helpers
# ===========================================================================

func _test_api() -> void:
	var kinds: Array = Formation.kind_ids()
	_assert("kinds_count", kinds.size() == 3, "kinds=%s" % str(kinds))
	for kind in [Formation.KIND_AFFLEUREMENT, Formation.KIND_EBOUIS, Formation.KIND_CARRIERE]:
		_assert("kind_%s" % kind, kinds.has(kind))
		_assert("kind_label_%s" % kind, not Formation.kind_label(kind).is_empty())
		var budget: int = Formation.max_elements_for(kind, 1.0)
		_assert("budget_%s" % kind, budget >= 6 and budget <= Formation.MAX_ELEMENTS_HARD,
			"budget=%d" % budget)
		_assert("budget_density_%s" % kind,
			Formation.max_elements_for(kind, 2.0) >= budget)
	_assert("kind_label_unknown", Formation.kind_label("inconnu") == "inconnu")

func _test_assets() -> void:
	var names: Array = []
	names.append_array(Formation.TRIPO_ASSETS)
	names.append_array(Formation.PEBBLE_ASSETS)
	names.append_array(Formation.KIT_ROCK_ASSETS)
	names.append_array(Formation.VEGETATION_ASSETS)
	for name_variant in names:
		var name := str(name_variant)
		var path: String = Formation.asset_path(name)
		_assert("asset_exists_%s" % name, ResourceLoader.exists(path), path)
		var dims: Vector3 = Formation.asset_dims(name)
		_assert("asset_dims_%s" % name,
			dims.x > 0.05 and dims.y > 0.05 and dims.z > 0.05, "dims=%s" % str(dims))
		var footprint: Vector2 = Formation.asset_footprint(name)
		_assert("asset_footprint_%s" % name, footprint.x > 0.05 and footprint.y > 0.05)
		_assert("asset_rotated_%s" % name,
			Formation.rotated_footprint(name, 1.0, 45.0).length() > 0.0)
	# Valeurs attendues du manifeste / replis (contrôle de cohérence).
	var socle := Formation.asset_dims(Formation.TRIPO_SOCLE)
	_assert("socle_width", absf(socle.x - 1.857) < TOLERANCE, "width=%.3f" % socle.x)
	_assert("socle_height", absf(socle.y - 1.111) < TOLERANCE, "height=%.3f" % socle.y)
	var gravier := Formation.asset_dims(Formation.PEBBLE_GRAVIER)
	_assert("gravier_width", absf(gravier.x - 0.140) < TOLERANCE, "width=%.3f" % gravier.x)
	# La projection d'un carré tourné à 45° est plus large que le carré.
	var square := Formation.rotated_footprint(Formation.TRIPO_COURONNE, 1.0, 45.0)
	var axis := Formation.asset_footprint(Formation.TRIPO_COURONNE)
	_assert("rotated_footprint_conservative", square.x > axis.x * 0.99)

# ===========================================================================
# Les 3 kinds : génération, garanties géométriques et de style
# ===========================================================================

func _test_kinds_and_guarantees() -> void:
	var assets_seen: Dictionary = {}
	for kind in Formation.kind_ids():
		var plan: Dictionary = Formation.generate(kind, Vector2(9.0, 9.0),
			Vector2(1.0, 0.35), 8.0, 4711, 1.0, MAP_OPTIONS)
		_assert("valid_%s" % kind, bool(plan.get("valid", false)))
		var elements: Array = plan.get("elements", [])
		_assert("has_elements_%s" % kind, elements.size() > 0, "count=%d" % elements.size())
		_assert("count_matches_%s" % kind, int(plan.get("count", -1)) == elements.size())
		_assert("budget_respected_%s" % kind,
			elements.size() <= int(plan.get("budget", 0)))
		_assert("bounds_present_%s" % kind,
			(plan.get("bounds", Rect2()) as Rect2).has_area())
		_check_plan(kind, plan)
		for element_variant in elements:
			var element: Dictionary = element_variant
			assets_seen[Formation.asset_name(str(element.get("asset", "")))] = true
	# Mélange réel des trois familles : Tripo3D, cailloux procéduraux, kit.
	var tripo := 0
	var pebbles := 0
	var kit := 0
	for name_variant in assets_seen.keys():
		var name := str(name_variant)
		if Formation.TRIPO_ASSETS.has(name):
			tripo += 1
		elif Formation.PEBBLE_ASSETS.has(name):
			pebbles += 1
		elif Formation.KIT_ROCK_ASSETS.has(name):
			kit += 1
	_assert("mix_tripo", tripo >= 2, "tripo=%d" % tripo)
	_assert("mix_pebbles", pebbles >= 2, "pebbles=%d" % pebbles)
	_assert("mix_kit", kit >= 1, "kit=%d" % kit)

## Contrôles communs à tous les plans : bornes, chevauchements, assises.
func _check_plan(kind: String, plan: Dictionary) -> void:
	var elements: Array = plan.get("elements", [])
	var map_size: Vector2i = plan.get("map_size", Vector2i(MAP_W, MAP_H))
	var map_w := float(map_size.x)
	var map_h := float(map_size.y)
	var grounds: Array = []
	var elevated: Array = []
	for element_variant in elements:
		var element: Dictionary = element_variant
		var label := "%s/%s" % [kind, str(element.get("name", "?"))]
		# Champs prêts pour doc.add_element.
		for key in ["asset", "x", "y", "scale", "rotation", "elevation", "label", "w", "h"]:
			_assert("field_%s_%s" % [label, key], element.has(key))
		var asset := str(element.get("asset", ""))
		_assert("asset_res_%s" % label, ResourceLoader.exists(asset), asset)
		var scale_v := float(element.get("scale", 1.0))
		_assert("scale_bounds_%s" % label,
			scale_v >= Formation.MIN_SCALE and scale_v <= Formation.MAX_SCALE,
			"scale=%.3f" % scale_v)
		var elevation := float(element.get("elevation", 0.0))
		_assert("elevation_bounds_%s" % label,
			elevation >= Formation.MIN_ELEVATION and elevation <= Formation.MAX_ELEVATION,
			"elev=%.3f" % elevation)
		var rotation := float(element.get("rotation", 0.0))
		_assert("rotation_wrapped_%s" % label,
			rotation >= 0.0 and rotation < 360.0, "rot=%.1f" % rotation)
		var row := int(element.get("row", 0))
		_assert("row_bounds_%s" % label, row >= 0 and row < Formation.MAX_ROWS,
			"row=%d" % row)
		_assert("row_elevation_%s" % label,
			(row == 0 and elevation <= 0.001) or (row > 0 and elevation > 0.0),
			"row=%d elev=%.2f" % [row, elevation])
		# Empreinte stockée cohérente avec la projection recalculée.
		var recomputed := Formation.rotated_footprint(asset, scale_v, rotation)
		_assert("footprint_w_%s" % label,
			absf(float(element.get("w", 0.0)) - recomputed.x) < TOLERANCE)
		_assert("footprint_h_%s" % label,
			absf(float(element.get("h", 0.0)) - recomputed.y) < TOLERANCE)
		# Tout dans la carte.
		var rect: Rect2 = Formation.element_rect(element)
		_assert("in_map_%s" % label,
			rect.position.x >= -0.001 and rect.position.y >= -0.001
			and rect.end.x <= map_w + 0.001 and rect.end.y <= map_h + 0.001,
			"rect=%s" % str(rect))
		if elevation <= 0.001:
			grounds.append({"element": element, "rect": rect, "label": label})
		else:
			elevated.append({"element": element, "rect": rect, "label": label})
	# Aucun chevauchement entre éléments au sol.
	for i in range(grounds.size()):
		for j in range(i + 1, grounds.size()):
			var a: Dictionary = grounds[i]
			var b: Dictionary = grounds[j]
			var rect_a: Rect2 = a["rect"]
			var rect_b: Rect2 = b["rect"]
			var shrunk_a := rect_a.grow(-OVERLAP_EPSILON)
			var shrunk_b := rect_b.grow(-OVERLAP_EPSILON)
			_assert("no_overlap_%s_%s" % [a["label"], b["label"]],
				not shrunk_a.intersects(shrunk_b),
				"%s ∩ %s" % [str(rect_a), str(rect_b)])
	# Chaque assise haute repose sur une empreinte au sol.
	for elevated_variant in elevated:
		var item: Dictionary = elevated_variant
		var rect: Rect2 = item["rect"]
		var supported := false
		for ground_variant in grounds:
			var ground_rect: Rect2 = (ground_variant as Dictionary)["rect"]
			if ground_rect.grow(Formation.CLEARANCE).encloses(rect):
				supported = true
				break
		_assert("assise_supportee_%s" % item["label"], supported, str(rect))
	# Jamais plus de deux assises empilées (row 1 et 2), jamais un mur.
	var stacked := 0
	for element_variant in elements:
		if int((element_variant as Dictionary).get("row", 0)) > 0:
			stacked += 1
	_assert("assises_bornees_%s" % kind, stacked <= 4, "stacked=%d" % stacked)

# ===========================================================================
# Déterminisme
# ===========================================================================

func _test_determinism() -> void:
	for kind in Formation.kind_ids():
		var first: Dictionary = Formation.generate(kind, Vector2(7.0, 12.0),
			Vector2(0.8, -0.6), 7.5, 20261112, 1.0, MAP_OPTIONS)
		var second: Dictionary = Formation.generate(kind, Vector2(7.0, 12.0),
			Vector2(0.8, -0.6), 7.5, 20261112, 1.0, MAP_OPTIONS)
		_assert("deterministic_sig_%s" % kind,
			Formation.signature(first) == Formation.signature(second))
		var a: Array = first.get("elements", [])
		var b: Array = second.get("elements", [])
		_assert("deterministic_count_%s" % kind, a.size() == b.size())
		var same := true
		for i in range(mini(a.size(), b.size())):
			var ea: Dictionary = a[i]
			var eb: Dictionary = b[i]
			if not str(ea["asset"]) == str(eb["asset"]) \
					or not is_equal_approx(float(ea["x"]), float(eb["x"])) \
					or not is_equal_approx(float(ea["y"]), float(eb["y"])) \
					or not is_equal_approx(float(ea["rotation"]), float(eb["rotation"])) \
					or not is_equal_approx(float(ea["scale"]), float(eb["scale"])):
				same = false
				break
		_assert("deterministic_items_%s" % kind, same)
		var other: Dictionary = Formation.generate(kind, Vector2(7.0, 12.0),
			Vector2(0.8, -0.6), 7.5, 7, 1.0, MAP_OPTIONS)
		_assert("seed_changes_plan_%s" % kind,
			Formation.signature(other) != Formation.signature(first))

# ===========================================================================
# Budget paramétrable
# ===========================================================================

func _test_budget() -> void:
	for kind in Formation.kind_ids():
		var options := MAP_OPTIONS.duplicate()
		options["max_elements"] = 6
		var plan: Dictionary = Formation.generate(kind, Vector2(10.0, 10.0),
			Vector2(1.0, 0.0), 9.0, 99, 1.2, options)
		_check_plan(kind, plan)
		_assert("explicit_budget_%s" % kind,
			(plan.get("elements", []) as Array).size() <= 6,
			"count=%d" % (plan.get("elements", []) as Array).size())
		var dense: Dictionary = Formation.generate(kind, Vector2(10.0, 10.0),
			Vector2(1.0, 0.0), 9.0, 99, 2.0, MAP_OPTIONS)
		var hard: int = Formation.max_elements_for(kind, 2.0)
		_assert("hard_budget_%s" % kind,
			(dense.get("elements", []) as Array).size() <= hard,
			"count=%d hard=%d" % [(dense.get("elements", []) as Array).size(), hard])

# ===========================================================================
# Paramètres extrêmes (jamais de crash)
# ===========================================================================

func _test_extremes() -> void:
	for kind in Formation.kind_ids():
		var zero: Dictionary = Formation.generate(kind, Vector2(5.0, 5.0),
			Vector2.RIGHT, 6.0, 3, 0.0, MAP_OPTIONS)
		_assert("density_zero_valid_%s" % kind, bool(zero.get("valid", false)))
		_assert("density_zero_empty_%s" % kind,
			(zero.get("elements", []) as Array).is_empty())
		_assert("tiny_length_empty_%s" % kind,
			(Formation.generate(kind, Vector2(5.0, 5.0), Vector2.RIGHT, 0.1, 3, 1.0,
				MAP_OPTIONS).get("elements", []) as Array).is_empty())
		var tiny_options := {"map_width": 8, "map_height": 8}
		var tiny: Dictionary = Formation.generate(kind, Vector2(4.0, 4.0),
			Vector2(1.0, 1.0), 8.0, 5, 1.0, tiny_options)
		_check_plan(kind, tiny)
		var zero_dir: Dictionary = Formation.generate(kind, Vector2(6.0, 6.0),
			Vector2.ZERO, 5.0, 11, 1.0, MAP_OPTIONS)
		_assert("zero_direction_valid_%s" % kind, bool(zero_dir.get("valid", false)))
		_check_plan(kind, zero_dir)
	var unknown: Dictionary = Formation.generate("inconnu", Vector2(4.0, 4.0),
		Vector2.RIGHT, 5.0, 1, 1.0, MAP_OPTIONS)
	_assert("unknown_kind_invalid", not bool(unknown.get("valid", true)))
	_assert("unknown_kind_empty", (unknown.get("elements", []) as Array).is_empty())

# ===========================================================================
# Robustesse sur de nombreuses graines
# ===========================================================================

func _test_many_seeds() -> void:
	for kind in Formation.kind_ids():
		for seed in range(20):
			var origin := Vector2(6.0 + float(seed % 4) * 3.0, 6.0 + float(seed % 5) * 2.0)
			var direction := Vector2(cos(float(seed) * 0.7), sin(float(seed) * 0.7))
			var length := 3.0 + float(seed % 7)
			var plan: Dictionary = Formation.generate(kind, origin, direction, length,
				seed * 131 + 17, 1.0, MAP_OPTIONS)
			_assert("seed_valid_%s_%d" % [kind, seed], bool(plan.get("valid", false)))
			_check_plan(kind, plan)
			var again: Dictionary = Formation.generate(kind, origin, direction, length,
				seed * 131 + 17, 1.0, MAP_OPTIONS)
			_assert("seed_deterministic_%s_%d" % [kind, seed],
				Formation.signature(plan) == Formation.signature(again))

func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [label, detail])
