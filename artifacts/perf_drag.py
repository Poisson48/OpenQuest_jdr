from pathlib import Path

# ===========================================================================
# 1) map_meshes_3d : mise à jour LIVE de la transform d'un objet (sans rebuild)
# ===========================================================================
p = Path('game/scripts/maps/map_layers/map_meshes_3d.gd')
s = p.read_text(encoding='utf-8')
anchor = '''## Premier descendant portant le meta demandé (null si absent).'''
assert anchor in s, 'ancre set_mesh_position introuvable'
new_func = '''## Met à jour la transform d'un objet 3D **sans reconstruire la scène**
## (drag live : déplacement, rotation, redimensionnement). `fields` reprend les
## clés du document (x, y, w, h, sizeX/Y/Z, display…). Évite le rebuild complet
## des couches à chaque mouvement de souris (freeze d'environ 1 s avec le kit HD).
func set_mesh_fields(mesh_id: String, fields: Dictionary) -> void:
	if not _nodes.has(mesh_id):
		return
	var node: Node3D = _nodes[mesh_id]
	var entry: Dictionary = _mesh_entries.get(mesh_id, {})
	if entry.is_empty():
		return
	entry = entry.duplicate()
	for key in fields:
		if key == "display" and fields[key] is Dictionary:
			var display: Dictionary = (entry.get("display", {}) as Dictionary).duplicate()
			for dkey in (fields[key] as Dictionary):
				display[dkey] = (fields[key] as Dictionary)[dkey]
			entry["display"] = display
		else:
			entry[key] = fields[key]
	_mesh_entries[mesh_id] = entry
	if _is_bridge(str(entry.get("asset", ""))):
		update_bridge(entry)
		return
	_place_root(node, entry)
	var shadow := _find_child_with_meta(node, "contact_shadow")
	if shadow is Node3D:
		_repose_contact_shadow(node, shadow as Node3D, _is_inclined(entry))


''' + anchor
s = s.replace(anchor, new_func, 1)
p.write_text(s, encoding='utf-8')
print('map_meshes_3d.set_mesh_fields ajouté')

# ===========================================================================
# 2) engine : relais de la mise à jour live
# ===========================================================================
p = Path('game/scripts/maps/complex_map_engine_3d.gd')
s = p.read_text(encoding='utf-8')
anchor = '''func set_element_light_radius(element_id: String, radius_cells: float) -> void:'''
assert anchor in s, 'ancre light radius introuvable'
new = '''## Met à jour x/y/rotation/échelle d'un élément 3D **sans reconstruire** la
## scène (poignées de rotation/redimensionnement en drag live).
func set_element_live_fields(element_id: String, fields: Dictionary) -> void:
	if _meshes_layer and _meshes_layer.has_method("set_mesh_fields"):
		_meshes_layer.set_mesh_fields(element_id, fields)
	if _props_layer and _props_layer.has_method("set_prop_fields"):
		_props_layer.set_prop_fields(element_id, fields)


''' + anchor
s = s.replace(anchor, new, 1)
p.write_text(s, encoding='utf-8')
print('engine.set_element_live_fields ajouté')

# ===========================================================================
# 3) edit_ops : appliquer les mises à jour incrémentales pendant le drag
# ===========================================================================
p = Path('game/scripts/maps/editor/map_editor_edit_ops.gd')
s = p.read_text(encoding='utf-8')

# 3a) start move : mode incrémental activé (move = toujours incrémental).
old = '''func _start_move_drag(ids: Array) -> void:
	_ed._press_mode = "move"
	_ed._drag_ids = ids.duplicate()'''
new = '''func _start_move_drag(ids: Array) -> void:
	_ed._press_mode = "move"
	# Le déplacement met à jour les nœuds 3D de façon incrémentale : aucun
	# rebuild de couche pendant le drag (plus de freeze d'une seconde).
	_ed._live_incremental = true
	_ed._drag_ids = ids.duplicate()'''
