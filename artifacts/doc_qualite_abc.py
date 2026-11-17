from pathlib import Path

p = Path('docs/RAPPORT_QUALITE_CS2.md')
s = p.read_text(encoding='utf-8')
anchor = '## Reste (pistes)'
assert anchor in s
section = """## Chantiers qualité des assets (A → B → C)

**A — Végétation en cartouches alpha (livré)** : `tools/blender/build_vegetation_cards.py`
+ `vegetation_cards.json` regénèrent roseaux, buisson, haie, nénuphars et bosquet
depuis les planches IA (alpha découpé, atlas 1024/2048, double face) : 4 à 6 tris
au lieu de 1 400–2 418, et **la silhouette peinte est retrouvée**. Le moteur
(`map_meshes_3d.gd`) détecte le matériau alpha-scissor et applique
`shaders/vegetation_card*.gdshader` (vent par sommet, variantes éclairée /
non éclairée) au lieu du matériau standard qui forçait le cull back. Test :
`vegetation_cards_test`.

**B — Rochers PBR d'origine (à faire)** : les GLB Tripo3D bruts
(`artifacts/tripo-review/rock-kit/rocher_*.glb`) ont la **même géométrie**
(973–1 036 tris) que les `bloc_rocheux_*` livrés, mais avec **3 textures 2048²
PBR** (albédo + rugosité/métal + normale). Restaurer ces textures (et la
normale) redonne le rendu Tripo sans coût géométrique.

**C — Bâti/décors HD + LOD (à faire)** : régénérer depuis les planches avec
`SIZE 160–256`, budget 6 000–12 000 tris, atlas 1024–2048 et contour conservé,
puis LOD (HD près / niveau actuel au loin). Le kit complet ne pèse que
191 072 tris aujourd'hui : la marge de performance est large.

""" + anchor
s = s.replace(anchor, section, 1)
p.write_text(s, encoding='utf-8')
print('RAPPORT_QUALITE mis à jour (A/B/C)')
