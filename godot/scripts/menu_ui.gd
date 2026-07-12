class_name MenuUI
extends CanvasLayer
## Launch menu: New Game (map size + terrain type) or Exit. Built in code
## like every other UI in the project.

signal start_game(size_chunks: int, preset: String, water: float, map_seed: int,
	flavor: String, council: bool)
signal continue_game
signal exit_game

const FLAVORS := [
	{"label": "Vanilla — one guided village of 10", "flavor": "vanilla"},
	{"label": "Emergent — two blank-mind villages of 5", "flavor": "emergent"},
]

const SIZES := [
	{"label": "Small (96 x 96)", "chunks": 6},
	{"label": "Medium (128 x 128)", "chunks": 8},
	{"label": "Large (192 x 192)", "chunks": 12},
	{"label": "Very large (256 x 256)", "chunks": 16},
	{"label": "Huge (512 x 512) — slow to generate", "chunks": 32},
	{"label": "Colossal (1024 x 1024) — very slow, lots of RAM", "chunks": 64},
]
const TERRAINS := [
	{"label": "Rolling hills (classic)", "preset": "hills"},
	{"label": "Open plains", "preset": "plains"},
	{"label": "River valley", "preset": "rivers"},
	{"label": "Mountains", "preset": "mountains"},
]

var _root: Control
var _home: VBoxContainer
var _setup: VBoxContainer
var _options: VBoxContainer
var _size_pick: OptionButton
var _terrain_pick: OptionButton
var _flavor_pick: OptionButton
var _water_slider: HSlider
var _council_check: CheckBox
var _water_label: Label
var _capturing := ""              # action currently waiting for a key press
var _bind_buttons := {}           # action name -> Button


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.08, 0.10, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "V O X"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "a village that thinks"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.6)
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	# --- home page: New Game / Exit ---
	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 8)
	column.add_child(_home)
	if FileAccess.file_exists("user://vox_save.json"):
		_home.add_child(_button("Continue", func() -> void: continue_game.emit()))
	_home.add_child(_button("New Game", func() -> void:
		_home.visible = false
		_setup.visible = true))
	_home.add_child(_button("Options", func() -> void:
		_home.visible = false
		_options.visible = true))
	_home.add_child(_button("Exit", func() -> void: exit_game.emit()))

	# --- setup page: size + terrain + start ---
	_setup = VBoxContainer.new()
	_setup.add_theme_constant_override("separation", 8)
	_setup.visible = false
	column.add_child(_setup)

	_setup.add_child(_label("Map size"))
	_size_pick = OptionButton.new()
	for s in SIZES:
		_size_pick.add_item(s.label)
	_size_pick.select(1)   # Medium
	_setup.add_child(_size_pick)

	_setup.add_child(_label("Terrain"))
	_terrain_pick = OptionButton.new()
	for t in TERRAINS:
		_terrain_pick.add_item(t.label)
	_terrain_pick.select(0)   # Hills
	_setup.add_child(_terrain_pick)

	_setup.add_child(_label("Cortex flavor (how the minds are run)"))
	_flavor_pick = OptionButton.new()
	for f in FLAVORS:
		_flavor_pick.add_item(f.label)
	_flavor_pick.select(0)
	_setup.add_child(_flavor_pick)

	_water_label = _label("Water: 20% of the map")
	_setup.add_child(_water_label)
	_water_slider = HSlider.new()
	_water_slider.min_value = 0
	_water_slider.max_value = 60
	_water_slider.step = 5
	_water_slider.value = 20
	_water_slider.value_changed.connect(func(v: float) -> void:
		_water_label.text = "Water: %d%% of the map%s" % [int(v),
			"  (dry world)" if v == 0 else ("  (island world)" if v >= 45 else "")])
	_setup.add_child(_water_slider)

	_council_check = CheckBox.new()
	_council_check.text = "Village council — every dawn the villagers gather at" \
		+ " the fire, report their day and agree a plan"
	_council_check.button_pressed = false
	_setup.add_child(_council_check)

	_setup.add_child(HSeparator.new())
	_setup.add_child(_button("Start", func() -> void:
		start_game.emit(int(SIZES[_size_pick.selected].chunks),
			str(TERRAINS[_terrain_pick.selected].preset),
			_water_slider.value / 100.0, -1,
			str(FLAVORS[_flavor_pick.selected].flavor),
			_council_check.button_pressed)))
	_setup.add_child(_button("Back", func() -> void:
		_setup.visible = false
		_home.visible = true))

	# --- options page: key bindings ---
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	_options.visible = false
	column.add_child(_options)
	_options.add_child(_label("Key bindings — click a key, then press the new one"))
	for action in InputConfig.ACTIONS:
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = str(action.label)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var key_btn := Button.new()
		key_btn.text = InputConfig.binding_label(str(action.name))
		key_btn.custom_minimum_size = Vector2(120, 0)
		var act := str(action.name)
		key_btn.pressed.connect(func() -> void: _begin_capture(act))
		row.add_child(key_btn)
		_bind_buttons[act] = key_btn
		_options.add_child(row)
	_options.add_child(HSeparator.new())
	_options.add_child(_button("Reset to defaults", func() -> void:
		InputConfig.reset_defaults()
		_refresh_bindings()))
	_options.add_child(_button("Back", func() -> void:
		_cancel_capture()
		_options.visible = false
		_home.visible = true))

	var hint := Label.new()
	hint.text = "start Cortex first for living minds:  cd cortex && python -m cortex"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.45)
	column.add_child(hint)


func close() -> void:
	visible = false


func show_generating() -> void:
	_home.visible = false
	_setup.visible = false
	_options.visible = false
	var lbl := Label.new()
	lbl.text = "Generating world...\nlarge maps can take a minute or two"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	_setup.get_parent().add_child(lbl)


# ---------------------------------------------------------------- key capture

func _begin_capture(action: String) -> void:
	_cancel_capture()
	_capturing = action
	_bind_buttons[action].text = "press a key..."


func _cancel_capture() -> void:
	if _capturing != "":
		_bind_buttons[_capturing].text = InputConfig.binding_label(_capturing)
		_capturing = ""


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = InputConfig.binding_label(action)


func _input(event: InputEvent) -> void:
	if _capturing == "" or not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_cancel_capture()
		else:
			var action := _capturing
			InputConfig.rebind(action, event)
			_capturing = ""
			_bind_buttons[action].text = InputConfig.binding_label(action)
		get_viewport().set_input_as_handled()


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(handler)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.7)
	return l
