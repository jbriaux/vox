# VOX Tech Tree — Stone Age to End of Iron Age

A DAG of ~340 technology nodes across 8 eras. Each node: **ID | Technology | Prereqs | Needs | Introduces**.

- **Prereqs** — node IDs that must be known (by at least one NPC in the settlement).
- **Needs** — materials, tools or stations that must physically exist to practice it.
- **Introduces** — items (i), blocks (b), structures (s), and actions/abilities (a) it adds to the world. Full reverse index in `02_WORLD_ELEMENTS.md`.
- Eras are labels, not gates: an isolated village can be "in" E5 for pottery and E3 for hunting.

Eras: **E1** Lower Paleolithic · **E2** Middle Paleolithic · **E3** Upper Paleolithic · **E4** Mesolithic · **E5** Neolithic · **E6** Chalcolithic (Copper) · **E7** Bronze Age · **E8** Iron Age

---

## E1 — Lower Paleolithic (foundation: ~25 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E1.01 | Stone percussion (hammerstone) | — | any hard cobble | i: hammerstone; a: strike-stone |
| E1.02 | Sharp flake use | E1.01 | flint/quartzite cobble | i: stone flake; a: cut |
| E1.03 | Tool-stone recognition | E1.02 | — | a: identify flint, quartzite, obsidian, chert deposits |
| E1.04 | Chopper (pebble tool) | E1.02 | cobble | i: chopper; a: chop, crush |
| E1.05 | Butchery | E1.02 | flake, carcass | i: raw meat, hide (crude), sinew, bone; a: butcher |
| E1.06 | Marrow extraction | E1.01, E1.05 | bone, hammerstone | i: marrow (food) |
| E1.07 | Foraging | — | — | i: berries, roots, nuts, eggs, insects; a: gather |
| E1.08 | Digging stick | E1.02 | branch | i: digging stick; a: dig tubers, dig soil |
| E1.09 | Wooden club | E1.02 | branch | i: club |
| E1.10 | Thrown stones | — | stone | a: ranged attack (crude) |
| E1.11 | Scavenging | E1.05 | — | a: locate/claim carcasses |
| E1.12 | Persistence hunting | E1.09, E1.11 | group of 2+ | a: run down game |
| E1.13 | Handaxe (biface) | E1.03, E1.04 | flint core, hammerstone | i: handaxe; a: heavy butchery, woodwork (crude) |
| E1.14 | Cleaver | E1.13 | flint core | i: cleaver |
| E1.15 | Soft-hammer knapping | E1.13 | bone/antler billet | i: refined biface; a: thinner edges |
| E1.16 | Bipolar knapping | E1.01 | anvil stone | a: split small pebbles/bone |
| E1.17 | Sharpened wooden spear | E1.13 | sapling, handaxe | i: wooden spear; a: thrust attack |
| E1.18 | Fire capture | — | wildfire/lightning event | b: campfire (wild ember); a: carry ember |
| E1.19 | Fire keeping | E1.18 | fuel (wood, dung) | s: tended fire; a: feed fire, bank embers |
| E1.20 | Cooking meat | E1.19, E1.05 | fire, raw meat | i: cooked meat (better nutrition, no disease) |
| E1.21 | Cooking plants | E1.19, E1.07 | fire, tubers | i: roasted tubers/nuts |
| E1.22 | Windbreak shelter | E1.13 | branches, brush | s: windbreak |
| E1.23 | Water carrying (gourd/shell) | E1.07 | gourd, large shell | i: water gourd; a: carry water |
| E1.24 | Crude hide stripping | E1.05 | flake, carcass | i: raw hide |
| E1.25 | Knowledge sharing (demonstration) | — | 2+ NPCs | a: teach by showing (tech diffusion, slow) |

