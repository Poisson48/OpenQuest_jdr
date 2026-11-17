from pathlib import Path

new_section = """### 1.7 Végétation en cartes alpha (A — livré)

Le pipeline `reference_hull.py` reconstruit un volume d'intersection de
silhouettes sur une grille **64³** puis le décime (`target = 700..2150` tris) et
cuit la texture par îlots de 18 px par face : les feuilles fines, les plumes et
les fleurs ne survivent pas (roseaux livrés = tas de facettes olive, 2 418 tris,
atlas 630²). La méthode correcte pour la végétation est celle des jeux
(Cities: Skylines II) : des **cartouches découpés par l'alpha**.

`tools/blender/build_vegetation_cards.py` (+ `vegetation_cards.json`) lit les
planches de référence IA (vues RGBA), nettoie le halo de détourage, packe les
vues en atlas et écrit des GLB de quads croisés alpha-testés double face :

| Asset | Avant (volume décimé) | Après (cartouches) |
|---|---|---|
| roseaux | 2 418 tris, atlas 630² | 6 tris, atlas 2048×1024 |
| buisson | 1 400 tris | 6 tris |
| haie | 1 400 tris | 4 tris |
| nénuphars | 1 400 tris | 4 tris |
| bosquet | 2 248 tris | 6 tris |

Côté jeu (`map_meshes_3d.gd` + `shaders/vegetation_card*.gdshader`) : détection
du matériau alpha-scissor, **double face conservée**, **balancement au vent**
par sommet (pied planté, cime qui ondule), variantes éclairée (`cinema`) et non
éclairée (`classique`). Vignettes de bibliothèque régénérées depuis les planches,
manifeste mis à jour. Tests : `vegetation_cards_test` ; captures :
`demo_riviere_s*.png`, `cite_*`.

Reste : variations d'instances/miroir (déjà partiel via cartouches), feuillages
d'arbres (hybride tronc 3D + cartouches), puis B (rochers PBR) et C (bâti HD + LOD)."""

p = Path('docs/RAPPORT_SESSION_CS2_CITE.md')
s = p.read_text(encoding='utf-8')
start = s.find('### 1.7 ')
end = s.find('\n---\n', start)
assert start != -1 and end != -1, 'section 1.7 introuvable'
s = s[:start] + new_section + s[end:]
p.write_text(s, encoding='utf-8')
print('RAPPORT_SESSION 1.7 mis à jour')
