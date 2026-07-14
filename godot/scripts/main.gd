extends Node3D
## VOX P3 bootstrap: world + resources + a VILLAGE of NPCs whose minds live in
## Cortex. Main owns the roster (spawned from Cortex's hello), message routing,
## proximity perception, tier assignment (full LLM near the camera, scripted
## far away), and converse coordination between two NPCs.
## Exit criterion: two NPCs exchange a technology.

const NEARBY_NPC_RADIUS := 40.0   # generous social range: someone to talk to is usually listed
const PERCEPTION_RADIUS := 10.0
const PERCEPTION_COOLDOWN := 45.0
const OFFLINE_ROSTER := [
	{"id": "anon", "name": "Anon"}, {"id": "toran", "name": "Toran"},
	{"id": "kara", "name": "Kara"},
]

const GIFT_RADIUS := 8.0
const GIFT_HUNGER := 80.0
# (FULL_TIER_RADIUS retired: every NPC gets a full LLM mind now)

var world: VoxelWorld
var tech: TechData
var field: ResourceField
var campfire: Campfire                   # the primary fire (village A)
var campfires: Array = []                # all fires (emergent flavor has two)
var village_fires := {}                  # village name -> Campfire
var flavor := "vanilla"
var structures: Array[Dictionary] = []   # built huts: {type, pos, node, warmth}
var cam_rig: OrbitCamera
var cortex: CortexClient
var chat_ui: ChatUI
var menu: MenuUI
var _started := false
var _save_cfg := {}                # {seed, chunks, preset, water} of this map
var _pending_save := {}            # parsed save file being restored

const SAVE_PATH := "user://vox_save.json"
var controllers := {}              # id -> NPCController, spawn order preserved
var brains := {}                   # id -> brain binding string (from roster)
var focused_id := ""
var day_number := 1
var era_name := "Lower Paleolithic"
var _season_idx := 0
var _pop_cap := 30
var _births := 0
var _rng := RandomNumberGenerator.new()
var path_line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _sun: DirectionalLight3D
var _env: Environment
var _day_seconds := 240.0
var _night_fraction := 0.35
var _day_t := 0.0
var _hud: Label
var _hud_t := 0.0
var _tick_t := 0.0
var _roster_spawned := false
var _total_spawned := 0
var _offline_t := 6.0
var _perception_t := 6.0
var _seen_cooldown := {}           # "a>b" -> seconds remaining
var _tech_exchanges := 0
var _deaths := 0
var _collapsed := false


func _ready() -> void:
	InputConfig.setup()
	_setup_environment()
	if DisplayServer.get_name() == "headless":
		# automation (self-tests, marathons) skips the menu; env vars pick the map
		var chunks := 8
		if OS.get_environment("VOX_MAP_CHUNKS").is_valid_int():
			chunks = OS.get_environment("VOX_MAP_CHUNKS").to_int()
		var terrain := OS.get_environment("VOX_TERRAIN")
		var water := 0.20
		if OS.get_environment("VOX_WATER").is_valid_int():
			water = OS.get_environment("VOX_WATER").to_int() / 100.0
		var seed_env := -1
		if OS.get_environment("VOX_SEED").is_valid_int():
			seed_env = OS.get_environment("VOX_SEED").to_int()
		var flavor_env := OS.get_environment("VOX_FLAVOR")
		if OS.get_environment("VOX_CONTINUE") == "1":
			_continue_game()   # automated save/load testing
		else:
			_start_game(chunks, terrain if terrain != "" else "hills", water, seed_env,
				flavor_env if flavor_env != "" else "vanilla")
		return
	menu = MenuUI.new()
	add_child(menu)
	menu.start_game.connect(_start_game)
	menu.continue_game.connect(_continue_game)
	menu.exit_game.connect(func() -> void: get_tree().quit())


