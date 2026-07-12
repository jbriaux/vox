#!/usr/bin/env python3
"""Regenerate data/tech_tree.json from 01_TECH_TREE.md.

Usage:  python tools/build_tech_tree.py   (run from the Vox folder root)

Parses every table row `| Ex.NN | name | prereqs | needs | introduces |`,
validates the graph (unique IDs, no dangling prereqs, no cycles), and
writes data/tech_tree.json. Exits non-zero on any validation error.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "01_TECH_TREE.md"
OUT = ROOT / "data" / "tech_tree.json"

ERAS = {
    "E1": "Lower Paleolithic",
    "E2": "Middle Paleolithic",
    "E3": "Upper Paleolithic",
    "E4": "Mesolithic",
    "E5": "Neolithic",
    "E6": "Chalcolithic (Copper Age)",
    "E7": "Bronze Age",
    "E8": "Iron Age",
}
TAGMAP = {"i": "items", "b": "blocks", "s": "structures", "a": "actions"}

META = {
    "name": "VOX Technology Tree",
    "version": "1.0",
    "source": "01_TECH_TREE.md",
    "eras": ERAS,
    "bottlenecks": ["E1.18", "E2.10", "E4.06", "E5.05", "E5.34",
                    "E6.07", "E7.02", "E7.30", "E8.02", "E8.30"],
    "terminal_nodes": ["E8.20", "E8.41", "E8.42", "E8.44"],
    "diffusion_tiers": [
        {"tech": "E1.25", "method": "demonstration", "speed": 1},
        {"tech": "E3.41", "method": "storytelling", "speed": 2},
        {"tech": "E7.31", "method": "schools", "speed": 4},
        {"tech": "E8.29", "method": "alphabetic literacy", "speed": 8},
    ],
    "rules": {
        "knowledge_holder": "npc",
        "settlement_knows_if": "any living NPC knows node",
        "loss_on_last_knower_death": True,
        "loss_mitigated_by": ["E7.30", "E8.34"],
    },
}

ID_RE = r"E\d\.\d{2}"
ROW_RE = re.compile(
    r"^\| (" + ID_RE + r") \| (.+?) \| (.+?) \| (.+?) \| (.+?) \|\s*$", re.M
)


def parse_prereqs(cell):
    cell = cell.strip()
    if cell in ("—", "-", ""):
        return [], []
    all_of, any_of = [], []
    for token in (t.strip() for t in cell.split(",")):
        ids = re.findall(ID_RE, token)
        if " or " in token and len(ids) > 1:
            any_of.append(ids)
        else:
            all_of.extend(ids)
    return all_of, any_of


def parse_needs(cell):
    cell = cell.strip()
    if cell in ("—", "-", ""):
        return []
    return [n.strip() for n in cell.split(",") if n.strip()]


def parse_introduces(node_id, cell, warnings):
    out = {"items": [], "blocks": [], "structures": [], "actions": []}
    for seg in (s.strip() for s in cell.split(";")):
        m = re.match(r"^([ibsa](?:/[ibsa])*)\s*:\s*(.+)$", seg)
        if not m:
            if seg and seg not in ("—", "-"):
                warnings.append(f"{node_id}: untagged introduces segment {seg!r} -> actions")
                out["actions"].append(seg)
            continue
        tags, body = m.group(1).split("/"), m.group(2)
        entries = [e.strip() for e in body.split(",") if e.strip()]
        for t in tags:
            out[TAGMAP[t]].extend(entries)
    return {k: v for k, v in out.items() if v}


def check_dag(graph):
    state = {}

    def visit(n, path):
        if state.get(n) == 1:
            raise SystemExit(f"ERROR: cycle detected: {' -> '.join(path + [n])}")
        if state.get(n) == 2:
            return
        state[n] = 1
        for p in graph[n]:
            visit(p, path + [n])
        state[n] = 2

    for n in graph:
        visit(n, [])


def main():
    txt = SRC.read_text(encoding="utf-8")
    warnings = []
    nodes = []
    for nid, name, pre, needs, intro in ROW_RE.findall(txt):
        all_of, any_of = parse_prereqs(pre)
        node = {
            "id": nid,
            "name": name.strip(),
            "era": nid.split(".")[0],
            "prerequisites": all_of,
        }
        if any_of:
            node["prerequisites_any_of"] = any_of
        node["needs"] = parse_needs(needs)
        node["introduces"] = parse_introduces(nid, intro, warnings)
        nodes.append(node)

    # --- validation ---
    ids = [n["id"] for n in nodes]
    idset = set(ids)
    if len(ids) != len(idset):
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        raise SystemExit(f"ERROR: duplicate node IDs: {dupes}")

    graph = {}
    for n in nodes:
        deps = n["prerequisites"] + [x for g in n.get("prerequisites_any_of", []) for x in g]
        for p in deps:
            if p not in idset:
                raise SystemExit(f"ERROR: {n['id']} references unknown prereq {p}")
        graph[n["id"]] = deps
    check_dag(graph)

    meta_refs = (META["bottlenecks"] + META["terminal_nodes"]
                 + [d["tech"] for d in META["diffusion_tiers"]]
                 + META["rules"]["loss_mitigated_by"])
    for x in meta_refs:
        if x not in idset:
            raise SystemExit(f"ERROR: meta references unknown node {x}")

    for n in nodes:
        if not n["introduces"]:
            warnings.append(f"{n['id']}: introduces nothing")

    # --- write ---
    doc = {"meta": {**META, "node_count": len(nodes)}, "nodes": nodes}
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for w in warnings:
        print("WARN:", w)
    print(f"OK: {len(nodes)} nodes -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
