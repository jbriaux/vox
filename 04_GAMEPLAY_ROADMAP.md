# VOX Gameplay Roadmap — from the Tech Tree to Playable Systems

Maps `01_TECH_TREE.md` (440 nodes, E1–E10) onto engine work. First arc
(waves A–H) below; second arc (waves I–M, covering the A–G leftovers and the
new E9/E10 eras) at the end of this file. Everything is
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

## Wave H — Conflict & defense  *(decided: property raids, MIND-driven only)* ✅ DONE (core)
**Tree**: bronze/iron weapons, armor, shields, walls, warfare skills.
The tree supports raids and war; whether VOX wants NPC-vs-NPC violence is a
design choice, not an engineering one. Minimum viable version: weapons/armor
affect only predator defense; palisades keep wolves out. Full version needs
morale, injury, and inter-village hostility systems. **Decide before building.**
**Decision (2026-07-13)**: rung 3 of 4 — property conflict, no deaths, and hostility may ONLY originate in a mind. **Shipped**: NPCs and structures carry village (fire) ownership; a stocked store of *another* village within sight adds a RAID section to the decide prompt — the survival instinct and every fallback are hard-banned from proposing it, only the LLM may choose `{"action":"raid"}`. Raiders steal ≤3 of one item; a defending villager scuffles (injuries floored at health 8 — nobody dies in a raid); village dogs drive raiders off half the time; every victim nearby remembers (`raided us` relationship note, −25 affinity/−30 trust, anger mood) — grudges, revenge raids and gift-bought peace are all left to the minds. Mock brains never raid unless the test harness sets `VOX_MOCK_RAID=1`. Walls (Wave K) will be the counter.

---

# Second arc — waves I–M (planned 2026-07-12, tree now E1–E10 / 440 nodes)

Waves A–G shipped their core loops. What follows plans the rest: the A–G
leftovers, plus executable gameplay for the new Classical (E9) and Medieval
(E10) eras. Two **new engine patterns** carry almost everything, both cheap
extensions of the existing structure system:

- **Dawn processors** — structures that transform stored goods at dawn
  (mill: grain→flour; press: grain→beer; smokehouse: meat→smoked). The dawn
  pipeline already iterates structures for spoilage/herds/crops; processors
  are one more pass.
- **Auras** — structures that passively affect villagers inside a radius
  (bathhouse heals, theater lifts mood, university multiplies teaching,
  clock tower speeds work). One `aura` dict on the structure entry + one
  check where needs/mood/teaching already tick.

## Wave I — Loose ends of the first arc  *(S–M effort, do first)* ✅ DONE
**Tree**: E3.27/E4.24 smoking, E5.33 salt, E5.31 beer, E5.20/21/25 cattle-pigs-oxen, E5.35–37 kiln, E5.44 dyes, E7.31 school.
- **Smoking rack** (dawn processor): raw meat/fish → smoked (20-day shelf life) — finishes the preservation ladder started in Wave A.
- **Salt** gathering on shore cells + salted meat recipe.
- **Beer** (E5.31): grain + pot at fire → beer; small mood lift when drunk — first "fun" consumable, pairs with feasts/councils.
- **Cattle & pigs** join the corral (data-only: two more capture/pen/slaughter rows); **draft oxen** (E5.25) speed plow-field work once Wave L's plow exists.
- **Kiln** (E5.37): second station structure; fires pots without the campfire and unlocks **dyes** (E5.44) → dyed garments (pure trade goods).
- **School** (E7.31 structure): a built school makes the existing ×4 diffusion *conditional on the building standing* — knowledge infrastructure you can point at (and lose).
**Shipped**: smoking rack = first **dawn processor** (raw meat/fish deposited in it cure overnight, 20-day shelf life); salt flats on shore sand → salted meat (30 days); beer (grain + pot at the fire) → "feels merry" mood lift; cattle (milk ×2, meat ×5) and pigs join the corral, `train_ox` converts a cow to a counted draft ox for Wave L; kiln = second station (batch-fires 2 pots, boils berry dye → dyed garments); school hall gates the ×4+ diffusion tiers on the *building standing* (Godot sends a `village` structure census; teach cap clamps to storytelling pace without it). Infrastructure instinct generalized: whoever knows a missing building's tech builds it (smelter/rack/kiln/school).