## E2 — Middle Paleolithic (~30 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E2.01 | Prepared-core knapping (Levallois) | E1.15 | flint core | i: Levallois flake/point (standardized blanks) |
| E2.02 | Retouching | E2.01 | flake, soft hammer | a: resharpen tools (durability repair) |
| E2.03 | Side scraper | E2.02 | flake | i: scraper |
| E2.04 | Stone point | E2.01 | Levallois flake | i: stone point |
| E2.05 | Awl / borer | E2.02 | flake | i: stone awl; a: pierce |
| E2.06 | Denticulate / notched tools | E2.02 | flake | i: notched scraper; a: shave shafts |
| E2.07 | Simple cordage (twisted fiber) | E1.07 | bark fiber, sinew | i: cord; a: bind |
| E2.08 | Knots & lashing | E2.07 | cord | a: lash, tie |
| E2.09 | Birch-tar adhesive | E1.19 | birch bark, fire | i: birch tar (glue) |
| E2.10 | Hafting | E2.04, E2.08, E2.09 | point, shaft, cord/tar | a: composite tools |
| E2.11 | Stone-tipped spear | E2.10, E1.17 | spear shaft, stone point | i: composite spear |
| E2.12 | Ambush hunting | E2.11 | terrain knowledge | a: coordinated ambush of big game |
| E2.13 | Fire by friction (hand drill) | E1.19 | dry softwood, tinder | a: make fire anywhere |
| E2.14 | Fire by percussion | E1.03, E1.19 | flint, pyrite, tinder | i: fire kit |
| E2.15 | Constructed hearth | E1.19 | stones | s: stone-ring hearth (efficient, safe) |
| E2.16 | Fire-hardening wood | E2.13 | fire, spear | i: fire-hardened spear (upgrade) |
| E2.17 | Hide scraping | E2.03, E1.24 | scraper, raw hide | i: cleaned hide |
| E2.18 | Hide drying/stretching | E2.17, E2.08 | frame of branches, cord | i: dried hide; s: hide frame |
| E2.19 | Hide wraps (clothing v0) | E2.18 | dried hide | i: hide wrap (cold protection) |
| E2.20 | Brush hut | E1.22, E2.08 | branches, hides, cord | s: brush/hide hut |
| E2.21 | Cave habitation | E2.15 | natural cave | s: occupied cave (storage, safety) |
| E2.22 | Ochre use | E1.07 | ochre deposit | i: ochre pigment; a: mark, decorate |
| E2.23 | Body painting / symbols | E2.22 | ochre, fat | a: group identity markers |
| E2.24 | Burial of the dead | E1.08 | digging stick | s: grave; a: bury (grief/memory mechanics) |
| E2.25 | Medicinal plant lore | E1.07 | herbs | i: healing herbs; a: treat wounds/sickness |
| E2.26 | Shellfish gathering | — | shoreline | i: shellfish; a: coastal foraging |
| E2.27 | Hand fishing / tidal traps | E2.26 | tide pools | i: fish; a: fish (crude) |
| E2.28 | Meat drying (sun/wind) | E1.20 | racks (branches) | i: dried meat (storable) |
| E2.29 | Seasonal round planning | E1.25 | — | a: seasonal migration, resource calendars |
| E2.30 | Wooden containers (bark tray) | E2.06 | bark, handaxe | i: bark container |

## E3 — Upper Paleolithic (~45 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E3.01 | Blade-core technology | E2.01 | fine flint, punch | i: stone blade (efficient blanks) |
| E3.02 | Flint heat treatment | E2.15, E3.01 | hearth, sand bed | a: improve knappability (better blades) |
| E3.03 | Pressure flaking | E3.01 | antler tine | i: fine points; a: precision edges |
| E3.04 | Burin | E3.01 | blade | i: burin; a: engrave, groove bone/antler |
| E3.05 | End scraper | E3.01 | blade | i: end scraper (hide work upgrade) |
| E3.06 | Backed blade / knife | E3.01 | blade | i: stone knife |
| E3.07 | Bone working | E3.04 | bone, burin | i: bone point, bone awl |
| E3.08 | Antler working (groove & splinter) | E3.04 | antler, burin | i: antler tines, billets, batons |
| E3.09 | Spear straightener (baton) | E3.08 | antler baton | a: straighten shafts (better spears/darts) |
| E3.10 | Eyed needle | E3.07, E2.05 | bone splinter, awl | i: bone needle |
| E3.11 | Sinew/gut thread | E1.05, E2.07 | sinew | i: thread |
| E3.12 | Tailored sewn clothing | E3.10, E3.11, E2.18 | needle, thread, hides | i: fitted parka, leggings (major cold protection) |
| E3.13 | Footwear | E3.12 | hide, cord | i: hide boots |
| E3.14 | Brain tanning | E2.17 | brains/fat, smoke | i: soft leather (durable) |
| E3.15 | Rawhide | E2.18 | dried hide | i: rawhide (hard bindings) |
| E3.16 | Plied rope | E2.07 | fiber bundles | i: rope |
| E3.17 | Atlatl (spear-thrower) | E3.08, E2.11 | wood/antler, composite dart | i: atlatl, dart; a: long-range hunt |
| E3.18 | Barbed harpoon | E3.07 | bone/antler, rope | i: harpoon; a: hunt aquatic prey |
| E3.19 | Leister (fish spear) | E2.27, E2.10 | shaft, bone prongs | i: fish spear |
| E3.20 | Gorge hook & line fishing | E3.07, E3.11 | bone gorge, thread | i: fishing line |
| E3.21 | Knotted netting | E3.16, E2.08 | cordage | i: net (fish/bird) |
| E3.22 | Snares | E2.07 | cord, stakes | a: passive small-game capture |
| E3.23 | Deadfall traps | E3.22 | logs, trigger sticks | a: trap medium game |
| E3.24 | Pit traps | E1.08, E2.12 | dug pit, stakes, cover | a: trap big game |
| E3.25 | Twined matting | E2.07 | reeds, grass | i: mats |
| E3.26 | Coiled basketry | E3.25 | grass, fiber | i: basket (carry capacity up) |
| E3.27 | Meat smoking | E2.28, E2.15 | smoke rack, fire | i: smoked meat/fish (long storage) |
| E3.28 | Rendered fat / pemmican | E1.20 | fat, dried meat, berries | i: pemmican (travel food) |
| E3.29 | Food caching | E2.28 | pit/cairn | s: cache; a: store food vs seasons |
| E3.30 | Oil lamp | E3.28 | stone bowl, fat, wick | i: fat lamp (portable light, cave work) |
| E3.31 | Torch | E2.09, E1.19 | resin, bark, stick | i: torch |
| E3.32 | Hide tent (portable) | E2.20, E3.12 | poles, sewn hides | s: hide tent |
| E3.33 | Travois / sled | E3.16 | poles, rope | i: travois; a: haul loads |
| E3.34 | Grinding slab (pigment/seeds) | E1.01 | flat stone, rubber stone | i: grinding slab |
| E3.35 | Ochre processing | E3.34, E2.22 | slab, ochre, fat | i: paint |
| E3.36 | Cave painting | E3.35, E3.30 | paint, lamp, cave wall | s: painted cave; a: record/ritual art |
| E3.37 | Figurine carving | E3.04 | ivory/stone/clay | i: figurine (ritual/gift item) |
| E3.38 | Bead & pendant making | E2.05, E3.07 | shell, teeth, ivory | i: ornaments (status/trade goods) |
| E3.39 | Bone flute | E3.04, E3.07 | hollow bone | i: flute (music, ritual, morale) |
| E3.40 | Drum | E3.15 | rawhide, hollow log | i: drum |
| E3.41 | Storytelling / oral tradition | E1.25 | language | a: teach by telling (faster tech diffusion, lore) |
| E3.42 | Tally marks / lunar notation | E3.04 | bone, burin | i: tally bone; a: count, track time |
| E3.43 | Exchange networks | E3.38, E2.29 | neighboring bands | a: barter between groups (tech/goods flow) |
| E3.44 | Throwing stick / boomerang | E1.09 | curved hardwood | i: throwing stick (birds, small game) |
| E3.45 | Bird snaring & fowling | E3.21, E3.22 | nets, snares | i: fowl, feathers |

