#!/usr/bin/env python3
"""Genere une carte Valbois au RATIO EXACT du plateau de la table 3D
(Meshy « Ironbound Oak Table » : 1,899 x 1,022 → 1,857:1).

Pipeline : Gemini 2.5 Flash Image (Nano Banana) en composition large (16:9),
reference de style = la carte Valbois actuelle, puis recadrage PIL au ratio
table. 2 candidats produits — on garde le meilleur.

Usage (PowerShell) :
  $env:GEMINI_API_KEY = "votre_cle"   # ou GOOGLE_API_KEY
  python tools/generate_valbois_table_map.py
  python tools/generate_valbois_table_map.py --candidates 1

Sortie : game/assets/maps/valbois_table_map.png (+ valbois_table_map_c*.png)
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from io import BytesIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "game" / "assets" / "maps"
REF_MAP = OUT_DIR / "valbois_village.png"

MODEL = "gemini-3-pro-image-preview"  # Nano Banana Pro (Gemini 3 Pro Image)
MODEL_FALLBACK = "gemini-2.5-flash-image"  # Nano Banana
API_ROOT = "https://generativelanguage.googleapis.com/v1beta/models"
COST_PER_IMAGE_USD = 0.134  # Nano Banana Pro 2K (~$0.134 / image)
COST_FALLBACK_USD = 0.039

# Ratio du plateau de table (AABB modèle : 1.898918 x 1.022444).
TABLE_RATIO = 1.898918 / 1.022444  # ≈ 1.8572
TARGET_W = 2048  # largeur cible après recadrage (2K)
TARGET_H = int(round(TARGET_W / TABLE_RATIO))  # ≈ 1103

PROMPT = (
    "Recreate the attached Valbois village map as a NEW WIDE 16:9 LANDSCAPE map "
    "for a tabletop RPG board. Keep EXACTLY the same art style: classic fantasy RPG "
    "illustrated map, fine dark ink outlines, soft watercolor washes, warm parchment "
    "and beige ground tones, muted earthy greens and browns, top-down bird's-eye "
    "dimetric view, cozy medieval village. "
    "Same world and same landmarks, re-composed to FILL a wide 16:9 frame edge to edge: "
    "a river with a waterfall on the left, the village wall with a southern gate, "
    "windmill (Moulin), stone temple with blue roof (Temple d'Eliandre), blacksmith "
    "forge with smoking chimney (Forge), timber-framed inn (Taverne du Cerf), "
    "central market square with stone fountain and striped stalls (Place du Marche), "
    "stables (Ecuries), armory (Armurier), bakery (Boulangerie), bookshop (Librairie), "
    "tailor (Tailleur), mayor's house (Maison du Maire), herbalist with purple roof "
    "(Pharmacie / Herboriste), forest paths leaving the village. "
    "Include the ornate parchment title cartouche top-left reading exactly "
    "'VALBOIS' with subtitle 'Village de l'Ouest', the legend cartouche bottom-left "
    "(Bâtiment / Commerce-Service / Lieu d'intérêt / Sortie de village) and the "
    "compass rose top-right. Small beige label cartouches next to each landmark "
    "with the French names above. "
    "CRITICAL: 16:9 widescreen composition filling the whole frame — never square, "
    "never letterboxed, no white margins. "
    "CRITICAL: every cartouche, label, the compass and the legend must sit fully "
    "INSIDE the frame with a clear margin — nothing may touch or cross the edges; "
    "leave a small safe border of plain ground all around. Spell every French "
    "label correctly and legibly. "
    "Hand-painted illustration only "
    "(not a photo, not a 3D render). No watermark, no UI, no extra text."
)


def resolve_api_key() -> str | None:
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_AI_API_KEY"):
        val = os.environ.get(name, "").strip()
        if val:
            return val
    return None


def extract_image_b64(payload: dict) -> bytes | None:
    for cand in payload.get("candidates") or []:
        content = cand.get("content") or {}
        for part in content.get("parts") or []:
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                return base64.b64decode(inline["data"])
    return None


def _ref_part(path: Path, max_side: int = 768) -> dict | None:
    if not path.is_file():
        print(f"WARN: reference absente {path}")
        return None
    raw = path.read_bytes()
    try:
        from PIL import Image

        im = Image.open(BytesIO(raw))
        if im.mode not in ("RGB", "RGBA"):
            im = im.convert("RGB")
        else:
            im = im.convert("RGB")
        if max(im.size) > max_side:
            im.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
        buf = BytesIO()
        im.save(buf, format="JPEG", quality=84)
        raw = buf.getvalue()
    except Exception:
        pass
    return {
        "inline_data": {
            "mime_type": "image/jpeg",
            "data": base64.b64encode(raw).decode("ascii"),
        }
    }


def generate_one(api_key: str, timeout: int = 300) -> tuple[bytes, str]:
    """Tente Nano Banana Pro (16:9 natif 2K) puis replis. Retourne (png, modele)."""
    parts: list[dict] = []
    ref = _ref_part(REF_MAP)
    if ref:
        parts.append(ref)
    parts.append({"text": PROMPT})
    base_body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]},
    }
    attempts = [
        (MODEL, {"imageConfig": {"aspectRatio": "16:9", "imageSize": "2K"}}),
        (MODEL, {}),
        (MODEL_FALLBACK, {}),
    ]
    last_err: Exception | None = None
    for model, extra in attempts:
        body = json.loads(json.dumps(base_body))
        body["generationConfig"].update(extra)
        req = urllib.request.Request(
            f"{API_ROOT}/{model}:generateContent",
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:400]
            last_err = RuntimeError(f"{model} HTTP {exc.code}: {detail}")
            print(f"   [{model}] {last_err} — tentative suivante...")
            continue
        raw = extract_image_b64(payload)
        if raw:
            return raw, model
        last_err = RuntimeError(f"{model}: pas d'image dans la reponse")
        print(f"   [{model}] {last_err} — tentative suivante...")
    raise last_err or RuntimeError("aucune generation")


def crop_to_table_ratio(raw: bytes) -> bytes:
    """Recadre au ratio table (1,857:1) — micro-crop (~4% de hauteur max) :
    avec 16:9 natif + marges de sécurité demandées, rien d'important n'est coupé."""
    from PIL import Image

    im = Image.open(BytesIO(raw))
    if im.mode not in ("RGB", "RGBA"):
        im = im.convert("RGB")
    w, h = im.size
    cur = w / h
    if cur > TABLE_RATIO:
        # Trop large : on coupe les côtés.
        new_w = int(round(h * TABLE_RATIO))
        x0 = (w - new_w) // 2
        im = im.crop((x0, 0, x0 + new_w, h))
    else:
        # Trop haut : on coupe haut/bas (le centre du village est gardé).
        new_h = int(round(w / TABLE_RATIO))
        y0 = (h - new_h) // 2
        im = im.crop((0, y0, w, y0 + new_h))
    if abs(im.width - TARGET_W) > 16:
        scale = TARGET_W / im.width
        im = im.resize(
            (TARGET_W, int(round(im.height * scale))), Image.Resampling.LANCZOS
        )
    out = BytesIO()
    im.save(out, format="PNG")
    return out.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--candidates", type=int, default=2, help="nb d'images a generer")
    args = ap.parse_args()

    api_key = resolve_api_key()
    if not api_key:
        print("ABORT: aucune cle (GEMINI_API_KEY / GOOGLE_API_KEY / GOOGLE_AI_API_KEY).")
        return 1

    n = max(1, min(args.candidates, 3))
    print(f"Modele   : {MODEL} (repli {MODEL_FALLBACK})")
    print(f"Table ratio = {TABLE_RATIO:.4f} (cible ~{TARGET_W}x{TARGET_H})")
    print(f"{n} candidat(s) — cout estime ${n * COST_PER_IMAGE_USD:.3f}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    made: list[Path] = []
    for i in range(n):
        print(f"-> candidat {i + 1}/{n} ...", flush=True)
        try:
            raw, model = generate_one(api_key)
        except Exception as exc:  # noqa: BLE001
            print(f"   ECHEC: {exc}")
            continue
        if len(raw) < 4096:
            print(f"   ECHEC: image trop petite ({len(raw)} o)")
            continue
        cropped = crop_to_table_ratio(raw)
        cand = OUT_DIR / f"valbois_table_map_c{i + 1}.png"
        cand.write_bytes(cropped)
        made.append(cand)
        print(f"   OK [{model}] {cand} ({len(cropped)} o)")

    if not made:
        print("Aucun candidat genere.")
        return 1
    # Le premier candidat devient la carte active.
    final = OUT_DIR / "valbois_table_map.png"
    final.write_bytes(made[0].read_bytes())
    print(f"Carte active : {final} (+ {len(made)} candidat(s) a comparer)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
