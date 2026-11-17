from pathlib import Path

p = Path('game/scripts/tests/terrain_strata_test.gd')
s = p.read_text(encoding='utf-8')
old = '\n_assert("control_tile_size"'
new = '\n\t_assert("control_tile_size"'
assert old in s, 'ligne non indentée introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('indentation corrigée')
