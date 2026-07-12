class_name NPC
extends Node3D
## Voxel person that follows waypoint paths. Origin = feet.
## Body from Godot; mind from Cortex. Exposes: set_path(), is_idle(), say(),
## begin_work(), needs (hunger/energy), inventory; signals arrived, work_done.

signal arrived
signal work_done

const SKIN_TONES := [Color(0.87, 0.72, 0.60), Color(0.76, 0.57, 0.42), Color(0.55, 0.40, 0.30)]
const TUNIC_TONES := [Color(0.55, 0.35, 0.25), Color(0.42, 0.46, 0.30), Color(0.50, 0.32, 0.40)]

var npc_id := ""
var npc_name := "Anon"
var speed := 3.5

# --- P2 body state: needs + what it carries ---
var hunger := 30.0            # 0 fed .. 100 starving
var energy := 80.0            # 100 fresh .. 0 exhausted
var health := 100.0           # 0 = dead; starvation drains it
var age := 25.0               # years; advances each dawn
var lifespan := 62.0          # rolled at spawn; old age takes them past it
var inventory := {}           # item id -> count
var warm := false             # near a lit fire (set by main each tick)
var wrapped := false          # carries a warmth item like a hide wrap (P5)
var night := false            # world time (set by main each tick)
var dead := false
var _hunger_rise := 4.0       # per real minute; overridden by set_needs_cfg
var _energy_fall := 3.0
var _energy_recover := 6.0
var _starve_damage := 3.0
var _health_regen := 2.0
var _fed_below := 50.0

var _path := PackedVector3Array()
var _wp := 0
var _moving := false
var _working := false
var _work_t := 0.0
var _anim_t := 0.0
var _anim: Dictionary = {}        # imported model: {player, walk, idle, work}
var _has_model := false           # true when an assets/npc/ model replaced the box body
var _visual: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _speech: Label3D
var _speech_t := 0.0


func _ready() -> void:
	_build_body()


func set_path(path: PackedVector3Array) -> void:
	if path.size() < 2:
		return
	_path = path
	_wp = 1
	_moving = true


func is_idle() -> bool:
	return not _moving and not _working


func is_working() -> bool:
	return _working


func stop() -> void:
	_path = PackedVector3Array()
	_moving = false


func set_needs_cfg(cfg: Dictionary) -> void:
	hunger = float(cfg.get("hunger", {}).get("start", hunger))
	energy = float(cfg.get("energy", {}).get("start", energy))
	_hunger_rise = float(cfg.get("hunger", {}).get("rise_per_minute", _hunger_rise))
	_energy_fall = float(cfg.get("energy", {}).get("fall_per_minute_moving", _energy_fall))
	_energy_recover = float(cfg.get("energy", {}).get("recover_per_minute_idle", _energy_recover))
	var h: Dictionary = cfg.get("health", {})
	health = float(h.get("start", health))
	_starve_damage = float(h.get("starve_damage_per_minute", _starve_damage))
	_health_regen = float(h.get("regen_per_minute_fed", _health_regen))
	_fed_below = float(h.get("fed_below_hunger", _fed_below))


func die() -> void:
	dead = true
	stop()
	_working = false
	_speech.visible = false
	_visual.rotation.x = PI / 2.0   # falls onto their back
	_visual.position.y = 0.35


func begin_work(seconds: float) -> void:
	_working = true
	_work_t = maxf(0.1, seconds)


func add_items(yields: Dictionary) -> void:
	for item in yields:
		inventory[item] = int(inventory.get(item, 0)) + int(yields[item])


func say(text: String) -> void:
	if text.strip_edges() == "":
		return
	_speech.text = text
	_speech.visible = true
	_speech_t = clampf(2.0 + text.length() * 0.06, 2.5, 10.0)


func _process(delta: float) -> void:
	if dead:
		return
	hunger = clampf(hunger + _hunger_rise / 60.0 * delta, 0.0, 100.0)
	if _moving or _working:
		energy = clampf(energy - _energy_fall / 60.0 * delta, 0.0, 100.0)
	elif night and not warm and not wrapped:
		# cold night away from the fire, with nothing to wear: no rest to be had
		energy = clampf(energy - _energy_fall * 0.5 / 60.0 * delta, 0.0, 100.0)
	else:
		var rate := _energy_recover * (2.0 if warm else 1.0)
		energy = clampf(energy + rate / 60.0 * delta, 0.0, 100.0)
	if hunger >= 99.5:
		health = clampf(health - _starve_damage / 60.0 * delta, 0.0, 100.0)
	elif hunger < _fed_below:
		health = clampf(health + _health_regen / 60.0 * delta, 0.0, 100.0)
	if _working:
		_work_t -= delta
		if _work_t <= 0.0:
			_working = false
			work_done.emit()
	if _moving:
		var target := _path[_wp]
		var to_t := target - position
		var step := speed * delta
		if to_t.length() <= step:
			position = target
			_wp += 1
			if _wp >= _path.size():
				_moving = false
				arrived.emit()
		else:
			position += to_t.normalized() * step
			var flat := Vector3(to_t.x, 0.0, to_t.z)
			if flat.length_squared() > 0.0001:
				rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 10.0 * delta)
	if _speech_t > 0.0:
		_speech_t -= delta
		if _speech_t <= 0.0:
			_speech.visible = false
	_animate(delta)


