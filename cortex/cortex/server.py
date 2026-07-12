"""FastAPI WebSocket server — the wire between Godot bodies and Agent minds.

Protocol (JSON messages over ws://host:port/ws):
  Godot -> Cortex:
    {"type": "hello", "world": "vox-p3"}
    {"type": "chat",     "npc": "anon", "text": "...", "state": {...}}
    {"type": "decide",   "npc": "anon", "state": {...}, "tier": "full|scripted"}
    {"type": "event",    "npc": "anon", "text": "..."}
    {"type": "converse", "a": "anon", "b": "kara"}      two NPCs stand together
  Cortex -> Godot:
    {"type": "roster",  "npcs": [{"id": "anon", "name": "Anon"}, ...]}
    {"type": "say",     "npc": "anon", "text": "..."}
    {"type": "action",  "npc": "anon", "action": "...", "target": "...", "say": "..."}
    {"type": "learned", "npc": "kara", "tech": "E1.17", "tech_name": "...", "from": "anon"}
    {"type": "converse_end", "a": "anon", "b": "kara"}
    {"type": "status",  "text": "..."}
"""

import asyncio
import json
import os
import random
from pathlib import Path

import httpx
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from .agent import Agent
from .config import load_config
from .llm import make_embedder, make_llm
from .memory import Memory
from .personas import (NAME_POOL, compile_persona, generate_child,
                       generate_emergent_village, generate_village)
from .world import World

app = FastAPI(title="VOX Cortex")

CONVERSE_TURNS = 6  # three lines each


_stats = {"decides": 0, "seconds": 0.0, "actions": {}}


async def _activity_reporter() -> None:
    """A heartbeat so a quiet log is never ambiguous: every 30s, one line of
    what the village's minds have been doing."""
    while True:
        await asyncio.sleep(30)
        n = _stats["decides"]
        if n == 0:
            print("[cortex] activity: no decides in the last 30s "
                  "(is the Godot village running?)")
            continue
        avg = _stats["seconds"] / n
        top = ", ".join(f"{k} x{v}" for k, v in
                        sorted(_stats["actions"].items(), key=lambda kv: -kv[1]))
        print(f"[cortex] activity: {n} decides in 30s (avg {avg:.1f}s) — {top}")
        _stats["decides"] = 0
        _stats["seconds"] = 0.0
        _stats["actions"].clear()


class _SafeSock:
    """Serializes concurrent websocket sends — handler tasks run in parallel,
    but frames must not interleave."""

    def __init__(self, sock: WebSocket):
        self._sock = sock
        self._lock = asyncio.Lock()

    async def send_json(self, payload: dict) -> None:
        async with self._lock:
            await self._sock.send_json(payload)


DEFAULT_EMERGENT_VILLAGES = {
    "riverside": [["asha", "beno"], ["ciro", "dena", "ewa"]],
    "hilltop": [["falo", "gani"], ["hesu", "iria", "jomo"]],
}


@app.on_event("startup")
async def _startup():
    cfg = load_config(os.environ.get("CORTEX_CONFIG", "config.yaml"))
    app.state.cfg = cfg
    world = None
    if cfg.get("data_dir"):
        world = World(cfg["data_dir"])
        print(f"[cortex] world loaded: {len(world.nodes)} tech nodes, "
              f"{len(world.recipes)} recipes, {len(world.resources)} resource types")
    app.state.world = world
    app.state.embedder = make_embedder(cfg.get("embeddings", {"provider": "mock"}))
    # Brain pool: NPCs without an explicit brain get these round-robin —
    # 4 models means NPC 1-4 get models 1-4, NPC 5 wraps back to model 1, etc.
    app.state.brain_pool = list(cfg.get("brain_pool") or [])
    if app.state.brain_pool:
        print(f"[cortex] brain pool: {len(app.state.brain_pool)} models, "
              "assigned round-robin")
    app.state.discovery_override = None
    rate_env = os.environ.get("VOX_DISCOVERY_RATE", "")
    if rate_env:
        app.state.discovery_override = float(rate_env)
        print(f"[cortex] discovery rate override: {rate_env}")
    app.state.flavor = ""
    _build_flavor(str(cfg.get("flavor", "vanilla")))
    await _check_endpoints(cfg)


