from pathlib import Path

p = Path('game/assets/objects3d/README.md')
s = p.read_text(encoding='utf-8')
anchor = "La sortie de Blender contient le GLB, sa vignette et le manifeste mis à jour."
assert anchor in s, 'ancre README introuvable'
insert = anchor + '''

### Preset HD (chantier C — bâti/décors)

Le pipeline est paramétrable : géométrie reconstruite sur une grille plus fine,
budget de triangles relevé, et surtout **texture par UV de projection continus**
(la planche de référence EST la texture ; plus de bake par îlots de 18 px qui
rendait les surfaces « bouillies »). Preset utilisé pour le kit HD :

```powershell
# 1) Reconstruction des volumes (Python : numpy/scipy/scikit-image)
python tools/blender/reference_hull.py --manifest game/assets/objects3d/manifest.json `
  --references tools/blender/references --out $inputDir `
  --hull-size 128 --atlas-tile 768 --only maison,forge

# 2) Export Blender (UV de projection + LOD générés à l'import Godot)
& "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background `
  --python-exit-code 1 --python tools/blender/build_reference_volumes.py -- `
  --manifest game/assets/objects3d/manifest.json --references tools/blender/references `
  --input $inputDir --out $stageDir --only maison,forge `
  --tris-budget 6000 --tri-scale 3 `
  --image-format JPEG --image-quality 88 --triangle-limit 14000
```

Repères : `--hull-size` 64 = historique, 128 = HD ; `--atlas-tile` 256 =
historique, 768 ≈ résolution native d'une vue (3×768 de large pour l'atlas) ;
`--tris-budget` plafonne le mesh de base, `--tri-scale` multiplie les triangles
du manifeste ; `--triangle-limit` relève le garde-fou global.
La végétation fine (roseaux, buissons, haies, nénuphars) n'utilise PAS ce
pipeline : voir `tools/blender/build_vegetation_cards.py` (cartouches alpha).
'''
s = s.replace(anchor, insert, 1)
p.write_text(s, encoding='utf-8')
print('README objects3d : preset HD documenté')
