#!/usr/bin/env python3
"""Report which drop-in model slots are filled and which are missing.

Usage:  python tools/list_assets.py   (from the Vox folder root)

Slots are derived from the live data: resources in data/era1_content.json,
named personas in cortex/personas/, generated-villager and child names from
cortex/cortex/personas.py NAME_POOL. See godot/assets/README.md.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "godot" / "assets"
EXTS = (".glb", ".gltf", ".tscn", ".scn")


def exists(rel: str) -> str | None:
    for ext in EXTS:
        p = ASSETS / (rel + ext)
        if p.exists():
            return p.name
    return None


def main():
    content = json.loads((ROOT / "data" / "era1_content.json").read_text(encoding="utf-8"))
    resources = list(content.get("resources", {}))
    named = sorted(p.stem for p in (ROOT / "cortex" / "personas").glob("*.yaml"))
    pool_src = (ROOT / "cortex" / "cortex" / "personas.py").read_text(encoding="utf-8")
    m = re.search(r"NAME_POOL = \[(.*?)\]", pool_src, re.S)
    pool = re.findall(r'"(\w+)"', m.group(1)) if m else []

    filled, missing = [], []

    def check(rel: str, note: str = ""):
        hit = exists(rel)
        (filled if hit else missing).append((rel, hit or "", note))

    check("campfire", "the hearth")
    for r in resources:
        check(f"props/{r}", content["resources"][r].get("label", ""))
    for b in content.get("buildables", {}):
        check(f"structures/{b}", content["buildables"][b].get("label", "buildable structure"))
    for p in content.get("predators", {}):
        check(f"predators/{p}", content["predators"][p].get("label", "predator"))
    for c in "abcde":
        check(f"trees/tree_{c}", "tree variety (any subset works; voxel-tree fallback)")
    check("npc/default", "fallback body: generated extras + children without their own file")
    for n in named:
        check(f"npc/{n}", "named villager")
    for n in pool:
        if n not in named:
            check(f"npc/{n}", "generated villager / child (optional — default.glb covers them)")

    print(f"== FILLED ({len(filled)}) ==")
    for rel, hit, _ in filled:
        print(f"  {rel:<28} -> {hit}")
    required = [(r, n) for r, _, n in missing if "optional" not in n]
    optional = [(r, n) for r, _, n in missing if "optional" in n]
    print(f"\n== MISSING ({len(required)} gameplay slots) ==")
    for rel, note in required:
        print(f"  {rel + '.glb':<32} {note}")
    print(f"\n== OPTIONAL ({len(optional)} — covered by npc/default.glb) ==")
    for rel, note in optional:
        print(f"  {rel + '.glb'}")
    if not required:
        print("  (none — every gameplay slot has a model)")

    decor_dir = ASSETS / "decor"
    decor = sorted(p.name for p in decor_dir.glob("*.glb")) if decor_dir.exists() else []
    print(f"\n== DECOR ({len(decor)} — open-ended, every .glb here is scattered) ==")
    print("  " + (", ".join(decor) if decor else "(none)"))


if __name__ == "__main__":
    main()