def _build_flavor(flavor: str) -> None:
    """Cast the agent roster for a flavor. Called at startup and again when
    Godot's hello asks for a different flavor (each keeps its own memory dir)."""
    if flavor == app.state.flavor:
        return
    cfg = app.state.cfg
    world = app.state.world
    embedder = app.state.embedder
    base = Path(cfg.get("_base_dir", "."))
    app.state.brain_i = 0
    app.state.agents = {}
    app.state.npc_meta = {}   # name -> {village, family} (emergent)

    if flavor == "emergent":
        app.state.mem_dir = base / "data" / "memory_emergent"
        villages = cfg.get("emergent", {}).get("villages", DEFAULT_EMERGENT_VILLAGES)
        cast = generate_emergent_village(villages,
                                         int(cfg.get("emergent", {}).get("seed", 3)))
        for name, raw in cast.items():
            agent = Agent(
                name=name,
                persona=compile_persona(raw, world.traits if world else {}),
                llm=make_llm(_next_pool_brain() or {"provider": "mock"}),
                memory=Memory(str(app.state.mem_dir / f"{name}.sqlite")),
                world=world,
                embedder=embedder,
                flavor="emergent",
            )
            app.state.agents[name] = agent
            app.state.npc_meta[name] = {"village": raw["village"],
                                        "family": raw["family"]}
        _seed_emergent_relationships(cast)
        print(f"[cortex] EMERGENT flavor: {len(cast)} villagers in "
              f"{len(villages)} villages, blank minds")
    else:
        app.state.mem_dir = base / "data" / "memory"
        for name, ncfg in cfg.get("npcs", {}).items():
            persona = compile_persona(ncfg["persona_data"], world.traits if world else {})
            app.state.agents[name] = Agent(
                name=name,
                persona=persona,
                llm=make_llm(ncfg.get("brain") or _next_pool_brain() or {}),
                memory=Memory(ncfg["memory_db"]),
                world=world,
                embedder=embedder,
            )
        village = cfg.get("village") or {}
        extras = int(village.get("extras", 0))
        if extras and world:
            generated = generate_village(extras, int(village.get("seed", 1)),
                                         world.traits,
                                         taken_names=list(app.state.agents))
            for name, raw in generated.items():
                app.state.agents[name] = Agent(
                    name=name,
                    persona=compile_persona(raw, world.traits),
                    llm=make_llm(village.get("brain") or _next_pool_brain() or {}),
                    memory=Memory(str(app.state.mem_dir / f"{name}.sqlite")),
                    world=world,
                    embedder=embedder,
                )
            print(f"[cortex] village extras cast: {list(generated)}")

    # resurrect runtime-born minds of THIS flavor (persona persisted at birth)
    if app.state.mem_dir.exists():
        for db_path in sorted(app.state.mem_dir.glob("*.sqlite")):
            name = db_path.stem
            if name in app.state.agents:
                continue
            mem = Memory(str(db_path))
            raw_json = mem.state_get("persona_json")
            if not raw_json:
                continue
            raw = json.loads(raw_json)
            app.state.agents[name] = Agent(
                name=name,
                persona=compile_persona(raw, world.traits if world else {}),
                llm=make_llm(_next_pool_brain() or {"provider": "mock"}),
                memory=mem,
                world=world,
                embedder=embedder,
                flavor=flavor,
            )
            if raw.get("village"):
                app.state.npc_meta[name] = {"village": raw["village"],
                                            "family": raw.get("family", 0)}
            print(f"[cortex] resurrected runtime-born mind: {name}"
                  + (" (deceased)" if app.state.agents[name].dead else ""))

    if world:
        seeded = set()
        for a in app.state.agents.values():
            seeded |= set(a.known_tech)
        world.settlement_era = max(1, world.compute_era(seeded))
        print(f"[cortex] settlement era: {world.settlement_era} "
              f"({world.era_name(world.settlement_era)})")
    village = cfg.get("village") or {}
    app.state.child_brain = village.get("brain")
    app.state.fallback_brain = (next(iter(cfg.get("npcs", {}).values()), {}).get("brain")
                                or {"provider": "mock"})
    if app.state.discovery_override is not None:
        for a in app.state.agents.values():
            a.discovery_rate = app.state.discovery_override
    app.state.flavor = flavor
    print(f"[cortex] agents ready ({flavor}): {len(app.state.agents)} "
          f"({', '.join(app.state.agents)})")