## E4 — Mesolithic (~30 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E4.01 | Microliths | E3.01, E3.03 | blade segments | i: microliths (standard inserts) |
| E4.02 | Composite edged tools | E4.01, E2.10 | microliths, tar, shaft | i: microlith knife/saw |
| E4.03 | Bow construction | E3.09, E3.16 | yew/elm stave, sinew string | i: bow |
| E4.04 | Arrow making | E4.01, E3.09 | shaft, microlith/bone point | i: arrow |
| E4.05 | Fletching | E4.04, E3.45 | feathers, tar/sinew | a: accurate arrows |
| E4.06 | Archery | E4.03, E4.05 | bow, arrows | a: ranged hunting/combat (major) |
| E4.07 | Dog domestication | E3.22, E1.20 | wolf pups event, meat | i: dog (hunting aid, guard, companion) |
| E4.08 | Hunting with dogs | E4.07, E4.06 | dog | a: tracking, driving game |
| E4.09 | Fish weir | E2.27, E3.21 | stakes, wattle | s: fish weir (passive protein) |
| E4.10 | Basket fish trap | E3.26 | withies | i: eel/fish trap |
| E4.11 | Tranchet adze (flaked axe) | E3.01 | flint, haft | i: flaked adze/axe; a: fell small trees |
| E4.12 | Ground-edge tools (early) | E3.34, E4.11 | grinding slab, water, sand | i: ground-edge axe (durable) |
| E4.13 | Tree felling | E4.12 | axe | a: harvest logs; b: log |
| E4.14 | Woodworking (adze/chisel) | E4.13, E4.11 | adze | i: worked wood, bowls, hafts |
| E4.15 | Dugout canoe | E4.13, E1.19 | log, adze, controlled fire | i: dugout canoe |
| E4.16 | Paddle | E4.14 | worked wood | i: paddle; a: water travel |
| E4.17 | Raft | E3.16, E4.13 | logs, rope | i: raft |
| E4.18 | Deep-water fishing | E4.15, E3.20 | canoe, lines/nets | a: offshore fishing |
| E4.19 | Wild grain harvesting | E1.07, E4.02 | wild cereal stands, sickle blade | i: wild grain |
| E4.20 | Seed grinding | E3.34, E4.19 | grinding slab | i: coarse flour |
| E4.21 | Storage pits (lined) | E3.29, E3.25 | dug pit, mats/clay | s: lined storage pit |
| E4.22 | Semi-sedentary camp | E4.09, E4.21 | rich locale | s: seasonal hamlet (huts cluster) |
| E4.23 | Wattle construction | E4.11, E2.20 | stakes, withies | s: wattle hut/fence panels |
| E4.24 | Smoking racks (fish scale-up) | E3.27, E4.09 | racks, fire | s: smokehouse rack |
| E4.25 | Honey gathering | E3.31 | wild hive, smoke torch | i: honey, beeswax |
| E4.26 | Fish poison | E2.25 | poison plants | a: stun fish in pools |
| E4.27 | Skin boat (coracle) | E3.14, E4.23 | hide, withies, tar | i: coracle |
| E4.28 | Sledge & winter travel | E3.33 | worked wood | i: sledge; a: winter transport |
| E4.29 | Cemetery / grave goods | E2.24, E3.38 | grave field | s: cemetery (culture, memory anchors) |
| E4.30 | Bone/antler mattock | E3.08 | antler, haft | i: mattock; a: earthworking |

## E5 — Neolithic (~70 nodes)

