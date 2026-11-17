from pathlib import Path

p = Path('tools/blender/build_reference_volumes.py')
s = p.read_text(encoding='utf-8')

# 1) build_mesh : budget triangles paramétrable + tuile de bake paramétrable.
old = '''def build_mesh(name, input_dir, entry):'''
new = '''def build_mesh(name, input_dir, entry, args):'''
assert old in s
s = s.replace(old, new, 1)

old = '''    target = max(700, min(2150, int(entry["triangles_base"] * 1.5)))'''
new = '''    budget = int(getattr(args, "tris_budget", 2150))
    scale = float(getattr(args, "tri_scale", 1.5))
    target = max(700, min(budget, int(entry["triangles_base"] * scale)))'''
assert old in s
s = s.replace(old, new, 1)

old = '''    texture_atlas, glow_atlas = bake_projection(mesh, name, input_dir / f"{name}_atlas.png")'''
new = '''    texture_atlas, glow_atlas = bake_projection(
        mesh, name, input_dir / f"{name}_atlas.png",
        tile=int(getattr(args, "bake_tile", 18)),
        atlas_max=int(getattr(args, "atlas_max", 0)))'''
assert old in s
s = s.replace(old, new, 1)

# 2) bake_projection : tuile et plafond d'atlas.
old = '''def bake_projection(mesh, name, source_path):
    """Cuit les vues mélangées sur une texture UV opaque, avec marge par face."""
    source = read_projection(source_path)
    mesh.update()
    uv = mesh.uv_layers.new(name="Reference")
    tile = 18'''
new = '''def bake_projection(mesh, name, source_path, tile=18, atlas_max=0):
    """Cuit les vues mélangées sur une texture UV opaque, avec marge par face.

    `tile` = pixels par face (18 historique, 24–32 pour un rendu HD) ;
    `atlas_max` = côté maximal de l'atlas (0 = pas de plafond), redimensionné
    après cuisson pour maîtriser le poids des GLB.
    """
    source = read_projection(source_path)
    mesh.update()
    uv = mesh.uv_layers.new(name="Reference")'''
assert old in s
s = s.replace(old, new, 1)

old = '''    surface = pack_atlas(f"{name}_surface", pixels)
    return surface, pack_atlas(f"{name}_lueur", glow) if glow is not None else None'''
new = '''    surface = pack_atlas(f"{name}_surface", pixels, atlas_max)
    return surface, pack_atlas(f"{name}_lueur", glow, atlas_max) if glow is not None else None'''
assert old in s
s = s.replace(old, new, 1)

old = '''def pack_atlas(name, pixels):
    image = bpy.data.images.new(name, width=pixels.shape[1], height=pixels.shape[0], alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    return image'''
new = '''def pack_atlas(name, pixels, max_size=0):
    image = bpy.data.images.new(name, width=pixels.shape[1], height=pixels.shape[0], alpha=False)
    image.pixels.foreach_set(pixels.ravel())
    if max_size and max_size > 0:
        size = max(image.size[0], image.size[1])
        if size > max_size:
            image.scale(max_size, max_size)
    image.pack()
    return image'''
assert old in s
s = s.replace(old, new, 1)

# 3) export_asset : appel build_mesh + format d'image.
old = '''        obj = build_mesh(name, args.input, entry)'''
new = '''        obj = build_mesh(name, args.input, entry, args)'''
assert old in s
s = s.replace(old, new, 1)

old = '''    glb = args.out / entry["glb"]
    oq.export_glb(glb, nodes)'''
new = '''    glb = args.out / entry["glb"]
    image_format = getattr(args, "image_format", None)
    if image_format == "AUTO":
        image_format = None
    oq.export_glb(glb, nodes, image_format=image_format,
                  image_quality=int(getattr(args, "image_quality", 90)))'''
assert old in s
s = s.replace(old, new, 1)

# 4) main : nouveaux arguments + relèvement du budget global.
old = '''    parser.add_argument("--samples", type=int, default=12)
    args = parser.parse_args(oq.cli_argv())'''
new = '''    parser.add_argument("--samples", type=int, default=12)
    parser.add_argument("--tris-budget", type=int, default=2150,
                        help="plafond de triangles du mesh de base (2150 historique)")
    parser.add_argument("--tri-scale", type=float, default=1.5,
                        help="multiplicateur de triangles_base du manifeste (3 = HD)")
    parser.add_argument("--bake-tile", type=int, default=18,
                        help="pixels par face dans l'atlas cuit (18 historique, 24-32 HD)")
    parser.add_argument("--atlas-max", type=int, default=0,
                        help="côté maximal de l'atlas cuit (0 = pas de plafond)")
    parser.add_argument("--image-format", choices=["AUTO", "PNG", "JPEG"], default="AUTO",
                        help="format des textures embarquées (JPEG = GLB plus légers)")
    parser.add_argument("--image-quality", type=int, default=90)
    parser.add_argument("--triangle-limit", type=int, default=0,
                        help="relève oq.TRIANGLE_BUDGET (0 = budget historique)")
    args = parser.parse_args(oq.cli_argv())
    if args.triangle_limit > 0:
        oq.TRIANGLE_BUDGET = args.triangle_limit'''
assert old in s
s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8')
print('build_reference_volumes.py paramétrable OK')
