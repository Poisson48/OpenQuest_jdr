from pathlib import Path

p = Path('tools/blender/reference_hull.py')
s = p.read_text(encoding='utf-8')
old = '''def make_atlas(views, path, tile=ATLAS_TILE):
    tiles = []
    for rgb, mask in views:
        indices = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
        tile = Image.fromarray(rgb[tuple(indices)])
        tiles.append(tile.resize((tile_ref, tile_ref), Image.Resampling.LANCZOS))
    atlas = Image.new("RGB", (ATLAS_TILE * 3, ATLAS_TILE))
    for i, tile in enumerate(tiles):
        atlas.paste(tile, (i * ATLAS_TILE, 0))
    atlas.save(path)
'''
new = '''def make_atlas(views, path, tile_size=ATLAS_TILE):
    """Atlas des 3 vues (résolution `tile_size` par vue).

    C'est la SOURCE du bake de projection : plus la tuile est grande, plus la
    texture des volumes est fine (références natives ~724 px par vue).
    """
    tiles = []
    for rgb, mask in views:
        indices = ndimage.distance_transform_edt(~mask, return_distances=False, return_indices=True)
        view = Image.fromarray(rgb[tuple(indices)])
        tiles.append(view.resize((tile_size, tile_size), Image.Resampling.LANCZOS))
    atlas = Image.new("RGB", (tile_size * 3, tile_size))
    for i, view in enumerate(tiles):
        atlas.paste(view, (i * tile_size, 0))
    atlas.save(path)
'''
assert old in s, 'make_atlas introuvable'
s = s.replace(old, new, 1)

# CLI : taille de grille de reconstruction + tuile d'atlas source.
old_cli = '''    parser.add_argument("--only", nargs="+")
    args = parser.parse_args()'''
new_cli = '''    parser.add_argument("--only", nargs="+")
    parser.add_argument("--hull-size", type=int, default=SIZE,
                        help="résolution de la grille de reconstruction (64 = historique)")
    parser.add_argument("--atlas-tile", type=int, default=ATLAS_TILE,
                        help="résolution de chaque vue dans l'atlas source (256 = historique)")
    args = parser.parse_args()'''
assert old_cli in s, 'cli hull introuvable'
s = s.replace(old_cli, new_cli, 1)

old_call = '''            vertices, triangles, coverage = reconstruct(views, dimensions, name.startswith("pnj_"))
            make_atlas(views, args.out / f"{name}_atlas.png")'''
new_call = '''            vertices, triangles, coverage = reconstruct(
                views, dimensions, name.startswith("pnj_"), size=args.hull_size)
            make_atlas(views, args.out / f"{name}_atlas.png", tile_size=args.atlas_tile)'''
assert old_call in s, 'appel reconstruct introuvable'
s = s.replace(old_call, new_call, 1)
p.write_text(s, encoding='utf-8')
print('reference_hull.py paramétrable OK')
