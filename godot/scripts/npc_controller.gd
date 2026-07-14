class_name NPCController
extends Node
## Brain-body loop for ONE NPC: wander/decide timer, goal executor
## (gather/craft/eat/talk), say queue, events to Cortex. Main owns the roster,
## message routing, perception, tiering, and converse coordination.

signal path_changed(id: String, path: PackedVector3Array)

const STARVING_REFLEX := 85.0   # hunger level where the body eats on its own
const WANDER_MIN := 2.0    # gap between finishing something and next decide
const WANDER_MAX := 5.0    # -> an LLM-driven choice roughly every 5-15s
const TALK_RANGE := 3.0
const SAY_SPACING := 2.8

var id := ""
var npc: NPC
var world: VoxelWorld
var field: ResourceField
var tech: TechData
var cortex: CortexClient
var chat_ui: ChatUI
var main: Node                     # orchestrator: tier_for(), nearby_npcs(), request_converse()

var activity := "standing around"
var talking := false

var _goal := {}                    # {"type","target","stage","gather_type","entry"}
var _wander_timer := 2.0
var _awaiting := false
var _decide_timeout := 0.0
var _talk_target: NPCController = null
var _talk_repaths := 0
var _talk_safety := 0.0
var _talk_ending := false
var _say_queue: Array[String] = []
var _say_t := 0.0


func setup(p_id: String, p_npc: NPC, p_world: VoxelWorld, p_field: ResourceField,
		p_tech: TechData, p_cortex: CortexClient, p_chat: ChatUI, p_main: Node) -> void:
	id = p_id
	npc = p_npc
	world = p_world
	field = p_field
	tech = p_tech
	cortex = p_cortex
	chat_ui = p_chat
	main = p_main
	_wander_timer = randf_range(1.0, WANDER_MAX)
	npc.arrived.connect(_on_arrived)
	npc.work_done.connect(_on_work_done)


func _process(delta: float) -> void:
	if npc == null:
		return
	npc.wrapped = _has_warmth_item()
	# paced speech while in a conversation
	if not _say_queue.is_empty():
		_say_t -= delta
		if _say_t <= 0.0:
			_say_t = SAY_SPACING
			npc.say(_say_queue.pop_front())
	if talking:
		_talk_safety -= delta
		if (_talk_ending and _say_queue.is_empty()) or _talk_safety <= 0.0:
			talking = false
			_talk_ending = false
			activity = "standing around"
			_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)
		return
	# body before mind: a starving body eats what it holds. A reflex like
	# fleeing — not knowledge, so even blank emergent minds don't starve
	# with a full pouch. Everything else (cooking, fire, foraging) stays
	# with the mind.
	if npc.hunger >= STARVING_REFLEX and not npc.dead \
			and str(_goal.get("stage", "")) != "eating":
		for item in npc.inventory:
			if int(npc.inventory[item]) > 0 and tech.is_food(item):
				_release_claim()
				do_eat(item)
				return
	if _awaiting:
		_decide_timeout -= delta
		if _decide_timeout <= 0.0:
			_awaiting = false
		return
	if npc.is_idle() and _goal.is_empty():
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)
			if cortex.online:
				cortex.send({"type": "decide", "npc": id, "state": build_state(),
					"tier": main.tier_for(self)})
				_awaiting = true
				_decide_timeout = 20.0
			else:
				_offline_fallback()


# ---------------------------------------------------------------- state

func build_state() -> Dictionary:
	var state := {
		"pos": [snappedf(npc.position.x, 0.1), snappedf(npc.position.y, 0.1),
			snappedf(npc.position.z, 0.1)],
		"time_of_day": main.time_of_day(),
		"season": main.season_name(),
		"day": main.day_number,
		"activity": activity,
		"needs": {"hunger": roundi(npc.hunger), "energy": roundi(npc.energy),
			"health": roundi(npc.health)},
		"inventory": npc.inventory.duplicate(),
		"nearby": field.distances(npc.position),
		"nearby_npcs": main.nearby_npcs(self),
		"huts": main.hut_count(),
		"population": main.controllers.size(),
		"dogs": main.dogs,
	}
	if not npc.warm and not npc.wrapped \
			and (npc.night or main.season_name() == "winter"):
		state["cold"] = true
	var fire: Dictionary = main.fire_state(npc.position)
	if not fire.is_empty():
		state["fire"] = fire
	var storage: Dictionary = main.storage_state(npc.position)
	if not storage.is_empty():
		state["storage"] = storage
	var fields: Dictionary = main.farm_stats(npc.position)
	if not fields.is_empty():
		state["fields"] = fields
	var corral: Dictionary = main.corral_state(npc.position)
	if not corral.is_empty():
		state["corral"] = corral
	var shops: Array = main.station_types()
	if not shops.is_empty():
		state["stations"] = shops
	var village: Array = main.structure_kinds()
	if not village.is_empty():
		state["village"] = village
	return state


