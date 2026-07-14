# VOX — Godot Client (P0 terrain · P1 mind bridge · P2 crafting · P3 village · P4 survival · P5 discovery · P6 generations)

Voxel world where a 30-person village of LLM-driven NPCs survives on its own and **advances through the ages**: day/night, a campfire that must be tended, hunting and cooking, conversations, teaching, food-sharing, death — and now discovery. Idle minds work out new technologies, knowledge spreads, and one day the console prints `THE BAND HAS ENTERED THE MIDDLE PALEOLITHIC`. Stock Godot, no plugins.

## Run

1. **Godot 4.3+** (standard build): open this folder, F5. A launch menu offers **New Game** (map size 96²→1024²; terrain: hills, plains, river valley, mountains), **Options** (rebindable keys, physical-position defaults so AZERTY just works), and **Exit**. Headless runs skip the menu (env: `VOX_MAP_CHUNKS`, `VOX_TERRAIN`).
2. Start the mind service — see `../cortex/README.md`:
   ```
   cd ../cortex && python -m cortex --config config.yaml        # real LLM
   cd ../cortex && python -m cortex --config config.mock.yaml   # no GPU needed
   ```
   The NPC roster arrives over the wire — whatever `config.yaml` defines gets a body. Offline fallback spawns 3 local wanderers.

## Controls

LMB: order the focused NPC / **click any NPC to chat with them** · F: focus next NPC · T: chat with focused · Esc: close chat · RMB drag: orbit · Wheel: zoom · WASD: pan.

## What happens (skill library — routines as culture)

- **Villagers develop habits**: an idle mind notices it keeps doing the same work and names it — `*** Sela worked out a routine of their own: berry run ***`. A routine is a chain of real steps (gather → craft → store...) the body then executes as **one action**, walking the whole circuit (`set about their berry run routine` ... `finished their berry run routine`).
- **Routines spread like knowledge**: one per conversation, demonstrated at the fire (`*** Kara picked up the smoke the catch routine from Toran ***`) — over generations, villages develop distinct working cultures. Inspired by NVIDIA GEAR's Voyager skill library.
- Routines abort honestly — a wolf, a missing ingredient, or a conversation interrupts the circuit and the villager says why.

## What happens (Wave J — power)

- **The watermill must stand on the bank** — the first building the land itself constrains. Deposit grain in it (or the windmill, whose sails rise anywhere) and dawn brings `the watermill milled 5 flour overnight` — the village's first non-muscle power.
- **The screw press** batches beer and berry preserves without pots; **the trip hammer** rigged beside the smelter halves every smithing job.

## What happens (Wave I — the pantry, the pen and the school)

- **The smoking rack works while the village sleeps**: deposit raw meat or fish in it and dawn brings `the smoking rack cured 4 smoked meat overnight` — 20-day food from 1-day food. Salt flats on the shore give salted meat (30 days). The preservation ladder is complete: cook < dry < smoke < salt < pickle.
- **Beer**: grain mashed in a pot becomes beer, and drinkers *feel merry* — the village's first luxury, and a mood you'll hear in their chatter.
- **The corral fills out**: cattle (twice the milk, a feast of meat) and pigs join goats and sheep; a cow can be trained into a **draft ox** — Wave L's plow teams will want them.
- **The kiln** batch-fires pots away from the campfire and boils berry dye for dyed garments — the first pure trade good.
- **The school hall makes knowledge infrastructure real**: the ×4+ teaching tiers now require the building to be *standing*, not just the idea of schools to be known. Lose the hall, lose the pace.

## What happens (Waves E+F — metal and markets)

- **Kara chases the copper**: green-stained veins (E6.04) in the stone give ore; branches char to charcoal at the fire (E6.05); mudbricks and clay raise a **smelter** — the village's first true workshop, and NPCs carry their ore to it like they carry meat to the fire.
- **Smelting is *stumbled on***: nobody reasons their way to E6.07 — someone carrying copper ore rests by a lit fire and `a nugget left in the hearth ran shining`. The tree's designated opportunity event.
- **Metal pays**: copper → bronze → iron axes speed *all* gathering and crafting (1.5× / 2× / 2.5×). Bronze needs tin, and tin is genuinely rare — two gravel beds per map — so it moves by wandering and **barter**.
- **Trade rides along with talk** (Wave F): when two villagers converse with complementary surpluses ("I hold plenty of what you lack"), goods change hands — `Kara traded copper ore for Toran's dried meat` — and both remember the partner as someone they trade with.