func _continue_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	_pending_save = data
	_start_game(int(data.get("chunks", 8)), str(data.get("preset", "hills")),
		float(data.get("water", 0.2)), int(data.get("seed", 1337)),
		str(data.get("flavor", "vanilla")), bool(data.get("council", false)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _start_game(size_chunks: int, preset: String, water := 0.20, map_seed := -1,
		p_flavor := "vanilla", p_council := false) -> void:
	council_enabled = p_council or OS.get_environment("VOX_COUNCIL") == "1"
	if _started:
		return
	_started = true
	flavor = p_flavor
	if map_seed < 0:
		map_seed = randi() & 0x7FFFFFFF   # every new game is a new world
	_save_cfg = {"seed": map_seed, "chunks": size_chunks, "preset": preset,
		"water": water, "flavor": flavor}
	if menu != null:
		menu.show_generating()
		await get_tree().process_frame   # let the "Generating..." screen paint
		await get_tree().process_frame
	world = VoxelWorld.new()
	add_child(world)
	world.configure(size_chunks, preset, water)
	world.world_seed = map_seed
	world.generate()
	tech = TechData.load_data()
	_setup_time()
	_setup_campfire()
	# the village lives in the LARGEST walk component; gatherables follow
	campfire.position = world.compute_best_component()
	if flavor == "emergent":
		# a second village, as far away as the land allows (but reachable)
		var far := world.farthest_reachable_from(campfire.position)
		_make_fire(far)
		print("[VOX P8] emergent: second village fire %.0f blocks away"
			% NPCController._flat_dist(campfire.position, far))
	field = ResourceField.new()
	add_child(field)
	field.setup(world, tech)
	if OS.get_environment("VOX_START_CACHE") == "1":
		# test hook: pre-dug cache so headless runs exercise the store economy
		var spot := world.random_walkable_near(campfire.position, 6.0)
		var cache := _place_structure("cache_pit", spot)
		cache.store["dried_meat"] = 6
		print("[VOX A] test hook: starting cache pit placed (6 dried meat)")
	if OS.get_environment("VOX_START_SMELTER") == "1":
		# test hook: a standing smelter so headless runs exercise the metal chain
		var sspot := world.random_walkable_near(campfire.position, 8.0)
		_place_structure("smelter", sspot)
		print("[VOX E] test hook: starting smelter placed")
	if OS.get_environment("VOX_START_MILL") == "1":
		# test hook: exercises the water-adjacent placement + grain processor
		var mspot := Vector3.INF
		for i in 400:
			var cand := world.random_walkable_near(campfire.position, 40.0)
			if cand != Vector3.ZERO and _touches_water(cand):
				mspot = cand
				break
		if mspot != Vector3.INF:
			var mill := _place_structure("watermill", mspot)
			mill.store["grain"] = 5
			print("[VOX J] test hook: watermill placed on the bank (5 grain in)")
		else:
			print("[VOX J] test hook: NO water-adjacent cell found for the mill")
	if OS.get_environment("VOX_START_RACK") == "1":
		# test hook: a smoking rack with meat hung, so dawn processors show
		var rspot := world.random_walkable_near(campfire.position, 7.0)
		var rack := _place_structure("smoking_rack", rspot)
		rack.store["raw_meat"] = 4
		print("[VOX I] test hook: smoking rack placed (4 raw meat hung)")
	if OS.get_environment("VOX_START_CORRAL") == "1":
		# test hook: a corral with a goat pair so herding runs from minute one
		var cspot := world.random_walkable_near(campfire.position, 9.0)
		var corral := _place_structure("corral", cspot)
		corral.herd["goat"] = 2
		print("[VOX C] test hook: starting corral placed (2 goats)")
	var decor := Decoration.new()
	add_child(decor)
	decor.setup(world)
	if tech.predators.has("wolf"):
		var predators := Predators.new()
		add_child(predators)
		predators.setup(world, self, tech.predators["wolf"])
	_setup_camera()
	_setup_path_line()
	if not _pending_save.is_empty():
		_apply_world_save()
	_setup_cortex()
	_setup_ui()
	_self_test()
	if menu != null:
		menu.close()


# ---------------------------------------------------------------- save/load

func save_game() -> void:
	if not _started or not _roster_spawned:
		return
	# headless marathons stay stateless unless a test explicitly opts in
	if DisplayServer.get_name() == "headless" \
			and OS.get_environment("VOX_ALLOW_HEADLESS_SAVE") != "1":
		return
	var npcs := {}
	for npc_id in controllers:
		var npc: NPC = controllers[npc_id].npc
		npcs[npc_id] = {
			"x": snappedf(npc.position.x, 0.1), "y": snappedf(npc.position.y, 0.1),
			"z": snappedf(npc.position.z, 0.1),
			"age": snappedf(npc.age, 0.1), "lifespan": snappedf(npc.lifespan, 0.1),
			"hunger": roundi(npc.hunger), "energy": roundi(npc.energy),
			"health": roundi(npc.health), "inventory": npc.inventory,
		}
	var structs := []
	for s in structures:
		structs.append({"type": s.type, "x": s.pos.x, "y": s.pos.y, "z": s.pos.z,
			"store": s.store, "planted": s.planted, "growth": s.growth,
			"herd": s.herd})
	var data := {
		"version": 1,
		"seed": _save_cfg.get("seed", 1337), "chunks": _save_cfg.get("chunks", 8),
		"preset": _save_cfg.get("preset", "hills"), "water": _save_cfg.get("water", 0.2),
		"flavor": flavor,
		"council": council_enabled,
		"day_number": day_number, "day_t": snappedf(_day_t, 0.1),
		"fire_fuel": snappedf(campfire.fuel, 0.1),
		"fire_fuels": campfires.map(func(f: Campfire) -> float:
			return snappedf(f.fuel, 0.1)),
		"era_name": era_name,
		"counters": {"births": _births, "deaths": _deaths,
			"exchanges": _tech_exchanges, "total": _total_spawned,
			"pop_cap": _pop_cap, "dogs": dogs},
		"structures": structs,
		"field": field.save_state(),
		"npcs": npcs,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		print("[VOX P7] world saved (day %d, %d villagers)" % [day_number, npcs.size()])


func _apply_world_save() -> void:
	## World-level restore, before the roster arrives (bodies restore in
	## _spawn_roster; minds live in Cortex and never left).
	day_number = int(_pending_save.get("day_number", 1))
	_day_t = float(_pending_save.get("day_t", 0.0))
	campfire.fuel = float(_pending_save.get("fire_fuel", campfire.fuel))
	var fuels: Array = _pending_save.get("fire_fuels", [])
	for i in mini(fuels.size(), campfires.size()):
		campfires[i].fuel = float(fuels[i])
	era_name = str(_pending_save.get("era_name", era_name))
	var c: Dictionary = _pending_save.get("counters", {})
	_births = int(c.get("births", 0))
	_deaths = int(c.get("deaths", 0))
	_tech_exchanges = int(c.get("exchanges", 0))
	_pop_cap = int(c.get("pop_cap", 30))
	dogs = int(c.get("dogs", 0))
	for s in _pending_save.get("structures", []):
		var entry := _place_structure(str(s.get("type", "brush_hut")),
			Vector3(float(s.x), float(s.y), float(s.z)))
		for item in s.get("store", {}):
			entry.store[item] = int(s.store[item])
		entry.planted = bool(s.get("planted", false))
		entry.growth = int(s.get("growth", 0))
		for kind in s.get("herd", {}):
			entry.herd[kind] = int(s.herd[kind])
	field.apply_save(_pending_save.get("field", {}))
	_update_season()
	print("[VOX P7] world restored: day %d, %d structures" % [day_number,
		structures.size()])


func _process(delta: float) -> void:
	if not _started:
		return
	_advance_time(delta)
	if not _roster_spawned:
		_offline_t -= delta
		if _offline_t <= 0.0 and not cortex.online:
			_spawn_roster(OFFLINE_ROSTER, flavor)   # match whatever flavor was picked
		return
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.2
		_update_hud()
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 0.5
		_survival_tick()
	_perception_t -= delta
	if _perception_t <= 0.0:
		_perception_t = 6.0
		_perception_scan()
		_gift_scan()
	for key in _seen_cooldown.keys():
		_seen_cooldown[key] -= delta
		if _seen_cooldown[key] <= 0.0:
			_seen_cooldown.erase(key)


# ---------------------------------------------------------------- time & survival

func _setup_time() -> void:
	_day_seconds = float(tech.time_cfg.get("day_seconds_default", 240))
	_night_fraction = float(tech.time_cfg.get("night_fraction", 0.35))
	var env_override := OS.get_environment("VOX_DAY_SECONDS")
	if env_override.is_valid_float():
		_day_seconds = maxf(10.0, env_override.to_float())
	print("[VOX P4] day length: %.0fs (night is the last %.0f%%)"
		% [_day_seconds, _night_fraction * 100.0])


func _setup_campfire() -> void:
	campfire = _make_fire(world.find_spawn())


func _make_fire(pos: Vector3) -> Campfire:
	var fire := Campfire.new()
	add_child(fire)
	fire.setup(tech.stations.get("campfire", {}))
	fire.position = pos
	var decay_override := OS.get_environment("VOX_FIRE_DECAY")
	if decay_override.is_valid_float():
		fire.decay_per_minute = decay_override.to_float()
	campfires.append(fire)
	return fire


func nearest_fire(pos: Vector3) -> Campfire:
	var best: Campfire = campfire
	var best_d := INF
	for f in campfires:
		var d := NPCController._flat_dist(pos, f.position)
		if d < best_d:
			best_d = d
			best = f
	return best


func is_night() -> bool:
	return _day_t / _day_seconds >= 1.0 - _night_fraction


func time_of_day() -> String:
	return "night" if is_night() else "day"


func season_name() -> String:
	var seasons: Array = tech.time_cfg.get("seasons",
		["spring", "summer", "autumn", "winter"])
	return str(seasons[_season_idx % seasons.size()])


func _update_season() -> void:
	var per := int(tech.time_cfg.get("days_per_season", 3))
	var seasons: Array = tech.time_cfg.get("seasons",
		["spring", "summer", "autumn", "winter"])
	var idx := (day_number - 1) / per % seasons.size()
	if idx != _season_idx:
		_season_idx = idx
		field.winter = season_name() == "winter"
		var line := "the season turns: it is now %s" % season_name()
		print("[VOX P6] ", line)
		if chat_ui != null:   # save-restore runs before the UI exists
			chat_ui.add_line("world", "[i]%s[/i]" % line)


func fire_state(pos: Vector3) -> Dictionary:
	var fire := nearest_fire(pos)
	return fire.state_for(pos) if fire != null else {}


func _advance_time(delta: float) -> void:
	var was_night := is_night()
	_day_t += delta
	if _day_t >= _day_seconds:
		_day_t -= _day_seconds
		day_number += 1
		_update_season()
		_age_the_band()
		_roll_birth()
		_dawn_processors()   # smoke tonight's catch BEFORE the rot check
		_dawn_economy()
		_dawn_fields()
		_dawn_herds()
		_dawn_report()
		_send_village()
		_hold_councils()
	if _sun != null:
		var frac := _day_t / _day_seconds
		var day_span := 1.0 - _night_fraction
		if frac < day_span:
			var t := frac / day_span
			_sun.rotation_degrees.x = lerpf(-12.0, -168.0, t)
			_sun.light_energy = 1.2 * clampf(sin(t * PI) + 0.25, 0.2, 1.0)
			_env.ambient_light_energy = lerpf(0.35, 1.0, clampf(sin(t * PI), 0.0, 1.0))
		else:
			_sun.light_energy = 0.12
			_env.ambient_light_energy = 0.22
	if was_night != is_night() and is_night():
		print("[VOX P4] night falls on day %d" % day_number)


func _age_the_band() -> void:
	var years := float(tech.lifecycle.get("years_per_day", 1))
	var adult := float(tech.lifecycle.get("adult_age", 14))
	for npc_id in controllers.keys():
		var npc: NPC = controllers[npc_id].npc
		npc.age += years
		npc.scale = Vector3.ONE * (0.7 if npc.age < adult else 1.0)
		if npc.age >= npc.lifespan and not npc.dead:
			_kill_npc(controllers[npc_id], "old age")


func _roll_birth() -> void:
	if not cortex.online or controllers.size() >= _pop_cap:
		return
	if _rng.randf() >= float(tech.lifecycle.get("birth_chance_per_dawn", 0.4)):
		return
	var adult := float(tech.lifecycle.get("adult_age", 14))
	var adults: Array = []
	for npc_id in controllers:
		if controllers[npc_id].npc.age >= adult:
			adults.append(npc_id)
	if adults.size() < 2:
		return
	adults.shuffle()
	cortex.send({"type": "birth", "a": adults[0], "b": adults[1]})


func _on_born(npc_data: Dictionary, parents: Array) -> void:
	_births += 1
	var npc_id := str(npc_data.get("id", ""))
	if npc_id == "" or controllers.has(npc_id):
		return
	var display := str(npc_data.get("name", npc_id.capitalize()))
	brains[npc_id] = str(npc_data.get("brain", "?"))
	# the child appears beside a parent (or the fire)
	var near: Vector3 = campfire.position
	if parents.size() > 0 and controllers.has(str(parents[0])):
		near = controllers[str(parents[0])].npc.position
	var npc := _spawn_body(npc_id, display, _connected_spot_near(near, 4.0))
	npc.age = 0.0
	npc.scale = Vector3.ONE * 0.7
	_total_spawned += 1
	var parent_names: Array = []
	for p in parents:
		parent_names.append(controllers[str(p)].npc.npc_name
			if controllers.has(str(p)) else str(p).capitalize())
	var line := "%s is born to %s" % [display, " and ".join(parent_names)]
	print("[VOX P6] BIRTH: ", line)
	chat_ui.add_line("world", "[b]*** %s ***[/b]" % line)


func _dawn_economy() -> void:
	## Spoilage: each dawn, every perishable stack loses ~count/spoils_days.
	## Vermin: open caches get raided; granaries are safe.
	for npc_id in controllers:
		var npc: NPC = controllers[npc_id].npc
		var rotted := _spoil_inventory(npc.inventory)
		if rotted != "":
			controllers[npc_id].emit_event("found that %s rotted" % rotted)
	for s in structures:
		if int(s.capacity) <= 0:
			continue
		_spoil_inventory(s.store)
		if not bool(s.vermin_safe) \
				and _rng.randf() < float(tech.storage_cfg.get("vermin_raid_chance_per_dawn", 0.3)):
			var eaten := _vermin_raid(s.store)
			if eaten != "":
				var line := "rats got into the %s and ate %s" % [
					str(tech.buildables.get(s.type, {}).get("label", s.type)), eaten]
				print("[VOX A] ", line)
				chat_ui.add_line("world", "[i]%s[/i]" % line)


func _spoil_inventory(inv: Dictionary) -> String:
	var rotted: Array = []
	for item in inv.keys():
		var days := float(tech.items.get(item, {}).get("spoils_days", 0))
		if days <= 0:
			continue
		var count := int(inv[item])
		var lost := 0
		for i in count:
			if _rng.randf() < 1.0 / days:
				lost += 1
		if lost > 0:
			inv[item] = count - lost
			if int(inv[item]) <= 0:
				inv.erase(item)
			rotted.append("%d %s" % [lost, tech.item_label(item)])
	return ", ".join(rotted)


func _vermin_raid(store: Dictionary) -> String:
	var frac := float(tech.storage_cfg.get("vermin_loss_fraction", 0.25))
	var eaten: Array = []
	for item in store.keys():
		if not tech.is_food(item):
			continue
		var lost := maxi(1, roundi(int(store[item]) * frac))
		lost = mini(lost, int(store[item]))
		store[item] = int(store[item]) - lost
		if int(store[item]) <= 0:
			store.erase(item)
		eaten.append("%d %s" % [lost, tech.item_label(item)])
	return ", ".join(eaten)


# ---------------------------------------------------------------- dawn council

var council_enabled := false


func _hold_councils() -> void:
	## Optional dawn assembly: each village gathers at its fire, reports the
	## past day and agrees a plan Cortex injects into every mind for the day.
	if not council_enabled or not cortex.online or not _roster_spawned:
		return
	if _day_seconds < 60.0:
		return   # marathon days are too short for meetings
	# one council per fire — emergent maps hold two, one per village
	for fire in campfires:
		var members: Array[NPCController] = []
		for npc_id in controllers:
			var ctrl: NPCController = controllers[npc_id]
			if ctrl.npc.dead or ctrl.talking:
				continue
			if nearest_fire(ctrl.npc.position) == fire:
				members.append(ctrl)
		if members.size() < 2:
			continue
		var ids: Array = []
		for i in members.size():
			var ang := TAU * i / members.size()
			members[i].begin_council(fire.position
				+ Vector3(cos(ang) * 2.5, 0, sin(ang) * 2.5))
			ids.append(members[i].id)
		var food := 0
		for s in structures:
			for item in s.store:
				if tech.is_food(item):
					food += int(s.store[item])
		cortex.send({"type": "council", "npcs": ids, "report": {
			"day": day_number, "season": season_name(), "era": era_name,
			"alive": ids.size(), "deaths": _deaths, "births": _births,
			"fire_pct": roundi(fire.fuel),
			"food_in_stores": food, "huts": hut_count()}})
		print("[VOX COUNCIL] dawn council of %d at the fire" % ids.size())


func _on_council_end(data: Dictionary) -> void:
	for npc_id in data.get("npcs", []):
		var ctrl: NPCController = controllers.get(str(npc_id))
		if ctrl != null:
			ctrl.end_council()
	var plan := str(data.get("plan", ""))
	if plan != "":
		var line := "The council agreed: %s" % plan
		print("[VOX COUNCIL] ", line)
		chat_ui.add_line("world", "[b]%s[/b]" % line)


func _dawn_processors() -> void:
	## Dawn-processor pattern: structures with a "processes" map transform
	## what was deposited in them overnight (smoking rack: raw -> smoked).
	for s in structures:
		var proc: Dictionary = tech.buildables.get(s.type, {}).get("processes", {})
		if proc.is_empty():
			continue
		var made: Array = []
		for item in proc.keys():
			var n := int(s.store.get(item, 0))
			if n <= 0:
				continue
			var out := str(proc[item])
			s.store.erase(item)
			s.store[out] = int(s.store.get(out, 0)) + n
			made.append("%d %s" % [n, tech.item_label(out)])
		if not made.is_empty():
			var line := "the %s %s %s overnight" % [
				str(tech.buildables.get(s.type, {}).get("label", s.type)),
				str(tech.buildables.get(s.type, {}).get("process_verb", "made")),
				", ".join(made)]
			print("[VOX I] ", line)
			chat_ui.add_line("world", "[i]%s[/i]" % line)


func structure_kinds() -> Array:
	var kinds := {}
	for s in structures:
		kinds[s.type] = true
	return kinds.keys()


func _send_village() -> void:
	## Lightweight census so Cortex can gate infrastructure-dependent rules
	## (the school makes the x4+ diffusion tiers real, not just known).
	if cortex.online:
		cortex.send({"type": "village", "structures": structure_kinds(),
			"dogs": dogs, "oxen": oxen})


func _dawn_report() -> void:
	var alive := controllers.size()
	print("[VOX P4] === Dawn of day %d (%s, %s): %d/%d alive, fire fuel %d%%, %d techs learned, %d births, %d deaths ==="
		% [day_number, season_name(), era_name, alive, _total_spawned,
			roundi(campfire.fuel), _tech_exchanges, _births, _deaths])
	save_game()   # autosave every dawn (no-op headless)
	if day_number == 11:
		if alive > 0:
			print("[VOX P4] VILLAGE SURVIVED 10 DAYS UNATTENDED (%d/%d alive)"
				% [alive, _total_spawned])
		else:
			print("[VOX P4] VILLAGE PERISHED BEFORE DAY 10")


func _survival_tick() -> void:
	var night := is_night()
	for npc_id in controllers.keys():
		var ctrl: NPCController = controllers[npc_id]
		var npc := ctrl.npc
		npc.night = night
		npc.warm = false
		for f in campfires:
			if f.is_lit() and NPCController._flat_dist(npc.position, f.position) \
					<= f.warmth_radius:
				npc.warm = true
				break
		if not npc.warm:
			for s in structures:
				if NPCController._flat_dist(npc.position, s.pos) <= float(s.warmth):
					npc.warm = true
					break
		if npc.health <= 0.0 and not npc.dead:
			_kill_npc(ctrl)
	if controllers.is_empty() and _total_spawned > 0 and not _collapsed:
		_collapsed = true
		print("[VOX P4] the village has perished on day %d" % day_number)


func _kill_npc(ctrl: NPCController, cause: String = "starvation") -> void:
	_deaths += 1
	var display := ctrl.npc.npc_name
	ctrl.npc.die()
	print("[VOX P4] DEATH: %s died of %s on day %d (age %d)"
		% [display, cause, day_number, roundi(ctrl.npc.age)])
	chat_ui.add_line("world", "[b]%s has died of %s.[/b]" % [display, cause])
	# Wave M: the pouch is inherited — coins, tools and all. The nearest
	# living villager takes up what the dead one carried.
	if not ctrl.npc.inventory.is_empty():
		var heir: NPCController = null
		var best_d := INF
		for other_id in controllers:
			var other: NPCController = controllers[other_id]
			if other == ctrl or other.npc.dead:
				continue
			var dist := NPCController._flat_dist(ctrl.npc.position,
				other.npc.position)
			if dist < best_d:
				best_d = dist
				heir = other
		if heir != null:
			var parts: Array = []
			for item in ctrl.npc.inventory:
				parts.append("%d %s" % [int(ctrl.npc.inventory[item]),
					tech.item_label(item)])
			heir.npc.add_items(ctrl.npc.inventory)
			ctrl.npc.inventory.clear()
			heir.emit_event("took up what %s left behind: %s"
				% [display, ", ".join(parts)])
	if cortex.online:
		cortex.send({"type": "died", "npc": ctrl.id, "cause": cause})
	controllers.erase(ctrl.id)
	if focused_id == ctrl.id:
		_focus_next()
	ctrl.queue_free()   # the body stays where it fell


func _gift_scan() -> void:
	## Settlement mutual aid: the fed share with the starving.
	for giver_id in controllers.keys():
		var giver: NPCController = controllers[giver_id]
		if giver.talking or not giver.npc.is_idle():
			continue
		var food_item := ""
		for item in giver.npc.inventory:
			if tech.is_food(item) and int(giver.npc.inventory[item]) >= 2:
				food_item = item
				break
		if food_item == "":
			continue
		for recv_id in controllers.keys():
			if recv_id == giver_id:
				continue
			var recv: NPCController = controllers[recv_id]
			if recv.npc.hunger < GIFT_HUNGER:
				continue
			var key := "gift:%s>%s" % [giver_id, recv_id]
			if _seen_cooldown.has(key):
				continue
			if NPCController._flat_dist(giver.npc.position, recv.npc.position) > GIFT_RADIUS:
				continue
			_seen_cooldown[key] = 90.0
			giver.npc.inventory[food_item] = int(giver.npc.inventory[food_item]) - 1
			recv.npc.add_items({food_item: 1})
			var line := "%s shares %s with %s" % [giver.npc.npc_name,
				tech.item_label(food_item), recv.npc.npc_name]
			print("[VOX P4] ", line)
			chat_ui.add_line("world", "[i]%s[/i]" % line)
			if cortex.online:
				cortex.send({"type": "social", "event": "gift",
					"from": giver_id, "to": recv_id, "item": food_item})
			break


func _unhandled_input(event: InputEvent) -> void:
	if not _started:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var from := cam.project_ray_origin(event.position)
		var dir := cam.project_ray_normal(event.position)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return
		var collider: Object = hit.get("collider")
		if collider is Area3D and collider.has_meta("npc"):
			var npc_id := str(collider.get_meta("npc"))
			var ctrl: NPCController = controllers.get(npc_id)
			if ctrl:
				focused_id = npc_id
				chat_ui.open_for(npc_id, ctrl.npc.npc_name)
		elif focused_id != "" and controllers.has(focused_id):
			controllers[focused_id].send_to(hit.position)
	elif event.is_action_pressed("focus_next"):
		_focus_next()
	elif event.is_action_pressed("toggle_autofocus"):
		autofocus = not autofocus
		chat_ui.add_line("system", "conversation auto-focus %s"
			% ("ON — the camera will jump to villagers who stop to talk"
				if autofocus else "off"))
	elif event.is_action_pressed("open_chat"):
		if focused_id != "" and controllers.has(focused_id):
			chat_ui.open_for(focused_id, controllers[focused_id].npc.npc_name)


# ---------------------------------------------------------------- orchestration
# (called by NPCControllers)

func tier_for(_ctrl: NPCController) -> String:
	# every villager runs on a full LLM mind, everywhere on the map — Cortex
	# dispatches decides concurrently so vLLM batches them. (The scripted tier
	# still exists in the protocol as the offline fallback and for tests.)
	return "full"


func nearby_npcs(ctrl: NPCController) -> Dictionary:
	var out := {}
	for other_id in controllers:
		if other_id == ctrl.id:
			continue
		var other: NPCController = controllers[other_id]
		if other.talking:
			continue
		var d := NPCController._flat_dist(ctrl.npc.position, other.npc.position)
		if d <= NEARBY_NPC_RADIUS:
			out[other_id] = snappedf(d, 0.1)
	return out


func controller_by_id(npc_id: String) -> NPCController:
	return controllers.get(npc_id)


func build_structure(builder_pos: Vector3, kind: String) -> bool:
	## Raise a hut in the village ring around the fire (falling back to the
	## builder's spot). The village visibly grows as the band learns shelter.
	var cfg: Dictionary = tech.buildables.get(kind, {})
	if cfg.is_empty():
		return false
	var min_fire := float(cfg.get("min_fire_distance", 4.0))
	var ring := float(cfg.get("ring_radius", 12.0))
	var home := nearest_fire(builder_pos)
	var spot := Vector3.ZERO
	var found := false
	for i in 40:
		var p := world.random_walkable_near(home.position, ring)
		if NPCController._flat_dist(p, home.position) < min_fire:
			continue
		if bool(cfg.get("needs_water", false)) and not _touches_water(p):
			continue   # a watermill needs a race — build on the bank
		var clear := true
		for s in structures:
			if NPCController._flat_dist(p, s.pos) < 3.0:
				clear = false
				break
		if clear:
			spot = p
			found = true
			break
	if not found:
		spot = builder_pos
	_place_structure(kind, spot)
	return true


func _touches_water(pos: Vector3) -> bool:
	## A cell counts as riverside/shore when water lies within 2 cells.
	var x := int(pos.x)
	var z := int(pos.z)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if world.is_water(x + dx, z + dz):
				return true
	return false


func station_speed_factor(kind: String) -> float:
	## Wave J: power structures speed a station's work (trip hammer -> smithy).
	var factor := 1.0
	for s in structures:
		var cfg: Dictionary = tech.buildables.get(s.type, {})
		if str(cfg.get("speeds_station", "")) == kind:
			factor *= float(cfg.get("speed_factor", 1.0))
	return factor


func _place_structure(kind: String, spot: Vector3) -> Dictionary:
	var cfg: Dictionary = tech.buildables.get(kind, {})
	if cortex != null:
		call_deferred("_send_village")   # new building — tell Cortex
	var node := AssetLib.instantiate("structures/" + kind)
	if node != null:
		AssetLib.fit(node, float(cfg.get("model_height", 2.4)))
	elif int(cfg.get("growth_days", 0)) > 0:
		node = _box_field()
	elif int(cfg.get("animal_capacity", 0)) > 0:
		node = _box_corral()
	elif bool(cfg.get("station", false)):
		node = _box_smelter()
	else:
		node = _box_hut()
	node.position = spot
	node.rotation.y = _rng.randf() * TAU
	add_child(node)
	var entry := {"type": kind, "pos": spot, "node": node,
		"warmth": float(cfg.get("warmth_radius", 0.0)),
		"capacity": int(cfg.get("capacity", 0)),
		"vermin_safe": bool(cfg.get("vermin_safe", true)),
		"store": {},
		"growth_days": int(cfg.get("growth_days", 0)),
		"planted": false, "growth": 0,
		"animal_cap": int(cfg.get("animal_capacity", 0)),
		"herd": {}}
	structures.append(entry)
	return entry


# ---------------------------------------------------------------- storage

func hut_count() -> int:
	var n := 0
	for s in structures:
		if float(s.warmth) > 0.0:
			n += 1
	return n


func nearest_storage(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in structures:
		if int(s.capacity) <= 0:
			continue
		var d := NPCController._flat_dist(pos, s.pos)
		if d < best_d:
			best_d = d
			best = s
	return best


func storage_state(pos: Vector3) -> Dictionary:
	var s := nearest_storage(pos)
	if s.is_empty():
		return {}
	var used := 0
	for item in s.store:
		used += int(s.store[item])
	return {"kind": str(s.type), "distance": snappedf(
		NPCController._flat_dist(pos, s.pos), 0.1),
		"space": maxi(0, int(s.capacity) - used), "holds": s.store.duplicate()}


func store_deposit(ctrl: NPCController, item: String) -> String:
	var s := nearest_storage(ctrl.npc.position)
	if s.is_empty():
		return ""
	var used := 0
	for it in s.store:
		used += int(s.store[it])
	# bank the surplus but keep a meal's worth in the pouch — nobody should
	# starve on the walk back from their own larder
	var keep := 2 if tech.is_food(item) else 0
	var amount := mini(int(ctrl.npc.inventory.get(item, 0)) - keep,
		maxi(0, int(s.capacity) - used))
	if amount <= 0:
		return ""
	ctrl.npc.inventory[item] = int(ctrl.npc.inventory[item]) - amount
	if int(ctrl.npc.inventory[item]) <= 0:
		ctrl.npc.inventory.erase(item)
	s.store[item] = int(s.store.get(item, 0)) + amount
	return "stored %d %s in the %s" % [amount, tech.item_label(item),
		str(tech.buildables.get(s.type, {}).get("label", s.type))]


func store_withdraw(ctrl: NPCController, item: String) -> String:
	var s := nearest_storage(ctrl.npc.position)
	if s.is_empty() or int(s.store.get(item, 0)) <= 0:
		return ""
	var amount := mini(int(tech.storage_cfg.get("withdraw_amount", 3)),
		int(s.store[item]))
	s.store[item] = int(s.store[item]) - amount
	if int(s.store[item]) <= 0:
		s.store.erase(item)
	ctrl.npc.add_items({item: amount})
	return "took %d %s from the %s" % [amount, tech.item_label(item),
		str(tech.buildables.get(s.type, {}).get("label", s.type))]


# ---------------------------------------------------------------- stations

func station_types() -> Array:
	## Built workshop types (smelter, ...) — campfires are tracked separately.
	var kinds := {}
	for s in structures:
		if bool(tech.buildables.get(s.type, {}).get("station", false)):
			kinds[s.type] = true
	return kinds.keys()


func nearest_station(kind: String, pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in structures:
		if str(s.type) != kind:
			continue
		var d := NPCController._flat_dist(pos, s.pos)
		if d < best_d:
			best_d = d
			best = s
	return best


# ---------------------------------------------------------------- herding

var dogs := 0   # village dogs: they keep the wolves honest near the fires
var oxen := 0   # draft oxen (E5.25) — Wave L's plow teams will want them


func nearest_corral(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in structures:
		if int(s.animal_cap) <= 0:
			continue
		var d := NPCController._flat_dist(pos, s.pos)
		if d < best_d:
			best_d = d
			best = s
	return best


func corral_state(pos: Vector3) -> Dictionary:
	var s := nearest_corral(pos)
	if s.is_empty():
		return {}
	var held := 0
	for kind in s.herd:
		held += int(s.herd[kind])
	return {"distance": snappedf(NPCController._flat_dist(pos, s.pos), 0.1),
		"herd": s.herd.duplicate(),
		"space": maxi(0, int(s.animal_cap) - held)}


func pen_animal(ctrl: NPCController, kind: String) -> String:
	## The trussed animal was consumed by the recipe; it joins the herd.
	var s := nearest_corral(ctrl.npc.position)
	if s.is_empty():
		return ""
	var held := 0
	for k in s.herd:
		held += int(s.herd[k])
	if held >= int(s.animal_cap):
		return ""
	s.herd[kind] = int(s.herd.get(kind, 0)) + 1
	return "loosed the %s inside the corral" % kind


func herd_take(ctrl: NPCController, kind: String) -> bool:
	var s := nearest_corral(ctrl.npc.position)
	if s.is_empty() or int(s.herd.get(kind, 0)) <= 0:
		return false
	s.herd[kind] = int(s.herd[kind]) - 1
	if int(s.herd[kind]) <= 0:
		s.herd.erase(kind)
	return true


func herd_has(pos: Vector3, kind: String) -> bool:
	var s := nearest_corral(pos)
	return not s.is_empty() and int(s.herd.get(kind, 0)) > 0


func _dawn_herds() -> void:
	## Penned animals breed: any species with a pair has a chance of young.
	for s in structures:
		if int(s.animal_cap) <= 0:
			continue
		var held := 0
		for k in s.herd:
			held += int(s.herd[k])
		var chance := float(tech.buildables.get(s.type, {}).get(
			"herd_growth_chance", 0.25))
		for kind in s.herd.keys():
			if int(s.herd[kind]) >= 2 and held < int(s.animal_cap) \
					and _rng.randf() < chance:
				s.herd[kind] = int(s.herd[kind]) + 1
				held += 1
				var line := "a young %s was born in the corral" % kind
				print("[VOX C] ", line)
				chat_ui.add_line("world", "[i]%s[/i]" % line)


# ---------------------------------------------------------------- farming

func farm_stats(pos: Vector3) -> Dictionary:
	## Field-plot census for the decide state: {} when the village has no fields.
	var plots := 0
	var empty := 0
	var growing := 0
	var ripe := 0
	var best_d := INF
	for s in structures:
		if int(s.growth_days) <= 0:
			continue
		plots += 1
		best_d = minf(best_d, NPCController._flat_dist(pos, s.pos))
		if not bool(s.planted):
			empty += 1
		elif int(s.growth) >= int(s.growth_days):
			ripe += 1
		else:
			growing += 1
	if plots == 0:
		return {}
	return {"plots": plots, "empty": empty, "growing": growing, "ripe": ripe,
		"distance": snappedf(best_d, 0.1)}


func farm_sow(ctrl: NPCController) -> String:
	## Seed goes into the nearest bare plot (the recipe consumed the seed grain).
	if season_name() == "winter":
		return ""   # the ground is frozen
	for s in _fields_by_distance(ctrl.npc.position):
		if not bool(s.planted):
			s.planted = true
			s.growth = 0
			return "sowed seed grain in the tilled earth"
	return ""


func farm_harvest(ctrl: NPCController) -> String:
	## Cut the nearest ripe plot; the field goes back to bare, ready to re-sow.
	for s in _fields_by_distance(ctrl.npc.position):
		if bool(s.planted) and int(s.growth) >= int(s.growth_days):
			s.planted = false
			s.growth = 0
			var yields: Dictionary = tech.buildables.get(s.type, {}).get(
				"harvest_yield", {"grain": 4})
			# a sickle (E5.08) cuts cleaner: +50% grain
			var bonus := 1.5 if int(ctrl.npc.inventory.get("sickle", 0)) > 0 else 1.0
			var got := {}
			for item in yields:
				got[item] = maxi(1, roundi(int(yields[item]) * bonus))
			ctrl.npc.add_items(got)
			var parts: Array = []
			for item in got:
				parts.append("%d %s" % [got[item], tech.item_label(item)])
			return "cut and gathered the ripe grain: " + ", ".join(parts)
	return ""


func farm_work_spot(pos: Vector3, want_ripe: bool) -> Vector3:
	## Where to stand for the next sow (bare plot) or harvest (ripe plot).
	for s in _fields_by_distance(pos):
		var ripe: bool = bool(s.planted) and int(s.growth) >= int(s.growth_days)
		if want_ripe and ripe:
			return s.pos
		if not want_ripe and not bool(s.planted):
			return s.pos
	return Vector3.INF


func _fields_by_distance(pos: Vector3) -> Array:
	var fields: Array = []
	for s in structures:
		if int(s.growth_days) > 0:
			fields.append(s)
	fields.sort_custom(func(a, b) -> bool:
		return NPCController._flat_dist(pos, a.pos) < NPCController._flat_dist(pos, b.pos))
	return fields


func _dawn_fields() -> void:
	## Crops grow a step each dawn; winter frost kills whatever stands.
	for s in structures:
		if int(s.growth_days) <= 0 or not bool(s.planted):
			continue
		if season_name() == "winter":
			s.planted = false
			s.growth = 0
			var line := "frost killed the crops in a field plot"
			print("[VOX B] ", line)
			chat_ui.add_line("world", "[i]%s[/i]" % line)
		elif int(s.growth) < int(s.growth_days):
			s.growth = int(s.growth) + 1
			if int(s.growth) >= int(s.growth_days):
				print("[VOX B] a field plot is ripe for harvest")


func _box_field() -> Node3D:
	# fallback art: a low square of tilled dark earth
	var plot := Node3D.new()
	var soil := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.6, 0.12, 2.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.19, 0.11)
	mesh.material = mat
	soil.mesh = mesh
	soil.position.y = 0.06
	plot.add_child(soil)
	return plot


func _box_smelter() -> Node3D:
	# fallback art: a squat clay furnace with a dark mouth
	var smelter := Node3D.new()
	var clay_c := Color(0.62, 0.42, 0.28)
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.7
	mesh.height = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = clay_c
	mesh.material = mat
	body.mesh = mesh
	body.position.y = 0.75
	smelter.add_child(body)
	var mouth := MeshInstance3D.new()
	var mmesh := BoxMesh.new()
	mmesh.size = Vector3(0.3, 0.35, 0.2)
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.08, 0.05, 0.04)
	mmesh.material = mmat
	mouth.mesh = mmesh
	mouth.position = Vector3(0, 0.3, 0.62)
	smelter.add_child(mouth)
	return smelter


func _box_corral() -> Node3D:
	# fallback art: a ring of fence posts with a top rail
	var corral := Node3D.new()
	var wood := Color(0.42, 0.30, 0.16)
	for i in 10:
		var ang := TAU * i / 10.0
		var post := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.12, 1.0, 0.12)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = wood
		pmesh.material = mat
		post.mesh = pmesh
		post.position = Vector3(cos(ang) * 1.6, 0.5, sin(ang) * 1.6)
		corral.add_child(post)
		var rail := MeshInstance3D.new()
		var rmesh := BoxMesh.new()
		rmesh.size = Vector3(0.08, 0.08, 1.05)
		rmesh.material = mat
		rail.mesh = rmesh
		rail.position = Vector3(cos(ang + TAU / 20.0) * 1.6, 0.85,
			sin(ang + TAU / 20.0) * 1.6)
		rail.rotation.y = -ang - TAU / 20.0 + PI / 2.0
		corral.add_child(rail)
	return corral


func _box_hut() -> Node3D:
	# fallback art: a lean-to cone of branches
	var hut := Node3D.new()
	for i in 8:
		var ang := TAU * i / 8.0
		var pole := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.14, 2.4, 0.14)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.24, 0.13)
		mesh.material = mat
		pole.mesh = mesh
		pole.position = Vector3(cos(ang) * 0.75, 1.0, sin(ang) * 0.75)
		pole.rotation = Vector3(cos(ang) * 0.5, 0, sin(ang) * -0.5)
		hut.add_child(pole)
	return hut


func request_converse(a: NPCController, b: NPCController) -> void:
	if a.talking or b.talking or not cortex.online:
		a._finish_goal()   # target got busy — drop the talk goal cleanly
		a.wander()
		return
	a.begin_converse(b)
	b.begin_converse(a)
	print("[VOX P3] %s and %s stop to talk" % [a.npc.npc_name, b.npc.npc_name])
	_autofocus_converse(a, b)
	cortex.send({"type": "converse", "a": a.id, "b": b.id,
		"inv_a": a.npc.inventory, "inv_b": b.npc.inventory})


# ---------------------------------------------------------------- perception

func _perception_scan() -> void:
	var ids := controllers.keys()
	for i in ids.size():
		for j in ids.size():
			if i == j:
				continue
			var actor: NPCController = controllers[ids[i]]
			var observer: NPCController = controllers[ids[j]]
			if not actor.npc.is_working():
				continue
			var key := "%s>%s" % [ids[j], ids[i]]
			if _seen_cooldown.has(key):
				continue
			var d := NPCController._flat_dist(actor.npc.position, observer.npc.position)
			if d > PERCEPTION_RADIUS:
				continue
			_seen_cooldown[key] = PERCEPTION_COOLDOWN
			if cortex.online:
				cortex.send({"type": "event", "npc": observer.id,
					"text": "saw %s %s" % [actor.npc.npc_name, actor.activity]})


# ---------------------------------------------------------------- cortex

func _setup_cortex() -> void:
	cortex = CortexClient.new()
	add_child(cortex)
	chat_ui = ChatUI.new()
	add_child(chat_ui)
	cortex.cortex_connected.connect(func() -> void:
		chat_ui.set_status("Cortex: online")
		cortex.send({"type": "hello", "world": "vox", "flavor": flavor}))
	cortex.cortex_disconnected.connect(func() -> void:
		chat_ui.set_status("Cortex: offline — local fallback"))
	cortex.status_received.connect(func(text: String) -> void:
		chat_ui.set_status("Cortex: " + text))
	cortex.roster_received.connect(_spawn_roster)
	cortex.say_received.connect(_on_say)
	cortex.action_received.connect(_on_action)
	cortex.learned_received.connect(_on_learned)
	cortex.trade_received.connect(_on_trade)
	cortex.skill_received.connect(_on_skill)
	cortex.council_end_received.connect(_on_council_end)
	cortex.converse_end_received.connect(_on_converse_end)
	cortex.era_received.connect(_on_era)
	cortex.born_received.connect(_on_born)
	chat_ui.message_submitted.connect(_on_chat_submitted)


func _spawn_roster(npcs: Array, roster_flavor := "vanilla") -> void:
	if _roster_spawned or npcs.is_empty():
		return
	if roster_flavor != flavor:
		return   # stale roster from before the flavor handshake — wait for ours
	_roster_spawned = true
	for entry in npcs:
		var npc_id := str(entry.get("id", ""))
		var display := str(entry.get("name", npc_id.capitalize()))
		if npc_id == "" or controllers.has(npc_id):
			continue
		brains[npc_id] = str(entry.get("brain", "?"))
		var center := _village_anchor(str(entry.get("village", "")))
		var saved: Dictionary = _pending_save.get("npcs", {}).get(npc_id, {})
		if not saved.is_empty():
			# a returning villager: body restored exactly where life left off
			var body := _spawn_body(npc_id, display,
				Vector3(float(saved.x), float(saved.y), float(saved.z)))
			body.age = float(saved.get("age", 25))
			body.lifespan = float(saved.get("lifespan", body.lifespan))
			body.hunger = float(saved.get("hunger", body.hunger))
			body.energy = float(saved.get("energy", body.energy))
			body.health = float(saved.get("health", 100))
			body.inventory = saved.get("inventory", {})
			body.scale = Vector3.ONE * (0.7 if body.age
				< float(tech.lifecycle.get("adult_age", 14)) else 1.0)
			continue
		var npc := _spawn_body(npc_id, display, _connected_spot_near(center, 22.0))
		npc.age = _rng.randf_range(float(tech.lifecycle.get("founder_age_min", 16)),
			float(tech.lifecycle.get("founder_age_max", 45)))
	if not _pending_save.is_empty():
		_total_spawned = int(_pending_save.get("counters", {}).get("total",
			controllers.size()))
		_pending_save.clear()
	else:
		_total_spawned = controllers.size()
	_pop_cap = maxi(_pop_cap, maxi(controllers.size(), 3))
	if focused_id == "":
		focused_id = str(npcs[0].get("id", ""))
	print("[VOX P4] village spawned (%s): %d NPCs (%s)" % [flavor,
		controllers.size(), ", ".join(controllers.keys())])


func _village_anchor(village: String) -> Vector3:
	## Which fire a villager belongs to. Villages are assigned to fires in
	## order of first appearance; no village name -> the primary fire.
	if village == "":
		return campfire.position
	if not village_fires.has(village):
		var idx := village_fires.size()
		village_fires[village] = campfires[mini(idx, campfires.size() - 1)]
		print("[VOX P8] village '%s' settles at fire %d" % [village,
			mini(idx, campfires.size() - 1)])
	return (village_fires[village] as Campfire).position


func _connected_spot_near(center: Vector3, radius: float) -> Vector3:
	## A walkable cell that can actually PATH to the anchor point — rivers and
	## steep terrain fragment the walk graph, and nobody spawns stranded.
	for i in 12:
		var p := world.random_walkable_near(center, radius)
		if world.find_path(center, p).size() > 1 or p.distance_to(center) < 2.0:
			return p
	return center + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))


