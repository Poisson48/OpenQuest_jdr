from pathlib import Path

p = Path('game/scripts/tests/terrain_strata_test.gd')
s = p.read_text(encoding='utf-8')
old = '_assert("control_tile_size", is_equal_approx(_param(mat, "tile_world_size"), 2.0))'
new = ('# Passe netteté CS2 : tuile 1,75 case (au lieu de 2) + micro-détail 0,38.\n'
       '_assert("control_tile_size", is_equal_approx(_param(mat, "tile_world_size"), 1.75))')
assert old in s, 'assertion tile introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('terrain_strata_test : tuile 1,75 attendue')
