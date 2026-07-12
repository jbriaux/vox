class_name CortexClient
extends Node
## WebSocket bridge to the Cortex cognition service. Auto-reconnects.

signal cortex_connected
signal cortex_disconnected
signal say_received(npc: String, text: String)
signal action_received(npc: String, data: Dictionary)
signal status_received(text: String)
signal roster_received(npcs: Array, flavor: String)
signal learned_received(data: Dictionary)
signal trade_received(data: Dictionary)
signal skill_received(data: Dictionary)
signal council_end_received(data: Dictionary)
signal converse_end_received(a: String, b: String)
signal era_received(era: int, era_name: String)
signal born_received(npc: Dictionary, parents: Array)

var url := "ws://127.0.0.1:8765/ws"
var online := false

var _ws := WebSocketPeer.new()
var _retry := 0.0
var _was_open := false


func _ready() -> void:
	# point at a remote Cortex (e.g. an Ubuntu GPU host) without code changes
	var env_url := OS.get_environment("VOX_CORTEX_URL")
	if env_url != "":
		url = env_url
		print("[VOX] Cortex URL override: ", url)
	_open_socket()


func _process(delta: float) -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			online = true
			cortex_connected.emit()
		while _ws.get_available_packet_count() > 0:
			var txt := _ws.get_packet().get_string_from_utf8()
			var data: Variant = JSON.parse_string(txt)
			if data is Dictionary:
				_dispatch(data)
	elif state == WebSocketPeer.STATE_CLOSED:
		if _was_open:
			_was_open = false
			online = false
			cortex_disconnected.emit()
		_retry -= delta
		if _retry <= 0.0:
			_retry = 3.0
			_open_socket()


func send(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))


func _open_socket() -> void:
	_ws = WebSocketPeer.new()
	if _ws.connect_to_url(url) != OK:
		_retry = 3.0


func _dispatch(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"say":
			say_received.emit(str(data.get("npc", "")), str(data.get("text", "")))
		"action":
			action_received.emit(str(data.get("npc", "")), data)
		"status":
			status_received.emit(str(data.get("text", "")))
		"roster":
			roster_received.emit(data.get("npcs", []), str(data.get("flavor", "vanilla")))
		"learned":
			learned_received.emit(data)
		"trade":
			trade_received.emit(data)
		"skill":
			skill_received.emit(data)
		"council_end":
			council_end_received.emit(data)
		"converse_end":
			converse_end_received.emit(str(data.get("a", "")), str(data.get("b", "")))
		"era":
			era_received.emit(int(data.get("era", 1)), str(data.get("name", "")))
		"born":
			born_received.emit(data.get("npc", {}), data.get("parents", []))
