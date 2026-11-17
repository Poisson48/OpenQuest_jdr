from pathlib import Path

# ---------------------------------------------------------------------------
# 1) map_water_3d : direction de courant par bassin + dérive lac calmée
# ---------------------------------------------------------------------------
p = Path('game/scripts/maps/map_layers/map_water_3d.gd')
s = p.read_text(encoding='utf-8')

old_const = '''## 0 = eau figée, 1 = vitesse brute (rapide). 0,10 = courant lisible et calme.
const RIVER_FLOW_VISUAL_SCALE := 0.10'''
new_const = '''## 0 = eau figée, 1 = vitesse brute (rapide). 0,10 = courant lisible et calme.
const RIVER_FLOW_VISUAL_SCALE := 0.10
## Lacs / plans d'eau polygonaux (canaux) : dérive du motif plus discrète
## encore. Un canal peut préciser sa direction via `flow_dir` ([x, y] en
## coordonnées monde normalisées) — sinon dérive historique (1, 0).
const LAKE_FLOW_VISUAL_SCALE := 0.18'''
assert old_const in s, 'constante rivière introuvable'
s = s.replace(old_const, new_const, 1)

old_lake = '''	var depth_data := _make_body_depth(level, max_depth, poly)
	var speed := float((body as Dictionary).get("flow_speed", 0.10))
	var mat := _make_body_material(depth_data["texture"],
		Vector2(1.0, 0.0), speed)
	_add_body_node(mesh, mat)'''
new_lake = '''	var depth_data := _make_body_depth(level, max_depth, poly)
	var speed := float((body as Dictionary).get("flow_speed", 0.10))
	# Direction de courant optionnelle (canaux) : coordonnées monde
	# normalisées, comme l'UV2 du shader. Défaut historique (1, 0).
	var flow_dir := Vector2(1.0, 0.0)
	var raw_dir = (body as Dictionary).get("flow_dir", null)
	if raw_dir is Array and (raw_dir as Array).size() >= 2:
		flow_dir = Vector2(float((raw_dir as Array)[0]), float((raw_dir as Array)[1]))
	var flow_strength := float((body as Dictionary).get("flow_strength", -1.0))
	var mat := _make_body_material(depth_data["texture"],
		flow_dir, speed, 0.0, Vector2.ZERO, flow_strength)
	_add_body_node(mesh, mat)'''
assert old_lake in s, 'bloc lac introuvable'
s = s.replace(old_lake, new_lake, 1)

old_sig = '''func _make_body_material(depth_texture: ImageTexture,
		flow_dir: Vector2, flow_speed: float,
		edge_softness: float = 0.0,
		ribbon_flow: Vector2 = Vector2.ZERO) -> ShaderMaterial:'''
new_sig = '''func _make_body_material(depth_texture: ImageTexture,
		flow_dir: Vector2, flow_speed: float,
		edge_softness: float = 0.0,
		ribbon_flow: Vector2 = Vector2.ZERO,
		flow_strength_override: float = -1.0) -> ShaderMaterial:'''
assert old_sig in s, 'signature matériau introuvable'
s = s.replace(old_sig, new_sig, 1)

old_strength = '''		flow_strength = 1.0'''
new_strength = '''		flow_strength = 1.0
	# Un canal (lac polygonal) peut demander une dérive plus marquée dans SA
	# direction, sans passer par les réglages du ruban de rivière.
	if flow_strength_override >= 0.0:
		flow_strength = clampf(flow_strength_override, 0.0, 1.0)'''
assert old_strength in s, 'flow_strength rivière introuvable'
s = s.replace(old_strength, new_strength, 1)

old_uniform = '''		# Dépendance VISUELLE calmée (le `flow_speed` des données est conservé).
		mat.set_shader_parameter("flow_visual_scale", RIVER_FLOW_VISUAL_SCALE)'''
new_uniform = '''		# Dépendance VISUELLE calmée (le `flow_speed` des données est conservé).
		mat.set_shader_parameter("flow_visual_scale", RIVER_FLOW_VISUAL_SCALE)
	else:
		# Lac / canal : dérive discrète (le courant d'un canal se lit, mais la
		# texture ne défile plus à toute vitesse sur toute la carte).
		mat.set_shader_parameter("flow_visual_scale", LAKE_FLOW_VISUAL_SCALE)'''