### E5.a — Agriculture

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.01 | Plant selection & seed saving | E4.19, E3.42 | wild grain, storage | a: keep best seed (crop lineage) |
| E5.02 | Land clearing (slash & burn) | E4.13, E2.13 | axe, fire | b: cleared field plot |
| E5.03 | Hoe cultivation | E4.30, E4.12 | hoe (stone/antler) | i: hoe; a: till soil; b: tilled soil |
| E5.04 | Sowing & crop tending | E5.01, E5.03 | seed, tilled plot | a: plant/weed/tend; b: crop blocks (growth stages) |
| E5.05 | Cereal domestication (wheat/barley) | E5.04 | generations of cultivation | i: domestic wheat, barley |
| E5.06 | Pulse crops (lentil, pea) | E5.04 | wild pulses | i: lentils, peas (protein, soil health) |
| E5.07 | Flax cultivation | E5.04 | flax seed | i: flax (fiber + linseed) |
| E5.08 | Harvesting sickle | E4.02 | microlith/flint sickle, haft | i: sickle |
| E5.09 | Threshing | E5.08 | threshing floor, flails | b: threshing floor; i: grain, straw |
| E5.10 | Winnowing | E5.09 | baskets, wind | i: clean grain, chaff |
| E5.11 | Granary | E4.21, E5.10 | raised platform, mats/mudbrick | s: granary (rodent-proof storage) |
| E5.12 | Fallowing & rotation | E5.06 | multiple plots | a: sustain soil fertility |
| E5.13 | Manuring | E5.20 | dung, fields | a: fertilize |
| E5.14 | Garden horticulture | E5.04 | vegetables, gourds | i: vegetables, gourds |
| E5.15 | Fig/fruit tree tending | E5.01 | fig/fruit saplings | s: orchard plot (long-cycle food) |
| E5.16 | Simple irrigation ditch | E5.04, E4.30 | stream, mattock | b: ditch; a: water fields |

### E5.b — Animal husbandry

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.17 | Goat/sheep domestication | E4.08, E2.29 | wild herds, penning | i: goat, sheep (tame) |
| E5.18 | Penning & corrals | E4.23 | wattle fence | s: corral |
| E5.19 | Herding | E5.17, E4.07 | flock, dog | a: pasture management |
| E5.20 | Cattle domestication | E5.18 | aurochs capture event | i: cattle |
| E5.21 | Pig domestication | E4.22 | wild boar, scraps | i: pig |
| E5.22 | Milking | E5.17 or E5.20 | tame animals, vessel | i: milk |
| E5.23 | Curdling & cheese | E5.22, E5.34 | milk, warm hearth, rennet | i: curds, cheese (storable dairy) |
| E5.24 | Wool exploitation (plucking) | E5.17 | sheep | i: wool |
| E5.25 | Castration & draft oxen | E5.20 | cattle | i: ox (draft power) |
| E5.26 | Selective breeding (livestock) | E5.19, E3.42 | generations | a: improve yield/temperament |

### E5.c — Food processing

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.27 | Saddle quern | E4.20 | shaped quern stones | i: saddle quern, flour |
| E5.28 | Mortar & pestle | E4.20 | stone mortar | i: mortar & pestle |
| E5.29 | Flatbread baking | E5.27, E2.15 | flour, water, hot stone/hearth | i: flatbread |
| E5.30 | Porridge & gruel | E5.27, E5.34 | grain, pot, fire | i: porridge |
| E5.31 | Beer brewing | E5.29, E5.34 | sprouted grain, pot, time | i: beer (social/ritual good) |
| E5.32 | Fermentation & pickling | E5.34 | pots, brine/whey | i: preserved foods |
| E5.33 | Salt gathering | E2.26 | salt pan/spring | i: salt (preservative, trade good) |

### E5.d — Pottery & fire craft

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.34 | Coil pottery | E3.37, E2.15 | clay deposit, temper | i: clay pot (cooking/storage revolution) |
| E5.35 | Open/pit firing | E5.34 | fuel, pit | s: firing pit; a: fire ceramics |
| E5.36 | Slips & burnishing | E5.35, E2.22 | fine clay, pebble | i: decorated ware (trade/status) |
| E5.37 | Updraft kiln | E5.35, E5.52 | mudbrick/clay kiln | s: kiln (hotter, reliable firing) |
| E5.38 | Bow drill | E4.03, E2.13 | bow, spindle | i: bow drill; a: fast fire, drill holes |
| E5.39 | Stone drilling & perforation | E5.38, E3.34 | drill, sand abrasive | a: axe eyes, beads at scale |
| E5.40 | Polished stone axe/adze | E4.12 | grinding, polishing stones | i: polished axe (forest clearing at scale) |

### E5.e — Textiles

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.41 | Fiber retting & processing | E5.07 | flax, water pit | i: flax fiber |
| E5.42 | Spindle-whorl spinning | E5.41 or E5.24 | spindle, whorl | i: yarn/thread (linen, wool) |
| E5.43 | Warp-weighted loom | E5.42, E4.14 | loom frame, weights | s: loom; i: woven cloth |
| E5.44 | Plant dyeing | E5.43, E2.25 | dye plants, mordant | i: dyed cloth |
| E5.45 | Woven garments | E5.43, E3.12 | cloth, needle | i: tunics, cloaks |

