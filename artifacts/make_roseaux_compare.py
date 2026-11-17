from pathlib import Path
from PIL import Image, ImageDraw

W = 1600
ref = Image.open('tools/blender/references/roseaux.png').convert('RGB')
ref_scale = W / ref.width
ref_r = ref.resize((W, int(ref.height * ref_scale)), Image.LANCZOS)

thumb = Image.open('game/assets/objects3d/vegetation/roseaux_thumb.png').convert('RGB')
thumb_r = thumb.resize((420, 420), Image.LANCZOS)

shot = Image.open('docs/screenshots/demo_riviere_s_detail.png').convert('RGB')
crop = shot.crop((250, 250, 520, 470)).resize((420, 342), Image.LANCZOS)

pad = 24
row_h = max(thumb_r.height, crop.height)
out = Image.new('RGB', (W, ref_r.height + row_h + pad * 3), (28, 30, 34))
out.paste(ref_r, (0, pad // 2))

y = ref_r.height + pad
out.paste(thumb_r, (pad, y))
out.paste(crop, (pad + thumb_r.width + pad, y))

d = ImageDraw.Draw(out)
d.text((pad + 8, y + 8), '3D livree : 2418 tris, atlas 630 px', fill=(255, 230, 200))
d.text((pad + thumb_r.width + pad + 8, y + 8), 'En jeu (demo riviere en S)', fill=(255, 230, 200))
d.text((pad, 6), 'REFERENCE IA FOURNIE (2172x724)  —  avant tout passage 3D', fill=(255, 255, 255))

out_path = Path('artifacts/roseaux_avant_apres.png')
out.save(out_path)
print(out_path, out.size)
