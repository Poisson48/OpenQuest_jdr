from pathlib import Path

p = Path('game/scripts/maps/editor/map_editor_edit_ops.gd')
s = p.read_text(encoding='utf-8')

# 1) Reset systématique au début d'un press.
marker = 'func _on_pointer_pressed('
idx = s.find(marker)
assert idx != -1
brace = s.find(':', idx)
line_end = s.find('\n', brace)
head = s[:line_end + 1]
tail = s[line_end + 1:]
if '_live_incremental = false' not in tail[:200]:
    tail = '\t_ed._live_incremental = false\n' + tail
s = head + tail

# 2) Resize : le flag doit être posé AVANT `doc.set_live_fields` (sinon le
#    premier mouvement déclenche encore un rebuild complet).
old = '''		_ed.doc.set_live_fields(id, fields)
		_ed._live_incremental = true
		_ed._engine.set_element_live_fields(id, fields)
		return'''
new = '''		# Flag posé AVANT le changement du document : le premier mouvement de la
		# poignée ne déclenche pas non plus le rebuild complet des couches.
		_ed._live_incremental = true
		_ed.doc.set_live_fields(id, fields)
		_ed._engine.set_element_live_fields(id, fields)
		return'''
assert old in s, 'resize mesh introuvable'
s = s.replace(old, new, 1)

# 3) Rotate : idem, et flag remis à false pour les éléments non-mesh.
old = '''	var fields := {"display": {"rotation": rot}}
	_ed.doc.set_live_fields(id, fields)
	var elem: Dictionary = _ed.doc.get_element(id)
	if str(elem.get("kind", "")) == DocumentScript.KIND_MESH:
		_ed._live_incremental = true
		_ed._engine.set_element_live_fields(id, fields)'''
new = '''	var fields := {"display": {"rotation": rot}}
	var elem: Dictionary = _ed.doc.get_element(id)
	var is_mesh := str(elem.get("kind", "")) == DocumentScript.KIND_MESH
	_ed._live_incremental = is_mesh
	_ed.doc.set_live_fields(id, fields)
	if is_mesh:
		_ed._engine.set_element_live_fields(id, fields)'''
assert old in s, 'rotate introuvable'
s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8')
print('flag incrémental posé avant le doc change (resize/rotate)')