## What happens (Waves C+D — herds, dogs, pots and real houses)

- **Toran keeps animals now**: wild goats and sheep (E5.17) are *captured*, not hunted — trussed and carried to a corral (E5.18, a ring of posts near the fire). Penned pairs breed each dawn (`a young goat was born in the corral`). The herd is a living larder: milk (E5.22), wool (E5.24), or slaughter for meat and hide without the hunt.
- **Dogs guard the village** (E4.07): each tamed dog widens the wolf-safe ground around the fires — `the dogs drove a wolf away from the village`.
- **Kara fires pottery**: clay banks by the water (E5.34) → pots fired in the embers. Pots unlock porridge (E5.30) and pickled berries (E5.32 — 40-day shelf life, the best cache filler in the game).
- **Real houses**: clay + straw → mudbricks (E5.48) → a mudbrick house (E5.49) with a wider warmth radius than any brush hut; builders prefer it once known. Wool spins to yarn, weaves to cloth, sews into warm garments (E5.42–43).

## What happens (Wave B — agriculture)

- **Lira knows the grasses**: wild cereal stands (E4.19) yield wild grain and seed grain. Anyone with Sowing & crop tending (E5.04) breaks ground with a hoe (`till_plot` → a dark square of tilled earth), walks seed out to the field, and sows.
- **Crops grow a step each dawn** (3 dawns to ripe); the console announces `a field plot is ripe for harvest`. Harvesting yields grain + seed to replant — a sickle (E5.08) cuts 50% more. **Winter frost kills standing crops**, so the farming year matters.
- **Grain chain**: grain → flour (ground with a hammerstone, E4.20) → flatbread baked at the fire (E5.29, best food in the game at 45 hunger).
- **Practice makes knowledge**: three harvests master Cereal domestication (E5.05, an era-5 bottleneck) — the first tech learned by *doing* instead of idle insight (`*** Lira MASTERED Cereal domestication through seasons of practice ***`).

## What happens (Wave A — the food economy)

- The village builds **storage**: anyone with Food caching (E3.29) digs a cache pit near the fire; a granary (E5.11) follows later. Stores hold a shared inventory — villagers `deposit` food surpluses and `withdraw` when hungry; the HUD/decide catalog shows what the store holds.
- **Food spoils**: each dawn every perishable stack (in pouches *and* stores) loses roughly `count / spoils_days` — berries last ~2 days, raw meat 1, dried meat 15. Preservation techs are now survival math, not flavor.
- **Vermin raid open caches**: 30%/dawn a non-vermin-safe store loses a quarter of its food (`rats got into the storage cache and ate 3 berries`). Granaries stand on posts and are immune — that's why E5.11 matters.
- Stores persist through save/load; only structures with warmth count toward the shelter quota.

## What happens (P7a — the living world)

- The map is **full**: real tree models (5 Kenney varieties), thousands of instanced grass tufts, flowers, mushrooms, pebbles and stumps (`decoration.gd`, MultiMesh — near-zero cost), and deer that **wander** between cells instead of standing like statues.
- The village **builds**: anyone who knows Brush hut (E2.20 — Bren starts with it, teaching spreads it) gathers branches and raises a hut whenever shelter runs short (~1 per 6 villagers). Huts are warm at night like the fire.
- The village anchor is placed in the **largest walk component** of the map and all gatherables spawn inside it — nobody starves next to an unreachable berry bush.

## What happens (P6)

- **Time passes for real**: villagers age each dawn (child-sized until adulthood), seasons turn — in winter the bushes and fiber plants stop regrowing — and past their lifespan people die of old age where they stand.
- **Children are born** (dawn rolls, population-capped): Cortex casts them with traits inherited from both parents plus noise, kin bonds on both sides, and almost no knowledge — the band must teach them everything before the old knowers die.
- The dawn report tracks it all: `Dawn of day 25 (spring, Middle Paleolithic): 25/35 alive, 207 techs learned, 5 births, 10 deaths`. In the verification marathon the settlement reached the **Upper Paleolithic** after most founders were dead — the climb survived its first generational turnover.
- Marathon mode: `VOX_DAY_SECONDS=15 VOX_FIRE_DECAY=6` (+ `VOX_DISCOVERY_RATE=0.7` on Cortex) compresses a generation into ~5 minutes. `VOX_START_CACHE=1` pre-places a stocked cache pit by the fire (test hook for the storage economy); `VOX_START_CORRAL=1` pre-places a corral with a goat pair (herding); `VOX_START_SMELTER=1` pre-places a smelter (metallurgy).

