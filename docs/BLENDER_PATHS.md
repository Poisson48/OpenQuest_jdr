# Chemins Blender — pipeline procédural

## Source

Le générateur de chemin en pierre vient de l’asset « Geometry nodes — Path through grass »
(fichiers `GeoNodesStonePath_Start.blend` / `GeoNodesStonePath_End.blend`).

Le `.blend` source n’est **pas** copié dans le dépôt : il reste dans le zip téléchargé.
Le script d’export prend son chemin en argument.

Références :
- [Stone Path Generator — Two Dancing Clams](https://twodancingclams.gumroad.com/l/stoneroad)
- [Procedural Pathway Generator — Obaidur Rahman](https://obaidurrahman.gumroad.com/l/zHuvH)
- [Vidéo Geometry Nodes — Path through grass](https://www.youtube.com/watch?v=MC_MXaGZfqM)

## Export

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
& $blender -b --python tools/blender/export_procedural_path.py -- `
  --blend "A:\Leo\Downloads\...\GeoNodesStonePath_End.blend" `
  --output "game/assets/objects3d/terrain/path_stone_procedural.glb" `
  --texture "game/assets/terrain/dirt_ai.png" `
  --scale 0.55 --decimate 0.28
```

Le script :
1. ouvre le `.blend` ;
2. évalue le chemin généré par **Geometry Nodes** ;
3. convertit le résultat en mesh ;
4. applique une **décimation** pour rester léger ;
5. crée un matériau avec la texture de terre IA ;
6. fait un **Smart UV Project** ;
7. exporte un GLB avec UVs, normales, matériau et texture.

Résultat actuel : `path_stone_procedural.glb`, ~17 600 triangles après décimation.

## Utilisation dans la démo

`game/scripts/debug/path_demo_boot.gd` pose ce GLB comme objet 3D sur la carte,
à côté des chemins peints. C’est la preuve du pipeline Blender → GLB → Godot.

## Limites

- le chemin Blender est un **asset statique** ; le tracé libre/peint reste le
  moyen de créer un chemin arbitraire dans l’éditeur ;
- le GLB n’est pas encore exposé dans la bibliothèque d’assets de l’éditeur ;
- source `.blend` non versionnée (asset tiers téléchargé).