func _spawn_body(npc_id: String, display: String, pos: Vector3) -> NPC:
	var npc := NPC.new()
	npc.npc_id = npc_id
	npc.npc_name = display
	add_child(npc)
	npc.position = pos
	npc.set_needs_cfg(tech.needs_cfg)
	npc.hunger = _rng.randf_range(15.0, 45.0)
	npc.lifespan = _rng.randfn(float(tech.lifecycle.get("lifespan_mean", 62)),
		float(tech.lifecycle.get("lifespan_jitter", 10)))
	var ctrl := NPCController.new()
	add_child(ctrl)
	ctrl.setup(npc_id, npc, world, field, tech, cortex, chat_ui, self)
	ctrl.path_changed.connect(_on_path_changed)
	controllers[npc_id] = ctrl
	return npc


func _on_say(npc_id: String, text: String) -> void:
	var ctrl: NPCController = controllers.get(npc_id)
	if ctrl:
		ctrl.enqueue_say(text)


func _on_action(npc_id: String, data: Dictionary) -> void:
	var ctrl: NPCController = controllers.get(npc_id)
	if ctrl == null:
		return
	print("[VOX P3] %s decided: %s %s" % [ctrl.npc.npc_name,
		str(data.get("action", "")), str(data.get("target", ""))])
	if data.has("learned"):
		_on_learned(data.get("learned"))
	ctrl.handle_action(data)


