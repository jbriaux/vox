class_name Campfire
extends Node3D
## The settlement's hearth: a fuel store that burns down in real time and must
## be tended (tend_fire recipe), a cooking station, warmth at night, and the
## village's social anchor. Config from era1_content.json "stations.campfire".

var fuel := 70.0
var fuel_max := 100.0
var decay_per_minute := 2.0
var low_fuel := 35.0
var warmth_radius := 7.0
var work_radius := 6.0

var _flame: MeshInstance3D
var _glow: OmniLight3D
var _flicker_t := 0.0


func setup(cfg: Dictionary) -> void:
	fuel = float(cfg.get("fuel_start", fuel))
	fuel_max = float(cfg.get("fuel_max", fuel_max))
	decay_per_minute = float(cfg.get("fuel_decay_per_minute", decay_per_minute))
	low_fuel = float(cfg.get("low_fuel", low_fuel))
	warmth_radius = float(cfg.get("warmth_radius", warmth_radius))
	work_radius = float(cfg.get("work_radius", work_radius))
	_build()


func _process(delta: float) -> void:
	fuel = maxf(0.0, fuel - decay_per_minute / 60.0 * delta)
	_flicker_t += delta * 7.0
	var strength := clampf(fuel / fuel_max, 0.0, 1.0)
	if is_lit():
		var flicker := 0.85 + 0.15 * sin(_flicker_t) * sin(_flicker_t * 1.7)
		_flame.visible = true
		_flame.scale = Vector3.ONE * (0.4 + 0.6 * strength) * flicker
		_glow.visible = true
		_glow.light_energy = (0.6 + 2.0 * strength) * flicker
	else:
		_flame.visible = false
		_glow.visible = false


func is_lit() -> bool:
	return fuel > 3.0


func add_fuel(amount: float) -> void:
	fuel = clampf(fuel + amount, 0.0, fuel_max)


func state_for(pos: Vector3) -> Dictionary:
	return {
		"lit": is_lit(),
		"fuel": roundi(fuel),
		"distance": snappedf(Vector2(position.x - pos.x, position.z - pos.z).length(), 0.1),
	}


func _build() -> void:
	# imported model (assets/campfire.glb) replaces the stone ring; the flame
	# and glow stay ours either way — they visualize the fuel level
	var model := AssetLib.instantiate("campfire")
	if model != null:
		AssetLib.fit(model, 0.6)
		add_child(model)
	else:
		# ring of stones
		for i in 7:
			var ang := TAU * i / 7.0
			_box(Vector3(0.30, 0.22, 0.24), Vector3(cos(ang) * 0.75, 0.11, sin(ang) * 0.75),
				Color(0.42, 0.42, 0.44)).rotation.y = ang
		# charred ground + log
		_box(Vector3(0.9, 0.06, 0.9), Vector3(0, 0.03, 0), Color(0.12, 0.10, 0.09))
		_box(Vector3(0.7, 0.14, 0.16), Vector3(0, 0.12, 0.05), Color(0.25, 0.17, 0.10)).rotation.y = 0.6

	_flame = _box(Vector3(0.45, 0.7, 0.45), Vector3(0, 0.45, 0), Color(1.0, 0.55, 0.12))
	var fmat: StandardMaterial3D = _flame.mesh.material
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.45, 0.08)
	fmat.emission_energy_multiplier = 2.0

	_glow = OmniLight3D.new()
	_glow.position = Vector3(0, 1.0, 0)
	_glow.light_color = Color(1.0, 0.6, 0.25)
	_glow.omni_range = 9.0
	_glow.shadow_enabled = true
	add_child(_glow)


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
	add_child(mi)
	return mi
