"""End-to-end Cortex test with the mock LLM provider (no GPU needed).

Run from the cortex/ folder:  python tests/test_cortex.py
Verifies: WS protocol, chat/decide, memory persistence + embedding retrieval,
reflection, persona compilation, the P2 gather/craft/eat loop, and the P3
social layer (converse, teaching transfer, relationships, tiering).
"""

import asyncio
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT.parent / "data"
sys.path.insert(0, str(ROOT))

PERSONA_A = """
name: Anon
role: a hunter-gatherer
era: Stone Age
personality: [curious, patient]
speech_style: plain and short
background: Born by the river.
goals: [keep the fire alive]
traits: {O: 75, A: 60}
values: [knowledge]
known_tech: [E1.01, E1.02, E1.04, E1.07, E1.08, E1.13, E1.18]
"""

PERSONA_B = """
name: Toran
role: a hunter
era: Stone Age
traits: {B: 90, A: 55}
values: [prestige, kinship]
speech_style: boastful and warm
background: Took his first boar young.
goals: [take big game]
known_tech: [E1.01, E1.02, E1.09, E1.17]
"""

CONFIG = """
server: {host: 127.0.0.1, port: 8765}
data_dir: %s
embeddings: {provider: mock}
npcs:
  anon:
    persona: personas/anon.yaml
    memory_db: data/memory/anon.sqlite
    brain: {provider: mock}
  toran:
    persona: personas/toran.yaml
    memory_db: data/memory/toran.sqlite
    brain: {provider: mock}
"""


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


def test_world():
    from cortex.world import World

    world = World(str(DATA))
    assert len(world.nodes) == 440, "tech tree not fully loaded"
    assert world.max_era == 10, world.max_era
    assert world.era_name(9) == "Classical Antiquity"
    assert world.era_name(10) == "Middle Ages"
    # E1/E10 prefix regression: E10 techs must never count as era-1 techs,
    # and era-1 gates must not include E10 bottlenecks
    world.settlement_era = 1
    assert all(g.split(".")[0] == "E1" for g in world.next_gates()), \
        world.next_gates()
    e10_only = ["E10.01", "E10.05", "E10.07", "E1.01"]
    assert world.compute_era(e10_only) == 1, "E10 techs leaked into era 1 count"
    assert world.traits.get("axes"), "traits.json not loaded"
    assert "knap_flake" in world.recipes
    assert world.is_food("berries") and not world.is_food("flint")

    known = ["E1.01", "E1.02", "E1.13"]
    recipes = world.known_recipes(known)
    assert "knap_flake" in recipes and "sharpen_spear" not in recipes

    st = world.recipe_status(world.recipes["knap_flake"], {"flint": 1})
    assert not st["ready"] and st["missing_tools"] == ["hammerstone"]
    assert world.resource_yielding("flint") == "flint_nodule"
    print("  world OK")
    return world


def test_embeddings():
    from cortex.llm import Embedder
    from cortex.memory import Memory, _cosine

    emb = Embedder({"provider": "mock"})
    a = run(emb.embed("knapping flint by the river"))
    b = run(emb.embed("flint knapping"))
    c = run(emb.embed("berries and honey taste sweet"))
    assert _cosine(a, b) > _cosine(a, c), "mock embeddings not similarity-preserving"

    tmp = Path(tempfile.mkdtemp(prefix="cortex_emb_"))
    mem = Memory(str(tmp / "m.sqlite"))
    mem.add("event", "I knapped flint into sharp flakes", 2, embedding=b)
    mem.add("event", "I ate berries with honey", 2, embedding=c)
    got = mem.retrieve("working flint stone", k=1,
                       query_emb=run(emb.embed("working flint stone")))
    assert "flint" in got[0][2], got
    print("  embeddings OK")


def test_reflection_and_personas(world):
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory
    from cortex.personas import compile_persona, render_traits

    # persona compilation: bands render, mid-band omitted, most extreme first
    lines = render_traits({"O": 90, "C": 75, "X": 50, "B": 12}, world.traits)
    assert "restlessly inventive; always experimenting" in lines
    assert not any("X" in ln for ln in lines) and len(lines) == 3, lines
    assert lines[0] == "restlessly inventive; always experimenting" or "runs from shadows" in lines[0]

    p = compile_persona({"traits": {"O": 90}, "values": ["knowledge"]}, world.traits)
    assert p["personality"] and p["values_prose"], p

    # reflection: enough remembered importance triggers belief storage
    tmp = Path(tempfile.mkdtemp(prefix="cortex_refl_"))
    import yaml
    agent = Agent("anon", yaml.safe_load(PERSONA_A), make_llm({"provider": "mock"}),
                  Memory(str(tmp / "a.sqlite")), world=world,
                  embedder=Embedder({"provider": "mock"}))

    async def flood():
        for i in range(8):
            await agent.remember("event", f"day {i}: worked stone and ate", 5)
    run(flood())
    beliefs = agent.memory.recent(kinds=("belief",), limit=5)
    assert beliefs, "reflection produced no beliefs"
    print("  reflection + personas OK")


def test_decide(world):
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory
    import yaml

    tmp = Path(tempfile.mkdtemp(prefix="cortex_p2_"))
    agent = Agent("anon", yaml.safe_load(PERSONA_A), make_llm({"provider": "mock"}),
                  Memory(str(tmp / "anon.sqlite")), world=world,
                  embedder=Embedder({"provider": "mock"}))

    def decide(state, tier="full"):
        return run(agent.decide(state, tier=tier))

    # hungry with food in hand -> eat
    r = decide({"needs": {"hunger": 80, "energy": 70},
                "inventory": {"berries": 2}, "nearby": {}})
    assert r == {"action": "eat", "target": "berries", "say": ""}, r

    # someone nearby and never talked -> talk (band cohesion)
    r = decide({"needs": {"hunger": 10, "energy": 90}, "inventory": {},
                "nearby": {}, "nearby_npcs": {"toran": 6.0}})
    assert (r["action"], r["target"]) == ("talk", "toran"), r
    agent._last_talk_ts = __import__("time").time()  # cooldown engaged

    # fed, materials ready -> craft (P2 exit criterion)
    r = decide({"needs": {"hunger": 10, "energy": 90},
                "inventory": {"flint": 1, "hammerstone": 1}, "nearby": {}})
    assert r["action"] == "craft", r

    # scripted tier: same outcome, no LLM round-trip needed
    r = decide({"needs": {"hunger": 80, "energy": 70},
                "inventory": {"berries": 1}, "nearby": {}}, tier="scripted")
    assert r["action"] == "eat", r

    # validation: bogus LLM output degrades to the scripted suggestion
    v = agent._validate({"action": "craft", "target": "build_rocket"},
                        agent._build_catalog({}),
                        {"action": "wander", "target": "", "say": ""})
    assert v["action"] == "wander", v
    print("  decide OK")