def _seed_emergent_relationships(cast: dict) -> None:
    """Village members know each other; family bonds are stronger than
    friendship. Seeded once per mind (flagged in its DB)."""
    for name, raw in cast.items():
        agent = app.state.agents[name]
        if agent.memory.state_get("rels_seeded") == "1":
            continue
        for other, other_raw in cast.items():
            if other == name or other_raw["village"] != raw["village"]:
                continue
            if other_raw["family"] == raw["family"]:
                agent.memory.rel_update(other, d_affinity=40, d_trust=45,
                                        d_familiarity=60, note="my family")
            else:
                agent.memory.rel_update(other, d_affinity=12, d_trust=15,
                                        d_familiarity=28)
        agent.memory.state_set("rels_seeded", "1")


async def _check_endpoints(cfg: dict) -> None:
    """Probe every distinct LLM endpoint once at startup — a dead endpoint
    should be one obvious line here, not a stream of mid-game failures."""
    endpoints = {}
    for brain in (cfg.get("brain_pool") or []):
        if brain.get("provider", "openai_compatible") != "mock":
            endpoints[str(brain.get("base_url", "")).rstrip("/")] = brain.get("model", "?")
    for ncfg in cfg.get("npcs", {}).values():
        brain = ncfg.get("brain") or {}
        if brain and brain.get("provider", "openai_compatible") != "mock":
            endpoints[str(brain.get("base_url", "")).rstrip("/")] = brain.get("model", "?")
    emb = cfg.get("embeddings") or {}
    if emb.get("provider") == "openai_compatible":
        endpoints[str(emb.get("base_url", "")).rstrip("/")] = "(embeddings)"
    for base, model in endpoints.items():
        if not base:
            continue
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                r = await client.get(f"{base}/models")
                r.raise_for_status()
            print(f"[cortex] endpoint OK: {base} ({model})")
        except Exception as e:
            npcs_hit = [a.name for a in app.state.agents.values()
                        if a.llm.base_url == base]
            print(f"[cortex] !! ENDPOINT UNREACHABLE: {base} ({model}) — "
                  f"{type(e).__name__}. Affected NPCs: "
                  f"{', '.join(npcs_hit) if npcs_hit else 'none'}")


@app.get("/")
async def health():
    return {"ok": True, "agents": list(app.state.agents.keys())}


def _next_pool_brain():
    """Next brain config from the pool (round-robin), or None if no pool."""
    pool = app.state.brain_pool
    if not pool:
        return None
    brain = pool[app.state.brain_i % len(pool)]
    app.state.brain_i += 1
    return brain


def _roster():
    out = []
    for a in app.state.agents.values():
        if getattr(a, "dead", False):
            continue
        meta = app.state.npc_meta.get(a.name, {})
        out.append({"id": a.name, "name": a.persona.get("name", a.name.capitalize()),
                    "brain": (a.llm.provider + (":" + a.llm.model if a.llm.model else "")),
                    "village": meta.get("village", ""),
                    "family": meta.get("family", -1)})
    return out


def _roster_msg() -> dict:
    return {"type": "roster", "flavor": app.state.flavor, "npcs": _roster()}


@app.post("/bind/{name}")
async def bind(name: str, body: dict):
    """Runtime per-NPC model rebinding — the 'bind any LLM to each person' seam.
    curl -X POST localhost:8765/bind/kara -H "Content-Type: application/json" \
         -d '{"provider":"openai_compatible","base_url":"http://127.0.0.1:11434/v1","model":"qwen2.5:14b"}'
    """
    agent = app.state.agents.get(name)
    if agent is None:
        return {"ok": False, "error": f"unknown npc {name!r}"}
    agent.llm = make_llm(body or {})
    brain = agent.llm.provider + (":" + agent.llm.model if agent.llm.model else "")
    print(f"[cortex] REBOUND: {name} -> {brain}")
    return {"ok": True, "npc": name, "brain": brain}


