class_name ResourceField
extends Node3D
## Gatherable era-1 props scattered on the terrain: flint nodules, loose
## cobbles, fallen branches, berry bushes. Data-driven from era1_content.json.

const NEARBY_RADIUS := 48.0


var world: VoxelWorld
var data: TechData
var winter := false                   # seasonal resources don't regrow in winter
var entries: Array[Dictionary] = []   # {type, pos, node, available, respawn_t, idx}
var _occupied := {}                   # Vector2i cell -> true
var _next_idx := 0                    # stable per-entry id for save files

const CLAIM_SECONDS := 25.0   # walk + gather comfortably; leaks self-heal

const SPAWN_BLOCK := {
	"grass": VoxelWorld.B.GRASS,
	"dirt": VoxelWorld.B.DIRT,
	"stone": VoxelWorld.B.STONE,
	"sand": VoxelWorld.B.SAND,
}


func setup(p_world: VoxelWorld, p_data: TechData) -> void:
	world = p_world
	data = p_data
	var rng := RandomNumberGenerator.new()
	rng.seed = world.world_seed + 4242
	for rtype in data.resources:
		_scatter(rtype, data.resources[rtype], rng)
	print("[VOX P2] resource field: %d props (%s)" % [entries.size(),
		", ".join(data.resources.keys())])


func _process(delta: float) -> void:
	for e in entries:
		if not e.available and e.respawn_t > 0.0:
			if winter and data.resources.get(e.type, {}).get("seasonal", false):
				continue   # nothing grows back under the snow
			e.respawn_t -= delta
			if e.respawn_t <= 0.0:
				e.available = true
				e.node.visible = true
		elif e.available and data.resources.get(e.type, {}).get("wanders", false):
			_wander_step(e, delta)


func _wander_step(e: Dictionary, delta: float) -> void:
	## Living props (game animals) drift between nearby cells instead of
	## standing like statues. Hunters path to where the animal was — close
	## enough; the chase is abstracted into the gather timer.
	if e.get("move_t", 0.0) > 0.0:
		e.move_t = maxf(0.0, e.move_t - delta)
		var f: float = 1.0 - e.move_t / e.move_dur
		e.node.position = e.move_from.lerp(e.move_to, f)
		e.pos = e.node.position
		if e.move_t <= 0.0:
			e.wait_t = randf_range(3.0, 9.0)
			_play_anim(e, "idle")
		return
	e.wait_t = e.get("wait_t", randf_range(0.0, 6.0)) - delta
	if e.wait_t > 0.0:
		return
	var target := world.random_walkable_near(e.pos, 5.0)
	if target == e.pos:
		e.wait_t = 4.0
		return
	e.move_from = e.node.position
	e.move_to = target
	e.move_dur = e.move_from.distance_to(target) / 1.6
	e.move_t = e.move_dur
	e.node.look_at(Vector3(target.x, e.node.position.y, target.z), Vector3.UP)
	e.node.rotate_y(PI)   # glTF models face +Z; look_at aims -Z — flip to walk nose-first
	_play_anim(e, "walk")


func _play_anim(e: Dictionary, kind: String) -> void:
	var anims: Dictionary = e.get("anims", {})
	if anims.is_empty():
		return
	var clip := str(anims.get(kind, anims.get("idle", anims.get("any", ""))))
	var player: AnimationPlayer = anims["player"]
	if clip != "" and player.current_animation != clip:
		player.play(clip)
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


# ---------------------------------------------------------------- queries

func nearest(rtype: String, pos: Vector3) -> Dictionary:
	var c := nearest_candidates(rtype, pos, 1)
	return c[0] if not c.is_empty() else {}


func nearest_candidates(rtype: String, pos: Vector3, k: int = 4) -> Array[Dictionary]:
	## k nearest available props of a type — callers try them in order, so an
	## unreachable one (island, across the river) doesn't dead-end the goal.
	var now := Time.get_ticks_msec() / 1000.0
	var scored: Array = []
	for e in entries:
		if e.type != rtype or not e.available:
			continue
		if now - float(e.get("claim_t", -INF)) < CLAIM_SECONDS:
			continue   # another villager is already walking there — but claims
			           # EXPIRE, so an interrupted (or dead) claimant never
			           # hides food from the village forever
		scored.append([Vector2(e.pos.x - pos.x, e.pos.z - pos.z).length(), e])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array[Dictionary] = []
	for i in mini(k, scored.size()):
		out.append(scored[i][1])
	return out


func distances(pos: Vector3) -> Dictionary:
	## Nearest available prop per type within NEARBY_RADIUS, as {type: distance}.
	var out := {}
	for e in entries:
		if not e.available:
			continue
		var d: float = Vector2(e.pos.x - pos.x, e.pos.z - pos.z).length()
		if d <= NEARBY_RADIUS and d < float(out.get(e.type, INF)):
			out[e.type] = snappedf(d, 0.1)
	return out


