# VOX — drop-in 3D models

## Currently installed (all CC0)

- **Villagers**: Kenney *Blocky Characters* — `npc/default.glb` + one distinct
  character per named villager (anon..juk). Animated: the game drives their
  `idle`, `walk`, and `pick-up` clips.
- **Campfire, cobble, flint**: Kenney *Survival Kit* (campfire-pit, rock-a,
  resource-stone).
- **Berry bush, branch, fiber plants**: Kenney *Nature Kit* (plant_bushDetailed,
  log, grass).
- **Small game**: Quaternius *Deer* (official TestGltfAssets repo).
- **Wolf & boar**: Quaternius *Wolf* and *Pig* via Poly Pizza (CC0).
- **Fishing shallows**: Kenney Nature Kit *lily_large*.
- **Hare**: "Cottontail rabbit" by **Poly by Google** via Poly Pizza —
  **CC-BY 3.0: this one requires attribution if you distribute the game.**

### Waves B–E models (all via Poly Pizza)

CC0 / Public Domain (no attribution needed):
- **Copper vein**: "Gold ore" by Quaternius
- **Bog iron**: "Rock Moss" by Quaternius
- **Granary**: "Silo" by Quaternius
- **Field plot**: "Crops" by Quaternius

**CC-BY 3.0 — attribution REQUIRED if the game is distributed:**
- **Wild goat**: "Goat" by Poly by Google
- **Wild sheep**: "Sheep" by Poly by Google
- **Wild cereal**: "Field of wheat" by Poly by Google
- **Tin gravel**: "Stones" by Poly by Google
- **Storage cache**: "Picnic Basket" by Poly by Google
- **Mudbrick house**: "Farm house" by Poly by Google
- **Clay bank**: "Soil mount" by apelab
- **Smelter**: "Forge" by Don Carson

The **corral** has no model on purpose — the procedural post-and-rail ring
(`_box_corral` in main.gd) is the right shape; a single fence-piece model isn't.

CC0 requires no attribution — but if you ship this, a thank-you to
kenney.nl and quaternius.com is good form (and every CC-BY credit above is mandatory).

Put `.glb` / `.gltf` (or `.tscn`) files in the folders below and the game uses
them automatically — anything missing keeps the built-in box art. Models are
auto-scaled to gameplay size and their feet dropped to the ground, so scale
doesn't matter. After adding files, let the Godot editor finish importing once
(or run headless with `--import`).

Run `python tools/list_assets.py` (from the repo root) any time to see which
slots are filled and which are missing.

## Naming map

| Path | Replaces | Notes |
|---|---|---|
| `assets/npc/default.glb` | every villager's body | animated: clips named *walk/run*, *idle*, and optionally *interact/attack/gather* are detected and played automatically |
| `assets/npc/<id>.glb` | one specific villager (e.g. `npc/bren.glb`) | overrides `default` for that NPC id |
| `assets/campfire.glb` | the hearth's stone ring | the flame + light overlay stays (it shows fuel level) |
| `assets/props/loose_cobble.glb` | loose cobble prop | |
| `assets/props/flint_nodule.glb` | flint nodule prop | |
| `assets/props/branch.glb` | fallen branch prop | |
| `assets/props/berry_bush.glb` | berry bush prop | |
| `assets/props/small_game.glb` | small game (the huntable critter) | |
| `assets/props/fiber_plant.glb` | fiber plants prop | |

Prop target height defaults to 0.8 m; override per resource with
`"model_height": 1.2` in `data/era1_content.json`.

**Textures gotcha**: if a model renders WHITE, its .glb references an external
texture (Kenney packs do: `Textures/colormap.png`, `Textures/texture-X.png`).
Copy the pack's `Textures/` folder next to the .glb — into EVERY folder that
holds Kenney models (`npc/`, `props/`, `structures/`, the assets root) — then
force a reimport (delete the model's `.glb.import` file, or `godot/.godot`).
Fully self-contained GLBs (most AI-generated ones) don't need this.

**Facing gotcha**: moving creatures (animals, predators) are turned with
`look_at` + a 180° flip because glTF models face +Z while Godot aims -Z. If a
new creature model walks backwards, it was authored facing -Z — remove the
flip for that one or re-export it rotated.

## Good free (CC0) sources — no attribution required

- **Kenney** — https://kenney.nl/assets — *Survival Kit* (campfires, tents, tools, rocks), *Nature Kit* (trees, bushes, stones), *Animated Characters*. CC0, GLB included.
- **Quaternius** — https://quaternius.com — *Ultimate Nature Pack*, *Animated Animals* (rabbits! deer!), *Modular Characters*. CC0, GLB.
- **KayKit (Kay Lousberg)** — https://kaylousberg.itch.io — animated character packs, dungeon/nature props. CC0.
- **Poly Pizza** — https://poly.pizza — searchable aggregator of CC0/CC-BY low-poly models (check the license shown per model; prefer CC0).

Low-poly packs fit the blocky terrain best. Rename the file to the slot name
(e.g. Quaternius `Rabbit.glb` → `props/small_game.glb`) and you're done.

## Generating your own (A6000)

Both flagship open image-to-3D models output GLB directly and run locally:

- **Hunyuan3D 2.1** (Tencent) — best textures; https://github.com/Tencent/Hunyuan3D-2
- **TRELLIS / TRELLIS.2** (Microsoft) — best geometry; https://github.com/microsoft/TRELLIS

Workflow: prompt an image model (or draw/photograph) → "low poly stone age
hut, game asset, plain background" style images work best → feed to
Hunyuan3D/TRELLIS → export GLB → drop into the folder. 48 GB VRAM is more
than enough for either (they run on 16-24 GB), so you can keep a vLLM
instance loaded alongside.