### E5.f — Building & settlement

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.46 | Wattle & daub | E4.23 | wattle, clay/dung daub | b: daub wall; s: wattle-daub house |
| E5.47 | Thatched roofing | E5.46, E4.19 | straw/reed bundles | b: thatch roof |
| E5.48 | Mudbrick making | E5.34, E5.09 | clay, straw, molds, sun | i/b: mudbrick |
| E5.49 | Mudbrick house | E5.48 | bricks, mortar (mud) | s: mudbrick house |
| E5.50 | Lime plaster | E5.37 | burnt limestone, water | i: lime plaster (floors, walls, cisterns) |
| E5.51 | Dug well | E4.30, E5.50 | deep digging, lining | s: well (settle away from rivers) |
| E5.52 | Clay oven | E5.34, E5.29 | clay dome | s: bread oven |
| E5.53 | Ditch & palisade | E4.13, E4.30 | logs, earthwork | s: palisade, defensive ditch |
| E5.54 | Megalith raising | E3.33, E5.68 | large stones, rollers, ropes, crowd | s: menhir/dolmen/circle (ritual anchor) |
| E5.55 | Communal buildings | E5.49 | surplus labor | s: shrine/meeting house |

### E5.g — Society, trade, conflict

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E5.56 | Village life (sedentism) | E5.11, E5.46 | food surplus | s: village (population growth unlocked) |
| E5.57 | Property & ownership marks | E5.56, E2.23 | pottery/tokens | a: ownership rules (theft becomes a concept) |
| E5.58 | Clay tokens (accounting) | E5.34, E3.42 | clay | i: counting tokens |
| E5.59 | Regular trade routes | E3.43, E5.56 | paths, surplus | a: inter-village trade (obsidian, salt, shells) |
| E5.60 | Reed boats | E3.25, E4.17 | reed bundles, rope | i: reed boat |
| E5.61 | Sling | E2.07, E5.43 | woven/leather sling | i: sling, sling stones |
| E5.62 | Mace | E5.39 | perforated stone head, haft | i: mace (first pure weapon) |
| E5.63 | Organized raiding & defense | E5.53, E5.62 | warriors | a: group combat doctrine |
| E5.64 | Shrines & ritual practice | E5.55, E3.36 | shrine, figurines | a: ritual calendar (cohesion, festivals) |
| E5.65 | Ancestor cult | E4.29, E5.64 | cemetery, shrine | a: lineage identity |
| E5.66 | Trepanation & bone setting | E2.25, E3.06 | flint tools, herbs | a: surgery (risky healing) |
| E5.67 | Solstice markers / calendar | E5.54, E3.42 | aligned stones | a: solar calendar (farming timing) |
| E5.68 | Levers, rollers & ramps | E4.13 | logs, know-how | a: move heavy loads |
| E5.69 | Pack animal use | E5.17 | goat/donkey, baskets | a: animal transport |
| E5.70 | Food redistribution (feasting) | E5.31, E5.56 | surplus, communal house | a: feasts (status, alliances) |