func _on_skill(data: Dictionary) -> void:
	## Voyager-style routines: composed alone or passed on at the fire.
	var ctrl: NPCController = controllers.get(str(data.get("npc", "")))
	var who := ctrl.npc.npc_name if ctrl else str(data.get("npc", ""))
	var skill_name := str(data.get("name", "")).replace("_", " ")
	var line: String
	if str(data.get("from", "")) == "practice":
		line = "*** %s worked out a routine of their own: %s ***" % [who, skill_name]
	else:
		var teacher: NPCController = controllers.get(str(data.get("from", "")))
		var t_name := teacher.npc.npc_name if teacher else str(data.get("from", ""))
		line = "*** %s picked up the %s routine from %s ***" % [who, skill_name, t_name]
	print("[VOX SKILL] ", line)
	chat_ui.add_line("world", "[b]%s[/b]" % line)


func _on_trade(data: Dictionary) -> void:
	## Wave F barter: Cortex proposed a swap during a conversation — the goods
	## live here, so the engine moves them (re-checking both pouches first).
	var a: NPCController = controllers.get(str(data.get("a", "")))
	var b: NPCController = controllers.get(str(data.get("b", "")))
	var give := str(data.get("give", ""))
	var take := str(data.get("take", ""))
	var give_n := maxi(1, int(data.get("give_n", 1)))
	var take_n := maxi(1, int(data.get("take_n", 1)))
	if a == null or b == null or give == "" or take == "":
		return
	if int(a.npc.inventory.get(give, 0)) < give_n \
			or int(b.npc.inventory.get(take, 0)) < take_n:
		return   # the goods were eaten/spent since the converse began
	a.npc.inventory[give] = int(a.npc.inventory[give]) - give_n
	if int(a.npc.inventory[give]) <= 0:
		a.npc.inventory.erase(give)
	b.npc.inventory[take] = int(b.npc.inventory[take]) - take_n
	if int(b.npc.inventory[take]) <= 0:
		b.npc.inventory.erase(take)
	a.npc.add_items({take: take_n})
	b.npc.add_items({give: give_n})
	var line := "%s traded %d %s for %s's %d %s" % [a.npc.npc_name,
		give_n, tech.item_label(give), b.npc.npc_name, take_n,
		tech.item_label(take)]
	print("[VOX F] TRADE: ", line)
	chat_ui.add_line("world", "[i]%s[/i]" % line)


