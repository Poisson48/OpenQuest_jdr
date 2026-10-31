"""Genere les textures de sol tuilables de la carte 2.5D (offline).

Cinq textures 512x512 **seamless** (bords raccord quand on les répète) :

* ``grass.png``  : herbe Valbois, vert désaturé, touffes et brins peints ;
* ``dirt.png``   : terre / chemin, brun chaud, cailloux, fissures et taches ;
* ``stone.png``  : pavé de pierre (dallage irrégulier), joints sombres et mousse ;
* ``snow.png``   : neige blanc bleuté, grain fin, congères et éclats de glace ;
* ``sand.png``   : sable chaud, rides douces, quelques cailloux et coquilles.

Tout est procédural (numpy + Pillow), sans téléchargement ni asset externe. Les
bruits sont **périodiques** (value noise à grille bouclée, fBm multi-échelle,
domain warp) ; les détails peints (brins, cailloux, fissures, joints) sont
dessinés avec repliement sur les bords. La texture se raccorde donc exactement.

Usage :

    python tools/blender/make_terrain_textures.py
    python tools/blender/make_terrain_textures.py --size 512 --out-root game/assets/terrain
    python tools/blender/make_terrain_textures.py --verify
    python tools/blender/make_terrain_textures.py --preview-only

Sorties (par défaut dans ``game/assets/terrain/``) :

    grass.png, dirt.png, stone.png, snow.png, sand.png   # 512x512 RGB, tuilables
    grass_thumb.png, ...                                 # 256x256, pour la bibliothèque
    _planche_terrain.png                                 # planche de contrôle (tuile 2x2)
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
TERRAIN_ROOT = REPO_ROOT / "game" / "assets" / "terrain"

DEFAULT_SIZE = 512
DEFAULT_SEED = 2026
THUMB_SIZE = 256

# Palettes Valbois (sRGB) : (ombre, base, lumière, pale, accent).
PALETTES: dict[str, dict[str, tuple[int, int, int]]] = {
    "grass": {
        "shadow": (58, 68, 41),      # #3a4429
        "base": (100, 112, 74),      # #64704a
        "light": (134, 147, 96),     # #869360
        "pale": (163, 168, 112),     # #a3a870
        "accent": (141, 136, 82),    # #8d8852 (herbe sèche)
        "flower": (206, 198, 160),   # #cec6a0 (petites fleurs)
    },
    "dirt": {
        "shadow": (92, 75, 56),      # #5c4b38
        "base": (138, 117, 92),      # #8a755c
        "light": (164, 141, 111),    # #a48d6f
        "pale": (182, 161, 131),     # #b6a183
        "accent": (139, 134, 121),   # #8b8679 (cailloux)
    },
    "stone": {
        "shadow": (84, 80, 72),      # #545048
        "base": (140, 136, 125),     # #8c887d
        "light": (165, 160, 148),    # #a5a094
        "pale": (183, 177, 164),     # #b7b1a4
        "accent": (100, 96, 87),     # #646057
    },
    "snow": {
        "shadow": (168, 184, 202),   # #a8b8ca (ombre bleutée)
        "base": (210, 221, 233),     # #d2dde9
        "light": (231, 239, 246),    # #e7eff6
        "pale": (247, 251, 254),     # #f7fbfe
        "accent": (190, 208, 224),   # #bed0e0 (congères / glace)
    },
    "sand": {
        "shadow": (163, 136, 94),    # #a3885e
        "base": (202, 174, 124),     # #caae7c
        "light": (222, 198, 150),    # #dec696
        "pale": (238, 220, 180),     # #eedcb4
        "accent": (198, 186, 162),   # #c6baa2 (cailloux clairs)
    },
}


# --------------------------------------------------------------------------- #
# Bruit périodique (seamless par construction)
# --------------------------------------------------------------------------- #


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def periodic_value_noise(size: int, period: int, rng: np.random.Generator) -> np.ndarray:
    """Value noise à grille périodique -> raccord parfait sur ``size``."""
    period = max(1, min(int(period), size))
    grid = rng.random((period, period))

    coords = np.arange(size, dtype=np.float64) * (period / size)
    idx = np.floor(coords).astype(np.int64)
    frac = coords - idx
    smooth = frac * frac * (3.0 - 2.0 * frac)

    idx0 = idx % period
    idx1 = (idx + 1) % period
    ux = smooth[None, :]
    uy = smooth[:, None]
    g00 = grid[np.ix_(idx0, idx0)]
    g10 = grid[np.ix_(idx1, idx0)]
    g01 = grid[np.ix_(idx0, idx1)]
    g11 = grid[np.ix_(idx1, idx1)]
    top = g00 * (1.0 - ux) + g01 * ux
    bottom = g10 * (1.0 - ux) + g11 * ux
    return top * (1.0 - uy) + bottom * uy


def fbm(
    size: int,
    seed: int,
    octaves: int = 5,
    base_period: int = 4,
    gain: float = 0.5,
    lacunarity: float = 2.0,
) -> np.ndarray:
    """Fractal brownian motion périodique, normalisé dans [0, 1]."""
    rng = _rng(seed)
    total = np.zeros((size, size), dtype=np.float64)
    amplitude = 1.0
    max_amplitude = 0.0
    period = float(base_period)
    for _ in range(octaves):
        total += amplitude * periodic_value_noise(size, int(round(period)), rng)
        max_amplitude += amplitude
        amplitude *= gain
        period = min(period * lacunarity, size)
    total /= max_amplitude
    return np.clip(total, 0.0, 1.0)


def sample_wrap(image: np.ndarray, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    """Échantillonnage bilinéaire avec repliement torique (pour le domain warp)."""
    height, width = image.shape
    x0 = np.floor(xs).astype(np.int64)
    y0 = np.floor(ys).astype(np.int64)
    fx = xs - x0
    fy = ys - y0
    x0 %= width
    y0 %= height
    x1 = (x0 + 1) % width
    y1 = (y0 + 1) % height
    v00 = image[y0, x0]
    v01 = image[y0, x1]
    v10 = image[y1, x0]
    v11 = image[y1, x1]
    top = v00 * (1.0 - fx) + v01 * fx
    bottom = v10 * (1.0 - fx) + v11 * fx
    return top * (1.0 - fy) + bottom * fy


def warp(field: np.ndarray, dx: np.ndarray, dy: np.ndarray, strength: float) -> np.ndarray:
    """Domain warp périodique : garde la tuabilité."""
    size = field.shape[0]
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    return sample_wrap(field, xs + dx * strength, ys + dy * strength)


def white_noise(size: int, seed: int) -> np.ndarray:
    """Bruit blanc déterministe (seamless trivialement, sans structure)."""
    return _rng(seed).random((size, size))


def _pil_from_array(image: np.ndarray, color: bool = True) -> Image.Image:
    if color:
        return Image.fromarray(np.clip(image * 255.0, 0, 255).astype(np.uint8))
    return Image.fromarray(np.clip(image * 255.0, 0, 255).astype(np.uint8), "L")


def wrap_filter(image: np.ndarray, radius: float, unsharp: bool = False) -> np.ndarray:
    """Flou / netteté qui respecte le raccord (tuile 3x3 puis crop central)."""
    if radius <= 0:
        return image
    pil = _pil_from_array(image, color=True)
    width, height = pil.size
    tiled = Image.new("RGB", (width * 3, height * 3))
    for ty in range(3):
        for tx in range(3):
            tiled.paste(pil, (tx * width, ty * height))
    if unsharp:
        processed = tiled.filter(
            ImageFilter.UnsharpMask(radius=radius, percent=70, threshold=2)
        )
    else:
        processed = tiled.filter(ImageFilter.GaussianBlur(radius))
    cropped = processed.crop((width, height, width * 2, height * 2))
    return np.asarray(cropped).astype(np.float64) / 255.0


def contrast(t: np.ndarray, strength: float = 1.5) -> np.ndarray:
    """Contraste doux autour de 0,5."""
    return np.clip((t - 0.5) * strength + 0.5, 0.0, 1.0)


def paint_tint(image: np.ndarray, field: np.ndarray, warm: float = 0.05) -> np.ndarray:
    """Module la teinte par un bruit large (chaud/froid) pour l'effet peint."""
    modulation = (field - 0.5) * 2.0 * warm
    tint = np.zeros_like(image)
    tint[..., 0] = 1.0 + modulation
    tint[..., 1] = 1.0 + modulation * 0.4
    tint[..., 2] = 1.0 - modulation * 0.6
    return np.clip(image * tint, 0.0, 1.0)


