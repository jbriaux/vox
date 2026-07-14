# VOX Gameplay Roadmap — from the Tech Tree to Playable Systems

Maps `01_TECH_TREE.md` (440 nodes, E1–E10) onto engine work. Everything is
*discoverable/teachable knowledge* today; this plan is about which nodes get
**gameplay** and what new engine verbs each wave needs. Status: E1 fully
playable, E2 mostly, E3–E4 partially (blades, sewing, bow, fishing, traps
missing). E5+ is knowledge-only.

Existing engine verbs (reused everywhere): gather (tool/tech-gated, danger,
wandering animals) · craft (stations, effects) · buildable structures
(warmth) · seasons/day-night · needs/health/death · predators + flee ·
converse/teach · discovery/eras · save/load · two-village emergent flavor.

---

## Wave A — Storage & the food economy  *(foundation, do first)* ✅ DONE
**Tree**: E3.27 smoking, E3.29 food caching, E5.11 granary, E5.32 pickling, E5.33 salt.
**New verbs**:
- **Container structures** with shared inventories (cache pit → granary): deposit / withdraw actions, listed in the decide catalog ("the granary holds: 12 grain").
- **Spoilage**: fresh food rots in days; dried/smoked/pemmican/pickled last seasons. Makes every preservation tech real.
- **Vermin**: rats raid open caches; granaries are immune (why E5.11 matters).
**Payoff**: stockpiling for winter becomes a real activity; villages develop a commons.
**Shipped**: cache pit (E3.29) + granary (E5.11) buildables with shared stores, deposit/withdraw actions + STORE decide-catalog section, per-dawn spoilage on inventories and stores (`spoils_days` per item), 30%/dawn vermin raids on non-safe caches (25% food loss). Smoking/pickling/salt recipes remain open for a later pass.

## Wave B — Agriculture  *(the Neolithic revolution, E4.19 → E5.16)* ✅ DONE (core loop)
**Tree**: wild grain harvesting, seed saving, land clearing, hoe/tilling, sowing
& tending, cereal/pulse/flax domestication, sickle, threshing, winnowing,
rotation, manuring, gardens, orchards, irrigation. E5.05 is an era bottleneck.
**New verbs**:
- **Wild cereal stands** (seasonal resource) → grain + seed items.
- **Field plots**: buildable tilled ground (generalizes hut-building).
- **Crop growth stages over in-game days**, season-gated: sow spring, tend, harvest autumn, dead in winter (winter respawn-halt already exists).
- **Practice-based discovery**: E5.05 domestication unlocks by *doing* (N harvest cycles) — first "needs"-column enforcement, not an idle roll.
- Food chain: grain → quern → flour → flatbread/porridge (fire station), beer (E5.31, morale/fun).
**Payoff**: the single most civilization-shaped loop; for emergent villages, "plant and wait" is the landmark discovery.
**Shipped**: wild cereal stands (E4.19-gated, seasonal) yielding wild grain + seed grain; hoe (E5.03) and sickle (E5.08, +50% harvest); till_plot → field_plot buildable, sow_field (consumes seed, refuses frozen ground), growth 3 dawns (frost kills standing crops in winter), harvest_field (grain + seed back); grain → flour (E4.20, hammerstone) → flatbread (E5.29, fire); **practice-based E5.05** — three harvests master Cereal domestication, the first "learn by doing" tech. Pulses/flax/rotation/manuring/irrigation/orchards stay knowledge-only.

## Wave C — Pastoralism  *(E4.07, E5.17–26)* ✅ DONE (core loop)
**Tree**: dog domestication, goat/sheep/cattle/pig capture, corrals, herding, milking, cheese, wool, draft oxen.
**New verbs**:
- **Taming**: capture-instead-of-kill on animals (needs corral built) → herd entities that live in the corral, grow over days.
- Herd verbs: milk, shear (wool → Wave D weaving), slaughter (meat + hide without hunting risk).
- **Dogs**: companion entity — improves hunting, warns of wolves (counters the predator system).
**Shipped**: wild goats/sheep (E5.17-gated capture → trussed animal item), corral buildable (E5.18, 8 animals, ring-of-posts fallback art), pen/milk (E5.22)/pluck wool (E5.24)/slaughter verbs (herd-gated in the catalog, worked at the corral), herds breed each dawn (pair + space → 25% young), milk→cheese (E5.23), tame_dog (E4.07) — village dogs widen the wolf-safe radius around fires and drive stalkers off. Cattle/pigs/draft oxen remain knowledge-only.

## Wave D — Crafts & real houses  *(E5.27–49)* ✅ DONE (core loop)
**Tree**: pottery (clay → coil pots → firing pit → kiln → glazes later), spinning/loom/woven garments/dyes, wattle-and-daub and mudbrick houses, polished stone tools.
**New verbs**:
- **Clay deposits** (terrain block near water) + **kiln as a second station type** (generalize the campfire-station code).
- Pots = carry-capacity boost + required for beer/pickling (Wave A/B synergy).
- **Loom structure** → woven clothing (warmth tier above hide wrap).
- **House upgrades**: hut → wattle-daub → mudbrick (bigger warmth radius, sleep capacity — village visibly modernizes each era).
**Shipped**: clay banks (E5.34-gated, on sand near water) → coil pots fired at the campfire; pot-gated cooking: porridge (E5.30) and pickled berries (E5.32, 40-day larder food — Wave A synergy); wool → yarn (E5.42) → cloth → woven garment (E5.43, warmth item); clay+straw mudbricks (E5.48) → mudbrick house (E5.49, warmth 5.0 vs hut 3.5 — shelter rule prefers it once known). Kilns/glazes/dyes/polished tools remain knowledge-only.

