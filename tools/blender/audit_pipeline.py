#!/usr/bin/env python3
"""Audit du pipeline d'assets procéduraux OpenQuest.

Vérifie que le manifeste produit par Blender couvre les familles nécessaires à
un éditeur pour MJ non graphiste, et que chaque entrée est exploitable par
Godot : GLB + vignette, dimensions, ancrage, budget de triangles.

Usage :
    python tools/blender/audit_pipeline.py
    python tools/blender/audit_pipeline.py --manifest game/assets/objects3d/manifest.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

REQUIRED_FAMILIES = {
    "architecture": [
        "mur", "mur_coin", "toit_2pentes", "toit_croupe", "toit_appentis",
        "toit_chaume", "porte_auvent", "fenetre_volets", "escalier_exterieur",
        "maison", "tour", "pont", "palissade", "barriere",
    ],
    "nature": [
        "arbre", "arbre_majestueux", "buisson", "haie", "roseaux", "rocher",
        "gros_rocher", "falaise", "nenuphars",
    ],
    "mobilier": [
        "table_tabourets", "banc", "lit", "tonneau", "tonneau_couche", "caisse",
        "comptoir", "etal_marche", "botte_foin", "tas_de_bois",
    ],
    "decor": [
        "lanterne", "torche_murale", "enseigne", "banniere", "puits",
        "fontaine", "tapis", "charrette", "panneau",
    ],
    "interieur": [
        "porte_auvent", "fenetre_volets", "lit", "table_tabourets", "tapis",
    ],
}

VALID_ANCHORS = {"base", "wall", "roof"}
BUDGET = 5000


def load_manifest(path: Path) -> dict:
    if not path.exists():
        raise SystemExit(f"manifeste introuvable : {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"manifeste JSON invalide : {exc}") from exc


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        default="game/assets/objects3d/manifest.json",
        help="Chemin du manifeste (défaut : game/assets/objects3d/manifest.json)",
    )
    args = parser.parse_args(argv)
    manifest_path = Path(args.manifest).resolve()
    data = load_manifest(manifest_path)
    assets = data.get("assets", [])
    if not isinstance(assets, list) or not assets:
        raise SystemExit("manifeste vide ou champ 'assets' absent")

    errors: list[str] = []
    names = {str(a.get("base") or a.get("name") or "") for a in assets}
    by_category = Counter(str(a.get("category", "?")) for a in assets)

    for category, required in REQUIRED_FAMILIES.items():
        missing = [name for name in required if name not in names]
        if missing:
            errors.append(f"{category}: familles manquantes : {', '.join(missing)}")

    for asset in assets:
        name = str(asset.get("name", "?"))
        if not asset.get("glb"):
            errors.append(f"{name}: champ 'glb' absent")
        if not asset.get("thumb"):
            errors.append(f"{name}: vignette absente")
        dims = asset.get("dimensions_cells")
        if not isinstance(dims, list) or len(dims) != 3:
            errors.append(f"{name}: dimensions_cells invalides")
        elif any(float(v) <= 0.0 for v in dims):
            errors.append(f"{name}: dimensions nulles/négatives")
        anchor = str(asset.get("anchor", "base"))
        if anchor not in VALID_ANCHORS:
            errors.append(f"{name}: ancrage inconnu '{anchor}'")
        triangles = int(asset.get("triangles", 0))
        if triangles <= 0:
            errors.append(f"{name}: nombre de triangles invalide")
        elif triangles > BUDGET:
            errors.append(f"{name}: {triangles} triangles (budget {BUDGET})")

    variants = sum(1 for a in assets if str(a.get("variant", "base")) not in ("", "base"))
    print(f"Manifeste       : {manifest_path}")
    print(f"Assets          : {len(assets)}")
    print(f"Variantes       : {variants}")
    print("Catégories      : " + ", ".join(f"{k}={v}" for k, v in sorted(by_category.items())))
    print("Familles requises : " + ", ".join(f"{k}={len(v)}" for k, v in REQUIRED_FAMILIES.items()))

    if errors:
        print("\nERREURS :", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    print("\nPASS — pipeline procédural complet pour l'éditeur.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
