#!/usr/bin/env python3
"""Génère des portraits Valbois (Aria, Thorin, PNJ clés) via Gemini Flash Image.

Usage:
  $env:GEMINI_API_KEY = "..."
  python scripts/generate_portraits_gemini.py --max-eur 2
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
OUT = ROOT / "game" / "assets" / "portraits"
REF_KAEL = OUT / "voleur_kael.png"
REF_MAP = ROOT / "game" / "assets" / "maps" / "valbois_village.png"

MODEL = "gemini-2.5-flash-image"
API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
COST_PER_IMAGE_USD = 0.039
EUR_PER_USD = 0.92

STYLE = (
    "Match the attached Kael portrait AND Valbois map style: medieval fantasy, "
    "muted earthy palette (browns, slate blue, olive), painterly clothes/leather. "
    "Full-body standing cutout, 3/4 view facing left, soft readable silhouette, "
    "dark solid background (no checkerboard, no white rectangle), no text, no watermark."
)

PORTRAITS = [
    {
        "file": "aria_sombrelame.png",
        "prompt": f"{STYLE} Female wood-elf ranger Aria: dark green hooded cloak, leather armor, short bow, long dark braided hair, calm focused look.",
    },
    {
        "file": "thorin.png",
        "prompt": f"{STYLE} Male dwarf warrior Thorin: thick beard, iron helmet, scale mail, war axe and round shield, stern expression.",
    },
    {
        "file": "maire_corbin.png",
        "prompt": f"{STYLE} Middle-aged male mayor in rich burgundy coat and gold chain of office, Valbois noble.",
    },
    {
        "file": "lyse_garde.png",
        "prompt": f"{STYLE} Female town guard Lyse with helmet and spear, militia of Valbois.",
    },
]


def api_key() -> str:
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_AI_API_KEY"):
        v = os.environ.get(name, "").strip()
        if v:
            return v
    return ""


def part_inline(path: Path, mime: str = "image/png") -> dict:
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return {"inline_data": {"mime_type": mime, "data": data}}


def generate(key: str, prompt: str) -> bytes:
    parts = [{"text": prompt}]
    if REF_KAEL.exists():
        parts.append(part_inline(REF_KAEL))
    if REF_MAP.exists():
        parts.append(part_inline(REF_MAP))
    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
    }
    req = urllib.request.Request(
        f"{API_URL}?key={key}",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=240) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
    for cand in payload.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                return base64.b64decode(inline["data"])
    raise RuntimeError("no image in response: %s" % json.dumps(payload)[:500])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-eur", type=float, default=2.0)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    key = api_key()
    if not key:
        print("ABORT: set GEMINI_API_KEY / GOOGLE_API_KEY", file=sys.stderr)
        return 2
    todo = [p for p in PORTRAITS if not (OUT / p["file"]).exists()]
    est = len(todo) * COST_PER_IMAGE_USD * EUR_PER_USD
    print(f"todo={len(todo)} est_eur={est:.2f} cap={args.max_eur}")
    if est > args.max_eur:
        print("ABORT: over budget", file=sys.stderr)
        return 3
    if args.dry_run:
        for p in todo:
            print("would", p["file"])
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for p in todo:
        print("gen", p["file"], "...", flush=True)
        try:
            png = generate(key, p["prompt"])
            (OUT / p["file"]).write_bytes(png)
            print("ok", p["file"], len(png))
        except Exception as e:
            print("FAIL", p["file"], e, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
