# VOX Cortex — NPC Cognition Service (P1–P6)

The "mind" half of the project. Godot runs the bodies (terrain, walking, gathering, crafting, meetings); Cortex runs the minds (personas, memory, relationships, tech knowledge, LLM calls) and they talk over a WebSocket.

- P1 exit criterion: **chat with an NPC that remembers you** — across restarts (SQLite).
- P2 exit criterion: **the NPC knaps a tool because it *decided* to.**
- P3 exit criterion: **two NPCs exchange a technology** — one demonstrates, the other permanently learns.
- P4 exit criterion: **the village survives 10 in-game days unattended** — eating, hunting, cooking, tending the fire, resting at night.
- P5 exit criterion: **era transitions occur emergently** — NPCs discover technologies at their knowledge frontier, teaching spreads them, and the settlement crosses into the next era on its own.
- P6 exit criterion: **the settlement advances eras across generations** — founders age and die, children are born with inherited traits and empty heads, and the era climb continues anyway because knowledge is taught before it is lost.

```
Godot (bodies) ── ws://127.0.0.1:8765/ws ── Cortex (minds) ── http://127.0.0.1:8000/v1 ── LLM server
                                                │
                                     ../data/tech_tree.json
                                     ../data/era1_content.json
                                     ../data/traits.json
```

## Setup

```bash
cd cortex
python -m venv .venv && .venv\Scripts\activate     # Windows
pip install -r requirements.txt
```

## Pick a brain (one of three)

**A. vLLM (recommended for your A6000)** — best throughput for a 10-NPC village:
```bash
pip install vllm
vllm serve Qwen/Qwen2.5-14B-Instruct-AWQ --port 8000 --gpu-memory-utilization 0.85 --max-model-len 8192
```
vLLM runs best on Linux/WSL2. On native Windows, use Ollama below.

**B. Ollama (easiest start)**:
```bash
ollama pull qwen2.5:14b
```
Then in `config.yaml` set `base_url: http://127.0.0.1:11434/v1` and `model: qwen2.5:14b`.

**C. Mock (no GPU)**: `python -m cortex --config config.mock.yaml`. The mock brain follows each agent's built-in scripted suggestion and canned dialogue — the whole village (talking, teaching, crafting) runs offline. This is also the "scripted tier" used for distant NPCs at scale.

## Binding LLMs to NPCs

Three levels, all mixable:

1. **`brain_pool`** (recommended): list any number of models at the top of `config.yaml`; every NPC without its own `brain:` is bound to them **round-robin** in roster order — named NPCs first, then generated extras, then children born at runtime continue the rotation. With 4 pool entries, NPCs 1-4 get models 1-4, NPC 5 wraps back to model 1. Entries can point at different machines.
2. **Explicit `brain:` on an NPC** pins that NPC to a specific model, ignoring the pool.
3. **Runtime rebinding**: `POST /bind/<npc>` swaps a living NPC's model on the fly.

The Godot HUD's "Mind:" line always shows who runs on what.

## Run

```bash
python -m cortex --config config.yaml      # or config.mock.yaml
```

Then run the Godot project. Ten villagers spawn (the roster comes from this config over the wire). Watch the log for `TECH EXCHANGED` lines.

## Test (no GPU or Godot needed)

```bash
python tests/test_cortex.py     # -> CORTEX TESTS OK
```

## Cortex flavors (P8)

One server serves both — the Godot menu picks, and the hello handshake rebuilds the roster:

- **vanilla**: the guided 10-villager band (hand-written personas, survival advice in prompts, scripted suggestion anchor, era-gate-focused discovery).
- **emergent**: two villages of 5 (two families each; family bonds seeded stronger than village friendship; villages start strangers to each other). Minds are **blank** — empty `known_tech`, no goals or backstory, prompts carry bare facts with zero advice or suggestion anchor, discovery is pure undirected experimentation, and no narrator memories (era transitions stay engine-side). Memory in `data/memory_emergent/`. Note: the mock provider mostly wanders in this flavor — emergent is meant for real LLMs.

