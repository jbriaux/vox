class_name InputConfig
extends RefCounted
## Rebindable input actions. Defaults use PHYSICAL key positions, so AZERTY
## keyboards get ZQSD-where-WASD-is automatically; the Options menu lets the
## player rebind anything. Bindings persist in user://keybinds.cfg.

const SAVE_PATH := "user://keybinds.cfg"

# name, menu label, default physical keycode (QWERTY position)
const ACTIONS := [
	{"name": "pan_forward", "label": "Camera pan forward", "key": KEY_W},
	{"name": "pan_back", "label": "Camera pan back", "key": KEY_S},
	{"name": "pan_left", "label": "Camera pan left", "key": KEY_A},
	{"name": "pan_right", "label": "Camera pan right", "key": KEY_D},
	{"name": "focus_next", "label": "Focus next villager", "key": KEY_F},
	{"name": "open_chat", "label": "Talk to focused villager", "key": KEY_T},
	{"name": "toggle_autofocus", "label": "Auto-focus conversations", "key": KEY_C},
]


static func setup() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a.name):
			InputMap.add_action(a.name)
		_bind(a.name, int(a.key), true)
	_load()


static func rebind(action: String, event: InputEventKey) -> void:
	## Bind the action to the key the player pressed (stored as physical,
	## so the position keeps working if they switch layouts).
	_bind(action, event.physical_keycode if event.physical_keycode != KEY_NONE
		else event.keycode, event.physical_keycode != KEY_NONE)
	_save()


static func reset_defaults() -> void:
	for a in ACTIONS:
		_bind(a.name, int(a.key), true)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


static func binding_label(action: String) -> String:
	## Human label in the PLAYER'S layout (physical W shows as "Z" on AZERTY).
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var key: int = ev.physical_keycode
			if key != KEY_NONE:
				var mapped := DisplayServer.keyboard_get_keycode_from_physical(key)
				return OS.get_keycode_string(mapped if mapped != KEY_NONE else key)
			return OS.get_keycode_string(ev.keycode)
	return "—"


static func _bind(action: String, key: int, physical: bool) -> void:
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	if physical:
		ev.physical_keycode = key
	else:
		ev.keycode = key
	InputMap.action_add_event(action, ev)


static func _save() -> void:
	var cfg := ConfigFile.new()
	for a in ACTIONS:
		for ev in InputMap.action_get_events(a.name):
			if ev is InputEventKey:
				var physical: bool = ev.physical_keycode != KEY_NONE
				cfg.set_value("keys", a.name,
					{"key": ev.physical_keycode if physical else ev.keycode,
						"physical": physical})
				break
	cfg.save(SAVE_PATH)


static func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for a in ACTIONS:
		var saved: Variant = cfg.get_value("keys", a.name, null)
		if saved is Dictionary:
			_bind(a.name, int(saved.get("key", a.key)), bool(saved.get("physical", true)))
