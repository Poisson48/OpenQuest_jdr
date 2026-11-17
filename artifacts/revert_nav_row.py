from pathlib import Path

p = Path('docs/MAP_EDITOR.md')
s = p.read_text(encoding='utf-8')
new = "| Navigation | \u270b Navigation | `H` | Clic-glisser (ou **clic droit glissé**) : **déplacer la vue — le décor saisi reste collé au curseur** · **`Maj`+clic droit ou clic milieu : orbite 3D libre** · `Maj`+clic milieu : déplacer · `Espace` maintenu : pan temporaire · molette : zoom · bouton **\U0001F9ED** : réinitialiser l'orbite |"
old = "| Navigation | \u270b Navigation | `H` | Clic-glisser : déplacer la vue (aussi : `Maj`+clic milieu, ou `Espace` maintenu) · **clic milieu ou clic droit glissé : orbite 3D libre** · `Maj`+clic droit/milieu : déplacer la vue · molette : zoom · bouton **\U0001F9ED** : réinitialiser l'orbite |"
assert new in s, 'ligne modifiée introuvable'
p.write_text(s.replace(new, old, 1), encoding='utf-8')
print('MAP_EDITOR: ma ligne retirée (modifs de autre session préservées)')
