#!/usr/bin/env python3
"""Migre tous les scénarios JSON vers la navigation non linéaire (ids + transitions)."""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRS = [ROOT / "game" / "data" / "scenarios", ROOT / "data" / "scenarios"]

ACT_RE = re.compile(r"^Acte\s+([IVXLC]+)\s*[—\-–]\s*", re.IGNORECASE)
FORK_HINTS = (
    "choix",
    "passage",
    " ou ",
    "poursuite",
    "combat,",
    "négociation",
    "infiltration",
    "détour",
    "accuser ou",
    "protéger ou",
    "escorter",
    "fuite",
    "secret",
    "trois passages",
    "plusieurs issues",
    "branches",
)


def slugify(text: str, index: int) -> str:
    base = ACT_RE.sub("", text).strip().lower()
    out = []
    for ch in base:
        if ch.isalnum():
            out.append(ch)
        elif ch in " '-_":
            out.append("-")
    slug = re.sub(r"-+", "-", "".join(out)).strip("-")
    if not slug:
        return f"scene-{index}"
    return slug[:64]


def act_tag(title: str) -> str | None:
    m = ACT_RE.match(title)
    if not m:
        return None
    return f"acte-{m.group(1).lower()}"


def act_key(title: str) -> str | None:
    m = ACT_RE.match(title)
    return m.group(1).lower() if m else None


def unique_id(base: str, used: set[str], index: int) -> str:
    candidate = base or f"scene-{index}"
    if candidate not in used:
        used.add(candidate)
        return candidate
    n = 2
    while f"{candidate}-{n}" in used:
        n += 1
    final = f"{candidate}-{n}"
    used.add(final)
    return final


def scene_tags(title: str, content: str, index: int, total: int) -> list[str]:
    tags: list[str] = []
    act = act_tag(title)
    if act:
        tags.append(act)
    lower = content.lower()
    if index == 0:
        tags.append("debut")
    if index == total - 1:
        tags.append("fin")
    if any(h in lower for h in FORK_HINTS):
        tags.append("carrefour")
    if "épilogue" in title.lower() or "verdict" in title.lower() or "couronnement" in title.lower():
        tags.append("epilogue")
    return tags


def default_label(current_title: str, target_title: str, forward: bool) -> str:
    target = ACT_RE.sub("", target_title).strip()
    if forward:
        return f"Continuer vers : {target[:48]}"
    return f"Revenir à : {target[:48]}"


def migrate_scenario(data: dict) -> dict:
    scenes = data.get("scenes", [])
    if not scenes:
        return data

    # Déjà migré manuellement avec transitions explicites sur chaque scène ?
    if all(isinstance(s, dict) and s.get("id") and s.get("transitions") for s in scenes):
        if data.get("startSceneId"):
            return data

    used: set[str] = set()
    prepared: list[dict] = []
    act_starts: dict[str, str] = {}

    for i, raw in enumerate(scenes):
        if not isinstance(raw, dict):
            continue
        scene = raw.copy()
        title = str(scene.get("title", f"Scène {i + 1}"))
        sid = str(scene.get("id", "")).strip()
        if not sid:
            sid = slugify(title, i)
        sid = unique_id(sid, used, i)
        scene["id"] = sid
        scene["tags"] = scene.get("tags") or scene_tags(title, str(scene.get("content", "")), i, len(scenes))
        ak = act_key(title)
        if ak and ak not in act_starts:
            act_starts[ak] = sid
        prepared.append(scene)

    total = len(prepared)
    finale_id = prepared[-1]["id"]

    for i, scene in enumerate(prepared):
        if scene.get("transitions"):
            continue
        title = scene.get("title", "")
        content = str(scene.get("content", "")).lower()
        transitions: list[dict] = []
        seen_to: set[str] = set()

        def add_transition(to_id: str, label: str, default: bool = False, gm_only: bool = False) -> None:
            if not to_id or to_id == scene["id"] or to_id in seen_to:
                return
            seen_to.add(to_id)
            entry = {"to": to_id, "label": label}
            if default:
                entry["default"] = True
            if gm_only:
                entry["gmOnly"] = True
            transitions.append(entry)

        if i + 1 < total:
            nxt = prepared[i + 1]
            add_transition(
                nxt["id"],
                default_label(title, nxt.get("title", ""), True),
                default=True,
            )

        if i > 0:
            prev = prepared[i - 1]
            add_transition(
                prev["id"],
                default_label(title, prev.get("title", ""), False),
                gm_only=True,
            )

        # Sauts d'acte pour campagnes longues
        ak = act_key(title)
        if ak:
            act_order = list(act_starts.keys())
            if ak in act_order:
                idx = act_order.index(ak)
                if idx + 1 < len(act_order):
                    next_act_id = act_starts[act_order[idx + 1]]
                    add_transition(
                        next_act_id,
                        f"Sauter à l'acte suivant ({act_order[idx + 1].upper()})",
                        gm_only=True,
                    )
                if idx > 0:
                    prev_act_id = act_starts[act_order[idx - 1]]
                    add_transition(
                        prev_act_id,
                        f"Revenir au début de l'acte {act_order[idx - 1].upper()}",
                        gm_only=True,
                    )

        # Carrefours narratifs : branches alternatives MJ
        if any(h in content for h in FORK_HINTS) or "carrefour" in scene.get("tags", []):
            for j, alt in enumerate(prepared):
                if j == i or j == i + 1 or j == i - 1:
                    continue
                if abs(j - i) <= 3:
                    add_transition(
                        alt["id"],
                        f"Branche MJ : {ACT_RE.sub('', alt.get('title', '')).strip()[:40]}",
                        gm_only=True,
                    )

        # Branches manoir / crypte style pour scènes multi-portes
        if "portes" in content or "passage" in content or "mène" in content:
            for j in range(i + 2, min(i + 4, total)):
                alt = prepared[j]
                add_transition(
                    alt["id"],
                    f"Emprunter un autre chemin : {ACT_RE.sub('', alt.get('title', '')).strip()[:36]}",
                    gm_only=True,
                )

        if i < total - 1:
            add_transition(finale_id, "Sauter directement à la scène finale (MJ)", gm_only=True)

        scene["transitions"] = transitions
        prepared[i] = scene

    data["scenes"] = prepared
    data["startSceneId"] = prepared[0]["id"]

    npc_used: set[str] = set()
    for npc in data.get("npcs", []):
        if not isinstance(npc, dict):
            continue
        nid = str(npc.get("id", "")).strip()
        if not nid:
            nid = slugify(str(npc.get("name", "npc")), 0)
        nid = unique_id(nid, npc_used, 0)
        npc["id"] = nid

    return data


def main() -> None:
    files = sorted({p for d in DIRS if d.exists() for p in d.glob("*.json")})
    for path in files:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        migrated = migrate_scenario(data)
        with path.open("w", encoding="utf-8", newline="\n") as f:
            json.dump(migrated, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"OK {path.name} ({len(migrated.get('scenes', []))} scènes)")


if __name__ == "__main__":
    main()
