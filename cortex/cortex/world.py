"""World knowledge shared by all agents: the tech tree DAG + era content.

Loads data/tech_tree.json and data/era1_content.json (generated/authored at the
repo root). Agents consult it to know which recipes their known_tech unlocks,
what materials those recipes need, and what counts as food. The engine (Godot)
loads the same files to execute; Cortex decides, Godot does.
"""

import json
from pathlib import Path


class World:
    def __init__(self, data_dir: str):
        base = Path(data_dir)
        tree = json.loads((base / "tech_tree.json").read_text(encoding="utf-8"))
        content = json.loads((base / "era1_content.json").read_text(encoding="utf-8"))
        traits_path = base / "traits.json"
        self.traits = (json.loads(traits_path.read_text(encoding="utf-8"))
                       if traits_path.exists() else {})

        self.meta = tree.get("meta", {})
        self.settlement_era = 1   # updated by the server as the village learns
        self.nodes = {n["id"]: n for n in tree.get("nodes", [])}
        self.resources = content.get("resources", {})
        self.items = content.get("items", {})
        self.recipes = content.get("recipes", {})
        self.needs_cfg = content.get("needs", {})
        self.stations = content.get("stations", {})
        self.time_cfg = content.get("time", {})

        for rid, r in self.recipes.items():
            if r.get("tech") and r["tech"] not in self.nodes:
                raise ValueError(f"recipe {rid} references unknown tech {r['tech']}")

    # ------------------------------------------------------------- queries

    def tech_name(self, tech_id: str) -> str:
        node = self.nodes.get(tech_id)
        return node["name"] if node else tech_id

    def era_name(self, n: int) -> str:
        return self.meta.get("eras", {}).get(f"E{n}", f"Era {n}")

    def prereq_closure(self, tech_id: str) -> set:
        """All techs (transitively) required for tech_id. Cached."""
        if not hasattr(self, "_closure_cache"):
            self._closure_cache = {}
        if tech_id in self._closure_cache:
            return self._closure_cache[tech_id]
        node = self.nodes.get(tech_id, {})
        out = set()
        deps = list(node.get("prerequisites", []))
        for group in node.get("prerequisites_any_of", []):
            deps += group
        for p in deps:
            out.add(p)
            out |= self.prereq_closure(p)
        self._closure_cache[tech_id] = out
        return out

    def diffusion_speed(self, known) -> int:
        """How fast knowledge moves, from the best diffusion tech anyone
        living holds (demonstration 1x -> storytelling 2x -> schools 4x ->
        literacy 8x, per the tree's meta.diffusion_tiers)."""
        known = set(known)
        speed = 1
        for tier in self.meta.get("diffusion_tiers", []):
            if tier.get("tech") in known:
                speed = max(speed, int(tier.get("speed", 1)))
        return speed

    def loss_mitigated(self, known) -> bool:
        """Archives/records (meta.rules.loss_mitigated_by) preserve a dead
        NPC's unique knowledge instead of losing it."""
        known = set(known)
        return any(t in known
                   for t in self.meta.get("rules", {}).get("loss_mitigated_by", []))

    def next_gates(self) -> list:
        """The bottleneck techs of the settlement's CURRENT era — the doors
        to the next age."""
        return [b for b in self.meta.get("bottlenecks", [])
                if b.startswith(f"E{self.settlement_era}.")]

    def compute_era(self, known) -> int:
        """Settlement era: era N is reached when every bottleneck of era N-1 is
        known AND at least 3 techs of era N are known. Eras chain — you cannot
        skip one."""
        known = set(known)
        era = 1
        for n in range(2, 9):
            gates = [b for b in self.meta.get("bottlenecks", [])
                     if b.startswith(f"E{n - 1}.")]
            if not all(b in known for b in gates):
                break
            if sum(1 for t in known if t.startswith(f"E{n}.")) < 3:
                break
            era = n
        return era

    def is_food(self, item: str) -> bool:
        return "food" in self.items.get(item, {})

    def known_recipes(self, known_tech) -> dict:
        known = set(known_tech or [])
        return {rid: r for rid, r in self.recipes.items() if r.get("tech") in known}

    def recipe_status(self, recipe: dict, inventory: dict) -> dict:
        """What is missing to run this recipe with the given inventory."""
        inv = inventory or {}
        missing_inputs = {}
        for item, count in recipe.get("inputs", {}).items():
            have = int(inv.get(item, 0))
            if have < count:
                missing_inputs[item] = count - have
        missing_tools = [t for t in recipe.get("tools", []) if int(inv.get(t, 0)) < 1]
        return {
            "ready": not missing_inputs and not missing_tools,
            "missing_inputs": missing_inputs,
            "missing_tools": missing_tools,
        }

    def resource_yielding(self, item: str):
        """Resource type whose gather yields the item, or None."""
        for rtype, r in self.resources.items():
            if item in r.get("yields", {}):
                return rtype
        return None

    # ------------------------------------------------------------- catalogs

    # farming recipes only make sense against the right field state
    FIELD_GATES = {"sow_field": "empty", "harvest_field": "ripe"}

    def action_catalog(self, known_tech, inventory: dict, nearby: dict,
                       fire: dict = None, storage: dict = None,
                       fields: dict = None, corral: dict = None,
                       stations: list = None) -> dict:
        """Everything an NPC can actually do right now, for the decide prompt.
        `fire` is the campfire state from the engine ({lit, fuel, distance})
        or None when no station exists — station recipes are gated on it."""
        inv = inventory or {}
        near = nearby or {}
        gather = []
        known = set(known_tech or [])
        for rtype, dist in sorted(near.items(), key=lambda kv: kv[1]):
            r = self.resources.get(rtype)
            if not r:
                continue
            if r.get("tech") and r["tech"] not in known:
                continue  # doesn't know the technique (e.g. hand fishing)
            tools_any = r.get("tools_any", [])
            if tools_any and not any(int(inv.get(t, 0)) > 0 for t in tools_any):
                continue  # can't hunt bare-handed
            yields = ", ".join(r["yields"].keys())
            entry = {"target": rtype, "label": r["label"],
                     "yields": yields, "distance": round(float(dist), 1)}
            if r.get("gather_verb"):
                entry["verb"] = r["gather_verb"]
            gather.append(entry)
        craft = []
        for rid, r in self.known_recipes(known_tech).items():
            station = r.get("station", "")
            gate = self.FIELD_GATES.get(rid)
            if gate and int((fields or {}).get(gate, 0)) <= 0:
                continue  # nothing to sow into / nothing ripe to cut
            if r.get("requires_corral") and not corral:
                continue  # no corral in the village yet
            herd_need = r.get("requires_herd", "")
            if herd_need and int((corral or {}).get("herd", {})
                                 .get(herd_need, 0)) <= 0:
                continue  # the corral holds no such animal
            if station and station != "campfire":
                if station not in (stations or []):
                    continue  # that workshop hasn't been built yet
            elif station and not fire:
                continue  # no fire in the world -> can't cook or tend
            elif station and not fire.get("lit", True) and r.get("effects", {}).get("fire_fuel"):
                pass  # tending is exactly how you revive a dying fire
            elif station and not fire.get("lit", True):
                continue  # dead fire cooks nothing
            st = self.recipe_status(r, inv)
            entry = {"target": rid, "label": r["label"], "ready": st["ready"],
                     "missing": {**st["missing_inputs"],
                                 **{t: 1 for t in st["missing_tools"]}}}
            if station:
                entry["station"] = station
            craft.append(entry)
        eat = [{"target": it, "label": self.items[it]["label"]}
               for it, n in inv.items()
               if int(n) > 0 and self.is_food(it)]
        return {"gather": gather, "craft": craft, "eat": eat,
                "store": self._store_catalog(inv, storage)}

    def _store_catalog(self, inv: dict, storage) -> dict:
        """Deposit/withdraw options against the nearest storage structure."""
        if not storage:
            return {}
        space = int(storage.get("space", 0))
        holds = storage.get("holds", {}) or {}
        deposit = [it for it, n in inv.items()
                   if int(n) >= 3 and self.is_food(it) and space > 0]
        withdraw = [it for it, n in holds.items() if int(n) > 0]
        if not deposit and not withdraw:
            return {}
        return {"kind": storage.get("kind", "store"),
                "distance": storage.get("distance", 0),
                "holds": holds, "space": space,
                "deposit": deposit, "withdraw": withdraw}