def _living():
    return [a for a in app.state.agents.values() if not getattr(a, "dead", False)]


async def _check_era(sock) -> None:
    """Era transitions are emergent: recomputed whenever anyone learns anything."""
    world = app.state.world
    if world is None:
        return
    known = set()
    for a in _living():
        known |= set(a.known_tech)
    era = world.compute_era(known)
    if era > world.settlement_era:
        world.settlement_era = era
        name = world.era_name(era)
        print(f"[cortex] ERA TRANSITION: the settlement has entered the {name} (era {era})")
        if app.state.flavor != "emergent":
            # eras are a narrator's concept — emergent minds get no such memo
            for a in _living():
                await a.remember("event", f"the band has entered a new age: the {name}", 9)
        await sock.send_json({"type": "era", "era": era, "name": name})


def _propose_trade(inv_a: dict, inv_b: dict):
    """Wave F barter: complementary surplus — I have plenty of something you
    lack, you have plenty of something I lack. One-for-one, deterministic."""
    inv_a, inv_b = inv_a or {}, inv_b or {}
    surplus_a = sorted(it for it, n in inv_a.items()
                       if int(n) >= 3 and int(inv_b.get(it, 0)) == 0)
    surplus_b = sorted(it for it, n in inv_b.items()
                       if int(n) >= 3 and int(inv_a.get(it, 0)) == 0)
    if surplus_a and surplus_b:
        return {"give": surplus_a[0], "take": surplus_b[0]}
    return None


