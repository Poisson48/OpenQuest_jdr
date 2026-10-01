#!/usr/bin/env python3
"""Genere les textures d'ambiance de la « table de taverne » via Gemini 2.5
Flash Image (Nano Banana) — sol, murs, feutrine, bois de repli.

Contexte : la table 3D (Meshy « Ironbound Oak Table ») a deja sa texture ;
ce script habille la SALLE autour (voir table_environment_3d.gd). Les fichiers
absents retombent sur des materiaux proceduraux — rien n'est bloquant.

Budget-first (copie du pipeline generate_props_gemini.py) :
  - hard cap images + --max-cost / --max-eur (defaut prudent)
  - modele le moins cher : gemini-2.5-flash-image (~$0.039 / image @ <=1K)
  - saute si fichier deja present
  - abort si pas de cle ou si cout estime > plafond

Usage (PowerShell) :
  $env:GEMINI_API_KEY = "votre_cle"   # ou GOOGLE_API_KEY
  python tools/generate_tabletop_gemini.py --dry-run
  python tools/generate_tabletop_gemini.py --max-eur 1.5

Ne stocke jamais la cle dans le depot.
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
OUT = ROOT / "game" / "assets" / "tabletop"

MODEL = "gemini-2.5-flash-image"
API_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
)
COST_PER_IMAGE_USD = 0.039
EUR_PER_USD = 0.92
HARD_MAX_IMAGES = 8
DEFAULT_MAX = 5
DEFAULT_MAX_COST_USD = 1.50

# References de style : la table (bois/fer) + la carte Valbois (palette monde).
REF_TABLE = ROOT / "game" / "assets" / "tabletop" / "models" / "ironbound_oak_table.png"
REF_MAP = ROOT / "game" / "assets" / "maps" / "valbois_village.png"

STYLE = (
    "Match the art direction of the attached references (Ironbound Oak table texture "
    "AND the Valbois fantasy map): medieval fantasy tavern, warm earthy palette "
    "(dark oak browns, ochre, soot black, iron grey), painterly hand-made surfaces, "
    "NO modern objects, NO text, NO watermark, NO UI. "
    "Flat texture sheet only, filling the entire frame edge to edge, evenly lit, "
    "seamless-ish (no vignette, no perspective, no objects casting shadows)."
)

ITEMS: list[dict[str, str]] = [
    {
        "file": "floor_planks.png",
        "prompt": (
            f"{STYLE} TOP-DOWN tavern FLOOR TEXTURE: wide dark oak planks with iron nails, "
            "worn matte finish, subtle saw marks and dust in the seams. "
            "Flat repeating wood floor texture, no furniture, no rug, no border."
        ),
    },
    {
        "file": "wall_plaster.png",
        "prompt": (
            f"{STYLE} FLAT tavern WALL TEXTURE: warm cream lime plaster with age stains, "
            "hairline cracks, faint smoke soot near the top. Muted warm tone. "
            "Flat wall surface only, no timber beams, no windows, no objects, no border."
        ),
    },
    {
        "file": "felt_rim.png",
        "prompt": (
            f"{STYLE} FLAT TABLE MAT TEXTURE: deep burgundy-brown wool felt / worn leather, "
            "fine fiber grain, slightly darker in the middle, cozy and matte. "
            "Flat fabric texture only, no objects, no stitching pattern, no border."
        ),
    },
    {
        "file": "table_wood.png",
        "prompt": (
            f"{STYLE} TOP-DOWN TABLE TOP TEXTURE: dark walnut/oak planks with subtle iron "
            "banding, candle wax stains and old ring marks, warm satin varnish. "
            "Flat repeating wood texture, no objects, no border."
        ),
    },
    {
        "file": "table_trim.png",
        "prompt": (
            f"{STYLE} FLAT WOOD TRIM TEXTURE: very dark stained oak with visible grain, "
            "used for table edges and chair backs, matte with worn highlights. "
            "Flat wood texture only, no shapes, no border."
        ),
    },
]


def resolve_api_key() -> str | None:
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_AI_API_KEY"):
        val = os.environ.get(name, "").strip()
        if val:
            return val
    return None


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


def _ref_part(path: Path, max_side: int = 640) -> dict | None:
    if not path.is_file():
        return None
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
            bg = Image.new("RGB", im.size, (32, 24, 16))
            bg.paste(im, mask=im.split()[-1])
            im = bg
        else:
            im = im.convert("RGB")
        im.save(buf, format="JPEG", quality=80)
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


def generate_one(api_key: str, prompt: str, timeout: int = 180) -> bytes:
    parts: list[dict] = []
    for ref in (REF_TABLE, REF_MAP):
        part = _ref_part(ref)
        if part:
            parts.append(part)
    parts.append({"text": prompt})

    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
    }
    req = urllib.request.Request(
        API_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
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
    try:
        from io import BytesIO

        from PIL import Image

        im = Image.open(BytesIO(raw))
        if im.mode != "RGBA":
            im = im.convert("RGBA")
        if max(im.size) > 1024:
            im.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        out = BytesIO()
        im.save(out, format="PNG")
        return out.getvalue()
    except Exception:
        return raw


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--max", type=int, default=DEFAULT_MAX, help="nb d'images max")
    ap.add_argument("--max-cost", type=float, default=DEFAULT_MAX_COST_USD, help="plafond USD")
    ap.add_argument("--max-eur", type=float, default=0.0, help="plafond EUR (prioritaire)")
    ap.add_argument("--dry-run", action="store_true", help="affiche le plan sans appeler l'API")
    ap.add_argument("--force", action="store_true", help="regarde meme si le fichier existe")
    args = ap.parse_args()

    hard_max = min(args.max, HARD_MAX_IMAGES)
    budget_usd = args.max_cost
    if args.max_eur > 0:
        budget_usd = min(budget_usd, args.max_eur / EUR_PER_USD)

    todo = [it for it in ITEMS[:hard_max] if args.force or not (OUT / it["file"]).is_file()]
    est = len(todo) * COST_PER_IMAGE_USD
    plan = OUT / "PLAN.txt"
    plan.parent.mkdir(parents=True, exist_ok=True)

    print(f"Sortie   : {OUT}")
    print(f"A faire  : {len(todo)} image(s) — cout estime ${est:.3f} (plafond ${budget_usd:.2f})")
    for it in todo:
        print(f"  - {it['file']}")

    if args.dry_run:
        print("DRY-RUN : aucun appel API.")
        return 0
    if not todo:
        print("Rien a generer (fichiers presents).")
        return 0
    if est > budget_usd + 1e-9:
        print("ABORT: cout estime > plafond. Releve --max-cost / --max-eur.")
        return 1
    api_key = resolve_api_key()
    if not api_key:
        print("ABORT: aucune cle (GEMINI_API_KEY / GOOGLE_API_KEY / GOOGLE_AI_API_KEY).")
        print('Exemple: $env:GEMINI_API_KEY = "votre_cle"')
        return 1

    ok = 0
    spent = 0.0
    for it in todo:
        if spent + COST_PER_IMAGE_USD > budget_usd + 1e-9:
            print(f"Plafond atteint (${spent:.3f}) — arret.")
            break
        dest = OUT / it["file"]
        print(f"-> {it['file']} ...", flush=True)
        try:
            raw = generate_one(api_key, it["prompt"])
        except Exception as exc:  # noqa: BLE001 — rapport synthetique
            print(f"   ECHEC: {exc}")
            continue
        if len(raw) < 2048:
            print(f"   ECHEC: image trop petite ({len(raw)} o) — ignoree.")
            continue
        dest.write_bytes(raw)
        spent += COST_PER_IMAGE_USD
        ok += 1
        print(f"   OK {dest} ({len(raw)} o)")
    print(f"Fait: {ok}/{len(todo)} — depense estimee ${spent:.3f}")
    return 0 if ok == len(todo) else 1


if __name__ == "__main__":
    sys.exit(main())