# --------------------------------------------------------------------------- #
# Helpers couleur / dessin avec repliement
# --------------------------------------------------------------------------- #


def mix_color(stops: list[tuple[float, tuple[int, int, int]]], t: np.ndarray) -> np.ndarray:
    """Interpole une liste (position, couleur RGB) en fonction de t ∈ [0,1]."""
    stops = sorted(stops, key=lambda item: item[0])
    t = np.clip(t, 0.0, 1.0)
    result = np.zeros(t.shape + (3,), dtype=np.float64)
    for index, (position, color) in enumerate(stops):
        if index == 0:
            continue
        previous_position, previous_color = stops[index - 1]
        if position <= previous_position:
            continue
        mask = (t >= previous_position) & (t <= position)
        if not np.any(mask):
            continue
        local = (t[mask] - previous_position) / (position - previous_position)
        for channel in range(3):
            result[..., channel][mask] = (
                previous_color[channel]
                + (color[channel] - previous_color[channel]) * local
            )
    first_color = stops[0][1]
    last_color = stops[-1][1]
    for channel in range(3):
        result[..., channel][t <= stops[0][0]] = first_color[channel]
        result[..., channel][t >= stops[-1][0]] = last_color[channel]
    return np.clip(result, 0.0, 255.0) / 255.0