async def _run_converse(sock, a: Agent, b: Agent, world,
                        inv_a: dict = None, inv_b: dict = None) -> None:
    """Multi-turn NPC dialogue + the P3 teaching mechanic (E1.25 demonstration)."""
    history = []
    speaker, listener = a, b
    print(f"[cortex] CONVERSE: {a.name} and {b.name} stop to talk")
    for _ in range(CONVERSE_TURNS):
        line = await speaker.converse_turn(listener.name, history)
        history.append((speaker.name, line))
        print(f"[cortex]   {speaker.name.capitalize()}: {line}")
        await sock.send_json({"type": "say", "npc": speaker.name, "text": line})
        speaker, listener = listener, speaker

    # knowledge exchange: whoever knows something the other doesn't may
    # demonstrate several things. Newest knowledge first — you show off your
    # latest craft, not how to pick berries. The COUNT scales with the
    # settlement's diffusion tier (storytelling, schools, literacy).
    known_all = set()
    for x in _living():
        known_all |= set(x.known_tech)
    teach_cap = 2 + (world.diffusion_speed(known_all) if world else 1)
    for teacher, learner in ((a, b), (b, a)):
        teachable = sorted(set(teacher.known_tech) - set(learner.known_tech),
                           reverse=True)
        if not teachable or not teacher.teach_willing():
            continue
        first = True
        for tech in teachable[:teach_cap]:
            tech_name = world.tech_name(tech) if world else tech
            if not learner.learn_tech(tech, teacher.name):
                continue
            if first:
                first = False
                demo = f"Here — watch my hands. This is how you do it: {tech_name.lower()}."
                history.append((teacher.name, demo))
                print(f"[cortex]   {teacher.name.capitalize()}: {demo}")
                await sock.send_json({"type": "say", "npc": teacher.name, "text": demo})
            await teacher.remember(
                "social", f"I showed {learner.name.capitalize()} how to do "
                f"{tech_name.lower()}", 6)
            await learner.remember(
                "social", f"{teacher.name.capitalize()} showed me how to do "
                f"{tech_name.lower()} — now I know it", 8)
            teacher.memory.rel_update(learner.name, d_affinity=4, d_familiarity=6)
            learner.memory.rel_update(teacher.name, d_affinity=5, d_trust=10,
                                      d_familiarity=6,
                                      note=f"taught me {tech_name.lower()}")
            learner.feel(8, "proud", f"learned {tech_name.lower()}")
            await sock.send_json({"type": "learned", "npc": learner.name,
                                  "tech": tech, "tech_name": tech_name,
                                  "from": teacher.name})
            print(f"[cortex] TECH EXCHANGED: {teacher.name} taught {learner.name} "
                  f"{tech} ({tech_name})")
            await _check_era(sock)
        break

    # skills move at the fire too: one routine per conversation, newest first
    for teacher, learner in ((a, b), (b, a)):
        l_names = {s[0] for s in learner.memory.skills_all()}
        teachable_skills = [s for s in teacher.memory.skills_all()
                            if s[0] not in l_names]
        if not teachable_skills or not teacher.teach_willing():
            continue
        name, desc, steps, _src, _uses = teachable_skills[-1]
        learner.memory.skill_add(name, desc, steps, teacher.name)
        spoken = name.replace("_", " ")
        line = f"Watch how I go about it — I call this {spoken}."
        await sock.send_json({"type": "say", "npc": teacher.name, "text": line})
        await teacher.remember(
            "social", f"showed {learner.name.capitalize()} my {spoken} routine", 5)
        await learner.remember(
            "social", f"{teacher.name.capitalize()} showed me their {spoken} "
            f"routine — {desc}", 7)
        learner.memory.rel_update(teacher.name, d_affinity=3, d_trust=5,
                                  d_familiarity=5)
        await sock.send_json({"type": "skill", "npc": learner.name,
                              "name": name, "from": teacher.name})
        print(f"[cortex] SKILL SHARED: {teacher.name} showed {learner.name} "
              f"'{name}'")
        break

    # Wave F: barter — surplus changes hands when it complements a lack
    swap = _propose_trade(inv_a, inv_b)
    if swap is not None and world:
        give_name = world.items.get(swap["give"], {}).get("label", swap["give"])
        take_name = world.items.get(swap["take"], {}).get("label", swap["take"])
        await sock.send_json({"type": "trade", "a": a.name, "b": b.name,
                              "give": swap["give"], "take": swap["take"]})
        await a.remember("social", f"traded my {give_name} for "
                         f"{b.name.capitalize()}'s {take_name}", 4)
        await b.remember("social", f"traded my {take_name} for "
                         f"{a.name.capitalize()}'s {give_name}", 4)
        a.memory.rel_update(b.name, d_affinity=3, d_trust=4, d_familiarity=4,
                            note="we trade")
        b.memory.rel_update(a.name, d_affinity=3, d_trust=4, d_familiarity=4,
                            note="we trade")
        print(f"[cortex] TRADE: {a.name} gave {swap['give']} for "
              f"{b.name}'s {swap['take']}")

    # both sides remember the meeting and grow a little closer
    if history:
        last_by = {who: line for who, line in history}
        for me, other in ((a, b), (b, a)):
            said = last_by.get(other.name, "")
            await me.remember(
                "social", f"talked with {other.name.capitalize()}"
                + (f'; they said "{said}"' if said else ""), 3)
            me.memory.rel_update(other.name, d_affinity=2, d_familiarity=5)
    await sock.send_json({"type": "converse_end", "a": a.name, "b": b.name})


COUNCIL_SPEAKERS = 8   # cap the dawn LLM burst; everyone still gets the plan


async def _run_council(sock, participants: list, report: dict) -> None:
    """Dawn assembly: reports from the past day, then one agreed plan that
    rides in every participant's decide prompt until the next dawn."""
    if not participants:
        return
    print(f"[cortex] COUNCIL: {len(participants)} gather at dawn "
          f"(day {report.get('day', '?')})")
    transcript = []
    for p in participants[:COUNCIL_SPEAKERS]:
        try:
            line = await p.council_line(report)
        except Exception as e:
            print(f"[cortex] council line failed for {p.name}: {e}")
            continue
        transcript.append((p.name, line))
        await sock.send_json({"type": "say", "npc": p.name, "text": line})
        print(f"[cortex]   {p.name.capitalize()}: {line}")
    chief = participants[0]
    try:
        plan = await chief.council_plan(report, transcript)
    except Exception as e:
        print(f"[cortex] council plan failed: {e}")
        plan = ""
    for p in participants:
        p.plan = plan
        await p.remember(
            "social", f"at the dawn council of day {report.get('day', '?')} "
            f"we agreed: {plan}" if plan else
            "stood at the dawn council with the others", 5)
    if plan:
        print(f"[cortex] COUNCIL PLAN: {plan}")
    await sock.send_json({"type": "council_end",
                          "npcs": [p.name for p in participants],
                          "plan": plan})