func _offline_fallback() -> void:
	if npc.hunger >= 80.0:
		for item in npc.inventory:
			if tech.is_food(item):
				do_eat(item)
				return
	wander()


# ---------------------------------------------------------------- actions

func handle_action(data: Dictionary) -> void:
	_awaiting = false
	if str(_goal.get("stage", "")) == "eating":
		return   # the starving-body reflex outranks whatever the mind decided
	_release_claim()   # any new decision abandons the previously claimed prop
	_skill_queue.clear()
	_skill_name = ""
	var say_text := str(data.get("say", ""))
	if say_text != "":
		enqueue_say(say_text)
	var target := str(data.get("target", ""))
	match str(data.get("action", "wander")):
		"wander":
			wander()
		"idle":
			activity = "resting"
			_wander_timer = randf_range(5.0, 10.0)
		"say":
			_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)
		"gather":
			_start_goal({"type": "gather", "target": target, "stage": ""})
		"craft":
			_start_goal({"type": "craft", "target": target, "stage": ""})
		"eat":
			do_eat(target)
		"talk":
			_start_talk(target)
		"rest":
			_start_rest()
		"deposit", "withdraw":
			_start_store_goal(str(data.get("action")), target)
		"skill":
			var steps: Array = data.get("steps", [])
			if steps.is_empty():
				wander()
			else:
				_skill_queue = steps.duplicate()
				_skill_name = target
				_skill_total = steps.size()
				emit_event("set about their %s routine"
					% _skill_name.replace("_", " "))
				_next_skill_step()
		"experiment":
			var tech_name := str(data.get("learned", {}).get("tech_name", "something new"))
			_goal = {"type": "experiment", "target": tech_name, "stage": "experimenting"}
			activity = "experimenting — eyes alight"
			npc.begin_work(5.0)


func enqueue_say(text: String) -> void:
	if text.strip_edges() == "":
		return
	chat_ui.add_line(npc.npc_name, text)
	if talking or not _say_queue.is_empty():
		_say_queue.append(text)
	else:
		npc.say(text)


func wander() -> void:
	activity = "wandering"
	var target := world.random_walkable_near(npc.position, 24.0)
	var path := world.find_path(npc.position, target)
	if path.size() > 1:
		npc.set_path(path)
		path_changed.emit(id, path)


func _start_store_goal(kind: String, target: String) -> void:
	var storage: Dictionary = main.nearest_storage(npc.position)
	if storage.is_empty():
		_fail_goal("has nowhere to store things")
		return
	_goal = {"type": kind, "target": target, "stage": "store_walk"}
	activity = "carrying things to the %s" % str(storage.type)
	var path := world.find_path(npc.position, storage.pos)
	if _flat_dist(npc.position, storage.pos) < 2.0:
		_do_store_transfer()
	elif path.size() > 1:
		npc.set_path(path)
		path_changed.emit(id, path)
	else:
		_fail_goal("could not reach the store")


# ---------------------------------------------------------------- skill routines
# Voyager-style macro-actions: Cortex sends the routine's steps with the
# action; the body runs them in order and reports how it went.

var _skill_queue: Array = []
var _skill_name := ""
var _skill_total := 0


