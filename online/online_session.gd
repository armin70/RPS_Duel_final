class_name RPSOnlineSession
extends Node

signal connected(user: Dictionary)
signal disconnected
signal status_changed(message: String)
signal friend_list_updated(payload: Dictionary)
signal invite_received(payload: Dictionary)
signal match_found(payload: Dictionary)
signal match_resumed(payload: Dictionary)
signal opponent_ready(turn_number: int)
signal opponent_disconnected(reconnect_seconds: int)
signal opponent_reconnected
signal turn_reveal(payload: Dictionary)
signal public_action_received(payload: Dictionary)
signal server_error(message: String)

const CONFIG_PATH := "user://rps_online.cfg"
const RECONNECT_DELAY_SECONDS := 2.0

var socket: WebSocketPeer = WebSocketPeer.new()
var server_url: String = "ws://127.0.0.1:8000/ws"
var username: String = "Player"
var token: String = ""
var user: Dictionary = {}
var current_match: Dictionary = {}
var should_reconnect: bool = true
var _hello_sent: bool = false
var _last_state: int = WebSocketPeer.STATE_CLOSED
var _reconnect_wait: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_config()

func _process(delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state_now := socket.get_ready_state()
	if state_now != _last_state:
		_last_state = state_now
		if state_now == WebSocketPeer.STATE_OPEN:
			_hello_sent = false
			_send_hello()
		elif state_now == WebSocketPeer.STATE_CLOSED:
			var close_code: int = socket.get_close_code()
			var close_reason: String = socket.get_close_reason()

			# Server code 4001 means another connection authenticated with the
			# same account token. Auto-reconnecting here would create a loop
			# where the two clients continuously kick each other offline.
			if close_code == 4001:
				should_reconnect = false
				user.clear()
				status_changed.emit(
					"Duplicate login detected. Use a different username."
				)
			elif close_reason.is_empty():
				status_changed.emit("Disconnected")
			else:
				status_changed.emit(
					"Disconnected: %s" % close_reason
				)

			disconnected.emit()

	if state_now == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var text := socket.get_packet().get_string_from_utf8()
			_handle_packet(text)
		return

	if should_reconnect and not server_url.is_empty():
		_reconnect_wait -= delta
		if _reconnect_wait <= 0.0:
			_reconnect_wait = RECONNECT_DELAY_SECONDS
			_connect_socket()

func configure(url: String, new_username: String) -> void:
	var previous_username: String = username

	server_url = url.strip_edges()
	username = new_username.strip_edges()
	if username.length() < 2:
		username = "Player"

	# A saved token identifies one server-side account. When two game
	# instances on the same PC use different usernames, they share the same
	# user:// config file. Reusing that token would make the server think both
	# sockets are the same account, causing an endless connect/disconnect loop.
	if (
		not previous_username.is_empty()
		and username.to_lower() != previous_username.to_lower()
	):
		token = ""
		user.clear()
		current_match.clear()

	_save_config()

func connect_server(url: String = "", new_username: String = "") -> void:
	if not url.is_empty() or not new_username.is_empty():
		configure(url if not url.is_empty() else server_url, new_username if not new_username.is_empty() else username)
	should_reconnect = true
	_reconnect_wait = 0.0
	_connect_socket()

func disconnect_server() -> void:
	should_reconnect = false
	if socket != null:
		socket.close()

func is_connected_to_server() -> bool:
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not user.is_empty()

func request_friend_list() -> void:
	_send({"type": "friend_list"})

func add_friend(friend_code: String) -> void:
	_send({"type": "friend_request", "friend_code": friend_code.strip_edges().to_upper()})

func accept_friend(user_id: int) -> void:
	_send({"type": "friend_accept", "user_id": user_id})

func join_matchmaking(mode: String, setup: Dictionary) -> void:
	_send({"type": "matchmaking_join", "mode": mode, "setup": setup})

func cancel_matchmaking() -> void:
	_send({"type": "matchmaking_cancel"})

func invite_friend(user_id: int, mode: String, setup: Dictionary) -> void:
	_send({"type": "match_invite", "user_id": user_id, "mode": mode, "setup": setup})

func accept_match_invite(invite_id: String, setup: Dictionary) -> void:
	_send({"type": "match_invite_accept", "invite_id": invite_id, "setup": setup})

func queue_hidden_action(action: Dictionary, turn_number: int) -> void:
	_send({"type": "hidden_action", "turn": turn_number, "action": action})

func send_public_action(action: Dictionary) -> void:
	_send({"type": "public_action", "action": action})

func ready_turn(turn_number: int, keep_ids: Array) -> void:
	_send({"type": "turn_ready", "turn": turn_number, "keep_ids": keep_ids})

func report_match_end(winner_seat: int) -> void:
	_send({"type": "match_end", "winner_seat": winner_seat})

func _connect_socket() -> void:
	if server_url.is_empty():
		return
	if socket != null and socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		return
	socket = WebSocketPeer.new()
	var err := socket.connect_to_url(server_url)
	if err != OK:
		status_changed.emit("WebSocket connect failed: %s" % err)
		return
	_hello_sent = false
	status_changed.emit("Connecting to %s" % server_url)

func _send_hello() -> void:
	if _hello_sent:
		return
	_hello_sent = true
	_send({"type": "hello", "token": token, "username": username})

func _send(payload: Dictionary) -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		status_changed.emit("Not connected to server")
		return
	var json_text := JSON.stringify(payload)
	socket.send_text(json_text)

func _handle_packet(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var payload: Dictionary = parsed
	var message_type := String(payload.get("type", ""))
	match message_type:
		"hello_ok":
			token = String(payload.get("token", ""))
			user = payload.get("user", {}) as Dictionary
			_save_config()
			status_changed.emit("Online")
			connected.emit(user)
		"friend_list":
			friend_list_updated.emit(payload)
		"friend_request_received":
			status_changed.emit("New friend request")
			request_friend_list()
		"match_invite_received":
			invite_received.emit(payload)
		"match_invite_sent":
			status_changed.emit("Match invite sent")
		"matchmaking_waiting":
			status_changed.emit("Searching for opponent...")
		"matchmaking_cancelled":
			status_changed.emit("Matchmaking cancelled")
		"match_found":
			current_match = payload.duplicate(true)
			status_changed.emit("Match found")
			match_found.emit(current_match)
		"match_resume":
			current_match = payload.duplicate(true)
			status_changed.emit("Match reconnected")
			match_resumed.emit(current_match)
		"opponent_ready":
			opponent_ready.emit(int(payload.get("turn", 0)))
		"opponent_disconnected":
			opponent_disconnected.emit(int(payload.get("reconnect_seconds", 60)))
		"opponent_reconnected":
			opponent_reconnected.emit()
		"turn_reveal":
			turn_reveal.emit(payload)
		"public_action":
			public_action_received.emit(payload)
		"match_closed":
			current_match.clear()
			status_changed.emit("Match closed")
		"error":
			var message := String(payload.get("message", "Server error"))
			status_changed.emit(message)
			server_error.emit(message)
		"pong":
			pass

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	server_url = String(cfg.get_value("online", "server_url", server_url))
	username = String(cfg.get_value("online", "username", username))
	token = String(cfg.get_value("online", "token", token))

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "server_url", server_url)
	cfg.set_value("online", "username", username)
	cfg.set_value("online", "token", token)
	cfg.save(CONFIG_PATH)