async def _handle_death(sock, agent: Agent, cause: str) -> None:
    """Mark the agent dead, tell the living, and compute what died with them.
    Knowledge lives in NPCs — if the last knower is gone, the tech is lost."""
    agent.dead = True
    agent.memory.state_set("dead", "1")
    world = app.state.world
    display = agent.persona.get("name", agent.name.capitalize())
    living = [x for x in app.state.agents.values() if not getattr(x, "dead", False)]
    living_known = set()
    for x in living:
        living_known |= set(x.known_tech)
    lost = sorted(set(agent.known_tech) - living_known)
    heir = None
    best_fam = -1.0
    for x in living:
        await x.remember("event", f"{display} died of {cause}", 8)
        rels = {r[0]: r for r in x.memory.rel_all()}
        rel = rels.get(agent.name)
        kin = rel is not None and rel[4] in ("my child", "my parent")
        close = rel is not None and rel[3] >= 15  # familiarity
        x.feel(-35 if kin else (-22 if close else -12), "grieving",
               f"{display} died of {cause}")
        fam = float(rel[3]) if rel is not None else 0.0
        if fam > best_fam:
            best_fam = fam
            heir = x
    text = f"{display} has died of {cause}."
    if lost and world and world.loss_mitigated(living_known) and heir is not None:
        # archives/records (E7.30/E8.34): the knowledge survives its knower
        for tech in lost:
            heir.learn_tech(tech, f"records of {display}")
        await heir.remember(
            "event", f"kept {display}'s knowledge alive through the records", 7)
        text += (f" Their knowledge was preserved in the records, "
                 f"kept by {heir.persona.get('name', heir.name.capitalize())}.")
        print(f"[cortex] KNOWLEDGE PRESERVED from {agent.name}: {lost} -> {heir.name}")
    elif lost:
        lost_names = ", ".join(world.tech_name(t) if world else t for t in lost)
        text += f" Their knowledge died with them: {lost_names}."
        print(f"[cortex] TECH LOST with {agent.name}: {lost}")
    print(f"[cortex] DEATH: {text}")
    await sock.send_json({"type": "status", "text": text})


async def _handle_birth(sock, a: Agent, b: Agent) -> None:
    """A child is born: traits inherited from the parents (+noise), knowledge
    starts at the basics — everything else must be taught before it's needed."""
    if a is None or b is None or a is b:
        return
    world = app.state.world
    used = set(app.state.agents)
    name = next((n for n in NAME_POOL if n not in used), None) or f"born{len(used)}"
    raw = generate_child(name, a.persona, b.persona,
                         world.traits if world else {}, seed=len(used) * 7919 + 13)
    parent_meta = app.state.npc_meta.get(a.name, {})
    if parent_meta.get("village"):
        raw["village"] = parent_meta["village"]
        raw["family"] = parent_meta.get("family", 0)
        app.state.npc_meta[name] = {"village": raw["village"], "family": raw["family"]}
    agent = Agent(
        name=name,
        persona=compile_persona(raw, world.traits if world else {}),
        llm=make_llm(app.state.child_brain or _next_pool_brain()
                     or app.state.fallback_brain),
        memory=Memory(str(app.state.mem_dir / f"{name}.sqlite")),
        world=world,
        embedder=app.state.embedder,
        flavor=app.state.flavor,
    )
    if app.state.discovery_override is not None:
        agent.discovery_rate = app.state.discovery_override
    # children exist only at runtime — persist the persona so the mind
    # survives a Cortex restart (resurrected in _startup)
    agent.memory.state_set("persona_json", json.dumps(raw))
    app.state.agents[name] = agent
    display = raw["name"]
    for parent in (a, b):
        await parent.remember("social", f"our child {display} was born", 9)
        parent.memory.rel_update(name, d_affinity=30, d_trust=20,
                                 d_familiarity=30, note="my child")
        agent.memory.rel_update(parent.name, d_affinity=30, d_trust=30,
                                d_familiarity=30, note="my parent")
        parent.feel(25, "joyful", f"our child {display} was born")
    brain = agent.llm.provider + (":" + agent.llm.model if agent.llm.model else "")
    print(f"[cortex] BIRTH: {display}, child of {a.name} and {b.name}")
    await sock.send_json({"type": "born",
                          "npc": {"id": name, "name": display, "brain": brain,
                                  "village": raw.get("village", "")},
                          "parents": [a.name, b.name]})


