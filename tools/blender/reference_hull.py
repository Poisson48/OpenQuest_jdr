"""Reconstruit un volume à partir des silhouettes d'une référence transparente.

La planche contient, de gauche à droite, les vues avant, droite et du dessus.
Le résultat (sommets, faces et atlas UV) est consommé par Blender.
"""

import argparse
from itertools import permutations
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage.measure import marching_cubes


SIZE = 64
ATLAS_TILE = 256


def extract_views(path):
    rgba = np.asarray(Image.open(path).convert("RGBA"))
    height, width = rgba.shape[:2]
    alpha = rgba[..., 3]
    if np.count_nonzero(alpha < 16) < alpha.size // 12:
        raise ValueError("L'image ne contient pas de fond transparent.")
    # Les gouttières peuvent être légèrement décentrées selon la composition.
    occupancy = np.count_nonzero(alpha >= 180, axis=0)
    cuts = [0]
    for fraction in (1 / 3, 2 / 3):
        middle = int(width * fraction)
        reach = max(1, width // 18)
        candidates = np.arange(middle - reach, middle + reach + 1)
        cost = occupancy[candidates] / height + 0.065 * np.abs(candidates - middle) / reach
        cuts.append(int(candidates[np.argmin(cost)]))
    cuts.append(width)
    views = []
    for left, right in zip(cuts, cuts[1:]):
        part = rgba[:, left:right]
        mask = part[..., 3] >= 180
        labels, count = ndimage.label(mask)
        if count == 0:
            raise ValueError("Une des trois vues est vide.")
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        mask &= sizes[labels] >= max(12, sizes.max() * 0.003)
        rows, cols = np.where(mask)
        if len(rows) < 128 or np.ptp(cols) < 10 or np.ptp(rows) < 4:
            raise ValueError("Une des trois silhouettes est trop petite.")
        crop = np.s_[rows.min():rows.max() + 1, cols.min():cols.max() + 1]
        views.append((part[crop][..., :3], mask[crop]))
    return views


def mask_distance(mask):
    # Une bordure vide évite de prolonger les pixels de contour hors de la vue.
    mask = np.pad(mask, 1)
    distance = ndimage.distance_transform_edt(mask) - ndimage.distance_transform_edt(~mask)
    return distance


def sample_distance(mask, across, up):
    distance = mask_distance(mask)
    rows, cols = mask.shape
    coords = np.broadcast_arrays(1 + (1 - up) * (rows - 1), 1 + across * (cols - 1))
    value = ndimage.map_coordinates(distance, coords, order=1, cval=-16)
    return value * SIZE / max(rows, cols)


def visibility_score(field, front, side, plan):
    present = field >= 0
    projected = (present.any(axis=1), present.any(axis=0), present.any(axis=2))
    return [
        float(np.count_nonzero(view & expected) / max(np.count_nonzero(expected), 1))
        for view, expected in zip(projected, (front, side, plan))
    ]


def elevation_colors(view, across, up):
    rgb, _ = view
    rows, cols = rgb.shape[:2]
    uv = np.broadcast_arrays((1 - up) * (rows - 1), across * (cols - 1))
    rgb = np.stack([ndimage.map_coordinates(rgb[..., c], uv, order=1) for c in range(3)], axis=-1)
    rgb = rgb.astype(np.float32) / 255
    return rgb / np.maximum(np.sum(rgb, axis=-1, keepdims=True), 0.08)


def bands(line):
    """Intervalles distincts d'une silhouette à une hauteur donnée."""
    edges = np.flatnonzero(np.diff(np.pad(line.astype(np.int8), 1)))
    return [(start, end) for start, end in zip(edges[::2], edges[1::2]) if end - start >= 2]


def match_figurine_parts(field, views, x, y, z, front, side):
    """Évite de croiser arme et plume lorsque les deux silhouettes les séparent."""
    front_color = elevation_colors(views[0], x, z).squeeze(1)
    side_color = elevation_colors(views[1], y, z).squeeze(0)
    for k in range(field.shape[2]):
        front_parts, side_parts = bands(front[:, k] > 0), bands(side[:, k] > 0)
        n = len(front_parts)
        if n not in (2, 3) or n != len(side_parts):
            continue
        left = np.asarray([np.median(front_color[a:b, k], axis=0) for a, b in front_parts])
        right = np.asarray([np.median(side_color[a:b, k], axis=0) for a, b in side_parts])
        distances = np.linalg.norm(left[:, None, :] - right[None, :, :], axis=-1)
        assignments = sorted((sum(distances[i, j] for i, j in enumerate(order)), order)
                             for order in permutations(range(n)))
        cost, order = assignments[0]
        if cost > n * 0.115 or assignments[1][0] - cost < 0.10:
            continue
        for i, (xa, xb) in enumerate(front_parts):
            for j, (ya, yb) in enumerate(side_parts):
                if j != order[i]:
                    field[xa:xb, ya:yb, k] = -2.0


def reconstruct(views, dimensions, figurine=False, size=SIZE):
    # Les axes sont X largeur, Y profondeur, Z hauteur (repère Blender).
    # Les éléments minces conservent assez de tranches pour le relief.
    longest = max(dimensions)
    steps = [max(13, round(size * (d / longest) ** 0.55)) for d in dimensions]
    axis = [np.linspace(-0.06, 1.06, n + 1) for n in steps]
    x, y, z = np.ix_(*axis)
    front = sample_distance(views[0][1], x, z).squeeze(1)
    side = sample_distance(views[1][1], y, z).squeeze(0)
    # La vue de dessus peut être tournée à 180° par l'illustrateur.
    # Préférer l'orientation spécifiée à qualité égale.
    best = None
    for rotation in (0, 2, 1, 3):
        top_mask = np.rot90(views[2][1], rotation)
        top = sample_distance(top_mask, x, y).squeeze(2)
        for side_flipped in (False, True):
            side_field = sample_distance(views[1][1][:, ::-1], y, z).squeeze(0) if side_flipped else side
            field = np.minimum(np.minimum(front[:, None, :], side_field[None, :, :]), top[..., None])
            score = visibility_score(field, front > 0, side_field > 0, top > 0)
            quality = np.mean(score) - 0.008 * bool(rotation) - 0.004 * side_flipped
            if best is None or quality > best[0]:
                best = quality, score, field, rotation, side_flipped

    _, coverage, field, rotation, side_flipped = best
    if min(coverage) < 0.36:
        raise ValueError(f"Vues incompatibles (couverture {np.round(coverage, 2)}).")

    if side_flipped:
        views[1] = tuple(v[:, ::-1] for v in views[1])
    views[2] = tuple(np.rot90(v, rotation) for v in views[2])
    if figurine:
        calibrated_side = sample_distance(views[1][1], y, z).squeeze(0)
        match_figurine_parts(field, views, x, y, z, front, calibrated_side)

    # Ôte les pixels isolés issus des reflets ou des ombres du détourage.
    positive = field >= 0
    labels, _ = ndimage.label(positive)
    count = np.bincount(labels.ravel())
    count[0] = 0
    remove = positive & (count[labels] < max(8, count.max() * 0.003))
    field[remove] = -1
    field = ndimage.gaussian_filter(np.clip(field, -3.0, 3.0), sigma=0.68)
    for dim in range(3):
        field.swapaxes(0, dim)[0] = -1
        field.swapaxes(0, dim)[-1] = -1
    vertices, triangles, _, _ = marching_cubes(field, level=0.0, allow_degenerate=False)
    vertices = vertices / np.asarray(steps) * 1.12 - 0.06
    # marching_cubes emploie une convention de winding dépendante du signe.
    a, b, c = vertices[triangles].transpose(1, 0, 2)
    if np.einsum("ij,ij->", a, np.cross(b, c)) < 0:
        triangles = triangles[:, ::-1]
    return vertices, triangles, coverage


def make_atlas(views, path, tile_size=ATLAS_TILE):
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--references", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", nargs="+")
    parser.add_argument("--hull-size", type=int, default=SIZE,
                        help="résolution de la grille de reconstruction (64 = historique)")
    parser.add_argument("--atlas-tile", type=int, default=ATLAS_TILE,
                        help="résolution de chaque vue dans l'atlas source (256 = historique)")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    assets = json.loads(args.manifest.read_text(encoding="utf-8"))["assets"]
    selected = set(args.only or (a["name"] for a in assets))
    failures = selected.difference(a["name"] for a in assets)
    for asset in assets:
        name = asset["name"]
        if name not in selected:
            continue
        try:
            path = args.references / f"{name}.png"
            views = extract_views(path)
            dimensions = asset.get("reference_bounds", asset["dimensions_cells"])
            vertices, triangles, coverage = reconstruct(
                views, dimensions, name.startswith("pnj_"), size=args.hull_size)
            make_atlas(views, args.out / f"{name}_atlas.png", tile_size=args.atlas_tile)
            np.savez_compressed(args.out / f"{name}.npz", vertices=vertices, triangles=triangles)
            print(f"[OK] {name} silhouette {' '.join(f'{v:.0%}' for v in coverage)}", flush=True)
        except (ValueError, OSError) as error:
            failures.add(name)
            print(f"[ECHEC] {name}: {error}", flush=True)
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
