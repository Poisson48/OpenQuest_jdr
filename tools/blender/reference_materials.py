"""Projection des échantillons d'image dans les couleurs de sommet des GLB."""

from pathlib import Path

import bpy
import numpy as np


class ReferenceMaterials:
    """Bois, pierre, toile et feuillage, lus dans la planche Valbois."""

    def __init__(self, path: Path):
        image = bpy.data.images.load(str(path))
        width, height = image.size
        if width != height or width < 128:
            raise ValueError("La planche de matières doit être carrée (au moins 128 px).")
        rgba = np.empty(width * height * 4, dtype=np.float32)
        image.pixels.foreach_get(rgba)
        pixels = rgba.reshape(height, width, 4)[..., :3]
        self.tiles = {}
        half = width // 2
        # Blender lit les pixels depuis le coin inférieur gauche.
        for name, x, y in (("wood", 0, 1), ("stone", 1, 1), ("cloth", 0, 0), ("leaf", 1, 0)):
            margin = max(4, half // 22)
            indices = np.linspace(margin, half - margin - 1, 144, dtype=int)
            patch = pixels[np.ix_(indices + y * half, indices + x * half)]
            luma = patch @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
            lo, hi = np.percentile(luma, [5, 95])
            self.tiles[name] = np.clip((luma - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
        bpy.data.images.remove(image)

    @staticmethod
    def family(name: str) -> str | None:
        if any(key in name for key in ("lamp", "flame", "glow", "water", "ink")):
            return None
        if any(key in name for key in ("leaf", "grass", "mousse", "reed", "blossom")):
            return "leaf"
        if any(key in name for key in ("wood", "bois_flotte", "hay", "wicker", "chaume", "fibre", "cernes")):
            return "wood"
        if any(key in name for key in ("cloth", "robe", "skin", "hair", "smoke")):
            return "cloth"
        return "stone"

    def apply(self, obj, name: str, seed: int) -> None:
        mesh = obj.data
        ao = mesh.color_attributes["Col"]
        shades = np.empty(len(ao.data) * 4, dtype=np.float32)
        ao.data.foreach_get("color", shades)
        shades = shades.reshape(-1, 4)
        mesh.color_attributes.remove(ao)
        color = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        output = np.ones((len(mesh.loops), 4), dtype=np.float32)
        for poly in mesh.polygons:
            material = mesh.materials[poly.material_index]
            family = self.family(material.name.lower().removeprefix(name + "_")) if material else None
            normal = poly.normal
            axis = max(range(3), key=lambda i: abs(normal[i]))
            u_axis, v_axis = ((1, 2), (0, 2), (0, 1))[axis]
            for loop_index in poly.loop_indices:
                vertex = mesh.loops[loop_index].vertex_index
                shade = shades[vertex, 0]
                if family is not None:
                    p = mesh.vertices[vertex].co
                    u_scale, v_scale = (0.72, 1.4) if family == "wood" else (0.9, 0.9)
                    u = (p[u_axis] * u_scale + seed * 0.073) % 2.0
                    v = (p[v_axis] * v_scale + seed * 0.113) % 2.0
                    tile = self.tiles[family]
                    sample = tile[round(min(v, 2.0 - v) * 143), round(min(u, 2.0 - u) * 143)]
                    shade *= 0.82 + 0.24 * float(sample)
                output[loop_index, :3] = min(1.0, shade)
        color.data.foreach_set("color", output.ravel())
        mesh.color_attributes.active_color_index = 0
        mesh.color_attributes.render_color_index = 0