func _on_learned(data: Dictionary) -> void:
	_tech_exchanges += 1
	var learner: NPCController = controllers.get(str(data.get("npc", "")))
	var learner_name := learner.npc.npc_name if learner else str(data.get("npc", ""))
	var tech_name := str(data.get("tech_name", data.get("tech", "")))
	var line: String
	if str(data.get("from", "")) == "insight":
		line = "*** %s DISCOVERED %s ***" % [learner_name, tech_name]
		print("[VOX P5] TECH DISCOVERED: ", line)
	elif str(data.get("from", "")) == "practice":
		line = "*** %s MASTERED %s through seasons of practice ***" % [
			learner_name, tech_name]
		print("[VOX B] TECH MASTERED: ", line)
	else:
		var teacher: NPCController = controllers.get(str(data.get("from", "")))
		var teacher_name := teacher.npc.npc_name if teacher else str(data.get("from", ""))
		line = "*** %s learned %s from %s ***" % [learner_name, tech_name, teacher_name]
		print("[VOX P3] TECH EXCHANGED: ", line)
	chat_ui.add_line("world", "[b]%s[/b]" % line)


func _on_era(era: int, p_era_name: String) -> void:
	era_name = p_era_name
	var banner := "========  THE BAND HAS ENTERED THE %s (era %d)  ========" \
		% [p_era_name.to_upper(), era]
	print("[VOX P5] ERA TRANSITION: ", banner)
	chat_ui.add_line("world", "[b]%s[/b]" % banner)


