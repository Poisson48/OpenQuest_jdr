"""Recolore la texture d'albedo embarquee dans un GLB, sans toucher au maillage.

Usage :
  python tools/blender/recolor_glb.py --input IN --out OUT \
      --saturation 0.52 --value 0.86 --tint 0.55,0.60,0.61

Les textures glTF sont encodees en sRGB : la correction est appliquee dans cet
espace (comme dans un logiciel de retouche), puis re-encodee en PNG. Les autres
images (metallic/roughness, normale) sont recopiees telles quelles.

Le script est volontairement autonome (Pillow + numpy) : il ne requiert ni
Blender ni reimport du modele, et le GLB produit reste conforme glTF 2.0.
"""
from __future__ import annotations

import argparse
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def parse_glb(data: bytes) -> tuple[dict, bytes]:
    magic, version, _length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("ce n'est pas un GLB")
    if version != 2:
        raise ValueError(f"version glTF non supportee : {version}")
    offset = 12
    gltf: dict | None = None
    binary = b""
    while offset < len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + chunk_length]
        if chunk_type == CHUNK_JSON:
            gltf = json.loads(payload.decode("utf-8"))
        elif chunk_type == CHUNK_BIN:
            binary = payload
        offset += 8 + chunk_length
    if gltf is None:
        raise ValueError("chunk JSON absent")
    return gltf, binary


def pack_glb(gltf: dict, binary: bytes) -> bytes:
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + (8 + len(binary) if binary else 0)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(json_bytes), CHUNK_JSON)
    out += json_bytes
    if binary:
        out += struct.pack("<II", len(binary), CHUNK_BIN)
        out += binary
    return bytes(out)


def albedo_image_indices(gltf: dict) -> set[int]:
    """Indices d'images utilisees comme baseColorTexture."""
    indices: set[int] = set()
    textures = gltf.get("textures", [])
    for material in gltf.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        ref = pbr.get("baseColorTexture")
        if not isinstance(ref, dict):
            continue
        texture_index = int(ref.get("index", -1))
        if 0 <= texture_index < len(textures):
            source = textures[texture_index].get("source")
            if source is not None:
                indices.add(int(source))
    return indices


def recolor_image(data: bytes, saturation: float, value: float,
                  tint: tuple[float, float, float], quality: int = 92,
                  max_size: int = 0) -> tuple[bytes, str]:
    image = Image.open(io.BytesIO(data)).convert("RGB")
    if max_size and max(image.size) > max_size:
        ratio = max_size / float(max(image.size))
        image = image.resize(
            (max(1, round(image.width * ratio)), max(1, round(image.height * ratio))),
            Image.LANCZOS,
        )
    pixels = np.asarray(image, dtype=np.float32) / 255.0
    luminance = (pixels * np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).sum(axis=2)
    grey = np.repeat(luminance[:, :, None], 3, axis=2)
    pixels = grey + (pixels - grey) * saturation
    pixels = pixels * value
    pixels = pixels * np.array(tint, dtype=np.float32)
    pixels = np.clip(pixels, 0.0, 1.0)
    result = Image.fromarray((pixels * 255.0 + 0.5).astype(np.uint8), "RGB")
    buffer = io.BytesIO()
    # JPEG : les albedos Tripo sont photographiques, le gain de poids est
    # important et invisible sur une roche, sans couture ni alpha.
    result.save(buffer, format="JPEG", quality=quality, optimize=True, subsampling=0)
    return buffer.getvalue(), "image/jpeg"


def encode_texture(data: bytes, quality: int, max_size: int) -> bytes:
    """Redimensionne et ré-encode une texture utilitaire (normale, ORM) en JPEG."""
    image = Image.open(io.BytesIO(data)).convert("RGB")
    if max_size and max(image.size) > max_size:
        ratio = max_size / float(max(image.size))
        image = image.resize(
            (max(1, round(image.width * ratio)), max(1, round(image.height * ratio))),
            Image.LANCZOS,
        )
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality, optimize=True, subsampling=0)
    return buffer.getvalue()


def recolor_glb(source: Path, target: Path, saturation: float, value: float,
                tint: tuple[float, float, float], quality: int = 92,
                max_size: int = 0, optimize: bool = False) -> dict:
    gltf, binary = parse_glb(source.read_bytes())
    views = gltf.get("bufferViews", [])
    targets = albedo_image_indices(gltf)
    if not targets:
        raise ValueError(f"{source.name} : aucune baseColorTexture")
    images = gltf.get("images", [])
    replacements: dict[int, bytes] = {}
    for image_index, image in enumerate(images):
        view_index = int(image["bufferView"])
        view = views[view_index]
        start = int(view.get("byteOffset", 0))
        end = start + int(view["byteLength"])
        payload_bytes = binary[start:end]
        if image_index in targets:
            payload, mime = recolor_image(
                payload_bytes, saturation, value, tint, quality, max_size
            )
            image["mimeType"] = mime
            image.pop("uri", None)
        elif optimize:
            # Normale et ORM : le PNG 2048 pèse l'essentiel du fichier ; en JPEG
            # haute qualité il reste fidèle et ~8x plus léger.
            payload = encode_texture(payload_bytes, 95, max_size or 1024)
            image["mimeType"] = "image/jpeg"
            image.pop("uri", None)
        else:
            continue
        replacements[view_index] = payload

    # Reconstruit le tampon binaire en conservant l'ordre des bufferViews.
    rebuilt = bytearray()
    for index, view in enumerate(views):
        start = int(view.get("byteOffset", 0))
        length = int(view["byteLength"])
        payload = replacements.get(index)
        if payload is None:
            payload = binary[start : start + length]
        view["byteOffset"] = len(rebuilt)
        view["byteLength"] = len(payload)
        rebuilt += payload
        rebuilt += b"\x00" * ((4 - len(rebuilt) % 4) % 4)

    buffers = gltf.get("buffers") or [{}]
    buffers[0]["byteLength"] = len(rebuilt)
    buffers[0].pop("uri", None)
    gltf["buffers"] = buffers
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(pack_glb(gltf, bytes(rebuilt)))
    return {
        "source": source.name,
        "target": target.name,
        "textures_rewritten": len(replacements),
        "bytes_in": source.stat().st_size,
        "bytes_out": target.stat().st_size,
    }


def parse_tint(text: str) -> tuple[float, float, float]:
    parts = [float(part) for part in text.replace(";", ",").split(",") if part.strip()]
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("--tint attend trois valeurs r,g,b")
    return (parts[0], parts[1], parts[2])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--saturation", type=float, default=0.52)
    parser.add_argument("--value", type=float, default=0.86)
    parser.add_argument("--tint", type=parse_tint, default=(0.55, 0.60, 0.61))
    parser.add_argument("--quality", type=int, default=92)
    parser.add_argument("--max-size", type=int, default=0,
                        help="Redimensionne l'albedo a cette taille maximale (0 = inchange).")
    parser.add_argument("--optimize", action="store_true",
                        help="Recompresse aussi normale/ORM en JPEG (reduit fortement le poids).")
    parser.add_argument("--only", nargs="+", default=None)
    args = parser.parse_args()

    source_root = Path(args.input)
    out_root = Path(args.out)
    files = sorted(source_root.glob("*.glb"))
    if args.only:
        wanted = {name.lower() for name in args.only}
        files = [path for path in files if path.stem.lower() in wanted]
    if not files:
        print("[ERREUR] aucun GLB a traiter")
        return 2
    for path in files:
        report = recolor_glb(
            path, out_root / path.name, args.saturation, args.value, args.tint,
            args.quality, args.max_size, args.optimize
        )
        print(
            "[OK] {target}: {textures_rewritten} texture(s), {bytes_in} -> {bytes_out} o".format(
                **report
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