assert old_uniform in s, 'bloc uniformes rivière introuvable'
s = s.replace(old_uniform, new_uniform, 1)

p.write_text(s, encoding='utf-8')
print('map_water_3d : flow_dir par bassin + dérive lac calmée OK')

# ---------------------------------------------------------------------------
# 2) Cité au fil de l'eau : le canal coule le long du canal (nord-sud)
# ---------------------------------------------------------------------------
p = Path('game/scripts/debug/cite_eau_boot.gd')
s = p.read_text(encoding='utf-8')
old = '''		{
			"id": "canal", "kind": "lake", "level": WATER_LEVEL,
			"area": canal_poly,
		},'''
new = '''		{
			"id": "canal", "kind": "lake", "level": WATER_LEVEL,
			"area": canal_poly,
			# Courant LE LONG du canal (axe nord-sud = +Z monde → UV2 (0, 1)),
			# calme : la dérive visible est tempérée par le shader.
			"flow_dir": [0.0, 1.0], "flow_speed": 0.20, "flow_strength": 0.85,
		},'''
assert old in s, 'bassin canal introuvable'
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print('cite_eau : canal avec flow_dir nord-sud OK')

# ---------------------------------------------------------------------------
# 3) water_bodies_test : verrouille direction + vitesse calmée
# ---------------------------------------------------------------------------
p = Path('game/scripts/tests/water_bodies_test.gd')
s = p.read_text(encoding='utf-8')
old_run = '''	await _test_editor_lake_on_flat_ground()'''
new_run = '''	await _test_canal_flow_direction()
	await _test_editor_lake_on_flat_ground()'''
assert old_run in s, 'appel test introuvable'
s = s.replace(old_run, new_run, 1)

anchor = '''func _test_editor_lake_on_flat_ground() -> void:'''
test = '''## Canal : un lac polygonal peut porter une DIRECTION de courant (`flow_dir`,
## coordonnées monde normalisées) et une dérive calmée. Sans ça, le motif
## défilait en +X monde à vitesse de carte — perpendiculaire au canal.
func _test_canal_flow_direction() -> void:
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(0.0)
	var canal := {
		"id": "canal", "kind": "lake", "level": 0.2,
		"area": [[7, 4], [11, 4], [11, 10], [7, 10]],
		"flow_dir": [0.0, 1.0], "flow_speed": 0.20, "flow_strength": 0.85,
	}
	var lake := {
		"id": "lac", "kind": "lake", "level": 0.2,
		"area": [[2, 2], [5, 2], [5, 5], [2, 5]],
	}
	var water = WaterScript.new()
	get_root().add_child(water)
	water.configure(20, 14, 1.0, -1.0, heights, false, 1, 1.0, [], {}, [canal, lake])
	await process_frame
	_assert("canal_two_bodies", water.get_body_count() == 2,
		"n=%d" % water.get_body_count())
	if water.get_body_count() == 2:
		var canal_mat: ShaderMaterial = water._body_nodes[0].material_override
		var dir = canal_mat.get_shader_parameter("flow_dir")
		_assert("canal_flow_dir_along", dir is Vector2 and absf((dir as Vector2).x) < 0.01
			and absf((dir as Vector2).y - 1.0) < 0.01, "flow_dir=%s" % str(dir))
		_assert("canal_flow_speed_is_data",
			absf(float(canal_mat.get_shader_parameter("flow_speed")) - 0.20) < 0.01)
		_assert("canal_flow_strength", absf(float(
			canal_mat.get_shader_parameter("flow_strength")) - 0.85) < 0.01)
		var visual := float(canal_mat.get_shader_parameter("flow_visual_scale"))
		_assert("canal_flow_calmed", visual > 0.0 and visual <= 0.30,
			"visual_scale=%.2f" % visual)
		var lake_mat: ShaderMaterial = water._body_nodes[1].material_override
		_assert("lake_flow_dir_default", (lake_mat.get_shader_parameter("flow_dir") as Vector2)
			.is_equal_approx(Vector2(1.0, 0.0)))
		_assert("lake_flow_calmed",
			float(lake_mat.get_shader_parameter("flow_visual_scale")) <= 0.30)
	water.queue_free()
	await process_frame


'''
assert anchor in s, 'ancre test éditeur introuvable'
s = s.replace(anchor, test + anchor, 1)
p.write_text(s, encoding='utf-8')
print('water_bodies_test : test canal OK')
