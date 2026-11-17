from pathlib import Path

# ===========================================================================
# 1) ToolsScript : Rivière et Lac deviennent des outils à part entière
# ===========================================================================
p = Path('game/scripts/maps/editor/map_editor_tools.gd')
s = p.read_text(encoding='utf-8')
old = 'const WATER_PAINT := "water_paint"'
new = ('const WATER_PAINT := "water_paint"\n'
       '## Variantes explicites de l\'outil eau (la palette les expose comme des\n'
       '## outils distincts : l\'eau était introuvable pour beaucoup d\'utilisateurs\n'
       '## car rivière/lac n\'étaient que des entrées du menu « Mode »).\n'
       'const WATER_RIVER := "water_river"\n'
       'const WATER_LAKE := "water_lake"')
assert old in s, 'constante eau introuvable'
s = s.replace(old, new, 1)

old_def = '''	{
		"id": WATER_PAINT, "icon": "💧", "label": "Peindre l'eau", "shortcut": "", "group": "terrain",'''
new_def = '''	{
		"id": WATER_RIVER, "icon": "🌊", "label": "Rivière (tracé)", "shortcut": "", "group": "water",
		"hint": "Clic-glisser : tracez la rivière ; les dénivelés deviennent des cascades. Le lit est creusé, le sens du tracé = sens du courant.",
	},
	{
		"id": WATER_LAKE, "icon": "🏞", "label": "Lac / mare", "shortcut": "", "group": "water",
		"hint": "Cliquez-glissez un rectangle : le bassin est creusé et rempli jusqu'à son niveau. Molette : niveau d'eau.",
	},
	{
		"id": WATER_PAINT, "icon": "💧", "label": "Peindre l'eau", "shortcut": "", "group": "water",'''
assert old_def in s, 'définition eau introuvable'
s = s.replace(old_def, new_def, 1)
p.write_text(s, encoding='utf-8')
print('ToolsScript : WATER_RIVER / WATER_LAKE ajoutés')

# ===========================================================================
# 2) Éditeur : alias d'outils + groupe « Eau » dans la palette
# ===========================================================================
p = Path('game/scripts/maps/map_complex_editor.gd')
s = p.read_text(encoding='utf-8')

old = '''		groups.append(_group_def("Terrain", [ToolsScript.PAINT, ToolsScript.GROUND_MATERIAL, ToolsScript.TERRAIN_HEIGHT, ToolsScript.WATER_PAINT]))'''
new = '''		groups.append(_group_def("Terrain", [ToolsScript.PAINT, ToolsScript.GROUND_MATERIAL, ToolsScript.TERRAIN_HEIGHT]))
		groups.append(_group_def("Eau", [ToolsScript.WATER_RIVER, ToolsScript.WATER_LAKE, ToolsScript.WATER_PAINT]))'''
assert old in s, 'groupe Terrain introuvable'
s = s.replace(old, new, 1)

old_set = '''func _set_tool(tool_id: String) -> void:
	var changed := tool_id != _tool
	_tool = tool_id
	if changed:
		_palette_opts = tool_id not in [ToolsScript.SELECT, ToolsScript.PAN]
	if _palette_v2 != null:
		_palette_v2.set_active(tool_id)'''
new_set = '''func _set_tool(tool_id: String) -> void:
	# Rivière / Lac sont des variantes explicites de l'outil Eau : elles restent
	# des outils de la palette (découvrables), mais partagent le même outil
	# moteur `water_paint` avec le mode correspondant.
	var previous_active := _active_tool_id()
	if tool_id == ToolsScript.WATER_RIVER:
		_water_mode = "river"
		tool_id = ToolsScript.WATER_PAINT
	elif tool_id == ToolsScript.WATER_LAKE:
		_water_mode = "lake"
		tool_id = ToolsScript.WATER_PAINT
	elif tool_id == ToolsScript.WATER_PAINT:
		_water_mode = "paint"
	var changed := tool_id != _tool or previous_active != _active_water_tool_id()
	_tool = tool_id
	if changed:
		_palette_opts = tool_id not in [ToolsScript.SELECT, ToolsScript.PAN]
	if _palette_v2 != null:
		_palette_v2.set_active(_active_water_tool_id())'''
assert old_set in s, 'set_tool introuvable'
s = s.replace(old_set, new_set, 1)

# Helpers : identifiant actif réel (variant eau selon le mode).
anchor = '''## Fondu enchaîné de la barre d'options au changement d'outil (100 ms).'''
helper = '''## Identifiant de l'outil « réel » (Rivière/Lac sont des variantes de l'eau).
func _active_water_tool_id() -> String:
	if _tool != ToolsScript.WATER_PAINT:
		return _tool
	match _water_mode:
		"river":
			return ToolsScript.WATER_RIVER
		"lake":
			return ToolsScript.WATER_LAKE
	return ToolsScript.WATER_PAINT

## Identifiant actif affiché (préfixe pour les comparaisons de changement).
func _active_tool_id() -> String:
	return _active_water_tool_id()

## Le menu « Mode » de l'outil eau a changé : rafraîchit le bouton actif de la
## palette (Rivière/Lac/Peindre) en plus des options.
func refresh_water_tool_active() -> void:
	if _palette_v2 != null:
		_palette_v2.set_active(_active_water_tool_id())
	_rebuild_tool_options()


''' + anchor
assert anchor in s, 'ancre fade introuvable'
s = s.replace(anchor, helper, 1)
p.write_text(s, encoding='utf-8')
print('éditeur : alias eau + groupe Eau + bouton actif synchronisé')

# ===========================================================================
# 3) Menu « Mode » : met aussi à jour la palette
# ===========================================================================
p = Path('game/scripts/maps/editor/map_editor_tool_options.gd')
s = p.read_text(encoding='utf-8')
old = '''		water_opt.item_selected.connect(func(index):
			_ed._water_mode = str(water_opt.get_item_metadata(index))
			_ed._rebuild_tool_options()
		)'''
new = '''		water_opt.item_selected.connect(func(index):
			_ed._water_mode = str(water_opt.get_item_metadata(index))
			# Le bouton actif de la palette suit le mode (Rivière / Lac / Peindre).
			_ed.refresh_water_tool_active()
		)'''
assert old in s, 'callback mode introuvable'
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print('tool_options : mode eau synchronise la palette')