def _draw_shifted(draw: ImageDraw.ImageDraw, size: int, x: float, y: float, fn) -> None:
    """Dessine ``fn(x, y)`` puis ses copies décalées si proche d'un bord."""
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            px, py = x + dx, y + dy
            if -40 <= px <= size + 40 and -40 <= py <= size + 40:
                fn(draw, px, py)


def _composite_layer(image: np.ndarray, layer: np.ndarray, strength: float = 0.85) -> np.ndarray:
    """Compose un calque peint (fond noir = transparent) sur l'image."""
    mask = layer.max(axis=2, keepdims=True) > 0.015
    return np.where(mask, image * (1.0 - strength) + layer * strength, image)


# --------------------------------------------------------------------------- #
# Génération des textures
# --------------------------------------------------------------------------- #


def build_grass(size: int, seed: int) -> np.ndarray:
    palette = PALETTES["grass"]
    rng = _rng(seed + 11)

    large = fbm(size, seed + 101, octaves=5, base_period=3)
    clumps = fbm(size, seed + 102, octaves=5, base_period=6)
    medium = fbm(size, seed + 103, octaves=4, base_period=16)
    fine = fbm(size, seed + 104, octaves=3, base_period=56)
    dx = fbm(size, seed + 105, octaves=3, base_period=4)
    dy = fbm(size, seed + 106, octaves=3, base_period=6)

    base_field = 0.40 * large + 0.30 * clumps + 0.20 * medium + 0.10 * fine
    base_field = warp(base_field, dx, dy, strength=size * 0.05)
    t = contrast(base_field, strength=1.55) * 0.9 + 0.05

    image = mix_color(
        [
            (0.0, palette["shadow"]),
            (0.30, palette["base"]),
            (0.62, palette["light"]),
            (0.88, palette["pale"]),
        ],
        t,
    )

    # Taches d'herbe sèche (jaune paille) et de terre nue.
    dry = np.clip((clumps - 0.58) * 3.2, 0.0, 1.0) * 0.45
    accent = np.asarray(palette["accent"], dtype=np.float64) / 255.0
    image = image * (1.0 - dry[..., None] * 0.35) + accent * (dry[..., None] * 0.35)

    dirt_patch = np.clip((medium - 0.66) * 4.0, 0.0, 1.0) * 0.30
    dirt_color = np.asarray(PALETTES["dirt"]["base"], dtype=np.float64) / 255.0
    image = image * (1.0 - dirt_patch[..., None] * 0.4) + dirt_color * (
        dirt_patch[..., None] * 0.4
    )

    grain = white_noise(size, seed + 107)
    image *= (0.90 + 0.17 * grain)[..., None]
    image = paint_tint(image, large, warm=0.06)

    # Touffes de brins peints : rayons groupés autour de centres de touffe.
    stroke_layer = Image.new("RGB", (size, size), (0, 0, 0))
    draw = ImageDraw.Draw(stroke_layer)
    dark = tuple(int(c * 0.66) for c in palette["shadow"])
    mid = tuple(int(c * 0.92) for c in palette["base"])
    light = tuple(int(min(255, c * 1.22)) for c in palette["light"])
    pale = tuple(min(255, int(c * 1.34)) for c in palette["pale"])

    cluster_count = int(size * size / 620)
    for _ in range(cluster_count):
        cx = rng.uniform(0, size)
        cy = rng.uniform(0, size)
        blades = int(rng.integers(6, 13))
        spread = rng.uniform(3.0, 9.0)
        base_angle = rng.uniform(-0.55, 0.55)
        for _blade in range(blades):
            x = cx + rng.normal(0, spread)
            y = cy + rng.normal(0, spread * 0.7)
            length = rng.uniform(4.5, 12.0)
            angle = base_angle + rng.uniform(-0.42, 0.42)
            width = 1 if rng.random() < 0.82 else 2
            roll = rng.random()
            color = dark if roll < 0.30 else (mid if roll < 0.55 else (light if roll < 0.85 else pale))
            end_x = x + math.sin(angle) * length
            end_y = y - math.cos(angle) * length

            def blade(
                d,
                px,
                py,
                ex=end_x,
                ey=end_y,
                c=color,
                w=width,
            ):
                d.line([(px, py), (px + (ex - x), py + (ey - y))], fill=c, width=w)

            _draw_shifted(draw, size, x, y, blade)

    strokes = np.asarray(stroke_layer).astype(np.float64) / 255.0
    image = _composite_layer(image, strokes, strength=0.75)

    # Quelques fleurs minuscules (touches claires).
    flower_layer = Image.new("RGB", (size, size), (0, 0, 0))
    flower_draw = ImageDraw.Draw(flower_layer)
    flower_color = palette["flower"]
    for _ in range(int(size * size / 5200)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(1.0, 2.1)

        def flower(d, px, py, r=radius, c=flower_color):
            d.ellipse([px - r, py - r, px + r, py + r], fill=c)
            d.point((px, py), fill=(90, 80, 50))

        _draw_shifted(flower_draw, size, x, y, flower)

    flowers = np.asarray(flower_layer).astype(np.float64) / 255.0
    image = _composite_layer(image, flowers, strength=0.8)

    image = wrap_filter(image, 0.45).copy()
    image = wrap_filter(image, 1.1, unsharp=True)
    return np.clip(image, 0.0, 1.0)


def build_dirt(size: int, seed: int) -> np.ndarray:
    palette = PALETTES["dirt"]
    rng = _rng(seed + 21)

    large = fbm(size, seed + 201, octaves=5, base_period=3)
    patches = fbm(size, seed + 202, octaves=4, base_period=7)
    medium = fbm(size, seed + 203, octaves=5, base_period=15)
    fine = fbm(size, seed + 204, octaves=3, base_period=48)
    dx = fbm(size, seed + 205, octaves=3, base_period=4)
    dy = fbm(size, seed + 206, octaves=3, base_period=5)

    field = 0.42 * large + 0.30 * patches + 0.18 * medium + 0.10 * fine
    field = warp(field, dx, dy, strength=size * 0.055)
    t = contrast(field, strength=1.7) * 0.92 + 0.04

    image = mix_color(
        [
            (0.0, palette["shadow"]),
            (0.32, palette["base"]),
            (0.66, palette["light"]),
            (0.90, palette["pale"]),
        ],
        t,
    )

    # Taches humides (sombres) et poussiéreuses (claires).
    humid = np.clip((0.52 - large) * 3.4, 0.0, 1.0) * 0.30
    image *= (1.0 - humid[..., None] * 0.35)
    dust = np.clip((medium - 0.60) * 3.0, 0.0, 1.0) * 0.22
    pale = np.asarray(palette["pale"], dtype=np.float64) / 255.0
    image = image * (1.0 - dust[..., None] * 0.5) + pale * (dust[..., None] * 0.5)

    grain = white_noise(size, seed + 207)
    image *= (0.90 + 0.16 * grain)[..., None]
    image = paint_tint(image, patches, warm=0.05)

    # Cailloux peints (ombre portée + face éclairée + reflet).
    pebble_layer = Image.new("RGB", (size, size), (0, 0, 0))
    draw = ImageDraw.Draw(pebble_layer)
    stone_mid = (152, 145, 131)
    stone_light = (201, 193, 179)
    stone_dark = (62, 57, 49)

    def draw_pebble(d, px, py, r, sq):
        # ombre portée
        d.ellipse(
            [px - r + 1.4, py - r * sq + 1.8, px + r + 1.4, py + r * sq + 1.8],
            fill=stone_dark,
        )
        # pierre
        d.ellipse([px - r, py - r * sq, px + r, py + r * sq], fill=stone_mid)
        # lumière
        d.ellipse(
            [px - r * 0.60, py - r * sq * 0.70, px + r * 0.16, py - r * sq * 0.02],
            fill=stone_light,
        )

    # Petits cailloux nombreux, puis quelques pierres plus grosses.
    for _ in range(int(size * size / 2600)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(2.0, 4.6)
        squash = rng.uniform(0.55, 0.82)
        _draw_shifted(
            draw,
            size,
            x,
            y,
            lambda d, px, py, r=radius, sq=squash: draw_pebble(d, px, py, r, sq),
        )
    for _ in range(int(size * size / 14000)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        radius = rng.uniform(5.0, 9.5)
        squash = rng.uniform(0.6, 0.85)
        _draw_shifted(
            draw,
            size,
            x,
            y,
            lambda d, px, py, r=radius, sq=squash: draw_pebble(d, px, py, r, sq),
        )

    pebbles = np.asarray(pebble_layer).astype(np.float64) / 255.0
    image = _composite_layer(image, pebbles, strength=0.82)

    # Fissures / fines racines peintes.
    crack_layer = Image.new("RGB", (size, size), (0, 0, 0))
    crack_draw = ImageDraw.Draw(crack_layer)
    crack_color = tuple(int(c * 0.55) for c in palette["shadow"])
    for _ in range(int(size * size / 2600)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        angle = rng.uniform(0, math.tau)
        points = [(x, y)]
        for _segment in range(int(rng.integers(2, 5))):
            angle += rng.uniform(-0.8, 0.8)
            length = rng.uniform(3, 9)
            x += math.cos(angle) * length
            y += math.sin(angle) * length
            points.append((x, y))

        def crack(d, px, py, pts=points):
            d.line([(px + (sx - pts[0][0]), py + (sy - pts[0][1])) for sx, sy in pts],
                   fill=crack_color, width=1)

        _draw_shifted(crack_draw, size, points[0][0], points[0][1], crack)

    cracks = np.asarray(crack_layer).astype(np.float64) / 255.0
    image = _composite_layer(image, cracks, strength=0.55)

    # Gravier fin : points clairs/sombres.
    speckles = white_noise(size, seed + 208)
    image *= np.where(speckles > 0.986, 1.10, 1.0)[..., None]
    image *= np.where(speckles < 0.014, 0.88, 1.0)[..., None]

    image = wrap_filter(image, 0.4).copy()
    image = wrap_filter(image, 1.0, unsharp=True)
    return np.clip(image, 0.0, 1.0)


def build_stone(size: int, seed: int) -> np.ndarray:
    """Pavé irrégulier : cellules de Voronoï périodiques, biseaux et joints moussus."""
    palette = PALETTES["stone"]
    rng = _rng(seed + 31)

    cell_count = 150
    points = rng.random((cell_count, 2)) * size
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)

    nearest = np.full((size, size), np.inf)
    second = np.full((size, size), np.inf)
    nearest_id = np.zeros((size, size), dtype=np.int32)
    half = size * 0.5
    for index, (px, py) in enumerate(points):
        dx = (xs - px + half) % size - half
        dy = (ys - py + half) % size - half
        dist = np.sqrt(dx * dx + dy * dy)
        closer = dist < nearest
        second = np.where(closer, nearest, np.minimum(second, dist))
        nearest = np.where(closer, dist, nearest)
        nearest_id = np.where(closer, index, nearest_id)

    # Couleur par pierre : variation de teinte/tonalité marquée.
    cell_rng = _rng(seed + 32)
    cell_tint = cell_rng.random(cell_count)
    cell_warm = cell_rng.random(cell_count)
    tint = cell_tint[nearest_id]
    warm = cell_warm[nearest_id]

    edge = second - nearest
    joint_width = 3.0
    bevel_width = 16.0
    joint = np.clip(edge / joint_width, 0.0, 1.0)
    bevel = np.clip(edge / bevel_width, 0.0, 1.0)

    # Relief de la pierre : biseau + éclairage directionnel haut-gauche.
    grain_field = fbm(size, seed + 301, octaves=5, base_period=28)
    macro = fbm(size, seed + 302, octaves=4, base_period=4)
    direction = np.clip((bevel * 0.8 + 0.2) * (warm - 0.5) * 0.5, -0.15, 0.15)

    t = (
        0.30
        + 0.36 * bevel
        + 0.18 * (tint - 0.5) * 2.0
        + 0.14 * (grain_field - 0.5) * 2.0
        + 0.08 * (macro - 0.5) * 2.0
        + direction
    )
    t = np.clip(t, 0.0, 1.0)

    image = mix_color(
        [
            (0.0, palette["shadow"]),
            (0.28, palette["base"]),
            (0.64, palette["light"]),
            (0.90, palette["pale"]),
        ],
        t,
    )

    # Joints sombres + mousse dans les creux.
    image *= (0.34 + 0.66 * joint)[..., None]
    moss_mask = np.clip((0.30 - joint) * 4.0, 0.0, 1.0)
    moss_mask *= np.clip((macro - 0.35) * 2.0, 0.0, 1.0) * 0.30
    moss_color = np.asarray(PALETTES["grass"]["base"], dtype=np.float64) / 255.0
    image = image * (1.0 - moss_mask[..., None]) + moss_color * moss_mask[..., None]

    # Grain, taches d'humidité, petites touches claires.
    grain = white_noise(size, seed + 303)
    image *= (0.90 + 0.17 * grain)[..., None]
    damp = np.clip((0.42 - macro) * 2.2, 0.0, 1.0) * 0.18
    image *= (1.0 - damp[..., None] * 0.4)
    image = paint_tint(image, macro, warm=0.06)

    # Fissures fines sur quelques pierres.
    crack_layer = Image.new("RGB", (size, size), (0, 0, 0))
    crack_draw = ImageDraw.Draw(crack_layer)
    crack_color = tuple(int(c * 0.48) for c in palette["shadow"])
    for _ in range(int(size * size / 9000)):
        x = rng.uniform(0, size)
        y = rng.uniform(0, size)
        angle = rng.uniform(0, math.tau)
        points_list = [(x, y)]
        for _segment in range(int(rng.integers(2, 4))):
            angle += rng.uniform(-0.9, 0.9)
            length = rng.uniform(5, 13)
            x += math.cos(angle) * length
            y += math.sin(angle) * length
            points_list.append((x, y))

        def crack(d, px, py, pts=points_list):
            d.line([(px + (sx - pts[0][0]), py + (sy - pts[0][1])) for sx, sy in pts],
                   fill=crack_color, width=1)

        _draw_shifted(crack_draw, size, points_list[0][0], points_list[0][1], crack)

    cracks = np.asarray(crack_layer).astype(np.float64) / 255.0
    image = _composite_layer(image, cracks, strength=0.45)

    image = wrap_filter(image, 0.4).copy()
    image = wrap_filter(image, 1.0, unsharp=True)
    return np.clip(image, 0.0, 1.0)


def build_snow(size: int, seed: int) -> np.ndarray:
    """Neige blanc bleuté : grain fin, congères douces et éclats de glace."""
    palette = PALETTES["snow"]
    rng = _rng(seed + 41)

    drifts = fbm(size, seed + 401, octaves=5, base_period=3)
    clumps = fbm(size, seed + 402, octaves=4, base_period=7)
    medium = fbm(size, seed + 403, octaves=5, base_period=18)
    fine = fbm(size, seed + 404, octaves=3, base_period=64)
    dx = fbm(size, seed + 405, octaves=3, base_period=4)
    dy = fbm(size, seed + 406, octaves=3, base_period=5)

    field = 0.44 * drifts + 0.28 * clumps + 0.18 * medium + 0.10 * fine
    field = warp(field, dx, dy, strength=size * 0.035)
    # La neige reste très claire : contraste doux et niveau haut.
    t = 0.22 + 0.72 * contrast(field, strength=1.25)

    image = mix_color(
        [
            (0.0, palette["shadow"]),
            (0.30, palette["base"]),
            (0.66, palette["light"]),
            (0.90, palette["pale"]),
        ],
        t,
    )

    # Congères : crêtes légèrement plus claires, creux bleutés.
    crest = np.clip((drifts - 0.58) * 3.2, 0.0, 1.0) * 0.22
    pale = np.asarray(palette["pale"], dtype=np.float64) / 255.0
    image = image * (1.0 - crest[..., None]) + pale * crest[..., None]
    hollow = np.clip((0.42 - clumps) * 2.8, 0.0, 1.0) * 0.18
    accent = np.asarray(palette["accent"], dtype=np.float64) / 255.0
    image = image * (1.0 - hollow[..., None]) + accent * hollow[..., None]
    image = paint_tint(image, clumps, warm=-0.045)

    # Grain fin + éclats de glace (points très clairs).
    grain = white_noise(size, seed + 407)
    image *= (0.94 + 0.09 * grain)[..., None]
    sparkles = white_noise(size, seed + 408)
    image = np.where(
        (sparkles > 0.996)[..., None],
        np.minimum(1.0, image * 1.18 + 0.05),
        image,
    )
    icy = np.clip((medium - 0.72) * 4.0, 0.0, 1.0) * 0.10
    image = image * (1.0 - icy[..., None]) + accent * icy[..., None]

    image = wrap_filter(image, 0.45).copy()
    image = wrap_filter(image, 1.0, unsharp=True)
    return np.clip(image, 0.0, 1.0)


def build_sand(size: int, seed: int) -> np.ndarray:
    """Sable chaud : rides douces, grain fin, quelques cailloux et coquilles."""
    palette = PALETTES["sand"]
    rng = _rng(seed + 51)

    dunes = fbm(size, seed + 501, octaves=5, base_period=3)
    ripples = fbm(size, seed + 502, octaves=4, base_period=9)
    medium = fbm(size, seed + 503, octaves=4, base_period=22)
    fine = fbm(size, seed + 504, octaves=3, base_period=70)
    dx = fbm(size, seed + 505, octaves=3, base_period=4)
    dy = fbm(size, seed + 506, octaves=3, base_period=6)

    field = 0.40 * dunes + 0.30 * ripples + 0.20 * medium + 0.10 * fine
    field = warp(field, dx, dy, strength=size * 0.05)
    t = contrast(field, strength=1.5) * 0.88 + 0.06

    image = mix_color(
        [
            (0.0, palette["shadow"]),
            (0.32, palette["base"]),
            (0.66, palette["light"]),
            (0.90, palette["pale"]),
        ],
        t,
    )

    # Rides de sable : fines ondulations douces qui suivent le warp.
    wave = np.sin(
        (np.arange(size, dtype=np.float64)[None, :] + dx * size * 0.05)
        * (2.0 * math.pi * 9.0 / size)
    )
    ripple = (wave * 0.5 + 0.5) * 0.12
    light = np.asarray(palette["light"], dtype=np.float64) / 255.0
    image = image * (1.0 - ripple[..., None] * 0.5) + light * (ripple[..., None] * 0.5)
    image = paint_tint(image, ripples, warm=0.06)

    # Grain fin et petits cailloux clairs dispersés.
    grain = white_noise(size, seed + 507)
    image *= (0.92 + 0.13 * grain)[..., None]
    speckles = white_noise(size, seed + 508)
    image *= np.where(speckles > 0.988, 1.08, 1.0)[..., None]
    image *= np.where(speckles < 0.012, 0.90, 1.0)[..., None]

    pebble_layer = Image.new("RGB", (size, size), (0, 0, 0))
    draw = ImageDraw.Draw(pebble_layer)
    stone_mid = (188, 178, 158)
    stone_light = (222, 214, 196)
    stone_dark = (128, 112, 88)
    for _ in range(int(size * size / 9000)):
        cx = rng.uniform(0, size)
        cy = rng.uniform(0, size)
        radius = rng.uniform(1.8, 3.6)
        squash = rng.uniform(0.6, 0.9)

        def pebble(d, px, py, r=radius, sq=squash):
            d.ellipse([px - r + 1.0, py - r * sq + 1.4, px + r + 1.0, py + r * sq + 1.4],
                      fill=stone_dark)
            d.ellipse([px - r, py - r * sq, px + r, py + r * sq], fill=stone_mid)
            d.ellipse([px - r * 0.55, py - r * sq * 0.75, px + r * 0.1, py - r * sq * 0.05],
                      fill=stone_light)

        _draw_shifted(draw, size, cx, cy, pebble)

    pebbles = np.asarray(pebble_layer).astype(np.float64) / 255.0
    image = _composite_layer(image, pebbles, strength=0.55)

    image = wrap_filter(image, 0.4).copy()
    image = wrap_filter(image, 1.0, unsharp=True)
    return np.clip(image, 0.0, 1.0)


# --------------------------------------------------------------------------- #
# Vérification / planche
# --------------------------------------------------------------------------- #


def verify_texture(path: Path, expected_size: int) -> list[str]:
    """Contrôle taille, canaux et raccord (différence de bord vs voisinage)."""
    issues: list[str] = []
    if not path.is_file():
        return [f"{path.name} absent"]
    image = Image.open(path)
    if image.size != (expected_size, expected_size):
        issues.append(f"{path.name}: taille {image.size} != {expected_size}²")
    if image.mode != "RGB":
        issues.append(f"{path.name}: mode {image.mode} (attendu RGB)")
    array = np.asarray(image.convert("RGB")).astype(np.float64)
    seam_x = np.mean(np.abs(array[:, -1] - array[:, 0]))
    inside_x = np.mean([
        np.mean(np.abs(array[:, x] - array[:, x + 1]))
        for x in (100, 200, 300, 400)
    ])
    seam_y = np.mean(np.abs(array[-1, :] - array[0, :]))
    inside_y = np.mean([
        np.mean(np.abs(array[y, :] - array[y + 1, :]))
        for y in (100, 200, 300, 400)
    ])
    tolerance_x = max(inside_x * 3.0, 2.0)
    tolerance_y = max(inside_y * 3.0, 2.0)
    if seam_x > tolerance_x:
        issues.append(f"{path.name}: raccord X visible ({seam_x:.2f} > {tolerance_x:.2f})")
    if seam_y > tolerance_y:
        issues.append(f"{path.name}: raccord Y visible ({seam_y:.2f} > {tolerance_y:.2f})")
    print(
        f"[seam] {path.name:10s} X={seam_x:.2f} (voisin {inside_x:.2f}) "
        f"Y={seam_y:.2f} (voisin {inside_y:.2f})"
    )
    return issues


def build_preview(out_root: Path) -> Path | None:
    """Planche : chaque texture répétée en 2x2 pour vérifier le raccord."""
    names = [
        ("grass", "herbe"),
        ("dirt", "terre / chemin"),
        ("stone", "pavé de pierre"),
        ("snow", "neige"),
        ("sand", "sable"),
    ]
    tile = 280
    label_h = 34
    cell = tile + 12
    preview = Image.new("RGB", (cell * len(names) + 12, tile + label_h + 24), (232, 221, 198))
    draw = ImageDraw.Draw(preview)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 17)
    except OSError:
        try:
            font = ImageFont.load_default(size=17)
        except TypeError:  # Pillow < 10
            font = ImageFont.load_default()

    missing = 0
    for index, (name, label) in enumerate(names):
        path = out_root / f"{name}.png"
        x = 12 + index * cell
        if not path.is_file():
            missing += 1
            draw.text((x + 8, 40), f"{name}.png absent", font=font, fill=(160, 60, 50))
            continue
        texture = Image.open(path).convert("RGB").resize((tile, tile), Image.LANCZOS)
        tiled = Image.new("RGB", (tile, tile))
        half = tile // 2
        for ty in range(2):
            for tx in range(2):
                tiled.paste(texture.resize((half, half), Image.LANCZOS), (tx * half, ty * half))
        preview.paste(tiled, (x, 12))
        draw.rectangle([x, 12, x + tile - 1, 12 + tile - 1], outline=(150, 135, 110))
        draw.text((x + 4, 12 + tile + 6), label, font=font, fill=(74, 60, 44))

    preview_path = out_root / "_planche_terrain.png"
    preview.save(preview_path, "PNG", optimize=True)
    print(f"[OK] planche terrain: {preview_path}")
    return preview_path if missing == 0 else None


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def main() -> int:
    parser = argparse.ArgumentParser(description="Textures de sol tuilables 2.5D.")
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--out-root", default=str(TERRAIN_ROOT))
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--preview-only", action="store_true")
    args = parser.parse_args()

    size = max(128, min(2048, args.size))
    out_root = Path(args.out_root).resolve()
    out_root.mkdir(parents=True, exist_ok=True)

    if not args.preview_only:
        builders = {
            "grass": build_grass,
            "dirt": build_dirt,
            "stone": build_stone,
            "snow": build_snow,
            "sand": build_sand,
        }
        for name, builder in builders.items():
            image = builder(size, args.seed)
            path = out_root / f"{name}.png"
            Image.fromarray(
                (np.clip(image, 0, 1) * 255.0).astype(np.uint8)
            ).save(path, "PNG", optimize=True)
            thumb = Image.open(path).resize((THUMB_SIZE, THUMB_SIZE), Image.LANCZOS)
            thumb.save(out_root / f"{name}_thumb.png", "PNG", optimize=True)
            print(f"[OK] {path} ({path.stat().st_size / 1024.0:.1f} Ko) + thumb {THUMB_SIZE}px")

    issues: list[str] = []
    for name in ("grass", "dirt", "stone", "snow", "sand"):
        issues.extend(verify_texture(out_root / f"{name}.png", size))

    build_preview(out_root)

    if issues:
        for issue in issues:
            print(f"[ECHEC] {issue}")
        return 1
    print(f"TERRAIN_RESULT ok=5 textures={size}x{size} seamless=oui")
    return 0


if __name__ == "__main__":
    sys.exit(main())