def test_survival(world):
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory
    from cortex.personas import generate_village

    # village generation: deterministic, valid techs, sane traits
    v1 = generate_village(20, 7, world.traits, taken_names=["anon"])
    v2 = generate_village(20, 7, world.traits, taken_names=["anon"])
    assert len(v1) == 20 and v1 == v2, "village casting not deterministic"
    for p in v1.values():
        assert all(t in world.nodes for t in p["known_tech"]), p
        assert all(5 <= s <= 95 for s in p["traits"].values()), p

    tmp = Path(tempfile.mkdtemp(prefix="cortex_p4_"))
    keeper = {"name": "Bren", "role": "fire-keeper", "era": "Stone Age",
              "known_tech": ["E1.01", "E1.02", "E1.07", "E1.09",
                             "E1.19", "E1.20", "E1.21"]}
    agent = Agent("bren", keeper, make_llm({"provider": "mock"}),
                  Memory(str(tmp / "bren.sqlite")), world=world,
                  embedder=Embedder({"provider": "mock"}))
    agent.discovery_rate = 0.0   # survival assertions must not race an insight

    # catalog gating: hunting needs a weapon; cooking needs a live fire
    cat = agent._build_catalog({"inventory": {}, "nearby": {"small_game": 5.0}})
    assert not cat["gather"], "hunted bare-handed"
    # E3-E4 wave: fishing is tech-gated, boars need real weapons
    cat = agent._build_catalog({"inventory": {"club": 1},
                                "nearby": {"fishing_spot": 4.0, "boar": 6.0}})
    assert not cat["gather"], f"fished without E2.27 / hunted boar with a club: {cat['gather']}"
    fisher = Agent("x", {"name": "X", "known_tech": ["E2.27"]},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "x.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    cat = fisher._build_catalog({"inventory": {"bow": 1},
                                 "nearby": {"fishing_spot": 4.0, "boar": 6.0}})
    assert {g["target"] for g in cat["gather"]} == {"fishing_spot", "boar"}, cat["gather"]
    cat = agent._build_catalog({"inventory": {"club": 1}, "nearby": {"small_game": 5.0}})
    assert cat["gather"] and cat["gather"][0]["target"] == "small_game"
    cat = agent._build_catalog({"inventory": {"raw_meat": 1}, "nearby": {}})
    assert "cook_meat" not in {c["target"] for c in cat["craft"]}, "cooked without fire"
    cat = agent._build_catalog({"inventory": {"raw_meat": 1}, "nearby": {},
                                "fire": {"lit": False, "fuel": 0, "distance": 4}})
    targets = {c["target"] for c in cat["craft"]}
    assert "cook_meat" not in targets and "tend_fire" in targets, targets

    def decide(state):
        return run(agent.decide(state, tier="scripted"))

    fire_ok = {"lit": True, "fuel": 80, "distance": 5}
    # night -> rest by the fire
    r = decide({"needs": {"hunger": 10, "energy": 80}, "inventory": {},
                "nearby": {}, "time_of_day": "night", "fire": fire_ok})
    assert r["action"] == "rest", r
    # fire burning low + branches in hand -> tend it
    r = decide({"needs": {"hunger": 10, "energy": 80}, "inventory": {"branch": 2},
                "nearby": {}, "time_of_day": "day",
                "fire": {"lit": True, "fuel": 20, "distance": 3}})
    assert (r["action"], r["target"]) == ("craft", "tend_fire"), r
    # fire low, no branches, branches on the ground -> fetch them
    r = decide({"needs": {"hunger": 10, "energy": 80}, "inventory": {},
                "nearby": {"branch": 6.0}, "time_of_day": "day",
                "fire": {"lit": True, "fuel": 20, "distance": 3}})
    assert (r["action"], r["target"]) == ("gather", "branch"), r
    # hungry with raw meat and a lit fire -> cook before eating
    r = decide({"needs": {"hunger": 70, "energy": 80}, "inventory": {"raw_meat": 1},
                "nearby": {}, "time_of_day": "day", "fire": fire_ok})
    assert (r["action"], r["target"]) == ("craft", "cook_meat"), r

    # P7: a builder raises huts while the band is under-sheltered
    builder = Agent("bren", {**keeper, "known_tech": keeper["known_tech"] + ["E2.20"]},
                    make_llm({"provider": "mock"}), Memory(str(tmp / "b.sqlite")),
                    world=world, embedder=Embedder({"provider": "mock"}))
    builder.discovery_rate = 0.0
    r = run(builder.decide({"needs": {"hunger": 10, "energy": 90},
                            "inventory": {"branch": 6}, "nearby": {},
                            "huts": 0, "population": 12}, tier="scripted"))
    assert (r["action"], r["target"]) == ("craft", "build_hut"), r
    # missing branches but some on the ground -> fetch them
    r = run(builder.decide({"needs": {"hunger": 10, "energy": 90},
                            "inventory": {}, "nearby": {"branch": 7.0},
                            "huts": 0, "population": 12}, tier="scripted"))
    assert (r["action"], r["target"]) == ("gather", "branch"), r
    # sheltered enough -> back to normal life
    r = run(builder.decide({"needs": {"hunger": 10, "energy": 90},
                            "inventory": {"branch": 6}, "nearby": {},
                            "huts": 2, "population": 12}, tier="scripted"))
    assert r["target"] != "build_hut", r
    print("  survival OK")


def test_storage_economy(world):
    """Wave A (stores) + Wave G (diffusion tiers): catalog, suggest, speeds."""
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory

    # diffusion tiers: better communication tech -> faster teaching
    assert world.diffusion_speed([]) == 1
    assert world.diffusion_speed(["E1.25"]) == 1        # demonstration
    assert world.diffusion_speed(["E3.41"]) == 2        # storytelling
    assert world.diffusion_speed(["E3.41", "E7.31"]) == 4   # schools
    assert world.diffusion_speed(["E8.29"]) == 8        # literacy
    # loss mitigation: archives/records preserve a dead NPC's knowledge
    assert not world.loss_mitigated(["E1.01", "E3.41"])
    assert world.loss_mitigated(["E7.30"]) and world.loss_mitigated(["E8.34"])

    tmp = Path(tempfile.mkdtemp(prefix="cortex_store_"))
    agent = Agent("bren", {"name": "Bren", "known_tech": ["E1.01", "E1.07"]},
                  make_llm({"provider": "mock"}), Memory(str(tmp / "b.sqlite")),
                  world=world, embedder=Embedder({"provider": "mock"}))
    agent.discovery_rate = 0.0

    # store catalog: only food stacks (>=2) go in; anything held comes out
    cat = agent._build_catalog({
        "inventory": {"berries": 5, "flint": 3, "raw_meat": 1},
        "nearby": {},
        "storage": {"kind": "cache_pit", "distance": 3.0, "space": 10,
                    "holds": {"dried_meat": 4}}})
    assert cat["store"]["deposit"] == ["berries"], cat["store"]
    assert cat["store"]["withdraw"] == ["dried_meat"], cat["store"]
    # no storage nearby -> no store section at all
    cat = agent._build_catalog({"inventory": {"berries": 5}, "nearby": {}})
    assert not cat["store"], cat["store"]
    # full store with nothing inside -> nothing to do with it
    cat = agent._build_catalog({
        "inventory": {"berries": 5}, "nearby": {},
        "storage": {"kind": "granary", "distance": 2.0, "space": 0, "holds": {}}})
    assert not cat["store"], cat["store"]

    def decide(state):
        return run(agent.decide(state, tier="scripted"))

    # starving with an empty pouch -> raid the larder
    r = decide({"needs": {"hunger": 70, "energy": 80}, "inventory": {},
                "nearby": {}, "time_of_day": "day",
                "storage": {"kind": "cache_pit", "distance": 3.0, "space": 10,
                            "holds": {"dried_meat": 4}}})
    assert (r["action"], r["target"]) == ("withdraw", "dried_meat"), r
    # well fed with a berry surplus -> bank it in the commons
    r = decide({"needs": {"hunger": 10, "energy": 90}, "inventory": {"berries": 5},
                "nearby": {}, "time_of_day": "day",
                "storage": {"kind": "cache_pit", "distance": 3.0, "space": 10,
                            "holds": {}}})
    assert (r["action"], r["target"]) == ("deposit", "berries"), r
    print("  storage economy OK")


