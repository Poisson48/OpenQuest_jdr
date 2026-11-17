from pathlib import Path

p = Path('game/project.godot')
s = p.read_text(encoding='utf-8')
old = 'scene={\n"gltf/embedded_image_handling": 3\n}'
new = 'scene={\n"gltf/embedded_image_handling": 3,\n"meshes/generate_lods": true\n}'
assert old in s, 'scene defaults introuvables'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('importer defaults LOD ajouté')
