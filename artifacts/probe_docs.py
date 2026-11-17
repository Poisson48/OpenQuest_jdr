from pathlib import Path

s = Path('docs/MAP_EDITOR.md').read_text(encoding='utf-8')
for line in s.splitlines():
    if 'Navigation' in line and 'H' in line and line.startswith('| Navigation'):
        print(repr(line))

t = Path('docs/GUIDE_CARTE_25D.md').read_text(encoding='utf-8')
idx = t.find("Navigation 3D dans l'")
print(repr(t[idx - 2:idx + 260]))
idx2 = t.find("Navigation éditeur :")
print(repr(t[idx2 - 2:idx2 + 120]))