func _next_skill_step() -> void:
	if _skill_queue.is_empty():
		if _skill_name != "":
			emit_event("finished their %s routine" % _skill_name.replace("_", " "))
			_skill_name = ""
		return
	var step: Dictionary = _skill_queue.pop_front()
	var target := str(step.get("target", ""))
	match str(step.get("action", "")):
		"gather":
			_start_goal({"type": "gather", "target": target, "stage": ""})
		"craft":
			_start_goal({"type": "craft", "target": target, "stage": ""})
		"eat":
			do_eat(target)
		"deposit", "withdraw":
			_start_store_goal(str(step.get("action")), target)
		_:
			_next_skill_step()   # unknown step — skip it


func _abort_skill(reason: String) -> void:
	if _skill_name == "":
		return
	_skill_queue.clear()
	emit_event("gave up on their %s routine (%s)"
		% [_skill_name.replace("_", " "), reason])
	_skill_name = ""


func _release_claim() -> void:
	var entry: Variant = _goal.get("entry")
	if entry is Dictionary:
		entry["claim_t"] = -INF


func send_to(pos: Vector3) -> void:
	# player order overrides the current goal
	_release_claim()
	_goal.clear()
	activity = "going where the visitor pointed"
	var path := world.find_path(npc.position, pos)
	if path.size() > 1:
		npc.set_path(path)
		path_changed.emit(id, path)
		_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)


# ---------------------------------------------------------------- talk goal

func _start_talk(other_id: String) -> void:
	var other: NPCController = main.controller_by_id(other_id)
	if other == null or other.talking:
		wander()
		return
	_goal = {"type": "talk", "target": other_id, "stage": "talk_walk"}
	_talk_target = other
	_talk_repaths = 0
	activity = "going to talk with %s" % other.npc.npc_name
	_walk_toward_talk_target()


func _walk_toward_talk_target() -> void:
	if _talk_target == null:
		_finish_goal()
		return
	var d := _flat_dist(npc.position, _talk_target.npc.position)
	if d <= TALK_RANGE:
		main.request_converse(self, _talk_target)
		return
	var path := world.find_path(npc.position, _talk_target.npc.position)
	if path.size() < 2:
		_fail_goal("could not reach %s" % _talk_target.npc.npc_name)
		return
	npc.set_path(path)
	path_changed.emit(id, path)


func begin_council(spot: Vector3) -> void:
	## Dawn assembly: drop everything, walk to the fire ring, listen and speak.
	_release_claim()
	_skill_queue.clear()
	_skill_name = ""
	_goal.clear()
	_talk_target = null
	talking = true
	_talk_ending = false
	_talk_safety = 75.0   # councils end via council_end; this is the failsafe
	activity = "at the dawn council"
	var path := world.find_path(npc.position, spot)
	if path.size() > 1:
		npc.set_path(path)
		path_changed.emit(id, path)


func end_council() -> void:
	talking = false
	_talk_ending = false
	activity = "standing around"
	_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)


func begin_converse(other: NPCController) -> void:
	## Called by main on BOTH participants when a converse starts.
	_release_claim()
	_skill_queue.clear()
	_skill_name = ""
	_goal.clear()
	npc.stop()
	talking = true
	_talk_ending = false
	_talk_safety = 60.0
	activity = "talking with %s" % other.npc.npc_name
	# face each other
	var to_other := other.npc.position - npc.position
	if Vector2(to_other.x, to_other.z).length() > 0.01:
		npc.rotation.y = atan2(to_other.x, to_other.z)


func end_converse() -> void:
	_talk_ending = true
	_talk_target = null


func flee_from(threat_pos: Vector3) -> void:
	_release_claim()   # dropped everything — the bush is up for grabs again
	_abort_skill("a wolf")
	## Predator too close: drop everything and run for the fire.
	if talking or npc.dead:
		return
	if str(_goal.get("type", "")) == "flee":
		return
	_goal = {"type": "flee", "stage": "fleeing"}
	_talk_target = null
	activity = "fleeing a wolf!"
	npc.say("Wolf!")
	emit_event("fled from a wolf")
	var path := world.find_path(npc.position, main.nearest_fire(npc.position).position)
	if path.size() > 1:
		npc.set_path(path)
		path_changed.emit(id, path)
	else:
		_finish_goal()


# ---------------------------------------------------------------- rest goal

