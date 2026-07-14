# VOX — Quick Start

Run a 30-person Stone Age village of LLM-driven NPCs that survives, learns, gives birth, dies, and advances through the ages on its own.

Two processes, in this order:

```
1. Cortex (the minds)   — Python service, port 8765
2. Godot  (the bodies)  — open godot/ and press F5
```

---

## 0. Prerequisites (one-time)

- **Godot 4.3+** standard build — you have `Godot_v4.3-stable_win64.exe` on the Desktop.
- **Python 3.10+** with the Cortex deps:
  ```powershell
  cd Desktop\Claude\Vox\cortex
  pip install -r requirements.txt
  ```
- *(Optional, for real LLM brains)* **Ollama** (easiest on Windows) or **vLLM** (best throughput, Linux/WSL2).

## 1. Start the minds

Pick ONE:

**A. No GPU / instant demo (mock brains)** — the whole simulation runs on scripted instincts and canned dialogue:
```powershell
cd Desktop\Claude\Vox\cortex
python -m cortex --config config.mock.yaml
```

**B. Ollama (real LLM, easiest)**:
```powershell
ollama pull qwen2.5:14b
```
Edit `cortex/config.yaml` → under `llm_defaults` set:
```yaml
base_url: http://127.0.0.1:11434/v1
model: qwen2.5:14b
```
then:
```powershell
python -m cortex --config config.yaml
```

**C. vLLM on the A6000 (WSL2/Linux)**:
```bash
vllm serve Qwen/Qwen2.5-14B-Instruct-AWQ --port 8000 --gpu-memory-utilization 0.85 --max-model-len 8192
python -m cortex --config config.yaml     # default config already points at :8000
```

You should see:
```
[cortex] world loaded: 440 tech nodes, 19 recipes, 6 resource types
[cortex] village extras cast: [arok, besh, ...]
[cortex] settlement era: 1 (Lower Paleolithic)
[cortex] agents ready: 30 (anon, toran, kara, bren, ...)
```

## 2. Start the bodies

Open the `godot/` folder in Godot 4.3 and press **F5**. A launch menu appears:

- **New Game** → pick a **map size** (96² / 128² / 192² / 256² / 512² / 1024² — the biggest takes ~90 s to generate and real RAM), **terrain**:
  - *Rolling hills* — the classic map
  - *Open plains* — wide, walkable, easy living
  - *River valley* — a winding river crossed by sand fords, lush banks
  - *Mountains* — dramatic peaks, scarce flat ground

  ...a **water slider** (0–60%): the sea level is placed so that exactly that share of the map is underwater — 0% is a dry world, 50%+ is an island world...

  ...and a **Cortex flavor**:
  - *Vanilla* — the guided village of 10 named villagers: personalities, goals, survival instincts woven into their prompts, story-focused discovery.
  - *Emergent* — **two villages of 5** (two families each, family bonds stronger than friendship), placed as far apart as the land allows, each with its own starting fire. Minds start **blank**: no knowledge, no goals, no advice, no suggested actions — bare facts only ("It is night. You are cold. You carry: nothing."). Everything must be experimented into existence or taught. Separate memory world (`data/memory_emergent/`). One concession to biology: a **starving body eats what it holds** on its own (a reflex like fleeing wolves, at hunger ≥85) — everything else, including keeping the fire alive, the minds must figure out or die.
- **Options** → **key bindings**: click a key, press the new one (persists across runs, `Reset to defaults` available).
- **Exit** — quits.

> **AZERTY users**: defaults are *physical* key positions, so camera pan is already on ZQSD without touching anything. Rebind in Options if you prefer other keys — all on-screen hints follow your bindings.

Press **Start**: the world generates (a fresh random seed every new game), the chat panel goes "Cortex: online", and 30 villagers spawn around the campfire.

**Continue** appears on the menu once a save exists: the game autosaves every dawn and on window close, and Continue rebuilds the exact same world — terrain, day, season, fire fuel, huts, gathered resources, and every villager's body where life left off (their minds never left; they live in Cortex).

> Headless/automated runs skip the menu automatically and take the map from env vars: `VOX_MAP_CHUNKS` (6..64), `VOX_TERRAIN` (`hills|plains|rivers|mountains`), and `VOX_WATER` (percent, e.g. `35`).

> First open after new code: if you see script errors, let the editor finish importing (or run once with `--headless --import`) and start again — Godot needs one pass to register new classes.

## 3. Controls (defaults — rebindable in Options)

