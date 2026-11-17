from pathlib import Path

p = Path('docs/MAP_EDITOR.md')
s = p.read_text(encoding='utf-8')
for line in s.splitlines():
    if line.startswith('| Navigation |') and 'H' in line and 'Clic-glisser' in line:
        print(repr(line))
