from pathlib import Path

p = Path('docs/MAP_EDITOR.md')
s = p.read_text(encoding='utf-8')
old = "| Navigation | \u270b Navigation | `H` | Clic-glisser : déplacer la vue (aussi : `Maj`+clic milieu, ou `Espace` maintenu) · **clic milieu ou clic droit glissé : orbite 3D libre** · `Maj`+clic droit/milieu : déplacer la vue · molette : zoom · bouton **\U0001F9ED** : réinitialiser l'orbite |"
new = "| Navigation | \u270b Navigation | `H` | Clic-glisser (ou **clic droit glissé**) : **déplacer la vue — le décor saisi reste collé au curseur** · **`Maj`+clic droit ou clic milieu : orbite 3D libre** · `Maj`+clic milieu : déplacer · `Espace` maintenu : pan temporaire · molette : zoom · bouton **\U0001F9ED** : réinitialiser l'orbite |"
assert old in s, 'MAP_EDITOR ligne navigation introuvable'
p.write_text(s.replace(old, new), encoding='utf-8')

g = Path('docs/GUIDE_CARTE_25D.md')
t = g.read_text(encoding='utf-8')
old2 = "- **Navigation 3D dans l'éditeur** : molette = zoom · **clic milieu ou clic droit\n  glissé = orbite libre** autour du point visé · **Maj + clic milieu/droit =\n  déplacer** la vue · bouton **\U0001F9ED** = revenir à l'angle de la carte. Un clic\n  droit sans glisser ouvre le menu contextuel."
new2 = "- **Navigation 3D dans l'éditeur** : molette = zoom · **clic droit glissé = déplacer la vue** (le décor saisi reste collé au curseur, quel que soit l'angle) · **Maj + clic droit = orbite libre** autour du point visé · **clic milieu = orbite**, **Maj + clic milieu = déplacer** · bouton **\U0001F9ED** = revenir à l'angle de la carte. Un clic droit sans glisser ouvre le menu contextuel."
assert old2 in t, 'GUIDE navigation introuvable'
t = t.replace(old2, new2)
old3 = "- Navigation éditeur : **clic droit glissé = déplacer la vue**, `Maj` + clic\n  droit = orbite, molette = zoom."
new3 = "- Navigation éditeur : **clic droit glissé = déplacer la vue** (suivi 1:1 du\n  curseur), `Maj` + clic droit = orbite, molette = zoom."
assert old3 in t, 'GUIDE raccourci introuvable'
t = t.replace(old3, new3)
g.write_text(t, encoding='utf-8')
print('docs navigation OK')
