# VOX World Elements Catalog

Reverse index of `01_TECH_TREE.md`: everything that must exist in the voxel world, grouped by category. Each entry notes the era it first matters (Ex) so world-gen and content waves can be staged. This becomes `data/elements.json`.

---

## 1. Terrain & natural blocks (world-gen)

| Block | Era | Role |
|---|---|---|
| Soil, sand, gravel, clay deposit | E1/E5 | clay is gated content: visible always, useful at E5.34 |
| Stone (generic), flint nodule, quartzite, obsidian, chert | E1 | knappable stones (E1.03 makes them distinguishable) |
| Limestone | E5 | lime plaster (E5.50), masonry |
| Copper ore (malachite — green-stained stone), native copper nugget | E6 | surface + vein spawns |
| Cassiterite (tin ore) | E7 | **rare, regional** — drives trade (E7.01) |
| Gold placer (river gravel), galena (lead/silver) | E6 | prestige metals |
| Iron ores: bog iron (marsh), hematite (hills) | E8 | **common** — iron democratizes metal |
| Salt pan / brine spring / rock salt | E5/E6 | preservation & trade |
| Ochre deposit | E2 | pigment |
| Peat, reeds, riverbank mud | E3/E5 | fuel, boats, mudbrick |
| Water (river, lake, sea, tide pools), ice/snow (seasonal) | E1 | fishing tiers, seasonal travel |
| Wildfire (event), lightning strike (event) | E1 | fire capture trigger (E1.18) |

## 2. Flora

| Element | Era | Role |
|---|---|---|
| Berry bush, nut tree, wild tubers, gourds | E1 | forage staples |
| Herbs (medicinal, dye, poison varieties) | E2+ | healing (E2.25), dyes (E5.44), fish poison (E4.26) |
| Trees: oak (hard), pine (resin), birch (tar/bark), yew/elm (bows), willow (withies), fig/olive/grape (E5/E6) | E1–E6 | species matter: bows need yew/elm, tar needs birch |
| Wild cereals (wheat/barley stands), wild pulses, flax | E4 | domestication chain E5.01–E5.07 |
| Reeds, grasses, straw | E3 | mats, thatch, boats |
| Dye plants (woad, madder), murex shells (coastal) | E5/E7 | textile economy |

## 3. Fauna

| Element | Era | Role |
|---|---|---|
| Small game (hare, birds), fish, shellfish, eels | E1 | early protein; birds → feathers (fletching) |
| Big game (deer, aurochs, boar, ibex), predators (wolf, bear, lion) | E1 | hunting tiers, danger |
| Wolf → dog (E4.07); wild goat/sheep → flock (E5.17); aurochs → cattle (E5.20); boar → pig (E5.21) | E4–E5 | each domestication = capture event + generations |
| Wild ass → donkey (E6.21); steppe horse → horse (E6.22) | E6 | transport revolution |
| Bees (wild hives → apiary E7.47) | E4 | honey, wax (lost-wax casting!) |
| Vermin (rats) | E5 | granary raiding — makes E5.11 matter |

## 4. Items (crafted) — by family