func _animate(delta: float) -> void:
	# imported model: drive its AnimationPlayer instead of the procedural limbs
	if _has_model:
		if not _anim.is_empty():
			var player: AnimationPlayer = _anim["player"]
			var clip := ""
			if _working:
				clip = str(_anim.get("work", _anim.get("idle", "")))
			elif _moving:
				clip = str(_anim.get("walk", ""))
			else:
				clip = str(_anim.get("idle", ""))
			if clip != "" and player.current_animation != clip:
				player.play(clip)
		return
	if _working:
		# kneeling-forward chopping motion: both arms swing hard, legs still
		_anim_t += delta * 12.0
		var w := sin(_anim_t)
		_arm_l.rotation.x = -1.1 + w * 0.6
		_arm_r.rotation.x = -1.1 + w * 0.6
		_leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, 0.0, 8.0 * delta)
		_leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, 0.0, 8.0 * delta)
		_visual.position.y = absf(w) * -0.06
	elif _moving:
		_anim_t += delta * 9.0
		var s := sin(_anim_t)
		_leg_l.rotation.x = s * 0.7
		_leg_r.rotation.x = -s * 0.7
		_arm_l.rotation.x = -s * 0.5
		_arm_r.rotation.x = s * 0.5
		_visual.position.y = absf(sin(_anim_t)) * 0.05
	else:
		_leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, 0.0, 8.0 * delta)
		_leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, 0.0, 8.0 * delta)
		_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, 0.0, 8.0 * delta)
		_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, 0.0, 8.0 * delta)
		_visual.position.y = lerpf(_visual.position.y, 0.0, 8.0 * delta)


# ---------------------------------------------------------------- body

func _build_body() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	# imported model? per-villager (assets/npc/<id>.glb) or shared default
	var model := AssetLib.instantiate("npc/" + npc_id)
	if model == null:
		model = AssetLib.instantiate("npc/default")
	if model != null:
		_has_model = true
		AssetLib.fit(model, 1.75)
		_visual.add_child(model)
		_anim = AssetLib.find_animations(model)
		_attach_ui_and_picker()
		return
	_build_box_body()


func _build_box_body() -> void:
	var skin: Color = SKIN_TONES.pick_random()
	var tunic: Color = TUNIC_TONES.pick_random()
	var hair := Color(0.14, 0.10, 0.08)

	_leg_l = _limb(Vector3(0.20, 0.70, 0.22), Vector3(-0.12, 0.70, 0.0), tunic.darkened(0.35))
	_leg_r = _limb(Vector3(0.20, 0.70, 0.22), Vector3(0.12, 0.70, 0.0), tunic.darkened(0.35))
	_box(Vector3(0.50, 0.65, 0.28), Vector3(0.0, 1.025, 0.0), tunic)  # torso
	_arm_l = _limb(Vector3(0.14, 0.60, 0.16), Vector3(-0.33, 1.32, 0.0), skin)
	_arm_r = _limb(Vector3(0.14, 0.60, 0.16), Vector3(0.33, 1.32, 0.0), skin)
	_box(Vector3(0.38, 0.38, 0.38), Vector3(0.0, 1.56, 0.0), skin)  # head
	_box(Vector3(0.40, 0.12, 0.40), Vector3(0.0, 1.78, 0.0), hair)  # hair cap
	_box(Vector3(0.06, 0.06, 0.02), Vector3(-0.09, 1.60, 0.20), Color(0.1, 0.1, 0.1))  # eye L
	_box(Vector3(0.06, 0.06, 0.02), Vector3(0.09, 1.60, 0.20), Color(0.1, 0.1, 0.1))   # eye R
	_attach_ui_and_picker()


func _attach_ui_and_picker() -> void:
	var label := Label3D.new()
	label.text = npc_name
	label.position = Vector3(0, 2.15, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008
	label.modulate = Color(1, 1, 1, 0.9)
	label.outline_size = 8
	_visual.add_child(label)

	_speech = Label3D.new()
	_speech.position = Vector3(0, 2.55, 0)
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.no_depth_test = true
	_speech.pixel_size = 0.009
	_speech.modulate = Color(1.0, 0.95, 0.75)
	_speech.outline_size = 10
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD
	_speech.width = 320.0
	_speech.visible = false
	add_child(_speech)

	# clickable pick area (for chat)
	var area := Area3D.new()
	area.set_meta("npc", npc_id)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 2.0
	cs.shape = cap
	cs.position = Vector3(0, 1.0, 0)
	area.add_child(cs)
	add_child(area)


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	_visual.add_child(mi)
	return mi


func _limb(size: Vector3, pivot_pos: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	_visual.add_child(pivot)
	var mi := _box(size, Vector3.ZERO, color)
	mi.get_parent().remove_child(mi)
	pivot.add_child(mi)
	mi.position = Vector3(0, -size.y * 0.5, 0)
	return pivot