## Mood & persistence (P7b)

- **Mood**: an OCC-lite appraisal layer — deaths bring grief (deeper for kin and close friends, and it lingers longer in high-Emotionality souls), births joy, gifts gratitude, discoveries pride, animal attacks fear. The strongest recent feeling renders into every prompt ("Mood: you are deeply grieving — Sela died of old age.") and decays over time. Persisted per-NPC.
- **Persistence**: deaths and runtime-born children survive Cortex restarts (dead flag + persona stored in each mind's DB; orphan minds are resurrected at startup and the roster excludes the deceased). Godot saves the world each dawn — menu "Continue" restores everything.
- **E3-E4 + fauna**: blades → needles → sewn clothing, bows and arrows; hares, boars (they fight back), fishing shallows (needs E2.27), and wolves the engine handles with a flee-to-the-fire reflex.

## Generations & seasons (P6)

- **Aging**: bodies age each dawn (`lifecycle` block in `era1_content.json`); past their rolled lifespan they die of old age — and any tech only they knew dies too, unless it was taught first.
- **Births**: Godot rolls a birth each dawn (population-capped); Cortex casts the child — traits are the parents' average plus gaussian noise (the `traits.json` generation spec), values inherited, kin relationships seeded on both sides, knowledge starts at the E1 basics. Children must be *taught*.
- **Teaching is newest-first**: you show off your latest craft, not berry-picking — this is what lets deep chains assemble in one head across generations. The per-conversation cap is `2 + diffusion speed` (Wave G): demonstration-only bands teach 3, storytelling (E3.41) 4, schools (E7.31) 6, literacy (E8.29) 10.
- **Knowledge loss mitigation** (Wave G): once the settlement knows archives/records (E7.30 or E8.34), a last-knower's death no longer destroys their unique techs — the closest companion (highest familiarity) inherits them "from the records".
- **Storage economy** (Wave A): the decide catalog gains a STORE section when a cache pit/granary is near — `deposit` banks food surpluses (suggest rule: fed + ≥3 of a food), `withdraw` raids the larder when starving. The suggestion also builds a cache/granary when the band has none. Spoilage and vermin live in Godot (see godot/README).
- **The farming year** (Wave B): Godot reports a `fields` census ({plots, empty, growing, ripe}) in the decide state; `sow_field`/`harvest_field` only appear in the catalog against the right field state. The suggestion runs the year — harvest what's ripe, sow what's bare (gathering wild cereal for seed), break new ground while plots are few (~1 per 10 villagers). The tool chain self-assembles: `craft_or_fetch` recurses into craftable missing pieces (no hoe → make hoe → need a flake → knap → gather flint).
- **Practice-based discovery** (Wave B): E5.05 Cereal domestication is granted after an agent's third harvest event — the first tech learned by doing rather than by insight roll. Pattern generalizes via the event handler in server.py.
- **The herd** (Wave C, widened in Wave I): Godot reports a `corral` census ({herd, space, distance}); recipes carry data-driven gates — `requires_corral` and `requires_herd: goat/sheep/cattle/pig` hide penning/milking/wool/slaughter until the corral and animals exist. The instinct pens what was caught, catches while there is room, milks when hungry, and (rule 1) milks or slaughters before starving. `build_corral` joins the "band has none" rules.
- **Village census** (Wave I): Godot sends `{"type":"village","structures":[...],"dogs":N,"oxen":N}` at dawn and on every build. It gates infrastructure-dependent rules — the ×4+ diffusion tiers need a **school** standing (`_effective_teach_cap`), and the build-what's-missing instinct covers smelter/smoking rack/kiln/school generically. Beer events ("feels merry") lift mood via the event path.
- **Crafts** (Wave D): pots, yarn/cloth/garments and mudbricks are plain recipes — the novelty rule crafts them unprompted; the shelter rule prefers `build_mud_house` over `build_hut` once E5.49 is known.
- **Stations beyond the fire** (Wave E): recipes may declare any `station:` — the catalog hides them until Godot's `stations` census says that workshop stands (the smelter is the first). The furnace rule builds one as soon as smelting recipes are known; the metal chain itself (charcoal → ingots → axes) runs on the novelty rule. The **opportunity event** lives in the server's decide branch: copper ore + a lit fire nearby = 20%/decide to learn E6.07 without its prereqs — discovery by accident, as the tree intends.
- **Barter & coin** (Waves F+M): `converse` carries both inventories; after teaching, `_propose_trade` finds a complementary surplus (≥3 of an item the other entirely lacks, both ways) — and failing that, the richer purse **buys** a unit of the other's surplus at `world.item_value` prices. Trades carry counts; coins are excluded from barter surplus. Traders remember each other ("we trade", +trust).
- **Dawn council** (optional, per-game): Godot sends `{"type":"council","npcs":[...],"report":{day, season, fire_pct, food_in_stores, ...}}` at each dawn per village fire. Up to 8 participants each speak one report line (from their memories); the first participant sums the transcript into **one plan**, which is stored on every participant (`agent.plan`) and injected into their decide prompts as "THE DAWN COUNCIL AGREED: ..." until the next council. Everyone remembers what was agreed. `council_end` releases the villagers.
- **Skill library** (Voyager-style): an idle full-tier mind sometimes (`skill_rate`, default 0.15) reflects on its recent doings and **composes a named routine** — 2–5 validated steps chaining primitive actions (gather/craft/eat/deposit/withdraw), stored per-NPC in SQLite like techs (max 8). Routines appear in the decide prompt under YOUR ROUTINES; choosing `{"action":"skill","target":"<name>"}` sends the steps to Godot, which runs them as one macro-action (aborting cleanly on failure, wolves, or conversations). **One routine per conversation spreads teacher→learner** — villages develop distinct working cultures. Steps are validated against what the composer actually knows (unknown recipes are rejected), Voyager's "self-verification" analog.
- **Focused discovery**: experimenting concentrates (75%) on the prerequisite path to the settlement's next era gate — necessity is the mother of invention. In the marathon run: Odan taught Senn soft-hammer knapping → Senn discovered Levallois → taught Rasha → Rasha discovered stone points; Lira found birch tar; hafting followed and the band entered the Upper Paleolithic on day 25 — after most founders were already dead.
- **Seasons**: winter halts berry/fiber regrowth (`seasonal: true` resources) and the prompt says so; stored dried meat matters.
- **Marathon knobs**: `VOX_DAY_SECONDS` + `VOX_FIRE_DECAY` (Godot) and `VOX_DISCOVERY_RATE` (Cortex env). A ~10-minute run at `VOX_DAY_SECONDS=15, VOX_DISCOVERY_RATE=0.7` reaches era 3 across ~2 generations; leave it running overnight for the climb toward the Middle Ages.

## Discovery & eras (P5)

- **Discovery**: on an idle (or fireside-resting) decide, an O-trait-modulated roll may produce an *insight* — the NPC learns an unknown tech whose prerequisites they already hold, capped one era beyond the settlement. Curiosity biases the pick toward the newest era on their frontier. The action comes back as `experiment` with a `learned` payload; the knowledge is permanent and teachable like any other.
- **Era tracking**: the settlement enters era N when it knows every bottleneck of era N-1 and ≥3 techs of era N (recomputed on every learn). Transitions broadcast `{"type":"era"}` and everyone remembers the new age. In practice: Odan (the only soft-hammer knapper) discovers Levallois, others find cordage and shellfish, and the band crosses into the Middle Paleolithic within days.
- **E2 content wave**: cordage → hide-working → hide wraps (warm at night away from the fire), stone points → composite spears (better hunting), dried meat. Later eras follow the same data-driven pattern in `era1_content.json`'s recipe/resource tables.
- **Per-NPC model rebinding at runtime**:
  ```bash
  curl -X POST localhost:8765/bind/kara -H "Content-Type: application/json" \
       -d '{"provider":"openai_compatible","base_url":"http://127.0.0.1:11434/v1","model":"qwen2.5:14b"}'
  ```
  The roster message carries each NPC's current brain; the Godot HUD shows it.

## Survival (P4)

- **30 NPCs**: the 10 hand-written personas plus extras cast deterministically from the archetype deck (`village: {extras, seed, brain}` in config). Each generated villager gets archetype traits + noise and a random handful of known techs.
- **The scripted suggestion is the survival instinct.** Priorities: eat/cook/find food when hungry → keep the fire fed (tend_fire, E1.19) → rest by the fire at night → stock food → socialize → craft. Distant (scripted-tier) NPCs run on it with zero LLM calls, which is exactly why the village survives unattended.
- **Stakes**: hunting needs a weapon (catalog gates it), cooking needs a live fire (station recipes), starvation drains health, and death is permanent — `died` messages mark the agent dead and report which technologies **died with them** if they were the last knower.
- **Mutual aid**: the engine reports gifts (`social`/`gift`) — the fed share with the starving; both remember it and the bond strengthens.

## The village (P3)

- **Roster**: every NPC in `config.yaml` gets a body in Godot. Each has a persona YAML in `personas/` with HEXACO-ish trait scores (`data/traits.json` defines the axes); `cortex/personas.py` renders scores into prompt language (mid-band traits omitted, max 4, most extreme first). Hand-written personality lines always win over compiled ones.
- **Relationships**: per-pair affinity/trust/familiarity rows in each NPC's SQLite, updated by meetings and teaching, rendered into every prompt ("Kara: a friend, familiar (taught me thrown stones)").
- **Teaching** (the exit criterion): when two NPCs converse and one knows a tech the other doesn't, a willing teacher (agreeableness + community/knowledge values) demonstrates it. The learner's `known_tech` grows **permanently** (DB), both remember it, and the relationship strengthens. Knowledge lives in NPCs — if the last knower dies unheard, it's gone.
- **Every villager thinks with the LLM, everywhere on the map** — the WS server dispatches each request as its own asyncio task, so 30 concurrent decides batch inside vLLM instead of queueing. NPCs make an LLM-driven choice roughly every 5–15 s. (The `tier: "scripted"` path still exists in the protocol — it's the offline fallback and available if you ever want to scale far beyond one GPU.)

## Memory (P3-upgraded)

Every chat line, event, decision, and meeting is a row in `data/memory/<npc>.sqlite` with importance and an **embedding** (config block `embeddings:` — point it at vLLM/Ollama `/v1/embeddings`, or `mock` for offline hashing). Retrieval = importance + cosine relevance + keyword overlap + recency. Every ~30 importance points the agent **reflects**: recent memories are distilled into 2-3 stored beliefs. Delete the .sqlite file to wipe a mind (it will re-seed `known_tech` from its persona).

## Protocol

| Direction | Message |
|---|---|
| Godot → Cortex | `{"type":"chat","npc":"anon","text":"...","state":{...}}` |
| Godot → Cortex | `{"type":"decide","npc":"anon","tier":"full\|scripted","state":{needs, inventory, nearby, nearby_npcs}}` |
| Godot → Cortex | `{"type":"event","npc":"anon","text":"saw Kara knapping..."}` |
| Godot → Cortex | `{"type":"converse","a":"anon","b":"kara"}` — two NPCs met up |
| Cortex → Godot | `{"type":"roster","npcs":[{"id","name"},...]}` — sent on connect/hello |
| Cortex → Godot | `{"type":"say","npc":"anon","text":"..."}` |
| Cortex → Godot | `{"type":"action","npc":"anon","action":"wander\|idle\|say\|gather\|craft\|eat\|talk","target":"<id>","say":"..."}` |
| Cortex → Godot | `{"type":"learned","npc":"kara","tech":"E1.17","tech_name":"...","from":"anon"}` |
| Cortex → Godot | `{"type":"converse_end","a":"anon","b":"kara"}` |

## Next (P6+)

Content waves E3→E8 (same data-driven pattern); seasons; scripted discovery events (wildfire fire-capture, copper-in-hearth smelting insight); shared food stores; births/generations so the band outlives its founders; in-game binding UI on top of `/bind`.
