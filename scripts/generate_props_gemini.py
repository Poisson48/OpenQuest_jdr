#!/usr/bin/env python3
"""Génère un petit lot de props VTT via Gemini 2.5 Flash Image (Nano Banana).

Budget-first:
  - hard cap images + --max-cost / --max-eur (défaut prudent)
  - modèle le moins cher: gemini-2.5-flash-image (~$0.039 / image @ ≤1K)
  - saute si fichier déjà présent
  - abort si pas de clé ou si coût estimé > plafond

Usage (PowerShell):
  $env:GEMINI_API_KEY = "votre_cle"   # ou GOOGLE_API_KEY
  python scripts/generate_props_gemini.py --max 28 --max-eur 5
  python scripts/generate_props_gemini.py --dry-run

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
PROPS = ROOT / "game" / "data" / "props"

MODEL = "gemini-2.5-flash-image"
API_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
)
# Tarif officiel approx. (paid tier, image ≤1024): $0.039 / image
COST_PER_IMAGE_USD = 0.039
EUR_PER_USD = 0.92  # conversion prudente pour plafonds EUR
HARD_MAX_IMAGES = 40
DEFAULT_MAX = 10
DEFAULT_MAX_COST_USD = 4.50  # plafond, pas une cible de depense

# Style Valbois (carte) + Kael (perso) — refs image envoyees a l'API.
REF_MAP = ROOT / "game" / "assets" / "maps" / "valbois_village.png"
REF_CHAR = ROOT / "game" / "assets" / "portraits" / "voleur_kael.png"

STYLE_MAP = (
    "Match EXACTLY the art style of the attached Valbois village map reference: "
    "classic fantasy RPG illustrated map, fine dark ink outlines, soft watercolor washes, "
    "warm parchment/beige ground tones, muted earthy greens and browns, "
    "isometric / bird's-eye dimetric view (same angle as the map buildings), "
    "timber-framed walls, tiled or thatch roofs, cozy medieval village. "
    "Transparent background only (no parchment sheet, no map labels, no legend, no compass). "
    "CRITICAL: real PNG alpha transparency — NEVER draw a gray/white checkerboard, NEVER a solid white/beige backdrop. "
    "Single centered prop cutout, readable at small size on a VTT map, ~512px. "
    "No text, no watermark, no UI."
)

STYLE_CHAR = (
    "Match the attached Valbois map AND the attached character portrait (Kael): "
    "same medieval fantasy world, muted earthy palette (browns, slate blue, olive), "
    "painterly textured clothes/leather like Kael, but drawn as a standing map token cutout "
    "compatible with the illustrated village map (readable silhouette, soft edges). "
    "Transparent background, front-ish 3/4 view, no text, no watermark, ~512px. "
    "CRITICAL: real PNG alpha — never paint a checkerboard or white rectangle behind the character."
)

TINY_BYTES = 2048

# Petit lot utile pour tester la biblio (pas le plafond budget).
CURATED: list[dict[str, str]] = [
    {"category": "buildings", "file": "forge_valbois.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Blacksmith forge building with rusty-red tiled roof, chimney smoke, timber framing — like the Forge on the Valbois map."},
    {"category": "buildings", "file": "moulin_valbois.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Village windmill with straw/yellow thatch-like roof and wooden sails — like the Moulin on the Valbois map."},
    {"category": "buildings", "file": "temple_eliandre.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Small stone temple/chapel with blue roof and simple steeple — like Temple d'Eliandre on the Valbois map."},
    {"category": "objects", "file": "fontaine_marche.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Circular stone market fountain with water basin — like the Place du Marche fountain."},
    {"category": "vehicles", "file": "etale_marche.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Small market stall with striped awning (blue/white or red/white), wooden counter — like Valbois market stalls."},
    {"category": "nature", "file": "arbre_valbois.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Dense rounded oak/forest tree cluster in muted olive greens — same foliage style as Valbois woods."},
    {"category": "vehicles", "file": "charrette_valbois.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Wooden merchant cart/wagon, isometric bird's-eye compatible with the map."},
    {"category": "furniture", "file": "tonneau_valbois.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Wooden barrel and crate stack, ink+watercolor, isometric-friendly cutout."},
    {"category": "characters", "file": "paysan_valbois.png", "kind": "char",
     "prompt": f"{STYLE_CHAR} Simple medieval villager / peasant of Valbois in tunic, friendly NPC token."},
    {"category": "characters", "file": "garde_valbois.png", "kind": "char",
     "prompt": f"{STYLE_CHAR} Town guard with helmet and spear/halberd, same world as Kael but local militia."},
]

# Lot classique VTT : manques + placeholders trop légers (herbe, porte, auberge…).
CLASSIC: list[dict[str, str]] = [
    {"category": "objects", "file": "porte_bois.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Wooden medieval door / cemetery gate cutout, dark oak planks, iron hinges, isometric-friendly, no frame around it."},
    {"category": "objects", "file": "torche.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Single wall torch on a wooden stake, warm flame, iron basket, isometric-friendly cutout."},
    {"category": "objects", "file": "feu_camp.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Small campfire with stones and wood, soft flame, isometric-friendly cutout."},
    {"category": "ground", "file": "herbe.png", "kind": "map",
     "prompt": (
         f"{STYLE_MAP} ONLY a square top-down GRASS GROUND TILE: muted olive/moss turf, "
         "soft watercolor blades, no well, no building, no object, no people, no path. "
         "Flat terrain texture filling the frame, seamless-ish, no border."
     )},
    {"category": "ground", "file": "chemin.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Square dirt path / packed earth ground tile, warm brown, top-down, no border."},
    {"category": "ground", "file": "pave.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Square cobblestone paving tile, muted grey-brown stones, top-down, no border."},
    {"category": "buildings", "file": "auberge.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Cozy timber-framed inn with hanging sign, tiled roof, isometric village building."},
    {"category": "buildings", "file": "maison.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Simple timber-framed village house with thatch or tile roof, isometric."},
    {"category": "buildings", "file": "tour.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Small stone watchtower with conical roof, isometric village tower."},
    {"category": "objects", "file": "puits.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Village stone well with wooden roof and bucket, isometric cutout."},
    {"category": "objects", "file": "lampe.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Iron street lamp / lantern on a wooden post, warm glow, isometric cutout."},
    {"category": "objects", "file": "caisse.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Closed wooden crate, iron bands, isometric cutout."},
    {"category": "nature", "file": "arbre.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Single rounded oak tree, muted olive canopy, isometric-friendly cutout."},
    {"category": "nature", "file": "buisson.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Small leafy bush, muted greens, isometric cutout."},
    {"category": "nature", "file": "rocher.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Grey mossy boulder / rock cluster, isometric cutout."},
    {"category": "furniture", "file": "table.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Rustic wooden table, slight top-down angle, isometric-friendly cutout."},
    {"category": "furniture", "file": "banc.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Simple wooden bench, weathered planks, isometric-friendly cutout."},
    {"category": "furniture", "file": "tonneau.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Single wooden barrel, iron hoops, isometric cutout."},
    {"category": "characters", "file": "villageois.png", "kind": "char",
     "prompt": f"{STYLE_CHAR} Simple medieval villager token, tunic and cloak, friendly NPC."},
    {"category": "characters", "file": "garde.png", "kind": "char",
     "prompt": f"{STYLE_CHAR} Town guard with helmet and short spear, local militia token."},
    {"category": "vehicles", "file": "charrette.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Simple wooden cart, two wheels, isometric-friendly cutout."},
    {"category": "vehicles", "file": "char_de_guerre.png", "kind": "map",
     "prompt": f"{STYLE_MAP} Small wooden war wagon / chariot, isometric-friendly cutout."},
]



def resolve_api_key() -> str | None:
    for name in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_AI_API_KEY"):
        val = os.environ.get(name, "").strip()
        if val:
            return val
    return None


def estimate_cost(n: int) -> float:
    return round(n * COST_PER_IMAGE_USD, 4)


def extract_image_b64(payload: dict) -> tuple[str | None, str | None]:
    """Retourne (base64, mime) ou (None, None)."""
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


def _ref_part(path: Path, max_side: int = 768) -> dict | None:
    if not path.is_file():
        print(f"WARN: missing style ref {path}")
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
        # JPEG plus leger pour la carte de reference
        if im.mode == "RGBA":
            bg = Image.new("RGB", im.size, (245, 236, 210))
            bg.paste(im, mask=im.split()[-1])
            im = bg
        else:
            im = im.convert("RGB")
        im.save(buf, format="JPEG", quality=82)
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


def generate_one(api_key: str, prompt: str, kind: str = "map", timeout: int = 180) -> bytes:
    parts: list[dict] = []
    map_part = _ref_part(REF_MAP)
    if map_part:
        parts.append(map_part)
    if kind == "char":
        char_part = _ref_part(REF_CHAR, max_side=512)
        if char_part:
            parts.append(char_part)
    parts.append({"text": prompt})

    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
        },
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

    b64, mime = extract_image_b64(payload)
    if not b64:
        raise RuntimeError(f"Pas d'image dans la reponse: {json.dumps(payload)[:500]}")
    raw = base64.b64decode(b64)
    try:
        from io import BytesIO

        from PIL import Image

        im = Image.open(BytesIO(raw))
        if im.mode != "RGBA":
            im = im.convert("RGBA")
        max_side = 512
        if max(im.size) > max_side:
            im.thumbnail((max_side, max_side), Image.Resampling.LANCZOS)
        out = BytesIO()
        im.save(out, format="PNG")
        return out.getvalue()
    except Exception:
        return raw


def _is_tiny(path: Path) -> bool:
    try:
        return path.exists() and path.stat().st_size < TINY_BYTES
    except OSError:
        return False


def planned_jobs(max_images: int, force: bool, pack: list[dict[str, str]], replace_tiny: bool) -> list[dict[str, str]]:
    jobs: list[dict[str, str]] = []
    for item in pack:
        if len(jobs) >= max_images:
            break
        dest = PROPS / item["category"] / item["file"]
        if dest.exists() and not force:
            if replace_tiny and _is_tiny(dest):
                print(f"replace tiny {item['category']}/{item['file']} ({dest.stat().st_size} B)")
            else:
                print(f"skip existing {item['category']}/{item['file']}")
                continue
        jobs.append(item)
    return jobs


def main() -> int:
    parser = argparse.ArgumentParser(description="Batch Gemini props (budget-capped)")
    parser.add_argument("--max", type=int, default=DEFAULT_MAX, help=f"Image count (default {DEFAULT_MAX})")
    parser.add_argument(
        "--max-cost",
        type=float,
        default=None,
        help=f"Abort if estimated USD > this (default {DEFAULT_MAX_COST_USD})",
    )
    parser.add_argument(
        "--max-eur",
        type=float,
        default=None,
        help="Abort if estimated EUR > this (converted with conservative rate)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Plan only, no API calls")
    parser.add_argument("--force", action="store_true", help="Overwrite existing targets")
    parser.add_argument(
        "--pack",
        choices=("curated", "classic"),
        default="classic",
        help="Asset list (classic = village/dungeon gaps)",
    )
    parser.add_argument(
        "--replace-tiny",
        action="store_true",
        default=True,
        help="Overwrite placeholder PNGs under 2 KB (default on)",
    )
    parser.add_argument(
        "--keep-tiny",
        action="store_true",
        help="Do not replace existing tiny placeholders",
    )
    args = parser.parse_args()

    max_images = max(0, min(args.max, HARD_MAX_IMAGES))
    if args.max > HARD_MAX_IMAGES:
        print(f"Note: --max clamped to hard cap {HARD_MAX_IMAGES}")

    max_cost_usd = DEFAULT_MAX_COST_USD
    if args.max_cost is not None:
        max_cost_usd = float(args.max_cost)
    if args.max_eur is not None:
        from_eur = float(args.max_eur) / max(EUR_PER_USD, 0.01)
        max_cost_usd = min(max_cost_usd, from_eur) if args.max_cost is None else min(float(args.max_cost), from_eur)

    print(f"Model: {MODEL}")
    print(f"Style refs: map={REF_MAP.name} char={REF_CHAR.name}")
    print(f"Cost estimate unit: ~${COST_PER_IMAGE_USD}/image")
    print(f"Budget ceiling (max only): ~${max_cost_usd:.2f} USD (~EUR {max_cost_usd * EUR_PER_USD:.2f})")
    print(f"Output root: {PROPS}")

    pack = CLASSIC if args.pack == "classic" else CURATED
    replace_tiny = bool(args.replace_tiny) and not bool(args.keep_tiny)
    jobs = planned_jobs(max_images, args.force, pack, replace_tiny)
    cost = estimate_cost(len(jobs))
    cost_eur = round(cost * EUR_PER_USD, 4)
    print(f"Planned requests: {len(jobs)}  estimated~${cost} (~EUR {cost_eur})")
    if cost > max_cost_usd:
        print(f"ABORT: estimated cost ${cost} > ceiling ${max_cost_usd:.2f}")
        return 3
    if not jobs:
        print("Nothing to do.")
        return 0

    api_key = resolve_api_key()
    if not api_key:
        if args.dry_run:
            print("Dry-run: no API key required.")
            return 0
        print(
            "ABORT: aucune cle (GEMINI_API_KEY / GOOGLE_API_KEY). "
            "Aucun appel API. Utilisez generate_prop_placeholders.py pour du gratuit."
        )
        return 2

    spent = 0.0
    ok = 0
    for i, item in enumerate(jobs, 1):
        print(f"[{i}/{len(jobs)}] {item['category']}/{item['file']} kind={item.get('kind','map')}")
        if args.dry_run:
            continue
        if spent + COST_PER_IMAGE_USD > max_cost_usd + 1e-9:
            print(f"Stop early: next image would exceed budget (spent~${spent:.3f}).")
            break
        dest_dir = PROPS / item["category"]
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / item["file"]
        try:
            png = generate_one(api_key, item["prompt"], kind=str(item.get("kind", "map")))
            dest.write_bytes(png)
            # Detourage systematique (Gemini peint souvent un damier opaque).
            try:
                sys.path.insert(0, str(Path(__file__).resolve().parent))
                from strip_prop_backgrounds import strip_image
                from PIL import Image as _PILImage

                cut = strip_image(_PILImage.open(dest))
                cut.save(dest, format="PNG", optimize=True)
            except Exception as strip_exc:
                print(f"  WARN strip: {strip_exc}")
            spent += COST_PER_IMAGE_USD
            ok += 1
            print(f"  saved {dest} ({dest.stat().st_size} bytes) running~${spent:.3f}/EUR {spent * EUR_PER_USD:.3f}")
        except Exception as exc:
            print(f"  FAIL: {exc}", file=sys.stderr)
            print("Aborting remaining requests to avoid wasted spend.")
            return 4

    total = spent if not args.dry_run else cost
    print(
        f"Done. model={MODEL} ok={ok if not args.dry_run else 0} "
        f"est~${total:.3f} (~EUR {total * EUR_PER_USD:.3f})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