func _on_converse_end(a: String, b: String) -> void:
	for npc_id in [a, b]:
		var ctrl: NPCController = controllers.get(npc_id)
		if ctrl:
			ctrl.end_converse()


func _on_chat_submitted(text: String) -> void:
	var target := chat_ui.target_id if chat_ui.target_id != "" else focused_id
	var ctrl: NPCController = controllers.get(target)
	if ctrl == null:
		return
	chat_ui.add_line("You (to %s)" % ctrl.npc.npc_name, text)
	if cortex.online:
		cortex.send({"type": "chat", "npc": target, "text": text,
			"state": ctrl.build_state()})
	else:
		chat_ui.add_line("system", "Cortex offline — start it: cd cortex && python -m cortex")


# ---------------------------------------------------------------- focus & path line

var autofocus := false             # camera jumps to conversations (toggle key)
var _autofocus_t := -999.0         # last jump, for the anti-ping-pong cooldown
const AUTOFOCUS_COOLDOWN := 10.0   # a second conversation elsewhere waits


func _autofocus_converse(a: NPCController, b: NPCController) -> void:
	## Fly the camera to a conversation that just started — but never hop
	## between simultaneous conversations more than once per cooldown.
	if not autofocus:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _autofocus_t < AUTOFOCUS_COOLDOWN:
		return
	_autofocus_t = now
	cam_rig.position = (a.npc.position + b.npc.position) * 0.5
	focused_id = a.id   # HUD follows one of the speakers
	_update_path_line(PackedVector3Array())