## Wave J — Power  *(M effort — the industrial hinge)* ✅ DONE
**Tree**: E8.18–20 querns/mills, E9.05 mechanics, E9.11–12 gearing & trip hammers, E9.40 screw press, E10.08 windmill, E10.10 cams.
- **Watermill** (must stand on a shore/river cell — first placement-constrained structure) and **windmill** (anywhere): dawn processors that mill *all* stored grain to flour, replacing hand-grinding.
- **Trip hammer** upgrade to the smelter: halves smithing seconds (aura on the station).
- **Screw press**: grain→beer and (with Wave I) berries→preserves at scale.
**Payoff**: the village's first non-muscle power; stored surplus starts working while everyone sleeps.
**Shipped**: watermill (E8.20) is the first placement-constrained structure — it must stand within 2 cells of water (`is_water` = surface below sea level; the builder's ring search skips dry spots); windmill (E10.08, cloth sails) builds anywhere. Both are grain→flour dawn processors with 40-slot stores. Screw press (E9.40): station with batch beer (grain 6→beer 4, no pot) and berry preserves. Trip hammer (E9.12): first work-speed structure — `speeds_station: smelter, factor 2.0` halves all smithing/smelting seconds via `station_speed_factor`. Rotary querns/animal mills superseded (knowledge-only).

## Wave K — Civic stone (Classical)  *(M–L effort)*
**Tree**: E9.13 concrete, E9.14 vault, E9.16 baths, E9.19 aqueduct, E9.27 walls, E9.32 theater, E9.42 ice house, E8.31 market.
- **Concrete chain**: limestone (new stone-cell resource) → lime (kiln) → concrete (+ existing clay/sand).
- **Civic buildings with auras**: bathhouse (health regen), theater (mood lift for audiences), forum/market (trade range: villagers can barter with the *store* at posted swaps, not just face-to-face).
- **Ice house**: a store whose contents never spoil — preservation endgame.
- **Stone walls** (E9.27): predators cannot enter the walled ring — the wolf problem becomes *solved infrastructure* (and the natural pre-work for Wave H if it ever happens).
- **Aqueduct + fountain**: raises the village population cap (the current `_pop_cap` becomes infrastructure-driven).

## Wave L — Medieval revolutions  *(L effort — the biggest payoff)*
**Tree**: E10.01/05 heavy plow & three-field, E10.08 windmill (J), E10.11–13 spinning/looms, E10.24 blast furnace, E10.36 university, E10.41 hospital, E10.18 clock, E10.17/44 printing.
- **Heavy plow**: field plots yield ×2 and support a second sowing per season; **three-field** adds a fallow bonus (fields remember their rotation).
- **Spinning wheel & treadle loom**: wool→yarn→cloth at 5× speed (data multiplier on existing recipes).
- **Blast furnace**: station upgrade; cast-iron toolkit at quality 3.0 — the final work-speed tier.
- **University**: aura structure that raises the teaching cap AND hosts *scheduled sessions* — a council-like event where one master teaches several students at once (reuses the council assembly machinery).
- **Hospital**: aura heals the injured/sick faster; **clock tower**: village-wide small work-speed bonus (shared time discipline).
- **Print shop** (E10.17/44): dawn processor that turns paper + a knower's tech into **books** — physical items that carry a technology. Reading a book teaches its tech; books survive their authors: *portable, tradeable, lootable archives*. This is the knowledge-death mitigation made tangible (and the single most emergent-friendly item in the plan).

## Wave M — Coin & commerce  *(S–M effort, anytime after E)* ✅ DONE (market stall waits for K)
**Tree**: E8.30 coinage, E8.31 markets, E8.32 credit, E9.46 mints, E10.39 bookkeeping.
- **Coins**: minted at the smithy from copper/silver ingots; a universal trade good.
- **Barter upgrade**: when no complementary surplus exists, `_propose_trade` falls back to *purchase* — goods for coins at simple valuations. Wealth becomes visible (and hoardable, and inheritable).
- **Market stall** (with Wave K's forum): posted offers let villagers trade with the commons asynchronously.
**Shipped**: `mint_coins` at the smelter (copper ingot + hammerstone → 8 stamped coins, E8.30); `world.item_value` prices everything (food by nourishment, tools by quality); `_propose_trade` falls back to **purchase** when no complementary surplus exists — the richer side buys a unit of the other's surplus, trades now carry counts (`give_n`/`take_n`); coins never count as barter surplus. **Inheritance**: a dead villager's entire pouch passes to the nearest living neighbor (`took up what X left behind`) — coins, iron axes and all; wealth outlives its earner. Market stall deferred to Wave K's forum.

## Order & dependencies

```
I (loose ends) ──────────────┐
J (power) ── K (civic stone) ─┼─ L (medieval revolutions)
E (done) ── M (coin) ─────────┘
H (conflict) — still gated on a design decision; K's walls are its natural prelude
```

Recommended order: **I → J → M → K → L** (each wave playable alone; L's
university/printing land best after K's civic pattern exists). Together they
make roughly another ~120 nodes executable; the remainder (ritual, art,
seasonal lore, law, navigation) stays knowledge-only — still discovered,
taught, era-counted, and mourned when lost.

Each wave follows the established pattern: extend `era1_content.json`
(resources/items/recipes/stations/buildables), small engine verbs in Godot,
suggestion-rule + catalog updates in Cortex, model slots auto-reported by
`tools/list_assets.py`, tests + a headless e2e proving the loop.