## E6 — Chalcolithic / Copper Age (~40 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E6.01 | Native copper collecting | E1.03, E3.43 | surface copper nuggets | i: native copper |
| E6.02 | Cold hammering copper | E6.01, E1.01 | nugget, hammerstone | i: copper beads, awls (first metal) |
| E6.03 | Annealing | E6.02, E2.15 | hearth | a: soften work-hardened copper |
| E6.04 | Ore recognition (malachite/azurite) | E6.01, E2.22 | green/blue ores | a: identify copper ores |
| E6.05 | Charcoal making | E4.13, E5.35 | wood, earth-covered clamp | i: charcoal (high-temp fuel); s: charcoal clamp |
| E6.06 | Crucible | E5.37 | refractory clay | i: crucible |
| E6.07 | Copper smelting | E6.04, E6.05, E6.06, E5.37 | ore, charcoal, kiln/furnace | i: copper ingot; s: smelting furnace |
| E6.08 | Open-mold casting | E6.07 | stone/clay mold | i: cast copper flat axe, chisel |
| E6.09 | Copper toolkit | E6.08, E6.03 | copper, hafts | i: copper axe, adze, chisel, awl, knife |
| E6.10 | Copper daggers | E6.08 | copper, rivets | i: copper dagger (status weapon) |
| E6.11 | Prospecting | E6.04, E2.29 | survey travel | a: find ore veins (map resource) |
| E6.12 | Pit & shaft mining (shallow) | E6.11, E4.30, E3.31 | picks, lamps, timber | s: mine; b: ore blocks exposed |
| E6.13 | Gold working (native) | E6.02 | placer gold | i: gold ornaments (prestige economy) |
| E6.14 | Silver & lead smelting | E6.07 | galena ore | i: lead, silver |
| E6.15 | Tournette (slow potter's wheel) | E5.34, E5.39 | pivoted platform | i: tournette (faster, rounder pots) |
| E6.16 | The wheel (solid disc) | E5.68, E4.14 | plank wood, axe/adze | i: wheel |
| E6.17 | Yoke & animal traction | E5.25 | ox, carved yoke | a: harness draft power |
| E6.18 | Ox-cart | E6.16, E6.17 | wheels, axle, bed, ox | i: cart (bulk land transport) |
| E6.19 | Ard (scratch plow) | E6.17, E4.14 | wooden ard, ox | i: ard (fields scale up 5×) |
| E6.20 | Canal irrigation | E5.16, E5.68 | organized labor | b: canal network (surplus, but coordination needed) |
| E6.21 | Donkey domestication | E5.69 | wild ass | i: donkey (caravans) |
| E6.22 | Horse domestication | E5.19 | steppe horses | i: horse (herding, later riding) |
| E6.23 | Woolly sheep breeds | E5.26, E5.24 | breeding generations | i: wool-rich sheep (textile economy) |
| E6.24 | Wool combs (plucking) | E5.24 | bone combs | i: wool comb |
| E6.25 | Horizontal ground loom | E5.43 | pegged loom | s: ground loom (wider cloth) |
| E6.26 | Olive & grape horticulture | E5.15 | cuttings, presses (basic) | i: olives, grapes |
| E6.27 | Wine making | E6.26, E5.31 | grapes, vats | i: wine (elite/trade good) |
| E6.28 | Oil pressing | E6.26, E5.28 | press stones | i: olive oil (food, light, trade) |
| E6.29 | Stamp seals | E5.57, E3.37 | carved stone | i: stamp seal (identity, sealing goods) |
| E6.30 | Closed kiln (two-chamber) | E5.37 | refined kiln build | s: advanced kiln (~1100°C) |
| E6.31 | Salt mining/boiling | E5.33 | salt deposit, brine pans | s: saltworks (industrial preservative) |
| E6.32 | Craft specialization | E5.56, E6.09 | surplus food | a: full-time potter/smith/weaver roles |
| E6.33 | Social stratification (chiefdoms) | E6.32, E6.13 | prestige goods | a: chief role, tribute |
| E6.34 | Fortified settlements (stone/mudbrick walls) | E5.53, E5.49 | wall building | s: town wall, gate |
| E6.35 | Arsenical copper (accidental alloy) | E6.07 | arsenic-bearing ores | i: hard copper (better blades) |
| E6.36 | Riding (horseback) | E6.22 | horse, mat/pad | a: riding (speed, herding, scouting) |
| E6.37 | Copper saw & drill bits | E6.09, E5.38 | copper blanks | i: copper saw (woodwork precision) |
| E6.38 | Plank woodworking | E6.37 | saw, logs | i/b: planks |
| E6.39 | Plank boats (sewn) | E6.38, E3.16 | planks, cord, tar | i: sewn-plank boat |
| E6.40 | Standard measures (early) | E5.58 | reference rods/vessels | a: consistent lengths/volumes |

## E7 — Bronze Age (~55 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E7.01 | Tin recognition & trade | E6.11, E5.59 | cassiterite sources (rare) | i: tin (strategic resource) |
| E7.02 | Tin-bronze alloying | E7.01, E6.07 | copper + tin, crucible | i: bronze ingot |
| E7.03 | Bivalve molds | E6.08 | two-part stone/clay molds | i: complex castings (socketed tools) |
| E7.04 | Lost-wax casting | E7.03, E4.25 | beeswax, clay investment | i: intricate bronze (figures, fittings) |
| E7.05 | Bronze toolkit | E7.02, E7.03 | bronze, hafts | i: bronze axe, saw, chisel, knife, sickle |
| E7.06 | Bronze weapons | E7.05 | bronze, rivets | i: spearhead, dagger, arrowhead (bronze) |
| E7.07 | The sword | E7.06 | long casting + smithing | i: bronze sword |
| E7.08 | Sheet metalworking | E6.03, E7.02 | hammers, stakes | i: bronze vessels, helmets (raising/sinking) |
| E7.09 | Bronze armor | E7.08 | sheet bronze, leather backing | i: helmet, cuirass, greaves |
| E7.10 | Shield making | E3.14, E4.14 | wood, hide, bronze boss | i: shield |
| E7.11 | Riveting & joining | E7.08 | rivets | a: assemble metal parts |
| E7.12 | Wire drawing/making | E7.08 | drawplates/strips | i: wire (jewelry, mail later) |
| E7.13 | Bag & pot bellows | E3.14, E6.07 | hide bags, tuyères | i: bellows (hotter furnaces) |
| E7.14 | Ore roasting & fluxing | E6.07 | roasting beds | a: efficient smelting of sulfide ores |
| E7.15 | Deep-shaft mining | E6.12, E7.05 | bronze picks, timbering, lamps | s: deep mine (galleries) |
| E7.16 | Cupellation | E6.14 | bone-ash hearth | i: refined silver (currency metal) |
| E7.17 | Goldsmithing (granulation, filigree) | E6.13, E7.12 | fine tools | i: masterwork jewelry |
| E7.18 | Faience | E6.30, E5.36 | quartz paste, glaze | i: faience beads/amulets |
| E7.19 | Glassmaking (core-formed) | E7.18, E7.13 | sand, natron, high heat | i: glass beads, small vessels |
| E7.20 | Pottery glazes | E7.18 | glaze minerals | i: glazed ware |
| E7.21 | Fast potter's wheel | E6.15, E6.16 | flywheel | s: potter's wheel (mass production) |
| E7.22 | Spoked wheel | E6.16, E6.37 | bentwood, precision joinery | i: spoked wheel (light, fast) |
| E7.23 | Chariot | E7.22, E6.22, E7.11 | 2 horses, light frame | i: war chariot |
| E7.24 | Horse bit & tack | E6.36, E3.14 | bronze bit, leather | i: bridle, bit (control at speed) |
| E7.25 | Square sail | E5.43, E6.39 | cloth sail, mast, rigging | a: wind propulsion |
| E7.26 | Mortise-and-tenon shipbuilding | E6.38, E7.05 | bronze tools | i: seagoing ship |
| E7.27 | Coastal & star navigation | E7.25, E5.67 | pilot lore | a: long-range sea trade |
| E7.28 | Anchor & harbor works | E7.26 | stone anchors, moles | s: harbor |
| E7.29 | Pictographic record keeping | E5.58, E6.29 | clay tablets, stylus | i: proto-writing tablets |
| E7.30 | Writing (cuneiform-like) | E7.29 | scribes, training | a: full writing (contracts, letters, lore storage) |
| E7.31 | Scribal schools | E7.30, E5.55 | tablet house | s: school (fast knowledge diffusion) |
| E7.32 | Cylinder seals & contracts | E6.29, E7.30 | carved cylinders | a: sealed contracts |
| E7.33 | Standard weights & measures | E6.40, E7.30 | balance scale, weight sets | i: balance scale; a: fair markets |
| E7.34 | Arithmetic & geometry | E7.30, E3.42 | numeracy training | a: area, volume, interest calc |
| E7.35 | Astronomical calendar | E5.67, E7.34 | observation records | a: lunisolar calendar, eclipse lore |
| E7.36 | Bureaucracy & taxation | E7.33, E7.32 | scribes, storehouses | a: centralized redistribution |
| E7.37 | Law codes | E7.30, E6.33 | stelae, judges | a: codified justice |
| E7.38 | City planning | E6.34, E7.36 | surveyors | s: city (districts, streets) |
| E7.39 | Palace/temple economy | E7.36, E5.64 | monumental buildings | s: palace, temple complex |
| E7.40 | Monumental architecture | E5.54, E5.68, E7.34 | dressed stone, ramps, labor | s: ziggurat/great temple |
| E7.41 | Stone dressing & masonry | E7.05, E5.50 | bronze chisels, squares | b: dressed stone; a: fine masonry |
| E7.42 | Professional soldiery | E7.36, E7.06 | rations, armory | a: standing troops, drill |
| E7.43 | Siegecraft (ladders, rams) | E7.42, E6.34 | timber engines | a: assault fortifications |
| E7.44 | Composite bow | E4.03, E2.09, E3.08 | horn, sinew, wood, glue | i: composite bow (compact power) |
| E7.45 | Shaduf irrigation | E5.68, E6.20 | counterweight lever | i: shaduf (lift water) |
| E7.46 | Terrace farming | E6.20, E7.41 | hillside walls | b: terraces |
| E7.47 | Beekeeping | E4.25, E5.34 | hive pots | s: apiary; i: honey/wax at scale |
| E7.48 | Textile industry & dye trade | E6.25, E6.23, E5.44 | workshops, murex/indigo | i: luxury cloth (export good) |
| E7.49 | Perfume & cosmetics | E6.28, E7.19 | oils, resins | i: perfume, kohl |
| E7.50 | Early soap | E6.28, E6.05 | oil + ashes (lye) | i: soap |
| E7.51 | Pharmacopeia & surgical kit | E5.66, E7.30 | written recipes, bronze scalpels | a: recorded medicine |
| E7.52 | Stringed instruments | E3.39, E3.11 | lyre/harp builds | i: lyre, harp |
| E7.53 | Board games & dice | E7.34 | boards, knucklebones | i: game sets (leisure culture) |
| E7.54 | Ice/cool storage houses | E5.49 | thick-walled cellar | s: cool store |
| E7.55 | Caravan trade (donkey trains) | E6.21, E7.33 | way stations | s: caravanserai; a: long-distance overland trade |

## E8 — Iron Age (~45 nodes)

| ID | Technology | Prereqs | Needs | Introduces |
|---|---|---|---|---|
| E8.01 | Iron ore recognition (bog/hematite) | E6.11 | iron ores | a: identify iron sources (common!) |
| E8.02 | Bloomery furnace | E8.01, E7.13, E6.05 | clay furnace, charcoal, bellows | s: bloomery; i: iron bloom |
| E8.03 | Bloom consolidation | E8.02, E1.01 | hammer, anvil stone | i: wrought iron billet |
| E8.04 | Smithing hearth & anvil | E8.03 | charcoal hearth, iron/stone anvil | s: smithy; i: anvil, tongs, smith's hammer |
| E8.05 | Forging fundamentals | E8.04 | smithy | a: draw, upset, bend, punch iron |
| E8.06 | Forge welding | E8.05 | flux (sand), high heat | a: join iron pieces |
| E8.07 | Carburization (steeling) | E8.05 | prolonged charcoal contact | i: steel edges |
| E8.08 | Quench hardening | E8.07 | water/oil trough | a: harden blades |
| E8.09 | Tempering | E8.08 | controlled reheat | a: tough + hard blades (mastery) |
| E8.10 | Iron toolkit | E8.05 | iron stock | i: iron axe, saw, hammer, chisel, knife, tongs |
| E8.11 | Iron nails & fittings | E8.05 | iron rod | i: nails, hinges, fittings (construction leap) |
| E8.12 | Iron agricultural tools | E8.10 | iron, wood | i: iron sickle, scythe, spade, hoe |
| E8.13 | Iron plowshare | E8.12, E6.19 | ard + iron share | i: iron plow (heavy soils open up) |
| E8.14 | Iron weapons | E8.07, E8.09 | steel-edged iron | i: iron sword, spear, arrowheads |
| E8.15 | Iron armor & helmets | E8.05, E7.09 | iron sheet/scales | i: iron helmet, scale armor |
| E8.16 | Chain mail | E7.12, E8.06 | iron wire, rivets | i: mail shirt |
| E8.17 | Cavalry warfare | E6.36, E8.14, E7.24 | trained horse+rider corps | a: cavalry doctrine |
| E8.18 | Rotary quern | E5.27, E8.10 | dressed stones, iron spindle | i: rotary quern (household flour 5× faster) |
| E8.19 | Animal-driven mill | E8.18, E6.17 | large quern, donkey/ox | s: animal mill |
| E8.20 | Water mill (terminal node) | E8.19, E7.41 | stream race, wheel | s: water mill (first non-muscle power) |
| E8.21 | Bow lathe | E5.38, E8.10 | lathe frame, iron tools | s: lathe; i: turned bowls, spokes |
| E8.22 | Advanced joinery | E8.10, E8.11 | planes, augers | a: framed buildings, furniture |
| E8.23 | Timber-framed architecture | E8.22 | beams, joints, nails | s: timber-frame houses, halls |
| E8.24 | True arch | E7.41 | voussoirs, centering | b: arch (gates, bridges) |
| E8.25 | Stone bridges | E8.24 | masonry, falsework | s: stone bridge |
| E8.26 | Paved roads | E7.38, E8.24 | roadbed, paving | b: paved road (trade speed) |
| E8.27 | Drainage & sewers | E8.24, E7.38 | channels, culverts | s: sewer (city health) |
| E8.28 | Aqueduct/water channels | E8.24, E7.45 | graded channels | s: aqueduct (urban water) |
| E8.29 | Alphabetic writing | E7.30 | simplified signs | a: mass literacy possible (22–30 signs) |
| E8.30 | Coinage | E7.16, E6.29, E7.33 | stamped precious metal | i: coins; a: money economy |
| E8.31 | Markets & shops | E8.30, E7.38 | agora/forum | s: marketplace |
| E8.32 | Interest & credit | E8.30, E7.34 | ledgers | a: loans, banking (proto) |
| E8.33 | Maps & surveying | E7.34, E8.26 | groma/ropes, records | i: maps; a: land division |
| E8.34 | Libraries & archives | E8.29, E7.31 | scroll/tablet stores | s: library (tech preservation vs loss) |
| E8.35 | Rational medicine | E7.51, E8.29 | written case lore | a: diagnosis, prognosis, iron surgical tools |
| E8.36 | Shears & scissors | E8.05 | sprung iron | i: shears (true sheep shearing, barbering) |
| E8.37 | Wool industry (shearing) | E8.36, E6.23 | shears, looms | i: wool trade at scale |
| E8.38 | Beam press | E5.68, E8.22 | timber beam, weights | s: oil/wine press (industrial) |
| E8.39 | Amphora & bulk trade | E7.21, E7.26 | standard vessels, ships | i: amphorae; a: bulk commodity shipping |
| E8.40 | Wooden pin locks & keys | E8.22 | precision woodwork | i: lock & key (property security) |
| E8.41 | Pattern-welded blades | E8.06, E8.09 | steel+iron billets | i: masterwork sword (endgame smithing) |
| E8.42 | Glassblowing (terminal node) | E7.19, E7.13 | blowpipe, furnace | i: blown glassware |
| E8.43 | Crossbow (optional, regional) | E4.06, E8.10 | stock, trigger, iron | i: crossbow |
| E8.44 | Siege engines (torsion, optional) | E7.43, E8.22 | timber, sinew ropes | i: catapult/ballista |
| E8.45 | Standardized workshops | E8.10, E6.32 | toolsets, apprentices | a: guild-like production, apprenticeship (fast teach) |

---

## Graph notes

- **Terminal nodes** (E8.20 water mill, E8.42 glassblowing, E8.41 pattern welding, E8.44) mark "end of Iron Age" — natural stopping frontier.
- **Great bottlenecks** (design intent — moments the whole sim pivots on): E1.18 fire, E2.10 hafting, E4.06 archery, E5.05 domesticated cereal, E5.34 pottery, E6.07 copper smelting, E7.02 bronze, E7.30 writing, E8.02 bloomery, E8.30 coinage.
- **Knowledge decay**: if all NPCs knowing a node die, the settlement loses it (writing E7.30+ and libraries E8.34 mitigate).
- **Diffusion speeds**: demonstration (E1.25) < storytelling (E3.41) < schools (E7.31) < alphabetic literacy (E8.29).
- Node count: **340**.