## What happens (P5)

- Idle or fireside NPCs sometimes have an **insight** (openness-modulated): a burst of experimenting animation, then `*** Odan DISCOVERED Prepared-core knapping (Levallois) ***` in the log. What they invent depends on what they already know — the master knapper pushes stone-craft, the fire-keeper pushes fire techs.
- Discoveries + teaching move the whole settlement: the HUD's top line shows the current era, and era transitions print a banner. E2 unlocks cordage, hide wraps (warm at night without the fire), stone-tipped spears, and dried meat.
- The HUD also shows the focused NPC's **mind binding** (which LLM drives them); rebind at runtime via Cortex's `POST /bind/<npc>`.

## What happens (P4)

- **Day/night**: the sun wheels overhead (day length from `era1_content.json`, override with env `VOX_DAY_SECONDS`); nights are dark and cold — NPCs head to the fire to rest, and away from it they recover nothing.
- **The campfire** is the settlement anchor: cooking station, warmth, light. Its fuel burns down (`VOX_FIRE_DECAY` to accelerate) and someone who knows fire-keeping must feed it branches.
- **Food economy**: berries and tubers, plus hunting small game (needs a club or spear) and roasting meat/tubers at the fire for much better nutrition. Starvation drains health; at zero the villager dies where they stand, the band remembers, and any technology only they knew is **lost forever**.
- **Mutual aid**: villagers with spare food share with starving neighbors — both remember it.
- Every dawn the console prints a survival report; after day 10 you get the P4 verdict (`VILLAGE SURVIVED 10 DAYS UNATTENDED`).

## What happens (P3)

- Ten villagers spawn near the center with distinct personas and uneven knowledge (Toran knows the spear, Odan the fine knapping, Bren the fire lore...).
- Idle NPCs ask Cortex what to do; nearby NPCs count as **talk** targets. Two who decide to talk walk together, freeze face-to-face, and exchange a few lines.
- If one knows a technology the other doesn't, a willing teacher **demonstrates it** — watch for `*** X learned ... from Y ***` in the log and the counter in the HUD. The knowledge is permanent (it's in the learner's memory DB).
- NPCs also *see* each other work ("saw Odan knapping a handaxe") — observations feed memories and relationships.
- **Tiering**: NPCs near the camera (or in chat) get full LLM decides; distant ones run on Cortex's scripted tier with zero LLM calls. The HUD shows the focused NPC's tier.

## Files

| File | Role |
|---|---|
| `scripts/main.gd` | Orchestrator: launch menu flow, roster spawn, day/night, message routing, perception, gifting, death, tiering, HUD |
| `scripts/menu_ui.gd` | Launch menu: New Game (map size + terrain), Options (key rebinding), Exit |
| `scripts/input_config.gd` | InputMap actions, physical-key defaults, persistence (user://keybinds.cfg) |
| `scripts/asset_lib.gd` | Drop-in GLB model loading: auto-scale, animation detection, box-art fallback (see `assets/README.md`) |
| `scripts/campfire.gd` | The hearth: fuel, decay, light, warmth/work radii |
| `scripts/npc_controller.gd` | Per-NPC brain-body loop: decide timer, goal executor (gather/craft/eat/talk), say queue |
| `scripts/npc.gd` | Voxel person: locomotion, needs, inventory, work timer + animation |
| `scripts/voxel_world.gd` | Terrain gen, block storage, A* walk graph |
| `scripts/chunk_mesher.gd` | Face-culled chunk meshes + collision |
| `scripts/tech_data.gd` | Loads tech_tree.json + era1_content.json; recipe status/apply |
| `scripts/resource_field.gd` | Scatters gatherable props; nearest/distance queries; respawn |
| `scripts/cortex_client.gd` | WebSocket client, auto-reconnect |
| `scripts/chat_ui.gd` | Chat panel (status, log, per-NPC input) |
| `scripts/orbit_camera.gd` | Camera rig |

## Headless check

```
Godot_v4.3-stable_win64_console.exe --headless --path . --quit
```
prints `PATHFINDING OK`, `CRAFT ENGINE OK`, `RESOURCE FIELD OK`. Run without `--quit` (Cortex up) to watch the village live in the console.

## Known limits

Single walkable layer; world generated at startup; one shared campfire (no building yet); conversations are pairwise; E3+ techs are discoverable but have no gameplay recipes yet; parentage ignores sex/kinship constraints. P7+: content waves E3→E8, scripted discovery events, multi-settlement + trade, in-game binding UI.