func _start_rest() -> void:
	var fire: Campfire = main.nearest_fire(npc.position)
	if fire == null or NPCController._flat_dist(npc.position, fire.position) <= fire.warmth_radius:
		_rest_here()
		return
	var spot := world.random_walkable_near(fire.position, fire.warmth_radius - 1.5)
	var path := world.find_path(npc.position, spot)
	if path.size() < 2:
		_rest_here()
		return
	_goal = {"type": "rest", "stage": "rest_walk"}
	activity = "heading to the fire to rest"
	npc.set_path(path)
	path_changed.emit(id, path)


func _rest_here() -> void:
	_goal.clear()
	activity = "resting by the fire" if main.campfire != null else "resting"
	_wander_timer = randf_range(8.0, 15.0)


# ---------------------------------------------------------------- goal executor

func _start_goal(goal: Dictionary) -> void:
	_goal = goal
	_advance_goal()


func _advance_goal() -> void:
	if _goal.is_empty():
		return
	match str(_goal.type):
		"gather":
			_goal_gather(str(_goal.target))
		"craft":
			_goal_craft()
		"talk":
			_walk_toward_talk_target()
		_:
			_finish_goal()


func _goal_gather(rtype: String) -> void:
	var candidates := field.nearest_candidates(rtype, npc.position, 4)
	if candidates.is_empty():
		_fail_goal("could not find any %s nearby" % _res_label(rtype))
		return
	for entry in candidates:
		_goal["gather_type"] = rtype
		_goal["entry"] = entry
		if _flat_dist(npc.position, entry.pos) < 1.6:
			entry["claim_t"] = Time.get_ticks_msec() / 1000.0
			_begin_gather_work()
			return
		var path := world.find_path(npc.position, entry.pos)
		if path.size() > 1:
			entry["claim_t"] = Time.get_ticks_msec() / 1000.0
			_goal["stage"] = "gather_walk"
			activity = "walking to a %s" % _res_label(rtype)
			npc.set_path(path)
			path_changed.emit(id, path)
			return
	_fail_goal("could not reach any %s" % _res_label(rtype))


func _begin_gather_work() -> void:
	var rtype := str(_goal.gather_type)
	_goal["stage"] = "gathering"
	activity = "gathering a %s" % _res_label(rtype)
	npc.begin_work(float(tech.resources[rtype].get("gather_seconds", 2.0))
		/ _tool_quality())


func _tool_quality() -> float:
	## Metal ages work faster: the best "quality" tool in hand speeds all work.
	var best := 1.0
	for item in npc.inventory:
		if int(npc.inventory[item]) > 0:
			best = maxf(best, float(tech.items.get(item, {}).get("quality", 1.0)))
	return best