func gather(entry: Dictionary) -> Dictionary:
	## Deplete the prop and return its yields ({item: count}).
	if entry.is_empty() or not entry.available:
		return {}
	var cfg: Dictionary = data.resources[entry.type]
	entry.available = false
	if cfg.get("respawns", false):
		entry.node.visible = false
		entry.respawn_t = float(cfg.get("respawn_seconds", 90))
	else:
		entry.node.queue_free()
		entries.erase(entry)
	return cfg.get("yields", {}).duplicate()


# ---------------------------------------------------------------- save/load

func save_state() -> Dictionary:
	## {idx: [available, respawn_t]} for entries that still exist — a missing
	## idx on load means the prop was consumed for good.
	var out := {}
	for e in entries:
		out[str(e.idx)] = [e.available, snappedf(e.respawn_t, 0.1)]
	return out

func apply_save(saved: Dictionary) -> void:
	## Same seed produced the same scatter; prune what was consumed and
	## restore availability/respawn timers on the rest.
	for e in entries.duplicate():
		var s: Variant = saved.get(str(e.idx))
		if s == null:
			e.node.queue_free()
			entries.erase(e)
			continue
		e.available = bool(s[0])
		e.respawn_t = float(s[1])
		e.node.visible = e.available


# ---------------------------------------------------------------- scatter

func _scatter(rtype: String, cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	# counts in the data are tuned for a 128x128 map; scale with area, but cap
	# it — on huge maps the village lives locally and 15k prop nodes would
	# only burn memory and frame time
	var area_scale := minf(float(world.W * world.D) / (128.0 * 128.0), 9.0)
	var want := maxi(4, roundi(float(cfg.get("count", 20)) * area_scale))
	var allowed: Array = cfg.get("spawn_on", [])
	var near_trees: bool = cfg.get("near_trees", false)
	var placed := 0
	for i in want * 20:
		if placed >= want:
			break
		var x: int
		var z: int
		if near_trees and not world.trees.is_empty():
			var t: Vector2i = world.trees[rng.randi_range(0, world.trees.size() - 1)]
			x = t.x + rng.randi_range(-4, 4)
			z = t.y + rng.randi_range(-4, 4)
		else:
			x = rng.randi_range(2, world.W - 3)
			z = rng.randi_range(2, world.D - 3)
		var cell := Vector2i(x, z)
		if _occupied.has(cell) or not world.is_walkable(x, z) or not world.is_reachable(x, z):
			continue
		var top := world.surface_block(x, z)
		var block_ok := false
		for name in allowed:
			if SPAWN_BLOCK.get(name, -1) == top:
				block_ok = true
				break
		if not block_ok:
			continue
		_occupied[cell] = true
		var node := _build_prop(rtype, rng)
		node.position = world.cell_pos(x, z)
		add_child(node)
		var entry := {"type": rtype, "pos": node.position, "node": node,
			"available": true, "respawn_t": 0.0, "idx": _next_idx}
		if cfg.get("wanders", false):
			entry["anims"] = AssetLib.find_animations(node)
			_play_anim(entry, "idle")
		entries.append(entry)
		_next_idx += 1
		placed += 1


func _build_prop(rtype: String, rng: RandomNumberGenerator) -> Node3D:
	# imported model wins (assets/props/<type>.glb); boxes are the fallback
	var model := AssetLib.instantiate("props/" + rtype)
	if model != null:
		AssetLib.fit(model, float(data.resources[rtype].get("model_height", 0.8)))
		model.rotation.y = rng.randf() * TAU
		return model
	var prop := Node3D.new()
	match rtype:
		"loose_cobble":
			_box(prop, Vector3(0.30, 0.22, 0.26), Vector3(0, 0.11, 0), Color(0.55, 0.55, 0.56))
		"flint_nodule":
			_box(prop, Vector3(0.34, 0.26, 0.30), Vector3(0, 0.13, 0), Color(0.16, 0.17, 0.22))
			_box(prop, Vector3(0.14, 0.10, 0.12), Vector3(0.12, 0.28, 0.02), Color(0.28, 0.30, 0.38))
		"branch":
			var b := _box(prop, Vector3(0.90, 0.10, 0.12), Vector3(0, 0.06, 0), Color(0.40, 0.28, 0.16))
			b.rotation.y = rng.randf() * TAU
		"berry_bush":
			_box(prop, Vector3(0.85, 0.70, 0.85), Vector3(0, 0.35, 0), Color(0.16, 0.34, 0.14))
			for i in 6:
				_box(prop, Vector3(0.09, 0.09, 0.09),
					Vector3(rng.randf_range(-0.34, 0.34), rng.randf_range(0.25, 0.68),
						rng.randf_range(-0.34, 0.34)), Color(0.72, 0.12, 0.15))
		_:
			# neutral mound for types without models yet (drop a .glb in
			# assets/props/ named after the resource to replace it)
			_box(prop, Vector3(0.42, 0.28, 0.38), Vector3(0, 0.14, 0), Color(0.45, 0.38, 0.28))
	prop.rotation.y = rng.randf() * TAU
	return prop


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi
