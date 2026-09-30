#!/usr/bin/env python3
"""Génère des versions nocturnes de battlemaps via Gemini (ou fallback procédural).

Budget-first:
  - hard cap 3 images (village + place + 1 optionnel)
  - modèle gemini-2.5-flash-image
  - abort API sans clé ; fallback offline toujours disponible
  - saute si *_night.png existe déjà (sauf --force)

Usage (PowerShell):
  $env:GEMINI_API_KEY = "votre_cle"   # ou GOOGLE_API_KEY
  python scripts/generate_map_night_gemini.py
  python scripts/generate_map_night_gemini.py --procedural-only
  python scripts/generate_map_night_gemini.py --dry-run

Ne stocke jamais la clé dans le dépôt.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAPS = ROOT / "game" / "assets" / "maps"

MODEL = "gemini-2.5-flash-image"
API_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
)
COST_PER_IMAGE_USD = 0.039
EUR_PER_USD = 0.92
HARD_MAX_IMAGES = 3
DEFAULT_MAX = 2
DEFAULT_MAX_COST_USD = 0.20

# Cartes Valbois (exactement layout jour → nuit).
DEFAULT_JOBS: list[dict[str, str]] = [
    {"file": "valbois_village.png", "out": "valbois_village_night.png"},
    {"file": "place_du_marche.png", "out": "place_du_marche_night.png"},
]

NIGHT_PROMPT = (
    "You are regenerating a fantasy RPG battlemap for a VTT night scene. "
    "The attached image is the DAY reference. Produce EXACTLY the same map: "
    "identical composition, buildings, roads, trees, labels, legend/cartouche, "
    "compass, and proportions — pixel-aligned layout as much as possible. "
    "Change ONLY lighting/mood to nighttime: cool moonlight, dark roofs and "
    "shadows, muted parchment ground, optional warm lit windows. "
    "Keep the same art style (ink outlines, soft watercolor). "
    "No new buildings, no moved labels, no watermark, no UI chrome. "
    "Output a full-bleed map image matching the reference framing."
)


def resolve_api_key() -> str | None:
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_AI_API_KEY"):
        val = os.environ.get(name, "").strip()
        if val:
            return val
    return None


def estimate_cost(n: int) -> float:
    return round(n * COST_PER_IMAGE_USD, 4)


def extract_image_b64(payload: dict) -> tuple[str | None, str | None]:
    for cand in payload.get("candidates") or []:
        content = cand.get("content") or {}
        for part in content.get("parts") or []:
            inline = part.get("inlineData") or part.get("inline_data")
            if not inline:
                continue
            data = inline.get("data")
            mime = inline.get("mimeType") or inline.get("mime_type") or "image/png"
            if data:
                return data, mime
    return None, None


def procedural_night(day_path: Path) -> bytes:
    """Assombrit / désature l'image jour — démo offline sans API."""
    from io import BytesIO

    from PIL import Image, ImageEnhance

    im = Image.open(day_path)
    if im.mode not in ("RGB", "RGBA"):
        im = im.convert("RGBA")
    has_alpha = im.mode == "RGBA"
    alpha = im.split()[-1] if has_alpha else None
    rgb = im.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(0.45)
    rgb = ImageEnhance.Brightness(rgb).enhance(0.38)
    # Voile bleu-nuit léger
    overlay = Image.new("RGB", rgb.size, (18, 28, 55))
    rgb = Image.blend(rgb, overlay, 0.28)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.12)
    if has_alpha and alpha is not None:
        out_im = rgb.convert("RGBA")
        out_im.putalpha(alpha)
    else:
        out_im = rgb
    buf = BytesIO()
    out_im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def _day_ref_part(path: Path, max_side: int = 1280) -> dict:
    raw = path.read_bytes()
    mime = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
    try:
        from io import BytesIO

        from PIL import Image

        im = Image.open(BytesIO(raw))
        if im.mode not in ("RGB", "RGBA"):
            im = im.convert("RGBA")
        if max(im.size) > max_side:
            im.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
        buf = BytesIO()
        if im.mode == "RGBA":
            bg = Image.new("RGB", im.size, (30, 28, 40))
            bg.paste(im, mask=im.split()[-1])
            im = bg
        else:
            im = im.convert("RGB")
        im.save(buf, format="JPEG", quality=88)
        raw = buf.getvalue()
        mime = "image/jpeg"
    except Exception:
        pass
    return {
        "inline_data": {
            "mime_type": mime,
            "data": base64.b64encode(raw).decode("ascii"),
        }
    }


def generate_night_gemini(api_key: str, day_path: Path, timeout: int = 240) -> bytes:
    parts = [_day_ref_part(day_path), {"text": NIGHT_PROMPT}]
    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:800]
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc

    b64, _mime = extract_image_b64(payload)
    if not b64:
        raise RuntimeError(f"Pas d'image dans la reponse: {json.dumps(payload)[:500]}")
    raw = base64.b64decode(b64)
    # Normaliser PNG ; conserver taille proche du jour si possible
    try:
        from io import BytesIO

        from PIL import Image

        day = Image.open(day_path)
        night = Image.open(BytesIO(raw))
        if night.mode != "RGBA":
            night = night.convert("RGBA")
        if day.size != night.size and day.size[0] > 0:
            night = night.resize(day.size, Image.Resampling.LANCZOS)
        out = BytesIO()
        night.save(out, format="PNG", optimize=True)
        return out.getvalue()
    except Exception:
        return raw


def planned_jobs(max_images: int, force: bool) -> list[dict[str, Path]]:
    jobs: list[dict[str, Path]] = []
    for item in DEFAULT_JOBS:
        if len(jobs) >= max_images:
            break
        src = MAPS / item["file"]
        dest = MAPS / item["out"]
        if not src.is_file():
            print(f"skip missing day map {src}")
            continue
        if dest.exists() and not force:
            print(f"skip existing {dest.name}")
            continue
        jobs.append({"src": src, "dest": dest, "name": item["file"]})
    return jobs


def main() -> int:
    parser = argparse.ArgumentParser(description="Night battlemaps via Gemini or procedural")
    parser.add_argument("--max", type=int, default=DEFAULT_MAX, help=f"Max images (default {DEFAULT_MAX}, hard {HARD_MAX_IMAGES})")
    parser.add_argument("--max-cost", type=float, default=DEFAULT_MAX_COST_USD)
    parser.add_argument("--max-eur", type=float, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument(
        "--procedural-only",
        action="store_true",
        help="Never call Gemini; write darkened day images as *_night.png",
    )
    parser.add_argument(
        "--input",
        type=str,
        default=None,
        help="Optional single day PNG path (output = <stem>_night.png beside it or under assets/maps)",
    )
    args = parser.parse_args()

    max_images = max(0, min(args.max, HARD_MAX_IMAGES))
    max_cost_usd = float(args.max_cost)
    if args.max_eur is not None:
        from_eur = float(args.max_eur) / max(EUR_PER_USD, 0.01)
        max_cost_usd = min(max_cost_usd, from_eur)

    print(f"Model: {MODEL}")
    print(f"Output root: {MAPS}")
    print(f"Budget ceiling: ~${max_cost_usd:.2f} USD")

    if args.input:
        src = Path(args.input)
        if not src.is_file():
            print(f"ABORT: input missing {src}", file=sys.stderr)
            return 2
        dest = src.with_name(f"{src.stem}_night{src.suffix}")
        jobs = [{"src": src, "dest": dest, "name": src.name}]
    else:
        jobs = planned_jobs(max_images, args.force)

    api_key = None if args.procedural_only else resolve_api_key()
    use_api = bool(api_key) and not args.procedural_only

    if not use_api:
        print(
            "INFO: pas de clé API (ou --procedural-only) — "
            "génération procédurale (assombrissement). "
            "Pour du HQ Gemini: GEMINI_API_KEY / GOOGLE_API_KEY."
        )

    cost = estimate_cost(len(jobs) if use_api else 0)
    print(f"Planned: {len(jobs)}  API est~${cost}")
    if use_api and cost > max_cost_usd:
        print(f"ABORT: estimated ${cost} > ceiling ${max_cost_usd:.2f}")
        return 3
    if not jobs:
        print("Nothing to do.")
        return 0

    spent = 0.0
    ok = 0
    for i, job in enumerate(jobs, 1):
        src: Path = job["src"]
        dest: Path = job["dest"]
        print(f"[{i}/{len(jobs)}] {src.name} -> {dest.name}")
        if args.dry_run:
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            if use_api:
                if spent + COST_PER_IMAGE_USD > max_cost_usd + 1e-9:
                    print(f"Stop early: budget (spent~${spent:.3f}). Falling back procedural for rest.")
                    use_api = False
                else:
                    png = generate_night_gemini(api_key, src)
                    spent += COST_PER_IMAGE_USD
            if not use_api or args.procedural_only:
                png = procedural_night(src)
            dest.write_bytes(png)
            ok += 1
            print(f"  saved {dest} ({len(png)} bytes)")
        except Exception as exc:
            print(f"  FAIL Gemini: {exc}", file=sys.stderr)
            print("  Falling back to procedural night…")
            try:
                png = procedural_night(src)
                dest.write_bytes(png)
                ok += 1
                print(f"  saved procedural {dest} ({len(png)} bytes)")
            except Exception as exc2:
                print(f"  FAIL procedural: {exc2}", file=sys.stderr)
                return 4

    print(f"Done. ok={ok} api_spent~${spent:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
