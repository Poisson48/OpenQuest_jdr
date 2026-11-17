from pathlib import Path

p = Path('game/scripts/tests/editor_drag_perf_test.gd')
s = p.read_text(encoding='utf-8')

old = '	var t0 := Time.get_ticks_usec()'
new = (
    '	var t_sync := Time.get_ticks_usec()\n'
    '	editor._sync_engine()\n'
    '	var sync_ms := float(Time.get_ticks_usec() - t_sync) / 1000.0\n'
    '	print("  [perf] rebuild complet (ancien freeze) : %.0f ms" % sync_ms)\n'
    '	var t0 := Time.get_ticks_usec()'
)
assert old in s
s = s.replace(old, new, 1)

pairs = [
    ('move_avg', 'déplacement'),
    ('rotate_avg', 'rotation'),
    ('resize_avg', 'redimensionnement'),
]
for var, label in pairs:
    old = '	var ' + var + ' := float(Time.get_ticks_usec() - t0) / 10.0 / 1000000.0'
    new = old + '\n	print("  [perf] ' + label + ' : %.1f ms / mouvement" % (' + var + ' * 1000.0))'
    assert old in s, var
    s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8')
print('timings ajoutés')