## Wave E — Metallurgy  *(E6 copper → E7 bronze → E8 iron)* ✅ DONE (core loop)
**Tree**: ore recognition, charcoal, crucible, smelting, casting, mining, bellows, alloying, forging, steel. E6.07 / E7.02 / E8.02 are era bottlenecks.
**New verbs**:
- **Ore veins in terrain**: copper (hills), gold (river gravel), bog iron (marsh — common), tin (RARE, one corner of the map: drives Wave F trade). Mining = gather on vein blocks with tool tiers.
- **Charcoal clamp, smelter, bloomery, smithy** — station chain built on the kiln generalization.
- **The scripted insight the tree calls for**: a copper nugget dropped in a hot hearth triggers the E6.07 discovery (first "opportunity event").
- Metal toolkits: better gather/craft speeds (introduce tool-quality multipliers).
**Payoff**: the Iron-Age-emergently marathon finally has real things to smelt.
**Shipped**: copper veins (E6.04, on stone), rare tin gravel (E7.01, count 2 — the trade driver), bog iron (E8.01, on sand); charcoal at the fire (E6.05); **generalized stations** — the smelter (E6.06, mudbrick+clay) is the first non-campfire workshop, recipes declare `station: smelter` and NPCs walk to it; smelt copper (E6.07) → cast copper axe (E6.09, quality 1.5×), tin-bronze (E7.02) → bronze axe (E7.05, 2.0×), iron bloom (E8.02) → forged iron axe (E8.05, 2.5×); **tool quality** speeds all gathering and crafting; **the opportunity event** — carrying copper ore beside a lit fire has a 20%/decide chance of revealing E6.07 ("a nugget left in the hearth ran shining"). Mining/bellows/steel remain knowledge-only.

## Wave F — Wheels, trade & the two villages  *(E6.16–18, E7.01, vehicles)* ✅ DONE (barter core)
**Tree**: wheel, yoke, ox-cart, travois/sledge (E3/E4), tin trade, chariot.
**New verbs**:
- **Inter-village contact** (emergent flavor's payoff): meeting strangers, stranger-wariness vs family bonds, cross-village teaching.
- **Trade**: converse extension — exchange items by mutual valuation; tin scarcity makes bronze *require* it.
- Carts raise carry capacity; worn paths appear between villages.
**Shipped**: **barter rides along with every conversation** — Godot sends both inventories with the converse; Cortex proposes a complementary-surplus swap (I hold ≥3 of something you lack, and vice versa) and a `trade` message moves the goods, with memories and a "we trade" relationship note on both sides. Tin's scarcity (2 veins per map) makes bronze depend on the wanderers who find it and the trades that spread it. Inter-village contact already emerges from wandering + converse. Carts/wheels/worn paths remain knowledge-only.

## Wave G — Knowledge & civic  *(cheap, high narrative value — can come early)* ✅ DONE (except schools structure)
**Tree**: E1.25/E3.41 storytelling → E7.31 schools → E8.29 literacy; E7.30/E8.34 loss mitigation; tokens → tablets → writing.
**New verbs** (mostly Cortex-side):
- **Diffusion tiers** ✅: teaching count per converse scales with the settlement's best diffusion tech — cap = 2 + speed (demonstration 1× → storytelling 2× → schools 4× → literacy 8×).
- **Loss mitigation** ✅: with archives/records known (E7.30/E8.34), a last-knower's death transfers their unique techs to their closest companion instead of destroying them.
- School structure (one teacher, several learners per session) — still open.

## Wave H — Conflict & defense  *(design decision required — deliberately last)*
**Tree**: bronze/iron weapons, armor, shields, walls, warfare skills.
The tree supports raids and war; whether VOX wants NPC-vs-NPC violence is a
design choice, not an engineering one. Minimum viable version: weapons/armor
affect only predator defense; palisades keep wolves out. Full version needs
morale, injury, and inter-village hostility systems. **Decide before building.**

---

## Order & dependencies

```
A (storage) ──> B (agriculture) ──> D (crafts/houses) ──> E (metallurgy) ──> F (trade)
                    └─> C (pastoralism, parallel with D)
G (knowledge) — anytime, recommend alongside B
H (conflict) — after F, if ever
```

Waves A–F make ~180 of the 285 unimplemented nodes *playable*; the rest stay
as flavor knowledge (ritual, art, seasonal lore) that still counts for eras.
Each wave follows the established pattern: extend `era1_content.json`
(resources/items/recipes/stations/buildables), small engine verbs in Godot,
suggestion-rule + catalog updates in Cortex, model slots auto-reported by
`tools/list_assets.py`, tests + a headless e2e proving the loop.