func _goal_craft() -> void:
	var rid := str(_goal.target)
	var recipe: Dictionary = tech.recipes.get(rid, {})
	if recipe.is_empty():
		_fail_goal("does not know how to make that")
		return
	var st := tech.recipe_status(recipe, npc.inventory)
	if st.ready:
		# herd work happens at the corral — walk over first if needed
		var effects: Dictionary = recipe.get("effects", {})
		if effects.has("pen") or effects.has("herd_take") \
				or recipe.has("requires_herd"):
			var corral: Dictionary = main.nearest_corral(npc.position)
			if corral.is_empty():
				_fail_goal("has no corral for that work")
				return
			if NPCController._flat_dist(npc.position, corral.pos) > 3.0:
				var cpath := world.find_path(npc.position, corral.pos)
				if cpath.size() < 2:
					_fail_goal("could not reach the corral")
					return
				_goal["stage"] = "station_walk"
				activity = "heading over to the corral"
				npc.set_path(cpath)
				path_changed.emit(id, cpath)
				return
		# field work happens at the plot — walk over first if needed
		if effects.get("sow", false) or effects.get("harvest", false):
			var plot: Vector3 = main.farm_work_spot(npc.position,
				bool(effects.get("harvest", false)))
			if plot == Vector3.INF:
				_fail_goal("found no field ready for that work")
				return
			if NPCController._flat_dist(npc.position, plot) > 2.5:
				var fpath := world.find_path(npc.position, plot)
				if fpath.size() < 2:
					_fail_goal("could not reach the field")
					return
				_goal["stage"] = "station_walk"
				activity = "heading out to the field"
				npc.set_path(fpath)
				path_changed.emit(id, fpath)
				return
		# station work happens at the fire — walk over first if needed
		var station := str(recipe.get("station", ""))
		if station == "campfire":
			var fire: Campfire = main.nearest_fire(npc.position)
			if fire == null:
				_fail_goal("has no fire to work at")
				return
			if NPCController._flat_dist(npc.position, fire.position) > fire.work_radius:
				var path := world.find_path(npc.position, fire.position)
				if path.size() < 2:
					_fail_goal("could not reach the fire")
					return
				_goal["stage"] = "station_walk"
				activity = "carrying things to the fire"
				npc.set_path(path)
				path_changed.emit(id, path)
				return
		elif station != "":
			# a built workshop (smelter, ...) — same walk, different anchor
			var shop: Dictionary = main.nearest_station(station, npc.position)
			if shop.is_empty():
				_fail_goal("has no %s to work at" % station)
				return
			if NPCController._flat_dist(npc.position, shop.pos) > 2.5:
				var spath := world.find_path(npc.position, shop.pos)
				if spath.size() < 2:
					_fail_goal("could not reach the %s" % station)
					return
				_goal["stage"] = "station_walk"
				activity = "carrying things to the %s" % station
				npc.set_path(spath)
				path_changed.emit(id, spath)
				return
		_goal["stage"] = "crafting"
		activity = str(recipe.get("label", rid))
		npc.begin_work(float(recipe.get("seconds", 3.0)) / _tool_quality())
		return
	for item in st.missing:
		var rtype := tech.resource_yielding(item)
		if rtype != "" and not field.nearest(rtype, npc.position).is_empty():
			_goal_gather(rtype)
			return
	var missing_names: Array = []
	for item in st.missing:
		missing_names.append(tech.item_label(item))
	_fail_goal("lacks %s for %s and found none nearby"
		% [", ".join(missing_names), str(recipe.get("label", rid))])


func do_eat(item: String) -> void:
	if int(npc.inventory.get(item, 0)) < 1 or not tech.is_food(item):
		_fail_goal("has nothing good to eat")
		return
	_goal = {"type": "eat", "target": item, "stage": "eating"}
	activity = "eating %s" % tech.item_label(item)
	npc.begin_work(1.2)


