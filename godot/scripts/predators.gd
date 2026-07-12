class_name Predators
extends Node3D
## Wolves: the world's first danger. They roam the wilds, avoid the lit fire,
## and stalk villagers who stray — who drop everything and flee. A wolf that
## catches someone bites (health damage) and then retreats.
## Config: "predators.wolf" in era1_content.json; model slot assets/predators/wolf.glb.

var world: VoxelWorld
var main: Node
var cfg := {}
var wolves: Array[Dictionary] = []   # {node, pos, move_*, wait_t, cooldown}


func setup(p_world: VoxelWorld, p_main: Node, p_cfg: Dictionary) -> void:
	world = p_world
	main = p_main
	cfg = p_cfg
	var count := int(cfg.get("count", 3))
	for i in count:
		var spot := _wild_spot()
		if spot == Vector3.ZERO:
			continue
		var node := _build_wolf()
		node.position = spot
		add_child(node)
		var w := {"node": node, "pos": spot, "move_t": 0.0, "move_dur": 1.0,
			"move_from": spot, "move_to": spot, "wait_t": randf_range(0.0, 4.0),
			"cooldown": 0.0, "anims": AssetLib.find_animations(node)}
		_play_anim(w, "idle")
		wolves.append(w)
	if not wolves.is_empty():
		print("[VOX P7] %d wolves prowl the wilds" % wolves.size())


func _process(delta: float) -> void:
	var threat := float(cfg.get("threat_radius", 6.0))
	if main.is_night():
		threat += float(cfg.get("night_threat_bonus", 3.0))
	for w in wolves:
		w.cooldown = maxf(0.0, w.cooldown - delta)
		var prey := _nearest_villager(w.pos)
		# village dogs (E4.07) widen the safe ground around the fires
		if not prey.is_empty() and int(main.dogs) > 0 \
				and _dogs_guard(prey.ctrl.npc.position):
			if w.cooldown <= 0.0 and prey.dist <= threat:
				w.cooldown = 25.0
				var line := "the dogs drove a wolf away from the village"
				print("[VOX C] ", line)
				main.chat_ui.add_line("world", "[i]%s[/i]" % line)
				_walk_to(w, world.random_walkable_near(w.pos,
					float(cfg.get("retreat_cells", 18.0))))
			prey = {}
		if not prey.is_empty() and w.cooldown <= 0.0:
			var d: float = prey.dist
			if d <= 1.4:
				_bite(w, prey.ctrl)
				continue
			if d <= threat:
				prey.ctrl.flee_from(w.pos)
				_chase(w, prey.ctrl.npc.position)
		_move(w, delta)


func _move(w: Dictionary, delta: float) -> void:
	if w.move_t > 0.0:
		w.move_t = maxf(0.0, w.move_t - delta)
		var f: float = 1.0 - w.move_t / w.move_dur
		w.node.position = w.move_from.lerp(w.move_to, f)
		w.pos = w.node.position
		if w.move_t <= 0.0:
			w.wait_t = randf_range(1.5, 6.0)
			_play_anim(w, "idle")
		return
	w.wait_t -= delta
	if w.wait_t > 0.0:
		return
	_walk_to(w, world.random_walkable_near(w.pos, float(cfg.get("wander_radius", 9.0))))


func _chase(w: Dictionary, target: Vector3) -> void:
	_walk_to(w, target, 1.6)


func _walk_to(w: Dictionary, target: Vector3, speed_mult := 1.0) -> void:
	# wolves shun any lit fire
	var near_fire: Campfire = main.nearest_fire(target)
	if near_fire != null and near_fire.is_lit() \
			and NPCController._flat_dist(target, near_fire.position) \
			< float(cfg.get("safe_fire_radius", 14.0)):
		w.wait_t = 2.0
		return
	if target == w.pos:
		w.wait_t = 2.0
		return
	w.move_from = w.node.position
	w.move_to = target
	w.move_dur = maxf(0.15, w.move_from.distance_to(target)
		/ (float(cfg.get("speed", 3.2)) * speed_mult))
	w.move_t = w.move_dur
	w.node.look_at(Vector3(target.x, w.node.position.y, target.z), Vector3.UP)
	w.node.rotate_y(PI)   # glTF forward is +Z; look_at aims -Z
	_play_anim(w, "walk")


func _bite(w: Dictionary, ctrl: NPCController) -> void:
	ctrl.npc.health = clampf(ctrl.npc.health - float(cfg.get("bite_damage", 12)),
		0.0, 100.0)
	ctrl.emit_event("was bitten by a wolf")
	w.cooldown = 20.0
	_walk_to(w, world.random_walkable_near(w.pos, float(cfg.get("retreat_cells", 18.0))))


func _play_anim(w: Dictionary, kind: String) -> void:
	var anims: Dictionary = w.get("anims", {})
	if anims.is_empty():
		return
	var clip := str(anims.get(kind, anims.get("idle", anims.get("any", ""))))
	var player: AnimationPlayer = anims["player"]
	if clip != "" and player.current_animation != clip:
		player.play(clip)
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _dogs_guard(pos: Vector3) -> bool:
	var fire: Campfire = main.nearest_fire(pos)
	if fire == null:
		return false
	var guard := float(cfg.get("safe_fire_radius", 14.0)) \
		+ 3.0 * mini(int(main.dogs), 4)
	return NPCController._flat_dist(pos, fire.position) < guard


func _nearest_villager(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for npc_id in main.controllers:
		var ctrl: NPCController = main.controllers[npc_id]
		if ctrl.npc.dead:
			continue
		var d := NPCController._flat_dist(pos, ctrl.npc.position)
		if d < best_d:
			best_d = d
			best = {"ctrl": ctrl, "dist": d}
	return best


func _wild_spot() -> Vector3:
	# spawn far from the fire, in reachable wilds
	for i in 40:
		var p := world.random_walkable_near(
			Vector3(world.W * randf(), 0, world.D * randf()), 20.0)
		if p != Vector3.ZERO and main.nearest_fire(p) != null \
				and NPCController._flat_dist(p, main.nearest_fire(p).position) > 30.0 \
				and world.is_reachable(int(p.x), int(p.z)):
			return p
	return Vector3.ZERO


func _build_wolf() -> Node3D:
	var model := AssetLib.instantiate("predators/wolf")
	if model != null:
		AssetLib.fit(model, float(cfg.get("model_height", 0.8)))
		return model
	# box-art wolf: low dark body, head, tail
	var wolf := Node3D.new()
	var dark := Color(0.22, 0.22, 0.25)
	_box(wolf, Vector3(0.9, 0.35, 0.3), Vector3(0, 0.45, 0), dark)
	_box(wolf, Vector3(0.28, 0.26, 0.24), Vector3(0, 0.62, 0.5), dark.lightened(0.1))
	_box(wolf, Vector3(0.08, 0.08, 0.35), Vector3(0, 0.62, -0.55), dark)
	for side in [-1.0, 1.0]:
		_box(wolf, Vector3(0.09, 0.45, 0.09), Vector3(side * 0.16, 0.22, 0.3), dark)
		_box(wolf, Vector3(0.09, 0.45, 0.09), Vector3(side * 0.16, 0.22, -0.25), dark)
	return wolf


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
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
