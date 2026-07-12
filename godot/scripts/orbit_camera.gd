class_name OrbitCamera
extends Node3D
## Orbit rig: node position = focus point; camera orbits it.
## RMB drag: orbit - wheel: zoom - WASD: pan (disabled while typing in UI).

var distance := 45.0
var yaw := 0.8
var pitch := -0.85
var pan_speed := 18.0

var _rotating := false
var _cam: Camera3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.far = 800.0
	add_child(_cam)
	_cam.make_current()
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rotating = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance * 0.9, 6.0, 200.0)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance * 1.1, 6.0, 200.0)
			_update_transform()
	elif event is InputEventMouseMotion and _rotating:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch - event.relative.y * 0.006, -1.45, -0.10)
		_update_transform()


func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return  # typing in chat — don't pan
	var dir := Vector3.ZERO
	if Input.is_action_pressed("pan_forward"):
		dir.z -= 1.0
	if Input.is_action_pressed("pan_back"):
		dir.z += 1.0
	if Input.is_action_pressed("pan_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("pan_right"):
		dir.x += 1.0
	if dir != Vector3.ZERO:
		var rot := Basis(Vector3.UP, yaw)
		position += rot * dir.normalized() * pan_speed * (distance / 40.0) * delta


func _update_transform() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	_cam.position = Vector3(0, 0, distance)