func _focus_next() -> void:
	var ids := controllers.keys()
	if ids.is_empty():
		focused_id = ""
		return
	var i := ids.find(focused_id)
	focused_id = ids[(i + 1) % ids.size()]
	cam_rig.position = controllers[focused_id].npc.position
	_update_path_line(PackedVector3Array())


func _on_path_changed(npc_id: String, path: PackedVector3Array) -> void:
	if npc_id == focused_id:
		_update_path_line(path)


# ---------------------------------------------------------------- setup

func _setup_environment() -> void:
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, -35, 0)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	add_child(_sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.80)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky_mat.ground_bottom_color = Color(0.25, 0.30, 0.35)
	sky_mat.ground_horizon_color = Color(0.72, 0.80, 0.88)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _setup_camera() -> void:
	cam_rig = OrbitCamera.new()
	add_child(cam_rig)
	cam_rig.position = world.find_spawn()


func _setup_path_line() -> void:
	_line_mesh = ImmediateMesh.new()
	path_line = MeshInstance3D.new()
	path_line.mesh = _line_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	mat.no_depth_test = true
	path_line.material_override = mat
	add_child(path_line)


func _update_path_line(path: PackedVector3Array) -> void:
	_line_mesh.clear_surfaces()
	if path.size() < 2:
		return
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in path:
		_line_mesh.surface_add_vertex(p + Vector3(0, 0.4, 0))
	_line_mesh.surface_end()


