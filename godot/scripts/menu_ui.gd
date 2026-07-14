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

const LLM_FILE := "user://llm_endpoints.cfg"
const CORTEX_HTTP := "http://127.0.0.1:8765"

var _root: Control
var _home: VBoxContainer
var _setup: VBoxContainer
var _options: VBoxContainer
var _llm: VBoxContainer
var _llm_list: ItemList
var _llm_url: LineEdit
var _llm_model: LineEdit
var _llm_status: Label
var _llm_http: HTTPRequest
var _llm_stage := ""              # "" | "models" | "test" | "apply"
var _llm_endpoints: Array = []    # [{url, model}], url is the .../v1/models probe URL
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
	_options.add_child(_button("LLM connections...", func() -> void:
		_cancel_capture()
		_options.visible = false
		_llm.visible = true
		_llm_refresh_list()))
	_options.add_child(_button("Back", func() -> void:
		_cancel_capture()
		_options.visible = false
		_home.visible = true))

	_build_llm_page(column)

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


# ---------------------------------------------------------------- LLM manager
# Options -> "LLM connections": add/edit/delete OpenAI-compatible endpoints,
# probe them for models, test a completion, and push the pool to Cortex.

func _build_llm_page(column: VBoxContainer) -> void:
	_llm = VBoxContainer.new()
	_llm.add_theme_constant_override("separation", 6)
	_llm.visible = false
	column.add_child(_llm)

	_llm.add_child(_label("LLM connections — OpenAI-compatible endpoints (vLLM, Ollama...)"))

	_llm_list = ItemList.new()
	_llm_list.custom_minimum_size = Vector2(0, 110)
	_llm_list.item_selected.connect(_on_llm_selected)
	_llm.add_child(_llm_list)

	_llm.add_child(_label("Endpoint URL (type an IP or host — v1/models is suggested, edit freely)"))
	_llm_url = LineEdit.new()
	_llm_url.placeholder_text = "192.168.1.10:8000"
	_llm_url.text_submitted.connect(func(_t: String) -> void: _llm_suggest_url())
	_llm_url.focus_exited.connect(_llm_suggest_url)
	_llm.add_child(_llm_url)

	_llm.add_child(_label("Model (use Find model, or type it)"))
	_llm_model = LineEdit.new()
	_llm_model.placeholder_text = "e.g. Qwen/Qwen2.5-14B-Instruct"
	_llm.add_child(_llm_model)

	_llm_status = Label.new()
	_llm_status.text = ""
	_llm_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_llm_status.add_theme_font_size_override("font_size", 12)
	_llm.add_child(_llm_status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for pair in [["Add", _llm_add], ["Update", _llm_update],
			["Delete", _llm_delete]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		row.add_child(b)
	_llm.add_child(row)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	for pair in [["Find model + test", _llm_find_model],
			["Apply to Cortex", _llm_apply]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		row2.add_child(b)
	_llm.add_child(row2)

	_llm.add_child(_button("Back", func() -> void:
		_llm.visible = false
		_options.visible = true))

	_llm_http = HTTPRequest.new()
	_llm_http.timeout = 20.0
	_llm_http.request_completed.connect(_on_llm_http_done)
	add_child(_llm_http)

	_llm_load()


func _llm_suggest_url() -> void:
	var t := _llm_url.text.strip_edges()
	if t != "" and _normalize_llm_url(t) != t:
		_llm_url.text = _normalize_llm_url(t)
		_llm_set_status("suggested %s — edit if your server differs" % _llm_url.text, false)


static func _normalize_llm_url(raw: String) -> String:
	## "192.168.1.10:8000" -> "http://192.168.1.10:8000/v1/models".
	## A URL that already carries a path is left alone.
	var t := raw.strip_edges().rstrip("/")
	if t == "":
		return ""
	if not t.contains("://"):
		t = "http://" + t
	var after := t.substr(t.find("://") + 3)
	if not after.contains("/"):
		return t + "/v1/models"
	if t.ends_with("/v1"):
		return t + "/models"
	return t


static func _llm_base(url: String) -> String:
	## The OpenAI-compatible base (".../v1") from the stored models URL.
	var t := url.rstrip("/")
	return t.trim_suffix("/models") if t.ends_with("/models") else t


func _llm_set_status(text: String, error: bool) -> void:
	_llm_status.text = text
	_llm_status.modulate = Color(1.0, 0.55, 0.5) if error else Color(0.7, 1.0, 0.7)


func _llm_refresh_list() -> void:
	_llm_list.clear()
	for e in _llm_endpoints:
		var model := str(e.get("model", ""))
		_llm_list.add_item("%s   [%s]" % [e.get("url", "?"),
			model if model != "" else "no model yet"])


func _on_llm_selected(idx: int) -> void:
	if idx < 0 or idx >= _llm_endpoints.size():
		return
	_llm_url.text = str(_llm_endpoints[idx].get("url", ""))
	_llm_model.text = str(_llm_endpoints[idx].get("model", ""))
	_llm_set_status("editing #%d — change fields, then Update" % (idx + 1), false)


func _llm_add() -> void:
	_llm_suggest_url()
	var url := _llm_url.text.strip_edges()
	if url == "":
		_llm_set_status("type an endpoint URL first", true)
		return
	_llm_endpoints.append({"url": url, "model": _llm_model.text.strip_edges()})
	_llm_save()
	_llm_refresh_list()
	_llm_set_status("added — now Find model + test", false)


func _llm_update() -> void:
	var sel := _llm_list.get_selected_items()
	if sel.is_empty():
		_llm_set_status("select an endpoint in the list first", true)
		return
	_llm_suggest_url()
	_llm_endpoints[sel[0]] = {"url": _llm_url.text.strip_edges(),
		"model": _llm_model.text.strip_edges()}
	_llm_save()
	_llm_refresh_list()
	_llm_set_status("updated", false)


func _llm_delete() -> void:
	var sel := _llm_list.get_selected_items()
	if sel.is_empty():
		_llm_set_status("select an endpoint in the list first", true)
		return
	_llm_endpoints.remove_at(sel[0])
	_llm_save()
	_llm_refresh_list()
	_llm_set_status("deleted", false)


func _llm_find_model() -> void:
	if _llm_stage != "":
		return   # a probe is already in flight
	_llm_suggest_url()
	var url := _llm_url.text.strip_edges()
	if url == "":
		_llm_set_status("type an endpoint URL first", true)
		return
	_llm_stage = "models"
	_llm_set_status("querying %s ..." % url, false)
	var err := _llm_http.request(url)
	if err != OK:
		_llm_stage = ""
		_llm_set_status("request failed to start (error %d)" % err, true)


func _llm_apply() -> void:
	if _llm_stage != "":
		return
	var pool: Array = []
	for e in _llm_endpoints:
		if str(e.get("model", "")) == "":
			_llm_set_status("'%s' has no model — Find model first or Delete it"
				% e.get("url", "?"), true)
			return
		pool.append({"provider": "openai_compatible",
			"base_url": _llm_base(str(e.url)), "model": str(e.model)})
	if pool.is_empty():
		_llm_set_status("no endpoints to apply — Add one first", true)
		return
	_llm_stage = "apply"
	_llm_set_status("sending pool to Cortex...", false)
	var err := _llm_http.request(CORTEX_HTTP + "/brain_pool",
		["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"pool": pool}))
	if err != OK:
		_llm_stage = ""
		_llm_set_status("request failed to start (error %d)" % err, true)


func _on_llm_http_done(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var stage := _llm_stage
	_llm_stage = ""
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_llm_set_status("%s failed: HTTP %d (result %d)%s" % [stage, code, result,
			" — is the server running?" if code == 0 else ""], true)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	match stage:
		"models":
			var models: Array = []
			if data is Dictionary:
				for m in data.get("data", data.get("models", [])):
					if m is Dictionary and m.has("id"):
						models.append(str(m.id))
					elif m is Dictionary and m.has("name"):
						models.append(str(m.name))   # Ollama /api/tags shape
			if models.is_empty():
				_llm_set_status("endpoint answered but listed no models", true)
				return
			if _llm_model.text.strip_edges() == "" \
					or not models.has(_llm_model.text.strip_edges()):
				_llm_model.text = models[0]
			_llm_set_status("found: %s — testing %s ..."
				% [", ".join(models), _llm_model.text], false)
			_llm_stage = "test"
			var payload := {"model": _llm_model.text, "max_tokens": 8,
				"messages": [{"role": "user", "content": "Reply with the single word OK."}]}
			var err := _llm_http.request(
				_llm_base(_llm_url.text) + "/chat/completions",
				["Content-Type: application/json"], HTTPClient.METHOD_POST,
				JSON.stringify(payload))
			if err != OK:
				_llm_stage = ""
				_llm_set_status("test request failed to start (error %d)" % err, true)
		"test":
			var reply := ""
			if data is Dictionary and not (data.get("choices", []) as Array).is_empty():
				reply = str(data.choices[0].get("message", {}).get("content", ""))
			if reply == "":
				_llm_set_status("model answered oddly — check it manually", true)
				return
			_llm_set_status("works! %s said: %s  — Add/Update, then Apply to Cortex"
				% [_llm_model.text, reply.strip_edges().left(60)], false)
		"apply":
			if data is Dictionary and data.get("ok", false):
				_llm_set_status("Cortex rebound %d villagers across %d models"
					% [(data.get("bound", {}) as Dictionary).size(),
						int(data.get("pool_size", 0))], false)
			else:
				var why := str(data.get("error", "unknown")) if data is Dictionary else "bad reply"
				_llm_set_status("Cortex refused the pool: %s" % why, true)


func _llm_save() -> void:
	var f := FileAccess.open(LLM_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"endpoints": _llm_endpoints}, "  "))


func _llm_load() -> void:
	if not FileAccess.file_exists(LLM_FILE):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LLM_FILE))
	if data is Dictionary and data.get("endpoints") is Array:
		_llm_endpoints = data.endpoints