| Input | Action |
|---|---|
| **Click an NPC** | open chat with them (they remember you across restarts) |
| **F** | focus next villager (HUD follows: needs, age, inventory, activity, tier, mind) |
| **LMB** on ground | order the focused NPC to walk there |
| **T** / **Esc** | open / close chat |
| **C** | toggle **conversation auto-focus** — the camera flies to villagers who stop to talk (won't hop between simultaneous conversations more than once per 10 s) |
| **RMB drag / Wheel / WASD (ZQSD on AZERTY)** | orbit / zoom / pan camera |

## 4. What to watch for

- Villagers gather, knap tools, hunt (hares, deer — and boars, which gore careless hunters), fish the shallows, cook at the fire, sew clothing, and rest by the fire at night.
- **Wolves prowl the wilds** — villagers who stray too far drop everything and run for the fire ("Wolf!"). The fire keeps wolves away... while it burns.
- Villagers **feel**: a death leaves them grieving, a birth joyful, a discovery proud — it colors everything they say and remember (ask one about their day after a funeral).
- `*** Kara DISCOVERED ... ***` — an idle mind worked something out.
- `*** Juk learned ... from Anon ***` — knowledge spreading (newest crafts first).
- `the season turns: it is now winter` — bushes stop regrowing; stores matter.
- `Sela dug and lined a storage cache` — the village gets a commons: surpluses are **deposited**, the hungry **withdraw**. Fresh food **rots** in days (`found that 2 berries rotted`), and `rats got into the storage cache...` until someone raises a granary (E5.11).
- `Lira broke and tilled the earth into a field plot` — **farming**: sow seed grain, wait 3 dawns (`a field plot is ripe for harvest`), cut the grain, replant. Frost kills winter crops; three harvests master Cereal domestication (E5.05) by practice. Grain grinds to flour, flour bakes to flatbread at the fire.
- `Toran cornered and trussed a wild goat` — **herding**: captured goats and sheep live in the corral, breed at dawn, and give milk, wool, and meat without the hunt. `the dogs drove a wolf away from the village` — tamed dogs (E4.07) push the wolves back.
- `Kara coiled clay and fired a pot in the embers` — **crafts**: pots unlock porridge and pickled berries; wool becomes yarn, cloth, then warm garments; mudbricks raise real houses with a wider hearth than any brush hut.
- `a nugget left in the hearth ran shining` — **metal**: copper smelting is discovered by accident, not reason. Charcoal + ore + a clay smelter give copper, bronze (needs rare tin), then iron — each axe tier speeds all work (up to 2.5×).
- `Kara traded copper ore for Toran's dried meat` — **barter**: villagers with complementary surpluses trade when they stop to talk, and remember their trading partners. With **coins** (struck 8 to the ingot at the smelter, E8.30) they can simply *buy* — `traded 5 copper coins for Sela's dried meat` — and when someone dies, the nearest villager `took up what they left behind`: wealth outlives its earner.
- `*** Sela worked out a routine of their own: berry run ***` — **skills** (Voyager-style): idle minds turn repeated work into named routines, run them as one action (`set about their berry run routine`), and pass them on at the fire — villages grow distinct working cultures.
- `Falo raided the other village's stores and made off with 3 dried meat` — **raids** (emergent flavor): taking what is not yours is a choice only a *mind* can make — no game rule ever starts one. Nobody dies: defenders scuffle, dogs drive thieves off, and the raided village *remembers*.
- `the watermill milled 5 flour overnight` — **power** (Wave J): mills on the riverbank (or windmills anywhere) grind whatever grain is deposited in them; a trip hammer halves smithing time; a screw press batches beer.
- `the smoking rack cured 4 smoked meat overnight` — **dawn processors**: racks smoke what was deposited in them while everyone sleeps; salt, beer (`drank beer and feels merry`), a kiln for batch pottery and dyes, cattle and pigs in the corral, and a **school hall** that the fast teaching tiers actually require to be standing.
- `The council agreed: ...` — **village council** (New Game checkbox, or `VOX_COUNCIL=1`): every dawn the villagers gather in a ring at their fire, each reports their day and speaks for the day ahead, and the elder sums it into one plan that guides every mind until the next dawn. Emergent maps hold one council per village. (Skipped on marathon days shorter than 60 s.)
- `X is born to Y and Z` / `X has died of old age` — generations turning over.
- `======== THE BAND HAS ENTERED THE MIDDLE PALEOLITHIC ========` — the point of it all.
- Every dawn, the console prints a chronicle line: alive count, season, era, fire fuel, births, deaths.

## 5. Time-lapse mode (optional)

Real-time days are 4 minutes. To watch generations pass, set env vars **before launching**:

```powershell
# Godot side (fast days, hungrier fire):
$env:VOX_DAY_SECONDS = "15"; $env:VOX_FIRE_DECAY = "6"
# Cortex side (more insights):
$env:VOX_DISCOVERY_RATE = "0.7"
```
~10 minutes ≈ two generations and an era or two. Leave it overnight for the Iron Age.

Headless time-lapse (no window, console chronicle only):
```powershell
& "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64_console.exe" --headless --path Desktop\Claude\Vox\godot
```

## 6. Handy operations

| Want to... | Do |
|---|---|
| Wipe all minds (fresh village) | delete `cortex\data\memory\*.sqlite` **and** the save file `%APPDATA%\Godot\app_userdata\VOX*\vox_save.json` (both apps stopped) — minds and world must reset together |
| Spread NPCs across several models | add entries to `brain_pool:` in the config — NPCs are bound round-robin (4 models → NPC 1-4 get models 1-4, NPC 5 wraps to 1) |
| Pin one NPC to a specific model | give that NPC an explicit `brain:` block (overrides the pool) |
| Rebind one NPC to another LLM at runtime | `curl -X POST localhost:8765/bind/kara -H "Content-Type: application/json" -d '{"provider":"openai_compatible","base_url":"http://127.0.0.1:11434/v1","model":"qwen2.5:14b"}'` |
| Check Cortex is healthy | `curl localhost:8765/` → lists agents |
| Run the test suite (no GPU/Godot needed) | `cd cortex && python tests\test_cortex.py` → `CORTEX TESTS OK` |
| Godot self-test only | run headless with `--quit` → `PATHFINDING OK / CRAFT ENGINE OK / RESOURCE FIELD OK` |
| Edit a villager's personality | `cortex\personas\*.yaml` (traits compile to prose automatically) |
| Change the roster size | `village: extras:` in the config |
| Regenerate the tech tree | `python tools\build_tech_tree.py` after editing `01_TECH_TREE.md` |
| Replace the box art with real 3D models | drop `.glb` files into `godot\assets\` (npc/, props/, campfire) — see `godot\assets\README.md` for the naming map, free CC0 packs, and AI generation on the A6000 |

## 7. Remote GPU host (Ubuntu)

The GPU box being Ubuntu-only is fine — every layer boundary is plain HTTP/WS. Two layouts:

**A. Only the LLM lives on Ubuntu** (simplest — Godot + Cortex stay on Windows):
```bash
# on the Ubuntu host
vllm serve Qwen/Qwen2.5-14B-Instruct-AWQ --host 0.0.0.0 --port 8000 \
     --gpu-memory-utilization 0.85 --max-model-len 8192
```
```yaml
# cortex/config.yaml on Windows
llm_defaults:
  base_url: http://<ubuntu-host>:8000/v1
embeddings:
  base_url: http://<ubuntu-host>:8000/v1
```

**B. Cortex also lives on Ubuntu** (minds co-located with the GPU):
```yaml
# cortex/config.yaml on the Ubuntu host — bind beyond localhost:
server: {host: 0.0.0.0, port: 8765}
```
```powershell
# on Windows, before launching Godot:
$env:VOX_CORTEX_URL = "ws://<ubuntu-host>:8765/ws"
```

Notes:
- Open the ports on the Ubuntu firewall (`sudo ufw allow 8000` / `8765`), or better, keep everything on localhost and use an SSH tunnel: `ssh -L 8000:localhost:8000 -L 8765:localhost:8765 user@ubuntu-host`.
- There is no auth on either service — treat them as LAN/tunnel-only.
- Per-NPC binding works across hosts: each NPC's `brain.base_url` (and `/bind`) can point at a *different* GPU box.
- Latency is a non-issue: calls are per-decision/per-utterance, not per-frame.

## 8. Troubleshooting

- **"Cortex: offline" in Godot** → start Cortex first (step 1); it auto-reconnects every 3 s.
- **Port 8765 busy** → an old Cortex is still running; kill the stray `python` process (or change `server.port` in the config).
- **NPCs wander but never talk/craft** → you're on the offline fallback (3 local NPCs). Same cause as above.
- **Slow/strange dialogue with a real LLM** → check the LLM server is up (`curl localhost:8000/v1/models` or `:11434`); the mock config always works for isolating this.
- **Everything looks wrong after a git pull / big edit** → run Godot once with `--headless --import`, and delete `cortex\data\memory\*.sqlite` if personas changed shape.

Design docs: [00_MASTER_PLAN.md](00_MASTER_PLAN.md) (architecture + roadmap, P0–P6 ✅), deeper READMEs in [cortex/](cortex/README.md) and [godot/](godot/README.md).
