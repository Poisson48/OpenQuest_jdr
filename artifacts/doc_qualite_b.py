from pathlib import Path

p = Path('docs/RAPPORT_QUALITE_CS2.md')
s = p.read_text(encoding='utf-8')
old = """**B — Rochers PBR d'origine (à faire)** : les GLB Tripo3D bruts
(`artifacts/tripo-review/rock-kit/rocher_*.glb`) ont la **même géométrie**
(973–1 036 tris) que les `bloc_rocheux_*` livrés, mais avec **3 textures 2048²
PBR** (albédo + rugosité/métal + normale). Restaurer ces textures (et la
normale) redonne le rendu Tripo sans coût géométrique."""
new = """**B — Rochers PBR d'origine (livré)** : les GLB Tripo3D bruts
(`artifacts/tripo-review/rock-kit/recolored_1024/`) ont la **même géométrie**
(973–1 036 tris) que les `bloc_rocheux_*` livrés, mais des textures PBR plus
fines. Régénération par `tools/blender/build_tripo_rocks.py --texture-size 1024` :
albédo **1024²** (au lieu de 512²) + **normale 1024²**, palette Valbois, AO et
mottling en vertex colors, vignettes et manifeste à jour. GLB : 258–469 Ko
(contre 164–230 Ko). Test : `rock_pbr_test` ; captures :
`rochers_formation_*.png`."""
assert old in s, 'section B introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('RAPPORT_QUALITE B mis à jour')