async def _handle_gift(giver: Agent, receiver: Agent, item: str) -> None:
    if giver is None or receiver is None or giver is receiver:
        return
    g_name = giver.persona.get("name", giver.name.capitalize())
    r_name = receiver.persona.get("name", receiver.name.capitalize())
    await giver.remember("social", f"gave {item} to {r_name} when they were starving", 5)
    await receiver.remember("social", f"{g_name} gave me {item} when I was starving", 7)
    giver.memory.rel_update(receiver.name, d_affinity=3, d_familiarity=3)
    receiver.memory.rel_update(giver.name, d_affinity=8, d_trust=6, d_familiarity=4,
                               note="shared food when I starved")
    receiver.feel(12, "grateful", f"{g_name} shared food with me")


@app.websocket("/ws")
async def ws_endpoint(sock: WebSocket):
    await sock.accept()
    await sock.send_json({"type": "status",
                          "text": "cortex online: " + ", ".join(app.state.agents)})
    await sock.send_json(_roster_msg())
    safe = _SafeSock(sock)

    async def handle(msg: dict) -> None:
        # each message runs as its own task: 30 villagers' decides hit the LLM
        # CONCURRENTLY (vLLM batches them) instead of queueing behind each other.
        # Read app.state.agents FRESH — a flavor switch rebinds the whole dict.
        agents = app.state.agents
        mtype = msg.get("type")
        agent = agents.get(str(msg.get("npc", "")))
        if agent is not None and getattr(agent, "dead", False) and mtype != "died":
            return  # the dead keep their memories but answer nothing
        try:
            if mtype == "chat" and agent:
                text = str(msg.get("text", ""))[:500]
                print(f"[cortex] CHAT visitor -> {agent.name}: {text}")
                reply = await agent.chat(text, state=msg.get("state"))
                print(f"[cortex]   {agent.name.capitalize()}: {reply}")
                await safe.send_json({"type": "say", "npc": agent.name, "text": reply})
            elif mtype == "decide" and agent:
                t0 = asyncio.get_event_loop().time()
                data = await agent.decide(msg.get("state", {}),
                                          tier=str(msg.get("tier", "full")))
                elapsed = asyncio.get_event_loop().time() - t0
                _stats["decides"] += 1
                _stats["seconds"] += elapsed
                _stats["actions"][data["action"]] = \
                    _stats["actions"].get(data["action"], 0) + 1
                if elapsed > 8.0:
                    print(f"[cortex] SLOW decide: {agent.name} took {elapsed:.1f}s")
                await safe.send_json({"type": "action", "npc": agent.name, **data})
                if "skill_learned" in data:
                    sk = data["skill_learned"]
                    print(f"[cortex] SKILL COMPOSED: {agent.name} -> "
                          f"'{sk['name']}' ({sk['description']})")
                    await safe.send_json({"type": "skill", "npc": agent.name,
                                          "name": sk["name"], "from": "practice"})
                if "learned" in data:
                    print(f"[cortex] TECH DISCOVERED: {agent.name} worked out "
                          f"{data['learned']['tech']} ({data['learned']['tech_name']})")
                    await _check_era(safe)
                # opportunity discovery (Wave E): a copper nugget carried to a
                # hot hearth runs shining — smelting is stumbled upon, not
                # reasoned out. The tree's designated "opportunity event".
                st = msg.get("state", {}) or {}
                world = app.state.world
                if (world and "E6.07" not in agent.known_tech
                        and "E6.01" in agent.known_tech
                        and int((st.get("inventory") or {}).get("copper_ore", 0)) > 0
                        and (st.get("fire") or {}).get("lit")
                        and float((st.get("fire") or {}).get("distance", 99)) < 6.0
                        and random.random() < 0.2):
                    agent.learn_tech("E6.07", "a nugget left in the hearth")
                    agent.feel(15, "awestruck",
                               "the green stone wept shining metal in the fire")
                    await safe.send_json(
                        {"type": "learned", "npc": agent.name, "tech": "E6.07",
                         "tech_name": world.tech_name("E6.07"),
                         "from": "insight"})
                    print(f"[cortex] OPPORTUNITY: {agent.name} saw copper run "
                          f"in the hearth -> E6.07")
                    await _check_era(safe)
            elif mtype == "event" and agent:
                text = str(msg.get("text", ""))[:300]
                hurt = "gored" in text or "bitten" in text
                await agent.remember("event", text, 6 if hurt else 2)
                if hurt:
                    agent.feel(-15, "shaken and fearful", text)
                # practice-based discovery: domestication is learned by DOING —
                # three harvest cycles, not an idle flash of insight
                world = app.state.world
                if "ripe grain" in text and world:
                    agent.harvest_count = getattr(agent, "harvest_count", 0) + 1
                    if (agent.harvest_count >= 3
                            and "E5.05" not in agent.known_tech
                            and "E5.04" in agent.known_tech):
                        agent.learn_tech("E5.05", "seasons of sowing and harvest")
                        agent.feel(12, "proud", "the grain grows tamer each year")
                        await safe.send_json(
                            {"type": "learned", "npc": agent.name, "tech": "E5.05",
                             "tech_name": world.tech_name("E5.05"),
                             "from": "practice"})
                        print(f"[cortex] TECH MASTERED BY PRACTICE: {agent.name} "
                              f"-> E5.05 ({world.tech_name('E5.05')})")
                        await _check_era(safe)
            elif mtype == "converse":
                a = agents.get(str(msg.get("a", "")))
                b = agents.get(str(msg.get("b", "")))
                if (a and b and a is not b
                        and not getattr(a, "dead", False)
                        and not getattr(b, "dead", False)):
                    await _run_converse(safe, a, b, app.state.world,
                                        inv_a=msg.get("inv_a"),
                                        inv_b=msg.get("inv_b"))
            elif mtype == "council":
                members = [agents.get(str(n)) for n in msg.get("npcs", [])]
                members = [m for m in members
                           if m is not None and not getattr(m, "dead", False)]
                await _run_council(safe, members, msg.get("report", {}) or {})
            elif mtype == "died" and agent and not getattr(agent, "dead", False):
                await _handle_death(safe, agent, str(msg.get("cause", "hardship")))
            elif mtype == "birth":
                await _handle_birth(safe, agents.get(str(msg.get("a", ""))),
                                    agents.get(str(msg.get("b", ""))))
            elif mtype == "social" and str(msg.get("event", "")) == "gift":
                await _handle_gift(agents.get(str(msg.get("from", ""))),
                                   agents.get(str(msg.get("to", ""))),
                                   str(msg.get("item", "food")))
            elif mtype == "hello":
                wanted = str(msg.get("flavor", "")) or app.state.flavor
                if wanted != app.state.flavor:
                    print(f"[cortex] switching flavor: {app.state.flavor} -> {wanted}")
                    _build_flavor(wanted)
                await safe.send_json(
                    {"type": "status", "text": "hello " + str(msg.get("world", "world"))
                        + f" ({app.state.flavor})"})
                await safe.send_json(_roster_msg())
        except Exception as e:  # LLM endpoint down/misbehaving must not kill the wire
            print(f"[cortex] {mtype} for {msg.get('npc')} failed: {e}")
            try:
                await safe.send_json(
                    {"type": "status", "text": f"{mtype} failed: {type(e).__name__}"})
            except Exception:
                pass  # socket already gone

    tasks: set = set()
    reporter = asyncio.create_task(_activity_reporter())
    try:
        while True:
            msg = await sock.receive_json()
            task = asyncio.create_task(handle(msg))
            tasks.add(task)
            task.add_done_callback(tasks.discard)
    except WebSocketDisconnect:
        pass
    finally:
        reporter.cancel()
        for task in tasks:
            task.cancel()