- **Knapped stone**: hammerstone, flake, chopper, handaxe, cleaver, Levallois point, scraper (side/end), awl, burin, blade, knife, microlith, sickle blade, arrowhead, drill bit.
- **Ground stone**: polished axe/adze, mace head, quern (saddle→rotary), mortar & pestle, grinding slab.
- **Wood**: digging stick, club, spear (wooden→fire-hardened→stone-tipped), shaft, haft, atlatl, dart, bow, arrow, throwing stick, paddle, travois, sledge, wheel (solid→spoked), ard, yoke, loom, planks, furniture, lock & key.
- **Bone/antler/ivory**: point, awl, needle, gorge hook, harpoon, mattock, baton, figurine, flute, tally bone, wool comb.
- **Fiber/hide**: cord, rope, thread, net, basket, mat, sling, hide wrap, fitted clothing, boots, tent, leather, rawhide, coracle, sail, cloth (linen/wool), dyed cloth, garments.
- **Fire & light**: fire kit, torch, fat lamp, charcoal, bellows.
- **Ceramic/glass**: pot, decorated ware, glazed ware, crucible, mold, tokens, tablets, faience, glass beads, blown glass, amphora.
- **Copper**: beads, awl, flat axe, chisel, knife, dagger, saw, wire.
- **Bronze**: ingot, socketed axe, saw, sickle, knife, spearhead, sword, helmet, cuirass, greaves, shield boss, vessels, bit, scalpels, razor.
- **Iron/steel**: bloom, billet, nails, hinges, toolkit (axe/saw/hammer/chisel/tongs), plowshare, scythe, spade, sword, mail, scale armor, shears, lock parts, surgical tools, pattern-welded blade.
- **Precious/exchange**: ochre, beads/pendants, gold/silver jewelry, stamp/cylinder seals, weights, balance scale, coins, maps, game sets, lyre/harp/drum, perfume, soap, kohl.
- **Food items** (spoilage-tiered): raw/cooked meat, dried/smoked meat, pemmican, fish, shellfish, marrow, berries, nuts, tubers, eggs, honey, grain, flour, flatbread, porridge, cheese, curds, milk, beer, wine, oil, salt, pickles, vegetables, olives, grapes, figs.

## 5. Structures & stations (multi-block, buildable)

| Structure | Era | Function (station verbs) |
|---|---|---|
| Windbreak, brush hut, hide tent, wattle hut | E1–E4 | sleep, shelter (weather sim) |
| Hearth (stone ring), tended fire | E1–E2 | cook, warm, gather (social anchor) |
| Hide frame, smoke rack, smokehouse | E2–E4 | process hides, preserve |
| Cache pit, lined storage pit, granary, cool store | E3–E7 | storage tiers (capacity, spoilage, vermin) |
| Grave, cemetery, shrine, temple, megalith circle | E2–E7 | ritual verbs, memory anchors, festivals |
| Fish weir, fields (tilled/crop/fallow), ditch, canal, terrace, orchard, apiary, corral, well | E4–E7 | food production chain |
| Firing pit, updraft kiln, closed kiln, bread oven | E5–E6 | ceramics & baking |
| Loom (warp-weighted→ground), spindle station | E5–E6 | textiles |
| Charcoal clamp, smelting furnace, bloomery, smithy (hearth+anvil+trough) | E6–E8 | metallurgy chain |
| Mine (pit→shaft with timbering, lamps) | E6–E7 | ore extraction |
| Potter's wheel (tournette→fast), lathe, beam press, animal mill, water mill | E6–E8 | mechanized crafts |
| Houses: mudbrick, wattle-daub, timber-frame; palisade, town wall, gate, tower | E5–E8 | settlement growth & defense |
| Village → town → city (streets, districts), palace, school, library, marketplace, caravanserai, harbor, sewer, aqueduct, paved road, stone bridge | E5–E8 | civic layer |

## 6. Vehicles & mounts

travois (E3) → sledge (E4) → dugout/raft/coracle (E4) → reed boat (E5) → ox-cart (E6) → sewn-plank boat (E6) → chariot (E7) → sailing ship (E7) → cavalry horse (E8).

## 7. Events & world mechanics tied to tech

- **Lightning/wildfire** → fire capture opportunity (E1.18).
- **Copper nugget in a hot hearth** → smelting insight trigger (E6.07).
- **Wolf pack near camp in winter** → dog domestication arc (E4.07).
- **Seasons**: drive clothing (E3.12), caching (E3.29), migration (E2.29), sowing/harvest windows (E5.04).
- **Spoilage & vermin**: make every preservation/storage tech matter.
- **Disease/injury**: gated by medicine chain (E2.25 → E5.66 → E7.51 → E8.35).
- **Death of last knower** → tech loss (mitigated by writing/library).
- **Trade caravans/ships** (NPC-run) → exotic goods + tech diffusion between settlements.