func _setup_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var label := Label.new()
	var pan_keys := "%s%s%s%s" % [InputConfig.binding_label("pan_forward"),
		InputConfig.binding_label("pan_left"), InputConfig.binding_label("pan_back"),
		InputConfig.binding_label("pan_right")]
	label.text = ("VOX P6   -   LMB: order focused NPC / click an NPC to chat   -   "
		+ ("%s: next NPC   -   %s: chat   -   %s: auto-focus talks   -   "
			+ "RMB drag: orbit   -   Wheel: zoom   -   %s: pan")
		% [InputConfig.binding_label("focus_next"), InputConfig.binding_label("open_chat"),
			InputConfig.binding_label("toggle_autofocus"), pan_keys])
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(label)

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -300.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	ui.add_child(panel)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 14)
	panel.add_child(_hud)


func _update_hud() -> void:
	var ctrl: NPCController = controllers.get(focused_id)
	if ctrl == null:
		_hud.text = "no NPC focused"
		return
	var npc := ctrl.npc
	var carried: Array = []
	for item in npc.inventory:
		carried.append("%d %s" % [int(npc.inventory[item]), tech.item_label(item)])
	_hud.text = "%s\nDay %d, %s (%s)   ·   fire %d%%%s\n\n%s, %d summers  (%s tier)   [%s: next]\nMind: %s\nHunger  %s %d\nEnergy  %s %d\nHealth  %s %d\nCarrying: %s\nDoing: %s\n\nVillage: %d alive (%d born, %d dead) · %d techs learned" % [
		era_name,
		day_number, time_of_day(), season_name(),
		roundi(campfire.fuel), "" if campfire.is_lit() else " (COLD)",
		npc.npc_name, roundi(npc.age), tier_for(ctrl),
		InputConfig.binding_label("focus_next"),
		str(brains.get(focused_id, "?")),
		_bar(npc.hunger), roundi(npc.hunger),
		_bar(npc.energy), roundi(npc.energy),
		_bar(npc.health), roundi(npc.health),
		", ".join(carried) if not carried.is_empty() else "nothing",
		ctrl.activity,
		controllers.size(), _births, _deaths, _tech_exchanges,
	]


func _bar(v: float) -> String:
	var filled := roundi(v / 10.0)
	return "#".repeat(filled) + "-".repeat(10 - filled)


# ---------------------------------------------------------------- self test

func _self_test() -> void:
	var from := world.find_spawn()
	var to := world.random_walkable_near(from, 40.0)
	var path := world.find_path(from, to)
	print("[VOX P3] test path: %d waypoints" % path.size())
	if path.size() > 1:
		print("[VOX P3] PATHFINDING OK")
	else:
		push_warning("[VOX P3] pathfinding self-test found no path")

	if not tech.ok:
		push_warning("[VOX P3] tech data failed to load — crafting disabled")
		return
	print("[VOX P3] tech data: %d nodes, %d recipes, %d resource types, %d items"
		% [tech.nodes.size(), tech.recipes.size(), tech.resources.size(), tech.items.size()])

	var inv := {"flint": 1, "hammerstone": 1}
	var recipe: Dictionary = tech.recipes["knap_flake"]
	var st := tech.recipe_status(recipe, inv)
	if st.ready:
		tech.apply_recipe(recipe, inv)
	if int(inv.get("stone_flake", 0)) == 2 and not inv.has("flint"):
		print("[VOX P3] CRAFT ENGINE OK")
	else:
		push_warning("[VOX P3] craft self-test failed: %s" % [inv])

	if field.nearest("flint_nodule", from).is_empty():
		push_warning("[VOX P3] no flint nodules spawned")
	else:
		print("[VOX P3] RESOURCE FIELD OK")
