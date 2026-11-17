from pathlib import Path

p = Path('game/scripts/maps/map_layers/map_water_3d.gd')
s = p.read_text(encoding='utf-8')

old = '''## Lacs / plans d'eau polygonaux (canaux) : dérive du motif plus discrète
## encore. Un canal peut préciser sa direction via `flow_dir` ([x, y] en
## coordonnées monde normalisées) — sinon dérive historique (1, 0).
const LAKE_FLOW_VISUAL_SCALE := 0.18'''
new = '''## Canaux : bassin polygonal AVEC `flow_dir` déclaré — le courant se lit, mais
## la dérive reste tempérée (0,18 du `flow_speed` des données).
const CANAL_FLOW_VISUAL_SCALE := 0.18
## Lacs : c'est un lac, l'eau doit à peine bouger. Dépendance du motif quasi
## nulle (0,025 du `flow_speed`) : un frémissement, pas un courant. La houle et
## les scintillements continuent d'animer la surface par ailleurs.
const LAKE_FLOW_VISUAL_SCALE := 0.025'''
assert old in s, 'constantes lac/canal introuvables'
s = s.replace(old, new, 1)

old_call = '''	var flow_strength := float((body as Dictionary).get("flow_strength", -1.0))
	var mat := _make_body_material(depth_data["texture"],
		flow_dir, speed, 0.0, Vector2.ZERO, flow_strength)'''
new_call = '''	var flow_strength := float((body as Dictionary).get("flow_strength", -1.0))
	# Échelle de dérive visuelle : un canal (flow_dir explicite) peut se lire,
	# un lac doit à peine bouger. Surchargeable par bassin (`flow_visual_scale`).
	var visual_scale := float((body as Dictionary).get("flow_visual_scale", -1.0))
	if visual_scale < 0.0:
		var has_dir := raw_dir is Array and (raw_dir as Array).size() >= 2
		visual_scale = CANAL_FLOW_VISUAL_SCALE if has_dir else LAKE_FLOW_VISUAL_SCALE
	var mat := _make_body_material(depth_data["texture"],
		flow_dir, speed, 0.0, Vector2.ZERO, flow_strength, visual_scale)'''
assert old_call in s, 'appel matériau lac introuvable'
s = s.replace(old_call, new_call, 1)

old_sig = '''		ribbon_flow: Vector2 = Vector2.ZERO,
		flow_strength_override: float = -1.0) -> ShaderMaterial:'''
new_sig = '''		ribbon_flow: Vector2 = Vector2.ZERO,
		flow_strength_override: float = -1.0,
		flow_visual_override: float = -1.0) -> ShaderMaterial:'''
assert old_sig in s, 'signature matériau introuvable'
s = s.replace(old_sig, new_sig, 1)

old_else = '''	else:
		# Lac / canal : dérive discrète (le courant d'un canal se lit, mais la
		# texture ne défile plus à toute vitesse sur toute la carte).
		mat.set_shader_parameter("flow_visual_scale", LAKE_FLOW_VISUAL_SCALE)'''
new_else = '''	else:
		# Lac / canal : dérive discrète (un canal se lit, un lac frémit à peine).
		mat.set_shader_parameter("flow_visual_scale",
			flow_visual_override if flow_visual_override >= 0.0 else LAKE_FLOW_VISUAL_SCALE)'''
assert old_else in s, 'else uniforme lac introuvable'
s = s.replace(old_else, new_else, 1)

p.write_text(s, encoding='utf-8')
print('lac : dérive quasi nulle (0,025) ; canal conservé (0,18)')

# Test : verrouille « lac à peine mobile, canal lisible ».
p = Path('game/scripts/tests/water_bodies_test.gd')
s = p.read_text(encoding='utf-8')
old_test = '''		var visual := float(canal_mat.get_shader_parameter("flow_visual_scale"))
		_assert("canal_flow_calmed", visual > 0.0 and visual <= 0.30,
			"visual_scale=%.2f" % visual)
		var lake_mat: ShaderMaterial = water._body_nodes[1].material_override
		_assert("lake_flow_dir_default", (lake_mat.get_shader_parameter("flow_dir") as Vector2)
			.is_equal_approx(Vector2(1.0, 0.0)))
		_assert("lake_flow_calmed",
			float(lake_mat.get_shader_parameter("flow_visual_scale")) <= 0.30)'''
new_test = '''		var visual := float(canal_mat.get_shader_parameter("flow_visual_scale"))
		_assert("canal_flow_readable", absf(visual - 0.18) < 0.02,
			"visual_scale=%.3f" % visual)
		var lake_mat: ShaderMaterial = water._body_nodes[1].material_override
		_assert("lake_flow_dir_default", (lake_mat.get_shader_parameter("flow_dir") as Vector2)
			.is_equal_approx(Vector2(1.0, 0.0)))
		var lake_visual := float(lake_mat.get_shader_parameter("flow_visual_scale"))
		_assert("lake_barely_moves", lake_visual >= 0.0 and lake_visual <= 0.05,
			"visual_scale=%.3f" % lake_visual)'''
assert old_test in s, 'assertions lac/canal introuvables'
s = s.replace(old_test, new_test, 1)
p.write_text(s, encoding='utf-8')
print('water_bodies_test : lac quasi immobile, canal lisible')