func _on_work_done() -> void:
	if _goal.is_empty():
		return
	match str(_goal.get("stage", "")):
		"gathering":
			var yields := field.gather(_goal.entry)
			if yields.is_empty():
				_fail_goal("found the spot already picked clean")
				return
			npc.add_items(yields)
			var got: Array = []
			for item in yields:
				got.append("%d %s" % [int(yields[item]), tech.item_label(item)])
			emit_event("gathered " + ", ".join(got))
			# big game fights back
			var danger: Dictionary = tech.resources.get(str(_goal.gather_type), {}).get("danger", {})
			if not danger.is_empty() and randf() < float(danger.get("chance", 0.0)):
				npc.health = clampf(npc.health - float(danger.get("damage", 10)), 0.0, 100.0)
				emit_event(str(danger.get("text", "was hurt by the animal")))
			if str(_goal.type) == "craft":
				_advance_goal()
			else:
				_finish_goal()
		"crafting":
			var recipe: Dictionary = tech.recipes.get(str(_goal.target), {})
			var st := tech.recipe_status(recipe, npc.inventory)
			if not st.ready:
				_fail_goal("lost track of the materials")
				return
			var herd_kind := str(recipe.get("requires_herd", ""))
			if herd_kind != "" and not main.herd_has(npc.position, herd_kind):
				_fail_goal("found no %s in the corral" % herd_kind)
				return
			tech.apply_recipe(recipe, npc.inventory)
			if recipe.get("effects", {}).has("herd_take"):
				main.herd_take(self, str(recipe.effects.herd_take))
			if recipe.get("effects", {}).get("tame_dog", false):
				main.dogs += 1
				print("[VOX C] a dog joins the village (%d now)" % main.dogs)
			if recipe.get("effects", {}).get("train_ox", false):
				main.oxen += 1
				print("[VOX I] a draft ox joins the village (%d now)" % main.oxen)
			if recipe.get("effects", {}).has("pen"):
				var penned: String = main.pen_animal(self, str(recipe.effects.pen))
				if penned == "":
					# the animal was consumed by the recipe — set it loose again
					npc.add_items(recipe.get("inputs", {}))
					_fail_goal("found the corral full")
					return
				emit_event(penned)
				_finish_goal()
				return
			var fuel := float(recipe.get("effects", {}).get("fire_fuel", 0))
			if fuel > 0.0 and main.campfire != null:
				main.nearest_fire(npc.position).add_fuel(fuel)
			var builds := str(recipe.get("effects", {}).get("build", ""))
			if builds != "":
				main.build_structure(npc.position, builds)
			if recipe.get("effects", {}).get("sow", false):
				var sowed: String = main.farm_sow(self)
				if sowed == "":
					# seed already consumed — give it back, the ground refused it
					npc.add_items(recipe.get("inputs", {}))
					_fail_goal("found no bare field to sow (or the ground is frozen)")
					return
				emit_event(sowed)
				_finish_goal()
				return
			if recipe.get("effects", {}).get("harvest", false):
				var reaped: String = main.farm_harvest(self)
				if reaped == "":
					_fail_goal("found nothing ripe to harvest")
					return
				emit_event(reaped)
				_finish_goal()
				return
			emit_event(str(recipe.get("verb", "crafted something")))
			_finish_goal()
		"experimenting":
			emit_event("worked out %s by themselves" % str(_goal.target).to_lower())
			_finish_goal()
		"eating":
			var item := str(_goal.target)
			npc.inventory[item] = int(npc.inventory.get(item, 0)) - 1
			if int(npc.inventory[item]) <= 0:
				npc.inventory.erase(item)
			npc.hunger = clampf(npc.hunger - tech.food_hunger_value(item), 0.0, 100.0)
			if tech.items.get(item, {}).get("cheer", false):
				emit_event("drank %s and feels merry" % tech.item_label(item))
			else:
				emit_event("ate %s" % tech.item_label(item))
			_finish_goal()


func _on_arrived() -> void:
	path_changed.emit(id, PackedVector3Array())
	match str(_goal.get("stage", "")):
		"gather_walk":
			_begin_gather_work()
		"station_walk":
			_advance_goal()      # arrived at the fire — re-run the craft
		"store_walk":
			_do_store_transfer()
		"rest_walk":
			_rest_here()
		"fleeing":
			emit_event("reached the safety of the fire")
			_finish_goal()
		"talk_walk":
			_talk_repaths += 1
			if _talk_repaths > 4:
				_fail_goal("gave up chasing %s" % (
					_talk_target.npc.npc_name if _talk_target else "them"))
			else:
				_walk_toward_talk_target()   # repath if target moved, or converse
		_:
			activity = "standing around"
			_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)


func _finish_goal() -> void:
	_release_claim()
	_goal.clear()
	_talk_target = null
	activity = "standing around"
	path_changed.emit(id, PackedVector3Array())
	_wander_timer = randf_range(WANDER_MIN, WANDER_MAX)
	if not _skill_queue.is_empty() or _skill_name != "":
		call_deferred("_next_skill_step")


func _fail_goal(reason: String) -> void:
	emit_event("tried, but " + reason)
	_abort_skill(reason)
	_finish_goal()


func emit_event(text: String) -> void:
	print("[VOX P3] %s %s" % [npc.npc_name, text])
	if cortex.online:
		cortex.send({"type": "event", "npc": id, "text": text})
	chat_ui.add_line(npc.npc_name, "[i]%s[/i]" % text)


func _do_store_transfer() -> void:
	var event_text := ""
	if str(_goal.get("type", "")) == "deposit":
		event_text = main.store_deposit(self, str(_goal.target))
	else:
		event_text = main.store_withdraw(self, str(_goal.target))
	if event_text == "":
		_fail_goal("found the store full or empty")
		return
	emit_event(event_text)
	_finish_goal()


func _has_warmth_item() -> bool:
	for item in npc.inventory:
		if int(npc.inventory[item]) > 0 and tech.items.get(item, {}).has("warmth"):
			return true
	return false


func _res_label(rtype: String) -> String:
	return str(tech.resources.get(rtype, {}).get("label", rtype))


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