assert old in s, 'start_move_drag introuvable'
s = s.replace(old, new, 1)

# 3b) resize mesh : transform incrémentale (échelle).
old = '''		_ed.doc.set_live_fields(id, fields)
		return
	if str(resized_elem.get("kind", "")) == DocumentScript.KIND_LIGHT:'''
new = '''		_ed.doc.set_live_fields(id, fields)
		_ed._live_incremental = true
		_ed._engine.set_element_live_fields(id, fields)
		return
	if str(resized_elem.get("kind", "")) == DocumentScript.KIND_LIGHT:'''
assert old in s, 'resize mesh introuvable'
s = s.replace(old, new, 1)

# 3c) rotate : transform incrémentale (lacet).
old = '''	_ed.doc.set_live_fields(id, {"display": {"rotation": rot}})'''
new = '''	var fields := {"display": {"rotation": rot}}
	_ed.doc.set_live_fields(id, fields)
	var elem: Dictionary = _ed.doc.get_element(id)
	if str(elem.get("kind", "")) == DocumentScript.KIND_MESH:
		_ed._live_incremental = true
		_ed._engine.set_element_live_fields(id, fields)'''
assert old in s, 'rotate introuvable'
s = s.replace(old, new, 1)

# 3d) reset du mode incrémental au press (avant toute opération live).
old = '''	_ed._press_mode = "none"'''
first_press_assign = s.find('func _on_pointer_pressed')
assert first_press_assign != -1, 'press handler introuvable'
segment = s[first_press_assign:first_press_assign + 4000]
if '_live_incremental = false' not in segment:
    segment = segment.replace('	_ed._press_mode = "none"',
                              '	_ed._press_mode = "none"\n	_ed._live_incremental = false', 1)
    s = s[:first_press_assign] + segment + s[first_press_assign + 4000:]
p.write_text(s, encoding='utf-8')
print('edit_ops : resize/rotate incrémentaux')

# ===========================================================================
# 4) editor : pas de rebuild couches ni de save pendant un drag incrémental
# ===========================================================================
p = Path('game/scripts/maps/map_complex_editor.gd')
s = p.read_text(encoding='utf-8')
old = '''	if reason in ["undo", "redo", "meta", "fog", "tiles", "order", "light_reveal", "modify", "commit", "add", "remove"]:
		_sync_engine()'''
new = '''	# Drag live incrémental (move/resize/rotate) : les nœuds 3D sont déjà mis à
	# jour par le moteur, on ne reconstruit PAS les couches à chaque mouvement
	# (c'était le freeze d'environ 1 s sur une carte remplie d'assets HD).
	var live_incremental := _press_mode in ["move", "resize", "rotate"] and _live_incremental
	if reason in ["undo", "redo", "meta", "fog", "tiles", "order", "light_reveal", "modify", "commit", "add", "remove"]:
		if not (live_incremental and reason == "modify"):
			_sync_engine()'''
assert old in s, 'doc_changed sync introuvable'
s = s.replace(old, new, 1)

old_save = '''	if _save_policy == SAVE_ON_CHANGE and doc.is_dirty() and reason != "load":
		save_now()'''
new_save = '''	if _save_policy == SAVE_ON_CHANGE and doc.is_dirty() and reason != "load" \\
			and not live_incremental:
		save_now()'''
assert old_save in s, 'save_on_change introuvable'
s = s.replace(old_save, new_save, 1)

# Déclaration de l'état.
old_var = '''var _drag_ids: Array = []'''
new_var = '''var _drag_ids: Array = []
## Vrai quand le drag live met à jour les nœuds 3D de façon incrémentale
## (déplacement/rotation/redimensionnement d'objets) : on saute alors le rebuild
## complet des couches dans `_on_doc_changed`.
var _live_incremental: bool = false'''
assert old_var in s, 'drag_ids introuvable'
s = s.replace(old_var, new_var, 1)
p.write_text(s, encoding='utf-8')
print('editor : skip du rebuild pendant le drag incrémental')
