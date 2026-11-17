from pathlib import Path

p = Path('game/scripts/tests/pan_cursor_tracking_test.gd')
s = p.read_text(encoding='utf-8')
# Section 1 : renomme les variables locales pour ne pas masquer celles des
# sections suivantes (GDScript interdit la redéclaration dans le même scope).
s = s.replace('var motion := InputEventMouseMotion.new()', 'var drag_motion := InputEventMouseMotion.new()', 1)
s = s.replace('motion.position = move_pos', 'drag_motion.position = move_pos', 1)
s = s.replace('motion.relative = move_pos - threshold_pos', 'drag_motion.relative = move_pos - threshold_pos', 1)
s = s.replace('engine._editor_gui_input(motion)', 'engine._editor_gui_input(drag_motion)', 1)
s = s.replace('var release := InputEventMouseButton.new()', 'var drag_release := InputEventMouseButton.new()', 1)
s = s.replace('release.button_index = MOUSE_BUTTON_RIGHT', 'drag_release.button_index = MOUSE_BUTTON_RIGHT', 1)
s = s.replace('release.pressed = false', 'drag_release.pressed = false', 1)
s = s.replace('release.position = move_pos', 'drag_release.position = move_pos', 1)
s = s.replace('engine._editor_gui_input(release)', 'engine._editor_gui_input(drag_release)', 1)
p.write_text(s, encoding='utf-8')
print('section 1 : variables renommées (drag_motion/drag_release)')
