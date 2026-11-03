#!/usr/bin/env python3
"""Génère une texture de chemin via Google Nano Banana / Gemini image.

La clé n'est jamais dans le dépôt : elle est lue dans
`%APPDATA%/OpenQuest_jdr/secrets/google_banana.key` (ou via
`GOOGLE_BANANA_API_KEY`). Sortie par défaut : game/assets/terrain/dirt_ai.png.

Usage :
  python tools/ai/generate_path_texture.py --prompt "seamless dirt path..." \
      --output game/assets/terrain/dirt_ai.png
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import urllib.request
from pathlib import Path

MODEL = "gemini-2.5-flash-image"
ENDPOINT = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"


def read_key() -> str:
    key = os.environ.get("GOOGLE_BANANA_API_KEY", "").strip()
    if key:
        return key
    appdata = os.environ.get("APPDATA")
    if appdata:
        path = Path(appdata) / "OpenQuest_jdr" / "secrets" / "google_banana.key"
        if path.exists():
            return path.read_text(encoding="utf-8").strip()
    raise SystemExit("Clé absente : définir GOOGLE_BANANA_API_KEY ou le fichier secrets/google_banana.key")


def generate(prompt: str, key: str) -> bytes:
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": "1:1"},
        },
    }
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as response:
        data = json.loads(response.read().decode("utf-8"))
    for part in data.get("candidates", [{}])[0].get("content", {}).get("parts", []):
        inline = part.get("inlineData") or {}
        if inline.get("data"):
            return base64.b64decode(inline["data"])
    raise SystemExit("Réponse sans image (vérifier le prompt/modèle)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--prompt",
        default=(
            "Seamless tileable top-down albedo texture for a medieval dirt footpath: "
            "packed earth, small gravel, subtle stones, worn center, warm natural browns, "
            "no shadows, no border, no text, game texture, 1024x1024, stylized."
        ),
    )
    parser.add_argument("--output", default="game/assets/terrain/dirt_ai.png")
    args = parser.parse_args()
    png = generate(args.prompt, read_key())
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)
    print(f"écrit {out} ({len(png)} octets)")


if __name__ == "__main__":
    main()