def test_farming(world):
    """Wave B: field-gated catalog + the farming year in the suggestion."""
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory

    tmp = Path(tempfile.mkdtemp(prefix="cortex_farm_"))
    FARM_TECH = ["E1.01", "E1.02", "E1.07", "E4.19", "E5.01", "E5.03", "E5.04"]
    farmer = Agent("fara", {"name": "Fara", "known_tech": FARM_TECH},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "f.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    farmer.discovery_rate = 0.0

    # catalog gating: sow needs a bare plot, harvest needs a ripe one
    cat = farmer._build_catalog({"inventory": {"seed_grain": 2}, "nearby": {}})
    targets = {c["target"] for c in cat["craft"]}
    assert "till_plot" in targets, targets
    assert "sow_field" not in targets and "harvest_field" not in targets, targets
    cat = farmer._build_catalog({"inventory": {"seed_grain": 2}, "nearby": {},
                                 "fields": {"plots": 1, "empty": 1, "growing": 0,
                                            "ripe": 0}})
    targets = {c["target"] for c in cat["craft"]}
    assert "sow_field" in targets and "harvest_field" not in targets, targets
    cat = farmer._build_catalog({"inventory": {}, "nearby": {},
                                 "fields": {"plots": 1, "empty": 0, "growing": 0,
                                            "ripe": 1}})
    targets = {c["target"] for c in cat["craft"]}
    assert "harvest_field" in targets and "sow_field" not in targets, targets
    # wild cereal stands are tech-gated on E4.19
    novice = Agent("x", {"name": "X", "known_tech": ["E1.07"]},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "x.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    assert not novice._build_catalog(
        {"inventory": {}, "nearby": {"wild_cereal": 4.0}})["gather"]
    assert farmer._build_catalog(
        {"inventory": {}, "nearby": {"wild_cereal": 4.0}})["gather"]

    def decide(state):
        return run(farmer.decide(state, tier="scripted"))

    base = {"needs": {"hunger": 10, "energy": 90}, "nearby": {},
            "time_of_day": "day", "population": 10}
    # ripe field -> bring in the harvest before anything else agricultural
    r = decide({**base, "inventory": {},
                "fields": {"plots": 2, "empty": 1, "growing": 0, "ripe": 1}})
    assert (r["action"], r["target"]) == ("craft", "harvest_field"), r
    # bare field + seed in hand -> sow
    r = decide({**base, "inventory": {"seed_grain": 3},
                "fields": {"plots": 1, "empty": 1, "growing": 0, "ripe": 0}})
    assert (r["action"], r["target"]) == ("craft", "sow_field"), r
    # bare field, no seed, wild cereal nearby -> go gather seed
    r = decide({**base, "inventory": {}, "nearby": {"wild_cereal": 6.0},
                "fields": {"plots": 1, "empty": 1, "growing": 0, "ripe": 0}})
    assert (r["action"], r["target"]) == ("gather", "wild_cereal"), r
    # no plots yet, hoe in hand -> break new ground
    r = decide({**base, "inventory": {"hoe": 1}})
    assert (r["action"], r["target"]) == ("craft", "till_plot"), r
    # no hoe either -> the tool chain self-assembles (make the hoe first)
    r = decide({**base, "inventory": {"branch": 1, "stone_flake": 1}})
    assert (r["action"], r["target"]) == ("craft", "make_hoe"), r
    print("  farming OK")


def test_farming_practice():
    """Wave B: E5.05 domestication is mastered by DOING (3 harvests)."""
    tmp = Path(tempfile.mkdtemp(prefix="cortex_prac_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "fara.yaml").write_text("""
name: Fara
role: a farmer
traits: {C: 80}
known_tech: [E1.01, E4.19, E5.01, E5.03, E5.04]
""", encoding="utf-8")
    (tmp / "personas" / "toran.yaml").write_text(PERSONA_B, encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text("""
server: {host: 127.0.0.1, port: 8765}
data_dir: %s
embeddings: {provider: mock}
npcs:
  fara:
    persona: personas/fara.yaml
    memory_db: data/memory/fara.sqlite
    brain: {provider: mock}
  toran:
    persona: personas/toran.yaml
    memory_db: data/memory/toran.sqlite
    brain: {provider: mock}
""" % DATA.as_posix(), encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        with client.websocket_connect("/ws") as ws:
            ws.receive_json()  # status
            ws.receive_json()  # roster
            for _ in range(3):
                ws.send_json({"type": "event", "npc": "fara",
                              "text": "cut and gathered the ripe grain: 5 grain"})
            r = ws.receive_json()
            assert r["type"] == "learned" and r["tech"] == "E5.05", r
            assert r["from"] == "practice", r
        assert "E5.05" in app.state.agents["fara"].known_tech
    print("  farming practice OK")


def test_herding_and_crafts(world):
    """Waves C+D: corral/herd catalog gating, pastoral instinct, craft chains."""
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory

    tmp = Path(tempfile.mkdtemp(prefix="cortex_herd_"))
    HERDER = ["E1.01", "E1.02", "E1.07", "E2.07", "E4.07", "E4.08",
              "E5.17", "E5.18", "E5.19", "E5.22", "E5.24"]
    herder = Agent("tor", {"name": "Tor", "known_tech": HERDER},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "t.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    herder.discovery_rate = 0.0

    # gating: no corral -> no penning/milking; corral+goat -> both appear
    cat = herder._build_catalog({"inventory": {"captured_goat": 1}, "nearby": {}})
    targets = {c["target"] for c in cat["craft"]}
    assert "build_corral" in targets, targets
    assert "pen_goat" not in targets and "milk_goats" not in targets, targets
    cat = herder._build_catalog({
        "inventory": {"captured_goat": 1}, "nearby": {},
        "corral": {"distance": 4.0, "herd": {}, "space": 8}})
    targets = {c["target"] for c in cat["craft"]}
    assert "pen_goat" in targets and "milk_goats" not in targets, targets
    cat = herder._build_catalog({
        "inventory": {}, "nearby": {},
        "corral": {"distance": 4.0, "herd": {"goat": 2}, "space": 6}})
    targets = {c["target"] for c in cat["craft"]}
    assert "milk_goats" in targets and "slaughter_goat" in targets, targets
    assert "pluck_wool" not in targets, targets  # no sheep in the pen

    def decide(state):
        return run(herder.decide(state, tier="scripted"))

    base = {"needs": {"hunger": 10, "energy": 90}, "nearby": {},
            "time_of_day": "day", "population": 10}
    # carrying a trussed goat near a corral -> pen it
    r = decide({**base, "inventory": {"captured_goat": 1},
                "corral": {"distance": 4.0, "herd": {}, "space": 8}})
    assert (r["action"], r["target"]) == ("craft", "pen_goat"), r
    # empty corral, wild goats on the hill -> go catch one
    r = decide({**base, "inventory": {}, "nearby": {"wild_goat": 8.0},
                "corral": {"distance": 4.0, "herd": {}, "space": 8}})
    assert (r["action"], r["target"]) == ("gather", "wild_goat"), r
    # starving with a milkable herd -> milk before slaughter
    r = decide({**base, "needs": {"hunger": 70, "energy": 80}, "inventory": {},
                "corral": {"distance": 4.0, "herd": {"goat": 3}, "space": 5}})
    assert (r["action"], r["target"]) == ("craft", "milk_goats"), r
    # no corral yet, materials in hand -> build one
    r = decide({**base, "inventory": {"branch": 6, "cord": 2}})
    assert (r["action"], r["target"]) == ("craft", "build_corral"), r
    # village has no dog and meat is in hand -> tame one
    r = decide({**base, "inventory": {"raw_meat": 2}, "dogs": 0,
                "corral": {"distance": 4.0, "herd": {"goat": 1}, "space": 7}})
    assert (r["action"], r["target"]) == ("craft", "tame_dog"), r

    # Wave D: the craft chains are plain recipes — novelty rule picks them up
    potter = Agent("pia", {"name": "Pia",
                           "known_tech": ["E1.01", "E5.34", "E5.48", "E5.49"]},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "p.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    potter.discovery_rate = 0.0
    r = run(potter.decide({"needs": {"hunger": 10, "energy": 90},
                           "inventory": {"clay": 2}, "nearby": {},
                           "fire": {"lit": True, "fuel": 80, "distance": 3},
                           "time_of_day": "day"}, tier="scripted"))
    assert (r["action"], r["target"]) == ("craft", "coil_pot"), r
    # under-sheltered village + mudbricks -> a real house beats a brush hut
    r = run(potter.decide({"needs": {"hunger": 10, "energy": 90},
                           "inventory": {"mudbrick": 6, "branch": 4},
                           "nearby": {}, "huts": 0, "population": 12,
                           "time_of_day": "day"}, tier="scripted"))
    assert (r["action"], r["target"]) == ("craft", "build_mud_house"), r
    # weaving chain: wool -> yarn -> cloth -> garment, all by novelty
    weaver = Agent("wea", {"name": "Wea", "known_tech": ["E5.42", "E5.43"]},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "w.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    weaver.discovery_rate = 0.0
    r = run(weaver.decide({"needs": {"hunger": 10, "energy": 90},
                           "inventory": {"wool": 2}, "nearby": {},
                           "time_of_day": "day"}, tier="scripted"))
    assert (r["action"], r["target"]) == ("craft", "spin_yarn"), r
    print("  herding + crafts OK")


def test_metallurgy_and_trade(world):
    """Waves E+F: station-gated smelting, the furnace rule, barter proposals."""
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory
    from cortex.server import _propose_trade

    tmp = Path(tempfile.mkdtemp(prefix="cortex_metal_"))
    SMITH = ["E1.01", "E5.34", "E5.48", "E6.01", "E6.04", "E6.05", "E6.06",
             "E6.07", "E6.09", "E7.01", "E7.02"]
    smith = Agent("smi", {"name": "Smi", "known_tech": SMITH},
                  make_llm({"provider": "mock"}), Memory(str(tmp / "s.sqlite")),
                  world=world, embedder=Embedder({"provider": "mock"}))
    smith.discovery_rate = 0.0

    # station gating: no smelter built -> no smelting; built -> it appears
    inv = {"copper_ore": 2, "charcoal": 2}
    cat = smith._build_catalog({"inventory": inv, "nearby": {},
                                "fire": {"lit": True, "fuel": 80, "distance": 3}})
    targets = {c["target"] for c in cat["craft"]}
    assert "build_smelter" in targets and "smelt_copper" not in targets, targets
    cat = smith._build_catalog({"inventory": inv, "nearby": {},
                                "fire": {"lit": True, "fuel": 80, "distance": 3},
                                "stations": ["smelter"]})
    targets = {c["target"] for c in cat["craft"]}
    assert "smelt_copper" in targets and "smelt_bronze" in targets, targets
    # ore veins are tech-gated like everything else
    assert smith._build_catalog(
        {"inventory": {}, "nearby": {"copper_vein": 5.0, "tin_vein": 8.0}})["gather"]

    def decide(state):
        return run(smith.decide(state, tier="scripted"))

    base = {"needs": {"hunger": 10, "energy": 90}, "nearby": {},
            "time_of_day": "day", "population": 10}
    # the furnace comes first: materials in hand, no smelter -> build it
    r = decide({**base, "inventory": {"mudbrick": 4, "clay": 2}})
    assert (r["action"], r["target"]) == ("craft", "build_smelter"), r
    # smelter up + ore + charcoal -> the novelty rule runs the metal chain
    r = decide({**base, "inventory": {"copper_ore": 2, "charcoal": 2},
                "stations": ["smelter"],
                "fire": {"lit": True, "fuel": 80, "distance": 3}})
    assert (r["action"], r["target"]) == ("craft", "smelt_copper"), r

    # Wave F barter: complementary surplus swaps, anything else doesn't
    swap = _propose_trade({"dried_meat": 4, "flint": 1},
                          {"berries": 5, "flint": 2})
    assert swap == {"give": "dried_meat", "take": "berries"}, swap
    assert _propose_trade({"berries": 5}, {"berries": 4}) is None
    assert _propose_trade({"berries": 2}, {"flint": 5}) is None  # no surplus
    print("  metallurgy + trade OK")


def test_skill_library(world):
    """Voyager-style routines: composed from experience, validated against
    real capabilities, executed as one macro-action, persistent."""
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory

    tmp = Path(tempfile.mkdtemp(prefix="cortex_skill_"))
    agent = Agent("rua", {"name": "Rua",
                          "known_tech": ["E1.01", "E1.02", "E1.07", "E3.29"]},
                  make_llm({"provider": "mock"}), Memory(str(tmp / "r.sqlite")),
                  world=world, embedder=Embedder({"provider": "mock"}))
    agent.discovery_rate = 0.0

    # validation: steps must be real — unknown recipes and bad actions die
    assert agent._valid_skill({"name": "x!", "steps": []}) is None
    assert agent._valid_skill(
        {"name": "cheat", "description": "?",
         "steps": [{"action": "craft", "target": "forge_iron_axe"},
                   {"action": "gather", "target": "berry_bush"}]}) is None
    ok = agent._valid_skill(
        {"name": "Berry Run", "description": "stock the larder",
         "steps": [{"action": "gather", "target": "berry_bush"},
                   {"action": "deposit", "target": "berries"}]})
    assert ok and ok["name"] == "berry_run" and len(ok["steps"]) == 2, ok

    # composition: enough lived experience + the mock's canned routine
    agent.skill_rate = 1.0
    for i in range(5):
        agent.memory.add("event", f"gathered 3 berries (trip {i})", 2)
    r = run(agent.decide({"needs": {"hunger": 5, "energy": 90},
                          "inventory": {}, "nearby": {}}, tier="full"))
    assert "skill_learned" in r and r["skill_learned"]["name"] == "berry_run", r
    agent.skill_rate = 0.0
    names = [s[0] for s in agent.memory.skills_all()]
    assert names == ["berry_run"], names

    # the routine shows in the prompt and an LLM pick returns its steps
    assert "berry_run" in agent._catalog_block(agent._build_catalog(
        {"inventory": {}, "nearby": {}}))
    picked = agent._validate({"action": "skill", "target": "berry_run"},
                             {}, {"action": "wander", "target": "", "say": ""})
    assert picked["action"] == "skill" and len(picked["steps"]) == 2, picked
    assert agent.memory.skills_all()[0][4] == 1, "use count not bumped"
    # unknown routine falls back to the suggestion
    picked = agent._validate({"action": "skill", "target": "nope"},
                             {}, {"action": "wander", "target": "", "say": ""})
    assert picked["action"] == "wander", picked

    # persistence: a new mind over the same sqlite still knows the routine
    again = Memory(str(tmp / "r.sqlite"))
    assert [s[0] for s in again.skills_all()] == ["berry_run"]
    print("  skill library OK")


def test_wave_i(world):
    """Wave I: infrastructure builds, wider herds, school-gated diffusion,
    beer cheer."""
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory
    from cortex.server import _effective_teach_cap

    tmp = Path(tempfile.mkdtemp(prefix="cortex_wavei_"))
    agent = Agent("ira", {"name": "Ira",
                          "known_tech": ["E1.01", "E2.07", "E2.28", "E3.27",
                                         "E5.20", "E5.21", "E5.22", "E5.31",
                                         "E5.33", "E5.37", "E7.31"]},
                  make_llm({"provider": "mock"}), Memory(str(tmp / "i.sqlite")),
                  world=world, embedder=Embedder({"provider": "mock"}))
    agent.discovery_rate = 0.0
    agent.skill_rate = 0.0

    def decide(state):
        return run(agent.decide(state, tier="scripted"))

    base = {"needs": {"hunger": 10, "energy": 90}, "nearby": {},
            "time_of_day": "day", "population": 10}
    # no smoking rack anywhere -> build one (materials in hand)
    r = decide({**base, "inventory": {"branch": 4, "cord": 2}})
    assert (r["action"], r["target"]) == ("craft", "build_smoking_rack"), r
    # rack exists -> the next gap is the kiln
    r = decide({**base, "inventory": {"mudbrick": 6, "clay": 4},
                "village": ["smoking_rack"]})
    assert (r["action"], r["target"]) == ("craft", "build_kiln"), r
    # cattle in the pen: starving -> milk them (cows before goats)
    r = decide({**base, "needs": {"hunger": 70, "energy": 80}, "inventory": {},
                "corral": {"distance": 3.0, "herd": {"cattle": 2}, "space": 6}})
    assert (r["action"], r["target"]) == ("craft", "milk_cattle"), r
    # a trussed pig in hand near the corral -> pen it
    r = decide({**base, "inventory": {"captured_pig": 1},
                "village": ["smoking_rack", "kiln", "school", "smelter"],
                "corral": {"distance": 3.0, "herd": {}, "space": 8}})
    assert (r["action"], r["target"]) == ("craft", "pen_pig"), r

    # school gates the fast diffusion tiers: schools known but not built
    known = {"E1.25", "E3.41", "E7.31"}
    assert _effective_teach_cap(world, known, []) == 4          # capped at story
    assert _effective_teach_cap(world, known, ["school"]) == 6  # hall standing
    assert _effective_teach_cap(world, {"E1.25"}, []) == 3      # low tiers free

    # beer: the merry event lifts the mood (server event path logic)
    agent.feel(10, "merry", "drank beer and feels merry")
    assert agent.mood.get("emotion") == "merry", agent.mood

    # Wave J: the miller builds what the village lacks, and press recipes
    # stay hidden until the press stands
    miller = Agent("mil", {"name": "Mil",
                           "known_tech": ["E1.01", "E8.20", "E9.40", "E9.12"]},
                   make_llm({"provider": "mock"}), Memory(str(tmp / "m.sqlite")),
                   world=world, embedder=Embedder({"provider": "mock"}))
    miller.discovery_rate = 0.0
    miller.skill_rate = 0.0
    r = run(miller.decide({"needs": {"hunger": 10, "energy": 90},
                           "inventory": {"branch": 10, "cord": 4, "mudbrick": 4},
                           "nearby": {}, "time_of_day": "day",
                           "village": ["smelter"], "population": 10},
                          tier="scripted"))
    assert (r["action"], r["target"]) == ("craft", "build_watermill"), r
    cat = miller._build_catalog({"inventory": {"grain": 6}, "nearby": {}})
    assert "press_beer" not in {c["target"] for c in cat["craft"]}
    cat = miller._build_catalog({"inventory": {"grain": 6}, "nearby": {},
                                 "stations": ["screw_press"]})
    assert "press_beer" in {c["target"] for c in cat["craft"]}
    print("  wave I OK")


def test_discovery(world):
    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory

    # era computation: bottleneck gate + 3 techs of the next era
    e1_full = [t for t in world.nodes if t.startswith("E1.")]
    assert world.compute_era(e1_full) == 1, "3 E2 techs required"
    assert world.compute_era(e1_full + ["E2.07", "E2.26", "E2.13"]) == 2
    no_fire = [t for t in e1_full if t != "E1.18"]
    assert world.compute_era(no_fire + ["E2.07", "E2.26", "E2.13"]) == 1, \
        "era 2 without the fire bottleneck"

    tmp = Path(tempfile.mkdtemp(prefix="cortex_p5_"))
    import yaml
    agent = Agent("anon", yaml.safe_load(PERSONA_A), make_llm({"provider": "mock"}),
                  Memory(str(tmp / "a.sqlite")), world=world,
                  embedder=Embedder({"provider": "mock"}))

    # frontier: prereqs known, era-capped at settlement_era + 1
    frontier = agent.discoverable()
    assert "E2.07" in frontier, frontier          # cordage: needs only foraging
    assert "E2.03" not in frontier, frontier      # scraper: needs the Levallois line
    assert all(t.startswith(("E1.", "E2.")) for t in frontier), frontier

    # forced insight: rate >= 1 fires every idle decide
    agent.discovery_rate = 100.0
    r = run(agent.decide({"needs": {"hunger": 5, "energy": 90},
                          "inventory": {}, "nearby": {}}, tier="scripted"))
    assert r["action"] == "experiment" and r["learned"]["from"] == "insight", r
    assert r["learned"]["tech"] in agent.known_tech, "insight not learned"
    mem2 = Memory(str(tmp / "a.sqlite"))
    assert r["learned"]["tech"] in mem2.techs_all(), "insight not persisted"
    print("  discovery OK")


def test_children(world):
    from cortex.personas import generate_child

    pa = {"name": "Anon", "traits": {"O": 80, "C": 70}, "values": ["knowledge"]}
    pb = {"name": "Sela", "traits": {"O": 20, "A": 90}, "values": ["kinship"]}
    c1 = generate_child("tavi", pa, pb, world.traits, seed=42)
    c2 = generate_child("tavi", pa, pb, world.traits, seed=42)
    assert c1 == c2, "child generation not deterministic"
    assert set(c1["traits"]) == {"O", "C", "A"}, c1["traits"]
    assert all(5 <= v <= 95 for v in c1["traits"].values()), c1["traits"]
    assert c1["values"] == ["knowledge", "kinship"], c1["values"]
    assert c1["known_tech"] == ["E1.01", "E1.02", "E1.07"], "children must be taught"
    assert c1["parents"] == ["Anon", "Sela"], c1
    # inheritance pulls toward the parents: O centered on 50, not on 80 or 20
    import statistics
    samples = [generate_child("x", pa, pb, world.traits, seed=s)["traits"]["O"]
               for s in range(60)]
    assert 40 <= statistics.mean(samples) <= 60, statistics.mean(samples)
    print("  children OK")


def test_mood(world):
    import time as _t

    import yaml

    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory

    tmp = Path(tempfile.mkdtemp(prefix="cortex_mood_"))
    agent = Agent("anon", yaml.safe_load(PERSONA_A), make_llm({"provider": "mock"}),
                  Memory(str(tmp / "a.sqlite")), world=world,
                  embedder=Embedder({"provider": "mock"}))
    assert agent._mood_line() == "", "fresh mind should be neutral"

    agent.feel(-35, "grieving", "Sela died of old age")
    line = agent.persona_block()
    assert "deeply grieving" in line and "Sela died" in line, line

    # decay: default temperament shakes it off sooner than a sensitive one
    agent.mood["ts"] = _t.time() - 2700
    assert agent._mood_line() == "", agent._mood_line()
    sensitive = Agent("sela", {**yaml.safe_load(PERSONA_A), "traits": {"E": 80}},
                      make_llm({"provider": "mock"}), Memory(str(tmp / "s.sqlite")),
                      world=world, embedder=Embedder({"provider": "mock"}))
    sensitive.feel(-35, "grieving", "Sela died")
    sensitive.mood["ts"] = _t.time() - 2700
    assert "grieving" in sensitive._mood_line(), sensitive._mood_line()

    # persistence across restart
    agent.feel(20, "joyful", "our child was born")
    reborn = Agent("anon", yaml.safe_load(PERSONA_A), make_llm({"provider": "mock"}),
                   Memory(str(tmp / "a.sqlite")), world=world,
                   embedder=Embedder({"provider": "mock"}))
    assert "joyful" in reborn._mood_line(), reborn._mood_line()
    print("  mood OK")


def test_emergent(world):
    import yaml

    from cortex.agent import Agent
    from cortex.llm import Embedder, make_llm
    from cortex.memory import Memory
    from cortex.personas import generate_emergent_village

    villages = {"riverside": [["asha", "beno"], ["ciro", "dena", "ewa"]],
                "hilltop": [["falo", "gani"], ["hesu", "iria", "jomo"]]}
    cast = generate_emergent_village(villages, seed=3)
    assert len(cast) == 10
    assert cast == generate_emergent_village(villages, seed=3), "not deterministic"
    assert all(p["known_tech"] == [] for p in cast.values()), "minds must start blank"
    assert cast["asha"]["village"] == "riverside" and cast["jomo"]["village"] == "hilltop"

    tmp = Path(tempfile.mkdtemp(prefix="cortex_emg_"))
    agent = Agent("asha", cast["asha"], make_llm({"provider": "mock"}),
                  Memory(str(tmp / "a.sqlite")), world=world,
                  embedder=Embedder({"provider": "mock"}), flavor="emergent")
    agent.discovery_rate = 0.0

    # prompt purity: no suggestion anchor, no survival advice, bare state facts
    async def capture():
        captured = {}
        orig = agent.llm.chat

        async def spy(messages, json_mode=False):
            captured["prompt"] = messages[0]["content"]
            return await orig(messages, json_mode)
        agent.llm.chat = spy
        await agent.decide({"needs": {"hunger": 70, "energy": 20},
                            "inventory": {}, "nearby": {"berry_bush": 4.0},
                            "time_of_day": "night", "cold": True,
                            "fire": {"lit": False, "fuel": 0, "distance": 5}})
        return captured["prompt"]
    prompt = run(capture())
    for banned in ("SUGGESTED_ACTION", "you need food soon", "keep the fire fed",
                   "falls apart", "dark and cold away"):
        assert banned not in prompt, f"emergent prompt not bare: found {banned!r}"
    assert "You are cold." in prompt and "The fire is out." in prompt, prompt

    # emergent frontier: only no-prerequisite techs are reachable from nothing
    frontier = agent.discoverable()
    assert frontier and all(not world.nodes[t]["prerequisites"] for t in frontier), \
        frontier
    print("  emergent OK")


def test_brain_pool():
    tmp = Path(tempfile.mkdtemp(prefix="cortex_pool_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "anon.yaml").write_text(PERSONA_A, encoding="utf-8")
    (tmp / "personas" / "toran.yaml").write_text(PERSONA_B, encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text("""
server: {host: 127.0.0.1, port: 8765}
data_dir: %s
embeddings: {provider: mock}
brain_pool:
  - {provider: mock, model: m1}
  - {provider: mock, model: m2}
  - {provider: mock, model: m3}
village: {extras: 3, seed: 5}
npcs:
  anon:
    persona: personas/anon.yaml
    memory_db: data/memory/anon.sqlite
  toran:
    persona: personas/toran.yaml
    memory_db: data/memory/toran.sqlite
    brain: {provider: mock, model: pinned}
""" % DATA.as_posix(), encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        agents = app.state.agents
        # named: anon takes pool slot 1; toran's explicit brain is untouched
        assert agents["anon"].llm.model == "m1", agents["anon"].llm.model
        assert agents["toran"].llm.model == "pinned", agents["toran"].llm.model
        # extras continue the rotation: m2, m3, wrap to m1
        extras = [a.llm.model for n, a in agents.items() if n not in ("anon", "toran")]
        assert extras == ["m2", "m3", "m1"], extras
        # a child born at runtime continues it further: m2
        with client.websocket_connect("/ws") as ws:
            ws.receive_json()  # status
            ws.receive_json()  # roster
            ws.send_json({"type": "birth", "a": "anon", "b": "toran"})
            r = ws.receive_json()
            assert r["type"] == "born", r
            assert agents[r["npc"]["id"]].llm.model == "m2", r
    print("  brain pool OK")


def test_server_social():
    tmp = Path(tempfile.mkdtemp(prefix="cortex_test_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "anon.yaml").write_text(PERSONA_A, encoding="utf-8")
    (tmp / "personas" / "toran.yaml").write_text(PERSONA_B, encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text(CONFIG % DATA.as_posix(), encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        health = client.get("/").json()
        assert set(health["agents"]) == {"anon", "toran"}, health

        # runtime model rebinding (the per-NPC binding seam)
        r = client.post("/bind/anon", json={"provider": "mock"}).json()
        assert r["ok"] and r["brain"].startswith("mock"), r
        r = client.post("/bind/nobody", json={"provider": "mock"}).json()
        assert not r["ok"], r

        with client.websocket_connect("/ws") as ws:
            assert ws.receive_json()["type"] == "status"
            roster = ws.receive_json()
            assert roster["type"] == "roster" and len(roster["npcs"]) == 2, roster
            assert all("brain" in n for n in roster["npcs"]), roster

            ws.send_json({"type": "chat", "npc": "anon",
                          "text": "Remember this: my name is JB."})
            r = ws.receive_json()
            assert r["type"] == "say" and r["npc"] == "anon" and r["text"], r

            ws.send_json({"type": "decide", "npc": "anon", "tier": "scripted",
                          "state": {"needs": {"hunger": 90}, "inventory": {"berries": 1}}})
            r = ws.receive_json()
            assert r["type"] == "action" and r["action"] == "eat", r

            # --- P3 exit criterion: two NPCs exchange technologies ---
            ws.send_json({"type": "converse", "a": "anon", "b": "toran"})
            says, learned_list, ended = [], [], False
            while not ended:
                r = ws.receive_json()
                if r["type"] == "say":
                    says.append(r)
                elif r["type"] == "learned":
                    learned_list.append(r)
                elif r["type"] == "converse_end":
                    ended = True
            assert len(says) >= 4, f"expected a real conversation, got {says}"
            taught = [r["tech"] for r in learned_list]
            # multi-teach, newest knowledge first
            assert taught == sorted(taught, reverse=True) and len(taught) >= 2, taught
            assert taught[0] == "E1.18", taught
            assert all(r["npc"] == "toran" for r in learned_list), learned_list

            # --- P6: a child is born, with inherited traits and kin bonds ---
            from cortex.server import app as live_app
            ws.send_json({"type": "birth", "a": "anon", "b": "toran"})
            r = ws.receive_json()
            assert r["type"] == "born" and r["parents"] == ["anon", "toran"], r
            child_id = r["npc"]["id"]
            assert child_id in client.get("/").json()["agents"], child_id
            child = live_app.state.agents[child_id]
            assert child.persona.get("parents") == ["Anon", "Toran"], child.persona
            child_rels = {x[0]: x for x in child.memory.rel_all()}
            assert child_rels.get("anon", (0,) * 5)[4] == "my parent", child_rels

            # --- P5 exit criterion: an era transition occurs emergently ---
            agents = live_app.state.agents
            agents["anon"].discovery_rate = 100.0   # force insights on idle decides
            era_msg = None
            for _ in range(80):
                ws.send_json({"type": "decide", "npc": "anon", "tier": "scripted",
                              "state": {"needs": {"hunger": 5, "energy": 90},
                                        "inventory": {}, "nearby": {}}})
                r = ws.receive_json()
                assert r["type"] == "action", r
                if "learned" in r:
                    known = set(agents["anon"].known_tech) | set(agents["toran"].known_tech)
                    if live_app.state.world.compute_era(known) >= 2:
                        era_msg = ws.receive_json()
                        break
            assert era_msg and era_msg["type"] == "era" and era_msg["era"] == 2, era_msg
            assert "Middle Paleolithic" in era_msg["name"], era_msg
            agents["anon"].discovery_rate = 0.0

            # --- P4: gifting food, then death with tech loss ---
            unique = set(agents["toran"].known_tech) - set(agents["anon"].known_tech)
            ws.send_json({"type": "social", "event": "gift",
                          "from": "anon", "to": "toran", "item": "berries"})
            ws.send_json({"type": "died", "npc": "toran", "cause": "starvation"})
            r = ws.receive_json()
            assert r["type"] == "status" and "died" in r["text"], r
            if unique:
                assert "knowledge died with them" in r["text"], \
                    f"unique tech loss not reported: {r['text']}"
            # the living grieve — and toran stays dead across restarts
            assert agents["anon"].mood.get("emotion") == "grieving", agents["anon"].mood
            from cortex.memory import Memory as _M
            assert _M(str(tmp / "data" / "memory" / "toran.sqlite")).state_get("dead") == "1"
            # the dead answer nothing; the wire stays alive
            ws.send_json({"type": "chat", "npc": "toran", "text": "hello?"})
            ws.send_json({"type": "hello", "world": "still-here"})
            r = ws.receive_json()
            assert r["type"] == "status" and "hello" in r["text"], r

    # --- persistence across restart: learned tech survives in the DB ---
    from cortex.memory import Memory

    mem = Memory(str(tmp / "data" / "memory" / "toran.sqlite"))
    assert "E1.18" in mem.techs_all(), "learned tech not persisted"
    rels = {r[0]: r for r in mem.rel_all()}
    assert "anon" in rels and rels["anon"][3] > 0, "relationship not recorded"
    assert "shared food" in (rels["anon"][4] or ""), rels  # gift note overwrote taught-me
    rows_t = mem.recent(limit=30)
    assert any(r[1] == "social" and "gave me berries" in r[2] for r in rows_t), \
        "gift not remembered"

    mem_a = Memory(str(tmp / "data" / "memory" / "anon.sqlite"))
    rows = mem_a.recent(limit=30)
    assert any("JB" in r[2] for r in rows), "chat memory not persisted"
    assert any(r[1] == "social" and "showed" in r[2] for r in rows), \
        "teacher does not remember teaching"

    # --- Cortex restart: runtime-born children resurrect, the dead stay dead ---
    with TestClient(app) as client2:
        assert child_id in client2.get("/").json()["agents"], \
            "runtime-born child lost on Cortex restart"
        assert app.state.agents["toran"].dead, "death not persisted across restart"
        with client2.websocket_connect("/ws") as ws2:
            ws2.receive_json()  # status
            ids = {n["id"] for n in ws2.receive_json()["npcs"]}
            assert child_id in ids and "toran" not in ids, ids
    print("  server social OK")


def test_death_mitigation():
    """Wave G: with archives (E7.30) alive, a dead NPC's unique knowledge is
    inherited by their closest companion instead of being lost."""
    tmp = Path(tempfile.mkdtemp(prefix="cortex_mitig_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "sage.yaml").write_text("""
name: Sage
role: a keeper of old ways
traits: {O: 80}
known_tech: [E1.01, E2.07, E2.26]
""", encoding="utf-8")
    (tmp / "personas" / "scribe.yaml").write_text("""
name: Scribe
role: a keeper of records
traits: {C: 80}
known_tech: [E1.01, E7.30]
""", encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text("""
server: {host: 127.0.0.1, port: 8765}
data_dir: %s
embeddings: {provider: mock}
npcs:
  sage:
    persona: personas/sage.yaml
    memory_db: data/memory/sage.sqlite
    brain: {provider: mock}
  scribe:
    persona: personas/scribe.yaml
    memory_db: data/memory/scribe.sqlite
    brain: {provider: mock}
""" % DATA.as_posix(), encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        agents = app.state.agents
        with client.websocket_connect("/ws") as ws:
            ws.receive_json()  # status
            ws.receive_json()  # roster
            ws.send_json({"type": "died", "npc": "sage", "cause": "old age"})
            r = ws.receive_json()
            assert r["type"] == "status" and "died" in r["text"], r
            assert "preserved in the records" in r["text"], r
            assert "Scribe" in r["text"], r
        # the heir carries the dead sage's unique techs now
        assert {"E2.07", "E2.26"} <= set(agents["scribe"].known_tech), \
            agents["scribe"].known_tech
        # and it persisted
        from cortex.memory import Memory
        mem = Memory(str(tmp / "data" / "memory" / "scribe.sqlite"))
        assert "E2.07" in mem.techs_all(), "inherited tech not persisted"
    print("  death mitigation OK")


def test_opportunity_and_trade():
    """Wave E: copper runs in the hearth (opportunity discovery).
    Wave F: a converse with complementary surpluses proposes a trade."""
    import random as _random

    tmp = Path(tempfile.mkdtemp(prefix="cortex_opp_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "kupa.yaml").write_text("""
name: Kupa
role: a stone-gatherer
traits: {O: 70}
known_tech: [E1.01, E6.01]
""", encoding="utf-8")
    (tmp / "personas" / "toran.yaml").write_text(PERSONA_B, encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text("""
server: {host: 127.0.0.1, port: 8765}
data_dir: %s
embeddings: {provider: mock}
npcs:
  kupa:
    persona: personas/kupa.yaml
    memory_db: data/memory/kupa.sqlite
    brain: {provider: mock}
  toran:
    persona: personas/toran.yaml
    memory_db: data/memory/toran.sqlite
    brain: {provider: mock}
""" % DATA.as_posix(), encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        agents = app.state.agents
        agents["kupa"].discovery_rate = 0.0
        _random.seed(7)
        with client.websocket_connect("/ws") as ws:
            ws.receive_json()  # status
            ws.receive_json()  # roster
            # ore in the pouch, resting by a lit fire: sooner or later the
            # nugget runs shining (20%/decide)
            state = {"needs": {"hunger": 5, "energy": 90},
                     "inventory": {"copper_ore": 1},
                     "fire": {"lit": True, "fuel": 80, "distance": 2.0},
                     "nearby": {}}
            fired = False
            for _ in range(60):
                ws.send_json({"type": "decide", "npc": "kupa",
                              "tier": "scripted", "state": state})
                r = ws.receive_json()
                assert r["type"] == "action", r
                if "E6.07" in agents["kupa"].known_tech:
                    r = ws.receive_json()
                    assert r["type"] == "learned" and r["tech"] == "E6.07", r
                    fired = True
                    break
            assert fired, "opportunity discovery never fired in 60 decides"

            # complementary surpluses -> a trade rides along with the converse;
            # a routine one side knows spreads too (Voyager skill library)
            agents["kupa"].memory.skill_add(
                "ore_walk", "collect the green stones",
                [{"action": "gather", "target": "copper_vein"}], "composed")
            ws.send_json({"type": "converse", "a": "kupa", "b": "toran",
                          "inv_a": {"copper_ore": 4},
                          "inv_b": {"dried_meat": 3}})
            trade, skill_msg, ended = None, None, False
            while not ended:
                r = ws.receive_json()
                if r["type"] == "trade":
                    trade = r
                elif r["type"] == "skill":
                    skill_msg = r
                elif r["type"] == "converse_end":
                    ended = True
            assert trade and trade["give"] == "copper_ore" \
                and trade["take"] == "dried_meat", trade
            assert skill_msg and skill_msg["npc"] == "toran" \
                and skill_msg["name"] == "ore_walk", skill_msg
            assert [s[0] for s in agents["toran"].memory.skills_all()] \
                == ["ore_walk"], "routine did not spread"
    print("  opportunity + trade OK")


def test_council():
    """Dawn council: everyone speaks, one plan lands in every mind."""
    tmp = Path(tempfile.mkdtemp(prefix="cortex_council_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "anon.yaml").write_text(PERSONA_A, encoding="utf-8")
    (tmp / "personas" / "toran.yaml").write_text(PERSONA_B, encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text(CONFIG % DATA.as_posix(), encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        agents = app.state.agents
        with client.websocket_connect("/ws") as ws:
            ws.receive_json()  # status
            ws.receive_json()  # roster
            ws.send_json({"type": "council", "npcs": ["anon", "toran"],
                          "report": {"day": 5, "season": "autumn",
                                     "alive": 2, "fire_pct": 40,
                                     "food_in_stores": 7, "huts": 1}})
            says, ended, plan = [], False, ""
            while not ended:
                r = ws.receive_json()
                if r["type"] == "say":
                    says.append(r["npc"])
                elif r["type"] == "council_end":
                    ended = True
                    plan = r["plan"]
                    assert set(r["npcs"]) == {"anon", "toran"}, r
            assert set(says) == {"anon", "toran"}, says
            assert "fire" in plan.lower() or "larder" in plan.lower(), plan
        # the plan now rides in every participant's head (and their memory)
        assert agents["anon"].plan == plan and agents["toran"].plan == plan
        rows = agents["anon"].memory.recent(kinds=["social"], limit=5)
        assert any("dawn council" in r[2] for r in rows), rows
    print("  council OK")


def test_flavor_switch():
    """Hello with a flavor rebuilds the roster: two villages, family bonds."""
    tmp = Path(tempfile.mkdtemp(prefix="cortex_flv_"))
    (tmp / "personas").mkdir()
    (tmp / "personas" / "anon.yaml").write_text(PERSONA_A, encoding="utf-8")
    (tmp / "personas" / "toran.yaml").write_text(PERSONA_B, encoding="utf-8")
    cfg_path = tmp / "config.yaml"
    cfg_path.write_text((CONFIG % DATA.as_posix()) + """
emergent:
  seed: 3
  villages:
    riverside:
      - [asha, beno]
      - [ciro, dena, ewa]
    hilltop:
      - [falo, gani]
      - [hesu, iria, jomo]
""", encoding="utf-8")
    os.environ["CORTEX_CONFIG"] = str(cfg_path)

    from fastapi.testclient import TestClient

    from cortex.server import app

    with TestClient(app) as client:
        with client.websocket_connect("/ws") as ws:
            ws.receive_json()  # status
            r = ws.receive_json()
            assert r["flavor"] == "vanilla" and len(r["npcs"]) == 2, r
            ws.send_json({"type": "hello", "flavor": "emergent"})
            ws.receive_json()  # hello status
            r = ws.receive_json()
            assert r["flavor"] == "emergent" and len(r["npcs"]) == 10, r
            villages = {n["village"] for n in r["npcs"]}
            assert villages == {"riverside", "hilltop"}, villages
            # regression guard: decides on the SAME connection must reach the
            # rebuilt roster (the handler once held a stale agents dict)
            app.state.agents["asha"].discovery_rate = 0.0  # keep the mind blank
            ws.send_json({"type": "decide", "npc": "asha", "tier": "full",
                          "state": {"needs": {"hunger": 10}, "inventory": {},
                                    "nearby": {}}})
            r = ws.receive_json()
            assert r["type"] == "action" and r["npc"] == "asha", r
        # family bonds stronger than village acquaintance, memories per flavor
        asha = app.state.agents["asha"]
        rels = {x[0]: x for x in asha.memory.rel_all()}
        assert rels["beno"][3] > rels["ciro"][3], "family must outrank village"
        assert rels["beno"][4] == "my family", rels["beno"]
        assert "falo" not in rels, "strangers across villages must not know each other"
        assert asha.known_tech == [], "emergent minds must start with nothing"
        assert "memory_emergent" in str(app.state.mem_dir)
    print("  flavor switch OK")


def main():
    world = test_world()
    test_embeddings()
    test_reflection_and_personas(world)
    test_decide(world)
    test_survival(world)
    test_storage_economy(world)
    test_farming(world)
    test_herding_and_crafts(world)
    test_metallurgy_and_trade(world)
    test_skill_library(world)
    test_wave_i(world)
    test_discovery(world)
    test_children(world)
    test_mood(world)
    test_emergent(world)
    test_brain_pool()
    test_server_social()
    test_death_mitigation()
    test_farming_practice()
    test_opportunity_and_trade()
    test_council()
    test_flavor_switch()
    print("CORTEX TESTS OK")


if __name__ == "__main__":
    main()
