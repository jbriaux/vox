class_name ChatUI
extends CanvasLayer
## Bottom-left chat panel: status line, log, input. Built in code.

signal message_submitted(text: String)

var target_id := ""          # which NPC the input box talks to
var _panel: PanelContainer
var _log: RichTextLabel
var _input_box: LineEdit
var _status: Label


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 12.0
	_panel.offset_right = 540.0
	_panel.offset_top = -280.0
	_panel.offset_bottom = -12.0
	add_child(_panel)

	var vb := VBoxContainer.new()
	_panel.add_child(vb)

	_status = Label.new()
	_status.text = "Cortex: connecting..."
	_status.add_theme_font_size_override("font_size", 12)
	_status.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(_status)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_log)

	var hb := HBoxContainer.new()
	vb.add_child(hb)

	_input_box = LineEdit.new()
	_input_box.placeholder_text = "Say something...  (Enter: send, Esc: close)"
	_input_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_box.text_submitted.connect(_on_submit)
	hb.add_child(_input_box)

	var btn := Button.new()
	btn.text = "Send"
	btn.pressed.connect(func() -> void: _on_submit(_input_box.text))
	hb.add_child(btn)

	visible = false


func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	_input_box.text = ""
	message_submitted.emit(text)


func _input_event_close(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE


func _input(event: InputEvent) -> void:
	if visible and _input_event_close(event):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	_input_box.grab_focus()


func open_for(id: String, display_name: String) -> void:
	target_id = id
	_input_box.placeholder_text = "Say something to %s...  (Enter: send, Esc: close)" % display_name
	open()


func close() -> void:
	_input_box.release_focus()
	visible = false


func is_open() -> bool:
	return visible


func add_line(who: String, text: String) -> void:
	_log.append_text("[b]%s:[/b] %s\n" % [who, text])


func set_status(text: String) -> void:
	_status.text = text
